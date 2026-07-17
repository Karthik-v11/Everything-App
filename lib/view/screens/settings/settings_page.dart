import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/backup/backup_bloc.dart';
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
import 'package:everything_app/data/repositories/gemini_repository.dart';
import 'package:everything_app/view/screens/dashboard/city_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

/// [SettingsPage] is the settings screen (Requirement 25).
///
/// Every control writes straight to its bloc and takes effect immediately
/// (Requirements 20.4, 25.2, 25.3).
///
/// No language picker: the app has no localization (no `flutter_localizations`,
/// no `.arb` files), so the control would change nothing. Part of Requirement
/// 25.1 that is deliberately unbuilt.
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

/// [_AccountSection] is the user's name (Requirement 3.1) and city
/// (Requirement 3.2).
///
/// The city is dispatched straight to [WeatherBloc], which owns it; routing it
/// through [SettingsBloc] would give it two owners.
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
/// Only the master switch shows until notifications are on: the rest can do
/// nothing until the OS grants the permission the master switch asks for.
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

            // Reserved space rather than a conditional child: the section grows
            // and shrinks in place instead of shoving Security down the screen.
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
/// A backup is one AES-256 file with an HMAC integrity tag, sealed with the
/// user's backup PIN. "Share" hands it to the OS sheet, so it reaches a cloud
/// drive without this app needing an account; the PIN is the only key, so the
/// file restores on any phone.
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
              leading: const Icon(Icons.pin_outlined),
              title: Text(
                state.hasBackupPIN ? 'Change backup PIN' : 'Set a backup PIN',
              ),
              subtitle: Text(
                state.hasBackupPIN
                    ? 'Backups are locked with your PIN. Existing backups keep '
                        'the PIN they were made with.'
                    : 'Needed before you can back up.',
                style: context.texts.bodySmall,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _promptForBackupPIN(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Back up now'),
              subtitle: Text(
                state.lastBackupAt == null
                    ? 'Encrypted with your backup PIN. Restores on any phone.'
                    : 'Last backup ${state.lastBackupAt!.shortDateTime}.',
                style: context.texts.bodySmall,
              ),
              trailing: state.isLoading
                  ? const _TrailingSpinner()
                  : const Icon(Icons.chevron_right_rounded),
              onTap: state.isLoading ? null : () => _backUpNow(context, state),
            ),
            // Shown even with no backups on disk: a fresh install restoring a
            // file from an old phone needs this tile most.
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: !state.isRestoring,
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Restore from a backup'),
              subtitle: Text(
                state.backups.isEmpty
                    ? 'No backups on this device — pick a backup file instead.'
                    : '${state.backups.length} backup'
                        '${state.backups.length == 1 ? '' : 's'} on this device, '
                        'or pick a file.',
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

  /// [_promptForBackupPIN] sets the PIN every future backup is sealed with.
  ///
  /// The PIN cannot be recovered: a backup file holds only a salt and a MAC, so
  /// a forgotten PIN and a lost file amount to the same thing.
  Future<void> _promptForBackupPIN(BuildContext context) async {
    final bloc = context.read<BackupBloc>();

    final pin = await showDialog<String>(
      context: context,
      builder: (_) => const _PINDialog(
        title: 'Backup PIN',
        message: 'Your backups are encrypted with this PIN. You will need it to '
            'restore them — on this phone or any other. It cannot be recovered, '
            'so keep it somewhere safe.',
        hint: 'At least 4 digits',
        action: 'Save',
        mustConfirm: true,
      ),
    );

    if (pin != null && pin.isNotEmpty) bloc.add(SetBackupPINEvent(pin: pin));
  }

  /// [_backUpNow] asks for a PIN first if there is none, since sealing is
  /// impossible without one.
  Future<void> _backUpNow(BuildContext context, BackupState state) async {
    if (!state.hasBackupPIN) {
      await _promptForBackupPIN(context);
      return;
    }
    if (context.mounted) context.read<BackupBloc>().add(const CreateBackupEvent());
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

/// [_BackupsSheet] lists the on-device backups to restore, share or delete, and
/// offers to restore a backup file from anywhere else on the device.
///
/// Restore replaces everything, so it confirms first and names when the backup
/// was taken. The repository verifies the HMAC before touching a row, so a
/// corrupt backup fails without a partial write.
///
/// A picked file uses the same `RestoreBackupEvent(path:)` path as a listed one:
/// the magic check and the HMAC decide, not the directory.
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
                  padding: responsivePadding(context).copyWith(bottom: 8),
                  child: Text(
                    'No backups on this device.',
                    style: context.texts.bodySmall,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: state.backups.length,
                    itemBuilder: (context, index) =>
                        _BackupTile(backup: state.backups[index]),
                  ),
                ),
              const Divider(height: 1),
              const _PickBackupFileTile(),
              const Gap(8),
            ],
          );
        },
      ),
    );
  }
}

