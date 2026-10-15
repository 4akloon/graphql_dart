# M6b Request Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the second part of stage M6 of `typed_graphql_server`: the request pipeline. `GraphQLServer.handle` turns a `ServerRequest` into a `ServerResponse` and never throws (R0.3): document length check, a bounded document cache, operation lookup, `GQL402` for a mutation over GET, the context factory, CSRF prevention, the cost limit, execution or subscription with the options of a `ServerProfile`, and `ServerExtension` hooks around the request, document and execution phases. It also adds the request-pipeline diagnostic codes to the core catalog and the server guide.

**Architecture:** The values (`ServerRequest`, `ServerResponse`, `ServerOutcome`, `RequestInfo`, `ContextFactory`) and the configuration (`ServerProfile`, `ServerLimits`, `CsrfPrevention`) are plain const or immutable classes in `lib/src/server/`. `GraphQLServer` is a thin face over `PipelineAssembly`, which composes the extension chains once at construction: CSRF prevention is an internal extension inside the user's, so their hooks see its refusal. Each phase is a small handler (`RequestHandler`, `DocumentHandler`, `ExecutionHandler`) over a request object. The document phase compiles a text once (`DocumentCompiler`: parse, validate, pick the operation) and `DocumentCache` stores the `DocumentResult`, keyed by `DocumentHash`. Errors become responses through `PipelineErrors` and `DiagnosticErrors`; an unexpected error is masked with the message shared with the executor.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5), `package:test`, `package:meta`; the server package gains the dependencies its pubspec diff in Task 2 shows.

**Spec:** `docs/superpowers/specs/2026-10-15-m6-server-pipeline-design.md` (sections 3-10, 12 and 14), `docs/requirements.md`.

**Base:** `0f202a3` (the tree after the M6a DataLoader plan). This plan is generated from the commits that implemented it, in order: `c5c6bab`, `ec8f132`, `231c52b`, `5227b02`, `4312ebb`, `512daf6`, `0d720f7`, `ac71c1b`, `5a1b8d8`, `62173b7`. Tasks 1-10 are done on `m6-final`. Tasks 11-13 remain: the controller wrote and verified them in a scratch copy (see "Tasks 11-13" below). Each task reproduces one commit; the fix commits (Tasks 4, 6, 9) answer reviews of the tasks before them and stay separate tasks because the files evolved between commits.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, never catch `Error`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and the server suite green (Task 1 also the core suite).
- **Memory and time limits.** Run every `dart` command as `flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 <cmd> )'`: one heavy Dart process at a time, no Chrome runs, filter the output with `| tail`.
- Format with the newer SDK (3.13.1's formatter crashes): `/home/genius/fvm/versions/3.47.6/bin/dart format packages test`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the subject given in the task and a trailer naming the real model of the implementer (for example `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`).
- Run every command from the repository root unless a step says otherwise.
- Changes to existing files are unified diffs against the tree the earlier tasks leave. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- Tests never read git-ignored or untracked files.
- Bad input never throws (R0.3): `GraphQLServer.handle` turns every failure, an unexpected exception included, into a `ServerResponse`.

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 2, 3, 5, 6, 7, 8 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 2 |
| `packages/typed_graphql_server/doc/server.md` | Create/Modify | 2, 4 |
| `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart` | Modify | 6 |
| `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart` | Modify | 6 |
| `packages/typed_graphql_server/lib/src/execution/error_reporter.dart` | Modify | 6 |
| `packages/typed_graphql_server/lib/src/execution/masked_message.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/server/context_factory.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/server/cost_limit.dart` | Create | 8 |
| `packages/typed_graphql_server/lib/src/server/cost_message.dart` | Create | 8 |
| `packages/typed_graphql_server/lib/src/server/csrf_extension.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/csrf_prevention.dart` | Create/Modify | 3, 4 |
| `packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart` | Create/Modify | 2, 4 |
| `packages/typed_graphql_server/lib/src/server/document_cache.dart` | Create/Modify | 2, 4, 7 |
| `packages/typed_graphql_server/lib/src/server/document_compiler.dart` | Create/Modify | 2, 4, 7, 9 |
| `packages/typed_graphql_server/lib/src/server/document_entry.dart` | Create/Delete | 2, 7 |
| `packages/typed_graphql_server/lib/src/server/document_handler.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/document_hash.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/server/document_length.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/document_request.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/document_result.dart` | Create/Modify | 7, 9 |
| `packages/typed_graphql_server/lib/src/server/document_step.dart` | Create/Modify | 5, 7 |
| `packages/typed_graphql_server/lib/src/server/execution_handler.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/execution_job.dart` | Create/Delete | 5, 7 |
| `packages/typed_graphql_server/lib/src/server/execution_request.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/execution_step.dart` | Create/Modify | 5, 7 |
| `packages/typed_graphql_server/lib/src/server/extension_chain.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/graphql_server.dart` | Create/Modify | 5, 6, 7, 8, 9 |
| `packages/typed_graphql_server/lib/src/server/header_names.dart` | Create/Modify | 2, 4 |
| `packages/typed_graphql_server/lib/src/server/operation_lookup.dart` | Create/Modify | 5, 8 |
| `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart` | Create | 9 |
| `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart` | Create/Modify | 5, 6, 7, 9 |
| `packages/typed_graphql_server/lib/src/server/request_handler.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/request_info.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/server/request_step.dart` | Create/Modify | 5, 7, 8 |
| `packages/typed_graphql_server/lib/src/server/server_extension.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/server/server_limits.dart` | Create/Modify | 3, 4 |
| `packages/typed_graphql_server/lib/src/server/server_outcome.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/server/server_profile.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/server/server_request.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/server/server_response.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 2, 3, 5, 7 |
| `packages/typed_graphql_server/pubspec.yaml` | Modify | 2 |
| `packages/typed_graphql_server/test/dataloader/request_scope_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/quality/import_rule.dart` | Modify | 2 |
| `packages/typed_graphql_server/test/quality/imports_test.dart` | Modify | 2, 4 |
| `packages/typed_graphql_server/test/server/csrf_prevention_test.dart` | Create/Modify | 3, 4 |
| `packages/typed_graphql_server/test/server/diagnostic_errors_test.dart` | Create | 4 |
| `packages/typed_graphql_server/test/server/document_cache_test.dart` | Create/Modify | 2, 7 |
| `packages/typed_graphql_server/test/server/document_compiler_test.dart` | Create/Modify | 2, 7, 9 |
| `packages/typed_graphql_server/test/server/graphql_server_profile_test.dart` | Create | 5 |
| `packages/typed_graphql_server/test/server/graphql_server_test.dart` | Create/Modify | 5, 6 |
| `packages/typed_graphql_server/test/server/hostile_csrf_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/server/hostile_document_cache_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/server/hostile_limits_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/server/hostile_masking_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/server/server_cost_test.dart` | Create | 8 |
| `packages/typed_graphql_server/test/server/server_csrf_test.dart` | Create/Modify | 7, 9 |
| `packages/typed_graphql_server/test/server/server_execute_hooks_test.dart` | Create/Modify | 7, 9 |
| `packages/typed_graphql_server/test/server/server_extension_test.dart` | Create/Modify | 7, 9 |
| `packages/typed_graphql_server/test/server/server_profile_test.dart` | Create/Modify | 3, 4 |
| `packages/typed_graphql_server/test/server/server_values_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/server/support/compiler_fixture.dart` | Create/Modify | 2, 7 |
| `packages/typed_graphql_server/test/server/support/cost_fixture.dart` | Create | 8 |
| `packages/typed_graphql_server/test/server/support/hook_extension.dart` | Create | 7 |
| `packages/typed_graphql_server/test/server/support/hostile_fixture.dart` | Create | 10 |
| `packages/typed_graphql_server/test/server/support/recording_extension.dart` | Create | 7 |
| `packages/typed_graphql_server/test/server/support/server_fixture.dart` | Create/Modify | 5, 6, 7 |

### Task 1: feat(typed_graphql): add the request pipeline diagnostic codes

**Why.** Adds the diagnostic codes the request pipeline reports (`GQL400`-`GQL403`: `queryRequired`, `documentTooLong`, `mutationRequiresPost`, `csrfRequestBlocked`) to the core catalog, in id order with a doc comment each, in the commit that first needs them (CLAUDE.md, Design rules). Nothing reports them yet; the server tasks that follow do. The core changelog lists them.

**Files** (commit `c5c6bab`):

- Modify `packages/typed_graphql/CHANGELOG.md`
- Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart test" )' 2>&1 | tail -30
```

Expected: Nothing fails: the commit adds catalog entries and no test file. Its check is the core suite, which verifies that ids are unique, in order and documented.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql/CHANGELOG.md b/packages/typed_graphql/CHANGELOG.md
index 5b08b6d..8b92fca 100644
--- a/packages/typed_graphql/CHANGELOG.md
+++ b/packages/typed_graphql/CHANGELOG.md
@@ -285,3 +285,6 @@
   code uses).
 - The catalog adds `GQL511` (an operation or fragment that would generate
   too many classes).
