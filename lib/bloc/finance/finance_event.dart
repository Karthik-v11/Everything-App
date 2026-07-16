part of 'finance_bloc.dart';

/// [FinanceEvent] is the base class for every Finance module event.
abstract class FinanceEvent extends Equatable {
  const FinanceEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchFinanceEvent] subscribes to the transaction and account streams.
///
/// Dispatched once, at bloc creation.
class WatchFinanceEvent extends FinanceEvent {
  const WatchFinanceEvent();
}

/// [AccountsUpdatedEvent] carries a new account list in from the account stream.
///
/// Internal: it is dispatched by the bloc's own subscription, never by the UI.
/// It exists because a handler's emitter is only valid while that handler runs,
/// so a second long-lived stream has to re-enter through an event rather than
/// emit from a callback.
///
/// [hasFailed] marks a stream error, which carries no accounts to show.
class AccountsUpdatedEvent extends FinanceEvent {
  const AccountsUpdatedEvent({
    required this.accounts,
    this.hasFailed = false,
  });

  final List<Account> accounts;
  final bool hasFailed;

  @override
  List<Object?> get props => [accounts, hasFailed];
}

/// [SelectMonthEvent] picks the month every summary, chart and budget figure is
/// about (Requirement 13.1).
/// [month] is any day within the wanted month.
class SelectMonthEvent extends FinanceEvent {
  const SelectMonthEvent({required this.month});

  final DateTime month;

  @override
  List<Object?> get props => [month];
}

/// [FilterTransactionsEvent] narrows the transaction list.
///
/// A null value clears that narrowing — which is how tapping a slice of the donut
/// and then clearing it are the same event (Requirement 13.3).
class FilterTransactionsEvent extends FinanceEvent {
  const FilterTransactionsEvent({
    this.type,
    this.category,
    this.accountId,
  });

  final TransactionType? type;
  final String? category;
  final String? accountId;

  @override
  List<Object?> get props => [type, category, accountId];
}

/// [SearchTransactionsEvent] filters by title, category and tags
/// (Requirement 12.4).
/// [query] is the search text; empty clears the search.
class SearchTransactionsEvent extends FinanceEvent {
  const SearchTransactionsEvent({required this.query});

  final String query;

  @override
  List<Object?> get props => [query];
}

/// [DeleteTransactionEvent] permanently removes a transaction.
/// [id] is the transaction to delete.
class DeleteTransactionEvent extends FinanceEvent {
  const DeleteTransactionEvent({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// [SaveAccountEvent] creates or updates an account (Requirement 12.3).
class SaveAccountEvent extends FinanceEvent {
  const SaveAccountEvent({required this.account});

  final Account account;

  @override
  List<Object?> get props => [account];
}

/// [RemoveAccountEvent] deletes an account, or archives it when transactions
/// still point at it.
class RemoveAccountEvent extends FinanceEvent {
  const RemoveAccountEvent({required this.account});

  final Account account;

  @override
  List<Object?> get props => [account];
}
