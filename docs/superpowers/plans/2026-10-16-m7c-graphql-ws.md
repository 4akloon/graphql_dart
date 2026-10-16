# M7c graphql-ws Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the graphql-ws transport of stage M7 in `typed_graphql_server` (R5.7): the `graphql-transport-ws` protocol over any WebSocket an adapter wraps as a `GraphQLSocket`, with the connection handshake and its `onConnect` hook, the operations of one connection running through `GraphQLServer.handle`, the protocol's close codes, the limits (init timeout, operations per connection, frame length, JSON depth, connections per handler), the Origin check that is the transport's CSRF defence, and the hostile-input tests. It adds `GQL432` to the core catalog and `RequestInfo.connectionParams` to the server.

**Architecture:** Everything lives in the server's new `lib/src/websocket/` folder (dartdoc category `websocket`, guide `doc/websocket.md`). The protocol's messages are internal: `ClientMessageReader` turns a frame into the sealed `ClientMessage` family or null (close `4400`), `ServerMessages` writes the server's. `GraphQLWsHandler.serve(socket, info)` runs one `SocketSession` per connection: `ConnectionHandshake` owns the init timer, the `connection_init` decision (`ConnectionHook`, `ConnectionDecision`) and the connection parameters; `SocketOperations` is the registry of running `SocketOperation`s, each a `ServerRequest` with a `CancelSignal` that `complete` or a disconnect cancels. `OriginPolicy` decides `allowsUpgrade` before the adapter upgrades. Keep-alive is the adapter's WebSocket ping frames; the handler never sends graphql-ws pings.

**Tech Stack:** Dart 3.13 (formatted with the 3.47.6 Flutter SDK's Dart 3.13.5), `package:test`, `package:meta`; no new dependency.

**Spec:** `docs/superpowers/specs/2026-10-16-m7-transports-design.md` (sections 7, 9, 13, 14, 15 and 17), `docs/requirements.md` (R0.3, R5.7, R5.13), the protocol `reference/graphql-ws/PROTOCOL.md`.

**Base:** `main` with the M7 spec (the tree of `m7-plan` at `0274818`). This plan does not depend on M7a, M7b or M7d. It is generated from the commits that implemented it in a scratch copy, in order.

**Parallel work:** M7c runs in parallel with the main M7 line (M7a, then M7b, then M7d), on its own branch from the same base. It shares these files with that line, and nothing else: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` and `packages/typed_graphql/CHANGELOG.md` (M7c adds only `GQL432`, between the main line's `GQL431` and `GQL433`), and in the server `lib/typed_graphql_server.dart` (exports and the library doc), `CHANGELOG.md`, `README.md` (the status lines) and `dartdoc_options.yaml` (the `websocket` category). `lib/src/server/request_info.dart` is touched only by M7c. M7c never edits `CLAUDE.md`, `llms.txt`, `docs/discovery.md` or the root `README.md`: M7e Task 1 merges this branch into the main line and resolves those shared files (keep both sides; codes in id order); M7e Task 8 adds the `websocket/` paragraph to `CLAUDE.md`.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too: a file in `lib/` has at most 300 lines and a test file at most 500; a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt); control blocks nest at most 3 deep; a file in `lib/` declares one public class or sealed family (a typedef counts); no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`, no `utils`/`helpers` names; no top-level function other than `main`, in tests too.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and the server suite green (a core task also the core suite; a shelf task the shelf suite).
- **Memory and time limits.** Run every heavy `dart` command (format, analyze, test, pub get, doc) as `flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd <dir> && timeout 900 dart <args>'`: one heavy Dart process at a time (another agent may hold the lock; waiting is normal), no Chrome runs, never kill a process you did not start. The steps below spell the wrapper out.
- Format with the 3.47.6 Flutter SDK's Dart (3.13.5): 3.13.1's formatter crashes on `diagnostic_code.dart`. The wrapper puts it first on `PATH`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen` or `packages/typed_graphql_client`.
- Commits use Conventional Commits, one per task, with the subject given in the task and a trailer naming the real model of the implementer (for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Run every command from the repository root unless a step says otherwise.
- New files are given in full; changes to existing files are exact unified diffs against the tree the earlier tasks leave. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- Tests never read git-ignored or untracked files, and never use `fake_async`: timing tests use real durations of tens of milliseconds.
- Bad input never throws (R0.3): every transport turns a malformed, oversized, slow or hostile request into a response (or a close code), and messages never echo request content.
- Diagnostic codes come from the range the spec reserves for M7 (`GQL420`-`GQL449`); `GQL460`-`GQL499` belong to the client runtime (M11), `GQL400`-`GQL415` to M6.
- The server's `lib/` imports only `dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:math`, `package:meta`, `package:crypto/crypto.dart`, the core barrel and its own files (relative imports); never `dart:io`.
- graphql-ws message types stay internal to the server (spec deviation 2): nothing under `websocket/` but `GraphQLSocket`, `GraphQLWsOptions`, `ConnectionHook`, `ConnectionDecision` (with `AcceptConnection`, `RefuseConnection`) and `GraphQLWsHandler` is exported.

## Review Focus

1. Every protocol violation the spec's section 9 table lists closes with its code (`4400`, `4401`, `4403`, `4406`, `4408`, `4409`, `4429`, `4500`, `1009`, `1013`) and nothing else; a `4409` reason never passes 123 UTF-8 bytes.
2. A frame is length-checked before it is parsed, and parsed with the depth limit; an unknown or server-only message type closes `4400`.
3. Every operation's resolvers stop when the client sends `complete` or disconnects: the `CancelSignal` fires and the result stream is cancelled; an id is free again only after its operation ended.
4. `subscribe` past `maxOperations` answers an `error` message with `GQL432` and keeps the socket open; the handler refuses a new connection past `maxConnections` with `1013`.
5. Each message's `RequestInfo` is a POST with `content-type: application/json` plus the connection parameters, so CSRF prevention and the GET-mutation guard of M6 treat a socket like a JSON POST (spec section 9).
6. `OriginPolicy` refuses the literal `null` origin and any origin other than the upgrade's own host or a listed one; a missing `Origin` (non-browser client) is allowed.
7. No unhandled asynchronous error can escape `serve`: an unexpected server failure becomes an `error` message with the masked `GQL330` text.

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 2, 4, 9 |
| `packages/typed_graphql_server/README.md` | Modify | 9 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 4 |
| `packages/typed_graphql_server/doc/websocket.md` | Create, then Modify | 4, 9 |
| `packages/typed_graphql_server/lib/src/server/request_info.dart` | Modify | 2 |
| `packages/typed_graphql_server/lib/src/websocket/client_message.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/websocket/client_message_reader.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/websocket/connection_decision.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/websocket/connection_handshake.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/websocket/connection_hook.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/websocket/duplicate_subscriber.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/websocket/graphql_socket.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/websocket/graphql_ws_handler.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/websocket/graphql_ws_options.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/websocket/origin_policy.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/websocket/server_messages.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/websocket/socket_operation.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/websocket/socket_operations.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/websocket/socket_session.dart` | Create, then Modify | 5, 6, 8 |
| `packages/typed_graphql_server/lib/src/websocket/ws_close.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 4, 7, 9 |
| `packages/typed_graphql_server/test/server/server_values_test.dart` | Modify | 2 |
| `packages/typed_graphql_server/test/websocket/client_message_reader_test.dart` | Create | 3 |
| `packages/typed_graphql_server/test/websocket/graphql_ws_handler_test.dart` | Create | 7 |
| `packages/typed_graphql_server/test/websocket/hostile_websocket_test.dart` | Create | 8 |
| `packages/typed_graphql_server/test/websocket/server_messages_test.dart` | Create | 3 |
| `packages/typed_graphql_server/test/websocket/socket_handshake_test.dart` | Create | 5 |
| `packages/typed_graphql_server/test/websocket/socket_operations_test.dart` | Create, then Modify | 6, 8 |
| `packages/typed_graphql_server/test/websocket/support/controlled_source.dart` | Create | 8 |
| `packages/typed_graphql_server/test/websocket/support/fake_socket.dart` | Create, then Modify | 5, 7 |
| `packages/typed_graphql_server/test/websocket/support/ws_fixture.dart` | Create | 5 |
| `packages/typed_graphql_server/test/websocket/ws_values_test.dart` | Create | 4 |

### Task 1: feat(typed_graphql): add the graphql-ws diagnostic code

**Why.** The operation limit of a connection needs its own stable code before any server code reports it (a core change goes in its own commit, before the server commit that needs it).

**Produces:** `DiagnosticCode.tooManySocketOperations` (`GQL432`).

**Files:**

- Modify `packages/typed_graphql/CHANGELOG.md`
- Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

- [ ] **Step 1: Write the tests.**

This task changes no test file; its check is the suites of Step 4.

- [ ] **Step 2: Run the tests and see them fail.**

Expected: this task changes no test; the core suite's catalog tests (ids in order, unique, documented) cover the new value.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql/CHANGELOG.md b/packages/typed_graphql/CHANGELOG.md
index 98dc7f1..7d29553 100644
--- a/packages/typed_graphql/CHANGELOG.md
+++ b/packages/typed_graphql/CHANGELOG.md
@@ -302,3 +302,4 @@
   `invalidPersistedQuery`, `untrustedDocument`, `unknownTrustedDocument`),
   reported by the server for persisted queries and trusted documents.
 - Documentation: `GQL402` also covers `HEAD`; the cost guide says a resolver must cap a slicing argument itself.
+- `DiagnosticCode.tooManySocketOperations` (`GQL432`): a graphql-ws `subscribe` past the socket's operation limit.
```

Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
index 241c8c7..b10754f 100644
--- a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
@@ -717,6 +717,12 @@ enum DiagnosticCode(
   /// response of `GraphQLServer.handle`.
   unknownTrustedDocument('GQL415'),
 
+  /// `GQL432`: reported when a graphql-ws `subscribe` arrives while the
+  /// socket already runs `GraphQLWsOptions.maxOperations` operations; it is
+  /// the `extensions.code` of the `error` message for that id, and the socket
+  /// stays open.
+  tooManySocketOperations('GQL432'),
+
   /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
   /// the YAML parser's.
   configSyntax('GQL500'),
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql): add the graphql-ws diagnostic code

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: feat(typed_graphql_server): carry the connection parameters in RequestInfo

**Why.** The `connection_init` payload of graphql-ws is the socket's equivalent of request headers: context factories and extensions must see it on every operation of the connection (spec section 7).

**Consumes:** M6's `RequestInfo`.

**Produces:** `RequestInfo.connectionParams` (`JsonObject?`, null for HTTP).

**Files:**

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/lib/src/server/request_info.dart`
- Modify `packages/typed_graphql_server/test/server/server_values_test.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/server/server_values_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_values_test.dart b/packages/typed_graphql_server/test/server/server_values_test.dart
index 0bc3bd4..4ce41fd 100644
--- a/packages/typed_graphql_server/test/server/server_values_test.dart
+++ b/packages/typed_graphql_server/test/server/server_values_test.dart
@@ -31,6 +31,22 @@ void main() {
     test('keeps the method as given', () {
       expect(RequestInfo(method: 'get', uri: Uri()).method, 'get');
     });
+
+    test('has no connection parameters by default', () {
+      expect(info.connectionParams, isNull);
+    });
+
+    test('carries the connection parameters it is given', () {
+      final params = JsonObject({'token': const JsonString('a')});
+      expect(
+        RequestInfo(
+          method: 'GET',
+          uri: Uri(),
+          connectionParams: params,
+        ).connectionParams,
+        params,
+      );
+    });
   });
 
   group('SingleResponse', () {
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/server/server_values_test.dart'
```

Expected: the two new tests in `server_values_test.dart` fail to compile: `connectionParams` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 5606345..4238199 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -212,3 +212,5 @@
   server, a failing store write is checked to be answered as `GQL330`, and
   the wall-clock assertion and most real sleeps of the pipeline tests are
   gone.
+- `RequestInfo.connectionParams`: the payload of the graphql-ws
+  `connection_init` message, for a context factory that reads a token sent there.
```

Modify `packages/typed_graphql_server/lib/src/server/request_info.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/request_info.dart b/packages/typed_graphql_server/lib/src/server/request_info.dart
index 96cbb67..5cd7440 100644
--- a/packages/typed_graphql_server/lib/src/server/request_info.dart
+++ b/packages/typed_graphql_server/lib/src/server/request_info.dart
@@ -1,3 +1,5 @@
+import 'package:typed_graphql/typed_graphql.dart';
+
 import 'header_names.dart';
 
 /// What the transport knows about one request, besides the GraphQL
@@ -14,6 +16,7 @@ final class RequestInfo {
     required this.uri,
     Map<String, String> headers = const {},
     this.source,
+    this.connectionParams,
   }) : headers = const HeaderNames().lowerCased(headers);
 
   /// The HTTP method as the transport gave it; the pipeline compares it with
@@ -30,6 +33,11 @@ final class RequestInfo {
   /// The host's own request object, never read by the library.
   final Object? source;
 
+  /// The payload of the graphql-ws `connection_init` message of the
+  /// connection the request came on, null for other transports; a context
+  /// factory reads a token sent there.
+  final JsonObject? connectionParams;
+
   /// The value of the header [name], whatever its case, or null.
   String? header(String name) => headers[name.toLowerCase()];
 }
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_server): carry the connection parameters in RequestInfo

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: feat(typed_graphql_server): read and write graphql-ws messages

**Why.** The session must never see raw JSON: the reader turns a frame into one of five client messages or null, and the writer builds every server message in one place, so the protocol's shapes are tested apart from the state machine.

**Consumes:** the core's `JsonReader`, `GraphQLRequest.decode`, `ExecutionResult`, `GraphQLError`.

**Produces:** internal `ClientMessage` (sealed: `InitMessage`, `PingMessage`, `PongMessage`, `SubscribeMessage`, `CompleteMessage`), `ClientMessageReader(maxJsonDepth).read(text)`, `ServerMessages` (`ack`, `ping`, `pong`, `next`, `error`, `complete`).

**Files:**

