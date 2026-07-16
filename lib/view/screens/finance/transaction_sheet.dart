import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/bloc/transaction_form/transaction_form_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/data/models/transaction.dart';
import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showTransactionSheet] opens the add/edit sheet (Requirement 12.1).
///
/// [transaction] is null when creating and the transaction itself when editing.
/// The root navigator is used so the sheet covers the bottom navigation and the
/// AI dock rather than being clipped into the shell's body.
Future<void> showTransactionSheet(
  BuildContext context, {
  Transaction? transaction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => TransactionSheet(transaction: transaction),
  );
}

/// [TransactionSheet] creates or edits a transaction.
///
/// The amount is the field that opens with the caret in it: it is the only thing
/// the user always has in mind when they reach for this sheet, and it is the only
/// one they cannot get wrong by leaving alone. Everything else has a working
/// default — today, the last-used account, `Other` — so a spend can be logged
/// with an amount, a word and one tap.
class TransactionSheet extends StatefulWidget {
  const TransactionSheet({this.transaction, super.key});

  final Transaction? transaction;

  @override
  State<TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<TransactionSheet> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _amountFocus = FocusNode();

  /// Read once, in [initState]: neither list changes while the sheet is open, and
  /// watching [FinanceBloc] would rebuild the sheet on every keystroke elsewhere.
  late final List<Account> _accounts;
  late final List<String> _categories;

  late TransactionType _type;
  late String _category;
  late String _accountId;
  late DateTime _date;

  bool _isMoreOpen = false;

  /// True once the category is the user's own choice — either one they picked from
  /// the menu or one an edited transaction already carried. [_readCategory] never
  /// overrules it: a guess that quietly replaces a deliberate choice is worse than
  /// no guess at all.
  bool _isCategoryPinned = false;

  Transaction? get _original => widget.transaction;

  bool get _isEditing => _original != null;

  /// The amount in minor units, or null while the field is empty or unparseable —
  /// which is also what disables the save button.
  int? get _amountMinor {
    final parsed = Helpers.parseMoney(_amount.text);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  @override
  void initState() {
    super.initState();

    final finance = context.read<FinanceBloc>().state;

    _accounts = finance.activeAccounts;
    _categories = finance.categories;

    final existing = _original;

    if (existing == null) {
      _type = TransactionType.expense;
      _category = kDefaultTransactionCategory;
      _accountId = _accounts.isEmpty ? '' : _accounts.first.id;
      _isCategoryPinned = false;

      // A transaction logged while the user is looking at a past month belongs to
      // *that* month, not to today — otherwise it lands somewhere they are not
      // looking and the total they were watching does not move.
      final month = finance.selectedMonth;
      final now = DateTime.now();
      _date = month.month == now.month && month.year == now.year
          ? now
          : month;

      return;
    }

    _amount.text = Helpers.toMajorUnits(existing.amountMinor)
        .toStringAsFixed(2)
        // A whole amount is shown as `250`, not `250.00`: the decimals are noise
        // in the field the user is most likely to retype.
        .replaceFirst(RegExp(r'\.00$'), '');
    _title.text = existing.title;
    _notes.text = existing.notes ?? '';
    _type = existing.type;
    _category = existing.category;
    _accountId = existing.accountId;
    _date = existing.date;
    _isMoreOpen = existing.notes != null && existing.notes!.isNotEmpty;
    _isCategoryPinned = true;
  }

  /// [_defaultCategory] is what the sheet falls back to when the title says
  /// nothing: income is a salary far more often than it is anything else.
  String _defaultCategory(TransactionType type) =>
      type == TransactionType.income ? 'Salary' : kDefaultTransactionCategory;

  /// [_readCategory] re-derives the category from what the user has typed
  /// ("Swiggy dinner" → Food) unless they have picked one themselves.
  ///
  /// Runs on every keystroke: the pill is the feedback, so it has to move while
  /// the title is still being typed rather than at save, when the user is no
  /// longer looking at it.
  void _readCategory() {
    if (_isCategoryPinned) return;

    final category =
        inferTransactionCategory(_title.text) ?? _defaultCategory(_type);
    if (category == _category) return;

    setState(() => _category = category);
  }

  void _selectCategory(String category) => setState(() {
        _category = category;
        _isCategoryPinned = true;
      });

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _notes.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
    );
    if (date == null || !mounted) return;

