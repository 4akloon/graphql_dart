import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'single_connection.dart';

/// One operation running on a single-connection stream.
///
/// It is admitted when its `POST` arrives, so its id is taken at once, and
/// receives its results once the pipeline has answered. Its source is not
/// listened to until the stream is, so a held subscription runs nothing.
@internal
final class StreamOperation {
  /// Creates the operation [id] of [_connection].
  StreamOperation(this.id, this._connection);

  /// The id the client gave in `extensions.operationId`.
  final String id;

  final SingleConnection _connection;
  Stream<JsonValue>? _source;
  StreamSubscription<JsonValue>? _subscription;
  bool _isCancelled = false;

  /// Gives the operation the stream of its results.
  ///
  /// An operation cancelled meanwhile (by a `DELETE` or by the stream going
  /// away) releases [source] without listening to it.
  void attach(Stream<JsonValue> source) {
    _source = source;
    if (_isCancelled) {
      _release(source);
    } else if (_connection.isListening) {
      start();
    }
  }

  /// Starts forwarding the results, if they are known and not started yet.
  void start() {
    final source = _source;
    if (source == null || _subscription != null || _isCancelled) return;
    _subscription = source.listen(
      (payload) => _connection.sendNext(this, payload),
      // A failing source ends the operation, so the client is not left
      // waiting for a result that never comes.
      onError: (Object _) => _connection.complete(this),
      onDone: () => _connection.complete(this),
      cancelOnError: true,
    );
    if (_connection.isPaused) _subscription?.pause();
  }

  /// Pauses the results while the client reads slowly.
  void pause() => _subscription?.pause();

  /// Resumes the results.
  void resume() => _subscription?.resume();

  /// Stops the operation; its resolvers are cancelled through the source.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final subscription = _subscription;
    final source = _source;
    if (subscription != null) {
      subscription.cancel().ignore();
    } else if (source != null) {
      _release(source);
    }
  }

  // Cancelling a never-listened pipeline stream releases what it holds.
  void _release(Stream<JsonValue> source) =>
      source.listen(null).cancel().ignore();
}
