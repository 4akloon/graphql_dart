# M11z End to End over M7 Implementation Plan (gated)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Gate.** Run this plan only after stage M7 (transports) is merged into `main`, and after M11a-M11f. It was written against the names of the M7 design spec (`docs/superpowers/specs/2026-10-16-m7-transports-design.md`, sections 3-5, 9 and 10) before M7 had code, so **its code has not been compiled**. Task 1 Step 1 checks every M7 name it uses against the merged code; when a name differs, change it everywhere in this plan's code before writing any file, and record the change in the commit message body.

**Goal:** Run the client's links against M7's real transport handlers, in memory and with no network: `HttpLink` against `GraphQLHttpHandler` (status codes, media types, body limit, persisted queries), `WebSocketLink` against `GraphQLWsHandler` over an in-memory socket pair, and `SseLink` against the handler's graphql-sse distinct connections mode (spec section 15, R8.4, R11.3).

**Architecture:** Tests only, in `packages/typed_graphql_client/test/e2e_m7/`. Two test supports: `HandlerTransport`, an `HttpTransport` that turns a `TransportRequest` into M7's `HttpRequestData`, calls `GraphQLHttpHandler.handle` and turns the `HttpResponseData` back (a `FixedBody` as one chunk, a `StreamedBody` as its stream, the client's abort as the request's `CancelSignal`); and `SocketPair`, two connected ends of an in-memory text socket, the client's `ClientSocket` and the server's `GraphQLSocket`. They reuse M11f's `TestSchema`, `TestServer`, `TickSource` and the test operations. Nothing in `lib/` changes.

**Tech Stack:** Dart 3.13 (formatted with the 3.47.6 SDK), `package:test`, `typed_graphql_server` (dev dependency since M11f).

**Spec:** `docs/superpowers/specs/2026-10-16-m11-client-runtime-design.md` (section 15), `docs/superpowers/specs/2026-10-16-m7-transports-design.md` (sections 3-5, 9, 10), `docs/requirements.md` (R8.4, R11.3).

**Base:** `main` with M7 (all of M7a-M7e) and M11a-M11f merged.

**Parallelism:** none; it is the last client plan of the stage. It touches only new files under `packages/typed_graphql_client/test/e2e_m7/` and, in Task 4, `CLAUDE.md` and `docs/superpowers/HANDOFF.md`.

