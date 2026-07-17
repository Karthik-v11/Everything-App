import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/database/daos/finance_dao.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:uuid/uuid.dart';

/// [FinanceService] is the Finance module's persistence layer (Requirements
/// 12–14).
///
/// Drift-backed, but keeps the standard service contract: every method returns
/// [JsonResponse] and nothing throws past this layer.
///
/// Validation lives here rather than in the blocs, so every entry point — the
/// form, the AI parser, the share intent — is subject to the same rules.
class FinanceService {
  FinanceService({required this.dao});

  final FinanceDao dao;

  static const Uuid _uuid = Uuid();

  // ── Streams ────────────────────────────────────────────────────────────────

  Stream<List<Transaction>> watchTransactions() => dao
      .watchTransactions()
      .map((rows) => rows.map(Transaction.fromEntry).toList());

  Stream<List<Account>> watchAccounts() =>
      dao.watchAccounts().map((rows) => rows.map(Account.fromEntry).toList());

  Stream<List<Budget>> watchBudgets() =>
      dao.watchBudgets().map((rows) => rows.map(Budget.fromEntry).toList());

  // ── Transactions ───────────────────────────────────────────────────────────

  /// [createTransaction] inserts a transaction.
  ///
  /// The amount must be positive and the title non-blank. Direction is carried by
  /// [Transaction.type], so a negative amount is a bug rather than an expense and
  /// is rejected rather than silently flipping a summary total (Properties 6, 7).
  Future<JsonResponse> createTransaction(Transaction transaction) async {
    try {
      final invalid = _validate(transaction);
      if (invalid != null) return invalid;

      final prepared = transaction.copyWith(
        id: transaction.id.isBlank ? _uuid.v4() : transaction.id,
        title: transaction.title.trim(),
        createdAt: DateTime.now(),
      );

      await dao.upsertTransaction(prepared.toCompanion());

      return JsonResponse.created(
        message: 'Transaction added.',
        data: prepared,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the transaction.',
      );
    }
  }

  /// [updateTransaction] saves an edited transaction, keeping its original
  /// [Transaction.createdAt].
  Future<JsonResponse> updateTransaction(Transaction transaction) async {
    try {
      final invalid = _validate(transaction);
      if (invalid != null) return invalid;

      final prepared = transaction.copyWith(title: transaction.title.trim());

      await dao.upsertTransaction(prepared.toCompanion());

      return JsonResponse.success(
        message: 'Transaction updated.',
        data: prepared,
      );
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not update the transaction.',
      );
    }
  }

  Future<JsonResponse> deleteTransaction(String id) async {
    try {
      final removed = await dao.deleteTransaction(id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That transaction no longer exists.',
            )
          : JsonResponse.success(message: 'Transaction deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the transaction.',
      );
    }
  }

  JsonResponse? _validate(Transaction transaction) {
    if (transaction.title.isBlank) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'A transaction needs a title.',
      );
    }

    if (transaction.amountMinor <= 0) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'Enter an amount greater than zero.',
      );
    }

    if (transaction.accountId.isBlank) {
      return JsonResponse.failure(
        statusCode: 400,
        message: 'Choose an account.',
      );
    }

    return null;
  }

  // ── Accounts ───────────────────────────────────────────────────────────────

  /// [seedDefaultAccounts] installs the starter accounts on first launch.
  Future<JsonResponse> seedDefaultAccounts() async {
    try {
      await dao.seedAccountsIfEmpty([
        for (final account in kDefaultAccounts)
          Account(
            id: _uuid.v4(),
            name: account.name,
            type: account.type,
          ).toCompanion(),
      ]);

      return JsonResponse.success(message: 'Accounts ready.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not prepare your accounts.',
      );
    }
  }

  Future<JsonResponse> saveAccount(Account account) async {
    try {
      if (account.name.isBlank) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'An account needs a name.',
        );
      }

      final prepared = account.copyWith(
        id: account.id.isBlank ? _uuid.v4() : account.id,
        name: account.name.trim(),
      );

      await dao.upsertAccount(prepared.toCompanion());

      return JsonResponse.success(message: 'Account saved.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the account.',
      );
    }
  }

  /// [deleteAccount] removes an account, or archives it if it has history.
  ///
  /// Deleting one that transactions point at would leave those rows — and every
  /// balance and filter reading them — naming an account that no longer exists.
  /// An archived account leaves the pickers but keeps explaining the past.
  Future<JsonResponse> deleteAccount(Account account) async {
    try {
      final used = await dao.countTransactionsForAccount(account.id);

      if (used > 0) {
        await dao.upsertAccount(account.copyWith(isArchived: true).toCompanion());

        return JsonResponse.success(
          message: 'Account archived — its $used transactions are kept.',
        );
      }

      final removed = await dao.deleteAccount(account.id);

      return removed == 0
          ? JsonResponse.failure(
              statusCode: 404,
              message: 'That account no longer exists.',
            )
          : JsonResponse.success(message: 'Account deleted.');
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not delete the account.',
      );
    }
  }

  // ── Budgets ────────────────────────────────────────────────────────────────

  /// [saveBudget] sets the limit for one month (Requirements 14.1, 14.2).
  ///
  /// One budget per month is an invariant, so an existing one is updated in place
  /// rather than joined by a second that would skew every percentage on screen.
  Future<JsonResponse> saveBudget(Budget budget) async {
    try {
      if (budget.monthlyLimitMinor < 0) {
        return JsonResponse.failure(
          statusCode: 400,
          message: 'A budget cannot be negative.',
        );
      }

      final existing = await dao.findBudget(
        month: budget.month,
        year: budget.year,
      );

      final prepared = budget.copyWith(
        id: existing?.id ?? (budget.id.isBlank ? _uuid.v4() : budget.id),
        categoryLimits: {
          for (final entry in budget.categoryLimits.entries)
            if (entry.value > 0) entry.key: entry.value,
        },
      );

      await dao.upsertBudget(prepared.toCompanion());

      return JsonResponse.success(message: 'Budget saved.', data: prepared);
    } on Exception {
      return JsonResponse.failure(
        statusCode: 500,
        message: 'Error: could not save the budget.',
      );
    }
  }
}
