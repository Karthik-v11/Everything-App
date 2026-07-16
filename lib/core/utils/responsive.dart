import 'package:flutter/material.dart';

/// Responsive layout helpers.
///
/// The app is phone-first and one-handed, so these breakpoints exist mainly to
/// keep large phones and tablets from stretching content to unreadable widths.
///
/// DO NOT MODIFY.

/// [Breakpoint] follows Material 3's window size classes.
class Breakpoint {
  const Breakpoint._();

  static const double compact = 600;
  static const double medium = 840;
}

/// [compact] is a phone in portrait — the primary target.
bool compact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < Breakpoint.compact;

/// [medium] is a large phone in landscape or a small tablet.
bool medium(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= Breakpoint.compact && width < Breakpoint.medium;
}

/// [expanded] is a tablet or desktop-class window.
bool expanded(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoint.medium;

/// [responsivePadding] is the standard horizontal page gutter.
EdgeInsets responsivePadding(BuildContext context) => EdgeInsets.symmetric(
      horizontal: compact(context) ? 16 : 24,
    );

/// [contentMaxWidth] caps line length on wide windows so text stays readable.
double contentMaxWidth(BuildContext context) =>
    expanded(context) ? 720 : double.infinity;

/// [Gap] is a fixed-size spacer, sized on both axes so it works inside a [Row]
/// and a [Column] alike. It exists so that layouts read as a flat list of
/// children instead of a tree of nested `Padding` widgets.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}