- Create `packages/typed_graphql_server/lib/src/websocket/client_message.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/client_message_reader.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/server_messages.dart`
- Create `packages/typed_graphql_server/test/websocket/client_message_reader_test.dart`
- Create `packages/typed_graphql_server/test/websocket/server_messages_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/websocket/client_message_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/client_message.dart';
import 'package:typed_graphql_server/src/websocket/client_message_reader.dart';

void main() {
  const reader = ClientMessageReader(8);
  final payload = JsonObject({'token': const JsonString('a')});

  group('connection_init, ping and pong', () {
    test('connection_init without a payload', () {
      expect(
        reader.read('{"type":"connection_init"}'),
        const InitMessage(null),
      );
    });

    test('connection_init with a null payload', () {
      expect(
        reader.read('{"type":"connection_init","payload":null}'),
        const InitMessage(null),
      );
    });

    test('connection_init with an object payload', () {
      expect(
        reader.read('{"type":"connection_init","payload":{"token":"a"}}'),
        InitMessage(payload),
      );
    });

    test('ping with a payload', () {
      expect(
        reader.read('{"type":"ping","payload":{"token":"a"}}'),
        PingMessage(payload),
      );
    });

    test('ping without a payload', () {
      expect(reader.read('{"type":"ping"}'), const PingMessage(null));
    });

    test('pong with a payload', () {
      expect(
        reader.read('{"type":"pong","payload":{"token":"a"}}'),
        PongMessage(payload),
      );
    });

    test('a payload that is an array is invalid', () {
      expect(reader.read('{"type":"connection_init","payload":[]}'), isNull);
    });

    test('a ping payload that is a string is invalid', () {
      expect(reader.read('{"type":"ping","payload":"x"}'), isNull);
    });
  });

  group('subscribe', () {
    test('reads the id and the request', () {
      expect(
        reader.read(
          '{"id":"1","type":"subscribe","payload":{"query":"{a}",'
          '"operationName":"Q","variables":{"x":1}}}',
        ),
        SubscribeMessage(
          '1',
          GraphQLRequest(
            query: '{a}',
            operationName: 'Q',
            variables: JsonObject({'x': JsonNumber(1)}),
          ),
        ),
      );
    });

    test('allows a missing query', () {
      expect(
        reader.read(
          '{"id":"1","type":"subscribe","payload":{"extensions":{}}}',
        ),
        SubscribeMessage('1', GraphQLRequest(extensions: JsonObject({}))),
      );
    });

    test('a missing id is invalid', () {
      expect(
        reader.read('{"type":"subscribe","payload":{"query":"{a}"}}'),
        isNull,
      );
    });

    test('an empty id is invalid', () {
      expect(
        reader.read('{"id":"","type":"subscribe","payload":{"query":"{a}"}}'),
        isNull,
      );
    });

    test('a numeric id is invalid', () {
      expect(
        reader.read('{"id":1,"type":"subscribe","payload":{"query":"{a}"}}'),
        isNull,
      );
    });

    test('a missing payload is invalid', () {
      expect(reader.read('{"id":"1","type":"subscribe"}'), isNull);
    });

    test('a payload that is an array is invalid', () {
      expect(
        reader.read('{"id":"1","type":"subscribe","payload":[]}'),
        isNull,
      );
    });

    test('a mistyped query is invalid', () {
      expect(
        reader.read('{"id":"1","type":"subscribe","payload":{"query":1}}'),
        isNull,
      );
    });
  });

  group('complete', () {
    test('reads the id', () {
      expect(
        reader.read('{"id":"7","type":"complete"}'),
        const CompleteMessage('7'),
      );
    });

    test('an empty id is invalid', () {
      expect(reader.read('{"id":"","type":"complete"}'), isNull);
    });

    test('a missing id is invalid', () {
      expect(reader.read('{"type":"complete"}'), isNull);
    });
  });

  group('invalid frames', () {
    test('text that is not JSON', () {
      expect(reader.read('{"type"'), isNull);
    });

    test('JSON that is not an object', () {
      expect(reader.read('[]'), isNull);
    });

    test('an object without a type', () {
      expect(reader.read('{}'), isNull);
    });

    test('a type that is not a string', () {
      expect(reader.read('{"type":1}'), isNull);
    });

    test('an unknown type', () {
      expect(reader.read('{"type":"hello"}'), isNull);
    });

    test('connection_ack, which only a server sends', () {
      expect(reader.read('{"type":"connection_ack"}'), isNull);
    });

    test('next, which only a server sends', () {
      expect(reader.read('{"id":"1","type":"next","payload":{}}'), isNull);
    });

    test('error, which only a server sends', () {
      expect(reader.read('{"id":"1","type":"error","payload":[]}'), isNull);
    });

    test('JSON deeper than the limit', () {
      final deep = '[' * 9 + ']' * 9;
      expect(reader.read('{"type":"ping","payload":{"a":$deep}}'), isNull);
    });
  });
}
```

Create `packages/typed_graphql_server/test/websocket/server_messages_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/server_messages.dart';

void main() {
  const messages = ServerMessages();

  test('connection_ack without a payload has only a type', () {
    expect(messages.ack(null), '{"type":"connection_ack"}');
  });

  test('connection_ack with a payload', () {
    expect(
      messages.ack(JsonObject({'a': JsonNumber(1)})),
      '{"type":"connection_ack","payload":{"a":1}}',
    );
  });

  test('pong without a payload has only a type', () {
    expect(messages.pong(null), '{"type":"pong"}');
  });

  test('pong echoes the payload', () {
    expect(
      messages.pong(JsonObject({'a': const JsonString('b')})),
      '{"type":"pong","payload":{"a":"b"}}',
    );
  });

  test('next writes type, id and payload in that order', () {
    final result = ExecutionResult(JsonObject({'a': JsonNumber(1)}));
    expect(
      messages.next('7', result),
      '{"type":"next","id":"7","payload":{"data":{"a":1}}}',
    );
  });

  test('error writes the errors as an array', () {
    expect(
      messages.error('7', [GraphQLError('boom')]),
      '{"type":"error","id":"7","payload":[{"message":"boom"}]}',
    );
  });

  test('complete has a type and an id', () {
    expect(messages.complete('7'), '{"type":"complete","id":"7"}');
  });

  test('an id with quotes is escaped', () {
    expect(messages.complete('a"b'), r'{"type":"complete","id":"a\"b"}');
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/websocket/client_message_reader_test.dart test/websocket/server_messages_test.dart'
```

Expected: both test files fail to compile: the `websocket/` libraries do not exist.

- [ ] **Step 3: Write the implementation.**

Create `packages/typed_graphql_server/lib/src/websocket/client_message.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// A graphql-ws message a client may send: the five types a server accepts.
///
/// Messages compare by value so that tests can state what was read.
@internal
sealed class ClientMessage {
  const ClientMessage();
}

/// `connection_init`: the first message, with the connection parameters.
@internal
final class InitMessage extends ClientMessage {
  /// Creates the message with its optional [payload].
  const InitMessage(this.payload);

  /// The connection parameters, null when the client sent none.
  final JsonObject? payload;

  @override
  bool operator ==(Object other) =>
      other is InitMessage && other.payload == payload;

  @override
  int get hashCode => Object.hash(InitMessage, payload);
}

/// `ping`: asks the server to answer with a `pong`.
@internal
final class PingMessage extends ClientMessage {
  /// Creates the message with its optional [payload].
  const PingMessage(this.payload);

  /// The payload the `pong` echoes, null when the client sent none.
  final JsonObject? payload;

  @override
  bool operator ==(Object other) =>
      other is PingMessage && other.payload == payload;

  @override
  int get hashCode => Object.hash(PingMessage, payload);
}

/// `pong`: the client's answer to a server `ping`; the server ignores it.
@internal
final class PongMessage extends ClientMessage {
  /// Creates the message with its optional [payload].
  const PongMessage(this.payload);

  /// The payload, null when the client sent none.
  final JsonObject? payload;

  @override
  bool operator ==(Object other) =>
      other is PongMessage && other.payload == payload;

  @override
  int get hashCode => Object.hash(PongMessage, payload);
}

/// `subscribe`: starts the operation [id] on the connection.
@internal
final class SubscribeMessage extends ClientMessage {
  /// Creates the message for operation [id] running [request].
  const SubscribeMessage(this.id, this.request);

  /// The id the client chose; every message about the operation carries it.
  final String id;

  /// The GraphQL request, whose `query` may be absent (persisted documents).
  final GraphQLRequest request;

  @override
  bool operator ==(Object other) =>
      other is SubscribeMessage && other.id == id && other.request == request;

  @override
  int get hashCode => Object.hash(SubscribeMessage, id, request);
}

/// `complete` from the client: stops the operation [id].
@internal
final class CompleteMessage extends ClientMessage {
  /// Creates the message for operation [id].
  const CompleteMessage(this.id);

  /// The id of the operation to stop.
  final String id;

  @override
  bool operator ==(Object other) => other is CompleteMessage && other.id == id;

  @override
  int get hashCode => Object.hash(CompleteMessage, id);
}
```

Create `packages/typed_graphql_server/lib/src/websocket/client_message_reader.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'client_message.dart';

/// Reads the text of a frame into a [ClientMessage] (R0.3: bad input is a
/// null, never an exception).
@internal
final class ClientMessageReader {
  /// Creates a reader that accepts JSON nested at most [maxJsonDepth] deep.
  const ClientMessageReader(this.maxJsonDepth);

  /// The nesting limit of the frame's JSON.
  final int maxJsonDepth;

  /// The message in [text], or null when it is not a valid client message:
  /// not JSON, too deep, not an object, no string `type`, a field of the
  /// wrong type, or a type only a server sends. The caller closes `4400`.
  ClientMessage? read(String text) {
    final parsed = JsonReader(maxDepth: maxJsonDepth).parse(text);
    if (parsed case DecodeSuccess(value: final JsonObject json)) {
      return switch (json['type']) {
        JsonString(value: 'connection_init') => _withPayload(
          json,
          InitMessage.new,
        ),
        JsonString(value: 'ping') => _withPayload(json, PingMessage.new),
        JsonString(value: 'pong') => _withPayload(json, PongMessage.new),
        JsonString(value: 'subscribe') => _subscribe(json),
        JsonString(value: 'complete') => _complete(json),
        _ => null,
      };
    }
    return null;
  }

  ClientMessage? _withPayload(
    JsonObject json,
    ClientMessage Function(JsonObject?) create,
  ) => switch (json['payload']) {
    null || JsonNull() => create(null),
    final JsonObject payload => create(payload),
    _ => null,
  };

  ClientMessage? _subscribe(JsonObject json) {
    final id = _id(json);
    final payload = json['payload'];
    if (id == null || payload is! JsonObject) {
      return null;
    }
    return switch (GraphQLRequest.decode(payload)) {
      DecodeSuccess(value: final request) => SubscribeMessage(id, request),
      DecodeFailure() => null,
    };
  }

  ClientMessage? _complete(JsonObject json) {
    final id = _id(json);
    return id == null ? null : CompleteMessage(id);
  }

  String? _id(JsonObject json) => switch (json['id']) {
    JsonString(value: final id) when id.isNotEmpty => id,
    _ => null,
  };
}
```

Create `packages/typed_graphql_server/lib/src/websocket/server_messages.dart`:

