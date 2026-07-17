import 'package:everything_app/bloc/ai/ai_bloc.dart';
import 'package:everything_app/bloc/speech/speech_bloc.dart';
import 'package:everything_app/core/route/routes.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/entity/ai_intent.dart';
import 'package:everything_app/data/entity/parsed_ai_inputs.dart';
import 'package:everything_app/data/entity/parsed_task_intent.dart';
import 'package:everything_app/data/entity/parsed_transaction_intent.dart';
import 'package:everything_app/data/models/search_result.dart';
import 'package:everything_app/view/screens/tasks/task_sheet.dart';
import 'package:everything_app/view/widgets/app_choice_chip.dart';
import 'package:everything_app/view/widgets/siri_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Opens the AI assistant from the floating dock (Requirement 16).
///
/// A modal sheet, not a route, so it opens over whatever screen the dock was
/// tapped from with the keyboard already up. Uses the root navigator so it covers
/// the bottom navigation and the dock itself.
Future<void> showAiSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const AiSheet(),
  );
}

/// One line of natural language in, one action out.
///
/// The assistant classifies the input as task, expense, note, search or question
/// and preselects that mode; the chips override it. Task and Expense show a live
/// preview so a wrong parse is caught before it is saved.
class AiSheet extends StatefulWidget {
  const AiSheet({super.key});

  @override
  State<AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<AiSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// [_speech] is held rather than read in [dispose], where the element is
  /// already defunct and `context.read` throws.
  late final SpeechBloc _speech;

  @override
  void initState() {
    super.initState();
    // The bloc is app-scoped: reset it so the sheet opens on a clean session
    // rather than the last one's results.
    context.read<AiBloc>().add(const AiOpened());

    _speech = context.read<SpeechBloc>()
      // Also app-scoped, and it holds a transcript. Without this the next open
      // would replay the last session's words into the field.
      ..add(const CancelDictationEvent());
  }

  @override
  void dispose() {
    // A session left open by a swipe-down keeps the OS recording indicator lit
    // over an app that is not listening.
    _speech.add(const CancelDictationEvent());
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

  /// Writes what was heard into the field and runs it through the same path
  /// typing takes.
  ///
  /// Speech lands in the [TextEditingController] rather than going straight to
  /// [AiBloc] so a misheard word can be corrected before it becomes a task or an
  /// amount.
  void _onDictation(String transcript) {
    if (transcript == _controller.text) return;

    _controller
      ..text = transcript
      // Dictation appends, so the caret belongs at the end — otherwise it sits
      // at offset 0 and the next typed character lands in front of the sentence.
      ..selection = TextSelection.collapsed(offset: transcript.length);

    _onChanged(transcript);
  }

  void _toggleMic() {
    final speech = context.read<SpeechBloc>();
    if (speech.state.isListening) {
      speech.add(const StopDictationEvent());
      return;
    }

    // The keyboard and the mic ask for the same sentence, so drop the keyboard
    // rather than leave it up over the waveform.
    _focus.unfocus();
    speech.add(const StartDictationEvent());
  }

  void _onModeSelected(AiIntent mode) {
    context.read<AiBloc>().add(AiModeSelected(mode: mode));
    _focus.requestFocus();
  }

  void _submit() =>
      context.read<AiBloc>().add(AiSubmitted(input: _controller.text));

  /// Hands off to the module that owns a search hit, closing the sheet first —
  /// the same destinations Global Search uses. The vault challenges before it
  /// shows a row, so a title here gives nothing away.
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
    return MultiBlocListener(
      listeners: [
        // Every partial result, not just the final one, so the field fills in as
        // the user speaks rather than all at once when they stop.
        BlocListener<SpeechBloc, SpeechState>(
          listenWhen: (previous, current) =>
              previous.transcript != current.transcript &&
              current.transcript.isNotEmpty,
          listener: (context, state) => _onDictation(state.transcript),
        ),
        BlocListener<SpeechBloc, SpeechState>(
          listenWhen: (previous, current) =>
              previous.error != current.error && current.error.isNotEmpty,
          listener: (context, state) =>
              context.showSnack(state.error, isError: true),
        ),
      ],
      child: _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                            hintText: 'Add a task, log a spend, or ask…',
                          ),
                          onChanged: _onChanged,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MicButton(onPressed: _toggleMic),
                      const SizedBox(width: 8),
                      _SendButton(
                        isEnabled:
                            _controller.text.trim().isNotEmpty && !state.isBusy,
                        isBusy: state.isBusy,
                        onPressed: _submit,
                      ),
                    ],
                  ),
                  const _DictationBar(),
                  const SizedBox(height: 12),
                  _ModeChips(selected: state.mode, onSelected: _onModeSelected),
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

