# shelf adapter

`typed_graphql_shelf` serves a `GraphQLServer` from a shelf application. The
adapter is thin: `GraphQLShelfHandler` turns each shelf `Request` into the
`HttpRequestData` of `typed_graphql_server`, runs `GraphQLHttpHandler` and
writes its `HttpResponseData` as a shelf `Response`; with `webSocket` set it
also turns a WebSocket upgrade into a graphql-ws session. The limits, the media
types, the status codes and the GraphiQL page are the HTTP guide's of
`typed_graphql_server`.

## The handler

```text
final class GraphQLShelfHandler<C> {
  GraphQLShelfHandler(
    GraphQLServer<C> server, {
    HttpOptions http,
    GraphQLWsOptions? webSocket,
    Duration webSocketPingInterval,
  });
  FutureOr<Response> call(Request request);
}
```

The handler is a shelf `Handler`: pass `handler.call` to `shelf_io.serve`, or
mount it in a router at the path of the endpoint. Routing, CORS and logging
stay with shelf. The page of GraphiQL sends its queries to the path the
browser opened it at, so any mount point works.

## A first program

This program serves one query on a free port, posts a request to it with
`HttpClient`, prints the status and the body, and stops. The default profile
is production, which does not serve the GraphiQL page.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', b.string).pure((_) => 'Hello from shelf!'),
    ],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => null,
  );
  final handler = GraphQLShelfHandler<Object?>(server);

  // Port 0 asks the system for a free port.
  final httpServer = await shelf_io.serve(
    handler.call,
    InternetAddress.loopbackIPv4,
    0,
  );

  final client = HttpClient();
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:${httpServer.port}/graphql'),
  );
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'query': '{ hello }'}));
  final response = await request.close();
  stdout.writeln(response.statusCode);
  stdout.writeln(await utf8.decodeStream(response));

  client.close();
  await httpServer.close();
}
```

It prints:

```text
200
{"data":{"hello":"Hello from shelf!"}}
```

The same schema with a subscription, a WebSocket and the GraphiQL page is
`example/example.dart` in the package.

## What the adapter decides

- Header names are lower-case and repeated headers are joined with `, `, as
  shelf gives them.
- A body is read from the request only when the handler needs it, and never
  past its size limit.
- A streamed body (an event stream) is written with `shelf.io.buffer_output`
  off, so each event reaches the client when it is written. `shelf_io` cancels
  the subscription when the client goes away, which ends the work behind it.
- No `CancelSignal` is given to the handler, because shelf does not report a
  client that went away outside a streamed body.
- A handler that fails in a way it did not expect, for example a request whose
  body a middleware already read (`StateError`) or a WebSocket upgrade on a
  host that cannot hijack, answers `500` with `GQL330` as JSON and reports to
  `HttpOptions.onError`; `call` never throws.

## Behind a proxy

`shelf_io` has two properties that the handler cannot change, so run it behind
a reverse proxy that caps request bodies and times:

- A refusal made before the body is read (`413` by the declared length, `415`)
  is delivered only after `shelf_io` has consumed the whole request body, and
  cancelling the body subscription destroys the connection without any
  response. A client that sends a body slowly therefore holds its socket for as
  long as it likes, and `bodyTimeout` does not apply because the handler never
  reads it.
- A client that disconnects while a fixed (non-streamed) response is computed
  is not noticed: the execution runs to its end, unlike an event stream, whose
  cancelled subscription stops the work. `ServerProfile.production` sets no
  timeout, so give the server one (`ServerProfile.withTimeout`, or
  `ExecutionOptions.timeout`) to bound abandoned work.

## WebSocket

With `webSocket` set, a `GET` that asks to upgrade to a WebSocket (an
`Upgrade: websocket` header) is served as graphql-ws (`graphql-transport-ws`)
by a `GraphQLWsHandler` built from the same server; without it, such a request
is an ordinary `GET`.

```text
GraphQLShelfHandler<Object?>(
  server,
  webSocket: const GraphQLWsOptions(allowedOrigins: ['https://app.example']),
  webSocketPingInterval: const Duration(seconds: 12),
)
```

- The `Origin` is checked before the upgrade, because a browser sends cookies
  with an upgrade and no preflight. A page on another site is answered `403`
  with `GQL403`, as JSON. An upgrade that lacks what the handshake needs (no
  `Connection: Upgrade`, a version other than 13, no key, not HTTP/1.1) is a
  `400` with `GQL425`, as JSON. An upgrade passes without an `Origin`, from the host's own origin or from one of
  `allowedOrigins`.
- The subprotocol must be `graphql-transport-ws`; a connection that offers
  another is closed with `4406` by the handler.
- `webSocketPingInterval` (12 seconds by default; zero or negative is an
  `ArgumentError`) is the interval of the WebSocket ping frames that keep the
  connection alive through proxies; the handler itself sends none.
- A frame may carry at most `3 * maxMessageLength + 1024` bytes: the adapter
  writes the `101` itself and gives `dart:io` that limit, so a frame header that
  declares more closes the socket (`dart:io` sends `1002`) before any payload is
  buffered. The limit is per frame: a message split into many frames is
  checked as a whole only after `dart:io` has assembled it, so a proxy that
  caps the total is still advisable.
- Limits, the `onConnect` hook and the close codes are the WebSocket guide's
  of `typed_graphql_server`.

## Uploads

`TempFileUploadStorage` is an `UploadStorage` that writes each upload to a
file and deletes it when the request ends, so a large file never waits in
memory. The size is bounded by the `UploadLimits` of the `Uploads` value.

```text
final uploads = Uploads(storage: TempFileUploadStorage());
final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
final handler = GraphQLShelfHandler<Object?>(
  server,
  http: HttpOptions(uploads: uploads),
);
```

The files get random names in a directory the storage makes under
`Directory.systemTemp` on its first upload and restricts to its owner (mode
`0700` with `chmod` on POSIX; if that fails, the upload fails). The empty
directory is left behind when the process ends. A directory given as
`TempFileUploadStorage(directory: ...)` must exist and is used as it is, with
its own permissions: make it private yourself. What the
client sent as a file name is only data: it is never used as a path. A
stream that fails, for example a file over its limit, leaves no partial file.
The Uploads guide of `typed_graphql_server` has the rest.

## GraphiQL

The page is the HTTP handler's, so it is served exactly when
`ServerProfile.graphiql` is on, which is the default of
`ServerProfile.development` and never of `production`. A browser that opens
the endpoint with an `Accept` that prefers `text/html` gets it. The page loads
React and GraphiQL from jsDelivr, pinned by version, so the browser needs
network access to the CDN; the server does not. Subscriptions are not run from
the page. It has no `content-security-policy`: its script is inline, so a nonce
would need per-response state, and the assets are protected by Subresource
Integrity only. It is a development tool; the response is `no-store` and varies
on `Accept`.

## Tests

The handler is an ordinary function of a `Request`, so a test can call it
without a socket: `handler(Request('POST', uri, body: ..., headers: ...))`.
The package's own end-to-end tests serve it with `shelf_io` on a loopback
port and talk to it with `HttpClient` and `WebSocketChannel`.
