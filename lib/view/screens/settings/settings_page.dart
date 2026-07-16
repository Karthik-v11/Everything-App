import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/backup/backup_bloc.dart';
import 'package:everything_app/bloc/on_device_model/on_device_model_bloc.dart';
import 'package:everything_app/bloc/settings/settings_bloc.dart';
import 'package:everything_app/bloc/storage/storage_bloc.dart';
import 'package:everything_app/bloc/theme/theme_bloc.dart';
import 'package:everything_app/bloc/weather/weather_bloc.dart';
import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/app_text_styles.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/core/utils/theme.dart';
import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/models/backup_metadata.dart';
import 'package:everything_app/data/models/notification_settings.dart';
import 'package:everything_app/data/models/storage_usage.dart';
import 'package:everything_app/view/screens/dashboard/city_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

/// [SettingsPage] is the settings screen (Requirement 25).
///
/// Every control writes straight to its bloc and takes effect immediately — the
/// theme across every screen with no restart (Requirement 20.4), the
/// notification schedule with no reopen (Requirement 25.2), and the assistant's
/// threshold on its next parse (Requirement 25.3).
///
/// **Language is deliberately absent**, and it is the one section of
/// Requirement 25.1 that is not built. The app has no localization at all — no
/// `flutter_localizations`, no `.arb` files, no delegates, and every string in
/// every screen is a hardcoded English literal. A language picker here would be
/// a control that changes nothing, which is worse than no control: it is a
/// promise the app cannot keep, and the only way to discover that is to pick a
/// language and watch nothing happen. Localization is a phase of its own —
/// extracting every string in the app — and this section belongs to it. See
/// `docs/plan.md`, Phase 12.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, state) {
          return ListView(
            padding: responsivePadding(context).copyWith(top: 8, bottom: 32),
            children: [
              _SectionLabel('Account'),
              const Gap(4),
              const _AccountSection(),
              const Gap(28),
              _SectionLabel('Theme'),
              const Gap(12),
              _ThemeVariantPicker(selected: state.variant),
              const Gap(28),
              _SectionLabel('Accent'),
              const Gap(12),
              _AccentPicker(selected: state.accent),
              const Gap(28),
              _SectionLabel('Font Size'),
              const Gap(12),
              _FontSizePicker(selected: state.fontSize),
              const Gap(28),
              _SectionLabel('Notifications'),
              const Gap(4),
              const _NotificationsSection(),
              const Gap(28),
              _SectionLabel('Backup'),
              const Gap(4),
              const _BackupSection(),
              const Gap(28),
              _SectionLabel('Security'),
              const Gap(12),
              const _SecuritySection(),
              const Gap(28),
              _SectionLabel('Home Screen'),
              const Gap(4),
              const _HomeWidgetsSection(),
              const Gap(28),
              _SectionLabel('Assistant'),
              const Gap(4),
              const _AiSection(),
              const Gap(28),
              _SectionLabel('Storage'),
              const Gap(4),
              const _StorageSection(),
              const Gap(28),
              _SectionLabel('About'),
              const Gap(4),
              const _AboutSection(),
            ],
          );
        },
      ),
    );
  }
}

/// [_AccountSection] is the two things the Dashboard needs to know about the
/// user: what to call them (Requirement 3.1) and where they are (Requirement 3.2).
///
/// The city is dispatched straight to [WeatherBloc], which owns it — a *screen*
/// may talk to any bloc, and routing it through [SettingsBloc] would give the
/// city two owners and no way to tell which one was right.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  Future<void> _edit(
    BuildContext context, {
    required String title,
    required String hint,
    required String initial,
    required ValueChanged<String> onSave,
  }) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, hint: hint, initial: initial),
    );

    if (value != null) onSave(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (previous, current) =>
              previous.userName != current.userName,
          builder: (context, state) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline_rounded),
            title: const Text('Your name'),
            subtitle: Text(
              state.userName.isEmpty
                  ? 'Used to greet you on the Dashboard'
                  : state.userName,
            ),
            onTap: () => _edit(
              context,
              title: 'Your name',
              hint: 'Karthik',
              initial: state.userName,
              onSave: (name) => context.read<SettingsBloc>().add(
                    ChangeUserNameEvent(name: name),
                  ),
            ),
          ),
        ),
        BlocBuilder<WeatherBloc, WeatherState>(
          buildWhen: (previous, current) => previous.city != current.city,
          builder: (context, state) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Your city'),
            subtitle: Text(
              state.city.isEmpty ? 'Needed for the weather' : state.city,
            ),
            onTap: () => showCitySheet(context),
          ),
        ),
      ],
    );
  }
}

