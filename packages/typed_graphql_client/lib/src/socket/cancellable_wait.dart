import 'dart:async';

import 'package:meta/meta.dart';

/// A pause that [cancel] ends early, unlike `Future.delayed`, whose timer
/// outlives the link that wanted it.
@internal
final class CancellableWait {
  Timer? _timer;
  Completer<void>? _pause;

  /// Completes after [duration], or when [cancel] is called.
  Future<void> wait(Duration duration) {
    final pause = Completer<void>();
    _pause = pause;
    _timer = Timer(duration, cancel);
    return pause.future;
  }

  /// Ends the pause now; the caller checks whether it is still wanted.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    final pause = _pause;
    _pause = null;
    if (pause != null && !pause.isCompleted) {
      pause.complete();
    }
  }
}
