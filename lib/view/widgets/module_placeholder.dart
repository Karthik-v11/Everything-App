import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/view/widgets/module_app_bar.dart';
import 'package:flutter/material.dart';

/// [ModulePlaceholder] is the scaffold each module screen wears until its real
/// content lands.
///
/// The header, gutters and typography here are the ones the real screens keep.
/// Each use is removed as Phases 3–7 fill its module in.
///
/// [title] is the monospace module label. [phase] names the phase that replaces
/// this placeholder.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({
    required this.title,
    required this.phase,
    super.key,
  });

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: responsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ModuleAppBar(title: title),
            const Gap(24),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: texts.headlineMedium),
                    const Gap(8),
                    Text(
                      'Arrives in $phase.',
                      style: texts.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
