import 'package:everything_app/bloc/ai/ai_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// [showAiSheet] opens the AI assistant from the floating dock (Requirement 16).
///
/// It is a modal sheet, not a route — like the task and transaction sheets — so it
/// opens over whatever screen the dock was tapped from with the keyboard already
/// up. The root navigator is used so it covers the bottom navigation and the dock
/// itself.
Future<void> showAiSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AiSheet(),
  );
}

/// [AiSheet] is one line in, one action out.
///
/// The user types in natural language; the assistant guesses whether it is a task,
/// an expense, a note, a search or a question and preselects that mode, which the
/// user can override with the chips. Task and Expense show a live preview of what
/// will be created so a wrong parse is caught before it is saved; Search and Ask
/// keep their results on screen.
class AiSheet extends StatefulWidget {
  const AiSheet({super.key});

  @override
  State<AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<AiSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The bloc is app-scoped: reset it so the sheet opens on a clean session
    // rather than the last one's results.
    context.read<AiBloc>().add(const AiOpened());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Rebuild now so the send button reflects the field immediately; the bloc's
    // classify-and-preview is debounced and lands a moment later.
    setState(() {});
    context.read<AiBloc>().add(AiInputChanged(input: value));
  }

  void _onModeSelected(AiIntent mode) {
    context.read<AiBloc>().add(AiModeSelected(mode: mode));
    _focus.requestFocus();
  }

  void _submit() =>
      context.read<AiBloc>().add(AiSubmitted(input: _controller.text));

  /// [_openResult] hands off to the module that owns a search hit, closing the
  /// sheet first — the same destinations Global Search uses. The vault challenges
  /// before it shows a row, so a title here has given nothing away.
  void _openResult(SearchResult result) {
    // Capture the router before popping: closing the sheet unmounts this element,
    // and reading navigation off a defunct context would throw.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();

    switch (result.module) {
      case SearchModule.tasks:
        router.goNamed(tasksRoute);
      case SearchModule.transactions:
        router.goNamed(transactionsRoute);
      case SearchModule.bookmarks:
        router.goNamed(bookmarksRoute);
      case SearchModule.toBuy:
        router.goNamed(toBuyRoute);
      case SearchModule.watchlist:
        router.goNamed(watchlistRoute);
      case SearchModule.vault:
        router.goNamed(vaultRoute);
      case SearchModule.projects:
        router.goNamed(projectRoute, pathParameters: {'id': result.id});
      case SearchModule.documents:
        router.goNamed(documentRoute, pathParameters: {'id': result.id});
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AiBloc, AiState>(
      listenWhen: (previous, current) =>
          previous.createdMessage != current.createdMessage ||
          previous.error != current.error,
      listener: (context, state) {
        if (state.createdMessage.isNotBlank) {
          context.showSnack(state.createdMessage);
          Navigator.of(context).pop();
        } else if (state.error.isNotBlank) {
          context.showSnack(state.error, isError: true);
        }
      },
      builder: (context, state) {
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          autofocus: true,
                          maxLines: null,
                          textInputAction: TextInputAction.done,
                          textCapitalization: TextCapitalization.sentences,
                          style: context.texts.titleMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            hintText: 'Add a task, log a spend, or ask…',
                          ),
                          onChanged: _onChanged,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _SendButton(
                        isEnabled: _controller.text.trim().isNotEmpty &&
                            !state.isBusy,
                        isBusy: state.isBusy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ModeChips(
                    selected: state.mode,
                    onSelected: _onModeSelected,
                  ),
                  _Outcome(state: state, onOpenResult: _openResult),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [_ModeChips] is the row that shows and changes the active mode.
class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.selected, required this.onSelected});

  final AiIntent selected;
  final ValueChanged<AiIntent> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final mode in AiIntent.values) ...[
            AppChoiceChip(
              label: mode.label,
              avatarIcon: mode.icon,
              isSelected: mode == selected,
              onSelected: (_) => onSelected(mode),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// [_Outcome] is the area under the chips: a clarifying prompt, a live preview of
/// what will be created, search results, or an answer — whichever the state holds.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.state, required this.onOpenResult});

  final AiState state;
  final void Function(SearchResult result) onOpenResult;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (state.clarification.isNotBlank) {
      children.add(_Prompt(message: state.clarification));
    }

    switch (state.mode) {
      case AiIntent.task:
        if (state.taskPreview case final preview?) {
          children.add(_TaskPreview(preview: preview));
        }
      case AiIntent.expense:
        if (state.transactionPreview case final preview?) {
          children.add(_TransactionPreview(preview: preview));
        }
      case AiIntent.bookmark:
        if (state.bookmarkPreview case final preview?) {
          children.add(_BookmarkPreview(preview: preview));
        }
      case AiIntent.toBuy:
        if (state.toBuyPreview case final preview?) {
          children.add(_ToBuyPreview(preview: preview));
        }
      case AiIntent.watchItem:
        if (state.watchPreview case final preview?) {
          children.add(_WatchPreview(preview: preview));
        }
      case AiIntent.vaultItem:
        if (state.vaultPreview case final preview?) {
          children.add(_VaultPreview(preview: preview));
        }
      case AiIntent.project:
        if (state.projectPreview case final preview?) {
          children.add(_ProjectPreview(preview: preview));
        }
      case AiIntent.search:
        if (state.hasResults) {
          children.add(_ResultsList(results: state.results, onTap: onOpenResult));
        }
      case AiIntent.question:
        if (state.hasAnswer) children.add(_Answer(text: state.answer));
      case AiIntent.note:
        break;
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// [_Prompt] is the clarifying question shown when the parse was too weak to act
/// (Requirement 16.7).
class _Prompt extends StatelessWidget {
  const _Prompt({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: context.colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPreview extends StatelessWidget {
  const _TaskPreview({required this.preview});

  final ParsedTaskIntent preview;

  @override
  Widget build(BuildContext context) {
    if (preview.title.trim().isEmpty) return const SizedBox.shrink();

    final parts = <String>[
      preview.title.trim(),
      if (preview.dueDate case final due?) due.relativeLabel,
    ];

    return _PreviewCard(
      icon: AiIntent.task.icon,
      text: parts.join('  ·  '),
    );
  }
}

class _TransactionPreview extends StatelessWidget {
  const _TransactionPreview({required this.preview});

  final ParsedTransactionIntent preview;

  @override
  Widget build(BuildContext context) {
    if (!preview.hasAmount) return const SizedBox.shrink();

    final text = '${preview.type.label}  ·  '
        '${Helpers.formatMoney(preview.amountMinor, compact: true)}  ·  '
        '${preview.category}';

    return _PreviewCard(icon: AiIntent.expense.icon, text: text);
  }
}

class _BookmarkPreview extends StatelessWidget {
  const _BookmarkPreview({required this.preview});

  final ParsedBookmarkInput preview;

  @override
  Widget build(BuildContext context) {
    if (preview.url.isEmpty) return const SizedBox.shrink();

    return _PreviewCard(
      icon: AiIntent.bookmark.icon,
      text: preview.url,
    );
  }
}

class _ToBuyPreview extends StatelessWidget {
  const _ToBuyPreview({required this.preview});

  final ParsedToBuyInput preview;

  @override
  Widget build(BuildContext context) {
    if (preview.name.isEmpty) return const SizedBox.shrink();

    final parts = <String>[
      preview.name,
      if (preview.store != null) 'at ${preview.store}',
      if (preview.estimatedPriceMinor != null)
        Helpers.formatMoney(preview.estimatedPriceMinor!, compact: true),
    ];

    return _PreviewCard(
      icon: AiIntent.toBuy.icon,
      text: parts.join('  ·  '),
    );
  }
}

class _WatchPreview extends StatelessWidget {
  const _WatchPreview({required this.preview});

  final ParsedWatchInput preview;

  @override
  Widget build(BuildContext context) {
    if (preview.title.isEmpty) return const SizedBox.shrink();

    return _PreviewCard(
      icon: AiIntent.watchItem.icon,
      text: '${preview.title}  ·  ${preview.mediaType.label}',
    );
  }
}

class _VaultPreview extends StatelessWidget {
  const _VaultPreview({required this.preview});

  final ParsedVaultInput preview;

  @override
  Widget build(BuildContext context) {
    if (preview.name.isEmpty) return const SizedBox.shrink();

    return _PreviewCard(
      icon: AiIntent.vaultItem.icon,
      text: '${preview.name}  ·  ${preview.type.label}',
    );
  }
}

class _ProjectPreview extends StatelessWidget {
  const _ProjectPreview({required this.preview});

  final ParsedProjectInput preview;

  @override
  Widget build(BuildContext context) {
    if (preview.name.isEmpty) return const SizedBox.shrink();

    return _PreviewCard(
      icon: AiIntent.project.icon,
      text: preview.name,
    );
  }
}

/// [_PreviewCard] is the shared one-line "this is what I'll create" row.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({required this.results, required this.onTap});

  final List<SearchResult> results;
  final void Function(SearchResult result) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final result in results.take(8))
          Material(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: Icon(result.module.icon, size: 20),
              title: Text(
                result.title.isBlank ? 'Untitled' : result.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(result.module.label),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onTap(result),
            ),
          ),
      ].separatedBy(const SizedBox(height: 8)),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: context.texts.bodyMedium),
    );
  }
}

/// [_SendButton] mirrors the task and transaction sheets' send control.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.isEnabled,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isEnabled;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.square(
      dimension: 44,
      child: IconButton.filled(
        onPressed: isEnabled ? onPressed : null,
        tooltip: 'Send',
        style: IconButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.surfaceContainerHighest,
          disabledForegroundColor: colors.onSurfaceVariant,
        ),
        icon: isBusy
            ? SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onPrimary,
                ),
              )
            : const Icon(Icons.arrow_upward_rounded, size: 20),
      ),
    );
  }
}
