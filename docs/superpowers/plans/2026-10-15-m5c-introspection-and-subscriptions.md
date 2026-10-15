# M5c Introspection and Subscriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Answer introspection and run subscriptions on an `ExecutableSchema` (R4.7, R4.8, R0.3): `__schema` and `__type(name:)` on the query root resolved over the core model so that executing `IntrospectionQuery.full` gives exactly `Schema.toIntrospection`, with `IntrospectionPolicy` (`GQL338`); `FieldStub.subscribe` / `subscribeWith`, the build check `GQL303`, `ExecutableSchema.subscribe` returning `SubscriptionStarted(Stream<ExecutionResult>)` or `SubscriptionRejected` (`GQL324`), one event at a time, cancellation passed to the source, and a final `GQL340` result for a failing source; the graphql-js introspection, subscribe and simplePubSub suites ported; the Introspection and Subscriptions guides.

**Architecture:** Introspection is ordinary execution: `lib/src/introspection/` holds internal pure-lane field tables for `__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue` and `__Directive` and the `__TypeKind` / `__DirectiveLocation` enums, registered in `SchemaBindings` after middleware composition (so middleware never wraps them); a list or non-null type is an `IntrospectedType` wrapper; `EntryFields` gives the planner the `SchemaField`s of `__schema` and `__type` on the query root only. The core exports `IntrospectionListing` (in its own commit), so both sides list types and directives in the same order. Subscriptions share `OperationPreparation` (plan, root value, variables) with `execute`; `SubscriptionExecution` opens the root field's source through `FieldExecution.openSource` (a throw or failed future is a `SubscriptionRejected`), and `SubscriptionResponses` maps events through a `StreamController` whose listen, pause, resume and cancel reach the source, pausing the source while an event executes. Middleware wraps the per-event resolver, never the source function.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5), `package:test`, `package:meta`, the core `typed_graphql`. graphql-js 17.0.2 in `reference/graphql-js` (`type/introspection.ts`, `execution/execute.ts` `subscribe`, `__tests__/subscribe-test.ts`, `simplePubSub.ts`).

**Spec:** `docs/superpowers/specs/2026-10-15-m5-execution-design.md` (sections 9, 10, 15, 18, 19, 20), `docs/requirements.md` R4.7 and R4.8.

