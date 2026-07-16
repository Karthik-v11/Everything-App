import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/home_widget/home_widget_bloc.dart';
import 'package:everything_app/core/route/app_router.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/data/models/widget_action.dart';
import 'package:everything_app/view/screens/ai/ai_sheet.dart';
import 'package:everything_app/view/screens/finance/transaction_sheet.dart';
import 'package:everything_app/view/screens/tasks/task_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// [HomeWidgetListener] takes a home screen widget tap to where it was going
/// (Requirement 13).
///
/// It sits above the router for the same reason [ShareListener] does: a tap can
/// land on a cold app or over any screen, including the full-screen routes above
/// the shell.
///
/// **Gated on the lock**, and this is not a formality. Every action here opens a
/// screen — the task sheet, the transaction sheet, the assistant — and opening any
/// of them over the lock screen would show or accept data on behalf of someone who
/// has not passed the challenge. The action is not dropped: it stays in
/// [HomeWidgetBloc], and the second listener runs it the moment the app unlocks,
/// so a widget tap on a locked phone still does what the user asked, after they
/// prove who they are.
class HomeWidgetListener extends StatelessWidget {
  const HomeWidgetListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<HomeWidgetBloc, HomeWidgetState>(
          listenWhen: (previous, current) =>
              previous.pendingAction != current.pendingAction &&
              current.pendingAction != null,
          listener: (context, state) => _run(context, state.pendingAction!),
        ),
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) =>
              !previous.isUnlocked && current.isUnlocked,
          listener: (context, state) {
            final pending = context.read<HomeWidgetBloc>().state.pendingAction;
            if (pending != null) _run(context, pending);
          },
        ),
      ],
      child: child,
    );
  }

  void _run(BuildContext context, WidgetAction action) {
    if (!context.read<AuthBloc>().state.isUnlocked) return;

    final navigatorContext = AppRouter.rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;

    context.read<HomeWidgetBloc>().add(const HomeWidgetTapHandled());

    switch (action) {
      // The two "new" actions open the app's own sheets rather than a route,
      // because that is what the + button does everywhere else in the app — a
      // widget tap should land somewhere the user recognises, not on a screen
      // that exists only for widgets.
      case WidgetAction.addTask:
        navigatorContext.goNamed(tasksRoute);
        showTaskSheet(navigatorContext);
      case WidgetAction.addTransaction:
        navigatorContext.goNamed(financeRoute);
        showTransactionSheet(navigatorContext);
      case WidgetAction.assistant:
        showAiSheet(navigatorContext);
      case WidgetAction.search:
        navigatorContext.goNamed(searchRoute);
      case WidgetAction.tasks:
        navigatorContext.goNamed(tasksRoute);
      case WidgetAction.finance:
        navigatorContext.goNamed(financeRoute);
    }
  }
}