/// [_PickBackupFileTile] restores a backup file from anywhere on the device —
/// a download, a cloud drive, a file shared over from an old phone.
///
/// Any `.evbak` works, from any phone, given its PIN: the file carries its own
/// KDF salt. Legacy files sealed with an install-keychain key are the exception,
/// and the restore reports that rather than calling them damaged.
class _PickBackupFileTile extends StatelessWidget {
  const _PickBackupFileTile();

  @override
  Widget build(BuildContext context) {
    final isRestoring = context.select<BackupBloc, bool>(
      (bloc) => bloc.state.isRestoring,
    );

    return ListTile(
      enabled: !isRestoring,
      leading: const Icon(Icons.folder_open_rounded),
      title: const Text('Restore from a file'),
      subtitle: Text(
        'Pick an .evbak file — including one from another phone.',
        style: context.texts.bodySmall,
      ),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final bloc = context.read<BackupBloc>();

    // `.evbak` as an extension group rather than a MIME type: the format is this
    // app's own, so no system type describes it, and an Android picker given an
    // unknown MIME type shows nothing selectable at all.
    const typeGroup = XTypeGroup(label: 'Everything backup', extensions: ['evbak']);

    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null || !context.mounted) return;

    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this file?'),
        content: Text(
          'This replaces everything currently in the app with ${file.name}. '
          'This cannot be undone.\n\n'
          "You will need the backup PIN this file was made with, which may not "
          'be the PIN set on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (isConfirmed != true || !context.mounted) return;

    final pin = await _askForBackupPIN(context);
    if (pin == null || pin.isEmpty) return;

    bloc.add(RestoreBackupEvent(path: file.path, pin: pin));
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// [_askForBackupPIN] asks for the PIN a backup was sealed with.
///
/// Always asked, never read from storage: the stored PIN is the one *new*
/// backups get, and the file may predate a PIN change or come from another
/// phone. Deriving from the stored PIN would fail the MAC on a good file.
Future<String?> _askForBackupPIN(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _PINDialog(
        title: 'Enter the backup PIN',
        message: 'The PIN this backup was made with.',
        hint: 'Backup PIN',
        action: 'Restore',
      ),
    );

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

    if (confirmed != true || !context.mounted) return;

    final pin = await _askForBackupPIN(context);
    if (pin == null || pin.isEmpty) return;

    bloc.add(RestoreBackupEvent(path: backup.path, pin: pin));
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
/// File-level so the Backup and Storage sections share one rounding rule.
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

  /// Requires the current PIN, not just a confirmation: an already-unlocked
  /// phone must not be able to shed its lock on one tap.
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

/// [_PINDialog] asks for a PIN and pops it as its result — used to set the app
/// lock, to confirm its removal, and to set or enter the backup PIN.
///
/// [mustConfirm] adds a second field for the backup PIN: a mistyped one seals
/// every future backup against its owner and is only discovered at restore.
///
/// It owns its [TextEditingController] because `showDialog` returns on pop while
/// the [TextField] stays mounted through the exit animation — a caller-owned
/// controller would be disposed out from under a live widget.
class _PINDialog extends StatefulWidget {
  const _PINDialog({
    required this.title,
    required this.hint,
    required this.action,
    this.message,
    this.isDestructive = false,
    this.mustConfirm = false,
  });

  final String title;
  final String hint;
  final String action;
  final String? message;
  final bool isDestructive;
  final bool mustConfirm;

  @override
  State<_PINDialog> createState() => _PINDialogState();
}

class _PINDialogState extends State<_PINDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Whether a backup PIN is the *right* one is unknowable here — the answer
  /// lives in the file's MAC — so a wrong PIN surfaces as a restore failure,
  /// not a field error.
  void _submit() {
    final pin = _controller.text.trim();
    if (widget.mustConfirm) {
      if (pin.length < 4) {
        setState(() => _error = 'Use at least 4 digits.');
        return;
      }
      if (pin != _confirmController.text.trim()) {
        setState(() => _error = 'The two PINs do not match.');
        return;
      }
    }
    Navigator.of(context).pop(pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!, style: context.texts.bodyMedium),
            const Gap(16),
          ],
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ],
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(hintText: widget.hint),
            onSubmitted: (_) => widget.mustConfirm ? null : _submit(),
          ),
          if (widget.mustConfirm) ...[
            const Gap(8),
            TextField(
              controller: _confirmController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
              ],
              obscureText: true,
              decoration: const InputDecoration(hintText: 'Confirm your PIN'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const Gap(8),
            Text(
              _error,
              style: context.texts.bodySmall?.copyWith(color: context.colors.error),
            ),
          ],
        ],
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
            child: _AccentSwatch(
              color: entry.value,
              isSelected: entry.value == selected,
              onTap: () => context
                  .read<ThemeBloc>()
                  .add(ChangeAccentColorEvent(accent: entry.value)),
            ),
          ),
      ],
    );
  }
}

