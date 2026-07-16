import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/data/repositories/finance_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'transaction_form_event.dart';
part 'transaction_form_state.dart';

/// [TransactionFormBloc] saves a new or edited transaction (Requirement 12.1).
///
/// Style B: one focused action with a clear start and end. It holds no data
/// between events; the saved transaction goes to the database and reaches every
/// screen through [FinanceBloc]'s stream.
///
/// It is separate from [FinanceBloc] for the same reason [TaskFormBloc] is
/// separate from [TasksBloc]: a validation failure in the form must not put an
/// error on the state the dashboard renders from.
///
/// Events:
/// 1) [SubmitTransactionEvent] — create or update, depending on [SubmitTransactionEvent.isEditing].
/// 2) [ResetTransactionFormEvent] — clear the state after the sheet closes.
class TransactionFormBloc
    extends Bloc<TransactionFormEvent, TransactionFormState> {
  TransactionFormBloc({required this.repository})
      : super(TransactionFormInitial()) {
    on<SubmitTransactionEvent>(_onSubmitTransactionEvent);
    on<ResetTransactionFormEvent>(_onResetTransactionFormEvent);
  }

  final FinanceRepository repository;

  FutureOr<void> _onSubmitTransactionEvent(
    SubmitTransactionEvent event,
    Emitter<TransactionFormState> emit,
  ) async {
    emit(SavingTransaction());
    try {
      final response = event.isEditing
          ? await repository.updateTransaction(event.transaction)
          : await repository.createTransaction(event.transaction);

      if (response.success) {
        emit(TransactionFormSuccess(transaction: response.data! as Transaction));
      } else {
        emit(TransactionFormFailure(message: response.message));
      }
    } catch (_) {
      emit(const TransactionFormFailure(message: 'Something went wrong'));
    }
  }

  FutureOr<void> _onResetTransactionFormEvent(
    ResetTransactionFormEvent event,
    Emitter<TransactionFormState> emit,
  ) {
    emit(TransactionFormInitial());
  }
}
