import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'event_stream.dart';
import 'event_stream_writer.dart';
import 'stream_operation.dart';

/// The state behind one reservation of single connection mode: the stream
/// and the operations that write to it (spec section 10).
///
/// Frames written before the host listens wait in the controller, but only
/// those of operations that were started, and none is before the connect, so
/// what a stream holds is bounded by [maxOperations].
@internal
final class SingleConnection {
  /// Creates a connection that runs at most [maxOperations] operations and
  /// calls [onClosed] once, when the stream ends or is abandoned.
  SingleConnection(this.maxOperations, {required this.onClosed});

  /// The most operations run or held at once.
  final int maxOperations;

  /// Called once, when the stream ends or is abandoned.
  final void Function() onClosed;
  final Map<String, StreamOperation> _operations = {};

  static const EventStreamWriter _writer = EventStreamWriter();

  // Late so that the callbacks can be instance methods.
  late final StreamController<List<int>> _frames = StreamController<List<int>>(
    onListen: _startOperations,
    onPause: _pauseOperations,
    onResume: _resumeOperations,
    onCancel: _clientWentAway,
  );

  /// Whether a request has connected the stream.
  bool isConnected = false;

  /// Whether the host listens to the stream, so operations may run.
  bool isListening = false;

  /// Whether the host asked for the stream to be paused.
  bool isPaused = false;

  bool _isClosed = false;

  /// Whether the stream already runs or holds [maxOperations] operations.
  bool get isFull => _operations.length >= maxOperations;

  /// Whether an operation named [id] is running or held.
  bool isRunning(String id) => _operations.containsKey(id);

  /// Takes [id] for a new operation.
  StreamOperation admit(String id) =>
      _operations[id] = StreamOperation(id, this);

  /// Forgets [operation] because its request was refused after all.
  void release(StreamOperation operation) {
    if (identical(_operations[operation.id], operation)) {
      _operations.remove(operation.id);
    }
  }

  /// Cancels the operation named [id], if there is one. No `complete` is
  /// sent.
  void cancelOperation(String id) => _operations.remove(id)?.cancel();

  /// Marks the stream as connected and gives its event stream, which sends a
  /// comment every [keepAliveInterval].
  EventStream connect(Duration keepAliveInterval) {
    isConnected = true;
    return EventStream.frames(
      _frames.stream,
      keepAliveInterval: keepAliveInterval,
    );
  }

  /// Writes a result of [operation].
  void sendNext(StreamOperation operation, JsonValue payload) {
    if (_isClosed) return;
    _frames.add(_writer.operationNext(operation.id, payload));
  }

  /// Ends [operation]: writes its `complete` and frees its id.
  void complete(StreamOperation operation) {
    if (_isClosed || !identical(_operations[operation.id], operation)) return;
    _operations.remove(operation.id);
    _frames.add(_writer.operationComplete(operation.id));
  }

  /// Drops the reservation: cancels every operation and ends the stream.
  void abandon() {
    if (!_cancelOperations()) return;
    _frames.close().ignore();
  }

  void _startOperations() {
    isListening = true;
    for (final operation in _operations.values.toList()) {
      operation.start();
    }
  }

  void _pauseOperations() {
    isPaused = true;
    for (final operation in _operations.values) {
      operation.pause();
    }
  }

  void _resumeOperations() {
    isPaused = false;
    for (final operation in _operations.values) {
      operation.resume();
    }
  }

  Future<void> _clientWentAway() {
    _cancelOperations();
    return Future<void>.value();
  }

  // False when the connection was closed already.
  bool _cancelOperations() {
    if (_isClosed) return false;
    _isClosed = true;
    for (final operation in _operations.values) {
      operation.cancel();
    }
    _operations.clear();
    onClosed();
    return true;
  }
}
