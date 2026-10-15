import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import 'execution_options.dart';

/// The cancellation of one run (spec 13): the caller's signal and the timer
/// linked into one [signal]. The caller's signal is only listened to.
///
/// Nothing exists when the options have neither a signal nor a timeout, so
/// the plain path pays nothing. [dispose] ends the timer and the listener
/// when the run ends.
final class RunCancellation {
  RunCancellation._(this.signal);

  /// The run's cancellation, or null when [options] ask for none. A timer
  /// started here must be ended with [dispose].
  static RunCancellation? from(ExecutionOptions options) {
    final caller = options.cancelSignal;
    final timeout = options.timeout;
    if (caller == null && timeout == null) {
      return null;
    }
    final cancellation = RunCancellation._(CancelSignal());
    if (caller != null) {
      cancellation._detach = caller.addListener(
        () => cancellation.signal.cancel(caller.reason),
      );
    }
    if (timeout != null && !cancellation.signal.isCancelled) {
      cancellation._timeout = timeout;
      cancellation._timer = Timer(timeout, cancellation._timeOut);
    }
    return cancellation;
  }

  /// The signal resolvers see as `FieldInfo.cancelSignal`; cancelling it
  /// cancels the run.
  final CancelSignal signal;

  Timer? _timer;
  void Function()? _detach;
  Duration? _timeout;
  bool _isTimedOut = false;

  /// Whether the run was cancelled or timed out.
  bool get isCancelled => signal.isCancelled;

  /// `GQL350`, or `GQL351` when the timeout ended the run.
  GraphQLError get error => _isTimedOut
      ? _coded(
          'Execution timed out after ${_timeout?.inMilliseconds} ms.',
          DiagnosticCode.executionTimedOut,
        )
      : _coded('Execution was cancelled.', DiagnosticCode.executionCancelled);

  /// The response of a cancelled run: no data and [error].
  ExecutionResult get result => ExecutionResult(null, errors: [error]);

  /// [pending], or the cancelled [result] as soon as the run is cancelled.
  Future<ExecutionResult> race(Future<ExecutionResult> pending) {
    if (isCancelled) {
      return Future.value(result);
    }
    final completer = Completer<ExecutionResult>();
    final detach = signal.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    });
    pending.then(
      (value) {
        detach();
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        detach();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  /// [pending] mapped by [onReady], or [onCancelled] as soon as the run is
  /// cancelled. [onReady] never runs for a [pending] that completes after
  /// the cancellation, and a late failure of it is dropped.
  Future<T> raceCancelled<S, T>(
    Future<S> pending,
    T Function(S value) onReady,
    T Function() onCancelled,
  ) {
    final completer = Completer<T>();
    final detach = signal.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(onCancelled());
      }
    });
    pending.then(
      (value) {
        detach();
        if (!completer.isCompleted) {
          completer.complete(onReady(value));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        detach();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  /// Ends the timer and stops listening to the caller's signal.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _detach?.call();
    _detach = null;
  }

  void _timeOut() {
    _isTimedOut = true;
    signal.cancel(_timeout);
  }

  GraphQLError _coded(String message, DiagnosticCode code) => GraphQLError(
    message,
    extensions: JsonObject({'code': JsonString(code.id)}),
  );
}