+- `DiagnosticCode`: `GQL400`-`GQL403` (`queryRequired`, `documentTooLong`,
+  `mutationRequiresPost`, `csrfRequestBlocked`), reported by the server's
+  request pipeline.
```

Modify `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
index f953e0c..1a300de 100644
--- a/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
+++ b/packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
@@ -508,7 +508,8 @@ enum DiagnosticCode(
   slicingArgumentsRequired('GQL237'),
 
   /// `GQL238`: an operation whose field cost or type cost is more than the
-  /// maximum `MaxCostRule` allows.
+  /// maximum `MaxCostRule` allows. `GraphQLServer` also reports it, once per
+  /// request, with the request's variables.
   maxCostExceeded('GQL238'),
 
   /// `GQL300`: an object type or an interface type built with
@@ -589,7 +590,9 @@ enum DiagnosticCode(
   /// `GQL330`: reported when a resolver, codec or decode function threw
   /// an unexpected error; the message is masked. It is a
   /// `GraphQLError`'s `extensions.code` in a response of
-  /// `ExecutableSchema.execute`.
+  /// `ExecutableSchema.execute`. `GraphQLServer` also reports it for an
+  /// unexpected error of its own pipeline (the context factory, an extension
+  /// or a store).
   unexpectedError('GQL330'),
 
   /// `GQL331`: reported when a resolver returned null for a non-null
@@ -655,6 +658,28 @@ enum DiagnosticCode(
   /// `ExecutableSchema.execute`.
   notAuthorized('GQL352'),
 
+  /// `GQL400`: reported when a request has no document text and no persisted
+  /// document resolved one ("Must provide query string."). It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `GraphQLServer.handle`.
+  queryRequired('GQL400'),
+
+  /// `GQL401`: reported when the document text is longer than the server's
+  /// `maxDocumentLength`; it is refused before it is hashed or parsed. It is
+  /// a `GraphQLError`'s `extensions.code` in a response of
+  /// `GraphQLServer.handle`.
+  documentTooLong('GQL401'),
+
+  /// `GQL402`: reported when a `GET` request selects a mutation; only a
+  /// `POST` request may run one. It is a `GraphQLError`'s `extensions.code`
+  /// in a response of `GraphQLServer.handle`.
+  mutationRequiresPost('GQL402'),
+
+  /// `GQL403`: reported when CSRF prevention refused the request. It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `GraphQLServer.handle`.
+  csrfRequestBlocked('GQL403'),
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
git add -A packages
git commit -m "feat(typed_graphql): add the request pipeline diagnostic codes

<your model trailer>"
```

### Task 2: feat(typed_graphql_server): add the server request values and document cache

**Why.** Adds the plain values the pipeline passes around (spec sections 3 and 4): `ServerRequest`, `ServerResponse`, `ServerOutcome`, `RequestInfo`, `ContextFactory`, `HeaderNames`, and the document side: `DocumentHash`, `DocumentCompiler` (parse, validate and pick the operation once per text), `DocumentCache` (a bounded cache of compiled documents keyed by the text hash), `DiagnosticErrors` (diagnostics to response errors). It also adds the server guide `doc/server.md`, its dartdoc category, the pubspec dependencies and the import-rule updates that let `lib/src/server` import what it needs.

**Files** (commit `ec8f132`):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/dartdoc_options.yaml`
- Create `packages/typed_graphql_server/doc/server.md`
- Create `packages/typed_graphql_server/lib/src/server/context_factory.dart`
- Create `packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_cache.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_compiler.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_entry.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_hash.dart`
- Create `packages/typed_graphql_server/lib/src/server/header_names.dart`
- Create `packages/typed_graphql_server/lib/src/server/request_info.dart`
- Create `packages/typed_graphql_server/lib/src/server/server_outcome.dart`
- Create `packages/typed_graphql_server/lib/src/server/server_request.dart`
- Create `packages/typed_graphql_server/lib/src/server/server_response.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Modify `packages/typed_graphql_server/pubspec.yaml`
- Modify `packages/typed_graphql_server/test/quality/import_rule.dart`
- Modify `packages/typed_graphql_server/test/quality/imports_test.dart`
- Create `packages/typed_graphql_server/test/server/document_cache_test.dart`
- Create `packages/typed_graphql_server/test/server/document_compiler_test.dart`
- Create `packages/typed_graphql_server/test/server/server_values_test.dart`
- Create `packages/typed_graphql_server/test/server/support/compiler_fixture.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/quality/import_rule.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/quality/import_rule.dart b/packages/typed_graphql_server/test/quality/import_rule.dart
index eaba944..d474259 100644
--- a/packages/typed_graphql_server/test/quality/import_rule.dart
+++ b/packages/typed_graphql_server/test/quality/import_rule.dart
@@ -2,8 +2,9 @@
 /// one library under `lib/`.
 ///
 /// The server runs on the VM, AOT, dart2js and dart2wasm, so it imports pure
-/// Dart, `meta`, the core's barrel and its own files, never `src/` of the
-/// core and never a web framework.
+/// Dart, `dart:convert`, `meta`, `package:crypto/crypto.dart` (SHA-256 of
+/// documents), the core's barrel and its own files, never `src/` of the core
+/// and never a web framework.
 final class ImportRule {
   /// Creates the rule.
   const ImportRule();
@@ -12,10 +13,13 @@ final class ImportRule {
   static const Set<String> _pureDart = {
     'dart:async',
     'dart:collection',
+    'dart:convert',
     'dart:core',
     'dart:math',
   };
 
+  static const String _crypto = 'package:crypto/crypto.dart';
+
   static const String _coreBarrel = 'package:typed_graphql/typed_graphql.dart';
 
   static final RegExp _directive = RegExp(
@@ -35,12 +39,14 @@ final class ImportRule {
           ? null
           : '$filePath imports $target: the server is platform independent';
     }
-    if (target.startsWith('package:meta/') || target == _coreBarrel) {
+    if (target.startsWith('package:meta/') ||
+        target == _coreBarrel ||
+        target == _crypto) {
       return null;
     }
     if (target.startsWith('package:')) {
-      return '$filePath imports $target: only meta and the core barrel '
-          '($_coreBarrel) are allowed';
+      return '$filePath imports $target: only meta, crypto and the core '
+          'barrel ($_coreBarrel) are allowed';
     }
     return null;
   }
```

Modify `packages/typed_graphql_server/test/quality/imports_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/quality/imports_test.dart b/packages/typed_graphql_server/test/quality/imports_test.dart
index 960b9a7..7cf610b 100644
--- a/packages/typed_graphql_server/test/quality/imports_test.dart
+++ b/packages/typed_graphql_server/test/quality/imports_test.dart
@@ -25,6 +25,27 @@ void main() {
       );
     });
 
+    test('allows dart:convert and package:crypto/crypto.dart', () {
+      expect(
+        rule.check(
+          'lib/src/server/a.dart',
+          "import 'dart:convert';\n"
+              "import 'package:crypto/crypto.dart';\n",
+        ),
+        isEmpty,
+      );
+    });
+
+    test('rejects another crypto library', () {
+      expect(
+        rule.check(
+          'lib/src/server/a.dart',
+          "import 'package:crypto/src/sha256.dart';\n",
+        ),
+        hasLength(1),
+      );
+    });
+
     test('rejects dart:io', () {
       expect(
         rule.check('lib/src/builder/a.dart', "import 'dart:io';\n"),
```

Create `packages/typed_graphql_server/test/server/document_cache_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/src/server/document_cache.dart';
import 'package:typed_graphql_server/src/server/document_entry.dart';
import 'package:typed_graphql_server/src/server/document_hash.dart';

import 'support/compiler_fixture.dart';

void main() {
  const fixture = CompilerFixture();

  group('DocumentHash', () {
    test('is the lower-case hex SHA-256 of the UTF-8 bytes', () {
      expect(
        const DocumentHash().of('{a}'),
        '460c3a93211614ac783c0f1d1bbbcb45a6da87d6421b5c0771772588f1015ff8',
      );
    });

    test('hashes bytes, not code units', () {
      expect(
        const DocumentHash().of('{a} # é'),
        isNot(const DocumentHash().of('{a} # e')),
      );
    });
  });

  group('DocumentCache', () {
    test('returns the same accepted entry for the same text', () {
      final cache = DocumentCache(10);
      final compiler = fixture.countingCompiler;
      final first = cache.entryFor('{a}', compiler);
      final second = cache.entryFor('{a}', compiler);
      expect(second, same(first));
      expect(compiler.calls, 1);
    });

    test('the accepted entry holds one ValidDocument for the text', () {
      final cache = DocumentCache(10);
      final compiler = fixture.compiler;
      final first = cache.entryFor('{a}', compiler) as AcceptedEntry;
      final second = cache.entryFor('{a}', compiler) as AcceptedEntry;
      expect(second.document, same(first.document));
    });

    test('the entry carries the hash of the text', () {
      final entry = DocumentCache(10).entryFor('{a}', fixture.compiler);
      expect(entry.hash, const DocumentHash().of('{a}'));
    });

    test('compiles a failure once', () {
      final cache = DocumentCache(10);
      final compiler = fixture.countingCompiler;
      final first = cache.entryFor('{', compiler);
      final second = cache.entryFor('{', compiler);
      expect(second, same(first));
      expect(compiler.calls, 1);
    });

    test('evicts the least recently used entry', () {
      final cache = DocumentCache(2);
      final compiler = fixture.countingCompiler;
      cache
        ..entryFor('{a}', compiler)
        ..entryFor('{ a }', compiler)
        ..entryFor('{  a }', compiler);
      expect(cache.length, 2);
      cache.entryFor('{a}', compiler);
      expect(compiler.calls, 4);
    });

    test('a hit makes the entry the most recent', () {
      final cache = DocumentCache(2);
      final compiler = fixture.countingCompiler;
      cache
        ..entryFor('{a}', compiler)
        ..entryFor('{ a }', compiler)
        ..entryFor('{a}', compiler)
        ..entryFor('{  a }', compiler);
      expect(compiler.calls, 3);
      cache.entryFor('{a}', compiler);
      expect(compiler.calls, 3);
      cache.entryFor('{ a }', compiler);
      expect(compiler.calls, 4);
    });

    test('capacity 0 never stores', () {
      final cache = DocumentCache(0);
      final compiler = fixture.countingCompiler;
      cache
        ..entryFor('{a}', compiler)
        ..entryFor('{a}', compiler);
      expect(compiler.calls, 2);
      expect(cache.length, 0);
    });

    test('a negative capacity is an ArgumentError', () {
      expect(() => DocumentCache(-1), throwsArgumentError);
    });
  });
}
```

Create `packages/typed_graphql_server/test/server/document_compiler_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/server/document_entry.dart';

import 'support/compiler_fixture.dart';

void main() {
  final compiler = const CompilerFixture().compiler;

  List<GraphQLError> errorsOf(String text) => switch (compiler.compile(
    text,
    'hash',
  )) {
    RejectedEntry(:final errors) => errors,
    AcceptedEntry() => throw StateError('expected a rejection'),
  };

  test('a valid text is accepted with its source', () {
    final entry = compiler.compile('{ a }', 'hash');
    expect(entry, isA<AcceptedEntry>());
    expect((entry as AcceptedEntry).source.body, '{ a }');
  });

  test('the entry keeps the hash it was given', () {
    expect(compiler.compile('{ a }', 'the-hash').hash, 'the-hash');
  });

  test('a syntax error becomes an error with its code and location', () {
    expect(errorsOf('{ a'), [
      GraphQLError(
        'Expected Name, found <EOF>.',
        locations: [const SourceLocation(1, 4)],
        extensions: JsonObject({'code': const JsonString('GQL007')}),
      ),
    ]);
  });

  test('a validation error becomes an error with its code and location', () {
    expect(errorsOf('{ b }'), [
      GraphQLError(
        'Cannot query field "b" on type "Query". Did you mean "a"?',
        locations: [const SourceLocation(1, 3)],
        extensions: JsonObject({'code': const JsonString('GQL205')}),
      ),
    ]);
  });
}
```

Create `packages/typed_graphql_server/test/server/server_values_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('RequestInfo', () {
    final info = RequestInfo(
      method: 'POST',
      uri: Uri.parse('http://localhost/graphql'),
      headers: {'Content-Type': 'application/json', 'X-Token': 'a'},
    );

    test('lower-cases the header names', () {
      expect(info.headers.keys, ['content-type', 'x-token']);
    });

    test('finds a header by any case', () {
      expect(info.header('CONTENT-type'), 'application/json');
    });

    test('a missing header is null', () {
      expect(info.header('accept'), isNull);
    });

    test('the headers are unmodifiable', () {
      expect(() => info.headers['a'] = 'b', throwsUnsupportedError);
    });

    test('keeps the method as given', () {
      expect(RequestInfo(method: 'get', uri: Uri()).method, 'get');
    });
  });

  group('SingleResponse', () {
    final payload = ExecutionResult(JsonObject({'a': JsonNumber(1)}));

    test('the body is the payload written', () {
      expect(SingleResponse(payload).body, payload.toJson());
    });

    test('lower-cases the header names', () {
      expect(
        SingleResponse(payload, headers: {'Allow': 'POST'}).headers,
        {'allow': 'POST'},
      );
    });

    test('the headers are unmodifiable', () {
      expect(
        () => SingleResponse(payload).headers['a'] = 'b',
        throwsUnsupportedError,
      );
    });

    test('withHeaders merges, lower-cases and lets new values win', () {
      final response = SingleResponse(
        payload,
        outcome: ServerOutcome.methodNotAllowed,
        headers: {'allow': 'GET', 'x-a': '1'},
      ).withHeaders({'Allow': 'POST', 'X-B': '2'});
      expect(response.headers, {'allow': 'POST', 'x-a': '1', 'x-b': '2'});
    });

    test('withHeaders keeps the subclass, payload and outcome', () {
      final ServerResponse response = SingleResponse(
        payload,
        outcome: ServerOutcome.requestError,
      ).withHeaders({'a': 'b'});
      expect(response, isA<SingleResponse>());
      expect((response as SingleResponse).payload, same(payload));
      expect(response.outcome, ServerOutcome.requestError);
    });
  });

  group('StreamResponse', () {
    const results = Stream<ExecutionResult>.empty();

    test('its outcome is executed', () {
      expect(StreamResponse(results).outcome, ServerOutcome.executed);
    });

    test('withHeaders keeps the subclass and the stream', () {
      final ServerResponse response = StreamResponse(
        results,
      ).withHeaders({'X-A': '1'});
      expect(response, isA<StreamResponse>());
      expect((response as StreamResponse).results, same(results));
      expect(response.headers, {'x-a': '1'});
    });
  });

  test('ServerRequest holds the parameters, info and signal', () {
    final signal = CancelSignal();
    final info = RequestInfo(method: 'GET', uri: Uri());
    const params = GraphQLRequest(query: '{a}');
    final request = ServerRequest(
      params: params,
      info: info,
      cancelSignal: signal,
    );
    expect(request.params, same(params));
    expect(request.info, same(info));
    expect(request.cancelSignal, same(signal));
  });
}
```

Create `packages/typed_graphql_server/test/server/support/compiler_fixture.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/server/document_compiler.dart';
import 'package:typed_graphql_server/src/server/document_entry.dart';

/// A small valid schema and compilers over it.
final class CompilerFixture {
  const CompilerFixture();

  ValidSchema get schema {
    final source = Source('type Query { a: Int }');
    final document = const Parser().parse(source).requireDocument();
    final built = const SchemaBuilder().fromSdl(document, source: source);
    return switch (built) {
      BuildSuccess(:final schema) =>
        const SchemaValidator().validate(schema) as ValidSchema,
      BuildFailure() => throw StateError('the fixture schema must build'),
    };
  }

  DocumentCompiler get compiler =>
      DocumentCompiler(const Parser(), const DocumentValidator(), schema);

  /// A compiler that counts its calls.
  CountingCompiler get countingCompiler => CountingCompiler(compiler);
}

final class CountingCompiler extends DocumentCompiler {
  CountingCompiler(DocumentCompiler inner)
    : super(inner.parser, inner.validator, inner.schema);

  int calls = 0;

  @override
  DocumentEntry compile(String text, String hash) {
    calls++;
    return super.compile(text, hash);
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The new test files import types that do not exist yet, so `dart test` in `packages/typed_graphql_server` fails to compile (`Undefined class` / `Target of URI doesn't exist`).

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index f2e5e76..882060f 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -146,3 +146,6 @@
 - `GroupedLoader` loads the list of children of a key (posts by author id) in
   one batch, with the cache and failure behaviour of `BatchLoader`; a missing
   key is an empty list and the lists it hands out are unmodifiable.
+- `RequestInfo`, `ServerRequest`, `ServerResponse` (`SingleResponse`,
+  `StreamResponse`), `ServerOutcome` and `ContextFactory`: the values the
+  request pipeline takes and returns. Header names are lower-case.
```

Modify `packages/typed_graphql_server/dartdoc_options.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/dartdoc_options.yaml b/packages/typed_graphql_server/dartdoc_options.yaml
index c9e5968..6c8d68e 100644
--- a/packages/typed_graphql_server/dartdoc_options.yaml
+++ b/packages/typed_graphql_server/dartdoc_options.yaml
@@ -21,6 +21,9 @@ dartdoc:
     lookahead:
       markdown: doc/lookahead.md
       displayName: Look-ahead
+    server:
+      markdown: doc/server.md
+      displayName: Server
     subscription:
       markdown: doc/subscriptions.md
       displayName: Subscriptions
@@ -32,5 +35,6 @@ dartdoc:
     - execution
     - introspection
     - lookahead
+    - server
     - subscription
   showUndocumentedCategories: true
```

Create `packages/typed_graphql_server/doc/server.md`:

````markdown
# Server

A transport hands the server a `ServerRequest` and gets a `ServerResponse`
back. This guide grows with the request pipeline; for now it describes the
values on both sides.

`RequestInfo` holds the method, the URI and the headers of a request. Header
names are lower-cased when it is made, and `header` finds one by any case.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final info = RequestInfo(
    method: 'POST',
    uri: Uri.parse('http://localhost/graphql'),
    headers: {'Content-Type': 'application/json'},
  );
  print(info.headers.keys.join(', '));
  print(info.header('CONTENT-TYPE'));
}
```

It prints:

```text
content-type
application/json
```
````

Create `packages/typed_graphql_server/lib/src/server/context_factory.dart`:

```dart
import 'dart:async';

import 'request_info.dart';

/// Builds the context of one executed request.
///
/// It runs once per executed request, after the document is accepted and
/// every limit has passed, so a refused request never builds a context.
///
/// {@category server}
typedef ContextFactory<C> = FutureOr<C> Function(RequestInfo request);
```

Create `packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Turns the diagnostics of the core into the errors of a response.
@internal
final class DiagnosticErrors {
  /// Creates the converter.
  const DiagnosticErrors();

  /// One error for each error diagnostic in [diagnostics], in order: the
  /// message, the place and the related places as `locations`, and the
  /// diagnostic's id as `extensions.code`.
  List<GraphQLError> of(List<Diagnostic> diagnostics) => [
    for (final diagnostic in diagnostics)
      if (diagnostic.isError)
        GraphQLError(
          diagnostic.message,
          locations: diagnostic.locations,
          extensions: JsonObject({'code': JsonString(diagnostic.code.id)}),
        ),
  ];
}
```

Create `packages/typed_graphql_server/lib/src/server/document_cache.dart`:

```dart
import 'dart:collection';

import 'package:meta/meta.dart';

import 'document_compiler.dart';
import 'document_entry.dart';
import 'document_hash.dart';

/// A least-recently-used cache of compiled documents, keyed by the SHA-256 of
/// the text (R5.2).
///
/// The key is computed here from the text, never taken from a client, so a
/// client-sent hash cannot poison the cache. Failures are cached too.
@internal
final class DocumentCache {
  /// Creates a cache of at most [capacity] entries; 0 stores nothing.
  DocumentCache(this.capacity) {
    if (capacity < 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must not be negative');
    }
  }

  /// The most entries the cache holds.
  final int capacity;

  // Dart's default map keeps insertion order: the first key is the oldest.
  final LinkedHashMap<String, DocumentEntry> _entries =
      LinkedHashMap<String, DocumentEntry>();

  /// The number of entries held.
  int get length => _entries.length;

  /// The entry for [text]: the stored one, which becomes the most recent, or
  /// the one [compiler] makes, stored unless the capacity is 0.
  DocumentEntry entryFor(String text, DocumentCompiler compiler) {
    final hash = const DocumentHash().of(text);
    final stored = _entries.remove(hash);
    if (stored != null) {
      _entries[hash] = stored;
      return stored;
    }
    final entry = compiler.compile(text, hash);
    if (capacity > 0) {
      _entries[hash] = entry;
      if (_entries.length > capacity) {
        _entries.remove(_entries.keys.first);
      }
    }
    return entry;
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/document_compiler.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'diagnostic_errors.dart';
import 'document_entry.dart';

/// Parses and validates one document text against the server's schema.
@internal
class DocumentCompiler {
  /// Creates a compiler that parses with [parser] and validates against
  /// [schema] with [validator].
  const DocumentCompiler(this.parser, this.validator, this.schema);

  /// The parser, with the server's token limit.
  final Parser parser;

  /// The validator, with the server's rules.
  final DocumentValidator validator;

  /// The schema documents are validated against.
  final ValidSchema schema;

  /// The entry for [text], whose SHA-256 is [hash]: the validated document,
  /// or the errors of the first stage that failed.
  DocumentEntry compile(String text, String hash) {
    final source = Source(text);
    return switch (parser.parse(source)) {
      ParseFailure(:final diagnostics) => RejectedEntry(
        hash,
        const DiagnosticErrors().of(diagnostics),
      ),
      ParseSuccess(:final document) => switch (validator.validate(
        schema,
        document,
        source: source,
      )) {
        final ValidDocument valid => AcceptedEntry(hash, valid, source),
        InvalidDocument(:final diagnostics) => RejectedEntry(
          hash,
          const DiagnosticErrors().of(diagnostics),
        ),
      },
    };
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/document_entry.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The outcome of compiling one document text, as the cache keeps it:
/// [AcceptedEntry] or [RejectedEntry]. Both know the [hash] of the text.
@internal
sealed class DocumentEntry {
  /// Creates an entry for the text whose hash is [hash].
  const DocumentEntry(this.hash);

  /// The SHA-256 of the text, computed by the server.
  final String hash;
}

/// A text that parsed and validated.
@internal
final class AcceptedEntry extends DocumentEntry {
  /// Creates an entry holding the [document] and the [source] it came from.
  const AcceptedEntry(super.hash, this.document, this.source);

  /// The validated document; the same object for every request with the same
  /// text.
  final ValidDocument document;

  /// The text, for locations in later messages.
  final Source source;
}

/// A text that did not parse or validate; failures are cached too.
@internal
final class RejectedEntry extends DocumentEntry {
  /// Creates an entry holding the [errors] of the text.
  const RejectedEntry(super.hash, this.errors);

  /// The errors, never empty.
  final List<GraphQLError> errors;
}
```

Create `packages/typed_graphql_server/lib/src/server/document_hash.dart`:

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// The key of a document text in the cache: the lower-case hex SHA-256 of its
/// UTF-8 bytes, which is also the hash of Apollo's persisted queries.
@internal
final class DocumentHash {
  /// Creates the hasher.
  const DocumentHash();

  /// The hash of [text].
  String of(String text) => sha256.convert(utf8.encode(text)).toString();
}
```

Create `packages/typed_graphql_server/lib/src/server/header_names.dart`:

```dart
import 'package:meta/meta.dart';

/// Lower-cases header names, because HTTP header names are case-insensitive.
@internal
final class HeaderNames {
  /// Creates the helper.
  const HeaderNames();

  /// An unmodifiable copy of [headers] with lower-case names; a later entry
  /// wins when two names differ only by case.
  Map<String, String> lowerCased(Map<String, String> headers) =>
      Map.unmodifiable({
        for (final MapEntry(:key, :value) in headers.entries)
          key.toLowerCase(): value,
      });

  /// [base] with [additions] on top, names lower-cased, new values winning.
  Map<String, String> merged(
    Map<String, String> base,
    Map<String, String> additions,
  ) => lowerCased({...base, ...lowerCased(additions)});
}
```

Create `packages/typed_graphql_server/lib/src/server/request_info.dart`:

```dart
import 'header_names.dart';

/// What the transport knows about one request, besides the GraphQL
/// parameters: the context factory and the extensions read it (R5.1).
///
/// {@category server}
final class RequestInfo {
  /// Creates the information about a request.
  ///
  /// [headers] names are lower-cased. [source] is the host's own request
  /// object (for example a `shelf` request); the library never reads it.
  RequestInfo({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    this.source,
  }) : headers = const HeaderNames().lowerCased(headers);

  /// The HTTP method as the transport gave it; the pipeline compares it with
  /// `GET` ignoring case.
  final String method;

  /// The URI the request was sent to.
  final Uri uri;

  /// The headers, unmodifiable, with lower-case names. A transport joins
  /// repeated values with `, `.
  final Map<String, String> headers;

  /// The host's own request object, never read by the library.
  final Object? source;

  /// The value of the header [name], whatever its case, or null.
  String? header(String name) => headers[name.toLowerCase()];
}
```

Create `packages/typed_graphql_server/lib/src/server/server_outcome.dart`:

```dart
/// How a request ended, the status-like part of a `ServerResponse`, which a
/// transport maps to a status of its protocol.
///
/// {@category server}
enum ServerOutcome {
  /// The operation ran; the result has `data`, which may be null after field
  /// errors, cancellation or a timeout.
  executed,

  /// The request is not executable: no query, a syntax or validation error,
  /// a limit, CSRF prevention, a persisted document problem, an operation
  /// that cannot be selected or variables that do not coerce. The result has
  /// no `data`.
  requestError,

  /// A mutation in a `GET` request.
  methodNotAllowed,

  /// An unexpected error in the pipeline itself, such as the context
  /// factory, an extension or a store; its message is masked by the profile.
  internalError,
}
```

Create `packages/typed_graphql_server/lib/src/server/server_request.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import 'request_info.dart';

/// One request for `GraphQLServer.handle`: the GraphQL parameters the
/// transport decoded and what it knows about the request (R5.1).
///
/// {@category server}
final class ServerRequest {
  /// Creates a request.
  const ServerRequest({
    required this.params,
    required this.info,
    this.cancelSignal,
  });

  /// The query, operation name, variables and extensions.
  final GraphQLRequest params;

  /// The method, URI and headers of the request.
  final RequestInfo info;

  /// Owned by the caller, for example cancelled when the client disconnects;
  /// null when nothing cancels the request.
  final CancelSignal? cancelSignal;
}
```

Create `packages/typed_graphql_server/lib/src/server/server_response.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'header_names.dart';
import 'server_outcome.dart';

/// What `GraphQLServer.handle` returns: a [SingleResponse] or a
/// [StreamResponse] (R5.1).
///
/// {@category server}
sealed class ServerResponse {
  /// Creates a response with [headers] (names are lower-cased).
  ServerResponse(Map<String, String> headers)
    : headers = const HeaderNames().lowerCased(headers);

  /// How the request ended.
  ServerOutcome get outcome;

  /// Headers the transport adds to its own, unmodifiable, with lower-case
  /// names.
  final Map<String, String> headers;

  /// A copy of the same kind of response with [additions] merged into the
  /// headers; names are lower-cased and the new values win.
  ServerResponse withHeaders(Map<String, String> additions);
}

/// One payload: the answer to a query or a mutation, or a refusal.
///
/// {@category server}
final class SingleResponse extends ServerResponse {
  /// Creates a response that ended as [outcome].
  SingleResponse(
    this.payload, {
    this.outcome = ServerOutcome.executed,
    Map<String, String> headers = const {},
  }) : super(headers);

  /// The result: an `ExecutionResult` or a `RequestErrorResult`.
  final ResponsePayload payload;

  @override
  final ServerOutcome outcome;

  /// The JSON body of the response, [payload] written.
  JsonObject get body => payload.toJson();

  @override
  SingleResponse withHeaders(Map<String, String> additions) => SingleResponse(
    payload,
    outcome: outcome,
    headers: const HeaderNames().merged(headers, additions),
  );
}

/// The results of a started subscription.
///
/// {@category server}
final class StreamResponse extends ServerResponse {
  /// Creates a response with the [results] of a subscription.
  StreamResponse(this.results, {Map<String, String> headers = const {}})
    : super(headers);

  /// The results, one per event of the subscription.
  final Stream<ExecutionResult> results;

  @override
  ServerOutcome get outcome => ServerOutcome.executed;

  @override
  StreamResponse withHeaders(Map<String, String> additions) => StreamResponse(
    results,
    headers: const HeaderNames().merged(headers, additions),
  );
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index 8ed11e4..b3b72f5 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -54,4 +54,9 @@ export 'src/introspection/introspection_policy.dart';
 export 'src/lookahead/column_allowlist.dart';
 export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
+export 'src/server/context_factory.dart';
+export 'src/server/request_info.dart';
+export 'src/server/server_outcome.dart';
+export 'src/server/server_request.dart';
+export 'src/server/server_response.dart';
 export 'src/subscription/subscription_result.dart';
```

Modify `packages/typed_graphql_server/pubspec.yaml` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/pubspec.yaml b/packages/typed_graphql_server/pubspec.yaml
index f2e36a4..5a75e74 100644
--- a/packages/typed_graphql_server/pubspec.yaml
+++ b/packages/typed_graphql_server/pubspec.yaml
@@ -10,6 +10,7 @@ environment:
   sdk: ^3.13.0
 
 dependencies:
+  crypto: ^3.0.6
   meta: ^1.15.0
   typed_graphql: ^0.0.1
 
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
git add -A packages
git commit -m "feat(typed_graphql_server): add the server request values and document cache

<your model trailer>"
```

### Task 3: feat(typed_graphql_server): add ServerProfile, ServerLimits and CsrfPrevention

**Why.** Adds `ServerProfile` (the development and production presets, spec section 5), `ServerLimits` (maximum document length and the like, with the production defaults) and `CsrfPrevention` (the rule that a request must carry a preflight-triggering header or content type). They are plain const configuration; the pipeline reads them in the next tasks.

**Files** (commit `231c52b`):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Create `packages/typed_graphql_server/lib/src/server/csrf_prevention.dart`
- Create `packages/typed_graphql_server/lib/src/server/server_limits.dart`
- Create `packages/typed_graphql_server/lib/src/server/server_profile.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Create `packages/typed_graphql_server/test/server/csrf_prevention_test.dart`
- Create `packages/typed_graphql_server/test/server/server_profile_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/server/csrf_prevention_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const csrf = CsrfPrevention();

  RequestInfo request(Map<String, String> headers, {String method = 'POST'}) =>
      RequestInfo(
        method: method,
        uri: Uri.parse('http://localhost/graphql'),
        headers: headers,
      );

  test('refuses a GET without headers', () {
    expect(csrf.allows(request({}, method: 'GET')), false);
  });

  for (final type in [
    'application/x-www-form-urlencoded',
    'multipart/form-data',
    'text/plain',
  ]) {
    test('refuses the simple type $type', () {
      expect(csrf.allows(request({'content-type': type})), false);
    });
  }

  test('refuses a simple type with parameters', () {
    final info = request({'content-type': 'text/plain; charset=utf-8'});
    expect(csrf.allows(info), false);
  });

  test('refuses a simple type in odd case', () {
    final info = request({'Content-Type': 'Text/Plain; charset=utf-8'});
    expect(csrf.allows(info), false);
  });

  test('allows application/json', () {
    expect(csrf.allows(request({'content-type': 'application/json'})), true);
  });

  test('allows application/graphql-response+json', () {
    final info = request({'content-type': 'application/graphql-response+json'});
    expect(csrf.allows(info), true);
  });

  for (final type in ['json', 'application/', 'a b/c']) {
    test('refuses the unparsable content type "$type" without a header', () {
      expect(csrf.allows(request({'content-type': type})), false);
    });
  }

  test('refuses an empty preflight header', () {
    expect(csrf.allows(request({'graphql-require-preflight': ''})), false);
  });

  test('refuses a whitespace-only preflight header', () {
    expect(csrf.allows(request({'graphql-require-preflight': '  '})), false);
  });

  test('allows a non-empty preflight header with text/plain', () {
    final info = request({
      'content-type': 'text/plain',
      'x-apollo-operation-name': 'Q',
    });
    expect(csrf.allows(info), true);
  });

  test('custom headers replace the defaults', () {
    const custom = CsrfPrevention(requestHeaders: ['x-my-header']);
    expect(custom.allows(request({'graphql-require-preflight': '1'})), false);
  });

  test('a custom header passes whatever its case in the list', () {
    const custom = CsrfPrevention(requestHeaders: ['X-My-Header']);
    expect(custom.allows(request({'x-my-header': '1'})), true);
  });

  test('the refusal names the headers and ends with a period', () {
    expect(
      csrf.refusal,
      endsWith(
        'headers: graphql-require-preflight, apollo-require-preflight, '
        'x-apollo-operation-name.',
      ),
    );
  });

  test('equal header lists are equal', () {
    expect(
      csrf,
      const CsrfPrevention(
        requestHeaders: [
          'graphql-require-preflight',
          'apollo-require-preflight',
          'x-apollo-operation-name',
        ],
      ),
    );
  });

  test('different header lists differ', () {
    expect(csrf, isNot(const CsrfPrevention(requestHeaders: ['x-a'])));
  });
}
```

Create `packages/typed_graphql_server/test/server/server_profile_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('ServerProfile.development', () {
    const profile = ServerProfile.development;

    test('enables introspection', () {
      expect(profile.introspection, IntrospectionPolicy.enabled);
    });

    test('includes suggestions', () {
      expect(profile.includesSuggestions, true);
    });

    test('does not mask errors', () => expect(profile.maskErrors, false));

    test('prevents CSRF', () {
      expect(profile.csrfPrevention, const CsrfPrevention());
    });

    test('uses the development limits', () {
      expect(profile.limits, ServerLimits.development);
    });

    test('has no timeout', () => expect(profile.timeout, isNull));
  });

  group('ServerProfile.production', () {
    const profile = ServerProfile.production;

    test('disables introspection', () {
      expect(profile.introspection, IntrospectionPolicy.disabled);
    });

    test('omits suggestions', () {
      expect(profile.includesSuggestions, false);
    });

    test('masks errors', () => expect(profile.maskErrors, true));

    test('prevents CSRF', () {
      expect(profile.csrfPrevention, const CsrfPrevention());
    });

    test('uses the production limits', () {
      expect(profile.limits, ServerLimits.production);
    });

    test('has no timeout', () => expect(profile.timeout, isNull));
  });

  group('ServerProfile with methods', () {
    const base = ServerProfile.production;

    test('withIntrospection changes only the introspection', () {
      final copy = base.withIntrospection(IntrospectionPolicy.enabled);
      expect(copy.introspection, IntrospectionPolicy.enabled);
      expect(copy.withIntrospection(IntrospectionPolicy.disabled), base);
    });

    test('withSuggestions changes only the suggestions', () {
      final copy = base.withSuggestions(true);
      expect(copy.includesSuggestions, true);
      expect(copy.withSuggestions(false), base);
    });

    test('withErrorMasking changes only the masking', () {
      final copy = base.withErrorMasking(false);
      expect(copy.maskErrors, false);
      expect(copy.withErrorMasking(true), base);
    });

    test('withCsrfPrevention accepts null to turn the rule off', () {
      final copy = base.withCsrfPrevention(null);
      expect(copy.csrfPrevention, isNull);
      expect(copy.withCsrfPrevention(const CsrfPrevention()), base);
    });

    test('withLimits changes only the limits', () {
      final copy = base.withLimits(ServerLimits.development);
      expect(copy.limits, ServerLimits.development);
      expect(copy.withLimits(ServerLimits.production), base);
    });

    test('withTimeout changes only the timeout', () {
      final copy = base.withTimeout(const Duration(seconds: 5));
      expect(copy.timeout, const Duration(seconds: 5));
      expect(copy.withTimeout(null), base);
    });
  });

  group('ServerProfile equality', () {
    test('equal profiles have equal hash codes', () {
      final copy = ServerProfile.production.withSuggestions(false);
      expect(copy.hashCode, ServerProfile.production.hashCode);
    });

    test('the two constants differ', () {
      expect(ServerProfile.development, isNot(ServerProfile.production));
    });
  });

  group('ServerLimits', () {
    List<Object?> fieldsOf(ServerLimits limits) => [
      limits.maxDocumentLength,
      limits.maxTokens,
      limits.maxDepth,
      limits.maxAliases,
      limits.maxDirectives,
      limits.maxCost,
      limits.defaultListSize,
    ];

    test('development bounds the text only', () {
      expect(fieldsOf(ServerLimits.development), [
        100000,
        15000,
        null,
        null,
        null,
        null,
        10,
      ]);
    });

    test('production sets every limit', () {
      expect(fieldsOf(ServerLimits.production), [
        100000,
        15000,
        15,
        15,
        50,
        10000.0,
        10,
      ]);
    });

    test('compare by value', () {
      expect(const ServerLimits(maxDepth: 3), const ServerLimits(maxDepth: 3));
      expect(
        const ServerLimits(maxDepth: 3).hashCode,
        const ServerLimits(maxDepth: 3).hashCode,
      );
    });

    test('differ when one limit differs', () {
      expect(
        const ServerLimits(maxCost: 1),
        isNot(const ServerLimits(maxCost: 2)),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The new tests construct `ServerProfile`, `ServerLimits` and `CsrfPrevention`, which do not exist yet: compile errors (`Undefined class`).

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 882060f..a212bb0 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -149,3 +149,6 @@
 - `RequestInfo`, `ServerRequest`, `ServerResponse` (`SingleResponse`,
   `StreamResponse`), `ServerOutcome` and `ContextFactory`: the values the
   request pipeline takes and returns. Header names are lower-case.
+- `ServerProfile` (`development`, `production`, one `with*` method per
+  protection), `ServerLimits` and `CsrfPrevention`: the protections of a
+  server as values that compare by value.
```

Create `packages/typed_graphql_server/lib/src/server/csrf_prevention.dart`:

```dart
import 'request_info.dart';

/// The cross-site request forgery rule of a server (R5.4, R5.15): a request
/// passes with a content type a browser cannot send cross-site without a
/// preflight, or with a non-empty custom header.
///
/// {@category server}
final class CsrfPrevention {
  /// Creates the rule; [requestHeaders] replace [defaultHeaders].
  const CsrfPrevention({this.requestHeaders = defaultHeaders});

  /// The headers Apollo Server and GraphQL Yoga accept, so Apollo clients
  /// pass.
  static const List<String> defaultHeaders = [
    'graphql-require-preflight',
    'apollo-require-preflight',
    'x-apollo-operation-name',
  ];

  /// The message of the `GQL403` error, for the default headers.
  static const String message =
      'This operation has been blocked as a potential Cross-Site Request '
      "Forgery (CSRF). Please either specify a 'content-type' header (with a "
      'type that is not one of application/x-www-form-urlencoded, '
      'multipart/form-data, text/plain) or provide a non-empty value for one '
      'of the following headers: ';

  static const List<String> _simpleTypes = [
    'application/x-www-form-urlencoded',
    'multipart/form-data',
    'text/plain',
  ];

  // RFC 7230 token: type "/" subtype.
  static final RegExp _mediaType = RegExp(
    r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+/[!#$%&'*+.^_`|~0-9A-Za-z-]+$",
  );

  /// The header names, any of which with a non-empty value lets a request
  /// pass.
  final List<String> requestHeaders;

  /// The refusal text for this rule, naming [requestHeaders].
  String get refusal => '$message${requestHeaders.join(', ')}.';

  /// Whether the request in [info] passes (September 2025 is silent; this is
  /// Apollo Server's rule).
  bool allows(RequestInfo info) =>
      _hasPreflightingType(info.header('content-type')) ||
      requestHeaders.any(
        (name) => (info.header(name) ?? '').trim().isNotEmpty,
      );

  bool _hasPreflightingType(String? contentType) {
    if (contentType == null) return false;
    final mediaType = contentType.split(';').first.trim().toLowerCase();
    return _mediaType.hasMatch(mediaType) && !_simpleTypes.contains(mediaType);
  }

  @override
  bool operator ==(Object other) =>
      other is CsrfPrevention &&
      other.requestHeaders.length == requestHeaders.length &&
      [for (final name in other.requestHeaders) name.toLowerCase()].join(
            '\n',
          ) ==
          [for (final name in requestHeaders) name.toLowerCase()].join('\n');

  @override
  int get hashCode =>
      Object.hashAll([for (final name in requestHeaders) name.toLowerCase()]);
}
```

Create `packages/typed_graphql_server/lib/src/server/server_limits.dart`:

```dart
/// The size limits of a server; a null limit is off (R5.4, R5.15).
///
/// {@category server}
final class ServerLimits {
  /// Creates limits; every limit but [defaultListSize] is off when null.
  const ServerLimits({
    this.maxDocumentLength = 100000,
    this.maxTokens = 15000,
    this.maxDepth,
    this.maxAliases,
    this.maxDirectives,
    this.maxCost,
    this.defaultListSize = 10,
  });

  /// The limits of a server in development: the bounds on the text only.
  static const ServerLimits development = ServerLimits();

  /// The limits of a server in production: also depth, aliases, directives
  /// and cost.
  static const ServerLimits production = ServerLimits(
    maxDepth: 15,
    maxAliases: 15,
    maxDirectives: 50,
    maxCost: 10000,
  );

  /// The longest document text accepted, in UTF-16 code units; checked
  /// before hashing and parsing, and refused with `GQL401`.
  final int? maxDocumentLength;

  /// The most tokens the parser reads (`ParserOptions.maxTokens`).
  final int? maxTokens;

  /// The deepest selection nesting, applied by `MaxDepthRule` (`GQL232`).
  final int? maxDepth;

  /// The most aliases in an operation, applied by `MaxAliasesRule`.
  final int? maxAliases;

  /// The most directives in an operation, applied by `MaxDirectivesRule`.
  final int? maxDirectives;

  /// The highest field cost or type cost of an operation, applied by the
  /// cost step of the pipeline (`GQL238`).
  final double? maxCost;

  /// The list size the cost step assumes for a list with no slicing
  /// argument or `@listSize`.
  final int defaultListSize;

  @override
  bool operator ==(Object other) =>
      other is ServerLimits &&
      other.maxDocumentLength == maxDocumentLength &&
      other.maxTokens == maxTokens &&
      other.maxDepth == maxDepth &&
      other.maxAliases == maxAliases &&
      other.maxDirectives == maxDirectives &&
      other.maxCost == maxCost &&
      other.defaultListSize == defaultListSize;

  @override
  int get hashCode => Object.hash(
    maxDocumentLength,
    maxTokens,
    maxDepth,
    maxAliases,
    maxDirectives,
    maxCost,
    defaultListSize,
  );
}
```

Create `packages/typed_graphql_server/lib/src/server/server_profile.dart`:

```dart
import '../introspection/introspection_policy.dart';
import 'csrf_prevention.dart';
import 'server_limits.dart';

/// Every protection of a server in one value (R5.4, R5.15).
///
/// {@category server}
final class ServerProfile {
  /// Creates a profile from its protections.
  const ServerProfile({
    required this.introspection,
    required this.includesSuggestions,
    required this.maskErrors,
    required this.csrfPrevention,
    required this.limits,
    this.timeout,
  });

  /// Open for development: introspection and suggestions on, errors
  /// unmasked, few limits.
  static const ServerProfile development = ServerProfile(
    introspection: .enabled,
    includesSuggestions: true,
    maskErrors: false,
    csrfPrevention: CsrfPrevention(),
    limits: .development,
  );

  /// Closed for production: introspection and suggestions off, errors
  /// masked, every limit set. `GraphQLServer` defaults to it.
  static const ServerProfile production = ServerProfile(
    introspection: .disabled,
    includesSuggestions: false,
    maskErrors: true,
    csrfPrevention: CsrfPrevention(),
    limits: .production,
  );

  /// Whether `__schema` and `__type` are answered.
  final IntrospectionPolicy introspection;

  /// Whether validation messages suggest names ("Did you mean").
  final bool includesSuggestions;

  /// Whether an unexpected error is reported as `GQL330` without its text.
  final bool maskErrors;

  /// The CSRF rule; null is off.
  final CsrfPrevention? csrfPrevention;

  /// The size limits.
  final ServerLimits limits;

  /// The time an execution may take; null is no limit.
  final Duration? timeout;

  /// A copy with [introspection].
  ServerProfile withIntrospection(IntrospectionPolicy introspection) =>
      _copy(introspection: introspection);

  /// A copy with [includesSuggestions].
  ServerProfile withSuggestions(bool includesSuggestions) =>
      _copy(includesSuggestions: includesSuggestions);

  /// A copy with [maskErrors].
  ServerProfile withErrorMasking(bool maskErrors) =>
      _copy(maskErrors: maskErrors);

  /// A copy with [csrfPrevention]; null turns the rule off.
  ServerProfile withCsrfPrevention(CsrfPrevention? csrfPrevention) =>
      ServerProfile(
        introspection: introspection,
        includesSuggestions: includesSuggestions,
        maskErrors: maskErrors,
        csrfPrevention: csrfPrevention,
        limits: limits,
        timeout: timeout,
      );

  /// A copy with [limits].
  ServerProfile withLimits(ServerLimits limits) => _copy(limits: limits);

  /// A copy with [timeout]; null removes the limit.
  ServerProfile withTimeout(Duration? timeout) => ServerProfile(
    introspection: introspection,
    includesSuggestions: includesSuggestions,
    maskErrors: maskErrors,
    csrfPrevention: csrfPrevention,
    limits: limits,
    timeout: timeout,
  );

  // Copies the non-nullable fields; the two nullable ones, which a caller
  // may set to null, are copied by their own methods above.
  ServerProfile _copy({
    IntrospectionPolicy? introspection,
    bool? includesSuggestions,
    bool? maskErrors,
    ServerLimits? limits,
  }) => ServerProfile(
    introspection: introspection ?? this.introspection,
    includesSuggestions: includesSuggestions ?? this.includesSuggestions,
    maskErrors: maskErrors ?? this.maskErrors,
    csrfPrevention: csrfPrevention,
    limits: limits ?? this.limits,
    timeout: timeout,
  );

  @override
  bool operator ==(Object other) =>
      other is ServerProfile &&
      other.introspection == introspection &&
      other.includesSuggestions == includesSuggestions &&
      other.maskErrors == maskErrors &&
      other.csrfPrevention == csrfPrevention &&
      other.limits == limits &&
      other.timeout == timeout;

  @override
  int get hashCode => Object.hash(
    introspection,
    includesSuggestions,
    maskErrors,
    csrfPrevention,
    limits,
    timeout,
  );
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index b3b72f5..aea3bf1 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -55,8 +55,11 @@ export 'src/lookahead/column_allowlist.dart';
 export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
 export 'src/server/context_factory.dart';
+export 'src/server/csrf_prevention.dart';
 export 'src/server/request_info.dart';
+export 'src/server/server_limits.dart';
 export 'src/server/server_outcome.dart';
+export 'src/server/server_profile.dart';
 export 'src/server/server_request.dart';
 export 'src/server/server_response.dart';
 export 'src/subscription/subscription_result.dart';
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
git add -A packages
git commit -m "feat(typed_graphql_server): add ServerProfile, ServerLimits and CsrfPrevention

<your model trailer>"
```

### Task 4: fix(typed_graphql_server): address the server values review

**Why.** Answers the review of Tasks 2 and 3 (the server values, the profile, limits and CSRF): tightens `CsrfPrevention`, `DiagnosticErrors`, `DocumentCache`, `DocumentCompiler`, `HeaderNames` and `ServerLimits`, adds a `DiagnosticErrors` test, extends the CSRF and profile tests, and updates the import-rule test and the server guide. It is a fix commit: the tests it changes fail on the tree Tasks 2 and 3 leave, for the reasons the review found.

**Files** (commit `5227b02`):

- Modify `packages/typed_graphql_server/doc/server.md`
- Modify `packages/typed_graphql_server/lib/src/server/csrf_prevention.dart`
- Modify `packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart`
- Modify `packages/typed_graphql_server/lib/src/server/document_cache.dart`
- Modify `packages/typed_graphql_server/lib/src/server/document_compiler.dart`
- Modify `packages/typed_graphql_server/lib/src/server/header_names.dart`
- Modify `packages/typed_graphql_server/lib/src/server/server_limits.dart`
- Modify `packages/typed_graphql_server/test/quality/imports_test.dart`
- Modify `packages/typed_graphql_server/test/server/csrf_prevention_test.dart`
- Create `packages/typed_graphql_server/test/server/diagnostic_errors_test.dart`
- Modify `packages/typed_graphql_server/test/server/server_profile_test.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/quality/imports_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/quality/imports_test.dart b/packages/typed_graphql_server/test/quality/imports_test.dart
index 7cf610b..dd42d7b 100644
--- a/packages/typed_graphql_server/test/quality/imports_test.dart
+++ b/packages/typed_graphql_server/test/quality/imports_test.dart
@@ -25,12 +25,18 @@ void main() {
       );
     });
 
-    test('allows dart:convert and package:crypto/crypto.dart', () {
+    test('allows dart:convert', () {
+      expect(
+        rule.check('lib/src/server/a.dart', "import 'dart:convert';\n"),
+        isEmpty,
+      );
+    });
+
+    test('allows package:crypto/crypto.dart', () {
       expect(
         rule.check(
           'lib/src/server/a.dart',
-          "import 'dart:convert';\n"
-              "import 'package:crypto/crypto.dart';\n",
+          "import 'package:crypto/crypto.dart';\n",
         ),
         isEmpty,
       );
```

Modify `packages/typed_graphql_server/test/server/csrf_prevention_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/csrf_prevention_test.dart b/packages/typed_graphql_server/test/server/csrf_prevention_test.dart
index 95dd89d..a4f6b57 100644
--- a/packages/typed_graphql_server/test/server/csrf_prevention_test.dart
+++ b/packages/typed_graphql_server/test/server/csrf_prevention_test.dart
@@ -50,6 +50,36 @@ void main() {
     });
   }
 
+  test('refuses a list of types that starts with a simple type', () {
+    final info = request({'content-type': 'text/plain, application/json'});
+    expect(csrf.allows(info), false);
+  });
+
+  test('refuses a list of types that ends with a simple type', () {
+    final info = request({'content-type': 'application/json, text/plain'});
+    expect(csrf.allows(info), false);
+  });
+
+  test('allows application/json with surrounding spaces', () {
+    expect(csrf.allows(request({'content-type': ' application/json '})), true);
+  });
+
+  test('refuses text/plain with surrounding spaces', () {
+    expect(csrf.allows(request({'content-type': ' text/plain '})), false);
+  });
+
+  test('refuses an empty content type', () {
+    expect(csrf.allows(request({'content-type': ''})), false);
+  });
+
+  test('allows an unparsable content type with a non-empty header', () {
+    final info = request({
+      'content-type': 'a b/c',
+      'graphql-require-preflight': '1',
+    });
+    expect(csrf.allows(info), true);
+  });
+
   test('refuses an empty preflight header', () {
     expect(csrf.allows(request({'graphql-require-preflight': ''})), false);
   });
@@ -99,6 +129,31 @@ void main() {
     );
   });
 
+  test('header lists in another order differ', () {
+    expect(
+      const CsrfPrevention(requestHeaders: ['x-a', 'x-b']),
+      isNot(const CsrfPrevention(requestHeaders: ['x-b', 'x-a'])),
+    );
+  });
+
+  test('header lists equal ignoring case', () {
+    expect(
+      const CsrfPrevention(requestHeaders: ['X-A']),
+      const CsrfPrevention(requestHeaders: ['x-a']),
+    );
+  });
+
+  test('with no headers, only a preflighting content type passes', () {
+    const strict = CsrfPrevention(requestHeaders: []);
+    expect(strict.allows(request({'content-type': 'application/json'})), true);
+    expect(strict.allows(request({'x-apollo-operation-name': 'Q'})), false);
+  });
+
+  test('with no headers, the refusal names no header', () {
+    const strict = CsrfPrevention(requestHeaders: []);
+    expect(strict.refusal, endsWith('multipart/form-data, text/plain.'));
+  });
+
   test('different header lists differ', () {
     expect(csrf, isNot(const CsrfPrevention(requestHeaders: ['x-a'])));
   });
```

Create `packages/typed_graphql_server/test/server/diagnostic_errors_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/server/diagnostic_errors.dart';

void main() {
  const errors = DiagnosticErrors();
  final error = Diagnostic(
    DiagnosticCode.values.first,
    DiagnosticSeverity.error,
    'an error',
  );
  final warning = Diagnostic(
    DiagnosticCode.values.first,
    DiagnosticSeverity.warning,
    'a warning',
  );

  test('drops a warning next to an error', () {
    expect(errors.of([warning, error]).map((e) => e.message), ['an error']);
  });

  test('reports warnings when there is no error', () {
    expect(errors.of([warning]).map((e) => e.message), ['a warning']);
  });
}
```

Modify `packages/typed_graphql_server/test/server/server_profile_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_profile_test.dart b/packages/typed_graphql_server/test/server/server_profile_test.dart
index 4667595..fc12afe 100644
--- a/packages/typed_graphql_server/test/server/server_profile_test.dart
+++ b/packages/typed_graphql_server/test/server/server_profile_test.dart
@@ -90,9 +90,41 @@ void main() {
     });
   });
 
+  group('ServerProfile with methods keep the other fields', () {
+    final base = ServerProfile.production
+        .withCsrfPrevention(null)
+        .withTimeout(const Duration(seconds: 5));
+
+    void expectKept(ServerProfile copy) {
+      expect(copy.timeout, const Duration(seconds: 5));
+      expect(copy.csrfPrevention, isNull);
+    }
+
+    test('withIntrospection', () {
+      expectKept(base.withIntrospection(IntrospectionPolicy.enabled));
+    });
+
+    test('withSuggestions', () => expectKept(base.withSuggestions(true)));
+
+    test('withErrorMasking', () => expectKept(base.withErrorMasking(false)));
+
+    test(
+      'withLimits',
+      () => expectKept(base.withLimits(ServerLimits.development)),
+    );
+  });
+
   group('ServerProfile equality', () {
     test('equal profiles have equal hash codes', () {
-      final copy = ServerProfile.production.withSuggestions(false);
+      // Built at run time, so it is not the canonical constant.
+      final copy = ServerProfile(
+        introspection: IntrospectionPolicy.values.byName('disabled'),
+        includesSuggestions: false,
+        maskErrors: true,
+        csrfPrevention: const CsrfPrevention(),
+        limits: ServerLimits.production,
+      );
+      expect(copy, ServerProfile.production);
       expect(copy.hashCode, ServerProfile.production.hashCode);
     });
 
@@ -144,6 +176,24 @@ void main() {
       );
     });
 
+    test('a NaN cost is a programmer error', () {
+      expect(
+        () => ServerLimits(maxCost: double.nan),
+        throwsA(isA<AssertionError>()),
+      );
+    });
+
+    test('a negative depth is a programmer error', () {
+      expect(() => ServerLimits(maxDepth: -1), throwsA(isA<AssertionError>()));
+    });
+
+    test('a negative default list size is a programmer error', () {
+      expect(
+        () => ServerLimits(defaultListSize: -1),
+        throwsA(isA<AssertionError>()),
+      );
+    });
+
     test('differ when one limit differs', () {
       expect(
         const ServerLimits(maxCost: 1),
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The new `diagnostic_errors_test.dart` and the extended `csrf_prevention_test.dart` and `server_profile_test.dart` fail on the tree Tasks 2 and 3 leave: behaviour the review named is wrong or missing (or a member they use does not exist yet, which is a compile error).

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/doc/server.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/doc/server.md b/packages/typed_graphql_server/doc/server.md
index bfb3f69..07a1f31 100644
--- a/packages/typed_graphql_server/doc/server.md
+++ b/packages/typed_graphql_server/doc/server.md
@@ -1,8 +1,7 @@
 # Server
 
-A transport hands the server a `ServerRequest` and gets a `ServerResponse`
-back. This guide grows with the request pipeline; for now it describes the
-values on both sides.
+This guide describes `RequestInfo`, the request a transport hands to the
+server. It grows with the request pipeline.
 
 `RequestInfo` holds the method, the URI and the headers of a request. Header
 names are lower-cased when it is made, and `header` finds one by any case.
```

Modify `packages/typed_graphql_server/lib/src/server/csrf_prevention.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/csrf_prevention.dart b/packages/typed_graphql_server/lib/src/server/csrf_prevention.dart
index baefbad..95a684a 100644
--- a/packages/typed_graphql_server/lib/src/server/csrf_prevention.dart
+++ b/packages/typed_graphql_server/lib/src/server/csrf_prevention.dart
@@ -7,6 +7,10 @@ import 'request_info.dart';
 /// {@category server}
 final class CsrfPrevention {
   /// Creates the rule; [requestHeaders] replace [defaultHeaders].
+  ///
+  /// [requestHeaders] must not be mutated afterwards: a constant constructor
+  /// cannot copy it. An empty list lets only a request with a content type a
+  /// browser cannot send cross-site pass.
   const CsrfPrevention({this.requestHeaders = defaultHeaders});
 
   /// The headers Apollo Server and GraphQL Yoga accept, so Apollo clients
@@ -25,6 +29,12 @@ final class CsrfPrevention {
       'multipart/form-data, text/plain) or provide a non-empty value for one '
       'of the following headers: ';
 
+  static const String _contentTypeOnlyMessage =
+      'This operation has been blocked as a potential Cross-Site Request '
+      "Forgery (CSRF). Please specify a 'content-type' header with a type "
+      'that is not one of application/x-www-form-urlencoded, '
+      'multipart/form-data, text/plain.';
+
   static const List<String> _simpleTypes = [
     'application/x-www-form-urlencoded',
     'multipart/form-data',
@@ -41,7 +51,9 @@ final class CsrfPrevention {
   final List<String> requestHeaders;
 
   /// The refusal text for this rule, naming [requestHeaders].
-  String get refusal => '$message${requestHeaders.join(', ')}.';
+  String get refusal => requestHeaders.isEmpty
+      ? _contentTypeOnlyMessage
+      : '$message${requestHeaders.join(', ')}.';
 
   /// Whether the request in [info] passes (September 2025 is silent; this is
   /// Apollo Server's rule).
@@ -59,12 +71,17 @@ final class CsrfPrevention {
 
   @override
   bool operator ==(Object other) =>
-      other is CsrfPrevention &&
-      other.requestHeaders.length == requestHeaders.length &&
-      [for (final name in other.requestHeaders) name.toLowerCase()].join(
-            '\n',
-          ) ==
-          [for (final name in requestHeaders) name.toLowerCase()].join('\n');
+      other is CsrfPrevention && _sameNames(other.requestHeaders);
+
+  bool _sameNames(List<String> others) {
+    if (others.length != requestHeaders.length) return false;
+    for (var index = 0; index < others.length; index++) {
+      if (others[index].toLowerCase() != requestHeaders[index].toLowerCase()) {
+        return false;
+      }
+    }
+    return true;
+  }
 
   @override
   int get hashCode =>
```

Modify `packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart b/packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart
index 2bfbc60..fb9c3e3 100644
--- a/packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart
+++ b/packages/typed_graphql_server/lib/src/server/diagnostic_errors.dart
@@ -10,13 +10,18 @@ final class DiagnosticErrors {
   /// One error for each error diagnostic in [diagnostics], in order: the
   /// message, the place and the related places as `locations`, and the
   /// diagnostic's id as `extensions.code`.
-  List<GraphQLError> of(List<Diagnostic> diagnostics) => [
-    for (final diagnostic in diagnostics)
-      if (diagnostic.isError)
+  ///
+  /// Warnings are dropped, unless there is no error: a rejection never has
+  /// zero errors, so then every diagnostic is reported.
+  List<GraphQLError> of(List<Diagnostic> diagnostics) {
+    final errors = diagnostics.where((diagnostic) => diagnostic.isError);
+    return [
+      for (final diagnostic in errors.isEmpty ? diagnostics : errors)
         GraphQLError(
           diagnostic.message,
           locations: diagnostic.locations,
           extensions: JsonObject({'code': JsonString(diagnostic.code.id)}),
         ),
-  ];
+    ];
+  }
 }
```

Modify `packages/typed_graphql_server/lib/src/server/document_cache.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_cache.dart b/packages/typed_graphql_server/lib/src/server/document_cache.dart
index 972f75e..1043069 100644
--- a/packages/typed_graphql_server/lib/src/server/document_cache.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_cache.dart
@@ -28,6 +28,7 @@ final class DocumentCache {
       LinkedHashMap<String, DocumentEntry>();
 
   /// The number of entries held.
+  @visibleForTesting
   int get length => _entries.length;
 
   /// The entry for [text]: the stored one, which becomes the most recent, or
```

Modify `packages/typed_graphql_server/lib/src/server/document_compiler.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_compiler.dart b/packages/typed_graphql_server/lib/src/server/document_compiler.dart
index 01eac2f..ee32407 100644
--- a/packages/typed_graphql_server/lib/src/server/document_compiler.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_compiler.dart
@@ -5,6 +5,8 @@ import 'diagnostic_errors.dart';
 import 'document_entry.dart';
 
 /// Parses and validates one document text against the server's schema.
+///
+/// Not final: tests subclass it to count the compilations.
 @internal
 class DocumentCompiler {
   /// Creates a compiler that parses with [parser] and validates against
```

Modify `packages/typed_graphql_server/lib/src/server/header_names.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/header_names.dart b/packages/typed_graphql_server/lib/src/server/header_names.dart
index c0e3dfb..b62983e 100644
--- a/packages/typed_graphql_server/lib/src/server/header_names.dart
+++ b/packages/typed_graphql_server/lib/src/server/header_names.dart
@@ -14,9 +14,10 @@ final class HeaderNames {
           key.toLowerCase(): value,
       });
 
-  /// [base] with [additions] on top, names lower-cased, new values winning.
+  /// [base], whose names are already lower-case, with [additions] on top (names
+  /// lower-cased), new values winning.
   Map<String, String> merged(
     Map<String, String> base,
     Map<String, String> additions,
-  ) => lowerCased({...base, ...lowerCased(additions)});
+  ) => Map.unmodifiable({...base, ...lowerCased(additions)});
 }
```

Modify `packages/typed_graphql_server/lib/src/server/server_limits.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/server_limits.dart b/packages/typed_graphql_server/lib/src/server/server_limits.dart
index 9cdbfda..646caea 100644
--- a/packages/typed_graphql_server/lib/src/server/server_limits.dart
+++ b/packages/typed_graphql_server/lib/src/server/server_limits.dart
@@ -3,6 +3,11 @@
 /// {@category server}
 final class ServerLimits {
   /// Creates limits; every limit but [defaultListSize] is off when null.
+  ///
+  /// A non-null limit must be positive, [maxCost] not NaN and
+  /// [defaultListSize] not negative. These are programmer errors, checked by
+  /// assertions because a constant constructor cannot throw an
+  /// [ArgumentError].
   const ServerLimits({
     this.maxDocumentLength = 100000,
     this.maxTokens = 15000,
@@ -11,7 +16,25 @@ final class ServerLimits {
     this.maxDirectives,
     this.maxCost,
     this.defaultListSize = 10,
-  });
+  }) : assert(
+         maxDocumentLength == null || maxDocumentLength > 0,
+         'maxDocumentLength must be positive',
+       ),
+       assert(maxTokens == null || maxTokens > 0, 'maxTokens must be positive'),
+       assert(maxDepth == null || maxDepth > 0, 'maxDepth must be positive'),
+       assert(
+         maxAliases == null || maxAliases > 0,
+         'maxAliases must be positive',
+       ),
+       assert(
+         maxDirectives == null || maxDirectives > 0,
+         'maxDirectives must be positive',
+       ),
+       assert(
+         maxCost == null || maxCost > 0,
+         'maxCost must be positive (NaN fails the comparison)',
+       ),
+       assert(defaultListSize >= 0, 'defaultListSize must not be negative');
 
   /// The limits of a server in development: the bounds on the text only.
   static const ServerLimits development = ServerLimits();
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
git add -A packages
git commit -m "fix(typed_graphql_server): address the server values review

<your model trailer>"
```

### Task 5: feat(typed_graphql_server): add GraphQLServer

**Why.** Adds `GraphQLServer`, the request pipeline without extensions, CSRF and cost (spec sections 6 to 8): length check, document cache, operation lookup, `GQL402` for a mutation over GET, the context factory, then execution or subscription with the profile's options. `handle` never throws: every failure becomes a `ServerResponse` (R0.3). The steps are small collaborators (`RequestStep`, `DocumentStep`, `ExecutionStep`, `OperationLookup`, `ExecutionJob`, `PipelineErrors`).

**Files** (commit `4312ebb`):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Create `packages/typed_graphql_server/lib/src/server/document_step.dart`
- Create `packages/typed_graphql_server/lib/src/server/execution_job.dart`
- Create `packages/typed_graphql_server/lib/src/server/execution_step.dart`
- Create `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Create `packages/typed_graphql_server/lib/src/server/operation_lookup.dart`
- Create `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart`
- Create `packages/typed_graphql_server/lib/src/server/request_step.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Create `packages/typed_graphql_server/test/server/graphql_server_profile_test.dart`
- Create `packages/typed_graphql_server/test/server/graphql_server_test.dart`
- Create `packages/typed_graphql_server/test/server/support/server_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/server/graphql_server_profile_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  Ctx failingFactory(RequestInfo info) => throw StateError('secret detail');

  test('a negative cache size is an ArgumentError', () {
    expect(
      () => fixture.server(documentCacheSize: -1),
      throwsArgumentError,
    );
  });

  group('errors of the context factory', () {
    test('a GraphQLException is a request error with its extensions', () async {
      final server = fixture.server(
        contextFactory: (_) => throw GraphQLException(
          'Not signed in',
          extensions: JsonObject({'code': const JsonString('AUTH')}),
        ),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(fixture.json(response), {
        'errors': [
          {
            'message': 'Not signed in',
            'extensions': {'code': 'AUTH'},
          },
        ],
      });
    });

    test(
      'production masks the error and calls the hook with the raw one',
      () async {
        Object? seen;
        final server = fixture.server(
          profile: ServerProfile.production,
          contextFactory: failingFactory,
          onError: (error, stackTrace, reported) {
            seen = error;
            return null;
          },
        );
        final response = await server.handle(fixture.request('{ hello }'));
        expect(
          (response as SingleResponse).outcome,
          ServerOutcome.internalError,
        );
        expect(fixture.codeOf(response), 'GQL330');
        expect(fixture.messageOf(response), 'Unexpected error.');
        expect(seen, isA<StateError>());
      },
    );

    test('development shows toString()', () async {
      final server = fixture.server(contextFactory: failingFactory);
      final response = await server.handle(fixture.request('{ hello }'));
      expect(
        fixture.messageOf(response),
        'Bad state: secret detail',
      );
    });

    test('a hook can replace the error', () async {
      final server = fixture.server(
        contextFactory: failingFactory,
        onError: (error, stackTrace, reported) => GraphQLError('replaced'),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'replaced');
    });

    test('a hook that throws gives the masked error', () async {
      final server = fixture.server(
        contextFactory: failingFactory,
        onError: (error, stackTrace, reported) => throw StateError('hook'),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'Unexpected error.');
      expect(fixture.codeOf(response), 'GQL330');
    });

    test('an asynchronous failure is handled too', () async {
      final server = fixture.server(
        contextFactory: (_) async => throw StateError('later'),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect((response as SingleResponse).outcome, ServerOutcome.internalError);
    });
  });

  group('the profile reaches the execution', () {
    test('production refuses introspection with GQL338', () async {
      final response = await fixture
          .server(
            profile: ServerProfile.production,
          )
          .handle(fixture.request('{ __schema { queryType { name } } }'));
      expect(fixture.json(response)['errors'], isNotNull);
      expect(fixture.codeOf(response), 'GQL338');
    });

    test('production still answers __typename', () async {
      final response = await fixture
          .server(
            profile: ServerProfile.production,
          )
          .handle(fixture.request('{ __typename }'));
      expect(fixture.json(response), {
        'data': {'__typename': 'Query'},
      });
    });

    test('development answers introspection', () async {
      final response = await fixture.server().handle(
        fixture.request('{ __schema { queryType { name } } }'),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });

    test('production gives no suggestions', () async {
      final response = await fixture
          .server(
            profile: ServerProfile.production,
          )
          .handle(fixture.request('{ helo }'));
      expect(fixture.messageOf(response), isNot(contains('Did you mean')));
    });

    test('development gives suggestions', () async {
      final response = await fixture.server().handle(
        fixture.request('{ helo }'),
      );
      expect(fixture.messageOf(response), contains('Did you mean "hello"'));
    });

    test('the timeout ends a slow query with GQL351', () async {
      final server = fixture.server(
        profile: ServerProfile.development.withTimeout(
          const Duration(milliseconds: 20),
        ),
      );
      final response = await server.handle(fixture.request('{ slow }'));
      expect(fixture.codeOf(response), 'GQL351');
    });

    test('the timeout does not end a subscription', () async {
      final server = fixture.server(
        profile: ServerProfile.development.withTimeout(
          const Duration(milliseconds: 20),
        ),
      );
      final response = await server.handle(
        fixture.request('subscription { ticks }'),
      );
      final results = await (response as StreamResponse).results.toList();
      expect(results.map((result) => result.errors), everyElement(isEmpty));
      expect(results, hasLength(2));
    });

    test('the cancel signal reaches the execution with GQL350', () async {
      final signal = CancelSignal()..cancel();
      final response = await fixture.server().handle(
        fixture.request('{ hello }', cancelSignal: signal),
      );
      expect(fixture.codeOf(response), 'GQL350');
    });
  });

  group('the limits', () {
    test('production refuses a depth-16 query before the context', () async {
      var built = 0;
      final server = fixture.server(
        profile: ServerProfile.production,
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
      );
      final response = await server.handle(
        fixture.request(fixture.nested(16)),
      );
      expect(fixture.codeOf(response), 'GQL232');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(built, 0);
    });

    test('development allows it', () async {
      final response = await fixture.server().handle(
        fixture.request(fixture.nested(16)),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });

    test('maxTokens reaches the parser', () async {
      final server = fixture.server(
        profile: ServerProfile.development.withLimits(
          const ServerLimits(maxTokens: 2),
        ),
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), startsWith('GQL0'));
      expect(fixture.messageOf(response), contains('token'));
    });

    test('custom validation rules run beside the limit rules', () async {
      final rule = CountingRule();
      final server = fixture.server(
        profile: ServerProfile.production,
        validationRules: [rule],
      );
      await server.handle(fixture.request(fixture.nested(16)));
      expect(rule.runs, 1);
    });
  });
}
```

Create `packages/typed_graphql_server/test/server/graphql_server_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  group('a query', () {
    test('runs and returns its data as executed', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }'),
      );
      expect((response as SingleResponse).outcome, ServerOutcome.executed);
      expect(fixture.json(response), {
        'data': {'hello': 'world'},
      });
    });

    test('receives its variables', () async {
      final response = await fixture.server().handle(
        fixture.request(
          r'query Q($n: String!) { greet(name: $n) }',
          variables: JsonObject({'n': const JsonString('Ada')}),
        ),
      );
      expect(fixture.json(response), {
        'data': {'greet': 'Ada'},
      });
    });

    test('runs the operation named by operationName', () async {
      final response = await fixture.server().handle(
        fixture.request(
          'query A { hello } query B { tag }',
          operationName: 'B',
        ),
      );
      expect(fixture.json(response), {
        'data': {'tag': 'default'},
      });
    });

    test('reads the context the factory built', () async {
      final server = fixture.server(contextFactory: (_) => const Ctx('mine'));
      final response = await server.handle(fixture.request('{ tag }'));
      expect(fixture.json(response), {
        'data': {'tag': 'mine'},
      });
    });

    test('is allowed with GET', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }', method: 'get'),
      );
      expect((response as SingleResponse).outcome, ServerOutcome.executed);
    });
  });

  group('a request without a document', () {
    test('has no query: GQL400', () async {
      final response = await fixture.server().handle(fixture.request(null));
      expect(fixture.codeOf(response), 'GQL400');
      expect(fixture.messageOf(response), 'Must provide query string.');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('has an empty query: GQL400', () async {
      final response = await fixture.server().handle(fixture.request(''));
      expect(fixture.codeOf(response), 'GQL400');
    });
  });

  group('the document length', () {
    const small = ServerProfile(
      introspection: .enabled,
      includesSuggestions: true,
      maskErrors: false,
      csrfPrevention: null,
      limits: ServerLimits(maxDocumentLength: 10),
    );

    test('over the maximum is GQL401', () async {
      final server = fixture.server(profile: small);
      final response = await server.handle(fixture.request('{ hello  }  '));
      expect(fixture.codeOf(response), 'GQL401');
      expect(
        fixture.messageOf(response),
        'The document is longer than the maximum of 10 characters.',
      );
    });

    test('over the maximum never reaches validation', () async {
      final rule = CountingRule();
      final server = fixture.server(
        profile: small,
        validationRules: [rule],
      );
      await server.handle(fixture.request('{ hello  }  '));
      expect(rule.runs, 0);
    });

    test('at the maximum is served', () async {
      final response = await fixture
          .server(
            profile: small,
          )
          .handle(fixture.request('{ hello } '));
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  group('a rejected document', () {
    test('is a request error with its errors', () async {
      final response = await fixture.server().handle(
        fixture.request('{ nothing }'),
      );
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(fixture.codeOf(response), startsWith('GQL2'));
    });

    test('is not validated again for the same text', () async {
      final rule = CountingRule();
      final server = fixture.server(validationRules: [rule]);
      await server.handle(fixture.request('{ hello }'));
      await server.handle(fixture.request('{ hello }'));
      expect(rule.runs, 1);
    });

    test('is validated again with the cache off', () async {
      final rule = CountingRule();
      final server = fixture.server(
        validationRules: [rule],
        documentCacheSize: 0,
      );
      await server.handle(fixture.request('{ hello }'));
      await server.handle(fixture.request('{ hello }'));
      expect(rule.runs, 2);
    });
  });

  group('the operation', () {
    test('a mutation with GET is GQL402 with an allow header', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }', method: 'GET'),
      );
      expect(
        (response as SingleResponse).outcome,
        ServerOutcome.methodNotAllowed,
      );
      expect(fixture.codeOf(response), 'GQL402');
      expect(response.headers, {'allow': 'POST'});
    });

    test('a mutation with get in lower case is refused too', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }', method: 'get'),
      );
      expect(fixture.codeOf(response), 'GQL402');
    });

    test('a mutation with POST runs', () async {
      final response = await fixture.server().handle(
        fixture.request('mutation { bump }'),
      );
      expect(fixture.json(response), {
        'data': {'bump': 'bumped'},
      });
    });

    test('the mutation of an operation name decides, not the first', () async {
      final response = await fixture.server().handle(
        fixture.request(
          'mutation M { bump } query Q { hello }',
          method: 'GET',
          operationName: 'Q',
        ),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('an unknown operation name is reported by the executor', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }', operationName: 'Nope'),
      );
      expect(fixture.codeOf(response), 'GQL320');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('several operations without a name are GQL321', () async {
      final response = await fixture.server().handle(
        fixture.request('query A { hello } query B { hello }'),
      );
      expect(fixture.codeOf(response), 'GQL321');
    });

    test('a refusal before the context never builds it', () async {
      var built = 0;
      final server = fixture.server(
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
      );
      await server.handle(fixture.request('mutation { bump }', method: 'GET'));
      await server.handle(fixture.request('{ nothing }'));
      await server.handle(fixture.request(null));
      expect(built, 0);
    });
  });

  group('a subscription', () {
    test('starts as a stream, also with GET', () async {
      final response = await fixture.server().handle(
        fixture.request('subscription { ticks }', method: 'GET'),
      );
      expect(response, isA<StreamResponse>());
      expect(response.outcome, ServerOutcome.executed);
      final results = await (response as StreamResponse).results.toList();
      expect(
        [for (final result in results) result.toJson().toJson()['data']],
        [
          {'ticks': 'tick 1'},
          {'ticks': 'tick 2'},
        ],
      );
    });

    test('rejected by the executor is a request error', () async {
      final response = await fixture.server().handle(
        fixture.request('subscription A { ticks } subscription B { ticks }'),
      );
      expect(fixture.codeOf(response), 'GQL321');
    });
  });
}
```

Create `packages/typed_graphql_server/test/server/support/server_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of the fixture schema.
final class Ctx {
  const Ctx(this.tag);

  final String tag;
}

/// A visitor that does nothing.
final class IdleVisitor extends AstVisitor {
  const IdleVisitor();
}

/// A validation rule that counts the runs it takes part in, to observe
/// whether a document reached validation.
final class CountingRule extends ValidationRule {
  CountingRule();

  int runs = 0;

  @override
  AstVisitor createVisitor(ValidationContext context) {
    runs++;
    return const IdleVisitor();
  }
}

/// A small executable schema and the servers and requests to test it.
final class ServerFixture {
  ServerFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final name = Arg('name', b.string);
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'world'),
        t
            .field('greet', b.string, args: [name])
            .resolve((parent, args, context, info) => args.get(name)),
        t
            .field('tag', b.string)
            .resolve((parent, args, context, info) => context.tag),
        t.field('slow', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return 'slow';
        }),
        t.field('self', query).pure((_) => const Object()),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t.field('ticks', b.string).subscribeWith<int>(
          (parent, args, context, info) => Stream.fromIterable([1, 2]),
          (event, args, context, info) async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return 'tick $event';
          },
        ),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  late final ExecutableSchema<Ctx> schema;

  GraphQLServer<Ctx> server({
    ServerProfile profile = ServerProfile.development,
    ContextFactory<Ctx>? contextFactory,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
  }) => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory: contextFactory ?? (_) => const Ctx('default'),
    profile: profile,
    validationRules: validationRules,
    onError: onError,
    documentCacheSize: documentCacheSize,
  );

  ServerRequest request(
    String? query, {
    String method = 'POST',
    String? operationName,
    JsonObject? variables,
    CancelSignal? cancelSignal,
  }) => ServerRequest(
    params: GraphQLRequest(
      query: query,
      operationName: operationName,
      variables: variables,
    ),
    info: RequestInfo(method: method, uri: Uri.parse('/graphql')),
    cancelSignal: cancelSignal,
  );

  /// A query nested [depth] levels deep: `{ self { self { hello } } }`.
  String nested(int depth) => '${'{ self ' * depth}{ hello }${' }' * depth}';

  /// The JSON of a single response.
  Map<String, Object?> json(ServerResponse response) =>
      (response as SingleResponse).body.toJson();

  /// The `extensions.code` of the first error of a single response.
  String codeOf(ServerResponse response) {
    final errors = json(response)['errors']! as List<Object?>;
    final extensions =
        (errors.first! as Map<String, Object?>)['extensions']!
            as Map<String, Object?>;
    return extensions['code']! as String;
  }

  /// The message of the first error of a single response.
  String messageOf(ServerResponse response) {
    final errors = json(response)['errors']! as List<Object?>;
    return (errors.first! as Map<String, Object?>)['message']! as String;
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The new pipeline tests construct `GraphQLServer`, which does not exist yet: compile errors.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index a212bb0..de2c476 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -152,3 +152,8 @@
 - `ServerProfile` (`development`, `production`, one `with*` method per
   protection), `ServerLimits` and `CsrfPrevention`: the protections of a
   server as values that compare by value.
+- `GraphQLServer<C>`: `handle(ServerRequest)` runs the request pipeline (document
+  length, `GQL400`/`GQL401`, the document cache, the operation lookup, `GQL402`
+  for a mutation over `GET`, the context factory, execution or subscription
+  with the options of the `ServerProfile`) and never throws; unexpected errors
+  go to `onError` and are masked (`GQL330`) per the profile.
```

Create `packages/typed_graphql_server/lib/src/server/document_step.dart`:

```dart
import 'package:meta/meta.dart';

import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_entry.dart';

/// The core step of the document phase: the text becomes a validated
/// document or its errors, through the cache (R5.2).
@internal
final class DocumentStep {
  /// Creates the step over [cache] and [compiler].
  const DocumentStep(this.cache, this.compiler);

  /// Where compiled texts are kept.
  final DocumentCache cache;

  /// Compiles a text the cache does not hold.
  final DocumentCompiler compiler;

  /// The entry for [text].
  DocumentEntry run(String text) => cache.entryFor(text, compiler);
}
```

Create `packages/typed_graphql_server/lib/src/server/execution_job.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'document_entry.dart';
import 'server_request.dart';

/// Everything the execution step needs once the pipeline has accepted a
/// request and built its context.
@internal
final class ExecutionJob<C> {
  /// Creates a job.
  const ExecutionJob({
    required this.entry,
    required this.operationType,
    required this.context,
    required this.request,
  });

  /// The accepted document and its source.
  final AcceptedEntry entry;

  /// The kind of the selected operation, null when none is selected.
  final OperationType? operationType;

  /// The context the context factory built.
  final C context;

  /// The request being served.
  final ServerRequest request;
}
```

Create `packages/typed_graphql_server/lib/src/server/execution_step.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import '../execution/execution_options.dart';
import '../subscription/subscription_result.dart';
import 'execution_job.dart';
import 'server_outcome.dart';
import 'server_profile.dart';
import 'server_response.dart';

/// The core step of the execution phase: runs the operation with the
/// options of section 12 and maps the result to a response.
@internal
final class ExecutionStep<C> {
  /// Creates the step for [schema] under [profile], passing [onError] on.
  const ExecutionStep(this.schema, this.profile, this.onError);

  /// The schema that executes.
  final ExecutableSchema<C> schema;

  /// The profile whose settings reach the execution.
  final ServerProfile profile;

  /// The server's error hook.
  final ErrorHook? onError;

  /// The options of [job]: no timeout for a subscription, which would end a
  /// long-lived stream.
  ExecutionOptions optionsFor(ExecutionJob<C> job) => ExecutionOptions(
    source: job.entry.source,
    maskErrors: profile.maskErrors,
    onError: onError,
    includesSuggestions: profile.includesSuggestions,
    introspection: profile.introspection,
    cancelSignal: job.request.cancelSignal,
    timeout: job.operationType == OperationType.subscription
        ? null
        : profile.timeout,
  );

  /// Executes [job] with its [optionsFor].
  Future<ServerResponse> run(ExecutionJob<C> job) async {
    final params = job.request.params;
    final options = optionsFor(job);
    if (job.operationType == OperationType.subscription) {
      final started = await schema.subscribe(
        job.entry.document,
        context: job.context,
        operationName: params.operationName,
        variables: params.variables,
        options: options,
      );
      return switch (started) {
        SubscriptionStarted(:final results) => StreamResponse(results),
        SubscriptionRejected(:final error) => SingleResponse(
          error,
          outcome: ServerOutcome.requestError,
        ),
      };
    }
    final payload = await schema.execute(
      job.entry.document,
      context: job.context,
      operationName: params.operationName,
      variables: params.variables,
      options: options,
    );
    return SingleResponse(
      payload,
      outcome: switch (payload) {
        ExecutionResult() => ServerOutcome.executed,
        RequestErrorResult() => ServerOutcome.requestError,
      },
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/graphql_server.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import '../execution/graphql_exception.dart';
import 'context_factory.dart';
import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_step.dart';
import 'execution_step.dart';
import 'pipeline_errors.dart';
import 'request_step.dart';
import 'server_limits.dart';
import 'server_profile.dart';
import 'server_request.dart';
import 'server_response.dart';

/// Serves GraphQL requests: parses and validates the document (cached),
/// applies the limits of the [ServerProfile], builds the context and
/// executes (R5.1).
///
/// It knows nothing of HTTP: a transport decodes a [ServerRequest] and
/// writes the [ServerResponse]. Every refusal comes before the context is
/// built and before any resolver runs.
///
/// {@category server}
final class GraphQLServer<C> {
  /// Creates a server for [schema], building each request's context with
  /// [contextFactory].
  ///
  /// [validationRules] are the base rules; the limit rules of
  /// `profile.limits` are added to them. [onError] is passed to every
  /// execution and sees the unexpected errors of the pipeline before they
  /// are masked. [documentCacheSize] is the most compiled documents kept;
  /// 0 keeps none and a negative size is an [ArgumentError].
  factory GraphQLServer({
    required ExecutableSchema<C> schema,
    required ContextFactory<C> contextFactory,
    ServerProfile profile = ServerProfile.production,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
  }) {
    final errors = PipelineErrors(
      maskErrors: profile.maskErrors,
      onError: onError,
    );
    final compiler = DocumentCompiler(
      Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
      DocumentValidator(
        rules: [...validationRules, ..._limitRules(profile.limits)],
        includesSuggestions: profile.includesSuggestions,
      ),
      schema.schema,
    );
    return GraphQLServer._(
      errors,
      RequestStep<C>(
        limits: profile.limits,
        documentStep: DocumentStep(DocumentCache(documentCacheSize), compiler),
        contextFactory: contextFactory,
        executionStep: ExecutionStep<C>(schema, profile, onError),
        errors: errors,
      ),
    );
  }

  GraphQLServer._(this._errors, this._request);

  final PipelineErrors _errors;
  final RequestStep<C> _request;

  static List<ValidationRule> _limitRules(ServerLimits limits) => [
    if (limits.maxDepth case final maxDepth?) MaxDepthRule(maxDepth: maxDepth),
    if (limits.maxAliases case final maxAliases?)
      MaxAliasesRule(maxAliases: maxAliases),
    if (limits.maxDirectives case final maxDirectives?)
      MaxDirectivesRule(maxDirectives: maxDirectives),
  ];

  /// Serves [request]. It never throws: a failure is a response.
  ///
  /// A [GraphQLException] from the context factory is a request error; any
  /// other error goes to the error hook and is masked by the profile.
  Future<ServerResponse> handle(ServerRequest request) async {
    try {
      return await _request.run(request);
    } on GraphQLException catch (exception) {
      return _errors.exception(exception);
    } on Object catch (error, stackTrace) {
      // The outermost boundary, as M5 catches what a resolver throws: user
      // code may throw anything and the caller must still get a response.
      return _errors.internal(error, stackTrace);
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/operation_lookup.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Finds which operation a request selects, as the executor will.
@internal
final class OperationLookup {
  /// Creates the lookup.
  const OperationLookup();

  /// The kind of the operation of [document] named [operationName] (the only
  /// operation when null), or null when there is none to select; the
  /// executor then reports `GQL320`-`GQL322` (September2025 6.1.2).
  OperationType? typeOf(Document document, String? operationName) {
    final operations = document.definitions.whereType<OperationDefinition>();
    if (operationName == null) {
      return operations.length == 1 ? operations.first.operation : null;
    }
    for (final operation in operations) {
      if (operation.name?.value == operationName) {
        return operation.operation;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/graphql_exception.dart';
import 'server_outcome.dart';
import 'server_response.dart';

/// Makes the responses a refusal or a failure of the pipeline ends with.
@internal
final class PipelineErrors {
  /// Creates the factory for a server whose profile masks errors when
  /// [maskErrors] is on and whose error hook is [onError].
  const PipelineErrors({required this.maskErrors, this.onError});

  /// Whether an unexpected error is replaced by a generic message.
  final bool maskErrors;

  /// The server's error hook, null when there is none.
  final ErrorHook? onError;

  static const String _maskedMessage = 'Unexpected error.';

  /// A refusal with one error coded [code].
  SingleResponse refusal(
    DiagnosticCode code,
    String message, {
    ServerOutcome outcome = ServerOutcome.requestError,
    Map<String, String> headers = const {},
  }) => SingleResponse(
    RequestErrorResult(errors: [_coded(code, message)]),
    outcome: outcome,
    headers: headers,
  );

  /// A request error carrying [errors].
  SingleResponse rejected(List<GraphQLError> errors) => SingleResponse(
    RequestErrorResult(errors: errors),
    outcome: ServerOutcome.requestError,
  );

  /// A request error with the message and extensions of [exception].
  SingleResponse exception(GraphQLException exception) => rejected([
    GraphQLError(exception.message, extensions: exception.extensions),
  ]);

  /// The response to an unexpected [error]: offered to the hook, then
  /// masked (`GQL330`) or shown by its `toString()`.
  SingleResponse internal(Object error, StackTrace stackTrace) {
    final reported = _coded(
      DiagnosticCode.unexpectedError,
      maskErrors ? _maskedMessage : error.toString(),
    );
    return SingleResponse(
      RequestErrorResult(errors: [_hooked(error, stackTrace, reported)]),
      outcome: ServerOutcome.internalError,
    );
  }

  GraphQLError _hooked(
    Object error,
    StackTrace stackTrace,
    GraphQLError reported,
  ) {
    final hook = onError;
    if (hook == null) {
      return reported;
    }
    try {
      return hook(error, stackTrace, reported) ?? reported;
    } on Object {
      return _coded(DiagnosticCode.unexpectedError, _maskedMessage);
    }
  }

  GraphQLError _coded(DiagnosticCode code, String message) => GraphQLError(
    message,
    extensions: JsonObject({'code': JsonString(code.id)}),
  );
}
```

Create `packages/typed_graphql_server/lib/src/server/request_step.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'context_factory.dart';
import 'document_entry.dart';
import 'document_step.dart';
import 'execution_job.dart';
import 'execution_step.dart';
import 'operation_lookup.dart';
import 'pipeline_errors.dart';
import 'server_limits.dart';
import 'server_outcome.dart';
import 'server_request.dart';
import 'server_response.dart';

/// The pipeline of section 6 from the length check to the execution. The
/// extension chains of the request, document and execution phases wrap
/// [run], [documentStep] and [executionStep] respectively.
@internal
final class RequestStep<C> {
  /// Creates the step.
  const RequestStep({
    required this.limits,
    required this.documentStep,
    required this.contextFactory,
    required this.executionStep,
    required this.errors,
  });

  /// The limits the length check reads.
  final ServerLimits limits;

  /// The document phase.
  final DocumentStep documentStep;

  /// Builds the context, after every refusal has been passed.
  final ContextFactory<C> contextFactory;

  /// The execution phase.
  final ExecutionStep<C> executionStep;

  /// Makes the refusals.
  final PipelineErrors errors;

  /// Serves [request]; may throw, the caller turns that into a response.
  Future<ServerResponse> run(ServerRequest request) async {
    final text = request.params.query;
    final maxLength = limits.maxDocumentLength;
    if (text != null && maxLength != null && text.length > maxLength) {
      return errors.refusal(
        DiagnosticCode.documentTooLong,
        'The document is longer than the maximum of $maxLength characters.',
      );
    }
    if (text == null || text.isEmpty) {
      return errors.refusal(
        DiagnosticCode.queryRequired,
        'Must provide query string.',
      );
    }
    return switch (documentStep.run(text)) {
      RejectedEntry(errors: final rejected) => errors.rejected(rejected),
      final AcceptedEntry accepted => _accepted(accepted, request),
    };
  }

  Future<ServerResponse> _accepted(
    AcceptedEntry entry,
    ServerRequest request,
  ) async {
    final type = const OperationLookup().typeOf(
      entry.document.document,
      request.params.operationName,
    );
    if (type == OperationType.mutation &&
        request.info.method.toUpperCase() == 'GET') {
      return errors.refusal(
        DiagnosticCode.mutationRequiresPost,
        'A mutation can only be sent with the POST method.',
        outcome: ServerOutcome.methodNotAllowed,
        headers: const {'allow': 'POST'},
      );
    }
    final context = await contextFactory(request.info);
    return executionStep.run(
      ExecutionJob<C>(
        entry: entry,
        operationType: type,
        context: context,
        request: request,
      ),
    );
  }
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index aea3bf1..e4b1095 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -56,6 +56,7 @@ export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
 export 'src/server/context_factory.dart';
 export 'src/server/csrf_prevention.dart';
+export 'src/server/graphql_server.dart';
 export 'src/server/request_info.dart';
 export 'src/server/server_limits.dart';
 export 'src/server/server_outcome.dart';
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
git add -A packages
git commit -m "feat(typed_graphql_server): add GraphQLServer

<your model trailer>"
```

### Task 6: fix(typed_graphql_server): address the GraphQLServer review

**Why.** Answers the review of Task 5 (`GraphQLServer`): guards the `toString` of an unexpected error, shares the masked message with the executor (a new `masked_message.dart` in `execution/`, used by the coercion and error-reporting code), splits and extends the pipeline tests, documents that the executor's refusals follow the context, and rewraps the changelog bullet.

**Files** (commit `512daf6`):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart`
- Modify `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart`
- Modify `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`
- Create `packages/typed_graphql_server/lib/src/execution/masked_message.dart`
- Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Modify `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart`
- Modify `packages/typed_graphql_server/test/server/graphql_server_test.dart`
- Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/server/graphql_server_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/graphql_server_test.dart b/packages/typed_graphql_server/test/server/graphql_server_test.dart
index e9e1d08..dd93aef 100644
--- a/packages/typed_graphql_server/test/server/graphql_server_test.dart
+++ b/packages/typed_graphql_server/test/server/graphql_server_test.dart
@@ -194,19 +194,80 @@ void main() {
       );
       expect(fixture.codeOf(response), 'GQL321');
     });
+    test('a mutation named next to an anonymous query is GQL402', () async {
+      // The lone-anonymous rule would refuse this document first.
+      final response = await fixture
+          .server(validationRules: [])
+          .handle(
+            fixture.request(
+              '{ hello } mutation M { bump }',
+              method: 'GET',
+              operationName: 'M',
+            ),
+          );
+      expect(fixture.codeOf(response), 'GQL402');
+    });
+
+    test('an empty operation name names no operation: GQL320', () async {
+      final response = await fixture.server().handle(
+        fixture.request('{ hello }', operationName: ''),
+      );
+      expect(fixture.codeOf(response), 'GQL320');
+    });
+  });
+
+  group('the context factory', () {
+    int built = 0;
+
+    GraphQLServer<Ctx> counting() => fixture.server(
+      contextFactory: (_) {
+        built++;
+        return const Ctx('x');
+      },
+    );
+
+    setUp(() => built = 0);
+
+    test('is not called for a mutation over GET', () async {
+      await counting().handle(
+        fixture.request('mutation { bump }', method: 'GET'),
+      );
+      expect(built, 0);
+    });
 
-    test('a refusal before the context never builds it', () async {
-      var built = 0;
+    test('is not called for an invalid document', () async {
+      await counting().handle(fixture.request('{ nothing }'));
+      expect(built, 0);
+    });
+
+    test('is not called without a query', () async {
+      await counting().handle(fixture.request(null));
+      expect(built, 0);
+    });
+
+    test('throwing synchronously gives GQL330', () async {
       final server = fixture.server(
         contextFactory: (_) {
-          built++;
-          return const Ctx('x');
+          throw StateError('boom');
         },
       );
-      await server.handle(fixture.request('mutation { bump }', method: 'GET'));
-      await server.handle(fixture.request('{ nothing }'));
-      await server.handle(fixture.request(null));
-      expect(built, 0);
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.codeOf(response), 'GQL330');
+      expect(
+        (response as SingleResponse).outcome,
+        ServerOutcome.internalError,
+      );
+    });
+
+    test('throwing an object whose toString throws still answers', () async {
+      final server = fixture.server(
+        contextFactory: (_) {
+          throw const UnprintableError();
+        },
+      );
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.codeOf(response), 'GQL330');
+      expect(fixture.messageOf(response), 'Unexpected error.');
     });
   });
 
```

Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/support/server_fixture.dart b/packages/typed_graphql_server/test/server/support/server_fixture.dart
index 8ac1e5c..1b2ff59 100644
--- a/packages/typed_graphql_server/test/server/support/server_fixture.dart
+++ b/packages/typed_graphql_server/test/server/support/server_fixture.dart
@@ -10,6 +10,14 @@ final class Ctx {
   final String tag;
 }
 
+/// A thrown object whose description cannot be made.
+final class UnprintableError implements Exception {
+  const UnprintableError();
+
+  @override
+  String toString() => throw StateError('no description');
+}
+
 /// A visitor that does nothing.
 final class IdleVisitor extends AstVisitor {
   const IdleVisitor();
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The extended `graphql_server_test.dart` and its fixture fail on the tree Task 5 leaves: the guarded `toString` and the shared masking are not there yet.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index de2c476..4ee55b6 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -152,8 +152,8 @@
 - `ServerProfile` (`development`, `production`, one `with*` method per
   protection), `ServerLimits` and `CsrfPrevention`: the protections of a
   server as values that compare by value.
-- `GraphQLServer<C>`: `handle(ServerRequest)` runs the request pipeline (document
-  length, `GQL400`/`GQL401`, the document cache, the operation lookup, `GQL402`
-  for a mutation over `GET`, the context factory, execution or subscription
-  with the options of the `ServerProfile`) and never throws; unexpected errors
-  go to `onError` and are masked (`GQL330`) per the profile.
+- `GraphQLServer<C>`: `handle(ServerRequest)` runs the request pipeline
+  (document length, `GQL400`/`GQL401`, the document cache, the operation
+  lookup, `GQL402` for a mutation over `GET`, the context factory, execution
+  or subscription with the options of the `ServerProfile`) and never throws;
+  unexpected errors go to `onError` and are masked (`GQL330`) per the profile.
```

Modify `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart b/packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart
index e5aec6e..03fee30 100644
--- a/packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart
+++ b/packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart
@@ -2,6 +2,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../builder/arguments.dart';
 import '../execution/graphql_exception.dart';
+import '../execution/masked_message.dart';
 import 'coercion_environment.dart';
 import 'coercion_problems.dart';
 import 'input_path.dart';
@@ -40,7 +41,7 @@ final class InputObjectDecoder {
       problems.add(exception.message, path, extensions: exception.extensions);
     } on Object catch (error, stackTrace) {
       problems.add(
-        'Unexpected error.',
+        const MaskedMessage().text,
         path,
         code: DiagnosticCode.inputDecodeFailed,
         thrown: (error: error, stackTrace: stackTrace),
```

Modify `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart b/packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart
index 116bf8f..6497efe 100644
--- a/packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart
+++ b/packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart
@@ -2,6 +2,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../builder/enum_type_def.dart';
 import '../builder/scalar_type_def.dart';
+import '../execution/masked_message.dart';
 import 'coercion_environment.dart';
 import 'coercion_problems.dart';
 import 'input_path.dart';
@@ -57,7 +58,7 @@ final class LeafCoercion {
       result = codec.decode(value);
     } on Object catch (error, stackTrace) {
       problems.add(
-        'Unexpected error.',
+        const MaskedMessage().text,
         path,
         code: DiagnosticCode.unexpectedError,
         thrown: (error: error, stackTrace: stackTrace),
```

Modify `packages/typed_graphql_server/lib/src/execution/error_reporter.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/execution/error_reporter.dart b/packages/typed_graphql_server/lib/src/execution/error_reporter.dart
index 325074a..e632f5b 100644
--- a/packages/typed_graphql_server/lib/src/execution/error_reporter.dart
+++ b/packages/typed_graphql_server/lib/src/execution/error_reporter.dart
@@ -5,6 +5,7 @@ import 'completion_site.dart';
 import 'error_log.dart';
 import 'execution_options.dart';
 import 'graphql_exception.dart';
+import 'masked_message.dart';
 import 'response_path.dart';
 
 /// Makes the errors of an execution (spec 7): the library's own, with their
@@ -76,7 +77,7 @@ final class ErrorReporter {
         extensions: extensions,
       ),
       _ => GraphQLError(
-        options.maskErrors ? _masked : error.toString(),
+        options.maskErrors ? const MaskedMessage().text : error.toString(),
         extensions: _codeOf(DiagnosticCode.subscriptionSourceFailed),
       ),
     };
@@ -99,7 +100,7 @@ final class ErrorReporter {
       return hook(error, stackTrace, reported) ?? reported;
     } on Object {
       return GraphQLError(
-        _masked,
+        const MaskedMessage().text,
         locations: reported.locations,
         path: reported.path,
         extensions: _codeOf(DiagnosticCode.unexpectedError),
@@ -107,8 +108,6 @@ final class ErrorReporter {
     }
   }
 
-  static const String _masked = 'Unexpected error.';
-
   GraphQLError _reportedFor(
     Object error,
     ResponsePath path,
@@ -122,7 +121,7 @@ final class ErrorReporter {
     ),
     _ => _coded(
       DiagnosticCode.unexpectedError,
-      options.maskErrors ? _masked : error.toString(),
+      options.maskErrors ? const MaskedMessage().text : error.toString(),
       path,
       nodes,
     ),
```

Create `packages/typed_graphql_server/lib/src/execution/masked_message.dart`:

```dart
import 'package:meta/meta.dart';

/// The message that replaces an unexpected error when errors are masked
/// (`GQL330`), shared by the executor, the coercion and the server pipeline.
@internal
final class MaskedMessage {
  /// Creates the holder.
  const MaskedMessage();

  /// The text clients see instead of the error's `toString()`.
  String get text => 'Unexpected error.';
}
```

Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/graphql_server.dart b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
index 7ef1355..9ebbe88 100644
--- a/packages/typed_graphql_server/lib/src/server/graphql_server.dart
+++ b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
@@ -20,8 +20,10 @@ import 'server_response.dart';
 /// executes (R5.1).
 ///
 /// It knows nothing of HTTP: a transport decodes a [ServerRequest] and
-/// writes the [ServerResponse]. Every refusal comes before the context is
-/// built and before any resolver runs.
+/// writes the [ServerResponse]. Every refusal of the server (length,
+/// document, method, limits) comes before the context is built and before
+/// any resolver runs; the refusals of the executor (an unknown operation
+/// name, invalid variables) come after the context is built.
 ///
 /// {@category server}
 final class GraphQLServer<C> {
```

Modify `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart b/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
index 02d7b1b..4c70e91 100644
--- a/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
+++ b/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../execution/error_hook.dart';
 import '../execution/graphql_exception.dart';
+import '../execution/masked_message.dart';
 import 'server_outcome.dart';
 import 'server_response.dart';
 
@@ -19,8 +20,6 @@ final class PipelineErrors {
   /// The server's error hook, null when there is none.
   final ErrorHook? onError;
 
-  static const String _maskedMessage = 'Unexpected error.';
-
   /// A refusal with one error coded [code].
   SingleResponse refusal(
     DiagnosticCode code,
@@ -49,7 +48,7 @@ final class PipelineErrors {
   SingleResponse internal(Object error, StackTrace stackTrace) {
     final reported = _coded(
       DiagnosticCode.unexpectedError,
-      maskErrors ? _maskedMessage : error.toString(),
+      _describe(error),
     );
     return SingleResponse(
       RequestErrorResult(errors: [_hooked(error, stackTrace, reported)]),
@@ -57,6 +56,16 @@ final class PipelineErrors {
     );
   }
 
+  // A `toString()` that throws must not turn the report into a failure.
+  String _describe(Object error) {
+    if (maskErrors) return const MaskedMessage().text;
+    try {
+      return error.toString();
+    } on Object {
+      return const MaskedMessage().text;
+    }
+  }
+
   GraphQLError _hooked(
     Object error,
     StackTrace stackTrace,
@@ -69,7 +78,7 @@ final class PipelineErrors {
     try {
       return hook(error, stackTrace, reported) ?? reported;
     } on Object {
-      return _coded(DiagnosticCode.unexpectedError, _maskedMessage);
+      return _coded(DiagnosticCode.unexpectedError, const MaskedMessage().text);
     }
   }
 
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
git add -A packages
git commit -m "fix(typed_graphql_server): address the GraphQLServer review

<your model trailer>"
```

### Task 7: feat(typed_graphql_server): add ServerExtension and CSRF prevention in the pipeline

**Why.** Adds `ServerExtension` (spec section 9): hooks for the request, document and execution phases. The chains are composed once, at construction (`ExtensionChain`). CSRF prevention becomes an internal extension placed inside the user's extensions, so their hooks see its refusal (`CsrfExtension`). The document cache now stores a `DocumentResult` instead of `DocumentEntry` (deleted), the phases get request objects and handlers, `ExecutionJob` is replaced by `ExecutionRequest`, and the execution options are built before the chain runs.

**Files** (commit `0d720f7`):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Create `packages/typed_graphql_server/lib/src/server/csrf_extension.dart`
- Modify `packages/typed_graphql_server/lib/src/server/document_cache.dart`
- Modify `packages/typed_graphql_server/lib/src/server/document_compiler.dart`
- Delete `packages/typed_graphql_server/lib/src/server/document_entry.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_handler.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_length.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_request.dart`
- Create `packages/typed_graphql_server/lib/src/server/document_result.dart`
- Modify `packages/typed_graphql_server/lib/src/server/document_step.dart`
- Create `packages/typed_graphql_server/lib/src/server/execution_handler.dart`
- Delete `packages/typed_graphql_server/lib/src/server/execution_job.dart`
- Create `packages/typed_graphql_server/lib/src/server/execution_request.dart`
- Modify `packages/typed_graphql_server/lib/src/server/execution_step.dart`
- Create `packages/typed_graphql_server/lib/src/server/extension_chain.dart`
- Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Modify `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart`
- Create `packages/typed_graphql_server/lib/src/server/request_handler.dart`
- Modify `packages/typed_graphql_server/lib/src/server/request_step.dart`
- Create `packages/typed_graphql_server/lib/src/server/server_extension.dart`
- Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Modify `packages/typed_graphql_server/test/server/document_cache_test.dart`
- Modify `packages/typed_graphql_server/test/server/document_compiler_test.dart`
- Create `packages/typed_graphql_server/test/server/server_csrf_test.dart`
- Create `packages/typed_graphql_server/test/server/server_execute_hooks_test.dart`
- Create `packages/typed_graphql_server/test/server/server_extension_test.dart`
- Modify `packages/typed_graphql_server/test/server/support/compiler_fixture.dart`
- Create `packages/typed_graphql_server/test/server/support/hook_extension.dart`
- Create `packages/typed_graphql_server/test/server/support/recording_extension.dart`
- Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/server/document_cache_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/document_cache_test.dart b/packages/typed_graphql_server/test/server/document_cache_test.dart
index 41efd2c..b3256ac 100644
--- a/packages/typed_graphql_server/test/server/document_cache_test.dart
+++ b/packages/typed_graphql_server/test/server/document_cache_test.dart
@@ -1,7 +1,7 @@
 import 'package:test/test.dart';
 import 'package:typed_graphql_server/src/server/document_cache.dart';
-import 'package:typed_graphql_server/src/server/document_entry.dart';
 import 'package:typed_graphql_server/src/server/document_hash.dart';
+import 'package:typed_graphql_server/src/server/document_result.dart';
 
 import 'support/compiler_fixture.dart';
 
@@ -28,8 +28,8 @@ void main() {
     test('returns the same accepted entry for the same text', () {
       final cache = DocumentCache(10);
       final compiler = fixture.countingCompiler;
-      final first = cache.entryFor('{a}', compiler);
-      final second = cache.entryFor('{a}', compiler);
+      final first = cache.resultFor('{a}', compiler);
+      final second = cache.resultFor('{a}', compiler);
       expect(second, same(first));
       expect(compiler.calls, 1);
     });
@@ -37,21 +37,23 @@ void main() {
     test('the accepted entry holds one ValidDocument for the text', () {
       final cache = DocumentCache(10);
       final compiler = fixture.compiler;
-      final first = cache.entryFor('{a}', compiler) as AcceptedEntry;
-      final second = cache.entryFor('{a}', compiler) as AcceptedEntry;
+      final first = cache.resultFor('{a}', compiler) as DocumentAccepted;
+      final second = cache.resultFor('{a}', compiler) as DocumentAccepted;
       expect(second.document, same(first.document));
     });
 
-    test('the entry carries the hash of the text', () {
-      final entry = DocumentCache(10).entryFor('{a}', fixture.compiler);
-      expect(entry.hash, const DocumentHash().of('{a}'));
+    test('the result carries the hash of the text', () {
+      final result = DocumentCache(
+        10,
+      ).resultFor('{a}', fixture.compiler) as DocumentAccepted;
+      expect(result.hash, const DocumentHash().of('{a}'));
     });
 
     test('compiles a failure once', () {
       final cache = DocumentCache(10);
       final compiler = fixture.countingCompiler;
-      final first = cache.entryFor('{', compiler);
-      final second = cache.entryFor('{', compiler);
+      final first = cache.resultFor('{', compiler);
+      final second = cache.resultFor('{', compiler);
       expect(second, same(first));
       expect(compiler.calls, 1);
     });
@@ -60,11 +62,11 @@ void main() {
       final cache = DocumentCache(2);
       final compiler = fixture.countingCompiler;
       cache
-        ..entryFor('{a}', compiler)
-        ..entryFor('{ a }', compiler)
-        ..entryFor('{  a }', compiler);
+        ..resultFor('{a}', compiler)
+        ..resultFor('{ a }', compiler)
+        ..resultFor('{  a }', compiler);
       expect(cache.length, 2);
-      cache.entryFor('{a}', compiler);
+      cache.resultFor('{a}', compiler);
       expect(compiler.calls, 4);
     });
 
@@ -72,14 +74,14 @@ void main() {
       final cache = DocumentCache(2);
       final compiler = fixture.countingCompiler;
       cache
-        ..entryFor('{a}', compiler)
-        ..entryFor('{ a }', compiler)
-        ..entryFor('{a}', compiler)
-        ..entryFor('{  a }', compiler);
+        ..resultFor('{a}', compiler)
+        ..resultFor('{ a }', compiler)
+        ..resultFor('{a}', compiler)
+        ..resultFor('{  a }', compiler);
       expect(compiler.calls, 3);
-      cache.entryFor('{a}', compiler);
+      cache.resultFor('{a}', compiler);
       expect(compiler.calls, 3);
-      cache.entryFor('{ a }', compiler);
+      cache.resultFor('{ a }', compiler);
       expect(compiler.calls, 4);
     });
 
@@ -87,8 +89,8 @@ void main() {
       final cache = DocumentCache(0);
       final compiler = fixture.countingCompiler;
       cache
-        ..entryFor('{a}', compiler)
-        ..entryFor('{a}', compiler);
+        ..resultFor('{a}', compiler)
+        ..resultFor('{a}', compiler);
       expect(compiler.calls, 2);
       expect(cache.length, 0);
     });
```

Modify `packages/typed_graphql_server/test/server/document_compiler_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/document_compiler_test.dart b/packages/typed_graphql_server/test/server/document_compiler_test.dart
index e6f2e0a..c905775 100644
--- a/packages/typed_graphql_server/test/server/document_compiler_test.dart
+++ b/packages/typed_graphql_server/test/server/document_compiler_test.dart
@@ -1,6 +1,6 @@
 import 'package:test/test.dart';
 import 'package:typed_graphql/typed_graphql.dart';
-import 'package:typed_graphql_server/src/server/document_entry.dart';
+import 'package:typed_graphql_server/src/server/document_result.dart';
 
 import 'support/compiler_fixture.dart';
 
@@ -11,18 +11,21 @@ void main() {
     text,
     'hash',
   )) {
-    RejectedEntry(:final errors) => errors,
-    AcceptedEntry() => throw StateError('expected a rejection'),
+    DocumentRejected(:final errors) => errors,
+    DocumentAccepted() => throw StateError('expected a rejection'),
   };
 
   test('a valid text is accepted with its source', () {
     final entry = compiler.compile('{ a }', 'hash');
-    expect(entry, isA<AcceptedEntry>());
-    expect((entry as AcceptedEntry).source.body, '{ a }');
+    expect(entry, isA<DocumentAccepted>());
+    expect((entry as DocumentAccepted).source.body, '{ a }');
   });
 
-  test('the entry keeps the hash it was given', () {
-    expect(compiler.compile('{ a }', 'the-hash').hash, 'the-hash');
+  test('an accepted result keeps the hash it was given', () {
+    expect(
+      (compiler.compile('{ a }', 'the-hash') as DocumentAccepted).hash,
+      'the-hash',
+    );
   });
 
   test('a syntax error becomes an error with its code and location', () {
```

Create `packages/typed_graphql_server/test/server/server_csrf_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/recording_extension.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  group('in production', () {
    test('a GET without content type or preflight header is GQL403', () async {
      var built = 0;
      final server = fixture.server(
        profile: ServerProfile.production,
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
      );
      final response = await server.handle(
        fixture.request('{ hello }', method: 'GET', headers: const {}),
      );
      expect(fixture.codeOf(response), 'GQL403');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      expect(built, 0);
    });

    test('a POST with application/json passes', () async {
      final response = await fixture
          .server(profile: ServerProfile.production)
          .handle(fixture.request('{ hello }'));
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a GET with a preflight header passes', () async {
      final response = await fixture
          .server(profile: ServerProfile.production)
          .handle(
            fixture.request(
              '{ hello }',
              method: 'GET',
              headers: const {'apollo-require-preflight': 'true'},
            ),
          );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('withCsrfPrevention(null) turns it off', () async {
      final server = fixture.server(
        profile: ServerProfile.production.withCsrfPrevention(null),
      );
      final response = await server.handle(
        fixture.request('{ hello }', method: 'GET', headers: const {}),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  test('the user extensions see the refusal', () async {
    final log = <String>[];
    final server = fixture.server(
      profile: ServerProfile.production,
      extensions: [RecordingExtension('a', log)],
    );
    final response = await server.handle(
      fixture.request('{ hello }', method: 'GET', headers: const {}),
    );
    expect(fixture.codeOf(response), 'GQL403');
    expect(log, ['a:request', '/a:request']);
  });
}
```

Create `packages/typed_graphql_server/test/server/server_execute_hooks_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  test('withContext reaches the resolvers', () async {
    final server = fixture.server(
      extensions: [
        HookExtension(
          execute: (request, next) =>
              next(request.withContext(const Ctx('hook'))),
        ),
      ],
    );
    final response = await server.handle(fixture.request('{ tag }'));
    expect(fixture.json(response)['data'], {'tag': 'hook'});
  });

  test('withOptions takes effect: introspection in production', () async {
    final server = fixture.server(
      profile: ServerProfile.production,
      extensions: [
        HookExtension(
          execute: (request, next) => next(
            request.withOptions(
              ExecutionOptions(
                source: request.options.source,
                introspection: .enabled,
              ),
            ),
          ),
        ),
      ],
    );
    final response = await server.handle(
      fixture.request('{ __schema { queryType { name } } }'),
    );
    expect(fixture.json(response)['data'], isNotNull);
  });

  test('the options hold the profile settings before any hook', () async {
    ExecutionOptions? seen;
    final server = fixture.server(
      profile: ServerProfile.production,
      extensions: [
        HookExtension(
          execute: (request, next) {
            seen = request.options;
            return next(request);
          },
        ),
      ],
    );
    await server.handle(fixture.request('{ hello }'));
    expect(seen?.maskErrors, isTrue);
    expect(seen?.source?.body, '{ hello }');
  });

  test('sees the response coming back and may add headers', () async {
    final server = fixture.server(
      extensions: [
        HookExtension(
          execute: (request, next) async =>
              (await next(request)).withHeaders({'X-Trace': '1'}),
        ),
      ],
    );
    final response = await server.handle(fixture.request('{ hello }'));
    expect(response.headers, {'x-trace': '1'});
  });

  test('is not reached by a rejected document', () async {
    var reached = false;
    final server = fixture.server(
      extensions: [
        HookExtension(
          execute: (request, next) {
            reached = true;
            return next(request);
          },
        ),
      ],
    );
    await server.handle(fixture.request('{ nothing }'));
    expect(reached, isFalse);
  });
}
```

Create `packages/typed_graphql_server/test/server/server_extension_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/recording_extension.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();

  group('the order of the hooks', () {
    test('the first extension is the outermost in every phase', () async {
      final log = <String>[];
      final server = fixture.server(
        extensions: [
          RecordingExtension('a', log),
          RecordingExtension('b', log),
        ],
      );
      await server.handle(fixture.request('{ hello }'));
      expect(log, [
        'a:request',
        'b:request',
        'a:document',
        'b:document',
        '/b:document',
        '/a:document',
        'a:execute',
        'b:execute',
        '/b:execute',
        '/a:execute',
        '/b:request',
        '/a:request',
      ]);
    });

    test('a request without extensions is served', () async {
      final response = await fixture.server().handle(
        fixture.request('{ hello }'),
      );
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  group('onRequest', () {
    test('may answer itself: nothing else runs', () async {
      final log = <String>[];
      var built = 0;
      final server = fixture.server(
        contextFactory: (_) {
          built++;
          return const Ctx('x');
        },
        extensions: [
          HookExtension(
            request: (request, next) async => SingleResponse(
              RequestErrorResult(errors: [GraphQLError('Closed')]),
              outcome: ServerOutcome.requestError,
            ),
          ),
          RecordingExtension('inner', log),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'Closed');
      expect(log, isEmpty);
      expect(built, 0);
    });

    test('sees the response coming back and may add headers', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            request: (request, next) async =>
                (await next(request)).withHeaders({'X-Served': 'yes'}),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(response.headers, {'x-served': 'yes'});
    });
  });

  group('onDocument', () {
    test('replacing the text runs the replacement', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) => next(request.withText('{ tag }')),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.json(response)['data'], {'tag': 'default'});
    });

    test('rejecting is a request error with its errors', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) async =>
                DocumentRejected([GraphQLError('Not allowed')]),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.messageOf(response), 'Not allowed');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('a text over the maximum is GQL401', () async {
      final server = fixture.server(
        profile: const ServerProfile(
          introspection: .enabled,
          includesSuggestions: true,
          maskErrors: false,
          csrfPrevention: null,
          limits: ServerLimits(maxDocumentLength: 10),
        ),
        extensions: [
          HookExtension(
            document: (request, next) =>
                next(request.withText('{ hello } # long comment')),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL401');
    });

    test('an empty text is GQL400', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) => next(request.withText('')),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL400');
    });

    test('the same text gives the identical document twice', () async {
      final documents = <ValidDocument>[];
      final server = fixture.server(
        extensions: [
          HookExtension(
            execute: (request, next) {
              documents.add(request.document);
              return next(request);
            },
          ),
        ],
      );
      await server.handle(fixture.request('{ hello }'));
      await server.handle(fixture.request('{ hello }'));
      expect(documents[1], same(documents[0]));
    });

    test('the accepted hash is the SHA-256 the server computed', () async {
      final hashes = <String>[];
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) async {
              final result = await next(request);
              if (result case DocumentAccepted(:final hash)) hashes.add(hash);
              return result;
            },
          ),
        ],
      );
      await server.handle(fixture.request('{ hello }'));
      expect(hashes.single, hasLength(64));
    });
  });

  group('errors of a hook', () {
    test('a GraphQLException is a request error with its extensions', () async {
      final server = fixture.server(
        extensions: [
          HookExtension(
            document: (request, next) => throw GraphQLException(
              'Denied',
              extensions: JsonObject({'code': const JsonString('DENIED')}),
            ),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'DENIED');
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    });

    test('any other error is masked and seen by onError', () async {
      final seen = <Object>[];
      final server = fixture.server(
        profile: ServerProfile.production,
        onError: (error, stackTrace, reported) {
          seen.add(error);
          return null;
        },
        extensions: [
          HookExtension(
            request: (request, next) => throw StateError('secret'),
          ),
        ],
      );
      final response = await server.handle(fixture.request('{ hello }'));
      expect(fixture.codeOf(response), 'GQL330');
      expect(fixture.messageOf(response), 'Unexpected error.');
      expect(seen.single, isA<StateError>());
    });
  });
}
```

Modify `packages/typed_graphql_server/test/server/support/compiler_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/support/compiler_fixture.dart b/packages/typed_graphql_server/test/server/support/compiler_fixture.dart
index 54452eb..41593fb 100644
--- a/packages/typed_graphql_server/test/server/support/compiler_fixture.dart
+++ b/packages/typed_graphql_server/test/server/support/compiler_fixture.dart
@@ -1,6 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/src/server/document_compiler.dart';
-import 'package:typed_graphql_server/src/server/document_entry.dart';
+import 'package:typed_graphql_server/src/server/document_result.dart';
 
 /// A small valid schema and compilers over it.
 final class CompilerFixture {
@@ -31,7 +31,7 @@ final class CountingCompiler extends DocumentCompiler {
   int calls = 0;
 
   @override
-  DocumentEntry compile(String text, String hash) {
+  DocumentResult compile(String text, String hash) {
     calls++;
     return super.compile(text, hash);
   }
```

Create `packages/typed_graphql_server/test/server/support/hook_extension.dart`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// An extension whose three hooks are given as functions; a missing one calls
/// `next`.
final class HookExtension extends ServerExtension<Ctx> {
  const HookExtension({this.request, this.document, this.execute});

  final Future<ServerResponse> Function(ServerRequest, RequestHandler)? request;
  final Future<DocumentResult> Function(DocumentRequest, DocumentHandler)?
  document;
  final Future<ServerResponse> Function(
    ExecutionRequest<Ctx>,
    ExecutionHandler<Ctx>,
  )?
  execute;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) => (this.request ?? super.onRequest)(request, next);

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) => (document ?? super.onDocument)(request, next);

  @override
  Future<ServerResponse> onExecute(
    ExecutionRequest<Ctx> request,
    ExecutionHandler<Ctx> next,
  ) => (execute ?? super.onExecute)(request, next);
}
```

Create `packages/typed_graphql_server/test/server/support/recording_extension.dart`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// Writes `name:phase` when a hook is entered and `/name:phase` when it
/// returns, into a shared log.
final class RecordingExtension extends ServerExtension<Ctx> {
  const RecordingExtension(this.name, this.log);

  final String name;
  final List<String> log;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async {
    log.add('$name:request');
    final response = await next(request);
    log.add('/$name:request');
    return response;
  }

  @override
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) async {
    log.add('$name:document');
    final result = await next(request);
    log.add('/$name:document');
    return result;
  }

  @override
  Future<ServerResponse> onExecute(
    ExecutionRequest<Ctx> request,
    ExecutionHandler<Ctx> next,
  ) async {
    log.add('$name:execute');
    final response = await next(request);
    log.add('/$name:execute');
    return response;
  }
}
```

Modify `packages/typed_graphql_server/test/server/support/server_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/support/server_fixture.dart b/packages/typed_graphql_server/test/server/support/server_fixture.dart
index 1b2ff59..7037b95 100644
--- a/packages/typed_graphql_server/test/server/support/server_fixture.dart
+++ b/packages/typed_graphql_server/test/server/support/server_fixture.dart
@@ -91,6 +91,7 @@ final class ServerFixture {
     List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
     ErrorHook? onError,
     int documentCacheSize = 1000,
+    List<ServerExtension<Ctx>> extensions = const [],
   }) => GraphQLServer<Ctx>(
     schema: schema,
     contextFactory: contextFactory ?? (_) => const Ctx('default'),
@@ -98,6 +99,7 @@ final class ServerFixture {
     validationRules: validationRules,
     onError: onError,
     documentCacheSize: documentCacheSize,
+    extensions: extensions,
   );
 
   ServerRequest request(
@@ -106,13 +108,18 @@ final class ServerFixture {
     String? operationName,
     JsonObject? variables,
     CancelSignal? cancelSignal,
+    Map<String, String> headers = const {'content-type': 'application/json'},
   }) => ServerRequest(
     params: GraphQLRequest(
       query: query,
       operationName: operationName,
       variables: variables,
     ),
-    info: RequestInfo(method: method, uri: Uri.parse('/graphql')),
+    info: RequestInfo(
+      method: method,
+      uri: Uri.parse('/graphql'),
+      headers: headers,
+    ),
     cancelSignal: cancelSignal,
   );
 
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The new extension, CSRF and execute-hook tests use `ServerExtension` and the new request and handler types, which do not exist yet: compile errors. The edited cache and compiler tests use `DocumentResult`.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 4ee55b6..df8ca8a 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -157,3 +157,14 @@
   lookup, `GQL402` for a mutation over `GET`, the context factory, execution
   or subscription with the options of the `ServerProfile`) and never throws;
   unexpected errors go to `onError` and are masked (`GQL330`) per the profile.
+- `ServerExtension<C>`: three hooks (`onRequest`, `onDocument`, `onExecute`),
+  each with a default that calls `next`, passed to `GraphQLServer.extensions`
+  (the first is the outermost and sees even the requests CSRF prevention
+  refuses). `RequestHandler`, `DocumentHandler` and `ExecutionHandler<C>` are
+  the `next` types; `DocumentRequest` (`withText`), the sealed
+  `DocumentResult` (`DocumentAccepted` with the hash the server computed,
+  `DocumentRejected`) and `ExecutionRequest<C>` (`withContext`,
+  `withOptions`) are what the hooks take and return.
+- CSRF prevention (`GQL403`) runs in the request phase when the profile has a
+  `CsrfPrevention`: a request without a content type a browser cannot send
+  cross-site and without a preflight header is refused before any other step.
```

Create `packages/typed_graphql_server/lib/src/server/csrf_extension.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'csrf_prevention.dart';
import 'pipeline_errors.dart';
import 'request_handler.dart';
import 'server_extension.dart';
import 'server_request.dart';
import 'server_response.dart';

/// The request-phase check of [CsrfPrevention] (R5.4, R5.15): a request it
/// does not allow is `GQL403`. The server places it inside the user's
/// extensions, so their hooks see the refusal.
@internal
final class CsrfExtension<C> extends ServerExtension<C> {
  /// Creates the extension for [prevention], refusing through [errors].
  const CsrfExtension(this.prevention, this.errors);

  /// The rule that decides.
  final CsrfPrevention prevention;

  /// Makes the refusal.
  final PipelineErrors errors;

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async {
    if (prevention.allows(request.info)) return next(request);
    return errors.refusal(
      DiagnosticCode.csrfRequestBlocked,
      prevention.refusal,
    );
  }
}
```

Modify `packages/typed_graphql_server/lib/src/server/document_cache.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_cache.dart b/packages/typed_graphql_server/lib/src/server/document_cache.dart
index 1043069..638a26f 100644
--- a/packages/typed_graphql_server/lib/src/server/document_cache.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_cache.dart
@@ -3,8 +3,8 @@ import 'dart:collection';
 import 'package:meta/meta.dart';
 
 import 'document_compiler.dart';
-import 'document_entry.dart';
 import 'document_hash.dart';
+import 'document_result.dart';
 
 /// A least-recently-used cache of compiled documents, keyed by the SHA-256 of
 /// the text (R5.2).
@@ -24,29 +24,29 @@ final class DocumentCache {
   final int capacity;
 
   // Dart's default map keeps insertion order: the first key is the oldest.
-  final LinkedHashMap<String, DocumentEntry> _entries =
-      LinkedHashMap<String, DocumentEntry>();
+  final LinkedHashMap<String, DocumentResult> _entries =
+      LinkedHashMap<String, DocumentResult>();
 
   /// The number of entries held.
   @visibleForTesting
   int get length => _entries.length;
 
-  /// The entry for [text]: the stored one, which becomes the most recent, or
+  /// The result for [text]: the stored one, which becomes the most recent, or
   /// the one [compiler] makes, stored unless the capacity is 0.
-  DocumentEntry entryFor(String text, DocumentCompiler compiler) {
+  DocumentResult resultFor(String text, DocumentCompiler compiler) {
     final hash = const DocumentHash().of(text);
     final stored = _entries.remove(hash);
     if (stored != null) {
       _entries[hash] = stored;
       return stored;
     }
-    final entry = compiler.compile(text, hash);
+    final result = compiler.compile(text, hash);
     if (capacity > 0) {
-      _entries[hash] = entry;
+      _entries[hash] = result;
       if (_entries.length > capacity) {
         _entries.remove(_entries.keys.first);
       }
     }
-    return entry;
+    return result;
   }
 }
```

Modify `packages/typed_graphql_server/lib/src/server/document_compiler.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_compiler.dart b/packages/typed_graphql_server/lib/src/server/document_compiler.dart
index ee32407..6f4c8d4 100644
--- a/packages/typed_graphql_server/lib/src/server/document_compiler.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_compiler.dart
@@ -2,7 +2,7 @@ import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'diagnostic_errors.dart';
-import 'document_entry.dart';
+import 'document_result.dart';
 
 /// Parses and validates one document text against the server's schema.
 ///
@@ -22,13 +22,12 @@ class DocumentCompiler {
   /// The schema documents are validated against.
   final ValidSchema schema;
 
-  /// The entry for [text], whose SHA-256 is [hash]: the validated document,
+  /// The result for [text], whose SHA-256 is [hash]: the validated document,
   /// or the errors of the first stage that failed.
-  DocumentEntry compile(String text, String hash) {
+  DocumentResult compile(String text, String hash) {
     final source = Source(text);
     return switch (parser.parse(source)) {
-      ParseFailure(:final diagnostics) => RejectedEntry(
-        hash,
+      ParseFailure(:final diagnostics) => DocumentRejected(
         const DiagnosticErrors().of(diagnostics),
       ),
       ParseSuccess(:final document) => switch (validator.validate(
@@ -36,9 +35,8 @@ class DocumentCompiler {
         document,
         source: source,
       )) {
-        final ValidDocument valid => AcceptedEntry(hash, valid, source),
-        InvalidDocument(:final diagnostics) => RejectedEntry(
-          hash,
+        final ValidDocument valid => DocumentAccepted(valid, source, hash),
+        InvalidDocument(:final diagnostics) => DocumentRejected(
           const DiagnosticErrors().of(diagnostics),
         ),
       },
```

Delete `packages/typed_graphql_server/lib/src/server/document_entry.dart`.

Create `packages/typed_graphql_server/lib/src/server/document_handler.dart`:

```dart
import 'document_request.dart';
import 'document_result.dart';

/// The rest of the document phase, as an extension's `onDocument` sees it.
///
/// {@category server}
typedef DocumentHandler = Future<DocumentResult> Function(
  DocumentRequest request,
);
```

Create `packages/typed_graphql_server/lib/src/server/document_length.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'pipeline_errors.dart';

/// The `limits.maxDocumentLength` check, run on the request's query before
/// any hashing and again on a text an extension supplied (R5.4).
@internal
final class DocumentLength {
  /// Creates the check for [maximum] characters, null for no limit.
  const DocumentLength(this.maximum, this.errors);

  /// The most characters a document text may have.
  final int? maximum;

  /// Makes the error.
  final PipelineErrors errors;

  /// The `GQL401` error when [text] is longer than the maximum, else null.
  GraphQLError? violation(String? text) {
    final limit = maximum;
    if (text == null || limit == null || text.length <= limit) return null;
    return errors.coded(
      DiagnosticCode.documentTooLong,
      'The document is longer than the maximum of $limit characters.',
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/document_request.dart`:

```dart
import 'server_request.dart';

/// The input of the document phase: the request and the document text found
/// so far (R5.3).
///
/// {@category server}
final class DocumentRequest {
  /// Creates the input for [request] with the document [text], null when
  /// there is none yet.
  const DocumentRequest(this.request, {this.text});

  /// The request being served.
  final ServerRequest request;

  /// The document text so far: first `request.params.query`, then whatever
  /// an extension put in its place; null when there is none.
  final String? text;

  /// The same request with [text] as the document text.
  DocumentRequest withText(String? text) =>
      DocumentRequest(request, text: text);
}
```

Create `packages/typed_graphql_server/lib/src/server/document_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// What resolving a document text ends with: [DocumentAccepted] or
/// [DocumentRejected] (R5.2, R5.3).
///
/// {@category server}
sealed class DocumentResult {
  const DocumentResult();
}

/// A text that parsed and validated.
///
/// {@category server}
final class DocumentAccepted extends DocumentResult {
  /// Creates a result holding the [document], the [source] it came from and
  /// the [hash] of the text.
  const DocumentAccepted(this.document, this.source, this.hash);

  /// The validated document; the same object for every request with the same
  /// text while the server's cache holds it.
  final ValidDocument document;

  /// The text, for locations in later messages.
  final Source source;

  /// The SHA-256 of the text, as lower-case hex: the cache key the server
  /// computed, never a value a client sent.
  final String hash;
}

/// A text that did not resolve to a document: it is missing, too long, or it
/// did not parse or validate. The request ends as a request error.
///
/// {@category server}
final class DocumentRejected extends DocumentResult {
  /// Creates a result holding the [errors], which must not be empty.
  const DocumentRejected(this.errors);

  /// The errors the response carries.
  final List<GraphQLError> errors;
}
```

Modify `packages/typed_graphql_server/lib/src/server/document_step.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_step.dart b/packages/typed_graphql_server/lib/src/server/document_step.dart
index 4937ff1..a4c7063 100644
--- a/packages/typed_graphql_server/lib/src/server/document_step.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_step.dart
@@ -1,15 +1,20 @@
 import 'package:meta/meta.dart';
+import 'package:typed_graphql/typed_graphql.dart';
 
 import 'document_cache.dart';
 import 'document_compiler.dart';
-import 'document_entry.dart';
+import 'document_length.dart';
+import 'document_request.dart';
+import 'document_result.dart';
+import 'pipeline_errors.dart';
 
 /// The core step of the document phase: the text becomes a validated
 /// document or its errors, through the cache (R5.2).
 @internal
 final class DocumentStep {
-  /// Creates the step over [cache] and [compiler].
-  const DocumentStep(this.cache, this.compiler);
+  /// Creates the step over [cache] and [compiler], checking the text with
+  /// [length] and refusing through [errors].
+  const DocumentStep(this.cache, this.compiler, this.length, this.errors);
 
   /// Where compiled texts are kept.
   final DocumentCache cache;
@@ -17,6 +22,26 @@ final class DocumentStep {
   /// Compiles a text the cache does not hold.
   final DocumentCompiler compiler;
 
-  /// The entry for [text].
-  DocumentEntry run(String text) => cache.entryFor(text, compiler);
+  /// Checks the length again: an extension may have supplied the text.
+  final DocumentLength length;
+
+  /// Makes the errors of a missing text.
+  final PipelineErrors errors;
+
+  /// The result for the text of [request].
+  Future<DocumentResult> run(DocumentRequest request) async {
+    final text = request.text;
+    if (text == null || text.isEmpty) {
+      return DocumentRejected([
+        errors.coded(
+          DiagnosticCode.queryRequired,
+          'Must provide query string.',
+        ),
+      ]);
+    }
+    if (length.violation(text) case final violation?) {
+      return DocumentRejected([violation]);
+    }
+    return cache.resultFor(text, compiler);
+  }
 }
```

Create `packages/typed_graphql_server/lib/src/server/execution_handler.dart`:

```dart
import 'execution_request.dart';
import 'server_response.dart';

/// The rest of the execution phase, as an extension's `onExecute` sees it.
///
/// {@category server}
typedef ExecutionHandler<C> = Future<ServerResponse> Function(
  ExecutionRequest<C> request,
);
```

Delete `packages/typed_graphql_server/lib/src/server/execution_job.dart`.

Create `packages/typed_graphql_server/lib/src/server/execution_request.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/execution_options.dart';
import 'server_request.dart';

/// The input of the execution phase: the accepted document, the context and
/// the options the execution will use (R5.3, R5.15).
///
/// {@category server}
final class ExecutionRequest<C> {
  /// Creates the input.
  const ExecutionRequest({
    required this.request,
    required this.document,
    required this.operationType,
    required this.context,
    required this.options,
  });

  /// The request being served.
  final ServerRequest request;

  /// The validated document.
  final ValidDocument document;

  /// The kind of the selected operation, null when none could be selected
  /// (the execution then reports it).
  final OperationType? operationType;

  /// The context the context factory built.
  final C context;

  /// The options of the execution: the profile's settings and the document's
  /// source.
  final ExecutionOptions options;

  /// The same request with [context] as the context.
  ExecutionRequest<C> withContext(C context) => ExecutionRequest<C>(
    request: request,
    document: document,
    operationType: operationType,
    context: context,
    options: options,
  );

  /// The same request with [options] as the execution options.
  ExecutionRequest<C> withOptions(ExecutionOptions options) =>
      ExecutionRequest<C>(
        request: request,
        document: document,
        operationType: operationType,
        context: context,
        options: options,
      );
}
```

Modify `packages/typed_graphql_server/lib/src/server/execution_step.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/execution_step.dart b/packages/typed_graphql_server/lib/src/server/execution_step.dart
index 660c3e2..4f02d72 100644
--- a/packages/typed_graphql_server/lib/src/server/execution_step.dart
+++ b/packages/typed_graphql_server/lib/src/server/execution_step.dart
@@ -1,17 +1,18 @@
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../cancellation/cancel_signal.dart';
 import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
 import '../execution/execution_options.dart';
 import '../subscription/subscription_result.dart';
-import 'execution_job.dart';
+import 'execution_request.dart';
 import 'server_outcome.dart';
 import 'server_profile.dart';
 import 'server_response.dart';
 
 /// The core step of the execution phase: runs the operation with the
-/// options of section 12 and maps the result to a response.
+/// options of the request and maps the result to a response.
 @internal
 final class ExecutionStep<C> {
   /// Creates the step for [schema] under [profile], passing [onError] on.
@@ -26,31 +27,34 @@ final class ExecutionStep<C> {
   /// The server's error hook.
   final ErrorHook? onError;
 
-  /// The options of [job]: no timeout for a subscription, which would end a
-  /// long-lived stream.
-  ExecutionOptions optionsFor(ExecutionJob<C> job) => ExecutionOptions(
-    source: job.entry.source,
+  /// The options of section 12 for a request on [source]: no timeout for a
+  /// subscription, which would end a long-lived stream.
+  ExecutionOptions optionsFor(
+    Source source,
+    OperationType? operationType,
+    CancelSignal? cancelSignal,
+  ) => ExecutionOptions(
+    source: source,
     maskErrors: profile.maskErrors,
     onError: onError,
     includesSuggestions: profile.includesSuggestions,
     introspection: profile.introspection,
-    cancelSignal: job.request.cancelSignal,
-    timeout: job.operationType == OperationType.subscription
+    cancelSignal: cancelSignal,
+    timeout: operationType == OperationType.subscription
         ? null
         : profile.timeout,
   );
 
-  /// Executes [job] with its [optionsFor].
-  Future<ServerResponse> run(ExecutionJob<C> job) async {
-    final params = job.request.params;
-    final options = optionsFor(job);
-    if (job.operationType == OperationType.subscription) {
+  /// Executes [request] with its options and context.
+  Future<ServerResponse> run(ExecutionRequest<C> request) async {
+    final params = request.request.params;
+    if (request.operationType == OperationType.subscription) {
       final started = await schema.subscribe(
-        job.entry.document,
-        context: job.context,
+        request.document,
+        context: request.context,
         operationName: params.operationName,
         variables: params.variables,
-        options: options,
+        options: request.options,
       );
       return switch (started) {
         SubscriptionStarted(:final results) => StreamResponse(results),
@@ -61,11 +65,11 @@ final class ExecutionStep<C> {
       };
     }
     final payload = await schema.execute(
-      job.entry.document,
-      context: job.context,
+      request.document,
+      context: request.context,
       operationName: params.operationName,
       variables: params.variables,
-      options: options,
+      options: request.options,
     );
     return SingleResponse(
       payload,
```

Create `packages/typed_graphql_server/lib/src/server/extension_chain.dart`:

```dart
import 'package:meta/meta.dart';

import 'document_handler.dart';
import 'execution_handler.dart';
import 'request_handler.dart';
import 'server_extension.dart';

/// Composes the hooks of an ordered list of extensions around a core step,
/// once per phase when the server is built: the first extension is the
/// outermost.
@internal
final class ExtensionChain<C> {
  /// Creates the chain over [extensions].
  const ExtensionChain(this.extensions);

  /// The extensions, outermost first.
  final List<ServerExtension<C>> extensions;

  /// [core] wrapped in every `onRequest`.
  RequestHandler request(RequestHandler core) {
    var next = core;
    for (final extension in extensions.reversed) {
      final inner = next;
      next = (request) => extension.onRequest(request, inner);
    }
    return next;
  }

  /// [core] wrapped in every `onDocument`.
  DocumentHandler document(DocumentHandler core) {
    var next = core;
    for (final extension in extensions.reversed) {
      final inner = next;
      next = (request) => extension.onDocument(request, inner);
    }
    return next;
  }

  /// [core] wrapped in every `onExecute`.
  ExecutionHandler<C> execution(ExecutionHandler<C> core) {
    var next = core;
    for (final extension in extensions.reversed) {
      final inner = next;
      next = (request) => extension.onExecute(request, inner);
    }
    return next;
  }
}
```

Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/graphql_server.dart b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
index 9ebbe88..4318c57 100644
--- a/packages/typed_graphql_server/lib/src/server/graphql_server.dart
+++ b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
@@ -4,12 +4,17 @@ import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
 import '../execution/graphql_exception.dart';
 import 'context_factory.dart';
+import 'csrf_extension.dart';
 import 'document_cache.dart';
 import 'document_compiler.dart';
+import 'document_length.dart';
 import 'document_step.dart';
 import 'execution_step.dart';
+import 'extension_chain.dart';
 import 'pipeline_errors.dart';
+import 'request_handler.dart';
 import 'request_step.dart';
+import 'server_extension.dart';
 import 'server_limits.dart';
 import 'server_profile.dart';
 import 'server_request.dart';
@@ -35,6 +40,10 @@ final class GraphQLServer<C> {
   /// execution and sees the unexpected errors of the pipeline before they
   /// are masked. [documentCacheSize] is the most compiled documents kept;
   /// 0 keeps none and a negative size is an [ArgumentError].
+  ///
+  /// [extensions] hook into the three phases of a request; the first is the
+  /// outermost and sees even the requests the built-in checks (CSRF
+  /// prevention) refuse.
   factory GraphQLServer({
     required ExecutableSchema<C> schema,
     required ContextFactory<C> contextFactory,
@@ -42,35 +51,57 @@ final class GraphQLServer<C> {
     List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
     ErrorHook? onError,
     int documentCacheSize = 1000,
+    List<ServerExtension<C>> extensions = const [],
   }) {
     final errors = PipelineErrors(
       maskErrors: profile.maskErrors,
       onError: onError,
     );
-    final compiler = DocumentCompiler(
-      Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
-      DocumentValidator(
-        rules: [...validationRules, ..._limitRules(profile.limits)],
-        includesSuggestions: profile.includesSuggestions,
-      ),
-      schema.schema,
-    );
-    return GraphQLServer._(
-      errors,
-      RequestStep<C>(
-        limits: profile.limits,
-        documentStep: DocumentStep(DocumentCache(documentCacheSize), compiler),
-        contextFactory: contextFactory,
-        executionStep: ExecutionStep<C>(schema, profile, onError),
-        errors: errors,
+    final length = DocumentLength(profile.limits.maxDocumentLength, errors);
+    // The user's extensions come first (outermost), then the built-in ones
+    // in a fixed order, so no list order puts an unchecked step before a
+    // security check. M6c adds the trusted-document and APQ extensions here.
+    final chain = ExtensionChain<C>([
+      ...extensions,
+      if (profile.csrfPrevention case final csrf?)
+        CsrfExtension<C>(csrf, errors),
+    ]);
+    final executionStep = ExecutionStep<C>(schema, profile, onError);
+    final request = RequestStep<C>(
+      length: length,
+      documentPhase: chain.document(
+        DocumentStep(
+          DocumentCache(documentCacheSize),
+          _compiler(schema.schema, profile, validationRules),
+          length,
+          errors,
+        ).run,
       ),
+      contextFactory: contextFactory,
+      executionStep: executionStep,
+      executionPhase: chain.execution(executionStep.run),
+      errors: errors,
     );
+    return GraphQLServer._(errors, chain.request(request.run));
   }
 
   GraphQLServer._(this._errors, this._request);
 
   final PipelineErrors _errors;
-  final RequestStep<C> _request;
+  final RequestHandler _request;
+
+  static DocumentCompiler _compiler(
+    ValidSchema schema,
+    ServerProfile profile,
+    List<ValidationRule> validationRules,
+  ) => DocumentCompiler(
+    Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
+    DocumentValidator(
+      rules: [...validationRules, ..._limitRules(profile.limits)],
+      includesSuggestions: profile.includesSuggestions,
+    ),
+    schema,
+  );
 
   static List<ValidationRule> _limitRules(ServerLimits limits) => [
     if (limits.maxDepth case final maxDepth?) MaxDepthRule(maxDepth: maxDepth),
@@ -86,7 +117,7 @@ final class GraphQLServer<C> {
   /// other error goes to the error hook and is masked by the profile.
   Future<ServerResponse> handle(ServerRequest request) async {
     try {
-      return await _request.run(request);
+      return await _request(request);
     } on GraphQLException catch (exception) {
       return _errors.exception(exception);
     } on Object catch (error, stackTrace) {
```

Modify `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart b/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
index 4c70e91..ee76963 100644
--- a/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
+++ b/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
@@ -27,7 +27,7 @@ final class PipelineErrors {
     ServerOutcome outcome = ServerOutcome.requestError,
     Map<String, String> headers = const {},
   }) => SingleResponse(
-    RequestErrorResult(errors: [_coded(code, message)]),
+    RequestErrorResult(errors: [coded(code, message)]),
     outcome: outcome,
     headers: headers,
   );
@@ -46,7 +46,7 @@ final class PipelineErrors {
   /// The response to an unexpected [error]: offered to the hook, then
   /// masked (`GQL330`) or shown by its `toString()`.
   SingleResponse internal(Object error, StackTrace stackTrace) {
-    final reported = _coded(
+    final reported = coded(
       DiagnosticCode.unexpectedError,
       _describe(error),
     );
@@ -78,11 +78,12 @@ final class PipelineErrors {
     try {
       return hook(error, stackTrace, reported) ?? reported;
     } on Object {
-      return _coded(DiagnosticCode.unexpectedError, const MaskedMessage().text);
+      return coded(DiagnosticCode.unexpectedError, const MaskedMessage().text);
     }
   }
 
-  GraphQLError _coded(DiagnosticCode code, String message) => GraphQLError(
+  /// One error with [message] and `extensions.code` of [code].
+  GraphQLError coded(DiagnosticCode code, String message) => GraphQLError(
     message,
     extensions: JsonObject({'code': JsonString(code.id)}),
   );
```

Create `packages/typed_graphql_server/lib/src/server/request_handler.dart`:

```dart
import 'server_request.dart';
import 'server_response.dart';

/// The rest of the request phase, as an extension's `onRequest` sees it.
///
/// {@category server}
typedef RequestHandler = Future<ServerResponse> Function(ServerRequest request);
```

Modify `packages/typed_graphql_server/lib/src/server/request_step.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/request_step.dart b/packages/typed_graphql_server/lib/src/server/request_step.dart
index e8d01c9..8c35b67 100644
--- a/packages/typed_graphql_server/lib/src/server/request_step.dart
+++ b/packages/typed_graphql_server/lib/src/server/request_step.dart
@@ -2,74 +2,72 @@ import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'context_factory.dart';
-import 'document_entry.dart';
-import 'document_step.dart';
-import 'execution_job.dart';
+import 'document_handler.dart';
+import 'document_length.dart';
+import 'document_request.dart';
+import 'document_result.dart';
+import 'execution_handler.dart';
+import 'execution_request.dart';
 import 'execution_step.dart';
 import 'operation_lookup.dart';
 import 'pipeline_errors.dart';
-import 'server_limits.dart';
 import 'server_outcome.dart';
 import 'server_request.dart';
 import 'server_response.dart';
 
-/// The pipeline of section 6 from the length check to the execution. The
-/// extension chains of the request, document and execution phases wrap
-/// [run], [documentStep] and [executionStep] respectively.
+/// The core of the request phase (section 6 of the M6 spec): the length
+/// check, the document phase, the operation, the context and the execution
+/// phase. The extension chains wrap [run], [documentPhase] and
+/// [executionPhase].
 @internal
 final class RequestStep<C> {
   /// Creates the step.
   const RequestStep({
-    required this.limits,
-    required this.documentStep,
+    required this.length,
+    required this.documentPhase,
     required this.contextFactory,
     required this.executionStep,
+    required this.executionPhase,
     required this.errors,
   });
 
-  /// The limits the length check reads.
-  final ServerLimits limits;
+  /// The length check of the request's query.
+  final DocumentLength length;
 
-  /// The document phase.
-  final DocumentStep documentStep;
+  /// The document phase with its extensions.
+  final DocumentHandler documentPhase;
 
   /// Builds the context, after every refusal has been passed.
   final ContextFactory<C> contextFactory;
 
-  /// The execution phase.
+  /// Builds the execution options.
   final ExecutionStep<C> executionStep;
 
+  /// The execution phase with its extensions.
+  final ExecutionHandler<C> executionPhase;
+
   /// Makes the refusals.
   final PipelineErrors errors;
 
   /// Serves [request]; may throw, the caller turns that into a response.
   Future<ServerResponse> run(ServerRequest request) async {
     final text = request.params.query;
-    final maxLength = limits.maxDocumentLength;
-    if (text != null && maxLength != null && text.length > maxLength) {
-      return errors.refusal(
-        DiagnosticCode.documentTooLong,
-        'The document is longer than the maximum of $maxLength characters.',
-      );
-    }
-    if (text == null || text.isEmpty) {
-      return errors.refusal(
-        DiagnosticCode.queryRequired,
-        'Must provide query string.',
-      );
+    if (length.violation(text) case final violation?) {
+      return errors.rejected([violation]);
     }
-    return switch (documentStep.run(text)) {
-      RejectedEntry(errors: final rejected) => errors.rejected(rejected),
-      final AcceptedEntry accepted => _accepted(accepted, request),
+    final result = await documentPhase(DocumentRequest(request, text: text));
+    return switch (result) {
+      DocumentRejected(errors: final rejected) => errors.rejected(rejected),
+      final DocumentAccepted accepted => _accepted(accepted, request),
     };
   }
 
   Future<ServerResponse> _accepted(
-    AcceptedEntry entry,
+    DocumentAccepted accepted,
     ServerRequest request,
   ) async {
     final type = const OperationLookup().typeOf(
-      entry.document.document,
+      accepted.document.document,
       request.params.operationName,
     );
     if (type == OperationType.mutation &&
@@ -82,12 +80,17 @@ final class RequestStep<C> {
       );
     }
     final context = await contextFactory(request.info);
-    return executionStep.run(
-      ExecutionJob<C>(
-        entry: entry,
+    return executionPhase(
+      ExecutionRequest<C>(
+        request: request,
+        document: accepted.document,
         operationType: type,
         context: context,
-        request: request,
+        options: executionStep.optionsFor(
+          accepted.source,
+          type,
+          request.cancelSignal,
+        ),
       ),
     );
   }
```

Create `packages/typed_graphql_server/lib/src/server/server_extension.dart`:

```dart
import 'document_handler.dart';
import 'document_request.dart';
import 'document_result.dart';
import 'execution_handler.dart';
import 'execution_request.dart';
import 'request_handler.dart';
import 'server_request.dart';
import 'server_response.dart';

/// A hook into the three phases of a request: the whole request, resolving
/// the document, and the execution (R5.3).
///
/// Each hook has a default that calls `next`. An extension may refuse by
/// returning without calling `next`, rewrite the value it passes on, or look
/// at what comes back. In `GraphQLServer.extensions` the first extension is
/// the outermost, so its hooks see every request, refused ones included.
///
/// {@category server}
abstract class ServerExtension<C> {
  /// Creates the extension.
  const ServerExtension();

  /// Wraps the whole request: CSRF prevention and the document phase are
  /// inside.
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) => next(request);

  /// Wraps the resolving of the document text to a validated document.
  Future<DocumentResult> onDocument(
    DocumentRequest request,
    DocumentHandler next,
  ) => next(request);

  /// Wraps the execution, which has the context and the options.
  Future<ServerResponse> onExecute(
    ExecutionRequest<C> request,
    ExecutionHandler<C> next,
  ) => next(request);
}
```

Modify `packages/typed_graphql_server/lib/typed_graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/typed_graphql_server.dart b/packages/typed_graphql_server/lib/typed_graphql_server.dart
index e4b1095..91b5886 100644
--- a/packages/typed_graphql_server/lib/typed_graphql_server.dart
+++ b/packages/typed_graphql_server/lib/typed_graphql_server.dart
@@ -56,8 +56,15 @@ export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
 export 'src/server/context_factory.dart';
 export 'src/server/csrf_prevention.dart';
+export 'src/server/document_handler.dart';
+export 'src/server/document_request.dart';
+export 'src/server/document_result.dart';
+export 'src/server/execution_handler.dart';
+export 'src/server/execution_request.dart';
 export 'src/server/graphql_server.dart';
+export 'src/server/request_handler.dart';
 export 'src/server/request_info.dart';
+export 'src/server/server_extension.dart';
 export 'src/server/server_limits.dart';
 export 'src/server/server_outcome.dart';
 export 'src/server/server_profile.dart';
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
git add -A packages
git commit -m "feat(typed_graphql_server): add ServerExtension and CSRF prevention in the pipeline

<your model trailer>"
```

### Task 8: feat(typed_graphql_server): add the cost limit to the pipeline

**Why.** Adds the cost limit to the pipeline (spec section 8): `CostLimit` runs the core cost analysis for the chosen operation against the profile's maximum cost and refuses a request over it, with the message built by `CostMessage`. `OperationLookup` and `RequestStep` hand it the operation.

**Files** (commit `ac71c1b`):

- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Create `packages/typed_graphql_server/lib/src/server/cost_limit.dart`
- Create `packages/typed_graphql_server/lib/src/server/cost_message.dart`
- Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Modify `packages/typed_graphql_server/lib/src/server/operation_lookup.dart`
- Modify `packages/typed_graphql_server/lib/src/server/request_step.dart`
- Create `packages/typed_graphql_server/test/server/server_cost_test.dart`
- Create `packages/typed_graphql_server/test/server/support/cost_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/server/server_cost_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/cost_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final costs = CostFixture();
  final fixture = ServerFixture();
  var built = 0;

  GraphQLServer<Ctx> serverWith(double? maxCost) => costs.server(maxCost, (_) {
    built++;
    return const Ctx('x');
  });

  Future<ServerResponse> send(
    double? maxCost,
    String query, {
    String method = 'POST',
    String? operationName,
    JsonObject? variables,
  }) => serverWith(maxCost).handle(
    fixture.request(
      query,
      method: method,
      operationName: operationName,
      variables: variables,
    ),
  );

  setUp(() => built = 0);

  group('a literal size', () {
    test('over the limit is GQL238 with the core rule message', () async {
      final response = await send(10, '{ items(first: 10) { name } }');
      expect(fixture.codeOf(response), 'GQL238');
      expect(
        fixture.messageOf(response),
        'The anonymous operation has a field cost of 1 and a type cost of 11, '
        'more than the maximum of 10.',
      );
    });

    test('is a request error pointing at a named operation', () async {
      final response = await send(
        10,
        '\n  query Q { items(first: 10) { name } }',
      );
      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
      final errors = fixture.json(response)['errors']! as List<Object?>;
      expect((errors.first! as Map<String, Object?>)['locations'], [
        {'line': 2, 'column': 3},
      ]);
      expect(
        fixture.messageOf(response),
        startsWith('The operation "Q" has a field cost of 1'),
      );
    });

    test('is refused before the context factory runs', () async {
      await send(10, '{ items(first: 10) { name } }');
      expect(built, 0);
    });

    test('exactly at the limit passes', () async {
      final response = await send(10, '{ items(first: 9) { name } }');
      expect(fixture.json(response)['data'], isNotNull);
    });
  });

  group('a size given by a variable', () {
    const text = r'query ($n: Int) { items(first: $n) { name } }';

    test('over the limit is refused', () async {
      final response = await send(
        10,
        text,
        variables: JsonObject({'n': JsonNumber(1000000)}),
      );
      expect(fixture.codeOf(response), 'GQL238');
    });

    test('under the limit passes for the same document', () async {
      final response = await send(
        10,
        text,
        variables: JsonObject({'n': JsonNumber(1)}),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });
  });

  group('a hostile variable value', () {
    const text = r'query ($n: Int) { items(first: $n) { name } }';

    for (final (label, value) in <(String, JsonValue)>[
      ('a string', const JsonString('many')),
      ('a fraction', JsonNumber(1.5)),
      ('a negative number', JsonNumber(-5)),
      ('a huge number', JsonNumber(1e300)),
      ('null', const JsonNull()),
      ('an object', JsonObject({})),
    ]) {
      test('$label is never an internal error', () async {
        final response = await send(
          10,
          text,
          variables: JsonObject({'n': value}),
        );
        expect(
          (response as SingleResponse).outcome,
          isNot(ServerOutcome.internalError),
        );
      });
    }
  });

  test('a GET query is costed', () async {
    final response = await send(
      10,
      '{ items(first: 10) { name } }',
      method: 'GET',
    );
    expect(fixture.codeOf(response), 'GQL238');
  });

  test('no limit never refuses', () async {
    final response = await send(null, '{ items(first: 100000) { name } }');
    expect(fixture.json(response)['data'], isNotNull);
  });

  test('a request selecting no operation is left to the executor', () async {
    final response = await send(
      10,
      '{ items(first: 10) { name } }',
      operationName: 'Nope',
    );
    expect(fixture.codeOf(response), isNot('GQL238'));
  });
}
```

Create `packages/typed_graphql_server/test/server/support/cost_fixture.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// A schema with `items(first: Int): [Item]` sized by `@listSize`, and the
/// servers to test the cost limit on it.
///
/// An `Item` weighs 1 and a scalar 0, so `{ items(first: n) { name } }` has a
/// field cost of 1 and a type cost of `n + 1`.
final class CostFixture {
  CostFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final first = Arg('first', b.int.nullable);
    final item = b.object<Object?>(
      'Item',
      fields: (t) => [t.field('name', b.string).pure((_) => 'item')],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('items', b.list(item).nullable, args: [first])
            .withDirectives([
              AppliedDirective(
                'listSize',
                arguments: [
                  Argument(
                    const Name('slicingArguments'),
                    ListValue([const StringValue('first')]),
                  ),
                ],
              ),
            ])
            .resolve(
              (parent, args, context, info) => const [Object(), Object()],
            ),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      options: BuildOptions<Ctx>(
        directives: [const BuiltIns().listSize, const BuiltIns().cost],
      ),
    );
  }

  late final ExecutableSchema<Ctx> schema;

  /// A server limiting the cost to [maxCost]; null is no limit.
  GraphQLServer<Ctx> server(double? maxCost, ContextFactory<Ctx> factory) =>
      GraphQLServer<Ctx>(
        schema: schema,
        contextFactory: factory,
        profile: ServerProfile.development.withLimits(
          ServerLimits(maxCost: maxCost),
        ),
      );
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: `server_cost_test.dart` (with its new `cost_fixture.dart`) expects a request over the limit to be refused; before the change the server answers it, so the tests fail.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index df8ca8a..30638c5 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -168,3 +168,8 @@
 - CSRF prevention (`GQL403`) runs in the request phase when the profile has a
   `CsrfPrevention`: a request without a content type a browser cannot send
   cross-site and without a preflight header is refused before any other step.
+- The cost limit (`ServerLimits.maxCost`, `defaultListSize`) runs for each
+  request after the operation is selected and before the context is built: a
+  request whose field cost or type cost is over the limit is refused with
+  `GQL238` and `MaxCostRule`'s message. Slicing arguments given as variables
+  count with the request's values.
```

Create `packages/typed_graphql_server/lib/src/server/cost_limit.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'cost_message.dart';
import 'server_request.dart';

/// The cost step of the pipeline (R5.4, `GQL238`): finds out whether the
/// selected operation costs more than the limit.
///
/// It runs per request, not per document, because a slicing argument given
/// as a variable gets its size from the request's variables.
@internal
final class CostLimit {
  /// Creates the step refusing more than [maxCost] on [analysis]'s costs.
  const CostLimit(this.analysis, this.maxCost);

  /// Computes the costs.
  final CostAnalysis analysis;

  /// The highest field cost and type cost allowed.
  final double maxCost;

  /// The refusal for [operation] of [document] (written in [source]) as
  /// [request] runs it, or null when it is within the limit.
  GraphQLError? violation(
    Document document,
    Source source,
    OperationDefinition operation,
    ServerRequest request,
  ) {
    final cost = analysis.costOf(
      document,
      operation,
      variables: request.params.variables?.fields ?? const {},
    );
    // Written as a negated `<=` so that a NaN could never pass the limit.
    if (cost.fieldCost <= maxCost && cost.typeCost <= maxCost) {
      return null;
    }
    return GraphQLError(
      const CostMessage().of(operation, cost, maxCost),
      locations: [SourceSpan(source, operation.start, operation.end).location],
      extensions: JsonObject({
        'code': JsonString(DiagnosticCode.maxCostExceeded.id),
      }),
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/server/cost_message.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// The text of a `GQL238` refusal: `MaxCostRule`'s message to the character.
///
/// The core's `OperationSubject` and `CostNumber` are not exported, so their
/// wording is reproduced here.
@internal
final class CostMessage {
  /// Creates the writer.
  const CostMessage();

  // Beyond 1e15 the platforms print doubles differently; the exponential
  // form is the same everywhere (as the core's `CostNumber`).
  static const double _largest = 1000000000000000;

  /// The message for [operation] costing [cost] against [maxCost].
  String of(OperationDefinition operation, OperationCost cost, double maxCost) {
    final subject = switch (operation.name) {
      final name? => 'The operation "${name.value}"',
      null => 'The anonymous operation',
    };
    return '$subject has a field cost of ${_number(cost.fieldCost)} and a '
        'type cost of ${_number(cost.typeCost)}, more than the maximum of '
        '${_number(maxCost)}.';
  }

  // A negative zero prints as "0" on every platform.
  String _number(double value) => switch (value == 0 ? 0.0 : value) {
    final number when !number.isFinite => number.toString(),
    final number when number.abs() >= _largest =>
      number.toStringAsExponential(),
    final number when number == number.truncateToDouble() =>
      number.toStringAsFixed(0),
    final number => number.toString(),
  };
}
```

Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/graphql_server.dart b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
index 4318c57..c04aa3b 100644
--- a/packages/typed_graphql_server/lib/src/server/graphql_server.dart
+++ b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
@@ -4,9 +4,11 @@ import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
 import '../execution/graphql_exception.dart';
 import 'context_factory.dart';
+import 'cost_limit.dart';
 import 'csrf_extension.dart';
 import 'document_cache.dart';
 import 'document_compiler.dart';
+import 'document_handler.dart';
 import 'document_length.dart';
 import 'document_step.dart';
 import 'execution_step.dart';
@@ -53,14 +55,11 @@ final class GraphQLServer<C> {
     int documentCacheSize = 1000,
     List<ServerExtension<C>> extensions = const [],
   }) {
-    final errors = PipelineErrors(
-      maskErrors: profile.maskErrors,
-      onError: onError,
-    );
+    final errors = _pipelineErrors(profile, onError);
     final length = DocumentLength(profile.limits.maxDocumentLength, errors);
-    // The user's extensions come first (outermost), then the built-in ones
-    // in a fixed order, so no list order puts an unchecked step before a
-    // security check. M6c adds the trusted-document and APQ extensions here.
+    // The user's extensions are outermost, then the built-in ones in a fixed
+    // order, so no list order puts a step before a security check. M6c adds
+    // the trusted-document and APQ extensions here.
     final chain = ExtensionChain<C>([
       ...extensions,
       if (profile.csrfPrevention case final csrf?)
@@ -70,17 +69,19 @@ final class GraphQLServer<C> {
     final request = RequestStep<C>(
       length: length,
       documentPhase: chain.document(
-        DocumentStep(
-          DocumentCache(documentCacheSize),
-          _compiler(schema.schema, profile, validationRules),
-          length,
+        _documentStep(
+          schema.schema,
+          profile,
+          validationRules,
+          documentCacheSize,
           errors,
-        ).run,
+        ),
       ),
       contextFactory: contextFactory,
       executionStep: executionStep,
       executionPhase: chain.execution(executionStep.run),
       errors: errors,
+      costLimit: _costLimit(schema.schema, profile.limits),
     );
     return GraphQLServer._(errors, chain.request(request.run));
   }
@@ -90,6 +91,11 @@ final class GraphQLServer<C> {
   final PipelineErrors _errors;
   final RequestHandler _request;
 
+  static PipelineErrors _pipelineErrors(
+    ServerProfile profile,
+    ErrorHook? onError,
+  ) => PipelineErrors(maskErrors: profile.maskErrors, onError: onError);
+
   static DocumentCompiler _compiler(
     ValidSchema schema,
     ServerProfile profile,
@@ -103,6 +109,28 @@ final class GraphQLServer<C> {
     schema,
   );
 
+  static DocumentHandler _documentStep(
+    ValidSchema schema,
+    ServerProfile profile,
+    List<ValidationRule> validationRules,
+    int cacheSize,
+    PipelineErrors errors,
+  ) => DocumentStep(
+    DocumentCache(cacheSize),
+    _compiler(schema, profile, validationRules),
+    DocumentLength(profile.limits.maxDocumentLength, errors),
+    errors,
+  ).run;
+
+  static CostLimit? _costLimit(ValidSchema schema, ServerLimits limits) =>
+      switch (limits.maxCost) {
+        final maxCost? => CostLimit(
+          CostAnalysis(schema.schema, defaultListSize: limits.defaultListSize),
+          maxCost,
+        ),
+        null => null,
+      };
+
   static List<ValidationRule> _limitRules(ServerLimits limits) => [
     if (limits.maxDepth case final maxDepth?) MaxDepthRule(maxDepth: maxDepth),
     if (limits.maxAliases case final maxAliases?)
```

Modify `packages/typed_graphql_server/lib/src/server/operation_lookup.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/operation_lookup.dart b/packages/typed_graphql_server/lib/src/server/operation_lookup.dart
index acf1eeb..dbefbe2 100644
--- a/packages/typed_graphql_server/lib/src/server/operation_lookup.dart
+++ b/packages/typed_graphql_server/lib/src/server/operation_lookup.dart
@@ -7,17 +7,17 @@ final class OperationLookup {
   /// Creates the lookup.
   const OperationLookup();
 
-  /// The kind of the operation of [document] named [operationName] (the only
-  /// operation when null), or null when there is none to select; the
-  /// executor then reports `GQL320`-`GQL322` (September2025 6.1.2).
-  OperationType? typeOf(Document document, String? operationName) {
+  /// The operation of [document] named [operationName] (the only operation
+  /// when null), or null when there is none to select; the executor then
+  /// reports `GQL320`-`GQL322` (September2025 6.1.2).
+  OperationDefinition? operationOf(Document document, String? operationName) {
     final operations = document.definitions.whereType<OperationDefinition>();
     if (operationName == null) {
-      return operations.length == 1 ? operations.first.operation : null;
+      return operations.length == 1 ? operations.first : null;
     }
     for (final operation in operations) {
       if (operation.name?.value == operationName) {
-        return operation.operation;
+        return operation;
       }
     }
     return null;
```

Modify `packages/typed_graphql_server/lib/src/server/request_step.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/request_step.dart b/packages/typed_graphql_server/lib/src/server/request_step.dart
index 8c35b67..fbe27f5 100644
--- a/packages/typed_graphql_server/lib/src/server/request_step.dart
+++ b/packages/typed_graphql_server/lib/src/server/request_step.dart
@@ -2,6 +2,7 @@ import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'context_factory.dart';
+import 'cost_limit.dart';
 import 'document_handler.dart';
 import 'document_length.dart';
 import 'document_request.dart';
@@ -29,6 +30,7 @@ final class RequestStep<C> {
     required this.executionStep,
     required this.executionPhase,
     required this.errors,
+    this.costLimit,
   });
 
   /// The length check of the request's query.
@@ -49,6 +51,9 @@ final class RequestStep<C> {
   /// Makes the refusals.
   final PipelineErrors errors;
 
+  /// The cost limit, null when the profile has none.
+  final CostLimit? costLimit;
+
   /// Serves [request]; may throw, the caller turns that into a response.
   Future<ServerResponse> run(ServerRequest request) async {
     final text = request.params.query;
@@ -66,10 +71,12 @@ final class RequestStep<C> {
     DocumentAccepted accepted,
     ServerRequest request,
   ) async {
-    final type = const OperationLookup().typeOf(
-      accepted.document.document,
+    final document = accepted.document.document;
+    final operation = const OperationLookup().operationOf(
+      document,
       request.params.operationName,
     );
+    final type = operation?.operation;
     if (type == OperationType.mutation &&
         request.info.method.toUpperCase() == 'GET') {
       return errors.refusal(
@@ -79,6 +86,9 @@ final class RequestStep<C> {
         headers: const {'allow': 'POST'},
       );
     }
+    if (_costRefusal(accepted, operation, request) case final refusal?) {
+      return refusal;
+    }
     final context = await contextFactory(request.info);
     return executionPhase(
       ExecutionRequest<C>(
@@ -94,4 +104,21 @@ final class RequestStep<C> {
       ),
     );
   }
+
+  // No operation selected: the executor reports it.
+  SingleResponse? _costRefusal(
+    DocumentAccepted accepted,
+    OperationDefinition? operation,
+    ServerRequest request,
+  ) {
+    final violation = operation == null
+        ? null
+        : costLimit?.violation(
+            accepted.document.document,
+            accepted.source,
+            operation,
+            request,
+          );
+    return violation == null ? null : errors.rejected([violation]);
+  }
 }
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
git add -A packages
git commit -m "feat(typed_graphql_server): add the cost limit to the pipeline

<your model trailer>"
```

### Task 9: fix(typed_graphql_server): address the extension review

**Why.** Answers the review of Task 7 (the extensions): `DocumentCompiler` and `DocumentResult` are adjusted, the wiring of the chains moves into a new `PipelineAssembly`, `GraphQLServer` and `PipelineErrors` are simplified, and the extension, CSRF, hook and compiler tests are extended with the cases the review asked for.

**Files** (commit `5a1b8d8`):

- Modify `packages/typed_graphql_server/lib/src/server/document_compiler.dart`
- Modify `packages/typed_graphql_server/lib/src/server/document_result.dart`
- Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart`
- Create `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart`
- Modify `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart`
- Modify `packages/typed_graphql_server/test/server/document_compiler_test.dart`
- Modify `packages/typed_graphql_server/test/server/server_csrf_test.dart`
- Modify `packages/typed_graphql_server/test/server/server_execute_hooks_test.dart`
- Modify `packages/typed_graphql_server/test/server/server_extension_test.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/server/document_compiler_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/document_compiler_test.dart b/packages/typed_graphql_server/test/server/document_compiler_test.dart
index c905775..2a8ae4c 100644
--- a/packages/typed_graphql_server/test/server/document_compiler_test.dart
+++ b/packages/typed_graphql_server/test/server/document_compiler_test.dart
@@ -47,4 +47,11 @@ void main() {
       ),
     ]);
   });
+
+  test('the errors of a rejection cannot be changed', () {
+    expect(
+      () => errorsOf('{ b }').add(GraphQLError('injected')),
+      throwsUnsupportedError,
+    );
+  });
 }
```

Modify `packages/typed_graphql_server/test/server/server_csrf_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_csrf_test.dart b/packages/typed_graphql_server/test/server/server_csrf_test.dart
index 1213b17..8f7b395 100644
--- a/packages/typed_graphql_server/test/server/server_csrf_test.dart
+++ b/packages/typed_graphql_server/test/server/server_csrf_test.dart
@@ -1,6 +1,7 @@
 import 'package:test/test.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
+import 'support/hook_extension.dart';
 import 'support/recording_extension.dart';
 import 'support/server_fixture.dart';
 
@@ -68,4 +69,48 @@ void main() {
     expect(fixture.codeOf(response), 'GQL403');
     expect(log, ['a:request', '/a:request']);
   });
+
+  group('a user extension that rewrites the request', () {
+    ServerRequest withHeaders(
+      ServerRequest request,
+      Map<String, String> headers,
+    ) => ServerRequest(
+      params: request.params,
+      info: RequestInfo(
+        method: request.info.method,
+        uri: request.info.uri,
+        headers: headers,
+      ),
+    );
+
+    test('adding the preflight header lets a blocked request pass', () async {
+      final server = fixture.server(
+        profile: ServerProfile.production,
+        extensions: [
+          HookExtension(
+            request: (request, next) => next(
+              withHeaders(request, {'graphql-require-preflight': '1'}),
+            ),
+          ),
+        ],
+      );
+      final response = await server.handle(
+        fixture.request('{ hello }', method: 'GET', headers: const {}),
+      );
+      expect(fixture.json(response)['data'], {'hello': 'world'});
+    });
+
+    test('removing the content type is GQL403', () async {
+      final server = fixture.server(
+        profile: ServerProfile.production,
+        extensions: [
+          HookExtension(
+            request: (request, next) => next(withHeaders(request, const {})),
+          ),
+        ],
+      );
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.codeOf(response), 'GQL403');
+    });
+  });
 }
```

Modify `packages/typed_graphql_server/test/server/server_execute_hooks_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_execute_hooks_test.dart b/packages/typed_graphql_server/test/server/server_execute_hooks_test.dart
index d1b6921..ad4c8de 100644
--- a/packages/typed_graphql_server/test/server/server_execute_hooks_test.dart
+++ b/packages/typed_graphql_server/test/server/server_execute_hooks_test.dart
@@ -88,4 +88,35 @@ void main() {
     await server.handle(fixture.request('{ nothing }'));
     expect(reached, isFalse);
   });
+
+  group('the timeout the hook sees', () {
+    final profile = ServerProfile.production.withTimeout(
+      const Duration(seconds: 5),
+    );
+
+    Future<Duration?> timeoutSeenFor(String query) async {
+      Duration? seen;
+      final server = fixture.server(
+        profile: profile,
+        extensions: [
+          HookExtension(
+            execute: (request, next) {
+              seen = request.options.timeout;
+              return next(request);
+            },
+          ),
+        ],
+      );
+      await server.handle(fixture.request(query));
+      return seen;
+    }
+
+    test('a query has the profile timeout', () async {
+      expect(await timeoutSeenFor('{ hello }'), const Duration(seconds: 5));
+    });
+
+    test('a subscription has none', () async {
+      expect(await timeoutSeenFor('subscription { ticks }'), isNull);
+    });
+  });
 }
```

Modify `packages/typed_graphql_server/test/server/server_extension_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_extension_test.dart b/packages/typed_graphql_server/test/server/server_extension_test.dart
index 5b5d92b..6568b8c 100644
--- a/packages/typed_graphql_server/test/server/server_extension_test.dart
+++ b/packages/typed_graphql_server/test/server/server_extension_test.dart
@@ -172,7 +172,10 @@ void main() {
         ],
       );
       await server.handle(fixture.request('{ hello }'));
-      expect(hashes.single, hasLength(64));
+      expect(
+        hashes.single,
+        '001c3174e099bd72b729d0c0a529ba9f5a740c446e2a6e1d71b283cb84ec3065',
+      );
     });
   });
 
@@ -213,4 +216,97 @@ void main() {
       expect(seen.single, isA<StateError>());
     });
   });
+
+  group('the trust placed in hooks', () {
+    test('a hook-built DocumentAccepted is executed as is', () async {
+      final server = fixture.server(
+        extensions: [
+          HookExtension(
+            document: (request, next) async {
+              final accepted =
+                  await next(request.withText('{ tag }')) as DocumentAccepted;
+              return DocumentAccepted(
+                accepted.document,
+                accepted.source,
+                'chosen-by-the-hook',
+              );
+            },
+          ),
+        ],
+      );
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.json(response)['data'], {'tag': 'default'});
+    });
+
+    test('a rejection by onDocument builds no context', () async {
+      var built = 0;
+      final server = fixture.server(
+        contextFactory: (_) {
+          built++;
+          return const Ctx('x');
+        },
+        extensions: [
+          HookExtension(
+            document: (request, next) async =>
+                DocumentRejected([GraphQLError('No')]),
+          ),
+        ],
+      );
+      await server.handle(fixture.request('{ hello }'));
+      expect(built, 0);
+    });
+
+    test('a rejection without errors is a masked GQL330', () async {
+      final server = fixture.server(
+        profile: ServerProfile.production,
+        extensions: [
+          HookExtension(
+            document: (request, next) async => const DocumentRejected([]),
+          ),
+        ],
+      );
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.codeOf(response), 'GQL330');
+      expect(fixture.messageOf(response), 'Unexpected error.');
+      expect((response as SingleResponse).outcome, ServerOutcome.internalError);
+    });
+  });
+
+  group('failures of a hook', () {
+    test('a failed future is GQL330', () async {
+      final server = fixture.server(
+        profile: ServerProfile.production,
+        extensions: [
+          HookExtension(
+            document: (request, next) async {
+              throw StateError('secret');
+            },
+          ),
+        ],
+      );
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.codeOf(response), 'GQL330');
+    });
+
+    test('a throwing onExecute is GQL330 and onError sees it', () async {
+      final seen = <Object>[];
+      final server = fixture.server(
+        profile: ServerProfile.production,
+        onError: (error, stackTrace, reported) {
+          seen.add(error);
+          return null;
+        },
+        extensions: [
+          HookExtension(
+            execute: (request, next) async {
+              throw StateError('secret');
+            },
+          ),
+        ],
+      );
+      final response = await server.handle(fixture.request('{ hello }'));
+      expect(fixture.codeOf(response), 'GQL330');
+      expect(seen.single, isA<StateError>());
+    });
+  });
 }
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: The changed tests fail on the tree Task 8 leaves: the behaviour the review named (for example hook order or the shape of the cached result) is not yet as the tests expect.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/lib/src/server/document_compiler.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_compiler.dart b/packages/typed_graphql_server/lib/src/server/document_compiler.dart
index 6f4c8d4..af78436 100644
--- a/packages/typed_graphql_server/lib/src/server/document_compiler.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_compiler.dart
@@ -27,19 +27,21 @@ class DocumentCompiler {
   DocumentResult compile(String text, String hash) {
     final source = Source(text);
     return switch (parser.parse(source)) {
-      ParseFailure(:final diagnostics) => DocumentRejected(
-        const DiagnosticErrors().of(diagnostics),
-      ),
+      ParseFailure(:final diagnostics) => _rejected(diagnostics),
       ParseSuccess(:final document) => switch (validator.validate(
         schema,
         document,
         source: source,
       )) {
         final ValidDocument valid => DocumentAccepted(valid, source, hash),
-        InvalidDocument(:final diagnostics) => DocumentRejected(
-          const DiagnosticErrors().of(diagnostics),
-        ),
+        InvalidDocument(:final diagnostics) => _rejected(diagnostics),
       },
     };
   }
+
+  // Unmodifiable: the cache hands the same list to every request, and an
+  // extension must not be able to change what later requests see.
+  DocumentRejected _rejected(List<Diagnostic> diagnostics) => DocumentRejected(
+    List.unmodifiable(const DiagnosticErrors().of(diagnostics)),
+  );
 }
```

Modify `packages/typed_graphql_server/lib/src/server/document_result.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/document_result.dart b/packages/typed_graphql_server/lib/src/server/document_result.dart
index 139228e..80f4fd7 100644
--- a/packages/typed_graphql_server/lib/src/server/document_result.dart
+++ b/packages/typed_graphql_server/lib/src/server/document_result.dart
@@ -23,8 +23,9 @@ final class DocumentAccepted extends DocumentResult {
   /// The text, for locations in later messages.
   final Source source;
 
-  /// The SHA-256 of the text, as lower-case hex: the cache key the server
-  /// computed, never a value a client sent.
+  /// The SHA-256 of the text, as lower-case hex: the cache key when the
+  /// server compiled the text, never a value a client sent; a hook that builds
+  /// its own result chooses it.
   final String hash;
 }
 
@@ -33,7 +34,8 @@ final class DocumentAccepted extends DocumentResult {
 ///
 /// {@category server}
 final class DocumentRejected extends DocumentResult {
-  /// Creates a result holding the [errors], which must not be empty.
+  /// Creates a result holding the [errors], which must not be empty (an empty
+  /// list ends the request as an unexpected error).
   const DocumentRejected(this.errors);
 
   /// The errors the response carries.
```

Modify `packages/typed_graphql_server/lib/src/server/graphql_server.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/graphql_server.dart b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
index c04aa3b..7821913 100644
--- a/packages/typed_graphql_server/lib/src/server/graphql_server.dart
+++ b/packages/typed_graphql_server/lib/src/server/graphql_server.dart
@@ -4,20 +4,10 @@ import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
 import '../execution/graphql_exception.dart';
 import 'context_factory.dart';
-import 'cost_limit.dart';
-import 'csrf_extension.dart';
-import 'document_cache.dart';
-import 'document_compiler.dart';
-import 'document_handler.dart';
-import 'document_length.dart';
-import 'document_step.dart';
-import 'execution_step.dart';
-import 'extension_chain.dart';
+import 'pipeline_assembly.dart';
 import 'pipeline_errors.dart';
 import 'request_handler.dart';
-import 'request_step.dart';
 import 'server_extension.dart';
-import 'server_limits.dart';
 import 'server_profile.dart';
 import 'server_request.dart';
 import 'server_response.dart';
@@ -55,35 +45,16 @@ final class GraphQLServer<C> {
     int documentCacheSize = 1000,
     List<ServerExtension<C>> extensions = const [],
   }) {
-    final errors = _pipelineErrors(profile, onError);
-    final length = DocumentLength(profile.limits.maxDocumentLength, errors);
-    // The user's extensions are outermost, then the built-in ones in a fixed
-    // order, so no list order puts a step before a security check. M6c adds
-    // the trusted-document and APQ extensions here.
-    final chain = ExtensionChain<C>([
-      ...extensions,
-      if (profile.csrfPrevention case final csrf?)
-        CsrfExtension<C>(csrf, errors),
-    ]);
-    final executionStep = ExecutionStep<C>(schema, profile, onError);
-    final request = RequestStep<C>(
-      length: length,
-      documentPhase: chain.document(
-        _documentStep(
-          schema.schema,
-          profile,
-          validationRules,
-          documentCacheSize,
-          errors,
-        ),
-      ),
+    final assembly = PipelineAssembly<C>(
+      schema: schema,
       contextFactory: contextFactory,
-      executionStep: executionStep,
-      executionPhase: chain.execution(executionStep.run),
-      errors: errors,
-      costLimit: _costLimit(schema.schema, profile.limits),
+      profile: profile,
+      validationRules: validationRules,
+      onError: onError,
+      documentCacheSize: documentCacheSize,
+      extensions: extensions,
     );
-    return GraphQLServer._(errors, chain.request(request.run));
+    return GraphQLServer._(assembly.errors, assembly.handler());
   }
 
   GraphQLServer._(this._errors, this._request);
@@ -91,54 +62,6 @@ final class GraphQLServer<C> {
   final PipelineErrors _errors;
   final RequestHandler _request;
 
-  static PipelineErrors _pipelineErrors(
-    ServerProfile profile,
-    ErrorHook? onError,
-  ) => PipelineErrors(maskErrors: profile.maskErrors, onError: onError);
-
-  static DocumentCompiler _compiler(
-    ValidSchema schema,
-    ServerProfile profile,
-    List<ValidationRule> validationRules,
-  ) => DocumentCompiler(
-    Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
-    DocumentValidator(
-      rules: [...validationRules, ..._limitRules(profile.limits)],
-      includesSuggestions: profile.includesSuggestions,
-    ),
-    schema,
-  );
-
-  static DocumentHandler _documentStep(
-    ValidSchema schema,
-    ServerProfile profile,
-    List<ValidationRule> validationRules,
-    int cacheSize,
-    PipelineErrors errors,
-  ) => DocumentStep(
-    DocumentCache(cacheSize),
-    _compiler(schema, profile, validationRules),
-    DocumentLength(profile.limits.maxDocumentLength, errors),
-    errors,
-  ).run;
-
-  static CostLimit? _costLimit(ValidSchema schema, ServerLimits limits) =>
-      switch (limits.maxCost) {
-        final maxCost? => CostLimit(
-          CostAnalysis(schema.schema, defaultListSize: limits.defaultListSize),
-          maxCost,
-        ),
-        null => null,
-      };
-
-  static List<ValidationRule> _limitRules(ServerLimits limits) => [
-    if (limits.maxDepth case final maxDepth?) MaxDepthRule(maxDepth: maxDepth),
-    if (limits.maxAliases case final maxAliases?)
-      MaxAliasesRule(maxAliases: maxAliases),
-    if (limits.maxDirectives case final maxDirectives?)
-      MaxDirectivesRule(maxDirectives: maxDirectives),
-  ];
-
   /// Serves [request]. It never throws: a failure is a response.
   ///
   /// A [GraphQLException] from the context factory is a request error; any
```

Create `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/error_hook.dart';
import '../execution/executable_schema.dart';
import 'context_factory.dart';
import 'cost_limit.dart';
import 'csrf_extension.dart';
import 'document_cache.dart';
import 'document_compiler.dart';
import 'document_handler.dart';
import 'document_length.dart';
import 'document_step.dart';
import 'execution_step.dart';
import 'extension_chain.dart';
import 'pipeline_errors.dart';
import 'request_handler.dart';
import 'request_step.dart';
import 'server_extension.dart';
import 'server_profile.dart';

/// Builds the handlers of a server from its settings, once: the extension
/// chains around the core steps. M6c adds its steps to [handler].
@internal
final class PipelineAssembly<C> {
  /// Creates the assembly; the arguments are those of `GraphQLServer`.
  PipelineAssembly({
    required this.schema,
    required this.contextFactory,
    required this.profile,
    required this.validationRules,
    required this.onError,
    required this.documentCacheSize,
    required this.extensions,
  }) : errors = PipelineErrors(
         maskErrors: profile.maskErrors,
         onError: onError,
       );

  /// The schema that executes.
  final ExecutableSchema<C> schema;

  /// Builds each request's context.
  final ContextFactory<C> contextFactory;

  /// The settings of the server.
  final ServerProfile profile;

  /// The base validation rules; the limit rules are added to them.
  final List<ValidationRule> validationRules;

  /// The server's error hook.
  final ErrorHook? onError;

  /// The most compiled documents kept.
  final int documentCacheSize;

  /// The user's extensions, outermost first.
  final List<ServerExtension<C>> extensions;

  /// Makes the refusals and the unexpected-error responses.
  final PipelineErrors errors;

  /// The handler of the request phase, with every extension around it.
  RequestHandler handler() {
    final length = DocumentLength(profile.limits.maxDocumentLength, errors);
    // The user's extensions are outermost, then the built-in ones in a fixed
    // order, so no list order puts a step before a security check. M6c adds
    // the trusted-document and APQ extensions here.
    final chain = ExtensionChain<C>([
      ...extensions,
      if (profile.csrfPrevention case final csrf?)
        CsrfExtension<C>(csrf, errors),
    ]);
    final executionStep = ExecutionStep<C>(schema, profile, onError);
    final request = RequestStep<C>(
      length: length,
      documentPhase: chain.document(_documentStep(length)),
      contextFactory: contextFactory,
      executionStep: executionStep,
      executionPhase: chain.execution(executionStep.run),
      errors: errors,
      costLimit: _costLimit(),
    );
    return chain.request(request.run);
  }

  DocumentHandler _documentStep(DocumentLength length) => DocumentStep(
    DocumentCache(documentCacheSize),
    _compiler(),
    length,
    errors,
  ).run;

  DocumentCompiler _compiler() => DocumentCompiler(
    Parser(options: ParserOptions(maxTokens: profile.limits.maxTokens)),
    DocumentValidator(
      rules: [...validationRules, ..._limitRules()],
      includesSuggestions: profile.includesSuggestions,
    ),
    schema.schema,
  );

  CostLimit? _costLimit() => switch (profile.limits.maxCost) {
    final maxCost? => CostLimit(
      CostAnalysis(
        schema.schema.schema,
        defaultListSize: profile.limits.defaultListSize,
      ),
      maxCost,
    ),
    null => null,
  };

  List<ValidationRule> _limitRules() {
    final limits = profile.limits;
    return [
      if (limits.maxDepth case final maxDepth?)
        MaxDepthRule(maxDepth: maxDepth),
      if (limits.maxAliases case final maxAliases?)
        MaxAliasesRule(maxAliases: maxAliases),
      if (limits.maxDirectives case final maxDirectives?)
        MaxDirectivesRule(maxDirectives: maxDirectives),
    ];
  }
}
```

Modify `packages/typed_graphql_server/lib/src/server/pipeline_errors.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart b/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
index ee76963..7eb7afa 100644
--- a/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
+++ b/packages/typed_graphql_server/lib/src/server/pipeline_errors.dart
@@ -32,11 +32,18 @@ final class PipelineErrors {
     headers: headers,
   );
 
-  /// A request error carrying [errors].
-  SingleResponse rejected(List<GraphQLError> errors) => SingleResponse(
-    RequestErrorResult(errors: errors),
-    outcome: ServerOutcome.requestError,
-  );
+  /// A request error carrying [errors]. An empty list is a bug in the hook
+  /// that built it (a response must carry an error): it is reported as an
+  /// unexpected error.
+  SingleResponse rejected(List<GraphQLError> errors) => errors.isEmpty
+      ? internal(
+          StateError('A rejection must carry at least one error.'),
+          StackTrace.current,
+        )
+      : SingleResponse(
+          RequestErrorResult(errors: errors),
+          outcome: ServerOutcome.requestError,
+        );
 
   /// A request error with the message and extensions of [exception].
   SingleResponse exception(GraphQLException exception) => rejected([
@@ -72,9 +79,7 @@ final class PipelineErrors {
     GraphQLError reported,
   ) {
     final hook = onError;
-    if (hook == null) {
-      return reported;
-    }
+    if (hook == null) return reported;
     try {
       return hook(error, stackTrace, reported) ?? reported;
     } on Object {
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
git add -A packages
git commit -m "fix(typed_graphql_server): address the extension review

<your model trailer>"
```

### Task 10: test(typed_graphql_server): add the request pipeline hostile-input tests

**Why.** Adds the hostile-input tests of the pipeline (R0.3): CSRF bypass attempts, document cache abuse, limits, error masking, and `request_scope_test.dart`, which ties the pipeline to the request-scoped DataLoader of M6a. It adds tests and one fixture only; no lib file changes, so the tests pass on the first run and serve as the regression net of the whole pipeline.

**Files** (commit `62173b7`):

- Create `packages/typed_graphql_server/test/dataloader/request_scope_test.dart`
- Create `packages/typed_graphql_server/test/server/hostile_csrf_test.dart`
- Create `packages/typed_graphql_server/test/server/hostile_document_cache_test.dart`
- Create `packages/typed_graphql_server/test/server/hostile_limits_test.dart`
- Create `packages/typed_graphql_server/test/server/hostile_masking_test.dart`
- Create `packages/typed_graphql_server/test/server/support/hostile_fixture.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql_server/test/dataloader/request_scope_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The batches one test observed: which request's loader asked, and for what.
final class BatchLog {
  final List<(String, List<String>)> batches = [];
}

/// The context of one request: its user and its own loader.
final class LoaderContext {
  LoaderContext(this.user, this.values);

  final String user;
  final BatchLoader<String, String> values;
}

void main() {
  final builder = ExecutableSchemaBuilder<LoaderContext>();
  final query = builder.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('values', builder.list(builder.string))
          .resolve(
            (parent, args, context, info) => context.values.loadMany([
              '${context.user}:a',
              '${context.user}:b',
            ]),
          ),
    ],
  );
  final schema = builder.build(query: query);
  const badUser = 'bad';

  GraphQLServer<LoaderContext> serverLogging(BatchLog log) =>
      GraphQLServer<LoaderContext>(
        schema: schema,
        profile: ServerProfile.development,
        contextFactory: (request) {
          final user = request.header('x-user')!;
          return LoaderContext(
            user,
            BatchLoader<String, String>((keys) async {
              log.batches.add((user, keys));
              await Future<void>.delayed(const Duration(milliseconds: 2));
              if (user == badUser) throw StateError('batch of $user failed');
              return {for (final key in keys) key: 'value of $key'};
            }),
          );
        },
      );

  ServerRequest requestFor(String user) => ServerRequest(
    params: const GraphQLRequest(query: '{ values }'),
    info: RequestInfo(
      method: 'POST',
      uri: Uri.parse('/graphql'),
      headers: {'x-user': user, 'content-type': 'application/json'},
    ),
  );

  Map<String, Object?> bodyOf(ServerResponse response) =>
      (response as SingleResponse).body.toJson();

  test('50 concurrent requests each get only their own values', () async {
    final log = BatchLog();
    final server = serverLogging(log);
    final users = [for (var index = 0; index < 50; index++) 'user$index'];

    final responses = await Future.wait([
      for (final user in users) server.handle(requestFor(user)),
    ]);

    for (final (index, response) in responses.indexed) {
      final user = users[index];
      expect(bodyOf(response)['data'], {
        'values': ['value of $user:a', 'value of $user:b'],
      });
    }
  });

  test('no batch mixes the keys of two requests', () async {
    final log = BatchLog();
    final server = serverLogging(log);
    final users = [for (var index = 0; index < 50; index++) 'user$index'];

    await Future.wait([
      for (final user in users) server.handle(requestFor(user)),
    ]);

    expect(log.batches, hasLength(50), reason: 'one batch per request');
    for (final (user, keys) in log.batches) {
      expect(keys, ['$user:a', '$user:b']);
    }
  });

  test('a failed batch does not affect another request', () async {
    final log = BatchLog();
    final server = serverLogging(log);

    final responses = await Future.wait([
      server.handle(requestFor('good1')),
      server.handle(requestFor(badUser)),
      server.handle(requestFor('good2')),
    ]);

    expect(bodyOf(responses[0])['data'], {
      'values': ['value of good1:a', 'value of good1:b'],
    });
    expect(bodyOf(responses[2])['data'], {
      'values': ['value of good2:a', 'value of good2:b'],
    });
    expect(bodyOf(responses[1])['errors'], isNotEmpty);
  });

  test('a failed batch leaves no uncaught error', () async {
    final log = BatchLog();
    final server = serverLogging(log);
    final uncaught = <Object>[];

    await runZonedGuarded(
      () async {
        await Future.wait([
          for (var index = 0; index < 10; index++)
            server.handle(requestFor(badUser)),
          server.handle(requestFor('good')),
        ]);
        // Give a stray error time to surface in the zone.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      (error, stackTrace) => uncaught.add(error),
    );

    expect(uncaught, isEmpty);
  });
}
```

Create `packages/typed_graphql_server/test/server/hostile_csrf_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();
  final server = hostile.server();

  setUp(() {
    hostile
      ..built = 0
      ..resolved = 0;
  });

  Future<ServerResponse> send(
    Map<String, String> headers, {
    String method = 'POST',
    String text = '{ hello }',
  }) => server.handle(fixture.request(text, method: method, headers: headers));

  void expectBlocked(ServerResponse response) {
    expect(fixture.codeOf(response), 'GQL403');
    expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    expect(hostile.built, 0, reason: 'no context');
    expect(hostile.resolved, 0, reason: 'no resolver');
  }

  group('a request a browser can send cross-site is GQL403', () {
    test('a GET without headers', () async {
      expectBlocked(await send(const {}, method: 'GET'));
    });

    for (final type in [
      'application/x-www-form-urlencoded',
      'multipart/form-data',
      'text/plain',
    ]) {
      test('a POST with $type', () async {
        expectBlocked(await send({'content-type': type}));
      });
    }

    test('a POST with odd case and a parameter', () async {
      expectBlocked(await send({'Content-Type': 'Text/Plain; charset=utf-8'}));
    });

    test('a POST with an unparsable type', () async {
      expectBlocked(await send({'content-type': 'json'}));
    });

    test('a POST with joined headers whose first value is simple', () async {
      expectBlocked(
        await send({'content-type': 'text/plain, application/json'}),
      );
    });

    test('an empty preflight header without a content type', () async {
      expectBlocked(await send({'graphql-require-preflight': ''}));
    });

    test('a whitespace preflight header without a content type', () async {
      expectBlocked(await send({'apollo-require-preflight': '  '}));
    });
  });

  group('a request a browser cannot send cross-site passes', () {
    test('a POST with application/json', () async {
      final response = await send({'content-type': 'application/json'});
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a POST with application/json and a charset', () async {
      final response = await send({
        'content-type': 'application/json; charset=utf-8',
      });
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });

    test('a GET with a non-empty preflight header', () async {
      final response = await send({
        'graphql-require-preflight': '1',
      }, method: 'GET');
      expect(fixture.json(response)['data'], {'hello': 'world'});
    });
  });

  test('a mutation in a GET with a preflight header is still GQL402', () async {
    final response = await send(
      {'graphql-require-preflight': '1'},
      method: 'GET',
      text: 'mutation { bump }',
    );
    expect(fixture.codeOf(response), 'GQL402');
    expect(
      (response as SingleResponse).outcome,
      ServerOutcome.methodNotAllowed,
    );
  });
}
```

Create `packages/typed_graphql_server/test/server/hostile_document_cache_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();

  /// A server whose only rule counts the validations that reach it.
  (GraphQLServer<Ctx>, CountingRule) countedServer(int cacheSize) {
    final rule = CountingRule();
    final server = hostile.server(
      profile: ServerProfile.development,
      validationRules: [rule, ...DocumentValidator.specifiedRules],
      documentCacheSize: cacheSize,
    );
    return (server, rule);
  }

  test('3000 distinct texts keep the cache at its capacity', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 3000; index++) {
      await server.handle(fixture.request('{ hello } # $index'));
    }
    expect(rule.runs, 3000);

    await server.handle(fixture.request('{ hello } # 2999'));
    await server.handle(fixture.request('{ hello } # 2900'));
    expect(rule.runs, 3000, reason: 'the 100 latest are still cached');

    await server.handle(fixture.request('{ hello } # 2899'));
    expect(rule.runs, 3001, reason: 'the 101st latest was evicted');
  });

  test('the first of 3000 texts is validated again', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 3000; index++) {
      await server.handle(fixture.request('{ hello } # $index'));
    }
    await server.handle(fixture.request('{ hello } # 0'));
    expect(rule.runs, 3001);
  });

  test('a failing text is validated once across repeated requests', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 50; index++) {
      final response = await server.handle(fixture.request('{ nothing }'));
      expect(fixture.codeOf(response), 'GQL205');
    }
    expect(rule.runs, 1);
  });

  test('1000 requests of the same valid text validate once', () async {
    final (server, rule) = countedServer(100);
    for (var index = 0; index < 1000; index++) {
      await server.handle(fixture.request('{ hello }'));
    }
    expect(rule.runs, 1);
  });

  test('a cache of size 0 validates every request', () async {
    final (server, rule) = countedServer(0);
    for (var index = 0; index < 10; index++) {
      await server.handle(fixture.request('{ hello }'));
    }
    expect(rule.runs, 10);
  });
}
```

Create `packages/typed_graphql_server/test/server/hostile_limits_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();
  final server = hostile.server();

  setUp(() {
    hostile
      ..built = 0
      ..resolved = 0;
  });

  Future<void> expectRefused(
    String text,
    String code, {
    JsonObject? variables,
  }) async {
    final response = await server.handle(
      fixture.request(text, variables: variables),
    );
    expect(fixture.codeOf(response), code);
    expect((response as SingleResponse).outcome, ServerOutcome.requestError);
    expect(hostile.built, 0, reason: 'no context');
    expect(hostile.resolved, 0, reason: 'no resolver');
  }

  group('in production a document over a limit', () {
    test('16 levels deep is GQL232', () async {
      await expectRefused(fixture.nested(15), 'GQL232');
    });

    test('with 16 aliases is GQL233', () async {
      await expectRefused(hostile.aliases(16), 'GQL233');
    });

    test('with 51 directives is GQL234', () async {
      await expectRefused(hostile.directives(51), 'GQL234');
    });

    test('costing more than the maximum by literal is GQL238', () async {
      await expectRefused('{ items(first: 10000) { name } }', 'GQL238');
    });

    test('costing more than the maximum by variable is GQL238', () async {
      await expectRefused(
        r'query ($n: Int) { items(first: $n) { name } }',
        'GQL238',
        variables: JsonObject({'n': JsonNumber(1000000)}),
      );
    });

    test('of 100001 characters is GQL401', () async {
      await expectRefused('{ hello }'.padRight(100001), 'GQL401');
    });

    test('of 15001 tokens within the length is GQL006', () async {
      final text = '{ ${List.filled(15000, 'a').join(' ')} }';
      expect(text.length, lessThan(100000));
      await expectRefused(text, 'GQL006');
    });
  });

  group('in production a document within the limits', () {
    test('15 levels deep is served', () async {
      final response = await server.handle(fixture.request(fixture.nested(14)));
      expect(fixture.json(response)['data'], isNotNull);
      expect(hostile.built, 1);
    });

    test('with 15 aliases is served', () async {
      final response = await server.handle(
        fixture.request(hostile.aliases(15)),
      );
      expect(fixture.json(response)['data'], isNotNull);
    });
  });

  group('a fragment fan-out document', () {
    test('is costed and served within two seconds', () async {
      final text = hostile.fanOut(30);
      final watch = Stopwatch()..start();
      final response = await server.handle(fixture.request(text));
      watch.stop();
      printOnFailure('fan-out of 30 fragments took ${watch.elapsed}');
      expect(
        (response as SingleResponse).outcome,
        isNot(ServerOutcome.internalError),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
```

Create `packages/typed_graphql_server/test/server/hostile_masking_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/hook_extension.dart';
import 'support/hostile_fixture.dart';
import 'support/server_fixture.dart';

void main() {
  final fixture = ServerFixture();
  final hostile = HostileFixture();

  /// Servers that fail in one place each, with the errors the hook saw.
  final failures = <String, ServerExtension<Ctx>?>{
    'a throwing extension in onRequest': HookExtension(
      request: (request, next) => throw StateError(hostileSecret),
    ),
    'a throwing extension in onDocument': HookExtension(
      document: (request, next) => throw StateError(hostileSecret),
    ),
    'a throwing extension in onExecute': HookExtension(
      execute: (request, next) => throw StateError(hostileSecret),
    ),
    'a throwing context factory': null,
  };

  GraphQLServer<Ctx> serverFor(
    ServerProfile profile,
    ServerExtension<Ctx>? extension,
    List<Object> seen,
  ) => hostile.server(
    profile: profile,
    contextFactory: extension == null
        ? (_) => throw StateError(hostileSecret)
        : null,
    extensions: [?extension],
    onError: (error, stackTrace, reported) {
      seen.add(error);
      return null;
    },
  );

  group('in production', () {
    for (final MapEntry(key: label, value: extension) in failures.entries) {
      test('$label is the masked message and nothing else', () async {
        final seen = <Object>[];
        final server = serverFor(ServerProfile.production, extension, seen);
        final response = await server.handle(fixture.request('{ hello }'));
        expect(fixture.codeOf(response), 'GQL330');
        expect(fixture.messageOf(response), 'Unexpected error.');
        expect(jsonEncode(fixture.json(response)), isNot(contains('secret')));
        expect(
          jsonEncode(fixture.json(response)),
          isNot(contains('Bad state')),
        );
        expect(jsonEncode(fixture.json(response)), isNot(contains('.dart')));
        expect(
          (response as SingleResponse).outcome,
          ServerOutcome.internalError,
        );
      });

      test('$label reaches onError raw', () async {
        final seen = <Object>[];
        final server = serverFor(ServerProfile.production, extension, seen);
        await server.handle(fixture.request('{ hello }'));
        expect(seen.single, isA<StateError>());
        expect(seen.single.toString(), contains(hostileSecret));
      });
    }

    test(
      'a throwing resolver is the masked message and nothing else',
      () async {
        final seen = <Object>[];
        final server = hostile.server(
          onError: (error, stackTrace, reported) {
            seen.add(error);
            return null;
          },
        );
        final response = await server.handle(fixture.request('{ boom }'));
        final body = jsonEncode(fixture.json(response));
        expect(fixture.messageOf(response), 'Unexpected error.');
        expect(body, isNot(contains('secret')));
        expect(body, isNot(contains('Bad state')));
        expect(seen.single, isA<StateError>());
      },
    );
  });

  group('in development', () {
    for (final MapEntry(key: label, value: extension) in failures.entries) {
      test('$label shows the message', () async {
        final server = serverFor(ServerProfile.development, extension, []);
        final response = await server.handle(fixture.request('{ hello }'));
        expect(fixture.messageOf(response), contains(hostileSecret));
      });
    }

    test('a throwing resolver shows the message', () async {
      final response = await hostile
          .server(profile: ServerProfile.development)
          .handle(fixture.request('{ boom }'));
      expect(fixture.messageOf(response), contains(hostileSecret));
    });
  });
}
```

Create `packages/typed_graphql_server/test/server/support/hostile_fixture.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'server_fixture.dart';

/// The text a hostile test throws, searched for in responses.
const String hostileSecret = 'secret-token-4711';

/// A schema whose resolvers and context factory count their calls, to prove
/// that a refusal comes before any work, and the servers over it.
final class HostileFixture {
  HostileFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final first = Arg('first', b.int.nullable);
    final item = b.object<Object?>(
      'Item',
      fields: (t) => [t.field('name', b.string).pure((_) => 'item')],
    );
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).resolve((parent, args, context, info) {
          resolved++;
          return 'world';
        }),
        t.field('self', query).resolve((parent, args, context, info) {
          resolved++;
          return const Object();
        }),
        t.field('boom', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) {
          resolved++;
          throw StateError(hostileSecret);
        }),
        t
            .field('items', b.list(item).nullable, args: [first])
            .withDirectives([
              AppliedDirective(
                'listSize',
                arguments: [
                  Argument(
                    const Name('slicingArguments'),
                    ListValue([const StringValue('first')]),
                  ),
                ],
              ),
            ])
            .resolve((parent, args, context, info) {
              resolved++;
              return const <Object>[];
            }),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('bump', b.string).pure((_) => 'bumped')],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      options: BuildOptions<Ctx>(
        directives: [const BuiltIns().listSize, const BuiltIns().cost],
      ),
    );
  }

  late final ExecutableSchema<Ctx> schema;

  /// The contexts built so far.
  int built = 0;

  /// The resolvers called so far.
  int resolved = 0;

  /// A server over the schema whose context factory counts [built] unless
  /// [contextFactory] is given.
  GraphQLServer<Ctx> server({
    ServerProfile profile = ServerProfile.production,
    ContextFactory<Ctx>? contextFactory,
    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
    ErrorHook? onError,
    int documentCacheSize = 1000,
    List<ServerExtension<Ctx>> extensions = const [],
  }) => GraphQLServer<Ctx>(
    schema: schema,
    contextFactory:
        contextFactory ??
        (_) {
          built++;
          return const Ctx('hostile');
        },
    profile: profile,
    validationRules: validationRules,
    onError: onError,
    documentCacheSize: documentCacheSize,
    extensions: extensions,
  );

  /// `{ a0: hello a1: hello ... }` with [count] aliases.
  String aliases(int count) =>
      '{ ${[for (var index = 0; index < count; index++) 'a$index: hello'].join(' ')} }';

  /// `{ hello @skip(if: false) ... }` with [count] directives.
  String directives(int count) =>
      '{ ${List.filled(count, 'hello @skip(if: false)').join(' ')} }';

  /// A document of [count] fragments, each spreading the next one twice; the
  /// last selects `hello`. Expanded naively it has 2^count spreads.
  String fanOut(int count) {
    final fragments = [
      for (var index = 0; index < count - 1; index++)
        'fragment f$index on Query { ...f${index + 1} ...f${index + 1} }',
      'fragment f${count - 1} on Query { hello }',
    ];
    return '{ ...f0 } ${fragments.join(' ')}';
  }
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: None of these tests is expected to fail: the commit adds coverage for behaviour Tasks 1 to 9 already implement. Run them once and confirm they pass; a failure is a bug in an earlier task.

- [ ] **Step 3: Write the implementation.**

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
git add -A packages
git commit -m "test(typed_graphql_server): add the request pipeline hostile-input tests

<your model trailer>"
```

## Tasks 11-13 (written by the controller)

Tasks 1-10 reproduce the commits already on `m6-final`. The controller wrote and verified Tasks 11-13 in a scratch copy of `m6-final` at `62173b7`, one commit per task (`d166897`, `631a760`, `db8de45`). Each task's diffs are that commit's diffs against the tree Task 10 leaves. Tasks 11 and 12 answer the review of Task 8 (the cost limit). Task 13 writes the stage documents of M6b.

File map of Tasks 11-13:

| File | Change | Task |
|---|---|---|
| `CLAUDE.md` | Modify | 13 |
| `README.md` | Modify | 13 |
| `docs/discovery.md` | Modify | 13 |
| `llms.txt` | Modify | 13 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 11 |
| `packages/typed_graphql/doc/validation.md` | Modify | 11 |
| `packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart` | Modify | 11 |
| `packages/typed_graphql/lib/src/validation/cost/list_sizes.dart` | Modify | 11 |
| `packages/typed_graphql/test/validation/cost/unsized_values_test.dart` | Create | 11 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 13 |
| `packages/typed_graphql_server/README.md` | Modify | 13 |
| `packages/typed_graphql_server/doc/server.md` | Modify | 13 |
| `packages/typed_graphql_server/example/example.dart` | Modify | 13 |
| `packages/typed_graphql_server/lib/src/server/operation_lookup.dart` | Modify | 12 |
| `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart` | Modify | 12 |
| `packages/typed_graphql_server/lib/src/server/request_step.dart` | Modify | 12 |
| `packages/typed_graphql_server/lib/src/server/server_extension.dart` | Modify | 12 |
| `packages/typed_graphql_server/test/server/graphql_server_test.dart` | Modify | 12 |
| `packages/typed_graphql_server/test/server/server_cost_test.dart` | Modify | 12 |
| `packages/typed_graphql_server/test/server/support/cost_fixture.dart` | Modify | 12 |

### Task 11: fix(typed_graphql): count a slicing value that names no size as not given

**Why.** Answers the review of Task 8 (the cost limit). `ListSizes` read a slicing argument's size from the request: a negative number counted as 0, and a variable that was absent, null, or not a number counted as 0 or fell through to the wrong default, so a client could lower the cost the server computes (R5.14). Now a value that names no size (an explicit null, which overrides the variable's default as in September2025 6.4.1, a non-number, a negative number, or neither a value nor a default) sizes the field as if the argument were not given: the argument's default, then `assumedSize`, then `defaultListSize`. Zero is still a size. This changes the M4 cost semantics, so the core changelog has a **Breaking** entry and the Operation Validation guide is updated (spec section 15).

**Files** (verified commit `d166897` of the controller's scratch copy):

- Modify `packages/typed_graphql/CHANGELOG.md`
- Modify `packages/typed_graphql/doc/validation.md`
- Modify `packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart`
- Modify `packages/typed_graphql/lib/src/validation/cost/list_sizes.dart`
- Create `packages/typed_graphql/test/validation/cost/unsized_values_test.dart`

- [ ] **Step 1: Write the tests.**

Create `packages/typed_graphql/test/validation/cost/unsized_values_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../schema/built.dart';

// `first` has no default and no assumedSize: a value that names no size
// falls to `defaultListSize` (10).
const _plain = '''
type Query {
  items(first: Int): [Item] @listSize(slicingArguments: ["first"])
}
type Item { id: ID }
''';

const _defaulted = '''
type Query {
  items(first: Int = 4): [Item] @listSize(slicingArguments: ["first"])
}
type Item { id: ID }
''';

const _assumed = '''
type Query {
  items(first: Int): [Item]
    @listSize(assumedSize: 7, slicingArguments: ["first"], requireOneSlicingArgument: false)
}
type Item { id: ID }
''';

final class _Costs {
  const _Costs();

  OperationCost of(
    String sdl,
    String text, {
    Map<String, JsonValue> variables = const {},
  }) {
    final schema = Built(
      sdl,
      builder: const SchemaBuilder(includesCostDirectives: true),
    ).schema;
    final document = const Parser().parse(Source(text)).requireDocument();
    final operation = document.definitions
        .whereType<OperationDefinition>()
        .first;
    return CostAnalysis(
      schema,
    ).costOf(document, operation, variables: variables);
  }
}

const _costs = _Costs();
const _byVariable = r'query ($n: Int) { items(first: $n) { id } }';

void main() {
  group('a variable without a value', () {
    test('takes the default of the slicing argument', () {
      // Types: 1 + 4 * (1 + 0) = 5.
      expect(_costs.of(_defaulted, _byVariable), const OperationCost(1, 5));
    });

    test('takes assumedSize', () {
      // Types: 1 + 7 * (1 + 0) = 8.
      expect(_costs.of(_assumed, _byVariable), const OperationCost(1, 8));
    });
  });

  group('a variable value that names no size', () {
    test('an explicit null does not take the variable default', () {
      // An explicit null overrides the default: 1 + 10 * (1 + 0) = 11.
      expect(
        _costs.of(
          _plain,
          r'query ($n: Int = 2) { items(first: $n) { id } }',
          variables: {'n': const JsonNull()},
        ),
        const OperationCost(1, 11),
      );
    });

    test('a negative number counts as not given', () {
      expect(
        _costs.of(_plain, _byVariable, variables: {'n': JsonNumber(-5)}),
        const OperationCost(1, 11),
      );
    });

    test('a string does not take the variable default', () {
      expect(
        _costs.of(
          _plain,
          r'query ($n: Int = 2) { items(first: $n) { id } }',
          variables: {'n': const JsonString('many')},
        ),
        const OperationCost(1, 11),
      );
    });

    test('an explicit null takes the argument default', () {
      expect(
        _costs.of(_defaulted, _byVariable, variables: {'n': const JsonNull()}),
        const OperationCost(1, 5),
      );
    });
  });

  test('a negative literal counts as not given', () {
    expect(
      _costs.of(_plain, '{ items(first: -5) { id } }'),
      const OperationCost(1, 11),
    );
  });

  test('zero is a size', () {
    // Types: 1 + 0 * (1 + 0) = 1.
    expect(
      _costs.of(_plain, _byVariable, variables: {'n': JsonNumber(0)}),
      const OperationCost(1, 1),
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart test" )' 2>&1 | tail -30
```

Expected: the new `test/validation/cost/unsized_values_test.dart` fails 7 of its 8 tests (every case but "zero is a size"): the old code counts those values as 0 or as the wrong default.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql/CHANGELOG.md b/packages/typed_graphql/CHANGELOG.md
index 8b92fca..c2b503b 100644
--- a/packages/typed_graphql/CHANGELOG.md
+++ b/packages/typed_graphql/CHANGELOG.md
@@ -288,3 +288,9 @@
 - `DiagnosticCode`: `GQL400`-`GQL403` (`queryRequired`, `documentTooLong`,
   `mutationRequiresPost`, `csrfRequestBlocked`), reported by the server's
   request pipeline.
+- **Breaking:** `CostAnalysis` and `MaxCostRule` count a slicing value that
+  names no size (`null`, a negative number, a variable value that is not a
+  number, a variable with neither a value nor a default) as a slicing
+  argument not given: the argument's default, `assumedSize`, then
+  `defaultListSize`. A negative value counted 0 and a variable without a
+  value skipped the argument's default and `assumedSize`.
```

Modify `packages/typed_graphql/doc/validation.md` (exact diff):

````diff
diff --git a/packages/typed_graphql/doc/validation.md b/packages/typed_graphql/doc/validation.md
index b224b1e..ada1585 100644
--- a/packages/typed_graphql/doc/validation.md
+++ b/packages/typed_graphql/doc/validation.md
@@ -320,8 +320,11 @@ Its model, in short (the doc comment of `CostAnalysis` is the contract):
   Directives on the field add their arguments the same way. The raw cost of
   a field is never below 0.
 - A list field has a size: the largest slicing argument given (a literal, or
-  a variable's value or default), else the largest default of a slicing
-  argument, else `assumedSize`, else `defaultListSize` (10 unless set). A
+  a variable's value or, without a value, its default), else the largest
+  default of a slicing argument, else `assumedSize`, else `defaultListSize`
+  (10 unless set). A value that names no size (`null`, a negative number, a
+  variable value that is not a number, a variable with neither a value nor
+  a default) counts as not given, so a client cannot lower the cost. A
   list field without `@listSize` has `defaultListSize`. With `sizedFields`
   the field has size 1 and the listed child fields get the size.
 - The field cost of a selection set is the sum of each field's raw cost plus
@@ -336,8 +339,8 @@ Its model, in short (the doc comment of `CostAnalysis` is the contract):
 
 `costOf(document, operation, variables:)` takes the coerced variable values
 for slicing arguments. `MaxCostRule` runs during validation, where there are
-none, so a variable counts with its default in the operation, else
-`defaultListSize`. The rule reports an operation when either cost is more
+none, so a variable counts with its default in the operation, else as a
+slicing argument not given. The rule reports an operation when either cost is more
 than `maxCost` (`GQL238`).
 
 ```dart
````

Modify `packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart b/packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart
index 6b6c21c..265f69b 100644
--- a/packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart
+++ b/packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart
@@ -32,13 +32,16 @@ import 'operation_cost.dart';
 ///   the cost only down to 0.
 /// - The **list size** of a field whose type is a list (ignoring non-null)
 ///   is the largest slicing argument given: an `Int` literal, or a
-///   variable's value in `variables`, else its default in the operation,
-///   else `defaultListSize`; a `null` is ignored. With none given, it is
-///   the largest default value of a slicing argument, else `assumedSize`,
-///   else `defaultListSize`. A list field without `@listSize` has
-///   `defaultListSize`; any other field has 1. When `@listSize` has
-///   `sizedFields`, the field itself has size 1 and the size above is the
-///   size of each child, fragments included, whose name is listed.
+///   variable's value in `variables`, else (without a value) its default in
+///   the operation. A value that names no size (`null`, a negative number,
+///   a variable value that is not a number, a variable with neither a value
+///   nor a default) is not given, so a client cannot lower the cost. With
+///   none given, it is the largest default value of a slicing argument,
+///   else `assumedSize`, else `defaultListSize`. A list field without
+///   `@listSize` has `defaultListSize`; any other field has 1. When
+///   `@listSize` has `sizedFields`, the field itself has size 1 and the size
+///   above is the size of each child, fragments included, whose name is
+///   listed.
 /// - The **field cost** of a selection set is the sum over its fields of
 ///   the raw cost plus the size times the field cost of the field's own
 ///   selection set. Inline fragments and spreads add the cost of their
```

Modify `packages/typed_graphql/lib/src/validation/cost/list_sizes.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql/lib/src/validation/cost/list_sizes.dart b/packages/typed_graphql/lib/src/validation/cost/list_sizes.dart
index 3b5ca74..f13f0af 100644
--- a/packages/typed_graphql/lib/src/validation/cost/list_sizes.dart
+++ b/packages/typed_graphql/lib/src/validation/cost/list_sizes.dart
@@ -101,27 +101,31 @@ final class ListSizes(
     _ => _count(value),
   };
 
-  double _variable(String name) {
-    // A whole number past the safe-integer range (or a fraction) is still
-    // the size the caller meant: its double value, not the default.
-    if (variables[name] case JsonNumber(:final value)) {
-      return _finiteSize(value.toDouble());
-    }
-    return _count(variableDefaults[name]) ?? defaultListSize.toDouble();
-  }
+  // The size a variable gives: its value, or its default when it has no
+  // value. Null when it names no size (an explicit null, which overrides the
+  // default as in September2025 6.4.1, a non-number, a negative number, or
+  // neither a value nor a default): the field is then sized as if the
+  // argument were not given, so a client cannot lower the cost (R5.14).
+  double? _variable(String name) => switch (variables[name]) {
+    JsonNumber(:final value) => _size(value.toDouble()),
+    null => _count(variableDefaults[name]),
+    _ => null,
+  };
 
   double? _count(Value? value) => switch (value) {
     IntValue(:final value) => switch (double.tryParse(value)) {
-      final number? => _finiteSize(number),
+      final number? => _size(number),
       null => null,
     },
     _ => null,
   };
 
-  // A 400-digit literal parses to Infinity: sizes stay finite so no product
-  // of costs is NaN (`SaturatingCost`).
-  double _finiteSize(double size) =>
-      min<double>(double.maxFinite, max<double>(0, size));
+  // A negative number names no size. A whole number past the safe-integer
+  // range (or a fraction) is still the size the caller meant; a 400-digit
+  // literal parses to Infinity, so sizes stay finite and no product of costs
+  // is NaN (`SaturatingCost`).
+  double? _size(double size) =>
+      size < 0 ? null : min<double>(double.maxFinite, size);
 
   // Loops, not recursion: a wrapper chain can be deep.
   TypeRef _unwrapNonNull(TypeRef type) {
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
git commit -m "fix(typed_graphql): count a slicing value that names no size as not given

<your model trailer>"
```

### Task 12: fix(typed_graphql_server): select and cost the operation the executor runs

**Why.** Answers the review of Task 8. `OperationLookup` took the first operation with a matching name while the executor (`OperationSelection`, September2025 6.1 `GetOperation`) takes the last; with caller-supplied rules that drop `UniqueOperationNames`, a client could name two operations alike so that the GET mutation check and the cost limit judged one and the executor ran the other. The lookup now delegates to `OperationSelection`. The cost tests are split one behaviour per test, guard the message against `MaxCostRule`'s wording, and cover a cached document costed again, values that name no size, a huge value, a fraction (left to coercion), `operationName`, duplicate names, GET, no limit and an unknown operation (`GQL320`). The `onExecute` doc says a hook that rewrites the operation name or variables is trusted server code.

**Files** (verified commit `631a760` of the controller's scratch copy):

- Modify `packages/typed_graphql_server/lib/src/server/operation_lookup.dart`
- Modify `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart`
- Modify `packages/typed_graphql_server/lib/src/server/request_step.dart`
- Modify `packages/typed_graphql_server/lib/src/server/server_extension.dart`
- Modify `packages/typed_graphql_server/test/server/graphql_server_test.dart`
- Modify `packages/typed_graphql_server/test/server/server_cost_test.dart`
- Modify `packages/typed_graphql_server/test/server/support/cost_fixture.dart`

- [ ] **Step 1: Write the tests.**

Modify `packages/typed_graphql_server/test/server/graphql_server_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/graphql_server_test.dart b/packages/typed_graphql_server/test/server/graphql_server_test.dart
index dd93aef..6ae8b1c 100644
--- a/packages/typed_graphql_server/test/server/graphql_server_test.dart
+++ b/packages/typed_graphql_server/test/server/graphql_server_test.dart
@@ -208,6 +208,23 @@ void main() {
       expect(fixture.codeOf(response), 'GQL402');
     });
 
+    test(
+      'of a query and a mutation sharing a name, the last decides',
+      () async {
+        // Without UniqueOperationNames the executor would run the mutation.
+        final response = await fixture
+            .server(validationRules: [])
+            .handle(
+              fixture.request(
+                'query Q { hello } mutation Q { bump }',
+                method: 'GET',
+                operationName: 'Q',
+              ),
+            );
+        expect(fixture.codeOf(response), 'GQL402');
+      },
+    );
+
     test('an empty operation name names no operation: GQL320', () async {
       final response = await fixture.server().handle(
         fixture.request('{ hello }', operationName: ''),
```

Modify `packages/typed_graphql_server/test/server/server_cost_test.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/server_cost_test.dart b/packages/typed_graphql_server/test/server/server_cost_test.dart
index 7f46826..05b6610 100644
--- a/packages/typed_graphql_server/test/server/server_cost_test.dart
+++ b/packages/typed_graphql_server/test/server/server_cost_test.dart
@@ -10,10 +10,13 @@ void main() {
   final fixture = ServerFixture();
   var built = 0;
 
-  GraphQLServer<Ctx> serverWith(double? maxCost) => costs.server(maxCost, (_) {
+  GraphQLServer<Ctx> serverWith(
+    double? maxCost, {
+    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
+  }) => costs.server(maxCost, (_) {
     built++;
     return const Ctx('x');
-  });
+  }, validationRules: validationRules);
 
   Future<ServerResponse> send(
     double? maxCost,
@@ -33,9 +36,13 @@ void main() {
   setUp(() => built = 0);
 
   group('a literal size', () {
-    test('over the limit is GQL238 with the core rule message', () async {
+    test('over the limit is GQL238', () async {
       final response = await send(10, '{ items(first: 10) { name } }');
       expect(fixture.codeOf(response), 'GQL238');
+    });
+
+    test('over the limit has the core rule message', () async {
+      final response = await send(10, '{ items(first: 10) { name } }');
       expect(
         fixture.messageOf(response),
         'The anonymous operation has a field cost of 1 and a type cost of 11, '
@@ -43,16 +50,24 @@ void main() {
       );
     });
 
-    test('is a request error pointing at a named operation', () async {
+    test('over the limit is a request error', () async {
+      final response = await send(10, '{ items(first: 10) { name } }');
+      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
+    });
+
+    test('over the limit points at the operation', () async {
       final response = await send(
         10,
         '\n  query Q { items(first: 10) { name } }',
       );
-      expect((response as SingleResponse).outcome, ServerOutcome.requestError);
       final errors = fixture.json(response)['errors']! as List<Object?>;
       expect((errors.first! as Map<String, Object?>)['locations'], [
         {'line': 2, 'column': 3},
       ]);
+    });
+
+    test('names a named operation', () async {
+      final response = await send(10, 'query Q { items(first: 10) { name } }');
       expect(
         fixture.messageOf(response),
         startsWith('The operation "Q" has a field cost of 1'),
@@ -70,6 +85,20 @@ void main() {
     });
   });
 
+  test('the message is the one MaxCostRule reports', () async {
+    const text = 'query Q { items(first: 10) { name } }';
+    final source = Source(text);
+    final document = const Parser().parse(source).requireDocument();
+    final result = const DocumentValidator(
+      rules: [MaxCostRule(maxCost: 10)],
+    ).validate(costs.schema.schema, document, source: source);
+    final response = await send(10, text);
+    expect(
+      fixture.messageOf(response),
+      (result as InvalidDocument).diagnostics.single.message,
+    );
+  });
+
   group('a size given by a variable', () {
     const text = r'query ($n: Int) { items(first: $n) { name } }';
 
@@ -90,31 +119,87 @@ void main() {
       );
       expect(fixture.json(response)['data'], isNotNull);
     });
+
+    test('is costed again for a cached document', () async {
+      final server = serverWith(10);
+      await server.handle(
+        fixture.request(text, variables: JsonObject({'n': JsonNumber(1)})),
+      );
+      final response = await server.handle(
+        fixture.request(
+          text,
+          variables: JsonObject({'n': JsonNumber(1000000)}),
+        ),
+      );
+      expect(fixture.codeOf(response), 'GQL238');
+    });
   });
 
-  group('a hostile variable value', () {
+  group('a variable value that names no size counts as not given', () {
+    // Not given, `items` has the default list size, 10: a type cost of 11.
     const text = r'query ($n: Int) { items(first: $n) { name } }';
 
     for (final (label, value) in <(String, JsonValue)>[
       ('a string', const JsonString('many')),
-      ('a fraction', JsonNumber(1.5)),
       ('a negative number', JsonNumber(-5)),
-      ('a huge number', JsonNumber(1e300)),
       ('null', const JsonNull()),
       ('an object', JsonObject({})),
     ]) {
-      test('$label is never an internal error', () async {
+      test(label, () async {
         final response = await send(
           10,
           text,
           variables: JsonObject({'n': value}),
         );
-        expect(
-          (response as SingleResponse).outcome,
-          isNot(ServerOutcome.internalError),
-        );
+        expect(fixture.codeOf(response), 'GQL238');
       });
     }
+
+    test('a missing value', () async {
+      final response = await send(10, text);
+      expect(fixture.codeOf(response), 'GQL238');
+    });
+  });
+
+  test('a huge variable value is refused', () async {
+    final response = await send(
+      10,
+      r'query ($n: Int) { items(first: $n) { name } }',
+      variables: JsonObject({'n': JsonNumber(1e300)}),
+    );
+    expect(fixture.codeOf(response), 'GQL238');
+  });
+
+  test('a fractional variable value is left to coercion', () async {
+    // 1.5 is within the limit; the executor refuses it as an Int.
+    final response = await send(
+      10,
+      r'query ($n: Int) { items(first: $n) { name } }',
+      variables: JsonObject({'n': JsonNumber(1.5)}),
+    );
+    expect(fixture.codeOf(response), isNot('GQL238'));
+  });
+
+  test('the operation named by operationName is costed', () async {
+    final response = await send(
+      10,
+      'query Cheap { items(first: 1) { name } } '
+      'query Costly { items(first: 10) { name } }',
+      operationName: 'Costly',
+    );
+    expect(fixture.codeOf(response), 'GQL238');
+  });
+
+  test('of two operations sharing a name the executed one is costed', () async {
+    // Without UniqueOperationNames the executor runs the last one.
+    final response = await serverWith(10, validationRules: const []).handle(
+      fixture.request(
+        'query Q { items(first: 1) { name } } '
+        'query Q { items(first: 10) { name } }',
+        operationName: 'Q',
+      ),
+    );
+    expect(fixture.codeOf(response), 'GQL238');
   });
 
   test('a GET query is costed', () async {
@@ -137,6 +222,6 @@ void main() {
       '{ items(first: 10) { name } }',
       operationName: 'Nope',
     );
-    expect(fixture.codeOf(response), isNot('GQL238'));
+    expect(fixture.codeOf(response), 'GQL320');
   });
 }
```

Modify `packages/typed_graphql_server/test/server/support/cost_fixture.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/test/server/support/cost_fixture.dart b/packages/typed_graphql_server/test/server/support/cost_fixture.dart
index d42cf14..4e67552 100644
--- a/packages/typed_graphql_server/test/server/support/cost_fixture.dart
+++ b/packages/typed_graphql_server/test/server/support/cost_fixture.dart
@@ -50,15 +50,20 @@ final class CostFixture {
     );
   }
 
+  // Late: the constructor body builds it, before any reader can run.
   late final ExecutableSchema<Ctx> schema;
 
   /// A server limiting the cost to [maxCost]; null is no limit.
-  GraphQLServer<Ctx> server(double? maxCost, ContextFactory<Ctx> factory) =>
-      GraphQLServer<Ctx>(
-        schema: schema,
-        contextFactory: factory,
-        profile: ServerProfile.development.withLimits(
-          ServerLimits(maxCost: maxCost),
-        ),
-      );
+  GraphQLServer<Ctx> server(
+    double? maxCost,
+    ContextFactory<Ctx> factory, {
+    List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
+  }) => GraphQLServer<Ctx>(
+    schema: schema,
+    contextFactory: factory,
+    profile: ServerProfile.development.withLimits(
+      ServerLimits(maxCost: maxCost),
+    ),
+    validationRules: validationRules,
+  );
 }
```

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: "duplicate names under `validationRules: const []` are costed as the last" in `server_cost_test.dart` and "of a query and a mutation sharing a name, the last decides" in `graphql_server_test.dart` fail: the old lookup takes the first operation.

- [ ] **Step 3: Write the implementation.**

Modify `packages/typed_graphql_server/lib/src/server/operation_lookup.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/operation_lookup.dart b/packages/typed_graphql_server/lib/src/server/operation_lookup.dart
index dbefbe2..4a696ad 100644
--- a/packages/typed_graphql_server/lib/src/server/operation_lookup.dart
+++ b/packages/typed_graphql_server/lib/src/server/operation_lookup.dart
@@ -1,25 +1,27 @@
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
-/// Finds which operation a request selects, as the executor will.
+import '../plan/operation_selection.dart';
+import '../plan/operation_selection_result.dart';
+
+/// Finds which operation a request selects with the executor's own
+/// selection, so the method check and the cost limit judge the operation
+/// that runs, even when caller-supplied rules let two operations share a
+/// name (the executor takes the last).
 @internal
 final class OperationLookup {
-  /// Creates the lookup.
-  const OperationLookup();
+  /// Creates the lookup over [selection].
+  const OperationLookup(this.selection);
+
+  /// The executor's selection (September2025 6.1 `GetOperation`).
+  final OperationSelection selection;
 
   /// The operation of [document] named [operationName] (the only operation
   /// when null), or null when there is none to select; the executor then
-  /// reports `GQL320`-`GQL322` (September2025 6.1.2).
-  OperationDefinition? operationOf(Document document, String? operationName) {
-    final operations = document.definitions.whereType<OperationDefinition>();
-    if (operationName == null) {
-      return operations.length == 1 ? operations.first : null;
-    }
-    for (final operation in operations) {
-      if (operation.name?.value == operationName) {
-        return operation;
-      }
-    }
-    return null;
-  }
+  /// reports why (`GQL320`-`GQL323`).
+  OperationDefinition? operationOf(Document document, String? operationName) =>
+      switch (selection.select(document, operationName)) {
+        OperationSelected(:final operation) => operation,
+        OperationRejected() => null,
+      };
 }
```

Modify `packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart b/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
index 5517967..2106c1d 100644
--- a/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
+++ b/packages/typed_graphql_server/lib/src/server/pipeline_assembly.dart
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../execution/error_hook.dart';
 import '../execution/executable_schema.dart';
+import '../plan/operation_selection.dart';
 import 'context_factory.dart';
 import 'cost_limit.dart';
 import 'csrf_extension.dart';
@@ -13,6 +14,7 @@ import 'document_length.dart';
 import 'document_step.dart';
 import 'execution_step.dart';
 import 'extension_chain.dart';
+import 'operation_lookup.dart';
 import 'pipeline_errors.dart';
 import 'request_handler.dart';
 import 'request_step.dart';
@@ -75,6 +77,7 @@ final class PipelineAssembly<C> {
     final executionStep = ExecutionStep<C>(schema, profile, onError);
     final request = RequestStep<C>(
       length: length,
+      operations: OperationLookup(OperationSelection(schema.schema.schema)),
       documentPhase: chain.document(_documentStep(length)),
       contextFactory: contextFactory,
       executionStep: executionStep,
```

Modify `packages/typed_graphql_server/lib/src/server/request_step.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/request_step.dart b/packages/typed_graphql_server/lib/src/server/request_step.dart
index fbe27f5..8c3a769 100644
--- a/packages/typed_graphql_server/lib/src/server/request_step.dart
+++ b/packages/typed_graphql_server/lib/src/server/request_step.dart
@@ -25,6 +25,7 @@ final class RequestStep<C> {
   /// Creates the step.
   const RequestStep({
     required this.length,
+    required this.operations,
     required this.documentPhase,
     required this.contextFactory,
     required this.executionStep,
@@ -36,6 +37,9 @@ final class RequestStep<C> {
   /// The length check of the request's query.
   final DocumentLength length;
 
+  /// Finds the operation the request selects.
+  final OperationLookup operations;
+
   /// The document phase with its extensions.
   final DocumentHandler documentPhase;
 
@@ -72,7 +76,7 @@ final class RequestStep<C> {
     ServerRequest request,
   ) async {
     final document = accepted.document.document;
-    final operation = const OperationLookup().operationOf(
+    final operation = operations.operationOf(
       document,
       request.params.operationName,
     );
```

Modify `packages/typed_graphql_server/lib/src/server/server_extension.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/lib/src/server/server_extension.dart b/packages/typed_graphql_server/lib/src/server/server_extension.dart
index 5a3faad..d0692f1 100644
--- a/packages/typed_graphql_server/lib/src/server/server_extension.dart
+++ b/packages/typed_graphql_server/lib/src/server/server_extension.dart
@@ -34,6 +34,10 @@ abstract class ServerExtension<C> {
   ) => next(request);
 
   /// Wraps the execution, which has the context and the options.
+  ///
+  /// The method check and the cost limit judged the request as it reached
+  /// this phase: a hook that rewrites the request's operation name or
+  /// variables is server code, trusted to keep within the limits.
   Future<ServerResponse> onExecute(
     ExecutionRequest<C> request,
     ExecutionHandler<C> next,
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
git commit -m "fix(typed_graphql_server): select and cost the operation the executor runs

<your model trailer>"
```

### Task 13: docs: document the request pipeline

**Why.** The stage documents of M6b (CLAUDE.md, Documentation): the full Server guide (serving a request, requests and responses, profiles, limits and the cost limit, CSRF prevention, the document cache, extensions, errors and masking, the codes), every program run and its output pasted; the example and the README quick tour serve through `GraphQLServer`; the README banner and "Should I use this?", `llms.txt`, the discovery row, the root README, CLAUDE.md (status, the `server/` paragraph, the allowed imports) and the changelog.

**Files** (verified commit `db8de45` of the controller's scratch copy):

- Modify `CLAUDE.md`
- Modify `README.md`
- Modify `docs/discovery.md`
- Modify `llms.txt`
- Modify `packages/typed_graphql_server/CHANGELOG.md`
- Modify `packages/typed_graphql_server/README.md`
- Modify `packages/typed_graphql_server/doc/server.md`
- Modify `packages/typed_graphql_server/example/example.dart`

- [ ] **Step 1: Write the tests.**

This commit changes no test file.

- [ ] **Step 2: Run the tests and see them fail.**

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test" )' 2>&1 | tail -30
```

Expected: nothing fails before the docs change; afterwards the documentation suite (`test/doc`) runs every program of `doc/server.md` and `example/example.dart` and compares its output.

- [ ] **Step 3: Write the implementation.**

Modify `CLAUDE.md` (exact diff):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 4a1748f..8296faf 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -64,7 +64,12 @@ benchmark and the Look-ahead, Authorization and Cancellation guides; with it
 stage M5 (execution) is complete. M6a (DataLoader) delivers `BatchLoader` and
 `GroupedLoader` (per-request batching after the microtask queue drains,
 de-duplication, a per-loader cache, `MissingValueException`) and the DataLoader
-guide. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+guide. M6b (request pipeline) delivers `GraphQLServer`, `RequestInfo`,
+`ServerRequest`, `ServerResponse` and `ServerOutcome`, the document cache,
+`ServerExtension` and its three phases, `ServerProfile` and `ServerLimits`
+(length, tokens, depth, aliases, directives, cost per request), CSRF
+prevention, error masking and the error hook in the pipeline (`GQL400`-
+`GQL403`), the hostile-input tests and the Server guide. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
 file or a URL, the project's documents as one fragment graph, the planner and
 emitters that generate the schema-types library and a library per document
 (operations, variables, data, fragments, sealed polymorphic classes, the
@@ -422,10 +427,11 @@ only through its barrel. One folder per concern, with no import order
 (`builder/` and `execution/` import each other): `builder/` (M5a),
 `coercion/`, `plan/` and `execution/` (M5b), `introspection/` and
 `subscription/` (M5c), `lookahead/`, `authorization/` and `cancellation/`
-(M5d). The package is
+(M5d), `dataloader/` (M6a) and `server/` (M6b). The package is
 transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
-or web framework, only `dart:async`, `dart:collection`, `dart:core`,
-`dart:math`, `meta` and the core (`test/quality/imports_test.dart`), and the
+or web framework, only `dart:async`, `dart:collection`, `dart:convert`,
+`dart:core`, `dart:math`, `meta`, `crypto` and the core
+(`test/quality/imports_test.dart`), and the
 builder never instantiates resolvers or services: closures get them from the
 context `C`. `ExecutableSchemaBuilder<C>` makes `OutputRef`/`InputRef`/
 `LeafRef` types and definitions in creation order; a field is
@@ -510,6 +516,22 @@ keeps the cache (a failed key is evicted by identity, so a later `clear` or
 listener on every future it creates, so an unread load never reports an
 unhandled error. Loaders are request-scoped because the context factory
 creates them for each request.
+`server/` (M6b): `GraphQLServer` builds a `PipelineAssembly` once: the
+extension chains (`ExtensionChain`, a fold per phase, the first extension
+outermost; the internal `CsrfExtension` sits inside the user's) around the
+core steps. `RequestStep` checks the length (`DocumentLength`, before any
+hashing), runs the document phase (`DocumentStep`: `GQL400`, the length
+again, `DocumentCache`, an LRU keyed by the server-computed SHA-256 of the
+text that also caches rejections, over `DocumentCompiler`: the parser with
+`maxTokens`, the validator with the base rules plus the limit rules),
+selects the operation with the executor's own `OperationSelection`
+(`OperationLookup`), refuses a `GET` mutation (`GQL402`), applies
+`CostLimit` (`CostAnalysis` with the request's variables, the message of
+`MaxCostRule` through `CostMessage`), and only then builds the context and
+runs the execution phase (`ExecutionStep`, options per profile).
+`PipelineErrors` makes every refusal and the masked `GQL330`;
+`GraphQLServer.handle` is the outermost catch, so it never throws.
+`dart:convert` and `crypto` are allowed in `lib/` for the hash.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
```

Modify `README.md` (exact diff):

````diff
diff --git a/README.md b/README.md
index bc6990f..edf1212 100644
--- a/README.md
+++ b/README.md
@@ -28,8 +28,9 @@ SDL), the schema (build it from SDL, extend, print and validate it, introspectio
 both ways, schema coordinates), operation validation, the wire protocol types,
 scalar codecs and the diagnostics model; and, in `typed_graphql_server`, a
 typed schema builder, the execution of a validated operation, introspection,
-subscriptions, look-ahead at the requested fields, field authorization and
-cancellation.
+subscriptions, look-ahead at the requested fields, field authorization,
+cancellation, DataLoader and a transport-agnostic request pipeline
+(`GraphQLServer`: limits, the cost limit, CSRF prevention, extensions).
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
@@ -112,7 +113,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete) and DataLoader (M6a) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader (M6a) and the request pipeline (M6b) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
````

Modify `docs/discovery.md` (exact diff):

```diff
diff --git a/docs/discovery.md b/docs/discovery.md
index 9f22e29..cee6d08 100644
--- a/docs/discovery.md
+++ b/docs/discovery.md
@@ -46,6 +46,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | authorize GraphQL fields dart | M5 | yes |
 | cancel or time out a GraphQL request dart | M5 | yes |
 | dataloader dart graphql | M6 | yes |
+| GraphQL CSRF prevention dart | M6 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
 
```

Modify `llms.txt` (exact diff):

```diff
diff --git a/llms.txt b/llms.txt
index 2b8fbb5..212a34d 100644
--- a/llms.txt
+++ b/llms.txt
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); the request pipeline (rest of M6) and the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; batches and caches the loads of one request with DataLoader (BatchLoader, GroupedLoader); and serves transport-agnostic requests with GraphQLServer (a document cache, depth, alias, directive, token, length and cost limits, production and development profiles, CSRF prevention, extensions and error masking); persisted queries (rest of M6) and the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation and DataLoader in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation and DataLoader (BatchLoader, GroupedLoader) work; the request pipeline (rest of M6) and transport handlers (M7) come later
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization, Cancellation, DataLoader and Server in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization, cancellation, DataLoader (BatchLoader, GroupedLoader) and the request pipeline (GraphQLServer with limits, the cost limit, CSRF prevention and extensions) work; persisted queries (rest of M6) and transport handlers (M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

Modify `packages/typed_graphql_server/CHANGELOG.md` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/CHANGELOG.md b/packages/typed_graphql_server/CHANGELOG.md
index 30638c5..112615d 100644
--- a/packages/typed_graphql_server/CHANGELOG.md
+++ b/packages/typed_graphql_server/CHANGELOG.md
@@ -173,3 +173,5 @@
   request whose field cost or type cost is over the limit is refused with
   `GQL238` and `MaxCostRule`'s message. Slicing arguments given as variables
   count with the request's values.
+- The Server guide and the example now serve a request with
+  `GraphQLServer`.
```

Modify `packages/typed_graphql_server/README.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/README.md b/packages/typed_graphql_server/README.md
index d3e3c41..28dbe7b 100644
--- a/packages/typed_graphql_server/README.md
+++ b/packages/typed_graphql_server/README.md
@@ -16,8 +16,11 @@
 > under a field, guard fields with an authorizer and stop a request with a
 > cancel signal or a timeout. DataLoader (M6a) works too: `BatchLoader` and
 > `GroupedLoader` batch and cache the loads of one request. The request
-> pipeline comes later in M6, the HTTP, graphql-ws and graphql-sse handlers
-> in M7. See the
+> pipeline (M6b) works: `GraphQLServer` serves a transport-agnostic request
+> with a document cache, the limits and the cost limit of a production or
+> development profile, CSRF prevention, extensions and error masking.
+> Persisted queries come later in M6, the HTTP, graphql-ws and graphql-sse
+> handlers in M7. See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
 ## Contents
@@ -50,8 +53,8 @@ dependencies:
   [Execution](doc/execution.md#executing-a-request)).
 - **You do not need it when** you only call a GraphQL server: that is the
   client package, not usable yet. Today it also has no HTTP or
-  WebSocket handler: you call `ExecutableSchema.execute` or `subscribe`
-  yourself with a parsed and validated document (the request pipeline is M6, the handlers M7).
+  WebSocket handler: you decode the request yourself and call
+  `GraphQLServer.handle` (the handlers are M7).
 - **What it replaces**: resolvers written against `Map<String, dynamic>`, where
   a wrong result type or a misspelled argument name fails at run time in the
   middle of a request. Here the wrong type does not compile, and every error
@@ -63,9 +66,10 @@ dependencies:
 
 ## A quick tour
 
-Declare the schema, validate a request, execute it. Every resolver here is
-synchronous; a resolver may also return a `Future`. The same program is in
-[example/example.dart](example/example.dart).
+Declare the schema, then serve a request with `GraphQLServer`: it parses and
+validates the document, applies the limits of its profile and executes. Every
+resolver here is synchronous; a resolver may also return a `Future`. The same
+program is in [example/example.dart](example/example.dart).
 
 ```dart
 import 'dart:io';
@@ -106,23 +110,31 @@ Future<void> main() async {
   );
   final schema = b.build(query: query);
 
-  // Parse and validate a request against the schema: a problem is a
-  // diagnostic, never an exception.
-  final source = Source('{ books(limit: 2) { title pages } }');
-  final document = const Parser().parse(source).requireDocument();
-  final checked = const DocumentValidator().validate(
-    schema.schema,
-    document,
-    source: source,
+  // Serve it: the server parses and validates the document (cached),
+  // applies the limits of its profile (production unless you pick one),
+  // builds the context and executes. It knows nothing of HTTP.
+  final server = GraphQLServer<Object?>(
+    schema: schema,
+    contextFactory: (request) => null,
   );
-  if (checked case final ValidDocument valid) {
-    // Execute it: the response is a value that writes itself as JSON.
-    final response = await schema.execute(
-      valid,
-      context: null,
-      options: ExecutionOptions(source: source),
-    );
-    stdout.writeln(response.toJson());
+  final response = await server.handle(
+    ServerRequest(
+      params: const GraphQLRequest(
+        query: '{ books(limit: 2) { title pages } }',
+      ),
+      info: RequestInfo(
+        method: 'POST',
+        uri: Uri.parse('http://localhost/graphql'),
+        headers: {'content-type': 'application/json'},
+      ),
+    ),
+  );
+
+  // The response is a value: an outcome a transport maps to a status, and
+  // a body that writes itself as JSON.
+  if (response case SingleResponse(:final outcome, :final body)) {
+    stdout.writeln(outcome.name);
+    stdout.writeln(body);
   }
 }
 ```
@@ -130,11 +142,15 @@ Future<void> main() async {
 It prints:
 
 ```text
+executed
 {"data":{"books":[{"title":"Dune","pages":412},{"title":"Emma","pages":null}]}}
 ```
 
 ## Guides
 
+- [Server](doc/server.md): `GraphQLServer`, requests, responses and outcomes,
+  profiles, limits and the cost limit, CSRF prevention, the document cache,
+  extensions, errors and masking.
 - [Schema Builder](doc/schema_builder.md): refs, objects, fields, arguments,
   scalars, enums, input objects, interfaces and unions, building the schema.
 - [Execution](doc/execution.md): executing a request, variables, request errors
````

Modify `packages/typed_graphql_server/doc/server.md` (exact diff):

````diff
diff --git a/packages/typed_graphql_server/doc/server.md b/packages/typed_graphql_server/doc/server.md
index 07a1f31..2deed47 100644
--- a/packages/typed_graphql_server/doc/server.md
+++ b/packages/typed_graphql_server/doc/server.md
@@ -1,28 +1,535 @@
 # Server
 
-This guide describes `RequestInfo`, the request a transport hands to the
-server. It grows with the request pipeline.
+`GraphQLServer` serves GraphQL requests over an `ExecutableSchema`: it
+parses and validates the document (cached), applies the limits and the
+protections of its profile, builds the context and executes (R5.1). It
+knows nothing of HTTP: a transport, or a host framework's adapter, decodes a
+`ServerRequest` and writes the `ServerResponse` back. This guide covers the
+request and the response, profiles and limits, the cost limit, CSRF
+prevention, the document cache, extensions and errors.
 
-`RequestInfo` holds the method, the URI and the headers of a request. Header
-names are lower-cased when it is made, and `header` finds one by any case.
+## Serving a request
+
+A server takes the schema and a context factory, which builds the context
+of each request from its `RequestInfo`. The factory runs once per request,
+after every check of the server has passed, so a refused request never
+builds a context.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+final class Viewer {
+  const Viewer(this.name);
+
+  final String name;
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
+    contextFactory: (request) => Viewer(request.header('x-user') ?? 'guest'),
+  );
+  final response = await server.handle(
+    ServerRequest(
+      params: const GraphQLRequest(query: '{ hello }'),
+      info: RequestInfo(
+        method: 'POST',
+        uri: Uri.parse('http://localhost/graphql'),
+        headers: {'Content-Type': 'application/json', 'X-User': 'Ada'},
+      ),
+    ),
+  );
+  switch (response) {
+    case SingleResponse(:final outcome, :final body):
+      print('${outcome.name} $body');
+    case StreamResponse():
+      print('a subscription stream');
+  }
+}
+```
+
+It prints:
+
+```text
+executed {"data":{"hello":"Hello, Ada!"}}
+```
+
+`handle` never throws: every refusal and every failure is a response.
+
+## Requests and responses
+
+- `RequestInfo` holds the method, the URI and the headers of a request, and
+  `source`, the host's own request object, which the library never reads.
+  Header names are lower-cased when it is made, and `header` finds one by
+  any case. A transport joins repeated values with `, `.
+- `ServerRequest` holds the `GraphQLRequest` (query, operation name,
+  variables, extensions), the `RequestInfo` and an optional `CancelSignal`
+  the caller owns, for example cancelled when the client disconnects.
+- `ServerResponse` is sealed: a `SingleResponse` holds a `ResponsePayload`
+  and its JSON `body`; a `StreamResponse` holds the results of a
+  subscription. Both have an `outcome` and `headers`, a hint the transport
+  adds to its own. `withHeaders` returns a copy with more headers.
+
+`ServerOutcome` is the status-like part, which the HTTP transport (M7) maps
+to a status code:
+
+| Outcome | When |
+|---|---|
+| `executed` | the operation ran; `data` may be `null` after field errors |
+| `requestError` | the request cannot run: no query, a syntax or validation error, a limit, CSRF, an unknown operation, bad variables, or a `GraphQLException` from the context factory or an extension |
+| `methodNotAllowed` | a mutation in a `GET` request; the headers say `allow: POST` |
+| `internalError` | an unexpected error of server code (the context factory, an extension), masked by the profile |
+
+A `GET` request may run a query or a subscription, never a mutation:
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
+  );
+  final mutation = b.object<Object?>(
+    'Mutation',
+    fields: (t) => [t.field('bump', b.int).pure((_) => 1)],
+  );
+  final server = GraphQLServer<Object?>(
+    schema: b.build(query: query, mutation: mutation),
+    contextFactory: (request) => null,
+  );
+  for (final (method, text) in [
+    ('GET', '{ hello }'),
+    ('GET', 'mutation { bump }'),
+    ('POST', '{ hello'),
+  ]) {
+    final response = await server.handle(
+      ServerRequest(
+        params: GraphQLRequest(query: text),
+        info: RequestInfo(
+          method: method,
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: {'graphql-require-preflight': '1'},
+        ),
+      ),
+    );
+    if (response case SingleResponse(:final outcome, :final body)) {
+      print('$method ${outcome.name} ${response.headers}');
+      print(body);
+    }
+  }
+}
+```
+
+It prints:
+
+```text
+GET executed {}
+{"data":{"hello":"world"}}
+GET methodNotAllowed {allow: POST}
+{"errors":[{"message":"A mutation can only be sent with the POST method.","extensions":{"code":"GQL402"}}]}
+POST requestError {}
+{"errors":[{"message":"Expected Name, found <EOF>.","locations":[{"line":1,"column":8}],"extensions":{"code":"GQL007"}}]}
+```
+
+## Profiles
+
+A `ServerProfile` holds every protection. `GraphQLServer` uses
+`ServerProfile.production` unless told otherwise, so a forgotten profile
+does not expose a server; `ServerProfile.development` is chosen explicitly.
+
+| Setting | `development` | `production` |
+|---|---|---|
+| `introspection` | `enabled` | `disabled` (`__schema` and `__type` are field errors, `__typename` works) |
+| `includesSuggestions` | `true` | `false` (no "Did you mean" in messages) |
+| `maskErrors` | `false` | `true` |
+| `csrfPrevention` | `CsrfPrevention()` | `CsrfPrevention()` |
+| `limits` | `ServerLimits.development` | `ServerLimits.production` |
+| `timeout` | none | none |
+
+Each setting has a `with*` method that returns a copy:
+`withIntrospection`, `withSuggestions`, `withErrorMasking`,
+`withCsrfPrevention` (null turns it off), `withLimits` and `withTimeout`
+(queries and mutations only: a timeout would end a subscription).
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
+  );
+  final schema = b.build(query: query);
+  for (final profile in [
+    ServerProfile.production,
+    ServerProfile.production.withIntrospection(IntrospectionPolicy.enabled),
+  ]) {
+    final server = GraphQLServer<Object?>(
+      schema: schema,
+      contextFactory: (request) => null,
+      profile: profile,
+    );
+    final response = await server.handle(
+      ServerRequest(
+        params: const GraphQLRequest(
+          query: '{ __typename __schema { queryType { name } } }',
+        ),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: {'content-type': 'application/json'},
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
+{"errors":[{"message":"GraphQL introspection has been disabled, but the requested query contained the field \"__schema\".","locations":[{"line":1,"column":14}],"path":["__schema"],"extensions":{"code":"GQL338"}}],"data":null}
+{"data":{"__typename":"Query","__schema":{"queryType":{"name":"Query"}}}}
+```
+
+A server that admits introspection for some callers only does so in an
+`onExecute` hook with `withOptions` (see Extensions below).
+
+## Limits and the cost limit
+
+`ServerLimits` bounds the work a request can ask for; a null limit is off.
+Every limit is checked before the context is built and before any resolver
+runs.
+
+| Limit | Applied by | `development` | `production` |
+|---|---|---|---|
+| `maxDocumentLength` | the server, before hashing (`GQL401`) | 100 000 | 100 000 |
+| `maxTokens` | the parser (`GQL006`) | 15 000 | 15 000 |
+| `maxDepth` | `MaxDepthRule` (`GQL232`) | none | 15 |
+| `maxAliases` | `MaxAliasesRule` (`GQL233`) | none | 15 |
+| `maxDirectives` | `MaxDirectivesRule` (`GQL234`) | none | 50 |
+| `maxCost` | the cost limit (`GQL238`) | none | 10 000 |
+| `defaultListSize` | the cost limit | 10 | 10 |
+
+The depth, alias and directive rules join the server's `validationRules`
+(by default `DocumentValidator.recommendedRules`; custom rules go there
+too). The cost limit runs per request, after the operation is selected,
+with the request's variables: a slicing argument such as `first: $n` is
+counted with the value the client sent, which a validation rule cannot see
+(see the Operation Validation guide of the core for how a cost is counted).
+A list field the schema gives no size counts `defaultListSize` items.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+final class Item {
+  const Item(this.name);
+
+  final String name;
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  // Late: the fields run on first use, after the assignment.
+  late final ObjectTypeDef<Item> item;
+  item = b.object<Item>(
+    'Item',
+    fields: (t) => [
+      t.field('name', b.string).pure((item) => item.name),
+      t.field('children', b.list(item)).pure((item) => const <Item>[]),
+    ],
+  );
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('items', b.list(item)).pure((_) => const [Item('a')]),
+    ],
+  );
+  final server = GraphQLServer<Object?>(
+    schema: b.build(query: query),
+    contextFactory: (request) => null,
+  );
+  for (final text in [
+    '{ items { children { name } } }',
+    '{ items { children { children { children { name } } } } }',
+  ]) {
+    final response = await server.handle(
+      ServerRequest(
+        params: GraphQLRequest(query: text),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: {'content-type': 'application/json'},
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
+{"data":{"items":[{"children":[]}]}}
+{"errors":[{"message":"The anonymous operation has a field cost of 1111 and a type cost of 11111, more than the maximum of 10000.","locations":[{"line":1,"column":1}],"extensions":{"code":"GQL238"}}]}
+```
+
+To change one limit, pass a whole `ServerLimits`:
+`ServerProfile.production.withLimits(const ServerLimits(maxDepth: 10, maxCost: 50000))`
+keeps the length and token defaults and turns the alias and directive
+limits off.
+
+## CSRF prevention
+
+A browser sends a cross-site `GET`, or a `POST` with a "simple" content
+type, without asking the server first, carrying the user's cookies.
+`CsrfPrevention` (on in both profiles) refuses such a request (`GQL403`)
+unless it shows it is not one: either its `content-type` is not
+`application/x-www-form-urlencoded`, `multipart/form-data` or `text/plain`
+(JSON passes), or it has a non-empty value for one of `requestHeaders`,
+headers a browser only sends after a preflight. The defaults are
+`graphql-require-preflight` and Apollo's `apollo-require-preflight` and
+`x-apollo-operation-name`, so their clients pass. A `GET` request needs one
+of the headers.
+
+```dart
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
+  );
+  for (final headers in [
+    {'content-type': 'text/plain'},
+    {'content-type': 'text/plain', 'graphql-require-preflight': '1'},
+    {'content-type': 'application/json; charset=utf-8'},
+  ]) {
+    final response = await server.handle(
+      ServerRequest(
+        params: const GraphQLRequest(query: '{ hello }'),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: headers,
+        ),
+      ),
+    );
+    if (response case SingleResponse(:final outcome)) print(outcome.name);
+  }
+}
+```
+
+It prints:
+
+```text
+requestError
+executed
+executed
+```
+
+`withCsrfPrevention(CsrfPrevention(requestHeaders: ['x-my-client']))`
+replaces the header list; `withCsrfPrevention(null)` turns the check off,
+for a server no browser can reach.
+
+## The document cache
+
+The server keeps the outcome of parsing and validating a text in an LRU
+cache of `documentCacheSize` entries (1000 by default, 0 turns it off). The
+key is the SHA-256 of the text, computed by the server, never a hash a
+client sent. A rejected document is cached too, so a repeated bad request
+costs a hash and a lookup. The same text gives the same `ValidDocument`
+object, so the executor's plan cache hits as well. A text longer than
+`maxDocumentLength` is refused before it is hashed, so every entry is
+bounded.
+
+## Extensions
+
+A `ServerExtension` hooks into the three phases of a request. Each hook
+receives the value of its phase and `next`; it may refuse by answering
+without calling `next`, pass on a rewritten value, or look at what comes
+back.
+
+- `onRequest(ServerRequest, next)` wraps the whole request; CSRF
+  prevention is inside it.
+- `onDocument(DocumentRequest, next)` wraps resolving the text to a
+  `ValidDocument`; `withText` replaces the text, and the result is
+  `DocumentAccepted` or `DocumentRejected`.
+- `onExecute(ExecutionRequest, next)` wraps the execution;
+  `withContext` and `withOptions` replace the context and the
+  `ExecutionOptions`.
+
+The first extension in `extensions` is the outermost: it sees every
+request, refused ones included. The built-in checks sit inside the user's
+extensions in a fixed order, so no list order runs a step before a security
+check. Per-field interception is field middleware, set when the schema is
+built (see the Execution guide).
 
 ```dart
+import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
-void main() {
-  final info = RequestInfo(
-    method: 'POST',
-    uri: Uri.parse('http://localhost/graphql'),
-    headers: {'Content-Type': 'application/json'},
+final class RequireKey extends ServerExtension<Object?> {
+  const RequireKey();
+
+  @override
+  Future<ServerResponse> onRequest(
+    ServerRequest request,
+    RequestHandler next,
+  ) async {
+    if (request.info.header('x-api-key') == 'secret') return next(request);
+    return SingleResponse(
+      RequestErrorResult(errors: [GraphQLError('An API key is required.')]),
+      outcome: ServerOutcome.requestError,
+    );
+  }
+}
+
+final class OperationHeader extends ServerExtension<Object?> {
+  const OperationHeader();
+
+  @override
+  Future<ServerResponse> onExecute(
+    ExecutionRequest<Object?> request,
+    ExecutionHandler<Object?> next,
+  ) async {
+    final response = await next(request);
+    final type = request.operationType?.name ?? 'none';
+    return response.withHeaders({'x-operation': type});
+  }
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
   );
-  print(info.headers.keys.join(', '));
-  print(info.header('CONTENT-TYPE'));
+  final server = GraphQLServer<Object?>(
+    schema: b.build(query: query),
+    contextFactory: (request) => null,
+    extensions: const [RequireKey(), OperationHeader()],
+  );
+  for (final key in ['wrong', 'secret']) {
+    final response = await server.handle(
+      ServerRequest(
+        params: const GraphQLRequest(query: '{ hello }'),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: {'content-type': 'application/json', 'x-api-key': key},
+        ),
+      ),
+    );
+    if (response case SingleResponse(:final body)) {
+      print('${response.headers} $body');
+    }
+  }
 }
 ```
 
 It prints:
 
 ```text
-content-type
-application/json
+{} {"errors":[{"message":"An API key is required."}]}
+{x-operation: query} {"data":{"hello":"world"}}
 ```
+
+## Errors and masking
+
+A `GraphQLException` thrown by the context factory or an extension is a
+`requestError` with its message and extensions, as a resolver's is a field
+error. Any other error is unexpected: the server passes it to `onError`
+(the executor's `ErrorHook`, which also sees every resolver's error, so a
+host logs in one place) and answers `internalError` with `GQL330`, its
+message masked as "Unexpected error." when the profile masks errors and the
+error's `toString()` when it does not. A hook that throws gives the masked
+error.
+
+```dart
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
+    contextFactory: (request) => switch (request.header('authorization')) {
+      null => throw const GraphQLException('Sign in first.'),
+      _ => throw StateError('the session store is down'),
+    },
+    onError: (error, stackTrace, reported) {
+      print('logged: $error');
+      return null;
+    },
+  );
+  for (final headers in [
+    {'content-type': 'application/json'},
+    {'content-type': 'application/json', 'authorization': 'Bearer x'},
+  ]) {
+    final response = await server.handle(
+      ServerRequest(
+        params: const GraphQLRequest(query: '{ hello }'),
+        info: RequestInfo(
+          method: 'POST',
+          uri: Uri.parse('http://localhost/graphql'),
+          headers: headers,
+        ),
+      ),
+    );
+    if (response case SingleResponse(:final outcome, :final body)) {
+      print('${outcome.name} $body');
+    }
+  }
+}
+```
+
+It prints:
+
+```text
+requestError {"errors":[{"message":"Sign in first."}]}
+logged: Bad state: the session store is down
+internalError {"errors":[{"message":"Unexpected error.","extensions":{"code":"GQL330"}}]}
+```
+
+## Diagnostic codes
+
+| Code | When |
+|---|---|
+| `GQL400` | the request has no document text: "Must provide query string." |
+| `GQL401` | the text is longer than `maxDocumentLength` |
+| `GQL402` | a mutation in a `GET` request |
+| `GQL403` | CSRF prevention refused the request |
+| `GQL238` | the operation costs more than `maxCost` with the request's variables |
+| `GQL330` | an unexpected error of the context factory or an extension |
+
+The parser's `GQL0xx`, the validator's `GQL2xx` and the executor's `GQL3xx`
+codes reach the client unchanged.
````

Modify `packages/typed_graphql_server/example/example.dart` (exact diff):

```diff
diff --git a/packages/typed_graphql_server/example/example.dart b/packages/typed_graphql_server/example/example.dart
index 02793fc..aa24f6a 100644
--- a/packages/typed_graphql_server/example/example.dart
+++ b/packages/typed_graphql_server/example/example.dart
@@ -36,22 +36,30 @@ Future<void> main() async {
   );
   final schema = b.build(query: query);
 
-  // Parse and validate a request against the schema: a problem is a
-  // diagnostic, never an exception.
-  final source = Source('{ books(limit: 2) { title pages } }');
-  final document = const Parser().parse(source).requireDocument();
-  final checked = const DocumentValidator().validate(
-    schema.schema,
-    document,
-    source: source,
+  // Serve it: the server parses and validates the document (cached),
+  // applies the limits of its profile (production unless you pick one),
+  // builds the context and executes. It knows nothing of HTTP.
+  final server = GraphQLServer<Object?>(
+    schema: schema,
+    contextFactory: (request) => null,
   );
-  if (checked case final ValidDocument valid) {
-    // Execute it: the response is a value that writes itself as JSON.
-    final response = await schema.execute(
-      valid,
-      context: null,
-      options: ExecutionOptions(source: source),
-    );
-    stdout.writeln(response.toJson());
+  final response = await server.handle(
+    ServerRequest(
+      params: const GraphQLRequest(
+        query: '{ books(limit: 2) { title pages } }',
+      ),
+      info: RequestInfo(
+        method: 'POST',
+        uri: Uri.parse('http://localhost/graphql'),
+        headers: {'content-type': 'application/json'},
+      ),
+    ),
+  );
+
+  // The response is a value: an outcome a transport maps to a status, and
+  // a body that writes itself as JSON.
+  if (response case SingleResponse(:final outcome, :final body)) {
+    stdout.writeln(outcome.name);
+    stdout.writeln(body);
   }
 }
```

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
git commit -m "docs: document the request pipeline

<your model trailer>"
```

## Verification

After Task 13, the scratch copy passed every check:

- format changed 0 files;
- `dart analyze --fatal-infos` printed `No issues found!`;
- the root suite passed 347 tests;
- the core suite passed 1514 tests;
- the server suite passed 1069 tests;
- the server's `test/doc` passed 200 tests;
- `dart doc` for the server reported 0 warnings and 0 errors.

The implementer of each task runs the green check of its Step 4. After Task 13, the controller (or the final reviewer) also runs these:

```sh
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql && dart test --compiler exe" )' 2>&1 | tail -5
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart test --compiler exe" )' 2>&1 | tail -5
flock /tmp/claude-1000/dart-heavy.lock bash -c '( ulimit -v 8000000; timeout 600 bash -c "cd packages/typed_graphql_server && dart pub publish --dry-run" )' 2>&1 | tail -5
```

Chrome runs (dart2js, dart2wasm) are left to CI.
