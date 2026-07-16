import 'package:everything_app/bloc/to_buy/to_buy_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/task.dart';
import 'package:everything_app/data/models/to_buy_item.dart';
import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showToBuySheet] opens the add/edit sheet (Requirement 7.1).
Future<void> showToBuySheet(BuildContext context, {ToBuyItem? item}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ToBuySheet(item: item),
  );
}

/// [ToBuySheet] adds or edits a thing to buy.
///
/// The name is the only required field and the one the caret opens in. A price, a
/// store, a priority and a reminder are all optional — plenty of things go on a
/// wishlist as nothing more than a word.
class ToBuySheet extends StatefulWidget {
  const ToBuySheet({this.item, super.key});

  final ToBuyItem? item;

  @override
  State<ToBuySheet> createState() => _ToBuySheetState();
}

class _ToBuySheetState extends State<ToBuySheet> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _store = TextEditingController();
  final _notes = TextEditingController();

  late TaskPriority _priority;

  DateTime? _reminderAt;

  bool _isMoreOpen = false;

  ToBuyItem? get _original => widget.item;

  bool get _isEditing => _original != null;

  @override
  void initState() {
    super.initState();

    final existing = _original;

    if (existing == null) {
      _priority = TaskPriority.medium;
      return;
    }

    _name.text = existing.name;
    _price.text = existing.estimatedPriceMinor == null
        ? ''
        : Helpers.toMajorUnits(existing.estimatedPriceMinor!)
            .toStringAsFixed(2)
            // A whole amount shows as `250`, not `250.00`: the decimals are noise in
            // a field the user is most likely to retype.
            .replaceFirst(RegExp(r'\.00$'), '');
    _store.text = existing.store ?? '';
    _notes.text = existing.notes ?? '';
    _priority = existing.priority;
    _reminderAt = existing.reminderAt;
    _isMoreOpen = existing.notes != null && existing.notes!.isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _store.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// [_pickReminder] asks for a day and then a time (Requirement 7.3).
  ///
  /// Both, not just a day: a reminder is a moment, and one that defaulted to
  /// midnight would fire while the user was asleep and be gone by the time they
  /// could act on it.
  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final current = _reminderAt;

    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        current ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _submit() {
    if (_name.text.isBlank) {
      context.showSnack('What do you want to buy?', isError: true);
      return;
    }

    final store = _store.text.trim();
    final notes = _notes.text.trim();

    final item = ToBuyItem(
      id: _original?.id ?? '',
      name: _name.text.trim(),
      estimatedPriceMinor:
          _price.text.isBlank ? null : Helpers.parseMoney(_price.text),
      store: store.isEmpty ? null : store,
      priority: _priority,
      isPurchased: _original?.isPurchased ?? false,
      reminderAt: _reminderAt,
      notes: notes.isEmpty ? null : notes,
      createdAt: _original?.createdAt ?? DateTime.now(),
    );

    context.read<ToBuyBloc>().add(
          SaveToBuyItemEvent(item: item, isEditing: _isEditing),
        );

    Navigator.of(context).pop();
  }

  void _delete() {
    context.read<ToBuyBloc>().add(DeleteToBuyItemEvent(id: _original!.id));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: context.texts.titleMedium,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'What do you want to buy?',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: 'Price',
                        prefixText: '₹ ',
                        isDense: true,
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextField(
                      controller: _store,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Store',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          OptionPillMenu<TaskPriority>(
                            icon: Icons.flag_outlined,
                            label: _priority.name.capitalized,
                            isSet: _priority != TaskPriority.medium,
                            accent: _priority.color,
                            onSelected: (value) =>
                                setState(() => _priority = value),
                            entries: [
                              for (final value in TaskPriority.values.reversed)
                                PillOption(
                                  value: value,
                                  label: value.name.capitalized,
                                  icon: Icons.brightness_1_rounded,
                                  iconColor: value.color,
                                ),
                            ],
                          ),
                          const Gap(8),
                          OptionPill(
                            icon: Icons.notifications_none_rounded,
                            label: _reminderAt?.shortDateTime ?? 'Remind',
                            isSet: _reminderAt != null,
                            accent: colors.primary,
                            onTap: _pickReminder,
                          ),
                          if (_reminderAt != null) ...[
                            const Gap(8),
                            OptionPill(
                              icon: Icons.close_rounded,
                              label: 'Clear',
                              isSet: false,
                              accent: colors.primary,
                              onTap: () => setState(() => _reminderAt = null),
                            ),
                          ],
                          const Gap(8),
                          OptionPill(
                            icon: _isMoreOpen
                                ? Icons.expand_less_rounded
                                : Icons.more_horiz_rounded,
                            label: 'More',
                            isSet: _isMoreOpen,
                            accent: colors.primary,
                            onTap: () =>
                                setState(() => _isMoreOpen = !_isMoreOpen),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(8),
                  SizedBox.square(
                    dimension: 44,
                    child: IconButton.filled(
                      onPressed: _name.text.isBlank ? null : _submit,
                      tooltip: 'Save item',
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        disabledBackgroundColor: colors.surfaceContainerHighest,
                        disabledForegroundColor: colors.onSurfaceVariant,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _isMoreOpen
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Gap(12),
                          TextField(
                            controller: _notes,
                            maxLines: 3,
                            minLines: 1,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Notes',
                              isDense: true,
                            ),
                          ),
                          if (_isEditing) ...[
                            const Gap(4),
                            TextButton.icon(
                              onPressed: _delete,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              label: const Text('Delete item'),
                              style: TextButton.styleFrom(
                                foregroundColor: colors.error,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
