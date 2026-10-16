# M11a Client Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the core of the client runtime in `typed_graphql_client` (R8.1, R8.2, R8.3, R8.5): the client diagnostic codes `GQL460`-`GQL474` in the core catalog, `CancelToken`, the sealed `ClientFailure` family, the link model (`LinkRequest`, the sealed `LinkResult`, `LinkContext` and its entries), `Link`, `Link.from`, `MockLink`, `GraphQLClient` with the sealed `GraphQLResponse`, `SplitLink`, `ContextLink`, `Backoff`, the upload types, the client import rule and the Client, Links and Uploads guides.

**Architecture:** Three new folders in `packages/typed_graphql_client/lib/src/`, each a dartdoc category with its guide: `client/` (`GraphQLClient`, `GraphQLResponse`, `ClientFailure`, `CancelToken`; internal `ResponseDecoder` and `OperationStream`), `link/` (`Link`, `NextLink`, `LinkRequest`, `LinkResult`, `LinkContext`, `ContextEntry`, `RequestHeaders`, `HttpResponseInfo`, `SplitLink`, `ContextLink`, `Backoff`, `MockLink`; internal `LinkChain`) and `upload/` (`UploadFile`, `UploadFileCodec`, `UploadFiles`). A link returns a `Stream<LinkResult>`; failures are `LinkFailure` values, never stream errors; cancellation inside the chain is stream cancellation. The client decodes the first result of a query or mutation with the generated operation's `decodeData` and cancels the chain; a subscription is a stream of decoded responses. The M10 `operation/` folder is unchanged.

**Tech Stack:** Dart 3.13 (formatted with the 3.47.6 SDK), `package:test`, `package:meta`, `package:fake_async` (dev, from M11a Task 10)

**Spec:** `docs/superpowers/specs/2026-10-16-m11-client-runtime-design.md` (sections 1-8, 9 for the upload types, 16-18), `docs/requirements.md` (R0.2, R0.3, R8.1-R8.5).

**Base:** `main` at `8ed1c85` (M6 merged, M10 delivered).

**Parallelism:** M11a runs alone and first; every other M11 plan builds on it. After M11a, the plans M11b (HTTP), M11c (request policies) and M11d (WebSocket) can run at the same time in separate worktrees: they create disjoint folders (`lib/src/http/`, `lib/src/policy/`, `lib/src/socket/` and their `test/` folders) and share only these files, where each adds lines and a merge keeps both sides: `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exports, sorted), `packages/typed_graphql_client/dartdoc_options.yaml` (one category each and one line each in `categoryOrder`; the order after the merge is client, link, http, sse, policy, socket, upload, operations), `packages/typed_graphql_client/CHANGELOG.md` (entries) and, for M11b only, `packages/typed_graphql_client/pubspec.yaml` and `test/quality/import_rule.dart`. M11e (SSE) starts after M11b is merged. M11f comes last; M11z only after M7 is merged.

**Provenance:** the controller wrote and verified every task in a scratch copy of `main` at `8ed1c85`, one commit per task (`e07111f`, `e8c573a`, `c1cc453`, `e8c70fb`, `1a36505`, `27d2ee6`, `f6fa729`, `e971b27`, `0a8ea33`, `f1a9664`). Each task's diffs are that commit's diffs, so they apply in order. After Task 10 the copy passed: format (0 changed), `dart analyze --fatal-infos` (no issues), the root suite (353 tests), the client suite (225), the core suite, and `dart doc` for the client (0 warnings, 0 errors).

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

- Core (`package:typed_graphql/typed_graphql.dart`): `DiagnosticCode`, `JsonValue` and its family, `JsonReader`, `DecodeResult`/`DecodeSuccess`/`DecodeFailure`, `PathSegment`, `GraphQLError`, `GraphQLRequest`, `ResponsePayload` (`ExecutionResult`, `RequestErrorResult`), `OperationType`, `ScalarCodec`.
- M10 contract (`lib/src/operation/`, unchanged): `GraphQLOperation`, `GraphQLQuery`, `GraphQLMutation`, `GraphQLSubscription`, `OperationDocument` (`text`, `sha256`, `type`, `operationName`), `decodeData`, `DataCodec`.

## Interfaces produced

- `DiagnosticCode.networkFailure` (`GQL460`) to `authenticationFailed` (`GQL474`).
- `CancelToken` (`isCancelled`, `reason`, `whenCancelled`, `cancel`).
- `ClientFailure` (sealed): `NetworkFailure`, `HttpStatusFailure`, `ResponseFormatFailure`, `DataFormatFailure`, `RequestCancelled`, `RequestTimedOut`, `UnsupportedOperation`, `SocketFailure`, `EventStreamFailure`, `AuthenticationFailure`; each with `code` and `message`.
- `LinkRequest` (`document`, `variables`, `extensions`, `context`, `sendsDocumentText`, `type`, `body`, `LinkRequest.of`, `withContext`, `withExtensions`, `withDocumentText`), `LinkResult` (sealed: `LinkPayload`, `LinkFailure`), `LinkContext` (`entry<T>()`, `withEntry`), `ContextEntry`, `RequestHeaders` (`withHeader`), `HttpResponseInfo`.
- `Link` (`request(request, forward)`, `Link.from`), `NextLink`, `MockLink` (`requests`, `pendingAnswerCount`, `add`, `addData`, `addErrors`, `addFailure`, `addStream`), `SplitLink`, `ContextLink`, `Backoff` (`ceilingFor`, `delayFor`).
- `GraphQLClient` (`query`, `mutate`, `subscribe`), `GraphQLResponse` (sealed: `GraphQLData`, `GraphQLErrors`, `GraphQLTransportFailure`).
- `UploadFile` (`fromBytes`, `fromStream`, `open`, `marker`), `UploadFileCodec`, `UploadFiles`.
- Test support every later plan uses: `test/support/test_operations.dart` (`HelloQuery`, `GreetQuery`, `RenameMutation`, `TicksSubscription`, `hello`), the client import rule (`test/quality/import_rule.dart`), the category tag test.

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_client/CHANGELOG.md` | Modify | 2, 3, 4, 5, 6, 7, 8, 9 |
| `packages/typed_graphql_client/dartdoc_options.yaml` | Modify | 2, 4, 9 |
| `packages/typed_graphql_client/doc/client.md` | Create/Modify | 2, 3, 6 |
| `packages/typed_graphql_client/doc/links.md` | Create/Modify | 4, 5, 7, 8 |
| `packages/typed_graphql_client/doc/uploads.md` | Create | 9 |
| `packages/typed_graphql_client/lib/src/client/cancel_token.dart` | Create | 2 |
| `packages/typed_graphql_client/lib/src/client/client_failure.dart` | Create | 3 |
| `packages/typed_graphql_client/lib/src/client/graphql_client.dart` | Create/Modify | 6, 10 |
| `packages/typed_graphql_client/lib/src/client/graphql_response.dart` | Create | 6 |
| `packages/typed_graphql_client/lib/src/client/operation_stream.dart` | Create/Modify | 6, 10 |
| `packages/typed_graphql_client/lib/src/client/response_decoder.dart` | Create | 6 |
| `packages/typed_graphql_client/lib/src/link/backoff.dart` | Create | 8 |
| `packages/typed_graphql_client/lib/src/link/context_entry.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/src/link/context_link.dart` | Create | 7 |
| `packages/typed_graphql_client/lib/src/link/http_response_info.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/src/link/link.dart` | Create | 5 |
| `packages/typed_graphql_client/lib/src/link/link_chain.dart` | Create | 5 |
| `packages/typed_graphql_client/lib/src/link/link_context.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/src/link/link_request.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/src/link/link_result.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/src/link/mock_link.dart` | Create | 5 |
| `packages/typed_graphql_client/lib/src/link/next_link.dart` | Create | 5 |
| `packages/typed_graphql_client/lib/src/link/request_headers.dart` | Create | 4 |
| `packages/typed_graphql_client/lib/src/link/split_link.dart` | Create | 7 |
| `packages/typed_graphql_client/lib/src/upload/upload_file.dart` | Create | 9 |
| `packages/typed_graphql_client/lib/src/upload/upload_file_codec.dart` | Create | 9 |
| `packages/typed_graphql_client/lib/src/upload/upload_files.dart` | Create | 9 |
| `packages/typed_graphql_client/lib/typed_graphql_client.dart` | Modify | 2, 3, 4, 5, 6, 7, 8, 9 |
| `packages/typed_graphql_client/pubspec.yaml` | Modify | 2, 10 |
| `packages/typed_graphql_client/test/client/cancel_token_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/client/client_cancellation_test.dart` | Create | 6 |
| `packages/typed_graphql_client/test/client/client_failure_test.dart` | Create | 3 |
| `packages/typed_graphql_client/test/client/graphql_client_test.dart` | Create/Modify | 6, 10 |
| `packages/typed_graphql_client/test/doc/category_tags_test.dart` | Modify | 2 |
| `packages/typed_graphql_client/test/link/backoff_test.dart` | Create | 8 |
| `packages/typed_graphql_client/test/link/link_context_test.dart` | Create | 4 |
| `packages/typed_graphql_client/test/link/link_request_test.dart` | Create | 4 |
| `packages/typed_graphql_client/test/link/link_test.dart` | Create | 5 |
| `packages/typed_graphql_client/test/link/mock_link_test.dart` | Create | 5 |
| `packages/typed_graphql_client/test/link/split_and_context_link_test.dart` | Create | 7 |
| `packages/typed_graphql_client/test/quality/import_rule.dart` | Create | 2 |
| `packages/typed_graphql_client/test/quality/imports_test.dart` | Create | 2 |
| `packages/typed_graphql_client/test/support/test_operations.dart` | Create | 4 |
| `packages/typed_graphql_client/test/upload/upload_file_test.dart` | Create | 9 |

### Task 1: feat(typed_graphql): add the client diagnostic codes

**Why.** Adds the fifteen client codes `GQL460`-`GQL474` (`networkFailure`, `httpErrorStatus`, `unsupportedResponseType`, `responseTooLarge`, `malformedResponse`, `dataShapeMismatch`, `requestCancelled`, `requestTimedOut`, `operationNotSupportedByLink`, `linkEndedWithoutResult`, `malformedSocketMessage`, `socketClosed`, `connectionAckTimeout`, `malformedEventStream`, `authenticationFailed`) to the core catalog in id order with a doc comment each (spec section 3). All fifteen come in one core commit so the later plans never touch the core (spec deviation 12; CLAUDE.md: a core change goes in its own commit before the package that needs it).

