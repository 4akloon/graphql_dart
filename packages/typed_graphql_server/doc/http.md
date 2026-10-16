# HTTP

`GraphQLHttpHandler` serves GraphQL over HTTP on top of a `GraphQLServer`
(R5.5). It implements the GraphQL over HTTP specification for `GET` and
`POST` with JSON bodies, in the current media type
`application/graphql-response+json` and in the legacy `application/json`. It
knows no web framework and imports no `dart:io`: a host adapter converts its
own request into an `HttpRequestData`, calls `handle` and writes the
`HttpResponseData` it gets back.

What the handler does:

- checks the URI length, the method and the `Accept` header;
- decodes the `GET` query string or the `POST` JSON body within a size, a time
  and a nesting limit;
- sends the request through the whole `GraphQLServer` pipeline (document
  cache, limits, CSRF prevention, extensions, masking);
- writes the result with the status code the specification gives it;
- runs a batch of requests, when you turn batching on.

What it does not do, because the host or the proxy in front of it does:

- **routing**: the host mounts the handler where it likes, and the handler
  ignores the path;
- **CORS**: `OPTIONS` is a `405` here, so answer a preflight in the host;
- **header and connection limits**: the time headers take to arrive, idle
  keep-alive connections, the number of connections and the size of the
  headers.

## The values

An `HttpRequestData` holds the method, the full URI, the headers (names are
lower-cased), the body as a stream of byte chunks, and optionally the host's
own request object and a `CancelSignal` the host cancels when the client goes
away. The body is a stream so that the handler can stop reading at its size
limit; a host that has the bytes passes `Stream.value(bytes)`. The body is read
at most once, and only when the request got that far. When the handler
refuses a request before it reads the body (`415`, or `413` by the declared
length), the stream is left unlistened: the host must drain it or close the
connection, or the connection cannot be reused.

An `HttpResponseData` holds a status, headers and a body. The body is a
`FixedBody` (all bytes known) or a `StreamedBody` (chunks written as they
come).

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final request = HttpRequestData(
    method: 'POST',
    uri: Uri.parse('http://localhost/graphql'),
    headers: {'Content-Type': 'application/json'},
    body: Stream.value(utf8.encode('{"query":"{ hello }"}')),
  );
  final response = HttpResponseData(
    200,
    headers: {'Content-Type': 'application/json'},
    body: FixedBody(utf8.encode('{"data":{"hello":"Hello"}}')),
  );
  print(request.header('CONTENT-TYPE'));
  print(response.headers['content-type']);
  print(response.status);
}
```

It prints:

```text
application/json
application/json
200
```

## Handling a request

Build the `GraphQLServer` as usual, wrap it in a handler and call `handle`.
`handle` never throws: a bad request is a response, and a bug in the handler
itself is a `500` with `GQL330` (masked when the server's profile masks
errors).

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
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
        'accept': 'application/graphql-response+json',
      },
      body: Stream.value(utf8.encode('{"query":"{ hello }"}')),
    ),
  );

  print(response.status);
  print(response.headers['content-type']);
  if (response.body case FixedBody(:final bytes)) {
    print(utf8.decode(bytes));
  }
}
```

It prints:

```text
200
application/graphql-response+json; charset=utf-8
{"data":{"hello":"world"}}
```

## Media types and status codes

`Accept` is read as media ranges with quality values. The handler offers
`application/graphql-response+json` first, `application/json` second and,
unless `HttpOptions.sse` is null (and never for a multipart `POST`),
`text/event-stream` third; `*/*` and `application/*` therefore give the first.
A missing or blank `Accept` is treated as `application/json`, so a client that
does not know the new media type keeps working; an `Accept` that allows none
of the offered types is a `406`, and its message names all of them (see the
Server-sent events guide for the event stream).

A result of the pipeline is written in the chosen type with `charset=utf-8`.
A refusal the transport itself makes (a size limit, a wrong content type, a bad
batch) is always `application/json`, because it is not a well-formed
GraphQL-over-HTTP response, and its body is
`{"errors":[{"message":...,"extensions":{"code":"GQL4xx"}}]}`.

| Result | `graphql-response+json` | `application/json` |
|---|---|---|
| executed, no errors | `200` | `200` |
| executed, errors present | `294` (`200` with `usesPartialSuccessStatus: false`) | `200` |
| the document does not parse (`GQL0xx`) | `400` | `400` |
| CSRF prevention (`GQL403`) | `403` | `403` |
| any other request error: no query, validation, limits, persisted documents, variables, `GQL430`, `GQL431` | `422` | `422` |
| a `GET` mutation | `405` with `allow` | `405` with `allow` |
| internal error | `500` | `500` |

