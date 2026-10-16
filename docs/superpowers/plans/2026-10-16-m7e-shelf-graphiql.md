# M7e Shelf Adapter and GraphiQL Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete stage M7: merge the graphql-ws line (M7c) into the main line, serve a GraphiQL page in development (R5.9, R5.15), and make `typed_graphql_shelf` usable: `GraphQLShelfHandler` serves GraphQL over HTTP (with uploads and event streams) and graphql-ws over shelf WebSockets, and `TempFileUploadStorage` keeps uploads in temporary files. End-to-end tests run every transport over `shelf_io` on loopback; the documentation, `CLAUDE.md`, `llms.txt`, `docs/discovery.md` and the READMEs say what works.

**Architecture:** GraphiQL is a server feature, not a shelf one: `ServerProfile.graphiql` switches it, `GraphiQLRequest` decides that a `GET` without a query prefers `text/html`, and `GraphiQLPage` writes a page that loads React and GraphiQL from jsDelivr with Subresource Integrity, so any host gets it. `typed_graphql_shelf` is a thin adapter: `RequestConversion` and `ResponseConversion` map shelf's `Request` and `Response` to the server's HTTP values (a streamed body unbuffered), `WebSocketChannelSocket` wraps a `WebSocketChannel` as a `GraphQLSocket`, and `GraphQLShelfHandler` routes an upgrade to `GraphQLWsHandler` after the Origin check and everything else to `GraphQLHttpHandler`. `TempFileUploadStorage` is the package's only `dart:io` storage.