```dart
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Writes the graphql-ws messages a server sends, as the text of a frame.
///
/// The keys are in the order `type`, `id`, `payload`, which `jsonEncode`
/// keeps.
@internal
final class ServerMessages {
  /// Creates the writer.
  const ServerMessages();

  /// `connection_ack`, with [payload] when it is not null.
  String ack(JsonObject? payload) => _write('connection_ack', payload: payload);

  /// `pong`, with [payload] when it is not null.
  String pong(JsonObject? payload) => _write('pong', payload: payload);

  /// `next`: one execution [result] of operation [id].
  String next(String id, ExecutionResult result) =>
      _write('next', id: id, payload: result.toJson());

  /// `error`: the [errors] that stopped operation [id] before it ran.
  String error(String id, List<GraphQLError> errors) => _write(
    'error',
    id: id,
    payload: JsonArray([for (final error in errors) error.toJson()]),
  );

  /// `complete`: operation [id] has no more results.
  String complete(String id) => _write('complete', id: id);

  String _write(String type, {String? id, JsonValue? payload}) => jsonEncode(
    JsonObject({
      'type': JsonString(type),
      if (id != null) 'id': JsonString(id),
      'payload': ?payload,
    }).toJson(),
  );
}
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_server): read and write graphql-ws messages

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: feat(typed_graphql_server): add the graphql-ws socket and options

**Why.** The public face of the transport comes before its behaviour so the adapter contract (`GraphQLSocket`) and the options are reviewed on their own; the close codes and the `4409` reason are values with their own tests.

**Produces:** `GraphQLSocket`, `GraphQLWsOptions`, `ConnectionHook`, `ConnectionDecision` (`AcceptConnection`, `RefuseConnection`), internal `WsClose` and `DuplicateSubscriber` (`4409` reason cut to 123 UTF-8 bytes at a code point boundary); the `websocket` dartdoc category and a first guide with a program that prints the defaults (Task 9 replaces it).

**Files:**

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/dartdoc_options.yaml`
- Create `packages/typed_graphql_server/doc/websocket.md`
- Create `packages/typed_graphql_server/lib/src/websocket/connection_decision.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/connection_hook.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/duplicate_subscriber.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/graphql_socket.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/graphql_ws_options.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/ws_close.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Create `packages/typed_graphql_server/test/websocket/ws_values_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/websocket/ws_values_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/duplicate_subscriber.dart';
import 'package:typed_graphql_server/src/websocket/ws_close.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('GraphQLWsOptions', () {
    const options = GraphQLWsOptions();

    test('waits three seconds for the connection to be initialised', () {
      expect(options.connectionInitTimeout, const Duration(seconds: 3));
    });

    test('runs a hundred operations at most', () {
      expect(options.maxOperations, 100);
    });

    test('accepts a frame of one mebi characters', () {
      expect(options.maxMessageLength, 1048576);
    });

    test('limits the JSON depth to 64', () {
      expect(options.maxJsonDepth, 64);
    });

    test('serves ten thousand connections', () {
      expect(options.maxConnections, 10000);
    });

    test('lists no origin and has no hook', () {
      expect(options.allowedOrigins, isNull);
      expect(options.onConnect, isNull);
    });
  });

  group('ConnectionDecision', () {
    test('accepting carries no payload by default', () {
      expect(const AcceptConnection().payload, isNull);
    });

    test('accepting carries the payload it is given', () {
      final payload = JsonObject({'a': JsonNumber(1)});
      expect(AcceptConnection(payload: payload).payload, payload);
    });

    test('accepting and refusing are the two decisions', () {
      const ConnectionDecision decision = RefuseConnection();
      expect(switch (decision) {
        AcceptConnection() => 'accept',
        RefuseConnection() => 'refuse',
      }, 'refuse');
    });
  });

  group('WsClose', () {
    test('has the codes and reasons of the protocol', () {
      expect(
        {for (final close in WsClose.values) close.code: close.reason},
        {
          4400: 'Invalid message received',
          4401: 'Unauthorized',
          4403: 'Forbidden',
          4406: 'Subprotocol not acceptable',
          4408: 'Connection initialisation timeout',
          4429: 'Too many initialisation requests',
          4500: 'Internal server error',
          1009: 'Message too big',
          1013: 'Try again later',
        },
      );
    });
  });

  group('DuplicateSubscriber', () {
    const duplicate = DuplicateSubscriber();

    test('uses the code 4409', () {
      expect(duplicate.code, 4409);
    });

    test('names a short id in full', () {
      expect(duplicate.reason('7'), 'Subscriber for 7 already exists');
    });

    test('cuts a long id to 123 UTF-8 bytes', () {
      final reason = duplicate.reason('a' * 500);
      expect(utf8.encode(reason), hasLength(123));
      expect(reason, endsWith(' already exists'));
    });

    test('cuts a multi-byte id at a code point boundary', () {
      final reason = duplicate.reason('\u{1F600}' * 100);
      expect(utf8.encode(reason).length, lessThanOrEqualTo(123));
      expect(reason, isNot(contains('�')));
      expect(reason, endsWith('\u{1F600} already exists'));
    });

    test('counts a lone surrogate as the three bytes it is written with', () {
      final reason = duplicate.reason('\uD800' * 100);
      expect(utf8.encode(reason).length, lessThanOrEqualTo(123));
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/websocket/ws_values_test.dart'
```

Expected: `ws_values_test.dart` fails to compile: the new types do not exist.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 4238199..1d18742 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -214,3 +214,5 @@
   gone.
 - `RequestInfo.connectionParams`: the payload of the graphql-ws
   `connection_init` message, for a context factory that reads a token sent there.
+- graphql-ws types: `GraphQLSocket`, `GraphQLWsOptions`, `ConnectionHook`,
+  `AcceptConnection` and `RefuseConnection`, and a first WebSocket guide.
```

Modify `packages/typed_graphql_server/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/dartdoc_options.yaml b/packages/typed_graphql_server/dartdoc_options.yaml
index 2581132..c1ea3fc 100644
--- a/packages/typed_graphql_server/dartdoc_options.yaml
+++ b/packages/typed_graphql_server/dartdoc_options.yaml
@@ -30,6 +30,9 @@ dartdoc:
     subscription:
       markdown: doc/subscriptions.md
       displayName: Subscriptions
+    websocket:
+      markdown: doc/websocket.md
+      displayName: WebSocket
   categoryOrder:
     - authorization
     - builder
@@ -41,4 +44,5 @@ dartdoc:
     - persisted
     - server
     - subscription
+    - websocket
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_server/doc/websocket.md`:

````markdown
# WebSocket

The graphql-ws transport (the `graphql-transport-ws` subprotocol) serves
queries, mutations and subscriptions over one WebSocket connection.

This guide is completed with the handler itself. For now it names the pieces
a host provides and configures: a `GraphQLSocket` over its own WebSocket,
`GraphQLWsOptions` for the limits and the origins it accepts, and a
`ConnectionHook` that decides, from the `connection_init` payload, whether to
acknowledge a connection.

The options have safe defaults:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const options = GraphQLWsOptions();
  print(options.connectionInitTimeout);
  print(options.maxOperations);
  print(options.maxMessageLength);
}
```

It prints:

```text
0:00:03.000000
100
1048576
```
````

Create `packages/typed_graphql_server/lib/src/websocket/connection_decision.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The answer of a `ConnectionHook`: [AcceptConnection] or
/// [RefuseConnection].
///
/// {@category websocket}
sealed class ConnectionDecision {
  const ConnectionDecision();
}

/// The connection may proceed: the server sends `connection_ack`.
///
/// {@category websocket}
final class AcceptConnection extends ConnectionDecision {
  /// Creates the decision; [payload] is the `connection_ack` payload.
  const AcceptConnection({this.payload});

  /// What the acknowledgement carries, null for none.
  final JsonObject? payload;
}

/// The connection is refused: the server closes it with `4403`.
///
/// {@category websocket}
final class RefuseConnection extends ConnectionDecision {
  /// Creates the decision.
  const RefuseConnection();
}
```

Create `packages/typed_graphql_server/lib/src/websocket/connection_hook.dart`:

```dart
import 'dart:async';

import '../server/request_info.dart';
import 'connection_decision.dart';

/// Decides whether a graphql-ws connection is accepted, when its
/// `connection_init` arrives.
///
/// [info] is the upgrade request's, with `RequestInfo.connectionParams` set
/// to the message's payload, so the hook may read a token there (or a header
/// or cookie of the upgrade) and refuse. A throw closes the connection with
/// `4500` and sends the client nothing of the error.
///
/// {@category websocket}
typedef ConnectionHook = FutureOr<ConnectionDecision> Function(
  RequestInfo info,
);
```

Create `packages/typed_graphql_server/lib/src/websocket/duplicate_subscriber.dart`:

```dart
import 'dart:convert';

import 'package:meta/meta.dart';

/// Builds the reason of the `4409` close: a client reused the id of a
/// running operation.
@internal
final class DuplicateSubscriber {
  /// Creates the builder.
  const DuplicateSubscriber();

  /// The WebSocket close code.
  int get code => 4409;

  /// The most UTF-8 bytes a close reason may hold (RFC 6455 section 5.5).
  static const int maxReasonBytes = 123;

  /// `Subscriber for <id> already exists`, with [id] cut at a code point
  /// boundary so that the whole reason fits in [maxReasonBytes] bytes; the
  /// id is cut, not the sentence, so the reason still says what happened.
  String reason(String id) {
    const prefix = 'Subscriber for ';
    const suffix = ' already exists';
    const budget = maxReasonBytes - prefix.length - suffix.length;
    final cut = StringBuffer();
    var bytes = 0;
    for (final rune in id.runes) {
      final character = String.fromCharCode(rune);
      bytes += utf8.encode(character).length;
      if (bytes > budget) {
        break;
      }
      cut.write(character);
    }
    return '$prefix$cut$suffix';
  }
}
```

Create `packages/typed_graphql_server/lib/src/websocket/graphql_socket.dart`:

```dart
/// One WebSocket connection, as the graphql-ws handler sees it; an adapter
/// (for example `typed_graphql_shelf`) implements it over its own WebSocket.
///
/// An adapter must:
///
/// - deliver text frames to [incoming] as they are, and binary frames
///   decoded as UTF-8 (the handler then fails them as JSON and closes
///   `4400`);
/// - complete [incoming] when the connection closes, whoever closed it;
/// - answer WebSocket ping frames and send them for keep-alive: the
///   handler never sends graphql-ws `ping` messages on its own.
///
/// {@category websocket}
abstract interface class GraphQLSocket {
  /// The subprotocol negotiated in the upgrade, null when the client offered
  /// none the host accepted; the handler requires
  /// `GraphQLWsHandler.protocol`.
  String? get protocol;

  /// The text frames the client sends, in order.
  Stream<String> get incoming;

  /// Sends [text] as one text frame, without waiting for the peer: it never
  /// throws, and a frame sent after the connection closed is dropped.
  void send(String text);

  /// Closes the connection with a WebSocket close [code] and [reason] (at
  /// most 123 UTF-8 bytes), completing when it is closed.
  Future<void> close(int code, String reason);
}
```

Create `packages/typed_graphql_server/lib/src/websocket/graphql_ws_options.dart`:

```dart
import 'connection_hook.dart';

/// The limits and hooks of a `GraphQLWsHandler` (R5.7).
///
/// {@category websocket}
final class GraphQLWsOptions {
  /// Creates options; the handler checks that the durations and limits are
  /// positive and that [maxJsonDepth] is supported.
  const GraphQLWsOptions({
    this.connectionInitTimeout = const Duration(seconds: 3),
    this.maxOperations = 100,
    this.maxMessageLength = 1048576,
    this.maxJsonDepth = 64,
    this.maxConnections = 10000,
    this.allowedOrigins,
    this.onConnect,
  });

  /// How long a connection may stay open without being acknowledged; past it
  /// the server closes `4408`.
  final Duration connectionInitTimeout;

  /// The most operations one connection runs at once; a `subscribe` past it
  /// is answered with an `error` message (`GQL432`) and the socket stays open.
  final int maxOperations;

  /// The longest frame accepted, in UTF-16 code units, checked before the
  /// text is parsed; a longer one closes `1009`.
  final int maxMessageLength;

  /// The deepest JSON nesting accepted in a frame (`JsonReader.maxDepth`); a
  /// deeper one closes `4400`.
  final int maxJsonDepth;

  /// The most connections one handler serves at once; past it a new one is
  /// closed `1013`.
  final int maxConnections;

  /// The origins, besides the upgrade's own host, whose WebSocket upgrades
  /// are accepted (exact match, ignoring case); null lists none. A browser
  /// sends cookies with an upgrade, so this is the CSRF defence of the
  /// transport.
  final List<String>? allowedOrigins;

  /// Runs when `connection_init` arrives and decides whether to acknowledge;
  /// null acknowledges every connection.
  final ConnectionHook? onConnect;
}
```

Create `packages/typed_graphql_server/lib/src/websocket/ws_close.dart`:

```dart
import 'package:meta/meta.dart';

/// The WebSocket close codes and fixed reasons of the graphql-ws handler.
///
/// A reason never echoes the client's text (spec M7 §17).
@internal
enum WsClose(
  /// The WebSocket close code.
  final int code,

  /// The reason, a fixed text of at most 123 UTF-8 bytes.
  final String reason,
) {
  /// A message that is not a valid client message (`4400`).
  invalidMessage(4400, 'Invalid message received'),

  /// A `subscribe` before the connection was acknowledged (`4401`).
  unauthorized(4401, 'Unauthorized'),

  /// The connection hook refused, or the Origin did (`4403`).
  forbidden(4403, 'Forbidden'),

  /// The subprotocol is not `graphql-transport-ws` (`4406`).
  subprotocolNotAcceptable(4406, 'Subprotocol not acceptable'),

  /// No acknowledgement within the timeout (`4408`).
  initTimeout(4408, 'Connection initialisation timeout'),

  /// A second `connection_init` (`4429`).
  tooManyInits(4429, 'Too many initialisation requests'),

  /// The connection hook threw (`4500`).
  internalError(4500, 'Internal server error'),

  /// A frame over the length limit (`1009`).
  messageTooBig(1009, 'Message too big'),

  /// More connections than the handler serves (`1013`).
  tryAgainLater(1013, 'Try again later'),
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index 924b3ff..f1ad5ad 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -77,3 +77,7 @@ export 'src/server/server_profile.dart';
 export 'src/server/server_request.dart';
 export 'src/server/server_response.dart';
 export 'src/subscription/subscription_result.dart';
+export 'src/websocket/connection_decision.dart';
+export 'src/websocket/connection_hook.dart';
+export 'src/websocket/graphql_socket.dart';
+export 'src/websocket/graphql_ws_options.dart';
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_server): add the graphql-ws socket and options

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: feat(typed_graphql_server): run the graphql-ws connection handshake

**Why.** The handshake is the state every later message depends on: `connection_init` once, within the timeout, through the hook, before any `subscribe` (spec section 9 table).

**Consumes:** Task 3's reader and writer, Task 4's values.

**Produces:** internal `ConnectionHandshake` and `SocketSession` (ping/pong, `4400`, `4401`, `4403`, `4408`, `4429`, `1009`, `4500` when the hook throws); test support `FakeSocket` and `WsFixture`.

**Files:**

- Create `packages/typed_graphql_server/lib/src/websocket/connection_handshake.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/socket_session.dart`
- Create `packages/typed_graphql_server/test/websocket/socket_handshake_test.dart`
- Create `packages/typed_graphql_server/test/websocket/support/fake_socket.dart`
- Create `packages/typed_graphql_server/test/websocket/support/ws_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/websocket/socket_handshake_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  const quick = GraphQLWsOptions(
    connectionInitTimeout: Duration(milliseconds: 50),
    maxMessageLength: 200,
  );
  final initText = jsonEncode({'type': 'connection_init'});

  group('connection_init', () {
    test('is acknowledged without a hook', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      expect(await fixture.init(socket), {'type': 'connection_ack'});
    });

    test('is acknowledged with the payload the hook accepts with', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => AcceptConnection(
            payload: JsonObject({'welcome': const JsonString('yes')}),
          ),
        ),
      );
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      expect(await fixture.init(socket), {
        'type': 'connection_ack',
        'payload': {'welcome': 'yes'},
      });
    });

    test('gives the hook the connection parameters and the upgrade', () async {
      RequestInfo? seen;
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) {
            seen = info;
            return const AcceptConnection();
          },
        ),
      );
      final socket = FakeSocket();
      unawaited(
        fixture.run(
          socket,
          upgrade: fixture.upgrade(headers: {'Cookie': 'a=b'}),
        ),
      );
      await fixture.init(socket, payload: {'token': 'secret'});
      expect(
        seen?.connectionParams,
        JsonObject({'token': const JsonString('secret')}),
      );
      expect(seen?.header('cookie'), 'a=b');
      expect(seen?.uri, Uri.parse('/graphql'));
    });

    test('is awaited when the hook is asynchronous', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return const AcceptConnection();
          },
        ),
      );
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      expect(await fixture.init(socket), {'type': 'connection_ack'});
    });

    test('closes 4403 when the hook refuses', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => const RefuseConnection(),
        ),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      await done;
      expect([socket.closeCode, socket.closeReason], [4403, 'Forbidden']);
      expect(socket.sent, isEmpty);
    });

    test('closes 4500 when the hook throws', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => throw StateError('database password'),
        ),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      await done;
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4500,
          'Internal server error',
        ],
      );
    });

    test('closes 4429 on a second connection_init', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      final done = fixture.run(socket);
      await fixture.init(socket);
      socket.receive(initText);
      await done;
      expect(socket.closeCode, 4429);
    });

    test('closes 4429 on a second init while the hook is pending', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => Completer<ConnectionDecision>().future,
        ),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      socket.receive(initText);
      await done;
      expect(socket.closeCode, 4429);
    });

    test('sends nothing when the socket closed while the hook ran', () async {
      final pending = Completer<ConnectionDecision>();
      final fixture = WsFixture(
        options: GraphQLWsOptions(onConnect: (info) => pending.future),
      );
      final socket = FakeSocket();
      final done = fixture.run(socket);
      socket.receive(initText);
      socket.receive(initText);
      await done;
      pending.complete(const AcceptConnection());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(socket.sent, isEmpty);
    });
  });

  group('the connection', () {
    test('closes 4408 when no connection_init arrives in time', () async {
      final socket = FakeSocket();
      await WsFixture(options: quick).run(socket);
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4408,
          'Connection initialisation timeout',
        ],
      );
    });

    test('keeps the timer off once acknowledged', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      await fixture.init(socket);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(socket.closeCode, isNull);
    });

    test('closes 4401 on subscribe before the acknowledgement', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      final done = fixture.run(socket);
      fixture.subscribe(socket, '1', '{ hello }');
      await done;
      expect([socket.closeCode, socket.closeReason], [4401, 'Unauthorized']);
      expect(fixture.contexts, 0);
    });

    test('closes 1009 on a frame longer than the limit', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive('x' * 201);
      await done;
      expect([socket.closeCode, socket.closeReason], [1009, 'Message too big']);
    });

    test('closes 4400 on text that is not JSON', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive('not json');
      await done;
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4400,
          'Invalid message received',
        ],
      );
    });

    test('closes 4400 on a type only a server sends', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive(jsonEncode({'type': 'connection_ack'}));
      await done;
      expect(socket.closeCode, 4400);
    });

    test('answers ping with pong echoing the payload', () async {
      final socket = FakeSocket();
      unawaited(WsFixture(options: quick).run(socket));
      socket.receive(
        jsonEncode({
          'type': 'ping',
          'payload': {'n': 1},
        }),
      );
      expect(await socket.nextSent(), {
        'type': 'pong',
        'payload': {'n': 1},
      });
    });

    test('answers ping without a payload with a bare pong', () async {
      final socket = FakeSocket();
      unawaited(WsFixture(options: quick).run(socket));
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
    });

    test('ignores pong', () async {
      final fixture = WsFixture(options: quick);
      final socket = FakeSocket();
      unawaited(fixture.run(socket));
      await fixture.init(socket);
      socket.receive(jsonEncode({'type': 'pong'}));
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.sent, hasLength(2));
    });

    test('ignores frames after it closed and closes once', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      socket.receive('not json');
      socket.receive('more garbage');
      socket.receive(initText);
      await done;
      expect(socket.closeCalls, 1);
      expect(socket.sent, isEmpty);
    });

    test('completes when the socket disconnects', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      await socket.disconnect();
      await done;
      expect(socket.closeCode, isNull);
    });

    test('does not time out after the socket disconnects', () async {
      final socket = FakeSocket();
      final done = WsFixture(options: quick).run(socket);
      await socket.disconnect();
      await done;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(socket.closeCalls, 0);
    });
  });
}
```

Create `packages/typed_graphql_server/test/websocket/support/fake_socket.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// An in-memory [GraphQLSocket] that records what the server sends.
final class FakeSocket implements GraphQLSocket {
  FakeSocket({this.protocol = 'graphql-transport-ws'});

  @override
  final String? protocol;

  final StreamController<String> _incoming = StreamController<String>();
  final Completer<void> _closed = Completer<void>();
  final List<Map<String, Object?>> _sent = [];
  final List<Completer<Map<String, Object?>>> _waiting = [];
  int _read = 0;

  /// The decoded messages the server sent, in order.
  List<Map<String, Object?>> get sent => List.unmodifiable(_sent);

  /// The code of the first close the server asked for; null while open.
  int? closeCode;

  /// The reason of the first close the server asked for; null while open.
  String? closeReason;

  /// How many times the server asked to close.
  int closeCalls = 0;

  /// Completes when the server closes the socket.
  Future<void> get closed => _closed.future;

  @override
  Stream<String> get incoming => _incoming.stream;

  /// Delivers a text frame to the server.
  void receive(String text) => _incoming.add(text);

  /// Ends the incoming frames, as a dropped connection does.
  Future<void> disconnect() => _incoming.close();

  /// The next message the server sends that the test has not read yet.
  Future<Map<String, Object?>> nextSent() {
    if (_read < _sent.length) {
      return Future.value(_sent[_read++]);
    }
    final waiting = Completer<Map<String, Object?>>();
    _waiting.add(waiting);
    return waiting.future;
  }

  @override
  void send(String text) {
    final message = jsonDecode(text) as Map<String, Object?>;
    _sent.add(message);
    if (_waiting.isNotEmpty) {
      _read++;
      _waiting.removeAt(0).complete(message);
    }
  }

  @override
  Future<void> close(int code, String reason) async {
    closeCalls++;
    closeCode ??= code;
    closeReason ??= reason;
    if (!_closed.isCompleted) {
      _closed.complete();
    }
    await _incoming.close();
  }
}
```

Create `packages/typed_graphql_server/test/websocket/support/ws_fixture.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/websocket/socket_session.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../../server/support/server_fixture.dart';
import 'fake_socket.dart';

/// A server fixture with sockets and sessions on top of it.
final class WsFixture {
  WsFixture({this.options = const GraphQLWsOptions()});

  final GraphQLWsOptions options;
  final ServerFixture fixture = ServerFixture();

  /// How many times the context factory ran.
  int contexts = 0;

  /// The connection parameters the context factory saw, per run.
  final List<JsonObject?> seenParams = [];

  /// An upgrade request with [headers].
  RequestInfo upgrade({Map<String, String> headers = const {}}) => RequestInfo(
    method: 'GET',
    uri: Uri.parse('/graphql'),
    headers: headers,
  );

  /// A server whose context factory counts its runs.
  GraphQLServer<Ctx> server() => fixture.server(
    contextFactory: (info) {
      contexts++;
      seenParams.add(info.connectionParams);
      return const Ctx('connection');
    },
  );

  /// A session over [socket]; the future completes when it ends.
  Future<void> run(
    FakeSocket socket, {
    GraphQLServer<Ctx>? server,
    GraphQLWsOptions? options,
    RequestInfo? upgrade,
  }) => SocketSession<Ctx>(
    server: server ?? this.server(),
    options: options ?? this.options,
    socket: socket,
    upgrade: upgrade ?? this.upgrade(),
  ).run();

  /// Sends `connection_init` and waits for the next message.
  Future<Map<String, Object?>> init(
    FakeSocket socket, {
    Map<String, Object?>? payload,
  }) {
    socket.receive(
      jsonEncode({'type': 'connection_init', 'payload': ?payload}),
    );
    return socket.nextSent();
  }

  /// Sends a `subscribe` message.
  void subscribe(FakeSocket socket, String id, String query) => socket.receive(
    jsonEncode({
      'type': 'subscribe',
      'id': id,
      'payload': {'query': query},
    }),
  );
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/websocket/socket_handshake_test.dart'
```

Expected: `socket_handshake_test.dart` fails to compile: `SocketSession` does not exist.

- [ ] **Step 3: Write the implementation.**

Create `packages/typed_graphql_server/lib/src/websocket/connection_handshake.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/request_info.dart';
import 'connection_decision.dart';
import 'graphql_ws_options.dart';

/// The state of one connection until it is acknowledged: the initialisation
/// timer, the connection parameters and the `onConnect` hook.
@internal
final class ConnectionHandshake {
  /// Creates the handshake of a connection upgraded by [upgrade].
  ConnectionHandshake(this.options, this.upgrade);

  /// The options of the handler.
  final GraphQLWsOptions options;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  /// Whether a `connection_init` was received, also one still being decided.
  bool hasInit = false;

  /// Whether `connection_ack` was sent; operations need it.
  bool isAcknowledged = false;

  /// The payload of the `connection_init` message; null until one arrives
  /// or when it carried none.
  JsonObject? connectionParams;

  Timer? _timer;

  /// Calls [onExpired] when the connection is not acknowledged within
  /// `connectionInitTimeout`.
  void startTimer(void Function() onExpired) {
    _timer = Timer(options.connectionInitTimeout, () {
      if (!isAcknowledged) {
        onExpired();
      }
    });
  }

  /// Stops the timer; calling it again is harmless.
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Records the `connection_init` and asks the hook (if any) what to do.
  ///
  /// [hasInit] is set before the hook runs, so a second message that
  /// arrives while the hook is pending is a second initialisation.
  Future<ConnectionDecision> decide(JsonObject? payload) async {
    hasInit = true;
    connectionParams = payload;
    final hook = options.onConnect;
    if (hook == null) {
      return const AcceptConnection();
    }
    return hook(
      RequestInfo(
        method: upgrade.method,
        uri: upgrade.uri,
        headers: upgrade.headers,
        source: upgrade.source,
        connectionParams: payload,
      ),
    );
  }

  /// Marks the connection acknowledged and stops the timer.
  void acknowledge() {
    isAcknowledged = true;
    stopTimer();
  }
}
```

Create `packages/typed_graphql_server/lib/src/websocket/socket_session.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import '../server/request_info.dart';
import 'client_message.dart';
import 'client_message_reader.dart';
import 'connection_decision.dart';
import 'connection_handshake.dart';
import 'graphql_socket.dart';
import 'graphql_ws_options.dart';
import 'server_messages.dart';
import 'ws_close.dart';

/// One graphql-ws connection: reads its frames, answers them and closes the
/// socket on a protocol violation (spec section 9).
@internal
final class SocketSession<C> {
  /// Creates the session of [socket], upgraded by [upgrade].
  SocketSession({
    required this.server,
    required this.options,
    required this.socket,
    required this.upgrade,
  }) : _handshake = ConnectionHandshake(options, upgrade),
       _reader = ClientMessageReader(options.maxJsonDepth);

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The options of the handler.
  final GraphQLWsOptions options;

  /// The connection.
  final GraphQLSocket socket;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  final ConnectionHandshake _handshake;
  final ClientMessageReader _reader;
  final ServerMessages _messages = const ServerMessages();
  final Completer<void> _ended = Completer<void>();
  bool _isClosed = false;

  /// Serves the connection; completes when `incoming` ends or fails.
  Future<void> run() {
    _handshake.startTimer(() => _close(WsClose.initTimeout));
    socket.incoming.listen(
      _onFrame,
      onError: (Object _) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
    return _ended.future;
  }

  void _end() {
    _handshake.stopTimer();
    if (!_ended.isCompleted) {
      _ended.complete();
    }
  }

  void _onFrame(String text) {
    if (_isClosed) {
      return;
    }
    if (text.length > options.maxMessageLength) {
      _close(WsClose.messageTooBig);
      return;
    }
    final message = _reader.read(text);
    switch (message) {
      case null:
        _close(WsClose.invalidMessage);
      case InitMessage(:final payload):
        unawaited(_initialise(payload));
      case PingMessage(:final payload):
        _send(_messages.pong(payload));
      case PongMessage():
        break;
      case SubscribeMessage():
        _subscribe(message);
      case CompleteMessage():
        break;
    }
  }

  Future<void> _initialise(JsonObject? payload) async {
    if (_handshake.hasInit) {
      _close(WsClose.tooManyInits);
      return;
    }
    final ConnectionDecision decision;
    try {
      decision = await _handshake.decide(payload);
    } on Object {
      _close(WsClose.internalError);
      return;
    }
    if (_isClosed) {
      return;
    }
    switch (decision) {
      case AcceptConnection(:final payload):
        _handshake.acknowledge();
        _send(_messages.ack(payload));
      case RefuseConnection():
        _close(WsClose.forbidden);
    }
  }

  void _subscribe(SubscribeMessage message) {
    if (!_handshake.isAcknowledged) {
      _close(WsClose.unauthorized);
    }
  }

  void _send(String text) {
    if (!_isClosed) {
      socket.send(text);
    }
  }

  void _close(WsClose reason) {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    _handshake.stopTimer();
    try {
      socket
          .close(reason.code, reason.reason)
          .then<void>(
            (_) {},
            onError: (Object _) {},
          );
    } on Object {
      // A socket that fails to close is gone already; nothing is left to do.
    }
  }
}
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_server): run the graphql-ws connection handshake

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: feat(typed_graphql_server): run graphql-ws operations

**Why.** Operations are what the transport is for; each one is a `ServerRequest` through the same pipeline as HTTP, cancelled by `complete` or a disconnect, so no resolver outlives the client.

**Consumes:** M6's `GraphQLServer.handle`, `ServerRequest`, `CancelSignal`, `MaskedMessage`; Task 5's session.

**Produces:** internal `SocketOperation<C>` and `SocketOperations<C>` (`4409` for a running id, `GQL432` past `maxOperations`).

**Files:**

- Create `packages/typed_graphql_server/lib/src/websocket/socket_operation.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/socket_operations.dart`
- Modify `packages/typed_graphql_server/lib/src/websocket/socket_session.dart`
- Create `packages/typed_graphql_server/test/websocket/socket_operations_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/websocket/socket_operations_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

/// A schema whose subscription is fed by a controller the test owns.
final class ControlledSource {
  ControlledSource() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('events', b.string)
            .subscribeWith<int>(
              (parent, args, context, info) => controller.stream,
              (event, args, context, info) => 'event $event',
            ),
      ],
    );
    schema = b.build(query: query, subscription: subscription);
  }

  bool isCancelled = false;
  late final StreamController<int> controller = StreamController<int>(
    onCancel: () => isCancelled = true,
  );
  late final ExecutableSchema<Ctx> schema;

  Future<void> close() => controller.close();

  GraphQLServer<Ctx> server() => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory: (_) => const Ctx('source'),
  );
}