/// [_TextDialog] edits one line of text and returns it, or null if dismissed.
class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.hint,
    required this.initial,
  });

  final String title;
  final String hint;
  final String initial;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// [_NotificationsSection] is the notification controls (Requirements 5, 25.2).
///
/// The master switch is the only control shown until notifications are on: five
/// disabled toggles and two time pickers under a switch that is off is a wall of
/// dead controls, and none of them can do anything until the OS has granted the
/// permission that the master switch itself asks for.
class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsBloc, SettingsState>(
      listenWhen: (previous, current) =>
          previous.message != current.message ||
          previous.error != current.error,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
        } else if (state.message.isNotEmpty) {
          context.showSnack(state.message);
        }
      },
      builder: (context, state) {
        final notifications = state.notifications;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.isDelivering,
              title: const Text('Notifications'),
              subtitle: Text(
                state.isPermissionGranted
                    ? 'Reminders, deadlines and summaries.'
                    : 'Allow notifications to get reminders.',
                style: context.texts.bodySmall,
              ),
              onChanged: (isEnabled) => context
                  .read<SettingsBloc>()
                  .add(ToggleNotificationsEvent(isEnabled: isEnabled)),
            ),

            // Reserved space rather than a conditional child: the section below
            // grows and shrinks in place instead of shoving Security down the
            // screen.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !state.isDelivering
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.isExactAlarmWarningVisible)
                          const _ExactAlarmWarning(),
                        for (final kind in NotificationKind.values)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: notifications.enabledKinds.contains(kind),
                            title: Text(kind.label),
                            subtitle: Text(
                              kind.description,
                              style: context.texts.bodySmall,
                            ),
                            onChanged: (isEnabled) =>
                                context.read<SettingsBloc>().add(
                                      ToggleNotificationKindEvent(
                                        kind: kind,
                                        isEnabled: isEnabled,
                                      ),
                                    ),
                          ),
                        if (notifications.enabledKinds
                            .contains(NotificationKind.dailySummary))
                          _SummaryTimeTile(
                            title: 'Daily summary at',
                            minutes: notifications.dailySummaryMinutes,
                            onChanged: (minutes) =>
                                context.read<SettingsBloc>().add(
                                      ChangeSummaryTimeEvent(
                                        kind: NotificationKind.dailySummary,
                                        minutes: minutes,
                                      ),
                                    ),
                          ),
                        if (notifications.enabledKinds
                            .contains(NotificationKind.weeklySummary)) ...[
                          _SummaryTimeTile(
                            title: 'Weekly summary at',
                            minutes: notifications.weeklySummaryMinutes,
                            onChanged: (minutes) =>
                                context.read<SettingsBloc>().add(
                                      ChangeSummaryTimeEvent(
                                        kind: NotificationKind.weeklySummary,
                                        minutes: minutes,
                                      ),
                                    ),
                          ),
                          _WeekdayPicker(
                            selected: notifications.weeklySummaryWeekday,
                            onChanged: (weekday) =>
                                context.read<SettingsBloc>().add(
                                      ChangeSummaryWeekdayEvent(
                                        weekday: weekday,
                                      ),
                                    ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// [_ExactAlarmWarning] appears when Android has not granted the exact-alarm
/// permission, which means reminders arrive late rather than on time.
///
/// It says so plainly. Silently delivering a 9:00 reminder at 9:40 and letting
/// the user conclude the app is broken is the worse outcome.
class _ExactAlarmWarning extends StatelessWidget {
  const _ExactAlarmWarning();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: colors.error),
          const Gap(10),
          Expanded(
            child: Text(
              'Exact alarms are off, so reminders may arrive a few minutes late.',
              style: context.texts.bodySmall,
            ),
          ),
          const Gap(8),
          TextButton(
            onPressed: () => context
                .read<SettingsBloc>()
                .add(const RequestNotificationPermissionEvent()),
            child: const Text('Fix'),
          ),
        ],
      ),
    );
  }
}