**Files** (verified commit `e07111f` of the controller's scratch copy):

- Modify `packages/typed_graphql/CHANGELOG.md`
- Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql && dart test"' 2>&1 | tail -30
```

Expected: nothing fails: the commit adds catalog entries only; the core suite checks that ids are unique, ordered and documented.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql/CHANGELOG.md b/packages/typed_graphql/CHANGELOG.md
index 98dc7f1..1f7d6b7 100644
--- a/packages/typed_graphql/CHANGELOG.md
+++ b/packages/typed_graphql/CHANGELOG.md
@@ -302,3 +302,10 @@
   `invalidPersistedQuery`, `untrustedDocument`, `unknownTrustedDocument`),
   reported by the server for persisted queries and trusted documents.
 - Documentation: `GQL402` also covers `HEAD`; the cost guide says a resolver must cap a slicing argument itself.
+- `DiagnosticCode`: `GQL460`-`GQL474` (`networkFailure`, `httpErrorStatus`,
+  `unsupportedResponseType`, `responseTooLarge`, `malformedResponse`,
+  `dataShapeMismatch`, `requestCancelled`, `requestTimedOut`,
+  `operationNotSupportedByLink`, `linkEndedWithoutResult`,
+  `malformedSocketMessage`, `socketClosed`, `connectionAckTimeout`,
+  `malformedEventStream`, `authenticationFailed`), the codes of the
+  client's failures.
```

Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
index 241c8c7..9a3ff3c 100644
--- a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
@@ -717,6 +717,82 @@ enum DiagnosticCode(
   /// response of `GraphQLServer.handle`.
   unknownTrustedDocument('GQL415'),
 
+  /// `GQL460`: reported by the client when its transport could not send a
+  /// request or read the answer: the HTTP client or the socket threw, or
+  /// the connection was lost. It is the `code` of a `NetworkFailure`.
+  networkFailure('GQL460'),
+
+  /// `GQL461`: reported by the client when an HTTP answer has a status
+  /// outside 2xx and a body that is not `application/graphql-response+json`,
+  /// so it is not a GraphQL response. It is the `code` of an
+  /// `HttpStatusFailure`.
+  httpErrorStatus('GQL461'),
+
+  /// `GQL462`: reported by the client when an answer has a content type it
+  /// cannot read: none, another media type, or a charset other than UTF-8.
+  /// It is the `code` of a `ResponseFormatFailure`.
+  unsupportedResponseType('GQL462'),
+
+  /// `GQL463`: reported by the client when an answer, or one event of a
+  /// stream, is longer than the link's byte limit; the request is aborted.
+  /// It is the `code` of a `ResponseFormatFailure`.
+  responseTooLarge('GQL463'),
+
+  /// `GQL464`: reported by the client when an answer is not a GraphQL
+  /// response: not UTF-8, not JSON, nested too deep, not an object of the
+  /// response format, or `"data": null` without errors. It is the `code`
+  /// of a `ResponseFormatFailure`.
+  malformedResponse('GQL464'),
+
+  /// `GQL465`: reported by the client when the `data` of a response does
+  /// not have the shape of the operation's generated classes. It is the
+  /// `code` of a `DataFormatFailure`.
+  dataShapeMismatch('GQL465'),
+
+  /// `GQL466`: reported by the client when the caller cancelled a request
+  /// before its answer. It is the `code` of a `RequestCancelled`.
+  requestCancelled('GQL466'),
+
+  /// `GQL467`: reported by the client when a link's timeout passed before
+  /// the answer; the request is aborted. It is the `code` of a
+  /// `RequestTimedOut`.
+  requestTimedOut('GQL467'),
+
+  /// `GQL468`: reported by the client when a terminating link cannot carry
+  /// a request, such as a subscription over HTTP or files over a socket.
+  /// It is the `code` of an `UnsupportedOperation`.
+  operationNotSupportedByLink('GQL468'),
+
+  /// `GQL469`: reported by the client when the link chain ended the stream
+  /// of a query or a mutation without a result. It is the `code` of an
+  /// `UnsupportedOperation`.
+  linkEndedWithoutResult('GQL469'),
+
+  /// `GQL470`: reported by the client when a graphql-transport-ws server
+  /// sends a message the protocol does not allow; the client closes the
+  /// socket. It is the `code` of a `SocketFailure`.
+  malformedSocketMessage('GQL470'),
+
+  /// `GQL471`: reported by the client when its socket closed with a code
+  /// that forbids reconnecting, or the reconnection attempts ran out. It
+  /// is the `code` of a `SocketFailure`.
+  socketClosed('GQL471'),
+
+  /// `GQL472`: reported by the client when a graphql-transport-ws server
+  /// did not acknowledge the connection in time; the client closes the
+  /// socket. It is the `code` of a `SocketFailure`.
+  connectionAckTimeout('GQL472'),
+
+  /// `GQL473`: reported by the client when a graphql-sse stream holds an
+  /// event of an unknown type or ends without `complete`. It is the `code`
+  /// of an `EventStreamFailure`.
+  malformedEventStream('GQL473'),
+
+  /// `GQL474`: reported by the client when the callback that gives or
+  /// refreshes an authentication token threw. It is the `code` of an
+  /// `AuthenticationFailure`.
+  authenticationFailed('GQL474'),
+
   /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
   /// the YAML parser's.
   configSyntax('GQL500'),
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format packages test'`), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql && dart test"'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql): add the client diagnostic codes

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 2: feat(typed_graphql_client): add CancelToken and the client import rule

**Why.** Spec section 4 and section 2. `CancelToken` is the caller's cancellation handle (`cancel` has an effect once; `whenCancelled` never completes with an error). The client gets its own import rule (`test/quality/import_rule.dart`, checked by `imports_test.dart`): `lib/` imports no platform or web library, so the package runs on the VM, AOT, dart2js and dart2wasm. The `client` dartdoc category and its guide open; the category tag test now walks every exported folder.

**Files** (verified commit `e8c573a` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/dartdoc_options.yaml`
- Create `packages/typed_graphql_client/doc/client.md`
- Create `packages/typed_graphql_client/lib/src/client/cancel_token.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Modify `packages/typed_graphql_client/pubspec.yaml`
- Create `packages/typed_graphql_client/test/client/cancel_token_test.dart`
- Modify `packages/typed_graphql_client/test/doc/category_tags_test.dart`
- Create `packages/typed_graphql_client/test/quality/import_rule.dart`
- Create `packages/typed_graphql_client/test/quality/imports_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/client/cancel_token_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  test('a new token is not cancelled', () {
    final token = CancelToken();
    expect(token.isCancelled, isFalse);
    expect(token.reason, isNull);
  });

  test('cancel keeps the first reason', () {
    final token = CancelToken()
      ..cancel('first')
      ..cancel('second');
    expect(token.isCancelled, isTrue);
    expect(token.reason, 'first');
  });

  test('whenCancelled completes on cancel', () async {
    final token = CancelToken();
    var isDone = false;
    final done = token.whenCancelled.then((_) => isDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(isDone, isFalse);
    token.cancel();
    await done;
    expect(isDone, isTrue);
  });

  test('a listener runs once, at cancel', () {
    final token = CancelToken();
    var calls = 0;
    token.addListener(() => calls++);
    token
      ..cancel()
      ..cancel();
    expect(calls, 1);
  });

  test('a listener added after cancel runs at once', () {
    final token = CancelToken()..cancel();
    var calls = 0;
    token.addListener(() => calls++);
    expect(calls, 1);
  });

  test('a removed listener does not run and is not kept', () {
    final token = CancelToken();
    var calls = 0;
    final remove = token.addListener(() => calls++);
    expect(token.listenerCount, 1);
    remove();
    expect(token.listenerCount, 0);
    token.cancel();
    expect(calls, 0);
  });
}
```

Modify `packages/typed_graphql_client/test/doc/category_tags_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/test/doc/category_tags_test.dart b/packages/typed_graphql_client/test/doc/category_tags_test.dart
index b6f557b..e396fab 100644
--- a/packages/typed_graphql_client/test/doc/category_tags_test.dart
+++ b/packages/typed_graphql_client/test/doc/category_tags_test.dart
@@ -7,8 +7,9 @@ import 'package:test/test.dart';
 
 import '../../../typed_graphql/test/doc/public_type.dart';
 
-/// Every exported type is in the `operations` dartdoc category, which
-/// `dartdoc_options.yaml` declares with its guide (R11.2).
+/// Every exported type is in the dartdoc category of its folder, and
+/// `dartdoc_options.yaml` declares those categories, each with a guide
+/// (R11.2).
 void main() {
   final barrel = File('lib/typed_graphql_client.dart').readAsStringSync();
   final exported = [
@@ -16,35 +17,60 @@ void main() {
       match[1]!,
   ];
   final options = File('dartdoc_options.yaml').readAsStringSync();
+  final declared = [
+    for (final match in RegExp(
+      r'^ {4}([a-z-]+):$',
+      multiLine: true,
+    ).allMatches(options))
+      match[1]!,
+  ];
+
+  /// The category of the types in the library file [path], from `lib/`:
+  /// its folder, except `operation/`, which M10 published as `operations`.
+  String categoryOf(String path) => switch (path.split('/')) {
+    ['src', 'operation', ...] => 'operations',
+    ['src', final folder, ...] => folder,
+    _ => throw ArgumentError.value(path, 'path', 'is not under lib/src'),
+  };
+
+  test('every category used is declared, and every one declared is used', () {
+    expect(declared.toSet(), exported.map(categoryOf).toSet());
+  });
 
-  test('the only category declared is operations', () {
-    final declared = [
+  test('every declared category has its guide', () {
+    for (final match in RegExp(r'markdown: (doc/\S+)').allMatches(options)) {
+      expect(File(match[1]!).existsSync(), isTrue, reason: match[1]);
+    }
+    expect(
+      RegExp('markdown: doc').allMatches(options),
+      hasLength(declared.length),
+    );
+  });
+
+  test('the category order lists every declared category once', () {
+    final order = [
       for (final match in RegExp(
-        r'^ {4}([a-z-]+):$',
+        r'^ {4}- ([a-z-]+)$',
         multiLine: true,
       ).allMatches(options))
         match[1]!,
     ];
-    expect(declared, ['operations']);
-  });
-
-  test('the category has its guide', () {
-    expect(options, contains('markdown: doc/operations.md'));
-    expect(File('doc/operations.md').existsSync(), isTrue);
+    expect(order, declared);
   });
 
   group('exported types', () {
     for (final path in exported) {
       test(path, () {
+        final tag = '{@category ${categoryOf(path)}}';
         final source = File('lib/$path').readAsStringSync();
         final untagged = [
           for (final type in const PublicTypes().declaredIn(source))
-            if (type.countOf('{@category operations}') != 1) type.name,
+            if (type.countOf(tag) != 1) type.name,
         ];
         expect(
           untagged,
           isEmpty,
-          reason: 'give each exactly one {@category operations} in its doc',
+          reason: 'give each exactly one $tag in its doc comment',
         );
       });
     }
```

Create `packages/typed_graphql_client/test/quality/import_rule.dart`:

```dart
/// The client's import rules (spec section 2, R0.5), checked on the text of
/// one library under `lib/`.
///
/// The client runs on the VM, AOT, dart2js and dart2wasm, so it imports pure
/// Dart, `meta`, the core's barrel and its own files, never `src/` of the
/// core, never `dart:io` or a web-only library.
final class ImportRule {
  /// Creates the rule.
  const ImportRule();

  /// The libraries that run on every platform the client supports.
  static const Set<String> _pureDart = {
    'dart:async',
    'dart:collection',
    'dart:convert',
    'dart:core',
    'dart:math',
    'dart:typed_data',
  };

  /// The package libraries the client may import.
  static const Set<String> _packages = {
    'package:typed_graphql/typed_graphql.dart',
  };

  static final RegExp _directive = RegExp(
    r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  /// The violations in [content], the text of the library at [filePath].
  List<String> check(String filePath, String content) => [
    for (final match in _directive.allMatches(content))
      ?_violation(filePath, match.group(1)!),
  ];

  String? _violation(String filePath, String target) {
    if (target.startsWith('dart:')) {
      return _pureDart.contains(target)
          ? null
          : '$filePath imports $target: the client is platform independent';
    }
    if (target.startsWith('package:meta/') || _packages.contains(target)) {
      return null;
    }
    if (target.startsWith('package:')) {
      return '$filePath imports $target: only meta and ${_packages.join(', ')} '
          'are allowed';
    }
    return null;
  }
}
```

Create `packages/typed_graphql_client/test/quality/imports_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'import_rule.dart';

void main() {
  const rule = ImportRule();

  group('ImportRule', () {
    test('allows pure Dart, meta, the core barrel and relative paths', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'dart:async';\n"
              "import 'dart:typed_data';\n"
              "import 'package:meta/meta.dart';\n"
              "import 'package:typed_graphql/typed_graphql.dart';\n"
              "import '../client/b.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects dart:io', () {
      expect(
        rule.check('lib/src/link/a.dart', "import 'dart:io';\n"),
        hasLength(1),
      );
    });

    test('rejects a web-only library', () {
      expect(
        rule.check('lib/src/link/a.dart', "import 'dart:js_interop';\n"),
        hasLength(1),
      );
    });

    test('rejects the core src folder', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'package:typed_graphql/src/protocol/json_value.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('rejects another package', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'package:web_socket_channel/web_socket_channel.dart';\n",
        ),
        hasLength(1),
      );
    });
  });

  test('lib follows the import rule', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      startsWith('name: typed_graphql_client\n'),
      reason: 'run from packages/typed_graphql_client',
    );
    final violations = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          ...rule.check(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/client/cancel_token_test.dart` does not compile: `CancelToken` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 0f44038..86b9c39 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -14,3 +14,5 @@
 - `JsonMerger` merges the JSON of a class and its fragments deeply (objects by
   key, arrays by index), so generated `toJson` keeps every field of
   overlapping nested selections; a null never replaces a value.
+- `CancelToken`: the caller's request to stop a call; the start of the
+  Client guide.
```

Modify `packages/typed_graphql_client/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/dartdoc_options.yaml b/packages/typed_graphql_client/dartdoc_options.yaml
index bc80a9d..af1311e 100644
--- a/packages/typed_graphql_client/dartdoc_options.yaml
+++ b/packages/typed_graphql_client/dartdoc_options.yaml
@@ -1,8 +1,12 @@
 dartdoc:
   categories:
+    client:
+      markdown: doc/client.md
+      displayName: Client
     operations:
       markdown: doc/operations.md
       displayName: Generated Operations
   categoryOrder:
+    - client
     - operations
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_client/doc/client.md`:

````markdown
# Client

`GraphQLClient` sends the operations `typed_graphql_codegen` generates and
returns typed responses. This guide grows with the client; this section
covers cancellation.

## Cancelling a call

A `CancelToken` belongs to the caller: create one, pass it to a call, and
cancel it when the answer is no longer needed. The client listens to it and
never cancels it.

```text
final token = CancelToken();
token.cancel('the user left the page');
token.isCancelled; // true
token.reason;      // 'the user left the page'
```

Only the first `cancel` has an effect, and `whenCancelled` completes, never
with an error, once the token is cancelled.
````

Create `packages/typed_graphql_client/lib/src/client/cancel_token.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

/// A request to stop a call, created and cancelled by the caller.
///
/// Pass one to `GraphQLClient.query`, `mutate` or `subscribe`; the client
/// listens to it and never cancels it. Cancelling it completes a pending
/// call with a `RequestCancelled` failure and ends the request in every
/// link: an HTTP request is aborted, a subscription is completed.
///
/// {@category client}
final class CancelToken {
  /// Creates a token that is not cancelled.
  CancelToken();

  final Completer<void> _completer = Completer<void>();
  List<void Function()>? _listeners;
  bool _isCancelled = false;
  Object? _reason;

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// What the first [cancel] was given, null before it or without a reason.
  Object? get reason => _reason;

  /// Completes, never with an error, when the token is cancelled; already
  /// complete for a token that was.
  Future<void> get whenCancelled => _completer.future;

  /// How many listeners wait for the token.
  @internal
  int get listenerCount => _listeners?.length ?? 0;

  /// Cancels the token with an optional [reason]. Only the first call has
  /// an effect.
  void cancel([Object? reason]) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _reason = reason;
    final listeners = _listeners;
    _listeners = null;
    _completer.complete();
    if (listeners != null) {
      for (final listener in listeners) {
        listener();
      }
    }
  }

  /// Calls [listener] when the token is cancelled, at once when it already
  /// is; returns a function that removes the listener, so a finished call
  /// leaves nothing behind.
  ///
  /// A listener must not throw: [cancel] calls them in turn. Every listener
  /// is the library's own, written not to.
  @internal
  void Function() addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }
    (_listeners ??= []).add(listener);
    return () => _listeners?.remove(listener);
  }
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index 3a8ad7f..211b0f9 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -7,6 +7,7 @@
 /// stage M11; see the package README.
 library;
 
+export 'src/client/cancel_token.dart';
 export 'src/operation/data_codec.dart';
 export 'src/operation/data_context.dart';
 export 'src/operation/data_enum.dart';
```

Modify `packages/typed_graphql_client/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/pubspec.yaml b/packages/typed_graphql_client/pubspec.yaml
index ab3d925..2e8a513 100644
--- a/packages/typed_graphql_client/pubspec.yaml
+++ b/packages/typed_graphql_client/pubspec.yaml
@@ -10,6 +10,7 @@ environment:
   sdk: ^3.13.0
 
 dependencies:
+  meta: ^1.15.0
   typed_graphql: ^0.0.1
 
 dev_dependencies:
```

- [ ] **Step 4: Format, then run the green check.**

This task changes a `pubspec.yaml`: run `flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart pub get'` at the root before anything else.

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
git commit -m "feat(typed_graphql_client): add CancelToken and the client import rule

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 3: feat(typed_graphql_client): add the ClientFailure family

**Why.** Spec section 5 (R8.2). The sealed `ClientFailure` family, one file because sealed subclasses share the library: every variant has its `DiagnosticCode` and a message, and `toString` is `<id>: <message>`. `ResponseFormatFailure`, `UnsupportedOperation` and `SocketFailure` take their code, checked against their range.

