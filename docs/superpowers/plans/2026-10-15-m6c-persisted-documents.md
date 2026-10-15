# M6c Persisted Documents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the last part of stage M6 of `typed_graphql_server` (R5.4): automatic persisted queries (`PersistedQueryStore`, `MemoryPersistedQueryStore`, `GraphQLServer(persistedQueries:)`) and trusted documents (`TrustedDocuments`, read from the manifest M10 writes, `GraphQLServer(trustedDocuments:)`), the codes `GQL410`-`GQL415`, their hostile-input tests, the Persisted Documents guide and the stage's last documents. With it stage M6 is complete.

**Architecture:** Everything lives in `lib/src/persisted/`. The public pieces are the store interface, the in-memory LRU store and `TrustedDocuments`; the rest is internal. Each mode is an internal `ServerExtension` with only `onDocument`, which `PipelineAssembly` places once, inside the user's extensions and after CSRF: `TrustedDocumentsCheck`, `AutomaticPersistedQueries` or `PersistedQueriesUnsupported`. They read `extensions.persistedQuery` through `PersistedQueryReader` into the sealed `PersistedQueryReference`, refuse through `PipelineErrors.coded`, hash with `DocumentHash`, check a stored text with `DocumentLength`, and hand a resolved text on with `DocumentRequest.withText`, so the document cache, the validator and the cost limit apply unchanged. `TrustedManifestReader` turns the manifest into ids and texts and refuses an id that is not its body's hash.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5 or later), `package:test`, `package:meta`, `package:crypto` (already a dependency since M6b Task 2).

**Spec:** `docs/superpowers/specs/2026-10-15-m6-server-pipeline-design.md` (sections 11, 13, 14 and 15), `docs/requirements.md` (R5.4, R5.14).

**Base:** the tree after the M6b plan, Task 13 included. Run M6b Tasks 11-13 first: Task 3 here changes `pipeline_assembly.dart` and `graphql_server.dart`, which M6b Task 12 changes, and Task 6 here edits the documents M6b Task 13 writes.