**Base:** the M5b plan (`2026-10-15-m5b-execution-core.md`) applied, then `main` with M10 merged into `m5-final` (6e5bd05: the server uses the core's `Optional` since then), at `af3ebfb`. The plan was verified by applying its tasks in order, one commit per task, with the green check after each and the server and core suites on exe at the end.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too.
- The server imports the core only through its barrel, and `lib/` imports no platform library but `dart:async`, `dart:collection`, `dart:core` and `dart:math` (spec section 17).
- Bad input never throws (R0.3): a bad subscription request is a `SubscriptionRejected`, a failing source a final `GQL340` result. Only programmer errors throw (`GQL303` through `SchemaBuildError`).
- A subscription never leaks: cancelling the response cancels the source; the source's done or error closes the response once; events run one at a time.
- Core changes go in their own commits (Tasks 1, 2 and 5). New codes go into `DiagnosticCode` in id order, with a doc comment.
- A ported graphql-js test is recorded in `packages/typed_graphql_conformance/mapping/execution.csv` in the same commit, and a behaviour difference goes into the spec's section 18.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time. Chrome cannot start under `ulimit -v`; bound the browser runs by resident memory with `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- `reference/` (git-ignored) holds graphql-js; fetch it with `tool/fetch_reference.sh` before the conformance task. Never `git add` it.

## Review Focus

1. Executing `IntrospectionQuery.full.text` equals `schema.toIntrospection(IntrospectionQuery.full)` for a schema with every kind. Task 3 (`introspection_test.dart`).
2. `IntrospectionPolicy.disabled` refuses `__schema` and `__type` with `GQL338` and still answers `__typename`; introspection is answered on the query root only. Task 3.
3. A subscription's response stream: cancel reaches the source (`onCancel`), events come in order with async resolvers, a source error gives one final `GQL340` result and closes, a throwing or failing source function is a `SubscriptionRejected` that `onError` sees. Task 4 (`subscription_test.dart`).
4. `GQL303` both ways: a source outside the subscription root, a subscription root field without one. Task 4 (`subscription_fields_test.dart`).

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/schema/introspection/introspection_listing.dart` | Create | 2 |
| `packages/typed_graphql/test/schema/introspection/introspection_listing_test.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/execution/introspection_policy.dart` | Create, then Delete | 3, 8 |
| `packages/typed_graphql_server/lib/src/introspection/entry_fields.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/introspection/introspected_type.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart` | Create, then Modify | 3, 12 |
| `packages/typed_graphql_server/lib/src/introspection/introspection_fields.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/introspection/member_lanes.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/introspection/type_kind.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/introspection/type_lanes.dart` | Create | 3 |
| `packages/typed_graphql_server/test/introspection/introspection_fixture.dart` | Create, then Modify | 3, 13 |
| `packages/typed_graphql_server/test/introspection/introspection_test.dart` | Create, then Modify | 3, 12 |
| `packages/typed_graphql_server/lib/src/execution/operation_preparation.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/execution/prepared_operation.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart` | Create, then Modify | 4, 8, 10 |
| `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart` | Create, then Modify | 4, 10 |
| `packages/typed_graphql_server/lib/src/execution/subscription_result.dart` | Create, then Delete | 4, 8 |
| `packages/typed_graphql_server/test/builder/subscription_fields_test.dart` | Create, then Modify | 4, 11 |
| `packages/typed_graphql_server/test/execution/subscription_fixture.dart` | Create | 4 |
| `packages/typed_graphql_server/test/execution/subscription_test.dart` | Create | 4 |
| `packages/typed_graphql_conformance/test/execution/fixtures/introspection_query_result.json` | Create | 6 |
| `packages/typed_graphql_conformance/test/execution/introspection_deprecation_test.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/execution/introspection_one_of_test.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/execution/introspection_test.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/execution/subscribe_initialization_test.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/execution/subscribe_publish_test.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/support/email_subscription.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/support/introspection_fixture.dart` | Create | 6 |
| `packages/typed_graphql_conformance/test/support/simple_pub_sub.dart` | Create | 6 |
| `packages/typed_graphql_server/doc/introspection.md` | Create | 8 |
| `packages/typed_graphql_server/doc/subscriptions.md` | Create, then Modify | 8, 14 |
| `packages/typed_graphql_server/lib/src/introspection/introspection_policy.dart` | Create | 8 |
| `packages/typed_graphql_server/lib/src/subscription/subscription_result.dart` | Create | 8 |
| `packages/typed_graphql_server/test/execution/subscription_flow_test.dart` | Create | 10 |
| `packages/typed_graphql_server/test/introspection/introspection_limits_test.dart` | Create | 13 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1, 2, 5 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart` | Modify | 2 |
| `packages/typed_graphql/lib/typed_graphql.dart` | Modify | 2 |
| `CLAUDE.md` | Modify | 3, 8 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 3, 4, 8, 14 |
| `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart` | Modify | 3, 4 |
| `packages/typed_graphql_server/lib/src/execution/execution_options.dart` | Modify | 3, 8 |
| `packages/typed_graphql_server/lib/src/execution/field_execution.dart` | Modify | 3, 4, 8, 10 |
| `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/src/plan/field_collector.dart` | Modify | 3 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 3, 4, 8 |
| `packages/typed_graphql_server/test/builder/build_test.dart` | Modify | 3, 4 |
| `packages/typed_graphql_server/test/execution/completion_failures_test.dart` | Modify | 3 |
| `packages/typed_graphql_conformance/test/execution/executor_operations_test.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/builder/builder_checks.dart` | Modify | 4, 11 |
| `packages/typed_graphql_server/lib/src/builder/field_lane.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/builder/field_stub.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/execution/error_reporter.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/execution/executable_schema.dart` | Modify | 4, 8 |
| `packages/typed_graphql_server/lib/src/execution/execution_run.dart` | Modify | 4 |
| `packages/typed_graphql_server/lib/src/execution/operation_execution.dart` | Modify | 4 |
| `packages/typed_graphql_server/test/builder/assembly_test.dart` | Modify | 4 |
| `packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart` | Modify | 5 |
| `packages/typed_graphql/test/validation/rules/argument_rules_test.dart` | Modify | 5 |
| `packages/typed_graphql_conformance/mapping/execution.csv` | Modify | 6 |
| `packages/typed_graphql_conformance/test/execution/enum_type_test.dart` | Modify | 6 |
| `packages/typed_graphql_conformance/test/execution/union_interface_test.dart` | Modify | 6 |
| `packages/typed_graphql_conformance/test/mapping_test.dart` | Modify | 6 |
| `packages/typed_graphql_conformance/test/support/execution_port.dart` | Modify | 6 |
| `docs/superpowers/specs/2026-10-15-m5-execution-design.md` | Modify | 7, 14 |
| `README.md` | Modify | 8 |
| `docs/discovery.md` | Modify | 8, 14 |
| `docs/superpowers/HANDOFF.md` | Modify | 8 |
| `llms.txt` | Modify | 8 |
| `packages/typed_graphql_server/README.md` | Modify | 8 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Modify | 8 |
| `packages/typed_graphql/doc/introspection.md` | Modify | 9 |

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

### Task 1: The M5c diagnostic codes (core)

Add `GQL303` (`misplacedSubscriptionField`), `GQL324` (`subscriptionRequired`), `GQL338` (`introspectionNotAllowed`) and `GQL340` (`subscriptionSourceFailed`) to the catalog in id order, with doc comments, and a core CHANGELOG line.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/CHANGELOG.md`

**Interfaces:**
- Consumes: the core as left by M5b and the merge of M10.
- Produces:
- Diagnostic codes: `GQL303` (`misplacedSubscriptionField`), `GQL324` (`subscriptionRequired`), `GQL338` (`introspectionNotAllowed`), `GQL340` (`subscriptionSourceFailed`).

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -526,6 +526,11 @@ enum DiagnosticCode(
   /// `encode` throws, or an input object has no `encode`).
   unencodableDefaultValue('GQL302'),
 
+  /// `GQL303`: reported when the executable schema builder finds a field
+  /// with a `subscribe` source outside the subscription root type, or a field
+  /// of the subscription root type without one.
+  misplacedSubscriptionField('GQL303'),
+
   /// `GQL310`: reported when a variable value is invalid, or a required
   /// variable is missing, as `ExecutableSchema.execute` coerces the variable
   /// values. It is a `GraphQLError`'s `extensions.code` in a
@@ -574,6 +579,9 @@ enum DiagnosticCode(
   /// response of `ExecutableSchema.execute`.
   unsupportedOperationType('GQL323'),
 
+  /// `GQL324`: reported when `subscribe` is called with a query or a mutation.
+  subscriptionRequired('GQL324'),
+
   /// `GQL330`: reported when a resolver, codec or decode function threw
   /// an unexpected error; the message is masked. It is a
   /// `GraphQLError`'s `extensions.code` in a response of
@@ -617,6 +625,14 @@ enum DiagnosticCode(
   /// `ExecutableSchema.execute`.
   maxExecutionStepsExceeded('GQL337'),
 
+  /// `GQL338`: reported when a query contained `__schema` or `__type` and
+  /// introspection is disabled for the execution.
+  introspectionNotAllowed('GQL338'),
+
+  /// `GQL340`: reported when the source stream of a subscription emitted an
+  /// error; the response stream ends with it.
+  subscriptionSourceFailed('GQL340'),
+
   /// `GQL500`: a `typed_graphql.yaml` that is not valid YAML; the message is
   /// the YAML parser's.
   configSyntax('GQL500'),
```

- [ ] **Step 2: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -269,6 +269,7 @@
 - `GQL300`-`GQL302`: the diagnostics of the executable schema builder (incompatible implementation, ambiguous type resolution, unencodable default value).
 - `Suggestions` is exported: graphql-js's "Did you mean" text for messages that suggest a name.
 - `GQL310`-`GQL337`: the diagnostics of execution (variable and argument coercion, operation selection, completion errors, limits); they are the `extensions.code` of the errors `ExecutableSchema.execute` returns.
+- `GQL303`, `GQL324`, `GQL338`, `GQL340`: the diagnostics of introspection and subscriptions (misplaced or missing subscription source, `subscribe` with a query or mutation, introspection not allowed, failed subscription source).
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
git commit -q -m "feat(typed_graphql): add the M5c diagnostic codes" \
  -m "GQL303, GQL324, GQL338, GQL340: subscription source placement, subscribe with a query or mutation, introspection policy and failed subscription source." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: `IntrospectionListing` (core)

Extract from `IntrospectionWriter` and export `IntrospectionListing`: the types and directives an introspection result lists, in the writer's order, so the server's resolvers list the same.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/introspection/introspection_listing.dart`
- Modify: `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md`
- Test: `packages/typed_graphql/test/schema/introspection/introspection_listing_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// schema/introspection/introspection_listing.dart
final class IntrospectionListing(…)
  List<SchemaType> get types
  List<SchemaDirective> get directives
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/schema/introspection/introspection_listing_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final schema = Built('type Query { a: Int }').schema;
  final listing = IntrospectionListing(schema);

  test('lists own types, then referenced built-ins, then introspection', () {
    final names = [for (final type in listing.types) type.name];
    expect(names.first, 'Query');
    expect(names, containsAllInOrder(['Query', 'String', 'Int', '__Schema']));
    expect(names, isNot(contains('Float')));
  });

  test('lists the specified directives after the schema own', () {
    final names = [for (final directive in listing.directives) directive.name];
    expect(names, containsAll(['skip', 'include', 'deprecated']));
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_listing_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/schema/introspection/introspection_listing.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../build/built_ins.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';

/// Which types and directives introspection lists for a schema, and in which
/// order (spec §4.2): the schema's own in declaration order, then the
/// built-in scalars it references (`String` and `Boolean` always), then the
/// introspection types; the built-in directives it did not redefine come
/// after its own.
///
/// {@category introspection}
final class IntrospectionListing(
  /// The schema listed.
  final Schema schema,
) {
  /// Lists [schema].
  this;

  /// The types in the order introspection lists them.
  List<SchemaType> get types {
    const builtIns = BuiltIns();
    final referenced = _referencedTypeNames();
    return [
      ...schema.types,
      for (final scalar in builtIns.scalars)
        if (identical(schema.typeNamed(scalar.name), scalar) &&
            referenced.contains(scalar.name))
          scalar,
      for (final type in builtIns.introspectionTypes)
        if (identical(schema.typeNamed(type.name), type)) type,
    ];
  }

  // Only for lookups, never iterated.
  Set<String> _referencedTypeNames() {
    final references = <TypeRef>[
      for (final type in schema.types) ..._typeReferences(type),
      for (final directive in directives)
        for (final argument in directive.arguments) argument.type,
    ];
    const comparator = TypeComparator();
    return {
      // The introspection types reference both.
      'String',
      'Boolean',
      for (final reference in references) comparator.namedTypeName(reference),
    };
  }

  List<TypeRef> _typeReferences(SchemaType type) => switch (type) {
    ObjectType(:final fields) || InterfaceType(:final fields) => [
      for (final field in fields) ...[
        field.type,
        ..._inputTypes(field.arguments),
      ],
    ],
    InputObjectType(:final fields) => _inputTypes(fields),
    ScalarType() || UnionType() || EnumType() => const [],
  };

  List<TypeRef> _inputTypes(List<InputValue> values) => [
    for (final value in values) value.type,
  ];

  /// The directives in the order introspection lists them.
  List<SchemaDirective> get directives {
    const builtIns = BuiltIns();
    return [
      ...schema.directives,
      for (final directive in [
        ...builtIns.directives,
        builtIns.defer,
        builtIns.stream,
        builtIns.cost,
        builtIns.listSize,
      ])
        if (identical(schema.directiveNamed(directive.name), directive))
          directive,
    ];
  }
}
```

In `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,11 +1,7 @@
-import '../../language/ast/type_ref.dart';
 import '../../protocol/json_value.dart';
-import '../build/built_ins.dart';
-import '../model/input_value.dart';
 import '../model/schema_directive.dart';
-import '../model/schema_type.dart';
-import '../relations/type_comparator.dart';
 import '../schema.dart';
+import 'introspection_listing.dart';
 import 'introspection_query.dart';
 import 'type_writer.dart';
 
@@ -28,6 +24,7 @@ final class IntrospectionWriter(
   this;
 
   final TypeWriter _types = TypeWriter(schema, query);
+  final IntrospectionListing _listing = IntrospectionListing(schema);
 
   /// `{"__schema": {...}}`.
   ///
@@ -50,10 +47,10 @@ final class IntrospectionWriter(
       'mutationType': _root(schema.mutationTypeName),
       'subscriptionType': _root(schema.subscriptionTypeName),
       'types': JsonArray([
-        for (final type in _listedTypes()) _types.type(type),
+        for (final type in _listing.types) _types.type(type),
       ]),
       'directives': JsonArray([
-        for (final directive in _listedDirectives()) _directive(directive),
+        for (final directive in _listing.directives) _directive(directive),
       ]),
     }),
   });
@@ -66,67 +63,6 @@ final class IntrospectionWriter(
     null => const JsonNull(),
   };
 
-  List<SchemaType> _listedTypes() {
-    const builtIns = BuiltIns();
-    final referenced = _referencedTypeNames();
-    return [
-      ...schema.types,
-      for (final scalar in builtIns.scalars)
-        if (identical(schema.typeNamed(scalar.name), scalar) &&
-            referenced.contains(scalar.name))
-          scalar,
-      for (final type in builtIns.introspectionTypes)
-        if (identical(schema.typeNamed(type.name), type)) type,
-    ];
-  }
-
-  // Only for lookups, never iterated.
-  Set<String> _referencedTypeNames() {
-    final references = <TypeRef>[
-      for (final type in schema.types) ..._typeReferences(type),
-      for (final directive in _listedDirectives())
-        for (final argument in directive.arguments) argument.type,
-    ];
-    const comparator = TypeComparator();
-    return {
-      // The introspection types reference both.
-      'String',
-      'Boolean',
-      for (final reference in references) comparator.namedTypeName(reference),
-    };
-  }
-
-  List<TypeRef> _typeReferences(SchemaType type) => switch (type) {
-    ObjectType(:final fields) || InterfaceType(:final fields) => [
-      for (final field in fields) ...[
-        field.type,
-        ..._inputTypes(field.arguments),
-      ],
-    ],
-    InputObjectType(:final fields) => _inputTypes(fields),
-    ScalarType() || UnionType() || EnumType() => const [],
-  };
-
-  List<TypeRef> _inputTypes(List<InputValue> values) => [
-    for (final value in values) value.type,
-  ];
-
-  List<SchemaDirective> _listedDirectives() {
-    const builtIns = BuiltIns();
-    return [
-      ...schema.directives,
-      for (final directive in [
-        ...builtIns.directives,
-        builtIns.defer,
-        builtIns.stream,
-        builtIns.cost,
-        builtIns.listSize,
-      ])
-        if (identical(schema.directiveNamed(directive.name), directive))
-          directive,
-    ];
-  }
-
   JsonObject _directive(SchemaDirective directive) => JsonObject({
     'name': JsonString(directive.name),
     if (query.includesDescriptions)
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -69,6 +69,7 @@ export 'src/schema/build/build_result.dart';
 export 'src/schema/build/built_ins.dart';
 export 'src/schema/build/schema_builder.dart';
 export 'src/schema/coordinates/coordinate_target.dart';
+export 'src/schema/introspection/introspection_listing.dart';
 export 'src/schema/introspection/introspection_query.dart';
 export 'src/schema/model/applied_directive.dart';
 export 'src/schema/model/input_value.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_listing_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `IntrospectionListing`: which types and directives introspection lists for
  a schema, and in which order (the order `Schema.toIntrospection` writes);
  the server's introspection resolvers share it.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/introspection/introspection_listing.dart packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/introspection/introspection_listing_test.dart
git commit -q -m "feat(typed_graphql): export IntrospectionListing" \
  -m "The types and directives an introspection result lists, in the writer's order, so the server's introspection resolvers answer exactly what Schema.toIntrospection writes." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Introspection fields

Add the internal introspection bindings (`IntrospectionBindings`, `IntrospectionFields`, `TypeLanes`, `MemberLanes`, `IntrospectedType`, `TypeKind`, `EntryFields`), recognise `__schema` and `__type` on the query root in the planner, and add `IntrospectionPolicy` and `ExecutionOptions.introspection` (`GQL338`).

**Files:**
- Create: `packages/typed_graphql_server/lib/src/execution/introspection_policy.dart`, `packages/typed_graphql_server/lib/src/introspection/entry_fields.dart`, `packages/typed_graphql_server/lib/src/introspection/introspected_type.dart`, `packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart`, `packages/typed_graphql_server/lib/src/introspection/introspection_fields.dart`, `packages/typed_graphql_server/lib/src/introspection/member_lanes.dart`, `packages/typed_graphql_server/lib/src/introspection/type_kind.dart`, `packages/typed_graphql_server/lib/src/introspection/type_lanes.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart`, `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, `packages/typed_graphql_server/lib/src/plan/field_collector.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `CLAUDE.md`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/introspection/introspection_fixture.dart`, `packages/typed_graphql_server/test/introspection/introspection_test.dart`, `packages/typed_graphql_server/test/builder/build_test.dart`, `packages/typed_graphql_server/test/execution/completion_failures_test.dart`

**Interfaces:**
- Consumes: Task 2, the executor and plan of M5b.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// execution/introspection_policy.dart
enum IntrospectionPolicy

// introspection/entry_fields.dart
final class const EntryFields()
  bool isEntry(String fieldName)
  SchemaField? of(Schema schema, ObjectType parentType, String fieldName)

// introspection/introspected_type.dart
final class IntrospectedType(…)

// introspection/introspection_bindings.dart
final class IntrospectionBindings(…)
  SchemaBindings addTo(SchemaBindings bindings)

// introspection/introspection_fields.dart
final class IntrospectionFields
  static bool includesDeprecated(Map<String, Object?> arguments)
  static Map<String, FieldDef<Object?, Object?>> table(…)

// introspection/member_lanes.dart
final class MemberLanes
  MemberLanes()
  Map<String, FieldDef<Object?, Object?>> get fieldFields
  Map<String, FieldDef<Object?, Object?>> get inputValueFields
  Map<String, FieldDef<Object?, Object?>> get enumValueFields
  Map<String, FieldDef<Object?, Object?>> get directiveFields

// introspection/type_kind.dart
enum TypeKind(…)
  scalar('SCALAR'),
  object('OBJECT'),
  interface('INTERFACE'),
  union('UNION'),
  enumeration('ENUM'),
  inputObject('INPUT_OBJECT'),
  list('LIST'),
  nonNull('NON_NULL'),

// introspection/type_lanes.dart
final class TypeLanes(…)
  Map<String, FieldDef<Object?, Object?>> get fields
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/introspection/introspection_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Role { admin, guest }

final class Account {
  const Account();
}

final class Robot {
  const Robot();
}

/// A schema with every kind of type, deprecations, descriptions and a
/// repeatable directive, and helpers to run queries against it.
final class IntrospectionFixture {
  IntrospectionFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final url = b.scalar<String>(
      'Url',
      const StringCodec(),
      description: 'A web address.',
      specifiedByUrl: 'https://example.com/url',
    );
    final role = b.enumType<Role>(
      'Role',
      Role.values,
      description: 'What an account may do.',
      mapping: EnumValueMapping<Role>(
        descriptionOf: (value) => value == Role.admin ? 'Does all.' : null,
        deprecationReasonOf: (value) =>
            value == Role.guest ? 'Use admin.' : null,
      ),
    );
    final node = b.interface<Object?>(
      'Node',
      description: 'Something with an id.',
      fields: (t) => [t.field('id', b.id).declareOnly()],
    );
    final entity = b.interface<Object?>(
      'Entity',
      interfaces: [node],
      fields: (t) => [
        t.field('id', b.id).declareOnly(),
        t.field('name', b.string).declareOnly(),
      ],
    );
    final account = b.object<Account>(
      'Account',
      interfaces: [entity, node],
      fields: (t) => [
        t.field('id', b.id).pure((_) => '1'),
        t.field('name', b.string, description: 'Shown name.').pure((_) => 'a'),
        t.field('role', role).pure((_) => Role.admin),
        t.field('site', url.nullable).pure((_) => null),
      ],
    );
    final robot = b.object<Robot>(
      'Robot',
      interfaces: [node],
      fields: (t) => [
        t.field('id', b.id).pure((_) => '2'),
        t
            .field(
              'serial',
              b.string,
              args: [
                Arg<String?>(
                  'unit',
                  b.string.nullable,
                  deprecationReason: 'Not used.',
                ),
              ],
            )
            .deprecated('Use id.')
            .withDirectives([AppliedDirective('tag')])
            .resolve((parent, args, context, info) => 's'),
      ],
    );
    final search = b.union<Object?>(
      'Search',
      members: [account, robot],
      description: 'Anything findable.',
    );
    final lookupId = Arg<String?>('id', b.string.nullable);
    final lookupName = Arg<String?>('name', b.string.nullable);
    final lookup = b.oneOfInputObject<String>(
      'Lookup',
      description: 'One way to find.',
      fields: () => [lookupId, lookupName],
      decode: (values) => values.get(lookupId) ?? values.get(lookupName) ?? '',
    );
    final term = Arg<String>('term', b.string, defaultValue: 'all');
    final by = Arg<String?>('by', lookup.nullable);
    final query = b.object<Object?>(
      'Query',
      description: 'The root.',
      fields: (t) => [
        t
            .field(
              'search',
              b.list(search),
              args: [term, by],
              description: 'Finds things.',
            )
            .resolve((parent, args, context, info) => const <Object>[]),
        t.field('me', account.nullable).pure((_) => const Account()),
        t.field('old', b.string).deprecated('Use me.').pure((_) => 'x'),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [t.field('ping', b.boolean).pure((_) => true)],
    );
    built = b.build(
      query: query,
      mutation: mutation,
      options: BuildOptions(
        description: 'The API.',
        directives: [
          SchemaDirective(
            'tag',
            description: 'Marks a field.',
            isRepeatable: true,
            locations: const [
              DirectiveLocation.fieldDefinition,
              DirectiveLocation.object,
            ],
            arguments: [
              InputValue(
                'name',
                const NamedType(Name('String')),
                description: 'The tag.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  late final ExecutableSchema<Object?> built;

  /// The JSON of the response to [text].
  Future<Map<String, Object?>> json(
    String text, {
    ExecutionOptions options = const ExecutionOptions(),
    JsonObject? variables,
  }) async {
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument();
    final FutureOr<ResponsePayload> payload = built.execute(
      ValidDocument.assumeValid(built.schema, document),
      context: null,
      options: options,
      variables: variables,
    );
    return (await payload).toJson().toJson();
  }
}
```

Create `packages/typed_graphql_server/test/introspection/introspection_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'introspection_fixture.dart';

void main() {
  final fixture = IntrospectionFixture();

  Future<Map<String, Object?>> dataOf(String query) async {
    final json = await fixture.json(query);
    expect(json['errors'], isNull, reason: '$json');
    return json['data']! as Map<String, Object?>;
  }

  test(
    'answers IntrospectionQuery.full exactly as the core writes it',
    () async {
      final json = await fixture.json(IntrospectionQuery.full.text);
      final expected = fixture.built.schema.schema.toIntrospection(
        IntrospectionQuery.full,
      );
      expect(json['errors'], isNull);
      expect(json['data'], expected.toJson());
    },
  );

  test('answers the default query without the draft fields', () async {
    const query = IntrospectionQuery();
    final json = await fixture.json(query.text);
    expect(
      json['data'],
      fixture.built.schema.schema.toIntrospection(query).toJson(),
    );
  });

  test('__type finds a type by name', () async {
    final data = await dataOf('{ __type(name: "Account") { kind name } }');
    expect(data['__type'], {'kind': 'OBJECT', 'name': 'Account'});
  });

  test('__type of a missing type is null', () async {
    final data = await dataOf('{ __type(name: "Nope") { name } }');
    expect(data['__type'], isNull);
  });

  test('__type takes its name from a variable', () async {
    final json = await fixture.json(
      r'query ($n: String!) { __type(name: $n) { name } }',
      variables: JsonObject({'n': const JsonString('Robot')}),
    );
    expect(json['data'], {
      '__type': {'name': 'Robot'},
    });
  });

  test('list and non-null types nest through ofType', () async {
    final data = await dataOf('''
{
  __type(name: "Query") {
    fields {
      name
      type { kind name ofType { kind name ofType { kind name ofType { name } } } }
    }
  }
}''');
    final fields = (data['__type']! as Map<String, Object?>)['fields']!;
    final search = (fields as List<Object?>).cast<Map<String, Object?>>().first;
    expect(search['type'], {
      'kind': 'NON_NULL',
      'name': null,
      'ofType': {
        'kind': 'LIST',
        'name': null,
        'ofType': {
          'kind': 'NON_NULL',
          'name': null,
          'ofType': {'name': 'Search'},
        },
      },
    });
  });

  test('deprecated fields are left out unless asked for', () async {
    final data = await dataOf('''
{
  __type(name: "Query") {
    plain: fields { name }
    all: fields(includeDeprecated: true) { name isDeprecated deprecationReason }
  }
}''');
    final type = data['__type']! as Map<String, Object?>;
    expect(type['plain'], [
      {'name': 'search'},
      {'name': 'me'},
    ]);
    expect((type['all']! as List<Object?>).last, {
      'name': 'old',
      'isDeprecated': true,
      'deprecationReason': 'Use me.',
    });
  });

  test('deprecated enum values and arguments follow the same rule', () async {
    final data = await dataOf('''
{
  role: __type(name: "Role") {
    plain: enumValues { name }
    all: enumValues(includeDeprecated: true) { name }
  }
  robot: __type(name: "Robot") {
    fields(includeDeprecated: true) {
      plain: args { name }
      all: args(includeDeprecated: true) { name }
    }
  }
}''');
    final role = data['role']! as Map<String, Object?>;
    expect(role['plain'], [
      {'name': 'admin'},
    ]);
    expect(role['all'], [
      {'name': 'admin'},
      {'name': 'guest'},
    ]);
    final field =
        ((data['robot']! as Map<String, Object?>)['fields']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .last;
    expect(field['plain'], isEmpty);
    expect(field['all'], [
      {'name': 'unit'},
    ]);
  });

  test('a default value is printed as GraphQL', () async {
    final data = await dataOf('''
{ __type(name: "Query") { fields { args { name defaultValue } } } }''');
    final fields = (data['__type']! as Map<String, Object?>)['fields']!;
    final search = (fields as List<Object?>).first! as Map<String, Object?>;
    expect(search['args'], [
      {'name': 'term', 'defaultValue': '"all"'},
      {'name': 'by', 'defaultValue': null},
    ]);
  });

  test('__typename names the introspection types', () async {
    final data = await dataOf(
      '{ __schema { __typename types { __typename } } }',
    );
    final schema = data['__schema']! as Map<String, Object?>;
    expect(schema['__typename'], '__Schema');
    expect((schema['types']! as List<Object?>).first, {'__typename': '__Type'});
  });

  test('a mutation root has no __schema or __type', () async {
    final json = await fixture.json(
      'mutation { __typename __type(name: "Query") { name } }',
    );
    expect(json['data'], {'__typename': 'Mutation'});
  });

  group('IntrospectionPolicy.disabled', () {
    const disabled = ExecutionOptions(
      introspection: IntrospectionPolicy.disabled,
    );

    test('makes __type a GQL338 field error and keeps __typename', () async {
      final json = await fixture.json(
        '{ __type(name: "Query") { name } kind: __typename }',
        options: disabled,
      );
      expect(json['data'], {'__type': null, 'kind': 'Query'});
      final errors = (json['errors']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(errors.single['path'], ['__type']);
      expect(errors.single['message'], contains('"__type"'));
      expect(errors.single['extensions'], {'code': 'GQL338'});
    });

    test('makes __schema a GQL338 error that nulls the data', () async {
      final json = await fixture.json(
        '{ __schema { queryType { name } } }',
        options: disabled,
      );
      expect(json['data'], isNull);
      final errors = json['errors']! as List<Object?>;
      expect((errors.single! as Map<String, Object?>)['extensions'], {
        'code': 'GQL338',
      });
    });

    test('does not stop ordinary fields', () async {
      final json = await fixture.json('{ me { name } }', options: disabled);
      expect(json['data'], {
        'me': {'name': 'a'},
      });
    });
  });
}
```

In `packages/typed_graphql_server/test/builder/build_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -314,8 +314,13 @@ type Mutation {
       expect(namesOf('SearchResult'), ['Account', 'Team']);
     });
 
-    test('keep the leaves and the input objects', () {
-      expect(bindings.leaves.keys, ['Url', 'Role']);
+    test('keep the leaves, then the introspection enums, and the inputs', () {
+      expect(bindings.leaves.keys, [
+        'Url',
+        'Role',
+        '__TypeKind',
+        '__DirectiveLocation',
+      ]);
       expect(bindings.inputObjects.keys, ['Filter', 'Lookup']);
     });
   });
```

In `packages/typed_graphql_server/test/execution/completion_failures_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -249,12 +249,4 @@ void main() {
       expect(counter.calls, 1);
     });
   });
-
-  group('introspection placeholder', () {
-    test('a non-null __schema propagates its error', () async {
-      final json = await f.json('{ __schema { queryType { name } } }');
-      expect(json['data'], isNull);
-      expect(errorsOf(json), hasLength(1));
-    });
-  });
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/introspection/introspection_test.dart test/builder/build_test.dart test/execution/completion_failures_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/execution/introspection_policy.dart`:

```dart
/// Whether an execution answers `__schema` and `__type`.
///
/// `__typename` is answered either way: it describes the response, not the
/// schema.
///
/// {@category execution}
enum IntrospectionPolicy {
  /// `__schema` and `__type` are answered (September2025 4.2).
  enabled,

  /// `__schema` and `__type` are field errors (`GQL338`), each with a null
  /// value.
  disabled,
}
```

Create `packages/typed_graphql_server/lib/src/introspection/entry_fields.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The two meta fields that open introspection, `__schema` and `__type`
/// (September2025 4.2). Only the query root type has them, as graphql-js's
/// `getFieldDef` finds them; the schema does not declare them.
final class const EntryFields() {
  /// Creates the reader.
  this;

  /// `__schema: __Schema!`.
  static final SchemaField schemaField = SchemaField(
    '__schema',
    const NonNullType(NamedType(Name('__Schema'))),
    description: 'Access the current type schema of this server.',
  );

  /// `__type(name: String!): __Type`.
  static final SchemaField typeField = SchemaField(
    '__type',
    const NamedType(Name('__Type')),
    description: 'Request the type information of a single type.',
    arguments: [
      InputValue('name', const NonNullType(NamedType(Name('String')))),
    ],
  );

  /// Whether [fieldName] opens introspection.
  bool isEntry(String fieldName) =>
      fieldName == '__schema' || fieldName == '__type';

  /// The entry field named [fieldName] of [parentType], null when the name
  /// is another one or [parentType] is not the query root.
  SchemaField? of(Schema schema, ObjectType parentType, String fieldName) {
    if (parentType.name != schema.queryTypeName) {
      return null;
    }
    return switch (fieldName) {
      '__schema' => schemaField,
      '__type' => typeField,
      _ => null,
    };
  }
}
```

Create `packages/typed_graphql_server/lib/src/introspection/introspected_type.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The value of a `__Type` object: a type as a schema writes it, a name or a
/// list or non-null wrapper around another type (September2025 4.2.1).
///
/// A wrapper is not a schema type, which is why introspection needs its own
/// value instead of the core's [SchemaType].
final class IntrospectedType(
  /// The type reference this value stands for.
  final TypeRef reference,
) {
  /// Wraps [reference].
  this;

  /// The value for the named type [name].
  factory IntrospectedType.named(String name) =>
      IntrospectedType(NamedType(Name(name)));
}
```

Create `packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/enum_type_def.dart';
import '../builder/enum_value_def.dart';
import '../builder/field_def.dart';
import '../builder/named_type_def.dart';
import '../execution/schema_bindings.dart';
import 'introspected_type.dart';
import 'introspection_fields.dart';
import 'member_lanes.dart';
import 'type_kind.dart';
import 'type_lanes.dart';

/// The run-time side of the introspection types for one schema: object
/// bindings with pure lanes over the core model for `__Schema`, `__Type`,
/// `__Field`, `__InputValue`, `__EnumValue` and `__Directive`, the two
/// enums, and the `__schema` and `__type` fields of the query root. The
/// schema never declares them; the core's `BuiltIns` has the types.
final class IntrospectionBindings(
  /// The schema introspection describes.
  final Schema schema,
) {
  /// Describes [schema].
  this;

  /// [bindings] with the introspection types and the query root's entry
  /// fields added.
  SchemaBindings addTo(SchemaBindings bindings) {
    final members = MemberLanes();
    final fields = {
      ...bindings.fields,
      '__Schema': _schemaFields,
      '__Type': TypeLanes(schema).fields,
      '__Field': members.fieldFields,
      '__InputValue': members.inputValueFields,
      '__EnumValue': members.enumValueFields,
      '__Directive': members.directiveFields,
    };
    final queryName = schema.queryTypeName;
    if (queryName != null) {
      fields[queryName] = {...?fields[queryName], ..._entryFields};
    }
    return bindings.withIntrospection(fields, _leaves);
  }

  Map<String, FieldDef<Object?, Object?>> get _entryFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<Object?>('__schema', (_) => schema),
        IntrospectionFields.withArguments<Object?>(
          '__type',
          (_, arguments) => switch (schema.typeNamed(
            arguments['name'] as String,
          )) {
            final type? => IntrospectedType.named(type.name),
            null => null,
          },
        ),
      ]);

  Map<String, FieldDef<Object?, Object?>> get _schemaFields {
    final listing = IntrospectionListing(schema);
    return IntrospectionFields.table([
      IntrospectionFields.pure<Schema>(
        'description',
        (_) => schema.description,
      ),
      IntrospectionFields.pure<Schema>(
        'types',
        (_) => [
          for (final type in listing.types) IntrospectedType.named(type.name),
        ],
      ),
      IntrospectionFields.pure<Schema>(
        'queryType',
        (_) => _root(schema.queryTypeName),
      ),
      IntrospectionFields.pure<Schema>(
        'mutationType',
        (_) => _root(schema.mutationTypeName),
      ),
      IntrospectionFields.pure<Schema>(
        'subscriptionType',
        (_) => _root(schema.subscriptionTypeName),
      ),
      IntrospectionFields.pure<Schema>('directives', (_) => listing.directives),
    ]);
  }

  IntrospectedType? _root(String? name) =>
      name == null ? null : IntrospectedType.named(name);

  Map<String, NamedTypeDef> get _leaves => {
    '__TypeKind': EnumTypeDef<TypeKind>('__TypeKind', [
      for (final kind in TypeKind.values) EnumValueDef(kind, kind.spelling),
    ]),
    '__DirectiveLocation': EnumTypeDef<DirectiveLocation>(
      '__DirectiveLocation',
      [
        for (final location in DirectiveLocation.values)
          EnumValueDef(location, location.spelling),
      ],
    ),
  };
}
```

Create `packages/typed_graphql_server/lib/src/introspection/introspection_fields.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/field_def.dart';
import '../builder/field_lane.dart';
import '../builder/output_ref.dart';
import '../builder/scalar_type_def.dart';

/// Makes the [FieldDef]s of the introspection objects: pure getters, or
/// resolvers that read their coerced arguments by name.
///
/// The executor reads the field's type from the core schema, which has the
/// introspection types already, so a definition's own [FieldDef.type] is a
/// placeholder nothing reads.
final class IntrospectionFields {
  IntrospectionFields._();

  static final OutputRef<Object?> _placeholder = ScalarTypeDef<String>(
    'String',
    const StringCodec(),
  );

  /// The field [name] that reads its value from the parent `P`.
  static FieldDef<Object?, Object?> pure<P>(
    String name,
    Object? Function(P parent) read,
  ) => FieldDef(
    name: name,
    type: _placeholder,
    args: const [],
    directives: const [],
    lane: PureLane((parent) => read(parent as P)),
  );

  /// The field [name] that reads its value from the parent `P` and the
  /// coerced arguments of the call, by name.
  static FieldDef<Object?, Object?> withArguments<P>(
    String name,
    Object? Function(P parent, Map<String, Object?> arguments) read,
  ) => FieldDef(
    name: name,
    type: _placeholder,
    args: const [],
    directives: const [],
    lane: ResolverLane(
      (parent, arguments, context, info) =>
          read(parent as P, arguments.coerced),
    ),
  );

  /// Whether the call asked for the deprecated elements too
  /// (`includeDeprecated: true`).
  static bool includesDeprecated(Map<String, Object?> arguments) =>
      arguments['includeDeprecated'] == true;

  /// The definitions in a table by field name.
  static Map<String, FieldDef<Object?, Object?>> table(
    List<FieldDef<Object?, Object?>> fields,
  ) => {for (final field in fields) field.name: field};
}
```

Create `packages/typed_graphql_server/lib/src/introspection/member_lanes.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/field_def.dart';
import 'introspected_type.dart';
import 'introspection_fields.dart';

/// The fields of `__Field`, `__InputValue`, `__EnumValue` and `__Directive`
/// over the core model (September2025 4.2.3 to 4.2.6).
final class MemberLanes {
  /// Creates the lanes.
  MemberLanes();

  /// `__Field` by field name; the parent is a [SchemaField].
  Map<String, FieldDef<Object?, Object?>> get fieldFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<SchemaField>('name', (field) => field.name),
        IntrospectionFields.pure<SchemaField>(
          'description',
          (field) => field.description,
        ),
        IntrospectionFields.withArguments<SchemaField>(
          'args',
          (field, arguments) => _inputValues(field.arguments, arguments),
        ),
        IntrospectionFields.pure<SchemaField>(
          'type',
          (field) => IntrospectedType(field.type),
        ),
        ..._deprecation<SchemaField>((field) => field.deprecationReason),
      ]);

  /// `__InputValue` by field name; the parent is an [InputValue].
  Map<String, FieldDef<Object?, Object?>> get inputValueFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<InputValue>('name', (value) => value.name),
        IntrospectionFields.pure<InputValue>(
          'description',
          (value) => value.description,
        ),
        IntrospectionFields.pure<InputValue>(
          'type',
          (value) => IntrospectedType(value.type),
        ),
        IntrospectionFields.pure<InputValue>(
          'defaultValue',
          (value) => switch (value.defaultValue) {
            final defaultValue? => const Printer().print(defaultValue),
            null => null,
          },
        ),
        ..._deprecation<InputValue>((value) => value.deprecationReason),
      ]);

  /// `__EnumValue` by field name; the parent is a [SchemaEnumValue].
  Map<String, FieldDef<Object?, Object?>> get enumValueFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<SchemaEnumValue>(
          'name',
          (value) => value.name,
        ),
        IntrospectionFields.pure<SchemaEnumValue>(
          'description',
          (value) => value.description,
        ),
        ..._deprecation<SchemaEnumValue>((value) => value.deprecationReason),
      ]);

  /// `__Directive` by field name; the parent is a [SchemaDirective].
  Map<String, FieldDef<Object?, Object?>> get directiveFields =>
      IntrospectionFields.table([
        IntrospectionFields.pure<SchemaDirective>(
          'name',
          (directive) => directive.name,
        ),
        IntrospectionFields.pure<SchemaDirective>(
          'description',
          (directive) => directive.description,
        ),
        IntrospectionFields.pure<SchemaDirective>(
          'isRepeatable',
          (directive) => directive.isRepeatable,
        ),
        IntrospectionFields.pure<SchemaDirective>(
          'locations',
          (directive) => directive.locations,
        ),
        IntrospectionFields.withArguments<SchemaDirective>(
          'args',
          (directive, arguments) =>
              _inputValues(directive.arguments, arguments),
        ),
      ]);

  List<InputValue> _inputValues(
    List<InputValue> values,
    Map<String, Object?> arguments,
  ) => [
    for (final value in values)
      if (IntrospectionFields.includesDeprecated(arguments) ||
          value.deprecationReason == null)
        value,
  ];

  List<FieldDef<Object?, Object?>> _deprecation<P>(
    String? Function(P parent) reason,
  ) => [
    IntrospectionFields.pure<P>(
      'isDeprecated',
      (parent) => reason(parent) != null,
    ),
    IntrospectionFields.pure<P>('deprecationReason', reason),
  ];
}
```

Create `packages/typed_graphql_server/lib/src/introspection/type_kind.dart`:

```dart
/// The values of `__TypeKind` (September2025 4.2.1).
enum TypeKind(
  /// The name in the schema.
  final String spelling,
) {
  /// `SCALAR`.
  scalar('SCALAR'),

  /// `OBJECT`.
  object('OBJECT'),

  /// `INTERFACE`.
  interface('INTERFACE'),

  /// `UNION`.
  union('UNION'),

  /// `ENUM`.
  enumeration('ENUM'),

  /// `INPUT_OBJECT`.
  inputObject('INPUT_OBJECT'),

  /// `LIST`.
  list('LIST'),

  /// `NON_NULL`.
  nonNull('NON_NULL'),
}
```

Create `packages/typed_graphql_server/lib/src/introspection/type_lanes.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/field_def.dart';
import 'introspected_type.dart';
import 'introspection_fields.dart';
import 'type_kind.dart';

/// The fields of `__Type` over the core schema; the parent is an
/// [IntrospectedType] (September2025 4.2.1).
final class TypeLanes(
  /// The schema whose types are described.
  final Schema schema,
) {
  /// Reads [schema].
  this;

  /// The fields by name.
  Map<String, FieldDef<Object?, Object?>> get fields =>
      IntrospectionFields.table(
        [
          IntrospectionFields.pure<IntrospectedType>('kind', _kind),
          IntrospectionFields.pure<IntrospectedType>(
            'name',
            (type) => _named(type)?.name,
          ),
          IntrospectionFields.pure<IntrospectedType>(
            'description',
            (type) => _named(type)?.description,
          ),
          IntrospectionFields.pure<IntrospectedType>('specifiedByURL', (type) {
            final named = _named(type);
            return named is ScalarType ? named.specifiedByUrl : null;
          }),
          IntrospectionFields.pure<IntrospectedType>('isOneOf', (type) {
            final named = _named(type);
            return named is InputObjectType ? named.isOneOf : null;
          }),
          IntrospectionFields.withArguments<IntrospectedType>(
            'fields',
            _fields,
          ),
          IntrospectionFields.pure<IntrospectedType>('interfaces', _interfaces),
          IntrospectionFields.pure<IntrospectedType>(
            'possibleTypes',
            _possibleTypes,
          ),
          IntrospectionFields.withArguments<IntrospectedType>(
            'enumValues',
            _enumValues,
          ),
          IntrospectionFields.withArguments<IntrospectedType>(
            'inputFields',
            _inputFields,
          ),
          IntrospectionFields.pure<IntrospectedType>('ofType', _ofType),
        ],
      );

  SchemaType? _named(IntrospectedType type) => switch (type.reference) {
    NamedType(:final name) => schema.typeNamed(name.value),
    _ => null,
  };

  TypeKind _kind(IntrospectedType type) => switch (type.reference) {
    ListType() => TypeKind.list,
    NonNullType() => TypeKind.nonNull,
    NamedType(:final name) => switch (schema.typeNamed(name.value)) {
      ScalarType() => TypeKind.scalar,
      ObjectType() => TypeKind.object,
      InterfaceType() => TypeKind.interface,
      UnionType() => TypeKind.union,
      EnumType() => TypeKind.enumeration,
      InputObjectType() => TypeKind.inputObject,
      null => throw StateError('"${name.value}" is not a type of the schema.'),
    },
  };

  List<SchemaField>? _fields(
    IntrospectedType type,
    Map<String, Object?> arguments,
  ) {
    final includesDeprecated = IntrospectionFields.includesDeprecated(
      arguments,
    );
    return switch (_named(type)) {
      ObjectType(:final fields) || InterfaceType(:final fields) => [
        for (final field in fields)
          if (includesDeprecated || field.deprecationReason == null) field,
      ],
      _ => null,
    };
  }

  List<IntrospectedType>? _interfaces(IntrospectedType type) =>
      switch (_named(type)) {
        ObjectType(:final interfaces) ||
        InterfaceType(:final interfaces) => _references(interfaces),
        _ => null,
      };

  // Interfaces list their implementers; a union lists every member, as the
  // core writes them.
  List<IntrospectedType>? _possibleTypes(IntrospectedType type) =>
      switch (_named(type)) {
        final InterfaceType named => [
          for (final possible in schema.possibleTypes(named))
            IntrospectedType.named(possible.name),
        ],
        UnionType(:final memberTypes) => _references(memberTypes),
        _ => null,
      };

  List<SchemaEnumValue>? _enumValues(
    IntrospectedType type,
    Map<String, Object?> arguments,
  ) {
    final includesDeprecated = IntrospectionFields.includesDeprecated(
      arguments,
    );
    return switch (_named(type)) {
      EnumType(:final values) => [
        for (final value in values)
          if (includesDeprecated || value.deprecationReason == null) value,
      ],
      _ => null,
    };
  }

  List<InputValue>? _inputFields(
    IntrospectedType type,
    Map<String, Object?> arguments,
  ) => switch (_named(type)) {
    InputObjectType(:final fields) => [
      for (final field in fields)
        if (IntrospectionFields.includesDeprecated(arguments) ||
            field.deprecationReason == null)
          field,
    ],
    _ => null,
  };

  IntrospectedType? _ofType(IntrospectedType type) => switch (type.reference) {
    ListType(:final type) || NonNullType(:final type) => IntrospectedType(type),
    NamedType() => null,
  };

  List<IntrospectedType> _references(List<NamedTypeReference> references) => [
    for (final reference in references) IntrospectedType.named(reference.name),
  ];
}
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../execution/executable_schema.dart';
+import '../introspection/introspection_bindings.dart';
 import 'build_options.dart';
 import 'builder_checks.dart';
 import 'field_middleware_composer.dart';
@@ -57,9 +58,14 @@ final class ExecutableSchemaAssembly<C> {
       definitions,
       possibleTypes,
     );
+    // After the middleware: introspection is not user code.
+    final composed = FieldMiddlewareComposer<C>(
+      schema,
+      options,
+    ).compose(bindings);
     return ExecutableSchema(
       ValidSchema.assumeValid(schema),
-      FieldMiddlewareComposer<C>(schema, options).compose(bindings),
+      IntrospectionBindings(schema).addTo(composed),
       planCacheSize: options.planCacheSize,
     );
   }
```

In `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import 'error_behavior.dart';
 import 'error_hook.dart';
+import 'introspection_policy.dart';
 
 /// The settings of one call of `ExecutableSchema.execute`.
 ///
@@ -24,6 +25,7 @@ final class ExecutionOptions {
     this.maxCoercionErrors = 50,
     this.maxDepth = 256,
     this.maxSteps = 10000000,
+    this.introspection = IntrospectionPolicy.enabled,
   });
 
   /// The parent value of the root fields; the root type's Dart type must
@@ -57,4 +59,7 @@ final class ExecutionOptions {
   /// The most values the execution completes; past it the execution halts
   /// (`GQL337`).
   final int maxSteps;
+
+  /// Whether `__schema` and `__type` are answered.
+  final IntrospectionPolicy introspection;
 }
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,10 +6,12 @@ import '../builder/arguments.dart';
 import '../builder/field_def.dart';
 import '../builder/field_lane.dart';
 import '../coercion/coercion_result.dart';
+import '../introspection/entry_fields.dart';
 import '../plan/field_plan.dart';
 import 'completion_site.dart';
 import 'execution_run.dart';
 import 'field_info.dart';
+import 'introspection_policy.dart';
 import 'response_path.dart';
 
 /// Resolves one field (September2025 6.4 "Executing Fields"): answers the
@@ -42,6 +44,10 @@ final class FieldExecution {
     if (field == null) {
       return _metaField(plan, site);
     }
+    if (_run.options.introspection == IntrospectionPolicy.disabled &&
+        const EntryFields().isEntry(plan.fieldName)) {
+      return _refused(field.type, site);
+    }
     final definition =
         _run.bindings.fields[plan.parentType.name]?[plan.fieldName];
     if (definition == null) {
@@ -55,22 +61,29 @@ final class FieldExecution {
     return _resolve(parent, definition, field.type, site);
   }
 
+  // Only `__typename` has no schema field; the planner drops any other
+  // name that is not defined.
   FutureOr<JsonValue?> _metaField(FieldPlan plan, CompletionSite site) {
     if (plan.fieldName == '__typename') {
       return JsonString(plan.parentType.name);
     }
     _run.reporter.fieldError(
       DiagnosticCode.unexpectedError,
-      'The introspection field "${plan.fieldName}" is not available.',
+      'The meta field "${plan.fieldName}" is not available.',
       site,
     );
-    return _run.settle(_metaFieldType(plan.fieldName), null);
+    return const JsonNull();
   }
 
-  // `__schema` is non-null, `__type` nullable (September2025 4.1.4).
-  TypeRef _metaFieldType(String fieldName) => fieldName == '__schema'
-      ? const NonNullType(NamedType(Name('__Schema')))
-      : const NamedType(Name('__Type'));
+  FutureOr<JsonValue?> _refused(TypeRef type, CompletionSite site) {
+    _run.reporter.fieldError(
+      DiagnosticCode.introspectionNotAllowed,
+      'GraphQL introspection has been disabled, but the requested query '
+      'contained the field "${site.plan.fieldName}".',
+      site,
+    );
+    return _run.settle(type, null);
+  }
 
   FutureOr<JsonValue?> _resolve(
     Object? parent,
```

In `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -31,6 +31,20 @@ final class SchemaBindings {
     inputObjects: inputObjects,
   );
 
+  /// The same tables with the introspection [fields] (every object's, the
+  /// introspection types' included) and [introspectionLeaves] added to the
+  /// scalar and enum definitions.
+  SchemaBindings withIntrospection(
+    Map<String, Map<String, FieldDef<Object?, Object?>>> fields,
+    Map<String, NamedTypeDef> introspectionLeaves,
+  ) => SchemaBindings(
+    objects: objects,
+    fields: fields,
+    abstractTypes: abstractTypes,
+    leaves: {...leaves, ...introspectionLeaves},
+    inputObjects: inputObjects,
+  );
+
   /// The object types.
   final Map<String, ObjectTypeDef<Object?>> objects;
 
```

In `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../introspection/entry_fields.dart';
 import 'field_plan.dart';
 import 'plan_context.dart';
 
@@ -25,10 +26,19 @@ final class FieldAccumulator {
   /// Whether the field exists on [parentType] (or is a meta field).
   /// September2025 section 6.4 (Executing Fields) skips a field without a
   /// definition, which only a document that was not validated can name.
-  bool isDefinedOn(ObjectType parentType) {
-    final name = _nodes.first.name.value;
-    return name.startsWith('__') || parentType.fieldNamed(name) != null;
-  }
+  bool isDefinedOn(PlanContext context, ObjectType parentType) =>
+      _nodes.first.name.value == '__typename' ||
+      _fieldOn(context, parentType) != null;
+
+  // `__typename` is no schema field; `__schema` and `__type` exist on the
+  // query root only.
+  SchemaField? _fieldOn(PlanContext context, ObjectType parentType) =>
+      const EntryFields().of(
+        context.schema,
+        parentType,
+        _nodes.first.name.value,
+      ) ??
+      parentType.fieldNamed(_nodes.first.name.value);
 
   /// The plan of the key for [parentType].
   FieldPlan build(PlanContext context, ObjectType parentType) {
@@ -38,7 +48,7 @@ final class FieldAccumulator {
       fieldName: first.name.value,
       nodes: _nodes.toList(),
       parentType: parentType,
-      field: parentType.fieldNamed(first.name.value),
+      field: _fieldOn(context, parentType),
       isDeferred: isDeferred,
       context: context,
     );
```

In `packages/typed_graphql_server/lib/src/plan/field_collector.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,7 +42,8 @@ final class FieldCollector {
     }
     return PlanNode(runtimeType, [
       for (final group in groups.values)
-        if (group.isDefinedOn(runtimeType)) group.build(context, runtimeType),
+        if (group.isDefinedOn(context, runtimeType))
+          group.build(context, runtimeType),
     ]);
   }
 
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -38,4 +38,5 @@ export 'src/execution/field_middleware.dart';
 export 'src/execution/field_resolver.dart';
 export 'src/execution/field_site.dart';
 export 'src/execution/graphql_exception.dart';
+export 'src/execution/introspection_policy.dart';
 export 'src/execution/response_path.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/introspection/introspection_test.dart test/builder/build_test.dart test/execution/completion_failures_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -437,6 +437,12 @@ variants; null propagation is a returned sentinel, not an exception, and
 `ErrorReporter` applies `ErrorBehavior`, masking (`GQL330`) and `onError`.
 `ExecutionOptions` holds every per-call setting, `maxDepth` and `maxSteps`
 bound the work (`GQL336`, `GQL337`).
+`introspection/` (M5c): `IntrospectionBindings` adds the `__Schema`, `__Type`, ...
+field tables (pure lanes over the core model; a list or non-null `__Type` is an
+`IntrospectedType` wrapper) and the query root's `__schema`/`__type` to the
+bindings after middleware; `EntryFields` gives the planner their `SchemaField`s,
+only on the query root; `ExecutionOptions.introspection` (`IntrospectionPolicy`)
+turns them into `GQL338` field errors.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Introspection: `__schema` and `__type(name:)` on the query root answer what
  `Schema.toIntrospection(IntrospectionQuery.full)` writes, through internal
  bindings for the `__Schema`, `__Type`, `__Field`, `__InputValue`,
  `__EnumValue` and `__Directive` objects registered by `build`.
  `ExecutionOptions.introspection` takes `IntrospectionPolicy`: `disabled`
  makes `__schema` and `__type` a `GQL338` field error; `__typename` still works.
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
git add CLAUDE.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart packages/typed_graphql_server/lib/src/execution/execution_options.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/introspection_policy.dart packages/typed_graphql_server/lib/src/execution/schema_bindings.dart packages/typed_graphql_server/lib/src/introspection/entry_fields.dart packages/typed_graphql_server/lib/src/introspection/introspected_type.dart packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart packages/typed_graphql_server/lib/src/introspection/introspection_fields.dart packages/typed_graphql_server/lib/src/introspection/member_lanes.dart packages/typed_graphql_server/lib/src/introspection/type_kind.dart packages/typed_graphql_server/lib/src/introspection/type_lanes.dart packages/typed_graphql_server/lib/src/plan/field_accumulator.dart packages/typed_graphql_server/lib/src/plan/field_collector.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/build_test.dart packages/typed_graphql_server/test/execution/completion_failures_test.dart packages/typed_graphql_server/test/introspection/introspection_fixture.dart packages/typed_graphql_server/test/introspection/introspection_test.dart
git commit -q -m "feat(typed_graphql_server): resolve introspection fields" \
  -m "__schema and __type on the query root are answered by internal pure-lane bindings over the core model and match Schema.toIntrospection; ExecutionOptions.introspection can refuse them with GQL338." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Subscriptions

Add `FieldStub.subscribe` / `subscribeWith` (a `SubscribeLane`), `GQL303` in `BuilderChecks`, `ExecutableSchema.subscribe` and `SubscriptionResult` (`SubscriptionStarted` / `SubscriptionRejected`), with `OperationPreparation` shared with `execute`, `SubscriptionExecution` and `SubscriptionResponses`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/execution/operation_preparation.dart`, `packages/typed_graphql_server/lib/src/execution/prepared_operation.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_result.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, `packages/typed_graphql_server/lib/src/builder/field_lane.dart`, `packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart`, `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`, `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/operation_execution.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/builder/subscription_fields_test.dart`, `packages/typed_graphql_server/test/execution/subscription_fixture.dart`, `packages/typed_graphql_server/test/execution/subscription_test.dart`, `packages/typed_graphql_conformance/test/execution/executor_operations_test.dart`, `packages/typed_graphql_server/test/builder/assembly_test.dart`, `packages/typed_graphql_server/test/builder/build_test.dart`

**Interfaces:**
- Consumes: Task 1 and the executor of M5b.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// execution/operation_preparation.dart
final class OperationPreparation
  OperationPreparation(…)
  PreparedOperation prepare(…)

// execution/prepared_operation.dart
sealed class PreparedOperation
final class OperationReady
final class OperationRefused

// execution/subscription_execution.dart
final class SubscriptionExecution
  SubscriptionExecution(…)
  FutureOr<SubscriptionResult> subscribe(…)

// execution/subscription_responses.dart
final class SubscriptionResponses
  SubscriptionResponses(this._template, this._source)
  Stream<ExecutionResult> get stream

// execution/subscription_result.dart
sealed class SubscriptionResult
final class SubscriptionStarted
final class SubscriptionRejected
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/subscription_fields_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  late ExecutableSchemaBuilder<Object?> b;

  setUp(() => b = ExecutableSchemaBuilder<Object?>());

  List<Diagnostic> problemsOf(void Function() build) {
    Object? thrown;
    try {
      build();
    } on Object catch (error) {
      thrown = error;
    }
    if (thrown case SchemaBuildError(:final diagnostics)) return diagnostics;
    fail('build did not throw a SchemaBuildError: $thrown');
  }

  group('GQL303', () {
    test('a subscribe source outside the subscription root', () {
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('ticks', b.int)
              .subscribe((parent, args, context, info) => Stream.value(1)),
        ],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.map((problem) => problem.code), [
        DiagnosticCode.misplacedSubscriptionField,
      ]);
      expect(
        problems.single.message,
        'Field "Query.ticks" has a subscribe source but "Query" is not the '
        'subscription root type.',
      );
    });

    test('a subscription root field without a source', () {
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final subscription = b.object<Object?>(
        'Subscription',
        fields: (t) => [t.field('ticks', b.int).pure((_) => 1)],
      );
      final problems = problemsOf(
        () => b.build(query: query, subscription: subscription),
      );
      expect(problems.map((problem) => problem.code), [
        DiagnosticCode.misplacedSubscriptionField,
      ]);
      expect(
        problems.single.message,
        'Field "Subscription.ticks" of the subscription root type has no '
        'subscribe source: declare it with subscribe or subscribeWith.',
      );
    });

    test('a correct subscription root builds', () {
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final subscription = b.object<Object?>(
        'Subscription',
        fields: (t) => [
          t
              .field('ticks', b.int)
              .subscribe((parent, args, context, info) => Stream.value(1)),
        ],
      );
      expect(
        () => b.build(query: query, subscription: subscription),
        returnsNormally,
      );
    });
  });
}
```

Create `packages/typed_graphql_server/test/execution/subscription_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of a subscription test: the source it listens to and what
/// happened around it.
final class Bus {
  /// The source; tests close it, or the subscription cancels it.
  late final StreamController<int> controller = StreamController<int>(
    onCancel: () => isCancelled = true,
  );

  bool isCancelled = false;

  /// Ends the source; a source nobody listened to stays pending.
  void dispose() => unawaited(controller.close());
  final List<String> log = [];

  /// When set, the resolver of event 1 waits for it.
  Completer<void>? gate;
}

/// A schema with one subscription field per behaviour under test.
final class SubscriptionFixture {
  SubscriptionFixture({BuildOptions<Bus>? options}) {
    final b = ExecutableSchemaBuilder<Bus>();
    final by = Arg('by', b.int);
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('noop', b.string).pure((_) => 'noop')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('count', b.int)
            .subscribe(
              (parent, args, context, info) => context.controller.stream,
            ),
        t.field('labeled', b.string.nullable).subscribeWith<int>(
          (parent, args, context, info) => context.controller.stream,
          (event, args, context, info) async {
            context.log.add('start $event');
            if (event == 1) {
              await context.gate?.future;
            } else if (event == 2) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
            if (event == 3) {
              throw StateError('bad event');
            }
            return 'n$event';
          },
        ),
        t
            .field('scaled', b.int, args: [by])
            .subscribe(
              (parent, args, context, info) =>
                  context.controller.stream.map((e) => e * args.get(by)),
            ),
        t
            .field('late', b.int)
            .subscribe(
              (parent, args, context, info) async => context.controller.stream,
            ),
        t
            .field('throwing', b.int)
            .subscribe((parent, args, context, info) => throw StateError('no')),
        t
            .field('failing', b.int)
            .subscribe(
              (parent, args, context, info) =>
                  Future<Stream<int>>.error(StateError('no future')),
            ),
      ],
    );
    built = b.build(
      query: query,
      subscription: subscription,
      options: options,
    );
  }

  late final ExecutableSchema<Bus> built;

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  ValidDocument validDocument(String text) =>
      ValidDocument.assumeValid(built.schema, parse(text));

  Future<SubscriptionResult> subscribe(
    String text,
    Bus bus, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async => built.subscribe(
    validDocument(text),
    context: bus,
    operationName: operationName,
    variables: variables,
    options: options,
  );
}
```

Create `packages/typed_graphql_server/test/execution/subscription_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'subscription_fixture.dart';

void main() {
  late SubscriptionFixture fixture;
  late Bus bus;

  setUp(() {
    fixture = SubscriptionFixture();
    bus = Bus();
    addTearDown(() => bus.dispose());
  });

  Future<Stream<ExecutionResult>> started(
    String text, {
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await fixture.subscribe(
      text,
      bus,
      variables: variables,
      options: options,
    );
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail(
        'rejected: ${error.toJson()}',
      ),
    };
  }

  Future<Map<String, Object?>> rejection(
    String text, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await fixture.subscribe(
      text,
      bus,
      operationName: operationName,
      variables: variables,
      options: options,
    );
    return switch (result) {
      SubscriptionRejected(:final error) => error.toJson().toJson(),
      SubscriptionStarted() => fail('started'),
    };
  }

  Map<String, Object?> jsonOf(ExecutionResult result) =>
      result.toJson().toJson();

  String codeOfFirst(Map<String, Object?> json) =>
      (((json['errors']! as List<Object?>).first!
                  as Map<String, Object?>)['extensions']!
              as Map<String, Object?>)['code']!
          as String;

  test('each source event is a result, in order', () async {
    final results = await started('subscription { count }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await bus.controller.close();
    expect(await collected, [
      {
        'data': {'count': 1},
      },
      {
        'data': {'count': 2},
      },
    ]);
  });

  test('async event resolvers keep the order of the events', () async {
    final results = await started('subscription { labeled }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await bus.controller.close();
    expect((await collected).map((json) => json['data']), [
      {'labeled': 'n1'},
      {'labeled': 'n2'},
    ]);
  });

  test('an event is executed only after the one before is answered', () async {
    bus.gate = Completer<void>();
    final results = await started('subscription { labeled }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bus.log, ['start 1']);
    bus.gate!.complete();
    await bus.controller.close();
    expect(await collected, hasLength(2));
    expect(bus.log, ['start 1', 'start 2']);
  });

  test('a field error inside an event stays in that result', () async {
    final results = await started('subscription { labeled }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(3)
      ..add(4);
    await bus.controller.close();
    final all = await collected;
    expect(all[0]['data'], {'labeled': null});
    expect(codeOfFirst(all[0]), 'GQL330');
    expect(all[1], {
      'data': {'labeled': 'n4'},
    });
  });

  test('cancelling the response subscription cancels the source', () async {
    final results = await started('subscription { count }');
    final subscription = results.listen((_) {});
    bus.controller.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(bus.isCancelled, isFalse);
    await subscription.cancel();
    expect(bus.isCancelled, isTrue);
  });

  test('the source is not listened to before the results are', () async {
    await started('subscription { count }');
    expect(bus.controller.hasListener, isFalse);
  });

  test('pause and resume pass through to the source', () async {
    final results = await started('subscription { count }');
    final subscription = results.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    subscription.pause();
    expect(bus.controller.isPaused, isTrue);
    subscription.resume();
    await Future<void>.delayed(Duration.zero);
    expect(bus.controller.isPaused, isFalse);
    await subscription.cancel();
  });

  test('the end of the source closes the results', () async {
    final results = await started('subscription { count }');
    final done = results.toList();
    await bus.controller.close();
    expect(await done, isEmpty);
  });

  test('a source error is a last masked result, then the end', () async {
    final results = await started('subscription { count }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..addError(StateError('secret'));
    final all = await collected;
    expect(all, hasLength(2));
    expect(all[1], {
      'data': null,
      'errors': [
        {
          'message': 'Unexpected error.',
          'extensions': {'code': 'GQL340'},
        },
      ],
    });
    expect(bus.isCancelled, isTrue);
  });

  test('a source error goes through onError', () async {
    final seen = <Object>[];
    final results = await started(
      'subscription { count }',
      options: ExecutionOptions(
        onError: (error, stackTrace, reported) {
          seen.add(error);
          return null;
        },
      ),
    );
    final collected = results.map(jsonOf).toList();
    bus.controller.addError(StateError('x'));
    await collected;
    expect(seen, [isA<StateError>()]);
  });

  test('variables reach the source and the events', () async {
    final results = await started(
      r'subscription ($by: Int!) { scaled(by: $by) }',
      variables: JsonObject({'by': JsonNumber(10)}),
    );
    final collected = results.map(jsonOf).toList();
    bus.controller.add(2);
    await bus.controller.close();
    expect(await collected, [
      {
        'data': {'scaled': 20},
      },
    ]);
  });

  test('a source function may answer with a future of the stream', () async {
    final results = await started('subscription { late }');
    final collected = results.map(jsonOf).toList();
    bus.controller.add(7);
    await bus.controller.close();
    expect(await collected, [
      {
        'data': {'late': 7},
      },
    ]);
  });

  test('a query is refused with GQL324', () async {
    final json = await rejection('{ noop }');
    expect(codeOfFirst(json), 'GQL324');
  });

  test('an unknown operation name is a request error', () async {
    final json = await rejection(
      'subscription A { count }',
      operationName: 'B',
    );
    expect(codeOfFirst(json), 'GQL320');
  });

  test('an unusable variable is a request error', () async {
    final json = await rejection(
      r'subscription ($by: Int!) { scaled(by: $by) }',
    );
    expect(codeOfFirst(json), 'GQL310');
  });

  test('a source function that throws rejects the subscription', () async {
    final json = await rejection('subscription { throwing }');
    final error =
        (json['errors']! as List<Object?>).single! as Map<String, Object?>;
    expect(error['path'], ['throwing']);
    expect(error['message'], 'Unexpected error.');
    expect(codeOfFirst(json), 'GQL330');
  });

  test('a source future that fails rejects, through onError', () async {
    final seen = <Object>[];
    final json = await rejection(
      'subscription { failing }',
      options: ExecutionOptions(
        onError: (error, stackTrace, reported) {
          seen.add(error);
          return null;
        },
      ),
    );
    expect(codeOfFirst(json), 'GQL330');
    expect(seen, [isA<StateError>()]);
  });

  test('execute runs a subscription operation once, as a query', () async {
    final payload = await fixture.built.execute(
      fixture.validDocument('subscription { labeled }'),
      context: bus,
      options: const ExecutionOptions(rootValue: 5),
    );
    expect(payload.toJson().toJson(), {
      'data': {'labeled': 'n5'},
    });
  });

  test('global middleware wraps the resolution of each event', () async {
    final seen = <String>[];
    final wrapped = SubscriptionFixture(
      options: BuildOptions<Bus>(
        middleware: [
          (next, site) => (parent, args, context, info) {
            seen.add('${site.field.name}:$parent');
            return next(parent, args, context, info);
          },
        ],
      ),
    );
    final result = await wrapped.subscribe('subscription { count }', bus);
    final results = (result as SubscriptionStarted).results;
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await bus.controller.close();
    await collected;
    expect(seen, ['count:1', 'count:2']);
  });
}
```

In `packages/typed_graphql_conformance/test/execution/executor_operations_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -23,6 +23,26 @@ void main() {
     ],
   );
 
+  // The same, as a subscription root: `execute` runs it once and hands the
+  // root value to the per-event resolver as the event.
+  ObjectTypeDef<Object?> subscriptionRoot(
+    ExecutableSchemaBuilder<Object?> b,
+    String typeName,
+    List<String> names,
+  ) => b.object<Object?>(
+    typeName,
+    fields: (t) => [
+      for (final name in names)
+        t
+            .field(name, b.string.nullable)
+            .subscribeWith<Object?>(
+              (parent, args, context, info) => const Stream<Object?>.empty(),
+              (event, args, context, info) =>
+                  (event as Map<String, String>?)?[name],
+            ),
+    ],
+  );
+
   ExecutableSchema<Object?> querySchema() {
     final b = ExecutableSchemaBuilder<Object?>();
     return b.build(query: root(b, 'Type', ['a']));
@@ -155,7 +175,7 @@ void main() {
       final schema = b.build(
         query: root(b, 'Q', ['a']),
         mutation: root(b, 'M', ['c']),
-        subscription: root(b, 'S', ['a']),
+        subscription: subscriptionRoot(b, 'S', ['a']),
       );
       expect(
         await port.json(
@@ -200,7 +220,7 @@ void main() {
       final b = ExecutableSchemaBuilder<Object?>();
       final schema = b.build(
         query: root(b, 'Q', ['a']),
-        subscription: root(b, 'S', ['a']),
+        subscription: subscriptionRoot(b, 'S', ['a']),
       );
       expect(
         await port.json(
```

In `packages/typed_graphql_server/test/builder/assembly_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -135,7 +135,11 @@ void main() {
       );
       final subscription = b.object<Object?>(
         'Subscription',
-        fields: (t) => [t.field('ticks', b.int).pure((_) => 1)],
+        fields: (t) => [
+          t
+              .field('ticks', b.int)
+              .subscribe((parent, args, context, info) => Stream.value(1)),
+        ],
       );
       final schema = b
           .build(query: query, subscription: subscription)
```

In `packages/typed_graphql_server/test/builder/build_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -235,9 +235,24 @@ type Mutation {
     });
 
     test('the schema carries the roots and the options', () {
-      final built = b.build(
-        query: query,
-        subscription: mutation,
+      // Its own builder: a subscribe field breaks every build that lacks
+      // the subscription root.
+      final c = ExecutableSchemaBuilder<Object?>();
+      final ticks = c.object<Object?>(
+        'Ticks',
+        fields: (t) => [
+          t
+              .field('tick', c.int)
+              .subscribe((parent, args, context, info) => Stream.value(1)),
+        ],
+      );
+      final root = c.object<Object?>(
+        'Query',
+        fields: (t) => [t.field('ok', c.boolean).pure((_) => true)],
+      );
+      final built = c.build(
+        query: root,
+        subscription: ticks,
         options: const BuildOptions(
           description: 'The API.',
           includesDeferAndStream: true,
@@ -246,7 +261,7 @@ type Mutation {
       final schema = built.schema.schema;
       expect(schema.queryTypeName, 'Query');
       expect(schema.mutationTypeName, isNull);
-      expect(schema.subscriptionTypeName, 'Mutation');
+      expect(schema.subscriptionTypeName, 'Ticks');
       expect(schema.description, 'The API.');
       expect(schema.includesDeferAndStream, isTrue);
     });
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/subscription_fields_test.dart test/execution/subscription_test.dart test/builder/assembly_test.dart test/builder/build_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/executor_operations_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/execution/operation_preparation.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import '../coercion/input_coercion.dart';
import '../coercion/unexpected_input_error.dart';
import '../coercion/variable_coercion.dart';
import '../coercion/variable_coercion_result.dart';
import '../plan/operation_plan.dart';
import '../plan/operation_planner.dart';
import '../plan/plan_cache.dart';
import '../plan/plan_result.dart';
import 'error_reporter.dart';
import 'execution_options.dart';
import 'execution_run.dart';
import 'prepared_operation.dart';
import 'schema_bindings.dart';

/// The part of a request that `execute` and `subscribe` share (September2025
/// 6.1 up to "ExecuteRequest"): selects and plans the operation and coerces
/// the variables. Request errors end as an [OperationRefused].
final class OperationPreparation {
  /// Prepares calls against [_schema] with [_options].
  OperationPreparation(
    this._schema,
    this._bindings,
    this._planCache,
    this._options,
  );

  final ValidSchema _schema;
  final SchemaBindings _bindings;
  final PlanCache _planCache;
  final ExecutionOptions _options;

  /// Prepares the operation named [operationName] of [document] with the
  /// request's [variables] and the resolvers' [context]. With
  /// [isSubscription] any other kind of operation is refused (`GQL324`).
  PreparedOperation prepare(
    Document document,
    Object? context, {
    String? operationName,
    JsonObject? variables,
    bool isSubscription = false,
  }) {
    final environment = CoercionEnvironment(
      _schema.schema,
      _bindings,
      includesSuggestions: _options.includesSuggestions,
    );
    switch (OperationPlanner(
      environment,
      _planCache,
    ).plan(document, operationName)) {
      case PlanRejected(:final error):
        return OperationRefused(RequestErrorResult(errors: [error]));
      case PlanReady(:final plan):
        if (isSubscription &&
            plan.operation.operation != OperationType.subscription) {
          return OperationRefused(_notSubscription());
        }
        _checkRootValue(plan);
        return _coerce(plan, context, variables ?? JsonObject({}));
    }
  }

  RequestErrorResult _notSubscription() => RequestErrorResult(
    errors: [
      GraphQLError(
        'Expected subscription operation.',
        extensions: JsonObject({
          'code': JsonString(DiagnosticCode.subscriptionRequired.id),
        }),
      ),
    ],
  );

  void _checkRootValue(OperationPlan plan) {
    final root = _bindings.objects[plan.rootType.name];
    if (root != null && !root.accepts(_options.rootValue)) {
      throw ArgumentError.value(
        _options.rootValue,
        'rootValue',
        'is not accepted by the root type "${root.name}" '
            '(${root.dartTypeName})',
      );
    }
  }

  PreparedOperation _coerce(
    OperationPlan plan,
    Object? context,
    JsonObject variables,
  ) {
    final coercion = VariableCoercion(
      InputCoercion(
        _schema.schema,
        _bindings,
        includesSuggestions: _options.includesSuggestions,
      ),
      maxCoercionErrors: _options.maxCoercionErrors,
    );
    switch (coercion.coerce(
      plan.operation.variableDefinitions,
      variables,
      source: _options.source,
    )) {
      case VariableCoercionFailure(:final errors, :final unexpected):
        return OperationRefused(
          RequestErrorResult(errors: _reportUnexpected(errors, unexpected)),
        );
      case CoercedVariables(:final values):
        return OperationReady(
          ExecutionRun(
            plan: plan,
            bindings: _bindings,
            schema: _schema,
            context: context,
            variables: values,
            rawVariables: variables,
            options: _options,
          ),
        );
    }
  }

  // The hook sees what user code threw while variables were coerced and may
  // replace the error that stands for it.
  List<GraphQLError> _reportUnexpected(
    List<GraphQLError> errors,
    List<UnexpectedInputError> unexpected,
  ) {
    final reporter = ErrorReporter(_options);
    final replacements = Map<GraphQLError, GraphQLError>.identity();
    for (final entry in unexpected) {
      replacements[entry.reported] = reporter.hooked(
        entry.error,
        entry.stackTrace,
        entry.reported,
      );
    }
    return [for (final error in errors) replacements[error] ?? error];
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/prepared_operation.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'execution_run.dart';

/// The outcome of preparing an operation: planned, variables coerced.
sealed class PreparedOperation {
  const PreparedOperation();
}

/// The operation can run; [run] holds its plan and coerced variables.
final class OperationReady extends PreparedOperation {
  /// Wraps [run].
  const OperationReady(this.run);

  /// The execution state of the first run.
  final ExecutionRun run;
}

/// The operation cannot run; [error] is the request error.
final class OperationRefused extends PreparedOperation {
  /// Wraps [error].
  const OperationRefused(this.error);

  /// The request error to answer with.
  final RequestErrorResult error;
}
```

Create `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_cache.dart';
import 'execution_options.dart';
import 'execution_run.dart';
import 'operation_preparation.dart';
import 'prepared_operation.dart';
import 'schema_bindings.dart';
import 'subscription_responses.dart';
import 'subscription_result.dart';

/// One call of `ExecutableSchema.subscribe` (September2025 6.2.3
/// "Subscription"): prepares the operation, creates the source event stream
/// of its single root field and maps the events to responses.
final class SubscriptionExecution {
  /// Prepares a call against [_schema] with [_options].
  SubscriptionExecution(
    this._schema,
    this._bindings,
    this._planCache,
    this._options,
  );

  final ValidSchema _schema;
  final SchemaBindings _bindings;
  final PlanCache _planCache;
  final ExecutionOptions _options;

  /// Starts the subscription [operationName] of [document].
  FutureOr<SubscriptionResult> subscribe(
    Document document,
    Object? context, {
    String? operationName,
    JsonObject? variables,
  }) {
    final prepared =
        OperationPreparation(
          _schema,
          _bindings,
          _planCache,
          _options,
        ).prepare(
          document,
          context,
          operationName: operationName,
          variables: variables,
          isSubscription: true,
        );
    return switch (prepared) {
      OperationRefused(:final error) => SubscriptionRejected(error),
      OperationReady(:final run) => _open(run),
    };
  }

  FutureOr<SubscriptionResult> _open(ExecutionRun run) {
    final root = run.plan.rootFor(run.plan.keyFor(run.variables));
    final fields = root.fields;
    if (root.problem case final problem?) {
      run.reporter.problem(problem, null, const []);
    }
    if (fields.isEmpty) {
      return _rejected(run);
    }
    final opened = run.fields.openSource(_options.rootValue, fields.first);
    return opened is Future<Stream<Object?>?>
        ? opened.then((source) => _started(run, source))
        : _started(run, opened);
  }

  SubscriptionResult _started(ExecutionRun run, Stream<Object?>? source) =>
      source == null
      ? _rejected(run)
      : SubscriptionStarted(SubscriptionResponses(run, source).stream);

  // A run that found no source has errors in its log; one that found no
  // root field at all has none, so it says so.
  SubscriptionRejected _rejected(ExecutionRun run) {
    final log = run.reporter.log;
    final errors = log.haltError != null ? [log.haltError!] : log.errors;
    return SubscriptionRejected(
      RequestErrorResult(
        errors: errors.isEmpty
            ? [
                GraphQLError(
                  'The subscription selects no root field.',
                  extensions: JsonObject({
                    'code': JsonString(DiagnosticCode.noOperation.id),
                  }),
                ),
              ]
            : errors,
      ),
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'execution_run.dart';

/// The response stream of a subscription (September2025 6.2.3.2
/// "MapSourceToResponseEvent"): every source event is executed as the root
/// field's value, one at a time and in order.
///
/// The source is paused while an event executes, so its events, its error and
/// its end wait their turn. The response stream is a single-subscription
/// controller: listening starts the source, pause and resume pass through to
/// it, and cancelling cancels it.
final class SubscriptionResponses {
  /// Maps the events of [_source] to results of runs like [_template].
  SubscriptionResponses(this._template, this._source) {
    _controller = StreamController<ExecutionResult>(
      onListen: _listen,
      onPause: () => _subscription?.pause(),
      onResume: () => _subscription?.resume(),
      onCancel: _cancel,
    );
  }

  final ExecutionRun _template;
  final Stream<Object?> _source;

  // Set in the constructor body, which runs before anything can listen.
  late final StreamController<ExecutionResult> _controller;
  StreamSubscription<Object?>? _subscription;
  bool _isCancelled = false;

  /// The results; listen once.
  Stream<ExecutionResult> get stream => _controller.stream;

  void _listen() {
    _subscription = _source.listen(
      _onEvent,
      onError: _fail,
      onDone: _onSourceDone,
    );
  }

  Future<void> _cancel() {
    _isCancelled = true;
    return _subscription?.cancel() ?? Future<void>.value();
  }

  void _onEvent(Object? event) {
    _subscription?.pause();
    try {
      final result = _template.restarted().executeRoot(event);
      if (result is Future<ExecutionResult>) {
        unawaited(result.then(_emit, onError: _fail));
      } else {
        _emit(result);
      }
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _emit(ExecutionResult result) {
    if (_isCancelled) {
      return;
    }
    _controller.add(result);
    _subscription?.resume();
  }

  void _onSourceDone() {
    if (!_isCancelled) {
      _controller.close();
    }
  }

  // The source failed (or the library did, which cannot be told apart by
  // the client): one last result with the error, then the end (spec 10).
  void _fail(Object error, StackTrace stackTrace) {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final reported = _template.reporter.sourceFailure(error, stackTrace);
    _controller.add(ExecutionResult(null, errors: [reported]));
    _controller.close();
    unawaited(_subscription?.cancel() ?? Future<void>.value());
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/subscription_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// What `ExecutableSchema.subscribe` answers: a stream of results, or a
/// request error and no stream.
///
/// {@category execution}
sealed class SubscriptionResult {
  const SubscriptionResult();
}

/// The subscription started.
///
/// [results] is a single-subscription stream: the source is listened to when
/// [results] is, pausing and resuming pass through to the source, and
/// cancelling the subscription to [results] cancels the source. It closes
/// when the source is done.
///
/// {@category execution}
final class SubscriptionStarted extends SubscriptionResult {
  /// Wraps [results].
  const SubscriptionStarted(this.results);

  /// One result per source event, in order.
  final Stream<ExecutionResult> results;
}

/// The subscription did not start: a request error, or the source stream
/// could not be created (September2025 6.2.3.1), as graphql-js answers with
/// a result of errors instead of a stream.
///
/// {@category execution}
final class SubscriptionRejected extends SubscriptionResult {
  /// Wraps [error].
  const SubscriptionRejected(this.error);

  /// The errors, as the response to the request.
  final RequestErrorResult error;
}
```

In `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'field_lane.dart';
 import 'interface_type_def.dart';
 import 'named_type_def.dart';
 import 'object_type_def.dart';
@@ -16,8 +17,13 @@ final class BuilderChecks {
   /// The diagnostics found so far; the checks add to them.
   final List<Diagnostic> problems;
 
-  /// Runs both checks over [definitions].
-  void check(List<NamedTypeDef> definitions, PossibleTypes possibleTypes) {
+  /// Runs the checks over [definitions]; [subscription] is the
+  /// subscription root, null when the schema has none.
+  void check(
+    List<NamedTypeDef> definitions,
+    PossibleTypes possibleTypes,
+    ObjectTypeDef<Object?>? subscription,
+  ) {
     for (final definition in definitions) {
       switch (definition) {
         case ObjectTypeDef<Object?>():
@@ -39,6 +45,36 @@ final class BuilderChecks {
       }
     }
     _checkTypeResolution(definitions, possibleTypes);
+    _checkSubscriptionFields(definitions, subscription);
+  }
+
+  // `GQL303`: a subscribe source belongs to the fields of the subscription
+  // root, and each of those fields needs one.
+  void _checkSubscriptionFields(
+    List<NamedTypeDef> definitions,
+    ObjectTypeDef<Object?>? subscription,
+  ) {
+    for (final definition in definitions) {
+      if (definition is! ObjectTypeDef<Object?>) continue;
+      final isRoot = identical(definition, subscription);
+      for (final field in definition.fields) {
+        final hasSource = field.lane is SubscribeLane;
+        if (hasSource == isRoot) continue;
+        problems.add(
+          Diagnostic(
+            .misplacedSubscriptionField,
+            .error,
+            isRoot
+                ? 'Field "${definition.name}.${field.name}" of the '
+                      'subscription root type has no subscribe source: '
+                      'declare it with subscribe or subscribeWith.'
+                : 'Field "${definition.name}.${field.name}" has a subscribe '
+                      'source but "${definition.name}" is not the '
+                      'subscription root type.',
+          ),
+        );
+      }
+    }
   }
 
   void _checkInterfaces(
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,7 +45,7 @@ final class ExecutableSchemaAssembly<C> {
   ExecutableSchema<C> assemble() {
     final problems = <Diagnostic>[];
     final possibleTypes = PossibleTypes(definitions);
-    BuilderChecks(problems).check(definitions, possibleTypes);
+    BuilderChecks(problems).check(definitions, possibleTypes, subscription);
     final schema = _schemaOf(problems);
     final result = const SchemaValidator().validate(schema);
     if (result case InvalidSchema(:final diagnostics)) {
```

In `packages/typed_graphql_server/lib/src/builder/field_lane.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -35,6 +35,34 @@ final class ResolverLane extends FieldLane {
   resolve;
 }
 
+/// A subscription root field: a source of events and the resolver run for
+/// each event (spec 10).
+final class SubscribeLane extends FieldLane {
+  /// Creates a lane that opens events with [source] and answers each with
+  /// [resolve].
+  const SubscribeLane(this.source, this.resolve);
+
+  /// Opens the stream of source events (September2025 6.2.3.1), once per
+  /// subscription; it may wait before it answers.
+  final FutureOr<Stream<Object?>> Function(
+    Object? parent,
+    Arguments arguments,
+    Object? context,
+    FieldInfo info,
+  )
+  source;
+
+  /// Turns one source event into the field's value (6.2.3.2). It is also
+  /// what `execute` calls, with the root value as the event.
+  final FutureOr<Object?> Function(
+    Object? event,
+    Arguments arguments,
+    Object? context,
+    FieldInfo info,
+  )
+  resolve;
+}
+
 /// An interface field without a resolver: implementations declare it.
 final class DeclaredOnlyLane extends FieldLane {
   /// Creates the lane.
```

In `packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,9 +1,13 @@
+import 'dart:async';
+
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../execution/field_info.dart';
 import '../execution/field_middleware.dart';
 import '../execution/field_resolver.dart';
 import '../execution/field_site.dart';
 import '../execution/schema_bindings.dart';
+import 'arguments.dart';
 import 'build_options.dart';
 import 'field_def.dart';
 import 'field_lane.dart';
@@ -57,21 +61,32 @@ final class FieldMiddlewareComposer<C> {
   ) {
     final lane = definition.lane;
     final schemaField = parent.fieldNamed(definition.name);
-    if (lane is! ResolverLane || schemaField == null) return definition;
+    if (schemaField == null) return definition;
+    // A subscription field's per-event resolver is the field's resolver; its
+    // source function is not wrapped (spec 10).
+    final FieldResolver<C>? base = switch (lane) {
+      ResolverLane(:final resolve) => resolve,
+      SubscribeLane(:final resolve) => resolve,
+      _ => null,
+    };
+    if (base == null) return definition;
     final site = FieldSite(parent, schemaField);
-    final FieldResolver<C> base = lane.resolve;
     var resolver = base;
     for (final middleware in _chainOf(definition, schemaField).reversed) {
       resolver = middleware(resolver, site);
     }
     if (identical(resolver, base)) return definition;
     final composed = resolver;
-    return definition.withLane(
-      ResolverLane(
-        (parent, arguments, context, info) =>
-            composed(parent, arguments, context as C, info),
-      ),
-    );
+    FutureOr<Object?> run(
+      Object? parent,
+      Arguments arguments,
+      Object? context,
+      FieldInfo info,
+    ) => composed(parent, arguments, context as C, info);
+    return definition.withLane(switch (lane) {
+      SubscribeLane(:final source) => SubscribeLane(source, run),
+      _ => ResolverLane(run),
+    });
   }
 
   // Global, then the field's own, then the directive slots in the order the
```

In `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -145,6 +145,47 @@ final class FieldStub<P, R, C> {
     );
   }
 
+  /// Completes a subscription root field whose events are the field's
+  /// values: each item of the stream [source] returns is completed as the
+  /// value of the field (spec 10).
+  ///
+  /// [source] may answer with a future of the stream. Global and field
+  /// middleware do not wrap it; they wrap the per-event resolution.
+  FieldDef<P, C> subscribe(
+    FutureOr<Stream<R>> Function(
+      P parent,
+      Arguments args,
+      C context,
+      FieldInfo info,
+    )
+    source,
+  ) => subscribeWith<R>(source, (event, args, context, info) => event);
+
+  /// Completes a subscription root field whose events of type `E` are turned
+  /// into the field's value by [resolve] (spec 10).
+  ///
+  /// [source] may answer with a future of the stream. [resolve] is the
+  /// field's resolver: global and field middleware wrap it, once per event.
+  FieldDef<P, C> subscribeWith<E>(
+    FutureOr<Stream<E>> Function(
+      P parent,
+      Arguments args,
+      C context,
+      FieldInfo info,
+    )
+    source,
+    FutureOr<R> Function(E event, Arguments args, C context, FieldInfo info)
+    resolve,
+  ) => _define(
+    SubscribeLane(
+      (parent, arguments, context, info) =>
+          source(parent as P, arguments, context as C, info),
+      (event, arguments, context, info) =>
+          resolve(event as E, arguments, context as C, info),
+    ),
+    _args,
+  );
+
   /// Completes an interface field that has no resolver: every implementing
   /// object declares it.
   FieldDef<P, C> declareOnly() => _define(const DeclaredOnlyLane(), _args);
```

In `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,6 +66,23 @@ final class ErrorReporter {
     );
   }
 
+  /// The error a failed source stream ends a subscription with (`GQL340`,
+  /// spec 10): a [GraphQLException] as it is, else the masked message, then
+  /// offered to `ExecutionOptions.onError`. It has no path or locations.
+  GraphQLError sourceFailure(Object error, StackTrace stackTrace) {
+    final reported = switch (error) {
+      GraphQLException(:final message, :final extensions) => GraphQLError(
+        message,
+        extensions: extensions,
+      ),
+      _ => GraphQLError(
+        options.maskErrors ? _masked : error.toString(),
+        extensions: _codeOf(DiagnosticCode.subscriptionSourceFailed),
+      ),
+    };
+    return hooked(error, stackTrace, reported);
+  }
+
   /// [reported] after `ExecutionOptions.onError` has seen it: the hook's
   /// replacement, [reported] itself, or the masked error when the hook
   /// throws.
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,6 +7,8 @@ import '../plan/plan_cache.dart';
 import 'execution_options.dart';
 import 'operation_execution.dart';
 import 'schema_bindings.dart';
+import 'subscription_execution.dart';
+import 'subscription_result.dart';
 
 /// A validated schema with the resolvers behind it: what
 /// `ExecutableSchemaBuilder.build` returns. `C` is the context type the
@@ -49,13 +51,7 @@ final class ExecutableSchema<C> {
     JsonObject? variables,
     ExecutionOptions options = const ExecutionOptions(),
   }) {
-    if (!identical(document.schema, schema)) {
-      throw ArgumentError.value(
-        document,
-        'document',
-        'was validated against another schema',
-      );
-    }
+    _checkDocument(document);
     return OperationExecution(
       schema,
       bindings,
@@ -68,4 +64,46 @@ final class ExecutableSchema<C> {
       variables: variables,
     );
   }
+
+  /// Starts the subscription named [operationName] of [document] (the only
+  /// operation when null): September2025 6.2.3 "Subscription".
+  ///
+  /// The result is a [SubscriptionStarted] with the stream of responses, or
+  /// a [SubscriptionRejected] when the request cannot start: the request
+  /// errors of [execute], `GQL324` for a query or a mutation, and a source
+  /// function that threw or whose future failed. Each source event is
+  /// executed on its own, in order.
+  ///
+  /// The requirements on [document] and [ExecutionOptions.rootValue] are
+  /// those of [execute].
+  FutureOr<SubscriptionResult> subscribe(
+    ValidDocument document, {
+    required C context,
+    String? operationName,
+    JsonObject? variables,
+    ExecutionOptions options = const ExecutionOptions(),
+  }) {
+    _checkDocument(document);
+    return SubscriptionExecution(
+      schema,
+      bindings,
+      planCache,
+      options,
+    ).subscribe(
+      document.document,
+      context,
+      operationName: operationName,
+      variables: variables,
+    );
+  }
+
+  void _checkDocument(ValidDocument document) {
+    if (!identical(document.schema, schema)) {
+      throw ArgumentError.value(
+        document,
+        'document',
+        'was validated against another schema',
+      );
+    }
+  }
 }
```

In `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,6 +11,7 @@ import 'field_execution.dart';
 import 'leaf_completion.dart';
 import 'list_completion.dart';
 import 'object_completion.dart';
+import 'response_path.dart';
 import 'schema_bindings.dart';
 import 'selection_executor.dart';
 import 'value_completion.dart';
@@ -78,6 +79,41 @@ final class ExecutionRun {
   /// Completes the value of an object, interface or union.
   late final ObjectCompletion objects = ObjectCompletion(this);
 
+  /// The same execution with a fresh error log: what each event of a
+  /// subscription runs in (spec 10).
+  ExecutionRun restarted() => ExecutionRun(
+    plan: plan,
+    bindings: bindings,
+    schema: schema,
+    context: context,
+    variables: variables,
+    rawVariables: rawVariables,
+    options: options,
+  );
+
+  /// Executes the operation's root selection on [rootValue] and builds the
+  /// response (September2025 6.2 "Executing Operations"). A mutation runs
+  /// its root fields serially.
+  FutureOr<ExecutionResult> executeRoot(Object? rootValue) {
+    final root = plan.rootFor(plan.keyFor(variables));
+    if (root.problem case final problem?) {
+      reporter.problem(problem, null, const []);
+      return _response(null);
+    }
+    final data = plan.operation.operation == OperationType.mutation
+        ? selection.executeSerially(rootValue, root, ResponsePath.root, 1)
+        : selection.execute(rootValue, root, ResponsePath.root, 1);
+    return data is Future<JsonObject?> ? data.then(_response) : _response(data);
+  }
+
+  ExecutionResult _response(JsonObject? data) {
+    final log = reporter.log;
+    if (log.haltError case final halted?) {
+      return ExecutionResult(null, errors: [halted]);
+    }
+    return ExecutionResult(data, errors: log.errors);
+  }
+
   /// A completed value at a position of type [type], after the position's
   /// own rule for failure (spec 6.4.4): a failed value (Dart `null`) becomes
   /// `null` in the response unless the position is non-null and errors
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -61,6 +61,65 @@ final class FieldExecution {
     return _resolve(parent, definition, field.type, site);
   }
 
+  /// Opens the source stream of the subscription root field [plan]
+  /// (September2025 6.2.3.1 "CreateSourceEventStream") on the root value
+  /// [parent]. Null after the problem has been recorded in the run's log:
+  /// an argument that cannot be coerced, a source function that threw or
+  /// whose future failed. Middleware does not wrap the source (spec 10).
+  FutureOr<Stream<Object?>?> openSource(Object? parent, FieldPlan plan) {
+    final site = CompletionSite(
+      plan,
+      ResponsePath.root.key(plan.responseKey, 0),
+      1,
+    );
+    final definition =
+        _run.bindings.fields[plan.parentType.name]?[plan.fieldName];
+    final lane = definition?.lane;
+    final field = plan.field;
+    if (definition == null || lane is! SubscribeLane || field == null) {
+      _run.reporter.fieldError(
+        DiagnosticCode.unexpectedError,
+        'Field "${site.fieldLabel}" is not a subscription field.',
+        site,
+      );
+      return null;
+    }
+    final arguments = _argumentsOf(definition, site);
+    if (arguments == null) {
+      return null;
+    }
+    return _callSource(lane, parent, arguments, (field.type, site));
+  }
+
+  FutureOr<Stream<Object?>?> _callSource(
+    SubscribeLane lane,
+    Object? parent,
+    Arguments arguments,
+    (TypeRef, CompletionSite) where,
+  ) {
+    final site = where.$2;
+    try {
+      final opened = lane.source(
+        parent,
+        arguments,
+        _run.context,
+        _infoOf(where.$1, site),
+      );
+      return opened is Future<Stream<Object?>>
+          ? opened.then<Stream<Object?>?>(
+              (stream) => stream,
+              onError: (Object error, StackTrace stackTrace) {
+                _run.reporter.thrown(error, stackTrace, site);
+                return null;
+              },
+            )
+          : opened;
+    } on Object catch (error, stackTrace) {
+      _run.reporter.thrown(error, stackTrace, site);
+      return null;
+    }
+  }
+
   // Only `__typename` has no schema field; the planner drops any other
   // name that is not defined.
   FutureOr<JsonValue?> _metaField(FieldPlan plan, CompletionSite site) {
@@ -143,7 +202,8 @@ final class FieldExecution {
     FieldDef<Object?, Object?> definition,
     CompletionSite site,
   ) {
-    if (definition.lane is! ResolverLane) {
+    final lane = definition.lane;
+    if (lane is PureLane || lane is DeclaredOnlyLane) {
       return Arguments.empty;
     }
     switch (site.plan.argumentsFor(_run.variables)) {
@@ -171,6 +231,13 @@ final class FieldExecution {
       _run.context,
       _infoOf(where.$1, where.$2),
     ),
+    // `execute` on a subscription runs it once: the root value is the event.
+    SubscribeLane(:final resolve) => resolve(
+      parent,
+      arguments,
+      _run.context,
+      _infoOf(where.$1, where.$2),
+    ),
     DeclaredOnlyLane() => throw StateError(
       'Field "${where.$2.fieldLabel}" is declared without a resolver.',
     ),
```

In `packages/typed_graphql_server/lib/src/execution/operation_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,26 +2,16 @@ import 'dart:async';
 
 import 'package:typed_graphql/typed_graphql.dart';
 
-import '../coercion/coercion_environment.dart';
-import '../coercion/input_coercion.dart';
-import '../coercion/unexpected_input_error.dart';
-import '../coercion/variable_coercion.dart';
-import '../coercion/variable_coercion_result.dart';
-import '../plan/operation_plan.dart';
-import '../plan/operation_planner.dart';
 import '../plan/plan_cache.dart';
-import '../plan/plan_result.dart';
-import 'error_reporter.dart';
 import 'execution_options.dart';
-import 'execution_run.dart';
-import 'response_path.dart';
+import 'operation_preparation.dart';
+import 'prepared_operation.dart';
 import 'schema_bindings.dart';
 
 /// One call of `ExecutableSchema.execute` (September2025 6.1 "Executing
-/// Requests"): plans the operation, coerces the variables, runs the root
-/// selection and builds the response. Request errors (no operation,
-/// unusable variables) end as a `RequestErrorResult`; everything after is
-/// an `ExecutionResult`.
+/// Requests"): prepares the operation, runs the root selection and builds
+/// the response. Request errors (no operation, unusable variables) end as a
+/// `RequestErrorResult`; everything after is an `ExecutionResult`.
 final class OperationExecution {
   /// Prepares a call against [_schema] with [_options].
   OperationExecution(
@@ -44,114 +34,21 @@ final class OperationExecution {
     String? operationName,
     JsonObject? variables,
   }) {
-    final environment = CoercionEnvironment(
-      _schema.schema,
-      _bindings,
-      includesSuggestions: _options.includesSuggestions,
-    );
-    switch (OperationPlanner(
-      environment,
-      _planCache,
-    ).plan(document, operationName)) {
-      case PlanRejected(:final error):
-        return RequestErrorResult(errors: [error]);
-      case PlanReady(:final plan):
-        _checkRootValue(plan);
-        return _coerceAndRun(plan, context, variables ?? JsonObject({}));
-    }
-  }
-
-  void _checkRootValue(OperationPlan plan) {
-    final root = _bindings.objects[plan.rootType.name];
-    if (root != null && !root.accepts(_options.rootValue)) {
-      throw ArgumentError.value(
-        _options.rootValue,
-        'rootValue',
-        'is not accepted by the root type "${root.name}" '
-            '(${root.dartTypeName})',
-      );
-    }
-  }
-
-  FutureOr<ResponsePayload> _coerceAndRun(
-    OperationPlan plan,
-    Object? context,
-    JsonObject variables,
-  ) {
-    final coercion = VariableCoercion(
-      InputCoercion(
-        _schema.schema,
-        _bindings,
-        includesSuggestions: _options.includesSuggestions,
-      ),
-      maxCoercionErrors: _options.maxCoercionErrors,
-    );
-    switch (coercion.coerce(
-      plan.operation.variableDefinitions,
-      variables,
-      source: _options.source,
-    )) {
-      case VariableCoercionFailure(:final errors, :final unexpected):
-        return RequestErrorResult(
-          errors: _reportUnexpected(errors, unexpected),
+    final prepared =
+        OperationPreparation(
+          _schema,
+          _bindings,
+          _planCache,
+          _options,
+        ).prepare(
+          document,
+          context,
+          operationName: operationName,
+          variables: variables,
         );
-      case CoercedVariables(:final values):
-        return _run(plan, context, values, variables);
-    }
-  }
-
-  // The hook sees what user code threw while variables were coerced and may
-  // replace the error that stands for it.
-  List<GraphQLError> _reportUnexpected(
-    List<GraphQLError> errors,
-    List<UnexpectedInputError> unexpected,
-  ) {
-    final reporter = ErrorReporter(_options);
-    final replacements = Map<GraphQLError, GraphQLError>.identity();
-    for (final entry in unexpected) {
-      replacements[entry.reported] = reporter.hooked(
-        entry.error,
-        entry.stackTrace,
-        entry.reported,
-      );
-    }
-    return [for (final error in errors) replacements[error] ?? error];
-  }
-
-  FutureOr<ResponsePayload> _run(
-    OperationPlan plan,
-    Object? context,
-    Map<String, Object?> values,
-    JsonObject rawVariables,
-  ) {
-    final run = ExecutionRun(
-      plan: plan,
-      bindings: _bindings,
-      schema: _schema,
-      context: context,
-      variables: values,
-      rawVariables: rawVariables,
-      options: _options,
-    );
-    final root = plan.rootFor(plan.keyFor(values));
-    if (root.problem case final problem?) {
-      run.reporter.problem(problem, null, const []);
-      return _response(run, null);
-    }
-    final rootValue = _options.rootValue;
-    final data = plan.operation.operation == OperationType.mutation
-        ? run.selection.executeSerially(rootValue, root, ResponsePath.root, 1)
-        : run.selection.execute(rootValue, root, ResponsePath.root, 1);
-    return data is Future<JsonObject?>
-        ? data.then((resolved) => _response(run, resolved))
-        : _response(run, data);
-  }
-
-  ExecutionResult _response(ExecutionRun run, JsonObject? data) {
-    final log = run.reporter.log;
-    if (log.haltError case final halted?) {
-      return ExecutionResult(null, errors: [halted]);
-    }
-    return ExecutionResult(data, errors: log.errors);
+    return switch (prepared) {
+      OperationRefused(:final error) => error,
+      OperationReady(:final run) => run.executeRoot(_options.rootValue),
+    };
   }
 }
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,3 +40,4 @@ export 'src/execution/field_site.dart';
 export 'src/execution/graphql_exception.dart';
 export 'src/execution/introspection_policy.dart';
 export 'src/execution/response_path.dart';
+export 'src/execution/subscription_result.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/subscription_fields_test.dart test/execution/subscription_test.dart test/builder/assembly_test.dart test/builder/build_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/executor_operations_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Subscriptions: `t.field(...).subscribe(source)` (each event is the field's
  value) and `subscribeWith<E>(source, resolve)` declare a subscription root
  field; `build` reports `GQL303` for a source outside the subscription root
  or a root field without one. `ExecutableSchema.subscribe` answers a
  `SubscriptionStarted` with a single-subscription stream of
  `ExecutionResult`s (one event at a time, in order; cancel, pause and resume
  reach the source; a source error is a last masked `GQL340` result) or a
  `SubscriptionRejected` (request errors, `GQL324` for a query or mutation, a
  failing source function). `execute` on a subscription runs it once as a
  query.
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
git add packages/typed_graphql_conformance/test/execution/executor_operations_test.dart packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/builder/builder_checks.dart packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart packages/typed_graphql_server/lib/src/builder/field_lane.dart packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart packages/typed_graphql_server/lib/src/builder/field_stub.dart packages/typed_graphql_server/lib/src/execution/error_reporter.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/lib/src/execution/execution_run.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/operation_execution.dart packages/typed_graphql_server/lib/src/execution/operation_preparation.dart packages/typed_graphql_server/lib/src/execution/prepared_operation.dart packages/typed_graphql_server/lib/src/execution/subscription_execution.dart packages/typed_graphql_server/lib/src/execution/subscription_responses.dart packages/typed_graphql_server/lib/src/execution/subscription_result.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/assembly_test.dart packages/typed_graphql_server/test/builder/build_test.dart packages/typed_graphql_server/test/builder/subscription_fields_test.dart packages/typed_graphql_server/test/execution/subscription_fixture.dart packages/typed_graphql_server/test/execution/subscription_test.dart
git commit -q -m "feat(typed_graphql_server): execute subscriptions" \
  -m "Adds subscribe and subscribeWith fields, the GQL303 build check and ExecutableSchema.subscribe, whose response stream maps source events one at a time and passes cancel, pause and resume to the source." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The meta-field name in a validation message (core)

The introspection port found that a missing `__type(name:)` argument was named `Query.__type(name:)`; graphql-js writes `<meta>.__type(name:)`. Fix `ProvidedRequiredArgumentsRule`.

**Files:**
- Modify: `packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart`, `packages/typed_graphql/CHANGELOG.md`
- Test: `packages/typed_graphql/test/validation/rules/argument_rules_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql/test/validation/rules/argument_rules_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -101,4 +101,16 @@ directive @tag(label: String!) on FIELD
       [startsWith('1:19 GQL208'), startsWith('1:3 GQL210')],
     );
   });
