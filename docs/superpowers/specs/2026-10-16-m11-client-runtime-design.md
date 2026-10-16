# M11 Client runtime: stage design

Status: written for the owner's review 2026-10-16 (the open questions are in
section 17). Every API below was checked by implementing the plans of M11a to
M11f in a scratch copy of `main` at `8ed1c85`, one commit per plan task, with
format, analyze and every affected suite green on the VM; the plans paste
that code. Refines section 6 "Client" of
[the architecture](2026-10-13-typed-graphql-design.md) and never overrides it
silently: deviations are numbered in section 16. Builds on the generated-code
contract of [M10](2026-10-15-m10-client-codegen-design.md) (section 8 there)
and matches the server pipeline of [M6](2026-10-15-m6-server-pipeline-design.md)
for persisted queries (section 11 there). Requirements: R0.2, R0.3, R0.4,
R0.5, R8.1-R8.5, R10.2, R10.5, R11.1-R11.3
([requirements](../../requirements.md)).

## 1. Scope and delivery

M11 builds the runtime of `packages/typed_graphql_client`: the client that
sends the operations M10 generates and returns typed, sealed responses. One
spec, **six plans and a gated seventh**:

| Plan | Content | Needs |
|---|---|---|
| **M11a** Client core | The client diagnostic codes in the core (`GQL460`-`GQL474`, one core commit); `CancelToken`; `ClientFailure` (sealed); `GraphQLResponse<D>` (sealed: `GraphQLData`, `GraphQLErrors`, `GraphQLTransportFailure`); `LinkContext`, `ContextEntry`, `RequestHeaders`, `HttpResponseInfo`; `LinkRequest`, `LinkResult` (sealed: `LinkPayload`, `LinkFailure`); `Link`, `NextLink`, `Link.from`, `SplitLink`, `ContextLink`; `Backoff`; `GraphQLClient` (`query`, `mutate`, `subscribe`); `MockLink`; `UploadFile`, `UploadFileCodec`, `UploadFiles` (the context entry every terminating link reads); the client import rule; the Client, Links and Uploads guides; `fake_async` and the fix that lets `query` complete under fake time (task 10) | main |
| **M11b** HTTP | The `http` dependency; `HttpTransport`, `TransportRequest`, `TransportResponse`, `PackageHttpTransport`; the response reader; `HttpLink` (GraphQL over HTTP: POST, GET for queries, media types, status codes, size limit, timeout, cancellation); multipart requests for `UploadFiles`; the hostile-response tests; the HTTP guide | M11a |
| **M11c** Request policies | `RetryLink`, `RetryPolicy`, `Idempotent`; `DedupeLink`; `PersistedQueryLink` (automatic persisted queries and trusted documents, matching M6); `AuthLink` (token, single-flight refresh); the Request Policies guide | M11a |
| **M11d** WebSocket | `ClientSocket`; `WebSocketLink` (graphql-transport-ws: lazy connection, `connection_init`/`connection_ack` with a timeout, ping/pong, keep-alive, multiplexed operations, reconnection with backoff, close codes); the internal message codec; the hostile-socket tests; the WebSocket guide | M11a |
| **M11e** Server-sent events | `SseLink` (graphql-sse distinct connections mode over `HttpTransport`); the internal event-stream parser; the hostile-stream tests; the SSE guide | M11a, M11b |
| **M11f** Stage documents and web CI | End-to-end tests against M6's `GraphQLServer` through an in-memory `HttpTransport` (no M7 needed); the client in the Chrome CI job (dart2js, dart2wasm); README, CHANGELOG, `docs/discovery.md`, `llms.txt`, `CLAUDE.md`, the handoff; the example | M11a-M11e |
| **M11z** (gated) End to end over M7 | The same scenarios over M7's real HTTP, graphql-ws and graphql-sse handlers, in memory: written as a follow-up plan, run only after M7 has merged (section 15) | M7, M11f |

**Parallelism.** After M11a is merged, M11b, M11c and M11d can be built at
the same time in three worktrees: they create disjoint folders (`http/`,
`policy/`, `socket/`) and share only these files, where each adds lines and a
merge keeps both: the barrel `lib/typed_graphql_client.dart` (exports),
`dartdoc_options.yaml` (one category each, and one line each in
`categoryOrder`), `CHANGELOG.md` (entries) and, for M11b only,
`pubspec.yaml` and `test/quality/import_rule.dart`. M11e starts when M11b is
merged (it uses `HttpTransport`, `MediaType`, `ResponseReader` and the
header merge of `HttpRequestEncoder`). M11f comes last. The category order
after the merge is: client, link, http, sse, policy, socket, upload,
operations.

Out of scope: the normalized cache, fetch policies and `watchQuery` (M12;
the seam is section 13), `@defer`/`@stream` delivery (M14), graphql-sse
single connection mode and request batching (later, section 17), the legacy
`subscriptions-transport-ws` (never, architecture section 5).

## 2. Package, layering and dependencies

New folders in `packages/typed_graphql_client/lib/src/`, each a dartdoc
category named after the folder, with its guide:

| Folder | Holds | Category, guide | Plan |
|---|---|---|---|
| `client/` | `GraphQLClient`, `GraphQLResponse` family, `ClientFailure` family, `CancelToken`; internal `ResponseDecoder` and `OperationStream` | `client`, `doc/client.md` | M11a |
| `link/` | `Link`, `NextLink`, `LinkRequest`, `LinkResult` family, `LinkContext`, `ContextEntry`, `RequestHeaders`, `HttpResponseInfo`, `SplitLink`, `ContextLink`, `Backoff`, `MockLink`; internal `LinkChain` | `link`, `doc/links.md` | M11a |
| `upload/` | `UploadFile`, `UploadFileCodec`, `UploadFiles` | `upload`, `doc/uploads.md` | M11a |
| `http/` | `HttpLink`, `HttpTransport`, `TransportRequest`, `TransportResponse`, `PackageHttpTransport`; internal `MediaType`, `ResponseReader`, `HttpRequestEncoder` (POST, GET and the header merge), `HttpExchange` (send, read, timeout, abort), `MultipartEncoder` | `http`, `doc/http.md` | M11b |
| `policy/` | `RetryLink`, `RetryPolicy`, `Idempotent`, `DedupeLink`, `PersistedQueryLink`, `AuthLink`; internal `RetryRun`, `SharedRequest`, `PersistedQueryRun`, `PersistedQueryErrors`, `AuthRun`, `TokenRenewal` | `policy`, `doc/policies.md` | M11c |
| `socket/` | `WebSocketLink`, `ClientSocket`; internal `SocketMessage`, `SocketMessageCodec`, `SocketConnection`, `SocketDriver`, `SocketOperations`, `OpenOperation`, `ReconnectPolicy`, `SocketSettings`, `SocketEnd`, `CancellableWait` | `socket`, `doc/websocket.md` | M11d |
| `sse/` | `SseLink`; internal `EventStreamParser`, `EventAssembler`, `ServerSentEvent`, `EventStreamError`, `SseExchange`, `SseRun` | `sse`, `doc/sse.md` | M11e |

