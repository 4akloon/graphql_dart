# M5d Look-ahead, Authorization and Cancellation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish stage M5 of `typed_graphql_server` (R4.17-R4.20, R0.3): `FieldInfo.selection` (look-ahead: `FieldSelection`, `SelectedField`, a canonical `fingerprint`, `ColumnWhitelist`), field authorization through an application `Authorizer` (`Authorization.public` / `requires`, `GQL304`, `GQL352`, `AuthorizationCoverage`), cancellation and timeouts through a caller-owned `CancelSignal` (`GQL350`, `GQL351`) for `execute` and `subscribe`, the graphql-js cancellation suite, executor benchmarks, and the Look-ahead, Authorization and Cancellation guides.

**Architecture:** Look-ahead is a lazy view: `FieldInfo.selection` is built on first read from the plan's field nodes and the run's coerced variables; `SelectionNodes` merges the plans of every possible type of an abstract field by response key; `SelectionFingerprint` and `CanonicalJson` walk with explicit stacks. Authorization never touches the executor: after middleware composition, the internal `AuthorizationApplier` rewrites the field tables, wrapping each guarded lane in a `FieldGuard` (the authorizer runs after argument coercion, before middleware; a guarded pure field becomes a resolver lane; introspection bindings are added afterwards and never guarded). Cancellation is `RunCancellation`, created only when a signal or a timeout is given: it links the caller's signal and the timer into the run's signal, races the root completion once, makes each field check `isCancelled` before it starts, and releases the timer and the listener when the run ends; `SubscriptionExecution` races a pending source the same way and `SubscriptionResponses` ends the stream with the final error result.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5), `package:test`, `package:meta`, the core `typed_graphql`. graphql-js 17.0.2 in `reference/graphql-js` (`execution/__tests__/cancellation-test.ts`).

**Spec:** `docs/superpowers/specs/2026-10-15-m5-execution-design.md` (sections 11-20, deviations 34-44), `docs/requirements.md` R4.17-R4.20.

**Base:** the M5c plan (`2026-10-15-m5c-introspection-and-subscriptions.md`) applied, at `ec17512`. The plan was verified by applying its tasks in order, one commit per task, with the green check after each and the server and core suites on exe at the end.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- The server imports the core only through its barrel, and `lib/` imports no platform library but `dart:async`, `dart:collection`, `dart:core` and `dart:math` (spec section 17).
- A ported graphql-js test is recorded in `packages/typed_graphql_conformance/mapping/execution.csv` in the same commit, and a behaviour difference goes into the spec's section 18.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time. Chrome cannot start under `ulimit -v`; bound the browser runs by resident memory with `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- `reference/` (git-ignored) holds graphql-js; fetch it with `tool/fetch_reference.sh` before the conformance task. Never `git add` it.
- Bad input never throws (R0.3): a deny is a `GQL352` field error, a cancellation or timeout a `GQL350` / `GQL351` result; only programmer errors throw (`GQL304` through `SchemaBuildError`, an empty `has` segment as `ArgumentError`).
- Nothing leaks: a timer is cancelled and the caller's signal loses its listener when a run ends; a cancelled subscription cancels its source once and closes once.
- The plain path pays nothing: without a signal or timeout no cancellation object is made, an unguarded field keeps its lane, and a resolver that never reads `selection` builds no selection.
- Core changes go in their own commit (Task 1). New codes go into `DiagnosticCode` in id order, with a doc comment.

## Review Focus