/// [_ModeChips] shows and changes the active mode.
///
/// Wraps rather than scrolling sideways: the mode is the one thing here the user
/// overrides, and the later modes sat off the right edge unfound.
class _ModeChips extends StatelessWidget {
  const _ModeChips({required this.selected, required this.onSelected});

  final AiIntent selected;
  final ValueChanged<AiIntent> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      // No runSpacing: a ChoiceChip's padded tap target already puts ~8px above
      // and below its outline, so any here lands on top of that.
      children: [
        for (final mode in AiIntent.values)
          AppChoiceChip(
            label: mode.label,
            avatarIcon: mode.icon,
            isSelected: mode == selected,
            onSelected: (_) => onSelected(mode),
          ),
      ],
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
          children.add(
            _ResultsList(results: state.results, onTap: onOpenResult),
          );
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
      if (preview.recurrence case final repeat?) repeat.label,
      // A reminder without a due date is dropped on save, so it is not promised
      // here either.
      if (preview.reminderOffset case final offset?)
        if (preview.dueDate != null) reminderOffsetLabel(offset),
    ];

    return _PreviewCard(icon: AiIntent.task.icon, text: parts.join('  ·  '));
  }
}

class _TransactionPreview extends StatelessWidget {
  const _TransactionPreview({required this.preview});

  final ParsedTransactionIntent preview;

  @override
  Widget build(BuildContext context) {
    if (!preview.hasAmount) return const SizedBox.shrink();

    final text =
        '${preview.type.label}  ·  '
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

    return _PreviewCard(icon: AiIntent.bookmark.icon, text: preview.url);
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

    return _PreviewCard(icon: AiIntent.toBuy.icon, text: parts.join('  ·  '));
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

    return _PreviewCard(icon: AiIntent.project.icon, text: preview.name);
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

/// Starts and stops dictation (Requirement 16). A toggle rather than
/// hold-to-talk, so the user need not keep a thumb on the screen while talking.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return BlocBuilder<SpeechBloc, SpeechState>(
      buildWhen: (previous, current) =>
          previous.isListening != current.isListening ||
          previous.isUnavailable != current.isUnavailable,
      builder: (context, state) {
        final isListening = state.isListening;

        return SizedBox.square(
          dimension: 44,
          child: IconButton(
            // Disabled only once the recogniser has actually refused: greying it
            // out before permission is asked hides the only control that can ask.
            onPressed: state.isUnavailable ? null : onPressed,
            tooltip: isListening ? 'Stop dictation' : 'Dictate',
            style: IconButton.styleFrom(
              backgroundColor: isListening
                  ? colors.error
                  : colors.surfaceContainerHighest,
              foregroundColor: isListening
                  ? colors.onError
                  : colors.onSurfaceVariant,
            ),
            icon: Icon(
              isListening ? Icons.stop_rounded : Icons.mic_rounded,
              size: 20,
            ),
          ),
        );
      },
    );
  }
}

/// The waveform and the space reserved for it. [AnimatedSize] over a conditional
/// child so the chips and preview below do not jump when the mic opens
/// (CLAUDE.md §12: reserve layout space for elements that come and go).
class _DictationBar extends StatelessWidget {
  const _DictationBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpeechBloc, SpeechState>(
      buildWhen: (previous, current) =>
          previous.isListening != current.isListening ||
          previous.level != current.level,
      builder: (context, state) {
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !state.isListening
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    label: 'Listening',
                    child: SiriWaveform(
                      level: state.level,
                      isListening: state.isListening,
                    ),
                  ),
                ),
        );
      },
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