`operation/` (M10) is unchanged: generated code keeps compiling against it.

**Imports** (R0.6 spirit, enforced by a new client test
`test/quality/imports_test.dart`, M11a): `lib/` imports no `dart:io`,
`dart:html`, `dart:js_interop`, `dart:isolate`, no web framework; only
`dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:math`,
`dart:typed_data`, `package:meta`, the core barrel, and from M11b
`package:http/http.dart` (the barrel only: `io_client.dart` and
`browser_client.dart` stay out). So the package compiles for the VM, AOT, dart2js
and dart2wasm, and the CI web job runs its suite (M11f).

**Dependencies.**
- `meta` (M11a; already used by the core and the server, `^1.15.0`).
- `http` `^1.5.0` (M11b, the stage that first uses it). Justification:
  R8.4 asks for "HTTP over any `http.Client`", and the architecture lists
  `http` as the client's dependency. `package:http` is pure Dart on every
  platform: its `Client` is implemented by `IOClient`, the browser's
  fetch-based `BrowserClient` (through `package:web`, dart2js and
  dart2wasm), `cupertino_http`, `cronet_http` and dio adapters. 1.5.0 is
  the first version with abortable requests (`AbortableStreamedRequest`),
  which cancellation needs. The link itself does not see `package:http`
  types: it talks to the `HttpTransport` seam (section 6), and
  `PackageHttpTransport` is the one class that adapts an `http.Client`. The
  seam lets tests and M11f/M11z drive the link with an in-memory transport
  and keeps the media-type, status and limit logic independent of the HTTP
  library.
- `web_socket_channel` is **not** a dependency (deviation 2): the WebSocket
  link speaks graphql-ws over `ClientSocket`, a three-member interface the
  app implements over whatever socket it has (`web_socket_channel`,
  `dart:io`'s `WebSocket`, the browser's `WebSocket`); the guide shows the
  adapter. Nothing is gained by forcing one socket library on every app.
- Dev dependencies: `fake_async` `^1.3.1` (M11a task 10) to drive timers
  (backoff, timeouts, keep-alive) deterministically on every platform.
  Task 10 also fixes what fake time exposed: `query` awaited the
  root-zone future that cancelling a subscription returns, which only the
  real event loop completes, so under `fakeAsync` a query never completed.
  `GraphQLClient` now takes the first result with `Stream.firstWhere` and
  `OperationStream` cancels its upstream without awaiting it;
  `typed_graphql_server` (M11f, workspace path) for the end-to-end tests.
  No dependency on `package:gql` or its ecosystem (R0.4).

## 3. Diagnostic codes (M11a, one core commit)

The client reports problems with a server's answer and with the request's
transport as `ClientFailure` values (section 5), each with a stable
`DiagnosticCode`, so "nothing is guessed silently" holds for responses as it
does for documents. The range `GQL460`-`GQL499` is the client's (`GQL400`-
`GQL415` are M6's, `GQL420`-`GQL449` are reserved for M7, `GQL5xx` for
codegen). All fifteen codes are added in M11a's first task so that the later
plans never touch the core:

| Id | Name | Failure | When |
|---|---|---|---|
| GQL460 | `networkFailure` | `NetworkFailure` | the transport could not send the request or read the answer (an exception of the HTTP client or the socket, a connection lost) |
| GQL461 | `httpErrorStatus` | `HttpStatusFailure` | an HTTP status outside 2xx whose body is not `application/graphql-response+json` |
| GQL462 | `unsupportedResponseType` | `ResponseFormatFailure` | a `Content-Type` the link cannot read (missing, another media type, a charset other than UTF-8) |
| GQL463 | `responseTooLarge` | `ResponseFormatFailure` | a body or an event longer than the link's byte limit |
| GQL464 | `malformedResponse` | `ResponseFormatFailure` | a body that is not UTF-8, not JSON, nested too deep, not a GraphQL response, or `"data": null` without errors |
| GQL465 | `dataShapeMismatch` | `DataFormatFailure` | `data` that does not have the shape of the operation's generated classes |
| GQL466 | `requestCancelled` | `RequestCancelled` | the caller's `CancelToken` was cancelled before the answer |
| GQL467 | `requestTimedOut` | `RequestTimedOut` | the link's timeout passed before the answer |
| GQL468 | `operationNotSupportedByLink` | `UnsupportedOperation` | a terminating link that cannot carry the operation: a subscription over `HttpLink`, files over a socket |
| GQL469 | `linkEndedWithoutResult` | `UnsupportedOperation` | the link chain closed a query's or mutation's stream without a result |
| GQL470 | `malformedSocketMessage` | `SocketFailure` | a graphql-ws message the protocol does not allow (the link closes the socket with `4400`) |
| GQL471 | `socketClosed` | `SocketFailure` | the socket closed with a fatal code, or the reconnection attempts ran out |
| GQL472 | `connectionAckTimeout` | `SocketFailure` | no `connection_ack` within `connectionAckTimeout` (the link closes with `4504` and does not reconnect) |
| GQL473 | `malformedEventStream` | `EventStreamFailure` | an SSE stream with an unknown event type, or one that ends without `complete` |
| GQL474 | `authenticationFailed` | `AuthenticationFailure` | `AuthLink`'s token or refresh callback threw |

Names were chosen so they cannot be mistaken for server-side transport
problems; if M7 picks one of the same enum names, the later merge renames
its own (names are public API only once released; ids never change).

## 4. Cancellation: `CancelToken` (M11a)

```text
final class CancelToken {
  CancelToken();
  bool get isCancelled;
  Object? get reason;
  Future<void> get whenCancelled;   // never completes with an error
  void cancel([Object? reason]);    // only the first call has an effect
}
```