1. A cancelled or timed-out run completes promptly with `data: null` and one `GQL350` / `GQL351`, drops late results, leaves no timer and no listener; a synchronous query with a timeout stays synchronous. Task 4 (`execute_cancellation_test.dart`).
2. A subscription cancelled while its source future is pending is a `SubscriptionRejected` and never listens to the late stream. Task 6 (`subscription_pending_source_test.dart`).
3. The authorizer runs after argument coercion and before middleware for every lane, a deny propagates on a non-null field, an authorizer exception is masked and seen by `onError`, introspection is never guarded. Task 3 (`authorization_test.dart`).
4. The fingerprint ignores aliases and argument key order and is built without recursion over 1000 levels. Task 2 (`selection_fingerprint_test.dart`).

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql_server/doc/lookahead.md` | Create, then Modify | 2, 9, 10, 17 |
| `packages/typed_graphql_server/lib/src/lookahead/argument_text.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart` | Create, then Modify | 2, 10 |
| `packages/typed_graphql_server/lib/src/lookahead/column_whitelist.dart` | Create, then Delete | 2, 17 |
| `packages/typed_graphql_server/lib/src/lookahead/field_selection.dart` | Create, then Modify | 2, 10 |
| `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart` | Create, then Modify | 2, 3, 10 |
| `packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart` | Create, then Modify | 2, 10 |
| `packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart` | Create, then Modify | 2, 10 |
| `packages/typed_graphql_server/test/lookahead/column_whitelist_test.dart` | Create, then Delete | 2, 17 |
| `packages/typed_graphql_server/test/lookahead/field_selection_test.dart` | Create, then Modify | 2, 10 |
| `packages/typed_graphql_server/test/lookahead/look_ahead_fixture.dart` | Create | 2 |
| `packages/typed_graphql_server/test/lookahead/selection_fingerprint_test.dart` | Create | 2 |
| `packages/typed_graphql_server/doc/authorization.md` | Create, then Modify | 3, 9, 12, 13 |
| `packages/typed_graphql_server/lib/src/authorization/authorization.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/authorization/authorization_coverage.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/authorization/authorization_decision.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/authorization/authorizer.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/authorization/field_access.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/builder/authorization_applier.dart` | Create, then Modify | 3, 13 |
| `packages/typed_graphql_server/lib/src/builder/field_guard.dart` | Create | 3 |
| `packages/typed_graphql_server/test/authorization/authorization_fixture.dart` | Create, then Modify | 3, 13 |
| `packages/typed_graphql_server/test/authorization/authorization_test.dart` | Create, then Modify | 3, 13 |
| `packages/typed_graphql_server/doc/cancellation.md` | Create, then Modify | 4, 9, 11 |
| `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart` | Create, then Modify | 4, 11, 15 |
| `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart` | Create, then Modify | 4, 6, 11, 16 |
| `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart` | Create, then Modify | 4, 6, 11 |
| `packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart` | Create, then Modify | 4, 16 |
| `packages/typed_graphql_server/test/cancellation/subscription_cancellation_test.dart` | Create | 4 |
| `packages/typed_graphql_conformance/test/execution/cancellation_bubbling_test.dart` | Create | 5 |
| `packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart` | Create, then Modify | 5, 6 |
| `packages/typed_graphql_conformance/test/execution/cancellation_test.dart` | Create | 5 |
| `packages/typed_graphql_conformance/test/support/cancellation_schema.dart` | Create | 5 |
| `packages/typed_graphql_server/test/cancellation/subscription_pending_source_test.dart` | Create | 6 |
| `packages/typed_graphql_conformance/benchmark/execution_benchmark.dart` | Create | 7 |
| `packages/typed_graphql_conformance/test/benchmark/execution_benchmark_test.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/lookahead/identity_key.dart` | Create | 10 |
| `packages/typed_graphql_server/lib/src/lookahead/look_ahead_budget.dart` | Create | 10 |
| `packages/typed_graphql_server/lib/src/lookahead/merge_key.dart` | Create | 10 |
| `packages/typed_graphql_server/test/lookahead/bounds_fixture.dart` | Create | 10 |
| `packages/typed_graphql_server/test/lookahead/bounds_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/cancellation/subscription_release_test.dart` | Create | 11 |
| `packages/typed_graphql_server/test/coercion/frozen_arguments_test.dart` | Create | 14 |
| `packages/typed_graphql_server/lib/src/lookahead/column_allowlist.dart` | Create | 17 |
| `packages/typed_graphql_server/test/lookahead/column_allowlist_test.dart` | Create | 17 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1, 19 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 2, 3, 4, 10, 11, 12, 13, 14, 15, 16, 17 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 2, 3, 4 |
| `packages/typed_graphql_server/lib/src/execution/field_execution.dart` | Modify | 2, 4, 10 |
| `packages/typed_graphql_server/lib/src/execution/field_info.dart` | Modify | 2, 4, 10 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 2, 3, 4, 12, 17 |
| `packages/typed_graphql_server/lib/src/builder/build_options.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/builder/field_def.dart` | Modify | 3, 15 |
| `packages/typed_graphql_server/lib/src/builder/field_stub.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/builder/object_options.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/execution/executable_schema.dart` | Modify | 3, 15 |
| `packages/typed_graphql_server/lib/src/execution/execution_options.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/execution/execution_run.dart` | Modify | 4, 10, 16 |
| `packages/typed_graphql_server/lib/src/execution/operation_execution.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/execution/operation_preparation.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart` | Modify | 4, 6 |
| `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart` | Modify | 4, 11 |
| `packages/typed_graphql_conformance/mapping/execution.csv` | Modify | 5, 6 |
| `packages/typed_graphql_conformance/test/mapping_test.dart` | Modify | 5 |
| `packages/typed_graphql_conformance/test/support/execution_port.dart` | Modify | 5 |
| `docs/superpowers/specs/2026-10-15-m5-execution-design.md` | Modify | 6, 8, 11, 12, 13, 14, 16, 17, 18, 20 |
| `packages/typed_graphql_conformance/README.md` | Modify | 7 |
| `CLAUDE.md` | Modify | 9, 10, 11, 12, 20 |
| `README.md` | Modify | 9 |
| `docs/discovery.md` | Modify | 9 |
| `docs/superpowers/HANDOFF.md` | Modify | 9, 17, 18 |
| `llms.txt` | Modify | 9 |
| `packages/typed_graphql_server/README.md` | Modify | 9, 17 |
| `packages/typed_graphql_server/lib/src/execution/execution_limits.dart` | Modify | 10 |
| `packages/typed_graphql_server/doc/subscriptions.md` | Modify | 13 |
| `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart` | Modify | 14 |
| `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart` | Modify | 14 |
| `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart` | Modify | 14 |
| `packages/typed_graphql_server/lib/src/coercion/value_coercion.dart` | Modify | 14 |
| `docs/requirements.md` | Modify | 17 |
| `docs/superpowers/specs/2026-10-13-typed-graphql-design.md` | Modify | 17 |
| `docs/superpowers/plans/2026-10-15-m5a-typed-builder.md` | Modify | 18 |
| `docs/superpowers/plans/2026-10-15-m5b-execution-core.md` | Modify | 18 |

## The green check

Every task ends with this check. "Green" means each command exits 0:

```sh
ulimit -v 8000000
timeout 300 dart pub get
timeout 300 dart format --output=none --set-exit-if-changed packages test
timeout 600 dart analyze --fatal-infos
timeout 600 dart test
for p in packages/*/; do (cd "$p" && timeout 900 dart test) || exit 1; done
```

Run a new test file alone first under the same limits. The documentation
suites run each guide program as a `dart` process. If a run is killed
(exit 137) or times out (exit 124), find the cause before going on. Run one
Dart process at a time.

After the last task, also run the server suite on every compiler:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
(cd packages/typed_graphql_server && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js)
(cd packages/typed_graphql_server && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm)
```

---

### Task 1: The M5d diagnostic codes (core)

Add `GQL304` (`missingAuthorizer`), `GQL350` (`executionCancelled`), `GQL351` (`executionTimedOut`) and `GQL352` (`notAuthorized`) to the catalog in id order, with doc comments, and a core CHANGELOG line.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/CHANGELOG.md`

**Interfaces:**
- Consumes: the core as left by M5c.
- Produces:
- Diagnostic codes: `GQL304` (`missingAuthorizer`), `GQL350` (`executionCancelled`), `GQL351` (`executionTimedOut`), `GQL352` (`notAuthorized`).

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -531,6 +531,10 @@ enum DiagnosticCode(
   /// of the subscription root type without one.
   misplacedSubscriptionField('GQL303'),
 
+  /// `GQL304`: reported when the executable schema builder finds fields
+  /// guarded by an authorization rule and no `Authorizer` to check them.
+  missingAuthorizer('GQL304'),
+
   /// `GQL310`: reported when a variable value is invalid, or a required
   /// variable is missing, as `ExecutableSchema.execute` coerces the variable
   /// values. It is a `GraphQLError`'s `extensions.code` in a
@@ -633,6 +637,24 @@ enum DiagnosticCode(
   /// error; the response stream ends with it.
   subscriptionSourceFailed('GQL340'),
 
+  /// `GQL350`: reported when the caller's cancel signal fired before the
+  /// execution finished; the response has no data. It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute` or the last result of a subscription.
+  executionCancelled('GQL350'),
+
+  /// `GQL351`: reported when the execution's timeout elapsed before it
+  /// finished; the response has no data. It is a `GraphQLError`'s
+  /// `extensions.code` in a response of `ExecutableSchema.execute` or the
+  /// last result of a subscription.
+  executionTimedOut('GQL351'),
+
+  /// `GQL352`: reported when the `Authorizer` denied access to a field; the
+  /// field is an error and null propagates as for any field error. It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  notAuthorized('GQL352'),
+
   /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
   /// the YAML parser's.
   configSyntax('GQL500'),
```

- [ ] **Step 2: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -270,6 +270,7 @@
 - `Suggestions` is exported: graphql-js's "Did you mean" text for messages that suggest a name.
 - `GQL310`-`GQL337`: the diagnostics of execution (variable and argument coercion, operation selection, completion errors, limits); they are the `extensions.code` of the errors `ExecutableSchema.execute` returns.
 - `GQL303`, `GQL324`, `GQL338`, `GQL340`: the diagnostics of introspection and subscriptions (misplaced or missing subscription source, `subscribe` with a query or mutation, introspection not allowed, failed subscription source).
+- `GQL304`, `GQL350`, `GQL351`, `GQL352`: the diagnostics of authorization and cancellation (guarded fields without an authorizer, execution cancelled, execution timed out, field not authorized).
 - The messages of the built-in scalar codecs print an offending list or object as graphql-js does (`[1, 2, 3]`, `{ a: 1 }`, at most ten items, nested containers cut at depth two), not as compact JSON.
 - The catalog has the code generator's codes `GQL500`-`GQL506`: configuration
   syntax and content, schema input, anonymous operations, unsupported
```

- [ ] **Step 3: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
git commit -q -m "feat(typed_graphql): add the M5d diagnostic codes" \
  -m "GQL304 missingAuthorizer, GQL350 executionCancelled, GQL351 executionTimedOut and GQL352 notAuthorized, for the server's authorization and cancellation (M5 spec section 15)." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Look-ahead

Add `lib/src/lookahead/` (`FieldSelection`, `SelectedField`, `ColumnWhitelist`, with the internal `SelectionNodes`, `SelectionFingerprint`, `CanonicalJson` and `ArgumentText`), the lazy `FieldInfo.selection`, the `lookahead` category and a first Look-ahead guide.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/lookahead/argument_text.dart`, `packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart`, `packages/typed_graphql_server/lib/src/lookahead/column_whitelist.dart`, `packages/typed_graphql_server/lib/src/lookahead/field_selection.dart`, `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart`, `packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart`, `packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart`
- Modify: `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/field_info.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/dartdoc_options.yaml`
- Create (documents): `packages/typed_graphql_server/doc/lookahead.md`
- Test: `packages/typed_graphql_server/test/lookahead/column_whitelist_test.dart`, `packages/typed_graphql_server/test/lookahead/field_selection_test.dart`, `packages/typed_graphql_server/test/lookahead/look_ahead_fixture.dart`, `packages/typed_graphql_server/test/lookahead/selection_fingerprint_test.dart`

**Interfaces:**
- Consumes: the plan and `FieldExecution` of M5b.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// lookahead/argument_text.dart
final class ArgumentText
  String of(Arguments arguments)

// lookahead/canonical_json.dart
final class CanonicalJson
  String write(JsonValue value)

// lookahead/column_whitelist.dart
final class ColumnWhitelist
  ColumnWhitelist(…)
  List<String> columnsFor(FieldSelection selection)

// lookahead/field_selection.dart
final class FieldSelection
  FieldSelection forType(String typeName)
  bool has(String path)
  List<SelectedField> fieldsNamed(String name)
  String get fingerprint

// lookahead/selected_field.dart
final class SelectedField
  SelectedField(…)
  String get name
  String get responseKey
  String? get alias

// lookahead/selection_fingerprint.dart
final class SelectionFingerprint
  String of(FieldSelection root)
final class _Level
  SelectedField? get next

// lookahead/selection_nodes.dart
final class SelectionNodes
  List<PlanNode> of(List<FieldPlan> plans, String? typeName)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/lookahead/column_whitelist_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();
  final whitelist = ColumnWhitelist(
    {'name': 'full_name', 'friend': 'friend_id', 'alias': 'full_name'},
    always: ['id'],
  );

  test('gives the sorted columns of the fields the map knows', () async {
    final selection = await f.selection(
      'user',
      '{ user { friend { name } name } }',
    );
    expect(whitelist.columnsFor(selection), ['friend_id', 'full_name', 'id']);
  });

  test('ignores the fields the map does not know', () async {
    final selection = await f.selection('user', '{ user { posts { title } } }');
    expect(whitelist.columnsFor(selection), ['id']);
  });

  test('lists a column once when two fields share it', () async {
    final both = ColumnWhitelist({'name': 'n', 'friend': 'n'});
    final selection = await f.selection(
      'user',
      '{ user { name friend { name } } }',
    );
    expect(both.columnsFor(selection), ['n']);
  });

  test('adds the always columns to an empty selection', () {
    expect(whitelist.columnsFor(FieldSelection.empty), ['id']);
  });

  test('reads names, so an alias does not hide a column', () async {
    final selection = await f.selection('user', '{ user { shown: name } }');
    expect(whitelist.columnsFor(selection), ['full_name', 'id']);
  });
}
```

Create `packages/typed_graphql_server/test/lookahead/field_selection_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();
  List<String> names(FieldSelection selection) => [
    for (final field in selection.fields) field.name,
  ];
  List<String> keys(FieldSelection selection) => [
    for (final field in selection.fields) field.responseKey,
  ];

  group('fields', () {
    test('flatten fragments and merge repeated fields', () async {
      final selection = await f.selection('user', '''
        { user { ...Parts name ... on User { friend { name } } } }
        fragment Parts on User { name posts { title } }
      ''');
      expect(names(selection), ['name', 'posts', 'friend']);
    });

    test('leave out a field that @skip removes', () async {
      final selection = await f.selection(
        'user',
        r'query($s: Boolean!) { user { name posts @skip(if: $s) { title } } }',
        variables: JsonObject({'s': const JsonBool(true)}),
      );
      expect(names(selection), ['name']);
    });

    test('keep a field that @include keeps', () async {
      const text =
          r'query($i: Boolean!) { user { name posts @include(if: $i) { title } } }';
      final kept = await f.selection(
        'user',
        text,
        variables: JsonObject({'i': const JsonBool(true)}),
      );
      final dropped = await f.selection(
        'user',
        text,
        variables: JsonObject({'i': const JsonBool(false)}),
      );
      expect(
        [names(kept), names(dropped)],
        [
          ['name', 'posts'],
          ['name'],
        ],
      );
    });

    test('keep each alias as its own field', () async {
      final selection = await f.selection(
        'user',
        '{ user { first: name second: name name } }',
      );
      expect(keys(selection), ['first', 'second', 'name']);
    });

    test('tell the alias from the name', () async {
      final selection = await f.selection(
        'user',
        '{ user { shown: name name } }',
      );
      expect(
        [for (final field in selection.fields) field.alias],
        [
          'shown',
          null,
        ],
      );
    });

    test('hide __typename', () async {
      final selection = await f.selection(
        'user',
        '{ user { __typename name } }',
      );
      expect(names(selection), ['name']);
    });

    test('are empty for a field of a leaf type', () async {
      final selection = await f.selection('plain', '{ plain }');
      expect(selection.fields, isEmpty);
    });

    test('collect what every possible type of an interface selects', () async {
      final selection = await f.selection('pet', '''
        { pet { name ... on Dog { barks } ... on Cat { meows } } }
      ''');
      expect(names(selection), ['name', 'barks', 'meows']);
    });

    test('collect what every member of a union selects', () async {
      final selection = await f.selection('found', '''
        { found { ... on Dog { barks } ... on Cat { meows } } }
      ''');
      expect(names(selection), ['barks', 'meows']);
    });
  });

  group('forType', () {
    const text = '''
      { pet { name ... on Dog { barks } ... on Cat { meows } } }
    ''';

    test('gives the view of one object type', () async {
      final selection = await f.selection('pet', text);
      expect(
        [names(selection.forType('Dog')), names(selection.forType('Cat'))],
        [
          ['name', 'barks'],
          ['name', 'meows'],
        ],
      );
    });

    test('is empty for an unknown type name', () async {
      final selection = await f.selection('pet', text);
      expect(selection.forType('Nope').fields, isEmpty);
    });

    test('is empty for a type the field cannot have', () async {
      final selection = await f.selection('pet', text);
      expect(selection.forType('User').fields, isEmpty);
    });

    test('is empty for an interface name, which is no object type', () async {
      final selection = await f.selection('pet', text);
      expect(selection.forType('Pet').fields, isEmpty);
    });

    test('applies to a union', () async {
      final selection = await f.selection('found', '''
        { found { ... on Dog { barks } ... on Cat { meows } } }
      ''');
      expect(names(selection.forType('Cat')), ['meows']);
    });
  });

  group('has', () {
    const text = '{ user { name posts { title comments { body } } } }';

    test('finds a nested path', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('posts.comments.body'), isTrue);
    });

    test('finds a single name', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('name'), isTrue);
    });

    test('misses a field the request did not select', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('posts.author'), isFalse);
    });

    test('misses a path that goes through a leaf', () async {
      final selection = await f.selection('user', text);
      expect(selection.has('name.first'), isFalse);
    });

    test('reads names, not aliases', () async {
      final selection = await f.selection('user', '{ user { a: name } }');
      expect([selection.has('name'), selection.has('a')], [true, false]);
    });

    test('follows every occurrence of a name', () async {
      final selection = await f.selection('user', '''
        { user { a: posts { title } b: posts { comments { body } } } }
      ''');
      expect(selection.has('posts.comments.body'), isTrue);
    });

    for (final path in ['', 'posts..title', '.posts', 'posts.']) {
      test('throws on the empty segment of "$path"', () async {
        final selection = await f.selection('user', text);
        expect(() => selection.has(path), throwsArgumentError);
      });
    }
  });

  group('fieldsNamed', () {
    test('lists every occurrence, aliases apart', () async {
      final selection = await f.selection(
        'user',
        '{ user { a: name name friend { name } } }',
      );
      expect(
        [for (final field in selection.fieldsNamed('name')) field.responseKey],
        ['a', 'name'],
      );
    });

    test('is empty for a name not selected', () async {
      final selection = await f.selection('user', '{ user { name } }');
      expect(selection.fieldsNamed('posts'), isEmpty);
    });
  });

  group('arguments', () {
    test('are the coerced values with defaults and enums', () async {
      final selection = await f.selection(
        'user',
        '{ user { posts(first: 3, order: desc) { title } } }',
      );
      expect(selection.fields.single.arguments.coerced, {
        'first': 3,
        'order': Sorting.desc,
      });
    });

    test('substitute the variables of the request', () async {
      final selection = await f.selection(
        'user',
        r'query($n: Int) { user { posts(first: $n) { title } } }',
        variables: JsonObject({'n': JsonNumber(5)}),
      );
      expect(selection.fields.single.arguments.coerced['first'], 5);
    });

    test('read as absent when the value fails coercion', () async {
      final selection = await f.selection(
        'user',
        '{ user { posts(first: "many") { title } } }',
      );
      expect(selection.fields.single.arguments.coerced, isEmpty);
    });

    test('belong to the field, with its own sub-selection', () async {
      final selection = await f.selection(
        'user',
        '{ user { posts(first: 1) { title comments { body } } } }',
      );
      expect(names(selection.fields.single.selection), ['title', 'comments']);
    });
  });

  group('FieldInfo.selection', () {
    test('is the same object each time it is read', () async {
      final info = await f.infoOf('user', '{ user { name } }');
      expect(identical(info.selection, info.selection), isTrue);
    });

    test('is not built until it is read', () async {
      final info = await f.infoOf('user', '{ user { name } }');
      var reads = 0;
      final copy = FieldInfo(
        fieldName: info.fieldName,
        parentType: info.parentType,
        returnType: info.returnType,
        path: info.path,
        fieldNodes: info.fieldNodes,
        operation: info.operation,
        variables: info.variables,
        schema: info.schema,
        selectionReader: () {
          reads++;
          return FieldSelection.empty;
        },
      );
      final before = reads;
      final same = identical(copy.selection, copy.selection);
      expect([before, reads, same], [0, 1, true]);
    });

    test('is empty when the call was not made by an execution', () async {
      final info = await f.infoOf('user', '{ user { name } }');
      final copy = FieldInfo(
        fieldName: info.fieldName,
        parentType: info.parentType,
        returnType: info.returnType,
        path: info.path,
        fieldNodes: info.fieldNodes,
        operation: info.operation,
        variables: info.variables,
        schema: info.schema,
      );
      expect(copy.selection.fields, isEmpty);
    });
  });
}
```

Create `packages/typed_graphql_server/test/lookahead/look_ahead_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Sorting { asc, desc }

sealed class Animal {
  const Animal();
}

final class Dog extends Animal {
  const Dog();
}

final class Cat extends Animal {
  const Cat();
}

final class Person {
  const Person();
}

/// A schema whose root fields keep the `FieldInfo` they are called with, so
/// a test reads the look-ahead of the field it ran.
final class LookAheadFixture {
  LookAheadFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final sorting = b.enumType<Sorting>('Sorting', Sorting.values);
    final comment = b.object<Object?>(
      'Comment',
      fields: (t) => [t.field('body', b.string).pure((_) => 'b')],
    );
    final post = b.object<Object?>(
      'Post',
      fields: (t) => [
        t.field('title', b.string).pure((_) => 't'),
        t.field('comments', b.list(comment)).pure((_) => const []),
      ],
    );
    late final ObjectTypeDef<Person> person;
    person = b.object<Person>(
      'User',
      fields: (t) => [
        t.field('name', b.string).pure((_) => 'n'),
        t
            .field(
              'posts',
              b.list(post),
              args: [
                Arg('first', b.int.nullable),
                Arg('order', sorting.nullable),
              ],
            )
            .resolve((parent, args, context, info) => const []),
        t.field('friend', person.nullable).pure((_) => null),
      ],
    );
    final pet = b.interface<Animal>(
      'Pet',
      fields: (t) => [t.field('name', b.string).declareOnly()],
    );
    final dog = b.object<Dog>(
      'Dog',
      interfaces: [pet],
      fields: (t) => [
        t.field('name', b.string).pure((_) => 'rex'),
        t.field('barks', b.boolean).pure((_) => true),
      ],
    );
    final cat = b.object<Cat>(
      'Cat',
      interfaces: [pet],
      fields: (t) => [
        t.field('name', b.string).pure((_) => 'tom'),
        t.field('meows', b.boolean).pure((_) => true),
      ],
    );
    final found = b.union<Animal>('Found', members: [dog, cat]);
    late final ObjectTypeDef<Object?> deep;
    deep = b.object<Object?>(
      'Deep',
      fields: (t) => [
        t.field('deep', deep.nullable).pure((_) => null),
        t.field('leaf', b.string).pure((_) => 'l'),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field(
              'user',
              person.nullable,
              args: [
                Arg('id', b.int.nullable),
                Arg('tags', b.inputList(b.string).nullable),
              ],
            )
            .resolve(
              (parent, args, context, info) =>
                  _keep('user', info, const Person()),
            ),
        t
            .field('pet', pet)
            .resolve(
              (parent, args, context, info) => _keep('pet', info, const Dog()),
            ),
        t
            .field('found', found)
            .resolve(
              (parent, args, context, info) =>
                  _keep('found', info, const Cat()),
            ),
        t
            .field('deep', deep.nullable)
            .resolve(
              (parent, args, context, info) => _keep('deep', info, 'deep'),
            ),
        t.field('plain', b.string).resolve((p, a, c, info) {
          _infos['plain'] = info;
          return 'p';
        }),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Object?> built;
  final Map<String, FieldInfo> _infos = {};

  T _keep<T>(String field, FieldInfo info, T value) {
    _infos[field] = info;
    return value;
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  /// Runs [text] and returns the `FieldInfo` of the root field [field].
  Future<FieldInfo> infoOf(
    String field,
    String text, {
    JsonObject? variables,
  }) async {
    _infos.clear();
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, parse(text)),
      context: null,
      variables: variables,
    );
    final info = _infos[field];
    if (info == null) {
      throw StateError('"$field" did not run: ${payload.toJson()}');
    }
    return info;
  }

  /// The selection under the root field [field] of [text].
  Future<FieldSelection> selection(
    String field,
    String text, {
    JsonObject? variables,
  }) async => (await infoOf(field, text, variables: variables)).selection;
}
```

Create `packages/typed_graphql_server/test/lookahead/selection_fingerprint_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/lookahead/canonical_json.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();

  Future<String> fingerprint(
    String selectionText, {
    JsonObject? variables,
    String header = '',
  }) async => (await f.selection(
    'user',
    '$header{ user $selectionText }',
    variables: variables,
  )).fingerprint;

  group('fingerprint', () {
    test('writes names, arguments and children canonically', () async {
      expect(
        await fingerprint('{ name posts(first: 2, order: asc) { title } }'),
        'name,posts(first:2,order:"asc"){title}',
      );
    });

    test('ignores the order of fields', () async {
      expect(
        await fingerprint('{ posts { title } name }'),
        await fingerprint('{ name posts { title } }'),
      );
    });

    test('ignores the order of arguments', () async {
      expect(
        await fingerprint('{ posts(first: 1, order: asc) { title } }'),
        await fingerprint('{ posts(order: asc, first: 1) { title } }'),
      );
    });

    test('ignores aliases', () async {
      expect(
        await fingerprint('{ posts { title } }'),
        await fingerprint('{ list: posts { heading: title } }'),
      );
    });

    test('resolves variables to their values', () async {
      expect(
        await fingerprint(
          r'{ posts(first: $n) { title } }',
          header: r'query($n: Int) ',
          variables: JsonObject({'n': JsonNumber(4)}),
        ),
        await fingerprint('{ posts(first: 4) { title } }'),
      );
    });

    test('flattens fragments', () async {
      final selection = await f.selection('user', '''
        { user { ...Parts } }
        fragment Parts on User { name posts { title } }
      ''');
      expect(
        selection.fingerprint,
        await fingerprint('{ name posts { title } }'),
      );
    });

    test('differs when an argument value differs', () async {
      expect(
        await fingerprint('{ posts(first: 1) { title } }'),
        isNot(await fingerprint('{ posts(first: 2) { title } }')),
      );
    });

    test('differs when a field is added', () async {
      expect(
        await fingerprint('{ name }'),
        isNot(await fingerprint('{ name posts { title } }')),
      );
    });

    test('differs when a field sits at another level', () async {
      expect(
        await fingerprint('{ posts { title } name }'),
        isNot(await fingerprint('{ posts { title name } }')),
      );
    });

    test('differs when a skipped field comes back', () async {
      const header = r'query($s: Boolean!) ';
      const body = r'{ name posts @skip(if: $s) { title } }';
      expect(
        await fingerprint(
          body,
          header: header,
          variables: JsonObject({'s': const JsonBool(true)}),
        ),
        isNot(
          await fingerprint(
            body,
            header: header,
            variables: JsonObject({'s': const JsonBool(false)}),
          ),
        ),
      );
    });

    test('is empty for a selection with no fields', () async {
      expect(FieldSelection.empty.fingerprint, '');
    });

    test('of a one-thousand-level selection needs no recursion', () async {
      const depth = 1000;
      final text = '{ deep ${'{ deep ' * (depth - 1)}{ leaf }${' }' * depth}';
      final selection = await f.selection('deep', text);
      expect(
        selection.fingerprint,
        '${'deep{' * (depth - 1)}leaf${'}' * (depth - 1)}',
      );
    });

    test('lets has walk a one-thousand-level path', () async {
      const depth = 1000;
      final text = '{ deep ${'{ deep ' * (depth - 1)}{ leaf }${' }' * depth}';
      final selection = await f.selection('deep', text);
      expect(selection.has('${'deep.' * (depth - 1)}leaf'), isTrue);
    });
  });

  group('CanonicalJson', () {
    test('sorts the keys of objects at every level', () {
      final value = JsonObject({
        'b': JsonNumber(1),
        'a': JsonObject({'y': const JsonNull(), 'x': const JsonBool(true)}),
      });
      expect(
        const CanonicalJson().write(value),
        '{"a":{"x":true,"y":null},"b":1}',
      );
    });

    test('keeps the order of array items and quotes strings', () {
      final value = JsonArray([const JsonString('z"'), const JsonString('a')]);
      expect(const CanonicalJson().write(value), r'["z\"","a"]');
    });

    test('writes a value nested one thousand levels deep', () {
      JsonValue value = JsonNumber(0);
      for (var i = 0; i < 1000; i++) {
        value = JsonArray([value]);
      }
      expect(const CanonicalJson().write(value), '${'[' * 1000}0${']' * 1000}');
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/lookahead/column_whitelist_test.dart test/lookahead/field_selection_test.dart test/lookahead/selection_fingerprint_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/lookahead/argument_text.dart`:

```dart
import '../builder/arg.dart';
import '../builder/arguments.dart';
import 'canonical_json.dart';

/// Writes the coerced arguments of a field call as one canonical text, for
/// a fingerprint: arguments by name, values as [CanonicalJson], so the order
/// the request wrote them in does not show.
final class ArgumentText {
  /// Creates the writer.
  const ArgumentText();

  /// `(a:1,b:"x")` for the arguments the request gave (defaults included),
  /// and an empty text when there are none.
  String of(Arguments arguments) {
    final parts = <String>[];
    for (final arg in arguments.declared) {
      if (!arguments.coerced.containsKey(arg.name)) {
        continue;
      }
      parts.add('${arg.name}:${_json(arg, arguments.coerced[arg.name])}');
    }
    if (parts.isEmpty) {
      return '';
    }
    parts.sort();
    return '(${parts.join(',')})';
  }

  // A value the argument's type cannot write (a codec refusing it) is
  // replaced by a marker: a fingerprint is a key, not a response.
  String _json(Arg<Object?> arg, Object? coerced) {
    try {
      return const CanonicalJson().write(
        arg.type.jsonOf(arg.type.adapt(coerced)),
      );
    } on Object {
      return '?';
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Writes a [JsonValue] as compact JSON with the keys of every object in
/// sorted order, so equal values give equal text whatever order they were
/// built in. It walks with an explicit stack: a value nested a thousand
/// levels deep costs no call depth.
final class CanonicalJson {
  /// Creates the writer.
  const CanonicalJson();

  /// The canonical text of [value].
  String write(JsonValue value) {
    final out = StringBuffer();
    final pending = <Object>[value];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final String text:
          out.write(text);
        case JsonArray(:final items):
          _push(pending, ['[', ..._separated(items), ']']);
        case JsonObject(:final fields):
          final keys = fields.keys.toList()..sort();
          _push(pending, [
            '{',
            ..._separated([
              for (final key in keys) ...['${JsonString(key)}:', fields[key]!],
            ], pairs: true),
            '}',
          ]);
        case final JsonValue leaf:
          out.write(leaf);
        case final Object other:
          throw StateError('Unexpected canonical JSON part $other.');
      }
    }
    return out.toString();
  }

  // Parts in reading order; pushed reversed so they pop in that order.
  void _push(List<Object> pending, List<Object> parts) {
    for (var i = parts.length - 1; i >= 0; i--) {
      pending.add(parts[i]);
    }
  }

  // Commas between the items, or between the key/value pairs.
  List<Object> _separated(List<Object> items, {bool pairs = false}) {
    final step = pairs ? 2 : 1;
    return [
      for (var i = 0; i < items.length; i += step) ...[
        if (i > 0) ',',
        for (var j = i; j < i + step; j++) items[j],
      ],
    ];
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/column_whitelist.dart`:

```dart
import 'field_selection.dart';

/// Maps GraphQL field names to database columns, so a resolver selects only
/// the columns the request needs (R4.18). It reads a [FieldSelection]; it
/// preloads nothing and writes no SQL.
///
/// {@category lookahead}
final class ColumnWhitelist {
  /// Maps each field name in [columns] to its column; the [always] columns
  /// are in every answer (a key, say).
  ColumnWhitelist(Map<String, String> columns, {List<String> always = const []})
    : _columns = Map.unmodifiable(columns),
      _always = List.unmodifiable(always);

  final Map<String, String> _columns;
  final List<String> _always;

  /// The columns of the fields [selection] selects at its own level that the
  /// map knows, plus the always ones, sorted and without repeats. Fields the
  /// map does not know are ignored.
  List<String> columnsFor(FieldSelection selection) {
    final columns = <String>{..._always};
    for (final field in selection.fields) {
      if (_columns[field.name] case final column?) {
        columns.add(column);
      }
    }
    return columns.toList()..sort();
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/field_selection.dart`:

```dart
import 'package:meta/meta.dart';

import '../builder/field_def.dart';
import '../plan/field_plan.dart';
import 'selected_field.dart';
import 'selection_fingerprint.dart';
import 'selection_nodes.dart';

/// The fields the request selected under a field, as the resolver of that
/// field sees them (R4.18): fragments flattened, `@skip` and `@include`
/// applied with the request's variables, `__typename` and the other meta
/// fields left out.
///
/// It is a view of the operation plan: nothing is collected until a member
/// is read, and a selection never changes.
///
/// {@category lookahead}
final class FieldSelection {
  /// Creates the selection under [plans], the plans of one response key, read
  /// with the coerced [variables] and the field tables [definitions]. Only the
  /// object type called [typeName] when it is given.
  @internal
  FieldSelection.under(
    List<FieldPlan> plans,
    Map<String, Object?> variables,
    Map<String, Map<String, FieldDef<Object?, Object?>>> definitions, [
    String? typeName,
  ]) : _plans = plans,
       _variables = variables,
       _definitions = definitions,
       _typeName = typeName;

  /// A selection with no fields: what a field of a leaf type, or a call
  /// made outside an execution, has.
  static final FieldSelection empty = FieldSelection.under(
    const [],
    const {},
    const {},
  );

  final List<FieldPlan> _plans;
  final Map<String, Object?> _variables;
  final Map<String, Map<String, FieldDef<Object?, Object?>>> _definitions;
  final String? _typeName;

  /// The selected fields in collection order, merged by response key. For
  /// a field of an abstract type these are the fields every possible type
  /// collects, in possible-type order; an alias keeps each occurrence apart.
  // `late`: collected on first read, so an unread selection costs nothing.
  late final List<SelectedField> fields = _collect();

  /// The selection restricted to the object type called [typeName].
  ///
  /// An unknown name, or a type the field's value cannot have, gives an
  /// empty selection; nothing throws.
  FieldSelection forType(String typeName) =>
      FieldSelection.under(_plans, _variables, _definitions, typeName);

  /// Whether the request selected the path [path] of field names (not
  /// aliases) joined by dots, as in `posts.comments.author`.
  ///
  /// An empty path or an empty segment is an [ArgumentError].
  bool has(String path) {
    var level = <FieldSelection>[this];
    for (final segment in path.split('.')) {
      if (segment.isEmpty) {
        throw ArgumentError.value(path, 'path', 'has an empty segment');
      }
      level = [
        for (final selection in level)
          for (final field in selection.fields)
            if (field.name == segment) field.selection,
      ];
    }
    return level.isNotEmpty;
  }

  /// Every selected field called [name] in the schema, whatever its alias.
  List<SelectedField> fieldsNamed(String name) => [
    for (final field in fields)
      if (field.name == name) field,
  ];

  /// A canonical text of the selection, equal for two selections that ask
  /// for the same fields with the same arguments: field names (not aliases)
  /// and arguments sorted, argument values as JSON with sorted keys and the
  /// variables substituted. Meant as a cache or DataLoader key.
  String get fingerprint => const SelectionFingerprint().of(this);

  List<SelectedField> _collect() {
    final byKey = <String, List<FieldPlan>>{};
    for (final node in const SelectionNodes().of(_plans, _typeName)) {
      for (final plan in node.fields) {
        if (plan.fieldName.startsWith('__')) {
          continue;
        }
        (byKey[plan.responseKey] ??= []).add(plan);
      }
    }
    return List.unmodifiable([
      for (final plans in byKey.values)
        SelectedField(plans, _variables, _definitions),
    ]);
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart`:

```dart
import 'package:meta/meta.dart';

import '../builder/arguments.dart';
import '../builder/field_def.dart';
import '../coercion/coercion_result.dart';
import '../plan/field_plan.dart';
import 'field_selection.dart';

/// One field of a [FieldSelection]: what the request asked for under one
/// response key.
///
/// {@category lookahead}
final class SelectedField {
  /// Creates the field of [plans], the plans of one response key (one per
  /// object type that collected it), read with the coerced [variables] and
  /// the field tables [definitions].
  @internal
  SelectedField(
    List<FieldPlan> plans,
    Map<String, Object?> variables,
    Map<String, Map<String, FieldDef<Object?, Object?>>> definitions,
  ) : _plans = plans,
      _variables = variables,
      _definitions = definitions;

  final List<FieldPlan> _plans;
  final Map<String, Object?> _variables;
  final Map<String, Map<String, FieldDef<Object?, Object?>>> _definitions;

  /// The field's name in the schema, never the alias.
  String get name => _plans.first.fieldName;

  /// The key of the field in the response: the alias, else [name].
  String get responseKey => _plans.first.responseKey;

  /// The alias the request gave, null when it gave none.
  String? get alias => responseKey == name ? null : responseKey;

  /// The field's arguments with the request's variables substituted and the
  /// defaults applied, coerced when first read.
  ///
  /// An argument whose value fails coercion reads as absent: the executor
  /// reports the problem when the field runs, so nothing is lost. Reading
  /// a required argument that way throws, as reading any missing one does.
  // `late`: the arguments are coerced on first read, so a look-ahead that
  // never asks for them does not pay for them.
  late final Arguments arguments = _readArguments();

  /// The sub-selection of the field: empty for a leaf. For a field of an
  /// abstract type it holds the fields every possible type collects.
  // `late` for the same reason: the children are collected on first read.
  late final FieldSelection selection = FieldSelection.under(
    _plans,
    _variables,
    _definitions,
  );

  Arguments _readArguments() {
    final plan = _plans.first;
    final declared =
        _definitions[plan.parentType.name]?[plan.fieldName]?.args ?? const [];
    return switch (plan.argumentsFor(_variables)) {
      CoercionSuccess(:final value) => Arguments(
        declared,
        value as Map<String, Object?>,
      ),
      CoercionFailure() => Arguments(declared, const <String, Object?>{}),
    };
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart`:

```dart
import 'argument_text.dart';
import 'field_selection.dart';
import 'selected_field.dart';

/// Builds the canonical text of a [FieldSelection] with an explicit stack,
/// so a selection a thousand levels deep costs no call depth (R0.3).
final class SelectionFingerprint {
  /// Creates the builder.
  const SelectionFingerprint();

  /// The text of [root]: each field as `name(arguments)` and, when it has a
  /// sub-selection, `{children}`; siblings sorted and joined by commas.
  String of(FieldSelection root) {
    final stack = <_Level>[_Level('', root.fields)];
    while (true) {
      final level = stack.last;
      if (level.next case final field?) {
        final text = '${field.name}${const ArgumentText().of(field.arguments)}';
        final children = field.selection.fields;
        if (children.isEmpty) {
          level.entries.add(text);
        } else {
          stack.add(_Level(text, children));
        }
        continue;
      }
      stack.removeLast();
      final joined = (level.entries..sort()).join(',');
      if (stack.isEmpty) {
        return joined;
      }
      stack.last.entries.add('${level.prefix}{$joined}');
    }
  }
}

// One selection being read: the text of the field that owns it, its fields
// still to read and the entries finished so far.
final class _Level {
  _Level(this.prefix, this._fields);

  final String prefix;
  final List<SelectedField> _fields;
  final List<String> entries = [];
  int _index = 0;

  SelectedField? get next => _index < _fields.length ? _fields[_index++] : null;
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart`:

```dart
import '../plan/field_plan.dart';
import '../plan/plan_node.dart';

/// Finds the plan nodes a field's sub-selection is collected into: one per
/// object type the field's value can have (R4.18).
final class SelectionNodes {
  /// Creates the finder.
  const SelectionNodes();

  /// The nodes of the sub-selections of [plans], in plan order and, within a
  /// plan, in possible-type order; only the object type called [typeName]
  /// when it is given. A field of a leaf type has none.
  List<PlanNode> of(List<FieldPlan> plans, String? typeName) {
    final nodes = <PlanNode>[];
    for (final plan in plans) {
      final declared = plan.field;
      if (declared == null) {
        continue;
      }
      final schema = plan.context.schema;
      final named = schema.namedTypeOf(declared.type);
      if (named == null || !named.isCompositeType) {
        continue;
      }
      for (final type in schema.possibleTypes(named)) {
        if (typeName == null || type.name == typeName) {
          nodes.add(plan.childFor(type));
        }
      }
    }
    return nodes;
  }
}
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,6 +8,7 @@ import '../builder/field_lane.dart';
 import '../coercion/coercion_result.dart';
 import '../introspection/entry_fields.dart';
 import '../introspection/introspection_policy.dart';
+import '../lookahead/field_selection.dart';
 import '../plan/field_plan.dart';
 import 'completion_site.dart';
 import 'execution_run.dart';
@@ -255,6 +256,11 @@ final class FieldExecution {
       variables: _run.rawVariables,
       schema: _run.schema,
       rootValue: _run.options.rootValue,
+      selectionReader: () => FieldSelection.under(
+        [plan],
+        _run.variables,
+        _run.bindings.fields,
+      ),
     );
   }
 }
```

In `packages/typed_graphql_server/lib/src/execution/field_info.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,7 @@
+import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../lookahead/field_selection.dart';
 import 'response_path.dart';
 
 /// What a resolver knows about the call it answers.
@@ -17,6 +19,7 @@ final class FieldInfo {
     required this.variables,
     required this.schema,
     this.rootValue,
+    this.selectionReader,
   });
 
   /// The field's name in the schema.
@@ -47,6 +50,19 @@ final class FieldInfo {
   /// The root value of the execution.
   final Object? rootValue;
 
+  /// Builds [selection] when it is first read; the executor sets it.
+  @internal
+  final FieldSelection Function()? selectionReader;
+
+  /// The fields the request selected under this field (R4.18), for a
+  /// resolver that loads only what is asked for.
+  ///
+  /// Built when first read, so a resolver that never reads it pays nothing
+  /// but the reader's closure; empty for a call made outside an execution.
+  // `late`: the reader runs on first read, not when the call starts.
+  late final FieldSelection selection =
+      selectionReader?.call() ?? FieldSelection.empty;
+
   /// The name of the object type the field is selected on.
   String get parentTypeName => parentType.name;
 }
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,4 +40,7 @@ export 'src/execution/field_site.dart';
 export 'src/execution/graphql_exception.dart';
 export 'src/execution/response_path.dart';
 export 'src/introspection/introspection_policy.dart';
+export 'src/lookahead/column_whitelist.dart';
+export 'src/lookahead/field_selection.dart';
+export 'src/lookahead/selected_field.dart';
 export 'src/subscription/subscription_result.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/lookahead/column_whitelist_test.dart test/lookahead/field_selection_test.dart test/lookahead/selection_fingerprint_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Create `packages/typed_graphql_server/doc/lookahead.md`:

````markdown
# Look-ahead

A resolver can see which fields the request selected under its own field, so
it can load only those: `FieldInfo.selection` is a `FieldSelection`, a view
of the operation plan with fragments flattened, `@skip` and `@include`
applied and `__typename` left out. Nothing is collected until a member is
read.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final user = b.object<Object?>(
    'User',
    fields: (t) => [
      t.field('name', b.string).pure((_) => 'Ada'),
      t.field('email', b.string).pure((_) => 'ada@example.com'),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('me', user).resolve((parent, args, context, info) {
        print(info.selection.has('email'));
        print(info.selection.fingerprint);
        return null;
      }),
    ],
  );
  final schema = b.build(query: query);
  final document = const Parser()
      .parse(Source('{ me { name email } }'))
      .requireDocument();
  schema.execute(
    ValidDocument.assumeValid(schema.schema, document),
    context: null,
  );
}
```

It prints:

```text
true
email,name
```

`fields` lists the `SelectedField`s; `forType(name)` narrows the selection of
an abstract type to one object type (an unknown name gives an empty
selection); `has('posts.comments')` tests a path of field names; `fieldsNamed`
lists every occurrence of a name. `fingerprint` is a canonical text, equal
for two selections that ask for the same fields and arguments, to use as a
cache or DataLoader key. `ColumnWhitelist` turns a selection into the sorted
columns of the fields it knows.
````

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Look-ahead: `FieldInfo.selection` is a `FieldSelection` of the fields the
  request selected under the field (fragments flattened, `@skip` and
  `@include` applied, `__typename` hidden), built when first read.
  `fields`, `forType`, `has('posts.comments')`, `fieldsNamed` and
  `fingerprint` (canonical, for DataLoader keys); `SelectedField` has `name`,
  `alias`, `responseKey`, `arguments` (coerced on first read; an argument that
  fails reads as absent) and its own `selection`. `ColumnWhitelist` maps field
  names to sorted, de-duplicated columns. `isDeferred` arrives with
  incremental delivery.
- The Look-ahead guide and its dartdoc category `lookahead`.
```

In `packages/typed_graphql_server/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,6 +9,9 @@ dartdoc:
     introspection:
       markdown: doc/introspection.md
       displayName: Introspection
+    lookahead:
+      markdown: doc/lookahead.md
+      displayName: Look-ahead
     subscription:
       markdown: doc/subscriptions.md
       displayName: Subscriptions
@@ -16,5 +19,6 @@ dartdoc:
     - builder
     - execution
     - introspection
+    - lookahead
     - subscription
   showUndocumentedCategories: true
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/dartdoc_options.yaml packages/typed_graphql_server/doc/lookahead.md packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/field_info.dart packages/typed_graphql_server/lib/src/lookahead/argument_text.dart packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart packages/typed_graphql_server/lib/src/lookahead/column_whitelist.dart packages/typed_graphql_server/lib/src/lookahead/field_selection.dart packages/typed_graphql_server/lib/src/lookahead/selected_field.dart packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/lookahead/column_whitelist_test.dart packages/typed_graphql_server/test/lookahead/field_selection_test.dart packages/typed_graphql_server/test/lookahead/look_ahead_fixture.dart packages/typed_graphql_server/test/lookahead/selection_fingerprint_test.dart
git commit -q -m "feat(typed_graphql_server): look ahead at the requested fields" \
  -m "FieldInfo.selection is a lazy FieldSelection over the plan: fields, forType, has, fieldsNamed and an explicit-stack fingerprint; SelectedField with lazily coerced arguments; ColumnWhitelist. R4.18." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Authorization

Add `lib/src/authorization/` (`Authorization`, `AuthorizationDecision`, `FieldAccess`, `Authorizer`, `AuthorizationCoverage`, the internal `AuthorizationApplier` and `FieldGuard`), `ObjectOptions.authorization`, `FieldStub.withAuthorization`, `BuildOptions.authorizer`, `GQL304`, `GQL352`, `SelectedField.authorization`, the `authorization` category and a first Authorization guide.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/authorization/authorization.dart`, `packages/typed_graphql_server/lib/src/authorization/authorization_coverage.dart`, `packages/typed_graphql_server/lib/src/authorization/authorization_decision.dart`, `packages/typed_graphql_server/lib/src/authorization/authorizer.dart`, `packages/typed_graphql_server/lib/src/authorization/field_access.dart`, `packages/typed_graphql_server/lib/src/builder/authorization_applier.dart`, `packages/typed_graphql_server/lib/src/builder/field_guard.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/build_options.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, `packages/typed_graphql_server/lib/src/builder/field_def.dart`, `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, `packages/typed_graphql_server/lib/src/builder/object_options.dart`, `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/dartdoc_options.yaml`
- Create (documents): `packages/typed_graphql_server/doc/authorization.md`
- Test: `packages/typed_graphql_server/test/authorization/authorization_fixture.dart`, `packages/typed_graphql_server/test/authorization/authorization_test.dart`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// authorization/authorization.dart
sealed class Authorization
final class PublicAuthorization
final class RequiredAuthorization
  RequiredAuthorization(List<String> requirements)

// authorization/authorization_coverage.dart
final class AuthorizationCoverage
  AuthorizationCoverage(ExecutableSchema<Object?> schema)

// authorization/authorization_decision.dart
sealed class AuthorizationDecision
final class Allow
final class Deny

// authorization/authorizer.dart
abstract interface class Authorizer<C>
  FutureOr<AuthorizationDecision> authorize(FieldAccess<C> access)

// authorization/field_access.dart
final class FieldAccess<C>
  FieldAccess(…)

// builder/authorization_applier.dart
final class AuthorizationApplier<C>
  AuthorizationApplier(this._authorizer)
  SchemaBindings apply(SchemaBindings bindings)

// builder/field_guard.dart
final class FieldGuard<C>
  FieldGuard(this._authorizer, this._requirements)
  FutureOr<T> Function(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/authorization/authorization_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The request's context: the roles of the caller.
final class Caller {
  const Caller([this.roles = const {}]);

  final Set<String> roles;
}

/// Allows a field when the caller has every required role; records the
/// coordinate of each access it is asked about.
class RoleAuthorizer implements Authorizer<Caller> {
  final List<String> calls = [];
  final List<FieldAccess<Caller>> accesses = [];

  @override
  FutureOr<AuthorizationDecision> authorize(FieldAccess<Caller> access) {
    calls.add('${access.info.parentTypeName}.${access.info.fieldName}');
    accesses.add(access);
    return decide(access);
  }

  FutureOr<AuthorizationDecision> decide(FieldAccess<Caller> access) =>
      access.requirements.every(access.context.roles.contains)
      ? const Allow()
      : const Deny();
}

/// Decides after a delay, with a message.
final class SlowAuthorizer extends RoleAuthorizer {
  @override
  FutureOr<AuthorizationDecision> decide(FieldAccess<Caller> access) async {
    await Future<void>.delayed(Duration.zero);
    return access.requirements.every(access.context.roles.contains)
        ? const Allow()
        : const Deny(message: 'Slow no.');
  }
}

/// Throws on every access.
final class ThrowingAuthorizer extends RoleAuthorizer {
  @override
  FutureOr<AuthorizationDecision> decide(FieldAccess<Caller> access) =>
      throw StateError('policy store down');
}

sealed class Entity {
  const Entity();
}

final class Memo extends Entity {
  const Memo();
}

final class Note extends Entity {
  const Note();
}

/// The schema of the authorization tests; the authorizer is a parameter.
final class AuthorizationFixture {
  AuthorizationFixture(this.authorizer) {
    built = _build(authorizer);
  }

  final Authorizer<Caller>? authorizer;
  late final ExecutableSchema<Caller> built;

  /// The builder with the types; `build` is the caller's.
  static ExecutableSchema<Caller> _build(Authorizer<Caller>? authorizer) {
    final b = ExecutableSchemaBuilder<Caller>();
    final name = Arg('name', b.string);
    final account = b.object<Object?>(
      'Account',
      options: ObjectOptions(authorization: Authorization.requires(['owner'])),
      fields: (t) => [
        t.field('id', b.string).pure((_) => 'a1'),
        t
            .field('motto', b.string)
            .withAuthorization(const Authorization.public())
            .pure((_) => 'free'),
        t
            .field('vip', b.string.nullable)
            .withAuthorization(Authorization.requires(['vip']))
            .pure((_) => 'gold'),
      ],
    );
    final entity = b.interface<Entity>(
      'Entity',
      fields: (t) => [
        t
            .field('title', b.string)
            .withAuthorization(Authorization.requires(['reader']))
            .pure((_) => 'inherited'),
      ],
    );
    final memo = b.object<Memo>(
      'Memo',
      interfaces: [entity],
      fields: (t) => [t.field('size', b.int).pure((_) => 1)],
    );
    final note = b.object<Note>(
      'Note',
      interfaces: [entity],
      fields: (t) => [
        t.field('title', b.string).pure((_) => 'redeclared'),
        t.field('size', b.int).pure((_) => 2),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('open', b.string).pure((_) => 'open'),
        t
            .field('secret', b.string.nullable)
            .withAuthorization(Authorization.requires(['admin']))
            .pure((_) => 'secret'),
        t
            .field('vault', b.string)
            .withAuthorization(Authorization.requires(['admin']))
            .pure((_) => 'vault'),
        t
            .field('shown', b.string)
            .withAuthorization(const Authorization.public())
            .pure((_) => 'shown'),
        t
            .field('greet', b.string.nullable, args: [name])
            .withAuthorization(Authorization.requires(['user', 'staff']))
            .resolve(
              (parent, args, context, info) async => 'hi ${args.get(name)}',
            ),
        t.field('account', account.nullable).resolve((p, a, c, i) => 1),
        t.field('memo', memo).pure((_) => const Memo()),
        t.field('note', note).pure((_) => const Note()),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('tick', b.int)
            .withAuthorization(Authorization.requires(['admin']))
            .subscribe((p, a, c, i) => Stream.value(1)),
      ],
    );
    return b.build(
      query: query,
      subscription: subscription,
      options: BuildOptions<Caller>(authorizer: authorizer),
    );
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  ValidDocument validDocument(String text) =>
      ValidDocument.assumeValid(built.schema, parse(text));

  /// The response to [text] as JSON, for a caller with [roles].
  Future<Map<String, Object?>> run(
    String text, {
    Set<String> roles = const {},
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final payload = await built.execute(
      validDocument(text),
      context: Caller(roles),
      options: options,
    );
    return payload.toJson().toJson();
  }
}
```

Create `packages/typed_graphql_server/test/authorization/authorization_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'authorization_fixture.dart';

void main() {
  late RoleAuthorizer authorizer;
  late AuthorizationFixture fixture;

  setUp(() {
    authorizer = RoleAuthorizer();
    fixture = AuthorizationFixture(authorizer);
  });

  Map<String, Object?> firstError(Map<String, Object?> json) =>
      (json['errors']! as List<Object?>).first! as Map<String, Object?>;

  String codeOf(Map<String, Object?> error) =>
      (error['extensions']! as Map<String, Object?>)['code']! as String;

  group('decisions', () {
    test('an allow runs the field', () async {
      final json = await fixture.run('{ secret }', roles: {'admin'});
      expect(json, {
        'data': {'secret': 'secret'},
      });
    });

    test('a deny is a GQL352 field error with the default message', () async {
      final json = await fixture.run('{ secret open }');
      expect(json['data'], {'secret': null, 'open': 'open'});
      final error = firstError(json);
      expect(error['message'], 'Not authorized to access Query.secret.');
      expect(error['path'], ['secret']);
      expect(codeOf(error), 'GQL352');
    });

    test('a deny can carry its own message', () async {
      final slow = AuthorizationFixture(SlowAuthorizer());
      final json = await slow.run('{ secret }');
      expect(firstError(json)['message'], 'Slow no.');
    });

    test('an asynchronous decision allows or denies', () async {
      final slow = AuthorizationFixture(SlowAuthorizer());
      expect(await slow.run('{ secret }', roles: {'admin'}), {
        'data': {'secret': 'secret'},
      });
      expect(codeOf(firstError(await slow.run('{ secret }'))), 'GQL352');
    });

    test('a deny on a non-null field propagates to the data', () async {
      final json = await fixture.run('{ open vault }');
      expect(json['data'], isNull);
      expect(codeOf(firstError(json)), 'GQL352');
    });

    test('the authorizer sees requirements, arguments and parent', () async {
      await fixture.run(
        '{ greet(name: "Ada") }',
        roles: {'user', 'staff'},
      );
      final access = authorizer.accesses.single;
      expect(access.requirements, ['user', 'staff']);
      expect(access.info.fieldName, 'greet');
      expect(access.arguments.coerced, {'name': 'Ada'});
      expect(access.context.roles, {'user', 'staff'});
    });

    test('all requirements are passed on, a missing role denies', () async {
      final json = await fixture.run('{ greet(name: "x") }', roles: {'user'});
      expect(json['data'], {'greet': null});
      expect(codeOf(firstError(json)), 'GQL352');
    });

    test(
      'an invalid argument is reported before the authorizer runs',
      () async {
        await fixture.run('{ greet }', roles: {'user', 'staff'});
        expect(authorizer.calls, isEmpty);
      },
    );
  });

  group('lanes', () {
    test('a pure field is guarded', () async {
      await fixture.run('{ secret }');
      expect(authorizer.calls, ['Query.secret']);
    });

    test('a synchronous decision keeps a pure query synchronous', () {
      final result = fixture.built.execute(
        fixture.validDocument('{ secret }'),
        context: const Caller({'admin'}),
      );
      expect(result, isNot(isA<Future<Object?>>()));
    });

    test('an authorizer exception is masked and offered to onError', () async {
      final throwing = AuthorizationFixture(ThrowingAuthorizer());
      final seen = <Object>[];
      final json = await throwing.run(
        '{ secret }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            seen.add(error);
            return null;
          },
        ),
      );
      expect(firstError(json)['message'], 'Unexpected error.');
      expect(codeOf(firstError(json)), 'GQL330');
      expect(seen.single, isA<StateError>());
    });

    test('a guarded subscription is refused at the source', () async {
      final result = await fixture.built.subscribe(
        fixture.validDocument('subscription { tick }'),
        context: const Caller(),
      );
      expect(result, isA<SubscriptionRejected>());
      final allowed = await fixture.built.subscribe(
        fixture.validDocument('subscription { tick }'),
        context: const Caller({'admin'}),
      );
      expect(allowed, isA<SubscriptionStarted>());
    });
  });

  group('rules', () {
    test('a type rule guards the fields without one', () async {
      final json = await fixture.run('{ account { id } }');
      expect(authorizer.calls, ['Account.id']);
      expect(codeOf(firstError(json)), 'GQL352');
    });

    test('a field rule wins over the type rule', () async {
      final json = await fixture.run(
        '{ account { id motto vip } }',
        roles: {'owner'},
      );
      expect(authorizer.calls, ['Account.id', 'Account.vip']);
      expect(json['data'], {
        'account': {'id': 'a1', 'motto': 'free', 'vip': null},
      });
    });

    test('a public field does not call the authorizer', () async {
      final json = await fixture.run('{ shown }');
      expect(json['data'], {'shown': 'shown'});
      expect(authorizer.calls, isEmpty);
    });

    test('an unguarded field does not call the authorizer', () async {
      await fixture.run('{ open }');
      expect(authorizer.calls, isEmpty);
    });

    test('an inherited interface field keeps the interface rule', () async {
      final json = await fixture.run('{ memo { title } }');
      expect(codeOf(firstError(json)), 'GQL352');
      expect(authorizer.calls, ['Memo.title']);
    });

    test('a redeclared interface field does not take its rule', () async {
      final json = await fixture.run('{ note { title } }');
      expect(json['data'], {
        'note': {'title': 'redeclared'},
      });
      expect(authorizer.calls, isEmpty);
    });

    test('introspection is never guarded', () async {
      final json = await fixture.run(
        '{ __typename __schema { queryType { name } } __type(name: "Query") '
        '{ name } }',
      );
      expect(json['data'], {
        '__typename': 'Query',
        '__schema': {
          'queryType': {'name': 'Query'},
        },
        '__type': {'name': 'Query'},
      });
      expect(authorizer.calls, isEmpty);
    });

    test('SelectedField.authorization is the effective rule', () async {
      final b = ExecutableSchemaBuilder<Caller>();
      final item = b.object<Object?>(
        'Item',
        options: ObjectOptions(authorization: Authorization.requires(['x'])),
        fields: (t) => [
          t.field('a', b.string).pure((_) => 'a'),
          t
              .field('b', b.string)
              .withAuthorization(const Authorization.public())
              .pure((_) => 'b'),
        ],
      );
      final rules = <String, Authorization?>{};
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('item', item).resolve((p, a, c, info) {
            for (final field in info.selection.fields) {
              rules[field.name] = field.authorization;
            }
            return 1;
          }),
          t.field('plain', b.string).pure((_) => 'p'),
        ],
      );
      final built = b.build(
        query: query,
        options: BuildOptions<Caller>(authorizer: RoleAuthorizer()),
      );
      await built.execute(
        ValidDocument.assumeValid(
          built.schema,
          fixture.parse('{ item { a b } }'),
        ),
        context: const Caller({'x'}),
      );
      expect(rules['a'], isA<RequiredAuthorization>());
      expect(rules['b'], isA<PublicAuthorization>());
    });
  });

  group('coverage', () {
    test('lists the unguarded fields, introspection excluded, sorted', () {
      expect(AuthorizationCoverage(fixture.built).uncovered, [
        'Memo.size',
        'Note.size',
        'Note.title',
        'Query.account',
        'Query.memo',
        'Query.note',
        'Query.open',
      ]);
    });
  });

  group('GQL304', () {
    test('a guarded field and no authorizer is a build error', () {
      expect(
        () => AuthorizationFixture(null),
        throwsA(
          isA<SchemaBuildError>().having(
            (error) => error.diagnostics.single,
            'diagnostic',
            isA<Diagnostic>()
                .having((d) => d.code, 'code', DiagnosticCode.missingAuthorizer)
                .having(
                  (d) => d.message,
                  'message',
                  contains('Query.secret, Query.vault'),
                ),
          ),
        ),
      );
    });

    test('public rules alone need no authorizer', () {
      final b = ExecutableSchemaBuilder<Caller>();
      final query = b.object<Object?>(
        'Query',
        options: const ObjectOptions(
          authorization: Authorization.public(),
        ),
        fields: (t) => [t.field('a', b.string).pure((_) => 'a')],
      );
      expect(b.build(query: query).authorizer, isNull);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/authorization/authorization_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/authorization/authorization.dart`:

```dart
/// The access rule of a field or of every field of an object type (R4.19).
///
/// A rule is data: the `Authorizer` decides what the requirements mean.
///
/// {@category authorization}
sealed class Authorization {
  const Authorization();

  /// A field anyone may read: the authorizer is not called, and the field
  /// counts as covered by `AuthorizationCoverage`.
  const factory Authorization.public() = PublicAuthorization;

  /// A field guarded by the authorizer, which receives [requirements] (for
  /// example roles or scopes) with every access.
  factory Authorization.requires(List<String> requirements) =
      RequiredAuthorization;
}

/// The rule of a field anyone may read.
///
/// {@category authorization}
final class PublicAuthorization extends Authorization {
  /// Creates the rule.
  const PublicAuthorization();
}

/// The rule of a field the authorizer guards.
///
/// {@category authorization}
final class RequiredAuthorization extends Authorization {
  /// Creates the rule with a copy of [requirements].
  RequiredAuthorization(List<String> requirements)
    : requirements = List.unmodifiable(requirements);

  /// What the authorizer is told the field needs.
  final List<String> requirements;
}
```

Create `packages/typed_graphql_server/lib/src/authorization/authorization_coverage.dart`:

```dart
import '../execution/executable_schema.dart';

/// Finds the fields no authorization rule covers, for a test that fails
/// when a new field ships unguarded.
///
/// {@category authorization}
final class AuthorizationCoverage {
  /// Reads the rules of [schema].
  AuthorizationCoverage(ExecutableSchema<Object?> schema)
    : uncovered = _uncoveredOf(schema);

  /// The coordinates (`Type.field`) of the fields with no rule on the field
  /// or its type, `public` rules counted as rules; introspection is
  /// excluded. Sorted.
  final List<String> uncovered;

  static List<String> _uncoveredOf(ExecutableSchema<Object?> schema) {
    final result = <String>[];
    for (final MapEntry(key: typeName, value: fields)
        in schema.bindings.fields.entries) {
      if (typeName.startsWith('__')) continue;
      for (final MapEntry(key: name, value: field) in fields.entries) {
        if (name.startsWith('__') || field.authorization != null) continue;
        result.add('$typeName.$name');
      }
    }
    return List.unmodifiable(result..sort());
  }
}
```

Create `packages/typed_graphql_server/lib/src/authorization/authorization_decision.dart`:

```dart
/// The answer of an `Authorizer`: [Allow] or [Deny].
///
/// {@category authorization}
sealed class AuthorizationDecision {
  const AuthorizationDecision();
}

/// Access is granted: the field runs.
///
/// {@category authorization}
final class Allow extends AuthorizationDecision {
  /// Creates the decision.
  const Allow();
}

/// Access is refused: the field is a `GQL352` error and null propagates as
/// for any field error.
///
/// {@category authorization}
final class Deny extends AuthorizationDecision {
  /// Creates the decision; [message] reaches the client in place of
  /// `Not authorized to access Type.field.`.
  const Deny({this.message});

  /// What the client reads, null for the default message.
  final String? message;
}
```

Create `packages/typed_graphql_server/lib/src/authorization/authorizer.dart`:

```dart
import 'dart:async';

import 'authorization_decision.dart';
import 'field_access.dart';

/// Decides whether a call of a guarded field may run (R4.19).
///
/// Called after the field's arguments are coerced and before its middleware,
/// on every lane, pure getters included; never for a `public` field or an
/// introspection field. An exception it throws is masked like a resolver's.
///
/// {@category authorization}
abstract interface class Authorizer<C> {
  /// The decision on [access]; it may wait.
  FutureOr<AuthorizationDecision> authorize(FieldAccess<C> access);
}
```

Create `packages/typed_graphql_server/lib/src/authorization/field_access.dart`:

```dart
import '../builder/arguments.dart';
import '../execution/field_info.dart';

/// What an `Authorizer` is asked about: one call of one guarded field.
///
/// {@category authorization}
final class FieldAccess<C> {
  /// Describes the access of the field [info] names on [parent].
  FieldAccess({
    required this.parent,
    required this.arguments,
    required this.context,
    required this.info,
    required this.requirements,
  });

  /// The value the field is read from.
  final Object? parent;

  /// The field's coerced arguments.
  final Arguments arguments;

  /// The request's context.
  final C context;

  /// The call, with its look-ahead (`info.selection`).
  final FieldInfo info;

  /// What the field's rule requires.
  final List<String> requirements;
}
```

Create `packages/typed_graphql_server/lib/src/builder/authorization_applier.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorization.dart';
import '../authorization/authorizer.dart';
import '../execution/schema_bindings.dart';
import 'field_def.dart';
import 'field_guard.dart';
import 'field_lane.dart';
import 'schema_build_error.dart';

/// Gives every object field its effective rule and guards the fields that
/// need the authorizer (R4.19, spec 12). Run after the middleware is
/// composed, so the check sits outside the chain, and before introspection
/// is added, which is never guarded.
///
/// The effective rule of an object's field is the rule on its definition
/// there (its own, or the interface field it inherits whole), else the
/// object type's. A field an object redeclares does not take the
/// interface's rule: an interface rule guards the implementations that
/// inherit the field.
final class AuthorizationApplier<C> {
  /// Applies the rules, checking with [_authorizer]; null when the build
  /// has none.
  AuthorizationApplier(this._authorizer);

  final Authorizer<C>? _authorizer;

  /// [bindings] with the rules applied; throws [SchemaBuildError] (`GQL304`)
  /// when a field is guarded and there is no authorizer.
  SchemaBindings apply(SchemaBindings bindings) {
    final unguardable = <String>[];
    final fields = {
      for (final MapEntry(key: typeName, value: own) in bindings.fields.entries)
        typeName: {
          for (final MapEntry(key: name, value: field) in own.entries)
            name: _applyTo(
              typeName,
              field,
              bindings.objects[typeName]?.options.authorization,
              unguardable,
            ),
        },
    };
    if (unguardable.isNotEmpty) {
      unguardable.sort();
      throw SchemaBuildError([
        Diagnostic(
          .missingAuthorizer,
          .error,
          'Fields are guarded by an authorization rule but the build has no '
          'authorizer (BuildOptions.authorizer): ${unguardable.join(', ')}.',
        ),
      ]);
    }
    return bindings.withFields(fields);
  }

  FieldDef<Object?, Object?> _applyTo(
    String typeName,
    FieldDef<Object?, Object?> field,
    Authorization? typeRule,
    List<String> unguardable,
  ) {
    final rule = field.authorization ?? typeRule;
    if (rule is! RequiredAuthorization) {
      return rule == null ? field : field.withLane(field.lane, rule);
    }
    final authorizer = _authorizer;
    if (authorizer == null) {
      unguardable.add('$typeName.${field.name}');
      return field;
    }
    final guard = FieldGuard<C>(authorizer, rule.requirements);
    return field.withLane(switch (field.lane) {
      PureLane(:final read) => ResolverLane(
        guard.guard<Object?>((parent, arguments, context, info) {
          return read(parent);
        }),
      ),
      ResolverLane(:final resolve) => ResolverLane(guard.guard(resolve)),
      SubscribeLane(:final source, :final resolve) => SubscribeLane(
        guard.guard(source),
        guard.guard(resolve),
      ),
      final DeclaredOnlyLane lane => lane,
    }, rule);
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/field_guard.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../authorization/authorization_decision.dart';
import '../authorization/authorizer.dart';
import '../authorization/field_access.dart';
import '../execution/field_info.dart';
import '../execution/graphql_exception.dart';
import 'arguments.dart';

/// Wraps the functions of one guarded field so the authorizer decides
/// first (R4.19, spec 12).
final class FieldGuard<C> {
  /// Guards with [_authorizer] a field that needs [_requirements].
  FieldGuard(this._authorizer, this._requirements);

  final Authorizer<C> _authorizer;
  final List<String> _requirements;

  /// [call] preceded by the authorizer: a [Deny] throws, so the outcome is
  /// the field's error. A synchronous decision keeps the call synchronous.
  FutureOr<T> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  guard<T>(
    FutureOr<T> Function(
      Object? parent,
      Arguments arguments,
      Object? context,
      FieldInfo info,
    )
    call,
  ) => (parent, arguments, context, info) {
    final decision = _authorizer.authorize(
      FieldAccess<C>(
        parent: parent,
        arguments: arguments,
        context: context as C,
        info: info,
        requirements: _requirements,
      ),
    );
    FutureOr<T> proceed(AuthorizationDecision settled) {
      _requireAllowed(settled, info);
      return call(parent, arguments, context, info);
    }

    return decision is Future<AuthorizationDecision>
        ? decision.then(proceed)
        : proceed(decision);
  };

  void _requireAllowed(AuthorizationDecision decision, FieldInfo info) {
    if (decision case Deny(:final message)) {
      throw GraphQLException(
        message ??
            'Not authorized to access ${info.parentTypeName}.'
                '${info.fieldName}.',
        extensions: JsonObject({
          'code': JsonString(DiagnosticCode.notAuthorized.id),
        }),
      );
    }
  }
}
```

In `packages/typed_graphql_server/lib/src/builder/build_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../authorization/authorizer.dart';
 import '../execution/directive_middleware.dart';
 import '../execution/field_middleware.dart';
 
@@ -18,6 +19,7 @@ final class BuildOptions<C> {
     this.planCacheSize = 1000,
     this.middleware = const [],
     this.directiveMiddleware = const {},
+    this.authorizer,
   }) : assert(planCacheSize >= 0, 'a cache size is not negative');
 
   /// The directive definitions the schema declares besides the specified
@@ -42,4 +44,9 @@ final class BuildOptions<C> {
   /// directive. A name the schema does not define is an [ArgumentError] when
   /// the schema is built.
   final Map<String, DirectiveMiddleware<C>> directiveMiddleware;
+
+  /// Decides the access to the fields an `Authorization.requires` rule
+  /// guards; a schema with such fields and no authorizer fails to build
+  /// (`GQL304`).
+  final Authorizer<C>? authorizer;
 }
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../execution/executable_schema.dart';
 import '../introspection/introspection_bindings.dart';
+import 'authorization_applier.dart';
 import 'build_options.dart';
 import 'builder_checks.dart';
 import 'field_middleware_composer.dart';
@@ -63,10 +64,14 @@ final class ExecutableSchemaAssembly<C> {
       schema,
       options,
     ).compose(bindings);
+    final guarded = AuthorizationApplier<C>(
+      options.authorizer,
+    ).apply(composed);
     return ExecutableSchema(
       ValidSchema.assumeValid(schema),
-      IntrospectionBindings(schema).addTo(composed),
+      IntrospectionBindings(schema).addTo(guarded),
       planCacheSize: options.planCacheSize,
+      authorizer: options.authorizer,
     );
   }
 
```

In `packages/typed_graphql_server/lib/src/builder/field_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../authorization/authorization.dart';
 import 'arg.dart';
 import 'field_lane.dart';
 import 'output_ref.dart';
@@ -20,6 +21,7 @@ final class FieldDef<P, C> {
     required this.lane,
     this.description,
     this.deprecationReason,
+    this.authorization,
     List<Object> middleware = const [],
   }) : args = List.unmodifiable(args),
        directives = List.unmodifiable(directives),
@@ -51,15 +53,22 @@ final class FieldDef<P, C> {
   /// `C`-typed function. The build casts them back where `C` is known.
   final List<Object> middleware;
 
+  /// The authorization rule that applies to the field: its own, else (after
+  /// the build) its object type's; null when it has none.
+  final Authorization? authorization;
+
   /// The same field with [lane] and no middleware of its own: the build
-  /// stores the composed chain this way.
-  FieldDef<P, C> withLane(FieldLane lane) => FieldDef(
-    name: name,
-    type: type,
-    args: args,
-    directives: directives,
-    lane: lane,
-    description: description,
-    deprecationReason: deprecationReason,
-  );
+  /// stores the composed chain this way. [authorization] replaces the rule
+  /// when given.
+  FieldDef<P, C> withLane(FieldLane lane, [Authorization? authorization]) =>
+      FieldDef(
+        name: name,
+        type: type,
+        args: args,
+        directives: directives,
+        lane: lane,
+        description: description,
+        deprecationReason: deprecationReason,
+        authorization: authorization ?? this.authorization,
+      );
 }
```

In `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,7 @@ import 'dart:async';
 
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../authorization/authorization.dart';
 import '../execution/field_info.dart';
 import '../execution/field_middleware.dart';
 import 'arg.dart';
@@ -25,7 +26,7 @@ final class FieldStub<P, R, C> {
     OutputRef<R> type, {
     List<Arg<Object?>> args = const [],
     String? description,
-  }) : this._(name, type, args, description, null, const [], const []);
+  }) : this._(name, type, args, description, null, const [], const [], null);
 
   FieldStub._(
     this.name,
@@ -35,6 +36,7 @@ final class FieldStub<P, R, C> {
     this._deprecationReason,
     this._directives,
     this._middleware,
+    this._authorization,
   );
 
   /// The field's name.
@@ -50,6 +52,7 @@ final class FieldStub<P, R, C> {
   final String? _deprecationReason;
   final List<AppliedDirective> _directives;
   final List<FieldMiddleware<C>> _middleware;
+  final Authorization? _authorization;
 
   /// The same field, deprecated for [reason].
   FieldStub<P, R, C> deprecated(String reason) => FieldStub._(
@@ -60,14 +63,24 @@ final class FieldStub<P, R, C> {
     reason,
     _directives,
     _middleware,
+    _authorization,
   );
 
   /// The same field with [directives] applied after the ones already given.
   FieldStub<P, R, C> withDirectives(List<AppliedDirective> directives) =>
-      FieldStub._(name, type, _args, description, _deprecationReason, [
-        ..._directives,
-        ...directives,
-      ], _middleware);
+      FieldStub._(
+        name,
+        type,
+        _args,
+        description,
+        _deprecationReason,
+        [
+          ..._directives,
+          ...directives,
+        ],
+        _middleware,
+        _authorization,
+      );
 
   /// The same field with [middleware] after the ones already given.
   ///
@@ -83,6 +96,27 @@ final class FieldStub<P, R, C> {
         _deprecationReason,
         _directives,
         [..._middleware, ...middleware],
+        _authorization,
+      );
+
+  /// The same field under [authorization], replacing a rule given before.
+  ///
+  /// The rule wins over the object type's (`ObjectOptions.authorization`).
+  /// A field that needs the authorizer is checked before its middleware,
+  /// whichever lane it has, and a build without an authorizer fails
+  /// (`GQL304`). On an interface field the rule guards the implementations
+  /// that inherit the field; an object that declares the field itself is
+  /// not guarded by it.
+  FieldStub<P, R, C> withAuthorization(Authorization authorization) =>
+      FieldStub._(
+        name,
+        type,
+        _args,
+        description,
+        _deprecationReason,
+        _directives,
+        _middleware,
+        authorization,
       );
 
   /// Completes the field with a synchronous getter (the pure lane, R4.2).
@@ -199,5 +233,6 @@ final class FieldStub<P, R, C> {
     directives: _directives,
     lane: lane,
     middleware: _middleware,
+    authorization: _authorization,
   );
 }
```

In `packages/typed_graphql_server/lib/src/builder/object_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,11 +1,17 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../authorization/authorization.dart';
+
 /// The rarer settings of an object type.
 ///
 /// {@category builder}
 final class ObjectOptions {
   /// Creates the options.
-  const ObjectOptions({this.isTypeOf, this.directives = const []});
+  const ObjectOptions({
+    this.isTypeOf,
+    this.directives = const [],
+    this.authorization,
+  });
 
   /// Tells whether a value belongs to the type, when `value is P` is not
   /// enough (for example two types over one Dart class).
@@ -13,4 +19,8 @@ final class ObjectOptions {
 
   /// The directives applied to the type.
   final List<AppliedDirective> directives;
+
+  /// The rule of every field of the type that has none of its own, null for
+  /// none.
+  final Authorization? authorization;
 }
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,7 @@ import 'dart:async';
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../authorization/authorizer.dart';
 import '../plan/plan_cache.dart';
 import '../subscription/subscription_result.dart';
 import 'execution_options.dart';
@@ -19,8 +20,12 @@ import 'subscription_execution.dart';
 /// {@category execution}
 final class ExecutableSchema<C> {
   /// Creates the schema from a validated [schema] and its [bindings].
-  ExecutableSchema(this.schema, this.bindings, {int planCacheSize = 1000})
-    : planCache = PlanCache(planCacheSize);
+  ExecutableSchema(
+    this.schema,
+    this.bindings, {
+    int planCacheSize = 1000,
+    this.authorizer,
+  }) : planCache = PlanCache(planCacheSize);
 
   /// The validated schema.
   final ValidSchema schema;
@@ -29,6 +34,9 @@ final class ExecutableSchema<C> {
   @internal
   final SchemaBindings bindings;
 
+  /// The authorizer the schema was built with, null when it has none.
+  final Authorizer<C>? authorizer;
+
   /// The operation plans made for this schema; not part of the public API.
   @internal
   final PlanCache planCache;
```

In `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:meta/meta.dart';
 
+import '../authorization/authorization.dart';
 import '../builder/arguments.dart';
 import '../builder/field_def.dart';
 import '../coercion/coercion_result.dart';
@@ -36,6 +37,13 @@ final class SelectedField {
   /// The alias the request gave, null when it gave none.
   String? get alias => responseKey == name ? null : responseKey;
 
+  /// The authorization rule that applies to the field (its own, else its
+  /// object type's), null when it has none or the field is introspection.
+  Authorization? get authorization {
+    final plan = _plans.first;
+    return _definitions[plan.parentType.name]?[plan.fieldName]?.authorization;
+  }
+
   /// The field's arguments with the request's variables substituted and the
   /// defaults applied, coerced when first read.
   ///
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,11 @@
 /// introspection and subscriptions (M5c) work. See the package README.
 library;
 
+export 'src/authorization/authorization.dart';
+export 'src/authorization/authorization_coverage.dart';
+export 'src/authorization/authorization_decision.dart';
+export 'src/authorization/authorizer.dart';
+export 'src/authorization/field_access.dart';
 export 'src/builder/arg.dart';
 export 'src/builder/arguments.dart';
 export 'src/builder/arguments_def.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/authorization/authorization_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Create `packages/typed_graphql_server/doc/authorization.md`:

````markdown
# Authorization

A field can carry an `Authorization` rule: `Authorization.requires(['admin'])`
names what the caller needs, `Authorization.public()` says anyone may read it.
The rule is data. An `Authorizer<C>`, given to `build` in
`BuildOptions.authorizer`, decides what the requirements mean and answers
`Allow` or `Deny`, now or later.

A rule is set on a field with `.withAuthorization(...)`, or on every field of
an object type with `ObjectOptions.authorization`; a field's own rule wins
over its type's. The authorizer runs for a guarded field after its arguments
are coerced and before its middleware, for pure getters too, and never for a
`public` or an introspection field. A schema with a guarded field and no
authorizer does not build (`GQL304`).

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Roles implements Authorizer<Set<String>> {
  @override
  FutureOr<AuthorizationDecision> authorize(FieldAccess<Set<String>> access) =>
      access.requirements.every(access.context.contains)
      ? const Allow()
      : const Deny();
}

void main() {
  final b = ExecutableSchemaBuilder<Set<String>>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', b.string).pure((_) => 'hello'),
      t
          .field('secret', b.string.nullable)
          .withAuthorization(Authorization.requires(['admin']))
          .pure((_) => 'the secret'),
    ],
  );
  final schema = b.build(
    query: query,
    options: BuildOptions<Set<String>>(authorizer: Roles()),
  );
  final document = const Parser()
      .parse(Source('{ hello secret }'))
      .requireDocument();
  for (final roles in [
    <String>{'admin'},
    <String>{},
  ]) {
    final result = schema.execute(
      ValidDocument.assumeValid(schema.schema, document),
      context: roles,
    );
    print(jsonEncode((result as ExecutionResult).toJson().toJson()));
  }
}
```

It prints:

```text
{"data":{"hello":"hello","secret":"the secret"}}
{"errors":[{"message":"Not authorized to access Query.secret.","path":["secret"],"extensions":{"code":"GQL352"}}],"data":{"hello":"hello","secret":null}}
```

A deny is a field error with the code `GQL352` and the message
`Not authorized to access Type.field.`, or the message given to `Deny`; null
propagates as for any field error. An exception thrown by the authorizer is
masked like a resolver's and reaches `ExecutionOptions.onError`.

`SelectedField.authorization` tells a look-ahead which rule applies to a field.
`AuthorizationCoverage(schema).uncovered` lists the fields with no rule on the
field or its type, introspection excluded, sorted; assert it is empty in an
application's tests so a new field cannot ship unguarded.
````

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Authorization: `Authorization.requires` and `Authorization.public` rules on a
  field (`.withAuthorization`) or an object type (`ObjectOptions.authorization`),
  an `Authorizer<C>` in `BuildOptions.authorizer` that answers `Allow` or `Deny`
  (a `GQL352` field error) after argument coercion and before the middleware,
  on every lane, `GQL304` for a guarded field without an authorizer,
  `SelectedField.authorization`, `AuthorizationCoverage.uncovered` and the
  Authorization guide.
```

In `packages/typed_graphql_server/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,8 @@
 dartdoc:
   categories:
+    authorization:
+      markdown: doc/authorization.md
+      displayName: Authorization
     builder:
       markdown: doc/schema_builder.md
       displayName: Schema Builder
@@ -16,6 +19,7 @@ dartdoc:
       markdown: doc/subscriptions.md
       displayName: Subscriptions
   categoryOrder:
+    - authorization
     - builder
     - execution
     - introspection
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/dartdoc_options.yaml packages/typed_graphql_server/doc/authorization.md packages/typed_graphql_server/lib/src/authorization/authorization.dart packages/typed_graphql_server/lib/src/authorization/authorization_coverage.dart packages/typed_graphql_server/lib/src/authorization/authorization_decision.dart packages/typed_graphql_server/lib/src/authorization/authorizer.dart packages/typed_graphql_server/lib/src/authorization/field_access.dart packages/typed_graphql_server/lib/src/builder/authorization_applier.dart packages/typed_graphql_server/lib/src/builder/build_options.dart packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart packages/typed_graphql_server/lib/src/builder/field_def.dart packages/typed_graphql_server/lib/src/builder/field_guard.dart packages/typed_graphql_server/lib/src/builder/field_stub.dart packages/typed_graphql_server/lib/src/builder/object_options.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/lib/src/lookahead/selected_field.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/authorization/authorization_fixture.dart packages/typed_graphql_server/test/authorization/authorization_test.dart
git commit -q -m "feat(typed_graphql_server): authorize fields through an Authorizer" \
  -m "Authorization rules on fields and object types, checked by an Authorizer after argument coercion and before middleware on every lane; GQL304 and GQL352; coverage check." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Cancellation and timeouts

Add `CancelSignal` in `lib/src/cancellation/`, `ExecutionOptions.cancelSignal` and `timeout`, `FieldInfo.cancelSignal`, the internal `RunCancellation` in the executor and in subscriptions (`GQL350`, `GQL351`), the `cancellation` category and a first Cancellation guide.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart`, `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`
- Modify: `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/field_info.dart`, `packages/typed_graphql_server/lib/src/execution/operation_execution.dart`, `packages/typed_graphql_server/lib/src/execution/operation_preparation.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/dartdoc_options.yaml`
- Create (documents): `packages/typed_graphql_server/doc/cancellation.md`
- Test: `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart`, `packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart`, `packages/typed_graphql_server/test/cancellation/subscription_cancellation_test.dart`

**Interfaces:**
- Consumes: Task 1 and the executor and subscriptions of M5b and M5c.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// cancellation/cancel_signal.dart
final class CancelSignal
  CancelSignal()
  List<void Function()>? _listeners
  bool get isCancelled
  Object? get reason
  Future<void> get whenCancelled
  void cancel([Object? reason])
  void Function() addListener(void Function() listener)

// execution/run_cancellation.dart
final class RunCancellation
  static RunCancellation? from(ExecutionOptions options)
  void Function()? _detach
  bool get isCancelled
  GraphQLError get error
  ExecutionResult get result
  Future<ExecutionResult> race(Future<ExecutionResult> pending)
  void dispose()
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of a cancellation test: what the resolvers saw, and the
/// gate they wait for.
final class Probe {
  final List<String> log = [];

  /// The run's signal as the slow resolver saw it.
  CancelSignal? seen;

  /// Whether the signal was already cancelled when the slow resolver ended.
  bool? wasCancelledAtEnd;

  /// Resolvers that wait stop here until the test completes it.
  final Completer<void> gate = Completer<void>();

  /// The caller's signal, for a resolver that cancels it.
  CancelSignal? caller;

  /// The source of the subscription fields.
  // `late`: the callback reads a field of this object.
  late final StreamController<int> source = StreamController<int>(
    onCancel: () => isSourceCancelled = true,
  );

  bool isSourceCancelled = false;

  /// Ends the source; one nobody listened to stays pending.
  void dispose() => unawaited(source.close());
}

/// Records the timers created with the watched duration, to tell that none
/// is left running.
final class TimerTracker {
  TimerTracker(this.watched);

  final Duration watched;
  final List<Timer> _created = [];

  /// Runs [body] so that the timers it starts are recorded.
  R run<R>(R Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        if (duration == watched) {
          _created.add(timer);
        }
        return timer;
      },
    ),
  );

  int get created => _created.length;

  bool get isIdle => _created.every((timer) => !timer.isActive);
}

/// A schema with one field per behaviour under test.
final class CancellationFixture {
  CancellationFixture() {
    final b = ExecutableSchemaBuilder<Probe>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('sync', b.string).pure((_) => 'ok'),
        t.field('slow', b.string).resolve((parent, args, context, info) async {
          context.log.add('slow start');
          context.seen = info.cancelSignal;
          await context.gate.future;
          context.wasCancelledAtEnd = info.cancelSignal.isCancelled;
          return 'slow';
        }),
        t.field('cancelsItself', b.string).resolve((
          parent,
          args,
          context,
          info,
        ) {
          context.caller?.cancel('stop');
          return 'done';
        }),
        t.field('after', b.string).resolve((parent, args, context, info) {
          context.log.add('after start');
          return 'after';
        }),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('first', b.string).resolve((parent, args, context, info) async {
          context.log.add('first start');
          await context.gate.future;
          return 'first';
        }),
        t.field('second', b.string).resolve((parent, args, context, info) {
          context.log.add('second start');
          return 'second';
        }),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('ticks', b.int)
            .subscribe((parent, args, context, info) => context.source.stream),
        t.field('held', b.int).subscribeWith<int>(
          (parent, args, context, info) => context.source.stream,
          (event, args, context, info) async {
            context.log.add('held $event');
            await context.gate.future;
            return event;
          },
        ),
      ],
    );
    built = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  // `late`: assigned at the end of the constructor body.
  late final ExecutableSchema<Probe> built;

  ValidDocument document(String text) => ValidDocument.assumeValid(
    built.schema,
    const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument(),
  );

  FutureOr<ResponsePayload> execute(
    String text,
    Probe probe, {
    ExecutionOptions options = const ExecutionOptions(),
    String? operationName,
  }) => built.execute(
    document(text),
    context: probe,
    options: options,
    operationName: operationName,
  );

  FutureOr<SubscriptionResult> subscribe(
    String text,
    Probe probe, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => built.subscribe(document(text), context: probe, options: options);

  /// The `extensions.code` of the only error of [result].
  static String codeOf(ResponsePayload result) {
    final json = result.toJson().toJson();
    final errors = json['errors'] as List<Object?>;
    final error = errors.single as Map<String, Object?>;
    return (error['extensions'] as Map<String, Object?>)['code'] as String;
  }

  /// The message of the only error of [result].
  static String messageOf(ResponsePayload result) {
    final json = result.toJson().toJson();
    final errors = json['errors'] as List<Object?>;
    return (errors.single as Map<String, Object?>)['message'] as String;
  }
}
```

Create `packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);

  group('a signal cancelled before execute', () {
    test('gives the cancelled result without a Future', () {
      final probe = Probe();
      final signal = CancelSignal()..cancel();
      final result = fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(result, isNot(isA<Future<Object?>>()));
      result as ExecutionResult;
      expect(result.data, isNull);
      expect(CancellationFixture.codeOf(result), 'GQL350');
      expect(
        CancellationFixture.messageOf(result),
        'Execution was cancelled.',
      );
      expect(probe.log, isEmpty);
    });

    test('loses to a request error', () {
      final signal = CancelSignal()..cancel();
      final result = fixture.execute(
        '{ sync }',
        Probe(),
        operationName: 'Missing',
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(result, isA<RequestErrorResult>());
    });
  });

  group('cancelling during an execution', () {
    test('completes at once and the resolver sees the signal', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(pending, isA<Future<Object?>>());
      expect(probe.seen?.isCancelled, isFalse);
      signal.cancel('client left');
      final result = await (pending as Future<ResponsePayload>).timeout(
        patience,
      );
      expect(CancellationFixture.codeOf(result), 'GQL350');
      expect((result as ExecutionResult).data, isNull);
      expect(probe.seen?.isCancelled, isTrue);
      expect(probe.seen?.reason, 'client left');
    });

    test('drops what a resolver returns afterwards', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      signal.cancel();
      final result = await (pending as Future<ResponsePayload>);
      probe.gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(probe.wasCancelledAtEnd, isTrue);
      expect((result as ExecutionResult).data, isNull);
      expect(result.errors, hasLength(1));
    });

    test('starts no field after it', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        'mutation { first second }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      signal.cancel();
      probe.gate.complete();
      final result = await (pending as Future<ResponsePayload>);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(CancellationFixture.codeOf(result), 'GQL350');
      expect(probe.log, ['first start']);
    });

    test('by a resolver of a synchronous query stays synchronous', () {
      final probe = Probe();
      final signal = CancelSignal();
      probe.caller = signal;
      final result = fixture.execute(
        '{ cancelsItself }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect(CancellationFixture.codeOf(result as ExecutionResult), 'GQL350');
    });
  });

  group('the timeout', () {
    test('ends a slow execution with GQL351', () async {
      final result = await (fixture.execute(
        '{ slow }',
        Probe(),
        options: const ExecutionOptions(timeout: Duration(milliseconds: 20)),
      ) as Future<ResponsePayload>).timeout(patience);
      expect((result as ExecutionResult).data, isNull);
      expect(CancellationFixture.codeOf(result), 'GQL351');
      expect(
        CancellationFixture.messageOf(result),
        'Execution timed out after 20 ms.',
      );
    });

    test('shows the resolver a cancelled signal', () async {
      final probe = Probe();
      await (fixture.execute(
        '{ slow }',
        probe,
        options: const ExecutionOptions(timeout: Duration(milliseconds: 20)),
      ) as Future<ResponsePayload>).timeout(patience);
      expect(probe.seen?.isCancelled, isTrue);
    });

    test('keeps a synchronous query synchronous', () {
      final result = fixture.execute(
        '{ sync }',
        Probe(),
        options: const ExecutionOptions(timeout: Duration(minutes: 5)),
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect((result as ExecutionResult).errors, isEmpty);
    });

    test('is not exceeded by a query that answers in time', () async {
      final probe = Probe()..gate.complete();
      final result = await fixture.execute(
        '{ slow }',
        probe,
        options: const ExecutionOptions(timeout: Duration(minutes: 5)),
      );
      expect((result as ExecutionResult).errors, isEmpty);
    });
  });

  group('the timer', () {
    const watched = Duration(minutes: 5);
    const options = ExecutionOptions(timeout: watched);

    test('is cancelled when a synchronous run ends', () {
      final tracker = TimerTracker(watched);
      tracker.run(() => fixture.execute('{ sync }', Probe(), options: options));
      expect(tracker.created, 1);
      expect(tracker.isIdle, isTrue);
    });

    test('is cancelled when an asynchronous run ends', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe()..gate.complete();
      final pending = tracker.run(
        () => fixture.execute('{ slow }', probe, options: options),
      );
      expect(tracker.isIdle, isFalse);
      await pending;
      expect(tracker.created, 1);
      expect(tracker.isIdle, isTrue);
    });

    test('is cancelled when the signal ends the run', () async {
      final tracker = TimerTracker(watched);
      final signal = CancelSignal();
      final pending = tracker.run(
        () => fixture.execute(
          '{ slow }',
          Probe(),
          options: ExecutionOptions(timeout: watched, cancelSignal: signal),
        ),
      );
      signal.cancel();
      await pending;
      expect(tracker.isIdle, isTrue);
    });

    test('is not started for a request error', () {
      final tracker = TimerTracker(watched);
      final result = tracker.run(
        () => fixture.execute(
          '{ sync }',
          Probe(),
          operationName: 'Missing',
          options: options,
        ),
      );
      expect(result, isA<RequestErrorResult>());
      expect(tracker.created, 0);
    });
  });

  group('the caller signal', () {
    test('is not cancelled by a timeout', () async {
      final signal = CancelSignal();
      await (fixture.execute(
        '{ slow }',
        Probe(),
        options: ExecutionOptions(
          cancelSignal: signal,
          timeout: const Duration(milliseconds: 10),
        ),
      ) as Future<ResponsePayload>).timeout(patience);
      expect(signal.isCancelled, isFalse);
    });

    test('is not cancelled when the run finishes', () {
      final signal = CancelSignal();
      fixture.execute(
        '{ sync }',
        Probe(),
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(signal.isCancelled, isFalse);
    });

    test('keeps no listener after the run', () async {
      final signal = CancelSignal();
      final probe = Probe()..gate.complete();
      await fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      probe.seen?.cancel();
      signal.cancel();
      expect(signal.isCancelled, isTrue);
    });
  });

  test('a call without a signal or timeout never sees a cancelled signal', () {
    final probe = Probe()..gate.complete();
    final result = fixture.execute('{ slow after }', probe);
    expect(result, isA<Future<Object?>>());
    expect(probe.seen?.isCancelled, isFalse);
  });
}
```

Create `packages/typed_graphql_server/test/cancellation/subscription_cancellation_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);

  Future<Stream<ExecutionResult>> started(
    String text,
    Probe probe,
    ExecutionOptions options,
  ) async {
    final result = await fixture.subscribe(text, probe, options: options);
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
    };
  }

  test('a signal cancelled before subscribe rejects with GQL350', () async {
    final signal = CancelSignal()..cancel();
    final probe = Probe();
    final result = await fixture.subscribe(
      'subscription { ticks }',
      probe,
      options: ExecutionOptions(cancelSignal: signal),
    );
    expect(result, isA<SubscriptionRejected>());
    final error = (result as SubscriptionRejected).error;
    expect(CancellationFixture.codeOf(error), 'GQL350');
    expect(probe.isSourceCancelled, isFalse);
  });

  test('cancelling ends the stream with a final GQL350 result', () async {
    final probe = Probe();
    final signal = CancelSignal();
    final results = await started(
      'subscription { ticks }',
      probe,
      ExecutionOptions(cancelSignal: signal),
    );
    final collected = results.toList();
    probe.source.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    signal.cancel();
    final all = await collected.timeout(patience);
    expect(all, hasLength(2));
    expect(all.first.data, isNotNull);
    expect(all.last.data, isNull);
    expect(CancellationFixture.codeOf(all.last), 'GQL350');
    expect(probe.isSourceCancelled, isTrue);
    probe.dispose();
  });

  test('the timeout ends the stream with a final GQL351 result', () async {
    final probe = Probe();
    final results = await started(
      'subscription { ticks }',
      probe,
      const ExecutionOptions(timeout: Duration(milliseconds: 20)),
    );
    final all = await results.toList().timeout(patience);
    expect(all, hasLength(1));
    expect(CancellationFixture.codeOf(all.single), 'GQL351');
    expect(
      CancellationFixture.messageOf(all.single),
      'Execution timed out after 20 ms.',
    );
    expect(probe.isSourceCancelled, isTrue);
    probe.dispose();
  });

  test('cancelling drops the event being executed', () async {
    final probe = Probe();
    final signal = CancelSignal();
    final results = await started(
      'subscription { held }',
      probe,
      ExecutionOptions(cancelSignal: signal),
    );
    final collected = results.toList();
    probe.source.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(probe.log, ['held 1']);
    signal.cancel();
    probe.gate.complete();
    final all = await collected.timeout(patience);
    expect(all, hasLength(1));
    expect(CancellationFixture.codeOf(all.single), 'GQL350');
    probe.dispose();
  });

  test('the caller signal is not cancelled by the timeout', () async {
    final probe = Probe();
    final signal = CancelSignal();
    final results = await started(
      'subscription { ticks }',
      probe,
      ExecutionOptions(
        cancelSignal: signal,
        timeout: const Duration(milliseconds: 10),
      ),
    );
    await results.toList().timeout(patience);
    expect(signal.isCancelled, isFalse);
    probe.dispose();
  });

  group('the timer', () {
    const watched = Duration(minutes: 5);
    const options = ExecutionOptions(timeout: watched);

    test('is cancelled when the source ends', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe();
      final results = await tracker.run(
        () => started('subscription { ticks }', probe, options),
      );
      expect(tracker.created, 1);
      final collected = results.toList();
      expect(tracker.isIdle, isFalse);
      await probe.source.close();
      await collected.timeout(patience);
      expect(tracker.isIdle, isTrue);
    });

    test('is cancelled when the consumer cancels', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe();
      final results = await tracker.run(
        () => started('subscription { ticks }', probe, options),
      );
      final subscription = results.listen((_) {});
      await subscription.cancel();
      expect(tracker.isIdle, isTrue);
      expect(probe.isSourceCancelled, isTrue);
    });

    test('is cancelled when the signal ends the stream', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe();
      final signal = CancelSignal();
      final results = await tracker.run(
        () => started(
          'subscription { ticks }',
          probe,
          ExecutionOptions(timeout: watched, cancelSignal: signal),
        ),
      );
      final collected = results.toList();
      signal.cancel();
      await collected.timeout(patience);
      expect(tracker.isIdle, isTrue);
      probe.dispose();
    });

    test('is cancelled when the subscription is rejected', () async {
      final tracker = TimerTracker(watched);
      final result = await tracker.run(
        () => fixture.subscribe('{ sync }', Probe(), options: options),
      );
      expect(result, isA<SubscriptionRejected>());
      expect(tracker.isIdle, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/execute_cancellation_test.dart test/cancellation/subscription_cancellation_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart`:

```dart
import 'dart:async';

import 'package:meta/meta.dart';

/// A request to stop work, created and cancelled by the caller.
///
/// Pass one in `ExecutionOptions.cancelSignal`; the executor listens to it
/// and never cancels it. It has no tie to a transport or a platform, so an
/// HTTP adapter, a WebSocket handler or a test can all cancel the same way.
///
/// {@category cancellation}
final class CancelSignal {
  /// Creates a signal that is not cancelled.
  CancelSignal();

  final Completer<void> _completer = Completer<void>();
  List<void Function()>? _listeners;
  bool _isCancelled = false;
  Object? _reason;

  /// Whether [cancel] has been called.
  bool get isCancelled => _isCancelled;

  /// What the first [cancel] was given, null before it or without a reason.
  Object? get reason => _reason;

  /// Completes, never with an error, when the signal is cancelled; already
  /// complete for a signal that was.
  Future<void> get whenCancelled => _completer.future;

  /// Cancels the signal with an optional [reason]. Only the first call has
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

  /// Calls [listener] at once when the signal is cancelled, else when it
  /// is; returns a function that removes the listener. Unlike
  /// [whenCancelled] it leaves nothing behind once removed.
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

Create `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../cancellation/cancel_signal.dart';
import 'execution_options.dart';

/// The cancellation of one run (spec 13): the caller's signal and the timer
/// linked into one [signal]. The caller's signal is only listened to.
///
/// Nothing exists when the options have neither a signal nor a timeout, so
/// the plain path pays nothing. [dispose] ends the timer and the listener
/// when the run ends.
final class RunCancellation {
  RunCancellation._(this.signal);

  /// The run's cancellation, or null when [options] ask for none. A timer
  /// started here must be ended with [dispose].
  static RunCancellation? from(ExecutionOptions options) {
    final caller = options.cancelSignal;
    final timeout = options.timeout;
    if (caller == null && timeout == null) {
      return null;
    }
    final cancellation = RunCancellation._(CancelSignal());
    if (caller != null) {
      cancellation._detach = caller.addListener(
        () => cancellation.signal.cancel(caller.reason),
      );
    }
    if (timeout != null && !cancellation.signal.isCancelled) {
      cancellation._timeout = timeout;
      cancellation._timer = Timer(timeout, cancellation._timeOut);
    }
    return cancellation;
  }

  /// The signal resolvers see as `FieldInfo.cancelSignal`; cancelling it
  /// cancels the run.
  final CancelSignal signal;

  Timer? _timer;
  void Function()? _detach;
  Duration? _timeout;
  bool _isTimedOut = false;

  /// Whether the run was cancelled or timed out.
  bool get isCancelled => signal.isCancelled;

  /// `GQL350`, or `GQL351` when the timeout ended the run.
  GraphQLError get error => _isTimedOut
      ? _coded(
          'Execution timed out after ${_timeout?.inMilliseconds} ms.',
          DiagnosticCode.executionTimedOut,
        )
      : _coded('Execution was cancelled.', DiagnosticCode.executionCancelled);

  /// The response of a cancelled run: no data and [error].
  ExecutionResult get result => ExecutionResult(null, errors: [error]);

  /// [pending], or the cancelled [result] as soon as the run is cancelled.
  Future<ExecutionResult> race(Future<ExecutionResult> pending) {
    if (isCancelled) {
      return Future.value(result);
    }
    final completer = Completer<ExecutionResult>();
    final detach = signal.addListener(() {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    });
    pending.then(
      (value) {
        detach();
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        detach();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );
    return completer.future;
  }

  /// Ends the timer and stops listening to the caller's signal.
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _detach?.call();
    _detach = null;
  }

  void _timeOut() {
    _isTimedOut = true;
    signal.cancel(_timeout);
  }

  GraphQLError _coded(String message, DiagnosticCode code) => GraphQLError(
    message,
    extensions: JsonObject({'code': JsonString(code.id)}),
  );
}
```

In `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../cancellation/cancel_signal.dart';
 import '../introspection/introspection_policy.dart';
 import 'error_behavior.dart';
 import 'error_hook.dart';
@@ -26,6 +27,8 @@ final class ExecutionOptions {
     this.maxDepth = 256,
     this.maxSteps = 10000000,
     this.introspection = IntrospectionPolicy.enabled,
+    this.cancelSignal,
+    this.timeout,
   });
 
   /// The parent value of the root fields; the root type's Dart type must
@@ -62,4 +65,12 @@ final class ExecutionOptions {
 
   /// Whether `__schema` and `__type` are answered.
   final IntrospectionPolicy introspection;
+
+  /// Stops the execution when cancelled (spec 13). The executor only
+  /// listens to it. One signal serves one request or subscription.
+  final CancelSignal? cancelSignal;
+
+  /// How long the execution (for a subscription, its whole life) may take
+  /// before it is stopped with `GQL351`.
+  final Duration? timeout;
 }
```

In `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,6 +12,7 @@ import 'leaf_completion.dart';
 import 'list_completion.dart';
 import 'object_completion.dart';
 import 'response_path.dart';
+import 'run_cancellation.dart';
 import 'schema_bindings.dart';
 import 'selection_executor.dart';
 import 'value_completion.dart';
@@ -29,6 +30,7 @@ final class ExecutionRun {
     required this.variables,
     required this.rawVariables,
     required this.options,
+    this.cancellation,
   }) : reporter = ErrorReporter(options);
 
   /// The operation to run.
@@ -52,6 +54,12 @@ final class ExecutionRun {
   /// The settings of the call.
   final ExecutionOptions options;
 
+  /// The signal and timer of the call, null when it has neither.
+  final RunCancellation? cancellation;
+
+  /// Whether the call was cancelled or timed out.
+  bool get isCancelled => cancellation?.isCancelled ?? false;
+
   /// Makes and records the errors.
   final ErrorReporter reporter;
 
@@ -89,12 +97,16 @@ final class ExecutionRun {
     variables: variables,
     rawVariables: rawVariables,
     options: options,
+    cancellation: cancellation,
   );
 
   /// Executes the operation's root selection on [rootValue] and builds the
   /// response (September2025 6.2 "Executing Operations"). A mutation runs
   /// its root fields serially.
   FutureOr<ExecutionResult> executeRoot(Object? rootValue) {
+    if (cancellation case final cancelled? when cancelled.isCancelled) {
+      return cancelled.result;
+    }
     final root = plan.rootFor(plan.keyFor(variables));
     if (root.problem case final problem?) {
       reporter.problem(problem, null, const []);
@@ -103,10 +115,18 @@ final class ExecutionRun {
     final data = plan.operation.operation == OperationType.mutation
         ? selection.executeSerially(rootValue, root, ResponsePath.root, 1)
         : selection.execute(rootValue, root, ResponsePath.root, 1);
-    return data is Future<JsonObject?> ? data.then(_response) : _response(data);
+    if (data is! Future<JsonObject?>) {
+      return _response(data);
+    }
+    final response = data.then(_response);
+    return cancellation?.race(response) ?? response;
   }
 
+  // A call cancelled meanwhile answers with the cancellation only (spec 13).
   ExecutionResult _response(JsonObject? data) {
+    if (cancellation case final cancelled? when cancelled.isCancelled) {
+      return cancelled.result;
+    }
     final log = reporter.log;
     if (log.haltError case final halted?) {
       return ExecutionResult(null, errors: [halted]);
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -36,6 +36,9 @@ final class FieldExecution {
     int depth,
     int position,
   ) {
+    if (_run.isCancelled) {
+      return null;
+    }
     final site = CompletionSite(
       plan,
       parentPath.key(plan.responseKey, position),
@@ -256,6 +259,7 @@ final class FieldExecution {
       variables: _run.rawVariables,
       schema: _run.schema,
       rootValue: _run.options.rootValue,
+      cancelSignal: _run.cancellation?.signal,
       selectionReader: () => FieldSelection.under(
         [plan],
         _run.variables,
```

In `packages/typed_graphql_server/lib/src/execution/field_info.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../cancellation/cancel_signal.dart';
 import '../lookahead/field_selection.dart';
 import 'response_path.dart';
 
@@ -20,7 +21,8 @@ final class FieldInfo {
     required this.schema,
     this.rootValue,
     this.selectionReader,
-  });
+    CancelSignal? cancelSignal,
+  }) : _runSignal = cancelSignal;
 
   /// The field's name in the schema.
   final String fieldName;
@@ -63,6 +65,18 @@ final class FieldInfo {
   late final FieldSelection selection =
       selectionReader?.call() ?? FieldSelection.empty;
 
+  final CancelSignal? _runSignal;
+
+  /// Fires when the execution is cancelled or times out (R4.20): a resolver
+  /// doing long work checks `isCancelled` or awaits `whenCancelled` to stop.
+  ///
+  /// It is the run's own signal, linked to the caller's and the timeout.
+  /// Read it; cancelling it cancels the run. A call made outside an
+  /// execution, or by one without a signal or timeout, gets a signal that
+  /// is never cancelled.
+  // `late`: a signal is made only for a resolver that reads it.
+  late final CancelSignal cancelSignal = _runSignal ?? CancelSignal();
+
   /// The name of the object type the field is selected on.
   String get parentTypeName => parentType.name;
 }
```

In `packages/typed_graphql_server/lib/src/execution/operation_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../plan/plan_cache.dart';
 import 'execution_options.dart';
+import 'execution_run.dart';
 import 'operation_preparation.dart';
 import 'prepared_operation.dart';
 import 'schema_bindings.dart';
@@ -48,7 +49,28 @@ final class OperationExecution {
         );
     return switch (prepared) {
       OperationRefused(:final error) => error,
-      OperationReady(:final run) => run.executeRoot(_options.rootValue),
+      OperationReady(:final run) => _run(run),
     };
   }
+
+  // The timer and the listener end with the run, whether it finished at once
+  // or later (spec 13).
+  FutureOr<ExecutionResult> _run(ExecutionRun run) {
+    final FutureOr<ExecutionResult> result;
+    try {
+      result = run.executeRoot(_options.rootValue);
+    } on Object {
+      run.cancellation?.dispose();
+      rethrow;
+    }
+    final cancellation = run.cancellation;
+    if (cancellation == null) {
+      return result;
+    }
+    if (result is Future<ExecutionResult>) {
+      return result.whenComplete(cancellation.dispose);
+    }
+    cancellation.dispose();
+    return result;
+  }
 }
```

In `packages/typed_graphql_server/lib/src/execution/operation_preparation.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,6 +13,7 @@ import 'error_reporter.dart';
 import 'execution_options.dart';
 import 'execution_run.dart';
 import 'prepared_operation.dart';
+import 'run_cancellation.dart';
 import 'schema_bindings.dart';
 
 /// The part of a request that `execute` and `subscribe` share (September2025
@@ -118,6 +119,7 @@ final class OperationPreparation {
             variables: values,
             rawVariables: variables,
             options: _options,
+            cancellation: RunCancellation.from(_options),
           ),
         );
     }
```

In `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -55,6 +55,12 @@ final class SubscriptionExecution {
   }
 
   FutureOr<SubscriptionResult> _open(ExecutionRun run) {
+    if (run.cancellation case final cancelled? when cancelled.isCancelled) {
+      cancelled.dispose();
+      return SubscriptionRejected(
+        RequestErrorResult(errors: [cancelled.error]),
+      );
+    }
     final root = run.plan.rootFor(run.plan.keyFor(run.variables));
     final fields = root.fields;
     if (root.problem case final problem?) {
@@ -77,6 +83,7 @@ final class SubscriptionExecution {
   // A run that found no source has errors in its log; one that found no
   // root field at all has none, so it says so.
   SubscriptionRejected _rejected(ExecutionRun run) {
+    run.cancellation?.dispose();
     final log = run.reporter.log;
     final errors = switch (log.haltError) {
       final halted? => [halted],
```

In `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import 'dart:collection';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'execution_run.dart';
+import 'run_cancellation.dart';
 
 /// The response stream of a subscription (September2025 6.2.3.2
 /// "MapSourceToResponseEvent"): every source event is executed as the root
@@ -43,6 +44,13 @@ final class SubscriptionResponses {
   Stream<ExecutionResult> get stream => _controller.stream;
 
   void _listen() {
+    if (_template.cancellation case final cancellation?) {
+      if (cancellation.isCancelled) {
+        _stop(cancellation);
+        return;
+      }
+      cancellation.signal.addListener(() => _stop(cancellation));
+    }
     _subscription = _source.listen(
       _onEvent,
       onError: (Object error, StackTrace stackTrace) =>
@@ -62,6 +70,7 @@ final class SubscriptionResponses {
     final wasCancelled = _isCancelled;
     _isCancelled = true;
     _waiting.clear();
+    _template.cancellation?.dispose();
     if (wasCancelled) {
       return Future<void>.value();
     }
@@ -140,10 +149,26 @@ final class SubscriptionResponses {
 
   void _close() {
     if (!_isCancelled) {
+      _template.cancellation?.dispose();
       _controller.close();
     }
   }
 
+  // The signal fired or the timeout elapsed: one last result with the
+  // cancellation, then the end; the event in flight is dropped (spec 13).
+  void _stop(RunCancellation cancellation) {
+    if (_isCancelled) {
+      return;
+    }
+    _isCancelled = true;
+    _isBusy = false;
+    _waiting.clear();
+    cancellation.dispose();
+    _controller.add(cancellation.result);
+    _controller.close();
+    _subscription?.cancel().ignore();
+  }
+
   // The source failed (or the library did, which cannot be told apart by
   // the client): one last result with the error, then the end (spec 10).
   void _fail(Object error, StackTrace stackTrace) {
@@ -153,6 +178,7 @@ final class SubscriptionResponses {
     }
     _isCancelled = true;
     _waiting.clear();
+    _template.cancellation?.dispose();
     final reported = _template.reporter.sourceFailure(error, stackTrace);
     _controller.add(ExecutionResult(null, errors: [reported]));
     _controller.close();
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -33,6 +33,7 @@ export 'src/builder/output_ref.dart';
 export 'src/builder/scalar_type_def.dart';
 export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
+export 'src/cancellation/cancel_signal.dart';
 export 'src/execution/directive_middleware.dart';
 export 'src/execution/error_behavior.dart';
 export 'src/execution/error_hook.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/execute_cancellation_test.dart test/cancellation/subscription_cancellation_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Create `packages/typed_graphql_server/doc/cancellation.md`:

````markdown
# Cancellation

A request can be stopped from outside with a `CancelSignal`, or by a time
limit. `CancelSignal` is a plain class the caller creates and cancels: it has
no tie to a transport, so an HTTP handler that sees the client leave, a
WebSocket handler that receives a stop message and a test all use it the same
way. Give it to `ExecutionOptions.cancelSignal`; set
`ExecutionOptions.timeout` for a time limit. The executor only listens to the
signal and never cancels it.

A resolver sees the run's own signal as `FieldInfo.cancelSignal`: it fires
when the caller's signal does or the timeout elapses, so a resolver doing long
work can check `isCancelled` or await `whenCancelled` and stop. Read it; do
not cancel it, which would cancel the whole run.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('slow', b.string).resolve((parent, args, context, info) async {
        await info.cancelSignal.whenCancelled;
        return 'stopped';
      }),
    ],
  );
  final schema = b.build(query: query);
  final document = ValidDocument.assumeValid(
    schema.schema,
    const Parser().parse(Source('{ slow }')).requireDocument(),
  );

  final timedOut = await schema.execute(
    document,
    context: null,
    options: const ExecutionOptions(timeout: Duration(milliseconds: 20)),
  );
  print(jsonEncode((timedOut as ExecutionResult).toJson().toJson()));

  final signal = CancelSignal();
  final running = schema.execute(
    document,
    context: null,
    options: ExecutionOptions(cancelSignal: signal),
  );
  signal.cancel('client left');
  final cancelled = await running;
  print(jsonEncode((cancelled as ExecutionResult).toJson().toJson()));
}
```

It prints:

```text
{"errors":[{"message":"Execution timed out after 20 ms.","extensions":{"code":"GQL351"}}],"data":null}
{"errors":[{"message":"Execution was cancelled.","extensions":{"code":"GQL350"}}],"data":null}
```

Once the run is cancelled no resolver starts, and `execute` completes at once
with `data: null` and one error: `GQL350` "Execution was cancelled." or, for
the timeout, `GQL351` "Execution timed out after N ms." Whatever the
resolvers still running return is dropped. graphql-js rejects the promise
instead. A query of synchronous resolvers with a timeout still returns
without a `Future`: the timer ends before `execute` returns, and it ends with
the run in every case.

A signal that is already cancelled gives the cancelled result without running
a resolver. Request errors win over it: an unknown operation or unusable
variables are `RequestErrorResult`s whatever the signal says.

For `ExecutableSchema.subscribe` the signal and the timeout last as long as
the subscription. When one fires, the stream delivers one last result with the
cancellation error, the source subscription is cancelled and the stream
closes; the event being executed is dropped. A signal already cancelled at
`subscribe` gives a `SubscriptionRejected` with `GQL350`.
````

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Cancellation (R4.20): `CancelSignal` (`cancel`, `isCancelled`, `whenCancelled`,
  `reason`; no platform import), `ExecutionOptions.cancelSignal` and `timeout`,
  and `FieldInfo.cancelSignal`, the run's own signal. A cancelled or timed-out
  run starts no field, completes at once with `data: null` and one `GQL350` or
  `GQL351` error, and drops later resolver results; a synchronous query with a
  timeout stays synchronous, and the timer ends with the run. A subscription
  ends with a final cancellation result, cancels its source and closes; a
  signal cancelled at `subscribe` is a `SubscriptionRejected`. The Cancellation
  guide and its dartdoc category `cancellation`.
```

In `packages/typed_graphql_server/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,9 @@ dartdoc:
     builder:
       markdown: doc/schema_builder.md
       displayName: Schema Builder
+    cancellation:
+      markdown: doc/cancellation.md
+      displayName: Cancellation
     execution:
       markdown: doc/execution.md
       displayName: Execution
@@ -21,6 +24,7 @@ dartdoc:
   categoryOrder:
     - authorization
     - builder
+    - cancellation
     - execution
     - introspection
     - lookahead
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/dartdoc_options.yaml packages/typed_graphql_server/doc/cancellation.md packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart packages/typed_graphql_server/lib/src/execution/execution_options.dart packages/typed_graphql_server/lib/src/execution/execution_run.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/field_info.dart packages/typed_graphql_server/lib/src/execution/operation_execution.dart packages/typed_graphql_server/lib/src/execution/operation_preparation.dart packages/typed_graphql_server/lib/src/execution/run_cancellation.dart packages/typed_graphql_server/lib/src/execution/subscription_execution.dart packages/typed_graphql_server/lib/src/execution/subscription_responses.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart packages/typed_graphql_server/test/cancellation/subscription_cancellation_test.dart
git commit -q -m "feat(typed_graphql_server): cancel executions and time them out" \
  -m "CancelSignal, ExecutionOptions.cancelSignal and timeout, FieldInfo.cancelSignal; GQL350 and GQL351 results for execute and subscribe (R4.20)." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Conformance: cancellation

Port `cancellation-test.ts` (ported, adapted by spec 18.9 and 18.13, or skipped for incremental delivery and async-iterator internals) and record the remaining spec section 19 files in `mapping/execution.csv`.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`
- Test: `packages/typed_graphql_conformance/test/execution/cancellation_bubbling_test.dart`, `packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart`, `packages/typed_graphql_conformance/test/execution/cancellation_test.dart`, `packages/typed_graphql_conformance/test/support/cancellation_schema.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/execution_port.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/execution/cancellation_bubbling_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from the two sibling-error tests of graphql-js
// src/execution/__tests__/cancellation-test.ts, which run without an abort
// signal; mapping/execution.csv says why they are adapted. Spec 18.13 of M5:
// the executor waits for the resolvers that already started, so a late
// sibling is still run and its error still reported.
void main() {
  const port = ExecutionPort();

  Future<Map<String, Object?>> runBubbling({
    required Future<String> boom,
    required Future<String> Function() side,
    required bool isSideObject,
    required String text,
  }) async {
    final b = ExecutableSchemaBuilder<Object?>();
    final lateSide = b.object<String>(
      'LateSide',
      fields: (t) => [t.field('value', b.string.nullable).pure((_) => 'late')],
    );
    final parent = b.object<Object?>(
      'Parent',
      fields: (t) => [
        t
            .field('boom', b.string)
            .resolve((parent, args, context, info) => boom),
        if (isSideObject)
          t
              .field('side', lateSide.nullable)
              .resolve((parent, args, context, info) => side())
        else
          t
              .field('side', b.string.nullable)
              .resolve((parent, args, context, info) => side()),
      ],
    );
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('parent', parent.nullable)
              .resolve((parent, args, context, info) => Object()),
          t.field('other', b.string.nullable).pure((_) => 'ok'),
        ],
      ),
    );
    return port.withoutCodes(await port.run(schema, text));
  }

  const bubbled = <String, Object?>{
    'data': {'parent': null, 'other': 'ok'},
    'errors': [
      {
        'message': 'boom',
        'locations': [
          {'line': 1, 'column': 12},
        ],
        'path': ['parent', 'boom'],
      },
    ],
  };

  group('Execute: Cancellation', () {
    test('suppresses sibling errors after a non-null error bubbles', () async {
      final boom = Completer<String>();
      final side = Completer<String>();
      final result = runBubbling(
        boom: boom.future,
        side: () => side.future,
        isSideObject: false,
        text: '{ parent { boom side } other }',
      );
      boom.completeError(const GraphQLException('boom'));
      await Future<void>.delayed(Duration.zero);
      side.completeError(const GraphQLException('side'));
      expect(await result, {
        ...bubbled,
        'errors': [
          ...(bubbled['errors']! as List<Object?>),
          {
            'message': 'side',
            'locations': [
              {'line': 1, 'column': 17},
            ],
            'path': ['parent', 'side'],
          },
        ],
      });
    });

    test(
      'should stop late sibling object completion after non-null bubbling returns a response',
      () async {
        final boom = Completer<String>();
        final side = Completer<String>();
        final result = runBubbling(
          boom: boom.future,
          side: () => side.future,
          isSideObject: true,
          text: '{ parent { boom side { value } } other }',
        );
        boom.completeError(const GraphQLException('boom'));
        await Future<void>.delayed(Duration.zero);
        side.complete('late value');
        expect(await result, bubbled);
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/cancellation_schema.dart';
import '../support/execution_port.dart';

// Ported from the subscription tests of graphql-js
// src/execution/__tests__/cancellation-test.ts; mapping/execution.csv says
// which tests are adapted or skipped, and why. A cancelled subscription
// ends with one last GQL350 result instead of a rejected `next()`
// (spec 18.9 of M5), and a subscription that cannot start is a
// `SubscriptionRejected` value (spec 18.30).
void main() {
  const port = ExecutionPort();
  final fixture = CancellationSchema();
  const fooEvent = <String, Object?>{
    'data': {'foo': 'foo'},
  };
  const cancelled = <String, Object?>{
    'errors': [
      {
        'message': 'Execution was cancelled.',
        'extensions': {'code': 'GQL350'},
      },
    ],
    'data': null,
  };

  Future<SubscriptionResult> subscribe(
    CancellationProbe probe,
    CancelSignal signal,
  ) async => port.subscribe<CancellationProbe>(
    fixture.schema,
    'subscription { foo }',
    context: probe,
    options: ExecutionOptions(maskErrors: false, cancelSignal: signal),
  );

  Future<StreamIterator<Map<String, Object?>>> open(
    CancellationProbe probe,
    CancelSignal signal,
  ) async => switch (await subscribe(probe, signal)) {
    SubscriptionStarted(:final results) => StreamIterator(
      results.map((result) => result.toJson().toJson()),
    ),
    SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
  };

  group('Execute: Cancellation', () {
    test('should successfully wrap the subscription', () async {
      final probe = CancellationProbe()
        ..source = () async => Stream.value('foo');
      final events = await open(probe, CancelSignal());
      expect(await events.moveNext(), isTrue);
      expect(events.current, fooEvent);
      expect(await events.moveNext(), isFalse);
    });

    test(
      'should stop the execution when aborted during subscription',
      () async {
        final source = StreamController<String>();
        final probe = CancellationProbe()..source = () => source.stream;
        final signal = CancelSignal();
        final events = await open(probe, signal);
        source.add('foo');
        expect(await events.moveNext(), isTrue);
        expect(events.current, fooEvent);
        signal.cancel();
        expect(await events.moveNext(), isTrue);
        expect(events.current, cancelled);
        expect(await events.moveNext(), isFalse);
        expect(source.hasListener, isFalse);
        await source.close();
      },
    );

    test(
      'should stop the execution when aborted during subscription returned asynchronously',
      () async {
        final source = StreamController<String>();
        final probe = CancellationProbe()..source = () async => source.stream;
        final signal = CancelSignal();
        final events = await open(probe, signal);
        source.add('foo');
        expect(await events.moveNext(), isTrue);
        expect(events.current, fooEvent);
        signal.cancel();
        expect(await events.moveNext(), isTrue);
        expect(events.current, cancelled);
        expect(await events.moveNext(), isFalse);
        expect(source.hasListener, isFalse);
        await source.close();
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/cancellation_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/cancellation_schema.dart';
import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/cancellation-test.ts (the
// queries and mutations; the subscriptions are in
// cancellation_subscription_test.dart and the sibling errors in
// cancellation_bubbling_test.dart); mapping/execution.csv says which tests
// are adapted or skipped, and why. graphql-js rejects with "This operation
// was aborted" where `execute` completes with a GQL350 result (spec 18.9 of
// M5), so every result is compared with `cancelled`.
void main() {
  const port = ExecutionPort();
  final fixture = CancellationSchema();
  const cancelled = <String, Object?>{
    'errors': [
      {
        'message': 'Execution was cancelled.',
        'extensions': {'code': 'GQL350'},
      },
    ],
    'data': null,
  };
  const patience = Duration(seconds: 2);

  FutureOr<ResponsePayload> run(
    String text,
    CancellationProbe probe,
    CancelSignal signal,
  ) => port.payload(
    fixture.schema,
    text,
    context: probe,
    options: ExecutionOptions(maskErrors: false, cancelSignal: signal),
  );

  Future<Map<String, Object?>> settled(
    FutureOr<ResponsePayload> pending,
  ) async => (await Future<ResponsePayload>.value(
    pending,
  ).timeout(patience)).toJson().toJson();

  Future<void> later() => Future<void>.delayed(const Duration(milliseconds: 5));

  const nestedQuery = 'query { todo { id author { id } } }';

  group('Execute: Cancellation', () {
    test(
      'should stop the execution when aborted during object field completion',
      () async {
        final probe = CancellationProbe()
          ..todo = () async => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(probe.log, isEmpty);
      },
    );

    test(
      'should provide access to the abort signal within resolvers',
      () async {
        var isNotified = false;
        final probe = CancellationProbe()
          ..todo = () => CancellationTodo((info) async {
            unawaited(
              info.cancelSignal.whenCancelled.then((_) => isNotified = true),
            );
            await Future<void>.delayed(Duration.zero);
            throw StateError(
              'some random other error that does not show up in response',
            );
          });
        final signal = CancelSignal();
        final pending = run('query { todo { id } }', probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(isNotified, isTrue);
      },
    );

    test(
      'should stop the execution when aborted during object field completion with a custom error',
      () async {
        final probe = CancellationProbe()
          ..todo = () async => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        final reason = StateError('Custom abort error');
        signal.cancel(reason);
        expect(await settled(pending), cancelled);
        expect(signal.reason, same(reason));
        await later();
        expect(probe.log, isEmpty);
      },
    );

    test(
      'rejects with the aborted execution error while initial result is pending',
      () async {
        final probe = CancellationProbe();
        final signal = CancelSignal();
        final pending = run('query { blocker }', probe, signal);
        await probe.blockerStarted.future;
        signal.cancel(StateError('Custom abort error'));
        final result = await settled(pending);
        probe.blockerValue.complete('ok');
        await later();
        expect(result, cancelled);
      },
    );

    test(
      'throws the aborted execution error with a completed initial result in the atypical internal resolver-abort case',
      () {
        final signal = CancelSignal();
        final probe = CancellationProbe()
          ..aborter = () {
            signal.cancel(StateError('Custom abort error'));
            return 'done';
          };
        final result = run('query { aborter }', probe, signal);
        expect(result, isNot(isA<Future<Object?>>()));
        expect((result as ExecutionResult).toJson().toJson(), cancelled);
      },
    );

    test(
      'should stop the execution when aborted during nested object field completion',
      () async {
        final probe = CancellationProbe()
          ..todo = () => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(probe.log, ['author']);
      },
    );

    test(
      'should stop the execution when aborted despite a hanging resolver',
      () async {
        final probe = CancellationProbe()
          ..todo = () => Completer<CancellationTodo?>().future;
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
      },
    );

    test(
      'should stop the execution when aborted with proper null bubbling',
      () async {
        final probe = CancellationProbe()
          ..nonNullableTodo = () async => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(
          'query { nonNullableTodo { id author { id } } }',
          probe,
          signal,
        );
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(probe.log, isEmpty);
      },
    );

    test('should stop the execution when aborted mid-mutation', () async {
      final probe = CancellationProbe();
      final signal = CancelSignal();
      final pending = run('mutation { foo bar }', probe, signal);
      signal.cancel();
      expect(await settled(pending), cancelled);
      await later();
      expect(probe.log, ['foo']);
    });

    test('should stop the execution when aborted pre-execute', () {
      final probe = CancellationProbe();
      probe.todo = () {
        probe.log.add('todo');
        return null;
      };
      final signal = CancelSignal()..cancel();
      final result = run(nestedQuery, probe, signal);
      expect(result, isNot(isA<Future<Object?>>()));
      expect((result as ExecutionResult).toJson().toJson(), cancelled);
      expect(probe.log, isEmpty);
    });

    test(
      'should stop the execution when aborted before cancellation is wired',
      () async {
        final signal = CancelSignal();
        final probe = CancellationProbe()
          ..aborter = () {
            signal.cancel(StateError('Custom abort error'));
            return Completer<String?>().future;
          };
        final pending = run('query { aborter }', probe, signal);
        expect(await settled(pending), cancelled);
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/support/cancellation_schema.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A `Todo` of the graphql-js cancellation tests; [id] is a function so a
/// test can read the run's signal in it.
final class CancellationTodo {
  /// A todo whose `id` resolver is [id].
  CancellationTodo(this.id);

  /// A todo with a fixed id.
  CancellationTodo.of(String value) : id = ((_) => value);

  /// The `id` resolver.
  final FutureOr<String?> Function(FieldInfo info) id;
}

/// The context of a cancellation test: the data the root fields return, a
/// log of the resolvers that ran, and the gates the tests open.
final class CancellationProbe {
  /// The names of the resolvers that started, in order.
  final List<String> log = [];

  /// What `Query.todo` returns.
  FutureOr<CancellationTodo?> Function() todo = () => null;

  /// What `Query.nonNullableTodo` returns.
  FutureOr<CancellationTodo> Function() nonNullableTodo = () =>
      CancellationTodo.of('1');

  /// What `Query.aborter` returns.
  FutureOr<String?> Function() aborter = () => 'done';

  /// What `Subscription.foo` listens to.
  FutureOr<Stream<String>> Function() source = () => const Stream.empty();

  /// Completes when `Query.blocker` starts.
  final Completer<void> blockerStarted = Completer<void>();

  /// What `Query.blocker` waits for.
  final Completer<String> blockerValue = Completer<String>();
}

/// graphql-js's cancellation test schema (`Todo`, `User`, `Query`,
/// `Mutation`, `Subscription`) in the builder, driven by a
/// [CancellationProbe].
final class CancellationSchema {
  /// Builds the schema.
  CancellationSchema() {
    final b = ExecutableSchemaBuilder<CancellationProbe>();
    final user = b.object<Object?>(
      'User',
      fields: (t) => [
        t.field('id', b.id.nullable).resolve((parent, args, context, info) {
          context.log.add('user.id');
          return '1';
        }),
        t.field('name', b.string.nullable).pure((_) => 'user'),
      ],
    );
    final todo = b.object<CancellationTodo>(
      'Todo',
      fields: (t) => [
        t
            .field('id', b.id.nullable)
            .resolve((parent, args, context, info) => parent.id(info)),
        t.field('author', user.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          context.log.add('author');
          await Future<void>.delayed(Duration.zero);
          return Object();
        }),
      ],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('todo', todo.nullable)
            .resolve((parent, args, context, info) => context.todo()),
        t
            .field('nonNullableTodo', todo)
            .resolve(
              (parent, args, context, info) => context.nonNullableTodo(),
            ),
        t.field('blocker', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) {
          context.blockerStarted.complete();
          return context.blockerValue.future;
        }),
        t
            .field('aborter', b.string.nullable)
            .resolve((parent, args, context, info) => context.aborter()),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('foo', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          context.log.add('foo');
          return 'baz';
        }),
        t.field('bar', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) {
          context.log.add('bar');
          return 'bar';
        }),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('foo', b.string.nullable)
            .subscribe((parent, args, context, info) => context.source()),
      ],
    );
    schema = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  /// The executable schema.
  // `late`: assigned at the end of the constructor body.
  late final ExecutableSchema<CancellationProbe> schema;
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -110,6 +110,19 @@ void main() {
         'execution/__tests__/oneof-test.ts',
         'execution/__tests__/simplePubSub-test.ts',
         'execution/__tests__/subscribe-test.ts',
+        'execution/__tests__/cancellation-test.ts',
+        'execution/__tests__/AbortedGraphQLExecutionError-test.ts',
+        'execution/__tests__/AsyncWorkTracker-test.ts',
+        'execution/__tests__/cancellablePromise-test.ts',
+        'execution/__tests__/collectIteratorPromises-test.ts',
+        'execution/__tests__/diagnostics-execute-test.ts',
+        'execution/__tests__/diagnostics-resolve-test.ts',
+        'execution/__tests__/diagnostics-subscribe-test.ts',
+        'execution/__tests__/diagnostics-variable-coercion-test.ts',
+        'execution/__tests__/hooks-test.ts',
+        'execution/__tests__/incremental-test.ts',
+        'execution/__tests__/mapAsyncIterable-test.ts',
+        'execution/__tests__/withConcurrentAbruptClose-test.ts',
         'type/__tests__/enumType-test.ts',
         'type/__tests__/introspection-test.ts',
         'utilities/__tests__/coerceInputValue-test.ts',
```

In `packages/typed_graphql_conformance/test/support/execution_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -72,6 +72,8 @@ final class ExecutionPort {
         maxDepth: options.maxDepth,
         maxSteps: options.maxSteps,
         introspection: options.introspection,
+        cancelSignal: options.cancelSignal,
+        timeout: options.timeout,
       );
 
   /// [payload] for a schema whose context is not read.
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -496,3 +496,139 @@ execution/__tests__/simplePubSub-test.ts,SimplePubSub,subscribe async-iterator m
 execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,can introspect on union and intersection types,adapted,test/execution/union_interface_test.dart,The executor requires a root value of the root type (a Person); the introspection query ignores it.
 type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input arguments to subscriptions,adapted,test/execution/enum_type_test.dart,"subscribeToEnum has a declared, empty source; the operation is run once with execute (spec 10), which resolves it with a null event."
 type/__tests__/enumType-test.ts,Type System: Enum Values,can be introspected without error,adapted,test/execution/enum_type_test.dart,schema.toIntrospection(IntrospectionQuery.full) stands for introspectionFromSchema.
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during object field completion,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the author resolver never runs."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should provide access to the abort signal within resolvers,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; info.cancelSignal stands for getAbortSignal and is notified, and the error the resolver throws later is dropped."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during object field completion with a custom error,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the custom error is kept as CancelSignal.reason and is not the error message (see report)."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,rejects with the aborted execution error while initial result is pending,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; AbortedGraphQLExecutionError and its abortedResult are JavaScript-only (spec 19): the result completes while the field is pending and the late value is dropped."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,throws the aborted execution error with a completed initial result in the atypical internal resolver-abort case,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; a resolver that cancels a synchronous query gets a synchronous GQL350 result with no data, where graphql-js keeps the completed data in abortedResult."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,throws the aborted execution error with an external abort while incremental initial result is still pending,skipped,,Needs executeIncrementally and @defer incremental payloads (M14); AbortedGraphQLExecutionError is JavaScript-only (spec 19).
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,does not wrap aborts after the initial result,skipped,,Needs executeIncrementally and @defer incremental payloads (M14); AbortedGraphQLExecutionError is JavaScript-only (spec 19).
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during nested object field completion,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the fields below the pending author never start."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted despite a hanging resolver,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; a resolver that never completes does not keep execute pending."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted despite a hanging item,skipped,,"A typed list holds values, not futures or async iterables (spec 18.17), so this list item cannot be written."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during promised list item completion,skipped,,"A typed list holds values, not futures or async iterables (spec 18.17), so this list item cannot be written."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted despite a hanging async item,skipped,,"A typed list holds values, not futures or async iterables (spec 18.17), so this list item cannot be written."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop resolving abstract types after aborting,skipped,,"resolveType and isTypeOf are synchronous (spec 18.24), so a pending one cannot be written."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop resolving isTypeOf after aborting,skipped,,"resolveType and isTypeOf are synchronous (spec 18.24), so a pending one cannot be written."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted with proper null bubbling,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the result is data null with the one GQL350 error."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,suppresses sibling errors after a non-null error bubbles,adapted,test/execution/cancellation_bubbling_test.dart,"Spec 18.13: the executor waits for the resolvers that already started, so the late sibling is still run and its outcome reported; the test has no abort signal. The side error is reported after the bubbled boom error."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop late sibling object completion after non-null bubbling returns a response,adapted,test/execution/cancellation_bubbling_test.dart,"Spec 18.13: the executor waits for the resolvers that already started, so the late sibling is still run and its outcome reported; the test has no abort signal. The response is the bubbled boom error."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted mid-mutation,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; cancelled while the first mutation field is pending, so the second never starts."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted pre-execute,adapted,test/execution/cancellation_test.dart,Spec 18.9: execute does not throw; a signal cancelled before the call gives a synchronous GQL350 result and no resolver runs.
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted before cancellation is wired,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; a resolver that cancels the signal and then never completes."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted prior to return of a subscription resolver,skipped,,"See report: subscribe does not race a subscribe resolver that has not returned against the signal, so the call stays pending (graphql-js answers with an error)."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should successfully wrap the subscription,ported,test/execution/cancellation_subscription_test.dart,
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during subscription,adapted,test/execution/cancellation_subscription_test.dart,"Spec 18.9: the stream delivers one last GQL350 result and closes, and the source is cancelled, where graphql-js rejects next()."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during subscription returned asynchronously,adapted,test/execution/cancellation_subscription_test.dart,"Spec 18.9: as the previous test, with a source stream that is a Future."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,ignores async iterator return errors after aborting list completion,skipped,,An async iterator as a list value is not a list value (spec 18.17); its return() is JavaScript-only.
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,ignores async iterator return promise rejections after aborting list completion,skipped,,An async iterator as a list value is not a list value (spec 18.17); its return() is JavaScript-only.
+execution/__tests__/AbortedGraphQLExecutionError-test.ts,AbortedGraphQLExecutionError,uses the original Error reason message and cause,skipped,,AbortedGraphQLExecutionError is a JavaScript-only error class; execute completes with a GQL350 result (spec 18.9).
+execution/__tests__/AbortedGraphQLExecutionError-test.ts,AbortedGraphQLExecutionError,uses the message property from non-Error reasons,skipped,,AbortedGraphQLExecutionError is a JavaScript-only error class; execute completes with a GQL350 result (spec 18.9).
+execution/__tests__/AbortedGraphQLExecutionError-test.ts,AbortedGraphQLExecutionError,stringifies reasons without a message,skipped,,AbortedGraphQLExecutionError is a JavaScript-only error class; execute completes with a GQL350 result (spec 18.9).
+execution/__tests__/AbortedGraphQLExecutionError-test.ts,AbortedGraphQLExecutionError,stringifies null reasons,skipped,,AbortedGraphQLExecutionError is a JavaScript-only error class; execute completes with a GQL350 result (spec 18.9).
+execution/__tests__/AsyncWorkTracker-test.ts,AsyncWorkTracker,works to track promises,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,promiseAllTrackOnReject,resolves like Promise.all,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,promiseAllTrackOnReject,resolves synchronous values without tracking,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,promiseAllTrackOnReject,does not add an extra microtask on fulfilled promiseAll results,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,promiseAllTrackOnReject,tracks all promises only after rejection,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,promiseAllTrackOnReject,tracks promises until they settle and catches later rejections,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,wait,returns synchronously when there is no pending async work,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,wait,waits when tracked async work is present,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,wait,keeps waiting when tracked async work is followed by more tracked async work,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/AsyncWorkTracker-test.ts,wait,does not wait for side-effect promiseAll tracking added on next microtask,skipped,,JavaScript-only: tracks promises and async iterators of the reference executor.
+execution/__tests__/cancellablePromise-test.ts,withCancellation,works to wrap a resolved promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,withCancellation,works to wrap a rejected promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,withCancellation,works to abort an already resolved promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,withCancellation,works to abort a hanging promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,withCancellation,does nothing when aborting an already settled promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,withCancellation,handles later original rejections when already aborted,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,cancellablePromise,works to wrap a resolved promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,cancellablePromise,works to wrap a rejected promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,cancellablePromise,rejects immediately when signal is already aborted,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,cancellablePromise,works to abort a hanging promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,cancellablePromise,does nothing when aborting an already settled promise,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/cancellablePromise-test.ts,cancellablePromise,handles later original rejections when already aborted,skipped,,JavaScript-only: cancellable promises over AbortSignal; Dart has CancelSignal and no promise wrapper.
+execution/__tests__/collectIteratorPromises-test.ts,collectIteratorPromises,collects promise values until completion,skipped,,JavaScript-only: collects the promises of async iterators.
+execution/__tests__/collectIteratorPromises-test.ts,collectIteratorPromises,returns collected promises when draining throws,skipped,,JavaScript-only: collects the promises of async iterators.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,emits start and end around a synchronous execute,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,"emits start, end, and async lifecycle when execute returns a promise",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,emits full async lifecycle with error when execute returns a rejected promise,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,emits once for executeSync via experimentalExecuteIncrementally,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,emits start and end around executeIgnoringIncremental,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,"emits start, error, and end when execute throws synchronously",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute root selection set diagnostics channel,emits start and end around a synchronous root selection set,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute root selection set diagnostics channel,emits the full async lifecycle when the root selection set returns a promise,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-execute-test.ts,execute root selection set diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,emits start and end around a synchronous resolver,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,emits the full async lifecycle when a resolver returns a promise,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,emits the full async lifecycle when a resolver returns a thenable,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,"emits start, error, end when a sync resolver throws",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,emits full async lifecycle with error when a resolver rejects,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,reports isDefaultResolver based on field.resolve presence,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,"serializes fieldPath lazily, joining path keys with dots",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,"reports the response key as alias, using it in fieldPath",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,"fires once per field, not per schema walk",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,emits per-field for serial mutation execution,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,observes subscribers added before the next async serial mutation field,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-resolve-test.ts,resolve diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,emits start and end for a synchronous subscription setup,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,emits the full async lifecycle when subscribe resolver returns a promise,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,emits execute root selection set events for each event with the default per-event executor,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,emits execute root selection set events for each event with a custom per-event executor,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,emits only start and end for a synchronous validation failure,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,"emits start, error, and end when subscribe throws synchronously",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,emits full async lifecycle when subscribe resolver rejects and subscribe resolves to an error result,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-subscribe-test.ts,subscribe diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-variable-coercion-test.ts,variable coercion diagnostics channel,emits start and end with the coerced variables on the result,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-variable-coercion-test.ts,variable coercion diagnostics channel,"reports coercion failures on the result, not the error channel",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-variable-coercion-test.ts,variable coercion diagnostics channel,"omits operationName and rawVariableValues for an anonymous, variable-less operation",skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/diagnostics-variable-coercion-test.ts,variable coercion diagnostics channel,stays on the fast path when nothing is subscribed,skipped,,JavaScript-only: Node diagnostics_channel events of graphql-js.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,maps over async generator,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,maps over async iterable,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,compatible with for-await-of,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,maps over async values with async function,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,allows returning early from mapped async generator,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,allows returning early from mapped async iterable,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,passes through early return from async values,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,allows throwing errors through async iterable,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,close source when mapped iterable is thrown even when the underlying source does not implement a throw method,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,waits for source handlers before actually throwing,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,"throws given reason, ignoring source throw result",skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,passes through caught errors through async generators,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,does not normally map over thrown errors,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,closes source if mapper throws an error,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,closes source if mapper rejects,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/mapAsyncIterable-test.ts,mapAsyncIterable,disposes of async generator,skipped,,JavaScript-only: mapAsyncIterable maps async iterators; subscriptions are Dart streams.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,calls function when returned,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,ignores sync errors when returned,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,ignores async errors when returned,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,tracks completion when next() rejects,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,calls function when thrown,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,ignores sync errors when thrown,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,ignores async errors when thrown,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,calls cleanup function when disposed,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,calls the abrupt-close function at most once before completion is observed,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,does not call cleanup function again when returned after completion,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,does not call cleanup function again when thrown after completion,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,does not call cleanup function again when disposed after completion,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,handles disposal when wrapped generator has no async-dispose hook,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,returns the generator itself when the `Symbol.asyncIterator` method is called,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/withConcurrentAbruptClose-test.ts,withConcurrentAbruptClose,awaits beforeThrow so an abrupt close can set the rejection reason,skipped,,JavaScript-only: closes async iterators concurrently.
+execution/__tests__/hooks-test.ts,Execute: Hooks,ignores errors thrown by hooks,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,runs post execution hooks synchronously when no async work is tracked,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,runs post execution hooks for asynchronous execution,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,ignores async-work tracker wait rejection,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,does not wait for un-awaited promiseAll helper usage before asyncWorkFinished,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,waits for track(...) helper usage before asyncWorkFinished,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,wrapper returns synchronously when asyncWorkFinished fires during execute,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,wrapper returns a promise and resolves after asyncWorkFinished for track(...) side effects,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,runs post execution hooks for aborted execution,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,fires asyncWorkFinished after async iterator return cleanup,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/hooks-test.ts,Execute: Hooks,fires asyncWorkFinished after all incremental payloads are delivered,skipped,,JavaScript-only: execution hooks of graphql-js 17 (spec 19).
+execution/__tests__/incremental-test.ts,Original execute errors on experimental @defer and @stream directives,errors when using original execute with schemas including experimental @defer directive,skipped,,Needs executeIncrementally and @defer / @stream incremental payloads (M14).
+execution/__tests__/incremental-test.ts,Original execute errors on experimental @defer and @stream directives,errors when using original execute with schemas including experimental @stream directive,skipped,,Needs executeIncrementally and @defer / @stream incremental payloads (M14).
+execution/__tests__/incremental-test.ts,Original execute errors on experimental @defer and @stream directives,original execute function throws error if anything is deferred and everything else is sync,skipped,,Needs executeIncrementally and @defer / @stream incremental payloads (M14).
+execution/__tests__/incremental-test.ts,Original execute errors on experimental @defer and @stream directives,original execute function resolves to error if anything is deferred and something else is async,skipped,,Needs executeIncrementally and @defer / @stream incremental payloads (M14).
+execution/__tests__/incremental-test.ts,Original execute errors on experimental @defer and @stream directives,original execute function throws error if anything is streamed and everything else is sync,skipped,,Needs executeIncrementally and @defer / @stream incremental payloads (M14).
+execution/__tests__/incremental-test.ts,Original execute errors on experimental @defer and @stream directives,original execute function resolves to error if anything is streamed and something else is async,skipped,,Needs executeIncrementally and @defer / @stream incremental payloads (M14).
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/cancellation_bubbling_test.dart test/execution/cancellation_subscription_test.dart test/execution/cancellation_test.dart test/mapping_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/cancellation_bubbling_test.dart packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart packages/typed_graphql_conformance/test/execution/cancellation_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/cancellation_schema.dart packages/typed_graphql_conformance/test/support/execution_port.dart
git commit -q -m "test(typed_graphql_conformance): port the cancellation suite" \
  -m "Ports graphql-js cancellation-test.ts and records the JavaScript-only execution suites of spec 19 in mapping/execution.csv." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: A subscription cancelled while its source starts

The cancellation port found that `subscribe` waited for a pending source future after cancellation. `RunCancellation.raceCancelled` makes it a prompt `SubscriptionRejected` (`GQL350` / `GQL351`) that never listens to the late stream; spec section 18 item 34 records the cancel reason difference.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`, `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`
- Test: `packages/typed_graphql_server/test/cancellation/subscription_pending_source_test.dart`, `packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart`, `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/cancellation/subscription_pending_source_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);
  const text = 'subscription { pending }';

  Future<SubscriptionResult> subscribeTo(
    Probe probe,
    ExecutionOptions options,
  ) async => fixture.subscribe(text, probe, options: options);

  SubscriptionRejected rejected(SubscriptionResult result) =>
      result is SubscriptionRejected
      ? result
      : fail('expected a rejection, got $result');

  test('a cancel while the source is pending rejects with GQL350', () async {
    final signal = CancelSignal();
    final pending = subscribeTo(
      Probe(),
      ExecutionOptions(cancelSignal: signal),
    );
    signal.cancel();
    final error = rejected(await pending.timeout(patience)).error;
    expect(CancellationFixture.codeOf(error), 'GQL350');
    expect(CancellationFixture.messageOf(error), 'Execution was cancelled.');
  });

  test('a timeout while the source is pending rejects with GQL351', () async {
    final result = await subscribeTo(
      Probe(),
      const ExecutionOptions(timeout: Duration(milliseconds: 20)),
    ).timeout(patience);
    final error = rejected(result).error;
    expect(CancellationFixture.codeOf(error), 'GQL351');
    expect(
      CancellationFixture.messageOf(error),
      'Execution timed out after 20 ms.',
    );
  });

  test('a stream that arrives after the cancel is never listened to', () async {
    final probe = Probe();
    final late = StreamController<int>();
    final signal = CancelSignal();
    final pending = subscribeTo(probe, ExecutionOptions(cancelSignal: signal));
    signal.cancel();
    await pending.timeout(patience);
    probe.pendingSource.complete(late.stream);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(late.hasListener, isFalse);
    unawaited(late.close());
  });

  test('an error that arrives after the cancel leaks nothing', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = subscribeTo(
        probe,
        ExecutionOptions(cancelSignal: signal),
      );
      signal.cancel();
      await pending.timeout(patience);
      probe.pendingSource.completeError(StateError('late'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }, (error, stackTrace) => uncaught.add(error));
    expect(uncaught, isEmpty);
  });

  test('the timer and the signal listener are released', () async {
    const watched = Duration(minutes: 5);
    final tracker = TimerTracker(watched);
    final signal = CancelSignal();
    final pending = tracker.run(
      () => subscribeTo(
        Probe(),
        ExecutionOptions(cancelSignal: signal, timeout: watched),
      ),
    );
    signal.cancel();
    await pending.timeout(patience);
    expect(tracker.created, 1);
    expect(tracker.isIdle, isTrue);
  });
}
```

In `packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -95,5 +95,26 @@ void main() {
         await source.close();
       },
     );
+    test(
+      'should stop the execution when aborted prior to return of a subscription resolver',
+      () async {
+        final started = Completer<Stream<String>>();
+        final probe = CancellationProbe()..source = () => started.future;
+        final signal = CancelSignal();
+        final pending = subscribe(probe, signal);
+        signal.cancel();
+        final result = await pending.timeout(const Duration(seconds: 2));
+        expect(result, isA<SubscriptionRejected>());
+        expect(
+          (result as SubscriptionRejected).error.toJson().toJson(),
+          {'errors': cancelled['errors']},
+        );
+        final late = StreamController<String>();
+        started.complete(late.stream);
+        await Future<void>.delayed(const Duration(milliseconds: 10));
+        expect(late.hasListener, isFalse);
+        unawaited(late.close());
+      },
+    );
   });
 }
```

In `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -28,6 +28,10 @@ final class Probe {
 
   bool isSourceCancelled = false;
 
+  /// What the `pending` subscription field's source function returns: a
+  /// future the test completes when it wants.
+  final Completer<Stream<int>> pendingSource = Completer<Stream<int>>();
+
   /// Ends the source; one nobody listened to stays pending.
   void dispose() => unawaited(source.close());
 }
@@ -109,6 +113,11 @@ final class CancellationFixture {
         t
             .field('ticks', b.int)
             .subscribe((parent, args, context, info) => context.source.stream),
+        t
+            .field('pending', b.int)
+            .subscribe(
+              (parent, args, context, info) => context.pendingSource.future,
+            ),
         t.field('held', b.int).subscribeWith<int>(
           (parent, args, context, info) => context.source.stream,
           (event, args, context, info) async {
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/subscription_pending_source_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/cancellation_subscription_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -498,7 +498,7 @@ type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals a
 type/__tests__/enumType-test.ts,Type System: Enum Values,can be introspected without error,adapted,test/execution/enum_type_test.dart,schema.toIntrospection(IntrospectionQuery.full) stands for introspectionFromSchema.
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during object field completion,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the author resolver never runs."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should provide access to the abort signal within resolvers,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; info.cancelSignal stands for getAbortSignal and is notified, and the error the resolver throws later is dropped."
-execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during object field completion with a custom error,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the custom error is kept as CancelSignal.reason and is not the error message (see report)."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during object field completion with a custom error,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; the custom error is kept as CancelSignal.reason and is not the error message (spec 18.34)."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,rejects with the aborted execution error while initial result is pending,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; AbortedGraphQLExecutionError and its abortedResult are JavaScript-only (spec 19): the result completes while the field is pending and the late value is dropped."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,throws the aborted execution error with a completed initial result in the atypical internal resolver-abort case,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; a resolver that cancels a synchronous query gets a synchronous GQL350 result with no data, where graphql-js keeps the completed data in abortedResult."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,throws the aborted execution error with an external abort while incremental initial result is still pending,skipped,,Needs executeIncrementally and @defer incremental payloads (M14); AbortedGraphQLExecutionError is JavaScript-only (spec 19).
@@ -516,7 +516,7 @@ execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop late
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted mid-mutation,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; cancelled while the first mutation field is pending, so the second never starts."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted pre-execute,adapted,test/execution/cancellation_test.dart,Spec 18.9: execute does not throw; a signal cancelled before the call gives a synchronous GQL350 result and no resolver runs.
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted before cancellation is wired,adapted,test/execution/cancellation_test.dart,"Spec 18.9: execute completes with a GQL350 result (data null) instead of rejecting with ""This operation was aborted""; a resolver that cancels the signal and then never completes."
-execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted prior to return of a subscription resolver,skipped,,"See report: subscribe does not race a subscribe resolver that has not returned against the signal, so the call stays pending (graphql-js answers with an error)."
+execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted prior to return of a subscription resolver,adapted,test/execution/cancellation_subscription_test.dart,"Spec 18.9: subscribe completes with a SubscriptionRejected carrying the GQL350 error (it rejects instead of a GQL350 result; spec 18.30); a stream the source yields later is never listened to."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should successfully wrap the subscription,ported,test/execution/cancellation_subscription_test.dart,
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during subscription,adapted,test/execution/cancellation_subscription_test.dart,"Spec 18.9: the stream delivers one last GQL350 result and closes, and the source is cancelled, where graphql-js rejects next()."
 execution/__tests__/cancellation-test.ts,Execute: Cancellation,should stop the execution when aborted during subscription returned asynchronously,adapted,test/execution/cancellation_subscription_test.dart,"Spec 18.9: as the previous test, with a source stream that is a Future."
```

In `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -86,6 +86,37 @@ final class RunCancellation {
     return completer.future;
   }
 
+  /// [pending] mapped by [onReady], or [onCancelled] as soon as the run is
+  /// cancelled. [onReady] never runs for a [pending] that completes after
+  /// the cancellation, and a late failure of it is dropped.
+  Future<T> raceCancelled<S, T>(
+    Future<S> pending,
+    T Function(S value) onReady,
+    T Function() onCancelled,
+  ) {
+    final completer = Completer<T>();
+    final detach = signal.addListener(() {
+      if (!completer.isCompleted) {
+        completer.complete(onCancelled());
+      }
+    });
+    pending.then(
+      (value) {
+        detach();
+        if (!completer.isCompleted) {
+          completer.complete(onReady(value));
+        }
+      },
+      onError: (Object error, StackTrace stackTrace) {
+        detach();
+        if (!completer.isCompleted) {
+          completer.completeError(error, stackTrace);
+        }
+      },
+    );
+    return completer.future;
+  }
+
   /// Ends the timer and stops listening to the caller's signal.
   void dispose() {
     _timer?.cancel();
```

In `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,6 +8,7 @@ import 'execution_options.dart';
 import 'execution_run.dart';
 import 'operation_preparation.dart';
 import 'prepared_operation.dart';
+import 'run_cancellation.dart';
 import 'schema_bindings.dart';
 import 'subscription_responses.dart';
 
@@ -70,9 +71,25 @@ final class SubscriptionExecution {
       return _rejected(run);
     }
     final opened = run.fields.openSource(_options.rootValue, fields.first);
-    return opened is Future<Stream<Object?>?>
-        ? opened.then((source) => _started(run, source))
-        : _started(run, opened);
+    if (opened is! Future<Stream<Object?>?>) {
+      return _started(run, opened);
+    }
+    // A source that is still pending when the run is cancelled must not
+    // keep `subscribe` pending (graphql-js's cancellation test); a stream
+    // it yields later is never listened to.
+    return switch (run.cancellation) {
+      final cancellation? => cancellation.raceCancelled(
+        opened,
+        (source) => _started(run, source),
+        () => _cancelled(cancellation),
+      ),
+      null => opened.then((source) => _started(run, source)),
+    };
+  }
+
+  SubscriptionRejected _cancelled(RunCancellation entry) {
+    entry.dispose();
+    return SubscriptionRejected(RequestErrorResult(errors: [entry.error]));
   }
 
   SubscriptionResult _started(ExecutionRun run, Stream<Object?>? source) =>
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/subscription_pending_source_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/cancellation_subscription_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -701,6 +701,10 @@ depends on the other). These constraints keep that possible:
     other root takes a value of its Dart type. A guide shows how to declare a
     root that needs none (`introspection_test.dart`,
     `union_interface_test.dart`).
+34. `CancelSignal.cancel(reason)` keeps the reason in `CancelSignal.reason`;
+    the `GQL350` message is always "Execution was cancelled.", where
+    graphql-js surfaces the abort reason's message
+    (`cancellation_test.dart`).
 
 ## 19. Conformance (R0.7, R10.3)
 
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/cancellation_subscription_test.dart packages/typed_graphql_server/lib/src/execution/run_cancellation.dart packages/typed_graphql_server/lib/src/execution/subscription_execution.dart packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart packages/typed_graphql_server/test/cancellation/subscription_pending_source_test.dart
git commit -q -m "fix(typed_graphql_server): reject a subscription cancelled while its source starts" \
  -m "subscribe raced only an already cancelled signal; a pending source future kept it pending. It now completes with SubscriptionRejected (GQL350 or GQL351) and never listens to a stream that arrives later. Adds spec 18.34." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Executor benchmarks

Add `benchmark/execution_benchmark.dart` (synchronous and asynchronous rows, nested fragments, full introspection; ops/s and RSS growth) and a smoke test that runs each scenario once.

**Files:**
- Create: `packages/typed_graphql_conformance/benchmark/execution_benchmark.dart`
- Modify: `packages/typed_graphql_conformance/README.md`
- Test: `packages/typed_graphql_conformance/test/benchmark/execution_benchmark_test.dart`

**Interfaces:**
- Consumes: the server as left by Task 6.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/benchmark/execution_benchmark_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../benchmark/execution_benchmark.dart';

void main() {
  const benchmark = ExecutionBenchmark();

  for (final scenario in benchmark.scenarios()) {
    test('${scenario.name} runs once without errors', () async {
      final payload = await scenario.run();
      expect(payload.errors, isEmpty);
      expect(payload, isA<ExecutionResult>());
    });
  }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/benchmark/execution_benchmark_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_conformance/benchmark/execution_benchmark.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// One measured operation: a [name] and a [run] that executes it.
typedef BenchmarkScenario = ({
  String name,
  FutureOr<ResponsePayload> Function() run,
});

/// A node of the tree the nested scenario reads.
final class BenchmarkNode {
  const BenchmarkNode(this.id, this.children);

  final int id;
  final List<BenchmarkNode> children;
}

/// The executor benchmark of M5 (spec 14, R4.17); run it by hand, see the
/// package README. Each scenario builds its schema and document once, so a
/// run measures execution only.
final class ExecutionBenchmark {
  const ExecutionBenchmark();

  static const int _rowCount = 1000;
  static const int _fieldCount = 10;
  static const int _treeDepth = 4;
  static const int _treeBreadth = 5;

  /// Every scenario, in the order the benchmark prints them.
  List<BenchmarkScenario> scenarios() => [
    syncRows(),
    asyncRows(),
    nestedFragments(),
    introspection(),
  ];

  /// A query of 1000 objects with 10 synchronous fields each.
  BenchmarkScenario syncRows() => _rows('sync rows', isAsync: false);

  /// The same query with resolvers that return futures.
  BenchmarkScenario asyncRows() => _rows('async rows', isAsync: true);

  /// A tree of 781 nodes read through a fragment at five levels.
  BenchmarkScenario nestedFragments() {
    final b = ExecutableSchemaBuilder<Object?>();
    // Assigned right below; the field list is built on first use, after it.
    late final ObjectTypeDef<BenchmarkNode> node;
    node = b.object<BenchmarkNode>(
      'Node',
      fields: (t) => [
        t.field('id', b.int).pure((value) => value.id),
        t.field('name', b.string).pure((value) => 'node ${value.id}'),
        t.field('children', b.list(node)).pure((value) => value.children),
      ],
    );
    final tree = _tree(_treeDepth);
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('tree', node).pure((_) => tree),
        ],
      ),
    );
    var selection = '...Fields';
    for (var level = 0; level < _treeDepth; level++) {
      selection = '...Fields children { $selection }';
    }
    final text =
        'query { tree { $selection } } '
        'fragment Fields on Node { id name }';
    return _scenario('nested fragments', schema, text);
  }

  /// The full introspection query against a schema of 40 object types.
  BenchmarkScenario introspection() {
    final b = ExecutableSchemaBuilder<Object?>();
    final types = [
      for (var typeIndex = 0; typeIndex < 40; typeIndex++)
        b.object<Object?>(
          'Type$typeIndex',
          description: 'The type number $typeIndex.',
          fields: (t) => [
            for (var index = 0; index < _fieldCount; index++)
              t.field('field$index', b.string.nullable).pure((_) => 'value'),
          ],
        ),
    ];
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          for (var index = 0; index < types.length; index++)
            t.field('type$index', types[index].nullable).pure((_) => null),
        ],
      ),
    );
    return _scenario('introspection', schema, IntrospectionQuery.full.text);
  }

  /// Warms [scenario] up, runs it for [duration] and prints operations per
  /// second and the growth of the resident set.
  Future<void> measure(
    BenchmarkScenario scenario, {
    Duration duration = const Duration(seconds: 3),
  }) async {
    for (var index = 0; index < 20; index++) {
      await scenario.run();
    }
    final rssBefore = ProcessInfo.currentRss;
    final stopwatch = Stopwatch()..start();
    var count = 0;
    while (stopwatch.elapsed < duration) {
      await scenario.run();
      count++;
    }
    final seconds = stopwatch.elapsedMicroseconds / 1000000;
    final growth = (ProcessInfo.currentRss - rssBefore) / (1024 * 1024);
    stdout.writeln(
      '${scenario.name.padRight(18)} '
      '${(count / seconds).toStringAsFixed(1).padLeft(10)} ops/s  '
      'RSS growth ${growth.toStringAsFixed(1)} MiB',
    );
  }

  BenchmarkScenario _rows(String name, {required bool isAsync}) {
    final b = ExecutableSchemaBuilder<Object?>();
    final row = b.object<int>(
      'Row',
      fields: (t) => [
        for (var index = 0; index < _fieldCount; index++)
          if (isAsync)
            t
                .field('field$index', b.int)
                .resolve(
                  (value, args, context, info) => Future.value(value + index),
                )
          else
            t.field('field$index', b.int).pure((value) => value + index),
      ],
    );
    final rows = List<int>.generate(_rowCount, (index) => index);
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('rows', b.list(row)).pure((_) => rows),
        ],
      ),
    );
    final selection = [
      for (var index = 0; index < _fieldCount; index++) 'field$index',
    ].join(' ');
    return _scenario(name, schema, '{ rows { $selection } }');
  }

  BenchmarkScenario _scenario(
    String name,
    ExecutableSchema<Object?> schema,
    String text,
  ) {
    final document = ValidDocument.assumeValid(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    );
    return (name: name, run: () => schema.execute(document, context: null));
  }

  BenchmarkNode _tree(int remaining) {
    // Ids need not be unique: the benchmark reads values, it never compares.
    return BenchmarkNode(remaining, [
      if (remaining > 0)
        for (var index = 0; index < _treeBreadth; index++) _tree(remaining - 1),
    ]);
  }
}

Future<void> main() async {
  stdout.writeln('Dart ${Platform.version.split(' ').first}');
  const benchmark = ExecutionBenchmark();
  for (final scenario in benchmark.scenarios()) {
    await benchmark.measure(scenario);
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/benchmark/execution_benchmark_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -61,6 +61,24 @@ never throws; `hostile_shape_fuzz_test.dart` validates documents of hostile
 shapes (deep, wide, exponentially expanding, cyclic) and checks that each
 run ends within ten seconds and that exponential merging gives `GQL230`.
 
+## Benchmarks
+
+`benchmark/execution_benchmark.dart` measures the executor (R4.17): a
+synchronous query of 1 000 objects with 10 fields each, the same with
+asynchronous resolvers, a nested query with fragments, and the full
+introspection query against a schema of 40 types. For each it prints
+operations per second and the growth of the resident set
+(`ProcessInfo.currentRss`) over a three-second run after a warm-up. It runs
+by hand, not in CI; keep the memory limit and the timeout:
+
+```sh
+cd packages/typed_graphql_conformance
+ulimit -v 8000000; timeout 600 dart run benchmark/execution_benchmark.dart
+```
+
+`test/benchmark/execution_benchmark_test.dart` runs each scenario once and
+checks that the response has no errors.
+
 ## License
 
 MIT — see [LICENSE](LICENSE). The ported tests derive from graphql-js,
````

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/benchmark/execution_benchmark.dart packages/typed_graphql_conformance/test/benchmark/execution_benchmark_test.dart
git commit -q -m "test(typed_graphql_conformance): benchmark the executor" \
  -m "Run on Dart 3.13.5 (3 s per scenario after a 20-run warm-up):
sync rows (1000 x 10 fields):  332.9 ops/s, RSS growth 0.0 MiB
async rows (same, futures):     60.2 ops/s, RSS growth -16.7 MiB
nested fragments (781 nodes): 1432.6 ops/s, RSS growth 0.0 MiB
introspection (40 types):      434.0 ops/s, RSS growth 0.4 MiB" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: The deviations in the spec

Record the M5d behaviour differences in section 18 (items 35-42).

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-m5-execution-design.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -705,6 +705,30 @@ depends on the other). These constraints keep that possible:
     the `GQL350` message is always "Execution was cancelled.", where
     graphql-js surfaces the abort reason's message
     (`cancellation_test.dart`).
+35. `SelectedField.isDeferred` (section 11) is not in M5: no `@defer` is
+    executed, so it would always be false. It arrives with incremental
+    delivery.
+36. `SelectedField.arguments` reads an argument whose value fails coercion
+    as absent. Reading a required one then throws, which the resolver's
+    error masking turns into `GQL330`; the executor reports the real
+    coercion error when that field runs, so no problem is silent.
+37. Look-ahead hides every meta field (a name starting with `__`), not only
+    `__typename`.
+38. The executor races the pending result against cancellation once, at the
+    root, and checks `isCancelled` before it starts each field. A resolver
+    already running is not interrupted; its result is dropped.
+39. Request errors win over an already-cancelled signal: an unknown
+    operation or unusable variables are a `RequestErrorResult`, and no timer
+    starts for them.
+40. `GQL304` is one diagnostic that lists every guarded field as
+    `Type.field`, not one diagnostic per field.
+41. An object field that redeclares an interface field does not inherit the
+    interface field's authorization rule: the rule guards the
+    implementations that inherit the field.
+42. A subscription response stream that is never listened to keeps its
+    listener on the caller's `CancelSignal` until that signal is cancelled;
+    the listener attaches on `listen`, the timeout timer starts at
+    `subscribe`. The guide says to listen to the stream or drop the signal.
 
 ## 19. Conformance (R0.7, R10.3)
 
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md
git commit -q -m "docs: record the M5d deviations in the M5 spec" \
  -m "Spec section 18 items 35-42: no isDeferred, failing look-ahead arguments read absent, meta fields hidden, cancellation raced once at the root, request errors win over a cancelled signal, one GQL304 diagnostic, a redeclared interface field is not guarded, an unlistened subscription keeps its signal listener." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: The Look-ahead, Authorization and Cancellation guides

Complete the three guides and close stage M5 in the README, `llms.txt`, `docs/discovery.md`, the root README, `CLAUDE.md` (Server paragraph, Status, Learned in M5) and HANDOFF.

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/discovery.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql_server/README.md`, `packages/typed_graphql_server/doc/authorization.md`, `packages/typed_graphql_server/doc/cancellation.md`, `packages/typed_graphql_server/doc/lookahead.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -55,7 +55,13 @@ example. M5c (introspection and subscriptions) delivers the `__schema` and
 `__type` resolvers, `IntrospectionPolicy` (`GQL338`), `subscribe` with its
 source streams and rejected requests (`GQL324`, `GQL340`), the graphql-js
 introspection and subscribe suites, and the Introspection and Subscriptions
-guides. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+guides. M5d (look-ahead, authorization, cancellation) delivers
+`FieldInfo.selection` (`FieldSelection`, `SelectedField`, `ColumnWhitelist`),
+`Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`,
+`GQL352`), `CancelSignal` with `ExecutionOptions.cancelSignal` and `timeout`
+(`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor
+benchmark and the Look-ahead, Authorization and Cancellation guides; with it
+stage M5 (execution) is complete. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
 file or a URL, the project's documents as one fragment graph, the planner and
 emitters that generate the schema-types library and a library per document
 (operations, variables, data, fragments, sealed polymorphic classes, the
@@ -412,8 +418,8 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 only through its barrel. One folder per concern, with no import order
 (`builder/` and `execution/` import each other): `builder/` (M5a),
 `coercion/`, `plan/` and `execution/` (M5b), `introspection/` and
-`subscription/` (M5c), then `lookahead/`, `authorization/` and `cancellation/`
-in later sub-stages. The package is
+`subscription/` (M5c), `lookahead/`, `authorization/` and `cancellation/`
+(M5d). The package is
 transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
 or web framework, only `dart:async`, `dart:collection`, `dart:core`,
 `dart:math`, `meta` and the core (`test/quality/imports_test.dart`), and the
@@ -456,6 +462,31 @@ latter); `execution/SubscriptionExecution` prepares the operation once
 order, pausing the source meanwhile; a source that fails after listening is the
 last result (`GQL340`), one that fails at start is a `SubscriptionRejected`.
 `subscription/` holds only the public `SubscriptionResult` family.
+`lookahead/` (M5d): `FieldInfo.selection` is a `FieldSelection` built on first
+read from the field's `FieldPlan`s and the run's variables
+(`FieldInfo.selectionReader` is `@internal`); `SelectionNodes` flattens
+fragments and applies `@skip`/`@include`, `forType` narrows an abstract type,
+every name starting with `__` is hidden. A `SelectedField` reads its
+`arguments` on first use (a failing argument reads absent; the executor
+reports it) and has its own `selection`. `SelectionFingerprint` (field names
+sorted, arguments as `CanonicalJson` with sorted keys, explicit stacks) is the
+DataLoader key; `ColumnWhitelist` maps field names to sorted columns.
+`authorization/` (M5d): `Authorization` is sealed (`public`, `requires`); a
+rule is set by `FieldStub.withAuthorization` or `ObjectOptions.authorization`
+(the field's own wins) and applied after middleware composition by
+`builder/AuthorizationApplier` and `FieldGuard`, which wrap the composed lane
+so the `Authorizer<C>` (in `BuildOptions.authorizer`) runs before middleware
+on every lane, a pure field included. A deny is `GQL352`, a missing authorizer
+one `GQL304` listing the coordinates; introspection fields are never guarded;
+a redeclared interface field does not inherit the interface's rule.
+`AuthorizationCoverage` lists unguarded fields for a test.
+`cancellation/` (M5d): `CancelSignal` is the caller's plain class (no
+platform import); `execution/RunCancellation` links it with the timeout into
+the run's signal (`FieldInfo.cancelSignal`) when `OperationPreparation` has no
+request error, and disposes the timer and the listener when the run ends.
+`ExecutionRun.executeRoot` races the pending result against it once and
+`FieldExecution` starts no field after it fires (`GQL350`, `GQL351`); a
+subscription keeps the timer from `subscribe` and the listener from `listen`.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
@@ -635,6 +666,24 @@ Learned in M4b:
 - graphql-js test names may be double-quoted in the source; the suite
   reader handles both quotes.
 
+Learned in M5:
+- A field typed with a class parameter in a function position (`P` in a
+  `resolveType` or lane that takes `Object?`) is contravariant: reading it
+  through `Foo<Object?>` throws a `TypeError`. Take `Object?` in lanes and cast
+  inside the definition, or expose `hasX`/`untypedX`.
+- A synchronous broadcast source can deliver inside `listen`, so state a
+  listener reads must be set before `listen`, and a paused subscription
+  buffers without bound.
+- Tests that spawn `dart` through `Platform.resolvedExecutable` break under
+  `--compiler exe` (it is the test binary): skip them there.
+- A pending future must be raced against cancellation, or `execute` waits for
+  the slowest resolver; check the signal before each field too.
+- A change to the core goes in its own commit, before the commit of the server
+  that needs it.
+- A guide program formats with `dart format`: `final x = F({...}, a: b)`
+  may become one argument per line; run the formatter on the fence before
+  trusting the guide test.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -27,8 +27,9 @@ What works today: the language (parse, print, visit and transform queries and
 SDL), the schema (build it from SDL, extend, print and validate it, introspection
 both ways, schema coordinates), operation validation, the wire protocol types,
 scalar codecs and the diagnostics model; and, in `typed_graphql_server`, a
-typed schema builder, the execution of a validated operation, introspection
-and subscriptions.
+typed schema builder, the execution of a validated operation, introspection,
+subscriptions, look-ahead at the requested fields, field authorization and
+cancellation.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
@@ -111,12 +112,12 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection and subscriptions (M5a-M5c) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization and cancellation (M5, complete) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
-| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema, introspection, validation and execution suites, fuzzers (M2-M5b) |
+| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema, introspection, validation and execution suites, fuzzers, benchmarks (M2-M5) |
 
 ## Install
 
````

In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,6 +42,9 @@ adds its row (or turns it to "yes") together with its README line and its
 | execute a GraphQL query dart | M5 | yes |
 | GraphQL introspection server dart | M5 | yes |
 | GraphQL subscriptions server dart | M5 | yes |
+| GraphQL look-ahead requested fields dart | M5 | yes |
+| authorize GraphQL fields dart | M5 | yes |
+| cancel or time out a GraphQL request dart | M5 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
 
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M10 complete on branch `m10-final`, awaiting merge (not merged); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
+Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M5 (a-d) complete on branch `m5-final`, not merged; M10 complete on branch `m10-final`, awaiting merge (not merged); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
@@ -16,7 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
-| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; next is M5d (look-ahead, authorization, cancellation) |
+| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; M5d is done on the same branch: `FieldInfo.selection` (look-ahead, `ColumnWhitelist`), `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`, `GQL352`), `CancelSignal`, `timeout` and `FieldInfo.cancelSignal` (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor benchmark, spec §18 items 34-42 and the Look-ahead, Authorization and Cancellation guides. **Stage M5 is complete on `m5-final`; it is not merged and not pushed.** Next: the M5d plan (regenerated from the commits like the earlier plans) and the final whole-branch review, then the merge. Open questions for the owner are in `.superpowers/m5-open-questions.md` (local, untracked, in the worktree) |
 | M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete on branch `m10-final`: the final opus whole-branch review is done and its fix round is committed; awaiting merge, not merged and not pushed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries and runs subscriptions over event streams; its look-ahead, authorization and cancellation (M5d) and transports (stages M6, M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries, runs subscriptions over event streams, lets a resolver look ahead at the fields a request selected, guards fields with an authorizer and stops a request with a cancel signal or a timeout; DataLoader and the request pipeline (M6) and the transports (M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection and Subscriptions in its doc folder, runnable example in its example folder); introspection resolvers and subscriptions work; look-ahead, authorization and cancellation (M5d) and transport handlers (M6, M7) come later
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection, Subscriptions, Look-ahead, Authorization and Cancellation in its doc folder, runnable example in its example folder); introspection resolvers, subscriptions, look-ahead, authorization and cancellation work; DataLoader and the request pipeline (M6) and transport handlers (M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

In `packages/typed_graphql_server/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,14 +6,16 @@
 
 **A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: under construction.** The typed schema builder (M5a), query
-> execution (M5b), introspection and subscriptions (M5c) work: you can declare
-> a schema in typed Dart code, parse and validate a request with the core, and
+> **Status: under construction.** Stage M5 is complete. The typed schema
+> builder (M5a), query execution (M5b), introspection and subscriptions (M5c),
+> look-ahead, authorization and cancellation (M5d) work: you can declare a
+> schema in typed Dart code, parse and validate a request with the core, and
 > execute it, with variables, specified null propagation, error behaviours,
-> masking and field middleware, answer introspection queries and run a
-> subscription over a stream of events. Look-ahead, authorization and
-> cancellation arrive in M5d; the request pipeline and the HTTP, graphql-ws and
-> graphql-sse handlers later. See the
+> masking and field middleware, answer introspection queries, run a
+> subscription over a stream of events, read which fields a request selected
+> under a field, guard fields with an authorizer and stop a request with a
+> cancel signal or a timeout. DataLoader and the request pipeline come in M6,
+> the HTTP, graphql-ws and graphql-sse handlers in M7. See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
 ## Contents
@@ -47,7 +49,7 @@ dependencies:
 - **You do not need it when** you only call a GraphQL server: that is the
   client package, not usable yet. Today it also has no HTTP or
   WebSocket handler: you call `ExecutableSchema.execute` or `subscribe`
-  yourself with a parsed and validated document.
+  yourself with a parsed and validated document (the handlers are M6 and M7).
 - **What it replaces**: resolvers written against `Map<String, dynamic>`, where
   a wrong result type or a misspelled argument name fails at run time in the
   middle of a request. Here the wrong type does not compile, and every error
@@ -140,6 +142,12 @@ It prints:
   answer as the core, `IntrospectionPolicy`, root types without a root value.
 - [Subscriptions](doc/subscriptions.md): source streams, one event at a time,
   rejected and failed subscriptions.
+- [Look-ahead](doc/lookahead.md): the fields a request selected under a field,
+  `fingerprint` as a DataLoader key, `ColumnWhitelist`.
+- [Authorization](doc/authorization.md): rules on fields and types, the
+  `Authorizer`, deny messages, `AuthorizationCoverage`.
+- [Cancellation](doc/cancellation.md): `CancelSignal`, timeouts, what
+  resolvers and subscriptions see.
 
 ## License
 
```

In `packages/typed_graphql_server/doc/authorization.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,6 +1,7 @@
 # Authorization
 
-A field can carry an `Authorization` rule: `Authorization.requires(['admin'])`
+The builder does not decide who may read a field; it gives every field a place
+to say what it needs and calls one hook to check it. A field can carry an `Authorization` rule: `Authorization.requires(['admin'])`
 names what the caller needs, `Authorization.public()` says anyone may read it.
 The rule is data. An `Authorizer<C>`, given to `build` in
 `BuildOptions.authorizer`, decides what the requirements mean and answers
@@ -69,10 +70,154 @@ It prints:
 
 A deny is a field error with the code `GQL352` and the message
 `Not authorized to access Type.field.`, or the message given to `Deny`; null
-propagates as for any field error. An exception thrown by the authorizer is
-masked like a resolver's and reaches `ExecutionOptions.onError`.
+propagates as for any field error, so guard a field that may be absent with a
+nullable type. An exception thrown by the authorizer is masked like a
+resolver's and reaches `ExecutionOptions.onError`. A denied field never runs
+its resolver or its middleware.
 
-`SelectedField.authorization` tells a look-ahead which rule applies to a field.
-`AuthorizationCoverage(schema).uncovered` lists the fields with no rule on the
-field or its type, introspection excluded, sorted; assert it is empty in an
-application's tests so a new field cannot ship unguarded.
+## Type rules, field rules and public fields
+
+A rule on an object type (`ObjectOptions.authorization`) covers every field of
+the type that has none of its own. A field's own rule replaces it, and
+`Authorization.public()` opts a field out of the type's rule: the authorizer is
+not asked. Introspection fields are never guarded.
+
+A rule on an interface field guards the implementations that inherit the field.
+An object that redeclares the field does not inherit the interface's rule: give
+it its own, or its type's.
+
+## Asynchronous decisions and deny messages
+
+`authorize` returns a `FutureOr`, so an authorizer may look the answer up in a
+database or a token service; a synchronous answer costs no `Future`. `Deny`
+takes an optional message for the client; keep it free of details an attacker
+could use.
+
+```dart
+import 'dart:async';
+import 'dart:convert';
+
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+final class Lookup implements Authorizer<Set<String>> {
+  @override
+  FutureOr<AuthorizationDecision> authorize(
+    FieldAccess<Set<String>> access,
+  ) async {
+    await Future<void>.delayed(Duration.zero);
+    final missing = access.requirements.where(
+      (role) => !access.context.contains(role),
+    );
+    return missing.isEmpty
+        ? const Allow()
+        : Deny(message: 'Missing role: ${missing.join(', ')}.');
+  }
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Set<String>>();
+  final account = b.object<Object?>(
+    'Account',
+    fields: (t) => [
+      t
+          .field('id', b.string)
+          .withAuthorization(Authorization.public())
+          .pure((_) => 'a-1'),
+      t.field('balance', b.int.nullable).pure((_) => 120),
+      t
+          .field('audit', b.string.nullable)
+          .withAuthorization(Authorization.requires(['admin']))
+          .pure((_) => 'clean'),
+    ],
+    options: ObjectOptions(authorization: Authorization.requires(['owner'])),
+  );
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('account', account).pure((_) => const Object())],
+  );
+  final schema = b.build(
+    query: query,
+    options: BuildOptions<Set<String>>(authorizer: Lookup()),
+  );
+  print(AuthorizationCoverage(schema).uncovered);
+
+  final document = const Parser()
+      .parse(Source('{ account { id balance audit } }'))
+      .requireDocument();
+  final result = await schema.execute(
+    ValidDocument.assumeValid(schema.schema, document),
+    context: {'owner'},
+  );
+  print(jsonEncode((result as ExecutionResult).toJson().toJson()));
+}
+```
+
+It prints:
+
+```text
+[Query.account]
+{"errors":[{"message":"Missing role: admin.","path":["account","audit"],"extensions":{"code":"GQL352"}}],"data":{"account":{"id":"a-1","balance":120,"audit":null}}}
+```
+
+`id` is public, `balance` takes the type's rule `owner`, and `audit` its own
+rule `admin`. `SelectedField.authorization` gives a look-ahead the rule that
+applies to a field, so a resolver can skip loading what the caller may not
+read.
+
+## Checking coverage in a test
+
+`AuthorizationCoverage(schema).uncovered` lists, sorted, the coordinates
+(`Type.field`) of the fields that have no rule on the field or on its type.
+`public` counts as a rule: the decision is explicit. Introspection fields are
+excluded. The program above prints `Query.account`, the root field nobody
+guarded. Assert that the list is empty in the application's tests, with the
+public entry points marked `public`, so that a new field cannot ship without
+a decision:
+
+```text
+test('every field has an authorization rule', () {
+  expect(AuthorizationCoverage(schema).uncovered, isEmpty);
+});
+```
+
+## A rule without an authorizer
+
+A rule is data until an authorizer reads it. A build with a field that needs
+the authorizer (`Authorization.requires`) and no `BuildOptions.authorizer`
+fails with one `GQL304` diagnostic that lists every such field, so a missing
+hook is never a silently open schema. A `public` rule needs no authorizer.
+
+```dart
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+void main() {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t
+          .field('a', b.string)
+          .withAuthorization(Authorization.requires(['x']))
+          .pure((_) => 'a'),
+      t
+          .field('b', b.string)
+          .withAuthorization(Authorization.requires(['y']))
+          .pure((_) => 'b'),
+    ],
+  );
+  try {
+    b.build(query: query);
+  } on SchemaBuildError catch (error) {
+    print(error.diagnostics.length);
+    print(error.diagnostics.single.message);
+  }
+}
+```
+
+It prints:
+
+```text
+1
+Fields are guarded by an authorization rule but the build has no authorizer (BuildOptions.authorizer): Query.a, Query.b.
+```
````

In `packages/typed_graphql_server/doc/cancellation.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,6 +1,8 @@
 # Cancellation
 
-A request can be stopped from outside with a `CancelSignal`, or by a time
+Work nobody waits for any more should stop: a client that disconnected, a
+request that took too long. The executor cannot know either, so the caller
+tells it. A request can be stopped from outside with a `CancelSignal`, or by a time
 limit. `CancelSignal` is a plain class the caller creates and cancels: it has
 no tie to a transport, so an HTTP handler that sees the client leave, a
 WebSocket handler that receives a stop message and a test all use it the same
@@ -75,8 +77,91 @@ A signal that is already cancelled gives the cancelled result without running
 a resolver. Request errors win over it: an unknown operation or unusable
 variables are `RequestErrorResult`s whatever the signal says.
 
+## One signal per request
+
+Make a `CancelSignal` for each request, not one for the server: cancelling it
+ends only that request. The caller owns the signal. The executor listens to
+it and never cancels it, and it removes its listener when the run ends, so a
+signal may outlive many runs. A transport that hosts the executor creates the
+signal when it accepts a request and cancels it when the connection closes or
+a stop message arrives; the timeout is a safety net for requests nobody
+cancels.
+
+## What a resolver sees
+
+`FieldInfo.cancelSignal` is the run's own signal, not the caller's. Without a
+signal or a timeout it is a signal that never fires. The executor races the
+pending result against the signal once, at the root, and checks `isCancelled`
+before it starts each field, so after a cancellation no new resolver runs. A
+resolver that already runs is not interrupted: it should check `isCancelled`
+between steps or race its work against `whenCancelled`, as the first program
+does. What it returns afterwards is dropped.
+
+## Subscriptions
+
 For `ExecutableSchema.subscribe` the signal and the timeout last as long as
 the subscription. When one fires, the stream delivers one last result with the
 cancellation error, the source subscription is cancelled and the stream
 closes; the event being executed is dropped. A signal already cancelled at
-`subscribe` gives a `SubscriptionRejected` with `GQL350`.
+`subscribe` gives a `SubscriptionRejected` with `GQL350`. The timeout starts
+at `subscribe`; the listener on the caller's signal attaches when the response
+stream is listened to.
+
+```dart
+import 'dart:async';
+
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
+  );
+  final source = StreamController<String>();
+  final subscription = b.object<Object?>(
+    'Subscription',
+    fields: (t) => [
+      t
+          .field('news', b.string)
+          .subscribe((parent, args, context, info) => source.stream),
+    ],
+  );
+  final schema = b.build(query: query, subscription: subscription);
+  final document = ValidDocument.assumeValid(
+    schema.schema,
+    const Parser().parse(Source('subscription { news }')).requireDocument(),
+  );
+
+  final signal = CancelSignal();
+  final started = await schema.subscribe(
+    document,
+    context: null,
+    options: ExecutionOptions(cancelSignal: signal),
+  );
+  if (started case SubscriptionStarted(:final results)) {
+    final done = results.forEach((result) => print(result.toJson()));
+    source.add('first');
+    await Future<void>.delayed(Duration.zero);
+    signal.cancel();
+    await done;
+    print('source cancelled: ${!source.hasListener}');
+  }
+}
+```
+
+It prints:
+
+```text
+{"data":{"news":"first"}}
+{"errors":[{"message":"Execution was cancelled.","extensions":{"code":"GQL350"}}],"data":null}
+source cancelled: true
+```
+
+## Listen to the stream, or drop the signal
+
+A response stream that is never listened to has already called the source
+function and holds a listener on the caller's signal until that signal is
+cancelled. Listen to the stream, or cancel the signal, as soon as you decide
+not to use the subscription; a signal per request makes the second free.
````

In `packages/typed_graphql_server/doc/lookahead.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,41 +1,88 @@
 # Look-ahead
 
-A resolver can see which fields the request selected under its own field, so
-it can load only those: `FieldInfo.selection` is a `FieldSelection`, a view
-of the operation plan with fragments flattened, `@skip` and `@include`
-applied and `__typename` left out. Nothing is collected until a member is
-read.
+A resolver often loads more than the request needs: every column of a row,
+every relation of an entity. Look-ahead lets it read, before it loads, which
+fields the request selected under its own field. `FieldInfo.selection` is a
+`FieldSelection`, a view of the operation plan with the request's variables:
+fragments are flattened, `@skip` and `@include` are applied, and meta fields
+(`__typename` and every other name that starts with `__`) are left out.
+Nothing is collected until a member is read, so a resolver that never asks
+pays nothing. The guide builds on the Schema Builder and Execution guides.
+
+## Reading the selection
+
+`fields` lists the `SelectedField`s in collection order, one per response key.
+A `SelectedField` has the schema `name`, the `responseKey`, the `alias` (null
+when the request gave none), its `arguments` and its own `selection`, which is
+empty for a leaf.
+
+`has('posts.title')` tests a path of field names, never aliases, through the
+nested selections. `fieldsNamed('posts')` lists every occurrence of a name, so
+two aliases of one field give two entries.
+
+`SelectedField.arguments` is an `Arguments`, read with the same `Arg` that
+declared the argument. The variables are substituted and the defaults applied
+when it is first read.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
-void main() {
+Future<void> main() async {
   final b = ExecutableSchemaBuilder<Object?>();
+  final post = b.object<Object?>(
+    'Post',
+    fields: (t) => [t.field('title', b.string).pure((_) => 'A post')],
+  );
+  final first = Arg('first', b.int, defaultValue: 10);
   final user = b.object<Object?>(
     'User',
     fields: (t) => [
       t.field('name', b.string).pure((_) => 'Ada'),
       t.field('email', b.string).pure((_) => 'ada@example.com'),
+      t
+          .field('posts', b.list(post), args: [first])
+          .resolve((parent, args, context, info) => const []),
     ],
   );
   final query = b.object<Object?>(
     'Query',
     fields: (t) => [
       t.field('me', user).resolve((parent, args, context, info) {
-        print(info.selection.has('email'));
-        print(info.selection.fingerprint);
-        return null;
+        final selection = info.selection;
+        print([for (final field in selection.fields) field.responseKey]);
+        print(selection.has('email'));
+        print(selection.has('posts.title'));
+        for (final posts in selection.fieldsNamed('posts')) {
+          print('posts(first: ${posts.arguments.get(first)})');
+        }
+        return const Object();
       }),
     ],
   );
   final schema = b.build(query: query);
   final document = const Parser()
-      .parse(Source('{ me { name email } }'))
+      .parse(
+        Source('''
+query Page(\$withEmail: Boolean!) {
+  me {
+    __typename
+    writer: name
+    ...Contact
+    posts(first: 3) { title }
+  }
+}
+
+fragment Contact on User {
+  email @include(if: \$withEmail)
+}
+'''),
+      )
       .requireDocument();
-  schema.execute(
+  await schema.execute(
     ValidDocument.assumeValid(schema.schema, document),
     context: null,
+    variables: JsonObject({'withEmail': JsonBool(false)}),
   );
 }
 ```
@@ -43,14 +90,98 @@ void main() {
 It prints:
 
 ```text
+[writer, posts]
+false
 true
+posts(first: 3)
+```
+
+The fragment `Contact` is flattened into `me`, but `@include(if: false)`
+removes its only field, and `__typename` never shows.
+
+## Abstract types
+
+Under a field of an interface or union type, `fields` holds what every
+possible type collects, merged by response key in possible-type order.
+`forType(name)` narrows the view to one object type: the fields that apply to
+it, including those from `... on Name` fragments. An unknown name, or a type
+that cannot occur there, gives an empty selection.
+
+## A key for a DataLoader
+
+`fingerprint` is a canonical text of the selection: the field names (not the
+aliases) sorted, the arguments written as JSON of the coerced values with the
+object keys sorted, the children nested. Two selections that ask for the same
+fields with the same arguments have the same fingerprint, whatever the order,
+the aliases or the fragments of their requests. Use it as a cache or
+DataLoader key, so that a batch is shared only between requests that want the
+same data. It is built with an explicit stack, so a deep selection cannot
+overflow the stack.
+
+`ColumnWhitelist` turns a selection into database columns. It maps field
+names to columns, adds the `always` columns (a key, say), ignores the fields
+it does not know and returns the sorted, de-duplicated list. It preloads
+nothing and writes no SQL: the resolver builds the query.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final user = b.object<Object?>(
+    'User',
+    fields: (t) => [
+      t.field('id', b.id).pure((_) => '1'),
+      t.field('name', b.string).pure((_) => 'Ada'),
+      t.field('email', b.string).pure((_) => 'ada@example.com'),
+    ],
+  );
+  final columns = ColumnWhitelist(
+    {'name': 'full_name', 'email': 'email_address'},
+    always: ['id'],
+  );
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('me', user).resolve((parent, args, context, info) {
+        print(info.selection.fingerprint);
+        print(columns.columnsFor(info.selection));
+        return const Object();
+      }),
+    ],
+  );
+  final schema = b.build(query: query);
+  for (final text in ['{ me { email name } }', '{ me { n: name } }']) {
+    final document = const Parser().parse(Source(text)).requireDocument();
+    await schema.execute(
+      ValidDocument.assumeValid(schema.schema, document),
+      context: null,
+    );
+  }
+}
+```
+
+It prints:
+
+```text
 email,name
+[email_address, full_name, id]
+name
+[full_name, id]
 ```
 
-`fields` lists the `SelectedField`s; `forType(name)` narrows the selection of
-an abstract type to one object type (an unknown name gives an empty
-selection); `has('posts.comments')` tests a path of field names; `fieldsNamed`
-lists every occurrence of a name. `fingerprint` is a canonical text, equal
-for two selections that ask for the same fields and arguments, to use as a
-cache or DataLoader key. `ColumnWhitelist` turns a selection into the sorted
-columns of the fields it knows.
+An alias does not change the fingerprint: `n: name` and `name` give the same
+text.
+
+## What the selection does not do
+
+- `SelectedField.arguments` reads an argument whose value fails coercion as
+  absent. Reading a required argument that way throws, which the resolver's
+  error masking turns into `GQL330`; the executor reports the real coercion
+  error when that field runs, so no problem is silent.
+- There is no `isDeferred`: `@defer` is not executed yet, so the property
+  arrives with incremental delivery.
+- Typed handles such as `has(user.posts)` are not provided; paths are field
+  names.
+- Look-ahead is read only: it never changes what the executor runs.
````

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add CLAUDE.md README.md docs/discovery.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql_server/README.md packages/typed_graphql_server/doc/authorization.md packages/typed_graphql_server/doc/cancellation.md packages/typed_graphql_server/doc/lookahead.md
git commit -q -m "docs(typed_graphql_server): document look-ahead, authorization and cancellation" \
  -m "Full Look-ahead, Authorization and Cancellation guides with checked programs; status in the README, llms.txt, discovery, CLAUDE.md (Server paragraph, Learned in M5) and HANDOFF: stage M5 is complete on m5-final." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Review fix: bounded look-ahead walks

The M5d review found look-ahead exponential on abstract types and on alias fan-out. `SelectionNodes` dedupes plan nodes per (type, field nodes) through `IdentityKey`; `MergeKey` (response key, field name, printed arguments) keeps different fields under one alias apart; the fingerprint memoises per node group and collapses identical entries; every walk charges the run's step budget through `ExecutionLimits.spend` and `LookAheadBudget` (a refused charge is a `GQL337` error of that field); `FieldInfo` builds the selection from the plan and the run, without a closure per call; `CanonicalJson` iterates sorted entries. Tests in `bounds_test.dart`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/lookahead/identity_key.dart`, `packages/typed_graphql_server/lib/src/lookahead/look_ahead_budget.dart`, `packages/typed_graphql_server/lib/src/lookahead/merge_key.dart`
- Modify: `packages/typed_graphql_server/lib/src/execution/execution_limits.dart`, `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/field_info.dart`, `packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart`, `packages/typed_graphql_server/lib/src/lookahead/field_selection.dart`, `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart`, `packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart`, `packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart`, `CLAUDE.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/lookahead.md`
- Test: `packages/typed_graphql_server/test/lookahead/bounds_fixture.dart`, `packages/typed_graphql_server/test/lookahead/bounds_test.dart`, `packages/typed_graphql_server/test/lookahead/field_selection_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// lookahead/identity_key.dart
final class IdentityKey
  IdentityKey(this._parts)
  bool operator ==(Object other)

// lookahead/look_ahead_budget.dart
final class LookAheadBudget
  LookAheadBudget(this._spend, this._message)
  void charge(int steps)

// lookahead/merge_key.dart
final class MergeKey
  String of(FieldPlan plan)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/lookahead/bounds_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Link {
  const Link();
}

final class LinkA extends Link {
  const LinkA();
}

final class LinkB extends Link {
  const LinkB();
}

final class LinkC extends Link {
  const LinkC();
}

final class LinkD extends Link {
  const LinkD();
}

final class LinkE extends Link {
  const LinkE();
}

final class Apple {
  const Apple();
}

final class Pear {
  const Pear();
}

/// A schema built to make look-ahead walks explode: an interface with five
/// implementations that points at itself, a type whose `next` takes an
/// argument, and a union whose members give different fields one alias. The
/// root fields run [onCall] with their `FieldInfo`.
final class BoundsFixture {
  BoundsFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    late final InterfaceTypeDef<Link> linked;
    linked = b.interface<Link>(
      'Linked',
      fields: (t) => [
        t.field('parent', linked).declareOnly(),
        t.field('id', b.int).declareOnly(),
      ],
    );
    ObjectTypeDef<T> implementation<T extends Link>(String name, T value) =>
        b.object<T>(
          name,
          interfaces: [linked],
          fields: (t) => [
            t.field('parent', linked).pure((_) => value),
            t.field('id', b.int).pure((_) => 1),
          ],
        );
    implementation('LinkA', const LinkA());
    implementation('LinkB', const LinkB());
    implementation('LinkC', const LinkC());
    implementation('LinkD', const LinkD());
    implementation('LinkE', const LinkE());
    late final ObjectTypeDef<Object?> chain;
    chain = b.object<Object?>(
      'Chain',
      fields: (t) => [
        t.field('id', b.int).pure((_) => 1),
        t
            .field('next', chain.nullable, args: [Arg('i', b.int.nullable)])
            .resolve((parent, args, context, info) => null),
      ],
    );
    final apple = b.object<Apple>(
      'Apple',
      fields: (t) => [t.field('weight', b.int).pure((_) => 1)],
    );
    final pear = b.object<Pear>(
      'Pear',
      fields: (t) => [t.field('length', b.int).pure((_) => 2)],
    );
    final fruit = b.union<Object>('Fruit', members: [apple, pear]);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('node', linked)
            .resolve((p, a, c, info) => _call(info, const LinkA())),
        t
            .field('chain', chain.nullable)
            .resolve((p, a, c, info) => _call(info, const Object())),
        t
            .field('fruit', fruit)
            .resolve((p, a, c, info) => _call(info, const Apple())),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Object?> built;

  /// What the root fields do with their `FieldInfo` before they answer.
  void Function(FieldInfo info) onCall = (_) {};

  T _call<T>(FieldInfo info, T value) {
    onCall(info);
    return value;
  }

  /// Runs [text] and returns the payload.
  FutureOr<ResponsePayload> run(
    String text, {
    ExecutionOptions options = const ExecutionOptions(),
  }) {
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument();
    return built.execute(
      ValidDocument.assumeValid(built.schema, document),
      context: null,
      options: options,
    );
  }

  /// The selection under the root field [field] of [text].
  Future<FieldSelection> selection(String field, String text) async {
    FieldSelection? found;
    onCall = (info) => found = info.selection;
    final payload = await run(text);
    return found ??
        (throw StateError('"$field" did not run: ${payload.toJson()}'));
  }
}
```

Create `packages/typed_graphql_server/test/lookahead/bounds_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'bounds_fixture.dart';

void main() {
  final f = BoundsFixture();

  // `fragment F0 on Chain { a: next {...F1} b: next(i: 2) {...F1} } ...`
  // down to `fragment F30 on Chain { id }`: [second] is the arguments of
  // the `b` field.
  String fanOut(String second) {
    final out = StringBuffer('{ chain { ...F0 } }\n');
    for (var n = 0; n < 30; n++) {
      out.writeln(
        'fragment F$n on Chain { a: next {...F${n + 1}} '
        'b: next$second {...F${n + 1}} }',
      );
    }
    out.writeln('fragment F30 on Chain { id }');
    return out.toString();
  }

  group('an abstract type', () {
    // `{ node { parent { parent { ... { id } } } } }`, twelve levels of an
    // interface with five implementations: 5^12 plans without the dedupe.
    final query = '{ node ${'{ parent ' * 12}{ id }${' }' * 12} }';

    test('costs its distinct nodes, not the product per level', () async {
      final clock = Stopwatch()..start();
      final selection = await f.selection('node', query);
      final read = [
        selection.fields.length,
        selection.has('${'parent.' * 12}id'),
        selection.has('${'parent.' * 13}id'),
        selection.fingerprint,
      ];
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(read, [
        1,
        true,
        false,
        '${'parent{' * 12}id${'}' * 12}',
      ]);
    });
  });

  group('one response key', () {
    test('over different fields is as many selected fields', () async {
      final selection = await f.selection(
        'fruit',
        '{ fruit { ... on Apple { k: weight } ... on Pear { k: length } } }',
      );
      expect(
        [for (final field in selection.fields) field.name],
        ['weight', 'length'],
      );
    });

    test('over the same field is one selected field', () async {
      final selection = await f.selection(
        'fruit',
        '{ fruit { ... on Apple { k: weight } ... on Pear { k: weight } } }',
      );
      expect(selection.fields.length, 1);
    });
  });

  group('aliases through fragments', () {
    test('with the same arguments fingerprint in linear time', () async {
      final clock = Stopwatch()..start();
      final selection = await f.selection('chain', fanOut(''));
      final read = [
        selection.fingerprint,
        selection.has('${'next.' * 30}id'),
      ];
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(read, ['${'next{' * 30}id${'}' * 30}', true]);
    });

    test('with other arguments are refused by maxSteps as GQL337', () async {
      final clock = Stopwatch()..start();
      f.onCall = (info) => info.selection.fingerprint;
      final payload = await f.run(
        fanOut('(i: 2)'),
        options: const ExecutionOptions(maxSteps: 1000),
      );
      final error = (payload as ExecutionResult).errors.single;
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(
        error.toJson()['extensions'],
        JsonObject({'code': const JsonString('GQL337')}),
      );
      expect(
        error.message,
        'Execution exceeds the limit of 1000 completed '
        'values.',
      );
    });

    test('with other arguments still fit a generous budget', () async {
      var text = '';
      f.onCall = (info) => text = info.selection.fingerprint;
      await f.run(
        '{ chain { ...F0 } }'
        'fragment F0 on Chain { a: next {...F1} b: next(i: 2) {...F1} }'
        'fragment F1 on Chain { id }',
      );
      expect(text, 'next(i:2){id},next{id}');
    });
  });
}
```

In `packages/typed_graphql_server/test/lookahead/field_selection_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -247,28 +247,6 @@ void main() {
       expect(identical(info.selection, info.selection), isTrue);
     });
 
-    test('is not built until it is read', () async {
-      final info = await f.infoOf('user', '{ user { name } }');
-      var reads = 0;
-      final copy = FieldInfo(
-        fieldName: info.fieldName,
-        parentType: info.parentType,
-        returnType: info.returnType,
-        path: info.path,
-        fieldNodes: info.fieldNodes,
-        operation: info.operation,
-        variables: info.variables,
-        schema: info.schema,
-        selectionReader: () {
-          reads++;
-          return FieldSelection.empty;
-        },
-      );
-      final before = reads;
-      final same = identical(copy.selection, copy.selection);
-      expect([before, reads, same], [0, 1, true]);
-    });
-
     test('is empty when the call was not made by an execution', () async {
       final info = await f.infoOf('user', '{ user { name } }');
       final copy = FieldInfo(
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/lookahead/bounds_test.dart test/lookahead/field_selection_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/lookahead/identity_key.dart`:

```dart
/// A map key made of parts compared by identity (syntax nodes) or by value
/// (type names), so two plans over the very same field nodes meet in a set
/// without printing or hashing the nodes' contents.
final class IdentityKey {
  /// Creates the key of [parts]: strings compare by value, anything else by
  /// identity.
  IdentityKey(this._parts)
    : hashCode = Object.hashAll([
        for (final part in _parts)
          if (part is String) part.hashCode else identityHashCode(part),
      ]);

  final List<Object> _parts;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! IdentityKey || other._parts.length != _parts.length) {
      return false;
    }
    for (var i = 0; i < _parts.length; i++) {
      final mine = _parts[i];
      final theirs = other._parts[i];
      if (mine is String ? mine != theirs : !identical(mine, theirs)) {
        return false;
      }
    }
    return true;
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/look_ahead_budget.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/graphql_exception.dart';

/// The steps a look-ahead may still spend: the run's own step counter, the
/// one `ExecutionOptions.maxSteps` limits, so a selection that fans out
/// through aliases and fragments cannot cost more than the request could.
final class LookAheadBudget {
  /// Spends through [spend], which says whether [steps] more fit; [message]
  /// is what the refusal says.
  @internal
  LookAheadBudget(this._spend, this._message);

  /// A budget that never refuses: a selection made outside an execution.
  static final LookAheadBudget unlimited = LookAheadBudget((_) => true, '');

  final bool Function(int steps) _spend;
  final String _message;

  /// Spends [steps], or throws a [GraphQLException] with the code `GQL337`:
  /// thrown inside a resolver, it becomes that field's error. A refused
  /// charge spends nothing, so the rest of the execution is unaffected.
  void charge(int steps) {
    if (_spend(steps)) {
      return;
    }
    throw GraphQLException(
      _message,
      extensions: JsonObject({
        'code': JsonString(DiagnosticCode.maxExecutionStepsExceeded.id),
      }),
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/lookahead/merge_key.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/field_plan.dart';

/// What decides that two plans of a response key are one selected field:
/// the key, the field's name and its arguments as written.
///
/// Object types that cannot overlap may give one alias to different fields
/// (spec 5.3.2, `FieldsInSetCanMerge` only compares fields of overlapping
/// types), so the key alone would merge fields that are not the same.
final class MergeKey {
  /// Creates the writer.
  const MergeKey();

  /// The text of [plan]'s merge key; arguments sorted by their text.
  String of(FieldPlan plan) {
    final arguments = plan.nodes.first.arguments;
    if (arguments.isEmpty) {
      return '${plan.responseKey}\u0000${plan.fieldName}';
    }
    final printed = [
      for (final argument in arguments) const Printer().print(argument),
    ]..sort();
    return '${plan.responseKey}\u0000${plan.fieldName}\u0000'
        '${printed.join(',')}';
  }
}
```

In `packages/typed_graphql_server/lib/src/execution/execution_limits.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,8 +24,7 @@ final class ExecutionLimits {
     if (_steps > _options.maxSteps) {
       _reporter.halt(
         DiagnosticCode.maxExecutionStepsExceeded,
-        'Execution exceeds the limit of ${_options.maxSteps} completed '
-        'values.',
+        stepsExceededMessage,
         site,
       );
       return false;
@@ -33,6 +32,21 @@ final class ExecutionLimits {
     return admitsDepth(site);
   }
 
+  /// The text of the error for a run past `maxSteps`.
+  String get stepsExceededMessage =>
+      'Execution exceeds the limit of ${_options.maxSteps} completed values.';
+
+  /// Spends [steps] on a look-ahead and says whether they fit under
+  /// `maxSteps`. A refusal spends nothing and ends nothing: the look-ahead
+  /// throws, which fails its field only.
+  bool spend(int steps) {
+    if (_reporter.log.isHalted || _steps + steps > _options.maxSteps) {
+      return false;
+    }
+    _steps += steps;
+    return true;
+  }
+
   /// Whether the place [site] is within `maxDepth`; a refusal is already
   /// reported as a field error. Costs no step, so a field can be refused
   /// before its resolver runs.
```

In `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,7 @@ import 'dart:async';
 
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../lookahead/look_ahead_budget.dart';
 import '../plan/operation_plan.dart';
 import 'error_behavior.dart';
 import 'error_reporter.dart';
@@ -69,6 +70,12 @@ final class ExecutionRun {
   /// Counts steps and depth.
   late final ExecutionLimits limits = ExecutionLimits(options, reporter);
 
+  /// What a look-ahead may spend: the steps `maxSteps` still allows.
+  late final LookAheadBudget lookAheadBudget = LookAheadBudget(
+    limits.spend,
+    limits.stepsExceededMessage,
+  );
+
   /// Runs the fields of a selection.
   late final SelectionExecutor selection = SelectionExecutor(this);
 
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,7 +8,6 @@ import '../builder/field_lane.dart';
 import '../coercion/coercion_result.dart';
 import '../introspection/entry_fields.dart';
 import '../introspection/introspection_policy.dart';
-import '../lookahead/field_selection.dart';
 import '../plan/field_plan.dart';
 import 'completion_site.dart';
 import 'execution_run.dart';
@@ -260,11 +259,8 @@ final class FieldExecution {
       schema: _run.schema,
       rootValue: _run.options.rootValue,
       cancelSignal: _run.cancellation?.signal,
-      selectionReader: () => FieldSelection.under(
-        [plan],
-        _run.variables,
-        _run.bindings.fields,
-      ),
+      plan: plan,
+      run: _run,
     );
   }
 }
```

In `packages/typed_graphql_server/lib/src/execution/field_info.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,8 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../cancellation/cancel_signal.dart';
 import '../lookahead/field_selection.dart';
+import '../plan/field_plan.dart';
+import 'execution_run.dart';
 import 'response_path.dart';
 
 /// What a resolver knows about the call it answers.
@@ -20,7 +22,8 @@ final class FieldInfo {
     required this.variables,
     required this.schema,
     this.rootValue,
-    this.selectionReader,
+    this.plan,
+    this.run,
     CancelSignal? cancelSignal,
   }) : _runSignal = cancelSignal;
 
@@ -52,21 +55,37 @@ final class FieldInfo {
   /// The root value of the execution.
   final Object? rootValue;
 
-  /// Builds [selection] when it is first read; the executor sets it.
+  /// The plan of the field, which [selection] reads; the executor sets it.
   @internal
-  final FieldSelection Function()? selectionReader;
+  final FieldPlan? plan;
+
+  /// The execution that made the call, whose variables, tables and step
+  /// budget [selection] reads; the executor sets it.
+  @internal
+  final ExecutionRun? run;
 
   /// The fields the request selected under this field (R4.18), for a
   /// resolver that loads only what is asked for.
   ///
   /// Built when first read, so a resolver that never reads it pays nothing
-  /// but the reader's closure; empty for a call made outside an execution.
-  // `late`: the reader runs on first read, not when the call starts.
-  late final FieldSelection selection =
-      selectionReader?.call() ?? FieldSelection.empty;
+  /// (the call keeps its plan and run, no more); empty for a call made
+  /// outside an execution. Reading it and walking it spend the run's step
+  /// budget, see [FieldSelection].
+  // `late`: the selection is built on first read, not when the call starts.
+  late final FieldSelection selection = _selectionOf(plan, run);
 
   final CancelSignal? _runSignal;
 
+  static FieldSelection _selectionOf(FieldPlan? plan, ExecutionRun? run) =>
+      plan == null || run == null
+      ? FieldSelection.empty
+      : FieldSelection.under(
+          [plan],
+          run.variables,
+          run.bindings.fields,
+          run.lookAheadBudget,
+        );
+
   /// Fires when the execution is cancelled or times out (R4.20): a resolver
   /// doing long work checks `isCancelled` or awaits `whenCancelled` to stop.
   ///
```

In `packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,11 +19,15 @@ final class CanonicalJson {
         case JsonArray(:final items):
           _push(pending, ['[', ..._separated(items), ']']);
         case JsonObject(:final fields):
-          final keys = fields.keys.toList()..sort();
+          final entries = fields.entries.toList()
+            ..sort((a, b) => a.key.compareTo(b.key));
           _push(pending, [
             '{',
             ..._separated([
-              for (final key in keys) ...['${JsonString(key)}:', fields[key]!],
+              for (final entry in entries) ...[
+                '${JsonString(entry.key)}:',
+                entry.value,
+              ],
             ], pairs: true),
             '}',
           ]);
```

In `packages/typed_graphql_server/lib/src/lookahead/field_selection.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,9 @@ import 'package:meta/meta.dart';
 
 import '../builder/field_def.dart';
 import '../plan/field_plan.dart';
+import 'identity_key.dart';
+import 'look_ahead_budget.dart';
+import 'merge_key.dart';
 import 'selected_field.dart';
 import 'selection_fingerprint.dart';
 import 'selection_nodes.dart';
@@ -14,6 +17,12 @@ import 'selection_nodes.dart';
 /// It is a view of the operation plan: nothing is collected until a member
 /// is read, and a selection never changes.
 ///
+/// Reading and walking a selection spend the run's step budget (the one
+/// `ExecutionOptions.maxSteps` limits): a read that would not fit throws a
+/// `GraphQLException` with the code `GQL337`, which fails the field whose
+/// resolver read it. A selection that asks for what the request asks for
+/// costs steps in proportion to the request.
+///
 /// {@category lookahead}
 final class FieldSelection {
   /// Creates the selection under [plans], the plans of one response key, read
@@ -23,11 +32,13 @@ final class FieldSelection {
   FieldSelection.under(
     List<FieldPlan> plans,
     Map<String, Object?> variables,
-    Map<String, Map<String, FieldDef<Object?, Object?>>> definitions, [
+    Map<String, Map<String, FieldDef<Object?, Object?>>> definitions,
+    LookAheadBudget budget, [
     String? typeName,
   ]) : _plans = plans,
        _variables = variables,
        _definitions = definitions,
+       _budget = budget,
        _typeName = typeName;
 
   /// A selection with no fields: what a field of a leaf type, or a call
@@ -36,16 +47,19 @@ final class FieldSelection {
     const [],
     const {},
     const {},
+    LookAheadBudget.unlimited,
   );
 
   final List<FieldPlan> _plans;
   final Map<String, Object?> _variables;
   final Map<String, Map<String, FieldDef<Object?, Object?>>> _definitions;
+  final LookAheadBudget _budget;
   final String? _typeName;
 
-  /// The selected fields in collection order, merged by response key. For
-  /// a field of an abstract type these are the fields every possible type
-  /// collects, in possible-type order; an alias keeps each occurrence apart.
+  /// The selected fields in collection order, merged by response key, field
+  /// name and arguments. For a field of an abstract type these are the
+  /// fields every possible type collects, in possible-type order; an alias
+  /// keeps each occurrence apart.
   // `late`: collected on first read, so an unread selection costs nothing.
   late final List<SelectedField> fields = _collect();
 
@@ -53,8 +67,13 @@ final class FieldSelection {
   ///
   /// An unknown name, or a type the field's value cannot have, gives an
   /// empty selection; nothing throws.
-  FieldSelection forType(String typeName) =>
-      FieldSelection.under(_plans, _variables, _definitions, typeName);
+  FieldSelection forType(String typeName) => FieldSelection.under(
+    _plans,
+    _variables,
+    _definitions,
+    _budget,
+    typeName,
+  );
 
   /// Whether the request selected the path [path] of field names (not
   /// aliases) joined by dots, as in `posts.comments.author`.
@@ -66,15 +85,25 @@ final class FieldSelection {
       if (segment.isEmpty) {
         throw ArgumentError.value(path, 'path', 'has an empty segment');
       }
-      level = [
-        for (final selection in level)
-          for (final field in selection.fields)
-            if (field.name == segment) field.selection,
-      ];
+      level = [for (final field in _named(level, segment)) field.selection];
     }
     return level.isNotEmpty;
   }
 
+  // Fields over the same nodes have the same sub-selection: keeping one of
+  // them keeps the walk linear when aliases repeat a fragment.
+  Iterable<SelectedField> _named(List<FieldSelection> level, String name) {
+    final byKey = <IdentityKey, SelectedField>{};
+    for (final selection in level) {
+      for (final field in selection.fields) {
+        if (field.name == name) {
+          byKey.putIfAbsent(field.key, () => field);
+        }
+      }
+    }
+    return byKey.values;
+  }
+
   /// Every selected field called [name] in the schema, whatever its alias.
   List<SelectedField> fieldsNamed(String name) => [
     for (final field in fields)
@@ -85,21 +114,23 @@ final class FieldSelection {
   /// for the same fields with the same arguments: field names (not aliases)
   /// and arguments sorted, argument values as JSON with sorted keys and the
   /// variables substituted. Meant as a cache or DataLoader key.
-  String get fingerprint => const SelectionFingerprint().of(this);
+  String get fingerprint => const SelectionFingerprint().of(this, _budget);
 
   List<SelectedField> _collect() {
     final byKey = <String, List<FieldPlan>>{};
-    for (final node in const SelectionNodes().of(_plans, _typeName)) {
+    final nodes = const SelectionNodes().of(_plans, _typeName, _budget);
+    for (final node in nodes) {
+      _budget.charge(1 + node.fields.length);
       for (final plan in node.fields) {
         if (plan.fieldName.startsWith('__')) {
           continue;
         }
-        (byKey[plan.responseKey] ??= []).add(plan);
+        (byKey[const MergeKey().of(plan)] ??= []).add(plan);
       }
     }
     return List.unmodifiable([
       for (final plans in byKey.values)
-        SelectedField(plans, _variables, _definitions),
+        SelectedField(plans, _variables, _definitions, _budget),
     ]);
   }
 }
```

In `packages/typed_graphql_server/lib/src/lookahead/selected_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,8 @@ import '../builder/field_def.dart';
 import '../coercion/coercion_result.dart';
 import '../plan/field_plan.dart';
 import 'field_selection.dart';
+import 'identity_key.dart';
+import 'look_ahead_budget.dart';
 
 /// One field of a [FieldSelection]: what the request asked for under one
 /// response key.
@@ -20,13 +22,25 @@ final class SelectedField {
     List<FieldPlan> plans,
     Map<String, Object?> variables,
     Map<String, Map<String, FieldDef<Object?, Object?>>> definitions,
+    LookAheadBudget budget,
   ) : _plans = plans,
       _variables = variables,
-      _definitions = definitions;
+      _definitions = definitions,
+      _budget = budget;
 
   final List<FieldPlan> _plans;
   final Map<String, Object?> _variables;
   final Map<String, Map<String, FieldDef<Object?, Object?>>> _definitions;
+  final LookAheadBudget _budget;
+
+  /// Which request fields this one stands for: equal for two selected
+  /// fields over the same field nodes and parent types, whatever object
+  /// they were reached through. A walk remembers what it did per key.
+  @internal
+  // `late`: only the walks that dedupe pay for it.
+  late final IdentityKey key = IdentityKey([
+    for (final plan in _plans) ...[plan.parentType.name, ...plan.nodes, '|'],
+  ]);
 
   /// The field's name in the schema, never the alias.
   String get name => _plans.first.fieldName;
@@ -61,6 +75,7 @@ final class SelectedField {
     _plans,
     _variables,
     _definitions,
+    _budget,
   );
 
   Arguments _readArguments() {
```

In `packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,48 +1,83 @@
 import 'argument_text.dart';
 import 'field_selection.dart';
+import 'identity_key.dart';
+import 'look_ahead_budget.dart';
 import 'selected_field.dart';
 
 /// Builds the canonical text of a [FieldSelection] with an explicit stack,
 /// so a selection a thousand levels deep costs no call depth (R0.3).
+///
+/// Fields over the same field nodes are read once (their text is
+/// remembered), and entries with the same text collapse to one, so aliases
+/// that repeat a fragment cost nothing extra. What remains is charged to the
+/// [LookAheadBudget] by the size of the text it builds, before it builds it.
 final class SelectionFingerprint {
   /// Creates the builder.
   const SelectionFingerprint();
 
   /// The text of [root]: each field as `name(arguments)` and, when it has a
-  /// sub-selection, `{children}`; siblings sorted and joined by commas.
-  String of(FieldSelection root) {
-    final stack = <_Level>[_Level('', root.fields)];
+  /// sub-selection, `{children}`; siblings sorted, joined by commas and
+  /// listed once when they read the same.
+  String of(FieldSelection root, LookAheadBudget budget) {
+    final done = <IdentityKey, _Entry>{};
+    final stack = <_Level>[_Level(null, null, root.fields)];
     while (true) {
       final level = stack.last;
       if (level.next case final field?) {
+        final known = done[field.key];
+        if (known != null) {
+          level.add(known);
+          continue;
+        }
         final text = '${field.name}${const ArgumentText().of(field.arguments)}';
         final children = field.selection.fields;
         if (children.isEmpty) {
-          level.entries.add(text);
+          budget.charge(1);
+          level.add(done[field.key] = (text: text, size: 1));
         } else {
-          stack.add(_Level(text, children));
+          stack.add(_Level(field.key, text, children));
         }
         continue;
       }
       stack.removeLast();
-      final joined = (level.entries..sort()).join(',');
-      if (stack.isEmpty) {
-        return joined;
+      final entry = level.finish(budget);
+      final key = level.key;
+      if (key == null) {
+        return entry.text;
       }
-      stack.last.entries.add('${level.prefix}{$joined}');
+      stack.last.add(done[key] = entry);
     }
   }
 }
 
-// One selection being read: the text of the field that owns it, its fields
-// still to read and the entries finished so far.
+// The text of a finished field and the number of fields that text holds.
+typedef _Entry = ({String text, int size});
+
+// One selection being read: the key and text of the field that owns it (null
+// for the root), its fields still to read and the distinct entries so far.
 final class _Level {
-  _Level(this.prefix, this._fields);
+  _Level(this.key, this._prefix, this._fields);
 
-  final String prefix;
+  final IdentityKey? key;
+  final String? _prefix;
   final List<SelectedField> _fields;
-  final List<String> entries = [];
+  final Map<String, int> _entries = {};
   int _index = 0;
 
   SelectedField? get next => _index < _fields.length ? _fields[_index++] : null;
+
+  void add(_Entry entry) => _entries[entry.text] = entry.size;
+
+  _Entry finish(LookAheadBudget budget) {
+    var size = _prefix == null ? 0 : 1;
+    for (final entrySize in _entries.values) {
+      size += entrySize;
+    }
+    budget.charge(size);
+    final joined = (_entries.keys.toList()..sort()).join(',');
+    return (
+      text: _prefix == null ? joined : '$_prefix{$joined}',
+      size: size,
+    );
+  }
 }
```

In `packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,7 @@
 import '../plan/field_plan.dart';
 import '../plan/plan_node.dart';
+import 'identity_key.dart';
+import 'look_ahead_budget.dart';
 
 /// Finds the plan nodes a field's sub-selection is collected into: one per
 /// object type the field's value can have (R4.18).
@@ -10,8 +12,18 @@ final class SelectionNodes {
   /// The nodes of the sub-selections of [plans], in plan order and, within a
   /// plan, in possible-type order; only the object type called [typeName]
   /// when it is given. A field of a leaf type has none.
-  List<PlanNode> of(List<FieldPlan> plans, String? typeName) {
+  ///
+  /// Plans of different parent types share their field nodes, so a node is
+  /// listed once per (field nodes, object type): an interface with five
+  /// implementations costs five nodes per level, not five to the depth.
+  /// Each visit is charged to [budget].
+  List<PlanNode> of(
+    List<FieldPlan> plans,
+    String? typeName,
+    LookAheadBudget budget,
+  ) {
     final nodes = <PlanNode>[];
+    final seen = <IdentityKey>{};
     for (final plan in plans) {
       final declared = plan.field;
       if (declared == null) {
@@ -23,7 +35,11 @@ final class SelectionNodes {
         continue;
       }
       for (final type in schema.possibleTypes(named)) {
-        if (typeName == null || type.name == typeName) {
+        budget.charge(1);
+        if (typeName != null && type.name != typeName) {
+          continue;
+        }
+        if (seen.add(IdentityKey([type.name, ...plan.nodes]))) {
           nodes.add(plan.childFor(type));
         }
       }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/lookahead/bounds_test.dart test/lookahead/field_selection_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -463,8 +463,8 @@ order, pausing the source meanwhile; a source that fails after listening is the
 last result (`GQL340`), one that fails at start is a `SubscriptionRejected`.
 `subscription/` holds only the public `SubscriptionResult` family.
 `lookahead/` (M5d): `FieldInfo.selection` is a `FieldSelection` built on first
-read from the field's `FieldPlan`s and the run's variables
-(`FieldInfo.selectionReader` is `@internal`); `SelectionNodes` flattens
+read from the field's `FieldPlan` and the run (`FieldInfo.plan` and `run` are
+`@internal`, so an unread selection allocates nothing); `SelectionNodes` flattens
 fragments and applies `@skip`/`@include`, `forType` narrows an abstract type,
 every name starting with `__` is hidden. A `SelectedField` reads its
 `arguments` on first use (a failing argument reads absent; the executor
```

In `packages/typed_graphql_server/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -104,6 +104,12 @@
   names to sorted, de-duplicated columns. `isDeferred` arrives with
   incremental delivery.
 - The Look-ahead guide and its dartdoc category `lookahead`.
+- Look-ahead walks are bounded: a selection over an interface with many
+  implementations costs its distinct nodes, not their product per level, a
+  fingerprint reads fields over the same nodes once and lists identical
+  entries once, and every walk spends the run's `maxSteps` budget (a read that
+  would not fit throws `GQL337` as that field's error). Fields that share a
+  response key but differ in name or arguments across object types stay apart.
 - Authorization: `Authorization.requires` and `Authorization.public` rules on a
   field (`.withAuthorization`) or an object type (`ObjectOptions.authorization`),
   an `Authorizer<C>` in `BuildOptions.authorizer` that answers `Allow` or `Deny`
```

In `packages/typed_graphql_server/doc/lookahead.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -102,7 +102,10 @@ removes its only field, and `__typename` never shows.
 ## Abstract types
 
 Under a field of an interface or union type, `fields` holds what every
-possible type collects, merged by response key in possible-type order.
+possible type collects, in possible-type order. Fields are merged when they
+have the same response key, the same field name and the same arguments as
+written: object types that cannot overlap may give one alias to different
+fields, and those stay apart as two `SelectedField`s.
 `forType(name)` narrows the view to one object type: the fields that apply to
 it, including those from `... on Name` fragments. An unknown name, or a type
 that cannot occur there, gives an empty selection.
@@ -116,7 +119,21 @@ fields with the same arguments have the same fingerprint, whatever the order,
 the aliases or the fragments of their requests. Use it as a cache or
 DataLoader key, so that a batch is shared only between requests that want the
 same data. It is built with an explicit stack, so a deep selection cannot
-overflow the stack.
+overflow the stack. Entries that read the same collapse to one, so aliases
+that repeat a fragment do not multiply the text.
+
+## The cost of a look-ahead
+
+A selection can fan out: aliases that each spread a fragment that does the
+same make a text that doubles at every level. A look-ahead is therefore
+bounded by the same step counter as `ExecutionOptions.maxSteps`: collecting a
+selection, and building a fingerprint (by the size of its text), spend steps
+of the run. When they would not fit, the read throws a `GraphQLException`
+with the code `GQL337` and the message of the executor's step limit, before
+it does the work; thrown in a resolver, that is the error of the field, and
+the rest of the execution goes on. Fields over the same field nodes are read
+once, so a selection whose aliases use the same arguments costs time in
+proportion to the request, not to its expansion.
 
 `ColumnWhitelist` turns a selection into database columns. It maps field
 names to columns, adds the `always` columns (a key, say), ignores the fields
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/lookahead.md packages/typed_graphql_server/lib/src/execution/execution_limits.dart packages/typed_graphql_server/lib/src/execution/execution_run.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/field_info.dart packages/typed_graphql_server/lib/src/lookahead/canonical_json.dart packages/typed_graphql_server/lib/src/lookahead/field_selection.dart packages/typed_graphql_server/lib/src/lookahead/identity_key.dart packages/typed_graphql_server/lib/src/lookahead/look_ahead_budget.dart packages/typed_graphql_server/lib/src/lookahead/merge_key.dart packages/typed_graphql_server/lib/src/lookahead/selected_field.dart packages/typed_graphql_server/lib/src/lookahead/selection_fingerprint.dart packages/typed_graphql_server/lib/src/lookahead/selection_nodes.dart packages/typed_graphql_server/test/lookahead/bounds_fixture.dart packages/typed_graphql_server/test/lookahead/bounds_test.dart packages/typed_graphql_server/test/lookahead/field_selection_test.dart
git commit -q -m "fix(typed_graphql_server): bound the look-ahead walks" \
  -m "Dedupe plan nodes by field nodes and object type, merge response keys by key, name and arguments, read fingerprints once per node group with a size-charged step budget (GQL337), and build FieldInfo.selection without a closure." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Review fix: subscription cancellation released without a listener

`RunCancellation` disposes itself when its own signal fires, so an unlistened subscription stream releases its timer and the caller's listener on cancel or timeout; `SubscriptionResponses` releases its stop listener when it closes, cancels or fails; `CancelSignal.addListener` documents that listeners must not throw. Tests in `subscription_release_test.dart`.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart`, `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`, `CLAUDE.md`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/cancellation.md`
- Test: `packages/typed_graphql_server/test/cancellation/subscription_release_test.dart`, `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/cancellation/subscription_release_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);

  Future<Stream<ExecutionResult>> started(
    Probe probe,
    ExecutionOptions options, {
    String field = 'ticks',
  }) async {
    final result = await fixture.subscribe(
      'subscription { $field }',
      probe,
      options: options,
    );
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
    };
  }

  group('a response stream nobody listens to', () {
    const watched = Duration(minutes: 5);

    test(
      'keeps its listener on the caller signal until it is cancelled',
      () async {
        final signal = CancelSignal();
        await started(Probe(), ExecutionOptions(cancelSignal: signal));
        expect(signal.listenerCount, 1);
      },
    );

    test('releases the timer when the caller cancels', () async {
      final tracker = TimerTracker(watched);
      final signal = CancelSignal();
      await tracker.run(
        () => started(
          Probe(),
          ExecutionOptions(cancelSignal: signal, timeout: watched),
        ),
      );
      expect(tracker.isIdle, isFalse);
      signal.cancel();
      expect(tracker.isIdle, isTrue);
    });

    test('releases the caller listener when the timeout fires', () async {
      final signal = CancelSignal();
      await started(
        Probe(),
        ExecutionOptions(
          cancelSignal: signal,
          timeout: const Duration(milliseconds: 10),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(signal.listenerCount, 0);
    });
  });

  test(
    'a finished stream leaves no listener of its own on the run signal',
    () async {
      final probe = Probe()..gate.complete();
      final results = await started(
        probe,
        ExecutionOptions(cancelSignal: CancelSignal()),
        field: 'held',
      );
      final collected = results.toList();
      probe.source.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await probe.source.close();
      final all = await collected.timeout(patience);
      expect(all, hasLength(1));
      // The one left is the run's own release, not the stream's.
      expect(probe.seen?.listenerCount, 1);
      expect(() => probe.seen?.cancel(), returnsNormally);
    },
  );
}
```

In `packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -122,6 +122,7 @@ final class CancellationFixture {
           (parent, args, context, info) => context.source.stream,
           (event, args, context, info) async {
             context.log.add('held $event');
+            context.seen = info.cancelSignal;
             await context.gate.future;
             return event;
           },
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/subscription_release_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -28,6 +28,10 @@ final class CancelSignal {
   /// complete for a signal that was.
   Future<void> get whenCancelled => _completer.future;
 
+  /// How many listeners wait for the signal.
+  @visibleForTesting
+  int get listenerCount => _listeners?.length ?? 0;
+
   /// Cancels the signal with an optional [reason]. Only the first call has
   /// an effect.
   void cancel([Object? reason]) {
@@ -49,6 +53,10 @@ final class CancelSignal {
   /// Calls [listener] at once when the signal is cancelled, else when it
   /// is; returns a function that removes the listener. Unlike
   /// [whenCancelled] it leaves nothing behind once removed.
+  ///
+  /// A listener must not throw: [cancel] calls them in turn and one that
+  /// throws would keep the rest from running. Every listener is the
+  /// library's own, written not to.
   @internal
   void Function() addListener(void Function() listener) {
     if (_isCancelled) {
```

In `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'dart:async';
 
+import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../cancellation/cancel_signal.dart';
@@ -10,7 +11,9 @@ import 'execution_options.dart';
 ///
 /// Nothing exists when the options have neither a signal nor a timeout, so
 /// the plain path pays nothing. [dispose] ends the timer and the listener
-/// when the run ends.
+/// when the run ends; the run's own signal calls it when it fires, so a
+/// subscription nobody listens to is released when it is cancelled or times
+/// out.
 final class RunCancellation {
   RunCancellation._(this.signal);
 
@@ -23,6 +26,9 @@ final class RunCancellation {
       return null;
     }
     final cancellation = RunCancellation._(CancelSignal());
+    // First, so that a cancellation from the caller's signal, already
+    // cancelled or not, or from the timer, releases both.
+    cancellation.signal.addListener(cancellation.dispose);
     if (caller != null) {
       cancellation._detach = caller.addListener(
         () => cancellation.signal.cancel(caller.reason),
@@ -117,6 +123,10 @@ final class RunCancellation {
     return completer.future;
   }
 
+  /// Whether the timeout timer is still running.
+  @visibleForTesting
+  bool get isTimerActive => _timer?.isActive ?? false;
+
   /// Ends the timer and stops listening to the caller's signal.
   void dispose() {
     _timer?.cancel();
```

In `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -35,6 +35,7 @@ final class SubscriptionResponses {
   StreamSubscription<Object?>? _subscription;
   final Queue<void Function()> _waiting = Queue<void Function()>();
   bool _isCancelled = false;
+  void Function()? _detachStop;
   bool _isBusy = false;
   bool _isDraining = false;
   // Pauses owed to the source because it delivered before `listen` returned.
@@ -49,7 +50,9 @@ final class SubscriptionResponses {
         _stop(cancellation);
         return;
       }
-      cancellation.signal.addListener(() => _stop(cancellation));
+      _detachStop = cancellation.signal.addListener(
+        () => _stop(cancellation),
+      );
     }
     _subscription = _source.listen(
       _onEvent,
@@ -70,7 +73,7 @@ final class SubscriptionResponses {
     final wasCancelled = _isCancelled;
     _isCancelled = true;
     _waiting.clear();
-    _template.cancellation?.dispose();
+    _release();
     if (wasCancelled) {
       return Future<void>.value();
     }
@@ -147,9 +150,18 @@ final class SubscriptionResponses {
     _isDraining = false;
   }
 
+  // The run's signal may outlive the stream (a resolver holds it), so the
+  // stream stops listening to it and ignores it from here on.
+  void _release() {
+    _detachStop?.call();
+    _detachStop = null;
+    _template.cancellation?.dispose();
+  }
+
   void _close() {
     if (!_isCancelled) {
-      _template.cancellation?.dispose();
+      _isCancelled = true;
+      _release();
       _controller.close();
     }
   }
@@ -178,7 +190,7 @@ final class SubscriptionResponses {
     }
     _isCancelled = true;
     _waiting.clear();
-    _template.cancellation?.dispose();
+    _release();
     final reported = _template.reporter.sourceFailure(error, stackTrace);
     _controller.add(ExecutionResult(null, errors: [reported]));
     _controller.close();
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/subscription_release_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -486,7 +486,9 @@ the run's signal (`FieldInfo.cancelSignal`) when `OperationPreparation` has no
 request error, and disposes the timer and the listener when the run ends.
 `ExecutionRun.executeRoot` races the pending result against it once and
 `FieldExecution` starts no field after it fires (`GQL350`, `GQL351`); a
-subscription keeps the timer from `subscribe` and the listener from `listen`.
+subscription starts the timer and the listener at `subscribe`, and the run's
+own signal releases both when it fires, so an unlistened stream is freed by a
+cancel or a timeout (one with neither keeps its listener on the caller's signal).
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
```

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -725,10 +725,13 @@ depends on the other). These constraints keep that possible:
 41. An object field that redeclares an interface field does not inherit the
     interface field's authorization rule: the rule guards the
     implementations that inherit the field.
-42. A subscription response stream that is never listened to keeps its
-    listener on the caller's `CancelSignal` until that signal is cancelled;
-    the listener attaches on `listen`, the timeout timer starts at
-    `subscribe`. The guide says to listen to the stream or drop the signal.
+42. A subscription's timeout timer and its listener on the caller's
+    `CancelSignal` start at `subscribe`, not at `listen`. When the run's signal
+    fires (the caller cancels or the timeout elapses) the cancellation
+    releases both even if nobody listens to the response stream. A stream never
+    listened to, with no cancel and no timeout, keeps its listener on the
+    caller's signal until that signal is cancelled or collected; the guide
+    says to listen to the stream or drop the signal.
 
 ## 19. Conformance (R0.7, R10.3)
 
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- A subscription starts its timer and its listener on the caller's signal at
  `subscribe` and releases both when the run's signal fires, also for a response
  stream nobody listens to; a finished stream stops listening to the run's signal.
```

In `packages/typed_graphql_server/doc/cancellation.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -103,9 +103,9 @@ For `ExecutableSchema.subscribe` the signal and the timeout last as long as
 the subscription. When one fires, the stream delivers one last result with the
 cancellation error, the source subscription is cancelled and the stream
 closes; the event being executed is dropped. A signal already cancelled at
-`subscribe` gives a `SubscriptionRejected` with `GQL350`. The timeout starts
-at `subscribe`; the listener on the caller's signal attaches when the response
-stream is listened to.
+`subscribe` gives a `SubscriptionRejected` with `GQL350`. The timeout and the
+listener on the caller's signal both start at `subscribe`, whether or not the
+response stream is ever listened to.
 
 ```dart
 import 'dart:async';
@@ -162,6 +162,9 @@ source cancelled: true
 ## Listen to the stream, or drop the signal
 
 A response stream that is never listened to has already called the source
-function and holds a listener on the caller's signal until that signal is
-cancelled. Listen to the stream, or cancel the signal, as soon as you decide
-not to use the subscription; a signal per request makes the second free.
+function and holds the timer and a listener on the caller's signal. When that
+signal is cancelled or the timeout elapses, the stream releases both, even
+though nobody listens. With neither a cancel nor a timeout, the listener stays
+on the caller's signal until the signal is cancelled or collected. Listen to
+the stream, or cancel the signal, as soon as you decide not to use the
+subscription; a signal per request makes the second free.
````

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/cancellation.md packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart packages/typed_graphql_server/lib/src/execution/run_cancellation.dart packages/typed_graphql_server/lib/src/execution/subscription_responses.dart packages/typed_graphql_server/test/cancellation/cancellation_fixture.dart packages/typed_graphql_server/test/cancellation/subscription_release_test.dart
git commit -q -m "fix(typed_graphql_server): release subscription cancellation without a listener" \
  -m "The run's own signal now disposes the timer and the caller listener when it fires; a finished stream stops listening to it; CancelSignal.addListener documents that listeners must not throw." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: Review fix: the M5d texts

The library doc says M5 is complete; `CLAUDE.md` says what `SelectionNodes` does and states the look-ahead step budget; the Authorization guide warns about a redeclared interface field; spec section 18 items 42 (rewritten), 43 (step budget) and 44 (merge key); CHANGELOG lines.

**Files:**
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `CLAUDE.md`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/authorization.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,8 +2,9 @@
 /// engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws
 /// and graphql-sse handlers.
 ///
-/// Under construction: the typed schema builder (M5a), query execution (M5b),
-/// introspection and subscriptions (M5c) work. See the package README.
+/// Under construction: stage M5 is complete (the typed schema builder,
+/// execution, introspection, subscriptions, look-ahead, authorization and
+/// cancellation); transports follow. See the package README.
 library;
 
 export 'src/authorization/authorization.dart';
```

- [ ] **Step 2: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -464,9 +464,16 @@ last result (`GQL340`), one that fails at start is a `SubscriptionRejected`.
 `subscription/` holds only the public `SubscriptionResult` family.
 `lookahead/` (M5d): `FieldInfo.selection` is a `FieldSelection` built on first
 read from the field's `FieldPlan` and the run (`FieldInfo.plan` and `run` are
-`@internal`, so an unread selection allocates nothing); `SelectionNodes` flattens
-fragments and applies `@skip`/`@include`, `forType` narrows an abstract type,
-every name starting with `__` is hidden. A `SelectedField` reads its
+`@internal`, so an unread selection allocates nothing). `FieldCollector`
+(`plan/`) flattens fragments and applies `@skip`/`@include`; `SelectionNodes`
+finds the plan nodes of a field's sub-selection, one per (field nodes, object
+type), so an abstract type costs its distinct nodes, not their product per
+level. `forType` narrows an abstract type, every name starting with `__` is
+hidden, and plans merge into one `SelectedField` by response key, field name
+and arguments. Every look-ahead walk spends the run's step counter
+(`LookAheadBudget`, over `ExecutionLimits.spend`): one that would pass
+`maxSteps` throws a `GraphQLException` with `GQL337`, the field's error, and
+spends nothing; a new walk must charge it. A `SelectedField` reads its
 `arguments` on first use (a failing argument reads absent; the executor
 reports it) and has its own `selection`. `SelectionFingerprint` (field names
 sorted, arguments as `CanonicalJson` with sorted keys, explicit stacks) is the
```

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -732,6 +732,17 @@ depends on the other). These constraints keep that possible:
     listened to, with no cancel and no timeout, keeps its listener on the
     caller's signal until that signal is cancelled or collected; the guide
     says to listen to the stream or drop the signal.
+43. Look-ahead walks spend the run's step counter (the one `maxSteps` limits).
+    Collecting a selection and building a fingerprint (by the size of its
+    text) charge it; a charge that would pass the limit spends nothing and
+    throws a `GraphQLException` with `GQL337` and the executor's step message,
+    which is the error of the field whose resolver read the selection, not a
+    halt. Plan nodes are listed once per (field nodes, object type) and a
+    fingerprint reads fields over the same nodes once, so a selection costs
+    in proportion to the request unless its text itself fans out.
+44. `SelectedField`s merge by response key, field name and printed arguments,
+    not by response key alone (spec 11): object types that cannot overlap may
+    give one alias to different fields, and `FieldsInSetCanMerge` allows it.
 
 ## 19. Conformance (R0.7, R10.3)
 
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Documentation: the barrel states that M5 is complete, the Authorization guide
  warns that a redeclared interface field is unguarded without its own rule.
```

In `packages/typed_graphql_server/doc/authorization.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -86,6 +86,12 @@ A rule on an interface field guards the implementations that inherit the field.
 An object that redeclares the field does not inherit the interface's rule: give
 it its own, or its type's.
 
+Security note: an object field that redeclares a guarded interface field is
+unguarded unless the field or its object type has a rule, so a query through
+the concrete type can reach data the interface protects. Declare the rule on
+the type, or check `AuthorizationCoverage`, which lists such a field as
+uncovered.
+
 ## Asynchronous decisions and deny messages
 
 `authorize` returns a `FutureOr`, so an authorizer may look the answer up in a
```

- [ ] **Step 3: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add CLAUDE.md docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/authorization.md packages/typed_graphql_server/lib/typed_graphql_server.dart
git commit -q -m "docs(typed_graphql_server): correct the M5d texts" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Final review fix: a subscription is authorized once

The final review found the authorizer guarding both the source and the per-event resolver of a `SubscribeLane`. `AuthorizationApplier` now guards only the source, so a guarded subscription is authorized once, at `subscribe` (spec section 18 item 45; open question 15). A test counts the authorizer calls across several events; the Authorization and Subscriptions guides say so.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/builder/authorization_applier.dart`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/authorization.md`, `packages/typed_graphql_server/doc/subscriptions.md`
- Test: `packages/typed_graphql_server/test/authorization/authorization_fixture.dart`, `packages/typed_graphql_server/test/authorization/authorization_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_server/test/authorization/authorization_fixture.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -142,7 +142,7 @@ final class AuthorizationFixture {
         t
             .field('tick', b.int)
             .withAuthorization(Authorization.requires(['admin']))
-            .subscribe((p, a, c, i) => Stream.value(1)),
+            .subscribe((p, a, c, i) => Stream.fromIterable([1, 2, 3])),
       ],
     );
     return b.build(
```

In `packages/typed_graphql_server/test/authorization/authorization_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -130,6 +130,16 @@ void main() {
     });
   });
 
+  test('a subscription is authorized once, not for every event', () async {
+    final result = await fixture.built.subscribe(
+      fixture.validDocument('subscription { tick }'),
+      context: const Caller({'admin'}),
+    );
+    final responses = await (result as SubscriptionStarted).results.toList();
+    expect(responses, hasLength(3));
+    expect(authorizer.calls, ['Subscription.tick']);
+  });
+
   group('rules', () {
     test('a type rule guards the fields without one', () async {
       final json = await fixture.run('{ account { id } }');
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/authorization/authorization_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/builder/authorization_applier.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -78,9 +78,10 @@ final class AuthorizationApplier<C> {
         }),
       ),
       ResolverLane(:final resolve) => ResolverLane(guard.guard(resolve)),
+      // Once per request, as for a query (spec 18.45).
       SubscribeLane(:final source, :final resolve) => SubscribeLane(
         guard.guard(source),
-        guard.guard(resolve),
+        resolve,
       ),
       final DeclaredOnlyLane lane => lane,
     }, rule);
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/authorization/authorization_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -743,6 +743,12 @@ depends on the other). These constraints keep that possible:
 44. `SelectedField`s merge by response key, field name and printed arguments,
     not by response key alone (spec 11): object types that cannot overlap may
     give one alias to different fields, and `FieldsInSetCanMerge` allows it.
+45. A subscription field's authorization guards the source only: the
+    authorizer runs once, at subscribe, not for each event. Authorization is
+    a per-request decision, as for a query; a per-event check would cost one
+    call per event and turn a revoked permission into a stream of GQL352
+    events. A server that must re-check per event does so in the event
+    resolver.
 
 ## 19. Conformance (R0.7, R10.3)
 
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- A subscription field's authorization runs once, at subscribe, not for each
  event.
```

Append to `packages/typed_graphql_server/doc/authorization.md`:

```markdown

## Subscriptions

A rule on a subscription field is checked once, when the subscription starts,
and not for each event. A server that must re-check per event does it in the
event resolver.
```

Append to `packages/typed_graphql_server/doc/subscriptions.md`:

```markdown

## Authorization

A rule on a subscription field is checked once, at subscribe; the events are
not authorized again.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/authorization.md packages/typed_graphql_server/doc/subscriptions.md packages/typed_graphql_server/lib/src/builder/authorization_applier.dart packages/typed_graphql_server/test/authorization/authorization_fixture.dart packages/typed_graphql_server/test/authorization/authorization_test.dart
git commit -q -m "fix(typed_graphql_server): authorize a subscription once, at subscribe" \
  -m "The guard wraps the source only; events are not authorized again." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: Final review fix: frozen coerced arguments

Coerced arguments are cached on the shared `FieldPlan`, so a resolver writing to `Arguments.coerced` changed later requests. Argument coercion now returns unmodifiable maps and lists (spec section 18 item 46); a test writes to `args.coerced` and checks that a second execution of the cached plan sees the original value.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart`, `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/value_coercion.dart`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/coercion/frozen_arguments_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/coercion/frozen_arguments_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  late ExecutableSchema<Object?> built;
  late ValidDocument document;
  var seen = <Object?>[];

  setUp(() {
    seen = [];
    final b = ExecutableSchemaBuilder<Object?>();
    final name = Arg('name', b.string);
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('greet', b.string.nullable, args: [name]).resolve((
          parent,
          args,
          context,
          info,
        ) {
          seen.add(args.coerced['name']);
          args.coerced['name'] = 'changed';
          return 'ok';
        }),
      ],
    );
    built = b.build(query: query);
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source('{ greet(name: "Ada") }')).requireDocument();
    document = ValidDocument.assumeValid(built.schema, parsed);
  });

  test('a resolver cannot write to the coerced arguments', () async {
    final payload = await built.execute(document, context: null);
    final errors = payload.toJson().toJson()['errors']! as List<Object?>;
    expect(errors, hasLength(1));
  });

  test('a later execution of the cached operation sees the original', () async {
    await built.execute(document, context: null);
    await built.execute(document, context: null);
    expect(seen, ['Ada', 'Ada']);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/frozen_arguments_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -51,7 +51,7 @@ final class ArgumentCoercion {
         return CoercionFailure([problem], hasOverflowed: false);
       }
     }
-    return CoercionSuccess(values);
+    return CoercionSuccess(Map<String, Object?>.unmodifiable(values));
   }
 
   CoercionProblem? _coerceOne(
```

In `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -33,7 +33,9 @@ final class InputObjectDecoder {
       return InvalidValue.instance;
     }
     try {
-      return definition.decode(Arguments(definition.fields, coerced));
+      return definition.decode(
+        Arguments(definition.fields, Map.unmodifiable(coerced)),
+      );
     } on GraphQLException catch (exception) {
       problems.add(exception.message, path, extensions: exception.extensions);
     } on Object catch (error, stackTrace) {
```

In `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -96,7 +96,9 @@ final class LiteralCoercion {
   Object? _list(Value literal, TypeRef item, InputPath path, int depth) {
     if (literal is! ListValue) {
       final single = coerce(literal, item, path, depth + 1);
-      return single is InvalidValue ? single : <Object?>[single];
+      return single is InvalidValue
+          ? single
+          : List<Object?>.unmodifiable([single]);
     }
     final result = <Object?>[];
     var isValid = true;
@@ -111,7 +113,7 @@ final class LiteralCoercion {
         result.add(coerced);
       }
     }
-    return isValid ? result : InvalidValue.instance;
+    return isValid ? List<Object?>.unmodifiable(result) : InvalidValue.instance;
   }
 
   Object? _named(Value literal, String name, InputPath path, int depth) =>
```

In `packages/typed_graphql_server/lib/src/coercion/value_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -67,7 +67,9 @@ final class ValueCoercion {
   Object? _list(JsonValue value, TypeRef item, InputPath path, int depth) {
     if (value is! JsonArray) {
       final single = coerce(value, item, path, depth + 1);
-      return single is InvalidValue ? single : <Object?>[single];
+      return single is InvalidValue
+          ? single
+          : List<Object?>.unmodifiable([single]);
     }
     final result = <Object?>[];
     var isValid = true;
@@ -79,7 +81,7 @@ final class ValueCoercion {
         result.add(coerced);
       }
     }
-    return isValid ? result : InvalidValue.instance;
+    return isValid ? List<Object?>.unmodifiable(result) : InvalidValue.instance;
   }
 
   Object? _named(JsonValue value, String name, InputPath path, int depth) =>
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/frozen_arguments_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -749,6 +749,11 @@ depends on the other). These constraints keep that possible:
     call per event and turn a revoked permission into a stream of GQL352
     events. A server that must re-check per event does so in the event
     resolver.
+46. Coerced arguments are frozen: the argument map, the map of each coerced
+    input object and each coerced list are unmodifiable. A plan caches the
+    arguments of a field without variables across requests, so a resolver
+    writing to `Arguments.coerced` would change later requests; it gets an
+    `UnsupportedError` instead.
 
 ## 19. Conformance (R0.7, R10.3)
 
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Coerced arguments are unmodifiable (the argument map, input-object maps and
  lists), so a resolver cannot change the cached arguments of later requests.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart packages/typed_graphql_server/lib/src/coercion/value_coercion.dart packages/typed_graphql_server/test/coercion/frozen_arguments_test.dart
git commit -q -m "fix(typed_graphql_server): freeze coerced arguments" \
  -m "The argument map, input-object maps and coerced lists are unmodifiable, so a resolver cannot change the arguments a plan caches." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 15: Final review fix: internal types out of the public API

`@internal` on the `ExecutableSchema` constructor (it takes the unexported `SchemaBindings`), on the `FieldDef` constructor, `lane` and `middleware`, and on `CancelSignal.listenerCount` (was `@visibleForTesting`).

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/builder/field_def.dart`, `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart`, `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/CHANGELOG.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql_server/lib/src/builder/field_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../authorization/authorization.dart';
@@ -12,7 +13,9 @@ import 'output_ref.dart';
 ///
 /// {@category builder}
 final class FieldDef<P, C> {
-  /// Declares the field [name] of type [type].
+  /// Declares the field [name] of type [type]; the builder calls it, so it
+  /// is not part of the public API.
+  @internal
   FieldDef({
     required this.name,
     required this.type,
@@ -45,12 +48,15 @@ final class FieldDef<P, C> {
   /// The directives applied to the field, besides `@deprecated`.
   final List<AppliedDirective> directives;
 
-  /// How the field produces its value.
+  /// How the field produces its value; not part of the public API.
+  @internal
   final FieldLane lane;
 
   /// The `FieldMiddleware<C>` values of the field, erased to [Object]: a
   /// definition read as `FieldDef<Object?, Object?>` must not hold a
-  /// `C`-typed function. The build casts them back where `C` is known.
+  /// `C`-typed function. The build casts them back where `C` is known; not
+  /// part of the public API.
+  @internal
   final List<Object> middleware;
 
   /// The authorization rule that applies to the field: its own, else (after
```

In `packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -29,7 +29,7 @@ final class CancelSignal {
   Future<void> get whenCancelled => _completer.future;
 
   /// How many listeners wait for the signal.
-  @visibleForTesting
+  @internal
   int get listenerCount => _listeners?.length ?? 0;
 
   /// Cancels the signal with an optional [reason]. Only the first call has
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,7 +19,9 @@ import 'subscription_execution.dart';
 ///
 /// {@category execution}
 final class ExecutableSchema<C> {
-  /// Creates the schema from a validated [schema] and its [bindings].
+  /// Creates the schema from a validated [schema] and its [bindings]; the
+  /// builder calls it, so it is not part of the public API.
+  @internal
   ExecutableSchema(
     this.schema,
     this.bindings, {
```

- [ ] **Step 2: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- The `ExecutableSchema` and `FieldDef` constructors, `FieldDef.lane`,
  `FieldDef.middleware` and `CancelSignal.listenerCount` are `@internal`.
```

- [ ] **Step 3: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/builder/field_def.dart packages/typed_graphql_server/lib/src/cancellation/cancel_signal.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart
git commit -q -m "fix(typed_graphql_server): keep internal types out of the public API" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 16: Final review fix: the halt error wins over a later cancel

`ExecutionRun` answered `GQL350` when the caller cancelled after a halt while started resolvers were awaited. The halt error now wins; spec section 18 item 38 says so; a test halts, cancels and checks the halt error.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -80,6 +80,20 @@ void main() {
       expect(result.errors, hasLength(1));
     });
 
+    test('after a halt keeps the halt error', () async {
+      final probe = Probe();
+      final signal = CancelSignal();
+      final pending = fixture.execute(
+        '{ slow sync after }',
+        probe,
+        options: ExecutionOptions(cancelSignal: signal, maxSteps: 1),
+      );
+      signal.cancel();
+      final result = await (pending as Future<ResponsePayload>);
+      probe.gate.complete();
+      expect(CancellationFixture.codeOf(result), 'GQL337');
+    });
+
     test('starts no field after it', () async {
       final probe = Probe();
       final signal = CancelSignal();
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/execute_cancellation_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -126,18 +126,20 @@ final class ExecutionRun {
       return _response(data);
     }
     final response = data.then(_response);
-    return cancellation?.race(response) ?? response;
+    return cancellation?.race(response, () => _response(null)) ?? response;
   }
 
-  // A call cancelled meanwhile answers with the cancellation only (spec 13).
+  // A halt wins over a cancellation that arrives after it: the limit is the
+  // cause, the cancel only cut the wait (spec 18.38). Otherwise a call
+  // cancelled meanwhile answers with the cancellation only (spec 13).
   ExecutionResult _response(JsonObject? data) {
-    if (cancellation case final cancelled? when cancelled.isCancelled) {
-      return cancelled.result;
-    }
     final log = reporter.log;
     if (log.haltError case final halted?) {
       return ExecutionResult(null, errors: [halted]);
     }
+    if (cancellation case final cancelled? when cancelled.isCancelled) {
+      return cancelled.result;
+    }
     return ExecutionResult(data, errors: log.errors);
   }
 
```

In `packages/typed_graphql_server/lib/src/execution/run_cancellation.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,15 +64,18 @@ final class RunCancellation {
   /// The response of a cancelled run: no data and [error].
   ExecutionResult get result => ExecutionResult(null, errors: [error]);
 
-  /// [pending], or the cancelled [result] as soon as the run is cancelled.
-  Future<ExecutionResult> race(Future<ExecutionResult> pending) {
+  /// [pending], or [cancelledResult] as soon as the run is cancelled.
+  Future<ExecutionResult> race(
+    Future<ExecutionResult> pending,
+    ExecutionResult Function() cancelledResult,
+  ) {
     if (isCancelled) {
-      return Future.value(result);
+      return Future.value(cancelledResult());
     }
     final completer = Completer<ExecutionResult>();
     final detach = signal.addListener(() {
       if (!completer.isCompleted) {
-        completer.complete(result);
+        completer.complete(cancelledResult());
       }
     });
     pending.then(
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/cancellation/execute_cancellation_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -716,7 +716,9 @@ depends on the other). These constraints keep that possible:
     `__typename`.
 38. The executor races the pending result against cancellation once, at the
     root, and checks `isCancelled` before it starts each field. A resolver
-    already running is not interrupted; its result is dropped.
+    already running is not interrupted; its result is dropped. A halt (for
+    example `GQL337`) wins over a cancellation that arrives after it: the
+    response carries the halt error, not `GQL350`.
 39. Request errors win over an already-cancelled signal: an unknown
     operation or unusable variables are a `RequestErrorResult`, and no timer
     starts for them.
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- A run that halted (for example `GQL337`) and is then cancelled answers with
  the halt error, not `GQL350`.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/execution/execution_run.dart packages/typed_graphql_server/lib/src/execution/run_cancellation.dart packages/typed_graphql_server/test/cancellation/execute_cancellation_test.dart
git commit -q -m "fix(typed_graphql_server): keep the halt error when a halted run is cancelled" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 17: Final review fix: ColumnAllowlist

`ColumnWhitelist` is renamed `ColumnAllowlist` (file, test, barrel, guide, README, CHANGELOG, spec, HANDOFF), as the repository says "allowlist" everywhere else.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/lookahead/column_allowlist.dart`
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `docs/requirements.md`, `docs/superpowers/HANDOFF.md`, `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/README.md`, `packages/typed_graphql_server/doc/lookahead.md`
- Test: `packages/typed_graphql_server/test/lookahead/column_allowlist_test.dart`
- Delete (with `git rm` in the commit step): `packages/typed_graphql_server/lib/src/lookahead/column_whitelist.dart`, `packages/typed_graphql_server/test/lookahead/column_whitelist_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// lookahead/column_allowlist.dart
final class ColumnAllowlist
  ColumnAllowlist(…)
  List<String> columnsFor(FieldSelection selection)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/lookahead/column_allowlist_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'look_ahead_fixture.dart';

void main() {
  final f = LookAheadFixture();
  final allowlist = ColumnAllowlist(
    {'name': 'full_name', 'friend': 'friend_id', 'alias': 'full_name'},
    always: ['id'],
  );

  test('gives the sorted columns of the fields the map knows', () async {
    final selection = await f.selection(
      'user',
      '{ user { friend { name } name } }',
    );
    expect(allowlist.columnsFor(selection), ['friend_id', 'full_name', 'id']);
  });

  test('ignores the fields the map does not know', () async {
    final selection = await f.selection('user', '{ user { posts { title } } }');
    expect(allowlist.columnsFor(selection), ['id']);
  });

  test('lists a column once when two fields share it', () async {
    final both = ColumnAllowlist({'name': 'n', 'friend': 'n'});
    final selection = await f.selection(
      'user',
      '{ user { name friend { name } } }',
    );
    expect(both.columnsFor(selection), ['n']);
  });

  test('adds the always columns to an empty selection', () {
    expect(allowlist.columnsFor(FieldSelection.empty), ['id']);
  });

  test('reads names, so an alias does not hide a column', () async {
    final selection = await f.selection('user', '{ user { shown: name } }');
    expect(allowlist.columnsFor(selection), ['full_name', 'id']);
  });
}
```

- [ ] **Step 2: Write the implementation**

Create `packages/typed_graphql_server/lib/src/lookahead/column_allowlist.dart`:

```dart
import 'field_selection.dart';

/// Maps GraphQL field names to database columns, so a resolver selects only
/// the columns the request needs (R4.18). It reads a [FieldSelection]; it
/// preloads nothing and writes no SQL.
///
/// {@category lookahead}
final class ColumnAllowlist {
  /// Maps each field name in [columns] to its column; the [always] columns
  /// are in every answer (a key, say).
  ColumnAllowlist(Map<String, String> columns, {List<String> always = const []})
    : _columns = Map.unmodifiable(columns),
      _always = List.unmodifiable(always);

  final Map<String, String> _columns;
  final List<String> _always;

  /// The columns of the fields [selection] selects at its own level that the
  /// map knows, plus the always ones, sorted and without repeats. Fields the
  /// map does not know are ignored.
  List<String> columnsFor(FieldSelection selection) {
    final columns = <String>{..._always};
    for (final field in selection.fields) {
      if (_columns[field.name] case final column?) {
        columns.add(column);
      }
    }
    return columns.toList()..sort();
  }
}
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -47,7 +47,7 @@ export 'src/execution/field_site.dart';
 export 'src/execution/graphql_exception.dart';
 export 'src/execution/response_path.dart';
 export 'src/introspection/introspection_policy.dart';
-export 'src/lookahead/column_whitelist.dart';
+export 'src/lookahead/column_allowlist.dart';
 export 'src/lookahead/field_selection.dart';
 export 'src/lookahead/selected_field.dart';
 export 'src/subscription/subscription_result.dart';
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/lookahead/column_allowlist_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Update the documents**

In `docs/requirements.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -88,7 +88,7 @@ stage.
 | R4.15 | DataLoader: `BatchLoader`, `GroupedLoader`, request-scoped, microtask dispatch plus level flush | MUST | M6 |
 | R4.16 | `executeIncrementally` for `@defer` / `@stream` | MUST | M14 |
 | R4.17 | Allocation and throughput benchmarks of the executor | MUST | M5 |
-| R4.18 | Look-ahead: `info.selection`, a tree of the requested fields computed once from the `OperationPlan` (fragments flattened, `@skip` / `@include` applied, type conditions resolved with `forType`, aliases and arguments per occurrence, `__typename` hidden, a `fingerprint` per sub-selection usable as a DataLoader key, `@defer`red fields flagged `isDeferred`); string-path access (`has('posts.comments')`, children and arguments accessors); typed field handles only if the builder yields them at no extra cost. The field-to-column mapping lives at the call site; the library offers only a whitelist helper and no built-in preload | MUST | M5 |
+| R4.18 | Look-ahead: `info.selection`, a tree of the requested fields computed once from the `OperationPlan` (fragments flattened, `@skip` / `@include` applied, type conditions resolved with `forType`, aliases and arguments per occurrence, `__typename` hidden, a `fingerprint` per sub-selection usable as a DataLoader key, `@defer`red fields flagged `isDeferred`); string-path access (`has('posts.comments')`, children and arguments accessors); typed field handles only if the builder yields them at no extra cost. The field-to-column mapping lives at the call site; the library offers only an allowlist helper and no built-in preload | MUST | M5 |
 | R4.19 | `Authorizer`: a typed hook called by the executor around field resolution and exposed to look-ahead and the pipeline, plus a lint / test helper that reports schema fields and types with no authorization coverage; no policy engine | MUST | M5 |
 | R4.20 | `CancelSignal` in the execution context, observable by resolvers; an execution timeout in the pipeline options; cancellation and timeout reported as errors with stable codes (`GQL3xx`); subscriptions end on cancellation | MUST | M5 |
 
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
-| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md); M5d: [plan](plans/2026-10-15-m5d-lookahead-authorization-cancellation.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; M5d is done on the same branch: `FieldInfo.selection` (look-ahead, `ColumnWhitelist`), `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`, `GQL352`), `CancelSignal`, `timeout` and `FieldInfo.cancelSignal` (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor benchmark, spec §18 items 34-44 and the Look-ahead, Authorization and Cancellation guides. **Stage M5 is complete on `m5-final`; it is not merged and not pushed.** Next: the final whole-branch review, then the merge (needs the owner's yes). Open questions for the owner are spec §21, with recommendations in `.superpowers/m5-open-questions.md` (local, untracked, in the worktree) |
+| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md); M5d: [plan](plans/2026-10-15-m5d-lookahead-authorization-cancellation.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; M5d is done on the same branch: `FieldInfo.selection` (look-ahead, `ColumnAllowlist`), `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`, `GQL352`), `CancelSignal`, `timeout` and `FieldInfo.cancelSignal` (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor benchmark, spec §18 items 34-44 and the Look-ahead, Authorization and Cancellation guides. **Stage M5 is complete on `m5-final`; it is not merged and not pushed.** Next: the final whole-branch review, then the merge (needs the owner's yes). Open questions for the owner are spec §21, with recommendations in `.superpowers/m5-open-questions.md` (local, untracked, in the worktree) |
 | M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete on branch `m10-final`: the final opus whole-branch review is done and its fix round is committed; awaiting merge, not merged and not pushed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
```

In `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -288,7 +288,7 @@ final schema = b.build(query: queryType, mutation: mutationType); // ExecutableS
   offers string paths (`has('posts.comments')`, children and arguments
   accessors); typed handles (`has(user.posts)`) only if the builder yields them at
   no extra cost. The field-to-column (SQL) mapping lives at the call site, never
-  in the schema; the library offers only a small whitelist helper from requested
+  in the schema; the library offers only a small allowlist helper from requested
   field names to columns. There is no built-in preload (the parent loaded a
   relation, the child reads it): the pattern is documented. Generated selection
   classes come with codegen (M8).
```

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,7 +45,7 @@ and the executor reads the builder's definitions, so `builder/` and
 | `execution/` | `ExecutableSchema.execute`, the executor, errors, `ExecutionOptions`, `FieldInfo`, middleware composition | M5a (`FieldInfo`, `ExecutableSchema`), M5b |
 | `introspection/` | the `__Schema` family as object types, `IntrospectionPolicy` | M5c |
 | `subscription/` | `subscribe`, `SubscriptionResult` | M5c |
-| `lookahead/` | `FieldSelection`, `SelectedField`, `ColumnWhitelist` | M5d |
+| `lookahead/` | `FieldSelection`, `SelectedField`, `ColumnAllowlist` | M5d |
 | `authorization/` | `Authorizer`, `Authorization`, `AuthorizationCoverage` | M5d |
 | `cancellation/` | `CancelSignal` | M5d |
 
@@ -427,7 +427,7 @@ member is read.
 - `fingerprint`: a canonical string of the sub-selection (field names
   sorted, arguments printed in sorted key order, children nested), usable
   as a DataLoader key; built with an explicit stack.
-- `ColumnWhitelist({fieldName: column}, {always})`:
+- `ColumnAllowlist({fieldName: column}, {always})`:
   `columnsFor(selection)` gives the sorted, de-duplicated columns of the
   requested fields the map knows, plus `always`. No preload, no SQL.
 - Typed handles (`has(user.posts)`): not in M5; the builder does not
```

In `packages/typed_graphql_server/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -100,7 +100,7 @@
   `fields`, `forType`, `has('posts.comments')`, `fieldsNamed` and
   `fingerprint` (canonical, for DataLoader keys); `SelectedField` has `name`,
   `alias`, `responseKey`, `arguments` (coerced on first read; an argument that
-  fails reads as absent) and its own `selection`. `ColumnWhitelist` maps field
+  fails reads as absent) and its own `selection`. `ColumnAllowlist` maps field
   names to sorted, de-duplicated columns. `isDeferred` arrives with
   incremental delivery.
 - The Look-ahead guide and its dartdoc category `lookahead`.
```

In `packages/typed_graphql_server/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -143,7 +143,7 @@ It prints:
 - [Subscriptions](doc/subscriptions.md): source streams, one event at a time,
   rejected and failed subscriptions.
 - [Look-ahead](doc/lookahead.md): the fields a request selected under a field,
-  `fingerprint` as a DataLoader key, `ColumnWhitelist`.
+  `fingerprint` as a DataLoader key, `ColumnAllowlist`.
 - [Authorization](doc/authorization.md): rules on fields and types, the
   `Authorizer`, deny messages, `AuthorizationCoverage`.
 - [Cancellation](doc/cancellation.md): `CancelSignal`, timeouts, what
```

In `packages/typed_graphql_server/doc/lookahead.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -135,7 +135,7 @@ the rest of the execution goes on. Fields over the same field nodes are read
 once, so a selection whose aliases use the same arguments costs time in
 proportion to the request, not to its expansion.
 
-`ColumnWhitelist` turns a selection into database columns. It maps field
+`ColumnAllowlist` turns a selection into database columns. It maps field
 names to columns, adds the `always` columns (a key, say), ignores the fields
 it does not know and returns the sorted, de-duplicated list. It preloads
 nothing and writes no SQL: the resolver builds the query.
@@ -154,7 +154,7 @@ Future<void> main() async {
       t.field('email', b.string).pure((_) => 'ada@example.com'),
     ],
   );
-  final columns = ColumnWhitelist(
+  final columns = ColumnAllowlist(
     {'name': 'full_name', 'email': 'email_address'},
     always: ['id'],
   );
```

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git rm -q packages/typed_graphql_server/lib/src/lookahead/column_whitelist.dart packages/typed_graphql_server/test/lookahead/column_whitelist_test.dart
git add docs/requirements.md docs/superpowers/HANDOFF.md docs/superpowers/specs/2026-10-13-typed-graphql-design.md docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/README.md packages/typed_graphql_server/doc/lookahead.md packages/typed_graphql_server/lib/src/lookahead/column_allowlist.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/lookahead/column_allowlist_test.dart
git commit -q -m "refactor(typed_graphql_server): rename ColumnWhitelist to ColumnAllowlist" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 18: Final review fix: the stage documents

An erratum in the M5a plan (merge 6e5bd05 replaced the server's `Optional` with the core's) and a note on the M5b plan's base; spec section 12 names `BuildOptions.authorizer`; spec section 18 item 36 says a look-ahead `decode` error reaches `onError` only when the field runs; HANDOFF says M10 is on `main` and records the 11 commits with a Sonnet trailer.

**Files:**
- Modify: `docs/superpowers/HANDOFF.md`, `docs/superpowers/plans/2026-10-15-m5a-typed-builder.md`, `docs/superpowers/plans/2026-10-15-m5b-execution-core.md`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,10 +1,15 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M5 (a-d) complete on branch `m5-final`, not merged; M10 complete on branch `m10-final`, awaiting merge (not merged); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
+Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b merged too; M5 (a-d) complete on branch `m5-final`, not merged; M10 complete and merged into `main` (3d1fe38); local `main` is ahead of `origin/main`, push needs the owner's yes). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
 
+Note: 11 M5 commits carry a `Claude Sonnet 5.5` trailer (585a4f0, 1b36f23,
+db33dc7, 62ba263, cb78cf6, 8be71bd, 6981a03, 6c0dc4d, 383fa6a, f469521,
+901adfc). They are left as they are: rewriting them would cross the merge
+6e5bd05 and change SHAs that the plans quote.
+
 ## State
 
 | Stage | Design | Plan | Code |
@@ -17,7 +22,7 @@ needed.
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
 | M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md); M5c: [plan](plans/2026-10-15-m5c-introspection-and-subscriptions.md); M5d: [plan](plans/2026-10-15-m5d-lookahead-authorization-cancellation.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; M5d is done on the same branch: `FieldInfo.selection` (look-ahead, `ColumnAllowlist`), `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`, `GQL352`), `CancelSignal`, `timeout` and `FieldInfo.cancelSignal` (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor benchmark, spec §18 items 34-44 and the Look-ahead, Authorization and Cancellation guides. **Stage M5 is complete on `m5-final`; it is not merged and not pushed.** Next: the final whole-branch review, then the merge (needs the owner's yes). Open questions for the owner are spec §21, with recommendations in `.superpowers/m5-open-questions.md` (local, untracked, in the worktree) |
-| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete on branch `m10-final`: the final opus whole-branch review is done and its fix round is committed; awaiting merge, not merged and not pushed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
+| M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete and merged into `main` (3d1fe38; not pushed): the final opus whole-branch review is done and its fix round is committed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
```

In `docs/superpowers/plans/2026-10-15-m5a-typed-builder.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,7 @@
 # M5a Typed Schema Builder Implementation Plan
 
+> **Erratum.** Superseded by merge 6e5bd05: the server's `Optional` was removed; `Arg.optional` uses the core's `Optional` from `package:typed_graphql`. The file `builder/optional.dart`, its export line and its `import 'optional.dart'` lines no longer exist.
+
 > **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
 
 **Goal:** Start `typed_graphql_server` with the typed schema builder (R4.1, R4.2, R0.2, R0.3): `ExecutableSchemaBuilder<C>` and its typed refs (`OutputRef`, `InputRef`, `LeafRef`), scalars, enums, typed arguments and input objects (`Arg`, `Arguments`, `Optional`, `@oneOf`), object types with two-step typed fields (`t.field(name, ref).pure|resolve|resolveWith|declareOnly`), interfaces and unions with inheritance and `resolveType` / `isTypeOf`, and `build`, which runs the builder checks `GQL300`-`GQL302` and the core `SchemaValidator` and returns an `ExecutableSchema<C>` or throws `SchemaBuildError`. Compile-failure fixtures prove that a wrong resolver type does not compile. The Schema Builder guide, the server documentation suite, CHANGELOG, README, `llms.txt` and `CLAUDE.md` describe it.
@@ -299,6 +301,8 @@ git commit -q -m "feat(typed_graphql): add the M5a diagnostic codes and export S
 
 ### Task 2: Refs, scalars, enums and `Optional`
 
+> **Erratum.** Superseded by merge 6e5bd05: the server's `Optional` was removed; `Arg.optional` uses the core's `Optional` from `package:typed_graphql`. The file `builder/optional.dart`, its export line and its `import 'optional.dart'` lines no longer exist.
+
 Create the package's type references (`NamedTypeDef`, `OutputRef`, `InputRef`, `LeafRef` and their nullable and list forms), custom scalars over a `ScalarCodec`, Dart-enum-backed enum types with `EnumValueMapping`, `Optional` (`Present` / `Absent`), the built-in scalar getters, the `DefinitionRegistry` and the `ExecutableSchemaBuilder<C>` entry point. Add the server's external-imports quality test.
 
 **Files:**
```

In `docs/superpowers/plans/2026-10-15-m5b-execution-core.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,6 +12,8 @@
 
 **Base:** the M5a plan (`2026-10-15-m5a-typed-builder.md`) applied, on branch `m5-final` at `8d59203`. The plan was verified by applying its tasks in order, one commit per task, with the green check after each and the server and core suites on exe at the end.
 
+`Optional<…>` now comes from the core (`package:typed_graphql`), since merge 6e5bd05; the plan's text and code stay as committed.
+
 ## Global Constraints
 
 - `CLAUDE.md` is binding. The code rules apply to tests too:
```

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -447,7 +447,7 @@ member is read.
   context, the `FieldInfo` (and so the look-ahead) and the requirements.
   A deny is a field error (`GQL352`, default message `Not authorized to
   access Type.field.`); an authorizer exception is masked.
-- `ExecutableSchema.authorizer` is set by `build(authorizer:)`; a schema
+- `ExecutableSchema.authorizer` is set by `BuildOptions.authorizer`; a schema
   with guarded fields and no authorizer is a build error (`GQL304`).
 - `AuthorizationCoverage(executableSchema).uncovered`: the coordinates
   (`Type.field`) of fields with no authorization on the field or its type,
@@ -711,7 +711,9 @@ depends on the other). These constraints keep that possible:
 36. `SelectedField.arguments` reads an argument whose value fails coercion
     as absent. Reading a required one then throws, which the resolver's
     error masking turns into `GQL330`; the executor reports the real
-    coercion error when that field runs, so no problem is silent.
+    coercion error when that field runs, so no problem is silent. Reading
+    `arguments` in look-ahead runs the user `decode`; what it throws there is
+    dropped, and `onError` sees it only when the field itself runs.
 37. Look-ahead hides every meta field (a name starting with `__`), not only
     `__typename`.
 38. The executor races the pending result against cancellation once, at the
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add docs/superpowers/HANDOFF.md docs/superpowers/plans/2026-10-15-m5a-typed-builder.md docs/superpowers/plans/2026-10-15-m5b-execution-core.md docs/superpowers/specs/2026-10-15-m5-execution-design.md
git commit -q -m "docs: record the M5 final review" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 19: Final review fix: core changelog order

The core CHANGELOG groups the M5 entries before the M10 ones, every line kept.

**Files:**
- Modify: `packages/typed_graphql/CHANGELOG.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -272,6 +272,11 @@
 - `GQL303`, `GQL324`, `GQL338`, `GQL340`: the diagnostics of introspection and subscriptions (misplaced or missing subscription source, `subscribe` with a query or mutation, introspection not allowed, failed subscription source).
 - `GQL304`, `GQL350`, `GQL351`, `GQL352`: the diagnostics of authorization and cancellation (guarded fields without an authorizer, execution cancelled, execution timed out, field not authorized).
 - The messages of the built-in scalar codecs print an offending list or object as graphql-js does (`[1, 2, 3]`, `{ a: 1 }`, at most ten items, nested containers cut at depth two), not as compact JSON.
+- `IntrospectionListing`: which types and directives introspection lists for
+  a schema, and in which order (the order `Schema.toIntrospection` writes);
+  the server's introspection resolvers share it.
+- `ProvidedRequiredArgumentsRule` names the missing argument of `__type`
+  `<meta>.__type(name:)`, as graphql-js.
 - The catalog has the code generator's codes `GQL500`-`GQL506`: configuration
   syntax and content, schema input, anonymous operations, unsupported
   constructs, unknown scalar mappings and no documents (a warning).
@@ -280,8 +285,3 @@
   code uses).
 - The catalog adds `GQL511` (an operation or fragment that would generate
   too many classes).
-- `IntrospectionListing`: which types and directives introspection lists for
-  a schema, and in which order (the order `Schema.toIntrospection` writes);
-  the server's introspection resolvers share it.
-- `ProvidedRequiredArgumentsRule` names the missing argument of `__type`
-  `<meta>.__type(name:)`, as graphql-js.
```

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md
git commit -q -m "docs(typed_graphql): group the M5 changelog entries before the M10 ones" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 20: Final review fix: CLAUDE.md and open question 15

`CLAUDE.md` says `ColumnAllowlist`, that a guarded subscription is authorized once and that coerced arguments are unmodifiable; spec section 21 adds open question 15 (when a guarded subscription is authorized).

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,7 +56,7 @@ example. M5c (introspection and subscriptions) delivers the `__schema` and
 source streams and rejected requests (`GQL324`, `GQL340`), the graphql-js
 introspection and subscribe suites, and the Introspection and Subscriptions
 guides. M5d (look-ahead, authorization, cancellation) delivers
-`FieldInfo.selection` (`FieldSelection`, `SelectedField`, `ColumnWhitelist`),
+`FieldInfo.selection` (`FieldSelection`, `SelectedField`, `ColumnAllowlist`),
 `Authorization`, `Authorizer` and `AuthorizationCoverage` (`GQL304`,
 `GQL352`), `CancelSignal` with `ExecutionOptions.cancelSignal` and `timeout`
 (`GQL350`, `GQL351`), the graphql-js cancellation suite, the executor
@@ -438,8 +438,9 @@ throws `SchemaBuildError`. Its guides are in `packages/typed_graphql_server/doc/
 `LiteralCoercion` (substitutes variables); a `CoercionProblem` carries its
 code and the `GraphQLException` extensions. `plan/`: `OperationPlanner` turns
 a document into an `OperationPlan` (fields per `ConditionKey`, constant
-arguments coerced once) kept in `ExecutableSchema.planCache`; request errors
-are never cached. `execution/`: `OperationExecution` runs a plan through
+arguments coerced once, as unmodifiable maps and lists, since a cached plan
+is shared by every request: spec §18 item 46) kept in
+`ExecutableSchema.planCache`; request errors are never cached. `execution/`: `OperationExecution` runs a plan through
 `ExecutionRun`, `SelectionExecutor`/`SerialFields`, `FieldExecution` (the one
 place a resolver lane is called, where middleware composed at build time
 lives) and `ValueCompletion` with its leaf, list, object and abstract
@@ -477,15 +478,17 @@ spends nothing; a new walk must charge it. A `SelectedField` reads its
 `arguments` on first use (a failing argument reads absent; the executor
 reports it) and has its own `selection`. `SelectionFingerprint` (field names
 sorted, arguments as `CanonicalJson` with sorted keys, explicit stacks) is the
-DataLoader key; `ColumnWhitelist` maps field names to sorted columns.
+DataLoader key; `ColumnAllowlist` maps field names to sorted columns.
 `authorization/` (M5d): `Authorization` is sealed (`public`, `requires`); a
 rule is set by `FieldStub.withAuthorization` or `ObjectOptions.authorization`
 (the field's own wins) and applied after middleware composition by
 `builder/AuthorizationApplier` and `FieldGuard`, which wrap the composed lane
 so the `Authorizer<C>` (in `BuildOptions.authorizer`) runs before middleware
-on every lane, a pure field included. A deny is `GQL352`, a missing authorizer
-one `GQL304` listing the coordinates; introspection fields are never guarded;
-a redeclared interface field does not inherit the interface's rule.
+on every lane, a pure field included; a subscription field's rule guards only
+its source, so it is authorized once, at `subscribe` (spec §18 item 45). A
+deny is `GQL352`, a missing authorizer one `GQL304` listing the coordinates;
+introspection fields are never guarded; a redeclared interface field does not
+inherit the interface's rule.
 `AuthorizationCoverage` lists unguarded fields for a test.
 `cancellation/` (M5d): `CancelSignal` is the caller's plain class (no
 platform import); `execution/RunCancellation` links it with the timeout into
```

Append to `docs/superpowers/specs/2026-10-15-m5-execution-design.md`:

```markdown
15. **When a guarded subscription is authorized.** Once, at `subscribe`:
    the rule guards the source, not each event (recommended: one decision
    per request, as for a query, and no authorizer call per event; section
    18 item 45) or on every event, a deny becoming a `GQL352` error in that
    event's result while the stream goes on.
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add CLAUDE.md docs/superpowers/specs/2026-10-15-m5-execution-design.md
git commit -q -m "docs: record the M5 review fixes in CLAUDE.md and the open questions" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

- The full list, with recommendations, is section 21 of the spec and `.superpowers/m5-open-questions.md`. M5d's behaviour differences are spec section 18, items 34-44.

## Self-review

- Spec coverage: section 11 (look-ahead) by Task 2; 12 (authorization) by Task 3; 13 (cancellation) by Tasks 4 and 6; 14 (benchmarks) by Task 7; 15 (codes) by Task 1; 18 by Tasks 6 and 8; 19 by Task 5; 20 by Task 9. Tasks 10-12 answer the M5d review: bounded look-ahead, released subscription cancellation, corrected texts.
- Every code block is the committed text that passed the green check; no placeholder remains.
- Names are consistent across tasks: `FieldSelection`, `SelectedField`, `ColumnWhitelist`, `Authorization`, `Authorizer`, `AuthorizationCoverage`, `CancelSignal`, `RunCancellation`.
- Tasks 13-20 answer the M5 final whole-branch review: subscription authorization once at subscribe, frozen coerced arguments, `@internal` on internal types, the halt error over a later cancel, `ColumnAllowlist`, the stage documents and `CLAUDE.md`.

## After the plan

Stage M5 is complete on `m5-final`, with the final whole-branch review answered (Tasks 13-20). Merging `m5-final` into `main` and pushing need the owner's explicit yes. M6 adds the request pipeline and DataLoader.
