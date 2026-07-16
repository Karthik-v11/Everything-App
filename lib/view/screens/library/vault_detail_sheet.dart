import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/view/screens/library/vault_item_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showVaultDetailSheet] opens one vault item and decrypts it (Requirement 9.2).
///
/// This is the **only** place in the app where a vault plaintext is on screen, and
/// the sheet clears it on the way out. `whenComplete` rather than an `onPopped`
/// callback, so it runs however the sheet is dismissed — the button, the drag, the
/// back gesture, or a route being popped from under it.
Future<void> showVaultDetailSheet(
  BuildContext context, {
  required VaultItem item,
}) {
  final bloc = context.read<VaultBloc>()..add(RevealVaultItemEvent(id: item.id));

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VaultDetailSheet(item: item),
  ).whenComplete(() => bloc.add(const ClearRevealedEvent()));
}

/// [VaultDetailSheet] shows a decrypted item.
///
/// Its fields arrive through [VaultState.revealed], which holds exactly one item at
/// a time and is dropped when this sheet closes. The sheet keeps no copy of its own:
/// a `String password` field on this widget's state would be a second place the
/// plaintext lives, outliving the bloc's own attempt to forget it.
///
/// Secret fields are masked until asked for (Requirement 23.4). The mask is a fixed
/// eight dots regardless of the value's length — see [kMaskedSecret].
class VaultDetailSheet extends StatefulWidget {
  const VaultDetailSheet({required this.item, super.key});

  final VaultItem item;

  @override
  State<VaultDetailSheet> createState() => _VaultDetailSheetState();
}

class _VaultDetailSheetState extends State<VaultDetailSheet> {
  /// Which secret fields the user has asked to see. Names, not values — this set
  /// holds no plaintext.
  final Set<String> _shown = {};

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final item = widget.item;

    return BlocBuilder<VaultBloc, VaultState>(
      builder: (context, state) {
        final secret = state.revealed;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(item.type.icon, size: 20, color: colors.primary),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.titleMedium,
                        ),
                        Text(item.type.label, style: context.texts.labelSmall),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      showVaultItemSheet(context, item: item, secret: secret);
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit item',
                  ),
                ],
              ),
              const Gap(16),
              if (state.isRevealing || secret == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (secret.fields.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'This item has nothing in it.',
                    style: context.texts.bodySmall,
                  ),
                )
              else
                for (final entry in secret.fields.entries)
                  _Field(
                    label: entry.key,
                    value: entry.value,
                    isSecret: VaultItemType.secretFields.contains(entry.key),
                    isShown: _shown.contains(entry.key),
                    onToggle: () => setState(() {
                      if (!_shown.remove(entry.key)) _shown.add(entry.key);
                    }),
                  ),
              const Gap(8),
              TextButton.icon(
                onPressed: () {
                  context.read<VaultBloc>().add(
                        DeleteVaultItemEvent(id: item.id),
                      );
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete item'),
                style: TextButton.styleFrom(foregroundColor: colors.error),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [_Field] is one decrypted field: its name, its value, and the two things you can
/// do with it — reveal it and copy it.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.isSecret,
    required this.isShown,
    required this.onToggle,
  });

  final String label;
  final String value;
  final bool isSecret;
  final bool isShown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isHidden = isSecret && !isShown;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: context.texts.labelSmall),
                const Gap(3),
                Text(
                  isHidden ? kMaskedSecret : value,
                  maxLines: isHidden ? 1 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.labelLarge?.copyWith(
                    // Monospace for a revealed secret: a password is read character
                    // by character, and an `l` next to a `1` in a proportional face
                    // is a password typed wrong somewhere else.
                    fontFamily: isSecret && !isHidden ? 'JetBrainsMono' : null,
                  ),
                ),
              ],
            ),
          ),
          if (isSecret)
            IconButton(
              onPressed: onToggle,
              icon: Icon(
                isShown
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              color: colors.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              tooltip: isShown ? 'Hide' : 'Show',
            ),
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              context.showSnack('$label copied.');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            color: colors.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy $label',
          ),
        ],
      ),
    );
  }
}
