import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A [WebSocketChannel] the test drives by hand.
final class FakeWebSocketChannel extends StreamChannelMixin<Object?>
    implements WebSocketChannel {
  FakeWebSocketChannel({this.protocol});

  /// The frames the "client" sends: a `String` or a list of bytes.
  final StreamController<Object?> frames = StreamController<Object?>();

  /// What the adapter wrote and closed.
  final FakeWebSocketSink fakeSink = FakeWebSocketSink();

  @override
  final String? protocol;

  /// Ends both directions; the sink records the close like any other.
  void finish() {
    unawaited(frames.close());
    unawaited(fakeSink.close());
  }

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get stream => frames.stream;

  @override
  WebSocketSink get sink => fakeSink;
}

/// The sink of [FakeWebSocketChannel]: it records instead of sending.
final class FakeWebSocketSink implements WebSocketSink {
  /// The frames added, in order.
  final List<Object?> added = [];

  /// The `(code, reason)` of each close.
  final List<(int?, String?)> closes = [];

  @override
  void add(Object? data) => added.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async =>
      closes.add((closeCode, closeReason));

  @override
  Future<void> get done => Future<void>.value();
}
