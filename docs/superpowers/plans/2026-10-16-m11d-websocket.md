# M11d WebSocket Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver graphql-transport-ws in `typed_graphql_client` (R8.4): the `ClientSocket` interface the app implements over its own socket, the internal message model and codec, `WebSocketLink` (lazy connection, `connection_init`/`connection_ack` with a timeout, ping/pong and keep-alive, multiplexed operations, reconnection with backoff and the reference client's close codes, `dispose`), the hostile-socket tests and the WebSocket guide.

**Architecture:** A new folder `lib/src/socket/` (category `socket`, guide `doc/websocket.md`). Public: `WebSocketLink` and `ClientSocket`. Internal: `SocketMessage` (sealed, one class per message type) and `SocketMessageCodec` (text to message with `JsonReader`, every malformed frame a problem), `SocketOperations` and `OpenOperation` (the open operations by id), `SocketDriver` (the connect-and-retry loop, one at a time, with cancellable waits through `CancellableWait`), `SocketConnection` (one socket: handshake, ack timeout, keep-alive, dispatch, close codes), `SocketEnd` (how a connection ended), `ReconnectPolicy` and `SocketSettings`. No socket library is a dependency (spec deviation 2): tests drive a `FakeSocket`.

**Tech Stack:** Dart 3.13 (formatted with the 3.47.6 SDK), `package:test`, `package:meta`, `package:fake_async` (dev, from M11a Task 10)

**Spec:** `docs/superpowers/specs/2026-10-16-m11-client-runtime-design.md` (sections 11 and 14; deviations 2, 3, 8, 13), `reference/graphql-ws/PROTOCOL.md`, `docs/requirements.md` (R0.3, R8.4).

**Base:** the tree after the M11a plan (Task 10 included). M11d does not need M11b or M11c.

**Parallelism:** M11d may run in parallel with M11b and M11c. After M11a, the plans M11b (HTTP), M11c (request policies) and M11d (WebSocket) can run at the same time in separate worktrees: they create disjoint folders (`lib/src/http/`, `lib/src/policy/`, `lib/src/socket/` and their `test/` folders) and share only these files, where each adds lines and a merge keeps both sides: `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exports, sorted), `packages/typed_graphql_client/dartdoc_options.yaml` (one category each and one line each in `categoryOrder`; the order after the merge is client, link, http, sse, policy, socket, upload, operations), `packages/typed_graphql_client/CHANGELOG.md` (entries) and, for M11b only, `packages/typed_graphql_client/pubspec.yaml` and `test/quality/import_rule.dart`. M11e (SSE) starts after M11b is merged. M11f comes last; M11z only after M7 is merged.

**Provenance:** the controller wrote and verified every task in a scratch copy, one commit per task on top of the M11a commits (`89b0707`, `37bf413`, `e93a91b`), after one review round whose fixes were folded into their commits. Every commit passed format (0 changed), `dart analyze --fatal-infos` (no issues), the root suite (353 tests) and the client suite (256, 318 and 320 tests after Tasks 1 to 3); `dart doc` for the client reports 0 warnings and 0 errors.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and the client suite green (a task that touches the core also the core suite).
- **Memory and time limits.** Run every `dart` command through this wrapper, one heavy Dart process at a time (the lock is shared with other agents: waiting on it is normal; never kill a process you did not start):

  ```sh
  flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 <command>'
  ```

  Filter the output with `| tail`. No Chrome runs locally: CI covers dart2js and dart2wasm.
- **Formatter.** The wrapper puts the 3.47.6 SDK first on `PATH`, so `dart format` is the newer formatter CLAUDE.md asks for (3.13.1's crashes on `diagnostic_code.dart`).
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen` or `packages/typed_graphql_server` (M11f only adds the server as a client dev dependency).
- Commits use Conventional Commits, one per task, with the subject given in the task and a trailer naming the real model of the implementer, for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Run every command from the repository root unless a step says otherwise.
- Changes to existing files are unified diffs against the tree the earlier tasks leave. If a hunk does not apply, the tree has drifted (or a parallel plan merged first): save the diff to a file and apply it with `git apply --3way`; for the shared files listed under **Parallelism**, keep both sides' lines (exports and categories sorted). If that fails, stop and report it.
- Tests never read git-ignored or untracked files and never open a socket or a port.
- `lib/` of the client imports only `dart:async`, `dart:collection`, `dart:convert`, `dart:core`, `dart:math`, `dart:typed_data`, `package:meta`, the core barrel and (from M11b) `package:http/http.dart` (`test/quality/imports_test.dart`).

## Interfaces consumed

- M11a: `Link`, `NextLink`, `LinkRequest` (`body`, `type`, `context`), `LinkResult`, `LinkPayload`, `LinkFailure`, `ClientFailure` (`NetworkFailure`, `RequestCancelled`, `UnsupportedOperation`, `SocketFailure`), `Backoff` (`delayFor`), `UploadFiles`, `GraphQLClient`, `fake_async`, the test operations (`TicksSubscription`).
- Core: `JsonReader`, `JsonValue`, `JsonObject`, `ResponsePayload.decode`, `RequestErrorResult`, `GraphQLError.decode`, `DiagnosticCode` `GQL468`, `GQL470`-`GQL472`.

## Interfaces produced

- `ClientSocket` (`messages`, `send`, `close([code, reason])`, `closeCode`, `closeReason`).
- `WebSocketLink({required connect, connectionParams, connectionAckTimeout = 10 s, keepAlive, retryAttempts = 5, backoff = Backoff(initialDelay: 1 s), random})` and `dispose()`.
- Test support: `test/support/fake_socket.dart` (`FakeSocket`), `test/support/socket_rig.dart`; M11z drives `WebSocketLink` against M7's handler with an in-memory `ClientSocket`.

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql_client/CHANGELOG.md` | Modify | 1, 2, 3 |
| `packages/typed_graphql_client/dartdoc_options.yaml` | Modify | 1 |
| `packages/typed_graphql_client/doc/websocket.md` | Create/Modify | 1, 3 |
| `packages/typed_graphql_client/lib/src/socket/cancellable_wait.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/client_socket.dart` | Create | 1 |
| `packages/typed_graphql_client/lib/src/socket/open_operation.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/reconnect_policy.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/socket_connection.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/socket_driver.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/socket_end.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/socket_message.dart` | Create | 1 |
| `packages/typed_graphql_client/lib/src/socket/socket_message_codec.dart` | Create | 1 |
| `packages/typed_graphql_client/lib/src/socket/socket_operations.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/socket_settings.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/socket/web_socket_link.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/typed_graphql_client.dart` | Modify | 1, 2 |
| `packages/typed_graphql_client/test/socket/hostile_socket_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/socket/socket_message_test.dart` | Create | 1 |
| `packages/typed_graphql_client/test/socket/web_socket_link_edge_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/socket/web_socket_link_failure_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/socket/web_socket_link_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/support/fake_socket.dart` | Create/Modify | 1, 2 |
| `packages/typed_graphql_client/test/support/socket_rig.dart` | Create | 2 |

### Task 1: feat(typed_graphql_client): add ClientSocket and the graphql-ws message codec

**Why.** Spec section 11. `ClientSocket` is the text-frame socket the app wraps (its doc comment shows a `web_socket_channel` adapter). The internal sealed `SocketMessage` holds the graphql-transport-ws messages; `SocketMessageCodec` encodes them and decodes a server frame with `JsonReader`, refusing what the protocol does not allow (not JSON, not an object, an unknown `type`, a missing or non-string `id`, a payload of the wrong shape) as a problem, never an exception. `FakeSocket` is the test socket. Opens the `socket` category and its guide.

**Files** (verified commit `89b0707` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/dartdoc_options.yaml`
- Create `packages/typed_graphql_client/doc/websocket.md`
- Create `packages/typed_graphql_client/lib/src/socket/client_socket.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_message.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_message_codec.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/socket/socket_message_test.dart`
- Create `packages/typed_graphql_client/test/support/fake_socket.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/socket/socket_message_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
// The internal codec is under test, so the tests import it by path.
import 'package:typed_graphql_client/src/socket/socket_message.dart';
import 'package:typed_graphql_client/src/socket/socket_message_codec.dart';

void main() {
  const codec = SocketMessageCodec();

  SocketMessage decoded(SocketMessage message) {
    final result = codec.decode(message.encode());
    if (result case DecodeSuccess(:final value)) {
      return value;
    }
    fail('$message did not decode: $result');
  }

  group('messages a server sends round trip', () {
    test('connection_ack with and without a payload', () {
      expect(
        decoded(const ConnectionAckMessage()).encode(),
        '{"type":"connection_ack"}',
      );
      final withPayload = ConnectionAckMessage(
        JsonObject({'user': const JsonString('ada')}),
      );
      expect(
        decoded(withPayload).encode(),
        '{"type":"connection_ack","payload":{"user":"ada"}}',
      );
    });

    test('ping and pong', () {
      expect(decoded(const PingMessage()), isA<PingMessage>());
      expect(decoded(const PongMessage()), isA<PongMessage>());
      expect(
        decoded(PingMessage(JsonObject({'n': JsonNumber(1)}))).encode(),
        '{"type":"ping","payload":{"n":1}}',
      );
    });

    test('next carries an execution result', () {
      final message = NextMessage(
        '7',
        ExecutionResult(JsonObject({'ticks': JsonNumber(3)})),
      );
      expect(decoded(message), isA<NextMessage>());
      expect(
        decoded(message).encode(),
        '{"type":"next","id":"7","payload":{"data":{"ticks":3}}}',
      );
    });

    test('error carries the errors', () {
      final message = ErrorMessage('2', [GraphQLError('boom')]);
      expect(decoded(message), isA<ErrorMessage>());
      expect(
        decoded(message).encode(),
        '{"type":"error","id":"2","payload":[{"message":"boom"}]}',
      );
    });

    test('complete carries the id', () {
      expect(
        decoded(const CompleteMessage('9')).encode(),
        '{"type":"complete","id":"9"}',
      );
    });
  });

  group('messages a client sends', () {
    test('connection_init writes its payload', () {
      expect(
        ConnectionInitMessage(
          JsonObject({'token': const JsonString('t')}),
        ).encode(),
        '{"type":"connection_init","payload":{"token":"t"}}',
      );
      expect(
        const ConnectionInitMessage().encode(),
        '{"type":"connection_init"}',
      );
    });

    test('subscribe writes the request as its payload', () {
      const message = SubscribeMessage(
        '1',
        GraphQLRequest(query: 'subscription Ticks{ticks}'),
      );
      expect(
        message.encode(),
        '{"type":"subscribe","id":"1",'
        '"payload":{"query":"subscription Ticks{ticks}"}}',
      );
    });

    test('a server cannot send them', () {
      for (final text in [
        '{"type":"connection_init"}',
        '{"type":"subscribe","id":"1","payload":{"query":"{a}"}}',
      ]) {
        expect(codec.decode(text), isA<DecodeFailure>(), reason: text);
      }
    });
  });

  group('hostile texts are failures, never exceptions', () {
    final texts = <String, String>{
      'not JSON': 'nope',
      'empty': '',
      'an array': '[]',
      'a number': '5',
      'a null': 'null',
      'an integer type': '{"type":1}',
      'no type': '{}',
      'unknown type': '{"type":"bogus"}',
      'next without id': '{"type":"next"}',
      'next with a numeric id': '{"type":"next","id":1,"payload":{"data":{}}}',
      'next with a scalar payload': '{"type":"next","id":"1","payload":5}',
      'next without data': '{"type":"next","id":"1","payload":{"errors":[]}}',
      'next without payload': '{"type":"next","id":"1"}',
      'error with no errors': '{"type":"error","id":"1","payload":[]}',
      'error with an object payload': '{"type":"error","id":"1","payload":{}}',
      'error with a bad error': '{"type":"error","id":"1","payload":[{}]}',
      'complete without id': '{"type":"complete"}',
      'ack with a list payload': '{"type":"connection_ack","payload":[]}',
      'ping with a string payload': '{"type":"ping","payload":"x"}',
      'a lone surrogate': '{"type":"\u{D800}"}',
      'deep nesting':
          '{"type":"next","id":"1","payload":'
          '${'[' * 5000}${']' * 5000}}',
    };
    for (final MapEntry(:key, :value) in texts.entries) {
      test(key, () {
        expect(codec.decode(value), isA<DecodeFailure>());
      });
    }
  });

  test('a failure names the payload path', () {
    final result = codec.decode(
      '{"type":"error","id":"1","payload":[{"message":"ok"},{}]}',
    );
    expect(
      result,
      isA<DecodeFailure>().having(
        (failure) => failure.path,
        'path',
        const [PathKey('payload'), PathIndex(1), PathKey('message')],
      ),
    );
  });
}
```