/// [_SummaryTimeTile] picks the time of day a digest fires.
class _SummaryTimeTile extends StatelessWidget {
  const _SummaryTimeTile({
    required this.title,
    required this.minutes,
    required this.onChanged,
  });

  final String title;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule_rounded),
      title: Text(title),
      trailing: Text(
        time.format(context),
        style: context.texts.titleSmall,
      ),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked == null) return;

        onChanged(picked.hour * 60 + picked.minute);
      },
    );
  }
}

/// [_WeekdayPicker] picks the day the weekly digest fires.
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const List<String> _labels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var weekday = DateTime.monday;
              weekday <= DateTime.sunday;
              weekday++)
            AppChoiceChip(
              label: _labels[weekday - 1],
              isSelected: weekday == selected,
              onSelected: (_) => onChanged(weekday),
            ),
        ],
      ),
    );
  }
}

/// [_BackupSection] is the encrypted backup, restore and automatic-backup
/// controls (Requirement 22).
///
/// A backup is one AES-256 file with an HMAC integrity tag, written to the app's
/// storage. "Share" hands that file to the OS sheet, which is how it reaches a
/// cloud drive without this app needing an account — the encryption is the app's,
/// the destination is the user's.
class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BackupBloc, BackupState>(
      listenWhen: (previous, current) =>
          previous.message != current.message ||
          previous.error != current.error,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
        } else if (state.message.isNotEmpty) {
          context.showSnack(state.message);
        }
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: state.isAutoBackupEnabled,
              title: const Text('Automatic backup'),
              subtitle: Text(
                'Backs up once a day, the next time you open the app.',
                style: context.texts.bodySmall,
              ),
              onChanged: (isEnabled) => context
                  .read<BackupBloc>()
                  .add(ToggleAutoBackupEvent(isEnabled: isEnabled)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Back up now'),
              subtitle: Text(
                state.lastBackupAt == null
                    ? 'Encrypted with a key only this device holds.'
                    : 'Last backup ${state.lastBackupAt!.shortDateTime}.',
                style: context.texts.bodySmall,
              ),
              trailing: state.isLoading
                  ? const _TrailingSpinner()
                  : const Icon(Icons.chevron_right_rounded),
              onTap: state.isLoading
                  ? null
                  : () =>
                      context.read<BackupBloc>().add(const CreateBackupEvent()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: state.backups.isNotEmpty && !state.isRestoring,
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Restore from a backup'),
              subtitle: Text(
                state.backups.isEmpty
                    ? 'No backups yet.'
                    : '${state.backups.length} backup'
                        '${state.backups.length == 1 ? '' : 's'} available.',
                style: context.texts.bodySmall,
              ),
              trailing: state.isRestoring
                  ? const _TrailingSpinner()
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _showBackupsSheet(context),
            ),
          ],
        );
      },
    );
  }

  void _showBackupsSheet(BuildContext context) {
    final bloc = context.read<BackupBloc>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          BlocProvider<BackupBloc>.value(value: bloc, child: const _BackupsSheet()),
    );
  }
}

