import 'dart:async';

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:everything_app/core/utils/constants.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/helpers.dart';
import 'package:everything_app/data/entity/ai_prompt.dart';
import 'package:everything_app/data/entity/briefing_facts.dart';
import 'package:everything_app/data/entity/briefing_fallback.dart';
import 'package:everything_app/data/repositories/text_engine.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'briefing_event.dart';
part 'briefing_state.dart';

/// [BriefingBloc] owns the Dashboard's daily briefing (design.md §5).
///
/// Hydrated so the card is populated on the first frame of a cold launch —
/// generation is a single awaited call with no streaming, so the card would
/// otherwise be empty for as long as the network takes.
///
/// It owns no sources: the Dashboard pushes facts in via [BriefingFactsChanged]
/// rather than the bloc reading other blocs' state (CLAUDE.md §4.4). The engine
/// is the [TextEngine] seam rather than a named model, so whatever `app.dart`
/// injects is what writes the briefing.
class BriefingBloc extends HydratedBloc<BriefingEvent, BriefingState> {
  BriefingBloc({required this.engine}) : super(const BriefingState()) {
    on<BriefingFactsChanged>(_onBriefingFactsChanged);
    on<RefreshBriefingEvent>(_onRefreshBriefingEvent);
  }

  final TextEngine engine;

  /// The last facts pushed in. Held outside the state because they are an input,
  /// and because [BriefingFacts] is not `Equatable` — in the state it would
  /// break equality and emit on every push.
  BriefingFacts? _facts;

  FutureOr<void> _onBriefingFactsChanged(
    BriefingFactsChanged event,
    Emitter<BriefingState> emit,
  ) async {
    _facts = event.facts;

    // A scroll-driven rebuild can push facts while a generate is still in
    // flight. Guarding here is what keeps them from stacking.
    if (state.isLoading) return;
    if (!_shouldRegenerate(event.facts)) return;

    await _generate(event.facts, emit);
  }

  FutureOr<void> _onRefreshBriefingEvent(
    RefreshBriefingEvent event,
    Emitter<BriefingState> emit,
  ) async {
    final facts = _facts;
    // The pull reached the bloc before the Dashboard's first push. Nothing to
    // brief on yet, and the push that follows will generate anyway.
    if (facts == null) return;
    if (state.isLoading) return;

    await _generate(facts, emit);
  }

  /// Regeneration policy (design.md §5.4). Facts change on every task keystroke
  /// elsewhere, so generate-per-change would be an API call per toggle.
  bool _shouldRegenerate(BriefingFacts facts) {
    // Nothing on the card, or only the deterministic placeholder on it.
    if (!state.hasText || state.isFallback) return true;

    final at = state.generatedAt;
    if (at == null) return true;

    // A new day is a new briefing, whatever the tasks did.
    if (!at.isSameDayAs(facts.now)) return true;

    // Rule 3, and the reason the card cannot say "Good morning" after lunch.
    return Helpers.greeting(at: at) != facts.greeting;
  }

  /// Asks the engine, falling back rather than failing: offline, no API key or
  /// exhausted quota all land on [BriefingFallback] with `isFallback: true` and
  /// no `error`, never an error card. The app is offline-first by design.
  Future<void> _generate(BriefingFacts facts, Emitter<BriefingState> emit) async {
    final fallback = BriefingFallback.compose(facts);

    if (!engine.isLoaded) {
      emit(
        state.copyWith(
          isLoading: false,
          error: '',
          message: '',
          text: fallback,
          generatedAt: clock.now(),
          isFallback: true,
        ),
      );
      return;
    }

    // Fallback goes up with the loading flag: the card must never be empty and
    // never show a spinner while the engine writes (design.md §5.5).
    emit(
      state.copyWith(
        isLoading: true,
        error: '',
        message: '',
        text: state.hasText ? state.text : fallback,
        isFallback: state.hasText ? state.isFallback : true,
      ),
    );

    try {
      final response = await engine.generate(
        AiPrompt.briefing(facts: facts),
        systemInstruction: AiPrompt.briefingSystemInstruction,
      );

      final text = response.data?.toString().trim() ?? '';
      // An empty success is treated exactly like a failure.
      final isGenerated = response.success && text.isNotBlank;

      emit(
        state.copyWith(
          isLoading: false,
          error: '',
          text: isGenerated ? text : fallback,
          generatedAt: clock.now(),
          isFallback: !isGenerated,
        ),
      );
    } on Exception {
      emit(
        state.copyWith(
          isLoading: false,
          error: '',
          text: fallback,
          generatedAt: clock.now(),
          isFallback: true,
        ),
      );
    }
  }

  @override
  BriefingState? fromJson(Map<String, dynamic> json) =>
      BriefingState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(BriefingState state) => state.toJson();
}
