# Server-sent events

GraphQL over server-sent events (R5.8) streams the results of a subscription,
or of any operation, as `text/event-stream`. `GraphQLHttpHandler` answers
event streams in both modes of the graphql-sse protocol: the distinct
connections mode, where each request has its own stream, and the single
connection mode, where one stream carries many operations. The first is on
by default; the second is opt-in. Like the rest of the handler, the code
imports no `dart:io`: the host adapter writes the chunks of the response body
to the socket as they arrive (see the HTTP guide).

## An event stream

An event stream answers `200` with `content-type: text/event-stream;
charset=utf-8` and `cache-control: no-cache`. It sends no `connection` header:
the header is hop-by-hop and forbidden in HTTP/2. The body is a `StreamedBody`
that is written as it comes. It starts with a comment (`:`), which flushes the
headers through proxies, and goes on with two kinds of event: `next`, one per
result, and `complete`, which says the operation is over.

```text
:

event: next
data: {"data":{"count":1}}

event: complete
data:

```

A slow client slows the operation down: when the host pauses the body, the
stream pauses the subscription it reads from, so no event piles up in memory.
A client that goes away makes the host cancel the body, which cancels the
subscription and every resolver behind it.

## Distinct connections mode

`HttpOptions.sse` is `SseOptions()` by default; `null` turns event streams off,
and `Accept: text/event-stream` alone is then `406` (`GQL422`). A `GET` or
`POST` whose `Accept` prefers `text/event-stream` is answered with an event
stream of its own operation, and `*/*` still gets
`application/graphql-response+json`. A subscription sends one `next` event
per result; a query, a mutation or a request error (a parse or validation
error included) sends one `next` event; each stream ends with `complete`.
A mutation is allowed over `POST` only, as everywhere. These stay JSON
refusals instead of a stream: `405`, `500`, the refusals that precede the
pipeline (`415`, `413`, `400`) and a request blocked by CSRF prevention
(`403`). A batch cannot be answered as an event stream (`406`, `GQL422`; in
single connection mode a batch is `422`, `GQL428`), and a multipart `POST`
does not offer one.

When `Accept` lists several media types at the same quality, the order of the
handler's offer wins: `text/event-stream, application/json` gets JSON, while
`text/*` gets the stream. A client that wants a stream should send
`text/event-stream` alone, as `EventSource` and the graphql-sse client do.

A native browser `EventSource` cannot set request headers, and CSRF prevention
refuses a `GET` that has none of its preflight headers (`403`, `GQL403`; see
the Server guide). A browser client therefore uses a fetch-based client that
sends `graphql-require-preflight: true`, or the server runs a profile with
`withCsrfPrevention` relaxed (null turns the check off, which is safe only for
an endpoint that carries no cookies). The same holds for the `GET` that
connects a single connection stream. While the mode is on, a distinct-mode
client that passes its credentials as a `?token=` parameter is not served: any
request with a `token` parameter is read as a stream token (`404`, `GQL433`).