- It is the caller's: `GraphQLClient` listens to it and never cancels it.
  Cancelling it completes a pending `query`/`mutate` with
  `GraphQLTransportFailure(RequestCancelled(reason))` at once and ends a
  `subscribe` stream with that failure as its last event; in both cases the
  client cancels its subscription to the link chain's stream.
- **Inside the chain, cancellation is stream cancellation.** A link never
  sees the token: when the client (or `DedupeLink`, or `RetryLink`) cancels
  its `StreamSubscription`, each link cancels what it holds: `HttpLink`
  aborts the HTTP request (`TransportRequest.abortTrigger`), `WebSocketLink`
  sends `complete` for the operation, `SseLink` aborts the
  connection, `RetryLink` cancels its backoff timer. A user link written
  with stream transformers (`asyncExpand`, `map`) propagates the cancel for
  free; the Links guide says so.
- A token already cancelled when the call starts completes at once without
  calling the link.
- Named `CancelToken`, not `CancelSignal`: the server's `CancelSignal`
  (M5d) is a different class in another package, and a test or app that
  imports both packages would see an ambiguous name (open question 3).

## 5. Responses and failures (M11a; R8.2)

```text
sealed class GraphQLResponse<D extends Object>
final class GraphQLData<D>(D data, {List<GraphQLError> errors, JsonObject? extensions, LinkContext context})
final class GraphQLErrors<D>(List<GraphQLError> errors, {JsonObject? extensions, LinkContext context})
final class GraphQLTransportFailure<D>(ClientFailure failure)
```

How a link result becomes a response (`ResponseDecoder`, internal):

| Link result | Response |
|---|---|
| `LinkPayload(ExecutionResult(data: {...}))`, `decodeData` succeeds | `GraphQLData(data, errors: [...])`, partial data when `errors` is not empty |
| the same, `decodeData` fails | `GraphQLTransportFailure(DataFormatFailure(decodeFailure, errors))` (`GQL465`); the server's errors are kept in the failure |
| `LinkPayload(ExecutionResult(data: null, errors: [e, ...]))` | `GraphQLErrors([e, ...])`: an error nulled the root, nothing to decode |
| `LinkPayload(ExecutionResult(data: null))` without errors | `GraphQLTransportFailure(ResponseFormatFailure(GQL464, ...))`: the specification never allows it |
| `LinkPayload(RequestErrorResult(errors))` | `GraphQLErrors(errors)` |
| `LinkFailure(failure)` | `GraphQLTransportFailure(failure)` |

`context` carries what the terminating link learned about the answer, such
as `HttpResponseInfo` (status, headers), so an app can read a response
header without a custom link.

`ClientFailure` is a sealed family in one file (sealed subclasses must share
the library); every variant has `code` (`DiagnosticCode`) and `message`:

```text
sealed class ClientFailure { DiagnosticCode get code; String get message; }  // toString: '<id>: <message>'
final class NetworkFailure(Exception cause)                         // GQL460
final class HttpStatusFailure(int statusCode, Map<String, String> headers)  // GQL461
final class ResponseFormatFailure(DiagnosticCode code, String message, {List<PathSegment> path}) // GQL462-464
final class DataFormatFailure(DecodeFailure decodeFailure, {List<GraphQLError> errors}) // GQL465
final class RequestCancelled([Object? reason])                     // GQL466
final class RequestTimedOut(Duration timeout)                      // GQL467
final class UnsupportedOperation(DiagnosticCode code, String message)      // GQL468, GQL469
final class SocketFailure(DiagnosticCode code, String message, {int? closeCode, String? closeReason}) // GQL470-472
final class EventStreamFailure(String message)                     // GQL473
final class AuthenticationFailure(Exception cause)                 // GQL474
```

Errors of a response are the core's `GraphQLError`: its `decode` already
refuses a missing or mistyped `message`, `locations` or `path` (any odd
`path` segment, a negative index, a float, an object, is a `DecodeFailure`
and so `GQL464`).

## 6. Links (M11a; R8.3)

```text
abstract base class Link {
  const Link();
  Stream<LinkResult> request(LinkRequest request, NextLink forward);
  static Link from(List<Link> links);       // a chain; empty is an ArgumentError
}
typedef NextLink = Stream<LinkResult> Function(LinkRequest request);
```