/// [_AccentSwatch] is one colour in the accent picker.
///
/// The selected swatch is marked twice — glow plus check — because a ring alone
/// is not legible across thirteen circles.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? colors.onSurface : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: -1,
                  ),
                ]
              : null,
        ),
        child: AnimatedScale(
          scale: isSelected ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Icon(Icons.check_rounded, size: 20, color: colors.surface),
        ),
      ),
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
/// Turning widgets on copies task titles and a spend figure into a container the
/// OS lets a widget process read, outside the database encryption. It is the one
/// setting that moves data out from behind the key, so the subtitle says so.
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
/// The confidence threshold is the only control: Requirement 25.3's "model
/// precision or response style" examples are not exposable here — the parsers are
/// deterministic regex and the cloud model's sampling is not configured by this
/// app.
///
/// The section leads unconditionally with where text goes, since two assistant
/// methods send text to Google and the rest never leave the device.
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
            const _AiEngineTile(),
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

/// [_AiEngineTile] says where the assistant's text goes.
///
/// A statement, not a control. The assistant's two prose methods — document
/// summaries and questions — call Gemini (see `GeminiService`); everything else
/// is deterministic and stays on the device.
///
/// It says "secrets", not "the vault": a vault item's *name* can reach a question
/// prompt via a search result; only the secret cannot, because the FTS index it
/// draws from never held one (`AiPrompt`).
class _AiEngineTile extends StatelessWidget {
  const _AiEngineTile();

  @override
  Widget build(BuildContext context) {
    // A build with no GEMINI_API_KEY has no cloud engine at all, and the honest
    // subtitle is a different one: nothing is sent because nothing can be.
    final isConfigured = context.read<GeminiRepository>().isConfigured;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isConfigured ? Icons.cloud_outlined : Icons.cloud_off_outlined,
      ),
      title: Text(isConfigured ? 'Summaries and answers' : 'Assistant engine'),
      subtitle: Text(
        isConfigured
            ? 'Document summaries and questions are sent to Google Gemini to be '
                'written, so they need a connection and they leave your device. '
                'Your vault’s secrets are never included. Everything else the '
                'assistant does — reading a task, an amount, a date out of what '
                'you type — happens here and is never sent.'
            : 'No API key in this build, so nothing is sent anywhere. Summaries '
                'and answers fall back to the built-in engine, which only ever '
                'repeats what your data already says.',
        style: context.texts.bodySmall,
      ),
      isThreeLine: true,
    );
  }
}

/// [_StorageSection] is the per-module storage breakdown (Requirement 25.4).
///
/// Measured on open, not on every write: the `dbstat` scan and two directory
/// walks are only ever read here.
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
                tooltip: 'Recalculate',
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
/// The version is omitted, not placeholdered, while the platform read is in
/// flight: a user could report the placeholder as the version.
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
                'Everything is stored encrypted on this device, and there is no '
                'account. The app makes three kinds of request: weather, news, '
                'and — only when you ask the assistant to summarise a document '
                'or answer a question — that text to Google Gemini. Your vault’s '
                'secrets are never sent.',
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
