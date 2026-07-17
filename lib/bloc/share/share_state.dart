part of 'share_bloc.dart';

/// [ShareState] is the pending share and the chooser's status
/// (Requirement 12).
///
/// Deliberately not hydrated: a share's file paths point into OS-owned
/// temporary storage that is gone by the next launch, so a persisted pending
/// share would restore a chooser for files that no longer exist.
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

  /// What is being filed. The first item decides for mixed shares; items the
  /// chosen destination cannot take are skipped rather than failing the share.
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
