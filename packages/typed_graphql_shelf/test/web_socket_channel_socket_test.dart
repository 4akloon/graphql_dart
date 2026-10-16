import 'package:test/test.dart';
import 'package:typed_graphql_shelf/src/web_socket_channel_socket.dart';

import 'support/fake_web_socket_channel.dart';

void main() {
  late FakeWebSocketChannel channel;
  late WebSocketChannelSocket socket;

  setUp(() {
    channel = FakeWebSocketChannel(protocol: 'graphql-transport-ws');
    socket = WebSocketChannelSocket(channel, channel.protocol);
    addTearDown(channel.finish);
  });

  test('exposes the negotiated subprotocol', () {
    expect(socket.protocol, 'graphql-transport-ws');
  });

  test('delivers a text frame as it is', () async {
    final frames = socket.incoming.toList();
    channel.frames.add('{"type":"ping"}');
    await channel.frames.close();
    expect(await frames, ['{"type":"ping"}']);
  });

  test('decodes a binary frame as UTF-8', () async {
    final frames = socket.incoming.toList();
    channel.frames.add([0x68, 0xC3, 0xA9]);
    await channel.frames.close();
    expect(await frames, ['hé']);
  });

  test('replaces malformed UTF-8 in a binary frame', () async {
    final frames = socket.incoming.toList();
    channel.frames.add([0xFF, 0x41]);
    await channel.frames.close();
    expect(await frames, ['�A']);
  });

  test('completes incoming when the connection ends', () async {
    final done = socket.incoming.isEmpty;
    await channel.frames.close();
    expect(await done, isTrue);
  });

  test('writes a sent message as one text frame', () {
    socket.send('hello');
    expect(channel.fakeSink.added, ['hello']);
  });

  test('drops a message sent after close', () async {
    await socket.close(1000, 'bye');
    socket.send('late');
    expect(channel.fakeSink.added, isEmpty);
  });

  test('drops a message sent after the peer closed', () {
    channel.closeCode = 1001;
    socket.send('late');
    expect(channel.fakeSink.added, isEmpty);
  });

  test('closes the sink with the code and the reason', () async {
    await socket.close(4400, 'Invalid message received');
    expect(channel.fakeSink.closes, [(4400, 'Invalid message received')]);
  });
}
