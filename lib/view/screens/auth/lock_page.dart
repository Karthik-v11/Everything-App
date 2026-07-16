import 'dart:async';

import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [LockPage] is the authentication gate (Requirement 1).
///
/// It offers biometrics first and falls back to the PIN pad, and it enforces the
/// 30-second lockout after three failures with a live countdown.
///
/// The router shows this page whenever the app is locked, and only unlocking
/// dismisses it; there is no navigation past it.
class LockPage extends StatefulWidget {
  const LockPage({super.key});

  @override
  State<LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<LockPage> {
  final _pin = TextEditingController();

  /// Ticks once a second purely to redraw the lockout countdown. It only runs
  /// while a lockout is active.
  Timer? _countdown;

  @override
  void initState() {
    super.initState();

    // Prompt for biometrics on mount, without waiting for a tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AuthBloc>().state;
      if (state.isBiometricAvailable && !state.isLockedOut) {
        context.read<AuthBloc>().add(const AuthenticateBiometricEvent());
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _pin.dispose();
    super.dispose();
  }

  /// [_syncCountdown] starts or stops the one-second repaint timer to match the
  /// lockout state.
  void _syncCountdown({required bool isLockedOut}) {
    if (isLockedOut && _countdown == null) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (!context.read<AuthBloc>().state.isLockedOut) {
          _countdown?.cancel();
          _countdown = null;
        }
      });
    } else if (!isLockedOut && _countdown != null) {
      _countdown?.cancel();
      _countdown = null;
    }
  }

  void _submit() {
    final pin = _pin.text.trim();
    if (pin.isEmpty) return;
    context.read<AuthBloc>().add(SubmitPINEvent(pin: pin));
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;
    final colors = context.colors;

    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          _syncCountdown(isLockedOut: state.isLockedOut);
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          }
        },
        builder: (context, state) {
          final isLockedOut = state.isLockedOut;

          return SafeArea(
            child: Padding(
              padding: responsivePadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isLockedOut ? Icons.lock_clock_rounded : Icons.lock_rounded,
                    size: 48,
                    color: colors.primary,
                  ),
                  const Gap(20),
                  Text('Everything', style: texts.headlineMedium),
                  const Gap(8),
                  Text(
                    isLockedOut
                        ? 'Too many attempts. Try again in '
                            '${state.lockoutRemaining.inSeconds + 1}s.'
                        : 'Enter your PIN to unlock',
                    style: texts.bodySmall?.copyWith(
                      color: isLockedOut ? colors.error : null,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(32),
                  TextField(
                    controller: _pin,
                    enabled: !isLockedOut && !state.isLoading,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    obscureText: true,
                    autofocus: false,
                    textAlign: TextAlign.center,
                    style: texts.headlineSmall,
                    decoration: const InputDecoration(hintText: '••••'),
                    onSubmitted: (_) => _submit(),
                  ),
                  const Gap(16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          isLockedOut || state.isLoading ? null : _submit,
                      child: state.isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Unlock'),
                    ),
                  ),
                  if (state.isBiometricAvailable) ...[
                    const Gap(12),
                    TextButton.icon(
                      onPressed: isLockedOut
                          ? null
                          : () => context
                              .read<AuthBloc>()
                              .add(const AuthenticateBiometricEvent()),
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Use biometrics'),
                    ),
                  ],
                  if (!isLockedOut && state.failedAttempts > 0) ...[
                    const Gap(12),
                    Text(
                      '${state.attemptsRemaining} of $kMaxPINAttempts attempts '
                      'remaining',
                      style: texts.labelSmall?.copyWith(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
