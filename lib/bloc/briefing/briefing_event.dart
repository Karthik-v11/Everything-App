part of 'briefing_bloc.dart';

sealed class BriefingEvent extends Equatable {
  const BriefingEvent();

  @override
  List<Object?> get props => [];
}

/// [BriefingFactsChanged] is the Dashboard pushing the day in. The briefing
/// needs tasks, weather and news — three other blocs — and a bloc may not read
/// another's state (CLAUDE.md §4.4), so the Dashboard widget assembles them.
class BriefingFactsChanged extends BriefingEvent {
  const BriefingFactsChanged({required this.facts});

  final BriefingFacts facts;

  // BriefingFacts is an entity and deliberately not Equatable (CLAUDE.md §8), so
  // it cannot be a prop. The bloc's regeneration policy, not event
  // de-duplication, decides whether an arriving fact set is worth acting on.
  @override
  List<Object?> get props => [];
}

/// [RefreshBriefingEvent] is the pull gesture: regenerate regardless of policy.
class RefreshBriefingEvent extends BriefingEvent {
  const RefreshBriefingEvent();
}