+
+  test('a missing argument of a meta-field names the field <meta>', () {
+    expect(
+      checked.errors('{ __type { name } }', [
+        const ProvidedRequiredArgumentsRule(),
+      ]),
+      [
+        '1:3 GQL210 Argument "<meta>.__type(name:)" of type "String!" is '
+            'required, but it was not provided.',
+      ],
+    );
+  });
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/argument_rules_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,6 +5,7 @@ import '../../language/ast/type_ref.dart';
 import '../../language/printer/printer.dart';
 import '../../language/visitor/ast_visitor.dart';
 import '../../schema/model/input_value.dart';
+import '../meta_fields.dart';
 import '../validation_context.dart';
 import '../validation_rule.dart';
 
@@ -46,13 +47,11 @@ final class _ProvidedRequiredArguments(final ValidationContext context)
     final provided = {
       for (final argument in node.arguments) argument.name.value,
     };
+    // graphql-js names a meta-field `<meta>`: it belongs to no type.
+    final owner = identical(field, MetaFields.type) ? '<meta>' : parent.name;
     for (final argument in field.arguments) {
       if (_isMissing(argument, provided)) {
-        _report(
-          node,
-          '${parent.name}.${field.name}(${argument.name}:)',
-          argument,
-        );
+        _report(node, '$owner.${field.name}(${argument.name}:)', argument);
       }
     }
   }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/argument_rules_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `ProvidedRequiredArgumentsRule` names the missing argument of `__type`
  `<meta>.__type(name:)`, as graphql-js.
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart packages/typed_graphql/test/validation/rules/argument_rules_test.dart
git commit -q -m "fix(typed_graphql): name the meta-field <meta> in the required-argument error" \
  -m "graphql-js words a missing argument of __type as <meta>.__type(name:) because a meta-field belongs to no type; the rule printed Query.__type(name:)." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Conformance: introspection and subscriptions