class _TrailingSpinner extends StatelessWidget {
  const _TrailingSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

/// [_BackupsSheet] lists the on-device backups to restore, share or delete.
///
/// Restore replaces everything, so it asks first and names the moment the backup
/// was taken — the one fact that tells the user which state they are rolling back
/// to. A backup that fails its integrity check never gets this far into the
/// database: the repository verifies the HMAC before touching a row and reports a
/// plain failure, so there is no "was anything lost?" to answer.
class _BackupsSheet extends StatelessWidget {
  const _BackupsSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: BlocBuilder<BackupBloc, BackupState>(
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: responsivePadding(context).copyWith(top: 4, bottom: 8),
                child: Text('Backups', style: context.texts.titleMedium),
              ),
              if (state.backups.isEmpty)
                Padding(
                  padding: responsivePadding(context).copyWith(bottom: 24),
                  child: Text(
                    'No backups yet.',
                    style: context.texts.bodySmall,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: state.backups.length,
                    itemBuilder: (context, index) =>
                        _BackupTile(backup: state.backups[index]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({required this.backup});

  final BackupMetadata backup;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.lock_outline_rounded),
      title: Text(backup.createdAt.shortDateTime),
      subtitle: Text(
        _formatSize(backup.sizeBytes),
        style: context.texts.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share',
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                files: [XFile(backup.path)],
                subject: 'Everything backup',
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: context.colors.error),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      onTap: () => _confirmRestore(context),
    );
  }

  Future<void> _confirmRestore(BuildContext context) async {
    final bloc = context.read<BackupBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'This replaces everything currently in the app with the backup from '
          '${backup.createdAt.shortDateTime}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    bloc.add(RestoreBackupEvent(path: backup.path));
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bloc = context.read<BackupBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this backup?'),
        content: Text('The backup from ${backup.createdAt.shortDateTime} '
            'will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) bloc.add(DeleteBackupEvent(path: backup.path));
  }

}

/// [_formatSize] renders a byte count for display.
///
/// File-level rather than private to a widget: the Backup and Storage sections
/// both size files, and two copies of this would be two rounding rules that
/// disagree about the same backup on the same screen.
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// [_SecuritySection] is the PIN and lock controls (Requirements 1, 23).
class _SecuritySection extends StatelessWidget {
  const _SecuritySection();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.message != current.message ||
          previous.error != current.error,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
        } else if (state.message.isNotEmpty) {
          context.showSnack(state.message);
        }
      },
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.pin_rounded),
              title: Text(state.hasPIN ? 'Change PIN' : 'Set a PIN'),
              subtitle: Text(
                state.hasPIN
                    ? 'The app locks after ${kAutoLockDuration.inMinutes} min '
                        'in the background.'
                    : 'Your data is already encrypted. A PIN adds a lock screen.',
                style: context.texts.bodySmall,
              ),
              onTap: () => _promptForPIN(context),
            ),
            if (state.hasPIN) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Lock now'),
                onTap: () =>
                    context.read<AuthBloc>().add(const LockEvent(force: true)),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.lock_open_rounded,
                  color: context.colors.error,
                ),
                title: Text(
                  'Remove app lock',
                  style: TextStyle(color: context.colors.error),
                ),
                subtitle: Text(
                  'The app opens without a PIN. Your data stays encrypted.',
                  style: context.texts.bodySmall,
                ),
                onTap: () => _promptToRemovePIN(context),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _promptForPIN(BuildContext context) async {
    final bloc = context.read<AuthBloc>();

    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PINDialog(
        title: 'Set a PIN',
        hint: 'At least 4 digits',
        action: 'Save',
      ),
    );

    if (pin != null && pin.isNotEmpty) bloc.add(SetPINEvent(pin: pin));
  }

  /// [_promptToRemovePIN] requires the current PIN, not just a confirmation: an
  /// already-unlocked phone must not be able to shed its lock on one tap.
  Future<void> _promptToRemovePIN(BuildContext context) async {
    final bloc = context.read<AuthBloc>();

    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PINDialog(
        title: 'Remove app lock',
        hint: 'Enter your current PIN',
        action: 'Remove',
        isDestructive: true,
      ),
    );

    if (pin != null && pin.isNotEmpty) bloc.add(RemovePINEvent(pin: pin));
  }
}

/// [_PINDialog] asks for a PIN and pops it as its result — used to set one and to
/// confirm removal.
///
/// It owns its [TextEditingController]. `showDialog` returns as soon as the route
/// is popped, while the dialog keeps its [TextField] mounted through the exit
/// animation, so a controller disposed by the caller after the `await` would be
/// disposed out from under a live widget.
class _PINDialog extends StatefulWidget {
  const _PINDialog({
    required this.title,
    required this.hint,
    required this.action,
    this.isDestructive = false,
  });

