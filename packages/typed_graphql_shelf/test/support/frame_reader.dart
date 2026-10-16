import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Reads the JSON messages of a graphql-ws client channel one at a time.
final class FrameReader {
  FrameReader(this.channel) : _frames = StreamIterator(channel.stream);

  final WebSocketChannel channel;
  final StreamIterator<Object?> _frames;

  /// Sends [message] as one text frame.
  void send(Map<String, Object?> message) =>
      channel.sink.add(jsonEncode(message));

  /// The next message; a timeout fails the test when none comes.
  Future<Map<String, Object?>> next() async {
    final hasFrame = await _frames.moveNext().timeout(
      const Duration(seconds: 5),
    );
    if (!hasFrame) {
      throw StateError('The channel closed: ${channel.closeCode}');
    }
    return jsonDecode(_frames.current! as String) as Map<String, Object?>;
  }

  /// Waits until the server closes the channel and returns its close code.
  Future<int?> closeCode() async {
    while (await _frames.moveNext().timeout(const Duration(seconds: 5))) {}
    return channel.closeCode;
  }
}
