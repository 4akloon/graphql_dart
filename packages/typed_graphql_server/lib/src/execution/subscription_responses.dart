import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'execution_run.dart';

/// The response stream of a subscription (September2025 6.2.3.2
/// "MapSourceToResponseEvent"): every source event is executed as the root
/// field's value, one at a time and in order.
///
/// The source is paused while an event executes, so its events, its error and
/// its end wait their turn. The response stream is a single-subscription
/// controller: listening starts the source, pause and resume pass through to
/// it, and cancelling cancels it.
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
  bool _isCancelled = false;

  /// The results; listen once.
  Stream<ExecutionResult> get stream => _controller.stream;

  void _listen() {
    _subscription = _source.listen(
      _onEvent,
      onError: _fail,
      onDone: _onSourceDone,
    );
  }

  Future<void> _cancel() {
    _isCancelled = true;
    return _subscription?.cancel() ?? Future<void>.value();
  }

  void _onEvent(Object? event) {
    _subscription?.pause();
    try {
      final result = _template.restarted().executeRoot(event);
      if (result is Future<ExecutionResult>) {
        unawaited(result.then(_emit, onError: _fail));
      } else {
        _emit(result);
      }
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _emit(ExecutionResult result) {
    if (_isCancelled) {
      return;
    }
    _controller.add(result);
    _subscription?.resume();
  }

  void _onSourceDone() {
    if (!_isCancelled) {
      _controller.close();
    }
  }

  // The source failed (or the library did, which cannot be told apart by
  // the client): one last result with the error, then the end (spec 10).
  void _fail(Object error, StackTrace stackTrace) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final reported = _template.reporter.sourceFailure(error, stackTrace);
    _controller.add(ExecutionResult(null, errors: [reported]));
    _controller.close();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
  }
}
