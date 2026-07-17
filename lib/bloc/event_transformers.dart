import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

/// [debounce] runs an event handler only after [duration] of quiet — each new
/// event cancels the pending one, so a burst of keystrokes runs the handler once
/// on the final query rather than on every prefix.
///
/// Written against `dart:async` rather than pulling in `rxdart` (CLAUDE.md §14 —
/// reuse over adding a competing dependency): a search box needs only this one
/// operator.
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
          // A pending event is dropped on teardown: the bloc is closing, and
          // emitting into a closed emitter throws.
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