  final String title;
  final String hint;
  final String action;
  final bool isDestructive;

  @override
  State<_PINDialog> createState() => _PINDialogState();
}

class _PINDialogState extends State<_PINDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(12),
        ],
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: context.colors.error,
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: context.texts.labelSmall);
}

class _ThemeVariantPicker extends StatelessWidget {
  const _ThemeVariantPicker({required this.selected});

  final AppThemeVariant selected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final variant in AppThemeVariant.values)
          AppChoiceChip(
            label: variant.name.capitalized,
            isSelected: variant == selected,
            onSelected: (_) => context
                .read<ThemeBloc>()
                .add(ChangeThemeVariantEvent(variant: variant)),
          ),
      ],
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.selected});

  final Color selected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in AppColors.accents.entries)
          Semantics(
            button: true,
            selected: entry.value == selected,
            label: entry.key,
            child: GestureDetector(
              onTap: () => context
                  .read<ThemeBloc>()
                  .add(ChangeAccentColorEvent(accent: entry.value)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: entry.value,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: entry.value == selected
                        ? context.colors.onSurface
                        : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FontSizePicker extends StatelessWidget {
  const _FontSizePicker({required this.selected});

  final FontSize selected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<FontSize>(
      segments: [
        for (final size in FontSize.values)
          ButtonSegment(value: size, label: Text(size.name.capitalized)),
      ],
      selected: {selected},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => context
          .read<ThemeBloc>()
          .add(ChangeFontSizeEvent(fontSize: selection.first)),
    );
  }
}

/// [_HomeWidgetsSection] is the home screen widget switch (Requirement 13).
///
/// The subtitle says what the switch actually does rather than describing the
/// feature. Turning widgets on copies task titles and a spend figure into a
/// container the OS lets a widget process read, and that container is *not*
/// covered by the database encryption Phase 2 built — so it is the one setting in
/// this app that moves data out from behind the key, and the user is told so in
/// the place where they decide.
class _HomeWidgetsSection extends StatelessWidget {
  const _HomeWidgetsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) =>
          previous.areWidgetsEnabled != current.areWidgetsEnabled,
      builder: (context, state) {
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: state.areWidgetsEnabled,
          title: const Text('Home screen widgets'),
          subtitle: Text(
            'Shows today’s tasks and this month’s spending on your home '
            'screen. A widget cannot read the encrypted database, so what it '
            'shows is copied somewhere the system can read it. Turning this '
            'off erases that copy.',
            style: context.texts.bodySmall,
          ),
          isThreeLine: true,
          onChanged: (isEnabled) => context
              .read<SettingsBloc>()
              .add(ToggleHomeWidgetsEvent(isEnabled: isEnabled)),
        );
      },
    );
  }
}

/// [_AiSection] is the assistant's settings (Requirements 16.7, 25.3).
///
/// One control, because the assistant has exactly one thing worth deciding today.
/// Requirement 25.3 offers "model precision or response style" as examples, and
/// both are properties of a model this app does not have yet — the engine is
/// Phase 10's rule-based parser. A precision slider over a regex would be a
/// control wired to nothing. The confidence threshold is the real equivalent: it
/// changes what the assistant does with the *next* thing typed, which is what the
/// requirement actually asks for.
///
/// Phase 13 added the second control — [_OnDeviceModelTile] — and it is a real
/// one for the same reason: it changes what the assistant *does*, not what it
/// claims. Note what it deliberately is not: there is still no "model precision"
/// or "response style" knob, because the model backs only two prose methods and
/// a temperature slider over a document summary would be a control over a thing
/// nobody has an opinion about.
class _AiSection extends StatelessWidget {
  const _AiSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) =>
          previous.aiConfidence != current.aiConfidence,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _OnDeviceModelTile(),
            const Gap(8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('When to ask before saving'),
              subtitle: Text(
                _describe(state.aiConfidence),
                style: context.texts.bodySmall,
              ),
            ),
            Slider(
              value: state.aiConfidence,
              min: kMinAiConfidence,
              max: kMaxAiConfidence,
              // Ten steps across the range: fine enough to tune, coarse enough
              // that a drag lands somewhere repeatable.
              divisions: 10,
              label: '${(state.aiConfidence * 100).round()}%',
              onChanged: (value) => context
                  .read<SettingsBloc>()
                  .add(ChangeAiConfidenceEvent(confidence: value)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Guess more', style: context.texts.bodySmall),
                Text('Ask more', style: context.texts.bodySmall),
              ],
            ),
          ],
        );
      },
    );
  }

  /// [_describe] says what the number means in the terms the user thinks in.
  ///
  /// "0.75" is not a thing anyone has an opinion about; "asks whenever it is not
  /// sure" is.
  static String _describe(double confidence) {
    if (confidence <= 0.45) {
      return 'The assistant saves what it understood, and rarely asks. Faster, '
          'but more likely to save something you did not mean.';
    }
    if (confidence >= 0.75) {
      return 'The assistant asks whenever it is not certain. Slower, but it '
          'will rarely save the wrong thing.';
    }
    return 'The assistant asks only when it cannot tell what you meant — no '
        'name for a task, no amount for an expense.';
  }
}

