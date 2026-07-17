import 'dart:async';

import 'package:everything_app/bloc/auth/auth_bloc.dart';
import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/view/screens/library/vault_detail_sheet.dart';
import 'package:everything_app/view/screens/library/vault_item_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [VaultPage] is the secure store (Requirement 9).
///
/// Two screens in one widget, and which of them you see is the whole feature:
/// [_Challenge] until the user has proved who they are **this visit**, and only then
/// the list (Requirement 9.2).
///
/// The vault re-locks in `dispose`, so leaving the screen and coming back is a fresh
/// challenge rather than a resumed session. That is why the gate is here rather than
/// in a `GoRouter.redirect`: a redirect is about which route you may reach, and this
/// is about proving who you are *every time you reach it*.
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _search = TextEditingController();

  Timer? _debounce;

  /// Held so [dispose] can re-lock without a `context.read`: by the time dispose
  /// runs the element is defunct, and looking an ancestor bloc up through it throws
  /// "Looking up a deactivated widget's ancestor is unsafe". The bloc is app-scoped,
  /// so this reference stays valid for the life of the screen.
  late final VaultBloc _vault;

  @override
  void initState() {
    super.initState();

    _vault = context.read<VaultBloc>();

    // The biometric prompt is raised the moment the screen opens rather than behind
    // a button: the user tapped a card marked with a shield, so being asked for a
    // fingerprint is what they came here expecting. The PIN pad is the fallback if
    // they cancel it or the device has no biometrics (Requirement 1.3).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final auth = context.read<AuthBloc>().state;
      if (!auth.isBiometricAvailable) return;

      _vault.add(const UnlockVaultEvent());
    });
  }

  @override
  void dispose() {
    // Re-lock on the way out, which also drops any decrypted item. The bloc is
    // app-scoped and outlives this screen, so without this the next person to open
    // the vault would find it already open, with the last person's password still
    // in memory.
    _vault.add(const LockVaultEvent());

    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(kSearchDebounce, () {
      if (!mounted) return;
      context.read<VaultBloc>().add(SearchVaultEvent(query: query));
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VaultBloc, VaultState>(
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Vault'),
            actions: [
              // No add button while locked. Adding an item means encrypting one, and
              // the vault has not yet agreed that you are allowed to.
              if (state.isUnlocked)
                IconButton(
                  onPressed: () => showVaultItemSheet(context),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add an item',
                                        color: context.colors.primary,

                ),
            ],
          ),
          body: state.isUnlocked
              ? _Vault(
                  state: state,
                  search: _search,
                  onSearchChanged: _onSearchChanged,
                )
              : _Challenge(state: state),
        );
      },
    );
  }
}

/// [_Challenge] is the gate (Requirement 9.2).
///
/// It offers the biometric prompt again and a PIN pad. Both go through the app's own
/// [AuthRepository], so a wrong PIN here advances the **same** lockout counter as a
/// wrong PIN on the lock screen — the vault is not a second front door with no bolt
/// on it (Requirement 1.4).
class _Challenge extends StatefulWidget {
  const _Challenge({required this.state});

  final VaultState state;

  @override
  State<_Challenge> createState() => _ChallengeState();
}