Create `packages/typed_graphql_client/test/support/fake_socket.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_client/typed_graphql_client.dart';

/// A [ClientSocket] the test drives: it records what the client sends and
/// closes, and the test plays the server.
final class FakeSocket implements ClientSocket {
  final StreamController<String> _incoming = StreamController();
  int? _closeCode;
  String? _closeReason;

  /// The texts the client sent, in order.
  final List<String> sent = [];

  /// The close code the client gave, or null while it has not closed.
  int? clientCloseCode;

  /// The close reason the client gave.
  String? clientCloseReason;

  /// Whether the client called [close].
  bool isClosedByClient = false;

  /// What the client sent, as the `type` of each message.
  List<String> get sentTypes => [
    for (final message in sentMessages) '${message['type']}',
  ];

  /// What the client sent, decoded.
  List<Map<String, Object?>> get sentMessages => [
    for (final text in sent) jsonDecode(text) as Map<String, Object?>,
  ];

  @override
  Stream<String> get messages => _incoming.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  void send(String text) => sent.add(text);

  @override
  Future<void> close([int? code, String? reason]) {
    isClosedByClient = true;
    clientCloseCode = code;
    clientCloseReason = reason;
    return _end(code, reason);
  }

  /// The server sends [text].
  void serverSends(String text) => _incoming.add(text);

  /// The server sends [message] as JSON.
  void serverSendsJson(Map<String, Object?> message) =>
      serverSends(jsonEncode(message));

  /// The server answers the handshake.
  void serverAcknowledges() =>
      serverSendsJson(const {'type': 'connection_ack'});

  /// The server closes the socket with [code] and [reason].
  Future<void> serverCloses(int code, String reason) => _end(code, reason);

  /// The network drops: the stream ends with no close code, as on a
  /// browser's code 1006.
  Future<void> serverDrops() => _end(1006, '');

  Future<void> _end(int? code, String? reason) {
    if (_incoming.isClosed) {
      return Future.value();
    }
    _closeCode = code;
    _closeReason = reason;
    return _incoming.close();
  }
}

/// The `connect` callback of a link under test: it hands out [FakeSocket]s
/// in order and counts the connections.
final class FakeSocketServer {
  final List<Exception> _failures = [];

  /// The sockets handed out, in order.
  final List<FakeSocket> sockets = [];

  /// How many times the link called [connect], failed ones included.
  int connectionCount = 0;

  /// The socket of the latest connection.
  FakeSocket get latest => sockets.last;

  /// Makes the next call to [connect] throw [failure].
  void failNext(Exception failure) => _failures.add(failure);

  /// The callback to give a link.
  Future<ClientSocket> connect() async {
    connectionCount++;
    if (_failures.isNotEmpty) {
      throw _failures.removeAt(0);
    }
    final socket = FakeSocket();
    sockets.add(socket);
    return socket;
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/socket/socket_message_test.dart` does not compile: `SocketMessageCodec` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 32faa45..296c366 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -36,3 +36,6 @@
 - `UploadFile`, `UploadFileCodec` (the `Upload` scalar's codec, which
   writes a file as its marker) and `UploadFiles` (the files of a request,
   in its context); the start of the Uploads guide.
+- `ClientSocket`: the text-frame socket the WebSocket link talks over, which the
+  app supplies; an internal codec for the graphql-transport-ws messages that
+  never throws on a bad frame; the start of the WebSocket guide.
```

Modify `packages/typed_graphql_client/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/dartdoc_options.yaml b/packages/typed_graphql_client/dartdoc_options.yaml
index 0d86a8d..6bd58d8 100644
--- a/packages/typed_graphql_client/dartdoc_options.yaml
+++ b/packages/typed_graphql_client/dartdoc_options.yaml
@@ -9,6 +9,9 @@ dartdoc:
     upload:
       markdown: doc/uploads.md
       displayName: Uploads
+    socket:
+      markdown: doc/websocket.md
+      displayName: WebSocket
     operations:
       markdown: doc/operations.md
       displayName: Generated Operations
@@ -16,5 +19,6 @@ dartdoc:
     - client
     - link
     - upload
+    - socket
     - operations
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_client/doc/websocket.md`:

````markdown
# WebSocket

Subscriptions travel over a WebSocket speaking the graphql-transport-ws
protocol. The package imports no socket library: the app opens the socket
and gives the link a `ClientSocket`, a small interface of text frames.

## The socket

A `ClientSocket` has the frames the server sends (`messages`, which ends
when the socket closes), `send`, `close`, and the `closeCode` and
`closeReason` once the stream has ended. Open the socket with the
sub-protocol `graphql-transport-ws`, and wrap it:

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
````

Create `packages/typed_graphql_client/lib/src/socket/client_socket.dart`:

````dart
/// The text-frame socket `WebSocketLink` talks graphql-transport-ws over.
///
/// The package imports no socket library: the app opens the socket, with
/// the sub-protocol `graphql-transport-ws`, and wraps it in this interface.
/// The link calls [send] and [close] and reads [messages]; it never opens a
/// socket itself, so it runs wherever the app's socket does.
///
/// An adapter over a `WebSocketChannel` or a browser `WebSocket` is a few
/// lines:
///
/// ```text
/// final class ChannelSocket implements ClientSocket {
///   ChannelSocket(this._channel);
///   final WebSocketChannel _channel;
///
///   Stream<String> get messages =>
///       _channel.stream.where((frame) => frame is String).cast<String>();
///   void send(String text) => _channel.sink.add(text);
///   Future<void> close([int? code, String? reason]) =>
///       _channel.sink.close(code, reason);
///   int? get closeCode => _channel.closeCode;
///   String? get closeReason => _channel.closeReason;
/// }
/// ```
///
/// A browser `WebSocket` adapter forwards `onMessage` text frames to a
/// stream controller, closes the controller in `onClose` after saving
/// `event.code` and `event.reason`, and calls `socket.close(code, reason)`.
///
/// {@category socket}
abstract interface class ClientSocket {
  /// The text frames the server sends, in order. The stream ends when the
  /// socket closes, whoever closed it; an error event is a network loss
  /// and may be sent as an error or as the end of the stream.
  Stream<String> get messages;

  /// Sends one text frame. The link only calls it on an open socket; a
  /// socket that is already closing may ignore the call or throw an
  /// [Exception].
  void send(String text);

  /// Closes the socket with [code] and [reason], and completes once it is
  /// closed.
  Future<void> close([int? code, String? reason]);

  /// The close code the closing handshake carried, known once [messages]
  /// has ended; null when there was none.
  int? get closeCode;

  /// The close reason that came with [closeCode].
  String? get closeReason;
}
````

Create `packages/typed_graphql_client/lib/src/socket/socket_message.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// One message of the graphql-transport-ws protocol, as the link writes it
/// and (for the kinds a server sends) reads it.
@internal
sealed class SocketMessage {
  /// Creates a message.
  const SocketMessage();

  /// The `type` member.
  String get type;

  /// The members after `type`.
  Map<String, JsonValue> get members => const {};

  /// The message as JSON text, `type` first.
  String encode() =>
      JsonObject({'type': JsonString(type), ...members}).toString();
}

/// `connection_init`: the first message a client sends.
@internal
final class const ConnectionInitMessage([
  /// The connection parameters, such as a token.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'connection_init';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `connection_ack`: the server accepts the connection.
@internal
final class const ConnectionAckMessage([
  /// What the server sent along, if anything.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'connection_ack';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `ping`: either side asks the other to answer with a pong.
@internal
final class const PingMessage([
  /// What was sent along, if anything.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'ping';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `pong`: the answer to a ping.
@internal
final class const PongMessage([
  /// What was sent along, if anything.
  final JsonObject? payload,
]) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'pong';

  @override
  Map<String, JsonValue> get members => {'payload': ?payload};
}

/// `subscribe`: a client starts an operation.
@internal
final class const SubscribeMessage(
  /// The operation's id on this socket.
  final String id,

  /// The request: query, variables, operation name, extensions.
  final GraphQLRequest request,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'subscribe';

  @override
  Map<String, JsonValue> get members => {
    'id': JsonString(id),
    'payload': request.toJson(),
  };
}

/// `next`: a server sends one execution result of an operation.
@internal
final class const NextMessage(
  /// The operation's id.
  final String id,

  /// The result.
  final ExecutionResult result,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'next';

  @override
  Map<String, JsonValue> get members => {
    'id': JsonString(id),
    'payload': result.toJson(),
  };
}

/// `error`: a server refuses an operation; nothing follows it.
@internal
final class const ErrorMessage(
  /// The operation's id.
  final String id,

  /// The errors, at least one.
  final List<GraphQLError> errors,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'error';

  @override
  Map<String, JsonValue> get members => {
    'id': JsonString(id),
    'payload': JsonArray([for (final error in errors) error.toJson()]),
  };
}

/// `complete`: a server ends an operation, or a client stops one.
@internal
final class const CompleteMessage(
  /// The operation's id.
  final String id,
) extends SocketMessage {
  /// Creates the message.
  this;

  @override
  String get type => 'complete';

  @override
  Map<String, JsonValue> get members => {'id': JsonString(id)};
}
```