/// [_OnDeviceModelTile] is the on-device model's switch, download and status
/// (Phase 13).
///
/// The switch and the download are **separate actions**, deliberately. Turning a
/// setting on must never start a 584 MB download on its own: the switch says
/// "use the model when there is one", and fetching one is a thing the user asks
/// for after being told what it costs. So a switch-on with nothing installed is
/// a legal, quiet state — the assistant stays rule-based and the download button
/// sits underneath saying its size.
///
/// The subtitle states what is *true right now* rather than what was chosen.
/// "On" with no weights on disk would be a lie of exactly the kind Phase 12
/// refused to ship a language picker over.
class _OnDeviceModelTile extends StatelessWidget {
  const _OnDeviceModelTile();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnDeviceModelBloc, OnDeviceModelState>(
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.error),
                backgroundColor: context.colors.error,
              ),
            );
        }
      },
      listenWhen: (previous, current) => previous.error != current.error,
      builder: (context, state) {
        final isEnabled = context.select<SettingsBloc, bool>(
          (bloc) => bloc.state.isOnDeviceAiEnabled,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isEnabled,
              title: const Text('On-device AI'),
              subtitle: Text(
                _describe(state: state, isEnabled: isEnabled),
                style: context.texts.bodySmall,
              ),
              onChanged: (value) => context
                  .read<SettingsBloc>()
                  .add(ToggleOnDeviceAiEvent(isEnabled: value)),
            ),
            if (state.isDownloading) ...[
              const Gap(4),
              LinearProgressIndicator(value: state.progress / 100),
              const Gap(4),
              Text(
                'Downloading… ${state.progress}%',
                style: context.texts.bodySmall,
              ),
            ] else if (state.isDownloadable)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context
                      .read<OnDeviceModelBloc>()
                      .add(const DownloadOnDeviceModelEvent()),
                  icon: const Icon(Icons.download_outlined),
                  label: Text('Download model (${state.downloadSizeLabel})'),
                ),
              )
            else if (state.isInstalled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _confirmRemove(context, state),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove model'),
                ),
              ),
          ],
        );
      },
    );
  }

  /// [_describe] says what is actually happening, in the order the user needs to
  /// hear it: the blockers first, then the state.
  static String _describe({
    required OnDeviceModelState state,
    required bool isEnabled,
  }) {
    // A build with no HF_TOKEN cannot download, and saying so is better than a
    // button that 401s after however long 584 MB takes (Phase 6, note 5).
    if (!state.isConfigured && !state.isInstalled) {
      return 'Unavailable in this build — no HuggingFace token. The assistant '
          'uses its built-in engine.';
    }
    if (!isEnabled) {
      return 'Summaries and answers use the built-in engine — instant, and they '
          'only ever repeat what your data says.';
    }
    if (!state.isInstalled) {
      return 'On, but no model is downloaded yet. Using the built-in engine '
          'until you download one.';
    }
    if (state.isLoading) return 'Loading the model…';
    if (state.isLoaded) {
      return 'Summaries and answers are written by the on-device model. Nothing '
          'leaves your phone.';
    }
    return 'The model is downloaded but not loaded. Using the built-in engine.';
  }

  /// [_confirmRemove] names what it deletes, per the rule Phase 7 set: a
  /// confirmation the user cannot act on is a confirmation they learn to dismiss.
  Future<void> _confirmRemove(
    BuildContext context,
    OnDeviceModelState state,
  ) async {
    final bloc = context.read<OnDeviceModelBloc>();

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove the model?'),
        content: Text(
          'This frees ${state.downloadSizeLabel}. The assistant keeps working '
          'with its built-in engine, and you can download the model again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (isConfirmed ?? false) bloc.add(const RemoveOnDeviceModelEvent());
  }
}