    setState(() {
      // The time of day is kept: it is what orders two transactions on the same
      // day, and a picker that has no opinion on it must not reset it to midnight.
      _date = DateTime(
        date.year,
        date.month,
        date.day,
        _date.hour,
        _date.minute,
      );
    });
  }

  void _submit() {
    final amountMinor = _amountMinor;
    if (amountMinor == null) {
      context.showSnack('Enter an amount greater than zero.', isError: true);
      return;
    }

    if (_accountId.isEmpty) {
      context.showSnack('Add an account first.', isError: true);
      return;
    }

    final title = _title.text.trim();
    final notes = _notes.text.trim();

    final transaction = Transaction(
      id: _original?.id ?? '',
      // An untitled transaction is named after what it was for. A blank title is
      // rejected by the service, and asking the user to type "Food" twice to
      // satisfy that is a worse answer than filling it in.
      title: title.isEmpty ? _category : title,
      amountMinor: amountMinor,
      date: _date,
      type: _type,
      category: _category,
      accountId: _accountId,
      notes: notes.isEmpty ? null : notes,
      tags: _original?.tags ?? const [],
      createdAt: _original?.createdAt ?? DateTime.now(),
    );

    context.read<TransactionFormBloc>().add(
          SubmitTransactionEvent(
            transaction: transaction,
            isEditing: _isEditing,
          ),
        );
  }

  void _delete() {
    context.read<FinanceBloc>().add(DeleteTransactionEvent(id: _original!.id));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BlocConsumer<TransactionFormBloc, TransactionFormState>(
      listener: (context, state) {
        if (state is TransactionFormSuccess) {
          // The bloc is app-scoped: a lingering success state would close the next
          // sheet the moment it opened.
          context.read<TransactionFormBloc>().add(
                const ResetTransactionFormEvent(),
              );
          Navigator.of(context).pop();
        } else if (state is TransactionFormFailure) {
          context.showSnack(state.message, isError: true);
        }
      },
      builder: (context, state) {
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
                  _TypeRow(
                    type: _type,
                    onSelected: (type) {
                      setState(() => _type = type);
                      // Income has nothing to do with the spending categories, and
                      // "Salary" filed as an expense is a wrong donut. Switching
                      // type re-reads the category so the default moves with it.
                      _readCategory();
                    },
                  ),
                  const Gap(14),
                  _AmountField(
                    controller: _amount,
                    focusNode: _amountFocus,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                  ),
                  const Gap(6),
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    style: context.texts.titleMedium,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'What was it for?',
                    ),
                    onChanged: (_) => _readCategory(),
                    onSubmitted: (_) => _submit(),
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: _OptionsRow(
                          date: _date,
                          category: _category,
                          categories: _categories,
                          accountId: _accountId,
                          accounts: _accounts,
                          isMoreOpen: _isMoreOpen,
                          onPickDate: _pickDate,
                          onCategorySelected: _selectCategory,
                          onAccountSelected: (id) =>
                              setState(() => _accountId = id),
                          onToggleMore: () => setState(
                            () => _isMoreOpen = !_isMoreOpen,
                          ),
                        ),
                      ),
                      const Gap(8),
                      _SaveButton(
                        isEnabled: _amountMinor != null &&
                            state is! SavingTransaction,
                        isSaving: state is SavingTransaction,
                        onPressed: _submit,
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
                                textCapitalization:
                                    TextCapitalization.sentences,
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
                                  label: const Text('Delete transaction'),
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
      },
    );
  }
}

/// [_TypeRow] is the four transaction types (Requirement 12.1).
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.onSelected});

  final TransactionType type;
  final ValueChanged<TransactionType> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: TransactionType.values.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, index) {
          final value = TransactionType.values[index];
          final isSelected = value == type;

          return GestureDetector(
            onTap: () => onSelected(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : colors.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? colors.primary : colors.outline,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    value.icon,
                    size: 15,
                    color: isSelected
                        ? colors.onPrimary
                        : colors.onSurfaceVariant,
                  ),
                  const Gap(6),
                  Text(
                    value.label,
                    style: context.texts.labelMedium?.copyWith(
                      color: isSelected
                          ? colors.onPrimary
                          : colors.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// [_AmountField] is the sheet's headline: a large monospace figure behind a fixed
/// currency symbol.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '₹',
          style: texts.displaySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
        const Gap(6),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              // Digits and at most one decimal point. The parser tolerates more
              // than this, but a field that accepts `1.2.3` and then quietly
              // reads it as something else is worse than one that never let it be
              // typed.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            style: texts.displaySmall,
            decoration: const InputDecoration(
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '0',
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}

/// [_OptionsRow] is the row of pills: date, category, account, more.
class _OptionsRow extends StatelessWidget {
  const _OptionsRow({
    required this.date,
    required this.category,
    required this.categories,
    required this.accountId,
    required this.accounts,
    required this.isMoreOpen,
    required this.onPickDate,
    required this.onCategorySelected,
    required this.onAccountSelected,
    required this.onToggleMore,
  });

  final DateTime date;
  final String category;
  final List<String> categories;
  final String accountId;
  final List<Account> accounts;
  final bool isMoreOpen;
  final VoidCallback onPickDate;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<String> onAccountSelected;
  final VoidCallback onToggleMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final account = accounts.where((a) => a.id == accountId).firstOrNull;

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          OptionPill(
            icon: Icons.event_rounded,
            label: date.relativeLabel,
            isSet: true,
            accent: colors.primary,
            onTap: onPickDate,
          ),
          const Gap(8),
          OptionPillMenu<String>(
            icon: categoryIcon(category),
            label: category,
            isSet: category != kDefaultTransactionCategory,
            accent: categoryColor(category),
            onSelected: onCategorySelected,
            entries: [
              for (final value in categories)
                PillOption(
                  value: value,
                  label: value,
                  icon: categoryIcon(value),
                  iconColor: categoryColor(value),
                ),
            ],
          ),
          const Gap(8),
          OptionPillMenu<String>(
            icon: account?.type.icon ?? Icons.account_balance_wallet_outlined,
            label: account?.name ?? 'Account',
            isSet: account != null,
            accent: colors.primary,
            onSelected: onAccountSelected,
            entries: [
              for (final value in accounts)
                PillOption(
                  value: value.id,
                  label: value.name,
                  icon: value.type.icon,
                ),
            ],
          ),
          const Gap(8),
          OptionPill(
            icon: isMoreOpen
                ? Icons.expand_less_rounded
                : Icons.more_horiz_rounded,
            label: 'More',
            isSet: isMoreOpen,
            accent: colors.primary,
            onTap: onToggleMore,
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.isEnabled,
    required this.isSaving,
    required this.onPressed,
  });

  final bool isEnabled;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.square(
      dimension: 44,
      child: IconButton.filled(
        onPressed: isEnabled ? onPressed : null,
        tooltip: 'Save transaction',
        style: IconButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.surfaceContainerHighest,
          disabledForegroundColor: colors.onSurfaceVariant,
        ),
        icon: isSaving
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onPrimary,
                ),
              )
            : const Icon(Icons.arrow_upward_rounded, size: 20),
      ),
    );
  }
}
