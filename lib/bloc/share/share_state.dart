part of 'share_bloc.dart';

/// [ShareState] is the pending share and the chooser's status
/// (Requirement 12).
///
/// It is **not** hydrated, deliberately. A share is a live handoff from another
/// app: the file paths in it point into OS-owned temporary storage that is gone
/// by the next launch, so a persisted pending share would restore a chooser
/// offering to file something that no longer exists.
class ShareState extends Equatable {
  const ShareState({
    this.isLoading = false,
    this.error = '',
    this.message = '',
    this.pending = const <SharedItem>[],
    this.isChooserOpen = false,
  });

  final bool isLoading;
  final String error;
  final String message;

  /// What another app handed over and the user has not filed yet. More than one
  /// item is a multi-select share, and all of it goes to one destination.
  final List<SharedItem> pending;

  final bool isChooserOpen;

  /// [kind] is what is being filed. Mixed shares are rare enough — and a mixed
  /// destination list meaningless enough — that the first item decides, and any
  /// item the chosen destination cannot take is skipped rather than failing the
  /// whole share.
  SharedKind? get kind => pending.isEmpty ? null : pending.first.kind;

  /// [destinations] is what the chooser offers for the pending share.
  List<ShareDestination> get destinations {
    final current = kind;
    return current == null
        ? const <ShareDestination>[]
        : ShareDestination.forKind(current);
  }

  ShareState copyWith({
    bool? isLoading,
    String? error,
    String? message,
    List<SharedItem>? pending,
    bool? isChooserOpen,
  }) =>
      ShareState(
        isLoading: isLoading ?? this.isLoading,
        error: error ?? this.error,
        message: message ?? this.message,
        pending: pending ?? this.pending,
        isChooserOpen: isChooserOpen ?? this.isChooserOpen,
      );

  @override
  List<Object?> get props => [
        isLoading,
        error,
        message,
        pending,
        isChooserOpen,
      ];
}