**Provenance:** hand-written against the M7 spec; **not verified** (M7 had no code when it was written). Every other M11 plan was verified commit by commit in a scratch copy. Treat a compile error here as a name to re-check (Task 1 Step 1), not as a design change; a behaviour that differs from what a test expects is reported, not patched in the server.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a test file has at most 500 lines;
  - no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`;
  - no top-level function other than `main`.
- Each task leaves format, analyze, the root suite and the client suite green.
- **Memory and time limits.** Run every `dart` command through this wrapper, one heavy Dart process at a time (the lock is shared with other agents: waiting on it is normal; never kill a process you did not start):

  ```sh
  flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 <command>'
  ```

  Filter the output with `| tail`. No Chrome runs locally: CI runs the client suite under dart2js and dart2wasm, so these tests must not import `dart:io`.
- Never `git push`. Take no outward action. Do not change `packages/typed_graphql_server` or `lib/` of the client: if a test shows a server behaviour that differs from the M7 spec, stop and report it.
- Commits use Conventional Commits, one per task, with the subject given in the task and a trailer naming the real model of the implementer, for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Tests never open a socket or a port, and never sleep: the only delays are the `Backoff` delays of Task 2, one millisecond each.

## Interfaces consumed

- M7 (server, from the M7 spec; re-checked in Task 1): `GraphQLHttpHandler<C>(GraphQLServer<C> server, {HttpOptions options})` with `Future<HttpResponseData> handle(HttpRequestData request)`; `HttpRequestData({method, uri, headers, body, source, cancelSignal})`; `HttpResponseData` (`status`, `headers`, `body`); the sealed `HttpResponseBody` (`FixedBody(bytes)`, `StreamedBody(chunks)`); `HttpOptions({maxBodyBytes, ..., sse})`; `GraphQLSocket` (`protocol`, `incoming`, `send`, `close(code, reason)`); `GraphQLWsHandler<C>(server, {GraphQLWsOptions options})` with `static const String protocol` and `Future<void> serve(GraphQLSocket socket, RequestInfo upgrade)`; `GraphQLWsOptions({onConnect})`, `ConnectionHook`, `AcceptConnection`, `RefuseConnection`; `RequestInfo.connectionParams`.
- M6: `GraphQLServer`, `RequestInfo({method, uri, headers})`, `CancelSignal` (`cancel()`), `MemoryPersistedQueryStore`.
- M11 client: `GraphQLClient`, `GraphQLData`, `GraphQLErrors`, `GraphQLTransportFailure`, `HttpStatusFailure`, `SocketFailure`, `HttpLink`, `PersistedQueryLink`, `WebSocketLink`, `ClientSocket`, `SseLink`, `HttpTransport`, `TransportRequest`, `TransportResponse`, `Backoff`.
- M11f test support (`test/e2e/support/`): `TestServer`, `TestSchema`, `TickSource`, `PartialQuery`, `UnknownFieldQuery`; `test/support/test_operations.dart`: `HelloQuery`, `GreetQuery`, `RenameMutation`, `TicksSubscription`.

## Interfaces produced

- Test support only: `test/e2e_m7/support/handler_transport.dart` (`HandlerTransport`), `test/e2e_m7/support/socket_pair.dart` (`SocketPair`).

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql_client/test/e2e_m7/support/handler_transport.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e_m7/http_test.dart` | Create | 1 |
| `packages/typed_graphql_client/test/e2e_m7/support/socket_pair.dart` | Create | 2 |
| `packages/typed_graphql_client/test/e2e_m7/websocket_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/e2e_m7/sse_test.dart` | Create | 3 |
| `CLAUDE.md` | Modify | 4 |
| `docs/superpowers/HANDOFF.md` | Modify | 4 |

### Task 1: test(typed_graphql_client): run the HTTP link against the M7 handler

**Why.** M11f proved the links against M6's pipeline with a test double for the HTTP layer; this task replaces the double with M7's own `GraphQLHttpHandler`, so the status codes (`200`, `294`, `422`, `413`), the media types and the body limit are M7's. `HandlerTransport` is the in-memory host a real adapter would be: it streams the request body in, and maps the client's abort to the request's `CancelSignal`.

**Files:**
- Create `packages/typed_graphql_client/test/e2e_m7/support/handler_transport.dart`
- Create `packages/typed_graphql_client/test/e2e_m7/http_test.dart`

- [ ] **Step 1: Re-check the M7 names.** For each name below, find its declaration in the merged server and note the actual name and signature:

  ```sh
  grep -rn "class GraphQLHttpHandler\|class HttpRequestData\|class HttpResponseData\|class FixedBody\|class StreamedBody\|class HttpOptions\|class GraphQLSocket\|class GraphQLWsHandler\|class GraphQLWsOptions\|class AcceptConnection\|class RefuseConnection\|connectionParams\|static const String protocol" packages/typed_graphql_server/lib
  grep -n "export" packages/typed_graphql_server/lib/typed_graphql_server.dart | grep -i "http\|websocket\|sse"
  ```

  Expected: every class exists and is exported by `package:typed_graphql_server/typed_graphql_server.dart`, with the constructor parameters listed under **Interfaces consumed**. For each difference, change the code of Tasks 1-3 in this plan before writing it (and mention it in the commit body). Also read the M7 HTTP guide (`packages/typed_graphql_server/doc/http.md`) for the status of a partial result (`294` under `application/graphql-response+json`) and of a validation error (`422`).

- [ ] **Step 2: Write the test support.**

