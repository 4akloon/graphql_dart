# WebSocket

`GraphQLWsHandler` serves the `graphql-transport-ws` subprotocol of the
graphql-ws library: queries, mutations and subscriptions over one WebSocket
connection. It knows nothing of HTTP or of a WebSocket library. A host
accepts the upgrade, wraps the connection in a `GraphQLSocket` and calls
`serve`; every `subscribe` message runs through a `GraphQLServer`, so the
document cache, the limits, the cost limit, error masking, persisted
documents and the context factory apply as they do for any request. It builds
on the Server and Subscriptions guides.

## A connection, end to end

The program below stands in for a host: `MemorySocket` is a `GraphQLSocket`
over two stream controllers. The client sends `connection_init` with a token
and one `subscribe`; the context factory reads the token from
`RequestInfo.connectionParams`.

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Viewer {
  const Viewer(this.name);

  final String name;
}

final class MemorySocket implements GraphQLSocket {
  final StreamController<String> _incoming = StreamController<String>();
  final StreamController<String> _outgoing = StreamController<String>();

  @override
  String? get protocol => GraphQLWsHandler.protocol;

  @override
  Stream<String> get incoming => _incoming.stream;

  Stream<String> get sent => _outgoing.stream;

  void receive(String text) => _incoming.add(text);

  Future<void> disconnect() => _incoming.close();

  @override
  void send(String text) => _outgoing.add(text);

