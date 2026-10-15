import 'dart:async';
import 'dart:collection';

import 'package:typed_graphql/typed_graphql.dart';

import 'execution_run.dart';
import 'run_cancellation.dart';

/// The response stream of a subscription (September2025 6.2.3.2
/// "MapSourceToResponseEvent"): every source event is executed as the root
/// field's value, one at a time and in order.
///
/// The source is paused while an event executes, so its events, its error and
/// its end wait their turn. A source that delivers synchronously inside
/// `listen` cannot be paused yet: what it delivers meanwhile waits in
/// [_waiting], and the pauses are applied when `listen` returns. The response
/// stream is a single-subscription controller: listening starts the source,
/// pause and resume pass through to it, and cancelling cancels it.
final class SubscriptionResponses {
  /// Maps the events of [_source] to results of runs like [_template].
  SubscriptionResponses(this._template, this._source) {
    _controller = StreamController<ExecutionResult>(
      onListen: _listen,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: _cancel,
    );
  }

  final ExecutionRun _template;
  final Stream<Object?> _source;

  // Set in the constructor body, which runs before anything can listen.
  late final StreamController<ExecutionResult> _controller;
  StreamSubscription<Object?>? _subscription;
  final Queue<void Function()> _waiting = Queue<void Function()>();
  bool _isCancelled = false;
  bool _isBusy = false;
  bool _isDraining = false;
  // Pauses owed to the source because it delivered before `listen` returned.
  int _owedPauses = 0;

  /// The results; listen once.
  Stream<ExecutionResult> get stream => _controller.stream;

  void _listen() {
    if (_template.cancellation case final cancellation?) {
      if (cancellation.isCancelled) {
        _stop(cancellation);
        return;
      }
      cancellation.signal.addListener(() => _stop(cancellation));
    }
    _subscription = _source.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) =>
          _whenIdle(() => _fail(error, stackTrace)),
      onDone: () => _whenIdle(_close),
    );
    for (; _owedPauses > 0; _owedPauses--) {
      _subscription?.pause();
    }
    if (_isCancelled) {
      _subscription?.cancel().ignore();
    }
  }

  Future<void> _cancel() {
    // After a failure the source is already cancelled and its outcome dropped.
    final wasCancelled = _isCancelled;
    _isCancelled = true;
    _waiting.clear();
    _template.cancellation?.dispose();
    if (wasCancelled) {
      return Future<void>.value();
    }
    return _subscription?.cancel() ?? Future<void>.value();
  }

  void _pauseSource() {
    final subscription = _subscription;
    if (subscription == null) {
      _owedPauses++;
    } else {
      subscription.pause();
    }
  }

  void _resumeSource() {
    final subscription = _subscription;
    if (subscription == null) {
      _owedPauses--;
    } else {
      subscription.resume();
    }
  }

  void _onEvent(Object? event) {
    _pauseSource();
    _whenIdle(() => _execute(event));
  }

  void _whenIdle(void Function() action) {
    if (_isBusy || _isDraining) {
      _waiting.add(action);
    } else {
      action();
      _drain();
    }
  }

  void _execute(Object? event) {
    _isBusy = true;
    try {
      final result = _template.restarted().executeRoot(event);
      if (result is Future<ExecutionResult>) {
        unawaited(result.then(_emit, onError: _fail));
      } else {
        _emit(result);
      }
    } on Object catch (error, stackTrace) {
      _isBusy = false;
      _fail(error, stackTrace);
    }
  }

  void _emit(ExecutionResult result) {
    _isBusy = false;
    if (_isCancelled) {
      return;
    }
    _controller.add(result);
    _resumeSource();
    _drain();
  }

  // Runs what arrived while an event executed. Guarded, so that a synchronous
  // result does not recurse once per waiting event.
  void _drain() {
    if (_isDraining) {
      return;
    }
    _isDraining = true;
    while (!_isBusy && !_isCancelled && _waiting.isNotEmpty) {
      _waiting.removeFirst()();
    }
    _isDraining = false;
  }

  void _close() {
    if (!_isCancelled) {
      _template.cancellation?.dispose();
      _controller.close();
    }
  }

  // The signal fired or the timeout elapsed: one last result with the
  // cancellation, then the end; the event in flight is dropped (spec 13).
  void _stop(RunCancellation cancellation) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _isBusy = false;
    _waiting.clear();
    cancellation.dispose();
    _controller.add(cancellation.result);
    _controller.close();
    _subscription?.cancel().ignore();
  }

  // The source failed (or the library did, which cannot be told apart by
  // the client): one last result with the error, then the end (spec 10).
  void _fail(Object error, StackTrace stackTrace) {
    _isBusy = false;
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _waiting.clear();
    _template.cancellation?.dispose();
    final reported = _template.reporter.sourceFailure(error, stackTrace);
    _controller.add(ExecutionResult(null, errors: [reported]));
    _controller.close();
    // A source whose cancel fails must not leave an unhandled error.
    _subscription?.cancel().ignore();
  }
}
