part of 'transaction_form_bloc.dart';

/// [TransactionFormEvent] is the base class for every transaction form event.
abstract class TransactionFormEvent extends Equatable {
  const TransactionFormEvent();

  @override
  List<Object?> get props => [];
}

/// [SubmitTransactionEvent] saves the form (Requirement 12.1).
///
/// [transaction] is the transaction to write. [isEditing] chooses between an
/// insert and an update — an edit that took the insert path would write a second
/// row and double the month's total.
class SubmitTransactionEvent extends TransactionFormEvent {
  const SubmitTransactionEvent({
    required this.transaction,
    required this.isEditing,
  });

  final Transaction transaction;
  final bool isEditing;

  @override
  List<Object?> get props => [transaction, isEditing];
}

/// [ResetTransactionFormEvent] returns the bloc to its initial state.
///
/// The bloc is app-scoped, so a lingering success state would close the next
/// sheet the moment it opened.
class ResetTransactionFormEvent extends TransactionFormEvent {
  const ResetTransactionFormEvent();
}