void main() {
  const quick = GraphQLWsOptions(
    connectionInitTimeout: Duration(seconds: 5),
    maxOperations: 1,
  );

  Future<FakeSocket> open(
    WsFixture fixture, {
    GraphQLServer<Ctx>? server,
    Map<String, Object?>? params,
  }) async {
    final socket = FakeSocket();
    unawaited(fixture.run(socket, server: server));
    await fixture.init(socket, payload: params);
    return socket;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 80));

  group('subscribe', () {
    test('answers a query with next and complete', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      expect(await socket.nextSent(), {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'hello': 'world'},
        },
      });
      expect(await socket.nextSent(), {'type': 'complete', 'id': '1'});
    });

    test('answers a request error with error and no complete', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ nope }');
      final error = await socket.nextSent();
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(error['type'], 'error');
      expect(error['id'], '1');
      expect(error['payload'], isA<List<Object?>>());
      expect(await socket.nextSent(), {'type': 'pong'});
    });

    test('streams a subscription as next messages then complete', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', 'subscription { ticks }');
      final first = await socket.nextSent();
      final second = await socket.nextSent();
      final last = await socket.nextSent();
      expect(first['payload'], {
        'data': {'ticks': 'tick 1'},
      });
      expect(second['payload'], {
        'data': {'ticks': 'tick 2'},
      });
      expect(last, {'type': 'complete', 'id': '1'});
    });

    test('runs a mutation, which needs a POST', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', 'mutation { bump }');
      expect((await socket.nextSent())['payload'], {
        'data': {'bump': 'bumped'},
      });
    });

    test('lets the context factory read the connection parameters', () async {
      final fixture = WsFixture();
      final socket = await open(fixture, params: {'token': 'secret'});
      fixture.subscribe(socket, '1', '{ tag }');
      await socket.nextSent();
      expect(fixture.seenParams, [
        JsonObject({'token': const JsonString('secret')}),
      ]);
    });

    test('closes 4409 for an id in use', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4409,
          'Subscriber for 1 already exists',
        ],
      );
    });

    test('accepts an id again once its operation completed', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.nextSent();
      await socket.nextSent();
      fixture.subscribe(socket, '1', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
      expect(socket.closeCode, isNull);
    });

    test('answers GQL432 past maxOperations and stays open', () async {
      final fixture = WsFixture(options: quick);
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      fixture.subscribe(socket, '2', '{ hello }');
      final error = await socket.nextSent();
      expect(error['type'], 'error');
      expect(error['id'], '2');
      expect(error['payload'], [
        {
          'message': 'Too many operations are running on this connection.',
          'extensions': {'code': 'GQL432'},
        },
      ]);
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.closeCode, isNull);
    });

    test('frees a slot when an operation completes', () async {
      final fixture = WsFixture(options: quick);
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.nextSent();
      await socket.nextSent();
      fixture.subscribe(socket, '2', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
    });
  });

  group('complete', () {
    test('stops a subscription and its source', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = await open(fixture, server: source.server());
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      source.controller.add(1);
      expect((await socket.nextSent())['payload'], {
        'data': {'events': 'event 1'},
      });
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      await settle();
      expect(source.isCancelled, isTrue);
      expect(socket.sent, hasLength(2));
    });

    test('ignores an unknown id', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      socket.receive(jsonEncode({'type': 'complete', 'id': 'nothing'}));
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.closeCode, isNull);
    });

    test('sends nothing for a query still pending', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      await settle();
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      await settle();
      socket.receive(jsonEncode({'type': 'ping'}));
      expect(await socket.nextSent(), {'type': 'pong'});
      expect(socket.sent, hasLength(2));
    });

    test('frees the id for reuse', () async {
      final fixture = WsFixture();
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      socket.receive(jsonEncode({'type': 'complete', 'id': '1'}));
      fixture.subscribe(socket, '1', '{ hello }');
      expect((await socket.nextSent())['type'], 'next');
      expect(socket.closeCode, isNull);
    });
  });

  group('disconnect', () {
    test('cancels a running subscription', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = FakeSocket();
      final done = fixture.run(socket, server: source.server());
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      await socket.disconnect();
      await done;
      await settle();
      expect(source.isCancelled, isTrue);
    });

    test('cancels the operations when the server closes the socket', () async {
      final source = ControlledSource();
      addTearDown(source.close);
      final fixture = WsFixture();
      final socket = await open(fixture, server: source.server());
      fixture.subscribe(socket, '1', 'subscription { events }');
      await settle();
      socket.receive('not json');
      await socket.closed;
      await settle();
      expect(source.isCancelled, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/websocket/socket_operations_test.dart'
```

Expected: `socket_operations_test.dart` fails to compile: `SocketOperations` does not exist.

- [ ] **Step 3: Write the implementation.**

Create `packages/typed_graphql_server/lib/src/websocket/socket_operation.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../execution/masked_message.dart';
import '../server/graphql_server.dart';
import '../server/server_request.dart';
import '../server/server_response.dart';
import 'server_messages.dart';

/// One `subscribe` of a graphql-ws connection: runs the request through the
/// server and writes its `next`, `error` and `complete` messages.
@internal
final class SocketOperation<C> {
  /// Creates the operation [id]; [send] writes a message to the socket and
  /// [onEnded] tells the registry the operation finished by itself.
  SocketOperation({
    required this.id,
    required this.server,
    required this.request,
    required this.signal,
    required this.send,
    required this.onEnded,
  });

  /// The id the client chose.
  final String id;

  /// The server that runs the request.
  final GraphQLServer<C> server;

  /// The request, carrying [signal].
  final ServerRequest request;

  /// Cancelled when the client completes the operation or disconnects.
  final CancelSignal signal;

  /// Writes a message to the socket.
  final void Function(String text) send;

  /// Called once when the operation ends without being cancelled.
  final void Function(SocketOperation<C> operation) onEnded;

  final ServerMessages _messages = const ServerMessages();
  StreamSubscription<ExecutionResult>? _subscription;
  bool _isCancelled = false;

  /// Runs the request and sends what it produces.
  Future<void> run() async {
    final ServerResponse response;
    try {
      response = await server.handle(request);
    } on Object {
      // The server reports its own failures as responses; this guards the
      // socket against a bug there without leaking its text.
      _sendUnexpected();
      return;
    }
    if (_isCancelled) {
      _discard(response);
      return;
    }
    switch (response) {
      case SingleResponse(:final payload):
        _sendSingle(payload);
      case StreamResponse(:final results):
        _forward(results);
    }
  }

  /// Stops the operation and sends nothing more for it.
  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _subscription?.cancel().ignore();
    signal.cancel();
  }

  // A stream that arrives after `complete` was never wanted: listening and
  // cancelling lets its source release what it holds.
  void _discard(ServerResponse response) {
    if (response case StreamResponse(:final results)) {
      results.listen(null).cancel().ignore();
    }
  }

  void _sendSingle(ResponsePayload payload) {
    switch (payload) {
      case ExecutionResult():
        send(_messages.next(id, payload));
        send(_messages.complete(id));
      case RequestErrorResult(:final errors):
        send(_messages.error(id, errors));
    }
    onEnded(this);
  }

  void _forward(Stream<ExecutionResult> results) {
    _subscription = results.listen(
      (result) => send(_messages.next(id, result)),
      onError: (Object _) => _sendUnexpected(),
      onDone: () {
        send(_messages.complete(id));
        onEnded(this);
      },
      cancelOnError: true,
    );
  }

  void _sendUnexpected() {
    if (!_isCancelled) {
      send(
        _messages.error(id, [
          GraphQLError(
            const MaskedMessage().text,
            extensions: JsonObject({
              'code': JsonString(DiagnosticCode.unexpectedError.id),
            }),
          ),
        ]),
      );
    }
    onEnded(this);
  }
}
```

Create `packages/typed_graphql_server/lib/src/websocket/socket_operations.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import '../server/graphql_server.dart';
import '../server/request_info.dart';
import '../server/server_request.dart';
import 'client_message.dart';
import 'socket_operation.dart';

/// The operations a graphql-ws connection is running, by id.
@internal
final class SocketOperations<C> {
  /// Creates an empty registry for the connection upgraded by [upgrade].
  SocketOperations({
    required this.server,
    required this.upgrade,
    required this.maxOperations,
    required this.send,
  });

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The upgrade request the connection came on.
  final RequestInfo upgrade;

  /// How many operations may run at once.
  final int maxOperations;

  /// Writes a message to the socket.
  final void Function(String text) send;

  final Map<String, SocketOperation<C>> _running = {};

  /// How many operations are running.
  int get length => _running.length;

  /// Whether an operation with [id] is running.
  bool contains(String id) => _running.containsKey(id);

  /// Whether [maxOperations] operations are running.
  bool get isFull => _running.length >= maxOperations;

  /// Registers and starts the operation of [message].
  ///
  /// Each message gets a `POST` with the upgrade's headers and a JSON
  /// content type, so the mutation guard and the CSRF rule see an ordinary
  /// request; the Origin check on the upgrade is what protects them
  /// (spec section 9).
  void start(SubscribeMessage message, JsonObject? connectionParams) {
    final signal = CancelSignal();
    final operation = SocketOperation<C>(
      id: message.id,
      server: server,
      request: ServerRequest(
        params: message.request,
        info: RequestInfo(
          method: 'POST',
          uri: upgrade.uri,
          headers: {...upgrade.headers, 'content-type': 'application/json'},
          source: upgrade.source,
          connectionParams: connectionParams,
        ),
        cancelSignal: signal,
      ),
      signal: signal,
      send: send,
      onEnded: _remove,
    );
    _running[message.id] = operation;
    unawaited(operation.run());
  }

  /// Cancels the operation [id] and frees the id; an unknown id is ignored.
  void cancel(String id) => _running.remove(id)?.cancel();

  /// Cancels every operation.
  void cancelAll() {
    final operations = _running.values.toList();
    _running.clear();
    for (final operation in operations) {
      operation.cancel();
    }
  }

  // The id may already belong to a newer operation after a `complete`.
  void _remove(SocketOperation<C> operation) {
    if (identical(_running[operation.id], operation)) {
      _running.remove(operation.id);
    }
  }
}
```

Modify `packages/typed_graphql_server/lib/src/websocket/socket_session.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/websocket/socket_session.dart b/packages/typed_graphql_server/lib/src/websocket/socket_session.dart
index bc53c45..d56690b 100644
--- a/packages/typed_graphql_server/lib/src/websocket/socket_session.dart
+++ b/packages/typed_graphql_server/lib/src/websocket/socket_session.dart
@@ -9,9 +9,11 @@ import 'client_message.dart';
 import 'client_message_reader.dart';
 import 'connection_decision.dart';
 import 'connection_handshake.dart';
+import 'duplicate_subscriber.dart';
 import 'graphql_socket.dart';
 import 'graphql_ws_options.dart';
 import 'server_messages.dart';
+import 'socket_operations.dart';
 import 'ws_close.dart';
 
 /// One graphql-ws connection: reads its frames, answers them and closes the
@@ -25,7 +27,14 @@ final class SocketSession<C> {
     required this.socket,
     required this.upgrade,
   }) : _handshake = ConnectionHandshake(options, upgrade),
-       _reader = ClientMessageReader(options.maxJsonDepth);
+       _reader = ClientMessageReader(options.maxJsonDepth) {
+    _operations = SocketOperations<C>(
+      server: server,
+      upgrade: upgrade,
+      maxOperations: options.maxOperations,
+      send: _send,
+    );
+  }
 
   /// The server that runs the operations.
   final GraphQLServer<C> server;
@@ -41,6 +50,8 @@ final class SocketSession<C> {
 
   final ConnectionHandshake _handshake;
   final ClientMessageReader _reader;
+  // Set by the constructor body, which needs `_send` of this instance.
+  late final SocketOperations<C> _operations;
   final ServerMessages _messages = const ServerMessages();
   final Completer<void> _ended = Completer<void>();
   bool _isClosed = false;
@@ -59,6 +70,7 @@ final class SocketSession<C> {
 
   void _end() {
     _handshake.stopTimer();
+    _operations.cancelAll();
     if (!_ended.isCompleted) {
       _ended.complete();
     }
@@ -84,8 +96,8 @@ final class SocketSession<C> {
         break;
       case SubscribeMessage():
         _subscribe(message);
-      case CompleteMessage():
-        break;
+      case CompleteMessage(:final id):
+        _operations.cancel(id);
     }
   }
 
@@ -116,24 +128,41 @@ final class SocketSession<C> {
   void _subscribe(SubscribeMessage message) {
     if (!_handshake.isAcknowledged) {
       _close(WsClose.unauthorized);
+    } else if (_operations.contains(message.id)) {
+      const duplicate = DuplicateSubscriber();
+      _closeWith(duplicate.code, duplicate.reason(message.id));
+    } else if (_operations.isFull) {
+      _send(_messages.error(message.id, [_tooManyOperations()]));
+    } else {
+      _operations.start(message, _handshake.connectionParams);
     }
   }
 
+  GraphQLError _tooManyOperations() => GraphQLError(
+    'Too many operations are running on this connection.',
+    extensions: JsonObject({
+      'code': JsonString(DiagnosticCode.tooManySocketOperations.id),
+    }),
+  );
+
   void _send(String text) {
     if (!_isClosed) {
       socket.send(text);
     }
   }
 
-  void _close(WsClose reason) {
+  void _close(WsClose reason) => _closeWith(reason.code, reason.reason);
+
+  void _closeWith(int code, String reason) {
     if (_isClosed) {
       return;
     }
     _isClosed = true;
     _handshake.stopTimer();
+    _operations.cancelAll();
     try {
       socket
-          .close(reason.code, reason.reason)
+          .close(code, reason)
           .then<void>(
             (_) {},
             onError: (Object _) {},
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_server): run graphql-ws operations

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 7: feat(typed_graphql_server): add GraphQLWsHandler

**Why.** The handler is what an adapter calls: it checks the subprotocol and the connection count, and its `allowsUpgrade` holds the Origin policy a host must apply before upgrading (a browser sends cookies with an upgrade).

**Consumes:** Task 5's session, Task 4's options.

**Produces:** `GraphQLWsHandler<C>` (`protocol`, `allowsUpgrade(info)`, `serve(socket, info)`), internal `OriginPolicy`.

**Files:**

- Create `packages/typed_graphql_server/lib/src/websocket/graphql_ws_handler.dart`
- Create `packages/typed_graphql_server/lib/src/websocket/origin_policy.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Create `packages/typed_graphql_server/test/websocket/graphql_ws_handler_test.dart`
- Modify `packages/typed_graphql_server/test/websocket/support/fake_socket.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/websocket/graphql_ws_handler_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  RequestInfo upgrade(Map<String, String> headers) => RequestInfo(
    method: 'GET',
    uri: Uri.parse('/graphql'),
    headers: headers,
  );

  group('allowsUpgrade', () {
    final fixture = WsFixture();
    final handler = GraphQLWsHandler(
      fixture.server(),
      options: const GraphQLWsOptions(allowedOrigins: ['https://App.Example']),
    );

    bool allows(Map<String, String> headers) =>
        handler.allowsUpgrade(upgrade(headers));

    test('passes an upgrade with no origin', () {
      expect(allows({'host': 'api.example'}), isTrue);
    });

    test('passes the origin of the same host', () {
      expect(
        allows({'origin': 'https://api.example', 'host': 'api.example'}),
        isTrue,
      );
    });

    test('compares the host ignoring case', () {
      expect(
        allows({'origin': 'https://API.example', 'host': 'api.EXAMPLE'}),
        isTrue,
      );
    });

    test('passes a default port the origin leaves out', () {
      expect(
        allows({'origin': 'https://api.example:443', 'host': 'api.example'}),
        isTrue,
      );
    });

    test('refuses the same host on another port', () {
      expect(
        allows({'origin': 'http://api.example:8080', 'host': 'api.example'}),
        isFalse,
      );
    });

    test('refuses another host', () {
      expect(
        allows({'origin': 'https://evil.example', 'host': 'api.example'}),
        isFalse,
      );
    });

    test('passes a listed origin ignoring case', () {
      expect(
        allows({'origin': 'https://app.example', 'host': 'api.example'}),
        isTrue,
      );
    });

    test('refuses the literal null origin', () {
      expect(allows({'origin': 'null', 'host': 'api.example'}), isFalse);
    });

    test('refuses an origin that is not a URI', () {
      expect(allows({'origin': 'a b:%%', 'host': 'api.example'}), isFalse);
    });

    test('refuses an origin with no host', () {
      expect(allows({'origin': 'garbage', 'host': 'garbage'}), isFalse);
    });

    test('refuses an origin when the host header is missing', () {
      expect(allows({'origin': 'https://api.example'}), isFalse);
    });
  });

  group('serve', () {
    test('closes 4406 for another subprotocol', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket(protocol: 'graphql-ws');
      await handler.serve(socket, fixture.upgrade());
      expect(
        [socket.closeCode, socket.closeReason],
        [
          4406,
          'Subprotocol not acceptable',
        ],
      );
    });

    test('closes 4406 when no subprotocol was negotiated', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket(protocol: null);
      await handler.serve(socket, fixture.upgrade());
      expect(socket.closeCode, 4406);
    });

    test('closes 4403 for a foreign origin', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket();
      await handler.serve(
        socket,
        fixture.upgrade(
          headers: {'origin': 'https://evil.example', 'host': 'api.example'},
        ),
      );
      expect([socket.closeCode, socket.closeReason], [4403, 'Forbidden']);
    });

    test('closes 1013 past maxConnections and keeps the first', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(
        fixture.server(),
        options: const GraphQLWsOptions(maxConnections: 1),
      );
      final first = FakeSocket();
      final firstDone = handler.serve(first, fixture.upgrade());
      final second = FakeSocket();
      await handler.serve(second, fixture.upgrade());
      expect([second.closeCode, second.closeReason], [1013, 'Try again later']);
      first.receive(jsonEncode({'type': 'ping'}));
      expect(await first.nextSent(), {'type': 'pong'});
      await first.disconnect();
      await firstDone;
    });

    test('takes a connection again once one ended', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(
        fixture.server(),
        options: const GraphQLWsOptions(maxConnections: 1),
      );
      final first = FakeSocket();
      final firstDone = handler.serve(first, fixture.upgrade());
      await first.disconnect();
      await firstDone;
      final second = FakeSocket();
      unawaited(handler.serve(second, fixture.upgrade()));
      second.receive(jsonEncode({'type': 'ping'}));
      expect(await second.nextSent(), {'type': 'pong'});
    });

    test('serves init, subscribe, next and complete', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      final socket = FakeSocket();
      unawaited(handler.serve(socket, fixture.upgrade()));
      expect(await fixture.init(socket), {'type': 'connection_ack'});
      fixture.subscribe(socket, '7', '{ hello }');
      expect(await socket.nextSent(), {
        'type': 'next',
        'id': '7',
        'payload': {
          'data': {'hello': 'world'},
        },
      });
      expect(await socket.nextSent(), {'type': 'complete', 'id': '7'});
    });

    test('does not throw when the socket cannot be closed', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler(fixture.server());
      await handler.serve(ThrowingSocket(), fixture.upgrade());
    });
  });

  group('constructor', () {
    final server = WsFixture().server();

    void rejects(GraphQLWsOptions options) => expect(
      () => GraphQLWsHandler(server, options: options),
      throwsArgumentError,
    );

    test('rejects a zero init timeout', () {
      rejects(const GraphQLWsOptions(connectionInitTimeout: Duration.zero));
    });

    test('rejects zero operations', () {
      rejects(const GraphQLWsOptions(maxOperations: 0));
    });

    test('rejects a zero message length', () {
      rejects(const GraphQLWsOptions(maxMessageLength: 0));
    });

    test('rejects zero connections', () {
      rejects(const GraphQLWsOptions(maxConnections: 0));
    });

    test('rejects a zero JSON depth', () {
      rejects(const GraphQLWsOptions(maxJsonDepth: 0));
    });

    test('rejects a JSON depth past the reader limit', () {
      rejects(const GraphQLWsOptions(maxJsonDepth: 1001));
    });

    test('accepts the default options', () {
      expect(
        GraphQLWsHandler(server).options.maxOperations,
        const GraphQLWsOptions().maxOperations,
      );
    });
  });
}

