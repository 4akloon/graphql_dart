# M7 Transports: stage design

Stage M7 of the [roadmap](../../roadmap.md): GraphQL over HTTP (with CSRF
prevention and the batching policy applied at the transport), multipart
uploads, graphql-ws, graphql-sse, and `typed_graphql_shelf` with the GraphiQL
page in development (R5.5-R5.9). It refines section 5 ("Transport-agnostic
handlers", "Adapters") of the architecture spec
(`2026-10-13-typed-graphql-design.md`) on top of M6's `GraphQLServer`
(`2026-10-15-m6-server-pipeline-design.md`); every change to either is listed
in section 15, and every decision left to the owner in section 16.

## 1. Scope and delivery

M7 lives in `packages/typed_graphql_server` (the transport handlers, which
import no `dart:io` and no web framework) and `packages/typed_graphql_shelf`
(the only package that imports `shelf` and `dart:io`). The core changes only
for the diagnostic codes `GQL420`-`GQL442` (section 13), one core commit per
sub-stage before the server commits that report them.

| Sub-stage | Delivers | Requirements | Plan | Base |
|---|---|---|---|---|
| M7a | `HttpRequestData`, `HttpResponseData`, `HttpResponseBody`, `HttpOptions`, `BatchPolicy`, `GraphQLHttpHandler` (GET, POST JSON, negotiation, status codes, body limits, batching); `GraphQLServer.profile`, `ServerRequest.allowedOperationTypes` and `costBudget`, `CostBudget`; `GQL420`-`GQL431`; the HTTP guide | R5.5, R5.12 (batching, opt-in), R5.15 | `2026-10-16-m7a-http.md` | `main` |
| M7b | `Upload`, `UploadStorage`, `MemoryUploadStorage`, `Uploads`, `UploadLimits`, the multipart reader; `GQL440`-`GQL442`; the Uploads guide | R5.6 | `2026-10-16-m7b-uploads.md` | M7a |
| M7c | `GraphQLSocket`, `GraphQLWsHandler`, `GraphQLWsOptions`, `ConnectionDecision`, `ConnectionHook`; `RequestInfo.connectionParams`; `GQL432`; the WebSocket guide | R5.7 | `2026-10-16-m7c-graphql-ws.md` | `main` (parallel) |
| M7d | `SseOptions`, `SingleConnectionOptions`, distinct connections and single connection modes in `GraphQLHttpHandler`; `GQL433`-`GQL438`; the SSE guide | R5.8 | `2026-10-16-m7d-sse.md` | M7b |
| M7e | merge of M7c; `ServerProfile.graphiql`; the GraphiQL page; `typed_graphql_shelf`: `GraphQLShelfHandler`, `TempFileUploadStorage`, the WebSocket bridge, end-to-end tests over `shelf_io`; the Shelf guide and the stage's last documents | R5.9, R5.15 | `2026-10-16-m7e-shelf-graphiql.md` | M7d + M7c |

Order: M7a, M7b, M7d, M7e on one branch; M7c depends only on M6 and can run
in a separate worktree at the same time as M7a-M7d. M7e's Task 1 merges it
(section 17 lists the files both sides touch and how the merge resolves
them). Run one after the other, M7c may also be applied after M7b; its
shared-file edits are anchored by content, not by line.

Out of scope: incremental delivery over `multipart/mixed` and SSE (R5.10,
M14), response cache and tracing (R5.12, LATER), the legacy
`subscriptions-transport-ws` protocol (architecture section 5), an adapter
for `dart:io` alone or dart_frog (one small class each, later), and the
grund adapter (it lives in the grund repository; section 2).

## 2. Layering and hosting

New folders in `packages/typed_graphql_server/lib/src/`, each a dartdoc
category with its guide:

| Folder | Holds | Category, guide | Sub-stage |
|---|---|---|---|
| `http/` | the HTTP handler, its values, negotiation, body reading, batching, the GraphiQL page, the SSE modes' wiring | `http`, `doc/http.md` | M7a, M7d, M7e |
| `upload/` | `Upload`, storage, the multipart reader, the map | `uploads`, `doc/uploads.md` | M7b |
| `websocket/` | graphql-ws: socket, handler, session, messages | `websocket`, `doc/websocket.md` | M7c |
| `sse/` | event-stream writing, reservations, the two modes' state | `sse`, `doc/sse.md` | M7d |

The server package keeps its import rule (M5 spec §17, M6 spec §2):
`dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:math`,
`meta`, `crypto` and the core barrel. M7 adds `dart:typed_data` (pure Dart,
the core already allows it) and `package:mime/mime.dart` (M7b, section 8;
deviation 4). No library of the server names `shelf`, `dart:io` or
`dart:html`.

**Hosts.** A host is a thin adapter that converts its request into
`HttpRequestData`, calls `GraphQLHttpHandler.handle`, and writes the
`HttpResponseData`; for WebSocket it wraps its connection in a
`GraphQLSocket` and calls `GraphQLWsHandler.serve`. `typed_graphql_shelf`
is the adapter shipped here (section 11). The sibling framework the task
names "dartnest" is not on disk; the sibling that consumes typed_graphql is
grund (`../grund`), whose `docs/adapters.md` streams bodies both ways and
whose `docs/grund-roadmap.md` asks M7 for exactly this: an HTTP handler over
bytes and headers without shelf, and graphql-ws and graphql-sse over an
abstract channel (deviation 1). Nothing in the server's public API names a
shelf or grund type: the host's own request object travels opaquely as
`source`.

## 3. The HTTP values (M7a; R5.5, R5.9)

```text
final class HttpRequestData {
  HttpRequestData({required String method, required Uri uri,
      Map<String, String> headers = const {},
      Stream<List<int>> body = const Stream.empty(),
      Object? source, CancelSignal? cancelSignal});
  String method;            // as given; compared ignoring case
  Uri uri;                  // the full URI, query string included
  Map<String, String> headers;   // lower-cased names, unmodifiable;
                                 // repeated values joined with ", "
  Stream<List<int>> body;   // read at most once, only when needed
  Object? source;           // the host's request, never read
  CancelSignal? cancelSignal;   // owned by the host (client gone)
  String? header(String name);
}

final class HttpResponseData {
  HttpResponseData(int status, {Map<String, String> headers = const {},
      HttpResponseBody body = const FixedBody([])});
  int status; Map<String, String> headers; HttpResponseBody body;
}

sealed class HttpResponseBody {}
final class FixedBody extends HttpResponseBody { List<int> bytes; }
final class StreamedBody extends HttpResponseBody { Stream<List<int>> chunks; }
```

- The body is a stream so a host that streams (grund, `dart:io`) never
  buffers more than the handler allows, and so the handler can apply its
  limit while reading (section 4). A host that has the bytes passes
  `Stream.value(bytes)`.
- A `StreamedBody` is an event stream (M7d). The host must write it as it
  comes (shelf: `shelf.io.buffer_output: false`) and cancel its subscription
  when the client goes away: the handler cancels the operation in
  `onCancel` (section 10).
- Header names are lower-cased by M6's `HeaderNames`. The handler never
  reads `source`.

`GraphQLHttpHandler<C>(GraphQLServer<C> server, {HttpOptions options})` has
one method, `Future<HttpResponseData> handle(HttpRequestData request)`, that
never throws (R0.3): the outermost `on Object` turns a bug into a `500` with
`GQL330`, masked per `server.profile.maskErrors`. It does not route by path:
the host mounts it where it likes.

## 4. HTTP requests (M7a; R5.5)

`HttpOptions` (const) holds the transport's settings:

| Option | Default | Effect |
|---|---|---|
| `maxBodyBytes` | 1,048,576 (1 MiB, grund's default) | a body longer is `413` (`GQL423`) |
| `bodyTimeout` | 30 s | the whole body must arrive within it, else `408` (`GQL427`) |
| `maxJsonDepth` | 64 | nesting of the JSON body and of the GET JSON parameters; deeper is `400` (`GQL424`) |
| `maxUriLength` | 8,192 characters | a longer URI is `414` (`GQL426`), before anything else |
| `usesPartialSuccessStatus` | `true` | `294` for a result with data and errors under `application/graphql-response+json` (section 5) |
| `batching` | `null` (off) | a `BatchPolicy` turns batching on (section 6) |
| `uploads` (M7b) | `null` (off) | an `Uploads` turns multipart requests on (section 8) |
| `sse` (M7d) | `SseOptions()` | `null` turns `text/event-stream` off (section 10) |

The handler's constructor checks them: a negative or zero size or duration,
or a `maxJsonDepth` above `JsonReader.maxSupportedDepth`, is an
`ArgumentError` (a programmer error, not input).

**Order of checks** (each refusal is the first that applies; refusals before
the pipeline are transport refusals, written as in section 5):

1. URI longer than `maxUriLength`: `414`, `GQL426`.
2. Method: `GET` and `POST` (and, with single connection mode, `PUT` and
   `DELETE`, section 10); any other, `HEAD` and `OPTIONS` included, is
   `405` with `allow: GET, POST` (`GQL420`). CORS preflight is the host's
   (deviation 9).
3. `Accept` (section 5): nothing acceptable is `406`, `GQL422`.
4. `GET`: the query string is decoded (WHATWG `URLSearchParams`, Dart's
   `Uri.queryParametersAll`): a parameter given twice, invalid UTF-8 in the
   query string, `variables` or `extensions` that are not a JSON object
   (after `JsonReader` with `maxJsonDepth`) are `422`, `GQL425`. An empty
   value means absent (spec §GET); `operationName=null` is the name
   `"null"`.
5. `POST`: `content-type` must be `application/json`, with no parameter but
   an optional `charset=utf-8` (any case); a missing type, another type or
   charset is `415`, `GQL421` (`multipart/form-data` goes to the multipart
   reader when uploads are on, section 8). A `content-length` above
   `maxBodyBytes` is `413` before reading.
6. The body is read by `BodyReader` with a running count: past
   `maxBodyBytes` it cancels the stream and answers `413` (`GQL423`), so a
   lying or absent `content-length` never makes the server buffer more than
   the limit; if the whole body has not arrived after `bodyTimeout` it
   cancels and answers `408` (`GQL427`).
7. The bytes are decoded as strict UTF-8 (a byte-order mark is not
   stripped: JSON forbids it), then parsed by the core's `JsonReader` with
   `maxJsonDepth` (it measures nesting before `jsonDecode`, so a deep body
   cannot overflow the stack): failures are `400`, `GQL424`, with the
   reader's message.
8. An object is one request, an array a batch (section 6; `422` `GQL428`
   when batching is off), anything else `422` `GQL425`. The object goes
   through `GraphQLRequest.decode` (types checked, unknown keys ignored,
   `null` meaning absent); a failure is `422`, `GQL425`, with the message
   and path of the `DecodeFailure`.
9. The pipeline runs with a `ServerRequest` whose `info` is a `RequestInfo`
   with the method, URI, headers and `source`, whose `cancelSignal` is the
   request's, and whose `allowedOperationTypes` are query and mutation
   (`GET` mutations are still refused by M6 with `405` `GQL402`): a
   subscription over plain JSON is `422`, `GQL431`, refused before the
   context is built (section 7).

**Slow clients (slowloris).** The handler bounds what it controls: the time
the body takes (`bodyTimeout`) and its size. The time headers take to
arrive, idle keep-alive connections and the number of connections are the
host's or the proxy's (`dart:io`'s `HttpServer.idleTimeout`, nginx
`client_header_timeout`); the guide says so. Header size is the host's too
(`431`).

## 5. Responses, media types and status codes (M7a; R5.5)

**Negotiation.** `Accept` is parsed into media ranges with `q` values
(RFC 9110 §12.5.1). The server offers, in its order of preference:
`application/graphql-response+json`, `application/json`, and (M7d)
`text/event-stream`. The chosen type is the offered type with the highest
`q` of its most specific matching range; ties go to the server's order; a
range with `q=0` excludes. `*/*` and `application/*` therefore give
`application/graphql-response+json`. A missing `Accept` is treated as
`application/json`, the legacy-safe choice the spec allows (deviation 5).
`text/html` is only offered for GraphiQL (section 12).

**Bodies.** A pipeline result is written with the chosen type and
`charset=utf-8`: `application/graphql-response+json; charset=utf-8`, or
`application/json; charset=utf-8` for a legacy client. A transport refusal
(sections 4, 6, 8, 10) is not a well-formed GraphQL-over-HTTP response, so
it never uses `application/graphql-response+json` (spec §Status Codes): its
body is `{"errors":[{"message":...,"extensions":{"code":"GQL4xx"}}]}` as
`application/json; charset=utf-8`. Every JSON body is `jsonEncode` of the
`JsonValue`, UTF-8 encoded.

**Status codes** (spec §Status Codes), from M6's `ServerOutcome`:

| Outcome | `graphql-response+json` | `application/json` (legacy) |
|---|---|---|
| `executed`, no errors | `200` | `200` |
| `executed`, `errors` present (data may be `null`) | `294`, or `200` when `usesPartialSuccessStatus` is off | `200` (deviation 6) |
| `requestError`, first error `GQL0xx` (the document does not parse) | `400` | `400` |
| `requestError`, first error `GQL403` (CSRF prevention) | `403` | `403` |
| any other `requestError` (no query, validation, limits, persisted documents, operation selection, variables, `GQL430`, `GQL431`) | `422` | `422` |
| `methodNotAllowed` (`GET` mutation) | `405`, the response's `allow` header | `405` |
| `internalError` | `500` | `500` |

The `ServerResponse.headers` (M6: `allow`, and whatever an extension adds)
are copied onto the HTTP response, then the handler's `content-type` wins.
A legacy client keeps `application/json` on every status, not only on `2xx`
as the spec words it (deviation 5): a client that did not accept
`application/graphql-response+json` must not receive it.

A `StreamResponse` reaching the JSON writer (only a user extension can
produce one, since subscriptions are refused) is cancelled and answered
`500` `GQL330`.

## 6. Batching (M7a; R5.12, R5.15)

Batching is off by default in both profiles: R5.15 requires it off in
production, and the guide says why a host would turn it on (fewer round
trips from Apollo's `BatchHttpLink`). `HttpOptions(batching:
BatchPolicy(maxRequests: 10, allowsMutations: false))` turns it on for
`POST` JSON bodies that are arrays (and for multipart `operations` arrays,
M7b). It is a transport setting, not a `ServerProfile` field (deviation 7).

- An array is refused whole, before anything runs, when batching is off
  (`422` `GQL428`), when it is empty or longer than `maxRequests` (`422`
  `GQL429`), or when an item does not decode (`422` `GQL425`, the message
  names the index).
- Items run one after the other, in order, each through the whole pipeline
  with its own context (a sequential run keeps the server's per-request
  bounds meaningful; a batch is not a way to multiply concurrency).
- Each item's `ServerRequest` allows queries only; with `allowsMutations`
  also mutations. A refused item answers `GQL431` in its slot; the others
  still run. Subscriptions are never batched.
- Cost (R5.14): the items share one `CostBudget`, so the profile's
  `maxCost` bounds the batch's summed field cost and summed type cost. An
  item that alone exceeds `maxCost` is `GQL238` (M6); one that would bring
  the sum over it is `GQL430`, and is not charged. Without `maxCost` there is
  no accounting.
- The response is `200` with a JSON array of the items' payloads in order,
  in the negotiated media type: one status cannot describe several results.

## 7. Pipeline refinements (M7a, M7c, M7e; M6 spec §16)

Small additions to M6's `server/`, each in the sub-stage that first needs it:

- `GraphQLServer.profile` (M7a): the handler reads `csrfPrevention`,
  `maskErrors` and (M7e) `graphiql` from it.
- `ServerRequest.allowedOperationTypes` (M7a): a `Set<OperationType>`,
  default all three. `RequestStep` refuses another type after the `GET`
  mutation guard and before the cost limit and the context factory, with
  `GQL431` ("A subscription is not allowed in this request.").
- `ServerRequest.costBudget` and the public `CostBudget` (M7a): the field
  and type cost spent so far by the requests that share it (section 6).
  `CostLimit` checks the request alone, then the budget, and charges it.
- `RequestInfo.connectionParams` (M7c): the `connection_init` payload of a
  graphql-ws connection (a `JsonObject?`), so the `ContextFactory` can read
  a token sent there (section 9).
- `ServerProfile.graphiql` and `withGraphiQL` (M7e): `true` in
  `development`, `false` in `production` (R5.15).

## 8. Multipart uploads (M7b; R5.6)

The GraphQL multipart request specification (jaydenseric): a
`multipart/form-data` body whose parts are, in this order, `operations` (a
request or a batch as JSON), `map` (JSON: file field name to a list of
object paths) and the files.

**API.**

```text
abstract interface class Upload {     // what a resolver reads
  String get filename; String get mediaType; int get length;
  Stream<List<int>> openRead();
}
abstract interface class UploadStorage {   // where a file waits
  Future<Upload> store(String filename, String mediaType,
      Stream<List<int>> content);
  Future<void> release(Upload upload);
}
final class MemoryUploadStorage implements UploadStorage { const ...; }
final class UploadLimits { const UploadLimits({int maxFiles = 10,
    int maxFileBytes = 5 MiB, int maxRequestBytes = 20 MiB,
    int maxFieldBytes = 1 MiB}); }
final class Uploads {
  Uploads({UploadStorage storage = const MemoryUploadStorage(),
      UploadLimits limits = const UploadLimits()});
  static const String scalarName = 'Upload';
  ScalarCodec<Upload> get codec;   // input only; encode is an ArgumentError
}
```

The schema declares `b.scalar<Upload>(Uploads.scalarName, uploads.codec)`
and the handler gets `HttpOptions(uploads: uploads)`: one `Uploads` value
wires both sides. `TempFileUploadStorage` (`dart:io`) is in
`typed_graphql_shelf` (section 11).

**How a file reaches a resolver.** The scalar codec has no request context
(M5's `LeafCoercion` calls `decode(JsonValue)` alone), so the reader
replaces each `null` the map names with a string token
`upload:<32 hex digits>` (128 bits from `Random.secure`) and registers the
`Upload` under it in the `Uploads` registry; the codec looks the token up.
After the response is built, the request's tokens are removed and its
uploads released, whatever happened. A token cannot be guessed, so a client
cannot reach another request's file; naming its own tokens in a literal is
harmless. A resolver must read the file during the request (the guide says
so).

**Rules** (all refusals are transport refusals, `application/json`):

- Uploads off: `multipart/form-data` is `415` `GQL421`.
- CSRF first: `multipart/form-data` is a type a browser sends cross-site
  without a preflight, so the handler asks
  `server.profile.csrfPrevention?.allows(info)` before reading the body and
  refuses with `403` and M6's `GQL403` message (deviation 8: the check runs
  in the transport too, so a forged request never costs a file write).
- The boundary parameter is required (`400` `GQL440`). The whole body is
  counted against `maxRequestBytes` (`413` `GQL441`) and `bodyTimeout`.
- `operations` first, then `map`, each at most `maxFieldBytes` and parsed
  with `JsonReader(maxJsonDepth)`; a missing, out-of-order or malformed
  field, a map that is not an object of non-empty string lists, a path that
  does not start with `variables.` (or `<index>.variables.` in a batch),
  that does not name an existing `null`, or a key that is not a file part
  that follows: `400` `GQL440`. More than `maxFiles` map keys, or more paths
  than `maxFiles` in total, is `413` `GQL442` (spec §Security: one part
  named many times cannot multiply the request).
- Files: each part must be a key of the map (an unknown part is `400`
  `GQL440`, not ignored: nothing is guessed silently); more than
  `maxFiles` is `413` `GQL442`; one longer than `maxFileBytes` is `413`
  `GQL441` (the storage's stream errors and the storage must drop what it
  wrote). A key of the map whose file never comes is `400` `GQL440`.
- A part's `content-disposition` must be `form-data` with a `name`; the
  file's `filename` (default `""`) and `content-type` (default
  `application/octet-stream`) are passed to the storage as given.
- Part headers are read by `package:mime`'s `MimeMultipartTransformer`;
  its `MimeMultipartException` and `FormatException` are `400` `GQL440`.
- Multipart requests allow queries and mutations, never subscriptions.

## 9. graphql-ws (M7c; R5.7)

The `graphql-transport-ws` protocol (`reference/graphql-ws/PROTOCOL.md`).

**API.**

```text
abstract interface class GraphQLSocket {
  String? get protocol;            // the negotiated subprotocol
  Stream<String> get incoming;     // text frames; done when closed
  void send(String text);
  Future<void> close(int code, String reason);
}
final class GraphQLWsOptions { const GraphQLWsOptions({
  Duration connectionInitTimeout = 3 s, int maxOperations = 100,
  int maxMessageLength = 1 MiB (characters), int maxJsonDepth = 64,
  int maxConnections = 10000, List<String>? allowedOrigins,
  ConnectionHook? onConnect}); }
typedef ConnectionHook = FutureOr<ConnectionDecision> Function(RequestInfo info);
sealed class ConnectionDecision {}
final class AcceptConnection extends ConnectionDecision { JsonObject? payload; }
final class RefuseConnection extends ConnectionDecision {}
final class GraphQLWsHandler<C> {
  GraphQLWsHandler(GraphQLServer<C> server, {GraphQLWsOptions options});
  static const String protocol = 'graphql-transport-ws';
  bool allowsUpgrade(RequestInfo upgrade);   // the Origin check
  Future<void> serve(GraphQLSocket socket, RequestInfo upgrade);
}
```

The message model (`connection_init`, `connection_ack`, `ping`, `pong`,
`subscribe`, `next`, `error`, `complete`) is internal to `websocket/`
(deviation 2): M11 keeps its own private model in the client for the same
reason, and moving one shared model into the core after both merge is open
question 3.

**Origin (the WebSocket CSRF defence).** A browser sends cookies with an
upgrade and no preflight, so cross-site WebSocket hijacking is the CSRF of
this transport. `allowsUpgrade` passes an upgrade with no `Origin` (not a
browser), with an `Origin` whose host and port equal the `host` header,
or with an `Origin` in `allowedOrigins` (exact, ignoring case). The host
calls it before upgrading and answers `403`; `serve` checks it again and
closes `4403` (defence in depth). M6's `CsrfPrevention` does not apply to
messages: each message's `RequestInfo` is `POST` with the upgrade's headers
plus `content-type: application/json`, so the mutation guard and the CSRF
rule pass (M6 spec §16), and the Origin check is what protects them.

**State machine** (one `SocketSession` per `serve`):

| Event | Effect |
|---|---|
| more than `maxConnections` sessions open | close `1013` "Try again later" |
| `protocol` is not `graphql-transport-ws` | close `4406` "Subprotocol not acceptable" |
| no acknowledgement within `connectionInitTimeout` | close `4408` "Connection initialisation timeout" |
| a frame longer than `maxMessageLength` | close `1009` "Message too big" |
| not JSON (or deeper than `maxJsonDepth`), not an object, no string `type`, an unknown type, a field of the wrong type, or a client sending `connection_ack`, `next` or `error` | close `4400` with a fixed reason ("Invalid message received") |
| `connection_init` (payload an object or absent) | runs `onConnect` with a `RequestInfo` holding `connectionParams`; `AcceptConnection` sends `connection_ack` (with its payload), `RefuseConnection` closes `4403` "Forbidden", a throw closes `4500` "Internal server error"; without a hook it acknowledges |
| a second `connection_init` | close `4429` "Too many initialisation requests" |
| `ping` | `pong`, echoing the payload when there is one; allowed before the ack |
| `pong` | ignored |
| `subscribe` before the ack | close `4401` "Unauthorized" |
| `subscribe` with an id in use | close `4409` "Subscriber for <id> already exists" (the reason cut to 123 UTF-8 bytes) |
| `subscribe` with `maxOperations` running | an `error` message for that id with `GQL432`; the socket stays open |
| `subscribe` | `server.handle` with the message's `GraphQLRequest`, a `RequestInfo` as above, a `CancelSignal` per operation; a `SingleResponse` with a result is `next` then `complete`, a request error is `error` (no `complete`, as the protocol says), a `StreamResponse` is one `next` per result then `complete` |
| `complete` from the client | cancels the operation (its stream subscription and its `CancelSignal`); nothing more is sent for the id; an unknown id is ignored |
| `incoming` ends or fails | every operation is cancelled, the timer stopped; `serve` completes |

An operation whose `complete` arrives while `server.handle` is pending sends
nothing when the response comes; a `StreamResponse` that arrives then is
cancelled at once. Ids are freed when their operation ends, so an id may be
reused (protocol §Subscribe). A missing `query` is not a `4400` here: the
request reaches the pipeline, so persisted documents work over WebSocket and
a missing document is `GQL400` in an `error` message (deviation 10).

**Keep-alive** is WebSocket ping frames, the adapter's (shelf's
`pingInterval`, grund's), not graphql-ws `ping` messages. **Backpressure:**
`send` is fire-and-forget because neither `dart:io`'s `WebSocket` nor
`WebSocketChannel` reports a full buffer; a client that reads nothing while
a subscription produces fast makes the host buffer. `maxOperations` and the
schema's own rate bound it; open question 5.

## 10. graphql-sse (M7d; R5.8)

`reference/graphql-sse/PROTOCOL.md` and its reference `handler.ts`. Both
modes are built because R5.8 is a MUST for both.

`HttpOptions.sse` is `SseOptions(keepAliveInterval: 12 s,
singleConnection: null)`; `null` turns event streams off (then `Accept:
text/event-stream` alone is `406`). `SingleConnectionOptions(maxReservations:
1000, reservationTimeout: 30 s, maxOperationsPerStream: 100)` turns single
connection mode on.

**Event stream.** `200`, `content-type: text/event-stream; charset=utf-8`,
`cache-control: no-cache`; no `connection` header (hop-by-hop, forbidden in
HTTP/2; the reference sets it, deviation 11). Events are
`event: next\ndata: <json>\n\n` and `event: complete\ndata: \n\n` (an empty
`data` so `EventSource` fires); a `:\n\n` comment is sent first (it flushes
the headers through proxies) and every `keepAliveInterval`. The body is a
`StreamedBody` over a controller: its `onPause`/`onResume` pause and resume
the operations' subscriptions (real backpressure: shelf and grund pause a
body stream when the socket is full), and its `onCancel` (the client went
away) cancels them and their `CancelSignal`s.

**Distinct connections mode** (on whenever `sse` is set): a `GET` or `POST`
whose negotiated type is `text/event-stream` and that carries no token.
Decoding is that of section 4. The pipeline runs with all operation types
allowed; then a `methodNotAllowed` outcome is `405` and an `internalError`
`500` (JSON, as section 5); any other `SingleResponse` (a result or a
request error, a parse error included) is one `next` and `complete` in an
accepted stream (protocol §Distinct: "validation steps ... MUST report
errors through an accepted SSE connection"; the reference answers a parse
error with `400`, here it is in the stream too); a `StreamResponse` is one
`next` per result, then `complete`, then the stream ends.

**Single connection mode** (state lives in the handler: a host with several
instances needs sticky sessions; the guide says so):

| Request | Answer |
|---|---|
| `PUT` | a reservation: `201`, `text/plain; charset=utf-8`, the token (32 hex digits from `Random.secure`); `Accept` must allow `text/plain` (`406` `GQL422`); more than `maxReservations` is `503` `GQL437`. A reservation no stream connects within `reservationTimeout` is dropped. |
| `GET` or `POST` with `Accept: text/event-stream` and a token (`x-graphql-event-stream-token` header or `token` parameter) | connects the stream: unknown token `404` `GQL433`, already connected `409` `GQL434`; it ends (and the reservation with its operations is dropped) when the client goes away |
| `POST` JSON with a token | an operation: unknown token `404` `GQL433`; `extensions.operationId` missing or not a non-empty string `400` `GQL435`; in use `409` `GQL436`; more than `maxOperationsPerStream` `409` `GQL438`; otherwise transport refusals as section 4, then the pipeline: `methodNotAllowed`, `internalError` and request errors answer the `POST` as section 5 (protocol §Executing operations), a result answers `202` and goes to the stream as `{"id":...,"payload":...}` then `complete` `{"id":...}` |
| `DELETE` with a token and `operationId` | unknown token `404` `GQL433`, no `operationId` `400` `GQL435`; cancels the operation (no `complete` is sent) and answers `200`, also for an unknown id |
| any request with a token while single connection mode is off | the token is ignored (`PUT` and `DELETE` are `405`) |

An operation posted before its stream connects is held: a result's payload
is kept (bounded by `maxOperationsPerStream`), a subscription's stream is
not listened to until the stream connects, so nothing executes unbounded.
The token is the CSRF defence of the stream: only a client that could read
the `PUT` response holds it, and a cross-site `PUT` needs a preflight. The
operations themselves are ordinary JSON `POST`s and pass M6's CSRF rule.

## 11. `typed_graphql_shelf` (M7e; R5.9)

Depends on `typed_graphql_server`, `shelf`, `shelf_web_socket`,
`web_socket_channel` and `stream_channel` (all already in the workspace lock
through `package:test`).

```text
final class GraphQLShelfHandler<C> {
  GraphQLShelfHandler(GraphQLServer<C> server, {HttpOptions http,
      GraphQLWsOptions? webSocket, Duration webSocketPingInterval = 12 s});
  FutureOr<Response> call(Request request);   // a shelf Handler
}
final class TempFileUploadStorage implements UploadStorage { ... }
```

- `call` turns a WebSocket upgrade (`upgrade: websocket`, `GET`) into a
  graphql-ws session when `webSocket` is given (the Origin check first,
  `403` otherwise; `shelf_web_socket` negotiates `graphql-transport-ws` and
  sends ping frames every `webSocketPingInterval`), and anything else into
  `HttpRequestData` (`requestedUri`, headers, `read()`, the shelf
  `Request` as `source`).
- A `FixedBody` becomes a `Response` body; a `StreamedBody` too, with the
  context `shelf.io.buffer_output: false` so each event is flushed.
- `WebSocketChannelSocket` adapts a `WebSocketChannel`: text frames as they
  are, binary frames decoded as UTF-8 with replacement (they then fail JSON
  parsing and close `4400`).
- `TempFileUploadStorage` writes each upload to a new file under a
  temporary directory (default `Directory.systemTemp`), deletes it on
  release, and deletes a partial file when the content stream fails.

## 12. GraphiQL (M7e; R5.9, R5.15)

The page lives in the server's `http/` (internal `GraphiQLPage`), so grund
and any host serve it through `GraphQLHttpHandler`: a `GET` with no `query`
parameter whose `Accept` prefers `text/html` (over the JSON types) gets the
page when `server.profile.graphiql` is on; otherwise the request goes on as
a GraphQL `GET` (and without a query it is `GQL400`).

- Assets are pinned by version and by Subresource Integrity, loaded from
  jsDelivr with `crossorigin="anonymous"`; no unpinned script:

| Asset | `integrity` |
|---|---|
| `https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js` | `sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z` |
| `https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js` | `sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1` |
| `https://cdn.jsdelivr.net/npm/graphiql@3.9.0/graphiql.min.css` | `sha384-QMux00XgRtwRLSYIY3kw2rj1ovk5AuuliAchk+HSQbqdbGFnz9GYuqIlOqxhwCE2` |
| `https://cdn.jsdelivr.net/npm/graphiql@3.9.0/graphiql.min.js` | `sha384-8NGfVj4CVlqHajlZj+bPJT4thxPMHMJYn7DWK2CvtopLd02E7qsPHazniBYvVjOO` |

  The hashes were computed from the downloaded files on 2026-10-16. 3.9.0 is
  the last GraphiQL with a UMD build that sets `window.GraphiQL` (4.x moved
  it, 5.x is ESM only); open question 6.
- Embedded as a Dart string constant (no asset files: the server package has
  no `dart:io` to read them). The page's script builds a `fetch` fetcher
  (`POST`, `content-type: application/json`, `accept:
  application/graphql-response+json, application/json;q=0.9`) for the
  request's own path; the path is written into a JSON string literal with
  `<`, `>`, `&`, U+2028 and U+2029 escaped, so a crafted URL cannot close the
  script. Subscriptions are not run from the page (open question 7).
- Headers: `content-type: text/html; charset=utf-8`,
  `x-content-type-options: nosniff`, `referrer-policy: no-referrer`,
  `x-frame-options: DENY`. No `content-security-policy` (open question 8).
- No browser runs in CI; a manual check (open the page against the shelf
  example) is in M7e's last task.

## 13. Diagnostic codes

`GQL4xx` is "transports and protocols". M7 uses only `GQL420`-`GQL449`
(`GQL400`-`GQL415` are M6's; `GQL460`-`GQL499` are reserved for M11's
client runtime). Each is a `GraphQLError`'s `extensions.code` in a response
of `GraphQLHttpHandler.handle` (or a graphql-ws `error` message).

| Code | Name | Status | When | Sub-stage |
|---|---|---|---|---|
| `GQL420` | `unsupportedHttpMethod` | 405 | method other than `GET`/`POST` (`PUT`/`DELETE` in single connection mode) | M7a |
| `GQL421` | `unsupportedMediaType` | 415 | `POST` body type not `application/json` (or `multipart/form-data` with uploads), or a charset other than UTF-8 | M7a |
| `GQL422` | `notAcceptable` | 406 | `Accept` allows no offered type | M7a |
| `GQL423` | `requestBodyTooLarge` | 413 | body past `maxBodyBytes` | M7a |
| `GQL424` | `malformedRequestBody` | 400 | body not UTF-8, not JSON, or deeper than `maxJsonDepth` | M7a |
| `GQL425` | `malformedRequestParameters` | 422 | not a GraphQL-over-HTTP request: wrong types, a repeated or undecodable `GET` parameter, a body that is not an object | M7a |
| `GQL426` | `requestUriTooLong` | 414 | URI past `maxUriLength` | M7a |
| `GQL427` | `requestBodyTimeout` | 408 | body not complete within `bodyTimeout` | M7a |
| `GQL428` | `batchingDisabled` | 422 | an array body with batching off | M7a |
| `GQL429` | `invalidBatchSize` | 422 | an empty batch or one past `maxRequests` | M7a |
| `GQL430` | `batchCostExceeded` | 422 (item) | the batch's summed cost would pass `maxCost` | M7a |
| `GQL431` | `operationTypeNotAllowed` | 422 | an operation type the request does not allow | M7a |
| `GQL432` | `tooManySocketOperations` | (`error` message) | `maxOperations` running on one socket | M7c |
| `GQL433` | `eventStreamNotFound` | 404 | no reservation for the token | M7d |
| `GQL434` | `eventStreamAlreadyOpen` | 409 | the reservation's stream is connected | M7d |
| `GQL435` | `operationIdRequired` | 400 | no `extensions.operationId` / `operationId` | M7d |
| `GQL436` | `operationIdInUse` | 409 | the id runs on the stream | M7d |
| `GQL437` | `tooManyReservations` | 503 | `maxReservations` held | M7d |
| `GQL438` | `tooManyStreamOperations` | 409 | `maxOperationsPerStream` running | M7d |
| `GQL440` | `malformedMultipartRequest` | 400 | section 8 | M7b |
| `GQL441` | `uploadTooLarge` | 413 | a file past `maxFileBytes` or the body past `maxRequestBytes` | M7b |
| `GQL442` | `tooManyUploads` | 413 | more than `maxFiles` files or paths | M7b |

`GQL439` and `GQL443`-`GQL449` stay free. graphql-ws protocol violations are
close codes, not diagnostics (the protocol has no message for them).

## 14. Hostile input (R0.3)

Each sub-stage has `hostile_*_test.dart` files; each test proves both the
refusal and that nothing ran (a counting context factory and resolvers, as
M6's `HostileFixture`):

- **HTTP** (M7a): a 10 MiB body with and without `content-length`, a
  `content-length` that lies low, a body that never ends (the timeout), a
  body that trickles one byte per 10 ms, invalid UTF-8, a byte-order mark,
  JSON nested 100,000 deep, a 9 KiB URI, 10,000 repeated `GET` parameters,
  `variables` as a deep JSON string in `GET`, a `POST` without a content
  type, `text/plain` and `application/x-www-form-urlencoded` bodies (the CSRF
  types), an `Accept` of 10,000 ranges, a batch of 10,000 items, a batch
  whose items each cost just under `maxCost`.
- **Uploads** (M7b): a forged multipart request without the preflight
  header (no file is stored), a missing boundary, parts out of order, a map
  naming 10,000 paths, a path into `query` or `extensions`, a path to a
  non-null value, an unknown part, a file over the limit (the storage holds
  nothing afterwards), too many files, a truncated body, a token sent as a
  literal from another request.
- **graphql-ws** (M7c): subscribe before init, a second init, no init (the
  timeout), malformed JSON, deep JSON, an oversized frame, an unknown type,
  `next` from the client, a duplicate id, 10,000 subscribes past
  `maxOperations`, a ping flood answered one for one, a client that
  disconnects mid-subscription (the source is cancelled), a foreign
  `Origin`, too many sockets, a wrong subprotocol, a throwing `onConnect`.
- **SSE** (M7d): a stream the client cancels (the subscription's source is
  cancelled), a stream the host pauses (the source pauses), an unknown or
  guessed token, two streams for one reservation, 1,001 reservations, a
  reservation never connected (dropped after the timeout), a duplicate
  operation id, operations past the limit, `DELETE` of another reservation's
  operation.

## 15. Deviations from the architecture spec, M6 and the protocols

1. **grund, not "dartnest".** The task names `../dartnest`; it does not
   exist. The consumer is grund (`../grund`); its `docs/adapters.md` and
   `docs/grund-roadmap.md` agree with this design (section 2).
2. **graphql-ws messages are internal to the server**, not in the core's
   `protocol/` as architecture section 5 says. M11 (designed at the same
   time) keeps its own private model in the client; two plans writing the
   same core files would collide. Open question 3.
3. **No SSE types in the core** for the same reason: the server's event
   writer is internal, M11's parser is internal.
4. **New dependency `mime`** in the server (dart-lang, pure Dart, no
   dependencies) for multipart parsing; the import rule allows
   `package:mime/mime.dart` and `dart:typed_data`.
5. **Negotiation without `Accept` gives `application/json`**, and a legacy
   client gets `application/json` on every status, not only `2xx` (section
   5).
6. **`294` only under `application/graphql-response+json`**; a legacy client
   gets `200` for partial success, since it and intermediaries may not know
   `294`. Open question 2.
7. **Batching is a transport option** (`HttpOptions.batching`), off in both
   profiles, not a `ServerProfile` field (R5.15 only requires it off in
   production); brought forward from R5.12 (LATER) because the roadmap puts
   the batching policy in M7.
8. **CSRF is checked in the transport for multipart**, before the body is
   read, in addition to M6's check in the pipeline.
9. **No CORS** in the handler: preflight `OPTIONS` is `405`; CORS is the
   host's middleware (shelf's `corsHeaders`, grund's).
10. **graphql-ws `subscribe` without `query` reaches the pipeline** instead
    of closing `4400` (persisted documents over WebSocket).
11. **No `connection: keep-alive` header** on event streams (section 10).
12. **M6 refinements**: `GraphQLServer.profile`,
    `ServerRequest.allowedOperationTypes` and `costBudget`, `CostBudget`,
    `RequestInfo.connectionParams`, `ServerProfile.graphiql` (section 7).
13. **Close codes `1009` and `1013`** (RFC 6455 "message too big", "try
    again later") for an oversized frame and a full server; the graphql-ws
    reference has no code for either.

## 16. Open questions for the owner

Each has the recommendation the plans implement until the owner decides.

1. **Missing `Accept`.** Implemented: `application/json` (legacy-safe).
   Alternative: `application/graphql-response+json`, the spec's preferred
   type.
2. **`294` for partial success.** Implemented: on by default under
   `application/graphql-response+json` (the spec's SHOULD), `200` for legacy
   clients, `usesPartialSuccessStatus: false` turns it off. Alternative: off
   by default until clients and proxies know `294`.
3. **One graphql-ws/graphql-sse message model in the core.** Recommended:
   after M7 and M11 merge, compare the two private models and move one into
   `protocol/` (architecture section 5), as M11's open question 4 says.
4. **Batching defaults.** Implemented: off in both profiles, 10 requests,
   no mutations, sequential. Alternative: on in `development`.
5. **WebSocket backpressure.** Implemented: none (fire-and-forget `send`).
   Recommended next: `send` returning `FutureOr<void>` so an adapter that
   can observe its buffer (grund) pauses the subscription; it changes
   `GraphQLSocket`, so decide before the first release.
6. **GraphiQL version.** Implemented: 3.9.0 (UMD). Alternative: 5.x as an
   ES module from an import map, which needs a browser test to adopt.
7. **Subscriptions in GraphiQL.** Implemented: none. Alternative: an SSE
   fetcher in the page script (about 40 lines of JavaScript, untested in CI).
8. **A `content-security-policy` on the GraphiQL page.** Implemented: none
   (development only, and an untested policy would break the page).
   Alternative: a policy with the inline script's hash, checked by hand.
9. **`maxConnections` default (10,000) and `maxOperations` (100) for
   graphql-ws; `maxReservations` (1,000) for SSE.** Implemented as listed.
10. **Status of a persisted-query miss (`GQL410`).** Implemented: `422` like
    any request error. Alternative: `200`, which some Apollo setups expect
    for `GET` caching.

## 17. Notes for the implementers

- **Parallel work.** M7c may run in its own worktree from `main` while
  M7a, M7b and M7d run in order on another. Files both lines touch: the
  core's `diagnostic_code.dart` and `CHANGELOG.md`, the server's barrel
  `lib/typed_graphql_server.dart`, `CHANGELOG.md`, `README.md`,
  `dartdoc_options.yaml`, `test/quality/import_rule.dart` (M7b only) and
  `lib/src/server/request_info.dart` (M7c only, so no conflict). M7e Task 1
  merges M7c and resolves each conflict by keeping both sides in id or
  alphabetical order; its plan gives the resolved text.
- M7c does not touch `CLAUDE.md`, `llms.txt`, `docs/discovery.md` or the
  root README; M7e adds its paragraph with the merge.
- Timing tests use short real durations (tens of milliseconds) and
  `Completer`s, not `fake_async` (not a dependency of the server).
- Every hostile test asserts the response (status, code) and that no
  context was built and no resolver ran when the refusal comes first.
- A refusal message never echoes request content beyond a parameter name or
  an id (an id is cut to 123 bytes in a close reason).
- `dart:io` appears only in `typed_graphql_shelf` and its tests
  (`@TestOn('vm')`).
