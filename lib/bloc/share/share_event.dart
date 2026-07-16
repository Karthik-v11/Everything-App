part of 'share_bloc.dart';

/// [ShareEvent] is the base class for every share event.
abstract class ShareEvent extends Equatable {
  const ShareEvent();

  @override
  List<Object?> get props => [];
}

/// [WatchSharesEvent] takes the share that launched the app and then listens for
/// the ones that arrive while it is running (Requirement 12.1). Fired once, at
/// launch.
class WatchSharesEvent extends ShareEvent {
  const WatchSharesEvent();
}

/// [SharesReceivedEvent] is one share, from either of the plugin's two paths.
///
/// Both the launch share and the stream funnel through here, so there is exactly
/// one place a share becomes state.
class SharesReceivedEvent extends ShareEvent {
  const SharesReceivedEvent({required this.items});

  final List<SharedItem> items;

  @override
  List<Object?> get props => [items];
}

/// [ShareDestinationChosen] files the pending share (Requirement 12.2).
///
/// [projectId] is required only for [ShareDestination.projectFile] — an
/// attachment has to hang off something.
class ShareDestinationChosen extends ShareEvent {
  const ShareDestinationChosen({required this.destination, this.projectId});

  final ShareDestination destination;
  final String? projectId;

  @override
  List<Object?> get props => [destination, projectId];
}

/// [ShareDismissed] drops the pending share unfiled.
class ShareDismissed extends ShareEvent {
  const ShareDismissed();
}