/// A socket whose close always fails.
final class ThrowingSocket implements GraphQLSocket {
  @override
  String? get protocol => 'other';

  @override
  Stream<String> get incoming => const Stream<String>.empty();

  @override
  void send(String text) {}

  @override
  Future<void> close(int code, String reason) =>
      throw StateError('already closed');
}
```

Modify `packages/typed_graphql_server/test/websocket/support/fake_socket.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/websocket/support/fake_socket.dart b/packages/typed_graphql_server/test/websocket/support/fake_socket.dart
index 8d3f601..ecf9b3a 100644
--- a/packages/typed_graphql_server/test/websocket/support/fake_socket.dart
+++ b/packages/typed_graphql_server/test/websocket/support/fake_socket.dart
@@ -68,6 +68,7 @@ final class FakeSocket implements GraphQLSocket {
     if (!_closed.isCompleted) {
       _closed.complete();
     }
-    await _incoming.close();
+    // Not awaited: with no listener the controller's close never completes.
+    unawaited(_incoming.close());
   }
 }
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/websocket/graphql_ws_handler_test.dart'
```

Expected: `graphql_ws_handler_test.dart` fails to compile: `GraphQLWsHandler` does not exist.

- [ ] **Step 3: Write the implementation.**

Create `packages/typed_graphql_server/lib/src/websocket/graphql_ws_handler.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../server/graphql_server.dart';
import '../server/request_info.dart';
import 'graphql_socket.dart';
import 'graphql_ws_options.dart';
import 'origin_policy.dart';
import 'socket_session.dart';
import 'ws_close.dart';