/// [_StorageSection] is the per-module storage breakdown (Requirement 25.4).
///
/// It measures on open rather than on every write: a `dbstat` scan and two
/// directory walks to keep a figure fresh that is only ever read here would be
/// work for nothing.
class _StorageSection extends StatefulWidget {
  const _StorageSection();

  @override
  State<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends State<_StorageSection> {
  @override
  void initState() {
    super.initState();
    context.read<StorageBloc>().add(const ReadStorageEvent());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StorageBloc, StorageState>(
      builder: (context, state) {
        // Exhaustive over the sealed state, so a state added later cannot be
        // forgotten here.
        return switch (state) {
          StorageInitial() || StorageLoading() => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: _TrailingSpinner()),
            ),
          StorageFailure(:final message) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.error_outline_rounded,
                color: context.colors.error,
              ),
              title: Text(message),
              trailing: IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () =>
                    context.read<StorageBloc>().add(const ReadStorageEvent()),
              ),
            ),
          StorageLoaded(:final usage) => _StorageBreakdown(usage: usage),
        };
      },
    );
  }
}

class _StorageBreakdown extends StatelessWidget {
  const _StorageBreakdown({required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in usage.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(line.module.label, style: context.texts.bodyMedium),
                      if (_captionOf(line).isNotEmpty) ...[
                        const Gap(2),
                        Text(
                          _captionOf(line),
                          style: context.texts.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  // With no dbstat the byte split is unknown, and the row shows
                  // its item count alone rather than a size it cannot stand
                  // behind.
                  usage.isEstimated && line.bytes == 0
                      ? '—'
                      : _formatSize(line.bytes),
                  style: context.texts.labelMedium,
                ),
              ],
            ),
          ),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: context.texts.bodyMedium),
            Text(
              _formatSize(usage.totalBytes),
              style: context.texts.labelMedium,
            ),
          ],
        ),
        const Gap(8),
        Text(
          'The database is encrypted; its size includes free space that a '
          'delete leaves behind.',
          style: context.texts.bodySmall,
        ),
        const Gap(4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Recalculate'),
            onPressed: () =>
                context.read<StorageBloc>().add(const ReadStorageEvent()),
          ),
        ),
      ],
    );
  }

  String _captionOf(StorageLine line) {
    if (line.detail.isNotEmpty) return line.detail;

    final count = line.itemCount;
    if (count == null) return '';
    return count == 1 ? '1 item' : '$count items';
  }
}

/// [_AboutSection] is what build this is (Requirement 25.1).
///
/// The version is omitted rather than shown as a placeholder while the platform
/// read is in flight: a dash where a version belongs is something a user might
/// report as the version.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) =>
          previous.appVersion != current.appVersion ||
          previous.packageName != current.packageName,
      builder: (context, state) {
        return Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Everything'),
              subtitle: Text(
                state.packageName.isEmpty
                    ? 'Your tasks, money, library and notes — on this device.'
                    : state.packageName,
                style: context.texts.bodySmall,
              ),
              trailing: state.appVersion.isEmpty
                  ? null
                  : Text(state.appVersion, style: context.texts.labelMedium),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Your data stays here'),
              subtitle: Text(
                'Everything is stored encrypted on this device. Nothing is '
                'uploaded, and there is no account. Weather and news are the '
                'only requests this app makes.',
                style: context.texts.bodySmall,
              ),
              isThreeLine: true,
            ),
          ],
        );
      },
    );
  }
}
