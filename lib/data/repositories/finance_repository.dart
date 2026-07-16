import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/budget.dart';
import 'package:everything_app/data/models/json_response.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/services/finance_service.dart';

/// [FinanceRepository] defines the contract for finance persistence
/// (Requirements 12–14).
abstract class FinanceRepository {
  /// [watchTransactions] streams every transaction, refreshing on any change.
  Stream<List<Transaction>> watchTransactions();

  /// [watchAccounts] streams the accounts, archived ones included.
  Stream<List<Account>> watchAccounts();

  /// [watchBudgets] streams every month's budget.
  Stream<List<Budget>> watchBudgets();

  /// [createTransaction] inserts a transaction. Fails on a blank title, a
  /// non-positive amount, or a missing account.
  Future<JsonResponse> createTransaction(Transaction transaction);

  /// [updateTransaction] saves an edited transaction.
  Future<JsonResponse> updateTransaction(Transaction transaction);

  /// [deleteTransaction] removes a transaction by id.
  Future<JsonResponse> deleteTransaction(String id);

  /// [seedDefaultAccounts] installs the starter accounts on first launch.
  Future<JsonResponse> seedDefaultAccounts();

  /// [saveAccount] inserts or updates an account.
  Future<JsonResponse> saveAccount(Account account);

  /// [deleteAccount] removes an account, archiving it instead when transactions
  /// still point at it.
  Future<JsonResponse> deleteAccount(Account account);

  /// [saveBudget] sets the limit for one month, replacing that month's existing
  /// budget if there is one.
  Future<JsonResponse> saveBudget(Budget budget);
}

class FinanceRepositoryImpl implements FinanceRepository {
  const FinanceRepositoryImpl({required this.financeService});

  final FinanceService financeService;

  @override
  Stream<List<Transaction>> watchTransactions() =>
      financeService.watchTransactions();

  @override
  Stream<List<Account>> watchAccounts() => financeService.watchAccounts();

  @override
  Stream<List<Budget>> watchBudgets() => financeService.watchBudgets();

  @override
  Future<JsonResponse> createTransaction(Transaction transaction) =>
      financeService.createTransaction(transaction);

  @override
  Future<JsonResponse> updateTransaction(Transaction transaction) =>
      financeService.updateTransaction(transaction);

  @override
  Future<JsonResponse> deleteTransaction(String id) =>
      financeService.deleteTransaction(id);

  @override
  Future<JsonResponse> seedDefaultAccounts() =>
      financeService.seedDefaultAccounts();

  @override
  Future<JsonResponse> saveAccount(Account account) =>
      financeService.saveAccount(account);

  @override
  Future<JsonResponse> deleteAccount(Account account) =>
      financeService.deleteAccount(account);

  @override
  Future<JsonResponse> saveBudget(Budget budget) =>
      financeService.saveBudget(budget);
}
