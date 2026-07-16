import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// [AppChoiceChip] is the app's selectable chip.
///
/// A bare Material [ChoiceChip] is unreadable under this theme: `chipTheme` in the
/// protected `core/utils/theme.dart` sets a label colour but no `selectedColor`,
/// so a selected chip falls back to the scheme's secondary container — a grey too
/// close to the label colour to read against. This widget pins both, and every
/// chip in the app goes through it.
///
/// [avatarColor] draws the leading dot used by the priority and category pickers.
/// [avatarIcon] draws a leading glyph instead, used by the account-type picker.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
    this.avatarColor,
    this.avatarIcon,
    super.key,
  });

  final String label;
  final bool isSelected;
  final ValueChanged<bool> onSelected;
  final Color? avatarColor;
  final IconData? avatarIcon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Selected, the chip is filled with the accent, so its own foreground has to
    // invert with it — an avatar left on the accent colour disappears into it.
    final foreground = isSelected ? colors.onPrimary : colors.onSurfaceVariant;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false,
      selectedColor: colors.primary,
      backgroundColor: colors.surfaceContainer,
      side: BorderSide(color: isSelected ? colors.primary : colors.outline),
      labelStyle: context.texts.labelMedium?.copyWith(
        color: foreground,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      avatar: switch ((avatarIcon, avatarColor)) {
        (final IconData icon, _) => Icon(icon, size: 14, color: foreground),
        (_, final Color color) => Icon(
            Icons.brightness_1_rounded,
            size: 12,
            color: isSelected ? colors.onPrimary : color,
          ),
        _ => null,
      },
      onSelected: onSelected,
    );
  }
}