class _ChallengeState extends State<_Challenge> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pin.text.trim().length < 4) return;

    context.read<VaultBloc>().add(UnlockVaultWithPINEvent(pin: _pin.text));
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = widget.state;

    final hasPIN = context.select<AuthBloc, bool>((b) => b.state.hasPIN);
    final hasBiometric =
        context.select<AuthBloc, bool>((b) => b.state.isBiometricAvailable);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: colors.primary),
            const Gap(20),
            Text('Your vault is locked', style: context.texts.titleMedium),
            const Gap(8),
            Text(
              hasPIN || hasBiometric
                  ? 'Unlock it to see what is inside.'
                  : 'Set an app PIN in Settings to use the vault.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
            const Gap(28),
            if (state.isUnlocking)
              const CircularProgressIndicator()
            else ...[
              if (hasBiometric) ...[
                FilledButton.icon(
                  onPressed: () =>
                      context.read<VaultBloc>().add(const UnlockVaultEvent()),
                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                  label: const Text('Unlock'),
                ),
                if (hasPIN) const Gap(20),
              ],
              if (hasPIN) ...[
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pin,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    maxLength: 12,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      hintText: 'PIN',
                      counterText: '',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const Gap(12),
                TextButton(
                  onPressed: _submit,
                  child: const Text('Unlock with PIN'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// [_Vault] is the unlocked list.
///
/// Every item on it is still ciphertext — the list is drawn from names and types
/// alone. A payload is decrypted only when one of these rows is tapped, and only
/// into the detail sheet.
class _Vault extends StatelessWidget {
  const _Vault({
    required this.state,
    required this.search,
    required this.onSearchChanged,
  });

  final VaultState state;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final visible = state.visibleItems;

    return Column(
      children: [
        Padding(
          padding: responsivePadding(context).copyWith(top: 4, bottom: 8),
          child: TextField(
            controller: search,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              // Says what it searches, because it is not what the user would assume.
              // Requirement 9.5 forbids vault *contents* from reaching a search
              // index, so a name is all there is to match on — and a search box that
              // silently failed to find a password by its username would look broken
              // rather than principled.
              hintText: 'Search by name',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
          ),
        ),
        _TypeFilters(state: state),
        Expanded(
          child: visible.isEmpty
              ? _Empty(isFiltered: state.isFiltered)
              : ListView.separated(
                  padding:
                      responsivePadding(context).copyWith(top: 8, bottom: 120),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (context, index) {
                    final item = visible[index];

                    return _VaultRow(
                      item: item,
                      folderName: state.folderOf(item)?.name,
                      onTap: () => showVaultDetailSheet(context, item: item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// [_VaultRow] is one item, drawn entirely from what is *not* secret about it.
class _VaultRow extends StatelessWidget {
  const _VaultRow({
    required this.item,
    required this.folderName,
    required this.onTap,
  });

  final VaultItem item;
  final String? folderName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texts = context.texts;

    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(item.type.icon, size: 20, color: colors.onSurfaceVariant),
              const Gap(14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: texts.labelLarge,
                    ),
                    const Gap(4),
                    Row(
                      children: [
                        Text(item.type.label, style: texts.labelSmall),
                        if (folderName != null) ...[
                          const Gap(8),
                          Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: colors.onSurfaceVariant,
                          ),
                          const Gap(4),
                          Flexible(
                            child: Text(
                              folderName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: texts.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeFilters extends StatelessWidget {
  const _TypeFilters({required this.state});

  final VaultState state;

  @override
  Widget build(BuildContext context) {
    final types = state.types;
    if (types.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: responsivePadding(context),
        children: [
          for (final type in types) ...[
            AppChoiceChip(
              label: '${type.label} ${state.countOf(type)}',
              isSelected: state.type == type,
              avatarIcon: type.icon,
              onSelected: (isSelected) => context.read<VaultBloc>().add(
                    FilterVaultEvent(
                      type: isSelected ? type : null,
                      folderId: state.folderId,
                    ),
                  ),
            ),
            const Gap(8),
          ],
          for (final folder in state.folders) ...[
            AppChoiceChip(
              label: folder.name,
              isSelected: state.folderId == folder.id,
              avatarIcon: Icons.folder_outlined,
              onSelected: (isSelected) => context.read<VaultBloc>().add(
                    FilterVaultEvent(
                      type: state.type,
                      folderId: isSelected ? folder.id : null,
                    ),
                  ),
            ),
            const Gap(8),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isFiltered});

  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isFiltered ? 'Nothing matched' : 'Your vault is empty',
              style: context.texts.titleMedium,
            ),
            const Gap(6),
            Text(
              isFiltered
                  ? 'Try a different name or clear the filters.'
                  : 'Passwords, bank details, IDs and cards — encrypted, '
                      'and readable only here.',
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
            if (!isFiltered) ...[
              const Gap(16),
              FilledButton.icon(
                onPressed: () => showVaultItemSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add an item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
