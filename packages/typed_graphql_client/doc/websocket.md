# WebSocket

Subscriptions travel over a WebSocket speaking the graphql-transport-ws
protocol (the `graphql-ws` library's). `WebSocketLink` is a terminating link
for it: it sends queries and mutations too, but it is the link to use for
subscriptions. The package imports no socket library: the app opens the
socket and gives the link a `ClientSocket`, a small interface of text frames.

## The socket

A `ClientSocket` has the frames the server sends (`messages`, which ends
when the socket closes), `send`, `close`, and the `closeCode` and
`closeReason` once the stream has ended. Open the socket with the
sub-protocol `graphql-transport-ws`, and wrap it. This is the adapter for a
`WebSocketChannel`:

```text
final class ChannelSocket implements ClientSocket {
  ChannelSocket(this._channel);
  final WebSocketChannel _channel;

  Stream<String> get messages =>
      _channel.stream.where((frame) => frame is String).cast<String>();
  void send(String text) => _channel.sink.add(text);
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);
  int? get closeCode => _channel.closeCode;
  String? get closeReason => _channel.closeReason;
}
```

The link takes a function that opens a socket, not a type:

```text
final link = WebSocketLink(
  connect: () async => ChannelSocket(
    WebSocketChannel.connect(
      Uri.parse('wss://example.com/graphql'),
      protocols: ['graphql-transport-ws'],
    ),
  ),
  connectionParams: () async =>
      JsonObject({'token': JsonString(await token())}),
);
```

`connectionParams` is optional and is called at each connection, so a
token that was refreshed is the one sent. A browser `WebSocket` adapter
forwards its text `message` events to a stream controller, saves
`event.code` and `event.reason` in its `close` event before closing the
controller, and calls `socket.close(code, reason)`.

## Subscribing

The link is lazy: the first request opens the socket and does the
handshake (`connection_init`, then `connection_ack`); every operation then
shares that socket, with an id from a counter. The program below stands an
in-memory socket in for a server that acknowledges the connection and
answers every `subscribe` with two results and `complete`.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class TicksSubscription extends GraphQLSubscription<int> {
  const TicksSubscription();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Ticks',
    type: OperationType.subscription,
    text: 'subscription Ticks{ticks}',
    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
  };
}

final class MemorySocket implements ClientSocket {
  final StreamController<String> _frames = StreamController();

  @override
  Stream<String> get messages => _frames.stream;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  void send(String text) {
    final message = jsonDecode(text) as Map<String, Object?>;
    switch (message['type']) {
      case 'connection_init':
        _reply({'type': 'connection_ack'});
      case 'subscribe':
        for (final tick in [1, 2]) {
          _reply({
            'type': 'next',
            'id': message['id'],
            'payload': {
              'data': {'ticks': tick},
            },
          });
        }
        _reply({'type': 'complete', 'id': message['id']});
    }
  }

  @override
  Future<void> close([int? code, String? reason]) {
    closeCode = code;
    closeReason = reason;
    return _frames.close();
  }

  void _reply(Map<String, Object?> message) => _frames.add(jsonEncode(message));
}

Future<void> main() async {
  final link = WebSocketLink(connect: () async => MemorySocket());
  final client = GraphQLClient(link: link);
  await for (final response in client.subscribe(const TicksSubscription())) {
    if (response case GraphQLData(:final data)) {
      print('tick $data');
    }
  }
  await link.dispose();
  print('disposed');
}
```

It prints:

```text
tick 1
tick 2
disposed
```

A `next` message is a `LinkPayload`; an `error` message is a `LinkPayload`
holding a `RequestErrorResult` and ends the operation; `complete` ends it.
A query or a mutation ends after its `complete`. Cancelling the stream
before the server completes sends `complete` for the operation's id. A
message for an id the link does not know is ignored.

The socket stays open after the last operation ends, so the next request
needs no handshake. `dispose()` closes it with code 1000 and ends every
open operation with `RequestCancelled`; a request made after that gets an
`UnsupportedOperation` (`GQL468`). So does a request with `UploadFiles`
in its context: a socket cannot send files, so route those over HTTP.

## Keeping the socket alive

A server `ping` is answered with `pong`. With `keepAlive: Duration(...)`
the link also sends a `ping` at that interval after the acknowledgement; if
no `pong` came back before the next one, the socket is closed with code
4499 and the link reconnects as it does for any lost connection.

## Reconnecting

When the socket closes, or `connect` throws, while operations are open,
the link tries again after `backoff.delayFor(n, random)`: the default
`Backoff` starts at one second, doubles up to thirty and draws a random
wait below that ceiling. `retryAttempts` (default 5) failed attempts in a
row are retried; an acknowledged connection resets the count. A new socket
does the handshake again, and the link subscribes again to every open
subscription and query under the same id. A mutation that was already sent
is not sent again, since the server may have run it: it ends with a
`NetworkFailure`. A mutation not yet sent when the connection was lost is
sent on the next one. When no operation is open, a lost socket is not
reconnected; the next request connects.

A subscription's events are buffered while its listener is paused: the link
does not pause the socket, which carries other operations.

| Event | The operations get |
|---|---|
| The socket closes with a code that is not final, attempts left | nothing: the link reconnects |
| A mutation was sent before the loss | `NetworkFailure` for that mutation |
| The socket closes with a final code | `SocketFailure` `GQL471` with `closeCode` and `closeReason` |
| The attempts run out | `SocketFailure` `GQL471` with the last close code |
| `connect` keeps throwing until the attempts run out | `NetworkFailure` with the last exception |
| No `connection_ack` within `connectionAckTimeout` (default 10 s) | `SocketFailure` `GQL472`; the link closes with 4504 and does not reconnect |
| The server sends a message the protocol does not allow | `SocketFailure` `GQL470`; the link closes with 4400 and does not reconnect |

Close codes that are final (never retried) follow the reference client:

| Code | Meaning |
|---|---|
| 4500 | internal server error |
| 4005 | internal client error |
| 4400 | bad request |
| 4004 | bad response |
| 4401 | unauthorized |
| 4406 | subprotocol not acceptable |
| 4409 | subscriber already exists |
| 4429 | too many initialisation requests |
| 1002 to 1999 | WebSocket-level errors (a protocol error, 1011 internal error, ...), except 1005, 1006, 1012, 1013 and 1014 |

Every other close code is retried: 1000, 1001, 1005, 1006, 1012, 1013 and
1014 (a normal or abnormal end, a restarting server), 4403 (forbidden: the
access may be granted), 4499 (the link's own keep-alive) and 4504 when a
server sends it. The link's own acknowledgement timeout is not a retried
loss: it fails the operations with `GQL472` and does not reconnect.

## Subscriptions over a socket, the rest over HTTP

`SplitLink` sends each request down one of two links. The usual
arrangement keeps queries and mutations on HTTP, where they get retries,
files and caching, and sends subscriptions over the socket:

```text
final link = SplitLink(
  test: (request) => request.type == OperationType.subscription,
  whenTrue: WebSocketLink(connect: openSocket),
  whenFalse: HttpLink(Uri.parse('https://example.com/graphql')),
);
final client = GraphQLClient(link: link);
```

`HttpLink` is the subject of the HTTP guide.
