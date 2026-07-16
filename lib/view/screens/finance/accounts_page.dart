import 'package:everything_app/bloc/finance/finance_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/account.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [AccountsPage] manages the accounts money is held in (Requirement 12.3).
///
/// A balance shown here is derived: the opening balance plus every transaction
/// ever filed against the account. Nothing on this screen writes a balance, so
/// none of them can drift away from the transactions that produced them.
class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            onPressed: () => _editAccount(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add account',
          ),
        ],
      ),
      body: BlocConsumer<FinanceBloc, FinanceState>(
        listenWhen: (previous, current) =>
            previous.error != current.error ||
            previous.message != current.message,
        listener: (context, state) {
          if (state.error.isNotEmpty) {
            context.showSnack(state.error, isError: true);
          } else if (state.message.isNotEmpty) {
            context.showSnack(state.message);
          }
        },
        builder: (context, state) {
          final active = state.activeAccounts;
          final archived = [
            for (final account in state.accounts)
              if (account.isArchived) account,
          ];

          return ListView(
            padding: responsivePadding(context).copyWith(bottom: 120),
            children: [
              _NetWorth(amountMinor: state.netWorthMinor),
              const Gap(8),
              for (final account in active)
                _AccountRow(
                  account: account,
                  balanceMinor: state.balanceOf(account),
                  onTap: () => _editAccount(context, account: account),
                  onDelete: () => context.read<FinanceBloc>().add(
                        RemoveAccountEvent(account: account),
                      ),
                ),
              if (archived.isNotEmpty) ...[
                const Gap(20),
                Text('Archived', style: context.texts.labelMedium),
                Text(
                  'Kept because transactions still point at them.',
                  style: context.texts.bodySmall,
                ),
                const Gap(4),
                for (final account in archived)
                  _AccountRow(
                    account: account,
                    balanceMinor: state.balanceOf(account),
                    onTap: () => context.read<FinanceBloc>().add(
                          SaveAccountEvent(
                            account: account.copyWith(isArchived: false),
                          ),
                        ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// [_editAccount] opens the add/edit sheet. [account] is null when adding.
  Future<void> _editAccount(BuildContext context, {Account? account}) async {
    final edited = await showModalBottomSheet<Account>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AccountSheet(account: account),
    );
    if (edited == null || !context.mounted) return;

    context.read<FinanceBloc>().add(SaveAccountEvent(account: edited));
  }
}

class _NetWorth extends StatelessWidget {
  const _NetWorth({required this.amountMinor});

  final int amountMinor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Across all accounts', style: context.texts.labelSmall),
          const Gap(4),
          Text(
            Helpers.formatMoney(amountMinor, compact: true),
            style: context.texts.labelLarge?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: amountMinor >= 0 ? colors.onSurface : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.balanceMinor,
    required this.onTap,
    this.onDelete,
  });

  final Account account;
  final int balanceMinor;
  final VoidCallback onTap;

  /// Null for an archived account: it is restored by tapping it, and there is
  /// nothing left to delete.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        height: 38,
        width: 38,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(account.type.icon, size: 18, color: colors.onSurfaceVariant),
      ),
      title: Text(account.name, style: context.texts.titleMedium),
      subtitle: Text(account.type.label, style: context.texts.labelSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Helpers.formatMoney(balanceMinor, compact: true),
            style: context.texts.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: balanceMinor >= 0 ? colors.onSurface : colors.error,
            ),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              color: colors.onSurfaceVariant,
              tooltip: 'Delete account',
            )
          else
            Icon(
              Icons.unarchive_outlined,
              size: 18,
              color: colors.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

/// [_AccountSheet] adds or edits one account. It pops the edited [Account] rather
/// than dispatching, so the sheet stays a pure form and the write happens in one
/// place.
class _AccountSheet extends StatefulWidget {
  const _AccountSheet({this.account});

  final Account? account;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  final _name = TextEditingController();
  final _balance = TextEditingController();

  late AccountType _type;

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.account;
    _type = existing?.type ?? AccountType.bank;

    if (existing == null) return;

    _name.text = existing.name;
    _balance.text = existing.openingBalanceMinor == 0
        ? ''
        : Helpers.toMajorUnits(existing.openingBalanceMinor)
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.00$'), '');
  }

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      context.showSnack('Give the account a name.', isError: true);
      return;
    }

    Navigator.of(context).pop(
      Account(
        id: widget.account?.id ?? '',
        name: name,
        type: _type,
        openingBalanceMinor: Helpers.parseMoney(_balance.text) ?? 0,
        isArchived: widget.account?.isArchived ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Text(
                _isEditing ? 'Edit account' : 'New account',
                style: context.texts.headlineSmall,
              ),
              const Gap(12),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(12),
              TextField(
                controller: _balance,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Opening balance',
                  prefixText: '₹ ',
                  isDense: true,
                  // A credit card is normally in the red, so the field takes a
                  // negative — the balance is what the account holds, not what it
                  // is worth.
                  helperText: 'What the account held when you added it.',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(16),
              Text('Type', style: context.texts.labelMedium),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in AccountType.values)
                    AppChoiceChip(
                      label: type.label,
                      avatarIcon: type.icon,
                      isSelected: _type == type,
                      onSelected: (_) => setState(() => _type = type),
                    ),
                ],
              ),
              const Gap(20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  child: Text(_isEditing ? 'Save' : 'Add account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