Create `packages/typed_graphql_client/test/e2e_m7/support/handler_transport.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// An [HttpTransport] that serves each request with M7's
/// [GraphQLHttpHandler], with no network, as a host adapter would.
///
/// The request body is streamed to the handler as the client wrote it; a
/// `FixedBody` comes back as one chunk and a `StreamedBody` as its stream.
/// The client's abort cancels the request's [CancelSignal], as a host does
/// when the client goes away.
final class HandlerTransport implements HttpTransport {
  /// Creates a transport over [handler].
  HandlerTransport(this.handler);

  /// The handler that answers.
  final GraphQLHttpHandler<Object?> handler;

  /// Every response status, in order.
  final List<int> statuses = [];

  /// Every response's `content-type` header, in order.
  final List<String?> contentTypes = [];

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final signal = CancelSignal();
    unawaited(request.abortTrigger?.then((_) => signal.cancel()));
    final response = await handler.handle(
      HttpRequestData(
        method: request.method,
        uri: request.uri,
        headers: request.headers,
        body: request.body ?? const Stream<List<int>>.empty(),
        cancelSignal: signal,
      ),
    );
    statuses.add(response.status);
    contentTypes.add(response.headers['content-type']);
    return TransportResponse(
      statusCode: response.status,
      headers: response.headers,
      body: switch (response.body) {
        FixedBody(:final bytes) => Stream.value(bytes),
        StreamedBody(:final chunks) => chunks,
      },
    );
  }
}
```

- [ ] **Step 3: Write the tests.**

Create `packages/typed_graphql_client/test/e2e_m7/http_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../e2e/support/e2e_operations.dart';
import '../e2e/support/test_server.dart';
import '../support/test_operations.dart';
import 'support/handler_transport.dart';

void main() {
  final uri = Uri.parse('http://localhost/graphql');

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  ({GraphQLClient client, HandlerTransport transport}) clientOver(
    GraphQLServer<Object?> server, {
    HttpOptions options = const HttpOptions(),
    bool usesGetForQueries = false,
    Link? before,
  }) {
    final transport = HandlerTransport(
      GraphQLHttpHandler<Object?>(server, options: options),
    );
    final http = HttpLink(
      uri: uri,
      transport: transport,
      usesGetForQueries: usesGetForQueries,
    );
    final link = before == null ? http : Link.from([before, http]);
    return (client: GraphQLClient(link: link), transport: transport);
  }

  group('HttpLink against the M7 handler', () {
    test('a query is a 200 graphql-response+json with the data', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(transport.statuses, [200]);
      expect(
        transport.contentTypes.single,
        startsWith('application/graphql-response+json'),
      );
    });

    test('a partial result is a 294 the client reads as data', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.query(const PartialQuery());
      final data = response as GraphQLData<String>;
      expect(data.data, 'hello');
      expect(data.errors, hasLength(1));
      expect(transport.statuses, [294]);
    });

    test('a validation error is a 422 the client reads as errors', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
      expect(transport.statuses, [422]);
    });

    test('a GET query with the preflight header passes', () async {
      final (:client, :transport) = clientOver(
        const TestServer().build(),
        usesGetForQueries: true,
      );
      final response = await client.query(const HelloQuery());
      expect(response, isA<GraphQLData<String>>());
      expect(transport.statuses, [200]);
    });

    test('a mutation over POST gives the data', () async {
      final (:client, :transport) = clientOver(const TestServer().build());
      final response = await client.mutate(const RenameMutation('Grace'));
      expect((response as GraphQLData<String>).data, 'Grace');
    });

    test('a body over the limit is a 413 transport failure', () async {
      final (:client, :transport) = clientOver(
        const TestServer().build(),
        options: const HttpOptions(maxBodyBytes: 64),
      );
      final response = await client.query(GreetQuery('a' * 100));
      final failure = (response as GraphQLTransportFailure<String>).failure;
      expect(failure, isA<HttpStatusFailure>());
      expect((failure as HttpStatusFailure).statusCode, 413);
    });

    test('automatic persisted queries reach the store in M7', () async {
      final (:client, :transport) = clientOver(
        const TestServer().build(
          persistedQueries: MemoryPersistedQueryStore(),
        ),
        before: PersistedQueryLink(),
      );
      await client.query(const HelloQuery());
      final second = await client.query(const HelloQuery());
      expect(second, isA<GraphQLData<String>>());
      // A miss and the text, then the hash alone.
      expect(transport.statuses, hasLength(3));
    });
  });
}
```