`294` tells a client that reads only the status that the result is partial.
A legacy client always gets `200` for an executed result, whatever it holds.

The refusals of the transport, in the order they are checked (the last row is
the pipeline's own, for a request that reached it):

| Check | Status | Code |
|---|---|---|
| URI longer than `maxUriLength` | `414` | `GQL426` |
| method other than `GET` and `POST` | `405`, `allow: GET, POST` (`GET, POST, PUT, DELETE` with single connection mode on) | `GQL420` |
| `Accept` allows nothing offered | `406` | `GQL422` |
| `GET`: a repeated parameter, bad UTF-8, `variables` or `extensions` not a JSON object | `422` | `GQL425` |
| `POST`: content type is not `application/json` (only `charset=utf-8` is allowed as a parameter) | `415` | `GQL421` |
| body longer than `maxBodyBytes` | `413` | `GQL423` |
| body not complete within `bodyTimeout` | `408` | `GQL427` |
| body not UTF-8, starts with a byte-order mark, not JSON, nested deeper than `maxJsonDepth` | `400` | `GQL424` |
| body is not an object or an array, or a request is malformed | `422` | `GQL425` |
| a batch while batching is off | `422` | `GQL428` |
| an empty batch, or one longer than `maxRequests` | `422` | `GQL429` |
| a subscription | `422` | `GQL431` |

## Limits

`HttpOptions` sets the limits; the handler's constructor throws an
`ArgumentError` naming an option that makes no sense.

| Option | Default | Effect |
|---|---|---|
| `maxBodyBytes` | 1 MiB | a longer body is `413` |
| `bodyTimeout` | 30 s | the whole body must arrive within it, else `408` |
| `maxJsonDepth` | 64 | nesting of the JSON body and of the JSON parameters of a `GET` |
| `maxUriLength` | 8192 characters | a longer URI is `414`, before anything else |
| `usesPartialSuccessStatus` | `true` | `294` for an executed result with errors |
| `batching` | `null` | a `BatchPolicy` turns batching on |
| `onError` | `null` | sees a bug in the handler and its stack trace before the `500` is written (the pipeline's own hook is `GraphQLServer.onError`) |

A `content-length` header can lie or be absent, so the handler refuses a
declared length over the limit without reading, and otherwise counts the bytes
that really arrive: it cancels the stream the moment the count passes the limit,
so it never holds more than `maxBodyBytes` plus one chunk. The time limit covers
the whole body, not each chunk, so a client that trickles one byte at a time is
stopped too. If the host's cancel signal fires while the body is still
arriving, reading stops and the request is refused with `400` (`GQL424`) as if
the connection had failed.

The handler bounds only what it controls. A client that is slow to send its
headers, or that holds a connection open and idle, is not seen by the handler
at all: set `HttpServer.idleTimeout` and a header timeout in the host, or
`client_header_timeout` in the proxy in front of it. The size of the headers
is also the host's (`431`).

Depth is measured before the JSON is decoded, so a body nested 100,000 levels
deep is a quick `400` and cannot overflow the stack.

## Batching

A JSON array of requests is a batch. It is off by default in every profile:
one HTTP request then carries many operations, which defeats the per-request
limits of a proxy or a rate limiter. Turn it on for clients that batch to save
round trips, such as Apollo's `BatchHttpLink`.

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final mutation = b.object<Object?>(
    'Mutation',
    fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query, mutation: mutation),
    contextFactory: (request) => null,
    profile: ServerProfile.development,
  );
  final handler = GraphQLHttpHandler<Object?>(
    server,
    options: const HttpOptions(batching: BatchPolicy(maxRequests: 2)),
  );

  final response = await handler.handle(
    HttpRequestData(
      method: 'POST',
      uri: Uri.parse('http://localhost/graphql'),
      headers: {'content-type': 'application/json'},
      body: Stream.value(
        utf8.encode('[{"query":"{ hello }"},{"query":"mutation { bump }"}]'),
      ),
    ),
  );

  print(response.status);
  if (response.body case FixedBody(:final bytes)) {
    print(utf8.decode(bytes));
  }
}
```

It prints:

```text
200
[{"data":{"hello":"world"}},{"errors":[{"message":"A mutation is not allowed in this request.","extensions":{"code":"GQL431"}}]}]
```

How a batch runs:

- The batch is refused whole, before anything runs, when it is empty, longer
  than `maxRequests` (the items are not even decoded then) or when one item is
  not a request (the message names its index).
- Items run one after the other, in order, each through the whole pipeline
  with its own context.
- Items may be queries; with `allowsMutations` they may also be mutations. A
  refused item holds `GQL431` in its slot and the others still run. A
  subscription is never batched.
- The items share one `CostBudget`: the `maxCost` of the server's profile
  bounds the summed field cost and the summed type cost of the whole batch. An
  item that alone is over `maxCost` is `GQL238`; one that would bring the sum
  over it is `GQL430` in its slot and is not charged.
- The response is `200` with a JSON array of the items' results in order, in
  the negotiated media type, because one status cannot describe several
  results.

## Uploads

A `POST` with the content type `multipart/form-data` carries files next to the
operation, as the GraphQL multipart request specification defines. It is
refused with `415` (`GQL421`) until `HttpOptions.uploads` holds an `Uploads`
value; see the Uploads guide for the schema scalar, the limits, the CSRF rule
and the storage.

## Event streams

A `GET` or `POST` whose `Accept` prefers `text/event-stream` is answered as
GraphQL over server-sent events, in the distinct connections mode, and
`HttpOptions.sse` can turn on the single connection mode; see the Server-sent
events guide. The response body is then a `StreamedBody` that the adapter must
write and flush chunk by chunk, and cancel when the client goes away.

## Writing a host adapter

An adapter for a framework does three things: convert the request, call the
handler, write the response. For shelf it is written: `typed_graphql_shelf`
ships `GraphQLShelfHandler`.

```text
Future<void> serve(FrameworkRequest request, FrameworkResponse out) async {
  final response = await handler.handle(
    HttpRequestData(
      method: request.method,
      uri: request.requestedUri,        // the full URI, query string included
      headers: request.headers,         // repeated values joined with ", "
      body: request.bodyStream,         // not read into memory first
      source: request,                  // the handler never reads it
      cancelSignal: clientGone,         // cancelled when the client leaves
    ),
  );
  out.status = response.status;
  response.headers.forEach(out.setHeader);
  switch (response.body) {
    case FixedBody(:final bytes):
      out.write(bytes);
    case StreamedBody(:final chunks):
      // Write each chunk as it comes, flush it, and cancel the subscription
      // when the client goes away.
      await out.addStream(chunks);
  }
  await out.close();
}
```

Pass a body stream, not a buffered list, when the framework gives one: the
handler then never buffers more than `maxBodyBytes`. Cancel the `CancelSignal`
when the connection closes so that a long query stops (see the Cancellation
guide). Compare the method as the framework gives it; the handler ignores its
case. A `StreamedBody` is an event stream: write it as it arrives, without
buffering, and cancel the subscription when the client goes away.

## Security notes

- **CSRF prevention stays in the pipeline.** A `GET` needs a header such as
  `graphql-require-preflight`, or `GQL403` (`403`) refuses it, as the server's
  `CsrfPrevention` is configured (see the Server guide); a `POST` with a JSON
  content type passes. The handler passes the pipeline the method, the URI and
  the headers and adds nothing of its own.
- **CORS is the host's.** Answer `OPTIONS` preflights and add
  `access-control-*` headers in the adapter, with the origins you trust. The
  handler answers `OPTIONS` with `405`.
- **Batching is off** until you choose a `BatchPolicy`; keep `maxRequests` small
  and `allowsMutations` off unless a client needs them, and set a `maxCost` in
  the server's limits so the shared budget bounds a batch.
- **Errors are masked** by the production profile, in transport refusals too:
  an unexpected failure in the handler is `GQL330` with a generic message.
- **Subscriptions are refused** over plain JSON (`GQL431`), before the context
  is built; they have their own transports.

## GraphiQL

With `ServerProfile.graphiql` on (the default of `ServerProfile.development`,
off in `production`), a `GET` without a `query` whose `Accept` ranks
`text/html` above both JSON types gets the GraphiQL page instead of an error.
A missing `Accept` or `*/*` ranks them equally, so it is still a GraphQL
request. The page loads React and GraphiQL 3.9.0 from jsDelivr, each pinned
by version and Subresource Integrity, sends its queries to the path it was
opened at, and is served with `nosniff`, `no-referrer` and `x-frame-options:
DENY`. Subscriptions are not run from the page. With the switch off, the same
request is an ordinary one and, with no query, `GQL400`.