Create `packages/typed_graphql_client/lib/src/socket/socket_message_codec.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'socket_message.dart';

/// Reads the text frames a server sends (R0.3): bad input is a
/// [DecodeFailure] with a path, never an exception.
///
/// Only the kinds a server sends are valid; `connection_init` and
/// `subscribe` are the client's.
@internal
final class const SocketMessageCodec() {
  /// Creates the codec.
  this;

  /// The message in [text], or why it is not one.
  DecodeResult<SocketMessage> decode(String text) =>
      switch (const JsonReader().parse(text)) {
        DecodeSuccess(value: final JsonObject message) => _read(message),
        DecodeSuccess() => const DecodeFailure('expected an object'),
        final DecodeFailure failure => failure,
      };

  DecodeResult<SocketMessage> _read(JsonObject message) =>
      switch (message['type']) {
        JsonString(:final value) => _readKind(value, message),
        null => const DecodeFailure(
          'missing "type"',
          path: [PathKey('type')],
        ),
        _ => const DecodeFailure(
          '"type" must be a string',
          path: [PathKey('type')],
        ),
      };

  DecodeResult<SocketMessage> _readKind(String kind, JsonObject message) =>
      switch (kind) {
        'connection_ack' => _withPayload(message, ConnectionAckMessage.new),
        'ping' => _withPayload(message, PingMessage.new),
        'pong' => _withPayload(message, PongMessage.new),
        'next' => _withId(message, _next),
        'error' => _withId(message, _error),
        'complete' => _withId(
          message,
          (id, _) => DecodeSuccess(CompleteMessage(id)),
        ),
        'connection_init' || 'subscribe' => DecodeFailure(
          'a server cannot send "$kind"',
          path: const [PathKey('type')],
        ),
        _ => DecodeFailure(
          'unknown message type "$kind"',
          path: const [PathKey('type')],
        ),
      };

  DecodeResult<SocketMessage> _withPayload(
    JsonObject message,
    SocketMessage Function(JsonObject? payload) create,
  ) => switch (message['payload']) {
    null || JsonNull() => DecodeSuccess(create(null)),
    final JsonObject payload => DecodeSuccess(create(payload)),
    _ => const DecodeFailure(
      '"payload" must be an object',
      path: [PathKey('payload')],
    ),
  };

  DecodeResult<SocketMessage> _withId(
    JsonObject message,
    DecodeResult<SocketMessage> Function(String id, JsonValue? payload) read,
  ) => switch (message['id']) {
    JsonString(:final value) => read(value, message['payload']),
    null => const DecodeFailure('missing "id"', path: [PathKey('id')]),
    _ => const DecodeFailure('"id" must be a string', path: [PathKey('id')]),
  };

  DecodeResult<SocketMessage> _next(String id, JsonValue? payload) {
    if (payload == null) {
      return const DecodeFailure(
        'missing "payload"',
        path: [PathKey('payload')],
      );
    }
    return switch (ResponsePayload.decode(payload)) {
      DecodeSuccess(value: final ExecutionResult result) => DecodeSuccess(
        NextMessage(id, result),
      ),
      DecodeSuccess() => const DecodeFailure(
        'a "next" payload must hold "data"',
        path: [PathKey('payload')],
      ),
      final DecodeFailure failure => failure.inside(const PathKey('payload')),
    };
  }

  DecodeResult<SocketMessage> _error(String id, JsonValue? payload) {
    if (payload is! JsonArray || payload.items.isEmpty) {
      return const DecodeFailure(
        'an "error" payload must be a list of errors, at least one',
        path: [PathKey('payload')],
      );
    }
    final errors = <GraphQLError>[];
    for (final (index, item) in payload.items.indexed) {
      switch (GraphQLError.decode(item)) {
        case DecodeSuccess(:final value):
          errors.add(value);
        case final DecodeFailure failure:
          return failure
              .inside(PathIndex(index))
              .inside(const PathKey('payload'));
      }
    }
    return DecodeSuccess(ErrorMessage(id, errors));
  }
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index 77884a8..4237638 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -38,6 +38,7 @@ export 'src/operation/nullable_data_codec.dart';
 export 'src/operation/object_data_codec.dart';
 export 'src/operation/operation_document.dart';
 export 'src/operation/scalar_data_codec.dart';
+export 'src/socket/client_socket.dart';
 export 'src/upload/upload_file.dart';
 export 'src/upload/upload_file_codec.dart';
 export 'src/upload/upload_files.dart';
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_client): add ClientSocket and the graphql-ws message codec

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 2: feat(typed_graphql_client): add WebSocketLink

**Why.** Spec section 11 and the WebSocket part of section 14. `WebSocketLink` over the internal `SocketOperations`, `OpenOperation`, `SocketDriver`, `SocketConnection`, `SocketEnd`, `ReconnectPolicy`, `SocketSettings` and `CancellableWait`: the lazy handshake with `connectionParams` and the ack timeout, multiplexed operations, ping/pong and keep-alive, reconnection with backoff and the reference client's fatal codes, the mutation rule, `dispose`, the configuration checks. The tests are split by concern (`web_socket_link_test.dart`, `web_socket_link_failure_test.dart`, `web_socket_link_edge_test.dart`) over a `SocketRig`; `hostile_socket_test.dart` covers every hostile frame of section 14, a flood of 10 000 `next` for unknown ids, a ping flood, a close mid-handshake and a server that never acks.

**Files** (verified commit `37bf413` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Create `packages/typed_graphql_client/lib/src/socket/cancellable_wait.dart`
- Create `packages/typed_graphql_client/lib/src/socket/open_operation.dart`
- Create `packages/typed_graphql_client/lib/src/socket/reconnect_policy.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_connection.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_driver.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_end.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_operations.dart`
- Create `packages/typed_graphql_client/lib/src/socket/socket_settings.dart`
- Create `packages/typed_graphql_client/lib/src/socket/web_socket_link.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/socket/hostile_socket_test.dart`
- Create `packages/typed_graphql_client/test/socket/web_socket_link_edge_test.dart`
- Create `packages/typed_graphql_client/test/socket/web_socket_link_failure_test.dart`
- Create `packages/typed_graphql_client/test/socket/web_socket_link_test.dart`
- Modify `packages/typed_graphql_client/test/support/fake_socket.dart`
- Create `packages/typed_graphql_client/test/support/socket_rig.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/socket/hostile_socket_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/socket_rig.dart';
import '../support/test_operations.dart';

/// A server that breaks the protocol (spec section 14): every frame ends in a
/// typed failure or is ignored, and nothing escapes as an exception.
void main() {
  void run(String name, void Function(FakeAsync async, SocketRig rig) body) {
    test(name, () {
      fakeAsync((async) {
        body(async, SocketRig(async));
      });
    });
  }

  void expectMalformed(RequestProbe probe, SocketRig rig) {
    expect(probe.failures.single.code, DiagnosticCode.malformedSocketMessage);
    expect(probe.isDone, isTrue);
    expect(rig.server.latest.clientCloseCode, 4400);
    rig.elapse(const Duration(minutes: 1));
    expect(rig.server.connectionCount, 1);
  }

  group('a frame that breaks the protocol after the handshake', () {
    final frames = <String, String>{
      'text that is not JSON': 'not json',
      'a JSON array': '[1, 2]',
      'an unknown type': '{"type":"bogus"}',
      'a next without an id': '{"type":"next","payload":{"data":{}}}',
      'a next with a numeric id': '{"type":"next","id":1,"payload":{}}',
      'an error whose payload is not a list':
          '{"type":"error","id":"1","payload":{"message":"x"}}',
      'a second acknowledgement': '{"type":"connection_ack"}',
    };
    for (final MapEntry(key: name, value: frame) in frames.entries) {
      run('$name closes with 4400 and a typed failure', (async, rig) {
        final probe = rig.request(const TicksSubscription());
        rig.acknowledge(rig.server.latest);
        rig.server.latest.serverSends(frame);
        rig.settle();
        expectMalformed(probe, rig);
      });
    }
  });

  group('a frame at the wrong time', () {
    run('a next before the acknowledgement is a typed failure', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {'data': <String, Object?>{}},
      });
      expectMalformed(probe, rig);
    });

    run('a duplicate complete is ignored', (async, rig) {
      final probe = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig
        ..serverSends(rig.server.latest, {'type': 'complete', 'id': '1'})
        ..serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      expect(probe.failures, isEmpty);
      expect(probe.isDone, isTrue);
      expect(rig.server.latest.isClosedByClient, isFalse);
    });
  });

  group('a flood', () {
    run('of results for unknown ids delivers nothing', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var i = 0; i < 10000; i++) {
        rig.server.latest.serverSendsJson({
          'type': 'next',
          'id': 'ghost-$i',
          'payload': {
            'data': {'ticks': i},
          },
        });
      }
      rig.settle();
      expect(probe.results, isEmpty);
      expect(rig.server.latest.isClosedByClient, isFalse);

      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'ticks': 1},
        },
      });
      expect(probe.payloads, hasLength(1));
    });

    run('of pings gets one pong each and nothing else', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var i = 0; i < 1000; i++) {
        rig.server.latest.serverSendsJson({'type': 'ping'});
      }
      rig.settle();
      expect(rig.server.latest.sentTypes, [
        'connection_init',
        'subscribe',
        ...List.filled(1000, 'pong'),
      ]);
    });
  });

  group('a server that does not finish the handshake', () {
    run('closing before the acknowledgement fails with its code', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.server.latest.serverCloses(4401, 'Unauthorized');
      rig.settle();
      final failure = probe.failures.single as SocketFailure;
      expect(failure.closeCode, 4401);
      expect(probe.isDone, isTrue);
    });

    run('never acknowledging fails with GQL472 and closes with 4504', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.elapse(const Duration(minutes: 1));
      expect(probe.failures.single.code, DiagnosticCode.connectionAckTimeout);
      expect(rig.server.latest.clientCloseCode, 4504);
      expect(rig.server.connectionCount, 1);
    });
  });
}
```

Create `packages/typed_graphql_client/test/socket/web_socket_link_edge_test.dart`:

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_socket.dart';
import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  const pause = Duration(milliseconds: 200);

  void run(
    String name,
    void Function(FakeAsync async, SocketRig rig) body, {
    FutureOr<JsonObject?> Function()? connectionParamsCallback,
    int retryAttempts = 5,
  }) {
    test(name, () {
      fakeAsync((async) {
        body(
          async,
          SocketRig(
            async,
            connectionParamsCallback: connectionParamsCallback,
            retryAttempts: retryAttempts,
          ),
        );
      });
    });
  }

  group('a socket that fails', () {
    run('is closed, and the next connection is used', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      final first = rig.server.latest..serverFails(Exception('reset'));
      rig.settle();
      expect(first.isClosedByClient, isTrue);
      expect(first.clientCloseCode, 4499);

      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
      expect(probe.failures, isEmpty);
    });
  });

  group('a request made while the loop ends', () {
    test('during the closing of an unused socket is served', () {
      fakeAsync((async) {
        final first = Completer<ClientSocket>();
        final unused = FakeSocket()..closeGate = Completer<void>();
        final second = FakeSocket();
        var calls = 0;
        final link = WebSocketLink(
          connect: () {
            calls++;
            return calls == 1 ? first.future : Future.value(second);
          },
        );
        RequestProbe(
          link.request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        ).cancel();
        async.flushMicrotasks();
        first.complete(unused);
        async.flushMicrotasks();
        expect(unused.isClosedByClient, isTrue);

        RequestProbe(
          link.request(
            LinkRequest.of(const HelloQuery()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        );
        async.flushMicrotasks();
        unused.closeGate?.complete();
        async.flushMicrotasks();
        expect(calls, 2);
        expect(second.sentTypes, ['connection_init']);
      });
    });
  });

  group('dispose', () {
    run('during the backoff leaves no timer', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverDrops();
      rig.settle();
      rig.link.dispose();
      rig.settle();
      expect(async.pendingTimers, isEmpty);
      expect(probe.failures.single, isA<RequestCancelled>());
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
    });

    run('ends a mutation that was sent', (async, rig) {
      final probe = rig.request(const RenameMutation('Ada'));
      rig.acknowledge(rig.server.latest);
      rig.link.dispose();
      rig.settle();
      expect(probe.failures.single, isA<RequestCancelled>());
      expect(probe.isDone, isTrue);
      expect(rig.server.latest.clientCloseCode, 1000);
    });

    test('while connect is pending closes the socket it gets', () {
      fakeAsync((async) {
        final opening = Completer<ClientSocket>();
        final link = WebSocketLink(connect: () => opening.future);
        final probe = RequestProbe(
          link.request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        );
        async.flushMicrotasks();
        link.dispose();
        final socket = FakeSocket();
        opening.complete(socket);
        async.flushMicrotasks();
        expect(socket.clientCloseCode, 1000);
        expect(socket.sent, isEmpty);
        expect(probe.failures.single, isA<RequestCancelled>());
      });
    });
  });

  group('connect', () {
    test('a socket that arrives after every operation left is closed', () {
      fakeAsync((async) {
        final opening = Completer<ClientSocket>();
        final link = WebSocketLink(connect: () => opening.future);
        final probe = RequestProbe(
          link.request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream<LinkResult>.empty(),
          ),
        );
        async.flushMicrotasks();
        probe.cancel();
        async.flushMicrotasks();
        final socket = FakeSocket();
        opening.complete(socket);
        async.flushMicrotasks();
        expect(socket.clientCloseCode, 1000);
        expect(socket.sent, isEmpty);
      });
    });
  });

  group('connectionParams', () {
    run('that throws fails the operations with 4005', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      expect(rig.server.latest.clientCloseCode, 4005);
      final failure = probe.failures.single as SocketFailure;
      expect(failure.code, DiagnosticCode.socketClosed);
      expect(failure.closeCode, 4005);
      expect(rig.server.latest.sent, isEmpty);
    }, connectionParamsCallback: () => throw Exception('no token'));
  });

  group('send', () {
    run('that throws leaves the operation to the reconnection', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.sendFailure = Exception('closing');
      final probe = rig.request(const HelloQuery());
      expect(probe.isDone, isFalse);
      rig.server.latest.serverDrops();
      rig.elapse(pause);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, [
        'connection_init',
        'subscribe',
        'subscribe',
      ]);
    });
  });

  group('a cancelled operation', () {
    run('ignores a late next', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      probe.cancel();
      rig.settle();
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'ticks': 1},
        },
      });
      expect(probe.results, isEmpty);
      expect(rig.server.latest.isClosedByClient, isFalse);
    });
  });

  group('the configuration', () {
    Future<ClientSocket> connect() async => FakeSocket();

    test('refuses a negative retryAttempts', () {
      expect(
        () => WebSocketLink(connect: connect, retryAttempts: -1),
        throwsArgumentError,
      );
    });

    test('refuses an acknowledgement timeout of zero', () {
      expect(
        () => WebSocketLink(
          connect: connect,
          connectionAckTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('refuses a keep-alive of zero', () {
      expect(
        () => WebSocketLink(connect: connect, keepAlive: Duration.zero),
        throwsArgumentError,
      );
    });

    test('accepts no keep-alive', () {
      expect(() => WebSocketLink(connect: connect), returnsNormally);
    });
  });
}
```