This program runs a subscription through the handler with an event stream
`Accept`:

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      t
          .field('count', b.int)
          .subscribe(
            (parent, args, context, info) => Stream.fromIterable([1, 2]),
          ),
    ],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query, subscription: subscription),
    contextFactory: (request) => null,
    profile: ServerProfile.development,
  );
  final handler = GraphQLHttpHandler<Object?>(server);

  final response = await handler.handle(
    HttpRequestData(
      method: 'POST',
      uri: Uri.parse('http://localhost/graphql'),
      headers: {
        'content-type': 'application/json',
        'accept': 'text/event-stream',
      },
      body: Stream.value(
        utf8.encode('{"query":"subscription { count }"}'),
      ),
    ),
  );

  print(response.status);
  print(response.headers['content-type']);
  if (response.body case StreamedBody(:final chunks)) {
    final text = await utf8.decoder.bind(chunks).join();
    for (final frame in text.split('\n\n')) {
      if (frame.isNotEmpty && !frame.startsWith(':')) {
        print(frame.replaceAll('\n', ' '));
      }
    }
  }
}
```

It prints:

```text
200
text/event-stream; charset=utf-8
event: next data: {"data":{"count":1}}
event: next data: {"data":{"count":2}}
event: complete data:
```

## Single connection mode

Browsers limit the connections to one origin under HTTP/1.1, so a client with
many subscriptions can ask for one stream that carries them all. It is on when
`SseOptions.singleConnection` holds a `SingleConnectionOptions` value:

```text
HttpOptions(
  sse: SseOptions(singleConnection: SingleConnectionOptions()),
)
```

The flow, with the token in the `x-graphql-event-stream-token` header or in
the `token` query parameter:

| Request | Answer |
|---|---|
| `PUT` | reserves a stream: `201`, `text/plain`, the token (the `Accept` header must allow `text/plain`) |
| `GET` with the token and `Accept: text/event-stream` | connects the stream; it stays open until the client goes away and never sends `complete` for itself |
| `POST` of a request with the token and `extensions.operationId` | starts the operation: `202` with an empty body; its events come on the stream |
| `DELETE` with the token and `?operationId=<id>` | cancels the operation: `200`, also for an id that is not running |

The events of an operation carry its id: `next` has the data
`{"id":"a","payload":{"data":{...}}}` and `complete` has `{"id":"a"}`. An
operation that is cancelled sends no `complete`. A result produced before the
client connects is held and flushed on connect; a subscription is not even
started until the stream is listened to.

Refusals:

| Status | Code | When |
|---|---|---|
| `404` | `GQL433` | no stream is reserved for the token |
| `409` | `GQL434` | the stream for the token is already open |
| `400` | `GQL435` | a `POST` has no `extensions.operationId` (a `DELETE` has no `operationId`) |
| `409` | `GQL436` | an operation with that id is already running on the stream |
| `409` | `GQL438` | the stream runs more than `maxOperationsPerStream` operations |
| `503` | `GQL437` | the server holds `maxReservations` reservations |

A batch cannot run on an event stream (`422`, `GQL428`, also when batching is
on). Only a `GET` connects a stream; a `POST` with the token is an operation
whatever its `Accept` says. While the mode is on,
a `405` lists `allow: GET, POST, PUT, DELETE`; while it is off, a token is
ignored and `PUT` and `DELETE` are `405`.

The reservations live in the handler, in memory. A deployment with several
instances needs sticky sessions, so that the `PUT`, the `GET` and the `POST`s
of one client reach the same instance.

`PUT` runs before any context factory, so it has no authentication hook:
anyone who can reach the endpoint can hold reservations for
`reservationTimeout` each, and `maxReservations` is what bounds that. This is
inherent in the protocol.

The token is what protects the stream: only a client that read the answer to
the `PUT` holds it, and a cross-site `PUT` needs a preflight. The operations
are ordinary JSON `POST`s and pass the CSRF rule of the server profile. Keep
the token out of logs, and prefer the header to the query parameter, which
proxies tend to log.

## Keep-alive

`SseOptions.keepAliveInterval` (12 seconds by default) is how long a stream
may stay silent before the server writes another comment, so that proxies and
load balancers do not close an idle connection. A paused client gets no
comment: it already has bytes it has not read.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const options = SseOptions(keepAliveInterval: Duration(seconds: 5));
  print(options.keepAliveInterval.inSeconds);
}
```

It prints:

```text
5
```

## Proxies

A proxy that buffers the response holds the events back until the buffer
fills. Turn buffering off for the endpoint: for nginx send the response header
`X-Accel-Buffering: no` (set it in the host, it is a proxy instruction and not
part of the protocol) or `proxy_buffering off`, and do not compress the
response. The host adapter must write each chunk to the socket and flush it,
not collect the body. Under HTTP/1.1 a browser opens six connections to an
origin, and every distinct stream takes one; that is what the single
connection mode is for.

## Limits

`SingleConnectionOptions` bounds the mode:

- `maxReservations` (1000): reservations held at once; more is `503`;
- `reservationTimeout` (30 seconds): a reservation that no `GET` connects, or
  whose connected stream the host does not listen to, in this time is dropped
  with the operations it held;
- `maxOperationsPerStream` (100): operations running or held on one stream.

A single connection stream the host never listens to is dropped by that
timeout, so a lost response does not hold its slot for ever. A distinct stream
starts its work when the host listens, so the host must still cancel or listen
to every body it gets. The limits of the
pipeline (`ServerLimits`, cost, cancellation and timeouts) apply to every
operation as for any request.
