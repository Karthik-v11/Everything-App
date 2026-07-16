import 'package:everything_app/core/utils/extensions.dart';
import 'package:flutter/material.dart';

/// [ModuleAppBar] is the header every module tab wears: the module's name on the
/// left, that module's own actions on the right.
///
/// It exists so the four tabs cannot drift apart — before it, Dashboard and
/// Library wore the placeholder's header, Tasks and Finance had each grown their
/// own, and the three disagreed on height, spacing and what belonged in them.
///
/// [height] is fixed rather than intrinsic so that swapping the header's contents
/// — Tasks trading its title for a search field — does not shift the content
/// underneath by a pixel.
///
/// Settings is deliberately not an action here: it is global, so it lives in the
/// floating dock rather than being repeated in four headers.
class ModuleAppBar extends StatelessWidget {
  const ModuleAppBar({
    required this.title,
    this.actions = const [],
    super.key,
  });

  /// The height a module header occupies, whatever it is showing.
  static const double height = 56;

  final String title;

  /// Trailing, right-aligned actions — usually [IconButton]s.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.texts.labelMedium)),
          ...actions,
        ],
      ),
    );
  }
}