Create `packages/typed_graphql_client/test/socket/web_socket_link_failure_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  const pause = Duration(milliseconds: 200);

  void run(
    String name,
    void Function(FakeAsync async, SocketRig rig) body, {
    Duration? keepAlive,
    int retryAttempts = 5,
  }) {
    test(name, () {
      fakeAsync((async) {
        body(
          async,
          SocketRig(async, keepAlive: keepAlive, retryAttempts: retryAttempts),
        );
      });
    });
  }

  group('keep-alive', () {
    run('sends a ping every interval', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.elapse(const Duration(seconds: 5));
      expect(rig.server.latest.sentTypes.where((type) => type == 'ping'), [
        'ping',
      ]);
    }, keepAlive: const Duration(seconds: 5));

    run('keeps the socket while pongs arrive', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var i = 0; i < 3; i++) {
        rig.elapse(const Duration(seconds: 5));
        rig.serverSends(rig.server.latest, {'type': 'pong'});
      }
      expect(rig.server.latest.isClosedByClient, isFalse);
    }, keepAlive: const Duration(seconds: 5));

    run('terminates a socket that does not answer and reconnects', (
      async,
      rig,
    ) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.elapse(const Duration(seconds: 10));
      expect(rig.server.sockets.first.clientCloseCode, 4499);
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
    }, keepAlive: const Duration(seconds: 5));
  });

  group('a message the link cannot read', () {
    run('closes with 4400, fails every operation and does not reconnect', (
      async,
      rig,
    ) {
      final first = rig.request(const TicksSubscription());
      final second = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'next', 'id': 1});
      expect(rig.server.latest.clientCloseCode, 4400);
      for (final probe in [first, second]) {
        expect(
          probe.failures.single.code,
          DiagnosticCode.malformedSocketMessage,
        );
        expect(probe.isDone, isTrue);
      }
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
    });

    run('a second acknowledgement is one too', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.clientCloseCode, 4400);
      expect(
        probe.failures.single.code,
        DiagnosticCode.malformedSocketMessage,
      );
    });

    run('a result before the acknowledgement is one too', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {'data': <String, Object?>{}},
      });
      expect(rig.server.latest.clientCloseCode, 4400);
      expect(probe.failures, hasLength(1));
    });

    run('a text that is not JSON is one too', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverSends('not json');
      rig.settle();
      expect(
        probe.failures.single.code,
        DiagnosticCode.malformedSocketMessage,
      );
    });
  });

  group('a lost connection', () {
    run('resubscribes subscriptions and queries, and fails mutations', (
      async,
      rig,
    ) {
      final ticks = rig.request(const TicksSubscription());
      final hello = rig.request(const HelloQuery());
      final rename = rig.request(const RenameMutation('Ada'));
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverDrops();
      rig.settle();
      expect(rename.failures.single, isA<NetworkFailure>());
      expect(rename.isDone, isTrue);

      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.acknowledge(rig.server.latest);
      expect(
        [
          for (final message in rig.server.latest.sentMessages)
            [message['type'], message['id']],
        ],
        [
          ['connection_init', null],
          ['subscribe', '1'],
          ['subscribe', '2'],
        ],
        reason: 'same ids; the mutation (id 3) is not sent again',
      );
      expect(ticks.isDone, isFalse);
      expect(hello.isDone, isFalse);
    });

    run('keeps delivering results under the same id', (async, rig) {
      final ticks = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverDrops();
      rig.elapse(pause);
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'ticks': 1},
        },
      });
      expect(ticks.payloads, hasLength(1));
    });

    run('sends a mutation that had not been sent when the socket was lost', (
      async,
      rig,
    ) {
      final rename = rig.request(const RenameMutation('Ada'));
      rig.server.latest.serverDrops();
      rig.elapse(pause);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
      expect(rename.isDone, isFalse);
    });

    run('does not reconnect when no operation is open', (async, rig) {
      rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      rig.server.latest.serverDrops();
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
      rig.request(const HelloQuery());
      expect(rig.server.connectionCount, 2);
    });

    run('a code that is never retried fails everything with its code', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.server.latest.serverCloses(4401, 'Unauthorized');
      rig.elapse(const Duration(minutes: 1));
      final failure = probe.failures.single;
      expect(failure, isA<SocketFailure>());
      expect(failure.code, DiagnosticCode.socketClosed);
      expect((failure as SocketFailure).closeCode, 4401);
      expect(failure.closeReason, 'Unauthorized');
      expect(rig.server.connectionCount, 1);
      expect(probe.isDone, isTrue);
    });

    run('fails with GQL471 when the attempts run out', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.server.latest.serverCloses(1013, 'Try again later');
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.server.latest.serverCloses(1013, 'Try again later');
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      final failure = probe.failures.single as SocketFailure;
      expect(failure.code, DiagnosticCode.socketClosed);
      expect(failure.closeCode, 1013);
    }, retryAttempts: 1);

    run('an acknowledgement gives the attempts back', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      for (var i = 0; i < 4; i++) {
        rig.acknowledge(rig.server.latest);
        rig.server.latest.serverDrops();
        rig.elapse(pause);
      }
      expect(rig.server.connectionCount, 5);
      expect(probe.failures, isEmpty);
    }, retryAttempts: 1);
  });

  group('connect', () {
    run('a connect that throws is tried again', (async, rig) {
      rig.server.failNext(Exception('refused'));
      final probe = rig.request(const TicksSubscription());
      expect(rig.server.connectionCount, 1);
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
      expect(probe.failures, isEmpty);
    });

    run('a connect that keeps throwing is a network failure', (async, rig) {
      rig.server
        ..failNext(Exception('refused'))
        ..failNext(Exception('refused'));
      final probe = rig.request(const TicksSubscription());
      rig.elapse(pause);
      rig.elapse(pause);
      expect(rig.server.connectionCount, 2);
      expect(probe.failures.single, isA<NetworkFailure>());
      expect(probe.isDone, isTrue);
    }, retryAttempts: 1);

    run('a request after the failure connects again', (async, rig) {
      rig.server.failNext(Exception('refused'));
      rig.request(const HelloQuery());
      rig.elapse(pause);
      rig.request(const HelloQuery());
      expect(rig.server.sockets, hasLength(1));
    }, retryAttempts: 0);
  });
}
```

Create `packages/typed_graphql_client/test/socket/web_socket_link_test.dart`:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_socket.dart';
import '../support/socket_rig.dart';
import '../support/test_operations.dart';

