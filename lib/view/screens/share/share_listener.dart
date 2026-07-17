import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/share/share_bloc.dart';
import 'package:everything_app/core/route/app_router.dart';
import 'package:everything_app/view/screens/share/share_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [ShareListener] opens the share chooser wherever the user happens to be
/// (Requirement 12.2).
///
/// It sits above the router rather than on any screen, because a share arrives
/// unannounced over whatever was last open — including the full-screen routes that
/// are pushed above the shell, which a listener inside the shell could not reach.
///
/// **It is gated on the lock.** A share that lands while the app is locked must
/// not put a chooser over the lock screen: filing it would write to the database
/// on behalf of someone who has not proved who they are, and Requirement 1's whole
/// point is that nothing happens before the challenge is passed. The share is not
/// dropped — it stays pending in [ShareBloc] — and the second listener below opens
/// the chooser the moment the app is unlocked, so sharing into a locked app is
/// deferred rather than lost.
///
/// The sheet is shown against [AppRouter.rootNavigatorKey] rather than this
/// widget's own context: this sits *above* the router's [Navigator], so
/// `Navigator.of(context)` from here would find nothing to push onto.
class ShareListener extends StatefulWidget {
  const ShareListener({required this.child, super.key});

  final Widget child;

  @override
  State<ShareListener> createState() => _ShareListenerState();
}

class _ShareListenerState extends State<ShareListener> {
  @override
  void initState() {
    super.initState();

    // This widget mounts when the auth gate opens, not at launch, so both
    // transitions the listeners below watch for can have already happened by the
    // time it exists — on the no-PIN path `isChecked` and `isUnlocked` flip in a
    // single emit. Re-checking the pending state on mount makes the replay
    // independent of that ordering; without it a share that arrived during the
    // gate would sit in the bloc with nothing left to open it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<ShareBloc>().state.isChooserOpen) _open(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ShareBloc, ShareState>(
          listenWhen: (previous, current) =>
              !previous.isChooserOpen && current.isChooserOpen,
          listener: (context, state) => _open(context),
        ),
        // The deferred case: a share arrived while locked and is still pending.
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (previous, current) =>
              !previous.isUnlocked && current.isUnlocked,
          listener: (context, state) {
            if (context.read<ShareBloc>().state.isChooserOpen) _open(context);
          },
        ),
      ],
      child: widget.child,
    );
  }

  void _open(BuildContext context) {
    if (!context.read<AuthBloc>().state.isUnlocked) return;

    final navigatorContext = AppRouter.rootNavigatorKey.currentContext;
    if (navigatorContext == null) return;

    showShareSheet(navigatorContext);
  }
}
