import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:flutter/material.dart';

/// A compact button that is both the control and the readout: it shows the value
/// it sets.
///
/// [isSet] tints the pill in [accent] to mark the value as the user's rather than
/// the default.
class OptionPill extends StatelessWidget {
  const OptionPill({
    required this.icon,
    required this.label,
    required this.isSet,
    required this.accent,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool isSet;
  final Color accent;
  final VoidCallback? onTap;

  /// Kept as a minimum rather than a fixed height so the pill sizes itself in an
  /// unbounded parent (a [Wrap]) and still fills a fixed-height row.
  static const double minHeight = 38;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = isSet ? accent : colors.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        // No `alignment`: it would make the pill fill the width it is offered,
        // which in a [Wrap] is the whole row. The Row below centres the content
        // within [minHeight] on its own.
        constraints: const BoxConstraints(minHeight: minHeight),
        decoration: BoxDecoration(
          color: isSet ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSet ? accent.withValues(alpha: 0.5) : colors.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const Gap(6),
            Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: foreground,
                fontWeight: isSet ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [PillEntry] is one line of an [OptionPillMenu].
sealed class PillEntry<T> {
  const PillEntry();
}

/// [PillOption] is a selectable value. [icon] and [iconColor] are optional — a
/// category shows its colour, a date shows nothing.
class PillOption<T> extends PillEntry<T> {
  const PillOption({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
  });

  final T value;
  final String label;
  final IconData? icon;
  final Color? iconColor;
}

/// [PillDivider] separates groups of options — the day shortcuts from the pickers.
class PillDivider<T> extends PillEntry<T> {
  const PillDivider();
}

/// An [OptionPill] that opens a menu of [entries] over itself.
///
/// Must stay on [MenuAnchor], not [PopupMenuButton]: the latter shows its menu by
/// pushing a route, which hands over the focus scope and closes the keyboard. The
/// sheets using this open with the caret in a field, so [MenuAnchor]'s overlay is
/// what keeps the keyboard up across selections.
class OptionPillMenu<T> extends StatelessWidget {
  const OptionPillMenu({
    required this.icon,
    required this.label,
    required this.isSet,
    required this.accent,
    required this.entries,
    required this.onSelected,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool isSet;
  final Color accent;
  final List<PillEntry<T>> entries;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      // Offset clear of the pill so the value being changed stays visible while
      // the menu is open.
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final entry in entries)
          switch (entry) {
            PillDivider<T>() => const Divider(height: 1),
            PillOption<T>(
              :final value,
              :final label,
              :final icon,
              :final iconColor,
            ) =>
              MenuItemButton(
                leadingIcon: icon == null
                    ? null
                    : Icon(icon, size: 16, color: iconColor),
                onPressed: () => onSelected(value),
                child: Text(label),
              ),
          },
      ],
      builder: (context, controller, child) => OptionPill(
        icon: icon,
        label: label,
        isSet: isSet,
        accent: accent,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