Port `introspection-test.ts`, the introspection cases left for M5c, `subscribe-test.ts` and `simplePubSub-test.ts` (with a Dart `SimplePubSub`), and extend `mapping/execution.csv`.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`
- Test: `packages/typed_graphql_conformance/test/execution/fixtures/introspection_query_result.json`, `packages/typed_graphql_conformance/test/execution/introspection_deprecation_test.dart`, `packages/typed_graphql_conformance/test/execution/introspection_one_of_test.dart`, `packages/typed_graphql_conformance/test/execution/introspection_test.dart`, `packages/typed_graphql_conformance/test/execution/subscribe_initialization_test.dart`, `packages/typed_graphql_conformance/test/execution/subscribe_publish_test.dart`, `packages/typed_graphql_conformance/test/support/email_subscription.dart`, `packages/typed_graphql_conformance/test/support/introspection_fixture.dart`, `packages/typed_graphql_conformance/test/support/simple_pub_sub.dart`, `packages/typed_graphql_conformance/test/execution/enum_type_test.dart`, `packages/typed_graphql_conformance/test/execution/union_interface_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/execution_port.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/execution/fixtures/introspection_query_result.json`:

```text
{
  "data": {
    "__schema": {
      "queryType": {
        "name": "SomeObject",
        "kind": "OBJECT"
      },
      "mutationType": null,
      "subscriptionType": null,
      "types": [
        {
          "kind": "OBJECT",
          "name": "SomeObject",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "someField",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "SCALAR",
          "name": "String",
          "specifiedByURL": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "SCALAR",
          "name": "Boolean",
          "specifiedByURL": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "OBJECT",
          "name": "__Schema",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "types",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Type",
                      "ofType": null
                    }
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "queryType",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "mutationType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "subscriptionType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "directives",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Boolean",
                      "ofType": null
                    }
                  },
                  "defaultValue": "false"
                }
              ],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__Directive",
                      "ofType": null
                    }
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "OBJECT",
          "name": "__Type",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "kind",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "ENUM",
                  "name": "__TypeKind",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "specifiedByURL",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "fields",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Boolean",
                      "ofType": null
                    }
                  },
                  "defaultValue": "false"
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Field",
                    "ofType": null
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "interfaces",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "possibleTypes",
              "args": [],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__Type",
                    "ofType": null
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "enumValues",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Boolean",
                      "ofType": null
                    }
                  },
                  "defaultValue": "false"
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__EnumValue",
                    "ofType": null
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "inputFields",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Boolean",
                      "ofType": null
                    }
                  },
                  "defaultValue": "false"
                }
              ],
              "type": {
                "kind": "LIST",
                "name": null,
                "ofType": {
                  "kind": "NON_NULL",
                  "name": null,
                  "ofType": {
                    "kind": "OBJECT",
                    "name": "__InputValue",
                    "ofType": null
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "ofType",
              "args": [],
              "type": {
                "kind": "OBJECT",
                "name": "__Type",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "isOneOf",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "Boolean",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "ENUM",
          "name": "__TypeKind",
          "specifiedByURL": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "enumValues": [
            {
              "name": "SCALAR",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "OBJECT",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "INTERFACE",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "UNION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "ENUM",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "INPUT_OBJECT",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "LIST",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "NON_NULL",
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "possibleTypes": null
        },
        {
          "kind": "OBJECT",
          "name": "__Field",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "args",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Boolean",
                      "ofType": null
                    }
                  },
                  "defaultValue": "false"
                }
              ],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "type",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "OBJECT",
          "name": "__InputValue",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "type",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "OBJECT",
                  "name": "__Type",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "defaultValue",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "OBJECT",
          "name": "__EnumValue",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "OBJECT",
          "name": "__Directive",
          "specifiedByURL": null,
          "fields": [
            {
              "name": "name",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "description",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "isRepeatable",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "locations",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "ENUM",
                      "name": "__DirectiveLocation",
                      "ofType": null
                    }
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "args",
              "args": [
                {
                  "name": "includeDeprecated",
                  "type": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "SCALAR",
                      "name": "Boolean",
                      "ofType": null
                    }
                  },
                  "defaultValue": "false"
                }
              ],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "LIST",
                  "name": null,
                  "ofType": {
                    "kind": "NON_NULL",
                    "name": null,
                    "ofType": {
                      "kind": "OBJECT",
                      "name": "__InputValue",
                      "ofType": null
                    }
                  }
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "isDeprecated",
              "args": [],
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              },
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "deprecationReason",
              "args": [],
              "type": {
                "kind": "SCALAR",
                "name": "String",
                "ofType": null
              },
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "inputFields": null,
          "interfaces": [],
          "enumValues": null,
          "possibleTypes": null
        },
        {
          "kind": "ENUM",
          "name": "__DirectiveLocation",
          "specifiedByURL": null,
          "fields": null,
          "inputFields": null,
          "interfaces": null,
          "enumValues": [
            {
              "name": "QUERY",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "MUTATION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "SUBSCRIPTION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "FIELD",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "FRAGMENT_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "FRAGMENT_SPREAD",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "INLINE_FRAGMENT",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "VARIABLE_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "FRAGMENT_VARIABLE_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "SCHEMA",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "SCALAR",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "OBJECT",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "FIELD_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "ARGUMENT_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "INTERFACE",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "UNION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "ENUM",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "ENUM_VALUE",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "INPUT_OBJECT",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "INPUT_FIELD_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            },
            {
              "name": "DIRECTIVE_DEFINITION",
              "isDeprecated": false,
              "deprecationReason": null
            }
          ],
          "possibleTypes": null
        }
      ],
      "directives": [
        {
          "name": "include",
          "isRepeatable": false,
          "locations": [
            "FIELD",
            "FRAGMENT_SPREAD",
            "INLINE_FRAGMENT"
          ],
          "args": [
            {
              "defaultValue": null,
              "name": "if",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            }
          ]
        },
        {
          "name": "skip",
          "isRepeatable": false,
          "locations": [
            "FIELD",
            "FRAGMENT_SPREAD",
            "INLINE_FRAGMENT"
          ],
          "args": [
            {
              "defaultValue": null,
              "name": "if",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "Boolean",
                  "ofType": null
                }
              }
            }
          ]
        },
        {
          "name": "deprecated",
          "isRepeatable": false,
          "locations": [
            "FIELD_DEFINITION",
            "ARGUMENT_DEFINITION",
            "INPUT_FIELD_DEFINITION",
            "ENUM_VALUE",
            "DIRECTIVE_DEFINITION"
          ],
          "args": [
            {
              "defaultValue": "\"No longer supported\"",
              "name": "reason",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ]
        },
        {
          "name": "specifiedBy",
          "isRepeatable": false,
          "locations": [
            "SCALAR"
          ],
          "args": [
            {
              "defaultValue": null,
              "name": "url",
              "type": {
                "kind": "NON_NULL",
                "name": null,
                "ofType": {
                  "kind": "SCALAR",
                  "name": "String",
                  "ofType": null
                }
              }
            }
          ]
        },
        {
          "name": "oneOf",
          "isRepeatable": false,
          "locations": [
            "INPUT_OBJECT"
          ],
          "args": []
        }
      ]
    }
  }
}
```

Create `packages/typed_graphql_conformance/test/execution/introspection_deprecation_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Fields {
  const _Fields();
}

enum _Value { nonDeprecated, deprecated, deprecatedWithEmptyReason, also }