  @override
  Future<void> close(int code, String reason) => _incoming.close();
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Viewer>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('hello', b.string)
          .resolve((parent, args, context, info) => 'Hello, ${context.name}!'),
    ],
  );
  final server = GraphQLServer<Viewer>(
    schema: b.build(query: query),
    contextFactory: (info) {
      final token = info.connectionParams?['token'];
      return Viewer(token is JsonString ? token.value : 'guest');
    },
  );
  final handler = GraphQLWsHandler<Viewer>(server);
  final socket = MemorySocket();
  final served = handler.serve(
    socket,
    RequestInfo(method: 'GET', uri: Uri.parse('http://localhost/graphql')),
  );
  socket.receive('{"type":"connection_init","payload":{"token":"Ada"}}');
  socket.receive(
    '{"type":"subscribe","id":"1","payload":{"query":"{ hello }"}}',
  );
  await socket.sent.take(3).forEach(print);
  await socket.disconnect();
  await served;
}
```

It prints:

```text
{"type":"connection_ack"}
{"type":"next","id":"1","payload":{"data":{"hello":"Hello, Ada!"}}}
{"type":"complete","id":"1"}
```

`serve` completes when the connection ends and never throws. A violation of
the protocol closes the socket with a code (below) instead.

## The state machine

| Event | Effect |
|---|---|
| more than `maxConnections` sessions open | close `1013` "Try again later" |
| `protocol` is not `graphql-transport-ws` | close `4406` "Subprotocol not acceptable" |
| `Origin` not allowed | close `4403` "Forbidden" |
| no acknowledgement within `connectionInitTimeout` | close `4408` "Connection initialisation timeout" |
| a frame longer than `maxMessageLength` | close `1009` "Message too big" |
| not JSON (or deeper than `maxJsonDepth`), not an object, no string `type`, an unknown type, a field of the wrong type, an id longer than `maxIdLength`, or `connection_ack`, `next` or `error` from the client | close `4400` "Invalid message received" |
| `connection_init` | runs `onConnect`; `AcceptConnection` sends `connection_ack` with its payload, `RefuseConnection` closes `4403`, a throw closes `4500`; without a hook the connection is acknowledged |
| a second `connection_init` | close `4429` "Too many initialisation requests" |
| `ping` | `pong`, echoing the payload; allowed before the acknowledgement |
| `pong` | ignored |
| `subscribe` before the acknowledgement | close `4401` "Unauthorized" |
| `subscribe` with an id in use | close `4409` "Subscriber for <id> already exists" |
| `subscribe` with `maxOperations` running | an `error` message for that id with `GQL432`; the socket stays open |
| `subscribe` | a result is `next` then `complete`; a request error is `error` alone; a subscription is one `next` per result, then `complete` |
| `complete` from the client | cancels the operation and its `CancelSignal`; nothing more is sent for the id |
| the connection ends, or a close the server asked for finishes | every operation is cancelled and the session ends, even if the peer never answers the closing handshake |

An id is free again once its operation ended, so a client may reuse it. A
`complete` that arrives while the server is still preparing the operation
sends nothing, and a subscription that starts after it is cancelled at once.
A `subscribe` without a `query` is not a protocol error: it reaches the
pipeline, so persisted documents work over WebSocket and a missing document
is a `GQL400` `error` message. An unexpected failure of an operation is an
`error` message with `GQL330` and the masked text "Unexpected error.".

## Authentication

Browsers cannot set headers on a WebSocket, so a token travels in the
`connection_init` payload. `GraphQLWsOptions.onConnect` receives a
`RequestInfo` of the upgrade (its URI, headers and `source`) with
`connectionParams` set to the payload. It returns `AcceptConnection`, whose
`payload` becomes the payload of `connection_ack`, or `RefuseConnection`,
which closes the socket with `4403`. Throwing closes it with `4500`; the
message of the exception is never sent.

Every operation of the connection gets a `RequestInfo` with the upgrade's
headers and the same `connectionParams`, so the context factory reads the
token for each one, as the program above does. Check the token in `onConnect`
as well, so that a bad token is refused once rather than on every operation.

## Origin and CSRF

A browser sends its cookies with a WebSocket upgrade and asks no preflight,
so a page on another site could open a connection as the user. The handler's
defence is the `Origin` header. `allowsUpgrade` passes an upgrade with no
`Origin` (not a browser), an `Origin` whose host and port equal the `Host`
header, or an `Origin` listed in `allowedOrigins` (ignoring case). Anything
else, including `Origin: null` and an unreadable value, fails. A host calls
`allowsUpgrade` before upgrading and answers `403`; `serve` checks again and
closes `4403`.

Each message runs as a `POST` with the upgrade's headers and
`content-type: application/json`, so the mutation guard and the CSRF rule of
the pipeline pass. The `Origin` check is what protects them.

## Limits

| Option | Default | Bounds |
|---|---|---|
| `connectionInitTimeout` | 3 s | a connection that never acknowledges |
| `maxOperations` | 100 | operations running at once on one connection |
| `maxMessageLength` | 1 MiB | the characters of one frame |
| `maxIdLength` | 256 | the characters of an operation id, which every running operation keeps |
| `maxJsonDepth` | 64 | the nesting of a message |
| `maxConnections` | 10000 | open sessions of one handler |

`maxOperations` counts operations in flight: an operation the client
completed still counts until the server stopped working on its request, so
a client cannot start more executions than the limit by subscribing and
completing in a loop.

What the limits do not cover:

- `maxMessageLength` is checked after the adapter has buffered the frame, so
  an adapter must cap the size of a frame before it buffers it
  (`typed_graphql_shelf` does, per frame).
- The `Origin` check ignores the scheme and trusts the `Host` header, which
  a DNS-rebinding page controls; it does not replace authentication in
  `onConnect`.
- A `ping` message is answered with a `pong` without a limit; a flood of
  pings is bounded only by `maxMessageLength` and the adapter.
- The `4408` timer also covers a slow `onConnect`: a hook that takes longer
  than `connectionInitTimeout` gets the connection closed.
- A subscription whose source fails after it started sends its earlier
  `next` messages, then a `next` carrying the error with `GQL340` and a
  `complete`; an `error` message with `GQL330` follows only when the result
  stream itself fails.

The limits of the pipeline (`ServerLimits`: document length, tokens, depth,
aliases, cost) apply to each `subscribe` as to any request.

## Keep-alive and backpressure

Keep-alive is WebSocket ping frames, which are the adapter's job; the
handler answers graphql-ws `ping` messages but sends none. `send` is
fire-and-forget: neither the `WebSocket` of `dart:io` nor a `WebSocketChannel`
reports a full buffer, so a client that reads nothing while a subscription
produces fast makes the host buffer without bound. This is a limit of the
handler: `maxOperations` and the schema's own rate are the only bounds.

## Reporting errors

`GraphQLWsOptions.onError` receives the errors the handler swallows, with
their stack traces: a throw of `onConnect` (the client gets `4500`), a throw
of the server pipeline and a result stream that itself fails (the client
gets an `error` message with `GQL330`; a failing subscription source is not
this case, it ends as a `GQL340` result), and a failure of the connection itself. An
`Error` is reported like any other object and is never rethrown into the
zone; these are boundary catches, so one broken connection cannot take the
process down. A hook that throws is ignored, and so is the failure of the
`Future` an `async` hook returns. Exactly six places catch `Object`: the
three boundaries above (the `onConnect` call, the operation's request and the
connection's outermost run) report through the hook; the other three are
guards (the hook call itself, a `close` that throws synchronously and the
close after a failure) that only end the connection and cannot hide an
`Error` nobody saw.

## Writing an adapter

An adapter implements `GraphQLSocket` over its WebSocket library:

```text
abstract interface class GraphQLSocket {
  String? get protocol;        // the negotiated subprotocol
  Stream<String> get incoming; // text frames; done when the connection closes
  void send(String text);
  Future<void> close(int code, String reason);
}
```

- Offer `GraphQLWsHandler.protocol` in the handshake and report what was
  negotiated as `protocol`.
- Deliver text frames as they are and binary frames decoded as UTF-8; the
  handler closes the connection when they are not messages.
- End `incoming` when the connection closes, from either side.
- Call `allowsUpgrade` before upgrading and answer `403`, then call `serve`
  with a `RequestInfo` of the upgrade request.

For shelf there is nothing to write: `GraphQLShelfHandler` of
`typed_graphql_shelf` does all of this when its `webSocket` option is set.
