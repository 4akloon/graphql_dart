import 'dart:async';

import 'package:meta/meta.dart';

import 'event_stream.dart';

/// The state behind one reservation of single connection mode: the stream
/// that carries every result of the reservation (spec section 10).
@internal
final class SingleConnection {
  /// Creates a connection that calls [onClosed] once, when the stream ends or
  /// is abandoned.
  SingleConnection({required this.onClosed});

  /// Called once, when the stream ends or is abandoned.
  final void Function() onClosed;

  // Late so that the callback can be an instance method.
  late final StreamController<List<int>> _frames = StreamController<List<int>>(
    onCancel: _clientWentAway,
  );

  /// Whether a request has connected the stream.
  bool isConnected = false;

  bool _isClosed = false;

  /// Marks the stream as connected and gives its event stream, which sends a
  /// comment every [keepAliveInterval]. It never ends by itself.
  EventStream connect(Duration keepAliveInterval) {
    isConnected = true;
    return EventStream.frames(
      _frames.stream,
      keepAliveInterval: keepAliveInterval,
    );
  }

  /// Drops the reservation and ends the stream.
  void abandon() {
    if (!_close()) return;
    _frames.close().ignore();
  }

  Future<void> _clientWentAway() {
    _close();
    return Future<void>.value();
  }

  // False when the connection was closed already.
  bool _close() {
    if (_isClosed) return false;
    _isClosed = true;
    onClosed();
    return true;
  }
}
