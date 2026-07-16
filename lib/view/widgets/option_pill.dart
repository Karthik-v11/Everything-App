import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:flutter/material.dart';

/// [OptionPill] is a compact button that is both the control and the readout: it
/// shows the value it sets. It is what keeps the task and transaction sheets to a
/// single row of options under the field.
///
/// [isSet] tints the pill in [accent] to say the value is the user's rather than
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
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

/// [OptionPillMenu] is an [OptionPill] that opens a menu of [entries] over itself.
///
/// It is built on [MenuAnchor] rather than [PopupMenuButton], and that is the
/// whole point of it. A [PopupMenuButton] shows its menu by **pushing a route**,
/// and pushing a route hands the focus scope to the new one — which closes the
/// keyboard. Both sheets that use this widget open with the caret already in a
/// field, so setting a category or an account from the row of pills underneath
/// used to dismiss the keyboard and leave the user to tap the field again to
/// carry on typing.
///
/// [MenuAnchor] renders into the [Overlay] instead. No route is pushed, nothing
/// requests focus (its menu only takes focus for keyboard traversal), so the
/// field keeps the caret and the keyboard stays up through as many selections as
/// the user cares to make.
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
      // Clear of the pill rather than over it, so the value being changed stays
      // visible while the menu that changes it is open.
      alignmentOffset: const Offset(0, 4),
      menuChildren: [
        for (final entry in entries)
          switch (entry) {
            PillDivider<T>() => const Divider(height: 1),
            PillOption<T>(:final value, :final label, :final icon, :final iconColor) =>
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