**Provenance:** the controller wrote and verified every task in a scratch copy of `m6-final` (one commit per task: `f3a6bdb`, `79a4369`, `7ccb169`, `369f259`, `7dcff12`, `1909931`, on top of the M6b Tasks 11-13 commits). Each task's diffs are that commit's diffs, so they apply in order to the tree the earlier tasks leave. After Task 6 the scratch copy passed: format (0 changed), `dart analyze --fatal-infos` (no issues), the root suite (353 tests), the server suite (1155), the core suite (1514), and `dart doc` for the server (0 warnings, 0 errors).

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and the server suite green (Task 1 also the core suite).
- **Memory and time limits.** Run every `dart` command as `flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 <cmd> )'`: one heavy Dart process at a time, no Chrome runs (CI covers dart2js and dart2wasm), and filter the output with `| tail`.
- Format with the newer SDK (3.13.1's formatter crashes): `/home/genius/fvm/versions/3.47.6/bin/dart format packages test`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the subject given in the task and a trailer naming the real model of the implementer (for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Run every command from the repository root unless a step says otherwise.
- Changes to existing files are unified diffs against the tree the earlier tasks leave. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- Tests never read git-ignored or untracked files.
- A hash always names its own text. No step may store, serve or trust a text whose SHA-256 is not the hash it is filed under (spec section 14).

## Shared interfaces (from M6b, used unchanged)

- `ServerExtension<C>.onDocument(DocumentRequest request, DocumentHandler next)` returns `Future<DocumentResult>`.
- `DocumentRequest(request, {text})` and `withText(text)`.
- `DocumentAccepted(document, source, hash)` and `DocumentRejected(errors)`.
- `PipelineErrors.coded(DiagnosticCode code, String message)` builds a `GraphQLError` with `extensions.code`.
- `DocumentHash().of(text)` is the lower-case hex SHA-256 of the UTF-8.
- `DocumentLength(maximum, errors).violation(text)` returns a `GQL401` error, or null.
- `PipelineAssembly.handler()` builds the `ExtensionChain` and is where the persisted step is placed.
- The test fixture `ServerFixture` is in `test/server/support/server_fixture.dart`.

## File map

| File | Change | Task |
|---|---|---|
| `CLAUDE.md` | Modify | 6 |
| `README.md` | Modify | 6 |
| `docs/discovery.md` | Modify | 6 |
| `docs/superpowers/HANDOFF.md` | Modify | 6 |
| `llms.txt` | Modify | 6 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 2, 3, 4 |
| `packages/typed_graphql_server/README.md` | Modify | 6 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 2 |
| `packages/typed_graphql_server/doc/persisted_documents.md` | Create/Modify | 2, 6 |
| `packages/typed_graphql_server/doc/server.md` | Modify | 6 |
| `packages/typed_graphql_server/lib/src/persisted/automatic_persisted_queries.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/persisted/memory_persisted_query_store.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/persisted/persisted_queries_unsupported.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/persisted/persisted_query_reader.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/persisted/persisted_query_reference.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/persisted/persisted_query_store.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/persisted/trusted_documents.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/persisted/trusted_documents_check.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/persisted/trusted_manifest_reader.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/server/graphql_server.dart` | Modify | 3, 4 |
| `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart` | Modify | 3, 4 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 2, 4 |
| `packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart` | Create/Modify | 3, 5 |
| `packages/typed_graphql_server/test/persisted/hostile_apq_test.dart` | Create | 5 |
| `packages/typed_graphql_server/test/persisted/hostile_trusted_documents_test.dart` | Create | 5 |
| `packages/typed_graphql_server/test/persisted/memory_persisted_query_store_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/persisted/support/failing_store.dart` | Create | 5 |
| `packages/typed_graphql_server/test/persisted/trusted_documents_test.dart` | Create | 4 |
| `packages/typed_graphql_server/test/server/support/server_fixture.dart` | Modify | 3, 4 |

### Task 1: feat(typed_graphql): add the persisted document diagnostic codes

**Why.** Adds `GQL410`-`GQL415` (`persistedQueryNotFound`, `persistedQueryHashMismatch`, `persistedQueryNotSupported`, `invalidPersistedQuery`, `untrustedDocument`, `unknownTrustedDocument`) to the core catalog in id order with a doc comment each (spec section 13). Tasks 3 and 4 report them.

**Files** (verified commit `f3a6bdb` of the controller's scratch copy):

- Modify `packages/typed_graphql/CHANGELOG.md`
- Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart test" )' 2>&1 | tail -30
```

Expected: nothing fails: the commit adds catalog entries only; the core suite checks that ids are unique, ordered and documented.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql/CHANGELOG.md b/packages/typed_graphql/CHANGELOG.md
index c2b503b..581ea35 100644
--- a/packages/typed_graphql/CHANGELOG.md
+++ b/packages/typed_graphql/CHANGELOG.md
@@ -294,3 +294,7 @@
   argument not given: the argument's default, `assumedSize`, then
   `defaultListSize`. A negative value counted 0 and a variable without a
   value skipped the argument's default and `assumedSize`.
+- `DiagnosticCode`: `GQL410`-`GQL415` (`persistedQueryNotFound`,
+  `persistedQueryHashMismatch`, `persistedQueryNotSupported`,
+  `invalidPersistedQuery`, `untrustedDocument`, `unknownTrustedDocument`),
+  reported by the server for persisted queries and trusted documents.
```

Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
index 1a300de..0ae7d7b 100644
--- a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
@@ -680,6 +680,43 @@ enum DiagnosticCode(
   /// `GraphQLServer.handle`.
   csrfRequestBlocked('GQL403'),
 
+  /// `GQL410`: reported when a request names a persisted query by its hash
+  /// alone and the server's store does not hold it; the message is
+  /// "PersistedQueryNotFound", which tells a client to send the text with
+  /// the hash. It is a `GraphQLError`'s `extensions.code` in a response of
+  /// `GraphQLServer.handle`.
+  persistedQueryNotFound('GQL410'),
+
+  /// `GQL411`: reported when a request sends a document text with a
+  /// persisted query hash that is not the SHA-256 of that text; nothing is
+  /// stored. It is a `GraphQLError`'s `extensions.code` in a response of
+  /// `GraphQLServer.handle`.
+  persistedQueryHashMismatch('GQL411'),
+
+  /// `GQL412`: reported when a request names a persisted query by its hash
+  /// alone and the server keeps neither persisted queries nor trusted
+  /// documents; the message is "PersistedQueryNotSupported", which tells a
+  /// client to stop sending hashes. It is a `GraphQLError`'s
+  /// `extensions.code` in a response of `GraphQLServer.handle`.
+  persistedQueryNotSupported('GQL412'),
+
+  /// `GQL413`: reported when `extensions.persistedQuery` of a request is not
+  /// an object with `version` 1 and a `sha256Hash` of 64 lower-case
+  /// hexadecimal digits. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `GraphQLServer.handle`.
+  invalidPersistedQuery('GQL413'),
+
+  /// `GQL414`: reported when a server that accepts only trusted documents
+  /// receives a document text that is not one of them. It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `GraphQLServer.handle`.
+  untrustedDocument('GQL414'),
+
+  /// `GQL415`: reported when a request names a trusted document by a hash
+  /// that names none. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `GraphQLServer.handle`.
+  unknownTrustedDocument('GQL415'),
+
   /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
   /// the YAML parser's.
   configSyntax('GQL500'),
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`/home/genius/fvm/versions/3.47.6/bin/dart format packages test`, wrapped as above), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart test" )'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages docs CLAUDE.md README.md llms.txt
git commit -m "feat(typed_graphql): add the persisted document diagnostic codes

<your model trailer>"
```

### Task 2: feat(typed_graphql_server): add PersistedQueryStore and MemoryPersistedQueryStore

**Why.** The store of automatic persisted queries (spec section 11): the `PersistedQueryStore` interface (both methods may return a `Future`, so a shared store fits) and `MemoryPersistedQueryStore`, a bounded LRU (`capacity` 1000, below 1 an `ArgumentError`). It opens the `persisted` dartdoc category with a first guide section; Task 6 completes the guide.

**Files** (verified commit `79a4369` of the controller's scratch copy):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/dartdoc_options.yaml`
- Create `packages/typed_graphql_server/doc/persisted_documents.md`
- Create `packages/typed_graphql_server/lib/src/persisted/memory_persisted_query_store.dart`
- Create `packages/typed_graphql_server/lib/src/persisted/persisted_query_store.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Create `packages/typed_graphql_server/test/persisted/memory_persisted_query_store_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/persisted/memory_persisted_query_store_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  test('reads what it wrote', () {
    final store = MemoryPersistedQueryStore()..write('a', '{ a }');
    expect(store.read('a'), '{ a }');
  });

  test('reads null for a hash it does not hold', () {
    expect(MemoryPersistedQueryStore().read('a'), isNull);
  });

  test('evicts the least recently written past the capacity', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('b', '{ b }')
      ..write('c', '{ c }');
    expect(store.read('a'), isNull);
  });

  test('keeps the capacity', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('b', '{ b }')
      ..write('c', '{ c }');
    expect(store.length, 2);
  });

  test('a read makes a text the most recently used', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('b', '{ b }');
    store
      ..read('a')
      ..write('c', '{ c }');
    expect(store.read('a'), '{ a }');
  });

  test('a write of a held hash replaces its text without growing', () {
    final store = MemoryPersistedQueryStore(capacity: 2)
      ..write('a', '{ a }')
      ..write('a', '{ b }');
    expect((store.read('a'), store.length), ('{ b }', 1));
  });

  test('a capacity below 1 is an ArgumentError', () {
    expect(() => MemoryPersistedQueryStore(capacity: 0), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: `test/persisted/memory_persisted_query_store_test.dart` does not compile: `MemoryPersistedQueryStore` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 112615d..e6cead2 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -175,3 +175,5 @@
   count with the request's values.
 - The Server guide and the example now serve a request with
   `GraphQLServer`.
+- `PersistedQueryStore`, where a server keeps automatic persisted queries,
+  and `MemoryPersistedQueryStore`, a bounded in-memory LRU.
```

Modify `packages/typed_graphql_server/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/dartdoc_options.yaml b/packages/typed_graphql_server/dartdoc_options.yaml
index 6c8d68e..2581132 100644
--- a/packages/typed_graphql_server/dartdoc_options.yaml
+++ b/packages/typed_graphql_server/dartdoc_options.yaml
@@ -21,6 +21,9 @@ dartdoc:
     lookahead:
       markdown: doc/lookahead.md
       displayName: Look-ahead
+    persisted:
+      markdown: doc/persisted_documents.md
+      displayName: Persisted Documents
     server:
       markdown: doc/server.md
       displayName: Server
@@ -35,6 +38,7 @@ dartdoc:
     - execution
     - introspection
     - lookahead
+    - persisted
     - server
     - subscription
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_server/doc/persisted_documents.md`:

````markdown
# Persisted Documents

This guide describes the stores of automatic persisted queries; the server
steps that use them come with the rest of the stage.

`MemoryPersistedQueryStore` keeps the most recently used texts by their
hash, evicting the least recently used one past its capacity.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final store = MemoryPersistedQueryStore(capacity: 1)
    ..write('a', '{ a }')
    ..write('b', '{ b }');
  print(store.read('a'));
  print(store.read('b'));
}
```

It prints:

```text
null
{ b }
```
````

Create `packages/typed_graphql_server/lib/src/persisted/memory_persisted_query_store.dart`:

```dart
import 'dart:collection';

import 'persisted_query_store.dart';

/// A [PersistedQueryStore] in memory: the [capacity] most recently used
/// texts, the least recently used one evicted first.
///
/// The capacity bounds the memory a client can fill by registering
/// queries; each text is bounded by the server's `maxDocumentLength`.
///
/// {@category persisted}
final class MemoryPersistedQueryStore implements PersistedQueryStore {
  /// Creates a store of at most [capacity] texts; a capacity below 1 is an
  /// [ArgumentError].
  MemoryPersistedQueryStore({this.capacity = 1000}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// The most texts the store holds.
  final int capacity;

  // A linked map keeps insertion order: the first key is the oldest.
  final LinkedHashMap<String, String> _texts = LinkedHashMap<String, String>();

  /// The number of texts held.
  int get length => _texts.length;

  /// The text stored for [hash], which becomes the most recently used, or
  /// null.
  @override
  String? read(String hash) {
    final text = _texts.remove(hash);
    if (text != null) _texts[hash] = text;
    return text;
  }

  /// Stores [text] for [hash] as the most recently used, evicting the least
  /// recently used text past the capacity.
  @override
  void write(String hash, String text) {
    _texts.remove(hash);
    _texts[hash] = text;
    if (_texts.length > capacity) {
      _texts.remove(_texts.keys.first);
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/persisted/persisted_query_store.dart`:

```dart
import 'dart:async';

/// Where a server keeps the texts of automatic persisted queries, by the
/// lower-case hex SHA-256 of each text (R5.4).
///
/// The server writes a text only after verifying that the hash is the
/// SHA-256 of the text and after the text parsed and validated, and checks
/// the hash again when it reads, so a store shared with other processes
/// cannot make a hash name another text. An error a store throws is an
/// unexpected error of the request (`GQL330`), never a silent miss.
/// [MemoryPersistedQueryStore] keeps them in memory; a store backed by a
/// shared cache implements this interface.
///
/// {@category persisted}
abstract interface class PersistedQueryStore {
  /// The text stored for [hash], or null when there is none.
  FutureOr<String?> read(String hash);

  /// Stores [text] for [hash].
  FutureOr<void> write(String hash, String text);
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index 91b5886..407d386 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -54,6 +54,8 @@ export 'src/introspection/introspection_policy.dart';
 export 'src/lookahead/column_allowlist.dart';
 export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
+export 'src/persisted/memory_persisted_query_store.dart';
+export 'src/persisted/persisted_query_store.dart';
 export 'src/server/context_factory.dart';
 export 'src/server/csrf_prevention.dart';
 export 'src/server/document_handler.dart';
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`/home/genius/fvm/versions/3.47.6/bin/dart format packages test`, wrapped as above), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages docs CLAUDE.md README.md llms.txt
git commit -m "feat(typed_graphql_server): add PersistedQueryStore and MemoryPersistedQueryStore

<your model trailer>"
```

### Task 3: feat(typed_graphql_server): add automatic persisted queries to the pipeline

**Why.** R5.4. `PersistedQueryReader` reads `extensions.persistedQuery` into the sealed `PersistedQueryReference` (a JSON null is none; not an object, a version other than 1 or a hash that is not 64 lower-case hex digits is `GQL413`). `AutomaticPersistedQueries` (with `GraphQLServer(persistedQueries:)`): a hash alone reads the store, checks the length and hashes the stored text again (a miss or a mismatch is `GQL410` "PersistedQueryNotFound"); a text with a hash must match (`GQL411`) and is stored only once the core step accepted it; a store error is an unexpected error (`GQL330`). Without a store, `PersistedQueriesUnsupported` refuses a hash alone with `GQL412` "PersistedQueryNotSupported". `PipelineAssembly` places the step after CSRF. The fixture gains `extensions`, `persistedQueries`, `hashOf` and `persisted`.

**Files** (verified commit `7ccb169` of the controller's scratch copy):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Create `packages/typed_graphql_server/lib/src/persisted/automatic_persisted_queries.dart`
- Create `packages/typed_graphql_server/lib/src/persisted/persisted_queries_unsupported.dart`
- Create `packages/typed_graphql_server/lib/src/persisted/persisted_query_reader.dart`
- Create `packages/typed_graphql_server/lib/src/persisted/persisted_query_reference.dart`
- Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Modify `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart`
- Create `packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart`
- Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  const text = '{ hello }';
  final hash = fixture.hashOf(text);

  group('with a store', () {
    test('runs a hash alone once its text was registered', () async {
      final server = fixture.server(
        persistedQueries: MemoryPersistedQueryStore(),
      );
      await server.handle(
        fixture.request(text, extensions: fixture.persisted(hash)),
      );
      final response = await server.handle(
        fixture.request(null, extensions: fixture.persisted(hash)),
      );
      expect(fixture.json(response), {
        'data': {'hello': 'world'},
      });
    });

    test('takes an empty query with a hash as the hash alone', () async {
      final store = MemoryPersistedQueryStore()..write(hash, text);
      final response = await fixture
          .server(persistedQueries: store)
          .handle(fixture.request('', extensions: fixture.persisted(hash)));
      expect(response.outcome, ServerOutcome.executed);
    });

    test('reports an unknown hash as PersistedQueryNotFound', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(fixture.request(null, extensions: fixture.persisted(hash)));
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL410', 'PersistedQueryNotFound'),
      );
    });

    test('refuses a text whose hash differs', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(
            fixture.request('{ greet }', extensions: fixture.persisted(hash)),
          );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL411', 'provided sha does not match query'),
      );
    });

    test('stores no text whose hash differs', () async {
      final store = MemoryPersistedQueryStore();
      await fixture
          .server(persistedQueries: store)
          .handle(
            fixture.request('{ greet }', extensions: fixture.persisted(hash)),
          );
      expect(store.length, 0);
    });

    test('stores no text that fails validation', () async {
      const invalid = '{ missing }';
      final store = MemoryPersistedQueryStore();
      await fixture
          .server(persistedQueries: store)
          .handle(
            fixture.request(
              invalid,
              extensions: fixture.persisted(fixture.hashOf(invalid)),
            ),
          );
      expect(store.length, 0);
    });

    test('runs a request without the extension as usual', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(fixture.request(text));
      expect(response.outcome, ServerOutcome.executed);
    });

    test('takes a JSON null extension as no persisted query', () async {
      final response = await fixture
          .server(persistedQueries: MemoryPersistedQueryStore())
          .handle(
            fixture.request(
              text,
              extensions: JsonObject({'persistedQuery': const JsonNull()}),
            ),
          );
      expect(response.outcome, ServerOutcome.executed);
    });

    test('refuses a stored text past the length limit', () async {
      final store = MemoryPersistedQueryStore()..write(hash, text);
      final profile = ServerProfile.development.withLimits(
        const ServerLimits(maxDocumentLength: 4),
      );
      final response = await fixture
          .server(profile: profile, persistedQueries: store)
          .handle(fixture.request(null, extensions: fixture.persisted(hash)));
      expect(fixture.codeOf(response), 'GQL401');
    });

    test('reports a store failure as an unexpected error', () async {
      final response = await fixture
          .server(persistedQueries: const FailingStore())
          .handle(fixture.request(null, extensions: fixture.persisted(hash)));
      expect(fixture.codeOf(response), 'GQL330');
    });
  });

  group('without a store', () {
    test('refuses a hash alone as PersistedQueryNotSupported', () async {
      final response = await fixture.server().handle(
        fixture.request(null, extensions: fixture.persisted(hash)),
      );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL412', 'PersistedQueryNotSupported'),
      );
    });

    test('runs a text and ignores its hash', () async {
      final response = await fixture.server().handle(
        fixture.request(text, extensions: fixture.persisted(hash)),
      );
      expect(response.outcome, ServerOutcome.executed);
    });
  });
}

