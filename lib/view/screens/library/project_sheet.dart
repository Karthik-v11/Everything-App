import 'package:everything_app/bloc/projects/projects_bloc.dart';
import 'package:everything_app/core/utils/app_colors.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:everything_app/data/models/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// [showProjectSheet] opens the create/edit sheet (Requirement 10.1).
///
/// [parentProjectId] makes it a sub-project (Requirement 10.2) — the same sheet,
/// with a parent. A separate "new sub-project" form would be this one with a field
/// pre-filled.
Future<void> showProjectSheet(
  BuildContext context, {
  Project? project,
  String? parentProjectId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ProjectSheet(
      project: project,
      parentProjectId: parentProjectId,
    ),
  );
}

/// [ProjectSheet] creates or edits a project.
class ProjectSheet extends StatefulWidget {
  const ProjectSheet({this.project, this.parentProjectId, super.key});

  final Project? project;
  final String? parentProjectId;

  @override
  State<ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends State<ProjectSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  int? _colorValue;

  Project? get _original => widget.project;

  bool get _isEditing => _original != null;

  @override
  void initState() {
    super.initState();

    final existing = _original;
    if (existing == null) return;

    _name.text = existing.name;
    _description.text = existing.description ?? '';
    _colorValue = existing.colorValue;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.isBlank) {
      context.showSnack('A project needs a name.', isError: true);
      return;
    }

    final description = _description.text.trim();
    final now = DateTime.now();

    final project = Project(
      id: _original?.id ?? '',
      name: _name.text.trim(),
      description: description.isEmpty ? null : description,
      // On edit the project keeps whichever parent it already has: this sheet is not
      // where a project is moved, and defaulting to the sheet's argument would
      // silently re-root it every time its name was changed.
      parentProjectId: _original?.parentProjectId ?? widget.parentProjectId,
      colorValue: _colorValue,
      createdAt: _original?.createdAt ?? now,
      updatedAt: now,
    );

    context.read<ProjectsBloc>().add(
          SaveProjectEvent(project: project, isEditing: _isEditing),
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSubProject =
        (_original?.parentProjectId ?? widget.parentProjectId) != null;

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
              if (isSubProject && !_isEditing) ...[
                Text('New sub-project', style: context.texts.labelSmall),
                const Gap(8),
              ],
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
                  hintText: 'Project name',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const Gap(8),
              TextField(
                controller: _description,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'What is it about?',
                  isDense: true,
                ),
              ),
              const Gap(16),
              _ColorRow(
                selected: _colorValue,
                onSelected: (value) => setState(() => _colorValue = value),
              ),
              const Gap(16),
              Row(
                children: [
                  const Spacer(),
                  SizedBox.square(
                    dimension: 44,
                    child: IconButton.filled(
                      onPressed: _name.text.isBlank ? null : _submit,
                      tooltip: 'Save project',
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        disabledBackgroundColor: colors.surfaceContainerHighest,
                        disabledForegroundColor: colors.onSurfaceVariant,
                      ),
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
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
}

/// [_ColorRow] is the project's colour — the spine down the left of its card, and
/// what tells two projects apart in a list at a glance.
///
/// The first swatch is "no colour", which means the accent: a project that has not
/// been given one should look like the app rather than like a colour someone forgot
/// to pick.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.selected, required this.onSelected});

  final int? selected;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Swatch(
            color: colors.primary,
            label: 'Default colour',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          const Gap(10),
          for (final (index, color) in AppColors.chartPalette.indexed) ...[
            _Swatch(
              color: color,
              // The palette is bare hex with no name map, so the swatches are
              // announced by their position in the row.
              label: 'Colour ${index + 1}',
              isSelected: selected == color.toARGB32(),
              onTap: () => onSelected(color.toARGB32()),
            ),
            const Gap(10),
          ],
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? context.colors.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}