**Files** (verified commit `c1cc453` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/doc/client.md`
- Create `packages/typed_graphql_client/lib/src/client/client_failure.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/client/client_failure_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/client/client_failure_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  test('every failure kind has its code', () {
    final failures = <ClientFailure, DiagnosticCode>{
      const NetworkFailure(FormatException('x')): DiagnosticCode.networkFailure,
      HttpStatusFailure(502): DiagnosticCode.httpErrorStatus,
      ResponseFormatFailure(DiagnosticCode.responseTooLarge, 'too long'):
          DiagnosticCode.responseTooLarge,
      DataFormatFailure(const DecodeFailure('expected a string')):
          DiagnosticCode.dataShapeMismatch,
      const RequestCancelled(): DiagnosticCode.requestCancelled,
      const RequestTimedOut(Duration(seconds: 1)):
          DiagnosticCode.requestTimedOut,
      const UnsupportedOperation(
        DiagnosticCode.linkEndedWithoutResult,
        'no result',
      ): DiagnosticCode.linkEndedWithoutResult,
      const SocketFailure(DiagnosticCode.socketClosed, 'closed'):
          DiagnosticCode.socketClosed,
      const EventStreamFailure('unknown event'):
          DiagnosticCode.malformedEventStream,
      const AuthenticationFailure(FormatException('x')):
          DiagnosticCode.authenticationFailed,
    };
    for (final MapEntry(key: failure, value: code) in failures.entries) {
      expect(failure.code, code, reason: '$failure');
    }
  });

  test('toString is the id and the message', () {
    expect(
      HttpStatusFailure(503).toString(),
      'GQL461: The server answered with HTTP status 503.',
    );
  });

  test('a network failure names its cause', () {
    expect(
      const NetworkFailure(FormatException('reset')).message,
      'The request failed: FormatException: reset',
    );
  });

  test('a cancelled request names its reason when it has one', () {
    expect(const RequestCancelled().message, 'The request was cancelled.');
    expect(
      const RequestCancelled('left').message,
      'The request was cancelled: left',
    );
  });

  test('a data format failure prints the path of the decode failure', () {
    final failure = DataFormatFailure(
      const DecodeFailure('expected a string', path: [PathKey('name')]),
    );
    expect(
      failure.message,
      r'The data does not fit the operation: $.name: expected a string',
    );
  });

  test('the lists and maps a failure holds cannot be modified', () {
    final status = HttpStatusFailure(500, headers: {'a': 'b'});
    final format = ResponseFormatFailure(
      DiagnosticCode.malformedResponse,
      'bad',
      path: [const PathKey('data')],
    );
    final data = DataFormatFailure(
      const DecodeFailure('bad'),
      errors: [GraphQLError('boom')],
    );
    expect(() => status.headers['c'] = 'd', throwsUnsupportedError);
    expect(() => format.path.add(const PathIndex(0)), throwsUnsupportedError);
    expect(data.errors.clear, throwsUnsupportedError);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/client/client_failure_test.dart` does not compile: `ClientFailure` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 86b9c39..2fd366c 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -16,3 +16,7 @@
   overlapping nested selections; a null never replaces a value.
 - `CancelToken`: the caller's request to stop a call; the start of the
   Client guide.
+- `ClientFailure`, a sealed family with a code each: `NetworkFailure`,
+  `HttpStatusFailure`, `ResponseFormatFailure`, `DataFormatFailure`,
+  `RequestCancelled`, `RequestTimedOut`, `UnsupportedOperation`,
+  `SocketFailure`, `EventStreamFailure`, `AuthenticationFailure`.
```

Modify `packages/typed_graphql_client/doc/client.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/doc/client.md b/packages/typed_graphql_client/doc/client.md
index 7638916..babaa60 100644
--- a/packages/typed_graphql_client/doc/client.md
+++ b/packages/typed_graphql_client/doc/client.md
@@ -1,8 +1,28 @@
 # Client
 
 `GraphQLClient` sends the operations `typed_graphql_codegen` generates and
-returns typed responses. This guide grows with the client; this section
-covers cancellation.
+returns typed responses. This guide grows with the client; these sections
+cover failures and cancellation.
+
+## Failures
+
+When a request gets no GraphQL response, the client reports why as a
+`ClientFailure`, a sealed family whose every kind has a stable `code`:
+
+| Failure | Code | When |
+|---|---|---|
+| `NetworkFailure` | `GQL460` | the transport threw or the connection was lost |
+| `HttpStatusFailure` | `GQL461` | an HTTP status outside 2xx without a GraphQL body |
+| `ResponseFormatFailure` | `GQL462`-`GQL464` | an unreadable content type, a body too long, a body that is not a GraphQL response |
+| `DataFormatFailure` | `GQL465` | `data` that does not fit the operation's classes |
+| `RequestCancelled` | `GQL466` | the caller cancelled |
+| `RequestTimedOut` | `GQL467` | a link's timeout passed |
+| `UnsupportedOperation` | `GQL468`, `GQL469` | no link can carry the request, or the chain ended without a result |
+| `SocketFailure` | `GQL470`-`GQL472` | a WebSocket broke the protocol, closed for good or was not acknowledged |
+| `EventStreamFailure` | `GQL473` | a server-sent event stream broke the protocol |
+| `AuthenticationFailure` | `GQL474` | the token callback threw |
+
+Nothing a server or a network does makes the client throw.
 
 ## Cancelling a call
 
```

Create `packages/typed_graphql_client/lib/src/client/client_failure.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Why a request got no GraphQL response: the transport failed, the answer
/// was not a GraphQL response, the data did not fit the operation, or the
/// caller stopped it (R8.2).
///
/// Every failure is a value with a stable [code] (`GQL460`-`GQL474`);
/// nothing a server or a network does makes the client throw (R0.3).
///
/// {@category client}
sealed class ClientFailure {
  /// Creates a failure.
  const ClientFailure();

  /// The diagnostic code of this kind of failure.
  DiagnosticCode get code;

  /// What happened, as a sentence.
  String get message;

  @override
  String toString() => '${code.id}: $message';
}

/// The transport could not send the request or read the answer (`GQL460`).
///
/// {@category client}
final class const NetworkFailure(
  /// What the HTTP client or the socket threw.
  final Exception cause,
) extends ClientFailure {
  /// Creates the failure for [cause].
  this;

  @override
  DiagnosticCode get code => .networkFailure;

  @override
  String get message => 'The request failed: $cause';
}

/// An HTTP answer with a status outside 2xx whose body is not a GraphQL
/// response (`GQL461`).
///
/// {@category client}
final class HttpStatusFailure(
  /// The HTTP status code.
  final int statusCode, {
  Map<String, String> headers = const {},
}) extends ClientFailure {
  /// Creates the failure for [statusCode]; [headers] is copied.
  this;

  /// The answer's headers, names in lower case.
  final Map<String, String> headers = Map.unmodifiable(headers);

  @override
  DiagnosticCode get code => .httpErrorStatus;

  @override
  String get message => 'The server answered with HTTP status $statusCode.';
}

/// An answer that is not a GraphQL response: an unreadable content type
/// (`GQL462`), too long (`GQL463`) or malformed (`GQL464`).
///
/// {@category client}
final class ResponseFormatFailure(
  @override final DiagnosticCode code,
  @override final String message, {
  List<PathSegment> path = const [],
}) extends ClientFailure {
  /// Creates the failure; [path] is copied.
  this;

  /// Where in the JSON body the problem is; empty for the body itself.
  final List<PathSegment> path = List.unmodifiable(path);
}

/// A response whose `data` does not have the shape of the operation's
/// generated classes (`GQL465`).
///
/// {@category client}
final class DataFormatFailure(
  /// What the generated reader found, and where in `data`.
  final DecodeFailure decodeFailure, {
  List<GraphQLError> errors = const [],
}) extends ClientFailure {
  /// Creates the failure; [errors] is copied.
  this;

  /// The errors the server sent with the data, kept for diagnosis.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  @override
  DiagnosticCode get code => .dataShapeMismatch;

  @override
  String get message => 'The data does not fit the operation: $decodeFailure';
}

/// The caller cancelled the request before its answer (`GQL466`).
///
/// {@category client}
final class const RequestCancelled([
  /// What the caller gave `CancelToken.cancel`, if anything.
  final Object? reason,
]) extends ClientFailure {
  /// Creates the failure.
  this;

  @override
  DiagnosticCode get code => .requestCancelled;

  @override
  String get message => reason == null
      ? 'The request was cancelled.'
      : 'The request was cancelled: $reason';
}

/// A link's timeout passed before the answer (`GQL467`).
///
/// {@category client}
final class const RequestTimedOut(
  /// The timeout that passed.
  final Duration timeout,
) extends ClientFailure {
  /// Creates the failure.
  this;

  @override
  DiagnosticCode get code => .requestTimedOut;

  @override
  String get message => 'No answer within ${timeout.inMilliseconds} ms.';
}

/// A link chain that cannot carry the request (`GQL468`) or that ended
/// without a result (`GQL469`).
///
/// {@category client}
final class const UnsupportedOperation(
  @override final DiagnosticCode code,
  @override final String message,
) extends ClientFailure {
  /// Creates the failure.
  this;
}

/// A graphql-transport-ws socket that broke the protocol (`GQL470`), closed
/// for good (`GQL471`) or was not acknowledged in time (`GQL472`).
///
/// {@category client}
final class const SocketFailure(
  @override final DiagnosticCode code,
  @override final String message, {

  /// The close code of the socket, when it closed.
  final int? closeCode,

  /// The close reason of the socket, when it gave one.
  final String? closeReason,
}) extends ClientFailure {
  /// Creates the failure.
  this;
}

/// A graphql-sse stream with an unknown event or without its `complete`
/// (`GQL473`).
///
/// {@category client}
final class const EventStreamFailure(@override final String message)
    extends ClientFailure {
  /// Creates the failure.
  this;

  @override
  DiagnosticCode get code => .malformedEventStream;
}

/// The callback that gives or refreshes an authentication token threw
/// (`GQL474`).
///
/// {@category client}
final class const AuthenticationFailure(
  /// What the callback threw.
  final Exception cause,
) extends ClientFailure {
  /// Creates the failure for [cause].
  this;

  @override
  DiagnosticCode get code => .authenticationFailed;

  @override
  String get message => 'Could not get a token: $cause';
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index 211b0f9..b286909 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -8,6 +8,7 @@
 library;
 
 export 'src/client/cancel_token.dart';
+export 'src/client/client_failure.dart';
 export 'src/operation/data_codec.dart';
 export 'src/operation/data_context.dart';
 export 'src/operation/data_enum.dart';
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
git commit -m "feat(typed_graphql_client): add the ClientFailure family

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 4: feat(typed_graphql_client): add link requests, results and context

**Why.** Spec section 6. `LinkRequest` (built from a generated operation with `LinkRequest.of`; `body` is the core `GraphQLRequest` as sent), the sealed `LinkResult` (`LinkPayload`, `LinkFailure`), `LinkContext` (immutable entries, `entry<T>()` is the last entry of type `T`, `withEntry` replaces the exact runtime type), `ContextEntry`, `RequestHeaders` (lower-case names) and `HttpResponseInfo`. Adds the `link` category and the test operations every later test uses.

**Files** (verified commit `e8c70fb` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/dartdoc_options.yaml`
- Create `packages/typed_graphql_client/doc/links.md`
- Create `packages/typed_graphql_client/lib/src/link/context_entry.dart`
- Create `packages/typed_graphql_client/lib/src/link/http_response_info.dart`
- Create `packages/typed_graphql_client/lib/src/link/link_context.dart`
- Create `packages/typed_graphql_client/lib/src/link/link_request.dart`
- Create `packages/typed_graphql_client/lib/src/link/link_result.dart`
- Create `packages/typed_graphql_client/lib/src/link/request_headers.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/link/link_context_test.dart`
- Create `packages/typed_graphql_client/test/link/link_request_test.dart`
- Create `packages/typed_graphql_client/test/support/test_operations.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/link/link_context_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class Tag extends ContextEntry {
  const Tag(this.name);

  final String name;
}

final class OtherTag extends Tag {
  const OtherTag(super.name);
}

void main() {
  group('LinkContext', () {
    test('an empty context has no entry', () {
      expect(const LinkContext.empty().entry<Tag>(), isNull);
    });

    test('entry gives the last entry of the type', () {
      final context = LinkContext([const Tag('a'), const Tag('b')]);
      expect(context.entry<Tag>()?.name, 'b');
    });

    test('entry finds a subtype', () {
      final context = LinkContext([const OtherTag('a')]);
      expect(context.entry<Tag>()?.name, 'a');
    });

    test('withEntry replaces the entries of the same exact type', () {
      final context = LinkContext([
        const Tag('a'),
        const OtherTag('b'),
      ]).withEntry(const Tag('c'));
      expect(
        [
          for (final entry in context.entries) (entry as Tag).name,
        ],
        ['b', 'c'],
      );
    });

    test('withEntry leaves the original unchanged', () {
      final original = LinkContext([const Tag('a')]);
      original.withEntry(const Tag('b'));
      expect(original.entry<Tag>()?.name, 'a');
    });

    test('the entries cannot be modified', () {
      final context = LinkContext([const Tag('a')]);
      expect(() => context.entries.add(const Tag('b')), throwsUnsupportedError);
    });
  });

  group('RequestHeaders', () {
    test('lower-cases the names', () {
      expect(RequestHeaders({'X-Trace': '1'}).values, {'x-trace': '1'});
    });

    test('withHeader replaces a value whatever its case', () {
      final headers = RequestHeaders({
        'Authorization': 'a',
      }).withHeader('AUTHORIZATION', 'b');
      expect(headers.values, {'authorization': 'b'});
    });
  });

  test('HttpResponseInfo copies its headers', () {
    final headers = {'etag': '1'};
    final info = HttpResponseInfo(200, headers: headers);
    headers['etag'] = '2';
    expect(info.headers, {'etag': '1'});
  });
}
```

Create `packages/typed_graphql_client/test/link/link_request_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  test('of reads the document and the variables of an operation', () {
    final request = LinkRequest.of(const GreetQuery('Ada'));
    expect(request.document, GreetQuery.operationDocument);
    expect(request.variables, JsonObject({'name': const JsonString('Ada')}));
    expect(request.type, OperationType.query);
  });

  test('the body holds the text, the name and the variables', () {
    final request = LinkRequest.of(const GreetQuery('Ada'));
    expect(
      request.body,
      GraphQLRequest(
        query: GreetQuery.operationDocument.text,
        operationName: 'Greet',
        variables: JsonObject({'name': const JsonString('Ada')}),
      ),
    );
  });

  test('the body has no variables when there are none', () {
    expect(LinkRequest.of(const HelloQuery()).body.variables, isNull);
  });

  test('the body has no query when the text is not sent', () {
    final request = LinkRequest.of(
      const HelloQuery(),
    ).withDocumentText(sendsDocumentText: false);
    expect(request.body.query, isNull);
    expect(request.body.operationName, 'Hello');
  });

  test('withExtensions puts the extensions in the body', () {
    final extensions = JsonObject({'trace': const JsonBool(true)});
    final request = LinkRequest.of(
      const HelloQuery(),
    ).withExtensions(extensions);
    expect(request.body.extensions, extensions);
  });

  test('withContext keeps everything else', () {
    final context = LinkContext([
      RequestHeaders({'a': 'b'}),
    ]);
    final request = LinkRequest.of(const GreetQuery('Ada'))
        .withExtensions(JsonObject(const {}))
        .withDocumentText(sendsDocumentText: false)
        .withContext(context);
    expect(request.context, same(context));
    expect(request.extensions, JsonObject(const {}));
    expect(request.sendsDocumentText, isFalse);
    expect(request.variables, JsonObject({'name': const JsonString('Ada')}));
  });

  test('a result is a payload or a failure', () {
    final results = <LinkResult>[
      LinkPayload(ExecutionResult(JsonObject(const {}))),
      const LinkFailure(RequestCancelled()),
    ];
    expect(
      [
        for (final result in results)
          switch (result) {
            LinkPayload() => 'payload',
            LinkFailure() => 'failure',
          },
      ],
      ['payload', 'failure'],
    );
  });
}
```

Create `packages/typed_graphql_client/test/support/test_operations.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

/// `query Hello{hello}`: data is the string `hello`.
final class HelloQuery extends GraphQLQuery<String> {
  /// Creates the query.
  const HelloQuery();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Hello',
    type: OperationType.query,
    text: 'query Hello{hello}',
    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('hello').read(data);
}

/// `query Greet($name:String!){greet(name:$name)}`.
final class GreetQuery extends GraphQLQuery<String> {
  /// Creates the query for [name].
  const GreetQuery(this.name);

  /// The `name` variable.
  final String name;

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Greet',
    type: OperationType.query,
    text: r'query Greet($name:String!){greet(name:$name)}',
    sha256: '4e2feb1a6790b6f16d7d1340acb4e70d97fa0dc940e6a43cd2ff8c5f4d31f550',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject({'name': JsonString(name)});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('greet').read(data);
}

/// `mutation Rename($name:String!){rename(name:$name)}`.
final class RenameMutation extends GraphQLMutation<String> {
  /// Creates the mutation for [name].
  const RenameMutation(this.name);

  /// The `name` variable.
  final String name;

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Rename',
    type: OperationType.mutation,
    text: r'mutation Rename($name:String!){rename(name:$name)}',
    sha256: '1bb30d2c80d17cea066ae8454207397630d460ca2084e2917961574f25b98386',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject({'name': JsonString(name)});

  @override
  DecodeResult<String> decodeData(JsonObject data) =>
      const StringField('rename').read(data);
}

/// `subscription Ticks{ticks}`: data is the integer `ticks`.
final class TicksSubscription extends GraphQLSubscription<int> {
  /// Creates the subscription.
  const TicksSubscription();

  /// The document, as M10 would generate it.
  static const OperationDocument operationDocument = OperationDocument(
    name: 'Ticks',
    type: OperationType.subscription,
    text: 'subscription Ticks{ticks}',
    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
  );

  @override
  OperationDocument get document => operationDocument;

  @override
  JsonObject get variablesJson => JsonObject(const {});

  @override
  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
  };
}

/// Reads one string field of `data`, as a generated reader would.
final class StringField {
  /// Creates the reader of [name].
  const StringField(this.name);

  /// The field's response name.
  final String name;

  /// The string at [name] in [data], or a failure at its path.
  DecodeResult<String> read(JsonObject data) => switch (data[name]) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => DecodeFailure('expected a string', path: [PathKey(name)]),
  };
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/link/link_request_test.dart` and `link_context_test.dart` do not compile: `LinkRequest` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 2fd366c..ad1d859 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -20,3 +20,6 @@
   `HttpStatusFailure`, `ResponseFormatFailure`, `DataFormatFailure`,
   `RequestCancelled`, `RequestTimedOut`, `UnsupportedOperation`,
   `SocketFailure`, `EventStreamFailure`, `AuthenticationFailure`.
+- `LinkRequest`, `LinkResult` (`LinkPayload`, `LinkFailure`), `LinkContext`,
+  `ContextEntry`, `RequestHeaders` and `HttpResponseInfo`; the start of the
+  Links guide.
```

Modify `packages/typed_graphql_client/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/dartdoc_options.yaml b/packages/typed_graphql_client/dartdoc_options.yaml
index af1311e..4228e24 100644
--- a/packages/typed_graphql_client/dartdoc_options.yaml
+++ b/packages/typed_graphql_client/dartdoc_options.yaml
@@ -3,10 +3,14 @@ dartdoc:
     client:
       markdown: doc/client.md
       displayName: Client
+    link:
+      markdown: doc/links.md
+      displayName: Links
     operations:
       markdown: doc/operations.md
       displayName: Generated Operations
   categoryOrder:
     - client
+    - link
     - operations
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_client/doc/links.md`:

````markdown
# Links

A request goes from the client through a chain of links to a terminating
link that talks to the server. This guide grows with the links; this
section covers what travels through them.

## Requests, results and context

A `LinkRequest` holds the operation's `document` (name, type, text and
hash), its `variables`, optional `extensions` and a `LinkContext`. Its
`body` is the request as it is sent. It is immutable: a link forwards a
copy made with `withContext`, `withExtensions` or `withDocumentText`.

A link answers with a stream of `LinkResult` values: a `LinkPayload` (the
response as the server sent it) or a `LinkFailure` (a `ClientFailure`).
Failures are values, never stream errors.

A `LinkContext` holds `ContextEntry` values; `entry<T>()` reads the last
entry of a type and `withEntry` gives a new context with an entry
replaced. Two entries come with the client: `RequestHeaders` adds HTTP
headers to one request, and `HttpResponseInfo` tells the status and the
headers of the answer a result came from.

```text
final context = LinkContext([RequestHeaders({'X-Trace': 'abc'})]);
context.entry<RequestHeaders>()?.values; // {x-trace: abc}
```
````

Create `packages/typed_graphql_client/lib/src/link/context_entry.dart`:

```dart
/// One piece of per-request information that links read and write, such as
/// extra headers or the HTTP status of the answer.
///
/// A link that needs its own information defines a class that extends this
/// one and reads it with `LinkContext.entry`.
///
/// {@category link}
abstract class ContextEntry {
  /// Creates an entry.
  const ContextEntry();
}
```

Create `packages/typed_graphql_client/lib/src/link/http_response_info.dart`:

```dart
import 'context_entry.dart';

/// The HTTP status and headers of the answer a result came from, written
/// by the HTTP and SSE links on the result's context.
///
/// {@category link}
final class HttpResponseInfo(
  /// The HTTP status code.
  final int statusCode, {
  Map<String, String> headers = const {},
}) extends ContextEntry {
  /// Creates the entry; [headers] is copied.
  this;

  /// The answer's headers, names in lower case.
  final Map<String, String> headers = Map.unmodifiable(headers);

  @override
  String toString() => 'HttpResponseInfo($statusCode)';
}
```

Create `packages/typed_graphql_client/lib/src/link/link_context.dart`:

```dart
import 'context_entry.dart';

/// The per-request information that travels with a request through the
/// links and back with its result: a list of [ContextEntry] values.
///
/// It is immutable: [withEntry] gives a new context. The client's cache
/// (M12) will carry its fetch policy here too.
///
/// {@category link}
final class LinkContext {
  /// Creates a context holding [entries], copied.
  LinkContext(Iterable<ContextEntry> entries)
    : entries = List.unmodifiable(entries);

  /// The context without entries.
  const LinkContext.empty() : entries = const [];

  /// The entries, in the order they were added.
  final List<ContextEntry> entries;

  /// The last entry that is a [T], or null when there is none.
  T? entry<T extends ContextEntry>() {
    for (final entry in entries.reversed) {
      if (entry is T) {
        return entry;
      }
    }
    return null;
  }

  /// This context with [entry] in place of the entries of its exact type.
  LinkContext withEntry(ContextEntry entry) => LinkContext([
    for (final existing in entries)
      if (existing.runtimeType != entry.runtimeType) existing,
    entry,
  ]);

  @override
  String toString() => 'LinkContext($entries)';
}
```

Create `packages/typed_graphql_client/lib/src/link/link_request.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../operation/graphql_operation.dart';
import '../operation/operation_document.dart';
import 'link_context.dart';

/// A request as it goes through the links: the operation's document and
/// variables, extensions, and the per-request [context].
///
/// It is immutable; a link that changes something forwards a copy made
/// with [withContext], [withExtensions] or [withDocumentText].
///
/// {@category link}
final class LinkRequest({
  /// The document of the operation, with its name, type and hash.
  required final OperationDocument document,

  /// The values of the operation's variables.
  required final JsonObject variables,

  /// Extra data for the server, such as a persisted query hash.
  final JsonObject? extensions,

  /// The per-request information links read and write.
  final LinkContext context = const LinkContext.empty(),

  /// Whether the document text is sent; the persisted query link turns
  /// it off to send the hash alone.
  final bool sendsDocumentText = true,
}) {
  /// Creates a request.
  this;

  /// The request for [operation] with [context].
  LinkRequest.of(
    GraphQLOperation<Object> operation, {
    LinkContext context = const LinkContext.empty(),
  }) : this(
         document: operation.document,
         variables: operation.variablesJson,
         context: context,
       );

  /// Whether the operation is a query, a mutation or a subscription.
  OperationType get type => document.type;

  /// The request as it is sent: without `query` when [sendsDocumentText]
  /// is false, without `variables` when there are none.
  GraphQLRequest get body => GraphQLRequest(
    query: sendsDocumentText ? document.text : null,
    operationName: document.name,
    variables: variables.fields.isEmpty ? null : variables,
    extensions: extensions,
  );

  /// This request with [context] in place of its own.
  LinkRequest withContext(LinkContext context) => LinkRequest(
    document: document,
    variables: variables,
    extensions: extensions,
    context: context,
    sendsDocumentText: sendsDocumentText,
  );

  /// This request with [extensions] in place of its own.
  LinkRequest withExtensions(JsonObject? extensions) => LinkRequest(
    document: document,
    variables: variables,
    extensions: extensions,
    context: context,
    sendsDocumentText: sendsDocumentText,
  );

  /// This request sending its document text or not.
  LinkRequest withDocumentText({required bool sendsDocumentText}) =>
      LinkRequest(
        document: document,
        variables: variables,
        extensions: extensions,
        context: context,
        sendsDocumentText: sendsDocumentText,
      );

  @override
  String toString() => 'LinkRequest(${document.name})';
}
```

Create `packages/typed_graphql_client/lib/src/link/link_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import 'link_context.dart';

/// One event of a link's answer: a GraphQL response, or why there is none.
///
/// Links report failures as [LinkFailure] values, never as stream errors.
///
/// {@category link}
sealed class LinkResult {
  /// Creates a result.
  const LinkResult();
}

/// A GraphQL response, untyped, with what the terminating link learned
/// about it in [context].
///
/// {@category link}
final class const LinkPayload(
  /// The response as the server sent it.
  final ResponsePayload payload, {

  /// Information about the answer, such as `HttpResponseInfo`.
  final LinkContext context = const LinkContext.empty(),
}) extends LinkResult {
  /// Creates a payload result.
  this;

  @override
  String toString() => 'LinkPayload($payload)';
}

/// A request that got no GraphQL response, and why.
///
/// {@category link}
final class const LinkFailure(
  /// Why there is no response.
  final ClientFailure failure,
) extends LinkResult {
  /// Creates a failure result.
  this;

  @override
  String toString() => 'LinkFailure($failure)';
}
```

Create `packages/typed_graphql_client/lib/src/link/request_headers.dart`:

```dart
import 'context_entry.dart';

/// Extra HTTP headers for one request, added by the HTTP and SSE links
/// after their own and the link's (R8.4).
///
/// Header names are case-insensitive, so they are kept in lower case.
///
/// {@category link}
final class RequestHeaders extends ContextEntry {
  /// Creates the entry for [values]; the names are lower-cased.
  RequestHeaders(Map<String, String> values)
    : values = Map.unmodifiable({
        for (final MapEntry(:key, :value) in values.entries)
          key.toLowerCase(): value,
      });

  /// The headers, names in lower case.
  final Map<String, String> values;

  /// These headers with [name] set to [value], replacing any earlier value.
  RequestHeaders withHeader(String name, String value) =>
      RequestHeaders({...values, name.toLowerCase(): value});

  @override
  String toString() => 'RequestHeaders($values)';
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index b286909..f21cd34 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -9,6 +9,12 @@ library;
 
 export 'src/client/cancel_token.dart';
 export 'src/client/client_failure.dart';
+export 'src/link/context_entry.dart';
+export 'src/link/http_response_info.dart';
+export 'src/link/link_context.dart';
+export 'src/link/link_request.dart';
+export 'src/link/link_result.dart';
+export 'src/link/request_headers.dart';
 export 'src/operation/data_codec.dart';
 export 'src/operation/data_context.dart';
 export 'src/operation/data_enum.dart';
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
git commit -m "feat(typed_graphql_client): add link requests, results and context

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 5: feat(typed_graphql_client): add Link, Link.from and MockLink

**Why.** Spec sections 6 and 8 (R8.3, R8.5). `Link` and `NextLink`; `Link.from` chains links through the internal `LinkChain` (an empty list is an `ArgumentError`, forwarding past the last link is a `StateError` stream). `MockLink` serves queued answers first in, first out, by operation name, records every request and answers a request with no queued answer with a `StateError` (a test bug).

**Files** (verified commit `1a36505` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/doc/links.md`
- Create `packages/typed_graphql_client/lib/src/link/link.dart`
- Create `packages/typed_graphql_client/lib/src/link/link_chain.dart`
- Create `packages/typed_graphql_client/lib/src/link/mock_link.dart`
- Create `packages/typed_graphql_client/lib/src/link/next_link.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/link/link_test.dart`
- Create `packages/typed_graphql_client/test/link/mock_link_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/link/link_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// Adds its [name] to the `x-trail` header, then forwards.
final class TrailLink extends Link {
  const TrailLink(this.name);

  final String name;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final headers =
        request.context.entry<RequestHeaders>() ?? RequestHeaders(const {});
    final trail = headers.values['x-trail'];
    return forward(
      request.withContext(
        request.context.withEntry(
          headers.withHeader('x-trail', trail == null ? name : '$trail,$name'),
        ),
      ),
    );
  }
}

/// Answers with the request's `x-trail` header as `data.trail`.
final class EchoLink extends Link {
  const EchoLink();

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final trail = request.context.entry<RequestHeaders>()?.values['x-trail'];
    return Stream.value(
      LinkPayload(ExecutionResult(JsonObject({'trail': JsonString('$trail')}))),
    );
  }
}

void main() {
  final request = LinkRequest.of(const HelloQuery());

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  Future<String> trailOf(Stream<LinkResult> results) async =>
      switch (await results.single) {
        LinkPayload(payload: ExecutionResult(:final data?)) =>
          (data['trail']! as JsonString).value,
        final other => fail('unexpected $other'),
      };

  test('from runs the links in order', () async {
    final link = Link.from([
      const TrailLink('a'),
      const TrailLink('b'),
      const EchoLink(),
    ]);
    expect(await trailOf(link.request(request, unterminated)), 'a,b');
  });

  test('from of one link is that link', () {
    const link = EchoLink();
    expect(Link.from([link]), same(link));
  });

  test('from of no link is an ArgumentError', () {
    expect(() => Link.from([]), throwsArgumentError);
  });

  test('the last link of a chain forwards to the chain\'s forward', () async {
    final inner = Link.from([const TrailLink('a'), const TrailLink('b')]);
    final outer = Link.from([inner, const TrailLink('c'), const EchoLink()]);
    expect(await trailOf(outer.request(request, unterminated)), 'a,b,c');
  });

  test('a chain that ends with a middle link reaches forward', () {
    final link = Link.from([const TrailLink('a'), const TrailLink('b')]);
    expect(link.request(request, unterminated).first, throwsStateError);
  });
}
```

Create `packages/typed_graphql_client/test/link/mock_link_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  final hello = LinkRequest.of(const HelloQuery());
  final greet = LinkRequest.of(const GreetQuery('Ada'));

  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  JsonObject? dataOf(LinkResult result) => switch (result) {
    LinkPayload(payload: ExecutionResult(:final data)) => data,
    _ => null,
  };

  test('records every request in order', () async {
    final link = MockLink()
      ..addData(JsonObject(const {}))
      ..addData(JsonObject(const {}));
    await link.request(hello, unterminated).drain<void>();
    await link.request(greet, unterminated).drain<void>();
    expect(
      [
        for (final request in link.requests) request.document.name,
      ],
      ['Hello', 'Greet'],
    );
  });

  test('answers in the order the answers were queued', () async {
    final link = MockLink()
      ..addData(JsonObject({'n': JsonNumber(1)}))
      ..addData(JsonObject({'n': JsonNumber(2)}));
    final first = await link.request(hello, unterminated).single;
    final second = await link.request(hello, unterminated).single;
    expect([first, second].map(dataOf), [
      JsonObject({'n': JsonNumber(1)}),
      JsonObject({'n': JsonNumber(2)}),
    ]);
  });

  test('an answer for an operation skips the others', () async {
    final link = MockLink()
      ..addData(
        JsonObject({'for': const JsonString('Greet')}),
        operationName: 'Greet',
      )
      ..addData(JsonObject({'for': const JsonString('any')}));
    final result = await link.request(hello, unterminated).single;
    expect(dataOf(result), JsonObject({'for': const JsonString('any')}));
    expect(link.pendingAnswerCount, 1);
  });

  test('addErrors queues a request error result', () async {
    final link = MockLink()..addErrors([GraphQLError('bad')]);
    final result = await link.request(hello, unterminated).single;
    expect(
      result,
      isA<LinkPayload>().having(
        (payload) => payload.payload,
        'payload',
        RequestErrorResult(errors: [GraphQLError('bad')]),
      ),
    );
  });

  test('addFailure queues a failure', () async {
    final link = MockLink()..addFailure(const RequestTimedOut(Duration.zero));
    final result = await link.request(hello, unterminated).single;
    expect(
      result,
      isA<LinkFailure>().having(
        (failure) => failure.failure,
        'failure',
        isA<RequestTimedOut>(),
      ),
    );
  });

  test('addStream serves every event of a stream', () async {
    final link = MockLink()
      ..addStream(
        Stream.fromIterable([
          LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(1)}))),
          LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(2)}))),
        ]),
      );
    final results = await link
        .request(LinkRequest.of(const TicksSubscription()), unterminated)
        .toList();
    expect(results, hasLength(2));
  });

  test('a request with no answer gets a StateError', () {
    expect(MockLink().request(hello, unterminated).first, throwsStateError);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/link/link_test.dart` and `mock_link_test.dart` do not compile: `Link` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index ad1d859..719ece4 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -23,3 +23,6 @@
 - `LinkRequest`, `LinkResult` (`LinkPayload`, `LinkFailure`), `LinkContext`,
   `ContextEntry`, `RequestHeaders` and `HttpResponseInfo`; the start of the
   Links guide.
+- `Link`, `NextLink` and `Link.from` (a chain), and `MockLink`, a
+  terminating link for tests that records requests and serves queued
+  answers (R8.5).
```

Modify `packages/typed_graphql_client/doc/links.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_client/doc/links.md b/packages/typed_graphql_client/doc/links.md
index 64a3298..049e980 100644
--- a/packages/typed_graphql_client/doc/links.md
+++ b/packages/typed_graphql_client/doc/links.md
@@ -25,3 +25,34 @@ headers of the answer a result came from.
 final context = LinkContext([RequestHeaders({'X-Trace': 'abc'})]);
 context.entry<RequestHeaders>()?.values; // {x-trace: abc}
 ```
+
+## Writing a link
+
+A link extends `Link` and implements `request(request, forward)`. A middle
+link calls `forward` with the request, changed or not, and returns the
+answer, changed or not; a terminating link answers itself. `Link.from`
+runs links in order: each one's `forward` calls the next.
+
+```text
+final class TraceLink extends Link {
+  @override
+  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
+    final headers = request.context.entry<RequestHeaders>() ?? RequestHeaders({});
+    return forward(request.withContext(
+      request.context.withEntry(headers.withHeader('x-trace', 'abc')),
+    ));
+  }
+}
+```
+
+Cancelling the subscription to a link's stream must end what the link
+started: a link built from stream operations (`map`, `asyncExpand`,
+`async*`) does so by itself.
+
+## Testing with MockLink
+
+`MockLink` is a terminating link for tests: it records every request in
+`requests` and answers each with the next queued answer. `addData`,
+`addErrors`, `addFailure` and `add` queue one result, `addStream` many; an
+`operationName` makes an answer serve only that operation. A request with
+no answer left gets a `StateError`, a bug in the test.
````

Create `packages/typed_graphql_client/lib/src/link/link.dart`:

```dart
import 'link_chain.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// One step between the client and the server (R8.3): it may change a
/// request, answer it, or forward it and change the answer.
///
/// A middle link calls `forward`; a terminating link (`HttpLink`,
/// `MockLink`, ...) ignores it and talks to a server. [request] returns a
/// stream: one event for a query or a mutation, many for a subscription.
/// Failures are [LinkFailure] events, never stream errors. Cancelling the
/// subscription to the stream ends the request in every link: a link that
/// holds a resource releases it in the stream's `onCancel`.
///
/// {@category link}
abstract base class Link {
  /// Creates a link.
  const Link();

  /// The answer to [request]; [forward] sends a request to the rest of the
  /// chain.
  Stream<LinkResult> request(LinkRequest request, NextLink forward);

  /// One link that runs [links] in order: each one's `forward` calls the
  /// next, and the last one's calls the `forward` of the chain. An empty
  /// list is an [ArgumentError].
  static Link from(List<Link> links) => switch (links) {
    [] => throw ArgumentError.value(links, 'links', 'is empty'),
    [final link] => link,
    _ => LinkChain(links),
  };
}
```

Create `packages/typed_graphql_client/lib/src/link/link_chain.dart`:

```dart
import 'link.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// Links run in order, built by [Link.from].
final class LinkChain extends Link {
  /// Creates the chain of [links], copied.
  LinkChain(List<Link> links) : _links = List.unmodifiable(links);

  final List<Link> _links;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      _from(0, request, forward);

  /// The answer of the links from [index] on; past the last, [forward].
  Stream<LinkResult> _from(int index, LinkRequest request, NextLink forward) {
    if (index == _links.length) {
      return forward(request);
    }
    return _links[index].request(
      request,
      (next) => _from(index + 1, next, forward),
    );
  }
}
```

Create `packages/typed_graphql_client/lib/src/link/mock_link.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../client/client_failure.dart';
import 'link.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// A terminating link for tests (R8.5): it records every request and
/// answers each with the next queued answer for its operation.
///
/// An answer queued with an `operationName` serves only that operation;
/// one without serves any. Answers are used once, first in, first out. A
/// request with no answer left gets a stream with a [StateError]: a bug in
/// the test, not a response.
///
/// {@category link}
final class MockLink extends Link {
  /// Creates a link with no answer queued.
  MockLink();

  final List<LinkRequest> _requests = [];
  final List<({String? operationName, Stream<LinkResult> Function() open})>
  _answers = [];

  /// Every request received, in order.
  List<LinkRequest> get requests => List.unmodifiable(_requests);

  /// How many queued answers no request has used yet.
  int get pendingAnswerCount => _answers.length;

  /// Queues [result] as one answer.
  void add(LinkResult result, {String? operationName}) => _answers.add((
    operationName: operationName,
    open: () => Stream.value(result),
  ));

  /// Queues an execution result holding [data] and [errors].
  void addData(
    JsonObject data, {
    List<GraphQLError> errors = const [],
    String? operationName,
  }) => add(
    LinkPayload(ExecutionResult(data, errors: errors)),
    operationName: operationName,
  );

  /// Queues a request error result holding [errors] (not empty).
  void addErrors(List<GraphQLError> errors, {String? operationName}) => add(
    LinkPayload(RequestErrorResult(errors: errors)),
    operationName: operationName,
  );

  /// Queues [failure] as one answer.
  void addFailure(ClientFailure failure, {String? operationName}) =>
      add(LinkFailure(failure), operationName: operationName);

  /// Queues [results] as one answer of many events, such as a
  /// subscription's; it is listened to once.
  void addStream(Stream<LinkResult> results, {String? operationName}) =>
      _answers.add((operationName: operationName, open: () => results));

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    _requests.add(request);
    final name = request.document.name;
    final index = _answers.indexWhere(
      (answer) => answer.operationName == null || answer.operationName == name,
    );
    if (index < 0) {
      return Stream.error(StateError('MockLink has no answer for $name.'));
    }
    return _answers.removeAt(index).open();
  }
}
```

Create `packages/typed_graphql_client/lib/src/link/next_link.dart`:

```dart
import 'link_request.dart';
import 'link_result.dart';

/// The rest of a link chain, as a link sees it: call it with the request
/// to forward, and get the answer's stream.
///
/// {@category link}
typedef NextLink = Stream<LinkResult> Function(LinkRequest request);
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index f21cd34..e682150 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -11,9 +11,12 @@ export 'src/client/cancel_token.dart';
 export 'src/client/client_failure.dart';
 export 'src/link/context_entry.dart';
 export 'src/link/http_response_info.dart';
+export 'src/link/link.dart';
 export 'src/link/link_context.dart';
 export 'src/link/link_request.dart';
 export 'src/link/link_result.dart';
+export 'src/link/mock_link.dart';
+export 'src/link/next_link.dart';
 export 'src/link/request_headers.dart';
 export 'src/operation/data_codec.dart';
 export 'src/operation/data_context.dart';
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
git commit -m "feat(typed_graphql_client): add Link, Link.from and MockLink

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 6: feat(typed_graphql_client): add GraphQLClient and GraphQLResponse

**Why.** Spec sections 5 and 7 (R8.1, R8.2). `GraphQLClient.query`/`mutate` take the first result of the chain, decode it through the internal `ResponseDecoder` (the table of section 5) and cancel the chain; `subscribe` is a single-subscription stream over the internal `OperationStream`. A `CancelToken` cancels at once; a stream error that is an `Exception` becomes `NetworkFailure`, an `Error` passes through; a stream that ends without a result is `UnsupportedOperation(GQL469)`.

**Files** (verified commit `27d2ee6` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/doc/client.md`
- Create `packages/typed_graphql_client/lib/src/client/graphql_client.dart`
- Create `packages/typed_graphql_client/lib/src/client/graphql_response.dart`
- Create `packages/typed_graphql_client/lib/src/client/operation_stream.dart`
- Create `packages/typed_graphql_client/lib/src/client/response_decoder.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/client/client_cancellation_test.dart`
- Create `packages/typed_graphql_client/test/client/graphql_client_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/client/client_cancellation_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// Answers every request with a new stream it keeps, so a test can feed
/// it and see whether it was cancelled.
final class OpenLink extends Link {
  final List<StreamController<LinkResult>> controllers = [];
  int cancelCount = 0;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final controller = StreamController<LinkResult>(
      onCancel: () => cancelCount++,
    );
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  LinkResult ticks(int value) =>
      LinkPayload(ExecutionResult(JsonObject({'ticks': JsonNumber(value)})));

  Matcher cancelledWith(Object? reason) =>
      isA<GraphQLTransportFailure<Object>>().having(
        (failure) => failure.failure,
        'failure',
        isA<RequestCancelled>().having(
          (cancelled) => cancelled.reason,
          'reason',
          reason,
        ),
      );

  group('a cancel token', () {
    test(
      'already cancelled answers at once without calling the link',
      () async {
        final link = MockLink();
        final token = CancelToken()..cancel('gone');
        final response = await GraphQLClient(
          link: link,
        ).query(const HelloQuery(), cancelToken: token);
        expect(response, cancelledWith('gone'));
        expect(link.requests, isEmpty);
      },
    );

    test('cancelled while waiting answers and cancels the link', () async {
      final link = OpenLink();
      final token = CancelToken();
      final pending = GraphQLClient(
        link: link,
      ).query(const HelloQuery(), cancelToken: token);
      await Future<void>.delayed(Duration.zero);
      token.cancel('late');
      expect(await pending, cancelledWith('late'));
      expect(link.cancelCount, 1);
    });

    test('is released once the call completes', () async {
      final link = MockLink()
        ..addData(JsonObject({'hello': const JsonString('a')}));
      final token = CancelToken();
      await GraphQLClient(
        link: link,
      ).query(const HelloQuery(), cancelToken: token);
      expect(token.listenerCount, 0);
    });

    test('ends a subscription with the failure as its last event', () async {
      final link = OpenLink();
      final token = CancelToken();
      final events = <GraphQLResponse<int>>[];
      final done = Completer<void>();
      GraphQLClient(link: link)
          .subscribe(const TicksSubscription(), cancelToken: token)
          .listen(events.add, onDone: done.complete);
      await Future<void>.delayed(Duration.zero);
      link.controllers.single.add(ticks(1));
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await done.future;
      expect(events, hasLength(2));
      expect(events.last, cancelledWith(null));
      expect(link.cancelCount, 1);
    });
  });

  group('subscribe', () {
    test('calls the link only when listened to', () async {
      final link = OpenLink();
      final responses = GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription());
      await Future<void>.delayed(Duration.zero);
      expect(link.controllers, isEmpty);
      final subscription = responses.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(link.controllers, hasLength(1));
      await subscription.cancel();
    });

    test('gives one response per event', () async {
      final link = MockLink()
        ..addStream(Stream.fromIterable([ticks(1), ticks(2), ticks(3)]));
      final responses = await GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription()).toList();
      expect(
        [
          for (final response in responses) (response as GraphQLData<int>).data,
        ],
        [1, 2, 3],
      );
    });

    test('cancelling the subscription cancels the link stream', () async {
      final link = OpenLink();
      final subscription = GraphQLClient(
        link: link,
      ).subscribe(const TicksSubscription()).listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(link.cancelCount, 1);
    });
  });
}
```

Create `packages/typed_graphql_client/test/client/graphql_client_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

/// Answers every request with the stream of [controller], recording it.
final class ControlledLink extends Link {
  ControlledLink(this.controller);

  final StreamController<LinkResult> controller;
  final List<LinkRequest> requests = [];

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    requests.add(request);
    return controller.stream;
  }
}

/// Forwards every request: a chain made only of it never terminates.
final class ForwardingLink extends Link {
  const ForwardingLink();

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      forward(request);
}

void main() {
  JsonObject hello(String value) => JsonObject({'hello': JsonString(value)});

  group('query', () {
    test('gives the decoded data', () async {
      final link = MockLink()..addData(hello('world'));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLData<String>>()
            .having((data) => data.data, 'data', 'world')
            .having((data) => data.hasErrors, 'hasErrors', isFalse),
      );
    });

    test('keeps the errors of partial data', () async {
      final link = MockLink()
        ..addData(hello('world'), errors: [GraphQLError('part failed')]);
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLData<String>>().having((data) => data.errors, 'errors', [
          GraphQLError('part failed'),
        ]),
      );
    });

    test('a request error is GraphQLErrors', () async {
      final link = MockLink()..addErrors([GraphQLError('syntax')]);
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLErrors<String>>().having(
          (errors) => errors.errors,
          'errors',
          [GraphQLError('syntax')],
        ),
      );
    });

    test('null data with errors is GraphQLErrors', () async {
      final link = MockLink()
        ..add(LinkPayload(ExecutionResult(null, errors: [GraphQLError('x')])));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(response, isA<GraphQLErrors<String>>());
    });

    test('null data without errors is a malformed response', () async {
      final link = MockLink()..add(LinkPayload(ExecutionResult(null)));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure.code,
          'code',
          DiagnosticCode.malformedResponse,
        ),
      );
    });

    test('data of the wrong shape is a data format failure that keeps the '
        'errors', () async {
      final link = MockLink()
        ..addData(
          JsonObject({'hello': JsonNumber(1)}),
          errors: [GraphQLError('x')],
        );
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure,
          'failure',
          isA<DataFormatFailure>()
              .having(
                (failure) => failure.decodeFailure.path,
                'path',
                [const PathKey('hello')],
              )
              .having((failure) => failure.errors, 'errors', [
                GraphQLError('x'),
              ]),
        ),
      );
    });

    test('a link failure is a transport failure', () async {
      final link = MockLink()..addFailure(HttpStatusFailure(502));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure,
          'failure',
          isA<HttpStatusFailure>(),
        ),
      );
    });

    test('sends the context and returns the result\'s', () async {
      final link = MockLink()
        ..add(
          LinkPayload(
            ExecutionResult(hello('world')),
            context: LinkContext([HttpResponseInfo(200)]),
          ),
        );
      final response = await GraphQLClient(link: link).query(
        const HelloQuery(),
        context: LinkContext([
          RequestHeaders({'x-a': '1'}),
        ]),
      );
      expect(
        link.requests.single.context.entry<RequestHeaders>()?.values,
        {'x-a': '1'},
      );
      expect(
        (response as GraphQLData<String>).context
            .entry<HttpResponseInfo>()
            ?.statusCode,
        200,
      );
    });

    test('a chain without a result is GQL469', () async {
      final link = ControlledLink(StreamController());
      unawaited(link.controller.close());
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure.code,
          'code',
          DiagnosticCode.linkEndedWithoutResult,
        ),
      );
    });

    test('an exception on the link stream is a network failure', () async {
      final link = ControlledLink(StreamController());
      link.controller.addError(const FormatException('reset'));
      final response = await GraphQLClient(
        link: link,
      ).query(const HelloQuery());
      expect(
        response,
        isA<GraphQLTransportFailure<String>>().having(
          (failure) => failure.failure,
          'failure',
          isA<NetworkFailure>(),
        ),
      );
    });

    test('a chain that forwards past its end is a StateError', () {
      final client = GraphQLClient(link: const ForwardingLink());
      expect(client.query(const HelloQuery()), throwsStateError);
    });

    test('takes the first result and cancels the link stream', () async {
      var isCancelled = false;
      final controller = StreamController<LinkResult>(
        onCancel: () => isCancelled = true,
      );
      controller.add(LinkPayload(ExecutionResult(hello('a'))));
      final response = await GraphQLClient(
        link: ControlledLink(controller),
      ).query(const HelloQuery());
      expect(response, isA<GraphQLData<String>>());
      expect(isCancelled, isTrue);
      await controller.close();
    });
  });

  test('mutate sends the mutation', () async {
    final link = MockLink()
      ..addData(JsonObject({'rename': const JsonString('Ada')}));
    final response = await GraphQLClient(
      link: link,
    ).mutate(const RenameMutation('Ada'));
    expect(link.requests.single.type, OperationType.mutation);
    expect(response, isA<GraphQLData<String>>());
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/client/graphql_client_test.dart` and `client_cancellation_test.dart` do not compile: `GraphQLClient` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 719ece4..d3e46dc 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -26,3 +26,6 @@
 - `Link`, `NextLink` and `Link.from` (a chain), and `MockLink`, a
   terminating link for tests that records requests and serves queued
   answers (R8.5).
+- `GraphQLClient` (`query`, `mutate`, `subscribe`, with a context and a
+  cancel token) and the sealed `GraphQLResponse` (`GraphQLData`,
+  `GraphQLErrors`, `GraphQLTransportFailure`) (R8.1, R8.2).
```

Modify `packages/typed_graphql_client/doc/client.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_client/doc/client.md b/packages/typed_graphql_client/doc/client.md
index babaa60..999b382 100644
--- a/packages/typed_graphql_client/doc/client.md
+++ b/packages/typed_graphql_client/doc/client.md
@@ -1,8 +1,81 @@
 # Client
 
 `GraphQLClient` sends the operations `typed_graphql_codegen` generates and
-returns typed responses. This guide grows with the client; these sections
-cover failures and cancellation.
+returns typed responses. A client holds one `Link`, the chain its requests
+go through (see the Links guide).
+
+## Sending an operation
+
+`query`, `mutate` and `subscribe` take a generated operation of the
+matching kind. `query` and `mutate` complete with one `GraphQLResponse`;
+`subscribe` returns a stream that starts the subscription when it is
+listened to and gives one response per event. The response is a sealed
+family:
+
+| Response | When |
+|---|---|
+| `GraphQLData(data, errors)` | the operation ran; `errors` is not empty for partial data |
+| `GraphQLErrors(errors)` | the request was refused, or an error left no data (`"data": null`) |
+| `GraphQLTransportFailure(failure)` | no GraphQL response: see Failures below |
+
+The program below stands a hand-written operation in for a generated one
+and a `MockLink` in for a server. The second answer has a number where the
+operation expects a string, so it does not fit the operation's classes.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_client/typed_graphql_client.dart';
+
+final class HelloQuery extends GraphQLQuery<String> {
+  const HelloQuery();
+
+  @override
+  OperationDocument get document => const OperationDocument(
+    name: 'Hello',
+    type: OperationType.query,
+    text: 'query Hello{hello}',
+    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
+  );
+
+  @override
+  JsonObject get variablesJson => JsonObject({});
+
+  @override
+  DecodeResult<String> decodeData(JsonObject data) => switch (data['hello']) {
+    JsonString(:final value) => DecodeSuccess(value),
+    _ => const DecodeFailure('expected a string', path: [PathKey('hello')]),
+  };
+}
+
+Future<void> main() async {
+  final link = MockLink()
+    ..addData(JsonObject({'hello': JsonString('world')}))
+    ..addData(JsonObject({'hello': JsonNumber(1)}))
+    ..addErrors([GraphQLError('Cannot query field "hello".')]);
+  final client = GraphQLClient(link: link);
+  for (var i = 0; i < 3; i++) {
+    switch (await client.query(const HelloQuery())) {
+      case GraphQLData(:final data):
+        print('data: $data');
+      case GraphQLErrors(:final errors):
+        print('errors: ${errors.first.message}');
+      case GraphQLTransportFailure(:final failure):
+        print('failure: $failure');
+    }
+  }
+}
+```
+
+It prints:
+
+```text
+data: world
+failure: GQL465: The data does not fit the operation: $.hello: expected a string
+errors: Cannot query field "hello".
+```
+
+A response carries the `context` its terminating link wrote, such as the
+HTTP status in `HttpResponseInfo`, and the response's `extensions`.
 
 ## Failures
 
@@ -39,3 +112,13 @@ token.reason;      // 'the user left the page'
 
 Only the first `cancel` has an effect, and `whenCancelled` completes, never
 with an error, once the token is cancelled.
+
+Cancelling completes a pending `query` or `mutate` at once with
+`GraphQLTransportFailure(RequestCancelled(reason))`, and ends a `subscribe`
+stream with that failure as its last event. The client then cancels its
+subscription to the link chain, which ends the request in every link: an
+HTTP request is aborted, a WebSocket subscription is completed. A token
+already cancelled answers without calling the link at all.
+
+Cancelling the subscription to a `subscribe` stream ends the subscription
+the same way, without a last event.
````

Create `packages/typed_graphql_client/lib/src/client/graphql_client.dart`:

```dart
import '../link/link.dart';
import '../link/link_context.dart';
import '../link/link_request.dart';
import '../operation/graphql_operation.dart';
import 'cancel_token.dart';
import 'client_failure.dart';
import 'graphql_response.dart';
import 'operation_stream.dart';
import 'response_decoder.dart';

/// Sends generated operations through a chain of links and returns typed
/// responses (R8.1).
///
/// Nothing a server or a transport does makes it throw: every outcome is a
/// [GraphQLResponse]. A programmer error, such as a chain whose last link
/// forwards, completes the call with that error.
///
/// {@category client}
final class GraphQLClient({
  /// The chain the requests go through; it must end with a terminating
  /// link.
  required final Link link,
}) {
  /// Creates a client over [link].
  this;

  /// Sends [query] and completes with its response; [context] travels with
  /// the request and [cancelToken] stops it.
  Future<GraphQLResponse<D>> query<D extends Object>(
    GraphQLQuery<D> query, {
    LinkContext context = const LinkContext.empty(),
    CancelToken? cancelToken,
  }) => _first(_responses(query, context, cancelToken));

  /// Sends [mutation] and completes with its response; [context] travels
  /// with the request and [cancelToken] stops it.
  Future<GraphQLResponse<D>> mutate<D extends Object>(
    GraphQLMutation<D> mutation, {
    LinkContext context = const LinkContext.empty(),
    CancelToken? cancelToken,
  }) => _first(_responses(mutation, context, cancelToken));

  /// Starts [subscription] when the stream is listened to and gives one
  /// response per event; cancelling the stream's subscription, or
  /// [cancelToken], ends it.
  Stream<GraphQLResponse<D>> subscribe<D extends Object>(
    GraphQLSubscription<D> subscription, {
    LinkContext context = const LinkContext.empty(),
    CancelToken? cancelToken,
  }) => _responses(subscription, context, cancelToken);

  Stream<GraphQLResponse<D>> _responses<D extends Object>(
    GraphQLOperation<D> operation,
    LinkContext context,
    CancelToken? cancelToken,
  ) => OperationStream(
    link,
    LinkRequest.of(operation, context: context),
    ResponseDecoder(operation),
    cancelToken,
  ).stream;

  /// The first response of [responses]; leaving the loop cancels the
  /// subscription, which ends the request in every link.
  Future<GraphQLResponse<D>> _first<D extends Object>(
    Stream<GraphQLResponse<D>> responses,
  ) async {
    await for (final response in responses) {
      return response;
    }
    return const GraphQLTransportFailure(
      UnsupportedOperation(
        .linkEndedWithoutResult,
        'The link chain ended without a result.',
      ),
    );
  }
}
```

Create `packages/typed_graphql_client/lib/src/client/graphql_response.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_context.dart';
import 'client_failure.dart';

/// The typed answer to an operation (R8.2): data, errors without data, or
/// a failure to get a response at all.
///
/// Switch over it; the three kinds tell apart what a caller handles
/// differently.
///
/// {@category client}
sealed class GraphQLResponse<D extends Object> {
  /// Creates a response.
  const GraphQLResponse();
}

/// The operation ran and gave [data]; [errors] is not empty when part of
/// it failed (partial data).
///
/// {@category client}
final class GraphQLData<D extends Object>(
  /// The data, read into the operation's generated classes.
  final D data, {
  List<GraphQLError> errors = const [],

  /// The response's `extensions`, null when it has none.
  final JsonObject? extensions,

  /// What the terminating link learned about the answer, such as
  /// `HttpResponseInfo`.
  final LinkContext context = const LinkContext.empty(),
}) extends GraphQLResponse<D> {
  /// Creates a data response; [errors] is copied.
  this;

  /// The errors raised on the way, in order.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  /// Whether part of the data failed.
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() => 'GraphQLData($data, errors: $errors)';
}

/// The server answered with errors and no data: the request was refused
/// (a syntax or validation error, a persisted query miss) or an error
/// nulled the whole result.
///
/// {@category client}
final class GraphQLErrors<D extends Object>(
  List<GraphQLError> errors, {

  /// The response's `extensions`, null when it has none.
  final JsonObject? extensions,

  /// What the terminating link learned about the answer, such as
  /// `HttpResponseInfo`.
  final LinkContext context = const LinkContext.empty(),
}) extends GraphQLResponse<D> {
  /// Creates an error response; [errors] is copied.
  this;

  /// The errors, in order; never empty.
  final List<GraphQLError> errors = List.unmodifiable(errors);

  @override
  String toString() => 'GraphQLErrors($errors)';
}

/// No GraphQL response: [failure] says why.
///
/// {@category client}
final class const GraphQLTransportFailure<D extends Object>(
  /// Why there is no response.
  final ClientFailure failure,
) extends GraphQLResponse<D> {
  /// Creates a failure response.
  this;

  @override
  String toString() => 'GraphQLTransportFailure($failure)';
}
```

Create `packages/typed_graphql_client/lib/src/client/operation_stream.dart`:

```dart
import 'dart:async';

import '../link/link.dart';
import '../link/link_request.dart';
import '../link/link_result.dart';
import 'cancel_token.dart';
import 'client_failure.dart';
import 'graphql_response.dart';
import 'response_decoder.dart';

/// The typed responses of one request: it calls the link chain when
/// listened to, decodes each result, and ends with [RequestCancelled] when
/// the caller's token fires (spec sections 4 and 7).
final class OperationStream<D extends Object> {
  /// Creates the stream of [_request] through [_link].
  OperationStream(
    this._link,
    this._request,
    this._decoder,
    this._cancelToken,
  );

  final Link _link;
  final LinkRequest _request;
  final ResponseDecoder<D> _decoder;
  final CancelToken? _cancelToken;

  late final StreamController<GraphQLResponse<D>> _controller =
      StreamController(
        onListen: _start,
        onCancel: _stop,
        onPause: () => _subscription?.pause(),
        onResume: () => _subscription?.resume(),
      );
  StreamSubscription<LinkResult>? _subscription;
  void Function()? _removeListener;

  /// The responses; single-subscription.
  Stream<GraphQLResponse<D>> get stream => _controller.stream;

  void _start() {
    final token = _cancelToken;
    if (token != null && token.isCancelled) {
      _cancel(token);
      return;
    }
    // Set before listening: a synchronous link may end inside `listen`.
    _removeListener = token?.addListener(() => _cancel(token));
    _subscription = _link
        .request(_request, _unterminated)
        .listen(
          (result) => _controller.add(_decoder.decode(result)),
          onError: _fail,
          onDone: _finish,
        );
  }

  Future<void>? _stop() {
    _removeListener?.call();
    _removeListener = null;
    return _subscription?.cancel();
  }

  void _cancel(CancelToken token) {
    unawaited(_stop());
    _controller.add(GraphQLTransportFailure(RequestCancelled(token.reason)));
    _finish();
  }

  /// A link stream that broke the rule and emitted an error: an
  /// [Exception] is a network failure, anything else a programmer error.
  void _fail(Object error, StackTrace stackTrace) {
    if (error is Exception) {
      _controller.add(GraphQLTransportFailure(NetworkFailure(error)));
    } else {
      _controller.addError(error, stackTrace);
    }
    unawaited(_stop());
    _finish();
  }

  void _finish() {
    _removeListener?.call();
    _removeListener = null;
    if (!_controller.isClosed) {
      unawaited(_controller.close());
    }
  }

  static Stream<LinkResult> _unterminated(LinkRequest request) => Stream.error(
    StateError(
      'The last link forwarded ${request.document.name}: end the chain with '
      'a terminating link, such as HttpLink.',
    ),
  );
}
```

Create `packages/typed_graphql_client/lib/src/client/response_decoder.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../link/link_context.dart';
import '../link/link_result.dart';
import '../operation/graphql_operation.dart';
import 'client_failure.dart';
import 'graphql_response.dart';

/// Turns the untyped results of a link chain into typed responses of one
/// operation (spec section 5).
final class ResponseDecoder<D extends Object> {
  /// Creates the decoder of [_operation]'s results.
  const ResponseDecoder(this._operation);

  final GraphQLOperation<D> _operation;

  /// The response [result] stands for.
  GraphQLResponse<D> decode(LinkResult result) => switch (result) {
    LinkFailure(:final failure) => GraphQLTransportFailure(failure),
    LinkPayload(
      payload: RequestErrorResult(:final errors, :final extensions),
      :final context,
    ) =>
      GraphQLErrors(errors, extensions: extensions, context: context),
    LinkPayload(
      payload: ExecutionResult(data: null, :final errors, :final extensions),
      :final context,
    ) =>
      errors.isEmpty
          ? GraphQLTransportFailure(
              ResponseFormatFailure(
                .malformedResponse,
                'The response has "data": null and no errors.',
              ),
            )
          : GraphQLErrors(errors, extensions: extensions, context: context),
    LinkPayload(
      payload: ExecutionResult(:final data?, :final errors, :final extensions),
      :final context,
    ) =>
      _data(data, errors, extensions, context),
  };

  GraphQLResponse<D> _data(
    JsonObject data,
    List<GraphQLError> errors,
    JsonObject? extensions,
    LinkContext context,
  ) => switch (_operation.decodeData(data)) {
    DecodeSuccess(:final value) => GraphQLData(
      value,
      errors: errors,
      extensions: extensions,
      context: context,
    ),
    final DecodeFailure failure => GraphQLTransportFailure(
      DataFormatFailure(failure, errors: errors),
    ),
  };
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index e682150..acae9d7 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -9,6 +9,8 @@ library;
 
 export 'src/client/cancel_token.dart';
 export 'src/client/client_failure.dart';
+export 'src/client/graphql_client.dart';
+export 'src/client/graphql_response.dart';
 export 'src/link/context_entry.dart';
 export 'src/link/http_response_info.dart';
 export 'src/link/link.dart';
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
git commit -m "feat(typed_graphql_client): add GraphQLClient and GraphQLResponse

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 7: feat(typed_graphql_client): add SplitLink and ContextLink

**Why.** Spec section 6. `SplitLink` routes a request to one of two links, both forwarding with the chain's `forward`. `ContextLink` rewrites the context before forwarding; an `Exception` from its callback is a `LinkFailure(NetworkFailure)` and nothing is forwarded. The Links guide shows dynamic headers.

**Files** (verified commit `f6fa729` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/doc/links.md`
- Create `packages/typed_graphql_client/lib/src/link/context_link.dart`
- Create `packages/typed_graphql_client/lib/src/link/split_link.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/link/split_and_context_link_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/link/split_and_context_link_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';

void main() {
  Stream<LinkResult> unterminated(LinkRequest request) =>
      Stream.error(StateError('forwarded past the end'));

  group('SplitLink', () {
    test('sends a request that passes the test to whenTrue', () async {
      final sockets = MockLink()..addData(JsonObject(const {}));
      final http = MockLink();
      final link = SplitLink(
        test: (request) => request.type == OperationType.subscription,
        whenTrue: sockets,
        whenFalse: http,
      );
      await link
          .request(LinkRequest.of(const TicksSubscription()), unterminated)
          .drain<void>();
      expect(sockets.requests, hasLength(1));
      expect(http.requests, isEmpty);
    });

    test('sends the other requests to whenFalse', () async {
      final sockets = MockLink();
      final http = MockLink()..addData(JsonObject(const {}));
      final link = SplitLink(
        test: (request) => request.type == OperationType.subscription,
        whenTrue: sockets,
        whenFalse: http,
      );
      await link
          .request(LinkRequest.of(const HelloQuery()), unterminated)
          .drain<void>();
      expect(http.requests, hasLength(1));
      expect(sockets.requests, isEmpty);
    });

    test('a branch gets the chain\'s forward', () async {
      final terminal = MockLink()..addData(JsonObject(const {}));
      final link = Link.from([
        SplitLink(
          test: (request) => true,
          whenTrue: ContextLink((request) => request.context),
          whenFalse: terminal,
        ),
        terminal,
      ]);
      await link
          .request(LinkRequest.of(const HelloQuery()), unterminated)
          .drain<void>();
      expect(terminal.requests, hasLength(1));
    });
  });

  group('ContextLink', () {
    test('forwards the request with the new context', () async {
      final terminal = MockLink()..addData(JsonObject(const {}));
      final link = Link.from([
        ContextLink(
          (request) async => request.context.withEntry(
            RequestHeaders({'authorization': 'Bearer t'}),
          ),
        ),
        terminal,
      ]);
      await link
          .request(LinkRequest.of(const HelloQuery()), unterminated)
          .drain<void>();
      expect(
        terminal.requests.single.context.entry<RequestHeaders>()?.values,
        {'authorization': 'Bearer t'},
      );
    });

    test(
      'an exception of update is a network failure, not forwarded',
      () async {
        final terminal = MockLink();
        final link = Link.from([
          ContextLink((request) => throw const FormatException('no token')),
          terminal,
        ]);
        final results = await link
            .request(LinkRequest.of(const HelloQuery()), unterminated)
            .toList();
        expect(results.single, isA<LinkFailure>());
        expect(
          (results.single as LinkFailure).failure,
          isA<NetworkFailure>(),
        );
        expect(terminal.requests, isEmpty);
      },
    );

    test('cancelling cancels the forwarded stream', () async {
      var isCancelled = false;
      final controller = StreamController<LinkResult>(
        onCancel: () => isCancelled = true,
      );
      final link = ContextLink((request) => request.context);
      final subscription = link
          .request(
            LinkRequest.of(const HelloQuery()),
            (request) => controller.stream,
          )
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(isCancelled, isTrue);
      await controller.close();
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/link/split_and_context_link_test.dart` does not compile: `SplitLink` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index d3e46dc..14fb804 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -29,3 +29,5 @@
 - `GraphQLClient` (`query`, `mutate`, `subscribe`, with a context and a
   cancel token) and the sealed `GraphQLResponse` (`GraphQLData`,
   `GraphQLErrors`, `GraphQLTransportFailure`) (R8.1, R8.2).
+- `SplitLink` (route a request to one of two links) and `ContextLink`
+  (rewrite a request's context before forwarding it).
```

Modify `packages/typed_graphql_client/doc/links.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_client/doc/links.md b/packages/typed_graphql_client/doc/links.md
index 049e980..0f7166c 100644
--- a/packages/typed_graphql_client/doc/links.md
+++ b/packages/typed_graphql_client/doc/links.md
@@ -49,6 +49,72 @@ Cancelling the subscription to a link's stream must end what the link
 started: a link built from stream operations (`map`, `asyncExpand`,
 `async*`) does so by itself.
 
+## Routing and context
+
+`SplitLink(test:, whenTrue:, whenFalse:)` sends each request down one of
+two links; the usual split sends subscriptions over a socket and the rest
+over HTTP. `ContextLink(update)` rewrites the context of each request
+before forwarding it, for headers computed at the time of the request; an
+exception of `update` is a `NetworkFailure` result.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_client/typed_graphql_client.dart';
+
+final class HelloQuery extends GraphQLQuery<String> {
+  const HelloQuery();
+
+  @override
+  OperationDocument get document => const OperationDocument(
+    name: 'Hello',
+    type: OperationType.query,
+    text: 'query Hello{hello}',
+    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
+  );
+
+  @override
+  JsonObject get variablesJson => JsonObject({});
+
+  @override
+  DecodeResult<String> decodeData(JsonObject data) => switch (data['hello']) {
+    JsonString(:final value) => DecodeSuccess(value),
+    _ => const DecodeFailure('expected a string', path: [PathKey('hello')]),
+  };
+}
+
+Future<void> main() async {
+  final http = MockLink()
+    ..addData(JsonObject({'hello': JsonString('over HTTP')}));
+  final sockets = MockLink();
+  final client = GraphQLClient(
+    link: Link.from([
+      ContextLink(
+        (request) =>
+            request.context.withEntry(RequestHeaders({'X-Trace': 'abc'})),
+      ),
+      SplitLink(
+        test: (request) => request.type == OperationType.subscription,
+        whenTrue: sockets,
+        whenFalse: http,
+      ),
+    ]),
+  );
+  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
+    print(data);
+  }
+  print(http.requests.single.context.entry<RequestHeaders>()?.values);
+  print(sockets.requests.length);
+}
+```
+
+It prints:
+
+```text
+over HTTP
+{x-trace: abc}
+0
+```
+
 ## Testing with MockLink
 
 `MockLink` is a terminating link for tests: it records every request in
````

Create `packages/typed_graphql_client/lib/src/link/context_link.dart`:

```dart
import 'dart:async';

import '../client/client_failure.dart';
import 'link.dart';
import 'link_context.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// Rewrites the context of each request before forwarding it, such as to
/// add headers computed at the time of the request (R8.4).
///
/// An [Exception] thrown by [update] is a [NetworkFailure] result and the
/// request is not forwarded.
///
/// {@category link}
final class ContextLink(
  /// The new context of a request, from the request.
  final FutureOr<LinkContext> Function(LinkRequest request) update,
) extends Link {
  /// Creates a link that rewrites contexts with [update].
  this;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) async* {
    final LinkContext context;
    try {
      context = await update(request);
    } on Exception catch (exception) {
      yield LinkFailure(NetworkFailure(exception));
      return;
    }
    yield* forward(request.withContext(context));
  }
}
```

Create `packages/typed_graphql_client/lib/src/link/split_link.dart`:

```dart
import 'link.dart';
import 'link_request.dart';
import 'link_result.dart';
import 'next_link.dart';

/// Sends a request down one of two links, chosen by [test]: typically
/// subscriptions over a socket and the rest over HTTP (R8.3).
///
/// The chosen link gets the chain's `forward`, so a branch may be a middle
/// link or a whole chain.
///
/// {@category link}
final class SplitLink({
  /// Whether a request goes to [whenTrue].
  required final bool Function(LinkRequest request) test,

  /// The link for requests that pass [test].
  required final Link whenTrue,

  /// The link for the other requests.
  required final Link whenFalse,
}) extends Link {
  /// Creates a split between [whenTrue] and [whenFalse].
  this;

  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) =>
      (test(request) ? whenTrue : whenFalse).request(request, forward);
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index acae9d7..0a9d474 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -12,6 +12,7 @@ export 'src/client/client_failure.dart';
 export 'src/client/graphql_client.dart';
 export 'src/client/graphql_response.dart';
 export 'src/link/context_entry.dart';
+export 'src/link/context_link.dart';
 export 'src/link/http_response_info.dart';
 export 'src/link/link.dart';
 export 'src/link/link_context.dart';
@@ -20,6 +21,7 @@ export 'src/link/link_result.dart';
 export 'src/link/mock_link.dart';
 export 'src/link/next_link.dart';
 export 'src/link/request_headers.dart';
+export 'src/link/split_link.dart';
 export 'src/operation/data_codec.dart';
 export 'src/operation/data_context.dart';
 export 'src/operation/data_enum.dart';
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
git commit -m "feat(typed_graphql_client): add SplitLink and ContextLink

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 8: feat(typed_graphql_client): add Backoff

**Why.** Spec section 6. `Backoff` (const: `initialDelay` 300 ms, `maxDelay` 30 s, `multiplier` 2): `ceilingFor(retry)` grows with a loop that stops at `maxDelay`, so a large retry cannot overflow; `delayFor(retry, random)` is full jitter. `RetryLink` (M11c) and `WebSocketLink` (M11d) share it.

**Files** (verified commit `e971b27` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/doc/links.md`
- Create `packages/typed_graphql_client/lib/src/link/backoff.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/link/backoff_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/link/backoff_test.dart`:

```dart
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

/// A random source that always draws [value].
final class FixedRandom implements Random {
  const FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => (value * max).floor();

  @override
  bool nextBool() => value >= 0.5;
}

void main() {
  const backoff = Backoff();

  test('the ceiling starts at the initial delay', () {
    expect(backoff.ceilingFor(0), const Duration(milliseconds: 300));
  });

  test('the ceiling grows by the multiplier', () {
    expect(backoff.ceilingFor(1), const Duration(milliseconds: 600));
    expect(backoff.ceilingFor(3), const Duration(milliseconds: 2400));
  });

  test('the ceiling stops at the maximum', () {
    expect(backoff.ceilingFor(20), const Duration(seconds: 30));
  });

  test('a huge retry number neither overflows nor loops long', () {
    expect(backoff.ceilingFor(1 << 40), const Duration(seconds: 30));
  });

  test('the delay is the draw times the ceiling', () {
    expect(
      backoff.delayFor(1, const FixedRandom(0.5)),
      const Duration(milliseconds: 300),
    );
  });

  test('the delay is never above the ceiling', () {
    final random = Random(7);
    for (var retry = 0; retry < 12; retry++) {
      final delay = backoff.delayFor(retry, random);
      expect(delay, lessThanOrEqualTo(backoff.ceilingFor(retry)));
      expect(delay, greaterThanOrEqualTo(Duration.zero));
    }
  });

  test('custom settings apply', () {
    const custom = Backoff(
      initialDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 5),
      multiplier: 3,
    );
    expect(custom.ceilingFor(1), const Duration(seconds: 3));
    expect(custom.ceilingFor(2), const Duration(seconds: 5));
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/link/backoff_test.dart` does not compile: `Backoff` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index 14fb804..dc6e0cf 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -31,3 +31,5 @@
   `GraphQLErrors`, `GraphQLTransportFailure`) (R8.1, R8.2).
 - `SplitLink` (route a request to one of two links) and `ContextLink`
   (rewrite a request's context before forwarding it).
+- `Backoff`: exponential delays with full jitter, for retries and
+  reconnections.
```

Modify `packages/typed_graphql_client/doc/links.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_client/doc/links.md b/packages/typed_graphql_client/doc/links.md
index 0f7166c..0b6639f 100644
--- a/packages/typed_graphql_client/doc/links.md
+++ b/packages/typed_graphql_client/doc/links.md
@@ -115,6 +115,20 @@ over HTTP
 0
 ```
 
+## Backoff
+
+`Backoff(initialDelay:, maxDelay:, multiplier:)` says how long to wait
+before a retry or a reconnection. The ceiling of retry `n` (from 0) is
+`initialDelay` times `multiplier` to the power `n`, at most `maxDelay`;
+`delayFor(n, random)` draws a wait between zero and that ceiling ("full
+jitter"), so clients that failed together do not retry together. The
+defaults are 300 ms, 30 s and 2.
+
+```text
+const Backoff().ceilingFor(0); // 0:00:00.300000
+const Backoff().ceilingFor(3); // 0:00:02.400000
+```
+
 ## Testing with MockLink
 
 `MockLink` is a terminating link for tests: it records every request in
````

Create `packages/typed_graphql_client/lib/src/link/backoff.dart`:

```dart
import 'dart:math';

/// How long to wait before a retry or a reconnection: exponential growth
/// with "full jitter", a uniform draw between zero and the ceiling, so
/// that many clients that failed together do not retry together (R8.4).
///
/// The ceiling of retry `n` (from 0) is [initialDelay] times [multiplier]
/// to the power `n`, at most [maxDelay].
///
/// {@category link}
final class const Backoff({
  /// The ceiling of the first retry.
  final Duration initialDelay = const Duration(milliseconds: 300),

  /// The highest ceiling.
  final Duration maxDelay = const Duration(seconds: 30),

  /// How much the ceiling grows from one retry to the next.
  final double multiplier = 2,
}) {
  /// Creates a backoff.
  this;

  /// The longest wait before retry [retry] (from 0).
  Duration ceilingFor(int retry) {
    final max = maxDelay.inMicroseconds;
    var ceiling = initialDelay.inMicroseconds.toDouble();
    for (var step = 0; step < retry && ceiling < max; step++) {
      ceiling *= multiplier;
    }
    return Duration(microseconds: min(ceiling, max.toDouble()).round());
  }

  /// The wait before retry [retry] (from 0), drawn with [random].
  Duration delayFor(int retry, Random random) => Duration(
    microseconds: (random.nextDouble() * ceilingFor(retry).inMicroseconds)
        .floor(),
  );
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index 0a9d474..d425d57 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -11,6 +11,7 @@ export 'src/client/cancel_token.dart';
 export 'src/client/client_failure.dart';
 export 'src/client/graphql_client.dart';
 export 'src/client/graphql_response.dart';
+export 'src/link/backoff.dart';
 export 'src/link/context_entry.dart';
 export 'src/link/context_link.dart';
 export 'src/link/http_response_info.dart';
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
git commit -m "feat(typed_graphql_client): add Backoff

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 9: feat(typed_graphql_client): add UploadFile, UploadFileCodec and UploadFiles

**Why.** Spec section 9, "Uploads" (deviation 4). The types live in M11a because every terminating link reads `UploadFiles`: `UploadFile` (`fromBytes` replays a copy, `fromStream` calls the caller's function on each `open`, so a retry can resend; `marker` is unique per object), `UploadFileCodec` (writes the marker, refuses to read a file from JSON) and the `UploadFiles` context entry. Opens the `upload` category and its guide; M11b adds the multipart body.

**Files** (verified commit `0a8ea33` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/CHANGELOG.md`
- Modify `packages/typed_graphql_client/dartdoc_options.yaml`
- Create `packages/typed_graphql_client/doc/uploads.md`
- Create `packages/typed_graphql_client/lib/src/upload/upload_file.dart`
- Create `packages/typed_graphql_client/lib/src/upload/upload_file_codec.dart`
- Create `packages/typed_graphql_client/lib/src/upload/upload_files.dart`
- Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Create `packages/typed_graphql_client/test/upload/upload_file_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_client/test/upload/upload_file_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  group('UploadFile', () {
    test('fromBytes copies the bytes and knows their length', () async {
      final bytes = [1, 2, 3];
      final file = UploadFile.fromBytes(bytes, filename: 'a.bin');
      bytes[0] = 9;
      expect(file.length, 3);
      expect(await file.open().expand((chunk) => chunk).toList(), [1, 2, 3]);
    });

    test('fromBytes can be opened again', () async {
      final file = UploadFile.fromBytes([1], filename: 'a.bin');
      await file.open().drain<void>();
      expect(await file.open().expand((chunk) => chunk).toList(), [1]);
    });

    test('fromStream opens a new stream each time', () async {
      var opened = 0;
      final file = UploadFile.fromStream(
        () {
          opened++;
          return Stream.value([7]);
        },
        length: 1,
        filename: 'a.bin',
      );
      await file.open().drain<void>();
      await file.open().drain<void>();
      expect(opened, 2);
    });

    test('has the default content type', () {
      expect(
        UploadFile.fromBytes(const [], filename: 'a').contentType,
        'application/octet-stream',
      );
    });

    test('each file has its own marker', () {
      final a = UploadFile.fromBytes(const [], filename: 'a');
      final b = UploadFile.fromBytes(const [], filename: 'a');
      expect(a.marker, isNot(b.marker));
      expect(a.marker, startsWith(UploadFile.markerPrefix));
    });
  });

  group('UploadFileCodec', () {
    test('writes a file as its marker', () {
      final file = UploadFile.fromBytes(const [], filename: 'a');
      expect(const UploadFileCodec().encode(file), JsonString(file.marker));
    });

    test('never reads a file', () {
      expect(
        const UploadFileCodec().decode(const JsonString('x')),
        isA<DecodeFailure>(),
      );
    });
  });

  group('UploadFiles', () {
    test('finds a file by its marker', () {
      final a = UploadFile.fromBytes(const [], filename: 'a');
      final b = UploadFile.fromBytes(const [], filename: 'b');
      final files = UploadFiles([a, b]);
      expect(files.withMarker(b.marker), same(b));
      expect(files.withMarker('other'), isNull);
    });

    test('is a context entry', () {
      final context = LinkContext([UploadFiles(const [])]);
      expect(context.entry<UploadFiles>(), isNotNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: `test/upload/upload_file_test.dart` does not compile: `UploadFile` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/CHANGELOG.md b/packages/typed_graphql_client/CHANGELOG.md
index dc6e0cf..32faa45 100644
--- a/packages/typed_graphql_client/CHANGELOG.md
+++ b/packages/typed_graphql_client/CHANGELOG.md
@@ -33,3 +33,6 @@
   (rewrite a request's context before forwarding it).
 - `Backoff`: exponential delays with full jitter, for retries and
   reconnections.
+- `UploadFile`, `UploadFileCodec` (the `Upload` scalar's codec, which
+  writes a file as its marker) and `UploadFiles` (the files of a request,
+  in its context); the start of the Uploads guide.
```

Modify `packages/typed_graphql_client/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/dartdoc_options.yaml b/packages/typed_graphql_client/dartdoc_options.yaml
index 4228e24..0d86a8d 100644
--- a/packages/typed_graphql_client/dartdoc_options.yaml
+++ b/packages/typed_graphql_client/dartdoc_options.yaml
@@ -6,11 +6,15 @@ dartdoc:
     link:
       markdown: doc/links.md
       displayName: Links
+    upload:
+      markdown: doc/uploads.md
+      displayName: Uploads
     operations:
       markdown: doc/operations.md
       displayName: Generated Operations
   categoryOrder:
     - client
     - link
+    - upload
     - operations
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_client/doc/uploads.md`:

````markdown
# Uploads

A GraphQL server that follows the multipart request specification takes
files as values of the `Upload` scalar. The client sends them in three
steps.

## Mapping the scalar

Map `Upload` in `typed_graphql.yaml`, so the generated variables hold an
`UploadFile`:

```text
scalars:
  Upload:
    type: package:typed_graphql_client/typed_graphql_client.dart#UploadFile
    codec: package:typed_graphql_client/typed_graphql_client.dart#UploadFileCodec
```

`UploadFileCodec` writes a file as its `marker`, a string unique to the
`UploadFile` object, and never reads one: a file does not come back in a
response.

## Files and their list

`UploadFile.fromBytes(bytes, filename:)` holds a copy of the bytes;
`UploadFile.fromStream(open, length:, filename:)` calls `open` for each
attempt, so a retried request sends the file again. Both take a
`contentType` (default `application/octet-stream`).

The variables of a generated operation are JSON, where a file is only its
marker, so the caller lists the files of a request in its context:

```text
final avatar = UploadFile.fromBytes(bytes, filename: 'avatar.png', contentType: 'image/png');
await client.mutate(
  SetAvatarMutation(file: avatar),
  context: LinkContext([UploadFiles([avatar])]),
);
```

A link that cannot send files answers a request with `UploadFiles` with an
`UnsupportedOperation` (`GQL468`).
````

Create `packages/typed_graphql_client/lib/src/upload/upload_file.dart`:

```dart
import 'dart:typed_data';

/// A file sent as the value of an `Upload` variable, following the GraphQL
/// multipart request specification (R8.4).
///
/// The generated variables hold the file's [marker] in its place, through
/// `UploadFileCodec`; the caller lists the files of a request in an
/// `UploadFiles` context entry, and `HttpLink` sends them as parts of a
/// `multipart/form-data` body.
///
/// {@category upload}
final class UploadFile {
  /// A file of [bytes], copied.
  UploadFile.fromBytes(
    List<int> bytes, {
    required this.filename,
    this.contentType = defaultContentType,
  }) : length = bytes.length,
       marker = _nextMarker(),
       _open = _opener(Uint8List.fromList(bytes));

  /// A file whose content [open] streams, [length] bytes long. [open] is
  /// called once per attempt, so a retried request sends the file again.
  UploadFile.fromStream(
    Stream<List<int>> Function() open, {
    required this.length,
    required this.filename,
    this.contentType = defaultContentType,
  }) : marker = _nextMarker(),
       _open = open;

  /// The content type of a file created without one.
  static const String defaultContentType = 'application/octet-stream';

  /// The prefix of every [marker].
  static const String markerPrefix = 'typed_graphql.upload/';

  static int _markerCount = 0;

  /// The file name sent in the part's `Content-Disposition`.
  final String filename;

  /// The part's `Content-Type`.
  final String contentType;

  /// The content's length in bytes.
  final int length;

  /// The string the generated variables hold in this file's place, unique
  /// to this object.
  final String marker;

  final Stream<List<int>> Function() _open;

  /// The content, from the start; a new stream on every call.
  Stream<List<int>> open() => _open();

  static String _nextMarker() => '$markerPrefix${_markerCount++}';

  static Stream<List<int>> Function() _opener(Uint8List bytes) =>
      () => Stream.value(bytes);

  @override
  String toString() => 'UploadFile($filename, $length bytes)';
}
```

Create `packages/typed_graphql_client/lib/src/upload/upload_file_codec.dart`:

````dart
import 'package:typed_graphql/typed_graphql.dart';

import 'upload_file.dart';

/// The codec of the `Upload` scalar: it writes a file as its marker, which
/// `HttpLink` replaces with the file itself (R8.4).
///
/// Map the scalar in `typed_graphql.yaml`:
///
/// ```text
/// scalars:
///   Upload:
///     type: package:typed_graphql_client/typed_graphql_client.dart#UploadFile
///     codec: package:typed_graphql_client/typed_graphql_client.dart#UploadFileCodec
/// ```
///
/// A file never comes back in a response, so [decode] always fails.
///
/// {@category upload}
final class const UploadFileCodec() implements ScalarCodec<UploadFile> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<UploadFile> decode(JsonValue json) =>
      const DecodeFailure('Upload cannot be read from a response');

  @override
  JsonValue encode(UploadFile value) => JsonString(value.marker);
}
````

Create `packages/typed_graphql_client/lib/src/upload/upload_files.dart`:

```dart
import '../link/context_entry.dart';
import 'upload_file.dart';

/// The files of one request, listed by the caller in its context so that
/// `HttpLink` can find the object behind each marker of the variables.
///
/// Links that cannot send files (`WebSocketLink`, `SseLink`) answer a
/// request with this entry with an `UnsupportedOperation`.
///
/// {@category upload}
final class UploadFiles extends ContextEntry {
  /// Creates the entry for [files], copied.
  UploadFiles(Iterable<UploadFile> files) : files = List.unmodifiable(files);

  /// The files, in the order given.
  final List<UploadFile> files;

  /// The file whose marker is [marker], or null.
  UploadFile? withMarker(String marker) {
    for (final file in files) {
      if (file.marker == marker) {
        return file;
      }
    }
    return null;
  }

  @override
  String toString() => 'UploadFiles($files)';
}
```

Modify `packages/typed_graphql_client/lib/typed_graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/typed_graphql_client.dart b/packages/typed_graphql_client/lib/typed_graphql_client.dart
index d425d57..77884a8 100644
--- a/packages/typed_graphql_client/lib/typed_graphql_client.dart
+++ b/packages/typed_graphql_client/lib/typed_graphql_client.dart
@@ -38,3 +38,6 @@ export 'src/operation/nullable_data_codec.dart';
 export 'src/operation/object_data_codec.dart';
 export 'src/operation/operation_document.dart';
 export 'src/operation/scalar_data_codec.dart';
+export 'src/upload/upload_file.dart';
+export 'src/upload/upload_file_codec.dart';
+export 'src/upload/upload_files.dart';
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
git commit -m "feat(typed_graphql_client): add UploadFile, UploadFileCodec and UploadFiles

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

### Task 10: fix(typed_graphql_client): answer queries under fake time

**Why.** Adds `fake_async` as a dev dependency (spec section 2; deviation 11) and fixes what it exposed: `query` awaited the future that cancelling a subscription returns, a root-zone future only the real event loop completes, so under `fakeAsync` a query never completed. `GraphQLClient` now takes the first result with `Stream.firstWhere` and `OperationStream` cancels its upstream without awaiting it. Every later plan drives timers with `fake_async`.

**Files** (verified commit `f1a9664` of the controller's scratch copy):

- Modify `packages/typed_graphql_client/lib/src/client/graphql_client.dart`
- Modify `packages/typed_graphql_client/lib/src/client/operation_stream.dart`
- Modify `packages/typed_graphql_client/pubspec.yaml`
- Modify `packages/typed_graphql_client/test/client/graphql_client_test.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_client/test/client/graphql_client_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/test/client/graphql_client_test.dart b/packages/typed_graphql_client/test/client/graphql_client_test.dart
index 1923187..1f30460 100644
--- a/packages/typed_graphql_client/test/client/graphql_client_test.dart
+++ b/packages/typed_graphql_client/test/client/graphql_client_test.dart
@@ -1,5 +1,6 @@
 import 'dart:async';
 
+import 'package:fake_async/fake_async.dart';
 import 'package:test/test.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_client/typed_graphql_client.dart';
@@ -229,4 +230,17 @@ void main() {
     expect(link.requests.single.type, OperationType.mutation);
     expect(response, isA<GraphQLData<String>>());
   });
+
+  test('answers under fake time without the real event loop', () {
+    fakeAsync((async) {
+      GraphQLResponse<String>? response;
+      unawaited(
+        GraphQLClient(link: MockLink()..addData(hello('world')))
+            .query(const HelloQuery())
+            .then((value) => response = value),
+      );
+      async.flushMicrotasks();
+      expect(response, isA<GraphQLData<String>>());
+    });
+  });
 }
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"' 2>&1 | tail -30
```

Expected: the test file does not compile until `fake_async` is a dependency. Apply the `pubspec.yaml` diff of Step 3 first and run `dart pub get` (wrapped); then "answers under fake time without the real event loop" in `test/client/graphql_client_test.dart` fails: the response stays null.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_client/lib/src/client/graphql_client.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/src/client/graphql_client.dart b/packages/typed_graphql_client/lib/src/client/graphql_client.dart
index 2412654..b5883d9 100644
--- a/packages/typed_graphql_client/lib/src/client/graphql_client.dart
+++ b/packages/typed_graphql_client/lib/src/client/graphql_client.dart
@@ -60,19 +60,22 @@ final class GraphQLClient({
     cancelToken,
   ).stream;
 
-  /// The first response of [responses]; leaving the loop cancels the
+  /// The first response of [responses]; taking it cancels the
   /// subscription, which ends the request in every link.
+  ///
+  /// `firstWhere`, not `await for`: leaving an `await for` awaits the
+  /// cancel future, which for a synchronous cancel is a root-zone future,
+  /// so under fake time (`fake_async`, Flutter's widget tests) the answer
+  /// would only arrive on the real event loop.
   Future<GraphQLResponse<D>> _first<D extends Object>(
     Stream<GraphQLResponse<D>> responses,
-  ) async {
-    await for (final response in responses) {
-      return response;
-    }
-    return const GraphQLTransportFailure(
+  ) => responses.firstWhere(
+    (response) => true,
+    orElse: () => const GraphQLTransportFailure(
       UnsupportedOperation(
         .linkEndedWithoutResult,
         'The link chain ended without a result.',
       ),
-    );
-  }
+    ),
+  );
 }
```

Modify `packages/typed_graphql_client/lib/src/client/operation_stream.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/lib/src/client/operation_stream.dart b/packages/typed_graphql_client/lib/src/client/operation_stream.dart
index 979ad65..bc1825f 100644
--- a/packages/typed_graphql_client/lib/src/client/operation_stream.dart
+++ b/packages/typed_graphql_client/lib/src/client/operation_stream.dart
@@ -55,14 +55,17 @@ final class OperationStream<D extends Object> {
         );
   }
 
-  Future<void>? _stop() {
+  /// Cancels the link chain's stream without returning its cancel future:
+  /// a returned one would make the caller wait on a root-zone future, so
+  /// under fake time a response would only arrive on the real event loop.
+  void _stop() {
     _removeListener?.call();
     _removeListener = null;
-    return _subscription?.cancel();
+    unawaited(_subscription?.cancel());
   }
 
   void _cancel(CancelToken token) {
-    unawaited(_stop());
+    _stop();
     _controller.add(GraphQLTransportFailure(RequestCancelled(token.reason)));
     _finish();
   }
@@ -75,7 +78,7 @@ final class OperationStream<D extends Object> {
     } else {
       _controller.addError(error, stackTrace);
     }
-    unawaited(_stop());
+    _stop();
     _finish();
   }
 
```

Modify `packages/typed_graphql_client/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_client/pubspec.yaml b/packages/typed_graphql_client/pubspec.yaml
index 2e8a513..84260c6 100644
--- a/packages/typed_graphql_client/pubspec.yaml
+++ b/packages/typed_graphql_client/pubspec.yaml
@@ -14,6 +14,7 @@ dependencies:
   typed_graphql: ^0.0.1
 
 dev_dependencies:
+  fake_async: ^1.3.1
   test: ^1.31.0
 
 resolution: workspace
```

- [ ] **Step 4: Format, then run the green check.**

This task changes a `pubspec.yaml`: run `flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart pub get'` at the root before anything else.

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
git commit -m "fix(typed_graphql_client): answer queries under fake time

Co-Authored-By: <the implementer's real model> <noreply@anthropic.com>"
```

## Review Focus

- `ClientFailure` and `LinkResult` are sealed and complete: every failure kind has its code, and every `switch` over them names every case.
- Nothing a server or a transport does throws (R0.3): a link failure is a value; only programmer errors (an open chain, a misplaced upload, `MockLink` without an answer) are errors.
- Cancellation: a cancelled `CancelToken` completes `query` at once and cancels the chain's subscription; a token cancelled before the call never calls the link.
- `LinkContext.withEntry` replaces only the exact runtime type; `RequestHeaders` lower-cases names.
- `Backoff.ceilingFor` cannot overflow for a large retry; `delayFor` is full jitter.
- `UploadFile.marker` is unique per object; `UploadFileCodec` refuses to decode.
- Task 10: `query` completes under `fakeAsync` (no awaited root-zone future).
- The client `lib/` imports nothing outside the allowed list; every exported type has its `{@category}`.

## Verification

After Task 10, run the full check once more and compare with the provenance counts:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart test"'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql && dart test"'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; timeout 900 bash -c "cd packages/typed_graphql_client && dart doc --dry-run"'
```

Expected: 0 files changed, `No issues found!`, the root suite (353 tests) and the client suite (225) pass, the core suite passes, `dart doc` reports "Found 0 warnings and 0 errors". Then run the self-review of CLAUDE.md (`wc -l` of every file touched, the longest method).