**Tech Stack:** Dart 3.13 (formatted with the 3.47.6 Flutter SDK's Dart 3.13.5), `package:test`, `package:meta`; `shelf` (`^1.4.0`, resolved 1.4.2) in Task 4, `shelf_web_socket`, `web_socket_channel` and `stream_channel` in Task 5 (all already in the workspace lock; `dart pub get --offline`).

**Spec:** `docs/superpowers/specs/2026-10-16-m7-transports-design.md` (sections 2, 7, 8, 9, 11, 12, 14 and 17), `docs/requirements.md` (R5.9, R5.15), `docs/discovery.md`.

**Base:** the tree M7d leaves (its plan's last task) on the main line, and the branch of M7c for Task 1. It is generated from the commits that implemented it in a scratch copy, in order.

**Parallel work:** M7e is the last plan of M7 and runs alone, after M7a, M7b and M7d on the main line; its Task 1 merges M7c, which ran in parallel. Nothing else runs beside it within M7. The M11 client runtime (another planner) may run at the same time; it shares no file with M7e but `llms.txt`, `docs/discovery.md` and the root `README.md` (Task 8: keep both sides when merging).

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
- The server's `lib/` keeps its import rule (no `dart:io`, no shelf). `typed_graphql_shelf` may import `dart:io` only where it needs it (`TempFileUploadStorage`); its tests that use `dart:io` start with `@TestOn('vm')`.
- From Task 4 on, the green check includes the shelf suite: run the wrapped `dart test` in `packages/typed_graphql_shelf` too.
- Run `dart pub get --offline` (wrapped) after each pubspec change; never fetch from the network.
- A test that starts a server on loopback (port 0) closes it in `tearDown`; no test depends on a fixed port.

## Review Focus

1. The merge keeps both sides everywhere: `GQL432` sits between `GQL431` and `GQL433`, both changelogs and both dartdoc categories survive, and the full green check passes on the merged tree before the commit.
2. The GraphiQL page loads only the four assets of spec section 12, each with its exact `integrity` and `crossorigin="anonymous"`; the endpoint is a JSON string literal with `<`, `>`, `&`, U+2028 and U+2029 escaped; the four headers are exact; it is served only under `ServerProfile.graphiql`, only for a `GET` without a query whose `Accept` ranks `text/html` above the JSON types.
3. The shelf conversions keep the body a stream both ways (no buffering of a request, `shelf.io.buffer_output: false` for a streamed response), join repeated headers with `, `, and pass the shelf `Request` as `source`.
4. An upgrade is checked by `allowsUpgrade` before shelf upgrades it (`403` otherwise), offers only the `graphql-transport-ws` subprotocol, and a binary frame is decoded leniently so the server can close it `4400`; frames sent after close are dropped.
5. `TempFileUploadStorage` never leaves a file behind: a failing content stream deletes the partial file and rethrows; `release` deletes it and ignores a missing file.
6. Documentation says only what works today (`docs/discovery.md` rules): the shelf README loses its skeleton banner and its "Not usable yet." line only now, and `llms.txt` lists only shipped capabilities.

## File map

| File | Change | Task |
|---|---|---|
| `CLAUDE.md` | Modify | 8 |
| `README.md` | Modify | 8 |
| `docs/discovery.md` | Modify | 8 |
| `llms.txt` | Modify | 8 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 1, 2, 3, 8 |
| `packages/typed_graphql_server/README.md` | Modify | 1, 8 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 1 |
| `packages/typed_graphql_server/doc/http.md` | Modify | 3, 8 |
| `packages/typed_graphql_server/doc/server.md` | Modify | 2 |
| `packages/typed_graphql_server/doc/uploads.md` | Modify | 8 |
| `packages/typed_graphql_server/doc/websocket.md` | Modify | 8 |
| `packages/typed_graphql_server/lib/src/http/accept_negotiation.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/http/graphiql_page.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/http/graphiql_request.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/http/media_range.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/server/server_profile.dart` | Modify | 2 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 1 |
| `packages/typed_graphql_server/test/http/accept_negotiation_test.dart` | Modify | 3 |
| `packages/typed_graphql_server/test/http/graphiql_page_test.dart` | Create | 3 |
| `packages/typed_graphql_server/test/http/media_range_test.dart` | Modify | 3 |
| `packages/typed_graphql_server/test/server/server_profile_test.dart` | Modify | 2 |
| `packages/typed_graphql_shelf/CHANGELOG.md` | Modify | 4, 8 |
| `packages/typed_graphql_shelf/README.md` | Modify | 8 |
| `packages/typed_graphql_shelf/dartdoc_options.yaml` | Create | 4 |
| `packages/typed_graphql_shelf/doc/shelf.md` | Create, then Modify | 4, 8 |
| `packages/typed_graphql_shelf/example/example.dart` | Create | 8 |
| `packages/typed_graphql_shelf/lib/src/file_upload.dart` | Create | 6 |
| `packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart` | Create, then Modify | 4, 5 |
| `packages/typed_graphql_shelf/lib/src/request_conversion.dart` | Create, then Modify | 4, 5 |
| `packages/typed_graphql_shelf/lib/src/response_conversion.dart` | Create | 4 |
| `packages/typed_graphql_shelf/lib/src/temp_file_upload_storage.dart` | Create | 6 |
| `packages/typed_graphql_shelf/lib/src/web_socket_channel_socket.dart` | Create | 5 |
| `packages/typed_graphql_shelf/lib/src/web_socket_upgrade.dart` | Create | 5 |
| `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart` | Modify | 4, 5, 6 |
| `packages/typed_graphql_shelf/pubspec.yaml` | Modify | 4, 5 |
| `packages/typed_graphql_shelf/test/doc/category_tags_test.dart` | Create | 4 |
| `packages/typed_graphql_shelf/test/doc/doc_links_test.dart` | Create | 8 |
| `packages/typed_graphql_shelf/test/doc/doc_snippets_test.dart` | Create | 8 |
| `packages/typed_graphql_shelf/test/end_to_end_http_test.dart` | Create | 7 |
| `packages/typed_graphql_shelf/test/end_to_end_streams_test.dart` | Create | 7 |
| `packages/typed_graphql_shelf/test/graphql_shelf_handler_test.dart` | Create | 4 |
| `packages/typed_graphql_shelf/test/graphql_shelf_upgrade_test.dart` | Create | 5 |
| `packages/typed_graphql_shelf/test/graphql_shelf_web_socket_test.dart` | Create | 5 |
| `packages/typed_graphql_shelf/test/request_conversion_test.dart` | Create | 4 |
| `packages/typed_graphql_shelf/test/response_conversion_test.dart` | Create | 4 |
| `packages/typed_graphql_shelf/test/support/end_to_end_fixture.dart` | Create | 7 |
| `packages/typed_graphql_shelf/test/support/fake_web_socket_channel.dart` | Create | 5 |
| `packages/typed_graphql_shelf/test/support/frame_reader.dart` | Create | 5 |
| `packages/typed_graphql_shelf/test/support/loopback_server.dart` | Create | 5 |
| `packages/typed_graphql_shelf/test/support/shelf_fixture.dart` | Create, then Modify | 4, 5 |
| `packages/typed_graphql_shelf/test/temp_file_upload_storage_test.dart` | Create | 6 |
| `packages/typed_graphql_shelf/test/web_socket_channel_socket_test.dart` | Create | 5 |

### Task 1: merge: bring the graphql-ws transport into the main line

**Why.** M7c (graphql-ws) was built in parallel on its own branch from the same base; the shelf adapter needs both lines, so they meet here. The lines touch disjoint folders and conflict only in shared catalogue, changelog, barrel, dartdoc and README text.

**Produces:** the main line with `lib/src/websocket/`, `RequestInfo.connectionParams` and `GQL432`.

**Files (conflicts to resolve; every other file merges cleanly):**

- `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`
- `packages/typed_graphql/CHANGELOG.md`
- `packages/typed_graphql_server/CHANGELOG.md`
- `packages/typed_graphql_server/README.md`
- `packages/typed_graphql_server/dartdoc_options.yaml`
- `packages/typed_graphql_server/lib/typed_graphql_server.dart`

This task writes no new code: it merges the branch that holds the M7c plan's
nine commits (graphql-ws, implemented in parallel from the same base) into
the main M7 line, which holds M7a, M7b and M7d. The two lines touch disjoint
folders (`lib/src/websocket/` against `lib/src/http/`, `upload/`, `sse/`);
they meet only in the catalogue, the changelogs, the barrel, the dartdoc
options and the README.

- [ ] **Step 1: Start the merge.**

```sh
git merge --no-ff --no-commit m7c
```

(`m7c` is the branch of the M7c plan; use its actual name.) Expected: six
conflicts, in the files listed above.

- [ ] **Step 2: Resolve each conflict.**

1. `diagnostic_code.dart`: keep both sides, in id order. The main line's
   block runs `GQL420`-`GQL431`, then `GQL433`-`GQL438`, then
   `GQL440`-`GQL442`; insert M7c's `GQL432` entry right after
   `operationTypeNotAllowed('GQL431'),` and its blank line, so that the
   result reads:

   ```text
     operationTypeNotAllowed('GQL431'),

     /// `GQL432`: reported when a graphql-ws `subscribe` arrives while the
     /// socket already runs `GraphQLWsOptions.maxOperations` operations; it is
     /// the `extensions.code` of the `error` message for that id, and the socket
     /// stays open.
     tooManySocketOperations('GQL432'),

     /// `GQL433`: reported when a request names an event stream token that no
   ```

2. `packages/typed_graphql/CHANGELOG.md`: keep both sides; M7c's
   `tooManySocketOperations` bullet goes right after the main line's
   `GQL420`-`GQL431` bullet and before the `GQL433`-`GQL438` one.

3. `packages/typed_graphql_server/CHANGELOG.md`: keep both sides, the main
   line's bullets first, then M7c's.

4. `packages/typed_graphql_server/dartdoc_options.yaml`: keep both sides in
   both conflicts: the `upload` category entry, then the `websocket` one;
   in `categoryOrder`, `upload` then `websocket` (alphabetical, after `sse`
   and `subscription`).

5. `packages/typed_graphql_server/lib/typed_graphql_server.dart`: in the
   exports, keep both sides (`src/upload/...` then `src/websocket/...`,
   alphabetical). Replace the conflicting library doc paragraph with:

   ```text
   /// Under construction: stages M5 and M6 are complete, and so are the HTTP
   /// handler of M7a, the multipart uploads of M7b, the graphql-ws handler of
   /// M7c and the server-sent events of M7d. The typed schema builder,
   /// execution, introspection, subscriptions, look-ahead, authorization and
   /// cancellation work, and so do DataLoader (`BatchLoader`, `GroupedLoader`),
   /// the request pipeline (`GraphQLServer`: document cache, limits and cost
   /// limit, CSRF prevention, extensions, error masking, automatic persisted
   /// queries and trusted documents), GraphQL over HTTP (`GraphQLHttpHandler`:
   /// `GET` and `POST`, media types and status codes, size and time limits,
   /// batching, multipart file uploads through `Uploads`, and GraphQL over
   /// server-sent events in both modes of graphql-sse through `SseOptions`)
   /// and graphql-ws (`GraphQLWsHandler` over any `GraphQLSocket`). The shelf
   /// adapter comes with the rest of M7. See the package README.
   ```

6. `packages/typed_graphql_server/README.md`: two conflicts. Replace the
   first (the status banner, after "with it stage") with:

   ```text
   > M6 is complete. The HTTP handler (M7a) works: `GraphQLHttpHandler` serves
   > GraphQL over HTTP (`GET` and `POST`, both media types, the status codes of
   > the specification, size and time limits, opt-in batching) for any web
   > framework through a small adapter, and reads multipart file uploads (M7b)
   > into the `Upload` scalar. The same handler streams results as server-sent
   > events (M7d, both modes of graphql-sse), and `GraphQLWsHandler` (M7c)
   > serves queries, mutations and subscriptions over a WebSocket. The shelf
   > adapter comes in the rest of M7. See the
   ```

   and the second (the "You do not need it when" bullet, after "that is
   the") with:

   ```text
     client package, not usable yet. Today it has the HTTP and graphql-ws
     handlers but no framework adapter: a host converts its request into an
     `HttpRequestData` and calls `GraphQLHttpHandler.handle`
     ([HTTP](doc/http.md)), or wraps its WebSocket in a `GraphQLSocket` and
     calls `GraphQLWsHandler.serve` ([WebSocket](doc/websocket.md)).
   ```

Check that no conflict marker is left:

```sh
git diff --check
grep -rn '^<<<<<<<\|^>>>>>>>' packages || true
```

Expected: no output from either command.

- [ ] **Step 3: Run the whole green check.** `CLAUDE.md`, `llms.txt`,
  `docs/discovery.md` and the root README are not touched here: Task 8
  writes the M7c and M7e parts of them.

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
```

Expected: 0 files changed, `No issues found!`, and every suite passes (in
the verification run: the root suite 361 tests, the core 1555, the server
1860).

- [ ] **Step 4: Commit the merge.**

```sh
git add -A packages
git commit -m "merge: bring the graphql-ws transport into the main line

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: feat(typed_graphql_server): switch GraphiQL on in the server profile

**Why.** R5.15 allows GraphiQL only in development; the switch belongs to the profile so one value decides it for every host (spec section 7).

**Produces:** `ServerProfile.graphiql` (true in `development`, false in `production`), `ServerProfile.withGraphiQL`, equality including it; the profile table of the server guide.

**Files:**

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/doc/server.md`
- Modify `packages/typed_graphql_server/lib/src/server/server_profile.dart`
- Modify `packages/typed_graphql_server/test/server/server_profile_test.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/server/server_profile_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_profile_test.dart b/packages/typed_graphql_server/test/server/server_profile_test.dart
index fc12afe..f919104 100644
--- a/packages/typed_graphql_server/test/server/server_profile_test.dart
+++ b/packages/typed_graphql_server/test/server/server_profile_test.dart
@@ -24,6 +24,8 @@ void main() {
     });
 
     test('has no timeout', () => expect(profile.timeout, isNull));
+
+    test('serves GraphiQL', () => expect(profile.graphiql, true));
   });
 
   group('ServerProfile.production', () {
@@ -48,6 +50,8 @@ void main() {
     });
 
     test('has no timeout', () => expect(profile.timeout, isNull));
+
+    test('does not serve GraphiQL', () => expect(profile.graphiql, false));
   });
 
   group('ServerProfile with methods', () {
@@ -88,18 +92,39 @@ void main() {
       expect(copy.timeout, const Duration(seconds: 5));
       expect(copy.withTimeout(null), base);
     });
+
+    test('withGraphiQL changes only the GraphiQL switch', () {
+      final copy = base.withGraphiQL(true);
+      expect(copy.graphiql, true);
+      expect(copy.withGraphiQL(false), base);
+    });
   });
 
   group('ServerProfile with methods keep the other fields', () {
     final base = ServerProfile.production
         .withCsrfPrevention(null)
-        .withTimeout(const Duration(seconds: 5));
+        .withTimeout(const Duration(seconds: 5))
+        .withGraphiQL(true);
 
     void expectKept(ServerProfile copy) {
       expect(copy.timeout, const Duration(seconds: 5));
       expect(copy.csrfPrevention, isNull);
+      expect(copy.graphiql, true);
     }
 
+    test('withCsrfPrevention', () {
+      expectKept(
+        base
+            .withCsrfPrevention(const CsrfPrevention())
+            .withCsrfPrevention(null),
+      );
+    });
+
+    test(
+      'withTimeout',
+      () => expectKept(base.withTimeout(const Duration(seconds: 5))),
+    );
+
     test('withIntrospection', () {
       expectKept(base.withIntrospection(IntrospectionPolicy.enabled));
     });
@@ -128,6 +153,12 @@ void main() {
       expect(copy.hashCode, ServerProfile.production.hashCode);
     });
 
+    test('differ when only GraphiQL differs', () {
+      final other = ServerProfile.production.withGraphiQL(true);
+      expect(other, isNot(ServerProfile.production));
+      expect(other.hashCode, isNot(ServerProfile.production.hashCode));
+    });
+
     test('the two constants differ', () {
       expect(ServerProfile.development, isNot(ServerProfile.production));
     });
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/server/server_profile_test.dart'
```

Expected: `server_profile_test.dart` fails to compile: `ServerProfile` has no getter `graphiql` and no method `withGraphiQL`.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index f74922a..37d4ae2 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -257,3 +257,5 @@
   (`allowsUpgrade`, `allowedOrigins`). The WebSocket guide is complete.
 - Tests: the graphql-ws hostile-input suite. A connection that ended while
   `onConnect` was pending is no longer acknowledged.
+- `ServerProfile.graphiql` (`true` in `development`, `false` in `production`)
+  and `withGraphiQL` switch the GraphiQL page of `GraphQLHttpHandler`.
```

Modify `packages/typed_graphql_server/doc/server.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/doc/server.md b/packages/typed_graphql_server/doc/server.md
index 13129c4..cbe6d0f 100644
--- a/packages/typed_graphql_server/doc/server.md
+++ b/packages/typed_graphql_server/doc/server.md
@@ -181,6 +181,7 @@ does not expose a server; `ServerProfile.development` is chosen explicitly.
 | `csrfPrevention` | `CsrfPrevention()` | `CsrfPrevention()` |
 | `limits` | `ServerLimits.development` | `ServerLimits.production` |
 | `timeout` | none | none |
+| `graphiql` | `true` | `false` (the GraphiQL page is not served) |
 
 `production` sets the limits of `ServerLimits.production` (document length,
 tokens, depth, aliases, directives, cost) but no `timeout`: add one with
@@ -191,7 +192,8 @@ and the limits are on.
 
 Each setting has a `with*` method that returns a copy:
 `withIntrospection`, `withSuggestions`, `withErrorMasking`,
-`withCsrfPrevention` (null turns it off), `withLimits` and `withTimeout`
+`withCsrfPrevention` (null turns it off), `withLimits`, `withGraphiQL` and
+`withTimeout`
 (queries and mutations only: a timeout would end a subscription).
 
 ```dart
````

Modify `packages/typed_graphql_server/lib/src/server/server_profile.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/server_profile.dart b/packages/typed_graphql_server/lib/src/server/server_profile.dart
index 0ef8a69..7b023d2 100644
--- a/packages/typed_graphql_server/lib/src/server/server_profile.dart
+++ b/packages/typed_graphql_server/lib/src/server/server_profile.dart
@@ -14,6 +14,7 @@ final class ServerProfile {
     required this.csrfPrevention,
     required this.limits,
     this.timeout,
+    this.graphiql = false,
   });
 
   /// Open for development: introspection and suggestions on, errors
@@ -24,11 +25,13 @@ final class ServerProfile {
     maskErrors: false,
     csrfPrevention: CsrfPrevention(),
     limits: .development,
+    graphiql: true,
   );
 
   /// Closed for production: introspection and suggestions off, errors
   /// masked, CSRF prevention on, and the limits of [ServerLimits.production]
-  /// (document length, tokens, depth, aliases, directives and cost). It sets
+  /// (document length, tokens, depth, aliases, directives and cost) and no
+  /// GraphiQL page. It sets
   /// no [timeout]: add one with [withTimeout]. `GraphQLServer` defaults to it.
   static const ServerProfile production = ServerProfile(
     introspection: .disabled,
@@ -56,6 +59,10 @@ final class ServerProfile {
   /// The time an execution may take; null is no limit.
   final Duration? timeout;
 
+  /// Whether `GraphQLHttpHandler` serves the GraphiQL page to a browser that
+  /// opens the endpoint.
+  final bool graphiql;
+
   /// A copy with [introspection].
   ServerProfile withIntrospection(IntrospectionPolicy introspection) =>
       _copy(introspection: introspection);
@@ -77,6 +84,7 @@ final class ServerProfile {
         csrfPrevention: csrfPrevention,
         limits: limits,
         timeout: timeout,
+        graphiql: graphiql,
       );
 
   /// A copy with [limits].
@@ -90,8 +98,12 @@ final class ServerProfile {
     csrfPrevention: csrfPrevention,
     limits: limits,
     timeout: timeout,
+    graphiql: graphiql,
   );
 
+  /// A copy with [graphiql].
+  ServerProfile withGraphiQL(bool graphiql) => _copy(graphiql: graphiql);
+
   // Copies the non-nullable fields; the two nullable ones, which a caller
   // may set to null, are copied by their own methods above.
   ServerProfile _copy({
@@ -99,6 +111,7 @@ final class ServerProfile {
     bool? includesSuggestions,
     bool? maskErrors,
     ServerLimits? limits,
+    bool? graphiql,
   }) => ServerProfile(
     introspection: introspection ?? this.introspection,
     includesSuggestions: includesSuggestions ?? this.includesSuggestions,
@@ -106,6 +119,7 @@ final class ServerProfile {
     csrfPrevention: csrfPrevention,
     limits: limits ?? this.limits,
     timeout: timeout,
+    graphiql: graphiql ?? this.graphiql,
   );
 
   @override
@@ -116,7 +130,8 @@ final class ServerProfile {
       other.maskErrors == maskErrors &&
       other.csrfPrevention == csrfPrevention &&
       other.limits == limits &&
-      other.timeout == timeout;
+      other.timeout == timeout &&
+      other.graphiql == graphiql;
 
   @override
   int get hashCode => Object.hash(
@@ -126,5 +141,6 @@ final class ServerProfile {
     csrfPrevention,
     limits,
     timeout,
+    graphiql,
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
git commit -m "feat(typed_graphql_server): switch GraphiQL on in the server profile

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: feat(typed_graphql_server): serve the GraphiQL page

**Why.** A browser opening the endpoint should see GraphiQL in development (R5.9). The page lives in the server so every host serves it; its assets come from a CDN with Subresource Integrity so a compromised CDN cannot run code on the page (spec section 12).

**Consumes:** Task 2's `ServerProfile.graphiql`; M7a's `AcceptNegotiation` and `MediaRange`.

**Produces:** internal `GraphiQLPage` and `GraphiQLRequest`; `MediaRange.specificityForName`, `AcceptNegotiation.qualityOfName`; the handler serves the page after the method check and before negotiation; a GraphiQL section in `doc/http.md`.

**Files:**

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/doc/http.md`
- Modify `packages/typed_graphql_server/lib/src/http/accept_negotiation.dart`
- Create `packages/typed_graphql_server/lib/src/http/graphiql_page.dart`
- Create `packages/typed_graphql_server/lib/src/http/graphiql_request.dart`
- Modify `packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart`
- Modify `packages/typed_graphql_server/lib/src/http/media_range.dart`
- Modify `packages/typed_graphql_server/test/http/accept_negotiation_test.dart`
- Create `packages/typed_graphql_server/test/http/graphiql_page_test.dart`
- Modify `packages/typed_graphql_server/test/http/media_range_test.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/http/accept_negotiation_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/http/accept_negotiation_test.dart b/packages/typed_graphql_server/test/http/accept_negotiation_test.dart
index 07c968a..e5e3e23 100644
--- a/packages/typed_graphql_server/test/http/accept_negotiation_test.dart
+++ b/packages/typed_graphql_server/test/http/accept_negotiation_test.dart
@@ -144,4 +144,25 @@ void main() {
       'application/graphql-response+json and application/json',
     );
   });
+
+  group('qualityOfName', () {
+    test('is 0 for a missing header', () {
+      expect(negotiation.qualityOfName('text', 'html', null), 0);
+    });
+
+    test('takes the quality of the most specific range', () {
+      expect(
+        negotiation.qualityOfName('text', 'html', '*/*;q=0.8, text/html'),
+        1,
+      );
+      expect(
+        negotiation.qualityOfName('text', 'html', 'text/*;q=0.5, */*'),
+        0.5,
+      );
+    });
+
+    test('is 0 for a type the header does not name', () {
+      expect(negotiation.qualityOfName('text', 'html', 'application/json'), 0);
+    });
+  });
 }
```

Create `packages/typed_graphql_server/test/http/graphiql_page_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/graphiql_page.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();
  const browser = {
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  };

  // A GET without a query that passes CSRF prevention, so a refusal is the
  // pipeline's GQL400 and not GQL403.
  HttpRequestData getWithoutQuery(String accept) => http.get(
    const {},
    headers: {...HttpFixture.preflight, 'accept': accept},
  );

  Future<String> pageOf(String path) =>
      http.text(const GraphiQLPage().response(path));

  group('the page', () {
    test('names React with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'src="https://cdn.jsdelivr.net/npm/react@18.3.1/umd/'
          'react.production.min.js" '
          'integrity="sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiD'
          'rcHkMLKI6fiB/Z" crossorigin="anonymous"',
        ),
      );
    });

    test('names ReactDOM with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'src="https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/'
          'react-dom.production.min.js" '
          'integrity="sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVd'
          'sSH1fSDUf5YJj1" crossorigin="anonymous"',
        ),
      );
    });

    test('names the GraphiQL style with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'href="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/'
          'graphiql.min.css" '
          'integrity="sha384-QMux00XgRtwRLSYIY3kw2rj1ovk5AuuliAchk+HSQbqdbGFnz9'
          'GYuqIlOqxhwCE2" crossorigin="anonymous"',
        ),
      );
    });

    test('names the GraphiQL script with its integrity', () async {
      final html = await pageOf('/graphql');
      expect(
        html,
        contains(
          'src="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/'
          'graphiql.min.js" '
          'integrity="sha384-8NGfVj4CVlqHajlZj+bPJT4thxPMHMJYn7DWK2CvtopLd02E7q'
          'sPHazniBYvVjOO" crossorigin="anonymous"',
        ),
      );
    });

    test('loads no script from anywhere else', () async {
      final html = await pageOf('/graphql');
      final sources = RegExp(
        '(?:src|href)="(https?:[^"]*)"',
      ).allMatches(html).map((match) => match.group(1)!);
      expect(
        sources.every((url) => url.startsWith('https://cdn.jsdelivr.net/npm/')),
        true,
      );
      expect(sources, hasLength(4));
    });

    test('posts to the endpoint with the response types', () async {
      final html = await pageOf('/graphql');
      expect(html, contains('const endpoint = "/graphql";'));
      expect(html, contains("method: 'POST'"));
      expect(html, contains("'content-type': 'application/json'"));
      expect(
        html,
        contains(
          'accept: '
          "'application/graphql-response+json, application/json;q=0.9'",
        ),
      );
      expect(html, contains('React.createElement(GraphiQL, {fetcher})'));
    });

    test('escapes what could close the script or end the line', () async {
      final html = await pageOf('/</script>&\u2028\u2029');
      expect(
        html,
        contains(
          r'const endpoint = "/\u003c/script\u003e\u0026\u2028\u2029";',
        ),
      );
      expect(html, isNot(contains('/</script>')));
      expect(html, isNot(contains('\u2028')));
      expect(html, isNot(contains('\u2029')));
    });

    test('has the security headers', () {
      final response = const GraphiQLPage().response('/graphql');
      expect(response.status, 200);
      expect(response.headers, {
        'content-type': 'text/html; charset=utf-8',
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'no-referrer',
        'x-frame-options': 'DENY',
      });
    });
  });

  group('the handler', () {
    test('serves the page to a browser in development', () async {
      final response = await http.handler().handle(
        http.get(const {}, headers: browser),
      );
      expect(response.status, 200);
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
      expect(
        await http.text(response),
        contains('const endpoint = "/graphql"'),
      );
    });

    test('does not serve the page in production', () async {
      final response = await http
          .handler(profile: ServerProfile.production)
          .handle(http.get(const {}, headers: browser));
      expect(response.headers['content-type'], isNot(contains('text/html')));
      expect(await http.code(response), 'GQL403');
    });

    test('answers a production browser without a query as before', () async {
      final response = await http
          .handler(profile: ServerProfile.production)
          .handle(getWithoutQuery('application/graphql-response+json'));
      expect(await http.code(response), 'GQL400');
    });

    test('serves the page again when GraphiQL is switched on', () async {
      final profile = ServerProfile.production.withGraphiQL(true);
      final response = await http
          .handler(profile: profile)
          .handle(
            http.get(const {}, headers: browser),
          );
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });

    test('does not serve the page for Accept application/json', () async {
      final response = await http.handler().handle(
        getWithoutQuery('application/json'),
      );
      expect(await http.code(response), 'GQL400');
    });

    test('does not serve the page without Accept', () async {
      final response = await http.handler().handle(http.get(const {}));
      expect(await http.code(response), 'GQL400');
    });

    test('does not serve the page for */*', () async {
      final response = await http.handler().handle(
        getWithoutQuery('*/*'),
      );
      expect(await http.code(response), 'GQL400');
    });

    test('does not serve the page when JSON ranks as high', () async {
      final response = await http.handler().handle(
        getWithoutQuery('text/html, application/json'),
      );
      expect(await http.code(response), 'GQL400');
    });

    test('serves the page when html outranks JSON', () async {
      final response = await http.handler().handle(
        getWithoutQuery('application/json;q=0.5, text/html'),
      );
      expect(response.headers['content-type'], 'text/html; charset=utf-8');
    });

    test('does not serve the page for a GET with a query', () async {
      final response = await http.handler().handle(
        http.get(
          {'query': '{ hello }'},
          headers: {...HttpFixture.preflight, 'accept': 'text/html'},
        ),
      );
      expect(response.status, 406);
    });

    test('does not serve the page for a POST', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ hello }'}, headers: {'accept': 'text/html'}),
      );
      expect(response.status, 406);
    });

    test('serves the page at the path of the request', () async {
      final response = await http.handler().handle(
        HttpRequestData(
          method: 'GET',
          uri: Uri.parse('/api/graphql?x=1'),
          headers: browser,
        ),
      );
      expect(
        await http.text(response),
        contains('const endpoint = "/api/graphql";'),
      );
    });
  });
}
```

Modify `packages/typed_graphql_server/test/http/media_range_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/http/media_range_test.dart b/packages/typed_graphql_server/test/http/media_range_test.dart
index ec00fe2..183213f 100644
--- a/packages/typed_graphql_server/test/http/media_range_test.dart
+++ b/packages/typed_graphql_server/test/http/media_range_test.dart
@@ -90,4 +90,18 @@ void main() {
       );
     });
   });
+
+  group('MediaRange.specificityForName', () {
+    test('matches a type that is not a ResponseMediaType', () {
+      expect(
+        MediaRange.parse('text/html')!.specificityForName('text', 'html'),
+        2,
+      );
+      expect(MediaRange.parse('text/*')!.specificityForName('text', 'html'), 1);
+      expect(
+        MediaRange.parse('application/*')!.specificityForName('text', 'html'),
+        isNull,
+      );
+    });
+  });
 }
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test test/http/accept_negotiation_test.dart test/http/graphiql_page_test.dart test/http/media_range_test.dart'
```

Expected: `graphiql_page_test.dart` fails to compile: `package:typed_graphql_server/src/http/graphiql_page.dart` does not exist.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 37d4ae2..a06ea5d 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -259,3 +259,7 @@
   `onConnect` was pending is no longer acknowledged.
 - `ServerProfile.graphiql` (`true` in `development`, `false` in `production`)
   and `withGraphiQL` switch the GraphiQL page of `GraphQLHttpHandler`.
+- The GraphiQL page: with `ServerProfile.graphiql` on, `GraphQLHttpHandler`
+  answers a `GET` without a `query` whose `Accept` ranks `text/html` above
+  the JSON types with a page that loads GraphiQL 3.9.0 from jsDelivr, pinned
+  by Subresource Integrity, and sends its queries to the request's path.
```

Modify `packages/typed_graphql_server/doc/http.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/doc/http.md b/packages/typed_graphql_server/doc/http.md
index 0c80949..75cacae 100644
--- a/packages/typed_graphql_server/doc/http.md
+++ b/packages/typed_graphql_server/doc/http.md
@@ -344,3 +344,15 @@ buffering, and cancel the subscription when the client goes away.
   an unexpected failure in the handler is `GQL330` with a generic message.
 - **Subscriptions are refused** over plain JSON (`GQL431`), before the context
   is built; they have their own transports.
+
+## GraphiQL
+
+With `ServerProfile.graphiql` on (the default of `ServerProfile.development`,
+off in `production`), a `GET` without a `query` whose `Accept` ranks
+`text/html` above both JSON types gets the GraphiQL page instead of an error.
+A missing `Accept` or `*/*` ranks them equally, so it is still a GraphQL
+request. The page loads React and GraphiQL 3.9.0 from jsDelivr, each pinned
+by version and Subresource Integrity, sends its queries to the path it was
+opened at, and is served with `nosniff`, `no-referrer` and `x-frame-options:
+DENY`. Subscriptions are not run from the page. With the switch off, the same
+request is an ordinary one and, with no query, `GQL400`.
```

Modify `packages/typed_graphql_server/lib/src/http/accept_negotiation.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/http/accept_negotiation.dart b/packages/typed_graphql_server/lib/src/http/accept_negotiation.dart
index 133637f..2668006 100644
--- a/packages/typed_graphql_server/lib/src/http/accept_negotiation.dart
+++ b/packages/typed_graphql_server/lib/src/http/accept_negotiation.dart
@@ -36,13 +36,11 @@ final class AcceptNegotiation {
           ? ResponseMediaType.json
           : null;
     }
-    final ranges = [
-      for (final element in accept.split(',')) ?MediaRange.parse(element),
-    ];
+    final ranges = _rangesOf(accept);
     ResponseMediaType? best;
     var bestQuality = 0.0;
     for (final candidate in offered) {
-      final quality = _qualityOf(candidate, ranges);
+      final quality = _qualityOf(candidate.type, candidate.subtype, ranges);
       if (quality > bestQuality) {
         best = candidate;
         bestQuality = quality;
@@ -51,11 +49,23 @@ final class AcceptNegotiation {
     return best;
   }
 
-  double _qualityOf(ResponseMediaType candidate, List<MediaRange> ranges) {
+  /// The quality [accept] gives to `type/subtype`, or 0 when it is missing,
+  /// blank or excludes it.
+  ///
+  /// Unlike [choose], a missing header gives nothing: the caller decides what
+  /// a client that did not say means.
+  double qualityOfName(String type, String subtype, String? accept) =>
+      accept == null ? 0 : _qualityOf(type, subtype, _rangesOf(accept));
+
+  static List<MediaRange> _rangesOf(String accept) => [
+    for (final element in accept.split(',')) ?MediaRange.parse(element),
+  ];
+
+  double _qualityOf(String type, String subtype, List<MediaRange> ranges) {
     var specificity = -1;
     var quality = 0.0;
     for (final range in ranges) {
-      final match = range.specificityFor(candidate);
+      final match = range.specificityForName(type, subtype);
       if (match == null || match < specificity) continue;
       if (match > specificity) quality = 0;
       specificity = match;
```

Create `packages/typed_graphql_server/lib/src/http/graphiql_page.dart`:

```dart
import 'dart:convert';

import 'package:meta/meta.dart';

import 'http_response_body.dart';
import 'http_response_data.dart';

/// The GraphiQL page `GraphQLHttpHandler` serves to a browser in development
/// (R5.9, R5.15).
///
/// Every asset is pinned by version and by Subresource Integrity, so a
/// compromised CDN cannot run code in the page. GraphiQL 3.9.0 is the last
/// release with a UMD build that sets `window.GraphiQL`.
@internal
final class GraphiQLPage {
  /// Creates the page.
  const GraphiQLPage();

  /// The Subresource Integrity values of the four assets, computed from the
  /// downloaded files on 2026-10-16.
  static const String reactIntegrity =
      'sha384-DGyLxAyjq0f9SPpVevD6IgztCFlnMF6oW/XQGmfe+IsZ8TqEiDrcHkMLKI6fiB/Z';

  /// See [reactIntegrity].
  static const String reactDomIntegrity =
      'sha384-gTGxhz21lVGYNMcdJOyq01Edg0jhn/c22nsx0kyqP0TxaV5WVdsSH1fSDUf5YJj1';

  /// See [reactIntegrity].
  static const String styleIntegrity =
      'sha384-QMux00XgRtwRLSYIY3kw2rj1ovk5AuuliAchk+HSQbqdbGFnz9GYuqIlOqxhwCE2';

  /// See [reactIntegrity].
  static const String scriptIntegrity =
      'sha384-8NGfVj4CVlqHajlZj+bPJT4thxPMHMJYn7DWK2CvtopLd02E7qsPHazniBYvVjOO';

  /// The page, which sends its queries to [path] (the path of the request
  /// that opened it).
  HttpResponseData response(String path) => HttpResponseData(
    200,
    headers: const {
      'content-type': 'text/html; charset=utf-8',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'x-frame-options': 'DENY',
    },
    body: FixedBody(utf8.encode(_html(path))),
  );

  // The path goes into a script, so it is a JSON string literal in which
  // nothing can close the script element or end the line early.
  String _endpointLiteral(String path) =>
      jsonEncode(path)
          .replaceAll('<', r'\u003c')
          .replaceAll('>', r'\u003e')
          .replaceAll('&', r'\u0026')
          .replaceAll('\u2028', r'\u2028')
          .replaceAll('\u2029', r'\u2029');

  String _html(String path) =>
      '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GraphiQL</title>
<style>body { height: 100vh; margin: 0; overflow: hidden; } #graphiql { height: 100vh; }</style>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/graphiql.min.css" integrity="$styleIntegrity" crossorigin="anonymous">
</head>
<body>
<div id="graphiql">Loading...</div>
<script src="https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js" integrity="$reactIntegrity" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js" integrity="$reactDomIntegrity" crossorigin="anonymous"></script>
<script src="https://cdn.jsdelivr.net/npm/graphiql@3.9.0/graphiql.min.js" integrity="$scriptIntegrity" crossorigin="anonymous"></script>
<script>
const endpoint = ${_endpointLiteral(path)};
const fetcher = async (params) => (await fetch(endpoint, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    accept: 'application/graphql-response+json, application/json;q=0.9',
  },
  body: JSON.stringify(params),
})).json();
ReactDOM.createRoot(document.getElementById('graphiql')).render(
  React.createElement(GraphiQL, {fetcher}),
);
</script>
</body>
</html>
''';
}
```

Create `packages/typed_graphql_server/lib/src/http/graphiql_request.dart`:

```dart
import 'package:meta/meta.dart';

import 'accept_negotiation.dart';
import 'http_request_data.dart';
import 'response_media_type.dart';

/// Decides whether a request is a browser opening the endpoint, which gets
/// the GraphiQL page instead of an answer (spec section 12).
@internal
final class GraphiQLRequest {
  /// Creates the decision.
  const GraphiQLRequest();

  static const AcceptNegotiation _negotiation = AcceptNegotiation([]);

  /// Whether [request] is a `GET` without a `query` whose `Accept` ranks
  /// `text/html` above both JSON types.
  ///
  /// A missing `Accept` or `*/*` ranks them equally, so it is a GraphQL
  /// request that will fail as one. A query string that is not valid UTF-8 is
  /// not a page request either: the handler refuses it.
  bool wants(HttpRequestData request) {
    if (request.method.toUpperCase() != 'GET') return false;
    if (_hasQuery(request.uri)) return false;
    final accept = request.header('accept');
    final html = _negotiation.qualityOfName('text', 'html', accept);
    if (html <= 0) return false;
    return html > _bestJson(accept);
  }

  bool _hasQuery(Uri uri) {
    try {
      return uri.queryParametersAll['query']?.any((v) => v.isNotEmpty) ?? false;
    } on FormatException {
      return true;
    }
  }

  double _bestJson(String? accept) {
    var best = 0.0;
    for (final type in const [
      ResponseMediaType.graphqlResponseJson,
      ResponseMediaType.json,
    ]) {
      final quality = _negotiation.qualityOfName(
        type.type,
        type.subtype,
        accept,
      );
      if (quality > best) best = quality;
    }
    return best;
  }
}
```

Modify `packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart b/packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart
index 22c58b7..b6ba20d 100644
--- a/packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart
+++ b/packages/typed_graphql_server/lib/src/http/graphql_http_handler.dart
@@ -10,6 +10,8 @@ import 'batch_policy.dart';
 import 'batch_runner.dart';
 import 'content_type.dart';
 import 'get_parameters.dart';
+import 'graphiql_page.dart';
+import 'graphiql_request.dart';
 import 'http_options.dart';
 import 'http_options_check.dart';
 import 'http_request_data.dart';
@@ -126,6 +128,9 @@ final class GraphQLHttpHandler<C> {
     final early = _routes?.early(request, method);
     if (early != null) return early;
     if (method != 'GET' && method != 'POST') return _unsupportedMethod();
+    if (server.profile.graphiql && const GraphiQLRequest().wants(request)) {
+      return const GraphiQLPage().response(request.uri.path);
+    }
     final negotiation = AcceptNegotiation(_offeredFor(request, method));
     final type = negotiation.choose(request.header('accept'));
     if (type == null) {
```

Modify `packages/typed_graphql_server/lib/src/http/media_range.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/http/media_range.dart b/packages/typed_graphql_server/lib/src/http/media_range.dart
index 731b307..fcc4436 100644
--- a/packages/typed_graphql_server/lib/src/http/media_range.dart
+++ b/packages/typed_graphql_server/lib/src/http/media_range.dart
@@ -41,11 +41,16 @@ final class MediaRange {
 
   /// How closely this range names [offered]: 2 for the exact type, 1 for
   /// `type/*`, 0 for `*/*`, null when it does not match.
-  int? specificityFor(ResponseMediaType offered) {
+  int? specificityFor(ResponseMediaType offered) =>
+      specificityForName(offered.type, offered.subtype);
+
+  /// [specificityFor] for a media type that is not a [ResponseMediaType], such
+  /// as the GraphiQL page's `text/html`.
+  int? specificityForName(String offeredType, String offeredSubtype) {
     if (type == '*') return 0;
-    if (type != offered.type) return null;
+    if (type != offeredType) return null;
     if (subtype == '*') return 1;
-    return subtype == offered.subtype ? 2 : null;
+    return subtype == offeredSubtype ? 2 : null;
   }
 
   static bool _isToken(String text) =>
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
git commit -m "feat(typed_graphql_server): serve the GraphiQL page

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: feat(typed_graphql_shelf): serve GraphQL over HTTP with shelf

**Why.** shelf is the adapter shipped with the server (R5.9, spec section 11): a handler that converts shelf's values to the server's and back, streaming both ways, so uploads and event streams work unbuffered.

**Consumes:** M7a's `GraphQLHttpHandler`, `HttpRequestData`, `HttpResponseData`.

**Produces:** the `shelf` dependency; public `GraphQLShelfHandler` (category `shelf`, a first `doc/shelf.md`, `dartdoc_options.yaml`); internal `RequestConversion`, `ResponseConversion`; test support `ShelfFixture`.

**Files:**

- Modify `packages/typed_graphql_shelf/CHANGELOG.md`
- Create `packages/typed_graphql_shelf/dartdoc_options.yaml`
- Create `packages/typed_graphql_shelf/doc/shelf.md`
- Create `packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart`
- Create `packages/typed_graphql_shelf/lib/src/request_conversion.dart`
- Create `packages/typed_graphql_shelf/lib/src/response_conversion.dart`
- Modify `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart`
- Modify `packages/typed_graphql_shelf/pubspec.yaml`
- Create `packages/typed_graphql_shelf/test/doc/category_tags_test.dart`
- Create `packages/typed_graphql_shelf/test/graphql_shelf_handler_test.dart`
- Create `packages/typed_graphql_shelf/test/request_conversion_test.dart`
- Create `packages/typed_graphql_shelf/test/response_conversion_test.dart`
- Create `packages/typed_graphql_shelf/test/support/shelf_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_shelf/test/doc/category_tags_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every exported public class is in the dartdoc category of the package, and
/// `dartdoc_options.yaml` declares it with a guide (R11.2).
void main() {
  final barrel = File('lib/typed_graphql_shelf.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();

  test('the category is declared with a guide that exists', () {
    expect(options, contains('shelf:\n      markdown: doc/shelf.md'));
    expect(File('doc/shelf.md').existsSync(), isTrue);
  });

  for (final path in exported) {
    test('$path tags each public class with the category', () {
      final source = File('lib/$path').readAsStringSync();
      final classes = RegExp(
        '^(?:final |base |abstract |sealed )*class [A-Z]',
        multiLine: true,
      ).allMatches(source);
      final tags = '{@category shelf}'.allMatches(source);
      expect(tags, hasLength(classes.length));
    });
  }
}
```

Create `packages/typed_graphql_shelf/test/graphql_shelf_handler_test.dart`:

```dart
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

import 'support/shelf_fixture.dart';

void main() {
  final fixture = ShelfFixture();
  final uri = Uri.parse('http://example.test/graphql');

  Future<Response> send(
    Request request, {
    ServerProfile profile = ServerProfile.development,
  }) async => await GraphQLShelfHandler<Object?>(
    fixture.server(profile: profile),
  )(request);

  Request post(String query) => Request(
    'POST',
    uri,
    headers: {'content-type': 'application/json'},
    body: jsonEncode({'query': query}),
  );

  test('answers a query posted as JSON', () async {
    final response = await send(post('{ hello }'));
    expect(response.statusCode, 200);
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('answers a mutation posted as JSON', () async {
    final response = await send(post('mutation { bump }'));
    expect(await response.readAsString(), '{"data":{"bump":"bumped"}}');
  });

  test('answers a query in a GET', () async {
    final response = await send(
      Request(
        'GET',
        uri.replace(queryParameters: {'query': '{ hello }'}),
        headers: {'graphql-require-preflight': 'true'},
      ),
    );
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('refuses a PUT with 405 and the allowed methods', () async {
    final response = await send(Request('PUT', uri));
    expect(response.statusCode, 405);
    expect(response.headers['allow'], 'GET, POST');
  });

  test('writes the media type of the result', () async {
    final response = await send(post('{ hello }'));
    expect(response.mimeType, 'application/json');
  });

  test('serves the GraphiQL page to a browser in development', () async {
    final response = await send(
      Request('GET', uri, headers: {'accept': 'text/html'}),
    );
    expect(response.mimeType, 'text/html');
  });

  test('does not serve the GraphiQL page in production', () async {
    final response = await send(
      Request('GET', uri, headers: {'accept': 'text/html'}),
      profile: ServerProfile.production,
    );
    expect(response.mimeType, isNot('text/html'));
  });

  test('is a shelf Handler', () {
    final Handler handler = GraphQLShelfHandler<Object?>(fixture.server()).call;
    expect(handler, isNotNull);
  });
}
```

Create `packages/typed_graphql_shelf/test/request_conversion_test.dart`:

```dart
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_shelf/src/request_conversion.dart';

void main() {
  const conversion = RequestConversion();

  Request request({
    String method = 'POST',
    String url = 'http://example.test/graphql?a=1',
    Map<String, Object> headers = const {},
    Object? body,
  }) => Request(method, Uri.parse(url), headers: headers, body: body);

  test('keeps the method', () {
    expect(conversion.convert(request(method: 'GET')).method, 'GET');
  });

  test('uses the requested URI with its query', () {
    final data = conversion.convert(request());
    expect(data.uri, Uri.parse('http://example.test/graphql?a=1'));
  });

  test('lower-cases header names', () {
    final data = conversion.convert(request(headers: {'Content-Type': 'x/y'}));
    expect(data.headers['content-type'], 'x/y');
    expect(data.headers.keys.every((name) => name == name.toLowerCase()), true);
  });

  test('joins repeated header values with a comma and a space', () {
    final data = conversion.convert(
      request(
        headers: {
          'Accept': ['text/html', 'application/json'],
        },
      ),
    );
    expect(data.header('accept'), 'text/html, application/json');
  });

  test('reads the body as bytes', () async {
    final data = conversion.convert(request(body: 'hello'));
    expect(
      utf8.decode(await data.body.expand((chunk) => chunk).toList()),
      'hello',
    );
  });

  test('hands the shelf request over as the source', () {
    final original = request();
    expect(conversion.convert(original).source, same(original));
  });

  test('gives no cancel signal, because shelf reports no disconnect', () {
    expect(conversion.convert(request()).cancelSignal, isNull);
  });
}
```

Create `packages/typed_graphql_shelf/test/response_conversion_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/src/response_conversion.dart';

void main() {
  const conversion = ResponseConversion();

  test('keeps the status', () {
    expect(conversion.convert(HttpResponseData(405)).statusCode, 405);
  });

  test('keeps the headers', () {
    final response = conversion.convert(
      HttpResponseData(200, headers: const {'allow': 'GET, POST'}),
    );
    expect(response.headers['allow'], 'GET, POST');
  });

  test('writes a fixed body with its length', () async {
    final response = conversion.convert(
      HttpResponseData(200, body: FixedBody(utf8.encode('{"a":1}'))),
    );
    expect(await response.readAsString(), '{"a":1}');
    expect(response.contentLength, 7);
  });

  test('writes a streamed body chunk by chunk', () async {
    final chunks = StreamController<List<int>>();
    final response = conversion.convert(
      HttpResponseData(200, body: StreamedBody(chunks.stream)),
    );
    final seen = <String>[];
    final done = response.read().map(utf8.decode).forEach(seen.add);
    chunks.add(utf8.encode('one'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen, ['one']);
    chunks.add(utf8.encode('two'));
    await chunks.close();
    await done;
    expect(seen, ['one', 'two']);
  });

  test('asks shelf_io not to buffer a streamed body', () {
    final response = conversion.convert(
      HttpResponseData(200, body: const StreamedBody(Stream.empty())),
    );
    expect(response.context['shelf.io.buffer_output'], false);
  });

  test('leaves a fixed body to the default buffering', () {
    final response = conversion.convert(HttpResponseData(200));
    expect(response.context.containsKey('shelf.io.buffer_output'), false);
  });
}
```

Create `packages/typed_graphql_shelf/test/support/shelf_fixture.dart`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A small executable schema and the server over it, for the adapter tests.
final class ShelfFixture {
  ShelfFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    schema = b.build(query: query, mutation: mutation);
  }

  // Set by the constructor body, before anything reads it.
  late final ExecutableSchema<Object?> schema;

  GraphQLServer<Object?> server({
    ServerProfile profile = ServerProfile.development,
  }) => GraphQLServer<Object?>(
    schema: schema,
    contextFactory: (_) => null,
    profile: profile,
  );
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test test/doc/category_tags_test.dart test/graphql_shelf_handler_test.dart test/request_conversion_test.dart test/response_conversion_test.dart'
```

Expected: the new tests fail to load: `package:shelf` is not a dependency and `GraphQLShelfHandler` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_shelf/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/CHANGELOG.md b/packages/typed_graphql_shelf/CHANGELOG.md
index aae31f5..1019926 100644
--- a/packages/typed_graphql_shelf/CHANGELOG.md
+++ b/packages/typed_graphql_shelf/CHANGELOG.md
@@ -6,3 +6,6 @@
 - `repository` points at the package folder; pub.dev is expected to rewrite
   relative README links from it (to confirm at M16).
 - The README says the package is not usable yet.
+- `GraphQLShelfHandler`: a shelf `Handler` that serves GraphQL over HTTP
+  through `GraphQLHttpHandler` (`HttpOptions` as `http`), with streamed bodies
+  written unbuffered. The shelf guide is `doc/shelf.md`.
```

Create `packages/typed_graphql_shelf/dartdoc_options.yaml`:

```yaml
dartdoc:
  categories:
    shelf:
      markdown: doc/shelf.md
      displayName: shelf
  categoryOrder:
    - shelf
  showUndocumentedCategories: true
```

Create `packages/typed_graphql_shelf/doc/shelf.md`:

````markdown
# shelf adapter

`typed_graphql_shelf` serves a `GraphQLServer` from a shelf application. The
adapter is thin: `GraphQLShelfHandler` turns each shelf `Request` into the
`HttpRequestData` of `typed_graphql_server`, runs `GraphQLHttpHandler` and
writes its `HttpResponseData` as a shelf `Response`. The limits, the media
types, the status codes and the GraphiQL page are the HTTP guide's of
`typed_graphql_server`.

## The handler

```text
final class GraphQLShelfHandler<C> {
  GraphQLShelfHandler(GraphQLServer<C> server, {HttpOptions http});
  FutureOr<Response> call(Request request);
}
```

The handler is a shelf `Handler`: pass `handler.call` to `shelf_io.serve`, or
mount it in a router at the path of the endpoint. Routing, CORS and logging
stay with shelf. The page of GraphiQL sends its queries to the path the
browser opened it at, so any mount point works.

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
````

Create `packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart`:

```dart
import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'request_conversion.dart';
import 'response_conversion.dart';

/// Serves GraphQL over HTTP as a shelf `Handler` (R5.9).
///
/// It converts each shelf [Request] for a [GraphQLHttpHandler] and writes the
/// answer as a [Response]; routing, CORS and middleware stay with shelf, so
/// mount it where the endpoint lives, for example with `Router.all`.
///
/// {@category shelf}
final class GraphQLShelfHandler<C> {
  /// Creates a handler that sends requests to [server] under the limits and
  /// settings of [http].
  ///
  /// Throws an `ArgumentError` when [http] holds a limit that makes no sense.
  GraphQLShelfHandler(
    GraphQLServer<C> server, {
    HttpOptions http = const HttpOptions(),
  }) : _http = GraphQLHttpHandler<C>(server, options: http);

  final GraphQLHttpHandler<C> _http;

  /// Answers [request]; it never throws.
  FutureOr<Response> call(Request request) async => const ResponseConversion()
      .convert(await _http.handle(const RequestConversion().convert(request)));
}
```

Create `packages/typed_graphql_shelf/lib/src/request_conversion.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// Turns a shelf [Request] into the [HttpRequestData] the HTTP handler reads.
@internal
final class RequestConversion {
  /// Creates the conversion.
  const RequestConversion();

  /// The data of [request].
  ///
  /// shelf lower-cases header names but joins repeated values with `,` only,
  /// so they are joined again with `, `, which is what the handler expects.
  /// The body is the request's own stream, read only when the handler needs
  /// it. No cancel signal is given: shelf does not report that the client
  /// went away, but `shelf_io` cancels the subscription to a streamed
  /// response body when it does, and that is what stops the work behind an
  /// event stream.
  HttpRequestData convert(Request request) => HttpRequestData(
    method: request.method,
    uri: request.requestedUri,
    headers: {
      for (final MapEntry(:key, :value) in request.headersAll.entries)
        key: value.join(', '),
    },
    body: request.read(),
    source: request,
  );
}
```

Create `packages/typed_graphql_shelf/lib/src/response_conversion.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// Turns the [HttpResponseData] of the HTTP handler into a shelf [Response].
@internal
final class ResponseConversion {
  /// Creates the conversion.
  const ResponseConversion();

  /// The response for [data].
  ///
  /// A streamed body asks `shelf_io` not to buffer its output, so each chunk
  /// (an event of a stream) reaches the client when it is written.
  Response convert(HttpResponseData data) => switch (data.body) {
    FixedBody(:final bytes) => Response(
      data.status,
      body: bytes,
      headers: data.headers,
    ),
    StreamedBody(:final chunks) => Response(
      data.status,
      body: chunks,
      headers: data.headers,
      context: const {'shelf.io.buffer_output': false},
    ),
  };
}
```

Modify `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart b/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
index f085805..69eb8f6 100644
--- a/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
+++ b/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
@@ -1,5 +1,11 @@
 /// The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket
 /// handlers for shelf, with an optional GraphiQL page in development.
 ///
-/// Under construction: nothing is exported yet; see the package README.
+/// Under construction: `GraphQLShelfHandler` serves GraphQL over HTTP (queries,
+/// mutations, batching, uploads, server-sent events and the GraphiQL page of
+/// `ServerProfile.development`, as configured by `HttpOptions`). The WebSocket
+/// transport and temporary-file uploads come with the rest of M7. See the
+/// package README.
 library;
+
+export 'src/graphql_shelf_handler.dart';
```

Modify `packages/typed_graphql_shelf/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/pubspec.yaml b/packages/typed_graphql_shelf/pubspec.yaml
index 001e4ba..d52330f 100644
--- a/packages/typed_graphql_shelf/pubspec.yaml
+++ b/packages/typed_graphql_shelf/pubspec.yaml
@@ -10,6 +10,8 @@ environment:
   sdk: ^3.13.0
 
 dependencies:
+  meta: ^1.15.0
+  shelf: ^1.4.0
   typed_graphql_server: ^0.0.1
 
 dev_dependencies:
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_shelf): serve GraphQL over HTTP with shelf

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: feat(typed_graphql_shelf): serve graphql-ws over shelf WebSockets

**Why.** graphql-ws needs a WebSocket, which only the host has: the adapter upgrades a shelf request after the server's Origin check (spec section 9) and hands the channel to `GraphQLWsHandler` as a `GraphQLSocket` (spec section 11).

**Consumes:** M7c's `GraphQLWsHandler`, `GraphQLWsOptions`, `GraphQLSocket` and `allowsUpgrade`; Task 4's `GraphQLShelfHandler` and `RequestConversion`.

**Produces:** the `shelf_web_socket` and `web_socket_channel` dependencies (`stream_channel` for tests); the `webSocket` and `webSocketPingInterval` parameters of `GraphQLShelfHandler`; internal `WebSocketChannelSocket` and `WebSocketUpgrade`; test support `LoopbackServer`, `FrameReader`, `FakeWebSocketChannel`.

**Files:**

- Modify `packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart`
- Modify `packages/typed_graphql_shelf/lib/src/request_conversion.dart`
- Create `packages/typed_graphql_shelf/lib/src/web_socket_channel_socket.dart`
- Create `packages/typed_graphql_shelf/lib/src/web_socket_upgrade.dart`
- Modify `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart`
- Modify `packages/typed_graphql_shelf/pubspec.yaml`
- Create `packages/typed_graphql_shelf/test/graphql_shelf_upgrade_test.dart`
- Create `packages/typed_graphql_shelf/test/graphql_shelf_web_socket_test.dart`
- Create `packages/typed_graphql_shelf/test/support/fake_web_socket_channel.dart`
- Create `packages/typed_graphql_shelf/test/support/frame_reader.dart`
- Create `packages/typed_graphql_shelf/test/support/loopback_server.dart`
- Modify `packages/typed_graphql_shelf/test/support/shelf_fixture.dart`
- Create `packages/typed_graphql_shelf/test/web_socket_channel_socket_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_shelf/test/graphql_shelf_upgrade_test.dart`:

```dart
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

import 'support/shelf_fixture.dart';

void main() {
  final fixture = ShelfFixture();
  final uri = Uri.parse('http://example.test/graphql');

  final queryUri = uri.replace(queryParameters: {'query': '{ hello }'});

  Request upgrade({Map<String, String> headers = const {}}) => Request(
    'GET',
    queryUri,
    headers: {
      'graphql-require-preflight': 'true',
      'connection': 'Upgrade',
      'upgrade': 'websocket',
      'sec-websocket-version': '13',
      'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
      ...headers,
    },
  );

  test('refuses an upgrade from a foreign origin with 403', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      upgrade(headers: {'origin': 'http://evil.example', 'host': 'a.test'}),
    );
    expect(response.statusCode, 403);
  });

  test('writes the refusal as a JSON error', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      upgrade(headers: {'origin': 'http://evil.example', 'host': 'a.test'}),
    );
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(response.headers['content-type'], startsWith('application/json'));
    expect(((body['errors'] as List).single as Map)['extensions'], {
      'code': 'GQL403',
    });
  });

  test('treats an upgrade as an ordinary GET without webSocket', () async {
    final handler = GraphQLShelfHandler<Object?>(fixture.server());
    final response = await handler(
      upgrade(headers: {'origin': 'http://evil.example'}),
    );
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('treats a GET without an upgrade as an ordinary GET', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      Request(
        'GET',
        queryUri,
        headers: {'graphql-require-preflight': 'true'},
      ),
    );
    expect(await response.readAsString(), '{"data":{"hello":"world"}}');
  });

  test('hands a same-host upgrade to the WebSocket handler', () async {
    final handler = GraphQLShelfHandler<Object?>(
      fixture.server(),
      webSocket: const GraphQLWsOptions(),
    );
    final response = await handler(
      upgrade(
        headers: {
          'origin': 'http://example.test',
          'host': 'example.test',
          'sec-websocket-version': '12',
        },
      ),
    );
    // shelf_web_socket answers 404 to a version it does not speak, which
    // shows the request got past the Origin check.
    expect(response.statusCode, 404);
  });
}
```

Create `packages/typed_graphql_shelf/test/graphql_shelf_web_socket_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';
import 'package:web_socket_channel/io.dart';

import 'support/frame_reader.dart';
import 'support/loopback_server.dart';
import 'support/shelf_fixture.dart';

void main() {
  final fixture = ShelfFixture();
  late LoopbackServer server;

  Future<void> serve({
    GraphQLWsOptions options = const GraphQLWsOptions(),
  }) async {
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(fixture.server(), webSocket: options).call,
    );
  }

  Future<FrameReader> connect({
    List<String>? protocols = const [GraphQLWsHandler.protocol],
    Map<String, Object>? headers,
  }) async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      protocols: protocols,
      headers: headers,
    );
    await channel.ready;
    return FrameReader(channel);
  }

  tearDown(() => server.close());

  test('acknowledges connection_init', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    expect((await client.next())['type'], 'connection_ack');
  });

  test('streams a subscription as next then complete', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    client.send({
      'id': '1',
      'type': 'subscribe',
      'payload': {'query': 'subscription { ticks }'},
    });
    final received = [for (var i = 0; i < 3; i++) await client.next()];
    expect(received, [
      {
        'id': '1',
        'type': 'next',
        'payload': {
          'data': {'ticks': 'tick 1'},
        },
      },
      {
        'id': '1',
        'type': 'next',
        'payload': {
          'data': {'ticks': 'tick 2'},
        },
      },
      {'id': '1', 'type': 'complete'},
    ]);
  });

  test('answers a query sent over the socket', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    client.send({
      'id': 'q',
      'type': 'subscribe',
      'payload': {'query': '{ hello }'},
    });
    expect((await client.next())['payload'], {
      'data': {'hello': 'world'},
    });
  });

  test('closes 4406 when the client offers no known subprotocol', () async {
    await serve();
    final client = await connect(protocols: null);
    expect(await client.closeCode(), 4406);
  });

  test('closes 4400 on a binary frame that is not JSON', () async {
    await serve();
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    client.channel.sink.add([0xFF, 0xFE]);
    expect(await client.closeCode(), 4400);
  });

  test('refuses an upgrade from a foreign origin with 403', () async {
    await serve();
    final http = HttpClient();
    addTearDown(http.close);
    final request = await http.getUrl(server.httpUri);
    request.headers
      ..set('connection', 'Upgrade')
      ..set('upgrade', 'websocket')
      ..set('sec-websocket-version', '13')
      ..set('sec-websocket-key', base64Encode(List.filled(16, 1)))
      ..set('origin', 'http://evil.example');
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 403);
  });

  test('accepts an origin listed in allowedOrigins', () async {
    await serve(
      options: const GraphQLWsOptions(allowedOrigins: ['http://app.example']),
    );
    final client = await connect(headers: {'origin': 'http://app.example'});
    client.send({'type': 'connection_init'});
    expect((await client.next())['type'], 'connection_ack');
  });

  test('negotiates the graphql-transport-ws subprotocol', () async {
    await serve();
    final client = await connect();
    expect(client.channel.protocol, GraphQLWsHandler.protocol);
  });

  test('sends WebSocket ping frames at the configured interval', () async {
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(
        fixture.server(),
        webSocket: const GraphQLWsOptions(),
        webSocketPingInterval: const Duration(milliseconds: 30),
      ).call,
    );
    final client = await connect();
    client.send({'type': 'connection_init'});
    await client.next();
    // A ping the client does not answer would end the connection; the pong
    // dart:io sends by itself keeps it open past several intervals.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(client.channel.closeCode, isNull);
  });
}
```

Create `packages/typed_graphql_shelf/test/support/fake_web_socket_channel.dart`:

```dart
import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A [WebSocketChannel] the test drives by hand.
final class FakeWebSocketChannel extends StreamChannelMixin<Object?>
    implements WebSocketChannel {
  FakeWebSocketChannel({this.protocol});

  /// The frames the "client" sends: a `String` or a list of bytes.
  final StreamController<Object?> frames = StreamController<Object?>();

  /// What the adapter wrote and closed.
  final FakeWebSocketSink fakeSink = FakeWebSocketSink();

  @override
  final String? protocol;

  /// Ends both directions; the sink records the close like any other.
  void finish() {
    unawaited(frames.close());
    unawaited(fakeSink.close());
  }

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get stream => frames.stream;

  @override
  WebSocketSink get sink => fakeSink;
}

/// The sink of [FakeWebSocketChannel]: it records instead of sending.
final class FakeWebSocketSink implements WebSocketSink {
  /// The frames added, in order.
  final List<Object?> added = [];

  /// The `(code, reason)` of each close.
  final List<(int?, String?)> closes = [];

  @override
  void add(Object? data) => added.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async =>
      closes.add((closeCode, closeReason));

  @override
  Future<void> get done => Future<void>.value();
}
```

Create `packages/typed_graphql_shelf/test/support/frame_reader.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Reads the JSON messages of a graphql-ws client channel one at a time.
final class FrameReader {
  FrameReader(this.channel) : _frames = StreamIterator(channel.stream);

  final WebSocketChannel channel;
  final StreamIterator<Object?> _frames;

  /// Sends [message] as one text frame.
  void send(Map<String, Object?> message) =>
      channel.sink.add(jsonEncode(message));

  /// The next message; a timeout fails the test when none comes.
  Future<Map<String, Object?>> next() async {
    final hasFrame = await _frames.moveNext().timeout(
      const Duration(seconds: 5),
    );
    if (!hasFrame) {
      throw StateError('The channel closed: ${channel.closeCode}');
    }
    return jsonDecode(_frames.current! as String) as Map<String, Object?>;
  }

  /// Waits until the server closes the channel and returns its close code.
  Future<int?> closeCode() async {
    while (await _frames.moveNext().timeout(const Duration(seconds: 5))) {}
    return channel.closeCode;
  }
}
```

Create `packages/typed_graphql_shelf/test/support/loopback_server.dart`:

```dart
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// A shelf handler served on a free loopback port, for a test to close.
final class LoopbackServer {
  LoopbackServer._(this._server);

  /// Starts serving [handler] on port 0.
  static Future<LoopbackServer> start(Handler handler) async =>
      LoopbackServer._(
        await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0),
      );

  final HttpServer _server;

  /// The HTTP address of the server.
  Uri get httpUri => Uri.parse('http://127.0.0.1:${_server.port}/graphql');

  /// The WebSocket address of the server.
  Uri get webSocketUri => Uri.parse('ws://127.0.0.1:${_server.port}/graphql');

  /// Stops the server and ends the connections still open.
  Future<void> close() => _server.close(force: true);
}
```

Modify `packages/typed_graphql_shelf/test/support/shelf_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/test/support/shelf_fixture.dart b/packages/typed_graphql_shelf/test/support/shelf_fixture.dart
index 30fb325..1138f02 100644
--- a/packages/typed_graphql_shelf/test/support/shelf_fixture.dart
+++ b/packages/typed_graphql_shelf/test/support/shelf_fixture.dart
@@ -1,3 +1,5 @@
+import 'dart:async';
+
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
 /// A small executable schema and the server over it, for the adapter tests.
@@ -12,7 +14,22 @@ final class ShelfFixture {
       'Mutation',
       fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
     );
-    schema = b.build(query: query, mutation: mutation);
+    final subscription = b.object<Object?>(
+      'Subscription',
+      fields: (t) => [
+        t
+            .field('ticks', b.string)
+            .subscribeWith<int>(
+              (parent, args, context, info) => Stream.fromIterable([1, 2]),
+              (event, args, context, info) => 'tick $event',
+            ),
+      ],
+    );
+    schema = b.build(
+      query: query,
+      mutation: mutation,
+      subscription: subscription,
+    );
   }
 
   // Set by the constructor body, before anything reads it.
```

Create `packages/typed_graphql_shelf/test/web_socket_channel_socket_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_shelf/src/web_socket_channel_socket.dart';

import 'support/fake_web_socket_channel.dart';

void main() {
  late FakeWebSocketChannel channel;
  late WebSocketChannelSocket socket;

  setUp(() {
    channel = FakeWebSocketChannel(protocol: 'graphql-transport-ws');
    socket = WebSocketChannelSocket(channel, channel.protocol);
    addTearDown(channel.finish);
  });

  test('exposes the negotiated subprotocol', () {
    expect(socket.protocol, 'graphql-transport-ws');
  });

  test('delivers a text frame as it is', () async {
    final frames = socket.incoming.toList();
    channel.frames.add('{"type":"ping"}');
    await channel.frames.close();
    expect(await frames, ['{"type":"ping"}']);
  });

  test('decodes a binary frame as UTF-8', () async {
    final frames = socket.incoming.toList();
    channel.frames.add([0x68, 0xC3, 0xA9]);
    await channel.frames.close();
    expect(await frames, ['hé']);
  });

  test('replaces malformed UTF-8 in a binary frame', () async {
    final frames = socket.incoming.toList();
    channel.frames.add([0xFF, 0x41]);
    await channel.frames.close();
    expect(await frames, ['�A']);
  });

  test('completes incoming when the connection ends', () async {
    final done = socket.incoming.isEmpty;
    await channel.frames.close();
    expect(await done, isTrue);
  });

  test('writes a sent message as one text frame', () {
    socket.send('hello');
    expect(channel.fakeSink.added, ['hello']);
  });

  test('drops a message sent after close', () async {
    await socket.close(1000, 'bye');
    socket.send('late');
    expect(channel.fakeSink.added, isEmpty);
  });

  test('drops a message sent after the peer closed', () {
    channel.closeCode = 1001;
    socket.send('late');
    expect(channel.fakeSink.added, isEmpty);
  });

  test('closes the sink with the code and the reason', () async {
    await socket.close(4400, 'Invalid message received');
    expect(channel.fakeSink.closes, [(4400, 'Invalid message received')]);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test test/graphql_shelf_upgrade_test.dart test/graphql_shelf_web_socket_test.dart test/web_socket_channel_socket_test.dart'
```

Expected: the new tests fail to compile: `WebSocketChannelSocket` is not defined and `GraphQLShelfHandler` has no named parameter `webSocket`.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart b/packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart
index 964bffb..929b6d9 100644
--- a/packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart
+++ b/packages/typed_graphql_shelf/lib/src/graphql_shelf_handler.dart
@@ -5,27 +5,51 @@ import 'package:typed_graphql_server/typed_graphql_server.dart';
 
 import 'request_conversion.dart';
 import 'response_conversion.dart';
+import 'web_socket_upgrade.dart';
 
-/// Serves GraphQL over HTTP as a shelf `Handler` (R5.9).
+/// Serves GraphQL over HTTP and WebSocket as a shelf `Handler` (R5.9).
 ///
 /// It converts each shelf [Request] for a [GraphQLHttpHandler] and writes the
-/// answer as a [Response]; routing, CORS and middleware stay with shelf, so
-/// mount it where the endpoint lives, for example with `Router.all`.
+/// answer as a [Response]; with `webSocket` set, a WebSocket upgrade becomes
+/// a graphql-ws session instead. Routing, CORS and middleware stay with
+/// shelf, so mount it where the endpoint lives, for example with
+/// `Router.all`.
 ///
 /// {@category shelf}
 final class GraphQLShelfHandler<C> {
   /// Creates a handler that sends requests to [server] under the limits and
   /// settings of [http].
   ///
-  /// Throws an `ArgumentError` when [http] holds a limit that makes no sense.
+  /// A `GET` that asks to upgrade to a WebSocket is served as graphql-ws under
+  /// [webSocket] when it is given, with WebSocket ping frames every
+  /// [webSocketPingInterval]; without it, such a request is an ordinary `GET`.
+  ///
+  /// Throws an `ArgumentError` when [http] or [webSocket] holds a limit that
+  /// makes no sense.
   GraphQLShelfHandler(
     GraphQLServer<C> server, {
     HttpOptions http = const HttpOptions(),
-  }) : _http = GraphQLHttpHandler<C>(server, options: http);
+    GraphQLWsOptions? webSocket,
+    Duration webSocketPingInterval = const Duration(seconds: 12),
+  }) : _http = GraphQLHttpHandler<C>(server, options: http),
+       _upgrade = webSocket == null
+           ? null
+           : WebSocketUpgrade<C>(
+               GraphQLWsHandler<C>(server, options: webSocket),
+               webSocketPingInterval,
+             );
 
   final GraphQLHttpHandler<C> _http;
+  final WebSocketUpgrade<C>? _upgrade;
 
   /// Answers [request]; it never throws.
-  FutureOr<Response> call(Request request) async => const ResponseConversion()
-      .convert(await _http.handle(const RequestConversion().convert(request)));
+  FutureOr<Response> call(Request request) async {
+    final upgrade = _upgrade;
+    if (upgrade != null && upgrade.isUpgrade(request)) {
+      return upgrade.handle(request);
+    }
+    return const ResponseConversion().convert(
+      await _http.handle(const RequestConversion().convert(request)),
+    );
+  }
 }
```

Modify `packages/typed_graphql_shelf/lib/src/request_conversion.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/lib/src/request_conversion.dart b/packages/typed_graphql_shelf/lib/src/request_conversion.dart
index 416e264..881e1f8 100644
--- a/packages/typed_graphql_shelf/lib/src/request_conversion.dart
+++ b/packages/typed_graphql_shelf/lib/src/request_conversion.dart
@@ -20,11 +20,22 @@ final class RequestConversion {
   HttpRequestData convert(Request request) => HttpRequestData(
     method: request.method,
     uri: request.requestedUri,
-    headers: {
-      for (final MapEntry(:key, :value) in request.headersAll.entries)
-        key: value.join(', '),
-    },
+    headers: _joinedHeaders(request),
     body: request.read(),
     source: request,
   );
+
+  /// What the graphql-ws handler reads of the upgrade [request], whose body
+  /// is not touched.
+  RequestInfo info(Request request) => RequestInfo(
+    method: request.method,
+    uri: request.requestedUri,
+    headers: _joinedHeaders(request),
+    source: request,
+  );
+
+  static Map<String, String> _joinedHeaders(Request request) => {
+    for (final MapEntry(:key, :value) in request.headersAll.entries)
+      key: value.join(', '),
+  };
 }
```

Create `packages/typed_graphql_shelf/lib/src/web_socket_channel_socket.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A [GraphQLSocket] over the [WebSocketChannel] that `shelf_web_socket`
/// hands to a connection.
@internal
final class WebSocketChannelSocket implements GraphQLSocket {
  /// Wraps [_channel], whose negotiated subprotocol is [protocol].
  WebSocketChannelSocket(this._channel, this.protocol)
    : incoming = _channel.stream.map(_text);

  final WebSocketChannel _channel;
  bool _isClosed = false;

  @override
  final String? protocol;

  @override
  final Stream<String> incoming;

  // A binary frame is decoded with replacement characters so that it fails
  // as JSON and closes the socket with `4400`, instead of throwing here.
  static String _text(Object? frame) => switch (frame) {
    String() => frame,
    List<int>() => utf8.decode(frame, allowMalformed: true),
    _ => '$frame',
  };

  @override
  void send(String text) {
    if (_isClosed || _channel.closeCode != null) {
      return;
    }
    _channel.sink.add(text);
  }

  @override
  Future<void> close(int code, String reason) async {
    _isClosed = true;
    await _channel.sink.close(code, reason);
  }
}
```

Create `packages/typed_graphql_shelf/lib/src/web_socket_upgrade.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'request_conversion.dart';
import 'web_socket_channel_socket.dart';

/// Turns a WebSocket upgrade into a graphql-ws session.
@internal
final class WebSocketUpgrade<C> {
  /// Creates the upgrade for [_handler], with WebSocket ping frames every
  /// [_pingInterval].
  WebSocketUpgrade(this._handler, this._pingInterval);

  final GraphQLWsHandler<C> _handler;
  final Duration _pingInterval;

  /// Whether [request] asks to become a WebSocket.
  bool isUpgrade(Request request) =>
      request.method == 'GET' &&
      request.headers['upgrade']?.toLowerCase() == 'websocket';

  /// Answers the upgrade [request]: a `403` when its `Origin` is not allowed
  /// (a browser sends cookies with an upgrade and no preflight, spec section
  /// 9), else the `101` that `shelf_web_socket` writes before the session.
  FutureOr<Response> handle(Request request) {
    final info = const RequestConversion().info(request);
    if (!_handler.allowsUpgrade(info)) {
      return _forbidden();
    }
    return webSocketHandler(
      (channel, protocol) => unawaited(
        _handler.serve(WebSocketChannelSocket(channel, protocol), info),
      ),
      protocols: const [GraphQLWsHandler.protocol],
      pingInterval: _pingInterval,
    )(request);
  }

  // A transport refusal, JSON like the HTTP handler's, with the CSRF code
  // because this is the CSRF defence of the WebSocket transport.
  Response _forbidden() => Response(
    403,
    body: RequestErrorResult(
      errors: [
        GraphQLError(
          'The Origin of this WebSocket upgrade is not allowed.',
          extensions: JsonObject({
            'code': JsonString(DiagnosticCode.csrfRequestBlocked.id),
          }),
        ),
      ],
    ).toJson().toString(),
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
```

Modify `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart b/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
index 69eb8f6..d7a6882 100644
--- a/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
+++ b/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
@@ -3,9 +3,9 @@
 ///
 /// Under construction: `GraphQLShelfHandler` serves GraphQL over HTTP (queries,
 /// mutations, batching, uploads, server-sent events and the GraphiQL page of
-/// `ServerProfile.development`, as configured by `HttpOptions`). The WebSocket
-/// transport and temporary-file uploads come with the rest of M7. See the
-/// package README.
+/// `ServerProfile.development`, as configured by `HttpOptions`) and, with
+/// `webSocket` set, graphql-ws over WebSocket. Temporary-file uploads come
+/// with the rest of M7. See the package README.
 library;
 
 export 'src/graphql_shelf_handler.dart';
```

Modify `packages/typed_graphql_shelf/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/pubspec.yaml b/packages/typed_graphql_shelf/pubspec.yaml
index d52330f..68ec65a 100644
--- a/packages/typed_graphql_shelf/pubspec.yaml
+++ b/packages/typed_graphql_shelf/pubspec.yaml
@@ -12,9 +12,13 @@ environment:
 dependencies:
   meta: ^1.15.0
   shelf: ^1.4.0
+  shelf_web_socket: ^3.0.0
+  typed_graphql: ^0.0.1
   typed_graphql_server: ^0.0.1
+  web_socket_channel: ^3.0.0
 
 dev_dependencies:
+  stream_channel: ^2.1.0
   test: ^1.31.0
 
 resolution: workspace
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_shelf): serve graphql-ws over shelf WebSockets

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: feat(typed_graphql_shelf): store uploads in temporary files

**Why.** `Uploads` needs an `UploadStorage` (M7b); the server ships only the in-memory one because its `lib/` imports no `dart:io`. A host on the VM wants files on disk that are deleted when the request ends (spec section 8).

**Consumes:** M7b's `UploadStorage`, `StoredUpload` and `Uploads`.

**Produces:** public `TempFileUploadStorage` and its `FileUpload` (category `shelf`).

**Files:**

- Create `packages/typed_graphql_shelf/lib/src/file_upload.dart`
- Create `packages/typed_graphql_shelf/lib/src/temp_file_upload_storage.dart`
- Modify `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart`
- Create `packages/typed_graphql_shelf/test/temp_file_upload_storage_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_shelf/test/temp_file_upload_storage_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

void main() {
  late Directory directory;
  late TempFileUploadStorage storage;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('typed_graphql_shelf_');
    storage = TempFileUploadStorage(directory: directory);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<String> read(Stream<List<int>> bytes) async =>
      utf8.decode([for (final chunk in await bytes.toList()) ...chunk]);

  test('reads back the bytes it stored', () async {
    final upload = await storage.store(
      'a.txt',
      'text/plain',
      Stream.fromIterable([utf8.encode('hel'), utf8.encode('lo')]),
    );
    expect(await read(upload.openRead()), 'hello');
  });

  test('keeps the file name and media type', () async {
    final upload = await storage.store(
      'a.txt',
      'text/plain',
      Stream.value(utf8.encode('x')),
    );
    expect((upload.filename, upload.mediaType), ('a.txt', 'text/plain'));
  });

  test('reports the byte count as the length', () async {
    final upload = await storage.store(
      'a.bin',
      'application/octet-stream',
      Stream.value([1, 2, 3, 4, 5]),
    );
    expect(upload.length, 5);
  });

  test('opens the content from the first byte every time', () async {
    final upload = await storage.store('a', 'b', Stream.value([7, 8]));
    await upload.openRead().drain<void>();
    expect(await upload.openRead().toList(), [
      [7, 8],
    ]);
  });

  test('stores two uploads of one name in two files', () async {
    final first = await storage.store('a', 'b', Stream.value([1]));
    final second = await storage.store('a', 'b', Stream.value([2]));
    expect(directory.listSync(), hasLength(2));
    expect(await first.openRead().toList(), [
      [1],
    ]);
    expect(await second.openRead().toList(), [
      [2],
    ]);
  });

  test('does not use the client file name as a path', () async {
    await storage.store('../../escape', 'b', Stream.value([1]));
    expect(directory.listSync().single.parent.path, directory.path);
  });

  test('deletes the file on release', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    expect(directory.listSync(), isEmpty);
  });

  test('releases an upload twice without failing', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    await expectLater(storage.release(upload), completes);
  });

  test('leaves no file when the content stream fails', () async {
    final content = Stream<List<int>>.multi((controller) {
      controller
        ..add([1, 2, 3])
        ..addError(const FormatException('too long'));
      controller.close();
    });
    await expectLater(
      storage.store('a', 'b', content),
      throwsA(isA<FormatException>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('stores in the system temporary directory by default', () async {
    final byDefault = TempFileUploadStorage();
    final upload = await byDefault.store('a', 'b', Stream.value([1]));
    addTearDown(() => byDefault.release(upload));
    expect(await upload.openRead().toList(), [
      [1],
    ]);
  });

  test('cannot read an upload after its release', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    await expectLater(
      upload.openRead().drain<void>(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test test/temp_file_upload_storage_test.dart'
```

Expected: `temp_file_upload_storage_test.dart` fails to compile: `TempFileUploadStorage` is not a type.

- [ ] **Step 3: Write the implementation.**

Create `packages/typed_graphql_shelf/lib/src/file_upload.dart`:

```dart
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// An [Upload] kept in a file that `TempFileUploadStorage` wrote.
@internal
final class FileUpload implements Upload {
  /// Describes the upload of [length] bytes kept in [file].
  const FileUpload(this.file, this.filename, this.mediaType, this.length);

  /// The file that holds the content.
  final File file;

  @override
  final String filename;

  @override
  final String mediaType;

  @override
  final int length;

  @override
  Stream<List<int>> openRead() => file.openRead();
}
```

Create `packages/typed_graphql_shelf/lib/src/temp_file_upload_storage.dart`:

```dart
import 'dart:io';
import 'dart:math';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'file_upload.dart';

/// An [UploadStorage] that writes each upload to a file in a temporary
/// directory and deletes the file on release.
///
/// It suits files too big for `MemoryUploadStorage`: the content never
/// waits in memory, and the size is bounded by `UploadLimits`. The files are
/// named at random, never after what the client sent, so a hostile file name
/// cannot reach another path.
///
/// {@category shelf}
final class TempFileUploadStorage implements UploadStorage {
  /// Creates a storage that writes under [directory], which must exist, or
  /// under `Directory.systemTemp` when it is null.
  TempFileUploadStorage({Directory? directory})
    : _directory = directory ?? Directory.systemTemp;

  final Directory _directory;
  final Random _random = Random.secure();

  @override
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  ) async {
    final file = await _newFile();
    final sink = file.openWrite();
    var isStored = false;
    try {
      await sink.addStream(content);
      await sink.close();
      isStored = true;
    } finally {
      // A failed content stream (a limit, a broken request) must not leave a
      // partial file; its own failure goes on to the caller.
      if (!isStored) await _discard(file, sink);
    }
    return FileUpload(file, filename, mediaType, await file.length());
  }

  @override
  Future<void> release(Upload upload) async {
    if (upload is! FileUpload) {
      return;
    }
    try {
      await upload.file.delete();
    } on PathNotFoundException {
      // Released twice, or removed from outside: nothing is left to free.
    }
  }

  // `exclusive` makes the creation fail rather than reuse a file that
  // another request, or another process, already made.
  Future<File> _newFile() async {
    final name = [
      for (var i = 0; i < 16; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    return File('${_directory.path}/upload_$name').create(exclusive: true);
  }

  Future<void> _discard(File file, IOSink sink) async {
    try {
      await sink.close();
    } on Exception {
      // The sink may hold the error of the failed content again; the
      // original failure is the one the caller sees.
    }
    try {
      await file.delete();
    } on PathNotFoundException {
      // Nothing was written.
    }
  }
}
```

Modify `packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart b/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
index d7a6882..66fe3fa 100644
--- a/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
+++ b/packages/typed_graphql_shelf/lib/typed_graphql_shelf.dart
@@ -4,8 +4,9 @@
 /// Under construction: `GraphQLShelfHandler` serves GraphQL over HTTP (queries,
 /// mutations, batching, uploads, server-sent events and the GraphiQL page of
 /// `ServerProfile.development`, as configured by `HttpOptions`) and, with
-/// `webSocket` set, graphql-ws over WebSocket. Temporary-file uploads come
-/// with the rest of M7. See the package README.
+/// `webSocket` set, graphql-ws over WebSocket; `TempFileUploadStorage` keeps
+/// multipart uploads in temporary files. See the package README.
 library;
 
 export 'src/graphql_shelf_handler.dart';
+export 'src/temp_file_upload_storage.dart';
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "feat(typed_graphql_shelf): store uploads in temporary files

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 7: test(typed_graphql_shelf): run the transports end to end over shelf_io

**Why.** The unit tests of Tasks 4-6 use shelf values in memory or a fake channel; only a real socket shows that a streamed body is flushed per event, that uploads reach the disk and leave nothing behind, and that a browser-like `Accept` gets the page (spec section 14, R5.9).

**Consumes:** Tasks 2-6.

**Produces:** end-to-end tests over `shelf_io` on loopback (HTTP `POST` and `GET`, `294`, `413`, a multipart upload into `TempFileUploadStorage`, the GraphiQL page in development and not in production, an event stream read with `HttpClient`, a graphql-ws subscription over `IOWebSocketChannel`) and their fixture `EndToEndFixture`.

**Files:**

- Create `packages/typed_graphql_shelf/test/end_to_end_http_test.dart`
- Create `packages/typed_graphql_shelf/test/end_to_end_streams_test.dart`
- Create `packages/typed_graphql_shelf/test/support/end_to_end_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_shelf/test/end_to_end_http_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

import 'support/end_to_end_fixture.dart';
import 'support/loopback_server.dart';

void main() {
  late EndToEndFixture fixture;
  late LoopbackServer server;
  late HttpClient client;
  late Directory directory;

  setUp(() {
    fixture = EndToEndFixture();
    client = HttpClient();
    directory = Directory.systemTemp.createTempSync('typed_graphql_e2e_');
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    await fixture.close();
    directory.deleteSync(recursive: true);
  });

  Future<void> serve({
    ServerProfile profile = ServerProfile.development,
    HttpOptions http = const HttpOptions(),
  }) async {
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(
        fixture.server(profile: profile),
        http: http,
      ).call,
    );
  }

  Future<(HttpClientResponse, String)> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) async {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    request.add(body);
    final response = await request.close();
    return (response, await utf8.decodeStream(response));
  }

  Future<(HttpClientResponse, String)> post(
    String query, {
    Map<String, String> headers = const {},
  }) => send(
    'POST',
    server.httpUri,
    headers: {'content-type': 'application/json', ...headers},
    body: utf8.encode(jsonEncode({'query': query})),
  );

  test('answers a JSON query over POST', () async {
    await serve();
    final (response, body) = await post('{ hello }');
    expect(response.statusCode, 200);
    expect(jsonDecode(body), {
      'data': {'hello': 'world'},
    });
  });

  test('answers a query over GET', () async {
    await serve();
    final uri = server.httpUri.replace(
      queryParameters: {'query': '{ hello }'},
    );
    final (response, body) = await send(
      'GET',
      uri,
      headers: {'graphql-require-preflight': 'true'},
    );
    expect(response.statusCode, 200);
    expect(jsonDecode(body), {
      'data': {'hello': 'world'},
    });
  });

  test(
    'sends status 294 for a partial result under graphql-response+json',
    () async {
      await serve();
      final (response, _) = await post(
        '{ hello broken }',
        headers: {'accept': 'application/graphql-response+json'},
      );
      expect(response.statusCode, 294);
    },
  );

  test('refuses a body larger than the limit with 413', () async {
    await serve(http: const HttpOptions(maxBodyBytes: 64));
    final (response, _) = await post('{ hello ${'x' * 200} }');
    expect(response.statusCode, 413);
  });

  test('stores an uploaded file and releases it after the response', () async {
    final storage = TempFileUploadStorage(directory: directory);
    final uploads = Uploads(storage: storage);
    await fixture.close();
    fixture = EndToEndFixture(uploads: uploads);
    await serve(http: HttpOptions(uploads: uploads));
    const boundary = 'e2eBoundary';
    final body = [
      '--$boundary',
      'content-disposition: form-data; name="operations"',
      '',
      jsonEncode({
        'query': r'mutation ($file: Upload!) { upload(file: $file) }',
        'variables': {'file': null},
      }),
      '--$boundary',
      'content-disposition: form-data; name="map"',
      '',
      '{"0":["variables.file"]}',
      '--$boundary',
      'content-disposition: form-data; name="0"; filename="notes.txt"',
      'content-type: text/plain',
      '',
      'hello',
      '--$boundary--',
      '',
    ].join('\r\n');
    final (response, answer) = await send(
      'POST',
      server.httpUri,
      headers: {
        'content-type': 'multipart/form-data; boundary=$boundary',
        'graphql-require-preflight': 'true',
      },
      body: utf8.encode(body),
    );
    expect(response.statusCode, 200);
    expect(jsonDecode(answer), {
      'data': {'upload': 'notes.txt: hello'},
    });
    expect(directory.listSync(), isEmpty);
  });

  test('serves the GraphiQL page to a browser in development', () async {
    await serve();
    final (response, body) = await send(
      'GET',
      server.httpUri,
      headers: {'accept': 'text/html'},
    );
    expect(
      (response.statusCode, response.headers.contentType?.mimeType),
      (
        200,
        'text/html',
      ),
    );
    expect(body, contains('GraphiQL'));
  });

  test('does not serve the GraphiQL page in production', () async {
    await serve(profile: ServerProfile.production);
    final (response, _) = await send(
      'GET',
      server.httpUri,
      headers: {'accept': 'text/html'},
    );
    expect(response.headers.contentType?.mimeType, isNot('text/html'));
  });
}
```

Create `packages/typed_graphql_shelf/test/end_to_end_streams_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';
import 'package:web_socket_channel/io.dart';

import 'support/end_to_end_fixture.dart';
import 'support/frame_reader.dart';
import 'support/loopback_server.dart';

void main() {
  late EndToEndFixture fixture;
  late LoopbackServer server;
  late HttpClient client;

  setUp(() async {
    fixture = EndToEndFixture();
    client = HttpClient();
    server = await LoopbackServer.start(
      GraphQLShelfHandler<Object?>(
        fixture.server(),
        webSocket: const GraphQLWsOptions(),
      ).call,
    );
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    await fixture.close();
  });

  test('delivers the first server-sent event before the second exists', () async {
    final request = await client.postUrl(server.httpUri);
    request.headers
      ..set('content-type', 'application/json')
      ..set('accept', 'text/event-stream')
      ..set('graphql-require-preflight', 'true');
    request.add(utf8.encode(jsonEncode({'query': 'subscription { ticks }'})));
    final response = await request.close();
    final lines = StreamIterator(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
    Future<String> nextData() async {
      while (await lines.moveNext().timeout(const Duration(seconds: 5))) {
        if (lines.current.startsWith('data:')) return lines.current;
      }
      throw StateError('The stream ended.');
    }

    // The subscription listens after the response starts; emit until it hears.
    final emitter = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => fixture.ticks.hasListener ? fixture.ticks.add(1) : null,
    );
    final first = await nextData();
    emitter.cancel();
    expect(response.headers.contentType?.mimeType, 'text/event-stream');
    expect(first, contains('"ticks":"tick 1"'));
    fixture.ticks.add(2);
    expect(await nextData(), contains('"ticks":"tick 2"'));
    await lines.cancel();
  });

  test('streams a graphql-ws subscription over a real socket', () async {
    final channel = IOWebSocketChannel.connect(
      server.webSocketUri,
      protocols: const [GraphQLWsHandler.protocol],
    );
    await channel.ready;
    final reader = FrameReader(channel);
    reader.send({'type': 'connection_init'});
    expect((await reader.next())['type'], 'connection_ack');
    reader.send({
      'id': '1',
      'type': 'subscribe',
      'payload': {'query': 'subscription { ticks }'},
    });
    final emitter = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => fixture.ticks.hasListener ? fixture.ticks.add(7) : null,
    );
    final message = await reader.next();
    emitter.cancel();
    expect(message, {
      'id': '1',
      'type': 'next',
      'payload': {
        'data': {'ticks': 'tick 7'},
      },
    });
    await channel.sink.close();
  });
}
```

Create `packages/typed_graphql_shelf/test/support/end_to_end_fixture.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A schema with a failing field, an upload mutation and a subscription whose
/// source the test emits into, for the end-to-end tests.
final class EndToEndFixture {
  EndToEndFixture({Uploads? uploads})
    : uploads = uploads ?? Uploads(),
      ticks = StreamController<int>.broadcast() {
    final b = ExecutableSchemaBuilder<Object?>();
    final upload = b.scalar<Upload>(
      Uploads.scalarName,
      this.uploads.codec,
    );
    final file = Arg('file', upload);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'world'),
        t
            .field('broken', b.string.nullable)
            .pure((_) => throw const GraphQLException('boom')),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('upload', b.string, args: [file]).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          final received = args.get(file);
          final bytes = await received.openRead().expand((c) => c).toList();
          return '${received.filename}: ${utf8.decode(bytes)}';
        }),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('ticks', b.string)
            .subscribeWith<int>(
              (parent, args, context, info) => ticks.stream,
              (event, args, context, info) => 'tick $event',
            ),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  /// The uploads shared by the schema's scalar and the HTTP options.
  final Uploads uploads;

  /// The source of the `ticks` subscription.
  final StreamController<int> ticks;

  /// Ends the subscription source.
  Future<void> close() => ticks.close();

  // Set by the constructor body, before anything reads it.
  late final ExecutableSchema<Object?> schema;

  GraphQLServer<Object?> server({
    ServerProfile profile = ServerProfile.development,
  }) => GraphQLServer<Object?>(
    schema: schema,
    contextFactory: (_) => null,
    profile: profile,
  );
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test test/end_to_end_http_test.dart test/end_to_end_streams_test.dart'
```

Expected: this task is test-only and every behaviour exists, so the new tests pass at once. To see the event-stream test guard what it should, set `shelf.io.buffer_output` to `true` in `ResponseConversion`: `delivers the first server-sent event before the second exists` then fails (`Expected: contains '"ticks":"tick 2"'`, the buffered stream holds back the events); restore `false` before Step 4.

- [ ] **Step 3: Write the implementation.**

No file outside the tests changes.

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages
git commit -m "test(typed_graphql_shelf): run the transports end to end over shelf_io

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 8: docs: document the shelf adapter and complete M7

**Why.** A stage that adds API adds its guide, and a stage that adds a capability updates `docs/discovery.md`, the READMEs and `llms.txt`, saying only what works (CLAUDE.md, Documentation). M7c left its parts of `CLAUDE.md`, `llms.txt`, `docs/discovery.md` and the root README to this task, so it writes M7c's and M7e's together and closes stage M7.

**Produces:** the shelf guide `doc/shelf.md` (a runnable program on port 0, WebSocket, uploads, GraphiQL and tests sections) and its doc tests (`test/doc/doc_snippets_test.dart`, `doc_links_test.dart`, copied from the server's), the shelf README without the skeleton banner and the "Not usable yet." line, the shelf `CHANGELOG.md` and `example/example.dart`; pointers to the shelf adapter in the server's `doc/http.md`, `doc/uploads.md` (`TempFileUploadStorage` instead of "planned") and `doc/websocket.md`, the server README and CHANGELOG; `CLAUDE.md` (the M7c and M7e status sentences ending "with it stage M7 (transports) is complete", the `websocket/`, GraphiQL and Shelf paragraphs, "Learned in M7", the test locations); `llms.txt`, `docs/discovery.md` ("GraphQL server dart" is now yes) and the root README.

**Files:**

- Modify `CLAUDE.md`
- Modify `README.md`
- Modify `docs/discovery.md`
- Modify `llms.txt`
- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/README.md`
- Modify `packages/typed_graphql_server/doc/http.md`
- Modify `packages/typed_graphql_server/doc/uploads.md`
- Modify `packages/typed_graphql_server/doc/websocket.md`
- Modify `packages/typed_graphql_shelf/CHANGELOG.md`
- Modify `packages/typed_graphql_shelf/README.md`
- Modify `packages/typed_graphql_shelf/doc/shelf.md`
- Create `packages/typed_graphql_shelf/example/example.dart`
- Create `packages/typed_graphql_shelf/test/doc/doc_links_test.dart`
- Create `packages/typed_graphql_shelf/test/doc/doc_snippets_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_shelf/test/doc/doc_links_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/doc_files.dart';
import '../../../typed_graphql/test/doc/markdown_links.dart';

/// Every relative link of the guides and READMEs leads somewhere (R11.1,
/// R11.2).
void main() {
  const links = MarkdownLinks();
  final files = const DocFiles().all();

  test('no guide links to another file, which dartdoc would break', () {
    for (final MapEntry(key: path, value: markdown)
        in const DocFiles().guides().entries) {
      expect(links.relativeIn(markdown), isEmpty, reason: path);
    }
  });

  group('links resolve', () {
    for (final MapEntry(key: path, value: markdown) in files.entries) {
      for (final MarkdownLink(:line, :target) in links.relativeIn(markdown)) {
        test('$path:$line -> $target', () {
          expect(links.problemOf(path, target), isNull);
        });
      }
    }
  });
}
```

Create `packages/typed_graphql_shelf/test/doc/doc_snippets_test.dart`:

```dart
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/doc_files.dart';
import '../../../typed_graphql/test/doc/doc_snippet.dart';
import '../../../typed_graphql/test/doc/snippet_runner.dart';

/// Every program in the guides and READMEs, a fence tagged `dart`, is
/// complete: it compiles, runs, and prints what the text after it says
/// (R11.2).
void main() {
  // The repository README is the server's to test; here only this package's.
  final files = const DocFiles().all()..remove('../../README.md');
  final snippets = [
    for (final MapEntry(key: path, value: markdown) in files.entries)
      ...const DocSnippets().of(path, markdown),
  ];
  final runs = <DocSnippet, Future<SnippetRun>>{};
  // `late`: the runner needs the package configuration, which only
  // `Isolate.packageConfig` (a Future) gives, and `setUpAll` sets it before
  // any test reads it. The folder is null until created, so a failure to
  // create it does not hide its cause in `tearDownAll`.
  late final SnippetRunner runner;
  Directory? directory;

  // Compiled with `--compiler exe` there is no package configuration and
  // every program is skipped, so nothing is set up or removed.
  setUpAll(() async {
    if (!SnippetRunner.isAvailable) return;
    final configuration = await Isolate.packageConfig;
    final created = Directory.systemTemp.createTempSync('typed_graphql_doc_');
    directory = created;
    runner = SnippetRunner(configuration!.toFilePath(), created);
  });
  tearDownAll(() {
    directory?.deleteSync(recursive: true);
  });

  test('every guide holds at least one program', () {
    for (final path in const DocFiles().guides().keys) {
      expect(snippets.where((snippet) => snippet.file == path), isNotEmpty);
    }
  });

  final skip = SnippetRunner.isAvailable
      ? null
      : 'needs the dart tool, not a compiled test';

  test('every program is formatted as dart format prints it', () async {
    expect(await runner.unformattedPlaces(snippets), isEmpty);
  }, skip: skip);
  for (final (index, snippet) in snippets.indexed) {
    Future<SnippetRun> run() =>
        runs.putIfAbsent(snippet, () => runner.run(snippet, 'snippet_$index'));

    test('${snippet.place} runs', () async {
      final result = await run();
      expect(result.exitCode, 0, reason: result.errors);
    }, skip: skip);

    if (snippet.expectedOutput case final expected?) {
      test('${snippet.place} prints what the guide says', () async {
        expect((await run()).output, expected.trimRight());
      }, skip: skip);
    }
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test test/doc/doc_links_test.dart test/doc/doc_snippets_test.dart'
```

Expected: this task changes documentation and adds the shelf doc tests together with the guide they check (they run its program and compare the `It prints:` output), so there is no red step. After Step 4, open the GraphiQL page by hand once: run `dart run example/example.dart` in `packages/typed_graphql_shelf`, open `http://localhost:8080/` in a browser with network access, and check that GraphiQL loads (no Subresource Integrity error in the console) and that `{ hello }` answers. CI runs no browser, so this check is manual (spec section 12).

- [ ] **Step 3: Write the implementation.**

Modify `CLAUDE.md` (exact diff):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 61d0a7e..43dc6d0 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -86,7 +86,15 @@ tests and the HTTP guide. M7b (multipart uploads) delivers `Upload`,
 the Uploads guide. M7d (GraphQL over SSE) delivers `SseOptions`,
 `SingleConnectionOptions`, `HttpOptions.sse`, the distinct connections mode
 and the single connection mode of graphql-sse, the codes `GQL433`-`GQL438`,
-the SSE hostile-input tests and the Server-sent events guide. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+the SSE hostile-input tests and the Server-sent events guide. M7c (graphql-ws)
+delivers `GraphQLWsHandler`, `GraphQLSocket`, `GraphQLWsOptions`,
+`ConnectionHook` with `AcceptConnection` and `RefuseConnection`,
+`RequestInfo.connectionParams`, the code `GQL432`, the WebSocket hostile-input
+tests and the WebSocket guide. M7e (shelf adapter) delivers
+`ServerProfile.graphiql` and the GraphiQL page of `GraphQLHttpHandler`, and in
+`typed_graphql_shelf` `GraphQLShelfHandler`, `TempFileUploadStorage`, the
+end-to-end tests over `shelf_io` and the shelf guide and example; with it stage
+M7 (transports) is complete. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
 file or a URL, the project's documents as one fragment graph, the planner and
 emitters that generate the schema-types library and a library per document
 (operations, variables, data, fragments, sealed polymorphic classes, the
@@ -444,7 +452,7 @@ only through its barrel. One folder per concern, with no import order
 (`builder/` and `execution/` import each other): `builder/` (M5a),
 `coercion/`, `plan/` and `execution/` (M5b), `introspection/` and
 `subscription/` (M5c), `lookahead/`, `authorization/` and `cancellation/`
-(M5d), `dataloader/` (M6a), `server/` (M6b), `persisted/` (M6c), `http/` (M7a), `upload/` (M7b) and `sse/` (M7d). The
+(M5d), `dataloader/` (M6a), `server/` (M6b), `persisted/` (M6c), `http/` (M7a), `upload/` (M7b), `sse/` (M7d) and `websocket/` (M7c). The
 package is
 transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
 or web framework, only `dart:async`, `dart:collection`, `dart:convert`,
@@ -596,6 +604,52 @@ frame controller and its `StreamOperation`s: an operation is admitted at its
 `POST` but its source is listened to only once the stream is, so held work
 runs nothing; the host closing the body cancels all of them. State is in the
 handler, so a deployment needs sticky sessions.
+`websocket/` (M7c): `GraphQLWsHandler.serve(GraphQLSocket, RequestInfo)` is
+the whole transport and imports no WebSocket library; an adapter implements
+`GraphQLSocket` (text frames in `incoming`, binary frames decoded as UTF-8,
+`incoming` done on any close, `send`, `close`). `serve` never throws: it
+refuses over `maxConnections` (`1013`), a subprotocol other than
+`graphql-transport-ws` (`4406`) and a foreign Origin (`4403`; the adapter
+answers `403` earlier through `allowsUpgrade`, `OriginPolicy`), then runs one
+`SocketSession` that owns the `ConnectionHandshake` (the `connection_init`
+timer, the parameters, `ConnectionHook` as `onConnect`), the frame reader
+(`ClientMessageReader`, `maxMessageLength` before parsing, `maxJsonDepth`) and
+`SocketOperations`. Each `subscribe` is a `SocketOperation` that runs a `POST`
+`ServerRequest` with the upgrade's headers, so the context factory, CSRF and
+the limits see an ordinary request; it writes `next`, `error` and `complete`
+through `ServerMessages` and is cancelled by its `CancelSignal` on `complete`
+or on close. `WsClose` holds the fixed close codes and reasons (never the
+client's text); `4409` for a reused id comes from `DuplicateSubscriber`. A
+session that ended is closed for good, so a hook still pending cannot
+acknowledge it. Ping frames are the adapter's job.
+`http/` (M7e): `GraphiQLRequest` decides whether a request opens the endpoint
+in a browser (a `GET` without `query` whose `Accept` ranks `text/html` above
+both JSON types); only `ServerProfile.graphiql` (on in `development`) lets
+`GraphQLHttpHandler` answer it with `GraphiQLPage`, a fixed page that loads
+React 18.3.1 and GraphiQL 3.9.0 from jsDelivr with Subresource Integrity and
+sends its queries to the request's own path (escaped as a JSON string).
+
+**Shelf** (`packages/typed_graphql_shelf/lib/src/`; M7e). Depends on
+`typed_graphql_server`, `shelf`, `shelf_web_socket` and `web_socket_channel`;
+it is the only transport package that imports `dart:io`, and only for
+`TempFileUploadStorage`. `GraphQLShelfHandler<C>` is a shelf `Handler`
+(`call`) over a `GraphQLHttpHandler`: `RequestConversion` makes the
+`HttpRequestData` (lower-case headers joined with `, `, `request.read()` as the
+body, `source: request`, no `CancelSignal`) and `ResponseConversion` the
+`Response` (a `StreamedBody` with `shelf.io.buffer_output` off, so an event
+reaches the client when written). `shelf_io` reports no client that went away
+outside a streamed body, so no `cancelSignal` is given; for an event stream it
+cancels the body's subscription, which stops the work. With `webSocket` set,
+`WebSocketUpgrade` takes a `GET` with `upgrade: websocket`: the Origin check
+first (`allowsUpgrade`, else a `403` JSON refusal with `GQL403`, before
+`shelf_web_socket` is reached), then `webSocketHandler` with the one
+subprotocol and `webSocketPingInterval`, whose connection becomes a
+`WebSocketChannelSocket` for `GraphQLWsHandler.serve`. `TempFileUploadStorage`
+writes each upload to an exclusive file with a random name (never the
+client's), deletes a partial file when the content stream fails and the file
+on `release`; its `FileUpload` reads it back. The tests run the transports end
+to end over `shelf_io` on a loopback port (`test/end_to_end_*_test.dart`, with
+`LoopbackServer`); the guide's program is run by `test/doc/`.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
@@ -793,6 +847,18 @@ Learned in M5:
   may become one argument per line; run the formatter on the fence before
   trusting the guide test.
 
+Learned in M7:
+- A transport that commits to a response before a check (an event stream
+  accepted, then a CSRF error written into it) answers the wrong status; run
+  every refusal that has its own status before the body starts.
+- A connection that ends while an async hook is pending must stay closed: the
+  hook's late answer may not acknowledge it.
+- `shelf_io` gives a plain request no client-gone signal; only the
+  subscription to a streamed body is cancelled. Do not promise a
+  `CancelSignal` from it.
+- An end-to-end subscription test cannot emit once: the source is listened to
+  after the response starts, so emit until the client hears an event.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
@@ -884,6 +950,13 @@ README that leaves the package folder is an absolute URL.
   `RulePort` for the validation rule suites, `ExecutionPort` for the
   execution, variables and input-coercion suites).
 - Hostile-document tests: `packages/typed_graphql/test/validation/hostile_*_test.dart`.
+- Hostile transport tests in `packages/typed_graphql_server/test/`:
+  `http/hostile_http_test.dart`, `http/hostile_batch_test.dart`,
+  `upload/hostile_upload_test.dart`, `sse/hostile_sse_test.dart` and
+  `websocket/hostile_websocket_test.dart`.
+- Shelf tests: `packages/typed_graphql_shelf/test/`, with the end-to-end tests
+  `end_to_end_http_test.dart` and `end_to_end_streams_test.dart` and the
+  fixtures in `test/support/`.
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
   round trip, hostile SDL, introspection round trip, hostile
   introspection, coordinates, valid operations, hostile operations and
```

Modify `README.md` (exact diff):

````diff
diff --git a/README.md b/README.md
index 26cac76..2ca3980 100644
--- a/README.md
+++ b/README.md
@@ -31,7 +31,10 @@ typed schema builder, the execution of a validated operation, introspection,
 subscriptions, look-ahead at the requested fields, field authorization,
 cancellation, DataLoader and a transport-agnostic request pipeline
 (`GraphQLServer`: limits, the cost limit, CSRF prevention, extensions,
-automatic persisted queries and trusted documents).
+automatic persisted queries and trusted documents); and the transports:
+GraphQL over HTTP (JSON, batching, multipart file uploads, server-sent
+events), graphql-ws over WebSocket and a GraphiQL page in development, served
+from a shelf application by `typed_graphql_shelf`.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
@@ -114,8 +117,8 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader, the request pipeline and persisted documents (M6, complete) |
-| [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader, the request pipeline and persisted documents (M6, complete), the HTTP, multipart upload, server-sent event and graphql-ws handlers and the GraphiQL page (M7, complete) |
+| [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | `GraphQLShelfHandler`: HTTP, uploads, server-sent events, graphql-ws and the GraphiQL page of the development profile (M7, complete) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
````

Modify `docs/discovery.md` (exact diff):

```diff
diff --git a/docs/discovery.md b/docs/discovery.md
index 3b0307e..a6b7598 100644
--- a/docs/discovery.md
+++ b/docs/discovery.md
@@ -49,7 +49,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | GraphQL CSRF prevention dart | M6 | yes |
 | GraphQL persisted queries dart | M6 | yes |
 | GraphQL trusted documents dart | M6 | yes |
-| GraphQL server dart | M7 | no |
+| GraphQL server dart | M7 | yes |
 | generate a typed GraphQL client dart | M10 | yes |
 
 ## Metadata
```

Modify `llms.txt` (exact diff):

```diff
diff --git a/llms.txt b/llms.txt
index 5dd08ff..f50b60f 100644
--- a/llms.txt
+++ b/llms.txt
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking) with automatic persisted queries or trusted documents; the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking) with automatic persisted queries or trusted documents; it serves GraphQL over HTTP (JSON, batching, multipart file uploads, server-sent events), over graphql-ws on a WebSocket and, in development, with a GraphiQL page, through GraphQLHttpHandler and GraphQLWsHandler, which typed_graphql_shelf mounts in a shelf application. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,8 +8,8 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation, DataLoader, Server and Persisted Documents in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation, DataLoader (BatchLoader, GroupedLoader) and the request pipeline (GraphQLServer with limits, the cost limit, CSRF prevention, extensions, automatic persisted queries and trusted documents) work; transport handlers (M7) come later
-- [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation, DataLoader, Server and Persisted Documents in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation, DataLoader (BatchLoader, GroupedLoader) and the request pipeline (GraphQLServer with limits, the cost limit, CSRF prevention, extensions, automatic persisted queries and trusted documents) work; the HTTP handler (JSON and batching, multipart uploads, server-sent events with graphql-sse), the graphql-ws handler and the GraphiQL page work (guides: HTTP, Uploads, Server-sent events, WebSocket), and a host adapts them to its web framework
+- [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): under construction; GraphQLShelfHandler, a shelf Handler that serves a GraphQLServer over HTTP (queries, mutations, batching, multipart uploads, server-sent events) and, with webSocket set, over graphql-ws, with TempFileUploadStorage for uploads and a GraphiQL page under the development profile (guide in its doc folder, runnable example in its example folder)
 
 ## Guides
 
```

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index a06ea5d..07499fa 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -263,3 +263,4 @@
   answers a `GET` without a `query` whose `Accept` ranks `text/html` above
   the JSON types with a page that loads GraphiQL 3.9.0 from jsDelivr, pinned
   by Subresource Integrity, and sends its queries to the request's path.
+- The server README and guides point to `typed_graphql_shelf`, the shelf adapter that completes stage M7: the Uploads guide names `TempFileUploadStorage`, the WebSocket and HTTP guides name `GraphQLShelfHandler`.
```

Modify `packages/typed_graphql_server/README.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/README.md b/packages/typed_graphql_server/README.md
index 15e8413..c2bd976 100644
--- a/packages/typed_graphql_server/README.md
+++ b/packages/typed_graphql_server/README.md
@@ -27,7 +27,9 @@
 > into the `Upload` scalar. The same handler streams results as server-sent
 > events (M7d, both modes of graphql-sse), and `GraphQLWsHandler` (M7c)
 > serves queries, mutations and subscriptions over a WebSocket. The shelf
-> adapter comes in the rest of M7. See the
+> adapter, `typed_graphql_shelf` (M7e), serves all of them from a shelf
+> application, with a GraphiQL page in development; with it stage M7
+> (transports) is complete. See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
 ## Contents
@@ -60,7 +62,9 @@ dependencies:
   [Execution](doc/execution.md#executing-a-request)).
 - **You do not need it when** you only call a GraphQL server: that is the
   client package, not usable yet. Today it has the HTTP and graphql-ws
-  handlers but no framework adapter: a host converts its request into an
+  handlers; for shelf the adapter is
+  [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_shelf),
+  and for any other framework a host converts its request into an
   `HttpRequestData` and calls `GraphQLHttpHandler.handle`
   ([HTTP](doc/http.md)), or wraps its WebSocket in a `GraphQLSocket` and
   calls `GraphQLWsHandler.serve` ([WebSocket](doc/websocket.md)).
@@ -161,7 +165,11 @@ executed
   profiles, limits and the cost limit, CSRF prevention, the document cache,
   extensions, errors and masking.
 - [HTTP](doc/http.md): `GraphQLHttpHandler`, media types and status codes,
-  limits, batching, writing a host adapter, security notes.
+  limits, batching, writing a host adapter, security notes, the GraphiQL page.
+- [Uploads](doc/uploads.md): multipart file uploads into the `Upload` scalar,
+  storage, limits.
+- [Server-sent events](doc/sse.md): graphql-sse, both modes, keep-alive,
+  limits.
 - [Persisted Documents](doc/persisted_documents.md): automatic persisted
   queries and their store, trusted documents from the codegen manifest.
 - [Schema Builder](doc/schema_builder.md): refs, objects, fields, arguments,
```

Modify `packages/typed_graphql_server/doc/http.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/doc/http.md b/packages/typed_graphql_server/doc/http.md
index 75cacae..f0166d9 100644
--- a/packages/typed_graphql_server/doc/http.md
+++ b/packages/typed_graphql_server/doc/http.md
@@ -292,7 +292,8 @@ write and flush chunk by chunk, and cancel when the client goes away.
 ## Writing a host adapter
 
 An adapter for a framework does three things: convert the request, call the
-handler, write the response.
+handler, write the response. For shelf it is written:
+`typed_graphql_shelf` ships `GraphQLShelfHandler`.
 
 ```text
 Future<void> serve(FrameworkRequest request, FrameworkResponse out) async {
````

Modify `packages/typed_graphql_server/doc/uploads.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/doc/uploads.md b/packages/typed_graphql_server/doc/uploads.md
index 7b9f66a..9251caa 100644
--- a/packages/typed_graphql_server/doc/uploads.md
+++ b/packages/typed_graphql_server/doc/uploads.md
@@ -176,8 +176,8 @@ too, so the program above sends a header.
 
 `MemoryUploadStorage`, the default, keeps each file in memory, which is right
 for small files and tests. Anything larger belongs on disk or in an object
-store: `typed_graphql_shelf` is planned to ship a temporary-file storage; until
-then write your own.
+store: `TempFileUploadStorage` of `typed_graphql_shelf` writes each file to a
+temporary file and deletes it on release; for an object store write your own.
 
 An `UploadStorage` has two methods. `store` receives the content of one file
 as a stream. When that stream fails, which is how a file over `maxFileBytes`
```

Modify `packages/typed_graphql_server/doc/websocket.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/doc/websocket.md b/packages/typed_graphql_server/doc/websocket.md
index cfd36ef..f82410c 100644
--- a/packages/typed_graphql_server/doc/websocket.md
+++ b/packages/typed_graphql_server/doc/websocket.md
@@ -197,3 +197,6 @@ abstract interface class GraphQLSocket {
 - End `incoming` when the connection closes, from either side.
 - Call `allowsUpgrade` before upgrading and answer `403`, then call `serve`
   with a `RequestInfo` of the upgrade request.
+
+For shelf there is nothing to write: `GraphQLShelfHandler` of
+`typed_graphql_shelf` does all of this when its `webSocket` option is set.
```

Modify `packages/typed_graphql_shelf/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_shelf/CHANGELOG.md b/packages/typed_graphql_shelf/CHANGELOG.md
index 1019926..b86b8e1 100644
--- a/packages/typed_graphql_shelf/CHANGELOG.md
+++ b/packages/typed_graphql_shelf/CHANGELOG.md
@@ -5,7 +5,21 @@
 - Package skeleton.
 - `repository` points at the package folder; pub.dev is expected to rewrite
   relative README links from it (to confirm at M16).
-- The README says the package is not usable yet.
 - `GraphQLShelfHandler`: a shelf `Handler` that serves GraphQL over HTTP
   through `GraphQLHttpHandler` (`HttpOptions` as `http`), with streamed bodies
   written unbuffered. The shelf guide is `doc/shelf.md`.
+- `GraphQLShelfHandler.webSocket` and `webSocketPingInterval`: with `webSocket`
+  set, a `GET` that asks to upgrade to a WebSocket is served as graphql-ws by a
+  `GraphQLWsHandler`, after the Origin check (`403`, `GQL403`, before
+  `shelf_web_socket` is reached), with ping frames every
+  `webSocketPingInterval` (12 seconds). Without `webSocket` such a request is
+  an ordinary `GET`.
+- `TempFileUploadStorage`: an `UploadStorage` that writes each upload to a
+  file with a random name in a temporary directory, deletes a partial file when
+  the content stream fails, and deletes the file on release.
+- The GraphiQL page of `ServerProfile.development` is served by the handler
+  (the page is the HTTP handler's).
+- The README says what works, the guide is complete (a runnable program,
+  WebSocket, uploads, GraphiQL), `example/example.dart` serves a small schema,
+  and the end-to-end tests run the transports over `shelf_io` on a loopback
+  port.
```

Modify `packages/typed_graphql_shelf/README.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_shelf/README.md b/packages/typed_graphql_shelf/README.md
index 8eefd4d..e510f32 100644
--- a/packages/typed_graphql_shelf/README.md
+++ b/packages/typed_graphql_shelf/README.md
@@ -6,13 +6,69 @@
 
 **The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket handlers for shelf, with an optional GraphiQL page in development.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: skeleton.** The package exists so the workspace, CI and the
-> code rules cover it from the start. Its code arrives in stage M7 of the
-> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.
+> **Status: under construction.** Stage M7 is complete: `GraphQLShelfHandler`
+> is a shelf `Handler` that serves a `GraphQLServer` over HTTP (`GET` and
+> `POST`, JSON and multipart uploads, batching, server-sent events) and, with
+> `webSocket` set, over graphql-ws; `TempFileUploadStorage` keeps uploaded
+> files in temporary files; under `ServerProfile.development` a browser that
+> opens the endpoint gets the GraphiQL page. See the
+> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
-**Not usable yet.** This package exports nothing; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
+## Contents
 
-Planned (M7): a `shelf` `Handler` for GraphQL over HTTP, graphql-ws over WebSocket and graphql-sse, and a GraphiQL page you switch on in development.
+- [Install](#install)
+- [Should I use this?](#should-i-use-this)
+- [A quick tour](#a-quick-tour)
+- [Guides](#guides)
+- [License](#license)
+
+## Install
+
+Nothing is on pub.dev yet. To try it from the repository:
+
+```yaml
+dependencies:
+  typed_graphql_server:
+    git:
+      url: https://github.com/4akloon/graphql_dart
+      path: packages/typed_graphql_server
+  typed_graphql_shelf:
+    git:
+      url: https://github.com/4akloon/graphql_dart
+      path: packages/typed_graphql_shelf
+```
+
+## Should I use this?
+
+- **Use it when** you serve GraphQL with `typed_graphql_server` from a shelf
+  application and want HTTP, WebSocket and server-sent events from one
+  handler.
+- **You do not need it when** you use another web framework: the HTTP and
+  graphql-ws handlers of `typed_graphql_server` take a small adapter, which
+  this package is for shelf.
+- **Which package**: this one next to
+  [typed_graphql_server](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_server),
+  which builds the schema and runs the requests.
+
+## A quick tour
+
+Build a `GraphQLServer`, wrap it in a `GraphQLShelfHandler` and give the
+handler to `shelf_io.serve`; routing, CORS and logging stay with shelf. The
+runnable program is [example/example.dart](example/example.dart); the guide
+has one that posts a query and prints the answer.
+
+```text
+final handler = GraphQLShelfHandler<Object?>(
+  server,
+  webSocket: const GraphQLWsOptions(),
+);
+await shelf_io.serve(handler.call, InternetAddress.loopbackIPv4, 8080);
+```
+
+## Guides
+
+- [shelf adapter](doc/shelf.md): the handler, a first program, WebSocket,
+  uploads, GraphiQL and what the adapter decides.
 
 ## License
 
````

Modify `packages/typed_graphql_shelf/doc/shelf.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_shelf/doc/shelf.md b/packages/typed_graphql_shelf/doc/shelf.md
index 537ae18..c53450a 100644
--- a/packages/typed_graphql_shelf/doc/shelf.md
+++ b/packages/typed_graphql_shelf/doc/shelf.md
@@ -3,7 +3,8 @@
 `typed_graphql_shelf` serves a `GraphQLServer` from a shelf application. The
 adapter is thin: `GraphQLShelfHandler` turns each shelf `Request` into the
 `HttpRequestData` of `typed_graphql_server`, runs `GraphQLHttpHandler` and
-writes its `HttpResponseData` as a shelf `Response`. The limits, the media
+writes its `HttpResponseData` as a shelf `Response`; with `webSocket` set it
+also turns a WebSocket upgrade into a graphql-ws session. The limits, the media
 types, the status codes and the GraphiQL page are the HTTP guide's of
 `typed_graphql_server`.
 
@@ -11,7 +12,12 @@ types, the status codes and the GraphiQL page are the HTTP guide's of
 
 ```text
 final class GraphQLShelfHandler<C> {
-  GraphQLShelfHandler(GraphQLServer<C> server, {HttpOptions http});
+  GraphQLShelfHandler(
+    GraphQLServer<C> server, {
+    HttpOptions http,
+    GraphQLWsOptions? webSocket,
+    Duration webSocketPingInterval,
+  });
   FutureOr<Response> call(Request request);
 }
 ```
@@ -21,6 +27,66 @@ mount it in a router at the path of the endpoint. Routing, CORS and logging
 stay with shelf. The page of GraphiQL sends its queries to the path the
 browser opened it at, so any mount point works.
 
+## A first program
+
+This program serves one query on a free port, posts a request to it with
+`HttpClient`, prints the status and the body, and stops. The development
+profile would switch the GraphiQL page on; the default, production, does not.
+
+```dart
+import 'dart:convert';
+import 'dart:io';
+
+import 'package:shelf/shelf_io.dart' as shelf_io;
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('hello', b.string).pure((_) => 'Hello from shelf!'),
+    ],
+  );
+  final server = GraphQLServer<Object?>(
+    schema: b.build(query: query),
+    contextFactory: (request) => null,
+  );
+  final handler = GraphQLShelfHandler<Object?>(server);
+
+  // Port 0 asks the system for a free port.
+  final httpServer = await shelf_io.serve(
+    handler.call,
+    InternetAddress.loopbackIPv4,
+    0,
+  );
+
+  final client = HttpClient();
+  final request = await client.postUrl(
+    Uri.parse('http://127.0.0.1:${httpServer.port}/graphql'),
+  );
+  request.headers.contentType = ContentType.json;
+  request.write(jsonEncode({'query': '{ hello }'}));
+  final response = await request.close();
+  stdout.writeln(response.statusCode);
+  stdout.writeln(await utf8.decodeStream(response));
+
+  client.close();
+  await httpServer.close();
+}
+```
+
+It prints:
+
+```text
+200
+{"data":{"hello":"Hello from shelf!"}}
+```
+
+The same schema with subscriptions, a WebSocket and the GraphiQL page is
+`example/example.dart` in the package.
+
 ## What the adapter decides
 
 - Header names are lower-case and repeated headers are joined with `, `, as
@@ -32,3 +98,66 @@ browser opened it at, so any mount point works.
   the subscription when the client goes away, which ends the work behind it.
 - No `CancelSignal` is given to the handler, because shelf does not report a
   client that went away outside a streamed body.
+
+## WebSocket
+
+With `webSocket` set, a `GET` that asks to upgrade to a WebSocket is served
+as graphql-ws (`graphql-transport-ws`) by a `GraphQLWsHandler` built from the
+same server; without it, such a request is an ordinary `GET`.
+
+```text
+GraphQLShelfHandler<Object?>(
+  server,
+  webSocket: const GraphQLWsOptions(allowedOrigins: ['https://app.example']),
+  webSocketPingInterval: const Duration(seconds: 12),
+)
+```
+
+- The `Origin` is checked before the upgrade, because a browser sends cookies
+  with an upgrade and no preflight. A page on another site is answered `403`
+  with `GQL403`, as JSON, and `shelf_web_socket` is never reached. An upgrade
+  without an `Origin`, from the same host or from `allowedOrigins` passes.
+- The subprotocol must be `graphql-transport-ws`; a connection that offers
+  another is closed with `4406` by the handler.
+- `webSocketPingInterval` is the interval of the WebSocket ping frames that
+  keep the connection alive through proxies; the handler itself sends none.
+- Limits, the `onConnect` hook and the close codes are the WebSocket guide's
+  of `typed_graphql_server`.
+
+## Uploads
+
+`TempFileUploadStorage` is an `UploadStorage` that writes each upload to a
+file and deletes it when the response is built, so a large file never waits in
+memory. The size is bounded by the `UploadLimits` of the `Uploads` value.
+
+```text
+final uploads = Uploads(storage: TempFileUploadStorage());
+final upload = b.scalar<Upload>(Uploads.scalarName, uploads.codec);
+final handler = GraphQLShelfHandler<Object?>(
+  server,
+  http: HttpOptions(uploads: uploads),
+);
+```
+
+The files get random names in `Directory.systemTemp`, or in the directory
+given as `TempFileUploadStorage(directory: ...)`, which must exist. What the
+client sent as a file name is only data: it is never used as a path. A
+stream that fails, for example a file over its limit, leaves no partial file.
+The Uploads guide of `typed_graphql_server` has the rest.
+
+## GraphiQL
+
+The page is the HTTP handler's, so it is served exactly when
+`ServerProfile.graphiql` is on, which is the default of
+`ServerProfile.development` and never of `production`. A browser that opens
+the endpoint with an `Accept` that prefers `text/html` gets it. The page loads
+React and GraphiQL from jsDelivr, pinned by version and Subresource
+Integrity, so the browser needs network access to the CDN; the server does
+not. Subscriptions are not run from the page.
+
+## Tests
+
+The handler is an ordinary function of a `Request`, so a test can call it
+without a socket: `handler(Request('POST', uri, body: ..., headers: ...))`.
+The package's own end-to-end tests serve it with `shelf_io` on a loopback
+port and talk to it with `HttpClient` and `WebSocketChannel`.
````

Create `packages/typed_graphql_shelf/example/example.dart`:

```dart
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

/// Serves a small schema at `http://localhost:8080/` (or the port in `PORT`):
/// queries and mutations over HTTP, a `ticks` subscription over graphql-ws or
/// server-sent events, and the GraphiQL page for a browser that opens the
/// address.
Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', b.string).pure((_) => 'Hello from shelf!'),
    ],
  );
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      t
          .field('ticks', b.int)
          .subscribeWith<int>(
            (parent, args, context, info) =>
                Stream.periodic(const Duration(seconds: 1), (count) => count),
            (event, args, context, info) => event,
          ),
    ],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query, subscription: subscription),
    contextFactory: (request) => null,
    // The development profile also switches the GraphiQL page on.
    profile: ServerProfile.development,
  );
  final handler = GraphQLShelfHandler<Object?>(
    server,
    webSocket: const GraphQLWsOptions(),
  );

  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final httpServer = await shelf_io.serve(
    handler.call,
    InternetAddress.loopbackIPv4,
    port,
  );
  stdout.writeln('GraphQL on http://localhost:${httpServer.port}/');
}
```

- [ ] **Step 4: Format, then run the green check.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart format --output=none --set-exit-if-changed packages test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart analyze --fatal-infos'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd . && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_server && timeout 900 dart test'
flock /tmp/claude-1000/dart-heavy.lock bash -c 'ulimit -v 8000000; export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"; cd packages/typed_graphql_shelf && timeout 900 dart test'
```

Expected: format changes 0 files on the second run, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A CLAUDE.md README.md docs llms.txt packages
git commit -m "docs: document the shelf adapter and complete M7

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

## Verification

After the last task, from the repository root, run the wrapped commands: `dart format --output=none --set-exit-if-changed packages test` (0 changed), `dart analyze --fatal-infos` (`No issues found!`), `dart test` at the root, `dart test` in `packages/typed_graphql`, `packages/typed_graphql_server` and `packages/typed_graphql_shelf`, and `dart doc` in `packages/typed_graphql_server` and `packages/typed_graphql_shelf` (0 warnings each).
