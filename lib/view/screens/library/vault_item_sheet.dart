import 'package:everything_app/bloc/vault/vault_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/folder.dart';
import 'package:everything_app/data/models/vault_item.dart';
import 'package:everything_app/view/widgets/option_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showVaultItemSheet] opens the add/edit sheet (Requirements 9.1, 9.3).
///
/// [secret] is the already-decrypted item when editing — passed from the detail
/// sheet, which is the only thing that has it. Editing cannot re-derive it: this
/// sheet holds a [VaultItem], whose payload is ciphertext.
Future<void> showVaultItemSheet(
  BuildContext context, {
  VaultItem? item,
  VaultSecret? secret,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => VaultItemSheet(item: item, secret: secret),
  );
}

/// [VaultItemSheet] adds or edits a vault item.
///
/// The fields are **free-form key/value pairs**, seeded from the type's usual shape
/// ([VaultItemType.fields]) rather than fixed by it. A vault whose card form had no
/// room for the PIN, or whose password form had no room for the recovery codes,
/// would be a vault the user kept a note in instead — and a note is not encrypted.
///
/// The values are plaintext while this sheet is open, which is unavoidable: they are
/// being typed. They are encrypted by `VaultService` on save and this widget's
/// controllers are disposed with the sheet.
class VaultItemSheet extends StatefulWidget {
  const VaultItemSheet({this.item, this.secret, super.key});

  final VaultItem? item;
  final VaultSecret? secret;

  @override
  State<VaultItemSheet> createState() => _VaultItemSheetState();
}

class _VaultItemSheetState extends State<VaultItemSheet> {
  final _name = TextEditingController();

  /// One controller per field, keyed by the field's name, in insertion order — so a
  /// card's number stays above its CVV.
  final Map<String, TextEditingController> _fields = {};

  late final List<Folder> _folders;

  late VaultItemType _type;

  String? _folderId;

  VaultItem? get _original => widget.item;

  bool get _isEditing => _original != null;

  @override
  void initState() {
    super.initState();

    _folders = context.read<VaultBloc>().state.folders;

    final existing = _original;

    if (existing == null) {
      _type = VaultItemType.password;
      _resetFields(_type);
      return;
    }

    _name.text = existing.name;
    _type = existing.type;
    _folderId = existing.folderId;

    // The decrypted fields, plus any of the type's usual ones the item does not have
    // — so an item saved before a field existed can gain it by being edited.
    final saved = widget.secret?.fields ?? const <String, String>{};

    for (final field in _type.fields) {
      _fields[field] = TextEditingController(text: saved[field] ?? '');
    }
    for (final entry in saved.entries) {
      _fields.putIfAbsent(
        entry.key,
        () => TextEditingController(text: entry.value),
      );
    }
  }

  /// [_resetFields] rebuilds the form for [type].
  ///
  /// Anything the user has already typed is carried across by name, so switching a
  /// password to a bank detail does not silently throw away the note they had put in
  /// a field both types happen to have.
  void _resetFields(VaultItemType type) {
    final kept = {
      for (final entry in _fields.entries)
        if (entry.value.text.isNotBlank) entry.key: entry.value.text,
    };

    for (final controller in _fields.values) {
      controller.dispose();
    }
    _fields.clear();

    for (final field in type.fields) {
      _fields[field] = TextEditingController(text: kept[field] ?? '');
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_name.text.isBlank) {
      context.showSnack('This item needs a name.', isError: true);
      return;
    }

    final now = DateTime.now();

    final item = VaultItem(
      id: _original?.id ?? '',
      type: _type,
      name: _name.text.trim(),
      // A placeholder. `VaultService.save` always rewrites this from the secret
      // below — the caller has no way to produce valid ciphertext, and accepting one
      // from here would be the one hole an unencrypted payload could get through.
      encryptedPayload: '',
      folderId: _folderId,
      createdAt: _original?.createdAt ?? now,
      updatedAt: now,
    );

    final secret = VaultSecret(
      itemId: _original?.id ?? '',
      fields: {
        for (final entry in _fields.entries)
          if (entry.value.text.isNotBlank) entry.key: entry.value.text.trim(),
      },
    );

    context.read<VaultBloc>().add(
          SaveVaultItemEvent(item: item, secret: secret),
        );

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
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: context.texts.titleMedium,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  // Said plainly, because it is the one field that is *not* encrypted
                  // — Requirement 9.5 needs a vault item findable by title, and a
                  // name is the only field that can be both searchable and safe.
                  hintText: 'Name (not encrypted)',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const Gap(12),
              _TypeRow(
                type: _type,
                onSelected: (type) => setState(() {
                  _type = type;
                  _resetFields(type);
                }),
              ),
              const Gap(16),
              for (final entry in _fields.entries) ...[
                TextField(
                  controller: entry.value,
                  obscureText:
                      VaultItemType.secretFields.contains(entry.key),
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: entry.key,
                    isDense: true,
                  ),
                ),
                const Gap(12),
              ],
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          OptionPillMenu<String>(
                            icon: Icons.folder_outlined,
                            label: _folderName ?? 'Folder',
                            isSet: _folderId != null,
                            accent: colors.primary,
                            onSelected: (id) => setState(
                              () => _folderId = id.isEmpty ? null : id,
                            ),
                            entries: [
                              const PillOption(
                                value: '',
                                label: 'No folder',
                                icon: Icons.folder_off_outlined,
                              ),
                              if (_folders.isNotEmpty) const PillDivider(),
                              for (final folder in _folders)
                                PillOption(
                                  value: folder.id,
                                  label: folder.name,
                                  icon: Icons.folder_outlined,
                                ),
                            ],
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
                      icon: const Icon(Icons.lock_outline_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? get _folderName {
    for (final folder in _folders) {
      if (folder.id == _folderId) return folder.name;
    }
    return null;
  }
}

/// [_TypeRow] is the six item types (Requirement 9.3).
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, required this.onSelected});

  final VaultItemType type;
  final ValueChanged<VaultItemType> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: VaultItemType.values.length,
        separatorBuilder: (_, _) => const Gap(8),
        itemBuilder: (context, index) {
          final value = VaultItemType.values[index];
          final isSelected = value == type;

          return Semantics(
            button: true,
            selected: isSelected,
            child: GestureDetector(
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
            ),
          );
        },
      ),
    );
  }
}