- [ ] **Step 4: Run the tests.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test test/e2e_m7"' 2>&1 | tail -30
```

Expected: all 7 tests pass. This task adds tests over code that exists, so nothing fails by design; a failure is either a name Step 1 missed (fix the test) or an M7 behaviour that differs from its spec (stop and report it with the status, the content type and the body).

- [ ] **Step 5: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 6: Commit.**

```sh
git add -A packages/typed_graphql_client/test/e2e_m7
git commit -m "test(typed_graphql_client): run the HTTP link against the M7 handler

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 2: test(typed_graphql_client): run the WebSocket link against the M7 handler

**Why.** `WebSocketLink` was verified against a scripted `FakeSocket`; here it talks graphql-transport-ws to M7's `GraphQLWsHandler` through `SocketPair`, an in-memory socket whose two ends are the client's `ClientSocket` and the server's `GraphQLSocket`. The tests cover the handshake with `connectionParams` reaching `onConnect`, a query, a subscription to its end, a cancel that reaches the server's source, a request error as an `error` message, a refused connection (`4403`, retried as the reference client does, then `GQL471`) and `dispose` (`1000`).

**Files:**
- Create `packages/typed_graphql_client/test/e2e_m7/support/socket_pair.dart`
- Create `packages/typed_graphql_client/test/e2e_m7/websocket_test.dart`

- [ ] **Step 1: Write the test support.**

Create `packages/typed_graphql_client/test/e2e_m7/support/socket_pair.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// Two connected ends of an in-memory text socket: [client] for
/// `WebSocketLink`, [server] for `GraphQLWsHandler.serve`.
///
/// A frame sent on one end arrives on the other. Closing either end closes
/// both, once, and records the code and reason both ends report.
final class SocketPair {
  /// Creates a pair whose server end reports [protocol] as negotiated.
  SocketPair({this.protocol = GraphQLWsHandler.protocol});

  /// The sub-protocol the server end reports.
  final String? protocol;

  final StreamController<String> _toServer = StreamController<String>();
  final StreamController<String> _toClient = StreamController<String>();

  /// The close code, once closed.
  int? closeCode;

  /// The close reason, once closed.
  String? closeReason;

  /// Whether either end closed the socket.
  bool get isClosed => _toClient.isClosed;

  // `late` because the ends need `this`; nothing reads them before the
  // constructor returns.
  /// The client's end.
  late final ClientSocket client = _ClientEnd(this);

  /// The server's end.
  late final GraphQLSocket server = _ServerEnd(this);

  void _close(int? code, String? reason) {
    if (isClosed) return;
    closeCode = code;
    closeReason = reason;
    // Not awaited: a controller nobody listens to never reports done.
    unawaited(_toServer.close());
    unawaited(_toClient.close());
  }
}

final class _ClientEnd implements ClientSocket {
  _ClientEnd(this._pair);

  final SocketPair _pair;

  @override
  Stream<String> get messages => _pair._toClient.stream;

  @override
  void send(String text) {
    if (!_pair.isClosed) _pair._toServer.add(text);
  }

  @override
  Future<void> close([int? code, String? reason]) async =>
      _pair._close(code, reason);

  @override
  int? get closeCode => _pair.closeCode;

  @override
  String? get closeReason => _pair.closeReason;
}

final class _ServerEnd implements GraphQLSocket {
  _ServerEnd(this._pair);

  final SocketPair _pair;

  @override
  String? get protocol => _pair.protocol;

  @override
  Stream<String> get incoming => _pair._toServer.stream;

  @override
  void send(String text) {
    if (!_pair.isClosed) _pair._toClient.add(text);
  }

  @override
  Future<void> close(int code, String reason) async =>
      _pair._close(code, reason);
}
```

- [ ] **Step 2: Write the tests.**

