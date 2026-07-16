import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// [debounce] runs an event handler only after [duration] of quiet.
///
/// A burst of events — the keystrokes of a search query — collapses to a single
/// handler run on the last one, instead of re-filtering and re-emitting the whole
/// list on every character. Each new event cancels the pending one, so the
/// handler sees only the final query rather than every prefix of it.
///
/// This is written against `dart:async` rather than pulling in `rxdart`
/// (CLAUDE.md §14 — reuse over adding a competing dependency): the app has no
/// stream package, and a search box needs only this one operator.
EventTransformer<E> debounce<E>(Duration duration) {
  return (events, mapper) =>
      events.transform(_DebounceStreamTransformer<E>(duration)).asyncExpand(mapper);
}

class _DebounceStreamTransformer<T> extends StreamTransformerBase<T, T> {
  const _DebounceStreamTransformer(this.duration);

  final Duration duration;

  @override
  Stream<T> bind(Stream<T> stream) {
    final controller = StreamController<T>();
    Timer? timer;

    controller.onListen = () {
      final subscription = stream.listen(
        (data) {
          timer?.cancel();
          timer = Timer(duration, () => controller.add(data));
        },
        onError: controller.addError,
        onDone: () {
          // A pending event still fires if the source closes before the window
          // elapses, so the last query is never dropped on teardown.
          timer?.cancel();
          controller.close();
        },
      );

      controller.onCancel = () {
        timer?.cancel();
        return subscription.cancel();
      };
    };

    return controller.stream;
  }
}