/// A store whose every call fails, as a broken shared store would.
final class FailingStore implements PersistedQueryStore {
  const FailingStore();

  @override
  FutureOr<String?> read(String hash) => throw StateError('store is down');

  @override
  FutureOr<void> write(String hash, String text) =>
      throw StateError('store is down');
}
```

Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/support/server_fixture.dart b/packages/typed_graphql_server/test/server/support/server_fixture.dart
index 7037b95..d807e98 100644
--- a/packages/typed_graphql_server/test/server/support/server_fixture.dart
+++ b/packages/typed_graphql_server/test/server/support/server_fixture.dart
@@ -1,4 +1,7 @@
 import 'dart:async';
+import 'dart:convert';
+
+import 'package:crypto/crypto.dart';
 
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
@@ -92,6 +95,7 @@ final class ServerFixture {
     ErrorHook? onError,
     int documentCacheSize = 1000,
     List<ServerExtension<Ctx>> extensions = const [],
+    PersistedQueryStore? persistedQueries,
   }) => GraphQLServer<Ctx>(
     schema: schema,
     contextFactory: contextFactory ?? (_) => const Ctx('default'),
@@ -100,6 +104,7 @@ final class ServerFixture {
     onError: onError,
     documentCacheSize: documentCacheSize,
     extensions: extensions,
+    persistedQueries: persistedQueries,
   );
 
   ServerRequest request(
@@ -109,11 +114,13 @@ final class ServerFixture {
     JsonObject? variables,
     CancelSignal? cancelSignal,
     Map<String, String> headers = const {'content-type': 'application/json'},
+    JsonObject? extensions,
   }) => ServerRequest(
     params: GraphQLRequest(
       query: query,
       operationName: operationName,
       variables: variables,
+      extensions: extensions,
     ),
     info: RequestInfo(
       method: method,
@@ -123,6 +130,17 @@ final class ServerFixture {
     cancelSignal: cancelSignal,
   );
 
+  /// The lower-case hex SHA-256 of [text], as clients name a document.
+  String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();
+
+  /// The `extensions` of a request naming the persisted query [hash].
+  JsonObject persisted(String hash) => JsonObject({
+    'persistedQuery': JsonObject({
+      'version': JsonNumber(1),
+      'sha256Hash': JsonString(hash),
+    }),
+  });
+
   /// A query nested [depth] levels deep: `{ self { self { hello } } }`.
   String nested(int depth) => '${'{ self ' * depth}{ hello }${' }' * depth}';
 
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: `test/persisted/automatic_persisted_queries_test.dart` does not compile: `GraphQLServer` has no `persistedQueries` parameter.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index e6cead2..c885d0f 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -177,3 +177,8 @@
   `GraphQLServer`.
 - `PersistedQueryStore`, where a server keeps automatic persisted queries,
   and `MemoryPersistedQueryStore`, a bounded in-memory LRU.
+- `GraphQLServer(persistedQueries:)` turns on automatic persisted queries:
+  a hash alone runs a stored text (`GQL410` when it is not stored), a text
+  with its hash is checked (`GQL411`) and stored once it validates, a
+  malformed `extensions.persistedQuery` is `GQL413`. Without a store a hash
+  alone is `GQL412`. A stored text is hashed again when read.
```

Create `packages/typed_graphql_server/lib/src/persisted/automatic_persisted_queries.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_handler.dart';
import '../server/document_hash.dart';
import '../server/document_length.dart';
import '../server/document_request.dart';
import '../server/document_result.dart';
import '../server/pipeline_errors.dart';
import '../server/server_extension.dart';
import 'persisted_query_reader.dart';
import 'persisted_query_reference.dart';
import 'persisted_query_store.dart';

/// The document-phase step of automatic persisted queries (R5.4): a hash
/// alone is read from [store]; a text with its hash is checked and, once
/// accepted, written to [store].
///
/// A hash always names its own text: a text whose SHA-256 is not the hash
/// is `GQL411` and never stored, a text is stored only after it parsed and
/// validated, and a stored text is checked again when read, so neither a
/// client nor a shared store can make a hash serve another document.
@internal
final class AutomaticPersistedQueries<C> extends ServerExtension<C> {
  /// Creates the step over [store], checking stored texts with [length] and
  /// refusing through [errors].
  const AutomaticPersistedQueries(this.store, this.length, this.errors);

  /// Where the texts are kept.
  final PersistedQueryStore store;

  /// The length check of a stored text, before it is hashed.
  final DocumentLength length;

  /// Makes the errors.
  final PipelineErrors errors;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    const reader = PersistedQueryReader();
    switch (reader.read(request.request.params.extensions)) {
      case NoPersistedQuery():
        return next(request);
      case final InvalidPersistedQuery invalid:
        return DocumentRejected([reader.errorOf(invalid, errors)]);
      case PersistedQueryHash(:final hash):
        final text = request.text;
        if (text == null || text.isEmpty) return _stored(request, hash, next);
        return _register(request, text, hash, next);
    }
  }

  Future<DocumentResult> _stored(
    DocumentRequest request,
    String hash,
    DocumentHandler next,
  ) async {
    final text = await store.read(hash);
    if (text == null) return _notFound();
    if (length.violation(text) case final violation?) {
      return DocumentRejected([violation]);
    }
    if (const DocumentHash().of(text) != hash) return _notFound();
    return next(request.withText(text));
  }

  Future<DocumentResult> _register(
    DocumentRequest request,
    String text,
    String hash,
    DocumentHandler next,
  ) async {
    if (const DocumentHash().of(text) != hash) {
      return DocumentRejected([
        errors.coded(
          DiagnosticCode.persistedQueryHashMismatch,
          'provided sha does not match query',
        ),
      ]);
    }
    final result = await next(request);
    if (result case DocumentAccepted()) await store.write(hash, text);
    return result;
  }

  // The message Apollo clients match to send the text with the hash.
  DocumentRejected _notFound() => DocumentRejected([
    errors.coded(
      DiagnosticCode.persistedQueryNotFound,
      'PersistedQueryNotFound',
    ),
  ]);
}
```

Create `packages/typed_graphql_server/lib/src/persisted/persisted_queries_unsupported.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_handler.dart';
import '../server/document_request.dart';
import '../server/document_result.dart';
import '../server/pipeline_errors.dart';
import '../server/server_extension.dart';
import 'persisted_query_reader.dart';
import 'persisted_query_reference.dart';

/// The document-phase step of a server that keeps neither persisted queries
/// nor trusted documents: a hash without a text is `GQL412`, whose message
/// tells Apollo clients to stop sending hashes; with a text the extension
/// is ignored.
@internal
final class PersistedQueriesUnsupported<C> extends ServerExtension<C> {
  /// Creates the step, refusing through [errors].
  const PersistedQueriesUnsupported(this.errors);

  /// Makes the error.
  final PipelineErrors errors;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    final text = request.text;
    final reference = const PersistedQueryReader().read(
      request.request.params.extensions,
    );
    if (reference is PersistedQueryHash && (text == null || text.isEmpty)) {
      return DocumentRejected([
        errors.coded(
          DiagnosticCode.persistedQueryNotSupported,
          'PersistedQueryNotSupported',
        ),
      ]);
    }
    return next(request);
  }
}
```

Create `packages/typed_graphql_server/lib/src/persisted/persisted_query_reader.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/pipeline_errors.dart';
import 'persisted_query_reference.dart';

/// Reads `extensions.persistedQuery` of a request (R5.4).
@internal
final class PersistedQueryReader {
  /// Creates the reader.
  const PersistedQueryReader();

  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// The persisted query [extensions] name; a JSON `null` names none.
  PersistedQueryReference read(JsonObject? extensions) =>
      switch (extensions?.fields['persistedQuery']) {
        null || JsonNull() => const NoPersistedQuery(),
        JsonObject(:final fields) => _read(fields),
        _ => const InvalidPersistedQuery('it must be an object'),
      };

  /// The `GQL413` error for [invalid].
  GraphQLError errorOf(InvalidPersistedQuery invalid, PipelineErrors errors) =>
      errors.coded(
        DiagnosticCode.invalidPersistedQuery,
        'Invalid persisted query: ${invalid.reason}.',
      );

  PersistedQueryReference _read(Map<String, JsonValue> fields) {
    if (fields['version'] case JsonNumber(:final value) when value == 1) {
      return switch (fields['sha256Hash']) {
        JsonString(:final value) when _sha256.hasMatch(value) =>
          PersistedQueryHash(value),
        _ => const InvalidPersistedQuery(
          'sha256Hash must be 64 lower-case hexadecimal digits',
        ),
      };
    }
    return const InvalidPersistedQuery('version must be 1');
  }
}
```

Create `packages/typed_graphql_server/lib/src/persisted/persisted_query_reference.dart`:

```dart
import 'package:meta/meta.dart';

/// What `extensions.persistedQuery` of a request says (Apollo's shape,
/// `{"version": 1, "sha256Hash": "<64 lower-case hex digits>"}`).
@internal
sealed class PersistedQueryReference {
  const PersistedQueryReference();
}

/// The request names no persisted query.
@internal
final class NoPersistedQuery extends PersistedQueryReference {
  /// Creates the reference.
  const NoPersistedQuery();
}

/// The request names the persisted query [hash].
@internal
final class PersistedQueryHash extends PersistedQueryReference {
  /// Creates the reference to [hash].
  const PersistedQueryHash(this.hash);

  /// The lower-case hex SHA-256 the request names.
  final String hash;
}

/// The extension is malformed; [reason] says how (`GQL413`).
@internal
final class InvalidPersistedQuery extends PersistedQueryReference {
  /// Creates the reference with [reason].
  const InvalidPersistedQuery(this.reason);

  /// What is wrong, a clause for the message.
  final String reason;
}
```

Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/graphql_server.dart b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
index 7821913..4c39fba 100644
--- a/packages/typed_graphql_server/lib/src/server/graphql_server.dart
+++ b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
 import '../execution/graphql_exception.dart';
+import '../persisted/persisted_query_store.dart';
 import 'context_factory.dart';
 import 'pipeline_assembly.dart';
 import 'pipeline_errors.dart';