- **Shape.** A link returns a `Stream<LinkResult>`: one event for a query or
  mutation, many for a subscription (and, in M14, for `@defer`). A middle
  link calls `forward`; a terminating link (`HttpLink`, `WebSocketLink`,
  `SseLink`, `MockLink`) ignores it. `Link.from([a, b, c])` gives `a` a
  `forward` that calls `b`, and so on; the last link's `forward` is an
  error stream with a `StateError` ("the last link forwarded the request:
  end the chain with a terminating link"), a programmer error.
- **Errors are values.** A link reports every failure as a `LinkFailure`
  event, never with `addError`. If a user link's stream does emit an error,
  the client turns an `Exception` into `NetworkFailure(exception)` and lets
  an `Error` through (a programmer error, R0.3).
- **`LinkResult`** (sealed): `LinkPayload(ResponsePayload payload, {LinkContext
  context})` and `LinkFailure(ClientFailure failure)`.
- **`LinkRequest`** (immutable): `document` (`OperationDocument`, M10),
  `variables` (`JsonObject`), `extensions` (`JsonObject?`), `context`
  (`LinkContext`) and `sendsDocumentText` (`bool`, default true; the
  persisted query link turns it off for a hash-only attempt).
  `LinkRequest.of(operation, context)` reads a generated operation;
  `type` is `document.type`; `body` is the core's `GraphQLRequest` as it is
  sent (no `query` when `sendsDocumentText` is false, no `variables` when
  there are none). Copies: `withContext`, `withExtensions`,
  `withDocumentText`.
- **`LinkContext`** (immutable): `LinkContext(Iterable<ContextEntry>)`
  copies the entries, `const LinkContext.empty()` is the default of every
  `context` parameter; `entry<T>()` is the last entry that is a `T`, or
  null; `withEntry(e)` replaces the entries of `e`'s exact runtime type.
  Built-in entries: `RequestHeaders(Map<String, String>)` (extra HTTP
  headers, names stored in lower case; `withHeader(name, value)` gives a
  copy; every entry is applied in order, so a later one wins),
  `HttpResponseInfo(statusCode, headers:)` (written by the HTTP and SSE
  links on a payload's context), `UploadFiles` (M11a), `Idempotent`
  (M11c). A user link defines its own entries by extending `ContextEntry`.
- **`SplitLink({required bool Function(LinkRequest) test, required Link
  whenTrue, required Link whenFalse})`** routes a request, forwarding with
  the chain's `forward` (so a branch can be a middle link).
- **`ContextLink(FutureOr<LinkContext> Function(LinkRequest) update)`**
  rewrites the context before forwarding (dynamic headers); an `Exception`
  thrown by `update` is a `LinkFailure(NetworkFailure(exception))` and the
  request is not forwarded (`AuthLink` reports its own callbacks'
  exceptions as `AuthenticationFailure` instead, section 10).
- **`Backoff({initialDelay = 300 ms, maxDelay = 30 s, double multiplier =
  2})`** (`const`): `ceilingFor(int retry)` is `min(maxDelay, initialDelay
  * multiplier^retry)` (computed with a loop that stops at `maxDelay`, so a
  large `retry` cannot overflow); `delayFor(int retry, Random random)` is
  "full jitter", a uniform draw in `[0, ceilingFor(retry)]`.
  `RetryLink` and `WebSocketLink` share it; tests pass a seeded `Random`
  and drive time with `fake_async`.

Recommended order of a chain (the Links guide): `DedupeLink`, `RetryLink`,
`AuthLink`, `PersistedQueryLink`, then a `SplitLink` whose branches are the
terminating links (`WebSocketLink` or `SseLink` for subscriptions,
`HttpLink` otherwise).

## 7. `GraphQLClient` (M11a; R8.1)

```text
final class GraphQLClient {
  GraphQLClient({required Link link});
  Future<GraphQLResponse<D>> query<D extends Object>(GraphQLQuery<D> query, {LinkContext context, CancelToken? cancelToken});
  Future<GraphQLResponse<D>> mutate<D extends Object>(GraphQLMutation<D> mutation, {LinkContext context, CancelToken? cancelToken});
  Stream<GraphQLResponse<D>> subscribe<D extends Object>(GraphQLSubscription<D> subscription, {LinkContext context, CancelToken? cancelToken});
}
```

- `query` and `mutate` listen to the chain, decode the first result,
  cancel their subscription (which ends the request in every link) and
  complete. A stream that ends with no result is
  `UnsupportedOperation(GQL469)`. Nothing throws for anything a server or
  a transport does (R0.3); a programmer error (`StateError` of an open
  chain, `ArgumentError` of a misplaced upload) completes the future with
  that error.
- `subscribe` returns a single-subscription stream: the chain is called on
  `listen`, each result is decoded, cancelling the returned subscription
  cancels the chain's. A `GraphQLTransportFailure` is delivered as an event;
  whether the stream then ends is the terminating link's choice (all
  built-in links end it after a failure).
- `watchQuery` is M12 (deviation 1, open question 1): without a cache it
  would be `query` as a one-event stream.

## 8. `MockLink` (M11a; R8.5)

```text
final class MockLink extends Link {
  MockLink();
  List<LinkRequest> get requests;                 // every request, in order
  int get pendingAnswerCount;                     // queued answers not used yet
  void add(LinkResult result, {String? operationName});
  void addData(JsonObject data, {List<GraphQLError> errors, String? operationName});
  void addErrors(List<GraphQLError> errors, {String? operationName});   // a RequestErrorResult
  void addFailure(ClientFailure failure, {String? operationName});
  void addStream(Stream<LinkResult> results, {String? operationName});
}
```

A queued answer is used once, first in, first out, by the first request
whose operation name matches (`null` matches any). A request with no queued
answer gets a stream with a `StateError` naming the operation: a test bug,
not a response. `addStream` serves a subscription (or any multi-event
answer) and is cancelled when the client cancels.

## 9. HTTP (M11b; R8.4)

```text
abstract interface class HttpTransport {
  Future<TransportResponse> send(TransportRequest request);
}
final class TransportRequest({required String method, required Uri uri, Map<String, String> headers /* lower-cased */, Stream<List<int>>? body, int? contentLength, Future<void>? abortTrigger})
final class TransportResponse({required int statusCode, required Stream<List<int>> body, Map<String, String> headers /* lower-cased */})
final class PackageHttpTransport(http.Client client) implements HttpTransport
final class HttpLink extends Link {
  HttpLink({required Uri uri, required HttpTransport transport,
      Map<String, String> headers = const {}, bool usesGetForQueries = false,
      Duration? timeout, int maxResponseBytes = defaultMaxResponseBytes /* 16 MiB */,
      int maxResponseDepth = JsonReader.defaultMaxDepth, Random? random});
  static const int defaultMaxResponseBytes;
}
```

A negative `maxResponseBytes`, or a `maxResponseDepth` outside `1` to
`JsonReader.maxSupportedDepth`, is a `RangeError`. `TransportResponse`
puts its required parameters first (the `always_put_required_named_parameters_first`
lint).

- **Requests** (GraphQL over HTTP, `reference/graphql-over-http`): `POST`
  with `content-type: application/json` and the JSON of `LinkRequest.body`;
  `accept: application/graphql-response+json, application/json;q=0.9`
  always. With `usesGetForQueries`, a query (never a mutation) goes as
  `GET` with `query`, `operationName`, `variables` and `extensions` (JSON)
  as query parameters, appended to `uri`'s own. A `GET` and a multipart
  `POST` add `graphql-require-preflight: true`, the header M6's CSRF
  prevention (section 10 there) requires for requests a browser could
  forge. Headers, lowest priority first: the protocol's, `headers` of the
  link, then every `RequestHeaders` entry of the context.
- A subscription is `UnsupportedOperation(GQL468)` without a request
  (incremental delivery over HTTP is M14).
- **Responses**, by `content-type` (media type before `;`, trimmed,
  lower-cased; a `charset` other than `utf-8` is `GQL462`):
  `application/graphql-response+json` is read whatever the status (the
  spec's rule); `application/json` is read only with a 2xx status, any
  other status is `HttpStatusFailure` (an intermediary may have answered);
  any other or missing type: a non-2xx status is `HttpStatusFailure`, a 2xx
  is `GQL462`. Reading (`ResponseReader`): bytes are counted as they arrive
  and the request is aborted past `maxResponseBytes` (`GQL463`); UTF-8 is
  strict (`GQL464`); `JsonReader(maxDepth: maxResponseDepth).parse`
  (`GQL464` with the path); `ResponsePayload.decode` (`GQL464` with the
  path). The payload's context gets `HttpResponseInfo(status, headers)`.
  A leading UTF-8 byte order mark is dropped by Dart's decoder and the
  body is read (RFC 8259 section 8.1 lets a parser ignore it).
  `ResponseReader.resultOf(text, context)` is the text-to-result step on
  its own, which `SseLink` reuses for each `next` event.
- **Failures:** an `Exception` of the transport (or of the body stream) is
  `NetworkFailure`; `timeout` (per attempt, from sending to the end of the
  body) aborts and is `RequestTimedOut`; cancelling the stream aborts the
  request (`abortTrigger`) and delivers nothing.
- **`PackageHttpTransport`** sends an `http.AbortableStreamedRequest` with
  `abortTrigger`, so cancellation closes the connection on every `http`
  client that supports aborting (all of `http`'s own); the response's
  headers are already lower-case in `package:http`.

**Uploads** (the jaydenseric multipart request spec,
`reference/graphql-multipart-request-spec`). The types are M11a's
(`upload/`), because every terminating link reads `UploadFiles`; M11b adds
the multipart body:

```text
final class UploadFile { UploadFile.fromBytes(List<int> bytes, {required String filename, String contentType});
                         UploadFile.fromStream(Stream<List<int>> Function() open, {required int length, required String filename, String contentType});
                         String get marker; }
final class const UploadFileCodec() implements ScalarCodec<UploadFile>   // for typed_graphql.yaml's `scalars:`
final class UploadFiles(List<UploadFile> files) extends ContextEntry
```

- The `Upload` scalar is mapped in `typed_graphql.yaml` to
  `package:typed_graphql_client/typed_graphql_client.dart#UploadFile` with
  the codec `...#UploadFileCodec`. The generated variables write a file as
  its `marker`, a string unique to the `UploadFile` object
  (`typed_graphql.upload/<n>`, `n` from a counter of the class); the codec
  refuses to read one from JSON (a file never comes back in a response).
- The caller lists the files of a request in the context:
  `client.mutate(op, context: LinkContext([UploadFiles([avatar])]))`
  (deviation 4: the generated variables are JSON, so the link cannot reach
  the objects otherwise). `HttpLink` walks the variables, replaces each
  marker by `null` in `operations`, writes `map` (`{"0":
  ["variables.file"]}`, a file used twice is listed with both paths) and
  streams `multipart/form-data` with a boundary drawn from `random` (32
  letters and digits; injected for tests). The parts are `operations` and
  `map` (each with `Content-Type: application/json`), then one part per
  file named by its index, `filename` escaped as an HTML form does (`"`,
  CR and LF as `%22`, `%0D`, `%0A`), with the file's content type; the
  `content-length` is computed from the files' lengths. The variables are
  walked breadth first with a queue, never recursively. A marker with no listed file, or
  a listed file no variable uses, is an `ArgumentError` (a programmer
  error); `UploadFiles` on a query with `usesGetForQueries` sends `POST`.
- `WebSocketLink` and `SseLink` answer a request with `UploadFiles`
  `UnsupportedOperation(GQL468)`.
- Every `UploadFile` gives a new stream per `open()` (`fromBytes` replays
  its copy, `fromStream` calls the caller's function), so `RetryLink` can
  resend any file.

## 10. Request policies (M11c; R8.4)

**`RetryLink({RetryPolicy policy = const RetryPolicy(), Random? random})`**
- `RetryPolicy({int maxAttempts = 3, Backoff backoff = const Backoff(),
  bool Function(ClientFailure failure)? retryIf})`; the default `retryIf`
  retries `NetworkFailure`, `RequestTimedOut`, and `HttpStatusFailure`
  with 408, 429, 500, 502, 503, 504. GraphQL errors are never retried.
- Only queries and mutations whose context has `Idempotent()` are retried;
  a mutation without it and every subscription pass through unchanged
  (the WebSocket link reconnects on its own). A request with
  `UploadFiles` is retried like any other: each attempt reopens every file.
- The attempt is forwarded again after `backoff.delayFor(attempt, random)`;
  cancelling during the delay cancels the timer; the last failure is
  delivered when the attempts run out. `maxAttempts` below 1 is an
  `ArgumentError`.
- **Stream errors.** The policy links pass an error event of the upstream
  stream through untouched, except `RetryLink`, which turns an `Exception`
  into `LinkFailure(NetworkFailure(exception))` so that its policy can judge
  it. Anything a caller's callback throws (`retryIf`, `isUnauthorized`, an
  `Error` from `token` or `refresh`) is delivered as an error event on the
  caller's stream, which then ends and cancels the upstream; it never
  escapes as an uncaught error and never leaves a stream open.

**`DedupeLink()`**: identical queries in flight share one forwarded
request. The key is the request's `body` (JSON values compare by value,
keys in any order) and its `RequestHeaders`; mutations, subscriptions and
requests with `UploadFiles` pass through. Each caller gets the shared
result; a caller that cancels leaves the others; the forwarded request is
cancelled when the last caller cancels; the entry is removed at the first
result or the end (also when `forward` throws or its stream ends inside
`listen`), so a later identical query is sent again (no caching: M12).
Internally one `SharedRequest` per key fans the forwarded stream out.

**`PersistedQueryLink({bool isAutomatic = true})`** (M6 section 11):
- Sends `extensions.persistedQuery = {"version": 1, "sha256Hash":
  document.sha256}` (M10's hash of the minified text, the same the server
  computes) and no `query` text.
- Automatic (APQ): when the answer has an error whose `message` is
  `PersistedQueryNotFound` or whose `extensions.code` is `GQL410` or
  `PERSISTED_QUERY_NOT_FOUND`, it sends again with the text and the hash.
  When it is `PersistedQueryNotSupported` / `GQL412` /
  `PERSISTED_QUERY_NOT_SUPPORTED`, it sends again with the text and no
  hash, and sends text only from then on (the link remembers it). The
  server stores the text only after it validated it (M6), so a second
  request with the hash alone succeeds. The resend happens once: a second
  "not found" answer is delivered as it is.
- Trusted documents (`isAutomatic: false`): the hash alone, always; the
  server's `GQL415` comes back as `GraphQLErrors`.
- Applies to queries and mutations; a subscription and a request with
  `UploadFiles` pass through. `HttpLink(usesGetForQueries: true)` sends a
  hash-only query as `GET`, which CDNs can cache.
- The GraphQL over HTTP `documentId` is not sent (M6 open question 12;
  open question 6 here).

**`AuthLink({required FutureOr<String?> Function() token, Future<String?>
Function()? refresh, String headerName = 'authorization', String scheme =
'Bearer', bool Function(LinkResult result)? isUnauthorized})`**
- Adds `<headerName>: <scheme> <token>` as a `RequestHeaders` entry (no
  header when `token` gives null).
- After the answer: the default `isUnauthorized` is an
  `HttpStatusFailure(401)` or a payload whose `HttpResponseInfo` has
  status 401. Then `refresh` runs **once for every request waiting on it**
  (single flight in the internal `TokenRenewal`, in this order: a refresh
  in flight is joined; a refresh that finished while this request read the
  current token is reused (a refresh counter tells); a current token that
  is non-null and differs from the refused one is used (someone else
  renewed it); otherwise a new refresh starts, which every request waiting
  at the same time shares). The request is sent again once with the new
  token (a 401 is a request-level refusal, so a mutation is safe to
  resend). If `refresh` is null, or a refresh gives null, the 401 answer is
  delivered as it is.
- An `Exception` from `token` or `refresh` is
  `AuthenticationFailure(GQL474)`; anything else they throw is a stream
  error (above).

## 11. WebSocket: graphql-transport-ws (M11d; R8.4)

```text
abstract interface class ClientSocket {
  Stream<String> get messages;                  // done when the socket closes
  void send(String text);
  Future<void> close([int? code, String? reason]);
  int? get closeCode;                           // read after `messages` is done
  String? get closeReason;
}
final class WebSocketLink extends Link {
  WebSocketLink({required Future<ClientSocket> Function() connect,
      FutureOr<JsonObject?> Function()? connectionParams,
      Duration connectionAckTimeout = 10 s, Duration? keepAlive,
      int retryAttempts = 5,
      Backoff backoff = const Backoff(initialDelay: 1 s), Random? random});
  Future<void> dispose();
}
```

`ClientSocket.close` has the optional parameters and the `Future` of
`WebSocketSink.close`, so an adapter over `web_socket_channel` is a
forwarding call (the doc comment shows it, and the guide shows the browser
one). A `connectionAckTimeout` or `keepAlive` that is not longer than zero,
or a negative `retryAttempts`, is an `ArgumentError`. The names follow the
reference client (`connectionParams`, `connectionAckWaitTimeout` shortened,
`retryAttempts`).

The protocol is `reference/graphql-ws/PROTOCOL.md`; the behaviour mirrors
the reference client (`reference/graphql-ws/src/client.ts`):

- **Lazy, then open.** The first operation connects (`connect()` must open
  the socket with the sub-protocol `graphql-transport-ws`; the app's
  adapter does that) and sends `connection_init` with
  `connectionParams()` (called at each connection, so a refreshed token is
  sent after a reconnection); operations wait for `connection_ack`. One
  socket carries every operation. The socket stays open after the last
  operation ends, until `dispose()` (ruling: the reference client's
  `lazyCloseTimeout` is left out; an app that wants the socket closed
  disposes the link). A socket that arrives after every operation has
  left, or while the link is being disposed, is closed at once.
- **Ack timeout.** No ack within `connectionAckTimeout` closes with `4504`
  and fails the waiting operations with `SocketFailure(GQL472)`, without
  reconnecting. A `4504` close sent *by a server* is retried like any
  other code.
- **Operations.** Each gets an id unique for the link's life (`"1"`, `"2"`,
  ...); `subscribe` carries `LinkRequest.body`. `next` is a `LinkPayload`
  (decoded with `ResponsePayload.decode`), `error` is a
  `LinkPayload(RequestErrorResult(errors))` and ends the stream, `complete`
  ends it. Cancelling a stream sends `complete` for its id when the
  `subscribe` was sent. A message for an unknown or finished id is ignored
  (the protocol allows it), in constant memory.
- **Ping/pong.** A server `ping` is answered with `pong` at once. With `keepAlive`, the link sends `ping` every interval
  after the ack; if no `pong` arrived since the previous ping, the socket
  is considered dead, closed with `4499` and reconnected.
- **Invalid server messages** (not JSON, not an object, unknown `type`, a
  missing or non-string `id`, a payload of the wrong shape, a second
  `connection_ack`, `next` before the ack) close the socket with `4400`,
  the protocol's code (deviation 3), and fail every operation with
  `SocketFailure(GQL470)`; there is no reconnection after it. A message is
  parsed with `JsonReader` (depth limit).
- **Reconnection.** A socket that closes, errors or fails to open while
  operations are open is reopened after `backoff.delayFor(n - 1, random)`,
  up to `retryAttempts` failed attempts in a row; an acknowledged
  connection gives the count back. A socket whose stream errors is closed
  with `4499` before the next one is opened. Close codes that are never
  retried (the reference client's list, internal `ReconnectPolicy`):
  `4500`, `4005`, `4400`, `4004`, `4401`, `4406`, `4409`, `4429`, and
  `1000`-`1999` except `1000`, `1001`, `1005`, `1006`, `1012`, `1013`,
  `1014`. After a reconnection, open queries and subscriptions are
  subscribed again **under the same id** (ruling: the reference client
  keeps its ids, and the protocol only forbids reusing an id that is still
  open on the same socket); **a mutation already sent is never resent**: it
  fails with `NetworkFailure`. When the attempts run out or the code is
  fatal, every operation gets `SocketFailure(GQL471, closeCode,
  closeReason)`, or the `NetworkFailure` of the last `connect()` that
  threw. `connectionParams` throwing closes the socket with `4005`, as the
  reference client does, which is fatal (`GQL471`). The backoff wait is
  cancellable: `dispose()` during it leaves no timer.
- **`dispose()`** ends every open operation with `RequestCancelled`,
  closes the socket with `1000`, and answers later requests with
  `UnsupportedOperation(GQL468)`.
- A request with `UploadFiles` is `UnsupportedOperation(GQL468)`.
- **Inside.** `WebSocketLink` is a thin face: `SocketOperations` holds the
  open operations (`OpenOperation`: the request, its controller, whether
  its `subscribe` was sent), `SocketDriver` runs the connect-and-retry
  loop over `SocketConnection` (one socket: handshake, ack timeout,
  keep-alive, dispatch), `SocketEnd` says how a connection ended,
  `ReconnectPolicy` and `SocketSettings` hold the configuration,
  `CancellableWait` is the backoff timer, and `SocketMessage` with
  `SocketMessageCodec` is the message model (deviation 8).

## 12. Server-sent events: graphql-sse (M11e; R8.4)

```text
final class SseLink extends Link {
  SseLink({required Uri uri, required HttpTransport transport,
      Map<String, String> headers = const {},
      int maxEventBytes = defaultMaxEventBytes,      // 16 MiB
      int maxResponseDepth = JsonReader.defaultMaxDepth});
  static const int defaultMaxEventBytes;
}
```

- Distinct connections mode (`reference/graphql-sse/PROTOCOL.md`): every
  operation is a `POST` with the JSON body and `accept: text/event-stream`;
  the headers merge as `HttpLink`'s do (`HttpRequestEncoder.headersFor`).
  Cancelling aborts the connection (the protocol's way to stop a
  subscription); pausing the result stream pauses the body. A negative
  `maxEventBytes` or a `maxResponseDepth` out of range is a `RangeError`, as
  in `HttpLink`. A request with `UploadFiles` is
  `UnsupportedOperation(GQL468)` and nothing is sent.
- A 2xx `text/event-stream` answer is parsed by the internal
  `EventStreamParser` over `EventAssembler` (the WHATWG rules: lines end
  with CRLF, LF or CR, also across chunks; a leading byte-order mark is
  dropped; `:` lines are comments, `data` lines join with `\n`, a blank
  line dispatches an event that has a type or data, an empty `event:` is
  `message`, `id` and `retry` are ignored). It is a stream transformer, not
  an `async*` generator, so cancelling stops a stalled body at once.
  `next` carries a GraphQL response (`LinkPayload`, with
  `HttpResponseInfo`), `complete` ends the stream. An event of another
  type, or the end of the body before `complete` (an unfinished event is
  dropped, as a browser does), is `EventStreamFailure(GQL473)`. An event
  whose `data` and `event` lines pass `maxEventBytes` (UTF-8 bytes as they
  arrive; comments do not count, so a keep-alive stream runs in constant
  memory) is `ResponseFormatFailure(GQL463)`; bytes that are not UTF-8 are
  `GQL464`; a 2xx event stream in another charset is `GQL462`. The parser's
  own errors are the internal sealed `EventStreamError`
  (`EventStreamTooLarge`, `EventStreamNotUtf8`).
- Any other answer is read as `HttpLink` reads it (`ResponseReader`), so a
  server that refuses the request with a JSON error body gives
  `GraphQLErrors`.
- **Inside.** `SseLink` is a thin face over `SseExchange` (configuration)
  and `SseRun` (one request: send, choose stream or single answer, relay
  events, own the result controller and the abort).
- Single connection mode is not built (open question 7).

## 13. The seam for M12 (normalized cache)

- `LinkContext` is the per-request carrier: M12 adds a `FetchPolicy` entry
  (and a `fetchPolicy` named parameter on `query`), both additions.
- `GraphQLClient({required Link link})` gains an optional `cache`
  parameter in M12; the client then puts its cache layer in front of `link`
  (a `Link` the client builds, so user links are untouched). `query` and
  `subscribe` already decode through one place (`ResponseDecoder`), where
  M12 writes the normalized records.
- `watchQuery` arrives with the cache (deviation 1).
- Nothing in M11 is shaped for the cache beyond this: no unused parameter,
  no placeholder entry (CLAUDE.md, "Do not abstract for a future need").

## 14. Hostile input (R0.3)

Every hostile answer becomes a typed failure, never an exception, and is
bounded in memory. Tests (one file per transport):

- **HTTP** (`test/http/hostile_response_test.dart`): a body past the limit
  (counted while streaming, the request aborted), an endless body, invalid
  JSON, `{` repeated 100 000 times (depth), invalid UTF-8, a UTF-8 BOM, an
  empty body, a JSON array or number, `{"data": null}`, `{"errors": []}`,
  `errors` with a `path` holding objects, floats or negative indexes, a
  `message` that is not a string, `data` of the wrong shape, a missing,
  unknown or non-UTF-8 content type, a 500 with JSON, a 401 with
  `graphql-response+json`, a body stream that throws.
- **WebSocket** (`test/socket/hostile_socket_test.dart`): non-JSON, a JSON
  array, an unknown type, `next` without an id, a numeric id, `next` before
  the ack, a second ack, a duplicate `complete`, 10 000 `next` for unknown
  ids, an `error` whose payload is not a list, a socket that closes
  mid-handshake, a server that never acks, a server ping flood.
- **SSE** (`test/sse/hostile_stream_test.dart`): an unknown event, an event
  without a type, a `next` with invalid JSON, one that is not a GraphQL
  response, one nested past the depth limit, a stream that ends without
  `complete`, an empty stream, an event split across every byte boundary,
  `\r` line ends, 10 000 comment lines, endless comments in constant space,
  a never-ending line (the body cancelled), endless `data` lines, a 2xx
  `application/json` answer (one result), 2xx `text/html` or no content
  type, an event stream with status 500, invalid UTF-8, a character cut by
  the end of the body, a body stream that throws after some events.

## 15. End-to-end tests

- **M11f (now):** the client against M6's `GraphQLServer` with no network:
  a test-only `HttpTransport` (`test/e2e/support/pipeline_transport.dart`)
  decodes the `TransportRequest` (the JSON body of a `POST`, the parameters
  of a `GET`), calls `GraphQLServer.handle`, and writes a `SingleResponse`
  as `application/graphql-response+json` (`executed` 200, `requestError`
  400, `methodNotAllowed` 405, `internalError` 500: a test double, since
  M7 owns the real mapping, which M11z checks) and a `StreamResponse` as a
  `text/event-stream` of `next` events and `complete`. Scenarios: a query
  with variables; partial data; a validation error (`GQL205`); a `GET`
  query (CSRF passes with the preflight header) beside a `POST` mutation
  on the same link; automatic persisted queries (miss, then text, then the
  hash alone hits M6's store); a server without a store (the link falls
  back to text for good); trusted documents from a manifest in M10's
  format (an untrusted query is `GQL415`); `AuthLink` refreshing once,
  also for two concurrent queries (ruling: the stale token is refused by
  the transport with a 401, as a gateway in front of the server would,
  because M6's context factory can only turn a refusal into a request
  error); `DedupeLink` sending two concurrent identical queries once;
  `SseLink` receiving a server subscription to its end, a cancel that
  reaches the server's source, and a query. `typed_graphql_server`
  becomes a dev dependency of the client (architecture section 1 allows
  it).
- **M11z (gated on M7):** the same scenarios through M7's own HTTP handler
  (status codes, media types, body limits from M7), plus graphql-ws and
  graphql-sse through M7's handlers over an in-memory `ClientSocket` and
  `HttpTransport` (`HandlerTransport` over `GraphQLHttpHandler`;
  `SocketPair`, whose ends are a `ClientSocket` and a `GraphQLSocket`).
  Its plan (`2026-10-16-m11z-end-to-end-over-m7.md`) is written now
  against the M7 spec's names and is to be run only after M7 merges; its
  code could not be compiled, so its first task re-checks every M7 name it
  uses and adjusts them (section 18). Not covered there: uploads end to
  end (the test schema has no `Upload` scalar; add with M7b's API).

## 16. Deviations from the architecture spec and the requirements

1. **`watchQuery` moves to M12.** R8.1 lists it for M11 and the roadmap
   lists it for M12; without a cache it would only wrap `query`, so it
   ships with the cache (open question 1).
2. **No `web_socket_channel` dependency.** The architecture names it; the
   link takes a `ClientSocket` the app implements (section 2).
3. **Close code `4400` for a bad server message**, the code the protocol
   text gives for an invalid message in either direction; the reference
   client closes with `4004` ("Bad response") instead. Both are in the
   never-retried list, so the only visible difference is the code a server
   logs.
4. **Files travel in the context.** `UploadFiles` lists the files of a
   request; the generated variables carry markers (section 9). Apollo iOS
   takes files beside the operation the same way.
5. **Uploads are a feature of `HttpLink`**, not a separate link: only the
   terminating HTTP link can write a multipart body.
6. **`HttpLink` talks to `HttpTransport`**, with `PackageHttpTransport`
   over any `http.Client` (R8.4 holds); the architecture says "over any
   `http.Client`" directly.
7. **Names that avoid clashes with the server:** `CancelToken` (server:
   `CancelSignal`), `UploadFile` (M7 will have its own upload type),
   `TransportRequest`/`TransportResponse` (the architecture gives the
   server `HttpRequestData`/`HttpResponseData`), `ClientSocket`.
8. **graphql-ws message types live in the client** (internal, `socket/`),
   not in the core's `protocol/` as architecture section 5 says ("all
   protocol message types live in the core"): M7 is designed at the same
   time, and two plans writing the same core files would collide. Moving
   one shared model into the core after both merge is open question 4.
9. **graphql-sse single connection mode is not built** (section 12).
10. **No insertion points.** The research (04 §13) suggests named
    insertion points; M11 has a plain ordered chain, and M12's cache layer
    is placed by the client itself (section 13).
11. **Time in tests is faked with `fake_async`**, not an injected clock;
    randomness is injected (`Random`).
12. **All fifteen client codes arrive in one core commit** (M11a Task 1),
    not each "in the commit that first reports it" as CLAUDE.md's design
    rules ask: the later plans run in parallel and must not touch the
    core's catalog, where their changes would collide. Every code is
    reported by the end of M11e, so none stays unused.
13. **No `lazyCloseTimeout`.** The reference client closes an idle socket
    after a delay; `WebSocketLink` keeps it open until `dispose()`, so a
    subscription started right after another ended reuses the connection
    and no timer outlives the operations (section 11).

## 17. Open questions for the owner

Each has the recommendation the plans follow until the owner decides.

1. **`watchQuery` in M11 or M12?** Recommended: M12, with the cache
   (deviation 1). Alternative: a cache-less `watchQuery` now that refetches
   on demand.
2. **Client diagnostic codes.** Recommended: `GQL460`-`GQL474` in the core
   catalog, one per failure kind (section 3). Alternative: a client-only
   enum outside `DiagnosticCode`.
3. **One cancel class for both sides.** Recommended: keep `CancelToken`
   (client) and `CancelSignal` (server) apart now; after M7, consider
   moving one `CancelSignal` into the core (its internal listener API would
   become public). Alternative: move it now (touches the server while M7
   is being built).
4. **graphql-ws and graphql-sse message model in the core.** Recommended:
   after M7 and M11 merge, compare the two private models and move one
   into `protocol/` if they agree (architecture section 5). Alternative:
   keep them private to each side.
5. **Upload API.** Recommended: `UploadFiles` in the context (deviation 4).
   Alternative: teach the generator (M10) to emit `uploads` on operations
   whose variables reach the `Upload` scalar, so no list is needed; a
   codegen change, not planned.
6. **`documentId`.** Recommended: not sent (matches M6); revisit with the
   GraphQL over HTTP persisted-documents appendix.
7. **graphql-sse single connection mode.** Recommended: later; HTTP/2 makes
   distinct connections cheap. Alternative: build it in M11e.
8. **Default limits.** `maxResponseBytes` 16 MiB, `maxEventBytes` 16 MiB,
   depth 512 (the core's default), `connectionAckTimeout` 10 s, 5 reconnection
   attempts, 3 retry attempts. Recommended as listed.
9. **Retrying mutations.** Recommended: never, unless the context has
   `Idempotent()`. Alternative: retry a mutation after a failure that
   proves it was not received (a refused connection), which `http` does not
   report reliably across platforms.
10. **`Retry-After`.** Recommended: not read in M11 (the backoff applies);
    a later addition to `RetryPolicy`.
11. **Dedupe key and headers.** Recommended: the body plus `RequestHeaders`
    (two users' tokens never share a request even when an `AuthLink` sits
    before `DedupeLink`). Alternative: the body only.

## 18. Notes for the implementers

- **Order.** M11a first. Then M11b, M11c and M11d in any order or in
  parallel (section 1 lists the shared files; resolve a conflict by
  keeping both sides' lines, exports and categories sorted). M11e after
  M11b. M11f last. M11z only after M7 merges.
- **Provenance.** Every plan task is one verified commit of the
  controller's scratch copy (`git archive` of `m11-plan`); the plans paste
  the full new files and the exact diffs. A hunk that does not apply means
  the tree drifted: apply with `git apply --3way` or stop and report.
- **Formatter.** Format with the 3.47.6 SDK's `dart` (3.13.5 or later),
  as CLAUDE.md says.
- **Chrome.** No Chrome runs locally (memory limit); M11f puts the client
  in CI's web job.
