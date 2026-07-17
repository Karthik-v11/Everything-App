import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/bloc/budget/budget_bloc.dart';
import 'package:everything_app/bloc/event_transformers.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_bloc/flutter_bloc.dart';

part 'finance_event.dart';
part 'finance_state.dart';

/// [FinanceBloc] owns the Finance module (Requirements 12, 13).
///
/// It subscribes once to the DAO stream and never re-reads: every summary,
/// chart, balance and filter is derived in memory from that one list, so nothing
/// keeps a copy that can disagree with the database.
///
/// It streams *every* transaction, not the selected month's — the trend chart is
/// six months wide, the summary one month, and search spans everything; one
/// query serves all three.
///
/// [BudgetBloc] owns the budget; this bloc pushes the month's expenses to it via
/// [UpdateSpendEvent] on every change (CLAUDE.md §3.6).
class FinanceBloc extends Bloc<FinanceEvent, FinanceState> {
  FinanceBloc({
    required this.repository,
    required this.budgetBloc,
  }) : super(FinanceState.initial()) {
    on<WatchFinanceEvent>(_onWatchFinanceEvent);
    on<AccountsUpdatedEvent>(_onAccountsUpdatedEvent);
    on<SelectMonthEvent>(_onSelectMonthEvent);
    on<FilterTransactionsEvent>(_onFilterTransactionsEvent);
    on<SearchTransactionsEvent>(
      _onSearchTransactionsEvent,
      transformer: debounce(const Duration(milliseconds: 250)),
    );
    on<DeleteTransactionEvent>(_onDeleteTransactionEvent);
    on<SaveAccountEvent>(_onSaveAccountEvent);
    on<RemoveAccountEvent>(_onRemoveAccountEvent);
  }

  final FinanceRepository repository;
  final BudgetBloc budgetBloc;

  /// The accounts subscription.
  ///
  /// `emit.forEach` holds one stream per handler and the module has two that
  /// never close, so transactions take the emitter and accounts are subscribed
  /// manually, re-entering as [AccountsUpdatedEvent] rather than emitting round a
  /// completed emitter.
  StreamSubscription<List<Account>>? _accounts;

  FutureOr<void> _onWatchFinanceEvent(
    WatchFinanceEvent event,
    Emitter<FinanceState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: '', message: ''));

    await repository.seedDefaultAccounts();

    await _accounts?.cancel();
    _accounts = repository.watchAccounts().listen(
          (accounts) => add(AccountsUpdatedEvent(accounts: accounts)),
          onError: (_) => add(
            const AccountsUpdatedEvent(accounts: <Account>[], hasFailed: true),
          ),
        );

    await emit.forEach<List<Transaction>>(
      repository.watchTransactions(),
      onData: (transactions) {
        // Every write comes back through this stream, so this is the one place
        // that tells the budget what has been spent. Legal in `onData` because
        // the dispatch is synchronous.
        _publishSpend(transactions, state.selectedMonth);

        return state.copyWith(
          isLoading: false,
          transactions: transactions,
          error: '',
        );
      },
      onError: (_, _) => state.copyWith(
        isLoading: false,
        error: 'Could not load your transactions.',
      ),
    );
  }

  FutureOr<void> _onAccountsUpdatedEvent(
    AccountsUpdatedEvent event,
    Emitter<FinanceState> emit,
  ) {
    emit(
      event.hasFailed
          ? state.copyWith(error: 'Could not load your accounts.')
          : state.copyWith(accounts: event.accounts, error: ''),
    );
  }

  @override
  Future<void> close() {
    _accounts?.cancel();
    return super.close();
  }

  FutureOr<void> _onSelectMonthEvent(
    SelectMonthEvent event,
    Emitter<FinanceState> emit,
  ) {
    final month = event.month.startOfMonth;

    emit(state.copyWith(selectedMonth: month));
    _publishSpend(state.transactions, month);
  }

  FutureOr<void> _onFilterTransactionsEvent(
    FilterTransactionsEvent event,
    Emitter<FinanceState> emit,
  ) {
    emit(
      state.copyWith(
        type: event.type,
        clearType: event.type == null,
        category: event.category,
        clearCategory: event.category == null,
        accountId: event.accountId,
        clearAccountId: event.accountId == null,
      ),
    );
  }

  FutureOr<void> _onSearchTransactionsEvent(
    SearchTransactionsEvent event,
    Emitter<FinanceState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  FutureOr<void> _onDeleteTransactionEvent(
    DeleteTransactionEvent event,
    Emitter<FinanceState> emit,
  ) async {
    try {
      // No isLoading: the stream returns the updated list within milliseconds,
      // and a spinner over the whole screen for a local delete would flicker.
      final response = await repository.deleteTransaction(event.id);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the transaction.'));
    }
  }

  FutureOr<void> _onSaveAccountEvent(
    SaveAccountEvent event,
    Emitter<FinanceState> emit,
  ) async {
    try {
      final response = await repository.saveAccount(event.account);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not save the account.'));
    }
  }

  FutureOr<void> _onRemoveAccountEvent(
    RemoveAccountEvent event,
    Emitter<FinanceState> emit,
  ) async {
    try {
      final response = await repository.deleteAccount(event.account);

      emit(
        response.success
            ? state.copyWith(message: response.message, error: '')
            : state.copyWith(error: response.message, message: ''),
      );
    } on Exception {
      emit(state.copyWith(error: 'Could not delete the account.'));
    }
  }

  /// [_publishSpend] hands the month's expenses to [BudgetBloc], which owns the
  /// limits and the alerts. Called on every transaction change and every month
  /// change, so the alerts always reflect the database.
  void _publishSpend(List<Transaction> transactions, DateTime month) {
    final spend = FinanceState.spendFor(transactions, month);

    budgetBloc.add(
      UpdateSpendEvent(
        month: month.month,
        year: month.year,
        spentMinor: spend.totalMinor,
        spentByCategory: spend.byCategory,
      ),
    );
  }
}