@@ -36,6 +37,10 @@ final class GraphQLServer<C> {
   /// [extensions] hook into the three phases of a request; the first is the
   /// outermost and sees even the requests the built-in checks (CSRF
   /// prevention) refuse.
+  ///
+  /// [persistedQueries] turns on automatic persisted queries (R5.4): a
+  /// request may send only the SHA-256 of a document the store holds. Without
+  /// a store, a request that sends only a hash is refused with `GQL412`.
   factory GraphQLServer({
     required ExecutableSchema<C> schema,
     required ContextFactory<C> contextFactory,
@@ -44,6 +49,7 @@ final class GraphQLServer<C> {
     ErrorHook? onError,
     int documentCacheSize = 1000,
     List<ServerExtension<C>> extensions = const [],
+    PersistedQueryStore? persistedQueries,
   }) {
     final assembly = PipelineAssembly<C>(
       schema: schema,
@@ -53,6 +59,7 @@ final class GraphQLServer<C> {
       onError: onError,
       documentCacheSize: documentCacheSize,
       extensions: extensions,
+      persistedQueries: persistedQueries,
     );
     return GraphQLServer._(assembly.errors, assembly.handler());
   }
```

Modify `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart b/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
index 2106c1d..56fe741 100644
--- a/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
+++ b/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
@@ -3,6 +3,9 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
+import '../persisted/automatic_persisted_queries.dart';
+import '../persisted/persisted_queries_unsupported.dart';
+import '../persisted/persisted_query_store.dart';
 import '../plan/operation_selection.dart';
 import 'context_factory.dart';
 import 'cost_limit.dart';
@@ -22,7 +25,7 @@ import 'server_extension.dart';
 import 'server_profile.dart';
 
 /// Builds the handlers of a server from its settings, once: the extension
-/// chains around the core steps. M6c adds its steps to [handler].
+/// chains around the core steps.
 @internal
 final class PipelineAssembly<C> {
   /// Creates the assembly; the arguments are those of `GraphQLServer`.
@@ -34,6 +37,7 @@ final class PipelineAssembly<C> {
     required this.onError,
     required this.documentCacheSize,
     required this.extensions,
+    required this.persistedQueries,
   }) : errors = PipelineErrors(
          maskErrors: profile.maskErrors,
          onError: onError,
@@ -60,6 +64,9 @@ final class PipelineAssembly<C> {
   /// The user's extensions, outermost first.
   final List<ServerExtension<C>> extensions;
 
+  /// The store of automatic persisted queries; null keeps none.
+  final PersistedQueryStore? persistedQueries;
+
   /// Makes the refusals and the unexpected-error responses.
   final PipelineErrors errors;
 
@@ -67,12 +74,12 @@ final class PipelineAssembly<C> {
   RequestHandler handler() {
     final length = DocumentLength(profile.limits.maxDocumentLength, errors);
     // The user's extensions are outermost, then the built-in ones in a fixed
-    // order, so no list order puts a step before a security check. M6c adds
-    // the trusted-document and APQ extensions here.
+    // order, so no list order puts a step before a security check.
     final chain = ExtensionChain<C>([
       ...extensions,
       if (profile.csrfPrevention case final csrf?)
         CsrfExtension<C>(csrf, errors),
+      _persistedDocuments(length),
     ]);
     final executionStep = ExecutionStep<C>(schema, profile, onError);
     final request = RequestStep<C>(
@@ -88,6 +95,12 @@ final class PipelineAssembly<C> {
     return chain.request(request.run);
   }
 
+  ServerExtension<C> _persistedDocuments(DocumentLength length) =>
+      switch (persistedQueries) {
+        final store? => AutomaticPersistedQueries<C>(store, length, errors),
+        null => PersistedQueriesUnsupported<C>(errors),
+      };
+
   DocumentHandler _documentStep(DocumentLength length) => DocumentStep(
     DocumentCache(documentCacheSize),
     _compiler(),
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`/home/genius/fvm/versions/3.47.6/bin/dart format packages test`, wrapped as above), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages docs CLAUDE.md README.md llms.txt
git commit -m "feat(typed_graphql_server): add automatic persisted queries to the pipeline

<your model trailer>"
```

### Task 4: feat(typed_graphql_server): add trusted documents

**Why.** R5.4. `TrustedDocuments` (public, `persisted` category): built from ids and texts (an id that is not its text's SHA-256 is an `ArgumentError`) or decoded from the manifest M10 writes (`TrustedManifestReader`: format and version checked, only `id` and `body` read, an id that is not its body's hash is a `DecodeFailure` at `$.operations[i].id`). `TrustedDocumentsCheck` (with `GraphQLServer(trustedDocuments:)`): a hash alone runs its trusted text (`GQL415` when none), a text runs only when its hash is trusted (`GQL414` "Only trusted documents are allowed."), a text with another hash is `GQL411`, a malformed extension `GQL413`, no text and no hash goes on to `GQL400`. Both `persistedQueries` and `trustedDocuments` are an `ArgumentError`.

**Files** (verified commit `369f259` of the controller's scratch copy):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Create `packages/typed_graphql_server/lib/src/persisted/trusted_documents.dart`
- Create `packages/typed_graphql_server/lib/src/persisted/trusted_documents_check.dart`
- Create `packages/typed_graphql_server/lib/src/persisted/trusted_manifest_reader.dart`
- Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Modify `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Create `packages/typed_graphql_server/test/persisted/trusted_documents_test.dart`
- Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/persisted/trusted_documents_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  const text = '{hello}';
  final hash = fixture.hashOf(text);

  JsonObject manifest(List<JsonValue> operations) => JsonObject({
    'format': const JsonString('apollo-persisted-query-manifest'),
    'version': JsonNumber(1),
    'operations': JsonArray(operations),
  });

  JsonObject entry(String id, String body) => JsonObject({
    'id': JsonString(id),
    'name': const JsonString('Hello'),
    'type': const JsonString('query'),
    'body': JsonString(body),
  });

  group('TrustedDocuments', () {
    test('gives the text of a trusted id', () {
      expect(TrustedDocuments({hash: text}).textOf(hash), text);
    });

    test('gives null for an id it does not hold', () {
      expect(TrustedDocuments({hash: text}).textOf('0' * 64), isNull);
    });

    test('refuses an id that is not the hash of its text', () {
      expect(
        () => TrustedDocuments({hash: '{ hello }'}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('decodes the manifest of typed_graphql_codegen', () {
      final result = TrustedDocuments.decode(manifest([entry(hash, text)]));
      expect(
        switch (result) {
          DecodeSuccess(:final value) => value.textOf(hash),
          DecodeFailure() => null,
        },
        text,
      );
    });

    test('decodes an entry whose id is not its hash as a failure', () {
      expect(
        TrustedDocuments.decode(manifest([entry('0' * 64, text)])),
        const DecodeFailure(
          'expected the SHA-256 of the body',
          path: [PathKey('operations'), PathIndex(0), PathKey('id')],
        ),
      );
    });

    test('decodes an entry without a body as a failure', () {
      expect(
        TrustedDocuments.decode(
          manifest([
            JsonObject({'id': JsonString(hash)}),
          ]),
        ),
        const DecodeFailure(
          'expected an object with a string id and body',
          path: [PathKey('operations'), PathIndex(0)],
        ),
      );
    });

    test('decodes another format as a failure', () {
      expect(
        TrustedDocuments.decode(
          JsonObject({...manifest([]).fields, 'format': const JsonString('x')}),
        ),
        const DecodeFailure(
          'expected "apollo-persisted-query-manifest"',
          path: [PathKey('format')],
        ),
      );
    });

    test('decodes another version as a failure', () {
      expect(
        TrustedDocuments.decode(
          JsonObject({...manifest([]).fields, 'version': JsonNumber(2)}),
        ),
        const DecodeFailure('expected 1', path: [PathKey('version')]),
      );
    });

    test('decodes a manifest without operations as a failure', () {
      expect(
        TrustedDocuments.decode(
          JsonObject({
            'format': const JsonString('apollo-persisted-query-manifest'),
            'version': JsonNumber(1),
          }),
        ),
        const DecodeFailure(
          'expected an array',
          path: [PathKey('operations')],
        ),
      );
    });

    test('decodes a value that is not an object as a failure', () {
      expect(
        TrustedDocuments.decode(const JsonString('manifest')),
        const DecodeFailure('expected an object'),
      );
    });
  });

  group('a server with trusted documents', () {
    GraphQLServer<Ctx> server() =>
        fixture.server(trustedDocuments: TrustedDocuments({hash: text}));

    test('runs a trusted hash alone', () async {
      final response = await server().handle(
        fixture.request(null, extensions: fixture.persisted(hash)),
      );
      expect(fixture.json(response), {
        'data': {'hello': 'world'},
      });
    });

    test('runs a trusted text without a hash', () async {
      final response = await server().handle(fixture.request(text));
      expect(response.outcome, ServerOutcome.executed);
    });

    test('runs a trusted text with its hash', () async {
      final response = await server().handle(
        fixture.request(text, extensions: fixture.persisted(hash)),
      );
      expect(response.outcome, ServerOutcome.executed);
    });

    test('refuses an unknown hash', () async {
      final unknown = '0' * 64;
      final response = await server().handle(
        fixture.request(null, extensions: fixture.persisted(unknown)),
      );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL415', 'No trusted document has the id "$unknown".'),
      );
    });

    test('refuses a text that is not trusted', () async {
      final response = await server().handle(fixture.request('{ greet }'));
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL414', 'Only trusted documents are allowed.'),
      );
    });

    test('refuses a trusted text sent with another hash', () async {
      final response = await server().handle(
        fixture.request(
          text,
          extensions: fixture.persisted(fixture.hashOf('{ greet }')),
        ),
      );
      expect(fixture.codeOf(response), 'GQL411');
    });

    test('refuses a malformed extension', () async {
      final response = await server().handle(
        fixture.request(
          text,
          extensions: JsonObject({'persistedQuery': const JsonString('x')}),
        ),
      );
      expect(
        (fixture.codeOf(response), fixture.messageOf(response)),
        ('GQL413', 'Invalid persisted query: it must be an object.'),
      );
    });

    test('reports a request with no text and no hash as GQL400', () async {
      final response = await server().handle(fixture.request(null));
      expect(fixture.codeOf(response), 'GQL400');
    });
  });

  test('a server with a store and trusted documents is refused', () {
    expect(
      () => fixture.server(
        persistedQueries: MemoryPersistedQueryStore(),
        trustedDocuments: TrustedDocuments({hash: text}),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/support/server_fixture.dart b/packages/typed_graphql_server/test/server/support/server_fixture.dart
index d807e98..915d444 100644
--- a/packages/typed_graphql_server/test/server/support/server_fixture.dart
+++ b/packages/typed_graphql_server/test/server/support/server_fixture.dart
@@ -96,6 +96,7 @@ final class ServerFixture {
     int documentCacheSize = 1000,
     List<ServerExtension<Ctx>> extensions = const [],
     PersistedQueryStore? persistedQueries,
+    TrustedDocuments? trustedDocuments,
   }) => GraphQLServer<Ctx>(
     schema: schema,
     contextFactory: contextFactory ?? (_) => const Ctx('default'),
@@ -105,6 +106,7 @@ final class ServerFixture {
     documentCacheSize: documentCacheSize,
     extensions: extensions,
     persistedQueries: persistedQueries,
+    trustedDocuments: trustedDocuments,
   );
 
   ServerRequest request(
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: `test/persisted/trusted_documents_test.dart` does not compile: `TrustedDocuments` is not defined.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index c885d0f..f10443d 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -182,3 +182,8 @@
   with its hash is checked (`GQL411`) and stored once it validates, a
   malformed `extensions.persistedQuery` is `GQL413`. Without a store a hash
   alone is `GQL412`. A stored text is hashed again when read.
+- `TrustedDocuments` (built from a map or decoded from the manifest
+  `typed_graphql_codegen` writes) and `GraphQLServer(trustedDocuments:)`: a
+  hash runs its trusted text (`GQL415` when none), a text runs only when it
+  is trusted to the character (`GQL414`). Combined with `persistedQueries`
+  it is an `ArgumentError`.
```

Create `packages/typed_graphql_server/lib/src/persisted/trusted_documents.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_hash.dart';
import 'trusted_manifest_reader.dart';

/// The only documents a server runs, by the SHA-256 of their text (R5.4).
///
/// With `GraphQLServer(trustedDocuments:)` a request names a document by its
/// hash in `extensions.persistedQuery`, or sends a text that is one of them
/// to the character; any other text is refused (`GQL414`).
///
/// {@category persisted}
final class TrustedDocuments {
  /// Creates the set from [documents], id to text.
  ///
  /// An id that is not the lower-case hexadecimal SHA-256 of the UTF-8 of
  /// its text is an [ArgumentError].
  TrustedDocuments(Map<String, String> documents)
    : _documents = Map.unmodifiable(documents) {
    for (final MapEntry(key: id, value: text) in documents.entries) {
      if (const DocumentHash().of(text) != id) {
        throw ArgumentError.value(
          id,
          'documents',
          'is not the SHA-256 of its text',
        );
      }
    }
  }

  /// Reads the persisted-operations manifest that `typed_graphql_codegen`
  /// writes (`apollo-persisted-query-manifest`, version 1).
  ///
  /// A malformed manifest, or an id that is not the SHA-256 of its body, is
  /// a [DecodeFailure] with its path.
  static DecodeResult<TrustedDocuments> decode(JsonValue manifest) =>
      switch (const TrustedManifestReader().read(manifest)) {
        DecodeSuccess(:final value) => DecodeSuccess(TrustedDocuments(value)),
        final DecodeFailure failure => failure,
      };

  final Map<String, String> _documents;

  /// The number of documents.
  int get length => _documents.length;

  /// The text of the document [id] names, or null when none is trusted.
  String? textOf(String id) => _documents[id];
}
```

Create `packages/typed_graphql_server/lib/src/persisted/trusted_documents_check.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_handler.dart';
import '../server/document_hash.dart';
import '../server/document_request.dart';
import '../server/document_result.dart';
import '../server/pipeline_errors.dart';
import '../server/server_extension.dart';
import 'persisted_query_reader.dart';
import 'persisted_query_reference.dart';
import 'trusted_documents.dart';

/// The document-phase step of trusted documents (R5.4): only a document in
/// [documents] reaches the core step.
///
/// A hash alone runs its trusted text (`GQL415` when there is none); a text
/// runs only when its SHA-256 is trusted (`GQL414`), so any change to a
/// trusted text, whitespace included, is refused. A request with no text and
/// no hash goes on to the core step, which reports `GQL400`.
@internal
final class TrustedDocumentsCheck<C> extends ServerExtension<C> {
  /// Creates the step over [documents], refusing through [errors].
  const TrustedDocumentsCheck(this.documents, this.errors);

  /// The documents the server runs.
  final TrustedDocuments documents;

  /// Makes the errors.
  final PipelineErrors errors;

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    const reader = PersistedQueryReader();
    final reference = reader.read(request.request.params.extensions);
    if (reference case final InvalidPersistedQuery invalid) {
      return DocumentRejected([reader.errorOf(invalid, errors)]);
    }
    final text = request.text;
    if (text == null || text.isEmpty) {
      return switch (reference) {
        PersistedQueryHash(:final hash) => _trusted(request, hash, next),
        _ => next(request),
      };
    }
    final textHash = const DocumentHash().of(text);
    if (reference case PersistedQueryHash(:final hash) when hash != textHash) {
      return _refused(
        DiagnosticCode.persistedQueryHashMismatch,
        'provided sha does not match query',
      );
    }
    if (documents.textOf(textHash) == null) {
      return _refused(
        DiagnosticCode.untrustedDocument,
        'Only trusted documents are allowed.',
      );
    }
    return next(request);
  }

  Future<DocumentResult> _trusted(
    DocumentRequest request,
    String hash,
    DocumentHandler next,
  ) async => switch (documents.textOf(hash)) {
    final text? => await next(request.withText(text)),
    null => _refused(
      DiagnosticCode.unknownTrustedDocument,
      'No trusted document has the id "$hash".',
    ),
  };

  DocumentRejected _refused(DiagnosticCode code, String message) =>
      DocumentRejected([errors.coded(code, message)]);
}
```

Create `packages/typed_graphql_server/lib/src/persisted/trusted_manifest_reader.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../server/document_hash.dart';

/// Reads the persisted-operations manifest M10 writes (Apollo's
/// `apollo-persisted-query-manifest`, version 1) into ids and texts.
///
/// Only `id` and `body` of an operation are read; an id that is not the
/// SHA-256 of its body is a failure, so a forged manifest entry cannot make
/// one hash stand for another text.
@internal
final class TrustedManifestReader {
  /// Creates the reader.
  const TrustedManifestReader();

  static const String _format = 'apollo-persisted-query-manifest';

  /// The documents of [manifest], id to text, or where it is malformed.
  DecodeResult<Map<String, String>> read(JsonValue manifest) =>
      switch (manifest) {
        JsonObject(:final fields) => _manifest(fields),
        _ => const DecodeFailure('expected an object'),
      };

  DecodeResult<Map<String, String>> _manifest(Map<String, JsonValue> fields) {
    if (fields['format'] != const JsonString(_format)) {
      return const DecodeFailure(
        'expected "$_format"',
      ).inside(const PathKey('format'));
    }
    if (fields['version'] != JsonNumber(1)) {
      return const DecodeFailure(
        'expected 1',
      ).inside(const PathKey('version'));
    }
    return switch (fields['operations']) {
      JsonArray(:final items) => _operations(
        items,
      ).inside(const PathKey('operations')),
      _ => const DecodeFailure(
        'expected an array',
      ).inside(const PathKey('operations')),
    };
  }

  DecodeResult<Map<String, String>> _operations(List<JsonValue> items) {
    final documents = <String, String>{};
    for (final (index, item) in items.indexed) {
      switch (_operation(item)) {
        case DecodeSuccess(value: (final id, final body)):
          documents[id] = body;
        case final DecodeFailure failure:
          return failure.inside(PathIndex(index));
      }
    }
    return DecodeSuccess(documents);
  }

  DecodeResult<(String, String)> _operation(JsonValue item) {
    if (item case JsonObject(
      fields: {
        'id': JsonString(value: final id),
        'body': JsonString(value: final body),
      },
    )) {
      if (const DocumentHash().of(body) == id) return DecodeSuccess((id, body));
      return const DecodeFailure(
        'expected the SHA-256 of the body',
      ).inside(const PathKey('id'));
    }
    return const DecodeFailure('expected an object with a string id and body');
  }
}
```

Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/graphql_server.dart b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
index 4c39fba..dc69084 100644
--- a/packages/typed_graphql_server/lib/src/server/graphql_server.dart
+++ b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
@@ -4,6 +4,7 @@ import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
 import '../execution/graphql_exception.dart';
 import '../persisted/persisted_query_store.dart';
+import '../persisted/trusted_documents.dart';
 import 'context_factory.dart';
 import 'pipeline_assembly.dart';
 import 'pipeline_errors.dart';
@@ -41,6 +42,11 @@ final class GraphQLServer<C> {
   /// [persistedQueries] turns on automatic persisted queries (R5.4): a
   /// request may send only the SHA-256 of a document the store holds. Without
   /// a store, a request that sends only a hash is refused with `GQL412`.
+  ///
+  /// [trustedDocuments] runs only the documents it holds, named by their
+  /// hash or sent as their exact text. It cannot be combined with
+  /// [persistedQueries], which would let a client register any document:
+  /// both are an [ArgumentError].
   factory GraphQLServer({
     required ExecutableSchema<C> schema,
     required ContextFactory<C> contextFactory,
@@ -50,7 +56,15 @@ final class GraphQLServer<C> {
     int documentCacheSize = 1000,
     List<ServerExtension<C>> extensions = const [],
     PersistedQueryStore? persistedQueries,
+    TrustedDocuments? trustedDocuments,
   }) {
+    if (persistedQueries != null && trustedDocuments != null) {
+      throw ArgumentError(
+        'Automatic persisted queries would let a client register any '
+            'document, which trusted documents forbid.',
+        'persistedQueries',
+      );
+    }
     final assembly = PipelineAssembly<C>(
       schema: schema,
       contextFactory: contextFactory,
@@ -60,6 +74,7 @@ final class GraphQLServer<C> {
       documentCacheSize: documentCacheSize,
       extensions: extensions,
       persistedQueries: persistedQueries,
+      trustedDocuments: trustedDocuments,
     );
     return GraphQLServer._(assembly.errors, assembly.handler());
   }
```

Modify `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart b/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
index 56fe741..04d216c 100644
--- a/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
+++ b/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
@@ -6,6 +6,8 @@ import '../execution/executable_schema.dart';
 import '../persisted/automatic_persisted_queries.dart';
 import '../persisted/persisted_queries_unsupported.dart';
 import '../persisted/persisted_query_store.dart';
+import '../persisted/trusted_documents.dart';
+import '../persisted/trusted_documents_check.dart';
 import '../plan/operation_selection.dart';
 import 'context_factory.dart';
 import 'cost_limit.dart';
@@ -38,6 +40,7 @@ final class PipelineAssembly<C> {
     required this.documentCacheSize,
     required this.extensions,
     required this.persistedQueries,
+    required this.trustedDocuments,
   }) : errors = PipelineErrors(
          maskErrors: profile.maskErrors,
          onError: onError,
@@ -67,6 +70,9 @@ final class PipelineAssembly<C> {
   /// The store of automatic persisted queries; null keeps none.
   final PersistedQueryStore? persistedQueries;
 
+  /// The only documents the server runs; null runs any document.
+  final TrustedDocuments? trustedDocuments;
+
   /// Makes the refusals and the unexpected-error responses.
   final PipelineErrors errors;
 
@@ -96,9 +102,14 @@ final class PipelineAssembly<C> {
   }
 
   ServerExtension<C> _persistedDocuments(DocumentLength length) =>
-      switch (persistedQueries) {
-        final store? => AutomaticPersistedQueries<C>(store, length, errors),
-        null => PersistedQueriesUnsupported<C>(errors),
+      switch ((trustedDocuments, persistedQueries)) {
+        (final trusted?, _) => TrustedDocumentsCheck<C>(trusted, errors),
+        (null, final store?) => AutomaticPersistedQueries<C>(
+          store,
+          length,
+          errors,
+        ),
+        (null, null) => PersistedQueriesUnsupported<C>(errors),
       };
 
   DocumentHandler _documentStep(DocumentLength length) => DocumentStep(
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index 407d386..71fdaea 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -56,6 +56,7 @@ export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
 export 'src/persisted/memory_persisted_query_store.dart';
 export 'src/persisted/persisted_query_store.dart';
+export 'src/persisted/trusted_documents.dart';
 export 'src/server/context_factory.dart';
 export 'src/server/csrf_prevention.dart';
 export 'src/server/document_handler.dart';
```

- [ ] **Step 4: Format, then run the green check.**

Format first (`/home/genius/fvm/versions/3.47.6/bin/dart format packages test`, wrapped as above), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages docs CLAUDE.md README.md llms.txt
git commit -m "feat(typed_graphql_server): add trusted documents

<your model trailer>"
```

### Task 5: test(typed_graphql_server): add the persisted document hostile-input tests

**Why.** Spec section 14: a text registered under another hash is never served, a poisoned store entry is not run, a syntax error is never stored, 3000 registrations keep the store at its capacity, an unknown hash never reaches validation, a store failure is masked in production, ten malformed extensions are `GQL413`; for trusted documents, whitespace and comment variants are refused, an untrusted or unparsable text never reaches validation, a trusted hash cannot carry another text, a forged manifest entry is not decoded, and APQ with trusted documents is refused. `FailingStore` moves to `test/persisted/support/`.

**Files** (verified commit `7dcff12` of the controller's scratch copy):

- Modify `packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart`
- Create `packages/typed_graphql_server/test/persisted/hostile_apq_test.dart`
- Create `packages/typed_graphql_server/test/persisted/hostile_trusted_documents_test.dart`
- Create `packages/typed_graphql_server/test/persisted/support/failing_store.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart b/packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart
index a66d4bf..2488406 100644
--- a/packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart
+++ b/packages/typed_graphql_server/test/persisted/automatic_persisted_queries_test.dart
@@ -1,10 +1,9 @@
-import 'dart:async';
-
 import 'package:test/test.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
 import '../server/support/server_fixture.dart';
+import 'support/failing_store.dart';
 
 void main() {
   final fixture = ServerFixture();
@@ -138,15 +137,3 @@ void main() {
     });
   });
 }
-
-/// A store whose every call fails, as a broken shared store would.
-final class FailingStore implements PersistedQueryStore {
-  const FailingStore();
-
-  @override
-  FutureOr<String?> read(String hash) => throw StateError('store is down');
-
-  @override
-  FutureOr<void> write(String hash, String text) =>
-      throw StateError('store is down');
-}
```

Create `packages/typed_graphql_server/test/persisted/hostile_apq_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/failing_store.dart';

// Automatic persisted queries under attack (R5.4, R5.14): a client must not
// make a hash serve another text, fill the store without bound, or reach
// validation with a hash the store does not hold.
void main() {
  final fixture = ServerFixture();
  const text = '{ hello }';
  final hash = fixture.hashOf(text);

  test('a text registered under another hash is never served', () async {
    final store = MemoryPersistedQueryStore();
    final server = fixture.server(persistedQueries: store);
    await server.handle(
      fixture.request('{ greet }', extensions: fixture.persisted(hash)),
    );
    final response = await server.handle(
      fixture.request(null, extensions: fixture.persisted(hash)),
    );
    expect(fixture.codeOf(response), 'GQL410');
  });

  test('a poisoned store entry is not run', () async {
    final store = MemoryPersistedQueryStore()..write(hash, '{ greet }');
    final response = await fixture
        .server(persistedQueries: store)
        .handle(fixture.request(null, extensions: fixture.persisted(hash)));
    expect(fixture.codeOf(response), 'GQL410');
  });

  test('a text with a syntax error is never stored', () async {
    const broken = '{ hello';
    final store = MemoryPersistedQueryStore();
    await fixture
        .server(persistedQueries: store)
        .handle(
          fixture.request(
            broken,
            extensions: fixture.persisted(fixture.hashOf(broken)),
          ),
        );
    expect(store.length, 0);
  });

  test('3000 registered texts keep the store at its capacity', () async {
    final store = MemoryPersistedQueryStore(capacity: 100);
    final server = fixture.server(persistedQueries: store);
    for (var index = 0; index < 3000; index++) {
      final query = '{ hello } # $index';
      await server.handle(
        fixture.request(
          query,
          extensions: fixture.persisted(fixture.hashOf(query)),
        ),
      );
    }
    expect(store.length, 100);
  });

  test('an unknown hash never reaches validation', () async {
    final rule = CountingRule();
    await fixture
        .server(
          persistedQueries: MemoryPersistedQueryStore(),
          validationRules: [rule, ...DocumentValidator.specifiedRules],
        )
        .handle(fixture.request(null, extensions: fixture.persisted(hash)));
    expect(rule.runs, 0);
  });

  test('a store failure is masked in production', () async {
    final response = await fixture
        .server(
          profile: ServerProfile.production,
          persistedQueries: const FailingStore(),
        )
        .handle(fixture.request(null, extensions: fixture.persisted(hash)));
    expect(fixture.messageOf(response), isNot(contains('store is down')));
  });

  group('a malformed extension is GQL413:', () {
    final cases = <String, JsonValue>{
      'a string': const JsonString('x'),
      'an array': JsonArray(const []),
      'version 2': JsonObject({
        'version': JsonNumber(2),
        'sha256Hash': JsonString(hash),
      }),
      'version as a string': JsonObject({
        'version': const JsonString('1'),
        'sha256Hash': JsonString(hash),
      }),
      'no version': JsonObject({'sha256Hash': JsonString(hash)}),
      'an upper-case hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString(hash.toUpperCase()),
      }),
      'a short hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString(hash.substring(1)),
      }),
      'a long hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonString('${hash}0'),
      }),
      'a numeric hash': JsonObject({
        'version': JsonNumber(1),
        'sha256Hash': JsonNumber(1),
      }),
      'no hash': JsonObject({'version': JsonNumber(1)}),
    };
    for (final MapEntry(key: label, value: extension) in cases.entries) {
      test(label, () async {
        final response = await fixture
            .server(persistedQueries: MemoryPersistedQueryStore())
            .handle(
              fixture.request(
                text,
                extensions: JsonObject({'persistedQuery': extension}),
              ),
            );
        expect(fixture.codeOf(response), 'GQL413');
      });
    }
  });
}
```

Create `packages/typed_graphql_server/test/persisted/hostile_trusted_documents_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';

// Trusted documents under attack (R5.4): only a trusted text runs, to the
// character, and nothing a client sends reaches the parser otherwise.
void main() {
  final fixture = ServerFixture();
  const text = '{hello}';
  final hash = fixture.hashOf(text);
  final trusted = TrustedDocuments({hash: text});

  (GraphQLServer<Ctx>, CountingRule) countedServer() {
    final rule = CountingRule();
    final server = fixture.server(
      trustedDocuments: trusted,
      validationRules: [rule, ...DocumentValidator.specifiedRules],
    );
    return (server, rule);
  }

  for (final variant in ['{ hello}', '{hello}\n', '{hello} # comment']) {
    test(
      'the variant ${jsonEncode(variant)} of a trusted text is refused',
      () async {
        final response = await fixture
            .server(trustedDocuments: trusted)
            .handle(fixture.request(variant));
        expect(fixture.codeOf(response), 'GQL414');
      },
    );
  }

  test('an untrusted text never reaches validation', () async {
    final (server, rule) = countedServer();
    await server.handle(fixture.request('{ greet }'));
    expect(rule.runs, 0);
  });

  test('an untrusted text is refused before it is parsed', () async {
    final response = await fixture
        .server(trustedDocuments: trusted)
        .handle(fixture.request('{ {{{ not graphql'));
    expect(fixture.codeOf(response), 'GQL414');
  });

  test('an unknown hash never reaches validation', () async {
    final (server, rule) = countedServer();
    await server.handle(
      fixture.request(null, extensions: fixture.persisted('0' * 64)),
    );
    expect(rule.runs, 0);
  });

  test('a trusted hash cannot carry an untrusted text', () async {
    final response = await fixture
        .server(trustedDocuments: trusted)
        .handle(
          fixture.request('{ greet }', extensions: fixture.persisted(hash)),
        );
    expect(fixture.codeOf(response), 'GQL411');
  });

  test('a manifest entry naming another body is not decoded', () {
    final forged = JsonObject({
      'format': const JsonString('apollo-persisted-query-manifest'),
      'version': JsonNumber(1),
      'operations': JsonArray([
        JsonObject({
          'id': JsonString(hash),
          'body': const JsonString('mutation { bump }'),
        }),
      ]),
    });
    expect(TrustedDocuments.decode(forged), isA<DecodeFailure>());
  });

  test('a server with a store and trusted documents is refused', () {
    expect(
      () => fixture.server(
        persistedQueries: MemoryPersistedQueryStore(),
        trustedDocuments: trusted,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

Create `packages/typed_graphql_server/test/persisted/support/failing_store.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A store whose every call fails, as a broken shared store would.
final class FailingStore implements PersistedQueryStore {
  const FailingStore();

  @override
  FutureOr<String?> read(String hash) => throw StateError('store is down');

  @override
  FutureOr<void> write(String hash, String text) =>
      throw StateError('store is down');
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: nothing fails: the tests cover behaviour Tasks 3 and 4 implement. Run them once and confirm they pass; a failure is a bug in an earlier task.

- [ ] **Step 3: Write the implementation.**

This commit changes only tests.

- [ ] **Step 4: Format, then run the green check.**

Format first (`/home/genius/fvm/versions/3.47.6/bin/dart format packages test`, wrapped as above), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )'
```

Expected: format changes 0 files, `No issues found!`, every suite passes.

- [ ] **Step 5: Commit.**

```sh
git add -A packages docs CLAUDE.md README.md llms.txt
git commit -m "test(typed_graphql_server): add the persisted document hostile-input tests

<your model trailer>"
```

### Task 6: docs: complete the persisted documents guide and the stage documents

**Why.** The stage documents of M6c: the full Persisted Documents guide (automatic persisted queries, the store, trusted documents from the manifest, the codes), every program run and its output pasted; the Server guide names the built-in order and the codes; the server README banner (M6 complete) and its guide list, `llms.txt`, two discovery rows, the root README, CLAUDE.md (status and the `persisted/` paragraph) and the HANDOFF row.

**Files** (verified commit `1909931` of the controller's scratch copy):

- Modify `CLAUDE.md`
- Modify `README.md`
- Modify `docs/discovery.md`
- Modify `docs/superpowers/HANDOFF.md`
- Modify `llms.txt`
- Modify `packages/typed_graphql_server/README.md`
- Modify `packages/typed_graphql_server/doc/persisted_documents.md`
- Modify `packages/typed_graphql_server/doc/server.md`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: nothing fails before the docs change; afterwards `test/doc` runs the three programs of `doc/persisted_documents.md` and compares their output.

- [ ] **Step 3: Write the implementation.**

Modify `CLAUDE.md` (exact diff):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 8296faf..83fc4ca 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -69,7 +69,11 @@ guide. M6b (request pipeline) delivers `GraphQLServer`, `RequestInfo`,
 `ServerExtension` and its three phases, `ServerProfile` and `ServerLimits`
 (length, tokens, depth, aliases, directives, cost per request), CSRF
 prevention, error masking and the error hook in the pipeline (`GQL400`-
-`GQL403`), the hostile-input tests and the Server guide. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+`GQL403`), the hostile-input tests and the Server guide. M6c (persisted
+documents) delivers automatic persisted queries (`PersistedQueryStore`,
+`MemoryPersistedQueryStore`), `TrustedDocuments` read from M10's manifest
+(`GQL410`-`GQL415`), their hostile-input tests and the Persisted Documents
+guide; with it stage M6 (server pipeline) is complete. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
 file or a URL, the project's documents as one fragment graph, the planner and
 emitters that generate the schema-types library and a library per document
 (operations, variables, data, fragments, sealed polymorphic classes, the
@@ -427,7 +431,8 @@ only through its barrel. One folder per concern, with no import order
 (`builder/` and `execution/` import each other): `builder/` (M5a),
 `coercion/`, `plan/` and `execution/` (M5b), `introspection/` and
 `subscription/` (M5c), `lookahead/`, `authorization/` and `cancellation/`
-(M5d), `dataloader/` (M6a) and `server/` (M6b). The package is
+(M5d), `dataloader/` (M6a), `server/` (M6b) and `persisted/` (M6c). The
+package is
 transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
 or web framework, only `dart:async`, `dart:collection`, `dart:convert`,
 `dart:core`, `dart:math`, `meta`, `crypto` and the core
@@ -532,6 +537,17 @@ runs the execution phase (`ExecutionStep`, options per profile).
 `PipelineErrors` makes every refusal and the masked `GQL330`;
 `GraphQLServer.handle` is the outermost catch, so it never throws.
 `dart:convert` and `crypto` are allowed in `lib/` for the hash.
+`persisted/` (M6c) and `server/` import each other: `PipelineAssembly`
+places one internal document-phase extension after CSRF, chosen once:
+`TrustedDocumentsCheck` with `trustedDocuments`, `AutomaticPersistedQueries`
+with `persistedQueries` (both together are an `ArgumentError`), else
+`PersistedQueriesUnsupported` (a hash alone is `GQL412`).
+`PersistedQueryReader` reads `extensions.persistedQuery` into the sealed
+`PersistedQueryReference` (`GQL413` when malformed). A hash always names its
+own text: a mismatch is `GQL411`, a text is stored only once the core step
+accepted it, a stored text is length-checked and hashed again on read (a
+mismatch is `GQL410`). `TrustedDocuments.decode` reads the manifest through
+`TrustedManifestReader`, which refuses an id that is not its body's hash.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
```

Modify `README.md` (exact diff):

````diff
diff --git a/README.md b/README.md
index edf1212..26cac76 100644
--- a/README.md
+++ b/README.md
@@ -30,7 +30,8 @@ scalar codecs and the diagnostics model; and, in `typed_graphql_server`, a
 typed schema builder, the execution of a validated operation, introspection,
 subscriptions, look-ahead at the requested fields, field authorization,
 cancellation, DataLoader and a transport-agnostic request pipeline
-(`GraphQLServer`: limits, the cost limit, CSRF prevention, extensions).
+(`GraphQLServer`: limits, the cost limit, CSRF prevention, extensions,
+automatic persisted queries and trusted documents).
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
@@ -113,7 +114,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader (M6a) and the request pipeline (M6b) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader, the request pipeline and persisted documents (M6, complete) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
````

Modify `docs/discovery.md` (exact diff):

```diff
diff --git a/docs/discovery.md b/docs/discovery.md
index cee6d08..3b0307e 100644
--- a/docs/discovery.md
+++ b/docs/discovery.md
@@ -47,6 +47,8 @@ adds its row (or turns it to "yes") together with its README line and its
 | cancel or time out a GraphQL request dart | M5 | yes |
 | dataloader dart graphql | M6 | yes |
 | GraphQL CSRF prevention dart | M6 | yes |
+| GraphQL persisted queries dart | M6 | yes |
+| GraphQL trusted documents dart | M6 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
 
```

Modify `docs/superpowers/HANDOFF.md` (exact diff):

```diff
diff --git a/docs/superpowers/HANDOFF.md b/docs/superpowers/HANDOFF.md
index cb98abb..ecb7cf5 100644
--- a/docs/superpowers/HANDOFF.md
+++ b/docs/superpowers/HANDOFF.md
@@ -22,6 +22,7 @@ db33dc7, 62ba263, cb78cf6, 8be71bd, 6981a03, 6c0dc4d, 383fa6a, f469521,
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
 | M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md); M5d: [plan](plans/2026-10-15-m5d-lookahead-authorization-cancellation.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; M5d is done on the same branch: `FieldInfo.selection` (look-ahead, `ColumnAllowlist`), `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`, `GQL352`), `CancelSignal`, `timeout` and `FieldInfo.cancelSignal` (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor benchmark, spec §18 items 34-44 and the Look-ahead, Authorization and Cancellation guides. **Stage M5 is complete and merged into `main` (f963761; not pushed).** The final opus whole-branch review and its fix round are done (a guarded subscription is authorized once, at `subscribe`, and `execute` on it runs the guard; coerced arguments are frozen). Open questions for the owner are spec §21, with recommendations in `docs/superpowers/specs/2026-10-15-m5-execution-design.md`. Next: M6 (server pipeline) |
+| M6 Server pipeline | [spec](specs/2026-10-15-m6-server-pipeline-design.md) | M6a: [plan](plans/2026-10-15-m6a-dataloader.md); M6b: [plan](plans/2026-10-15-m6b-request-pipeline.md); M6c: [plan](plans/2026-10-15-m6c-persisted-documents.md) | On branch `m6-final` (not merged, not pushed): M6a DataLoader (`BatchLoader`, `GroupedLoader`) and the DataLoader guide; M6b `GraphQLServer`, profiles and limits, the cost limit, CSRF prevention, the document cache, extensions (`GQL400`-`GQL403`), the hostile-input tests and the Server guide; M6c automatic persisted queries and trusted documents (`GQL410`-`GQL415`) and the Persisted Documents guide. Open questions for the owner are spec §17, with recommendations. Next: the final whole-branch review, then M7 (transports) |
 | M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete and merged into `main` (3d1fe38; not pushed): the final opus whole-branch review is done and its fix round is committed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
```

Modify `llms.txt` (exact diff):

```diff
diff --git a/llms.txt b/llms.txt
index 212a34d..5dd08ff 100644
--- a/llms.txt
+++ b/llms.txt
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking); persisted queries (rest of M6) and the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking) with automatic persisted queries or trusted documents; the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation, DataLoader and Server in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation, DataLoader (BatchLoader, GroupedLoader) and the request pipeline (GraphQLServer with limits, the cost limit, CSRF prevention and extensions) work; persisted queries (rest of M6) and transport handlers (M7) come later
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation, DataLoader, Server and Persisted Documents in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation, DataLoader (BatchLoader, GroupedLoader) and the request pipeline (GraphQLServer with limits, the cost limit, CSRF prevention, extensions, automatic persisted queries and trusted documents) work; transport handlers (M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

Modify `packages/typed_graphql_server/README.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/README.md b/packages/typed_graphql_server/README.md
index 28dbe7b..b013fd2 100644
--- a/packages/typed_graphql_server/README.md
+++ b/packages/typed_graphql_server/README.md
@@ -18,9 +18,10 @@
 > `GroupedLoader` batch and cache the loads of one request. The request
 > pipeline (M6b) works: `GraphQLServer` serves a transport-agnostic request
 > with a document cache, the limits and the cost limit of a production or
-> development profile, CSRF prevention, extensions and error masking.
-> Persisted queries come later in M6, the HTTP, graphql-ws and graphql-sse
-> handlers in M7. See the
+> development profile, CSRF prevention, extensions and error masking, and
+> with automatic persisted queries or trusted documents (M6c); with it stage
+> M6 is complete. The HTTP, graphql-ws and graphql-sse handlers come in M7.
+> See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
 ## Contents
@@ -151,6 +152,8 @@ executed
 - [Server](doc/server.md): `GraphQLServer`, requests, responses and outcomes,
   profiles, limits and the cost limit, CSRF prevention, the document cache,
   extensions, errors and masking.
+- [Persisted Documents](doc/persisted_documents.md): automatic persisted
+  queries and their store, trusted documents from the codegen manifest.
 - [Schema Builder](doc/schema_builder.md): refs, objects, fields, arguments,
   scalars, enums, input objects, interfaces and unions, building the schema.
 - [Execution](doc/execution.md): executing a request, variables, request errors
```

Modify `packages/typed_graphql_server/doc/persisted_documents.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/doc/persisted_documents.md b/packages/typed_graphql_server/doc/persisted_documents.md
index c5f6e10..42db7bc 100644
--- a/packages/typed_graphql_server/doc/persisted_documents.md
+++ b/packages/typed_graphql_server/doc/persisted_documents.md
@@ -1,10 +1,101 @@
 # Persisted Documents
 
-This guide describes the stores of automatic persisted queries; the server
-steps that use them come with the rest of the stage.
+A client may name a document by the SHA-256 of its text instead of sending
+the text (R5.4). `GraphQLServer` reads the name from
+`extensions.persistedQuery`, the shape Apollo clients send:
 
-`MemoryPersistedQueryStore` keeps the most recently used texts by their
-hash, evicting the least recently used one past its capacity.
+```text
+{"version": 1, "sha256Hash": "<64 lower-case hexadecimal digits>"}
+```
+
+The hash is the lower-case hexadecimal SHA-256 of the text's UTF-8 bytes.
+A server uses it in one of two ways, never both: automatic persisted
+queries, where clients register their texts at run time, or trusted
+documents, where the server runs only the texts it was given at build time.
+Without either, a request that sends only a hash is refused with `GQL412`
+and the message `PersistedQueryNotSupported`, which tells Apollo clients to
+send texts again; a request with a text runs as usual.
+
+## Automatic persisted queries
+
+`GraphQLServer(persistedQueries:)` takes a `PersistedQueryStore`. A client
+first sends only the hash. When the store does not hold it, the answer is
+`GQL410` with the message `PersistedQueryNotFound`, and the client sends the
+text with the hash; the server checks that the hash is the text's, runs it
+and stores it. From then on the hash alone is enough.
+
+```dart
+import 'dart:convert';
+
+import 'package:crypto/crypto.dart';
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
+  );
+  final server = GraphQLServer<Object?>(
+    schema: b.build(query: query),
+    contextFactory: (request) => null,
+    persistedQueries: MemoryPersistedQueryStore(),
+  );
+  const text = '{ hello }';
+  final hash = sha256.convert(utf8.encode(text)).toString();
+  final extensions = JsonObject({
+    'persistedQuery': JsonObject({
+      'version': JsonNumber(1),
+      'sha256Hash': JsonString(hash),
+    }),
+  });
+  Future<void> send(String? query) async {
+    final response = await server.handle(
+      ServerRequest(
+        params: GraphQLRequest(query: query, extensions: extensions),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: const {'content-type': 'application/json'},
+        ),
+      ),
+    );
+    if (response case SingleResponse(:final body)) print(body);
+  }
+
+  await send(null);
+  await send(text);
+  await send(null);
+}
+```
+
+It prints:
+
+```text
+{"errors":[{"message":"PersistedQueryNotFound","extensions":{"code":"GQL410"}}]}
+{"data":{"hello":"world"}}
+{"data":{"hello":"world"}}
+```
+
+A hash always names its own text, so no client can make it serve another
+document:
+
+- A text whose SHA-256 is not the hash is refused with `GQL411` ("provided
+  sha does not match query") and nothing is stored.
+- A text is stored only after it parsed and validated; a refused document
+  never enters the store.
+- A text read from the store is checked against the document length limit
+  and hashed again before it runs; a text that does not match its hash is
+  treated as missing (`GQL410`), so a shared store that was written by
+  someone else cannot change what a hash runs.
+- A malformed extension (not an object, a version other than `1`, a hash
+  that is not 64 lower-case hexadecimal digits) is `GQL413`. A JSON `null`
+  is no extension.
+
+`MemoryPersistedQueryStore` keeps the most recently used texts, 1000 by
+default, and evicts the least recently used one past its capacity, so
+clients that register many texts cannot grow it without bound.
 
 ```dart
 import 'package:typed_graphql_server/typed_graphql_server.dart';
@@ -24,3 +115,107 @@ It prints:
 null
 { b }
 ```
+
+A store shared by several servers (a database, a cache service)
+implements `PersistedQueryStore`; both of its methods may return a
+`Future`. An error a store throws is an unexpected error of the request:
+it goes to `onError` and is masked as `GQL330` by the profile.
+
+## Trusted documents
+
+`TrustedDocuments` holds the only documents a server runs, by their hash.
+A request names one by its hash alone, or sends its exact text; any other
+text is refused with `GQL414` before it is parsed, a change of whitespace
+included, and an unknown hash is `GQL415`. A text sent with a hash that is
+not its own is `GQL411`.
+
+`TrustedDocuments.decode` reads the persisted-operations manifest that
+`typed_graphql_codegen` writes for the client (`persisted_queries.json`,
+Apollo's `apollo-persisted-query-manifest` format), whose ids are the
+hashes of the minified texts the generated operations send.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+const manifest = '''
+{
+  "format": "apollo-persisted-query-manifest",
+  "version": 1,
+  "operations": [
+    {
+      "id": "9dd7ff987fac8d0d1979084ebde5ce8bd855cd066d1a34e98432275cc6bc264c",
+      "name": "",
+      "type": "query",
+      "body": "{hello}"
+    }
+  ]
+}
+''';
+
+Future<void> main() async {
+  final decoded = switch (const JsonReader().parse(manifest)) {
+    DecodeSuccess(:final value) => TrustedDocuments.decode(value),
+    final DecodeFailure failure => failure,
+  };
+  // A broken manifest is a deployment error: the server must not start.
+  final trusted = switch (decoded) {
+    DecodeSuccess(:final value) => value,
+    DecodeFailure() => throw StateError('Bad manifest: $decoded'),
+  };
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
+  );
+  final server = GraphQLServer<Object?>(
+    schema: b.build(query: query),
+    contextFactory: (request) => null,
+    trustedDocuments: trusted,
+  );
+  for (final text in ['{hello}', '{ hello }']) {
+    final response = await server.handle(
+      ServerRequest(
+        params: GraphQLRequest(query: text),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: const {'content-type': 'application/json'},
+        ),
+      ),
+    );
+    if (response case SingleResponse(:final body)) print(body);
+  }
+}
+```
+
+It prints:
+
+```text
+{"data":{"hello":"world"}}
+{"errors":[{"message":"Only trusted documents are allowed.","extensions":{"code":"GQL414"}}]}
+```
+
+A manifest entry whose id is not the hash of its body is a `DecodeFailure`
+with its path, such as `$.operations[0].id: expected the SHA-256 of the
+body`, so an edited manifest cannot make a trusted hash run another text.
+`TrustedDocuments(map)` builds the set from ids and texts in another format;
+there a wrong id is an `ArgumentError`.
+
+Trusted documents and automatic persisted queries together are an
+`ArgumentError`: a store would let any client register a new document,
+which is what trusted documents forbid.
+
+## Diagnostic codes
+
+| Code | When |
+|---|---|
+| `GQL410` | A hash the store does not hold, or whose stored text does not match it (`PersistedQueryNotFound`). |
+| `GQL411` | A text sent with a hash that is not its SHA-256. |
+| `GQL412` | A hash without a text, on a server with neither a store nor trusted documents (`PersistedQueryNotSupported`). |
+| `GQL413` | A malformed `extensions.persistedQuery`. |
+| `GQL414` | A text that is not a trusted document. |
+| `GQL415` | A hash that names no trusted document. |
+
+Each is a request error: the response has no `data`, the context is not
+built and no resolver runs.
````

Modify `packages/typed_graphql_server/doc/server.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/doc/server.md b/packages/typed_graphql_server/doc/server.md
index 2deed47..440f804 100644
--- a/packages/typed_graphql_server/doc/server.md
+++ b/packages/typed_graphql_server/doc/server.md
@@ -385,8 +385,10 @@ back.
 
 The first extension in `extensions` is the outermost: it sees every
 request, refused ones included. The built-in checks sit inside the user's
-extensions in a fixed order, so no list order runs a step before a security
-check. Per-field interception is field middleware, set when the schema is
+extensions in a fixed order (CSRF prevention, then persisted documents: see
+the Persisted Documents guide), so no list order runs a step before a
+security check, and a user's `onDocument` sees the text a hash names only
+after it returns from `next`. Per-field interception is field middleware, set when the schema is
 built (see the Execution guide).
 
 ```dart
@@ -529,7 +531,8 @@ internalError {"errors":[{"message":"Unexpected error.","extensions":{"code":"GQ
 | `GQL402` | a mutation in a `GET` request |
 | `GQL403` | CSRF prevention refused the request |
 | `GQL238` | the operation costs more than `maxCost` with the request's variables |
-| `GQL330` | an unexpected error of the context factory or an extension |
+| `GQL330` | an unexpected error of the context factory, an extension or a persisted query store |
+| `GQL410`-`GQL415` | a persisted query or trusted document problem (Persisted Documents guide) |
 
 The parser's `GQL0xx`, the validator's `GQL2xx` and the executor's `GQL3xx`
 codes reach the client unchanged.
````

- [ ] **Step 4: Format, then run the green check.**

Format first (`/home/genius/fvm/versions/3.47.6/bin/dart format packages test`, wrapped as above), then:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 /home/genius/fvm/versions/3.47.6/bin/dart format --output=none --set-exit-if-changed packages test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart analyze --fatal-infos )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 dart test )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )'
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart doc --dry-run" )'
```

Expected: format changes 0 files, `No issues found!`, every suite passes, `dart doc` reports "Found 0 warnings and 0 errors".

- [ ] **Step 5: Commit.**

```sh
git add -A packages docs CLAUDE.md README.md llms.txt
git commit -m "docs: complete the persisted documents guide and the stage documents

<your model trailer>"
```

## Verification

After Task 6, run the green check once more, then the stage checks:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart test --compiler exe" )' 2>&1 | tail -5
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test --compiler exe" )' 2>&1 | tail -5
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart doc --dry-run" )' 2>&1 | tail -3
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart pub publish --dry-run" )' 2>&1 | tail -5
```

In the scratch copy, after Task 6:

- the root suite passed 353 tests;
- the server suite passed 1155 tests;
- the core suite passed 1514 tests;
- `dart doc` for the server reported 0 warnings and 0 errors.

The `--compiler exe` runs and `pub publish --dry-run` were not run there; they belong to the final whole-branch review. Chrome runs (dart2js, dart2wasm) are left to CI.