/// Serves the `graphql-transport-ws` protocol of the graphql-ws library over
/// a [GraphQLSocket], running each operation through a [GraphQLServer].
///
/// The handler knows nothing of HTTP: a host accepts the upgrade, wraps the
/// connection in a [GraphQLSocket] and calls [serve].
///
/// {@category websocket}
final class GraphQLWsHandler<C> {
  /// Creates a handler for [server].
  ///
  /// Throws an [ArgumentError] when a duration or a limit in [options] is
  /// not positive or `maxJsonDepth` is outside `1` to
  /// [JsonReader.maxSupportedDepth].
  GraphQLWsHandler(
    this.server, {
    this.options = const GraphQLWsOptions(),
  }) : _origins = OriginPolicy(options.allowedOrigins) {
    _check(options);
  }

  /// The WebSocket subprotocol this handler speaks.
  static const String protocol = 'graphql-transport-ws';

  /// The server that runs the operations.
  final GraphQLServer<C> server;

  /// The limits and hooks of this handler.
  final GraphQLWsOptions options;

  final OriginPolicy _origins;
  int _openSessions = 0;

  /// Whether [upgrade] may become a connection, judged by its `Origin`.
  ///
  /// A host calls this before upgrading and answers `403` when it is false;
  /// [serve] checks again (defence in depth). An upgrade with no `Origin`
  /// is not from a browser and passes; so does one whose `Origin` has the
  /// host of its `Host` header or is in `allowedOrigins`.
  bool allowsUpgrade(RequestInfo upgrade) => _origins.allows(upgrade);

  /// Serves [socket], upgraded by [upgrade], until it closes.
  ///
  /// Never throws: a refusal or a failure closes the socket with a code.
  Future<void> serve(GraphQLSocket socket, RequestInfo upgrade) async {
    try {
      final refusal = _refusal(socket, upgrade);
      if (refusal != null) {
        await socket.close(refusal.code, refusal.reason);
        return;
      }
      _openSessions++;
      try {
        await SocketSession<C>(
          server: server,
          options: options,
          socket: socket,
          upgrade: upgrade,
        ).run();
      } finally {
        _openSessions--;
      }
    } on Object {
      await _closeAfterFailure(socket);
    }
  }

  WsClose? _refusal(GraphQLSocket socket, RequestInfo upgrade) {
    if (_openSessions >= options.maxConnections) {
      return WsClose.tryAgainLater;
    }
    if (socket.protocol != protocol) {
      return WsClose.subprotocolNotAcceptable;
    }
    return allowsUpgrade(upgrade) ? null : WsClose.forbidden;
  }

  Future<void> _closeAfterFailure(GraphQLSocket socket) async {
    try {
      await socket.close(
        WsClose.internalError.code,
        WsClose.internalError.reason,
      );
    } on Object {
      // The socket is gone; nothing is left to tell the client.
    }
  }

  static void _check(GraphQLWsOptions options) {
    _positive(
      'connectionInitTimeout',
      options.connectionInitTimeout,
      options.connectionInitTimeout > .zero,
    );
    _positive(
      'maxOperations',
      options.maxOperations,
      options.maxOperations > 0,
    );
    _positive(
      'maxMessageLength',
      options.maxMessageLength,
      options.maxMessageLength > 0,
    );
    _positive(
      'maxConnections',
      options.maxConnections,
      options.maxConnections > 0,
    );
    if (options.maxJsonDepth < 1 ||
        options.maxJsonDepth > JsonReader.maxSupportedDepth) {
      throw ArgumentError.value(
        options.maxJsonDepth,
        'maxJsonDepth',
        'must be between 1 and JsonReader.maxSupportedDepth',
      );
    }
  }