void main() {
  Map<String, Object?> next(String id, int ticks) => {
    'type': 'next',
    'id': id,
    'payload': {
      'data': {'ticks': ticks},
    },
  };

  void run(String name, void Function(FakeAsync async, SocketRig rig) body) {
    test(name, () {
      fakeAsync((async) {
        body(async, SocketRig(async));
      });
    });
  }

  group('the handshake', () {
    run('connects on the first request and not before', (async, rig) {
      expect(rig.server.connectionCount, 0);
      rig.request(const TicksSubscription());
      expect(rig.server.connectionCount, 1);
      expect(rig.server.latest.sentTypes, ['connection_init']);
    });

    run('sends the first operation after the acknowledgement', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      expect(rig.server.latest.sentMessages.last, {
        'type': 'subscribe',
        'id': '1',
        'payload': {
          'query': 'subscription Ticks{ticks}',
          'operationName': 'Ticks',
        },
      });
    });

    test('sends the connection parameters', () {
      fakeAsync((async) {
        final rig = SocketRig(
          async,
          connectionParams: JsonObject({'token': const JsonString('t')}),
        )..request(const TicksSubscription());
        expect(rig.server.latest.sentMessages.single, {
          'type': 'connection_init',
          'payload': {'token': 't'},
        });
      });
    });

    run('an operation after the acknowledgement subscribes at once', (
      async,
      rig,
    ) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.request(const HelloQuery());
      expect(rig.server.latest.sentTypes, [
        'connection_init',
        'subscribe',
        'subscribe',
      ]);
    });

    run('fails the waiting operations when no acknowledgement comes', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.elapse(const Duration(seconds: 10));
      expect(rig.server.latest.clientCloseCode, 4504);
      expect(rig.server.latest.clientCloseReason, isNotEmpty);
      expect(probe.failures.single.code, DiagnosticCode.connectionAckTimeout);
      expect(probe.isDone, isTrue);
    });
  });

  group('operations', () {
    run('a query gets its result and ends at complete', (async, rig) {
      final probe = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '1',
        'payload': {
          'data': {'hello': 'world'},
        },
      });
      expect(probe.isDone, isFalse);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      expect(probe.payloads, [
        ExecutionResult(JsonObject({'hello': const JsonString('world')})),
      ]);
      expect(probe.isDone, isTrue);
    });

    run('a subscription gets every result', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      for (var tick = 1; tick <= 3; tick++) {
        rig.serverSends(rig.server.latest, next('1', tick));
      }
      expect(probe.payloads, hasLength(3));
      expect(probe.isDone, isFalse);
    });

    run('an error message is a request error result and ends', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {
        'type': 'error',
        'id': '1',
        'payload': [
          {'message': 'Cannot query field "ticks".'},
        ],
      });
      expect(probe.payloads, [
        RequestErrorResult(
          errors: [GraphQLError('Cannot query field "ticks".')],
        ),
      ]);
      expect(probe.isDone, isTrue);
    });

    run('cancelling before the server completes sends complete', (
      async,
      rig,
    ) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      probe.cancel();
      rig.settle();
      expect(rig.server.latest.sentMessages.last, {
        'type': 'complete',
        'id': '1',
      });
    });

    run('a finished operation sends no complete when cancelled', (
      async,
      rig,
    ) {
      final probe = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      probe.cancel();
      rig.settle();
      expect(rig.server.latest.sentTypes, ['connection_init', 'subscribe']);
    });

    run('a message for an unknown id is ignored', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, next('99', 1));
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '99'});
      expect(probe.results, isEmpty);
      expect(rig.server.latest.isClosedByClient, isFalse);
    });

    run('two operations share one socket', (async, rig) {
      final first = rig.request(const TicksSubscription());
      final second = rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, next('1', 1));
      rig.serverSends(rig.server.latest, {
        'type': 'next',
        'id': '2',
        'payload': {
          'data': {'hello': 'x'},
        },
      });
      expect(rig.server.connectionCount, 1);
      expect(first.payloads, hasLength(1));
      expect(second.payloads, hasLength(1));
      expect(
        [
          for (final message in rig.server.latest.sentMessages) message['id'],
        ],
        [null, '1', '2'],
      );
    });

    run('the socket stays open after the last operation ends', (async, rig) {
      rig.request(const HelloQuery());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'complete', 'id': '1'});
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.latest.isClosedByClient, isFalse);
      rig.request(const HelloQuery());
      expect(rig.server.connectionCount, 1);
    });

    run('a request with files is not supported and sends nothing', (
      async,
      rig,
    ) {
      final probe = RequestProbe(
        rig.link.request(
          LinkRequest.of(
            const GreetQuery('Ada'),
            context: LinkContext([
              UploadFiles([
                UploadFile.fromBytes(const [1], filename: 'a.txt'),
              ]),
            ]),
          ),
          (request) => const Stream.empty(),
        ),
      );
      rig.settle();
      expect(
        probe.failures.single.code,
        DiagnosticCode.operationNotSupportedByLink,
      );
      expect(rig.server.connectionCount, 0);
    });
  });

  group('keeping the socket alive', () {
    run('answers a ping with a pong', (async, rig) {
      rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.serverSends(rig.server.latest, {'type': 'ping'});
      expect(rig.server.latest.sentMessages.last, {'type': 'pong'});
    });
  });

  group('dispose', () {
    run('closes the socket and cancels the operations', (async, rig) {
      final probe = rig.request(const TicksSubscription());
      rig.acknowledge(rig.server.latest);
      rig.link.dispose();
      rig.settle();
      expect(rig.server.latest.clientCloseCode, 1000);
      expect(probe.failures.single, isA<RequestCancelled>());
      expect(probe.isDone, isTrue);
      rig.elapse(const Duration(minutes: 1));
      expect(rig.server.connectionCount, 1);
    });

    run('a later request is not supported and does not connect', (
      async,
      rig,
    ) {
      rig.link.dispose();
      rig.settle();
      final probe = rig.request(const HelloQuery());
      expect(
        probe.failures.single.code,
        DiagnosticCode.operationNotSupportedByLink,
      );
      expect(rig.server.connectionCount, 0);
    });
  });

  // Real time, not the fake clock: the client's own futures run in the
  // test's zone.
  test('GraphQLClient.subscribe reads the results', () async {
    final server = FakeSocketServer();
    final client = GraphQLClient(link: WebSocketLink(connect: server.connect));
    final values = <int>[];
    final subscription = client.subscribe(const TicksSubscription()).listen((
      response,
    ) {
      if (response case GraphQLData(:final data)) {
        values.add(data);
      }
    });
    await pumpEventQueue();
    server.latest.serverAcknowledges();
    await pumpEventQueue();
    server.latest
      ..serverSendsJson(next('1', 5))
      ..serverSendsJson(next('1', 6));
    await pumpEventQueue();
    expect(values, [5, 6]);
    await subscription.cancel();
    await pumpEventQueue();
    expect(server.latest.sentTypes.last, 'complete');
  });
}
```

Modify `packages/typed_graphql_client/test/support/fake_socket.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/test/support/fake_socket.dart b/packages/typed_graphql_client/test/support/fake_socket.dart
index c54eaa3..b550275 100644
--- a/packages/typed_graphql_client/test/support/fake_socket.dart
+++ b/packages/typed_graphql_client/test/support/fake_socket.dart
@@ -19,6 +19,12 @@ final class FakeSocket implements ClientSocket {
   /// The close reason the client gave.
   String? clientCloseReason;
 
+  /// What [send] throws, as a socket that is closing may; null for nothing.
+  Exception? sendFailure;
+
+  /// When set, [close] completes only after this does.
+  Completer<void>? closeGate;
+
   /// Whether the client called [close].
   bool isClosedByClient = false;
 
@@ -42,14 +48,23 @@ final class FakeSocket implements ClientSocket {
   String? get closeReason => _closeReason;
 
   @override
-  void send(String text) => sent.add(text);
+  void send(String text) {
+    final failure = sendFailure;
+    if (failure != null) {
+      throw failure;
+    }
+    sent.add(text);
+  }
 
   @override
   Future<void> close([int? code, String? reason]) {
     isClosedByClient = true;
     clientCloseCode = code;
     clientCloseReason = reason;
-    return _end(code, reason);
+    final gate = closeGate;
+    return gate == null
+        ? _end(code, reason)
+        : gate.future.then((_) => _end(code, reason));
   }
 
   /// The server sends [text].
@@ -63,6 +78,9 @@ final class FakeSocket implements ClientSocket {
   void serverAcknowledges() =>
       serverSendsJson(const {'type': 'connection_ack'});
 
+  /// The socket reports a network error on its messages stream.
+  void serverFails(Object error) => _incoming.addError(error);
+
   /// The server closes the socket with [code] and [reason].
   Future<void> serverCloses(int code, String reason) => _end(code, reason);
 
@@ -76,7 +94,9 @@ final class FakeSocket implements ClientSocket {
     }
     _closeCode = code;
     _closeReason = reason;
-    return _incoming.close();
+    // A controller that nobody listens to never completes its `close` future.
+    unawaited(_incoming.close());
+    return Future.value();
   }
 }
 
```

Create `packages/typed_graphql_client/test/support/socket_rig.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import 'fake_socket.dart';

/// The events of one request to a link, recorded as they arrive.
final class RequestProbe {
  /// Listens to [stream].
  RequestProbe(Stream<LinkResult> stream) {
    _subscription = stream.listen(
      results.add,
      onDone: () {
        isDone = true;
        onDone?.call();
      },
    );
  }

  // `late`: assigned in the constructor body, before any event can be read.
  late final StreamSubscription<LinkResult> _subscription;

  /// Every result so far.
  final List<LinkResult> results = [];

  /// Runs when the stream ends, as a listener that reacts to the end.
  void Function()? onDone;

  /// Whether the stream ended.
  bool isDone = false;

  /// The failures among [results].
  List<ClientFailure> get failures => [
    for (final result in results)
      if (result case LinkFailure(:final failure)) failure,
  ];

  /// The payloads among [results].
  List<ResponsePayload> get payloads => [
    for (final result in results)
      if (result case LinkPayload(:final payload)) payload,
  ];

  /// Stops listening, as a caller that cancels its subscription.
  Future<void> cancel() => _subscription.cancel();
}

/// A [WebSocketLink] over [FakeSocketServer] under a fake clock.
///
/// A short backoff (up to 100 ms) keeps the reconnection tests quick.
final class SocketRig {
  /// Creates the rig inside [async].
  SocketRig(
    this.async, {
    JsonObject? connectionParams,
    FutureOr<JsonObject?> Function()? connectionParamsCallback,
    Duration? keepAlive,
    int retryAttempts = 5,
    Duration connectionAckTimeout = const Duration(seconds: 10),
  }) {
    link = WebSocketLink(
      connect: server.connect,
      connectionParams:
          connectionParamsCallback ??
          (connectionParams == null ? null : () => connectionParams),
      connectionAckTimeout: connectionAckTimeout,
      keepAlive: keepAlive,
      retryAttempts: retryAttempts,
      backoff: const Backoff(
        initialDelay: Duration(milliseconds: 100),
        maxDelay: Duration(milliseconds: 100),
      ),
      random: Random(1),
    );
  }

  /// The fake clock.
  final FakeAsync async;

  /// Where the link connects.
  final FakeSocketServer server = FakeSocketServer();

  /// The link under test.
  // `late`: assigned in the constructor body.
  late final WebSocketLink link;

  /// The probes made, so a test can cancel them all.
  final List<RequestProbe> probes = [];

  /// Sends [operation] through the link and lets the microtasks run.
  RequestProbe request(GraphQLOperation<Object> operation) {
    final probe = RequestProbe(
      link.request(
        LinkRequest.of(operation),
        (request) => Stream.error(StateError('a terminating link forwarded')),
      ),
    );
    probes.add(probe);
    settle();
    return probe;
  }

  /// Runs the microtasks that are due.
  void settle() => async.flushMicrotasks();

  /// Moves the clock by [duration] and runs what became due.
  void elapse(Duration duration) {
    async.elapse(duration);
    settle();
  }

  /// Opens the first socket's handshake: the server acknowledges.
  void acknowledge(FakeSocket socket) {
    socket.serverAcknowledges();
    settle();
  }

  /// The server sends [message] on [socket].
  void serverSends(FakeSocket socket, Map<String, Object?> message) {
    socket.serverSendsJson(message);
    settle();
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/socket/web_socket_link_test.dart` does not compile: `WebSocketLink` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 296c366..5ec36a1 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -39,3 +39,7 @@
 - `ClientSocket`: the text-frame socket the WebSocket link talks over, which the
   app supplies; an internal codec for the graphql-transport-ws messages that
   never throws on a bad frame; the start of the WebSocket guide.
+- `WebSocketLink`: operations over one graphql-transport-ws socket the app
+  supplies, with the handshake and its timeout, ping and pong, an optional
+  keep-alive, reconnection with backoff that subscribes again, and `dispose`
+  (R8.4); the codes `GQL470`-`GQL472`.
```

Create `packages/typed_graphql_client/lib/src/socket/cancellable_wait.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

/// A pause that [cancel] ends early, unlike `Future.delayed`, whose timer
/// outlives the link that wanted it.
@internal
final class CancellableWait {
  Timer? _timer;
  Completer<void>? _pause;

  /// Completes after [duration], or when [cancel] is called.
  Future<void> wait(Duration duration) {
    final pause = Completer<void>();
    _pause = pause;
    _timer = Timer(duration, cancel);
    return pause.future;
  }

  /// Ends the pause now; the caller checks whether it is still wanted.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    final pause = _pause;
    _pause = null;
    if (pause != null && !pause.isCompleted) {
      pause.complete();
    }
  }
}
```

Create `packages/typed_graphql_client/lib/src/socket/open_operation.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_request.dart';
import '../link/link_result.dart';

/// One request to a `WebSocketLink` that has not ended: its id on the
/// socket, the stream its caller listens to, and whether the current socket
/// has been told to run it.
@internal
final class OpenOperation {
  /// Creates the operation; [onListen] and [onCancel] run when the caller
  /// listens to and cancels the stream.
  OpenOperation(
    this.id,
    this.request, {
    required void Function(OpenOperation operation) onListen,
    required void Function(OpenOperation operation) onCancel,
  }) {
    controller = StreamController<LinkResult>(
      onListen: () => onListen(this),
      onCancel: () => onCancel(this),
    );
  }

  /// The id the protocol knows the operation by; it stays the same across
  /// reconnections, as a new socket has no operations.
  final String id;

  /// The request, kept to subscribe again after a reconnection.
  final LinkRequest request;

  /// The stream the caller listens to.
  // `late`: the callbacks refer to this operation, so the constructor body
  // makes the controller, before anything can read it.
  late final StreamController<LinkResult> controller;

  /// Whether the current socket has been sent the `subscribe`.
  bool isSent = false;

  /// Whether the request is a mutation, which is never sent twice.
  bool get isMutation => request.type == OperationType.mutation;

  /// Gives the caller [last], if any, and ends its stream.
  void end([LinkResult? last]) {
    if (last != null) {
      controller.add(last);
    }
    unawaited(controller.close());
  }
}
```

Create `packages/typed_graphql_client/lib/src/socket/reconnect_policy.dart`:

```dart
import 'dart:math';

import 'package:meta/meta.dart';

import '../link/backoff.dart';

/// When `WebSocketLink` tries a lost connection again, and how long it
/// waits (R8.4), after graphql-ws's reference client.
@internal
final class ReconnectPolicy({
  /// How many failed attempts in a row are tried again.
  required final int retryAttempts,

  /// The wait before each retry.
  required final Backoff backoff,

  /// The source of the backoff's jitter.
  required final Random random,
}) {
  /// Creates the policy.
  this;

  /// Close codes the reference client never retries: its own errors
  /// (`4500`, `4005`), a bad request or response (`4400`, `4004`), a
  /// refused or conflicting one (`4401`, `4406`, `4409`, `4429`).
  ///
  /// `4403` (forbidden) and `4504` stay retryable, as there: the access
  /// may be granted, or the server may answer in time, on the next try. That
  /// is about a 4504 *sent by a server*. The link's own acknowledgement
  /// timeout fails the operations with `GQL472` and does not reconnect: it is
  /// reported as `AckTimedOut`, which never reaches this policy.
  static const Set<int> _neverRetried = {
    4500,
    4005,
    4400,
    4004,
    4401,
    4406,
    4409,
    4429,
  };

  /// The `1xxx` codes that mean "try again": a normal end, a server going
  /// away or restarting, an abnormal close. Every other `1xxx` code is the
  /// WebSocket layer reporting an error that a retry would repeat.
  static const Set<int> _retriedInternal = {
    1000,
    1001,
    1005,
    1006,
    1012,
    1013,
    1014,
  };

  /// Whether a socket closed with [code] is never connected again.
  bool isFatal(int? code) {
    if (code == null) {
      return false;
    }
    if (_neverRetried.contains(code)) {
      return true;
    }
    return code >= 1000 && code <= 1999 && !_retriedInternal.contains(code);
  }

  /// Whether [failedAttempts] failures in a row (from 1) may be followed
  /// by another try.
  bool allowsRetry(int failedAttempts) => failedAttempts <= retryAttempts;

  /// The wait after [failedAttempts] failures in a row (from 1).
  Duration delayFor(int failedAttempts) =>
      backoff.delayFor(failedAttempts - 1, random);
}
```

Create `packages/typed_graphql_client/lib/src/socket/socket_connection.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_result.dart';
import 'client_socket.dart';
import 'open_operation.dart';
import 'socket_end.dart';
import 'socket_message.dart';
import 'socket_message_codec.dart';
import 'socket_operations.dart';
import 'socket_settings.dart';

/// One socket's life: the handshake, the ack timer, the keep-alive, and the
/// reading of every frame into [SocketOperations].
///
/// [run] completes once, with how the socket ended; it never throws.
@internal
final class SocketConnection {
  /// Creates the connection over [_socket].
  SocketConnection(this._socket, this._settings, this._operations);

  final ClientSocket _socket;
  final SocketSettings _settings;
  final SocketOperations _operations;
  final Completer<SocketEnd> _ended = Completer();
  final SocketMessageCodec _codec = const SocketMessageCodec();
  StreamSubscription<String>? _subscription;
  Timer? _ackTimer;
  Timer? _keepAliveTimer;
  bool _isAwaitingPong = false;
  bool _isAcknowledged = false;

  /// Whether the server sent `connection_ack`.
  bool get isAcknowledged => _isAcknowledged;

  /// Starts reading and sends `connection_init`; completes when the socket
  /// ends.
  Future<SocketEnd> run() {
    _subscription = _socket.messages.listen(
      _handleText,
      onError: (Object error) => _terminate(ConnectionLost(cause: error)),
      onDone: () => _end(
        ConnectionLost(
          closeCode: _socket.closeCode,
          closeReason: _socket.closeReason,
        ),
      ),
    );
    _ackTimer = Timer(_settings.connectionAckTimeout, _timeOutAck);
    unawaited(_sendInit());
    return _ended.future;
  }

  /// Tells the server to run [operation], once the connection is
  /// acknowledged; before that, the acknowledgement does it.
  void subscribe(OpenOperation operation) {
    if (!isAcknowledged || operation.isSent || _ended.isCompleted) {
      return;
    }
    operation.isSent = true;
    _send(SubscribeMessage(operation.id, operation.request.body));
  }

  /// Tells the server the caller no longer wants the operation [id].
  void complete(String id) {
    if (isAcknowledged && !_ended.isCompleted) {
      _send(CompleteMessage(id));
    }
  }

  /// Ends the connection for the link's own reasons and closes the socket.
  Future<void> close(int code, String reason) {
    _end(ConnectionLost(closeCode: code, closeReason: reason));
    return _closeSocket(code, reason);
  }

  Future<void> _sendInit() async {
    try {
      final params = await _settings.connectionParams?.call();
      if (!_ended.isCompleted) {
        _send(ConnectionInitMessage(params));
      }
    } on Exception catch (error) {
      _end(ConnectionLost(closeCode: 4005, cause: error));
      await _closeSocket(4005, 'Internal client error');
    }
  }

  void _handleText(String text) {
    switch (_codec.decode(text)) {
      case DecodeSuccess(:final value):
        _handle(value);
      case final DecodeFailure failure:
        _reject('$failure');
    }
  }

  void _handle(SocketMessage message) {
    switch (message) {
      case ConnectionAckMessage():
        _acknowledge();
      case PingMessage():
        _send(const PongMessage());
      case PongMessage():
        _isAwaitingPong = false;
      case _ when !isAcknowledged:
        _reject('"${message.type}" came before "connection_ack"');
      case NextMessage(:final id, :final result):
        _operations.emit(id, LinkPayload(result));
      case ErrorMessage(:final id, :final errors):
        _operations.finish(
          id,
          last: LinkPayload(RequestErrorResult(errors: errors)),
        );
      case CompleteMessage(:final id):
        _operations.finish(id);
      case ConnectionInitMessage() || SubscribeMessage():
        _reject('a server cannot send "${message.type}"');
    }
  }

  void _acknowledge() {
    if (_isAcknowledged) {
      _reject('a second "connection_ack"');
      return;
    }
    _isAcknowledged = true;
    _ackTimer?.cancel();
    final interval = _settings.keepAlive;
    if (interval != null) {
      _keepAliveTimer = Timer.periodic(interval, (_) => _ping());
    }
    _operations.all.forEach(subscribe);
  }

  /// A ping every interval; a pong must come back before the next one, or
  /// the socket is dead (it may have frozen without closing).
  void _ping() {
    if (_isAwaitingPong) {
      _terminate(
        const ConnectionLost(closeCode: 4499, closeReason: 'Terminated'),
      );
      return;
    }
    _isAwaitingPong = true;
    _send(const PingMessage());
  }

  /// Ends the connection for a reason the socket did not report by closing,
  /// and closes the socket with 4499, so that a reconnection never leaves two
  /// live sockets. A client cannot send 1006, so 4499 is the code of the
  /// reference client's own "Terminated".
  void _terminate(SocketEnd end) {
    _end(end);
    unawaited(_closeSocket(4499, 'Terminated'));
  }

  void _timeOutAck() {
    _end(const AckTimedOut());
    unawaited(_closeSocket(4504, 'Connection acknowledgement timeout'));
  }

  /// 4400, "Bad request": the code graphql-ws gives for an invalid message.
  void _reject(String reason) {
    _end(MalformedMessage(reason));
    unawaited(_closeSocket(4400, 'Invalid message'));
  }

  void _end(SocketEnd end) {
    if (_ended.isCompleted) {
      return;
    }
    _ackTimer?.cancel();
    _keepAliveTimer?.cancel();
    unawaited(_subscription?.cancel());
    _ended.complete(end);
  }

  void _send(SocketMessage message) {
    try {
      _socket.send(message.encode());
    } on Exception {
      // The socket is closing; its messages stream reports the loss.
    }
  }

  Future<void> _closeSocket(int code, String reason) async {
    try {
      await _socket.close(code, reason);
    } on Exception {
      // The socket is already gone; there is nothing left to close.
    }
  }
}
```

Create `packages/typed_graphql_client/lib/src/socket/socket_driver.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import 'cancellable_wait.dart';
import 'client_socket.dart';
import 'open_operation.dart';
import 'socket_connection.dart';
import 'socket_end.dart';
import 'socket_operations.dart';
import 'socket_settings.dart';

/// Why an attempt failed in a way the loop may try again, and whether the
/// server had accepted the connection before it did.
typedef _Loss = ({ClientFailure cause, bool hadAcknowledgement});

/// Keeps one socket alive for as long as operations are open: it connects,
/// serves the socket, and after a loss reconnects by the policy's rules.
///
/// At most one loop runs; a request after the loop ended (every operation
/// done, or the link gave up) starts a new one.
@internal
final class SocketDriver {
  /// Creates a driver for [_operations] with [_settings].
  SocketDriver(this._settings, this._operations);

  final SocketSettings _settings;
  final SocketOperations _operations;
  SocketConnection? _connection;
  bool _isRunning = false;
  bool _isStopped = false;
  final CancellableWait _backoff = CancellableWait();

  /// Starts the connection loop unless it runs, or the driver is stopped.
  void ensureRunning() {
    if (_isRunning || _isStopped) {
      return;
    }
    _isRunning = true;
    unawaited(_drive());
  }

  /// Tells the current socket, if acknowledged, to run [operation].
  void subscribe(OpenOperation operation) => _connection?.subscribe(operation);

  /// Tells the current socket the caller dropped the operation [id].
  void complete(String id) => _connection?.complete(id);

  /// Ends the loop for good and closes the socket with 1000.
  Future<void> stop() async {
    _isStopped = true;
    _backoff.cancel();
    await _connection?.close(1000, 'Normal Closure');
  }

  Future<void> _drive() async {
    try {
      await _reconnectLoop();
    } finally {
      _isRunning = false;
      _connection = null;
    }
    // An operation requested while the loop was still running, for instance
    // while it closed an unused socket, found `_isRunning` set and started
    // nothing; this loop is the only one that can serve it.
    if (_isWanted) {
      ensureRunning();
    }
  }

  Future<void> _reconnectLoop() async {
    var failedAttempts = 0;
    while (_isWanted) {
      final loss = await _connectAndServe();
      if (loss == null || _operations.isEmpty) {
        return;
      }
      failedAttempts = (loss.hadAcknowledgement ? 0 : failedAttempts) + 1;
      if (!_settings.policy.allowsRetry(failedAttempts)) {
        _operations.failAll(loss.cause);
        return;
      }
      await _backoff.wait(_settings.policy.delayFor(failedAttempts));
    }
  }

  bool get _isWanted => !_isStopped && !_operations.isEmpty;

  /// One attempt: null when the loop must stop (the operations have been
  /// told why, or the link is disposed), else what to try again after.
  Future<_Loss?> _connectAndServe() async {
    final ClientSocket socket;
    try {
      socket = await _settings.connect();
    } on Exception catch (error) {
      return (cause: NetworkFailure(error), hadAcknowledgement: false);
    }
    if (_isStopped || _operations.isEmpty) {
      await _closeUnused(socket);
      return null;
    }
    final connection = SocketConnection(socket, _settings, _operations);
    _connection = connection;
    final end = await connection.run();
    _connection = null;
    return _lossFor(end, connection.isAcknowledged);
  }

  /// A socket that opened after the link was disposed or no longer needed.
  Future<void> _closeUnused(ClientSocket socket) async {
    try {
      await socket.close(1000, 'Normal Closure');
    } on Exception {
      // The socket is already gone; there is nothing left to close.
    }
  }

  _Loss? _lossFor(SocketEnd end, bool wasAcknowledged) {
    switch (end) {
      case AckTimedOut():
        _operations.failAll(
          const SocketFailure(
            .connectionAckTimeout,
            'The server did not acknowledge the connection in time.',
          ),
        );
        return null;
      case MalformedMessage(:final reason):
        _operations.failAll(
          SocketFailure(.malformedSocketMessage, 'Invalid message: $reason'),
        );
        return null;
      case final ConnectionLost lost:
        return _lossAfter(lost, wasAcknowledged);
    }
  }

  _Loss? _lossAfter(ConnectionLost lost, bool wasAcknowledged) {
    if (_isStopped) {
      return null;
    }
    final failure = SocketFailure(
      .socketClosed,
      lost.message,
      closeCode: lost.closeCode,
      closeReason: lost.closeReason,
    );
    if (_settings.policy.isFatal(lost.closeCode)) {
      _operations.failAll(failure);
      return null;
    }
    _operations
      ..failSentMutations(NetworkFailure(Exception(lost.message)))
      ..markAllUnsent();
    return (cause: failure, hadAcknowledgement: wasAcknowledged);
  }
}
```

Create `packages/typed_graphql_client/lib/src/socket/socket_end.dart`:

```dart
import 'package:meta/meta.dart';

/// How one socket's life ended, as `SocketConnection.run` reports it.
@internal
sealed class SocketEnd {
  /// Creates an end.
  const SocketEnd();
}

/// The socket closed or failed, by the server, the network or the link's
/// own keep-alive; the reconnection rules decide what follows.
@internal
final class const ConnectionLost({
  /// The close code, when the socket gave one.
  final int? closeCode,

  /// The close reason, when the socket gave one.
  final String? closeReason,

  /// What the messages stream failed with, when it failed.
  final Object? cause,
}) extends SocketEnd {
  /// Creates the end.
  this;

  /// What happened, as a sentence.
  String get message {
    if (cause != null) {
      return 'The socket failed: $cause';
    }
    final reason = closeReason;
    final suffix = reason == null || reason.isEmpty ? '' : ': $reason';
    return closeCode == null
        ? 'The socket closed.'
        : 'The socket closed with code $closeCode$suffix';
  }
}

/// The server did not send `connection_ack` in time (`GQL472`).
@internal
final class const AckTimedOut() extends SocketEnd {
  /// Creates the end.
  this;
}

/// The server sent a message the protocol does not allow (`GQL470`).
@internal
final class const MalformedMessage(
  /// What was wrong with it.
  final String reason,
) extends SocketEnd {
  /// Creates the end.
  this;
}
```

Create `packages/typed_graphql_client/lib/src/socket/socket_operations.dart`:

```dart
import 'package:meta/meta.dart';

import '../client/client_failure.dart';
import '../link/link_result.dart';
import 'open_operation.dart';

/// The operations of a `WebSocketLink` that have not ended, by id.
///
/// It holds one entry per active operation and nothing per message, so a
/// flood of results for unknown ids costs a lookup each (spec section 11).
@internal
final class SocketOperations {
  final Map<String, OpenOperation> _open = {};
  int _lastId = 0;

  /// Whether no operation is open.
  bool get isEmpty => _open.isEmpty;

  /// The open operations, in the order they were added.
  List<OpenOperation> get all => List.of(_open.values);

  /// The id for the next operation: `"1"`, `"2"`, ... for the link's life.
  String nextId() => '${++_lastId}';

  /// Registers [operation] as open.
  void add(OpenOperation operation) => _open[operation.id] = operation;

  /// Forgets the operation [id]; whether it was open.
  bool remove(String id) => _open.remove(id) != null;

  /// Gives the operation [id], if open, one more result.
  void emit(String id, LinkResult result) => _open[id]?.controller.add(result);

  /// Ends the operation [id], if open, after [last] if given.
  void finish(String id, {LinkResult? last}) {
    _open.remove(id)?.end(last);
  }

  /// Ends every operation with [failure].
  void failAll(ClientFailure failure) => _failWhere(failure, (_) => true);

  /// Ends the mutations the socket was told to run with [failure]: a
  /// mutation is never sent twice, as the server may have run it.
  void failSentMutations(ClientFailure failure) => _failWhere(
    failure,
    (operation) => operation.isMutation && operation.isSent,
  );

  /// Marks every operation as not sent, for a new socket.
  void markAllUnsent() {
    for (final operation in _open.values) {
      operation.isSent = false;
    }
  }

  void _failWhere(
    ClientFailure failure,
    bool Function(OpenOperation operation) test,
  ) {
    for (final operation in all.where(test)) {
      _open.remove(operation.id);
      operation.end(LinkFailure(failure));
    }
  }
}
```

Create `packages/typed_graphql_client/lib/src/socket/socket_settings.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'client_socket.dart';
import 'reconnect_policy.dart';

/// What a `WebSocketLink` was configured with, as its collaborators read it.
@internal
final class SocketSettings({
  /// Opens a socket.
  required final Future<ClientSocket> Function() connect,

  /// The payload of `connection_init`, asked for at each connection.
  required final FutureOr<JsonObject?> Function()? connectionParams,

  /// How long the server has to send `connection_ack`.
  required final Duration connectionAckTimeout,

  /// The interval of the client's pings; null for none.
  required final Duration? keepAlive,

  /// When a lost connection is tried again.
  required final ReconnectPolicy policy,
}) {
  /// Creates the settings.
  this;
}
```

Create `packages/typed_graphql_client/lib/src/socket/web_socket_link.dart`:

```dart
import 'dart:async';
import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import '../link/backoff.dart';
import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import '../link/next_link.dart';
import '../upload/upload_files.dart';
import 'client_socket.dart';
import 'open_operation.dart';
import 'reconnect_policy.dart';
import 'socket_driver.dart';
import 'socket_operations.dart';
import 'socket_settings.dart';

/// A terminating link that sends operations over one WebSocket speaking
/// graphql-transport-ws (R8.4); it is the link for subscriptions, and
/// carries queries and mutations as well.
///
/// **Connecting.** The link is lazy: the first request calls [connect],
/// which must open a socket with the sub-protocol `graphql-transport-ws`
/// and wrap it in a [ClientSocket] (a `Future<ClientSocket> Function()`
/// rather than a type of its own: the app has nothing else to implement).
/// One socket carries every operation. The link sends `connection_init`,
/// with the object [connectionParams] returns, waits up to
/// [connectionAckTimeout] for `connection_ack`, and then sends each
/// operation as a `subscribe` with an id (`"1"`, `"2"`, ...) unique for the
/// link's life. The socket stays open after the last operation ends, until
/// [dispose].
///
/// **Results.** `next` is a [LinkPayload]; `error` is a [LinkPayload] of a
/// `RequestErrorResult` and ends the operation; `complete` ends it. A
/// caller that cancels its subscription sends `complete` for the id.
/// Messages for an unknown id are ignored. A message that breaks the
/// protocol closes the socket with 4400 and fails every operation with
/// `SocketFailure` `GQL470`; no acknowledgement in time closes it with 4504
/// and fails them with `GQL472`, without reconnecting (a 4504 close that a
/// *server* sends is retried like any other).
///
/// **Keeping alive.** A server `ping` is answered with `pong`. With
/// [keepAlive], the link also pings at that interval; if no `pong` came
/// back by the next one, it closes the socket with 4499 and reconnects.
///
/// **Reconnecting.** When the socket closes or [connect] throws while
/// operations are open, the link tries again after
/// `backoff.delayFor(n, random)`, up to [retryAttempts] failed attempts in a
/// row (an acknowledged connection gives the count back). A new socket gets
/// a new handshake, and every open query and subscription is subscribed
/// again under the same id; a mutation already sent is not (the server may
/// have run it) and ends with `NetworkFailure`. Codes the reference
/// client never retries (see the WebSocket guide), or running out of
/// attempts, end every operation with `SocketFailure` `GQL471` that holds
/// the close code, or with the `NetworkFailure` of the last [connect].
///
/// A request with `UploadFiles` in its context, or made after [dispose],
/// gets `UnsupportedOperation` `GQL468`.
///
/// {@category socket}
final class WebSocketLink extends Link {
  /// Creates a link that opens its socket with [connect].
  ///
  /// [connectionParams] gives the payload of `connection_init` at each
  /// connection (a token that may have been refreshed); [keepAlive] turns
  /// the client's pings on; [retryAttempts] failed attempts in a row are
  /// tried again, with [backoff] between them; [random] is the source of
  /// the backoff's jitter. A [connectionAckTimeout] or [keepAlive] that is not
  /// longer than zero, or a negative [retryAttempts], is an [ArgumentError].
  WebSocketLink({
    required Future<ClientSocket> Function() connect,
    FutureOr<JsonObject?> Function()? connectionParams,
    Duration connectionAckTimeout = const Duration(seconds: 10),
    Duration? keepAlive,
    int retryAttempts = 5,
    Backoff backoff = const Backoff(initialDelay: Duration(seconds: 1)),
    Random? random,
  }) {
    _requireLongerThanZero(connectionAckTimeout, 'connectionAckTimeout');
    if (keepAlive != null) {
      _requireLongerThanZero(keepAlive, 'keepAlive');
    }
    if (retryAttempts < 0) {
      throw ArgumentError.value(retryAttempts, 'retryAttempts', 'is negative');
    }
    _driver = SocketDriver(
      SocketSettings(
        connect: connect,
        connectionParams: connectionParams,
        connectionAckTimeout: connectionAckTimeout,
        keepAlive: keepAlive,
        policy: ReconnectPolicy(
          retryAttempts: retryAttempts,
          backoff: backoff,
          random: random ?? Random(),
        ),
      ),
      _operations,
    );
  }

  static void _requireLongerThanZero(Duration value, String name) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, name, 'must be longer than zero');
    }
  }

  final SocketOperations _operations = SocketOperations();
  // `late`: the driver needs the settings, which the constructor body builds.
  late final SocketDriver _driver;
  bool _isDisposed = false;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    if (request.context.entry<UploadFiles>() != null) {
      return Stream.value(
        const LinkFailure(
          UnsupportedOperation(
            .operationNotSupportedByLink,
            'WebSocketLink cannot send files; send them over HttpLink.',
          ),
        ),
      );
    }
    if (_isDisposed) {
      return Stream.value(_disposedFailure);
    }
    return OpenOperation(
      _operations.nextId(),
      request,
      onListen: _start,
      onCancel: _stop,
    ).controller.stream;
  }

  /// Closes the socket with 1000, ends every open operation with
  /// `RequestCancelled`, and refuses later requests.
  Future<void> dispose() async {
    _isDisposed = true;
    _operations.failAll(
      const RequestCancelled('The WebSocketLink was disposed.'),
    );
    await _driver.stop();
  }

  static const LinkResult _disposedFailure = LinkFailure(
    UnsupportedOperation(
      .operationNotSupportedByLink,
      'The WebSocketLink was disposed.',
    ),
  );

  void _start(OpenOperation operation) {
    if (_isDisposed) {
      operation.end(_disposedFailure);
      return;
    }
    _operations.add(operation);
    _driver
      ..ensureRunning()
      ..subscribe(operation);
  }

  void _stop(OpenOperation operation) {
    if (_operations.remove(operation.id) && operation.isSent) {
      _driver.complete(operation.id);
    }
  }
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index 4237638..a452551 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -39,6 +39,7 @@ export 'src/operation/object_data_codec.dart';
 export 'src/operation/operation_document.dart';
 export 'src/operation/scalar_data_codec.dart';
 export 'src/socket/client_socket.dart';
+export 'src/socket/web_socket_link.dart';
 export 'src/upload/upload_file.dart';
 export 'src/upload/upload_file_codec.dart';
 export 'src/upload/upload_files.dart';
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_client): add WebSocketLink

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 3: docs: complete the WebSocket guide

**Why.** The WebSocket guide: the socket adapter, subscribing, keeping the socket alive, reconnecting (the table of close codes and what the link does with each, the ack timeout rule) and the recommended `SplitLink` (subscriptions over the socket, the rest over HTTP), each program with its output.

**Files** (verified commit `e93a91b` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/doc/websocket.md`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: nothing fails before the guide changes; afterwards `test/doc` runs its programs and compares their output.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 5ec36a1..64872cf 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -43,3 +43,5 @@
   supplies, with the handshake and its timeout, ping and pong, an optional
   keep-alive, reconnection with backoff that subscribes again, and `dispose`
   (R8.4); the codes `GQL470`-`GQL472`.
+- The WebSocket guide: a runnable in-memory subscription, the reconnection
+  rules, the final close codes, and subscriptions over a socket beside HTTP.
```

Modify `packages/typed_graphql_client/doc/websocket.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_client/doc/websocket.md b/packages/typed_graphql_client/doc/websocket.md
index f4acd79..af898af 100644
--- a/packages/typed_graphql_client/doc/websocket.md
+++ b/packages/typed_graphql_client/doc/websocket.md
@@ -1,15 +1,18 @@
 # WebSocket
 
 Subscriptions travel over a WebSocket speaking the graphql-transport-ws
-protocol. The package imports no socket library: the app opens the socket
-and gives the link a `ClientSocket`, a small interface of text frames.
+protocol (the `graphql-ws` library's). `WebSocketLink` is a terminating link
+for it: it sends queries and mutations too, but it is the link to use for
+subscriptions. The package imports no socket library: the app opens the
+socket and gives the link a `ClientSocket`, a small interface of text frames.
 
 ## The socket
 
 A `ClientSocket` has the frames the server sends (`messages`, which ends
 when the socket closes), `send`, `close`, and the `closeCode` and
 `closeReason` once the stream has ended. Open the socket with the
-sub-protocol `graphql-transport-ws`, and wrap it:
+sub-protocol `graphql-transport-ws`, and wrap it. This is the adapter for a
+`WebSocketChannel`:
 
 ```text
 final class ChannelSocket implements ClientSocket {
@@ -25,3 +28,206 @@ final class ChannelSocket implements ClientSocket {
   String? get closeReason => _channel.closeReason;
 }
 ```
+
+The link takes a function that opens a socket, not a type:
+
+```text
+final link = WebSocketLink(
+  connect: () async => ChannelSocket(
+    WebSocketChannel.connect(
+      Uri.parse('wss://example.com/graphql'),
+      protocols: ['graphql-transport-ws'],
+    ),
+  ),
+  connectionParams: () async =>
+      JsonObject({'token': JsonString(await token())}),
+);
+```
+
+`connectionParams` is optional and is called at each connection, so a
+token that was refreshed is the one sent. A browser `WebSocket` adapter
+forwards its text `message` events to a stream controller, saves
+`event.code` and `event.reason` in its `close` event before closing the
+controller, and calls `socket.close(code, reason)`.
+
+## Subscribing
+
+The link is lazy: the first request opens the socket and does the
+handshake (`connection_init`, then `connection_ack`); every operation then
+shares that socket, with an id from a counter. The program below stands an
+in-memory socket in for a server that acknowledges the connection and
+answers every `subscribe` with two results and `complete`.
+
+```dart
+import 'dart:async';
+import 'dart:convert';
+
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_client/typed_graphql_client.dart';
+
+final class TicksSubscription extends GraphQLSubscription<int> {
+  const TicksSubscription();
+
+  @override
+  OperationDocument get document => const OperationDocument(
+    name: 'Ticks',
+    type: OperationType.subscription,
+    text: 'subscription Ticks{ticks}',
+    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
+  );
+
+  @override
+  JsonObject get variablesJson => JsonObject({});
+
+  @override
+  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
+    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
+    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
+  };
+}
+
+final class MemorySocket implements ClientSocket {
+  final StreamController<String> _frames = StreamController();
+
+  @override
+  Stream<String> get messages => _frames.stream;
+
+  @override
+  int? closeCode;
+
+  @override
+  String? closeReason;
+
+  @override
+  void send(String text) {
+    final message = jsonDecode(text) as Map<String, Object?>;
+    switch (message['type']) {
+      case 'connection_init':
+        _reply({'type': 'connection_ack'});
+      case 'subscribe':
+        for (final tick in [1, 2]) {
+          _reply({
+            'type': 'next',
+            'id': message['id'],
+            'payload': {
+              'data': {'ticks': tick},
+            },
+          });
+        }
+        _reply({'type': 'complete', 'id': message['id']});
+    }
+  }
+
+  @override
+  Future<void> close([int? code, String? reason]) {
+    closeCode = code;
+    closeReason = reason;
+    return _frames.close();
+  }
+
+  void _reply(Map<String, Object?> message) => _frames.add(jsonEncode(message));
+}
+
+Future<void> main() async {
+  final link = WebSocketLink(connect: () async => MemorySocket());
+  final client = GraphQLClient(link: link);
+  await for (final response in client.subscribe(const TicksSubscription())) {
+    if (response case GraphQLData(:final data)) {
+      print('tick $data');
+    }
+  }
+  await link.dispose();
+  print('disposed');
+}
+```
+
+It prints:
+
+```text
+tick 1
+tick 2
+disposed
+```
+
+A `next` message is a `LinkPayload`; an `error` message is a `LinkPayload`
+holding a `RequestErrorResult` and ends the operation; `complete` ends it.
+A query or a mutation ends after its `complete`. Cancelling the stream
+before the server completes sends `complete` for the operation's id. A
+message for an id the link does not know is ignored.
+
+The socket stays open after the last operation ends, so the next request
+needs no handshake. `dispose()` closes it with code 1000 and ends every
+open operation with `RequestCancelled`; a request made after that gets an
+`UnsupportedOperation` (`GQL468`). So does a request with `UploadFiles`
+in its context: a socket cannot send files, so route those over HTTP.
+
+## Keeping the socket alive
+
+A server `ping` is answered with `pong`. With `keepAlive: Duration(...)`
+the link also sends a `ping` at that interval after the acknowledgement; if
+no `pong` came back before the next one, the socket is closed with code
+4499 and the link reconnects as it does for any lost connection.
+
+## Reconnecting
+
+When the socket closes, or `connect` throws, while operations are open,
+the link tries again after `backoff.delayFor(n, random)`: the default
+`Backoff` starts at one second, doubles up to thirty and draws a random
+wait below that ceiling. `retryAttempts` (default 5) failed attempts in a
+row are retried; an acknowledged connection resets the count. A new socket
+does the handshake again, and the link subscribes again to every open
+subscription and query under the same id. A mutation that was already sent
+is not sent again, since the server may have run it: it ends with a
+`NetworkFailure`. A mutation not yet sent when the connection was lost is
+sent on the next one. When no operation is open, a lost socket is not
+reconnected; the next request connects.
+
+A subscription's events are buffered while its listener is paused: the link
+does not pause the socket, which carries other operations.
+
+| Event | The operations get |
+|---|---|
+| The socket closes with a code that is not final, attempts left | nothing: the link reconnects |
+| A mutation was sent before the loss | `NetworkFailure` for that mutation |
+| The socket closes with a final code | `SocketFailure` `GQL471` with `closeCode` and `closeReason` |
+| The attempts run out | `SocketFailure` `GQL471` with the last close code |
+| `connect` keeps throwing until the attempts run out | `NetworkFailure` with the last exception |
+| No `connection_ack` within `connectionAckTimeout` (default 10 s) | `SocketFailure` `GQL472`; the link closes with 4504 and does not reconnect |
+| The server sends a message the protocol does not allow | `SocketFailure` `GQL470`; the link closes with 4400 and does not reconnect |
+
+Close codes that are final (never retried) follow the reference client:
+
+| Code | Meaning |
+|---|---|
+| 4500 | internal server error |
+| 4005 | internal client error |
+| 4400 | bad request |
+| 4004 | bad response |
+| 4401 | unauthorized |
+| 4406 | subprotocol not acceptable |
+| 4409 | subscriber already exists |
+| 4429 | too many initialisation requests |
+| 1002 to 1999 | WebSocket-level errors (a protocol error, 1011 internal error, ...), except 1005, 1006, 1012, 1013 and 1014 |
+
+Every other close code is retried: 1000, 1001, 1005, 1006, 1012, 1013 and
+1014 (a normal or abnormal end, a restarting server), 4403 (forbidden: the
+access may be granted), 4499 (the link's own keep-alive) and 4504 when a
+server sends it. The link's own acknowledgement timeout is not a retried
+loss: it fails the operations with `GQL472` and does not reconnect.
+
+## Subscriptions over a socket, the rest over HTTP
+
+`SplitLink` sends each request down one of two links. The usual
+arrangement keeps queries and mutations on HTTP, where they get retries,
+files and caching, and sends subscriptions over the socket:
+
+```text
+final link = SplitLink(
+  test: (request) => request.type == OperationType.subscription,
+  whenTrue: WebSocketLink(connect: openSocket),
+  whenFalse: HttpLink(Uri.parse('https://example.com/graphql')),
+);
+final client = GraphQLClient(link: link);
+```
+
+`HttpLink` is the subject of the HTTP guide.
````

- [ ] **Step 4: Format, then run the green check.**

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart doc --dry-run"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes, `dart doc` reports "Found 0 warnings and 0 errors".

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "docs: complete the WebSocket guide

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

## Review Focus

- The protocol: `connection_init` first, nothing before `connection_ack`, ids unique for the link's life, `complete` sent on cancel only for a sent `subscribe`, messages for unknown ids ignored in constant memory.
- Close codes: 4400 for an invalid server message (no reconnection), 4504 for the link's own ack timeout (`GQL472`, no reconnection), 4499 for a dead or failed socket (reconnects), 4005 when `connectionParams` throws, 1000 on dispose; the never-retried list matches the reference client.
- Reconnection: the count resets after an ack; open queries and subscriptions resubscribe under the same id; a sent mutation fails with `NetworkFailure` and is never resent.
- One loop at a time in `SocketDriver`: a request arriving while a socket closes is served; dispose during a backoff leaves no timer; a socket that arrives after every operation left is closed.
- Every failure is a value: a socket error, a throwing `send`, a throwing `connect` or `connectionParams`.

## Verification

After the last task, run the format, analyze, root, client and `dart doc` checks with the Global Constraints wrapper (the commands are listed in M11a's Verification). Expected: 0 files changed, `No issues found!`, the root suite (353 tests) and the client suite (320) pass, `dart doc` reports "Found 0 warnings and 0 errors". Then run the self-review of CLAUDE.md (`wc -l` of every file touched, the longest method).
