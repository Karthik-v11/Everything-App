part of 'transaction_form_bloc.dart';

/// [TransactionFormState] is the abstract base for every form state.
abstract class TransactionFormState extends Equatable {
  const TransactionFormState();

  @override
  List<Object> get props => [];
}

/// [TransactionFormInitial] is the idle state — the sheet is open and untouched.
class TransactionFormInitial extends TransactionFormState {}

/// [SavingTransaction] is emitted while the write is in flight.
class SavingTransaction extends TransactionFormState {}

/// [TransactionFormSuccess] is emitted once the transaction is saved.
/// [transaction] is the saved row, with its generated id and timestamp.
class TransactionFormSuccess extends TransactionFormState {
  const TransactionFormSuccess({required this.transaction});

  final Transaction transaction;

  @override
  List<Object> get props => [transaction];
}

/// [TransactionFormFailure] is emitted when the save fails.
/// [message] is always present and safe to show the user.
class TransactionFormFailure extends TransactionFormState {
  const TransactionFormFailure({required this.message});

  final String message;

  @override
  List<Object> get props => [message];
}