// Ported from the deprecation tests of graphql-js
// src/type/__tests__/introspection-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. graphql-js builds its schemas from
// SDL; these are built with the typed builder and have the same members.
void main() {
  const port = ExecutionPort();

  ExecutableSchemaBuilder<Object?> builder() => ExecutableSchemaBuilder();

  ObjectTypeDef<Object?> queryOf(
    ExecutableSchemaBuilder<Object?> b,
    List<FieldDef<Object?, Object?>> Function(FieldsBuilder<Object?, Object?> t)
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  FieldStub<Object?, String?, Object?> stringField(
    FieldsBuilder<Object?, Object?> t,
    ExecutableSchemaBuilder<Object?> b,
    String name, {
    List<Arg<Object?>> args = const [],
  }) => t.field(name, b.string.nullable, args: args);

  FieldDef<Object?, Object?> resolved(
    FieldStub<Object?, String?, Object?> stub,
  ) => stub.resolve((_, a, c, i) => null);

  Future<Map<String, Object?>> introspect(
    ExecutableSchema<Object?> schema,
    String source,
  ) => port.respond(schema, source);

  ExecutableSchema<Object?> fieldSchema({required bool hasEmptyReason}) {
    final b = builder();
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(stringField(t, b, 'nonDeprecated')),
          resolved(
            stringField(t, b, 'deprecated').deprecated('Removed in 1.0'),
          ),
          if (hasEmptyReason)
            resolved(
              stringField(t, b, 'deprecatedWithEmptyReason').deprecated(''),
            ),
        ],
      ),
    );
  }

  ExecutableSchema<Object?> argumentSchema({required bool hasEmptyReason}) {
    final b = builder();
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(
            stringField(
              t,
              b,
              'someField',
              args: [
                Arg('nonDeprecated', b.string.nullable),
                Arg(
                  'deprecated',
                  b.string.nullable,
                  deprecationReason: 'Removed in 1.0',
                ),
                if (hasEmptyReason)
                  Arg(
                    'deprecatedWithEmptyReason',
                    b.string.nullable,
                    deprecationReason: '',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ExecutableSchema<Object?> enumSchema({required bool hasEmptyReason}) {
    final b = builder();
    final someEnum = b.enumType<_Value>(
      'SomeEnum',
      [
        for (final value in _Value.values)
          if (hasEmptyReason || value != _Value.deprecatedWithEmptyReason)
            value,
      ],
      mapping: EnumValueMapping<_Value>(
        nameOf: (value) => switch (value) {
          _Value.nonDeprecated => 'NON_DEPRECATED',
          _Value.deprecated => 'DEPRECATED',
          _Value.deprecatedWithEmptyReason => 'DEPRECATED_WITH_EMPTY_REASON',
          _Value.also => 'ALSO_NON_DEPRECATED',
        },
        deprecationReasonOf: (value) => switch (value) {
          _Value.deprecated => 'Removed in 1.0',
          _Value.deprecatedWithEmptyReason => '',
          _ => null,
        },
      ),
    );
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(
            stringField(
              t,
              b,
              'someField',
              args: [Arg('someArg', someEnum.nullable)],
            ),
          ),
        ],
      ),
    );
  }

  ExecutableSchema<Object?> inputSchema({required bool hasEmptyReason}) {
    final b = builder();
    final someInput = b.inputObject<_Fields>(
      'SomeInputObject',
      fields: () => [
        Arg('nonDeprecated', b.string.nullable),
        Arg(
          'deprecated',
          b.string.nullable,
          deprecationReason: 'Removed in 1.0',
        ),
        if (hasEmptyReason)
          Arg(
            'deprecatedWithEmptyReason',
            b.string.nullable,
            deprecationReason: '',
          ),
      ],
      decode: (values) => const _Fields(),
    );
    return b.build(
      query: queryOf(
        b,
        (t) => [
          resolved(
            stringField(
              t,
              b,
              'someField',
              args: [Arg('someArg', someInput.nullable)],
            ),
          ),
        ],
      ),
    );
  }

  group('Introspection', () {
    test('identifies deprecated fields', () async {
      const source = '''

      {
        __type(name: "Query") {
          fields(includeDeprecated: true) {
            name
            isDeprecated,
            deprecationReason
          }
        }
      }
    ''';

      expect(await introspect(fieldSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'fields': [
              {
                'name': 'nonDeprecated',
                'isDeprecated': false,
                'deprecationReason': null,
              },
              {
                'name': 'deprecated',
                'isDeprecated': true,
                'deprecationReason': 'Removed in 1.0',
              },
              {
                'name': 'deprecatedWithEmptyReason',
                'isDeprecated': true,
                'deprecationReason': '',
              },
            ],
          },
        },
      });
    });

    test('respects the includeDeprecated parameter for fields', () async {
      const source = '''

      {
        __type(name: "Query") {
          trueFields: fields(includeDeprecated: true) {
            name
          }
          falseFields: fields(includeDeprecated: false) {
            name
          }
          omittedFields: fields {
            name
          }
        }
      }
    ''';

      expect(await introspect(fieldSchema(hasEmptyReason: false), source), {
        'data': {
          '__type': {
            'trueFields': [
              {'name': 'nonDeprecated'},
              {'name': 'deprecated'},
            ],
            'falseFields': [
              {'name': 'nonDeprecated'},
            ],
            'omittedFields': [
              {'name': 'nonDeprecated'},
            ],
          },
        },
      });
    });

    test('identifies deprecated args', () async {
      const source = '''

      {
        __type(name: "Query") {
          fields {
            args(includeDeprecated: true) {
              name
              isDeprecated,
              deprecationReason
            }
          }
        }
      }
    ''';

      expect(await introspect(argumentSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'fields': [
              {
                'args': [
                  {
                    'name': 'nonDeprecated',
                    'isDeprecated': false,
                    'deprecationReason': null,
                  },
                  {
                    'name': 'deprecated',
                    'isDeprecated': true,
                    'deprecationReason': 'Removed in 1.0',
                  },
                  {
                    'name': 'deprecatedWithEmptyReason',
                    'isDeprecated': true,
                    'deprecationReason': '',
                  },
                ],
              },
            ],
          },
        },
      });
    });

    test('respects the includeDeprecated parameter for args', () async {
      const source = '''

      {
        __type(name: "Query") {
          fields {
            trueArgs: args(includeDeprecated: true) {
              name
            }
            falseArgs: args(includeDeprecated: false) {
              name
            }
            omittedArgs: args {
              name
            }
          }
        }
      }
    ''';

      expect(await introspect(argumentSchema(hasEmptyReason: false), source), {
        'data': {
          '__type': {
            'fields': [
              {
                'trueArgs': [
                  {'name': 'nonDeprecated'},
                  {'name': 'deprecated'},
                ],
                'falseArgs': [
                  {'name': 'nonDeprecated'},
                ],
                'omittedArgs': [
                  {'name': 'nonDeprecated'},
                ],
              },
            ],
          },
        },
      });
    });

    test('identifies deprecated enum values', () async {
      const source = '''

      {
        __type(name: "SomeEnum") {
          enumValues(includeDeprecated: true) {
            name
            isDeprecated,
            deprecationReason
          }
        }
      }
    ''';

      // The graphql-js enum has no value with an empty reason here.
      expect(await introspect(enumSchema(hasEmptyReason: false), source), {
        'data': {
          '__type': {
            'enumValues': [
              {
                'name': 'NON_DEPRECATED',
                'isDeprecated': false,
                'deprecationReason': null,
              },
              {
                'name': 'DEPRECATED',
                'isDeprecated': true,
                'deprecationReason': 'Removed in 1.0',
              },
              {
                'name': 'ALSO_NON_DEPRECATED',
                'isDeprecated': false,
                'deprecationReason': null,
              },
            ],
          },
        },
      });
    });

    test('respects the includeDeprecated parameter for enum values', () async {
      const source = '''

      {
        __type(name: "SomeEnum") {
          trueValues: enumValues(includeDeprecated: true) {
            name
          }
          falseValues: enumValues(includeDeprecated: false) {
            name
          }
          omittedValues: enumValues {
            name
          }
        }
      }
    ''';

      expect(await introspect(enumSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'trueValues': [
              {'name': 'NON_DEPRECATED'},
              {'name': 'DEPRECATED'},
              {'name': 'DEPRECATED_WITH_EMPTY_REASON'},
              {'name': 'ALSO_NON_DEPRECATED'},
            ],
            'falseValues': [
              {'name': 'NON_DEPRECATED'},
              {'name': 'ALSO_NON_DEPRECATED'},
            ],
            'omittedValues': [
              {'name': 'NON_DEPRECATED'},
              {'name': 'ALSO_NON_DEPRECATED'},
            ],
          },
        },
      });
    });

    test('identifies deprecated for input fields', () async {
      const source = '''

      {
        __type(name: "SomeInputObject") {
          inputFields(includeDeprecated: true) {
            name
            isDeprecated,
            deprecationReason
          }
        }
      }
    ''';

      expect(await introspect(inputSchema(hasEmptyReason: true), source), {
        'data': {
          '__type': {
            'inputFields': [
              {
                'name': 'nonDeprecated',
                'isDeprecated': false,
                'deprecationReason': null,
              },
              {
                'name': 'deprecated',
                'isDeprecated': true,
                'deprecationReason': 'Removed in 1.0',
              },
              {
                'name': 'deprecatedWithEmptyReason',
                'isDeprecated': true,
                'deprecationReason': '',
              },
            ],
          },
        },
      });
    });

    test(
      'respects the includeDeprecated parameter for input fields',
      () async {
        const source = '''

      {
        __type(name: "SomeInputObject") {
          trueFields: inputFields(includeDeprecated: true) {
            name
          }
          falseFields: inputFields(includeDeprecated: false) {
            name
          }
          omittedFields: inputFields {
            name
          }
        }
      }
    ''';

        expect(await introspect(inputSchema(hasEmptyReason: false), source), {
          'data': {
            '__type': {
              'trueFields': [
                {'name': 'nonDeprecated'},
                {'name': 'deprecated'},
              ],
              'falseFields': [
                {'name': 'nonDeprecated'},
              ],
              'omittedFields': [
                {'name': 'nonDeprecated'},
              ],
            },
          },
        });
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/introspection_one_of_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Fields {
  const _Fields();
}

enum _OnlyEnum { someObject }

// Ported from the oneOf tests of graphql-js
// src/type/__tests__/introspection-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. graphql-js builds its schemas from
// SDL; these are built with the typed builder and have the same types.
void main() {
  const port = ExecutionPort();

  ExecutableSchemaBuilder<Object?> builder() => ExecutableSchemaBuilder();

  ObjectTypeDef<Object?> queryOf(
    ExecutableSchemaBuilder<Object?> b,
    List<FieldDef<Object?, Object?>> Function(FieldsBuilder<Object?, Object?> t)
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  FieldDef<Object?, Object?> someField(
    FieldsBuilder<Object?, Object?> t,
    OutputRef<Object?> type, {
    List<Arg<Object?>> args = const [],
    String name = 'someField',
  }) => t.field(name, type, args: args).resolve((_, a, c, i) => null);

  Future<Map<String, Object?>> introspect(
    ExecutableSchema<Object?> schema,
    String source,
  ) => port.respond(schema, source);

  group('Introspection', () {
    test('identifies oneOf for input objects', () async {
      final b = builder();
      final someInput = b.oneOfInputObject<_Fields>(
        'SomeInputObject',
        fields: () => [Arg('a', b.string.nullable)],
        decode: (values) => const _Fields(),
      );
      final anotherInput = b.inputObject<_Fields>(
        'AnotherInputObject',
        fields: () => [
          Arg('a', b.string.nullable),
          Arg('b', b.string.nullable),
        ],
        decode: (values) => const _Fields(),
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              b.string.nullable,
              args: [Arg('someArg', someInput.nullable)],
            ),
            someField(
              t,
              b.string.nullable,
              args: [Arg('anotherArg', anotherInput.nullable)],
              name: 'anotherField',
            ),
          ],
        ),
      );

      const source = '''

      {
        oneOfInputObject: __type(name: "SomeInputObject") {
          isOneOf
        }
        inputObject: __type(name: "AnotherInputObject") {
          isOneOf
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          'oneOfInputObject': {'isOneOf': true},
          'inputObject': {'isOneOf': false},
        },
      });
    });

    test('returns null for oneOf for other types', () async {
      final b = builder();
      final someEnum = b.enumType<_OnlyEnum>(
        'SomeEnum',
        _OnlyEnum.values,
        mapping: EnumValueMapping<_OnlyEnum>(nameOf: (value) => 'SomeObject'),
      );
      final someInterface = b.interface<Object?>(
        'SomeInterface',
        fields: (t) => [t.field('fieldA', b.string.nullable).declareOnly()],
      );
      final someObject = b.object<Object?>(
        'SomeObject',
        interfaces: [someInterface],
        fields: (t) => [someField(t, b.string.nullable, name: 'fieldA')],
      );
      final someUnion = b.union<Object?>(
        'SomeUnion',
        members: [someObject],
        resolveType: (value) => someObject,
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              someUnion.nullable,
              args: [Arg('enum', someEnum.nullable)],
            ),
            someField(
              t,
              someInterface.nullable,
              args: [Arg('enum', someEnum.nullable)],
              name: 'anotherField',
            ),
          ],
        ),
      );

      const source = '''

      {
        object: __type(name: "SomeObject") {
          isOneOf
        }
        enum: __type(name: "SomeEnum") {
          isOneOf
        }
        interface: __type(name: "SomeInterface") {
          isOneOf
        }
        scalar: __type(name: "String") {
          isOneOf
        }
        union: __type(name: "SomeUnion") {
          isOneOf
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          'object': {'isOneOf': null},
          'enum': {'isOneOf': null},
          'interface': {'isOneOf': null},
          'scalar': {'isOneOf': null},
          'union': {'isOneOf': null},
        },
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/introspection_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/introspection_fixture.dart';

final class _Fields {
  const _Fields(this.values);

  final Map<String, Object?> values;
}

final class _Complex {
  const _Complex(this.x, this.y);

  final List<String> x;
  final int y;
}

enum _SomeEnum { value }

// Ported from graphql-js src/type/__tests__/introspection-test.ts (the
// deprecation tests are in introspection_deprecation_test.dart);
// mapping/execution.csv says which tests are adapted or skipped, and why.
// graphql-js builds its schemas from SDL; these are built with the typed
// builder and have the same types, fields, defaults and descriptions.
void main() {
  const port = ExecutionPort();

  ExecutableSchemaBuilder<Object?> builder() => ExecutableSchemaBuilder();

  ObjectTypeDef<Object?> queryOf(
    ExecutableSchemaBuilder<Object?> b,
    List<FieldDef<Object?, Object?>> Function(FieldsBuilder<Object?, Object?> t)
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  FieldDef<Object?, Object?> someField(
    FieldsBuilder<Object?, Object?> t,
    OutputRef<Object?> type, {
    List<Arg<Object?>> args = const [],
    String name = 'someField',
  }) => t.field(name, type, args: args).resolve((_, a, c, i) => null);

  Future<Map<String, Object?>> introspect(
    ExecutableSchema<Object?> schema,
    String source,
  ) => port.respond(schema, source);

  group('Introspection', () {
    test('executes an introspection query', () async {
      final b = builder();
      final someObject = b.object<Object?>(
        'SomeObject',
        fields: (t) => [someField(t, b.string.nullable)],
      );
      final schema = b.build(query: someObject);

      final source = const IntrospectionQuery(
        includesDescriptions: false,
        includesSpecifiedByUrl: true,
        includesDirectiveIsRepeatable: true,
      ).text;

      final expected = const IntrospectionFixture().expected();
      expect(await introspect(schema, source), expected);
    });

    test('introspects on input object', () async {
      final b = builder();
      final someInput = b.inputObject<_Fields>(
        'SomeInputObject',
        fields: () => [
          Arg('a', b.string.nullable, defaultValue: 'tes\t de\fault'),
          Arg('b', b.inputList(b.string.nullable).nullable),
          Arg('c', b.string.nullable),
        ],
        decode: (values) => const _Fields({}),
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              b.string.nullable,
              args: [Arg('someArg', someInput.nullable)],
            ),
          ],
        ),
      );

      const source = '''

      {
        __type(name: "SomeInputObject") {
          kind
          name
          inputFields {
            name
            type { ...TypeRef }
            defaultValue
          }
        }
      }

      fragment TypeRef on __Type {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
            }
          }
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          '__type': {
            'kind': 'INPUT_OBJECT',
            'name': 'SomeInputObject',
            'inputFields': [
              {
                'name': 'a',
                'type': {'kind': 'SCALAR', 'name': 'String', 'ofType': null},
                'defaultValue': r'"tes\t de\fault"',
              },
              {
                'name': 'b',
                'type': {
                  'kind': 'LIST',
                  'name': null,
                  'ofType': {
                    'kind': 'SCALAR',
                    'name': 'String',
                    'ofType': null,
                  },
                },
                'defaultValue': null,
              },
              {
                'name': 'c',
                'type': {'kind': 'SCALAR', 'name': 'String', 'ofType': null},
                'defaultValue': null,
              },
            ],
          },
        },
      });
    });

    test('introspects any default value', () async {
      final b = builder();
      final complex = b.inputObject<_Complex>(
        'Complex',
        fields: () => [
          Arg('x', b.inputList(b.string.nullable).nullable),
          Arg('y', b.int.nullable),
        ],
        decode: (values) => const _Complex([], 0),
        encode: (value) => JsonObject({
          'x': JsonArray([for (final item in value.x) JsonString(item)]),
          'y': JsonNumber(value.y),
        }),
      );
      final withDefaults = b.inputObject<_Fields>(
        'InputObjectWithDefaultValues',
        fields: () => [
          Arg('a', b.string.nullable, defaultValue: 'Emoji: \u{1F600}'),
          Arg(
            'b',
            complex.nullable,
            defaultValue: const _Complex(['abc'], 123),
          ),
        ],
        decode: (values) => const _Fields({}),
      );
      final schema = b.build(
        query: queryOf(
          b,
          (t) => [
            someField(
              t,
              b.string.nullable,
              args: [Arg('someArg', withDefaults.nullable)],
            ),
          ],
        ),
      );

      const source = '''

      {
        __type(name: "InputObjectWithDefaultValues") {
          inputFields {
            name
            defaultValue
          }
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          '__type': {
            'inputFields': [
              {'name': 'a', 'defaultValue': '"Emoji: \u{1F600}"'},
              {'name': 'b', 'defaultValue': '{ x: ["abc"], y: 123 }'},
            ],
          },
        },
      });
    });

    test('supports the __type root field', () async {
      final b = builder();
      final schema = b.build(
        query: queryOf(b, (t) => [someField(t, b.string.nullable)]),
      );

      const source = '''

      {
        __type(name: "Query") {
          name
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          '__type': {'name': 'Query'},
        },
      });
    });

    test('fails as expected on the __type root field without an arg', () async {
      final b = builder();
      final schema = b.build(
        query: queryOf(b, (t) => [someField(t, b.string.nullable)]),
      );

      const source = '''

      {
        __type {
          name
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'errors': [
          {
            'message': 'Argument "<meta>.__type(name:)" of type "String!" is required, but it was not provided.',
            'locations': [
              {'line': 3, 'column': 9},
            ],
          },
        ],
      });
    });

    test('exposes descriptions', () async {
      final b = builder();
      final someEnum = b.enumType<_SomeEnum>(
        'SomeEnum',
        _SomeEnum.values,
        description: 'Enum description',
        mapping: EnumValueMapping<_SomeEnum>(
          nameOf: (value) => 'VALUE',
          descriptionOf: (value) => 'Value description',
        ),
      );
      final someObject = b.object<Object?>(
        'SomeObject',
        description: 'Object description',
        fields: (t) => [
          t
              .field(
                'someField',
                b.string.nullable,
                args: [Arg('arg', someEnum.nullable)],
                description: 'Field description',
              )
              .resolve((_, a, c, i) => null),
        ],
      );
      final schema = b.build(
        query: someObject,
        options: const BuildOptions(description: 'Schema description'),
      );

      const source = '''

      {
        Schema: __schema { description }
        SomeObject: __type(name: "SomeObject") {
          description,
          fields {
            name
            description
          }
        }
        SomeEnum: __type(name: "SomeEnum") {
          description
          enumValues {
            name
            description
          }
        }
      }
    ''';

      expect(await introspect(schema, source), {
        'data': {
          'Schema': {'description': 'Schema description'},
          'SomeEnum': {
            'description': 'Enum description',
            'enumValues': [
              {'name': 'VALUE', 'description': 'Value description'},
            ],
          },
          'SomeObject': {
            'description': 'Object description',
            'fields': [
              {'name': 'someField', 'description': 'Field description'},
            ],
          },
        },
      });
    });

    test(
      'executes an introspection query without calling global resolvers',
      () async {
        final b = ExecutableSchemaBuilder<Object?>();
        final calls = <String>[];
        final schema = b.build(
          query: queryOf(b, (t) => [someField(t, b.string.nullable)]),
          options: BuildOptions<Object?>(
            middleware: [
              (next, site) => (parent, args, context, info) {
                calls.add('${info.parentTypeName}::${info.fieldName}');
                return next(parent, args, context, info);
              },
            ],
          ),
        );

        final source = const IntrospectionQuery(
          includesSpecifiedByUrl: true,
          includesDirectiveIsRepeatable: true,
          includesSchemaDescription: true,
        ).text;

        expect(await introspect(schema, source), isNot(contains('errors')));
        expect(calls, isEmpty);
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/subscribe_initialization_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from the "Subscription Initialization Phase" tests of graphql-js
// src/execution/__tests__/subscribe-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. The source of a subscription field
// is declared on the field (graphql-js reads it from the root value or from
// `subscribe`), and `subscribe` answers a rejected request with a value
// where graphql-js throws.
void main() {
  const port = ExecutionPort();

  ExecutableSchema<Object?> schemaOf(
    List<FieldDef<Object?, Object?>> Function(
      ExecutableSchemaBuilder<Object?> b,
      FieldsBuilder<Object?, Object?> t,
    )
    fields,
  ) {
    final b = ExecutableSchemaBuilder<Object?>();
    return b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [t.field('dummy', b.string.nullable).pure((_) => null)],
      ),
      subscription: b.object<Object?>(
        'Subscription',
        fields: (t) => fields(b, t),
      ),
    );
  }

  Future<SubscriptionResult> start(
    ExecutableSchema<Object?> schema,
    String text, {
    Object? rootValue,
    JsonObject? variables,
  }) async => port.subscribe<Object?>(
    schema,
    text,
    context: null,
    variables: variables,
    options: ExecutionOptions(rootValue: rootValue, maskErrors: false),
  );

  Future<List<Map<String, Object?>>> resultsOf(SubscriptionResult started) =>
      switch (started) {
        SubscriptionStarted(:final results) =>
          results.map(port.withoutCodes).toList(),
        SubscriptionRejected(:final error) => throw StateError('$error'),
      };

  Map<String, Object?> rejection(SubscriptionResult started) =>
      switch (started) {
        SubscriptionRejected(:final error) => port.withoutCodes(error),
        SubscriptionStarted() => throw StateError('started'),
      };

  Stream<Map<String, Object?>> fooValue() =>
      Stream.value(<String, Object?>{'foo': 'FooValue'});

  final fooSchema = schemaOf(
    (b, t) => [
      t
          .field('foo', b.string.nullable)
          .subscribeWith<Map<String, Object?>>(
            (parent, args, context, info) => fooValue(),
            (event, args, context, info) => event['foo'] as String?,
          ),
    ],
  );
  const fooResults = [
    {
      'data': {'foo': 'FooValue'},
    },
  ];

  group('Subscription Initialization Phase', () {
    test(
      'throws when subscribe is called with a non-subscription operation',
      () async {
        final started = await start(fooSchema, '{ dummy }');
        expect(rejection(started), {
          'errors': [
            {'message': 'Expected subscription operation.'},
          ],
        });
      },
    );

    test('accepts multiple subscription fields defined in schema', () async {
      final schema = schemaOf(
        (b, t) => [
          for (final name in ['foo', 'bar'])
            t
                .field(name, b.string.nullable)
                .subscribeWith<Map<String, Object?>>(
                  (parent, args, context, info) => fooValue(),
                  (event, args, context, info) => event['foo'] as String?,
                ),
        ],
      );

      final started = await start(schema, 'subscription { foo }');

      expect(await resultsOf(started), fooResults);
    });

    test('accepts type definition with sync subscribe function', () async {
      final started = port.subscribe<Object?>(
        fooSchema,
        'subscription { foo }',
        context: null,
      );

      expect(started, isNot(isA<Future<Object?>>()));
      expect(await resultsOf(await started), fooResults);
    });

    test('accepts type definition with async subscribe function', () async {
      final schema = schemaOf(
        (b, t) => [
          t.field('foo', b.string.nullable).subscribeWith<Map<String, Object?>>(
            (parent, args, context, info) async {
              await Future<void>.delayed(Duration.zero);
              return fooValue();
            },
            (event, args, context, info) => event['foo'] as String?,
          ),
        ],
      );

      final promise = port.subscribe<Object?>(
        schema,
        'subscription { foo }',
        context: null,
      );

      expect(promise, isA<Future<Object?>>());
      expect(await resultsOf(await promise), fooResults);
    });

    test(
      'should only resolve the first field of invalid multi-field',
      () async {
        var fooCalls = 0;
        var barCalls = 0;
        final schema = schemaOf(
          (b, t) => [
            t
                .field('foo', b.string.nullable)
                .subscribeWith<Map<String, Object?>>(
                  (parent, args, context, info) {
                    fooCalls++;
                    return fooValue();
                  },
                  (event, args, context, info) => event['foo'] as String?,
                ),
            t
                .field('bar', b.string.nullable)
                .subscribeWith<Map<String, Object?>>(
                  (parent, args, context, info) {
                    barCalls++;
                    return const Stream.empty();
                  },
                  (event, args, context, info) => null,
                ),
          ],
        );

        final started = await start(schema, 'subscription { foo bar }');

        expect(fooCalls, 1);
        expect(barCalls, 0);
        final results = await resultsOf(started);
        expect(results, hasLength(1));
        expect(results.single['data'], containsPair('foo', 'FooValue'));
      },
    );

    test(
      'resolves to an error if schema does not support subscriptions',
      () async {
        final b = ExecutableSchemaBuilder<Object?>();
        final schema = b.build(
          query: b.object<Object?>(
            'Query',
            fields: (t) => [
              t.field('dummy', b.string.nullable).pure((_) => null),
            ],
          ),
        );

        final started = await start(schema, 'subscription { unknownField }');

        expect(rejection(started), {
          'errors': [
            {
              'message':
                  'Schema is not configured to execute subscription operation.',
            },
          ],
        });
      },
    );

    test('resolves to an error for unknown subscription field', () async {
      final started = await start(fooSchema, 'subscription { unknownField }');

      expect(rejection(started), {
        'errors': [
          {
            'message': 'The subscription selects no root field.',
          },
        ],
      });
    });

    test('resolves to an error for subscription resolver errors', () async {
      final expected = {
        'errors': [
          {
            'message': 'test error',
            'locations': [
              {'line': 1, 'column': 16},
            ],
            'path': ['foo'],
          },
        ],
      };
      ExecutableSchema<Object?> failing(
        FutureOr<Stream<String>> Function() source,
      ) => schemaOf(
        (b, t) => [
          t
              .field('foo', b.string.nullable)
              .subscribe((parent, args, context, info) => source()),
        ],
      );

      // Throwing an error
      expect(
        rejection(
          await start(
            failing(() => throw const GraphQLException('test error')),
            'subscription { foo }',
          ),
        ),
        expected,
      );
      // Rejecting with an error
      expect(
        rejection(
          await start(
            failing(
              () => Future<Stream<String>>.error(
                const GraphQLException('test error'),
              ),
            ),
            'subscription { foo }',
          ),
        ),
        expected,
      );
    });

    test('resolves to an error if variables were wrong type', () async {
      final schema = schemaOf(
        (b, t) => [
          t
              .field(
                'foo',
                b.string.nullable,
                args: [Arg('arg', b.int.nullable)],
              )
              .subscribe((parent, args, context, info) => Stream.value('x')),
        ],
      );

      // If we receive variables that cannot be coerced correctly, subscribe()
      // will resolve to an ExecutionResult that contains an informative error
      // description.
      final started = await start(
        schema,
        r'''

      subscription ($arg: Int) {
        foo(arg: $arg)
      }
    ''',
        variables: port.variablesOf({'arg': 'meow'}),
      );

      expect(rejection(started), {
        'errors': [
          {
            'message': r'Variable "$arg" has invalid value: Int cannot represent non-integer value: "meow"',
            'locations': [
              {'line': 2, 'column': 21},
            ],
          },
        ],
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/subscribe_publish_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/email_subscription.dart';
import '../support/execution_port.dart';
import '../support/simple_pub_sub.dart';

// Ported from the "Subscription Publish Phase" tests of graphql-js
// src/execution/__tests__/subscribe-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. `subscription.next()` is
// `StreamIterator.moveNext` and `subscription.return()` is
// `StreamIterator.cancel`.
void main() {
  const port = ExecutionPort();
  final emails = EmailSubscription();

  const alright = Email(
    from: 'yuzhi@graphql.org',
    subject: 'Alright',
    message: 'Tests are good',
    unread: true,
  );
  Map<String, Object?> payloadOf(
    String from,
    String subject, {
    required int unread,
    required int total,
    Map<String, Object?> email = const {},
  }) => {
    'data': {
      'importantEmail': {
        'email': {'from': from, 'subject': subject, ...email},
        'inbox': {'unread': unread, 'total': total},
      },
    },
  };

  Future<StreamIterator<Map<String, Object?>>> open(
    SimplePubSub<Email> pubsub, {
    Map<String, Object?>? variables,
  }) async => StreamIterator(await emails.open(pubsub, variables: variables));

  group('Subscription Publish Phase', () {
    test(
      'produces a payload for multiple subscribe in same subscription',
      () async {
        final pubsub = SimplePubSub<Email>();
        final subscription = await open(pubsub);
        final secondSubscription = await open(pubsub);

        final payload1 = subscription.moveNext();
        final payload2 = secondSubscription.moveNext();

        expect(pubsub.emit(alright), isTrue);

        final expectedPayload = payloadOf(
          'yuzhi@graphql.org',
          'Alright',
          unread: 1,
          total: 2,
        );
        expect(await payload1, isTrue);
        expect(subscription.current, expectedPayload);
        expect(await payload2, isTrue);
        expect(secondSubscription.current, expectedPayload);
        await subscription.cancel();
        await secondSubscription.cancel();
      },
    );

    test('produces a payload when queried fields are async', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(
        pubsub,
        variables: {'asyncResolver': true},
      );

      expect(pubsub.emit(alright), isTrue);

      expect(await subscription.moveNext(), isTrue);
      expect(
        subscription.current,
        payloadOf(
          'yuzhi@graphql.org',
          'Alright',
          unread: 1,
          total: 2,
          email: {'asyncSubject': 'Alright'},
        ),
      );
      await subscription.cancel();
    });

    test('produces a payload per subscription event', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      // Wait for the next subscription payload.
      final payload = subscription.moveNext();

      // A new email arrives!
      expect(pubsub.emit(alright), isTrue);

      // The previously waited on payload now has a value.
      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright', unread: 1, total: 2),
      );

      // Another new email arrives, before subscription.next() is called.
      expect(
        pubsub.emit(
          const Email(
            from: 'hyo@graphql.org',
            subject: 'Tools',
            message: 'I <3 making things',
            unread: true,
          ),
        ),
        isTrue,
      );

      // The next waited on payload will have a value.
      expect(await subscription.moveNext(), isTrue);
      expect(
        subscription.current,
        payloadOf('hyo@graphql.org', 'Tools', unread: 2, total: 3),
      );

      // The client decides to disconnect.
      await subscription.cancel();

      // Which may result in disconnecting upstream services as well.
      expect(
        pubsub.emit(
          const Email(
            from: 'adam@graphql.org',
            subject: 'Important',
            message: 'Read me please',
            unread: true,
          ),
        ),
        isFalse,
      ); // No more listeners.

      // Awaiting a subscription after closing it results in completed results.
      expect(await subscription.moveNext(), isFalse);
    });

    test('produces a payload when there are multiple events', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      var payload = subscription.moveNext();

      // A new email arrives!
      expect(pubsub.emit(alright), isTrue);

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright', unread: 1, total: 2),
      );

      payload = subscription.moveNext();

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Alright 2',
            message: 'Tests are good 2',
            unread: true,
          ),
        ),
        isTrue,
      );

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright 2', unread: 2, total: 3),
      );
      await subscription.cancel();
    });

    test('should not trigger when subscription is already done', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      var payload = subscription.moveNext();

      // A new email arrives!
      expect(pubsub.emit(alright), isTrue);

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Alright', unread: 1, total: 2),
      );

      payload = subscription.moveNext();
      await subscription.cancel();

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Alright 2',
            message: 'Tests are good 2',
            unread: true,
          ),
        ),
        isFalse,
      );

      expect(await payload, isFalse);
    });

    test('event order is correct for multiple publishes', () async {
      final pubsub = SimplePubSub<Email>();
      final subscription = await open(pubsub);

      var payload = subscription.moveNext();

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Message',
            message: 'Tests are good',
            unread: true,
          ),
        ),
        isTrue,
      );

      // A new email arrives!
      expect(
        pubsub.emit(
          const Email(
            from: 'yuzhi@graphql.org',
            subject: 'Message 2',
            message: 'Tests are good 2',
            unread: true,
          ),
        ),
        isTrue,
      );

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Message', unread: 2, total: 3),
      );

      payload = subscription.moveNext();

      expect(await payload, isTrue);
      expect(
        subscription.current,
        payloadOf('yuzhi@graphql.org', 'Message 2', unread: 2, total: 3),
      );
      await subscription.cancel();
    });

    group('with a field of its own', () {
      Future<List<Map<String, Object?>>> run(
        Stream<String> Function() source,
        String? Function(String message) resolve,
      ) async {
        final b = ExecutableSchemaBuilder<Object?>();
        final schema = b.build(
          query: b.object<Object?>(
            'Query',
            fields: (t) => [
              t.field('dummy', b.string.nullable).pure((_) => null),
            ],
          ),
          subscription: b.object<Object?>(
            'Subscription',
            fields: (t) => [
              t
                  .field('newMessage', b.string.nullable)
                  .subscribeWith<String>(
                    (parent, args, context, info) => source(),
                    (message, args, context, info) => resolve(message),
                  ),
            ],
          ),
        );
        final started = await port.subscribe<Object?>(
          schema,
          'subscription { newMessage }',
          context: null,
        );
        return switch (started) {
          SubscriptionStarted(:final results) =>
            results.map(port.withoutCodes).toList(),
          SubscriptionRejected() => throw StateError('rejected'),
        };
      }

      test('should handle error during execution of source event', () async {
        final results = await run(
          () => Stream.fromIterable(['Hello', 'Goodbye', 'Bonjour']),
          (message) {
            if (message == 'Goodbye') {
              throw const GraphQLException('Never leave.');
            }
            return message;
          },
        );

        expect(results, [
          // An error in execution is presented as such, and does not close the
          // response event stream: subsequent events are still executed.
          {
            'data': {'newMessage': 'Hello'},
          },
          {
            'data': {'newMessage': null},
            'errors': [
              {
                'message': 'Never leave.',
                'locations': [
                  {'line': 1, 'column': 16},
                ],
                'path': ['newMessage'],
              },
            ],
          },
          {
            'data': {'newMessage': 'Bonjour'},
          },
        ]);
      });

      test('should pass through error thrown in source event stream', () async {
        final results = await run(() async* {
          yield 'Hello';
          throw const GraphQLException('test error');
        }, (message) => message);

        expect(results, [
          {
            'data': {'newMessage': 'Hello'},
          },
          {
            'data': null,
            'errors': [
              {'message': 'test error'},
            ],
          },
        ]);
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/support/email_subscription.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_port.dart';
import 'simple_pub_sub.dart';

/// An email of graphql-js's subscribe-test.
final class Email {
  /// Creates an email.
  const Email({
    required this.from,
    required this.subject,
    required this.message,
    required this.unread,
  });

  /// The sender.
  final String from;

  /// The subject.
  final String subject;

  /// The body.
  final String message;

  /// Whether it was not read yet.
  final bool unread;
}

/// The emails of one subscription, which the source appends to.
final class EmailInbox {
  /// Creates an inbox holding [emails].
  EmailInbox(this.emails);

  /// Every email so far.
  final List<Email> emails;
}

/// What the `importantEmail` field holds for one event.
final class EmailEvent {
  /// Creates the event of [email] in [inbox].
  const EmailEvent(this.email, this.inbox);

  /// The new email.
  final Email email;

  /// The inbox it arrived in.
  final EmailInbox inbox;
}

/// The root value of a subscription: where its events come from.
final class EmailSource {
  /// Creates a source on [pubsub].
  EmailSource(this.pubsub)
    : emails = [
        const Email(
          from: 'joe@graphql.org',
          subject: 'Hello',
          message: 'Hello World',
          unread: false,
        ),
      ];

  /// Where the new emails are published.
  final SimplePubSub<Email> pubsub;

  /// The inbox's emails, starting with one.
  final List<Email> emails;
}

/// graphql-js's `emailSchema` and `createSubscription` of
/// `execution/__tests__/subscribe-test.ts`.
///
/// Spec 18.10 of M5: the source of `importantEmail` is declared on the field
/// (graphql-js reads it from the root value) and each event is the field's
/// value, so the source builds the `EmailEvent` that graphql-js's mapping
/// function wraps in `{ importantEmail: ... }`.
final class EmailSubscription {
  /// Builds the schema.
  EmailSubscription() {
    final b = ExecutableSchemaBuilder<Object?>();
    final email = b.object<Email>(
      'Email',
      fields: (t) => [
        t.field('from', b.string.nullable).pure((e) => e.from),
        t.field('subject', b.string.nullable).pure((e) => e.subject),
        t
            .field('asyncSubject', b.string.nullable)
            .resolve((e, args, context, info) => Future.value(e.subject)),
        t.field('message', b.string.nullable).pure((e) => e.message),
        t.field('unread', b.boolean.nullable).pure((e) => e.unread),
      ],
    );
    final inbox = b.object<EmailInbox>(
      'Inbox',
      fields: (t) => [
        t.field('total', b.int.nullable).pure((i) => i.emails.length),
        t
            .field('unread', b.int.nullable)
            .pure((i) => i.emails.where((e) => e.unread).length),
        t
            .field('emails', b.list(email.nullable).nullable)
            .pure((i) => i.emails),
      ],
    );
    final event = b.object<EmailEvent>(
      'EmailEvent',
      fields: (t) => [
        t.field('email', email.nullable).pure((e) => e.email),
        t.field('inbox', inbox.nullable).pure((e) => e.inbox),
      ],
    );
    final priority = Arg('priority', b.int.nullable);
    schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('inbox', inbox.nullable).pure((_) => EmailInbox(const [])),
        ],
      ),
      subscription: b.object<EmailSource>(
        'Subscription',
        fields: (t) => [
          t.field('importantEmail', event.nullable, args: [priority]).subscribe(
            (source, args, context, info) {
              final inbox = EmailInbox(source.emails);
              return source.pubsub.getSubscriber(
                (newEmail) {
                  source.emails.add(newEmail);
                  return EmailEvent(newEmail, inbox);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  /// The email schema.
  late final ExecutableSchema<Object?> schema;

  /// The subscription document of `createSubscription`; it starts with the
  /// blank line of the JavaScript template, so locations match.
  static const String document = r'''

    subscription (
      $priority: Int = 0
      $shouldDefer: Boolean = false
      $shouldStream: Boolean = false
      $asyncResolver: Boolean = false
    ) {
      importantEmail(priority: $priority) {
        email {
          from
          subject
          ... @include(if: $asyncResolver) {
            asyncSubject
          }
        }
        ... @defer(if: $shouldDefer) {
          inbox {
            emails @include(if: $shouldStream) @stream(if: $shouldStream)
            unread
            total
          }
        }
      }
    }
  ''';

  /// Starts the subscription on [pubsub] with [variables], and returns its
  /// responses as JSON (codes dropped).
  Future<Stream<Map<String, Object?>>> open(
    SimplePubSub<Email> pubsub, {
    Map<String, Object?>? variables,
  }) async {
    const port = ExecutionPort();
    final started = await port.subscribe<Object?>(
      schema,
      document,
      context: null,
      variables: variables == null ? null : port.variablesOf(variables),
      options: ExecutionOptions(
        rootValue: EmailSource(pubsub),
        maskErrors: false,
      ),
    );
    return switch (started) {
      SubscriptionStarted(:final results) => results.map(port.withoutCodes),
      SubscriptionRejected(:final error) => throw StateError('$error'),
    };
  }
}
```

Create `packages/typed_graphql_conformance/test/support/introspection_fixture.dart`:

```dart
import 'dart:convert';
import 'dart:io';

/// The result graphql-js's introspection-test expects of the introspection
/// query, adapted to this edition of the specification.
///
/// graphql-js 17 also has the working-draft parts of the spec (directive
/// deprecation, fragment variables); this edition's introspection types have
/// none of them, so they are dropped from the expectation.
final class IntrospectionFixture {
  /// Creates the reader.
  const IntrospectionFixture();

  static const Set<String> _draftMembers = {
    'isDeprecated',
    'deprecationReason',
    'FRAGMENT_VARIABLE_DEFINITION',
    'DIRECTIVE_DEFINITION',
  };

  /// The expected response.
  Map<String, Object?> expected() {
    final expected = jsonDecode(
      File(
        'test/execution/fixtures/introspection_query_result.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final data = expected['data'] as Map<String, Object?>;
    final schema = data['__schema'] as Map<String, Object?>;
    for (final type in _maps(schema['types'])) {
      _dropDraftParts(type);
    }
    for (final directive in _maps(schema['directives'])) {
      if (directive['name'] == 'deprecated') {
        (directive['locations'] as List<Object?>).remove(
          'DIRECTIVE_DEFINITION',
        );
      }
    }
    return expected;
  }

  List<Map<String, Object?>> _maps(Object? list) =>
      (list as List<Object?>).cast<Map<String, Object?>>();

  void _dropDraftParts(Map<String, Object?> type) {
    switch (type['name']) {
      case '__Schema':
        for (final field in _maps(type['fields'])) {
          if (field['name'] == 'directives') {
            field['args'] = <Object?>[];
          }
        }
      case '__Directive':
        _maps(type['fields']).removeWhere(_isDraft);
      case '__DirectiveLocation':
        _maps(type['enumValues']).removeWhere(_isDraft);
    }
  }

  bool _isDraft(Map<String, Object?> member) =>
      _draftMembers.contains(member['name']);
}
```

Create `packages/typed_graphql_conformance/test/support/simple_pub_sub.dart`:

```dart
import 'dart:async';

/// graphql-js's `SimplePubSub`: a mock of a pub/sub system whose subscribers
/// are streams.
///
/// A subscriber exists from the call of [getSubscriber] until its stream is
/// cancelled, whether or not anybody listens yet: events emitted before the
/// first listener are kept for it, as graphql-js's push queue keeps them.
/// `transform` runs at [emit], not at delivery.
final class SimplePubSub<T> {
  /// Creates a pub/sub without subscribers.
  SimplePubSub();

  final Set<void Function(T event)> _subscribers = {};

  /// Hands [event] to every subscriber; whether there was one.
  bool emit(T event) {
    for (final subscriber in _subscribers.toList()) {
      subscriber(event);
    }
    return _subscribers.isNotEmpty;
  }

  /// A single-subscription stream of the events emitted from now on, each
  /// passed through [transform]; cancelling it ends the subscription.
  Stream<R> getSubscriber<R>(R Function(T event) transform) {
    // late: assigned right below, before any event can reach [push].
    late final StreamController<R> controller;
    void push(T event) => controller.add(transform(event));
    controller = StreamController<R>(
      onCancel: () {
        _subscribers.remove(push);
        return controller.close();
      },
    );
    _subscribers.add(push);
    return controller.stream;
  }
}
```

In `packages/typed_graphql_conformance/test/execution/enum_type_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,7 @@
+import 'dart:async';
+
 import 'package:test/test.dart';
+import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
 import '../support/execution_port.dart';
@@ -49,6 +52,17 @@ void main() {
   final thunkFromEnum = Arg('fromEnum', thunkValues.nullable);
   final colorArg = Arg('color', color.nullable);
   final schema = b.build(
+    subscription: b.object<Object?>(
+      'Subscription',
+      fields: (t) => [
+        t
+            .field('subscribeToEnum', color.nullable, args: [colorArg])
+            .subscribeWith<Object?>(
+              (parent, args, context, info) => const Stream.empty(),
+              (event, args, context, info) => args.get(colorArg),
+            ),
+      ],
+    ),
     query: b.object<Object?>(
       'Query',
       fields: (t) => [
@@ -229,6 +243,21 @@ void main() {
       );
     });
 
+    test(
+      'accepts enum literals as input arguments to subscriptions',
+      () async {
+        expect(
+          await respond(
+            r'subscription ($color: Color!) { subscribeToEnum(color: $color) }',
+            variables: {'color': 'GREEN'},
+          ),
+          {
+            'data': {'subscribeToEnum': 'GREEN'},
+          },
+        );
+      },
+    );
+
     test('does not accept internal value as enum variable', () async {
       expect(
         await respond(
@@ -352,5 +381,12 @@ void main() {
         'data': {'thunkValuesString': 'b'},
       });
     });
+
+    test('can be introspected without error', () {
+      expect(
+        () => schema.schema.schema.toIntrospection(IntrospectionQuery.full),
+        returnsNormally,
+      );
+    });
   });
 }
```

In `packages/typed_graphql_conformance/test/execution/union_interface_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -51,6 +51,10 @@ void main() {
   late final ObjectTypeDef<_Dog> dog;
   late final ObjectTypeDef<_Cat> cat;
   late final ObjectTypeDef<_Person> person;
+  // late: the person's fields are a thunk that reads them after they are set,
+  // and the types are created in graphql-js's order (Person before Plant).
+  late final UnionTypeDef<Object?> pet;
+  late final UnionTypeDef<Object?> petOrPlant;
   final named = b.interface<Object?>(
     'Named',
     fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
@@ -94,21 +98,6 @@ void main() {
       t.field('father', cat.nullable).pure((c) => c.father),
     ],
   );
-  final plant = b.object<_Plant>(
-    'Plant',
-    interfaces: [named],
-    options: ObjectOptions(isTypeOf: (value) => value is _Plant),
-    fields: (t) => [t.field('name', b.string.nullable).pure((p) => p.name)],
-  );
-  final pet = b.union<Object?>(
-    'Pet',
-    members: [dog, cat],
-    resolveType: (value) => value is _Dog ? dog : cat,
-  );
-  final petOrPlant = b.union<Object?>(
-    'PetOrPlantType',
-    members: [plant, dog, cat],
-  );
   person = b.object<_Person>(
     'Person',
     interfaces: [named, mammal, life],
@@ -129,6 +118,21 @@ void main() {
       t.field('father', person.nullable).pure((p) => p.father),
     ],
   );
+  final plant = b.object<_Plant>(
+    'Plant',
+    interfaces: [named],
+    options: ObjectOptions(isTypeOf: (value) => value is _Plant),
+    fields: (t) => [t.field('name', b.string.nullable).pure((p) => p.name)],
+  );
+  pet = b.union<Object?>(
+    'Pet',
+    members: [dog, cat],
+    resolveType: (value) => value is _Dog ? dog : cat,
+  );
+  petOrPlant = b.union<Object?>(
+    'PetOrPlantType',
+    members: [plant, dog, cat],
+  );
   final schema = b.build(query: person);
 
   final garfield = _Cat('Garfield', false);
@@ -158,6 +162,78 @@ void main() {
   ];
 
   group('Execute: Union and intersection types', () {
+    test('can introspect on union and intersection types', () async {
+      String selection(String alias, String name) =>
+          '''
+        $alias: __type(name: "$name") {
+          kind
+          name
+          fields { name }
+          interfaces { name }
+          possibleTypes { name }
+          enumValues { name }
+          inputFields { name }
+        }
+''';
+      expect(
+        await run('''
+      {
+${selection('Named', 'Named')}${selection('Mammal', 'Mammal')}${selection('Pet', 'Pet')}      }
+    ''', rootValue: john),
+        {
+          'data': {
+            'Named': {
+              'kind': 'INTERFACE',
+              'name': 'Named',
+              'fields': [
+                {'name': 'name'},
+              ],
+              'interfaces': <Object?>[],
+              'possibleTypes': [
+                {'name': 'Dog'},
+                {'name': 'Cat'},
+                {'name': 'Person'},
+                {'name': 'Plant'},
+              ],
+              'enumValues': null,
+              'inputFields': null,
+            },
+            'Mammal': {
+              'kind': 'INTERFACE',
+              'name': 'Mammal',
+              'fields': [
+                {'name': 'progeny'},
+                {'name': 'mother'},
+                {'name': 'father'},
+              ],
+              'interfaces': [
+                {'name': 'Life'},
+              ],
+              'possibleTypes': [
+                {'name': 'Dog'},
+                {'name': 'Cat'},
+                {'name': 'Person'},
+              ],
+              'enumValues': null,
+              'inputFields': null,
+            },
+            'Pet': {
+              'kind': 'UNION',
+              'name': 'Pet',
+              'fields': null,
+              'interfaces': null,
+              'possibleTypes': [
+                {'name': 'Dog'},
+                {'name': 'Cat'},
+              ],
+              'enumValues': null,
+              'inputFields': null,
+            },
+          },
+        },
+      );
+    });
+
     test('executes using union types', () async {
       expect(
         await run('''
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -108,7 +108,10 @@ void main() {
         'execution/__tests__/union-interface-test.ts',
         'execution/__tests__/variables-test.ts',
         'execution/__tests__/oneof-test.ts',
+        'execution/__tests__/simplePubSub-test.ts',
+        'execution/__tests__/subscribe-test.ts',
         'type/__tests__/enumType-test.ts',
+        'type/__tests__/introspection-test.ts',
         'utilities/__tests__/coerceInputValue-test.ts',
         'utilities/__tests__/validateInputValue-test.ts',
       ],
```

In `packages/typed_graphql_conformance/test/support/execution_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,19 +39,41 @@ final class ExecutionPort {
     context: context,
     operationName: operationName,
     variables: variables,
-    options: ExecutionOptions(
-      rootValue: options.rootValue,
-      source: Source(text),
-      errorBehavior: options.errorBehavior,
-      maskErrors: options.maskErrors,
-      includesSuggestions: options.includesSuggestions,
-      onError: options.onError,
-      maxCoercionErrors: options.maxCoercionErrors,
-      maxDepth: options.maxDepth,
-      maxSteps: options.maxSteps,
-    ),
+    options: _withSource(options, text),
+  );
+
+  /// graphql-js's `subscribe` for the unvalidated [text]: the source of the
+  /// single root field is created and the stream (or the request error) is
+  /// returned.
+  FutureOr<SubscriptionResult> subscribe<C>(
+    ExecutableSchema<C> schema,
+    String text, {
+    required C context,
+    String? operationName,
+    JsonObject? variables,
+    ExecutionOptions options = unmasked,
+  }) => schema.subscribe(
+    ValidDocument.assumeValid(schema.schema, parse(text)),
+    context: context,
+    operationName: operationName,
+    variables: variables,
+    options: _withSource(options, text),
   );
 
+  ExecutionOptions _withSource(ExecutionOptions options, String text) =>
+      ExecutionOptions(
+        rootValue: options.rootValue,
+        source: Source(text),
+        errorBehavior: options.errorBehavior,
+        maskErrors: options.maskErrors,
+        includesSuggestions: options.includesSuggestions,
+        onError: options.onError,
+        maxCoercionErrors: options.maxCoercionErrors,
+        maxDepth: options.maxDepth,
+        maxSteps: options.maxSteps,
+        introspection: options.introspection,
+      );
+
   /// [payload] for a schema whose context is not read.
   FutureOr<ResponsePayload> run(
     ExecutableSchema<Object?> schema,
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -415,7 +415,6 @@ execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract type
 execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolve Union type using __typename on source object,adapted,test/execution/abstract_test.dart,There is no default resolveType reading __typename from the source: the union gets a resolveType over Map sources that reads the key.
 execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolve Interface type using __typename on source object,adapted,test/execution/abstract_test.dart,There is no default resolveType reading __typename from the source: the interface gets a resolveType over Map sources that reads the key.
 execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolveType on Interface yields useful error,adapted,test/execution/abstract_test.dart,"resolveType returns an object type definition, never a name: only the ""no type accepts the value"" error and the ""not a possible type"" error (GQL334) can happen; the messages for an undefined, unknown, non-object or wrongly typed name cannot be reached."
-execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,can introspect on union and intersection types,skipped,,M5c
 execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes using union types,ported,test/execution/union_interface_test.dart,
 execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes union types with inline fragments,ported,test/execution/union_interface_test.dart,
 execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes using interface types,ported,test/execution/union_interface_test.dart,
@@ -438,7 +437,6 @@ type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept interna
 type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept enum literal in place of int,ported,test/execution/enum_type_test.dart,
 type/__tests__/enumType-test.ts,Type System: Enum Values,accepts JSON string as enum variable,ported,test/execution/enum_type_test.dart,
 type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input arguments to mutations,ported,test/execution/enum_type_test.dart,
-type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input arguments to subscriptions,skipped,,M5c (subscriptions).
 type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept internal value as enum variable,ported,test/execution/enum_type_test.dart,
 type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept string variables as enum input,ported,test/execution/enum_type_test.dart,
 type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept internal value variable as enum input,ported,test/execution/enum_type_test.dart,
@@ -449,4 +447,52 @@ type/__tests__/enumType-test.ts,Type System: Enum Values,presents a getValue() A
 type/__tests__/enumType-test.ts,Type System: Enum Values,may be internally represented with complex values,adapted,test/execution/enum_type_test.dart,"The ""bad"" field (a value equal to but not the same as an internal value) cannot be written with a typed enum and is not ported; the other three fields are."
 type/__tests__/enumType-test.ts,Type System: Enum Values,may be internally represented with complex values using legacy internal defaults,adapted,test/execution/enum_type_test.dart,"Defaults are Dart enum values; graphql-js's legacy internal-value default has no counterpart, so the default is the enum value itself."
 type/__tests__/enumType-test.ts,Type System: Enum Values,may have values specified via a callback,adapted,test/execution/enum_type_test.dart,"Enum values are given as a list, not a callback; the resolver returns the enum value's name."
-type/__tests__/enumType-test.ts,Type System: Enum Values,can be introspected without error,skipped,,M5c (introspection).
+type/__tests__/introspection-test.ts,Introspection,executes an introspection query,adapted,test/execution/introspection_test.dart,"The schema is built with the typed builder. graphql-js 17 also has the working-draft parts of the specification (directive deprecation, fragment variables); this edition's introspection types have none, so the expected result lacks __Schema.directives(includeDeprecated:), __Directive.isDeprecated and deprecationReason, the FRAGMENT_VARIABLE_DEFINITION and DIRECTIVE_DEFINITION locations and the latter on @deprecated."
+type/__tests__/introspection-test.ts,Introspection,introspects on input object,adapted,test/execution/introspection_test.dart,"An Arg default of null means no default, so `c: String = null` cannot be declared: its defaultValue is null, not the text 'null'."
+type/__tests__/introspection-test.ts,Introspection,introspects any default value,ported,test/execution/introspection_test.dart,
+type/__tests__/introspection-test.ts,Introspection,supports the __type root field,ported,test/execution/introspection_test.dart,
+type/__tests__/introspection-test.ts,Introspection,identifies deprecated fields,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,respects the includeDeprecated parameter for fields,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,identifies deprecated args,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,respects the includeDeprecated parameter for args,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,identifies deprecated enum values,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,respects the includeDeprecated parameter for enum values,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,identifies deprecated for input fields,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,respects the includeDeprecated parameter for input fields,ported,test/execution/introspection_deprecation_test.dart,
+type/__tests__/introspection-test.ts,Introspection,identifies oneOf for input objects,ported,test/execution/introspection_one_of_test.dart,
+type/__tests__/introspection-test.ts,Introspection,returns null for oneOf for other types,ported,test/execution/introspection_one_of_test.dart,
+type/__tests__/introspection-test.ts,Introspection,fails as expected on the __type root field without an arg,ported,test/execution/introspection_test.dart,
+type/__tests__/introspection-test.ts,Introspection,exposes descriptions,ported,test/execution/introspection_test.dart,
+type/__tests__/introspection-test.ts,Introspection,executes an introspection query without calling global resolvers,adapted,test/execution/introspection_test.dart,"There are no fieldResolver or typeResolver options: global field middleware that records its calls stands for them, and introspection fields are never wrapped by it."
+type/__tests__/introspection-test.ts,Introspection,identifies deprecated directives,skipped,,"A directive definition cannot be deprecated in this edition: @deprecated is not allowed on DIRECTIVE_DEFINITION (GQL118), so the schema is refused at build; directive deprecation is working-draft."
+type/__tests__/introspection-test.ts,Introspection,respects the includeDeprecated parameter for directives,skipped,,"A directive definition cannot be deprecated in this edition: @deprecated is not allowed on DIRECTIVE_DEFINITION (GQL118), so the schema is refused at build; directive deprecation is working-draft."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,throws for legacy ExecutionArgs passed to createSourceEventStream,skipped,,JavaScript API: createSourceEventStream takes validated arguments.
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,throws when validateSubscriptionArgs is called with a non-subscription operation,skipped,,There is no validateSubscriptionArgs; the same check is the GQL324 rejection of subscribe (next row).
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,throws when subscribe is called with a non-subscription operation,adapted,test/execution/subscribe_initialization_test.dart,"subscribe answers a SubscriptionRejected (GQL324 'Expected subscription operation.', no location) instead of throwing."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,accepts multiple subscription fields defined in schema,adapted,test/execution/subscribe_initialization_test.dart,Each field declares its source (subscribeWith); graphql-js reads it from the root value. The stream ends after the one event.
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,accepts type definition with sync subscribe function,adapted,test/execution/subscribe_initialization_test.dart,"The source is declared on the field and builds a Stream; the result of subscribe is checked to be a value, not a Future."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,accepts type definition with async subscribe function,adapted,test/execution/subscribe_initialization_test.dart,The source answers a Future of a Stream; the result of subscribe is checked to be a Future.
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,uses a custom default subscribeFieldResolver,skipped,,There is no subscribeFieldResolver option: a source is always declared on the field.
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,maps a source stream to response events with a custom rootSelectionSetExecutor,skipped,,"createSourceEventStream, mapSourceToResponseEvent and rootSelectionSetExecutor are not public API."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,should only resolve the first field of invalid multi-field,adapted,test/execution/subscribe_initialization_test.dart,"Sources are declared on the fields. The first event is checked to hold foo: 'FooValue' (the response also holds bar: null, which graphql-js does not check)."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,resolves to an error if schema does not support subscriptions,adapted,test/execution/subscribe_initialization_test.dart,The request error has no locations (spec 18 of M5: request errors carry none).
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,resolves to an error for unknown subscription field,adapted,test/execution/subscribe_initialization_test.dart,"An undefined field is dropped from the plan (spec 6.4), as in execute, so the error is GQL322 'The subscription selects no root field.' without locations."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,should pass through unexpected errors thrown in subscribe,skipped,,"JavaScript: passes a malformed document object, which the typed API cannot express."
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,throws an error if subscribe does not return an iterator,skipped,,A typed source returns a Stream; a value that is not a stream cannot be written.
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,resolves to an error for subscription resolver errors,adapted,test/execution/subscribe_initialization_test.dart,Returning or resolving to an Error value is a JavaScript idiom with no counterpart; throwing and a failed future are ported (GraphQLException keeps its message).
+execution/__tests__/subscribe-test.ts,Subscription Initialization Phase,resolves to an error if variables were wrong type,ported,test/execution/subscribe_initialization_test.dart,
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,produces a payload for multiple subscribe in same subscription,adapted,test/execution/subscribe_publish_test.dart,"Each event is the field's value: the source builds the EmailEvent that graphql-js wraps in { importantEmail }, and the source is declared on the field; next() is StreamIterator.moveNext."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,produces a payload when queried fields are async,adapted,test/execution/subscribe_publish_test.dart,"Each event is the field's value: the source builds the EmailEvent that graphql-js wraps in { importantEmail }, and the source is declared on the field; next() is StreamIterator.moveNext. return() is StreamIterator.cancel."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,produces a payload per subscription event,adapted,test/execution/subscribe_publish_test.dart,"Each event is the field's value: the source builds the EmailEvent that graphql-js wraps in { importantEmail }, and the source is declared on the field; next() is StreamIterator.moveNext. return() is StreamIterator.cancel."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,subscribe function returns errors with @defer,skipped,,"@defer and @stream are M14: the executor ignores them on every operation, so there is no 'directive not supported on subscription operations' error."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,subscribe function returns errors with @stream,skipped,,"@defer and @stream are M14: the executor ignores them on every operation, so there is no 'directive not supported on subscription operations' error."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,produces a payload when there are multiple events,adapted,test/execution/subscribe_publish_test.dart,"Each event is the field's value: the source builds the EmailEvent that graphql-js wraps in { importantEmail }, and the source is declared on the field; next() is StreamIterator.moveNext. return() is StreamIterator.cancel."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,should not trigger when subscription is already done,adapted,test/execution/subscribe_publish_test.dart,"Each event is the field's value: the source builds the EmailEvent that graphql-js wraps in { importantEmail }, and the source is declared on the field; next() is StreamIterator.moveNext. return() is StreamIterator.cancel."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,should not trigger when subscription is thrown,skipped,,JavaScript async iterator protocol (throw()).
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,event order is correct for multiple publishes,adapted,test/execution/subscribe_publish_test.dart,"Each event is the field's value: the source builds the EmailEvent that graphql-js wraps in { importantEmail }, and the source is declared on the field; next() is StreamIterator.moveNext. return() is StreamIterator.cancel."
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,should handle error during execution of source event,adapted,test/execution/subscribe_publish_test.dart,The source and the per-event resolver are declared with subscribeWith; the error is a GraphQLException.
+execution/__tests__/subscribe-test.ts,Subscription Publish Phase,should pass through error thrown in source event stream,adapted,test/execution/subscribe_publish_test.dart,A source error ends the response stream with a final result (data null and the error) instead of rejecting next() (spec 18.10).
+execution/__tests__/simplePubSub-test.ts,SimplePubSub,subscribe async-iterator mock,skipped,,JavaScript async iterator protocol: the test reads ahead with concurrent next() calls and return(); the Dart SimplePubSub is exercised by the subscribe tests.
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,can introspect on union and intersection types,adapted,test/execution/union_interface_test.dart,The executor requires a root value of the root type (a Person); the introspection query ignores it.
+type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input arguments to subscriptions,adapted,test/execution/enum_type_test.dart,"subscribeToEnum has a declared, empty source; the operation is run once with execute (spec 10), which resolves it with a null event."
+type/__tests__/enumType-test.ts,Type System: Enum Values,can be introspected without error,adapted,test/execution/enum_type_test.dart,schema.toIntrospection(IntrospectionQuery.full) stands for introspectionFromSchema.
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/introspection_deprecation_test.dart test/execution/introspection_one_of_test.dart test/execution/introspection_test.dart test/execution/subscribe_initialization_test.dart test/execution/subscribe_publish_test.dart test/execution/enum_type_test.dart test/execution/union_interface_test.dart test/mapping_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/enum_type_test.dart packages/typed_graphql_conformance/test/execution/fixtures/introspection_query_result.json packages/typed_graphql_conformance/test/execution/introspection_deprecation_test.dart packages/typed_graphql_conformance/test/execution/introspection_one_of_test.dart packages/typed_graphql_conformance/test/execution/introspection_test.dart packages/typed_graphql_conformance/test/execution/subscribe_initialization_test.dart packages/typed_graphql_conformance/test/execution/subscribe_publish_test.dart packages/typed_graphql_conformance/test/execution/union_interface_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/email_subscription.dart packages/typed_graphql_conformance/test/support/execution_port.dart packages/typed_graphql_conformance/test/support/introspection_fixture.dart packages/typed_graphql_conformance/test/support/simple_pub_sub.dart
git commit -q -m "test(typed_graphql_conformance): port the introspection and subscription suites" \
  -m "Ports graphql-js's introspection, subscribe and simplePubSub tests and the enum and union introspection tests left skipped in M5b, with a Dart SimplePubSub; async-iterator protocol tests and the @defer/@stream and directive-deprecation tests are skipped with their reasons." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: The deviations in the spec

Record the M5c behaviour differences in section 18 (items 26-33).

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-m5-execution-design.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -662,6 +662,37 @@ depends on the other). These constraints keep that possible:
 25. Enum values are Dart enum values, with no internal values: the tests
     with a "bad" complex internal value or a string given for an enum
     cannot be written (`enum_type_test.dart`).
+26. Introspection follows the September2025 edition, which lacks graphql-js
+    17's working-draft parts: directive deprecation
+    (`__Schema.directives(includeDeprecated:)`, `__Directive.isDeprecated`)
+    and the `DIRECTIVE_DEFINITION` and `FRAGMENT_VARIABLE_DEFINITION`
+    locations are not in the results (`introspection_test.dart`).
+27. `@deprecated` on a directive definition is refused (`GQL118`), so the two
+    graphql-js tests about deprecated directives are `skipped`
+    (`introspection_deprecation_test.dart`).
+28. An `Arg` has no explicit `null` default: a null default means "no
+    default", so introspection says `defaultValue: null` where graphql-js
+    says `'null'` (`introspection_test.dart`).
+29. `@defer` and `@stream` in a subscription are ignored, not refused, until
+    M14, so graphql-js's two "returns errors with @defer / @stream" tests are
+    `skipped` (`subscribe_publish_test.dart`).
+30. A subscription that cannot start is a `SubscriptionRejected` value, never
+    a throw: a non-subscription operation is `GQL324` ("Expected
+    subscription operation."), a root field that is skipped or undefined is
+    `GQL322` ("The subscription selects no root field."), and these request
+    errors carry no `locations` (`subscribe_initialization_test.dart`).
+31. A source stream that errors only after it has been listened to cannot be
+    seen at start: it becomes the final `GQL340` result of the stream, which
+    then closes, where graphql-js rejects `next()` (item 10)
+    (`subscribe_publish_test.dart`).
+32. The source subscription is paused while an event executes, so events are
+    executed one at a time and in order, and a source error or its end waits
+    for the event in flight (`subscribe_publish_test.dart`).
+33. `execute` needs a root value that the root type accepts, introspection
+    queries included: a root typed `Object?` or `void` takes `null`, any
+    other root takes a value of its Dart type. A guide shows how to declare a
+    root that needs none (`introspection_test.dart`,
+    `union_interface_test.dart`).
 
 ## 19. Conformance (R0.7, R10.3)
 
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md
git commit -q -m "docs: record the M5c deviations in the M5 spec" \
  -m "Items 26-33 of section 18: the introspection and subscription behaviour that differs from graphql-js, each with the conformance file that shows it." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: The Introspection and Subscriptions guides

Move `IntrospectionPolicy` to `introspection/` and the `SubscriptionResult` family to `subscription/` so their dartdoc categories follow the folder, and write `doc/introspection.md` and `doc/subscriptions.md`, `dartdoc_options.yaml`, the README, CHANGELOG, `llms.txt`, `docs/discovery.md`, the root README, `CLAUDE.md` and HANDOFF.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/introspection/introspection_policy.dart`, `packages/typed_graphql_server/lib/src/subscription/subscription_result.dart`
- Modify: `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `CLAUDE.md`, `README.md`, `docs/discovery.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/README.md`, `packages/typed_graphql_server/dartdoc_options.yaml`
- Create (documents): `packages/typed_graphql_server/doc/introspection.md`, `packages/typed_graphql_server/doc/subscriptions.md`
- Delete (with `git rm` in the commit step): `packages/typed_graphql_server/lib/src/execution/introspection_policy.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_result.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// introspection/introspection_policy.dart
enum IntrospectionPolicy

// subscription/subscription_result.dart
sealed class SubscriptionResult
final class SubscriptionStarted
final class SubscriptionRejected
```

- [ ] **Step 1: Write the implementation**

Create `packages/typed_graphql_server/lib/src/introspection/introspection_policy.dart`:

```dart
/// Whether an execution answers `__schema` and `__type`.
///
/// `__typename` is answered either way: it describes the response, not the
/// schema.
///
/// {@category introspection}
enum IntrospectionPolicy {
  /// `__schema` and `__type` are answered (September2025 4.2).
  enabled,

  /// `__schema` and `__type` are field errors (`GQL338`), each with a null
  /// value.
  disabled,
}
```

Create `packages/typed_graphql_server/lib/src/subscription/subscription_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// What `ExecutableSchema.subscribe` answers: a stream of results, or a
/// request error and no stream.
///
/// {@category subscription}
sealed class SubscriptionResult {
  const SubscriptionResult();
}

/// The subscription started.
///
/// [results] is a single-subscription stream: the source is listened to when
/// [results] is, pausing and resuming pass through to the source, and
/// cancelling the subscription to [results] cancels the source. It closes
/// when the source is done.
///
/// {@category subscription}
final class SubscriptionStarted extends SubscriptionResult {
  /// Wraps [results].
  const SubscriptionStarted(this.results);

  /// One result per source event, in order.
  final Stream<ExecutionResult> results;
}

/// The subscription did not start: a request error, or the source stream
/// could not be created (September2025 6.2.3.1), as graphql-js answers with
/// a result of errors instead of a stream.
///
/// {@category subscription}
final class SubscriptionRejected extends SubscriptionResult {
  /// Wraps [error].
  const SubscriptionRejected(this.error);

  /// The errors, as the response to the request.
  final RequestErrorResult error;
}
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,11 +4,11 @@ import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../plan/plan_cache.dart';
+import '../subscription/subscription_result.dart';
 import 'execution_options.dart';
 import 'operation_execution.dart';
 import 'schema_bindings.dart';
 import 'subscription_execution.dart';
-import 'subscription_result.dart';
 
 /// A validated schema with the resolvers behind it: what
 /// `ExecutableSchemaBuilder.build` returns. `C` is the context type the
```

In `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,9 +1,9 @@
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../introspection/introspection_policy.dart';
 import 'error_behavior.dart';
 import 'error_hook.dart';
-import 'introspection_policy.dart';
 
 /// The settings of one call of `ExecutableSchema.execute`.
 ///
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,11 +7,11 @@ import '../builder/field_def.dart';
 import '../builder/field_lane.dart';
 import '../coercion/coercion_result.dart';
 import '../introspection/entry_fields.dart';
+import '../introspection/introspection_policy.dart';
 import '../plan/field_plan.dart';
 import 'completion_site.dart';
 import 'execution_run.dart';
 import 'field_info.dart';
-import 'introspection_policy.dart';
 import 'response_path.dart';
 
 /// Resolves one field (September2025 6.4 "Executing Fields"): answers the
```

In `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,13 +3,13 @@ import 'dart:async';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../plan/plan_cache.dart';
+import '../subscription/subscription_result.dart';
 import 'execution_options.dart';
 import 'execution_run.dart';
 import 'operation_preparation.dart';
 import 'prepared_operation.dart';
 import 'schema_bindings.dart';
 import 'subscription_responses.dart';
-import 'subscription_result.dart';
 
 /// One call of `ExecutableSchema.subscribe` (September2025 6.2.3
 /// "Subscription"): prepares the operation, creates the source event stream
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,8 +2,8 @@
 /// engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws
 /// and graphql-sse handlers.
 ///
-/// Under construction: the typed schema builder (M5a) and query execution
-/// (M5b) work. See the package README.
+/// Under construction: the typed schema builder (M5a), query execution (M5b),
+/// introspection and subscriptions (M5c) work. See the package README.
 library;
 
 export 'src/builder/arg.dart';
@@ -38,6 +38,6 @@ export 'src/execution/field_middleware.dart';
 export 'src/execution/field_resolver.dart';
 export 'src/execution/field_site.dart';
 export 'src/execution/graphql_exception.dart';
-export 'src/execution/introspection_policy.dart';
 export 'src/execution/response_path.dart';
-export 'src/execution/subscription_result.dart';
+export 'src/introspection/introspection_policy.dart';
+export 'src/subscription/subscription_result.dart';
```

- [ ] **Step 2: Update the documents**

Create `packages/typed_graphql_server/doc/introspection.md`:

````markdown
# Introspection

A client learns a server's schema by asking it: `__schema` returns the whole
schema and `__type(name:)` one type (September2025 section 4.2).
`ExecutableSchema` answers both by itself. There are no resolvers to write and
nothing to register: the answer is read from the schema the builder made, so
it cannot disagree with what the server executes. This guide shows an
introspection query, the guarantee about its answer, how to switch it off, and
how to declare the root types so that no root value is needed. It builds on
the Schema Builder and Execution guides.

## Asking the schema about itself

An introspection query is an ordinary document: validate it, execute it. The
meta fields `__schema` and `__type` exist on the query root type only, and
`__typename` on every object. The types and fields of the answer are the
specification's `__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue`
and `__Directive`, with the enums `__TypeKind` and `__DirectiveLocation`. A
type's `description` is the one given to the builder, and a field that is not
null is reported as a `NON_NULL` wrapper around its type.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<String>(
    'Book',
    description: 'A book in the library.',
    fields: (t) => [
      t.field('title', b.string).pure((title) => title),
      t.field('pages', b.int.nullable).pure((title) => title.length),
    ],
  );
  // The root type takes no parent value: `Object?` accepts the default
  // `null` root value.
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('books', b.list(book)).pure((_) => const ['Dune']),
    ],
  );
  final schema = b.build(query: query);

  const text = '''
{
  __type(name: "Book") {
    name
    description
    fields { name type { kind name ofType { kind name } } }
  }
}''';
  final response = await schema.execute(check(schema, text), context: null);
  print(response.toJson());

  final counts = await schema.execute(
    check(schema, '{ __schema { queryType { name } types { name } } }'),
    context: null,
  );
  print(counts.toJson());
}
```

It prints:

```text
{"data":{"__type":{"name":"Book","description":"A book in the library.","fields":[{"name":"title","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String"}}},{"name":"pages","type":{"kind":"SCALAR","name":"Int","ofType":null}}]}}}
{"data":{"__schema":{"queryType":{"name":"Query"},"types":[{"name":"Book"},{"name":"Query"},{"name":"String"},{"name":"Int"},{"name":"Boolean"},{"name":"__Schema"},{"name":"__Type"},{"name":"__TypeKind"},{"name":"__Field"},{"name":"__InputValue"},{"name":"__EnumValue"},{"name":"__Directive"},{"name":"__DirectiveLocation"}]}}}
```

`__schema { types }` lists the schema's own types first, in the order they
were created, then the built-in scalars the schema uses, then the
introspection types. The listing is the core's `IntrospectionListing`, shared
with `Schema.toIntrospection`, so both give the same order. `fields`,
`enumValues`, `args` and `inputFields` take `includeDeprecated`, and a field
or enum value marked deprecated carries its `deprecationReason`.
`possibleTypes` of an abstract type lists its object types in the core's
order, `specifiedByURL` and `isOneOf` read the scalar and the input object,
and a default value is printed as GraphQL text.

## The same answer as the core

The server and the core agree: executing `IntrospectionQuery.full` gives the
`data` that `toIntrospection` writes for the schema, so a client built with
`SchemaBuilder().fromIntrospection` sees the schema the server built. This
edition's introspection has none of graphql-js 17's working-draft parts:
directive deprecation (`__Schema.directives(includeDeprecated:)`,
`__Directive.isDeprecated`) and the `DIRECTIVE_DEFINITION` and
`FRAGMENT_VARIABLE_DEFINITION` locations are not there.

## Turning introspection off

`ExecutionOptions.introspection` takes an `IntrospectionPolicy`: `enabled`
(the default) or `disabled`. When it is disabled `__schema` and `__type` are
field errors with the code `GQL338`; `__schema` is non-null, so its error
nulls `data`. `__typename` still works, because it describes the response,
not the schema. The check is made by field name on every execution, so a
field reached through a fragment is refused too. Global middleware never
wraps introspection fields. To refuse such a query before it runs, use the
core's `NoIntrospectionRule` at validation time.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final schema = b.build(query: query);

  // The full introspection query gets what the core writes for the schema.
  final full = await schema.execute(
    check(schema, IntrospectionQuery.full.text),
    context: null,
  );
  final expected = schema.schema.schema.toIntrospection();
  print(full is ExecutionResult && full.data == expected);

  // A server that hides its schema turns the policy off.
  const closed = ExecutionOptions(introspection: IntrospectionPolicy.disabled);
  final hidden = await schema.execute(
    check(schema, '{ __typename __schema { queryType { name } } }'),
    context: null,
    options: closed,
  );
  print(hidden.toJson());
}
```

It prints:

```text
true
{"errors":[{"message":"GraphQL introspection has been disabled, but the requested query contained the field \"__schema\".","path":["__schema"],"extensions":{"code":"GQL338"}}],"data":null}
```

## Root types without a root value

`execute` hands `ExecutionOptions.rootValue` (`null` by default) to the root
fields as their parent, and the root type must accept it. A root type
declared with the parent type `Object?` accepts `null` and needs no root
value: write `b.object<Object?>('Query', ...)`, as the programs above do, and
execute without `rootValue`. A root type declared with another Dart type,
such as `b.object<Library>('Query', ...)`, needs a `Library` in `rootValue`,
and that holds for an introspection query too. A `rootValue` the root type
does not accept is an `ArgumentError`.
````

Create `packages/typed_graphql_server/doc/subscriptions.md`:

````markdown
# Subscriptions

A subscription operation turns a stream of events into a stream of
responses. `ExecutableSchema.subscribe` starts one: it runs the source
function of the operation's root field, then executes the selection set once
for every event the source stream emits. It builds on the Schema Builder and
Execution guides; the response to each event is an `ExecutionResult`, like
the response to a query.

## Declaring a subscription

A subscription root field takes its events from a source, declared on the
field stub with `subscribe` or `subscribeWith`. `subscribe` takes a function
that returns the `Stream` (or a `Future` of it) of values of the field's own
type: each item is completed as the value of the field. `subscribeWith<E>`
takes a source of events of another type `E` and a second function that turns
each event into the field's value, as graphql-js's field `resolve` does next
to its `subscribe`. The source function gets the root value, the arguments,
the context and the `FieldInfo` once, when the subscription starts. The root
type may be declared with `Object?` as its parent, so no root value is needed.

`subscribe` answers a `FutureOr<SubscriptionResult>`, sealed:
`SubscriptionStarted(results)` holds the stream of responses, and
`SubscriptionRejected(error)` the request error of a subscription that could
not start. Cancelling the listener of `results` cancels the source stream;
when the source is done, `results` closes. The programs here use a finite
source so that they end.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final limit = Arg('to', b.int);
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      // Each item of the stream is the value of the field.
      t
          .field('count', b.int, args: [limit])
          .subscribe(
            (parent, args, context, info) => Stream.fromIterable([
              for (var i = 1; i <= args.get(limit); i++) i,
            ]),
          ),
      // The events are raw words; `resolve` turns each into the field's value.
      t
          .field('shout', b.string)
          .subscribeWith<String>(
            (parent, args, context, info) =>
                Stream.fromIterable(const ['hey', 'ho']),
            (event, args, context, info) => event.toUpperCase(),
          ),
    ],
  );
  final schema = b.build(query: query, subscription: subscription);

  final started = await schema.subscribe(
    check(schema, 'subscription { count(to: 3) }'),
    context: null,
  );
  if (started case SubscriptionStarted(:final results)) {
    await for (final result in results) {
      print(result.toJson());
    }
  }

  final shouts = await schema.subscribe(
    check(schema, 'subscription { shout }'),
    context: null,
  );
  if (shouts case SubscriptionStarted(:final results)) {
    print(await results.map((result) => result.toJson()).toList());
  }

  // A query is not a subscription: the request is rejected, not thrown.
  final rejected = await schema.subscribe(
    check(schema, '{ hello }'),
    context: null,
  );
  if (rejected case SubscriptionRejected(:final error)) {
    print(error.toJson());
  }
}
```

It prints:

```text
{"data":{"count":1}}
{"data":{"count":2}}
{"data":{"count":3}}
[{"data":{"shout":"HEY"}}, {"data":{"shout":"HO"}}]
{"errors":[{"message":"Expected subscription operation.","extensions":{"code":"GQL324"}}]}
```

## One event at a time

Events are executed one at a time and in order. While an event executes, the
source subscription is paused, so a source that emits faster than the
resolvers answer waits instead of piling up; a source error, or the end of
the source, is seen after the event in flight. Pausing and resuming
`results` pause and resume the source, and the source is listened to only
when `results` is. The field errors of an event are in that event's result,
with the null propagation of a query, and do not end the stream.

Global and field middleware wrap the per-event resolution, not the source
function, and the parent that middleware sees is the event.

## Failures

A subscription that cannot start is a `SubscriptionRejected`, never a throw:
a document whose operation is not a subscription (`GQL324`, "Expected
subscription operation."), a root field that is skipped or undefined
(`GQL322`, "The subscription selects no root field."), bad variables or
arguments, and a source function that throws or whose future fails. The
last is the field error of the root field, masked like any other (`GQL330`)
unless it is a `GraphQLException`. These request errors carry no `locations`.

A source stream that fails only after it has been listened to cannot be seen
when the subscription starts. It becomes the last result of `results`, an
error result with the code `GQL340` (or the message and extensions of a
`GraphQLException`), and `results` then closes. `@defer` and `@stream` in a
subscription are ignored until M14.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Stream<int> flaky() async* {
  yield 1;
  throw StateError('The feed is down.');
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      t
          .field('ticks', b.int)
          .subscribe((parent, args, context, info) => flaky()),
      t
          .field('broken', b.int)
          .subscribe(
            (parent, args, context, info) => throw StateError('No feed.'),
          ),
    ],
  );
  final schema = b.build(query: query, subscription: subscription);

  // A failure while the source stream is created rejects the request.
  final rejected = await schema.subscribe(
    check(schema, 'subscription { broken }'),
    context: null,
  );
  if (rejected case SubscriptionRejected(:final error)) {
    print(error.toJson());
  }

  // A failure after the stream started is its last result; then it closes.
  final started = await schema.subscribe(
    check(schema, 'subscription { ticks }'),
    context: null,
  );
  if (started case SubscriptionStarted(:final results)) {
    await for (final result in results) {
      print(result.toJson());
    }
    print('closed');
  }
}
```

It prints:

```text
{"errors":[{"message":"Unexpected error.","path":["broken"],"extensions":{"code":"GQL330"}}]}
{"data":{"ticks":1}}
{"errors":[{"message":"Unexpected error.","extensions":{"code":"GQL340"}}],"data":null}
closed
```

## Subscriptions and execute

`execute` on a subscription operation runs it once, as a query, with the root
value as the single event, as graphql-js does. Use `subscribe` to get the
stream.
````

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -51,7 +51,11 @@ executor with specified null propagation, error behaviours, masking and
 `onError`, field middleware, abstract-type resolution at run time
 (`GQL310`-`GQL337`), the graphql-js execution, variables, directives,
 abstract-type, enum and input-coercion suites, and the Execution guide and
-example. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
+example. M5c (introspection and subscriptions) delivers the `__schema` and
+`__type` resolvers, `IntrospectionPolicy` (`GQL338`), `subscribe` with its
+source streams and rejected requests (`GQL324`, `GQL340`), the graphql-js
+introspection and subscribe suites, and the Introspection and Subscriptions
+guides. M10 (client code generation) delivers the `typed_graphql.yaml` reader, schema loading from a
 file or a URL, the project's documents as one fragment graph, the planner and
 emitters that generate the schema-types library and a library per document
 (operations, variables, data, fragments, sealed polymorphic classes, the
@@ -407,9 +411,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 **Server** (`packages/typed_graphql_server/lib/src/`; M5). Imports the core
 only through its barrel. One folder per concern, with no import order
 (`builder/` and `execution/` import each other): `builder/` (M5a),
-`coercion/`, `plan/` and `execution/` (M5b), then `introspection/`,
-`subscription/`, `lookahead/`, `authorization/` and `cancellation/` in later
-sub-stages. The package is
+`coercion/`, `plan/` and `execution/` (M5b), `introspection/` and
+`subscription/` (M5c), then `lookahead/`, `authorization/` and `cancellation/`
+in later sub-stages. The package is
 transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
 or web framework, only `dart:async`, `dart:collection`, `dart:core`,
 `dart:math`, `meta` and the core (`test/quality/imports_test.dart`), and the
@@ -442,7 +446,16 @@ field tables (pure lanes over the core model; a list or non-null `__Type` is an
 `IntrospectedType` wrapper) and the query root's `__schema`/`__type` to the
 bindings after middleware; `EntryFields` gives the planner their `SchemaField`s,
 only on the query root; `ExecutionOptions.introspection` (`IntrospectionPolicy`)
-turns them into `GQL338` field errors.
+turns them into `GQL338` field errors. `IntrospectionPolicy` is in
+`introspection/` and `SubscriptionResult` in `subscription/` because a type's
+dartdoc category is its folder.
+Subscriptions (M5c): `FieldStub.subscribe`/`subscribeWith` make a
+`SubscribeLane` (source plus per-event `resolve`; middleware wraps only the
+latter); `execution/SubscriptionExecution` prepares the operation once
+(`OperationPreparation`) and `SubscriptionResponses` executes each event in
+order, pausing the source meanwhile; a source that fails after listening is the
+last result (`GQL340`), one that fails at start is a `SubscriptionRejected`.
+`subscription/` holds only the public `SubscriptionResult` family.
 
 **Codegen** (`packages/typed_graphql_codegen`; M10). Depends on the core,
 `args`, `crypto`, `glob`, `path` and `yaml`, never on `analyzer`; the engine
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -27,7 +27,8 @@ What works today: the language (parse, print, visit and transform queries and
 SDL), the schema (build it from SDL, extend, print and validate it, introspection
 both ways, schema coordinates), operation validation, the wire protocol types,
 scalar codecs and the diagnostics model; and, in `typed_graphql_server`, a
-typed schema builder and the execution of a validated operation.
+typed schema builder, the execution of a validated operation, introspection
+and subscriptions.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
@@ -110,7 +111,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder and query execution (M5a, M5b) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection and subscriptions (M5a-M5c) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
````

In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,6 +40,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | validate a GraphQL operation dart | M4 | yes |
 | limit GraphQL query depth or cost dart | M4 | yes |
 | execute a GraphQL query dart | M5 | yes |
+| GraphQL subscriptions server dart | M5 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
 
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
-| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; next is M5c (introspection, subscriptions) |
+| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: [plan](plans/2026-10-15-m5a-typed-builder.md); M5b: [plan](plans/2026-10-15-m5b-execution-core.md) | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; M5c is done on the same branch: the `__schema`/`__type` resolvers and `IntrospectionPolicy` (`GQL338`), `subscribe` (`GQL324`, `GQL340`), the graphql-js introspection and subscribe suites, spec §18 items 26-33 and the Introspection and Subscriptions guides; next is M5d (look-ahead, authorization, cancellation) |
 | M10 Client code generation | [spec](specs/2026-10-15-m10-client-codegen-design.md) | M10a: [plan](plans/2026-10-15-m10a-codegen-front-end.md); M10b: [plan](plans/2026-10-15-m10b-runtime-and-schema-types.md); M10c: [plan](plans/2026-10-15-m10c-operations-and-fragments.md); M10d: [plan](plans/2026-10-15-m10d-command-line.md) | M10 is complete on branch `m10-final`: the final opus whole-branch review is done and its fix round is committed; awaiting merge, not merged and not pushed (the plans are generated from the commits; the fix round's commits are in the M10d plan). The client's Chrome test runs are deferred to M11. `typed_graphql_codegen` reads `typed_graphql.yaml` (`GQL500`, `GQL501`), loads the schema from SDL, an introspection result or a URL (`GQL502`, `GQL510`), checks the documents as one fragment graph (`GQL503`-`GQL506`, `GQL511`), plans the classes and generates the schema-types library, a library per document and the persisted-operations manifest (`GQL507`, `GQL508`); the CLI `generate` / `check` (`GQL509`) lives in `lib/src/cli/`; the core gained `Optional` and the client the generated-code contract (`JsonMerger` included); goldens, an analysis test and the checked-in `example/` project; the guide `client_codegen.md` |
 
 **Decisions (2026-10-14):**
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware; its transports (stages M6, M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware, answers introspection queries and runs subscriptions over event streams; its look-ahead, authorization and cancellation (M5d) and transports (stages M6, M7) are not built yet. The code generator typed_graphql_codegen generates typed classes for the operations and fragments of .graphql documents; the client runtime they run on (M11) is not built yet. Nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; the CLI `dart run typed_graphql_codegen generate|check` reads typed_graphql.yaml, loads the schema from a file or a URL, validates the .graphql documents and generates the schema types and the operation and fragment classes of each document; the generated code needs typed_graphql_client, which holds only its contract until M11 (the server generator is M8)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder and Execution in its doc folder, runnable example in its example folder); introspection resolvers and subscriptions (M5c) and transport handlers (M6, M7) come later
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder, Execution, Introspection and Subscriptions in its doc folder, runnable example in its example folder); introspection resolvers and subscriptions work; look-ahead, authorization and cancellation (M5d) and transport handlers (M6, M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Introspection: `__schema` and `__type(name:)` on the query root and the
  `__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue`,
  `__Directive` types are answered from the core model, in the order of
  `IntrospectionListing`; executing `IntrospectionQuery.full` gives
  `toIntrospection`. `ExecutionOptions.introspection` takes
  `IntrospectionPolicy` (`enabled`, `disabled`); disabled gives `GQL338`.
- Subscriptions: `FieldStub.subscribe` and `subscribeWith` declare a source
  stream; `ExecutableSchema.subscribe` answers a `SubscriptionResult`
  (`SubscriptionStarted` with a stream of results, or `SubscriptionRejected`).
  Events are executed one at a time and in order; a source that fails after
  it started ends the stream with a final `GQL340` result; a query or
  mutation is `GQL324`.
- The Introspection and Subscriptions guides, with the dartdoc categories
  `introspection` and `subscription`.
```

In `packages/typed_graphql_server/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,12 +6,13 @@
 
 **A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: under construction.** The typed schema builder (M5a) and query
-> execution (M5b) work: you can declare a schema in typed Dart code, parse and
-> validate a request with the core, and execute it, with variables, specified
-> null propagation, error behaviours, masking and field middleware. Introspection
-> resolvers and subscriptions arrive in M5c; look-ahead, authorization and
-> cancellation in M5d; the request pipeline and the HTTP, graphql-ws and
+> **Status: under construction.** The typed schema builder (M5a), query
+> execution (M5b), introspection and subscriptions (M5c) work: you can declare
+> a schema in typed Dart code, parse and validate a request with the core, and
+> execute it, with variables, specified null propagation, error behaviours,
+> masking and field middleware, answer introspection queries and run a
+> subscription over a stream of events. Look-ahead, authorization and
+> cancellation arrive in M5d; the request pipeline and the HTTP, graphql-ws and
 > graphql-sse handlers later. See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
@@ -44,9 +45,9 @@ dependencies:
   ([Schema Builder](doc/schema_builder.md#objects-and-fields),
   [Execution](doc/execution.md#executing-a-request)).
 - **You do not need it when** you only call a GraphQL server: that is the
-  client package, not usable yet. Today it also has no HTTP handler or
-  subscriptions: you call `ExecutableSchema.execute` yourself with a parsed
-  and validated document.
+  client package, not usable yet. Today it also has no HTTP or
+  WebSocket handler: you call `ExecutableSchema.execute` or `subscribe`
+  yourself with a parsed and validated document.
 - **What it replaces**: resolvers written against `Map<String, dynamic>`, where
   a wrong result type or a misspelled argument name fails at run time in the
   middle of a request. Here the wrong type does not compile, and every error
@@ -135,6 +136,10 @@ It prints:
 - [Execution](doc/execution.md): executing a request, variables, request errors
   and field errors, error behaviours, masking and `onError`, middleware,
   abstract types, limits and the plan cache.
+- [Introspection](doc/introspection.md): `__schema` and `__type`, the same
+  answer as the core, `IntrospectionPolicy`, root types without a root value.
+- [Subscriptions](doc/subscriptions.md): source streams, one event at a time,
+  rejected and failed subscriptions.
 
 ## License
 
```

In `packages/typed_graphql_server/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,7 +6,15 @@ dartdoc:
     execution:
       markdown: doc/execution.md
       displayName: Execution
+    introspection:
+      markdown: doc/introspection.md
+      displayName: Introspection
+    subscription:
+      markdown: doc/subscriptions.md
+      displayName: Subscriptions
   categoryOrder:
     - builder
     - execution
+    - introspection
+    - subscription
   showUndocumentedCategories: true
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
git rm -q packages/typed_graphql_server/lib/src/execution/introspection_policy.dart packages/typed_graphql_server/lib/src/execution/subscription_result.dart
git add CLAUDE.md README.md docs/discovery.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/README.md packages/typed_graphql_server/dartdoc_options.yaml packages/typed_graphql_server/doc/introspection.md packages/typed_graphql_server/doc/subscriptions.md packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/lib/src/execution/execution_options.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/subscription_execution.dart packages/typed_graphql_server/lib/src/introspection/introspection_policy.dart packages/typed_graphql_server/lib/src/subscription/subscription_result.dart packages/typed_graphql_server/lib/typed_graphql_server.dart
git commit -q -m "docs(typed_graphql_server): document introspection and subscriptions" \
  -m "Adds the Introspection and Subscriptions guides with runnable programs and the categories introspection and subscription; IntrospectionPolicy and SubscriptionResult move into their folders so the category follows the folder." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: `IntrospectionListing` in the core Introspection guide (core)

One sentence in the core's Introspection guide: `IntrospectionListing(schema)` gives the order of `types` and `directives`, for a server that writes its own introspection resolvers.

**Files:**
- Modify: `packages/typed_graphql/doc/introspection.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `packages/typed_graphql/doc/introspection.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -43,7 +43,9 @@ answer to a narrower query is smaller. A union lists every member as a
 possible type, even one that is not an object type, so the validator still
 sees it on the client; a member named twice (`union U = A | A`) is written
 twice, as declared, whereas `Schema.possibleTypes` lists each object type
-once. Introspect a validated schema: a reference to a type
+once. `IntrospectionListing(schema)` gives the order in which the answer lists
+`types` and `directives`, for a server that writes its own introspection
+resolvers. Introspect a validated schema: a reference to a type
 the schema does not have is an `ArgumentError`.
 
 ```dart
````

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
git add packages/typed_graphql/doc/introspection.md
git commit -q -m "docs(typed_graphql): mention IntrospectionListing in the Introspection guide" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Review fix: a hardened subscription response stream

A source that delivers synchronously inside `listen` still runs one event at a time (events, errors and done queue while an event runs; pauses owed before `listen` returned are applied after it); a failing `onCancel` leaves no uncaught error; `haltError` is read through a pattern; `_callSource` takes five plain parameters. Tests in `subscription_flow_test.dart`: an in-flight event dropped on cancel, error and done delivered after the running event's result, the synchronous source, the failing `onCancel`.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`
- Test: `packages/typed_graphql_server/test/execution/subscription_flow_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/execution/subscription_flow_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of these tests: the source, and what the event resolver saw.
final class Feed {
  Feed(this.source);

  final Stream<int> source;
  final List<String> log = [];
  int running = 0;
  int mostRunning = 0;

  /// When set, every resolver waits for it.
  Completer<void>? gate;
}

/// Builds the schema of these tests and starts subscriptions on it.
final class FlowHarness {
  /// Creates a harness.
  const FlowHarness();

  ExecutableSchema<Feed> schema() {
    final b = ExecutableSchemaBuilder<Feed>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('noop', b.string).pure((_) => 'noop')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t.field('count', b.int).subscribeWith<int>(
          (parent, args, context, info) => context.source,
          (
            event,
            args,
            context,
            info,
          ) async {
            context.running++;
            if (context.running > context.mostRunning) {
              context.mostRunning = context.running;
            }
            context.log.add('start $event');
            await (context.gate?.future ??
                Future<void>.delayed(const Duration(milliseconds: 1)));
            context.log.add('end $event');
            context.running--;
            return event;
          },
        ),
      ],
    );
    return b.build(query: query, subscription: subscription);
  }

  Future<Stream<ExecutionResult>> started(Feed feed) async {
    final built = schema();
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source('subscription { count }')).requireDocument();
    final result = await built.subscribe(
      ValidDocument.assumeValid(built.schema, document),
      context: feed,
    );
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
    };
  }

  Object? dataOf(ExecutionResult result) => result.toJson().toJson()['data'];
}

void main() {
  const harness = FlowHarness();
  final started = harness.started;
  final dataOf = harness.dataOf;
  test(
    'a source that delivers inside listen runs one event at a time',
    () async {
      late final StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..add(2)
          ..add(3),
      );
      final feed = Feed(controller.stream);
      final results = await started(feed);
      final collected = <Object?>[];
      final done = Completer<void>();
      results.listen((result) {
        collected.add(dataOf(result));
        if (collected.length == 3) {
          done.complete();
        }
      });
      await done.future;
      expect(collected, [
        {'count': 1},
        {'count': 2},
        {'count': 3},
      ]);
      expect(feed.mostRunning, 1);
      expect(feed.log, [
        'start 1',
        'end 1',
        'start 2',
        'end 2',
        'start 3',
        'end 3',
      ]);
      await controller.close();
    },
  );

  test('a source whose cancel fails leaves no uncaught error', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(
      () async {
        final controller = StreamController<int>(
          onCancel: () => Future<void>.error(StateError('cancel failed')),
        );
        addTearDown(controller.close);
        final results = await started(Feed(controller.stream));
        final collected = results.toList();
        controller.addError(StateError('source failed'));
        expect(await collected, hasLength(1));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      (error, stackTrace) => uncaught.add(error),
    );
    expect(uncaught, isEmpty);
  });

  test(
    'an event in flight when the consumer cancels gives no result',
    () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final gate = Completer<void>();
      final feed = Feed(controller.stream)..gate = gate;
      final results = await started(feed);
      final collected = <ExecutionResult>[];
      final subscription = results.listen(collected.add);
      controller.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(feed.log, ['start 1']);
      await subscription.cancel();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(collected, isEmpty);
    },
  );

  test('a source error during an event comes after its result', () async {
    final controller = StreamController<int>();
    addTearDown(controller.close);
    final gate = Completer<void>();
    final feed = Feed(controller.stream)..gate = gate;
    final results = await started(feed);
    final collected = results.map(dataOf).toList();
    controller
      ..add(1)
      ..addError(StateError('late failure'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();
    expect(await collected, [
      {'count': 1},
      null,
    ]);
  });

  test(
    'the end of the source during an event comes after its result',
    () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final gate = Completer<void>();
      final feed = Feed(controller.stream)..gate = gate;
      final results = await started(feed);
      final collected = results.map(dataOf).toList();
      controller
        ..add(1)
        ..close().ignore();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      expect(await collected, [
        {'count': 1},
      ]);
    },
  );
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/subscription_flow_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -88,22 +88,22 @@ final class FieldExecution {
     if (arguments == null) {
       return null;
     }
-    return _callSource(lane, parent, arguments, (field.type, site));
+    return _callSource(lane, parent, arguments, field.type, site);
   }
 
   FutureOr<Stream<Object?>?> _callSource(
     SubscribeLane lane,
     Object? parent,
     Arguments arguments,
-    (TypeRef, CompletionSite) where,
+    TypeRef type,
+    CompletionSite site,
   ) {
-    final site = where.$2;
     try {
       final opened = lane.source(
         parent,
         arguments,
         _run.context,
-        _infoOf(where.$1, site),
+        _infoOf(type, site),
       );
       return opened is Future<Stream<Object?>>
           ? opened.then<Stream<Object?>?>(
```

In `packages/typed_graphql_server/lib/src/execution/subscription_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -78,7 +78,10 @@ final class SubscriptionExecution {
   // root field at all has none, so it says so.
   SubscriptionRejected _rejected(ExecutionRun run) {
     final log = run.reporter.log;
-    final errors = log.haltError != null ? [log.haltError!] : log.errors;
+    final errors = switch (log.haltError) {
+      final halted? => [halted],
+      null => log.errors,
+    };
     return SubscriptionRejected(
       RequestErrorResult(
         errors: errors.isEmpty
```

In `packages/typed_graphql_server/lib/src/execution/subscription_responses.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import 'dart:async';
+import 'dart:collection';
 
 import 'package:typed_graphql/typed_graphql.dart';
 
@@ -9,9 +10,11 @@ import 'execution_run.dart';
 /// field's value, one at a time and in order.
 ///
 /// The source is paused while an event executes, so its events, its error and
-/// its end wait their turn. The response stream is a single-subscription
-/// controller: listening starts the source, pause and resume pass through to
-/// it, and cancelling cancels it.
+/// its end wait their turn. A source that delivers synchronously inside
+/// `listen` cannot be paused yet: what it delivers meanwhile waits in
+/// [_waiting], and the pauses are applied when `listen` returns. The response
+/// stream is a single-subscription controller: listening starts the source,
+/// pause and resume pass through to it, and cancelling cancels it.
 final class SubscriptionResponses {
   /// Maps the events of [_source] to results of runs like [_template].
   SubscriptionResponses(this._template, this._source) {
@@ -29,7 +32,12 @@ final class SubscriptionResponses {
   // Set in the constructor body, which runs before anything can listen.
   late final StreamController<ExecutionResult> _controller;
   StreamSubscription<Object?>? _subscription;
+  final Queue<void Function()> _waiting = Queue<void Function()>();
   bool _isCancelled = false;
+  bool _isBusy = false;
+  bool _isDraining = false;
+  // Pauses owed to the source because it delivered before `listen` returned.
+  int _owedPauses = 0;
 
   /// The results; listen once.
   Stream<ExecutionResult> get stream => _controller.stream;
@@ -37,18 +45,63 @@ final class SubscriptionResponses {
   void _listen() {
     _subscription = _source.listen(
       _onEvent,
-      onError: _fail,
-      onDone: _onSourceDone,
+      onError: (Object error, StackTrace stackTrace) =>
+          _whenIdle(() => _fail(error, stackTrace)),
+      onDone: () => _whenIdle(_close),
     );
+    for (; _owedPauses > 0; _owedPauses--) {
+      _subscription?.pause();
+    }
+    if (_isCancelled) {
+      _subscription?.cancel().ignore();
+    }
   }
 
   Future<void> _cancel() {
+    // After a failure the source is already cancelled and its outcome dropped.
+    final wasCancelled = _isCancelled;
     _isCancelled = true;
+    _waiting.clear();
+    if (wasCancelled) {
+      return Future<void>.value();
+    }
     return _subscription?.cancel() ?? Future<void>.value();
   }
 
+  void _pauseSource() {
+    final subscription = _subscription;
+    if (subscription == null) {
+      _owedPauses++;
+    } else {
+      subscription.pause();
+    }
+  }
+
+  void _resumeSource() {
+    final subscription = _subscription;
+    if (subscription == null) {
+      _owedPauses--;
+    } else {
+      subscription.resume();
+    }
+  }
+
   void _onEvent(Object? event) {
-    _subscription?.pause();
+    _pauseSource();
+    _whenIdle(() => _execute(event));
+  }
+
+  void _whenIdle(void Function() action) {
+    if (_isBusy || _isDraining) {
+      _waiting.add(action);
+    } else {
+      action();
+      _drain();
+    }
+  }
+
+  void _execute(Object? event) {
+    _isBusy = true;
     try {
       final result = _template.restarted().executeRoot(event);
       if (result is Future<ExecutionResult>) {
@@ -57,19 +110,35 @@ final class SubscriptionResponses {
         _emit(result);
       }
     } on Object catch (error, stackTrace) {
+      _isBusy = false;
       _fail(error, stackTrace);
     }
   }
 
   void _emit(ExecutionResult result) {
+    _isBusy = false;
     if (_isCancelled) {
       return;
     }
     _controller.add(result);
-    _subscription?.resume();
+    _resumeSource();
+    _drain();
+  }
+
+  // Runs what arrived while an event executed. Guarded, so that a synchronous
+  // result does not recurse once per waiting event.
+  void _drain() {
+    if (_isDraining) {
+      return;
+    }
+    _isDraining = true;
+    while (!_isBusy && !_isCancelled && _waiting.isNotEmpty) {
+      _waiting.removeFirst()();
+    }
+    _isDraining = false;
   }
 
-  void _onSourceDone() {
+  void _close() {
     if (!_isCancelled) {
       _controller.close();
     }
@@ -78,13 +147,16 @@ final class SubscriptionResponses {
   // The source failed (or the library did, which cannot be told apart by
   // the client): one last result with the error, then the end (spec 10).
   void _fail(Object error, StackTrace stackTrace) {
+    _isBusy = false;
     if (_isCancelled) {
       return;
     }
     _isCancelled = true;
+    _waiting.clear();
     final reported = _template.reporter.sourceFailure(error, stackTrace);
     _controller.add(ExecutionResult(null, errors: [reported]));
     _controller.close();
-    unawaited(_subscription?.cancel() ?? Future<void>.value());
+    // A source whose cancel fails must not leave an unhandled error.
+    _subscription?.cancel().ignore();
   }
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/subscription_flow_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/subscription_execution.dart packages/typed_graphql_server/lib/src/execution/subscription_responses.dart packages/typed_graphql_server/test/execution/subscription_flow_test.dart
git commit -q -m "fix(typed_graphql_server): harden the subscription response stream" \
  -m "A source that delivers inside listen is held to one event at a time, a failing source cancel leaves no unhandled error, and an error or end during an event waits for its result." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Review fix: `GQL303` on interface fields

`BuilderChecks` reports a `subscribe` / `subscribeWith` source on an interface field too.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`
- Test: `packages/typed_graphql_server/test/builder/subscription_fields_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_server/test/builder/subscription_fields_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,6 +39,30 @@ void main() {
       );
     });
 
+    test('a subscribe source on an interface field', () {
+      final query = b.object<Object?>(
+        'Query',
+        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
+      );
+      b.interface<Object?>(
+        'Ticker',
+        resolveType: (value) => query,
+        fields: (t) => [
+          t
+              .field('ticks', b.int)
+              .subscribe((parent, args, context, info) => Stream.value(1)),
+        ],
+      );
+      final problems = problemsOf(() => b.build(query: query));
+      expect(
+        problems.map((problem) => problem.message),
+        [
+          'Field "Ticker.ticks" has a subscribe source but "Ticker" is not '
+              'the subscription root type.',
+        ],
+      );
+    });
+
     test('a subscription root field without a source', () {
       final query = b.object<Object?>(
         'Query',
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/subscription_fields_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'field_def.dart';
 import 'field_lane.dart';
 import 'interface_type_def.dart';
 import 'named_type_def.dart';
@@ -49,34 +50,51 @@ final class BuilderChecks {
   }
 
   // `GQL303`: a subscribe source belongs to the fields of the subscription
-  // root, and each of those fields needs one.
+  // root, and each of those fields needs one. An interface is never the root.
   void _checkSubscriptionFields(
     List<NamedTypeDef> definitions,
     ObjectTypeDef<Object?>? subscription,
   ) {
     for (final definition in definitions) {
-      if (definition is! ObjectTypeDef<Object?>) continue;
-      final isRoot = identical(definition, subscription);
-      for (final field in definition.fields) {
-        final hasSource = field.lane is SubscribeLane;
-        if (hasSource == isRoot) continue;
-        problems.add(
-          Diagnostic(
-            .misplacedSubscriptionField,
-            .error,
-            isRoot
-                ? 'Field "${definition.name}.${field.name}" of the '
-                      'subscription root type has no subscribe source: '
-                      'declare it with subscribe or subscribeWith.'
-                : 'Field "${definition.name}.${field.name}" has a subscribe '
-                      'source but "${definition.name}" is not the '
-                      'subscription root type.',
-          ),
-        );
+      switch (definition) {
+        case ObjectTypeDef<Object?>():
+          _checkSourcesOf(
+            definition.name,
+            definition.fields,
+            identical(definition, subscription),
+          );
+        case InterfaceTypeDef<Object?>():
+          _checkSourcesOf(definition.name, definition.fields, false);
+        // `NamedTypeDef` is not sealed, so the switch needs a default.
+        default:
       }
     }
   }
 
+  void _checkSourcesOf(
+    String typeName,
+    List<FieldDef<Object?, Object?>> fields,
+    bool isRoot,
+  ) {
+    for (final field in fields) {
+      final hasSource = field.lane is SubscribeLane;
+      if (hasSource == isRoot) continue;
+      problems.add(
+        Diagnostic(
+          .misplacedSubscriptionField,
+          .error,
+          isRoot
+              ? 'Field "$typeName.${field.name}" of the '
+                    'subscription root type has no subscribe source: '
+                    'declare it with subscribe or subscribeWith.'
+              : 'Field "$typeName.${field.name}" has a subscribe '
+                    'source but "$typeName" is not the '
+                    'subscription root type.',
+        ),
+      );
+    }
+  }
+
   void _checkInterfaces(
     String name,
     String dartTypeName,
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/subscription_fields_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/builder/builder_checks.dart packages/typed_graphql_server/test/builder/subscription_fields_test.dart
git commit -q -m "fix(typed_graphql_server): report a subscription source on an interface field" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: Review fix: `__type` answers only listed types

`__type(name:)` answers only for names in `IntrospectionListing`'s types, as graphql-js's `getType` has no built-in fallback: an unused `Float` is null, `__Schema` still answers.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart`
- Test: `packages/typed_graphql_server/test/introspection/introspection_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_server/test/introspection/introspection_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -44,6 +44,16 @@ void main() {
     expect(data['__type'], isNull);
   });
 
+  test('__type of a built-in scalar the schema does not use is null', () async {
+    final data = await dataOf('{ __type(name: "Float") { name } }');
+    expect(data['__type'], isNull);
+  });
+
+  test('__type still answers for an introspection type', () async {
+    final data = await dataOf('{ __type(name: "__Schema") { name } }');
+    expect(data['__type'], {'name': '__Schema'});
+  });
+
   test('__type takes its name from a variable', () async {
     final json = await fixture.json(
       r'query ($n: String!) { __type(name: $n) { name } }',
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/introspection/introspection_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -43,16 +43,22 @@ final class IntrospectionBindings(
     return bindings.withIntrospection(fields, _leaves);
   }
 
+  // `typeNamed` also answers built-ins the schema does not use; as in
+  // graphql-js, `__type` answers only for the types `__schema` lists.
+  // Set on first use: lookups only, never iterated.
+  late final Set<String> _listedNames = {
+    for (final type in IntrospectionListing(schema).types) type.name,
+  };
+
   Map<String, FieldDef<Object?, Object?>> get _entryFields =>
       IntrospectionFields.table([
         IntrospectionFields.pure<Object?>('__schema', (_) => schema),
         IntrospectionFields.withArguments<Object?>(
           '__type',
-          (_, arguments) => switch (schema.typeNamed(
-            arguments['name'] as String,
-          )) {
-            final type? => IntrospectedType.named(type.name),
-            null => null,
+          (_, arguments) => switch (arguments['name'] as String) {
+            final name when _listedNames.contains(name) =>
+              IntrospectedType.named(name),
+            _ => null,
           },
         ),
       ]);
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/introspection/introspection_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/introspection/introspection_bindings.dart packages/typed_graphql_server/test/introspection/introspection_test.dart
git commit -q -m "fix(typed_graphql_server): answer __type only for listed types" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Review fix: introspection limits and the middleware exemption

`introspection_limits_test.dart`: global middleware wraps an ordinary resolved field but no introspection field; a deep cyclic `__schema` walk ends with `GQL336`, a branching one with `GQL337`, an `ofType` chain 300 deep completes.

**Files:**
- Test: `packages/typed_graphql_server/test/introspection/introspection_limits_test.dart`, `packages/typed_graphql_server/test/introspection/introspection_fixture.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/introspection/introspection_limits_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'introspection_fixture.dart';

void main() {
  List<String> codesOf(Map<String, Object?> json) => [
    for (final error in (json['errors'] ?? const <Object?>[]) as List<Object?>)
      ((error! as Map<String, Object?>)['extensions']!
              as Map<String, Object?>)['code']!
          as String,
  ];

  // `fields { type {` repeated: the types of the fixture refer to each other,
  // so the walk branches at every level.
  String cyclicQuery(int levels) =>
      '{ __schema { types { ${'fields { type { ' * levels}name'
      '${' } }' * levels} } } }';

  test(
    'global middleware skips introspection and wraps other fields',
    () async {
      final seen = <String>[];
      final fixture = IntrospectionFixture(
        middleware: [
          (next, site) => (parent, args, context, info) {
            seen.add(site.field.name);
            return next(parent, args, context, info);
          },
        ],
      );
      final json = await fixture.json(
        '{ search { __typename } __schema { queryType { name } } '
        '__type(name: "Account") { fields { name } } }',
      );
      expect(json['errors'], isNull);
      expect(seen, ['search']);
    },
  );

  group('hostile queries', () {
    final fixture = IntrospectionFixture();

    test('a deep walk over cyclic types ends with GQL336', () async {
      final json = await fixture.json(
        cyclicQuery(4),
        options: const ExecutionOptions(maxDepth: 6),
      );
      expect(codesOf(json), contains('GQL336'));
    });

    test('a branching walk is stopped by maxSteps with GQL337', () async {
      final json = await fixture.json(
        cyclicQuery(60),
        options: const ExecutionOptions(maxSteps: 5000),
      );
      expect(codesOf(json), ['GQL337']);
      expect(json['data'], isNull);
    });

    test('an ofType chain 300 levels deep ends without error', () async {
      final json = await fixture.json(
        '{ __schema { types { fields { type { ${'ofType { ' * 300}name'
        '${' }' * 300} } } } } }',
      );
      expect(json['errors'], isNull);
    });
  });
}
```

In `packages/typed_graphql_server/test/introspection/introspection_fixture.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@ final class Robot {
 /// A schema with every kind of type, deprecations, descriptions and a
 /// repeatable directive, and helpers to run queries against it.
 final class IntrospectionFixture {
-  IntrospectionFixture() {
+  IntrospectionFixture({List<FieldMiddleware<Object?>> middleware = const []}) {
     final b = ExecutableSchemaBuilder<Object?>();
     final url = b.scalar<String>(
       'Url',
@@ -119,6 +119,7 @@ final class IntrospectionFixture {
       mutation: mutation,
       options: BuildOptions(
         description: 'The API.',
+        middleware: middleware,
         directives: [
           SchemaDirective(
             'tag',
```

- [ ] **Step 2: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/introspection/introspection_limits_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql_server/test/introspection/introspection_fixture.dart packages/typed_graphql_server/test/introspection/introspection_limits_test.dart
git commit -q -m "test(typed_graphql_server): prove introspection limits and middleware exemption" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: Review fix: the backpressure wording

The Subscriptions guide, spec section 18 item 32 and the CHANGELOG say that a paused broadcast source keeps buffering (the application bounds it), that a library error while executing an event ends the stream with `GQL340`, and that a response stream never listened to has already called the source; the CHANGELOG's duplicated entries are merged; `docs/discovery.md` gains the introspection row.

**Files:**
- Modify: `docs/discovery.md`, `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/subscriptions.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,6 +40,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | validate a GraphQL operation dart | M4 | yes |
 | limit GraphQL query depth or cost dart | M4 | yes |
 | execute a GraphQL query dart | M5 | yes |
+| GraphQL introspection server dart | M5 | yes |
 | GraphQL subscriptions server dart | M5 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | yes |
```

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -685,9 +685,17 @@ depends on the other). These constraints keep that possible:
     seen at start: it becomes the final `GQL340` result of the stream, which
     then closes, where graphql-js rejects `next()` (item 10)
     (`subscribe_publish_test.dart`).
-32. The source subscription is paused while an event executes, so events are
-    executed one at a time and in order, and a source error or its end waits
-    for the event in flight (`subscribe_publish_test.dart`).
+32. Events are executed one at a time and in order. The source subscription
+    is paused while an event executes, and a source error or its end waits
+    for the event in flight, also when the source delivers synchronously
+    inside `listen` (`subscribe_publish_test.dart`,
+    `subscription_flow_test.dart`). A single-subscription source then waits;
+    a broadcast source keeps buffering inside its paused subscription
+    without bound, so the application must bound it. An unexpected library
+    error while executing an event ends the stream with a `GQL340` result. A
+    response stream that is never listened to has already called the source
+    function: listen to it or drop it promptly when the source registers
+    eagerly.
 33. `execute` needs a root value that the root type accepts, introspection
     queries included: a root typed `Object?` or `void` takes `null`, any
     other root takes a value of its Dart type. A guide shows how to declare a
```

In `packages/typed_graphql_server/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -76,27 +76,21 @@
   `__EnumValue` and `__Directive` objects registered by `build`.
   `ExecutionOptions.introspection` takes `IntrospectionPolicy`: `disabled`
   makes `__schema` and `__type` a `GQL338` field error; `__typename` still works.
+  `__type` answers only for the types `__schema` lists, in the order of
+  `IntrospectionListing`; global middleware does not wrap introspection fields.
 - Subscriptions: `t.field(...).subscribe(source)` (each event is the field's
   value) and `subscribeWith<E>(source, resolve)` declare a subscription root
   field; `build` reports `GQL303` for a source outside the subscription root
   or a root field without one. `ExecutableSchema.subscribe` answers a
   `SubscriptionStarted` with a single-subscription stream of
-  `ExecutionResult`s (one event at a time, in order; cancel, pause and resume
-  reach the source; a source error is a last masked `GQL340` result) or a
+  `ExecutionResult`s (one event at a time, in order, the source paused while
+  an event executes, so a broadcast source buffers without bound inside its
+  paused subscription and the application must bound it; cancel, pause and
+  resume reach the source; a source error, or an unexpected library error
+  while executing an event, is a last masked `GQL340` result; the source
+  function has already run when the stream is never listened to) or a
   `SubscriptionRejected` (request errors, `GQL324` for a query or mutation, a
   failing source function). `execute` on a subscription runs it once as a
   query.
-- Introspection: `__schema` and `__type(name:)` on the query root and the
-  `__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue`,
-  `__Directive` types are answered from the core model, in the order of
-  `IntrospectionListing`; executing `IntrospectionQuery.full` gives
-  `toIntrospection`. `ExecutionOptions.introspection` takes
-  `IntrospectionPolicy` (`enabled`, `disabled`); disabled gives `GQL338`.
-- Subscriptions: `FieldStub.subscribe` and `subscribeWith` declare a source
-  stream; `ExecutableSchema.subscribe` answers a `SubscriptionResult`
-  (`SubscriptionStarted` with a stream of results, or `SubscriptionRejected`).
-  Events are executed one at a time and in order; a source that fails after
-  it started ends the stream with a final `GQL340` result; a query or
-  mutation is `GQL324`.
 - The Introspection and Subscriptions guides, with the dartdoc categories
   `introspection` and `subscription`.
```

In `packages/typed_graphql_server/doc/subscriptions.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -108,12 +108,21 @@ It prints:
 ## One event at a time
 
 Events are executed one at a time and in order. While an event executes, the
-source subscription is paused, so a source that emits faster than the
-resolvers answer waits instead of piling up; a source error, or the end of
-the source, is seen after the event in flight. Pausing and resuming
-`results` pause and resume the source, and the source is listened to only
-when `results` is. The field errors of an event are in that event's result,
-with the null propagation of a query, and do not end the stream.
+source subscription is paused; a source error, or the end of the source, is
+seen after the event in flight. A single-subscription source then waits for
+the resolvers. A broadcast source, the usual publish and subscribe channel,
+keeps buffering inside its paused subscription without bound, so the
+application must bound it (drop or sample events before they reach the
+stream). Pausing and resuming `results` pause and resume the source, and the
+source is listened to only when `results` is. The field errors of an event
+are in that event's result, with the null propagation of a query, and do not
+end the stream. An unexpected library error while executing an event ends
+the stream with a `GQL340` result.
+
+The source function runs when the subscription starts, before anyone listens
+to `results`. A response stream that is never listened to has therefore
+already called it: when the source registers eagerly, listen to `results` or
+drop it promptly.
 
 Global and field middleware wrap the per-event resolution, not the source
 function, and the parent that middleware sees is the event.
```

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
git add docs/discovery.md docs/superpowers/specs/2026-10-15-m5-execution-design.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/subscriptions.md
git commit -q -m "docs(typed_graphql_server): correct the subscription backpressure wording" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

- The full list, with recommendations, is section 21 of the spec and `.superpowers/m5-open-questions.md`. M5c adds no new question; its behaviour differences are spec section 18, items 26-33.

## Self-review

- Spec coverage: section 9 (introspection) by Tasks 2-3; 10 (subscriptions) by Task 4; 15 (codes) by Task 1; 19 (conformance) by Task 6; 18 by Task 7; 20 (documents) by Task 8. Tasks 10-14 answer the M5c review: the backpressure wording, untested stream paths, `GQL303` on interfaces, the `__type` listing, introspection limits.
- Every code block is the committed text that passed the green check; no placeholder remains.
- Names are consistent across tasks: `IntrospectionPolicy`, `IntrospectionListing`, `SubscriptionResult`, `SubscriptionStarted`, `SubscriptionRejected`, `subscribe`, `subscribeWith`.

## After the plan

M5d (`2026-10-15-m5d-lookahead-authorization-cancellation.md`) adds look-ahead, authorization, cancellation and the benchmarks. Merging `m5-final` into `main` and pushing need the owner's explicit yes.