  static void _positive(String name, Object value, bool isPositive) {
    if (!isPositive) {
      throw ArgumentError.value(value, name, 'must be positive');
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/websocket/origin_policy.dart`:

```dart
import 'package:meta/meta.dart';

import '../server/request_info.dart';

/// Decides whether a WebSocket upgrade may proceed, from its `Origin`.
///
/// A browser sends cookies with an upgrade and no preflight, so a page on
/// another site could open an authenticated socket; checking the origin is
/// the defence against that cross-site hijacking (spec section 9).
@internal
final class OriginPolicy {
  /// Creates a policy that also allows the exact origins in [allowedOrigins].
  const OriginPolicy(this.allowedOrigins);

  /// The origins allowed besides the host's own, compared ignoring case.
  final List<String>? allowedOrigins;

  /// Whether [upgrade] has no `Origin`, the host's own or a listed one.
  bool allows(RequestInfo upgrade) {
    final origin = upgrade.header('origin');
    if (origin == null) {
      return true;
    }
    // A sandboxed frame or a redirect sends the literal `null`; it names no
    // site, so no host comparison can vouch for it.
    if (origin.toLowerCase() == 'null') {
      return false;
    }
    return _isListed(origin) || _isSameHost(origin, upgrade.header('host'));
  }

  bool _isListed(String origin) {
    final lowered = origin.toLowerCase();
    return allowedOrigins?.any((listed) => listed.toLowerCase() == lowered) ??
        false;
  }

  bool _isSameHost(String origin, String? host) {
    final uri = Uri.tryParse(origin);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty || host == null) {
      return false;
    }
    // `Uri` drops the default port of the scheme from the authority.
    return uri.authority.toLowerCase() == host.toLowerCase();
  }
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index f1ad5ad..a91a345 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -80,4 +80,5 @@ export 'src/subscription/subscription_result.dart';
 export 'src/websocket/connection_decision.dart';
 export 'src/websocket/connection_hook.dart';
 export 'src/websocket/graphql_socket.dart';
+export 'src/websocket/graphql_ws_handler.dart';
 export 'src/websocket/graphql_ws_options.dart';
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_server): add GraphQLWsHandler

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 8: test(typed_graphql_server): add the graphql-ws hostile-input tests

**Why.** Spec section 14 lists what a hostile client does to a socket; each item is a test that asserts the close code or message and that no resolver keeps running. Writing them found one defect, fixed here: a connection that ended while a slow `onConnect` hook was pending was still sent `connection_ack` when the hook returned, so an ended session is now closed for good. `ControlledSource` moves to `test/websocket/support/` so both test files share it.

**Consumes:** Tasks 5-7.

**Produces:** `test/websocket/hostile_websocket_test.dart` (28 tests), `test/websocket/support/controlled_source.dart`; the `SocketSession._end` fix.

**Files:**

- Modify `packages/typed_graphql_server/lib/src/websocket/socket_session.dart`
- Create `packages/typed_graphql_server/test/websocket/hostile_websocket_test.dart`
- Modify `packages/typed_graphql_server/test/websocket/socket_operations_test.dart`
- Create `packages/typed_graphql_server/test/websocket/support/controlled_source.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/websocket/hostile_websocket_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/controlled_source.dart';
import 'support/fake_socket.dart';
import 'support/ws_fixture.dart';

void main() {
  const patient = GraphQLWsOptions(
    connectionInitTimeout: Duration(seconds: 5),
  );
  const oneConnection = GraphQLWsOptions(
    connectionInitTimeout: Duration(seconds: 5),
    maxConnections: 1,
  );

  Future<FakeSocket> open(WsFixture fixture) async {
    final socket = FakeSocket();
    unawaited(fixture.run(socket));
    await fixture.init(socket);
    return socket;
  }

  FakeSocket start(WsFixture fixture) {
    final socket = FakeSocket();
    unawaited(fixture.run(socket));
    return socket;
  }

  void expectClosed(FakeSocket socket, int code, String reason) {
    expect(socket.closeCode, code);
    expect(socket.closeReason, reason);
    expect(socket.closeCalls, 1);
  }

  group('before the connection is acknowledged', () {
    test('subscribe before init closes 4401 and runs nothing', () async {
      final fixture = WsFixture(options: patient);
      final socket = start(fixture);
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expectClosed(socket, 4401, 'Unauthorized');
      expect(fixture.contexts, 0);
      expect(socket.sent, isEmpty);
    });

    test('a second init closes 4429', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      socket.receive(jsonEncode({'type': 'connection_init'}));
      await socket.closed;
      expectClosed(socket, 4429, 'Too many initialisation requests');
    });

    test('no init closes 4408 after the timeout', () async {
      final fixture = WsFixture(
        options: const GraphQLWsOptions(
          connectionInitTimeout: Duration(milliseconds: 30),
        ),
      );
      final socket = start(fixture);
      await socket.closed;
      expectClosed(socket, 4408, 'Connection initialisation timeout');
      expect(fixture.contexts, 0);
    });

    test('a throwing onConnect closes 4500 without its message', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) => throw StateError('secret database password'),
        ),
      );
      final socket = start(fixture);
      socket.receive(jsonEncode({'type': 'connection_init'}));
      await socket.closed;
      expectClosed(socket, 4500, 'Internal server error');
      expect(socket.sent, isEmpty);
    });

    test('an asynchronously throwing onConnect closes 4500', () async {
      final fixture = WsFixture(
        options: GraphQLWsOptions(
          onConnect: (info) async => throw const UnprintableError(),
        ),
      );
      final socket = start(fixture);
      socket.receive(jsonEncode({'type': 'connection_init'}));
      await socket.closed;
      expectClosed(socket, 4500, 'Internal server error');
    });

    test(
      'a connection dropped while onConnect is pending is not acked',
      () async {
        final decision = Completer<ConnectionDecision>();
        final fixture = WsFixture(
          options: GraphQLWsOptions(onConnect: (info) => decision.future),
        );
        final socket = FakeSocket();
        final ended = fixture.run(socket);
        socket.receive(jsonEncode({'type': 'connection_init'}));
        await socket.disconnect();
        await ended;
        decision.complete(const AcceptConnection());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(socket.sent, isEmpty);
      },
    );
  });

  group('unreadable frames', () {
    Future<void> expectInvalid(String frame) async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      socket.receive(frame);
      await socket.closed;
      expectClosed(socket, 4400, 'Invalid message received');
      expect(fixture.contexts, 0);
    }

    test('malformed JSON closes 4400', () => expectInvalid('{"type":'));

    test('JSON nested 100,000 deep closes 4400 quickly', () async {
      final deep = '${'[' * 100000}${']' * 100000}';
      final watch = Stopwatch()..start();
      await expectInvalid(deep);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a payload nested 100,000 deep closes 4400', () async {
      final deep = '${'{"a":' * 100000}1${'}' * 100000}';
      await expectInvalid('{"type":"connection_init","payload":$deep}');
    });

    test('an unknown type closes 4400', () => expectInvalid('{"type":"x"}'));

    test('a message without a type closes 4400', () => expectInvalid('{}'));

    test('next from the client closes 4400', () async {
      await expectInvalid('{"type":"next","id":"1","payload":{}}');
    });

    test('error from the client closes 4400', () async {
      await expectInvalid('{"type":"error","id":"1","payload":[]}');
    });

    test('connection_ack from the client closes 4400', () async {
      await expectInvalid('{"type":"connection_ack"}');
    });

    test('a subscribe without an id closes 4400', () async {
      await expectInvalid('{"type":"subscribe","payload":{"query":"{a}"}}');
    });

    test('an oversized frame closes 1009', () async {
      final fixture = WsFixture(
        options: const GraphQLWsOptions(
          connectionInitTimeout: Duration(seconds: 5),
          maxMessageLength: 64,
        ),
      );
      final socket = await open(fixture);
      socket.receive(
        jsonEncode({
          'type': 'subscribe',
          'id': '1',
          'payload': {'query': '{ hello ${' ' * 100} }'},
        }),
      );
      await socket.closed;
      expectClosed(socket, 1009, 'Message too big');
      expect(fixture.contexts, 0);
    });

    test('frames after a close are ignored', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      socket.receive('garbage');
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(socket.closeCalls, 1);
      expect(fixture.contexts, 0);
    });
  });

  group('operations', () {
    test('a duplicate id closes 4409', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      fixture.subscribe(socket, '1', '{ slow }');
      fixture.subscribe(socket, '1', '{ hello }');
      await socket.closed;
      expectClosed(socket, 4409, 'Subscriber for 1 already exists');
      expect(fixture.contexts, 1);
    });

    test('10,000 subscribes past the limit are answered by errors', () async {
      final fixture = WsFixture(
        options: const GraphQLWsOptions(
          connectionInitTimeout: Duration(seconds: 5),
          maxOperations: 5,
        ),
      );
      final socket = await open(fixture);
      for (var i = 0; i < 10000; i++) {
        fixture.subscribe(socket, 'op$i', '{ slow }');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final errors = socket.sent.where((m) => m['type'] == 'error').toList();
      expect(errors, hasLength(9995));
      expect(errors.first['payload'], [
        {
          'message': 'Too many operations are running on this connection.',
          'extensions': {'code': 'GQL432'},
        },
      ]);
      // Only the five that fit were started, so the registry never grew past
      // the limit.
      expect(fixture.contexts, 5);
      expect(socket.closeCalls, 0);
      socket.receive(jsonEncode({'type': 'ping'}));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(socket.sent.last['type'], 'pong');
    });

    test('10,000 pings are answered one for one', () async {
      final fixture = WsFixture(options: patient);
      final socket = await open(fixture);
      for (var i = 0; i < 10000; i++) {
        socket.receive(
          jsonEncode({
            'type': 'ping',
            'payload': {'n': i},
          }),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final pongs = socket.sent.where((m) => m['type'] == 'pong').toList();
      expect(pongs, hasLength(10000));
      expect(pongs.last['payload'], {'n': 9999});
    });

    test('a disconnect mid-subscription cancels the source', () async {
      final source = ControlledSource();
      final fixture = WsFixture(options: patient);
      final socket = FakeSocket();
      final ended = fixture.run(socket, server: source.server());
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      source.controller.add(1);
      expect((await socket.nextSent())['type'], 'next');
      await socket.disconnect();
      await ended;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.isCancelled, isTrue);
    });

    test('a close by the server cancels the source', () async {
      final source = ControlledSource();
      final fixture = WsFixture(options: patient);
      final socket = FakeSocket();
      unawaited(fixture.run(socket, server: source.server()));
      await fixture.init(socket);
      fixture.subscribe(socket, '1', 'subscription { events }');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      socket.receive('garbage');
      await socket.closed;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.isCancelled, isTrue);
    });
  });

  group('the handler', () {
    RequestInfo upgrade(Map<String, String> headers) => RequestInfo(
      method: 'GET',
      uri: Uri.parse('/graphql'),
      headers: headers,
    );

    test('a foreign Origin closes 4403 and runs nothing', () async {
      final fixture = WsFixture(options: patient);
      final handler = GraphQLWsHandler<Ctx>(fixture.server());
      final socket = FakeSocket();
      await handler.serve(
        socket,
        upgrade({'origin': 'https://evil.example', 'host': 'api.example'}),
      );
      expectClosed(socket, 4403, 'Forbidden');
      expect(fixture.contexts, 0);
    });

    test('a wrong subprotocol closes 4406', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(fixture.server());
      final socket = FakeSocket(protocol: 'graphql-ws');
      await handler.serve(socket, fixture.upgrade());
      expectClosed(socket, 4406, 'Subprotocol not acceptable');
    });

    test('a missing subprotocol closes 4406', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(fixture.server());
      final socket = FakeSocket(protocol: null);
      await handler.serve(socket, fixture.upgrade());
      expectClosed(socket, 4406, 'Subprotocol not acceptable');
    });

    test('more sockets than maxConnections close 1013', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(
        fixture.server(),
        options: oneConnection,
      );
      final first = FakeSocket();
      unawaited(handler.serve(first, fixture.upgrade()));
      final extra = <FakeSocket>[];
      for (var i = 0; i < 50; i++) {
        final socket = FakeSocket();
        extra.add(socket);
        await handler.serve(socket, fixture.upgrade());
      }
      for (final socket in extra) {
        expectClosed(socket, 1013, 'Try again later');
      }
      first.receive(jsonEncode({'type': 'connection_init'}));
      expect((await first.nextSent())['type'], 'connection_ack');
      await first.disconnect();
    });

    test('a slot is freed when its socket ends', () async {
      final fixture = WsFixture();
      final handler = GraphQLWsHandler<Ctx>(
        fixture.server(),
        options: oneConnection,
      );
      final first = FakeSocket();
      final served = handler.serve(first, fixture.upgrade());
      await first.disconnect();
      await served;
      final second = FakeSocket();
      unawaited(handler.serve(second, fixture.upgrade()));
      second.receive(jsonEncode({'type': 'connection_init'}));
      expect((await second.nextSent())['type'], 'connection_ack');
      await second.disconnect();
    });
  });
}
```

Modify `packages/typed_graphql_server/test/websocket/socket_operations_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/websocket/socket_operations_test.dart b/packages/typed_graphql_server/test/websocket/socket_operations_test.dart
index 350ec70..638aec9 100644
--- a/packages/typed_graphql_server/test/websocket/socket_operations_test.dart
+++ b/packages/typed_graphql_server/test/websocket/socket_operations_test.dart
@@ -6,45 +6,10 @@ import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
 import '../server/support/server_fixture.dart';
+import 'support/controlled_source.dart';
 import 'support/fake_socket.dart';
 import 'support/ws_fixture.dart';
 
-/// A schema whose subscription is fed by a controller the test owns.
-final class ControlledSource {
-  ControlledSource() {
-    final b = ExecutableSchemaBuilder<Ctx>();
-    final query = b.object<Object?>(
-      'Query',
-      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
-    );
-    final subscription = b.object<Object?>(
-      'Subscription',
-      fields: (t) => [
-        t
-            .field('events', b.string)
-            .subscribeWith<int>(
-              (parent, args, context, info) => controller.stream,
-              (event, args, context, info) => 'event $event',
-            ),
-      ],
-    );
-    schema = b.build(query: query, subscription: subscription);
-  }
-
-  bool isCancelled = false;
-  late final StreamController<int> controller = StreamController<int>(
-    onCancel: () => isCancelled = true,
-  );
-  late final ExecutableSchema<Ctx> schema;
-
-  Future<void> close() => controller.close();
-
-  GraphQLServer<Ctx> server() => GraphQLServer<Ctx>(
-    schema: schema,
-    contextFactory: (_) => const Ctx('source'),
-  );
-}
-
 void main() {
   const quick = GraphQLWsOptions(
     connectionInitTimeout: Duration(seconds: 5),
```

Create `packages/typed_graphql_server/test/websocket/support/controlled_source.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../../server/support/server_fixture.dart';

/// A schema whose subscription is fed by a controller the test owns.
final class ControlledSource {
  ControlledSource() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('events', b.string)
            .subscribeWith<int>(
              (parent, args, context, info) => controller.stream,
              (event, args, context, info) => 'event $event',
            ),
      ],
    );
    schema = b.build(query: query, subscription: subscription);
  }

  bool isCancelled = false;
  late final StreamController<int> controller = StreamController<int>(
    onCancel: () => isCancelled = true,
  );
  late final ExecutableSchema<Ctx> schema;

  Future<void> close() => controller.close();

  GraphQLServer<Ctx> server() => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory: (_) => const Ctx('source'),
  );
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/websocket/hostile_websocket_test.dart test/websocket/socket_operations_test.dart'
```

Expected: the test 'a connection dropped while onConnect is pending is not acked' fails: the session sends `connection_ack` after the socket ended (the other hostile tests pass on Task 7's tree).

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/lib/src/websocket/socket_session.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/websocket/socket_session.dart b/packages/typed_graphql_server/lib/src/websocket/socket_session.dart
index d56690b..656ccb4 100644
--- a/packages/typed_graphql_server/lib/src/websocket/socket_session.dart
+++ b/packages/typed_graphql_server/lib/src/websocket/socket_session.dart
@@ -68,7 +68,10 @@ final class SocketSession<C> {
     return _ended.future;
   }
 
+  // A connection that ended is closed for good: a hook still pending must
+  // not acknowledge it.
   void _end() {
+    _isClosed = true;
     _handshake.stopTimer();
     _operations.cancelAll();
     if (!_ended.isCompleted) {
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "test(typed_graphql_server): add the graphql-ws hostile-input tests

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 9: docs: document the graphql-ws transport

**Why.** A stage that adds API adds its guide section in the same stage; the guide's program drives the handler over an in-memory socket so the doc test runs it.

**Produces:** the complete `doc/websocket.md` (a runnable program, the state table, authentication through `connectionParams`, Origin and CSRF, limits, keep-alive, an adapter sketch), the barrel doc comment, the server `README.md` and `CHANGELOG.md`. `CLAUDE.md`, `llms.txt`, `docs/discovery.md` and the root README wait for M7e.

**Files:**

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/README.md`
- Modify `packages/typed_graphql_server/doc/websocket.md`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`

- [ ] **Step 1: Write the tests.**

This task changes no test file; its check is the suites of Step 4.

- [ ] **Step 2: Run the tests and see them fail.**

Expected: this task changes no test file; the server's doc tests run the guide's program and compare its output.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 1d18742..aa70e4f 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -216,3 +216,11 @@
   `connection_init` message, for a context factory that reads a token sent there.
 - graphql-ws types: `GraphQLSocket`, `GraphQLWsOptions`, `ConnectionHook`,
   `AcceptConnection` and `RefuseConnection`, and a first WebSocket guide.
+- `GraphQLWsHandler` serves the `graphql-transport-ws` subprotocol over a
+  `GraphQLSocket`: the connection handshake with `onConnect` and a timeout,
+  `subscribe` through `GraphQLServer.handle` with a `CancelSignal` per
+  operation, `maxOperations` (`GQL432`), `maxMessageLength`, `maxJsonDepth`
+  and `maxConnections`, the protocol's close codes, and an `Origin` check
+  (`allowsUpgrade`, `allowedOrigins`). The WebSocket guide is complete.
+- Tests: the graphql-ws hostile-input suite. A connection that ended while
+  `onConnect` was pending is no longer acknowledged.
```

Modify `packages/typed_graphql_server/README.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/README.md b/packages/typed_graphql_server/README.md
index e8aff04..adb6693 100644
--- a/packages/typed_graphql_server/README.md
+++ b/packages/typed_graphql_server/README.md
@@ -20,7 +20,9 @@
 > with a document cache, the limits and the cost limit of a production or
 > development profile, CSRF prevention, extensions and error masking, and
 > with automatic persisted queries or trusted documents (M6c); with it stage
-> M6 is complete. The HTTP, graphql-ws and graphql-sse handlers come in M7.
+> M6 is complete. The graphql-ws handler (`GraphQLWsHandler`, M7c) serves
+> queries, mutations and subscriptions over a WebSocket; the HTTP and
+> graphql-sse handlers come in M7.
 > See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
@@ -53,9 +55,9 @@ dependencies:
   ([Schema Builder](doc/schema_builder.md#objects-and-fields),
   [Execution](doc/execution.md#executing-a-request)).
 - **You do not need it when** you only call a GraphQL server: that is the
-  client package, not usable yet. Today it also has no HTTP or
-  WebSocket handler: you decode the request yourself and call
-  `GraphQLServer.handle` (the handlers are M7).
+  client package, not usable yet. Today it has a graphql-ws handler but no
+  HTTP handler: you decode an HTTP request yourself and call
+  `GraphQLServer.handle` (the HTTP handler is M7).
 - **What it replaces**: resolvers written against `Map<String, dynamic>`, where
   a wrong result type or a misspelled argument name fails at run time in the
   middle of a request. Here the wrong type does not compile, and every error
@@ -171,6 +173,9 @@ executed
   `Authorizer`, deny messages, `AuthorizationCoverage`.
 - [Cancellation](doc/cancellation.md): `CancelSignal`, timeouts, what
   resolvers and subscriptions see.
+- [WebSocket](doc/websocket.md): `GraphQLWsHandler` and `GraphQLSocket`,
+  the graphql-ws state machine, close codes, authentication in
+  `connection_init`, Origin checks, limits, writing an adapter.
 
 ## License
 
```

Modify `packages/typed_graphql_server/doc/websocket.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/doc/websocket.md b/packages/typed_graphql_server/doc/websocket.md
index 1777f2b..cfd36ef 100644
--- a/packages/typed_graphql_server/doc/websocket.md
+++ b/packages/typed_graphql_server/doc/websocket.md
@@ -1,31 +1,199 @@
 # WebSocket
 
-The graphql-ws transport (the `graphql-transport-ws` subprotocol) serves
-queries, mutations and subscriptions over one WebSocket connection.
+`GraphQLWsHandler` serves the `graphql-transport-ws` subprotocol of the
+graphql-ws library: queries, mutations and subscriptions over one WebSocket
+connection. It knows nothing of HTTP or of a WebSocket library. A host
+accepts the upgrade, wraps the connection in a `GraphQLSocket` and calls
+`serve`; every `subscribe` message runs through a `GraphQLServer`, so the
+document cache, the limits, the cost limit, error masking, persisted
+documents and the context factory apply as they do for any request. It builds
+on the Server and Subscriptions guides.
 
-This guide is completed with the handler itself. For now it names the pieces
-a host provides and configures: a `GraphQLSocket` over its own WebSocket,
-`GraphQLWsOptions` for the limits and the origins it accepts, and a
-`ConnectionHook` that decides, from the `connection_init` payload, whether to
-acknowledge a connection.
+## A connection, end to end
 
-The options have safe defaults:
+The program below stands in for a host: `MemorySocket` is a `GraphQLSocket`
+over two stream controllers. The client sends `connection_init` with a token
+and one `subscribe`; the context factory reads the token from
+`RequestInfo.connectionParams`.
 
 ```dart
+import 'dart:async';
+
+import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
-void main() {
-  const options = GraphQLWsOptions();
-  print(options.connectionInitTimeout);
-  print(options.maxOperations);
-  print(options.maxMessageLength);
+final class Viewer {
+  const Viewer(this.name);
+
+  final String name;
+}
+
+final class MemorySocket implements GraphQLSocket {
+  final StreamController<String> _incoming = StreamController<String>();
+  final StreamController<String> _outgoing = StreamController<String>();
+
+  @override
+  String? get protocol => GraphQLWsHandler.protocol;
+
+  @override
+  Stream<String> get incoming => _incoming.stream;
+
+  Stream<String> get sent => _outgoing.stream;
+
+  void receive(String text) => _incoming.add(text);
+
+  Future<void> disconnect() => _incoming.close();
+
+  @override
+  void send(String text) => _outgoing.add(text);
+
+  @override
+  Future<void> close(int code, String reason) => _incoming.close();
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Viewer>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t
+          .field('hello', b.string)
+          .resolve((parent, args, context, info) => 'Hello, ${context.name}!'),
+    ],
+  );
+  final server = GraphQLServer<Viewer>(
+    schema: b.build(query: query),
+    contextFactory: (info) {
+      final token = info.connectionParams?['token'];
+      return Viewer(token is JsonString ? token.value : 'guest');
+    },
+  );
+  final handler = GraphQLWsHandler<Viewer>(server);
+  final socket = MemorySocket();
+  final served = handler.serve(
+    socket,
+    RequestInfo(method: 'GET', uri: Uri.parse('http://localhost/graphql')),
+  );
+  socket.receive('{"type":"connection_init","payload":{"token":"Ada"}}');
+  socket.receive(
+    '{"type":"subscribe","id":"1","payload":{"query":"{ hello }"}}',
+  );
+  await socket.sent.take(3).forEach(print);
+  await socket.disconnect();
+  await served;
 }
 ```
 
 It prints:
 
 ```text
-0:00:03.000000
-100
-1048576
+{"type":"connection_ack"}
+{"type":"next","id":"1","payload":{"data":{"hello":"Hello, Ada!"}}}
+{"type":"complete","id":"1"}
 ```
+
+`serve` completes when the connection ends and never throws. A violation of
+the protocol closes the socket with a code (below) instead.
+
+## The state machine
+
+| Event | Effect |
+|---|---|
+| more than `maxConnections` sessions open | close `1013` "Try again later" |
+| `protocol` is not `graphql-transport-ws` | close `4406` "Subprotocol not acceptable" |
+| `Origin` not allowed | close `4403` "Forbidden" |
+| no acknowledgement within `connectionInitTimeout` | close `4408` "Connection initialisation timeout" |
+| a frame longer than `maxMessageLength` | close `1009` "Message too big" |
+| not JSON (or deeper than `maxJsonDepth`), not an object, no string `type`, an unknown type, a field of the wrong type, or `connection_ack`, `next` or `error` from the client | close `4400` "Invalid message received" |
+| `connection_init` | runs `onConnect`; `AcceptConnection` sends `connection_ack` with its payload, `RefuseConnection` closes `4403`, a throw closes `4500`; without a hook the connection is acknowledged |
+| a second `connection_init` | close `4429` "Too many initialisation requests" |
+| `ping` | `pong`, echoing the payload; allowed before the acknowledgement |
+| `pong` | ignored |
+| `subscribe` before the acknowledgement | close `4401` "Unauthorized" |
+| `subscribe` with an id in use | close `4409` "Subscriber for <id> already exists" |
+| `subscribe` with `maxOperations` running | an `error` message for that id with `GQL432`; the socket stays open |
+| `subscribe` | a result is `next` then `complete`; a request error is `error` alone; a subscription is one `next` per result, then `complete` |
+| `complete` from the client | cancels the operation and its `CancelSignal`; nothing more is sent for the id |
+| the connection ends | every operation is cancelled |
+
+An id is free again once its operation ended, so a client may reuse it. A
+`complete` that arrives while the server is still preparing the operation
+sends nothing, and a subscription that starts after it is cancelled at once.
+A `subscribe` without a `query` is not a protocol error: it reaches the
+pipeline, so persisted documents work over WebSocket and a missing document
+is a `GQL400` `error` message. An unexpected failure of an operation is an
+`error` message with `GQL330` and the masked text "Unexpected error.".
+
+## Authentication
+
+Browsers cannot set headers on a WebSocket, so a token travels in the
+`connection_init` payload. `GraphQLWsOptions.onConnect` receives a
+`RequestInfo` of the upgrade (its URI, headers and `source`) with
+`connectionParams` set to the payload. It returns `AcceptConnection`, whose
+`payload` becomes the payload of `connection_ack`, or `RefuseConnection`,
+which closes the socket with `4403`. Throwing closes it with `4500`; the
+message of the exception is never sent.
+
+Every operation of the connection gets a `RequestInfo` with the upgrade's
+headers and the same `connectionParams`, so the context factory reads the
+token for each one, as the program above does. Check the token in `onConnect`
+as well, so that a bad token is refused once rather than on every operation.
+
+## Origin and CSRF
+
+A browser sends its cookies with a WebSocket upgrade and asks no preflight,
+so a page on another site could open a connection as the user. The handler's
+defence is the `Origin` header. `allowsUpgrade` passes an upgrade with no
+`Origin` (not a browser), an `Origin` whose host and port equal the `Host`
+header, or an `Origin` listed in `allowedOrigins` (ignoring case). Anything
+else, including `Origin: null` and an unreadable value, fails. A host calls
+`allowsUpgrade` before upgrading and answers `403`; `serve` checks again and
+closes `4403`.
+
+Each message runs as a `POST` with the upgrade's headers and
+`content-type: application/json`, so the mutation guard and the CSRF rule of
+the pipeline pass. The `Origin` check is what protects them.
+
+## Limits
+
+| Option | Default | Bounds |
+|---|---|---|
+| `connectionInitTimeout` | 3 s | a connection that never acknowledges |
+| `maxOperations` | 100 | operations running at once on one connection |
+| `maxMessageLength` | 1 MiB | the characters of one frame |
+| `maxJsonDepth` | 64 | the nesting of a message |
+| `maxConnections` | 10000 | open sessions of one handler |
+
+The limits of the pipeline (`ServerLimits`: document length, tokens, depth,
+aliases, cost) apply to each `subscribe` as to any request.
+
+## Keep-alive and backpressure
+
+Keep-alive is WebSocket ping frames, which are the adapter's job (for
+example the `pingInterval` of the shelf adapter); the handler answers
+graphql-ws `ping` messages but sends none. `send` is fire-and-forget:
+neither the `WebSocket` of `dart:io` nor a `WebSocketChannel` reports a full
+buffer, so a client that reads nothing while a subscription produces fast
+makes the host buffer. `maxOperations` and the schema's own rate bound it;
+this is an open question of the design.
+
+## Writing an adapter
+
+An adapter implements `GraphQLSocket` over its WebSocket library:
+
+```text
+abstract interface class GraphQLSocket {
+  String? get protocol;        // the negotiated subprotocol
+  Stream<String> get incoming; // text frames; done when the connection closes
+  void send(String text);
+  Future<void> close(int code, String reason);
+}
+```
+
+- Offer `GraphQLWsHandler.protocol` in the handshake and report what was
+  negotiated as `protocol`.
+- Deliver text frames as they are and binary frames decoded as UTF-8; the
+  handler closes the connection when they are not messages.
+- End `incoming` when the connection closes, from either side.
+- Call `allowsUpgrade` before upgrading and answer `403`, then call `serve`
+  with a `RequestInfo` of the upgrade request.
````

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index a91a345..9c30720 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -7,8 +7,9 @@
 /// authorization and cancellation work, and so do DataLoader (`BatchLoader`,
 /// `GroupedLoader`) and the request pipeline (`GraphQLServer`: document
 /// cache, limits and cost limit, CSRF prevention, extensions, error masking,
-/// automatic persisted queries and trusted documents). The transports (HTTP,
-/// graphql-ws, graphql-sse) come with M7. See the package README.
+/// automatic persisted queries and trusted documents). `GraphQLWsHandler`
+/// serves the graphql-ws protocol over any `GraphQLSocket`; the HTTP and
+/// graphql-sse transports come with M7. See the package README.
 library;
 
 export 'src/authorization/authorization.dart';
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "docs: document the graphql-ws transport

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

## Verification

After the last task, from the repository root, run the wrapped commands: `dart format --output=none --set-exit-if-changed packages test` (0 changed), `dart analyze --fatal-infos` (`No issues found!`), `dart test` at the root, `dart test` in `packages/typed_graphql` and in `packages/typed_graphql_server`, and `dart doc` in `packages/typed_graphql_server` (0 warnings). Then hand the branch to M7e Task 1, which merges it into the main line.