Create `packages/typed_graphql_client/test/e2e_m7/websocket_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../e2e/support/e2e_operations.dart';
import '../e2e/support/test_server.dart';
import '../e2e/support/tick_source.dart';
import '../support/test_operations.dart';
import 'support/socket_pair.dart';

void main() {
  final upgrade = RequestInfo(
    method: 'GET',
    uri: Uri.parse('ws://localhost/graphql'),
  );

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  late TickSource ticks;
  late List<SocketPair> pairs;
  late List<Future<void>> sessions;
  late WebSocketLink link;
  late GraphQLClient client;

  WebSocketLink linkTo(
    GraphQLWsHandler<Object?> handler, {
    FutureOr<JsonObject?> Function()? connectionParams,
    int retryAttempts = 5,
  }) => WebSocketLink(
    connect: () async {
      final pair = SocketPair();
      pairs.add(pair);
      sessions.add(handler.serve(pair.server, upgrade));
      return pair.client;
    },
    connectionParams: connectionParams,
    retryAttempts: retryAttempts,
    backoff: const Backoff(
      initialDelay: Duration(milliseconds: 1),
      maxDelay: Duration(milliseconds: 1),
    ),
  );

  setUp(() {
    ticks = TickSource();
    pairs = [];
    sessions = [];
    link = linkTo(
      GraphQLWsHandler<Object?>(const TestServer().build(ticks: ticks)),
    );
    client = GraphQLClient(link: link);
  });

  tearDown(() => link.dispose());

  group('WebSocketLink against the M7 handler', () {
    test('a query gives the data over one socket', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(pairs, hasLength(1));
    });

    test('a subscription gives every event and ends', () async {
      final events = await client.subscribe(const TicksSubscription()).toList();
      expect(events.map((e) => (e as GraphQLData<int>).data), [1, 2, 3]);
    });

    test('cancelling a subscription cancels the server source', () async {
      final first = await client.subscribe(const TicksSubscription()).first;
      expect((first as GraphQLData<int>).data, 1);
      await pumpEventQueue();
      expect(ticks.isCancelled, isTrue);
    });

    test('a request error arrives as errors', () async {
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
    });

    test('connectionParams reach onConnect', () async {
      final seen = <JsonObject?>[];
      final handler = GraphQLWsHandler<Object?>(
        const TestServer().build(),
        options: GraphQLWsOptions(
          onConnect: (info) {
            seen.add(info.connectionParams);
            return AcceptConnection();
          },
        ),
      );
      final params = JsonObject({'token': const JsonString('t')});
      final other = linkTo(handler, connectionParams: () => params);
      addTearDown(other.dispose);
      await GraphQLClient(link: other).query(const HelloQuery());
      expect(seen, [params]);
    });

    test('a refused connection ends in GQL471 with code 4403', () async {
      final handler = GraphQLWsHandler<Object?>(
        const TestServer().build(),
        options: GraphQLWsOptions(onConnect: (info) => RefuseConnection()),
      );
      final other = linkTo(handler, retryAttempts: 1);
      addTearDown(other.dispose);
      final response = await GraphQLClient(
        link: other,
      ).query(const HelloQuery());
      final failure = (response as GraphQLTransportFailure<String>).failure;
      expect(failure, isA<SocketFailure>());
      expect((failure as SocketFailure).closeCode, 4403);
    });

    test('dispose closes the socket with 1000 and ends the session', () async {
      await client.query(const HelloQuery());
      await link.dispose();
      await Future.wait(sessions);
      expect(pairs.single.closeCode, 1000);
    });
  });
}
```

- [ ] **Step 3: Run the tests.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test test/e2e_m7/websocket_test.dart"' 2>&1 | tail -30
```

Expected: all 7 tests pass. If `TestServer.build` has no `ticks` parameter or `TickSource` has another name, use what M11f Task 2 named them (`test/e2e/support/`). If `SocketFailure` names its code field differently, use the M11a name (`lib/src/client/client_failure.dart`).

- [ ] **Step 4: Format, then run the green check** (the five commands of Task 1 Step 5). Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages/typed_graphql_client/test/e2e_m7
git commit -m "test(typed_graphql_client): run the WebSocket link against the M7 handler

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 3: test(typed_graphql_client): run the SSE link against the M7 handler

**Why.** `SseLink` against M7's distinct connections mode: the handler negotiates `text/event-stream`, writes `next` and `complete` events into a `StreamedBody`, puts a request error into the accepted stream (M7 spec section 10), and cancels the operation when the host cancels the body, which `HandlerTransport` does when the client aborts.

**Files:**
- Create `packages/typed_graphql_client/test/e2e_m7/sse_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/e2e_m7/sse_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../e2e/support/e2e_operations.dart';
import '../e2e/support/test_server.dart';
import '../e2e/support/tick_source.dart';
import '../support/test_operations.dart';
import 'support/handler_transport.dart';

void main() {
  late TickSource ticks;
  late HandlerTransport transport;
  late GraphQLClient client;

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  setUp(() {
    ticks = TickSource();
    transport = HandlerTransport(
      GraphQLHttpHandler<Object?>(const TestServer().build(ticks: ticks)),
    );
    client = GraphQLClient(
      link: SseLink(
        uri: Uri.parse('http://localhost/graphql/stream'),
        transport: transport,
      ),
    );
  });

  group('SseLink against the M7 handler', () {
    test('a subscription gives every event and ends', () async {
      final events = await client.subscribe(const TicksSubscription()).toList();
      expect(events.map((e) => (e as GraphQLData<int>).data), [1, 2, 3]);
      expect(transport.contentTypes.single, startsWith('text/event-stream'));
    });

    test('cancelling a subscription cancels the server source', () async {
      final first = await client.subscribe(const TicksSubscription()).first;
      expect((first as GraphQLData<int>).data, 1);
      await pumpEventQueue();
      expect(ticks.isCancelled, isTrue);
    });

    test('a query is one next event', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(transport.statuses, [200]);
    });

    test('a validation error arrives inside the accepted stream', () async {
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
      expect(transport.contentTypes.single, startsWith('text/event-stream'));
    });
  });
}
```

- [ ] **Step 2: Run the tests.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test test/e2e_m7/sse_test.dart"' 2>&1 | tail -30
```

Expected: all 4 tests pass. A keep-alive comment (`:`) at the start of the stream is ignored by the parser; if the handler's keep-alive timer keeps the test alive after the stream ends, that is an M7 bug to report.

- [ ] **Step 3: Format, then run the green check** (the five commands of Task 1 Step 5). Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 4: Commit.**

```sh
git add -A packages/typed_graphql_client/test/e2e_m7
git commit -m "test(typed_graphql_client): run the SSE link against the M7 handler

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 4: docs: record the end-to-end tests over M7

**Why.** CLAUDE.md's "Where things are" and the handoff must say that the client is now tested against M7's handlers, and where.

**Files:**
- Modify `CLAUDE.md`
- Modify `docs/superpowers/HANDOFF.md`

- [ ] **Step 1: Edit `CLAUDE.md`.** In "Where things are", after the line on the client's end-to-end tests that M11f added, add:

  ```text
  - Client against M7's handlers (in memory, no port):
    `packages/typed_graphql_client/test/e2e_m7/` (`HandlerTransport` over
    `GraphQLHttpHandler`, `SocketPair` for `GraphQLWsHandler`).
  ```

- [ ] **Step 2: Edit `docs/superpowers/HANDOFF.md`.** Where it lists M11z as waiting for M7, say instead that M11z is done, with the three test files and the count of tests (18), and any M7 behaviour the tests showed that differs from the M7 spec.

- [ ] **Step 3: Run the root suite** (the discovery and link checks read these files):

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test' 2>&1 | tail -5
```

Expected: all tests pass.

- [ ] **Step 4: Commit.**

```sh
git add CLAUDE.md docs/superpowers/HANDOFF.md
git commit -m "docs: record the end-to-end tests over M7

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

## Review Focus

- Task 1 Step 1 was done: every M7 name was checked against the merged code and each change is in a commit body.
- `HandlerTransport` maps the client's abort to the request's `CancelSignal`, and a `StreamedBody` is passed through lazily (never collected), so cancellation reaches M7's `onCancel`.
- `SocketPair` closes both ends once and records one code; nothing awaits a controller that has no listener.
- No test sleeps, opens a port or imports `dart:io` (CI runs them in Chrome).
- Any M7 behaviour that differs from its spec is reported, not patched in the test or the server.

## Verification

After Task 4, run format, analyze, the root suite and the client suite with the wrapper (the commands of Task 1 Step 5). Expected: 0 files changed, `No issues found!`, all suites pass, the client suite has 18 more tests than after M11f.
