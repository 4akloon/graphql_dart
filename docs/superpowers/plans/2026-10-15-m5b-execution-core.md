# M5b Coercion and Execution Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute queries and mutations on an `ExecutableSchema` (R4.3-R4.6, R0.3, R11): input coercion of variables and arguments with graphql-js 17's messages, `@oneOf` and bounded depth; operation selection and a cached operation plan (field collection with `@skip` / `@include` / `@defer` evaluated once per condition key); the executor (`FutureOr` all the way, null propagation, `ErrorBehavior`, masking with `GraphQLException` and the `onError` hook, `maxDepth` and `maxSteps`); abstract types at run time; field middleware composed at build time; the graphql-js executor, null, list, mutation, variable, input-coercion, directive, abstract-type and enum suites ported; the Execution guide and the example.

**Architecture:** Three folders in `packages/typed_graphql_server/lib/src/`. `coercion/` turns JSON variables (`VariableCoercion` over `InputCoercion`, `LeafCoercion`, `InputObjectCoercion`) and argument literals (`ArgumentCoercion` over `LiteralCoercion`, substituting coerced variables, and the raw JSON of a variable inside a custom scalar's literal) into Dart values, reporting `CoercionProblem`s with graphql-js's message and path; depth is bounded at 1000. `plan/` selects the operation (`GQL320`-`GQL323`), collects fields with an explicit stack (each fragment once per collection) and caches an `OperationPlan` per (Document identity, operation name, includesSuggestions) in an LRU of `BuildOptions.planCacheSize`; a plan memoises its root per `ConditionKey` (16 per plan) and each `FieldPlan` its child node per object type and its constant arguments. `execution/` runs one `ExecutionRun` per call: `SelectionExecutor` (parallel) or `SerialFields` (mutations), `FieldExecution` (the one place a lane is called; middleware is already composed into the lane at build), `ValueCompletion` with leaf, list, object and abstract completion, `PendingValues` (no future, one `then`, or `Future.wait`), `ErrorReporter` (masking, `GraphQLException`, `onError`, codes, locations, paths) and `ExecutionLimits`. Dart `null` is the propagation sentinel and `JsonNull` a real null, so a sync-only query returns a non-`Future` result. The core gains the `GQL310`-`GQL337` codes and `JsonInspector` (graphql-js `inspect` in scalar messages) in their own commits.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5), `package:test`, `package:meta`, the core `typed_graphql`. graphql-js 17.0.2 in `reference/graphql-js` (`execution/`, `utilities/coerceInputValue.ts`, `utilities/validateInputValue.ts`, `jsutils/inspect.ts`) for messages, null propagation and the ported suites.

**Spec:** `docs/superpowers/specs/2026-10-15-m5-execution-design.md` (sections 4-8, 15, 16, 18, 19), `docs/requirements.md` R4.3-R4.6 and R11.

**Base:** the M5a plan (`2026-10-15-m5a-typed-builder.md`) applied, on branch `m5-final` at `8d59203`. The plan was verified by applying its tasks in order, one commit per task, with the green check after each and the server and core suites on exe at the end.

`Optional<…>` now comes from the core (`package:typed_graphql`), since merge 6e5bd05; the plan's text and code stay as committed.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, in tests too (helpers are classes in `test/support/` or local functions in `main`).
- The server imports the core only through its barrel, and `lib/` imports no platform library but `dart:async`, `dart:collection`, `dart:core` and `dart:math` (spec section 17).
- Bad input never throws (R0.3): a bad variable is a `RequestErrorResult`, a bad argument or a failing resolver a field error in the `ExecutionResult`. Only programmer errors throw (`ArgumentError` for a document validated against another schema or a root value of the wrong type).
- **No unbounded recursion and no blow-up on hostile input.** Coercion stops at 1000 levels with one problem; field collection uses an explicit stack and expands each fragment once; completion depth is bounded by `maxDepth` (256); `maxSteps` (10 000 000 completed values) halts a run; the plan cache and the condition keys are LRU-bounded.
- No `async` function on the execution paths: results are `FutureOr`, so a query whose resolvers are all synchronous returns a non-`Future` response.
- Messages are graphql-js 17.0.2's to the character where graphql-js has the same check; every library-made error carries `extensions.code` (`GQL3xx`). New codes go into `DiagnosticCode` in id order, with a doc comment, in their own core commit.
- A ported graphql-js test is recorded in `packages/typed_graphql_conformance/mapping/execution.csv` in the same commit (`ported`, `adapted` with the reason, or `skipped` with the reason), and its file is added to the table's covered files in `test/mapping_test.dart`. A behaviour difference goes into the spec's section 18.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time. Chrome cannot start under `ulimit -v`; bound the browser runs by resident memory with `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- `reference/` (git-ignored) holds graphql-js; fetch it with `tool/fetch_reference.sh` before the conformance tasks. Never `git add` it.

## Review Focus

1. Null propagation: a null or an error at a non-null position nulls the nearest nullable ancestor, the error is recorded once, and `ErrorBehavior.nullValue` / `halt` change exactly that. Tasks 5 and 9 (`null_propagation_test.dart`, `nonnull_test.dart`, `error_propagation_test.dart`).
2. A query with only synchronous resolvers returns a non-`Future`; a failing future never escapes unhandled; errors of resolvers already started still reach the response. Task 5 (`execute_test.dart`, `limits_and_order_test.dart`).
3. Hostile input: a 2000-deep variable value, a 2^20 fragment fan-out, a response deeper than `maxDepth`, a run past `maxSteps`. Tasks 2, 4 and 5 (`input_coercion_test.dart`, `field_collection_test.dart`, `limits_and_order_test.dart`).
4. The plan cache: keyed by `Document` identity, operation name and `includesSuggestions`; LRU eviction; request errors never cached; condition keys per plan bounded. Tasks 4 and 6 (`plan_cache_test.dart`, `abstract_types_test.dart`).
5. Masking: an unexpected error becomes `Unexpected error.` with `GQL330` unless `maskErrors` is false; `GraphQLException` passes through; a throwing `onError` gives the masked error. Task 5 (`error_reporting_test.dart`).
6. Middleware: composed once at build in the order global, field, directive; an empty chain keeps the very same resolver; the pure lane has none. Task 7 (`middleware_test.dart`).

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql_server/lib/src/coercion/coercion_environment.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart` | Create | 2, 9 |
| `packages/typed_graphql_server/lib/src/coercion/coercion_problems.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/coercion_result.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/input_coercion.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart` | Create | 2, 3 |
| `packages/typed_graphql_server/lib/src/coercion/input_path.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/invalid_value.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart` | Create | 2, 3 |
| `packages/typed_graphql_server/lib/src/coercion/unexpected_input_error.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/value_coercion.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/value_inspector.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/variable_coercion.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/variable_coercion_result.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/variable_errors.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/execution/graphql_exception.dart` | Create | 2 |
| `packages/typed_graphql_server/test/coercion/coercion_fixture.dart` | Create | 2, 3 |
| `packages/typed_graphql_server/test/coercion/graphql_exception_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/coercion/input_coercion_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/coercion/value_inspector_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/coercion/variable_coercion_test.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart` | Create | 3, 9 |
| `packages/typed_graphql_server/lib/src/coercion/conditional_directives.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/coercion/input_messages.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart` | Create | 3, 11 |
| `packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart` | Create | 3, 11 |
| `packages/typed_graphql_server/lib/src/coercion/object_literal_coercion.dart` | Create | 3 |
| `packages/typed_graphql_server/test/coercion/argument_coercion_test.dart` | Create | 3 |
| `packages/typed_graphql_server/test/coercion/conditional_directives_test.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/plan/condition_key.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/condition_variables.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/defer_directive.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart` | Create | 4, 8, 17 |
| `packages/typed_graphql_server/lib/src/plan/field_collector.dart` | Create | 4, 8 |
| `packages/typed_graphql_server/lib/src/plan/field_plan.dart` | Create | 4, 17 |
| `packages/typed_graphql_server/lib/src/plan/lru_map.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/operation_plan.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/operation_planner.dart` | Create | 4, 6 |
| `packages/typed_graphql_server/lib/src/plan/operation_selection.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/operation_selection_result.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/plan_cache.dart` | Create | 4, 6, 17 |
| `packages/typed_graphql_server/lib/src/plan/plan_context.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/plan_node.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/plan_result.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/plan/value_variables.dart` | Create | 4 |
| `packages/typed_graphql_server/test/plan/field_collection_test.dart` | Create | 4 |
| `packages/typed_graphql_server/test/plan/operation_selection_test.dart` | Create | 4 |
| `packages/typed_graphql_server/test/plan/plan_cache_test.dart` | Create | 4 |
| `packages/typed_graphql_server/test/plan/plan_fixture.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart` | Create | 5, 6, 17 |
| `packages/typed_graphql_server/lib/src/execution/completion_site.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/error_behavior.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/error_hook.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/error_log.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/error_reporter.dart` | Create | 5, 9, 17 |
| `packages/typed_graphql_server/lib/src/execution/execution_limits.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/execution_options.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/execution_run.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/field_execution.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/leaf_completion.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/list_completion.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/object_completion.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/operation_execution.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/execution/pending_values.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/response_path.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/selection_executor.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/serial_fields.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/lib/src/execution/value_completion.dart` | Create | 5 |
| `packages/typed_graphql_server/test/execution/error_reporting_test.dart` | Create | 5, 9 |
| `packages/typed_graphql_server/test/execution/execute_test.dart` | Create | 5, 8 |
| `packages/typed_graphql_server/test/execution/execution_fixture.dart` | Create | 5 |
| `packages/typed_graphql_server/test/execution/limits_and_order_test.dart` | Create | 5, 17 |
| `packages/typed_graphql_server/test/execution/null_propagation_test.dart` | Create | 5 |
| `packages/typed_graphql_server/test/execution/abstract_types_test.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/execution/directive_middleware.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/execution/field_middleware.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/execution/field_resolver.dart` | Create | 7 |
| `packages/typed_graphql_server/lib/src/execution/field_site.dart` | Create | 7 |
| `packages/typed_graphql_server/test/execution/middleware_test.dart` | Create | 7 |
| `packages/typed_graphql_conformance/mapping/execution.csv` | Create | 8, 9, 12, 13, 16, 17 |
| `packages/typed_graphql_conformance/test/execution/executor_errors_test.dart` | Create | 8, 17 |
| `packages/typed_graphql_conformance/test/execution/executor_operations_test.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/execution/executor_rest_test.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/execution/executor_test.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/execution/resolve_test.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/execution/schema_test.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/execution/sync_test.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/support/execution_port.dart` | Create | 8, 12, 13 |
| `packages/typed_graphql_conformance/test/support/unchecked_ref.dart` | Create | 8 |
| `packages/typed_graphql_conformance/test/execution/error_propagation_test.dart` | Create | 9 |
| `packages/typed_graphql_conformance/test/execution/lists_nullability_test.dart` | Create | 9 |
| `packages/typed_graphql_conformance/test/execution/lists_test.dart` | Create | 9, 17 |
| `packages/typed_graphql_conformance/test/execution/mutations_test.dart` | Create | 9 |
| `packages/typed_graphql_conformance/test/execution/nonnull_arguments_test.dart` | Create | 9 |
| `packages/typed_graphql_conformance/test/execution/nonnull_multiple_test.dart` | Create | 9 |
| `packages/typed_graphql_conformance/test/execution/nonnull_test.dart` | Create | 9, 17 |
| `packages/typed_graphql_conformance/test/support/list_field_schema.dart` | Create | 9 |
| `packages/typed_graphql_conformance/test/support/non_null_schema.dart` | Create | 9 |
| `packages/typed_graphql/lib/src/protocol/json_inspector.dart` | Create | 10 |
| `packages/typed_graphql/test/protocol/json_inspector_test.dart` | Create | 10 |
| `packages/typed_graphql_server/lib/src/coercion/variable_literal_json.dart` | Create | 11 |
| `packages/typed_graphql_server/test/coercion/variable_literal_json_test.dart` | Create | 11 |
| `packages/typed_graphql_conformance/test/execution/coerce_input_literal_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/coerce_input_value_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/oneof_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/validate_input_literal_oneof_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/validate_input_literal_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/validate_input_value_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/variables_lists_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/variables_objects_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/variables_scalars_test.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/support/input_probe.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/support/js_inspect.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/support/variables_schema.dart` | Create | 12 |
| `packages/typed_graphql_conformance/test/execution/abstract_test.dart` | Create | 13 |
| `packages/typed_graphql_conformance/test/execution/directives_test.dart` | Create | 13 |
| `packages/typed_graphql_conformance/test/execution/enum_type_test.dart` | Create | 13 |
| `packages/typed_graphql_conformance/test/execution/union_interface_test.dart` | Create | 13 |
| `packages/typed_graphql_server/example/example.dart` | Create | 15 |
| `packages/typed_graphql_server/test/doc/example_test.dart` | Create | 15 |
| `packages/typed_graphql_server/test/execution/completion_failures_test.dart` | Create | 17 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1, 10 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 2, 4, 5, 7, 15, 17 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 2, 5, 7 |
| `packages/typed_graphql_server/lib/src/builder/build_options.dart` | Modify | 4, 7 |
| `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart` | Modify | 4, 7 |
| `packages/typed_graphql_server/lib/src/execution/executable_schema.dart` | Modify | 4, 5 |
| `packages/typed_graphql_server/doc/execution.md` | Modify | 5, 15, 17 |
| `packages/typed_graphql_server/lib/src/execution/field_info.dart` | Modify | 5 |
| `packages/typed_graphql_server/test/builder/fields_test.dart` | Modify | 5, 17 |
| `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart` | Modify | 7 |
| `packages/typed_graphql_server/lib/src/builder/field_def.dart` | Modify | 7 |
| `packages/typed_graphql_server/lib/src/builder/field_stub.dart` | Modify | 7 |
| `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart` | Modify | 7 |
| `packages/typed_graphql_conformance/pubspec.yaml` | Modify | 8 |
| `packages/typed_graphql_conformance/test/mapping_test.dart` | Modify | 8, 9, 12, 13 |
| `packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart` | Modify | 10 |
| `packages/typed_graphql/lib/src/schema/scalars/float_codec.dart` | Modify | 10 |
| `packages/typed_graphql/lib/src/schema/scalars/id_codec.dart` | Modify | 10 |
| `packages/typed_graphql/lib/src/schema/scalars/int_codec.dart` | Modify | 10 |
| `packages/typed_graphql/lib/src/schema/scalars/string_codec.dart` | Modify | 10 |
| `docs/superpowers/specs/2026-10-15-m5-execution-design.md` | Modify | 14 |
| `CLAUDE.md` | Modify | 15, 17 |
| `README.md` | Modify | 15 |
| `docs/discovery.md` | Modify | 15 |
| `docs/superpowers/HANDOFF.md` | Modify | 15 |
| `llms.txt` | Modify | 15 |
| `packages/typed_graphql/README.md` | Modify | 15 |
| `packages/typed_graphql_server/README.md` | Modify | 15 |
| `packages/typed_graphql_server/doc/schema_builder.md` | Modify | 15 |
| `packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart` | Modify | 17 |

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

### Task 1: The M5b diagnostic codes (core)

Add `GQL310`-`GQL314` (coercion), `GQL320`-`GQL323` (operation selection) and `GQL330`-`GQL337` (execution) to the catalog, with doc comments saying when each is reported, and a core CHANGELOG line.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/CHANGELOG.md`

**Interfaces:**
- Consumes: the core as left by M5a.
- Produces:
- Diagnostic codes: `GQL310` (`invalidVariableValue`), `GQL311` (`invalidVariableDefault`), `GQL312` (`tooManyVariableErrors`), `GQL313` (`invalidArgumentValue`), `GQL314` (`inputDecodeFailed`), `GQL320` (`unknownOperation`), `GQL321` (`operationNameRequired`), `GQL322` (`noOperation`), `GQL323` (`unsupportedOperationType`), `GQL330` (`unexpectedError`), `GQL331` (`nullNonNullField`), `GQL332` (`unserializableValue`), `GQL333` (`unresolvedAbstractType`), `GQL334` (`impossibleRuntimeType`), `GQL335` (`unexpectedValue`), `GQL336` (`maxExecutionDepthExceeded`), `GQL337` (`maxExecutionStepsExceeded`).

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -525,4 +525,95 @@ enum DiagnosticCode(
   /// `ExecutableSchemaBuilder` cannot be written as a literal (the codec's
   /// `encode` throws, or an input object has no `encode`).
   unencodableDefaultValue('GQL302'),
+
+  /// `GQL310`: reported when a variable value is invalid, or a required
+  /// variable is missing, as `ExecutableSchema.execute` coerces the variable
+  /// values. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `ExecutableSchema.execute`.
+  invalidVariableValue('GQL310'),
+
+  /// `GQL311`: reported when the default value of a variable cannot be
+  /// coerced (for example a custom scalar rejects the default literal).
+  /// It is a `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  invalidVariableDefault('GQL311'),
+
+  /// `GQL312`: reported when variable coercion stopped because
+  /// `maxCoercionErrors` was reached. It is a `GraphQLError`'s
+  /// `extensions.code` in a response of `ExecutableSchema.execute`.
+  tooManyVariableErrors('GQL312'),
+
+  /// `GQL313`: reported when a field or directive argument cannot be
+  /// coerced at run time. It is a `GraphQLError`'s `extensions.code` in
+  /// a response of `ExecutableSchema.execute`.
+  invalidArgumentValue('GQL313'),
+
+  /// `GQL314`: reported when an input object's `decode` threw something
+  /// other than a `GraphQLException`; the message is masked. It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  inputDecodeFailed('GQL314'),
+
+  /// `GQL320`: reported when the document has no operation with the
+  /// requested name. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `ExecutableSchema.execute`.
+  unknownOperation('GQL320'),
+
+  /// `GQL321`: reported when the document has several operations and no
+  /// operation name was given. It is a `GraphQLError`'s
+  /// `extensions.code` in a response of `ExecutableSchema.execute`.
+  operationNameRequired('GQL321'),
+
+  /// `GQL322`: reported when the document has no operation to execute.
+  /// It is a `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  noOperation('GQL322'),
+
+  /// `GQL323`: reported when the schema has no root type for the
+  /// operation's type. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `ExecutableSchema.execute`.
+  unsupportedOperationType('GQL323'),
+
+  /// `GQL330`: reported when a resolver, codec or decode function threw
+  /// an unexpected error; the message is masked. It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  unexpectedError('GQL330'),
+
+  /// `GQL331`: reported when a resolver returned null for a non-null
+  /// field. It is a `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  nullNonNullField('GQL331'),
+
+  /// `GQL332`: reported when a leaf value cannot be serialized by its
+  /// scalar codec or enum. It is a `GraphQLError`'s `extensions.code` in
+  /// a response of `ExecutableSchema.execute`.
+  unserializableValue('GQL332'),
+
+  /// `GQL333`: reported when no possible type of an abstract type
+  /// accepts the value. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `ExecutableSchema.execute`.
+  unresolvedAbstractType('GQL333'),
+
+  /// `GQL334`: reported when `resolveType` gave a type that is not a
+  /// possible type of the abstract type, or one whose Dart type does not
+  /// hold the value. It is a `GraphQLError`'s `extensions.code` in a
+  /// response of `ExecutableSchema.execute`.
+  impossibleRuntimeType('GQL334'),
+
+  /// `GQL335`: reported when a value of the wrong Dart shape reached
+  /// completion (for example a non-`Iterable` for a list field). It is a
+  /// `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  unexpectedValue('GQL335'),
+
+  /// `GQL336`: reported when the response is deeper than `maxDepth`. It
+  /// is a `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  maxExecutionDepthExceeded('GQL336'),
+
+  /// `GQL337`: reported when execution used more steps than `maxSteps`.
+  /// It is a `GraphQLError`'s `extensions.code` in a response of
+  /// `ExecutableSchema.execute`.
+  maxExecutionStepsExceeded('GQL337'),
 }
```

- [ ] **Step 2: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `GQL310`-`GQL337`: the diagnostics of execution (variable and argument coercion, operation selection, completion errors, limits); they are the `extensions.code` of the errors `ExecutableSchema.execute` returns.
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
git commit -q -m "feat(typed_graphql): add the M5b diagnostic codes" \
  -m "GQL310-GQL337: variable and argument coercion, operation selection, completion errors and execution limits." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Variable coercion

Add `GraphQLException` (exported) and the internal coercion of JSON input values (`ValueInspector`, `InputCoercion`, `LeafCoercion`, `InputObjectCoercion`, `InputPath`, `CoercionProblem`) and of an operation's variables (`VariableCoercion`, `VariableCoercionResult`), with graphql-js's messages, `@oneOf`, defaults from literals, `maxCoercionErrors` and the 1000-level bound.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/coercion/coercion_environment.dart`, `packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart`, `packages/typed_graphql_server/lib/src/coercion/coercion_problems.dart`, `packages/typed_graphql_server/lib/src/coercion/coercion_result.dart`, `packages/typed_graphql_server/lib/src/coercion/input_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/input_path.dart`, `packages/typed_graphql_server/lib/src/coercion/invalid_value.dart`, `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/unexpected_input_error.dart`, `packages/typed_graphql_server/lib/src/coercion/value_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/value_inspector.dart`, `packages/typed_graphql_server/lib/src/coercion/variable_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/variable_coercion_result.dart`, `packages/typed_graphql_server/lib/src/coercion/variable_errors.dart`, `packages/typed_graphql_server/lib/src/execution/graphql_exception.dart`
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/coercion/coercion_fixture.dart`, `packages/typed_graphql_server/test/coercion/graphql_exception_test.dart`, `packages/typed_graphql_server/test/coercion/input_coercion_test.dart`, `packages/typed_graphql_server/test/coercion/value_inspector_test.dart`, `packages/typed_graphql_server/test/coercion/variable_coercion_test.dart`

**Interfaces:**
- Consumes: M5a's refs, `Arguments`, `InputObjectDef`, `EnumTypeDef` and `SchemaBindings`; the core's `Suggestions` and `LiteralConverter`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// coercion/coercion_environment.dart
final class CoercionEnvironment(…)

// coercion/coercion_problem.dart
final class CoercionProblem(…)

// coercion/coercion_problems.dart
final class CoercionProblems
  CoercionProblems(this.limit)
  void add(…)

// coercion/coercion_result.dart
sealed class CoercionResult
final class CoercionSuccess
final class CoercionFailure
  CoercionFailure(…)

// coercion/input_coercion.dart
final class InputCoercion
  InputCoercion(…)
  bool isInputType(TypeRef type)
  CoercionResult coerceValue(…)
  CoercionResult coerceLiteral(…)

// coercion/input_object_coercion.dart
final class InputObjectCoercion
  InputObjectCoercion(this.environment, this.problems, this.values)
  Object? coerce(…)

// coercion/input_path.dart
final class InputPath
  InputPath key(String name)
  InputPath index(int position)
  List<PathSegment> get segments
  String get description

// coercion/invalid_value.dart
final class InvalidValue

// coercion/leaf_coercion.dart
final class LeafCoercion
  LeafCoercion(this.environment, this.problems)
  Object? coerce(JsonValue value, SchemaType type, InputPath path)

// coercion/unexpected_input_error.dart
final class UnexpectedInputError(…)

// coercion/value_coercion.dart
final class ValueCoercion
  ValueCoercion(this.environment, this.problems)
  Object? coerce(JsonValue value, TypeRef type, InputPath path, int depth)

// coercion/value_inspector.dart
final class ValueInspector
  String inspect(Object? value)

// coercion/variable_coercion.dart
final class VariableCoercion
  VariableCoercion(…)
  VariableCoercionResult coerce(…)

// coercion/variable_coercion_result.dart
sealed class VariableCoercionResult
final class CoercedVariables
  CoercedVariables(Map<String, Object?> values)
final class VariableCoercionFailure
  VariableCoercionFailure(…)

// coercion/variable_errors.dart
final class VariableErrors
  VariableErrors(this.maxErrors, this.source)
  int get remaining
  void report(String message, DiagnosticCode code, int? offset)
  void reportFailure(…)
  void stop()

// execution/graphql_exception.dart
final class GraphQLException
  String toString()
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/coercion/coercion_fixture.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_problem.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/coercion/input_coercion.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Color { red, green }

final class ComplexScalarCodec implements ScalarCodec<String> {
  const ComplexScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(value: 'ExternalValue') => const DecodeSuccess('InternalValue'),
    _ => const DecodeFailure('ComplexScalar must be ExternalValue'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}

final class FaultyScalarCodec implements ScalarCodec<String> {
  const FaultyScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) =>
      const DecodeFailure('FaultyScalarErrorMessage');

  @override
  JsonValue encode(String value) => JsonString(value);
}

final class ThrowingScalarCodec implements ScalarCodec<String> {
  const ThrowingScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => throw StateError('codec bug');

  @override
  JsonValue encode(String value) => JsonString(value);
}

/// The schema the coercion tests run against, and parsing helpers.
final class CoercionFixture {
  CoercionFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final complex = b.scalar<String>(
      'ComplexScalar',
      const ComplexScalarCodec(),
    );
    final faulty = b.scalar<String>('FaultyScalar', const FaultyScalarCodec());
    final throwing = b.scalar<String>(
      'ThrowingScalar',
      const ThrowingScalarCodec(),
    );
    final color = b.enumType<Color>(
      'Color',
      Color.values,
      mapping: EnumValueMapping<Color>(nameOf: (value) => value.name),
    );
    final a = Arg('a', b.string.nullable);
    final list = Arg('b', b.inputList(b.string.nullable).nullable);
    final c = Arg('c', b.string);
    final d = Arg('d', complex.nullable);
    final e = Arg('e', faulty.nullable);
    final testInput = b.inputObject<Map<String, Object?>>(
      'TestInputObject',
      fields: () => [a, list, c, d, e],
      decode: (values) => {
        'a': values.get(a),
        'b': values.get(list),
        'c': values.get(c),
        'd': values.get(d),
        'e': values.get(e),
      },
    );
    final na = Arg('na', testInput);
    final nb = Arg('nb', b.string);
    final nested = b.inputObject<List<Object?>>(
      'TestNestedInputObject',
      fields: () => [na, nb],
      decode: (values) => [values.get(na), values.get(nb)],
    );
    final count = Arg('count', b.int, defaultValue: 5);
    final shade = Arg('shade', color, defaultValue: Color.green);
    final tags = Arg('tags', b.inputList(b.string.nullable).nullable);
    final defaulted = b.inputObject<Map<String, Object?>>(
      'Defaulted',
      fields: () => [count, shade, tags],
      decode: (values) => {
        'count': values.get(count),
        'shade': values.get(shade),
        'tags': values.get(tags),
      },
    );
    final lookupId = Arg('id', b.int.nullable);
    final lookupEmail = Arg('email', b.string.nullable);
    final lookup = b.oneOfInputObject<String>(
      'Lookup',
      fields: () => [lookupId, lookupEmail],
      decode: (values) => '${values.get(lookupId)}/${values.get(lookupEmail)}',
    );
    late final InputObjectDef<String> chain;
    chain = b.inputObject<String>(
      'Chain',
      fields: () => [Arg('next', chain.nullable)],
      decode: (values) => 'link',
    );
    final exploding = b.inputObject<String>(
      'Exploding',
      fields: () => [Arg('x', b.int.nullable)],
      decode: (_) => throw GraphQLException(
        'refused',
        extensions: JsonObject({'reason': const JsonString('policy')}),
      ),
    );
    final crashing = b.inputObject<String>(
      'Crashing',
      fields: () => [Arg('x', b.int.nullable)],
      decode: (_) => throw StateError('secret detail'),
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field(
              'probe',
              b.string.nullable,
              args: [
                Arg('input', testInput.nullable),
                Arg('nested', nested.nullable),
                Arg('defaulted', defaulted.nullable),
                Arg('lookup', lookup.nullable),
                Arg('chain', chain.nullable),
              ],
            )
            .resolve((parent, args, context, info) => null),
        t
            .field(
              'more',
              b.string.nullable,
              args: [
                Arg('exploding', exploding.nullable),
                Arg('crashing', crashing.nullable),
                Arg('throwing', throwing.nullable),
              ],
            )
            .resolve((parent, args, context, info) => null),
      ],
    );
    final built = b.build(query: query);
    schema = built.schema.schema;
    coercion = InputCoercion(schema, built.bindings);
    hiddenSuggestions = InputCoercion(
      schema,
      built.bindings,
      includesSuggestions: false,
    );
  }

  late final Schema schema;
  late final InputCoercion coercion;
  late final InputCoercion hiddenSuggestions;

  TypeRef type(String text) =>
      switch (const Parser().parseTypeRef(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure() => throw ArgumentError('bad type $text'),
      };

  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    DecodeFailure(:final message) => throw ArgumentError(message),
  };

  /// The variable definitions of the only operation of [text].
  List<VariableDefinition> variables(String text) => [
    for (final definition
        in const Parser().parse(Source(text)).requireDocument().definitions)
      if (definition is OperationDefinition) ...definition.variableDefinitions,
  ];

  /// `where: message` of each problem.
  List<String> texts(List<CoercionProblem> problems) => [
    for (final problem in problems) '${problem.where}: ${problem.message}',
  ];

  /// Coerces a `Chain` value nested [depth] levels deep.
  CoercionResult chain(int depth) {
    JsonValue value = JsonObject({});
    for (var i = 0; i < depth; i++) {
      value = JsonObject({'next': value});
    }
    return coercion.coerceValue(value, type('Chain'));
  }
}
```

Create `packages/typed_graphql_server/test/coercion/graphql_exception_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  group('GraphQLException', () {
    test('is an Exception', () {
      expect(const GraphQLException('x'), isA<Exception>());
    });

    test('toString is the message', () {
      expect(const GraphQLException('Not allowed.').toString(), 'Not allowed.');
    });

    test('keeps its extensions', () {
      final exception = GraphQLException(
        'x',
        extensions: JsonObject({'code': const JsonString('E')}),
      );
      expect(exception.extensions, JsonObject({'code': const JsonString('E')}));
    });

    test('has no extensions by default', () {
      expect(const GraphQLException('x').extensions, isNull);
    });
  });
}
```

Create `packages/typed_graphql_server/test/coercion/input_coercion_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();
  const oneOfMessage =
      ': Within OneOf Input Object type "Lookup", exactly one field must be '
      'specified, and the value for that field must be non-null.';

  CoercionResult coerce(String type, String json) =>
      fx.coercion.coerceValue(fx.json(json), fx.type(type));

  Object? valueOf(String type, String json) => switch (coerce(type, json)) {
    CoercionSuccess(:final value) => value,
    CoercionFailure(:final problems) => fail('failed: ${fx.texts(problems)}'),
  };

  List<String> problemsOf(String type, String json) =>
      switch (coerce(type, json)) {
        CoercionSuccess() => fail('expected a failure'),
        CoercionFailure(:final problems) => fx.texts(problems),
      };

  group('lists and null', () {
    test('a single value stands for a list of one', () {
      expect(valueOf('[String]', '"bar"'), ['bar']);
    });

    test('a list keeps its null items when the item type allows them', () {
      expect(valueOf('[String]', '["a", null]'), ['a', null]);
    });

    test('null is null for a nullable type', () {
      expect(valueOf('String', 'null'), isNull);
    });

    test('null for a non-null type is reported', () {
      expect(problemsOf('String!', 'null'), [
        ': Expected value of non-null type "String!" not to be null.',
      ]);
    });

    test('null for a non-null list is reported with the list type', () {
      expect(problemsOf('[String]!', 'null'), [
        ': Expected value of non-null type "[String]!" not to be null.',
      ]);
    });

    test('null in a list of non-null items is reported with its index', () {
      expect(problemsOf('[String!]', '["a", null]'), [
        ' at [1]: Expected value of non-null type "String!" not to be null.',
      ]);
    });
  });

  group('leaves', () {
    test('a custom scalar decodes through its codec', () {
      expect(valueOf('ComplexScalar', '"ExternalValue"'), 'InternalValue');
    });

    test('the message of a codec failure is used as it is', () {
      expect(problemsOf('FaultyScalar', '"x"'), [': FaultyScalarErrorMessage']);
    });

    test('a built-in scalar failure uses the codec message', () {
      expect(problemsOf('String', '123'), [
        ': String cannot represent a non string value: 123',
      ]);
    });

    test('an enum value is read by name', () {
      expect(valueOf('Color', '"green"'), Color.green);
    });

    test('an unknown enum value is reported, with a suggestion', () {
      expect(problemsOf('Color', '"GREEN"'), [
        ': Value "GREEN" does not exist in "Color" enum. '
            'Did you mean the enum value "green" or "red"?',
      ]);
    });

    test('suggestions can be left out', () {
      final result = fx.hiddenSuggestions.coerceValue(
        fx.json('"GREEN"'),
        fx.type('Color'),
      );
      expect(
        fx.texts((result as CoercionFailure).problems),
        [': Value "GREEN" does not exist in "Color" enum.'],
      );
    });

    test('a non-string enum value is reported with its printed form', () {
      expect(problemsOf('Color', '1'), [
        ': Enum "Color" cannot represent non-string value: 1.',
      ]);
    });

    test('a codec that throws is a masked problem with its cause', () {
      final result = coerce('ThrowingScalar', '"x"') as CoercionFailure;
      expect(result.problems.single.message, 'Unexpected error.');
      expect(result.problems.single.code, DiagnosticCode.unexpectedError);
      expect(result.problems.single.thrown?.error, isA<StateError>());
    });
  });

  group('input objects', () {
    test('a complete object is decoded', () {
      expect(
        valueOf('TestInputObject', '{"a":"foo","b":["bar"],"c":"baz"}'),
        {
          'a': 'foo',
          'b': ['bar'],
          'c': 'baz',
          'd': null,
          'e': null,
        },
      );
    });

    test('a field with a custom scalar goes through its codec', () {
      expect(
        (valueOf('TestInputObject', '{"c":"x","d":"ExternalValue"}')
            as Map<String, Object?>)['d'],
        'InternalValue',
      );
    });

    test('a faulty scalar field is reported with its path', () {
      expect(problemsOf('TestInputObject', '{"c":"x","e":"v"}'), [
        ' at .e: FaultyScalarErrorMessage',
      ]);
    });

    test('null for a nested non-null field is reported at the field', () {
      expect(problemsOf('TestInputObject', '{"a":"foo","c":null}'), [
        ' at .c: Expected value of non-null type "String!" not to be null.',
      ]);
    });

    test('a value that is not an object is reported', () {
      expect(problemsOf('TestInputObject', '"foo bar"'), [
        ': Expected value of type "TestInputObject" to be an object, '
            'found: "foo bar".',
      ]);
    });

    test('a list is not an object', () {
      expect(problemsOf('TestInputObject', '["foo","bar","baz"]'), [
        ': Expected value of type "TestInputObject" to be an object, '
            'found: ["foo", "bar", "baz"].',
      ]);
    });

    test('a missing required field is reported with the object', () {
      expect(problemsOf('TestInputObject', '{"a":"foo","b":["bar"]}'), [
        ': Expected value of type "TestInputObject" to include required '
            'field "c", found: { a: "foo", b: ["bar"] }.',
      ]);
    });

    test('nested problems come before the problems of the parent', () {
      expect(problemsOf('TestNestedInputObject', '{"na":{"a":"foo"}}'), [
        ' at .na: Expected value of type "TestInputObject" to include '
            'required field "c", found: { a: "foo" }.',
        ': Expected value of type "TestNestedInputObject" to include '
            'required field "nb", found: { na: { a: "foo" } }.',
      ]);
    });

    test('an unknown field is reported', () {
      expect(
        problemsOf(
          'TestInputObject',
          '{"a":"foo","b":"bar","c":"baz","extra":"dog"}',
        ),
        [
          ': Expected value of type "TestInputObject" not to include '
              'unknown field "extra", found: '
              '{ a: "foo", b: "bar", c: "baz", extra: "dog" }.',
        ],
      );
    });

    test('an unknown field gets a suggestion', () {
      expect(problemsOf('TestInputObject', '{"c":"ok","aa":"x"}'), [
        ': Expected value of type "TestInputObject" not to include '
            'unknown field "aa". Did you mean "a"? Found: '
            '{ c: "ok", aa: "x" }.',
      ]);
    });

    test('suggestions for unknown fields can be left out', () {
      final result = fx.hiddenSuggestions.coerceValue(
        fx.json('{"c":"ok","aa":"x"}'),
        fx.type('TestInputObject'),
      );
      expect(fx.texts((result as CoercionFailure).problems), [
        ': Expected value of type "TestInputObject" not to include '
            'unknown field "aa", found: { c: "ok", aa: "x" }.',
      ]);
    });

    test('missing fields take their coerced defaults', () {
      expect(valueOf('Defaulted', '{}'), {
        'count': 5,
        'shade': Color.green,
        'tags': null,
      });
    });

    test('a given field wins over its default', () {
      expect(
        (valueOf('Defaulted', '{"count":7}') as Map<String, Object?>)['count'],
        7,
      );
    });
  });

  group('input objects with @oneOf', () {
    test('exactly one non-null field is accepted', () {
      expect(valueOf('Lookup', '{"id":1}'), '1/null');
    });

    test('no field is reported', () {
      expect(problemsOf('Lookup', '{}'), [oneOfMessage]);
    });

    test('two fields are reported', () {
      expect(problemsOf('Lookup', '{"id":1,"email":"a"}'), [oneOfMessage]);
    });

    test('a null field is reported at the field', () {
      expect(problemsOf('Lookup', '{"id":null}'), [' at .id$oneOfMessage']);
    });
  });

  group('decode', () {
    test('a GraphQLException becomes a problem with its message', () {
      final result = coerce('Exploding', '{}') as CoercionFailure;
      expect(result.problems.single.message, 'refused');
      expect(
        result.problems.single.extensions,
        JsonObject({'reason': const JsonString('policy')}),
      );
      expect(result.problems.single.code, isNull);
    });

    test('any other error is masked, coded GQL314 and kept as the cause', () {
      final result = coerce('Crashing', '{}') as CoercionFailure;
      expect(result.problems.single.message, 'Unexpected error.');
      expect(result.problems.single.code, DiagnosticCode.inputDecodeFailed);
      expect(result.problems.single.thrown?.error, isA<StateError>());
    });
  });

  group('limits', () {
    test(
      'at most maxProblems problems are kept, and the overflow is noted',
      () {
        final items = List.filled(100, '"x"').join(',');
        final result = fx.coercion.coerceValue(
          fx.json('[$items]'),
          fx.type('[Int]'),
          maxProblems: 3,
        ) as CoercionFailure;
        expect(result.problems, hasLength(3));
        expect(result.hasOverflowed, isTrue);
      },
    );

    test('a value nested 900 levels deep is coerced', () {
      expect(fx.chain(900), isA<CoercionSuccess>());
    });

    test('a value nested 2000 levels deep is one problem, not a crash', () {
      final result = fx.chain(2000) as CoercionFailure;
      expect(result.problems.map((problem) => problem.message), [
        'Input value is nested too deeply.',
      ]);
    });
  });

  group('literals', () {
    test('an enum literal is read by name', () {
      final result = fx.coercion.coerceLiteral(
        const EnumValue('red'),
        fx.type('Color'),
      );
      expect((result as CoercionSuccess).value, Color.red);
    });

    test('a variable in a literal is a problem', () {
      final result = fx.coercion.coerceLiteral(
        const Variable(Name('x')),
        fx.type('Int'),
      ) as CoercionFailure;
      expect(result.problems.single.message, contains(r'"$x"'));
    });
  });
}
```

Create `packages/typed_graphql_server/test/coercion/value_inspector_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/value_inspector.dart';

void main() {
  const inspector = ValueInspector();

  group('ValueInspector of Dart values', () {
    test('quotes strings as JSON', () {
      expect(inspector.inspect('a "b"'), r'"a \"b\""');
    });

    test('escapes control characters as JSON does', () {
      expect(inspector.inspect('a\nb\u0001\\'), r'"a\nb\u0001\\"');
    });

    test('prints null, booleans and numbers plainly', () {
      expect(
        [null, true, 3, 1.5, 2.0].map(inspector.inspect).toList(),
        ['null', 'true', '3', '1.5', '2'],
      );
    });

    test('prints an object as { key: value }', () {
      expect(inspector.inspect({'a': 1, 'b': 'x'}), '{ a: 1, b: "x" }');
    });

    test('prints empty containers compactly', () {
      expect(inspector.inspect(<Object?>[]), '[]');
      expect(inspector.inspect(<String, Object?>{}), '{}');
    });

    test('prints a list as [a, b]', () {
      expect(inspector.inspect([1, 'x', null]), '[1, "x", null]');
    });

    test('cuts a list after ten items, with the count left', () {
      expect(
        inspector.inspect(List<int>.generate(12, (i) => i)),
        '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, ... 2 more items]',
      );
    });

    test('says "1 more item" for exactly one left', () {
      expect(
        inspector.inspect(List<int>.generate(11, (i) => i)),
        '[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, ... 1 more item]',
      );
    });

    test('prints nesting deeper than two levels as [Object] or [Array]', () {
      expect(
        inspector.inspect({
          'a': {
            'b': {'c': 1},
          },
        }),
        '{ a: { b: [Object] } }',
      );
      expect(
        inspector.inspect([
          [
            [1],
          ],
        ]),
        '[[[Array]]]',
      );
    });
  });

  group('ValueInspector of JSON values', () {
    test('reads a JsonValue like the plain value', () {
      final value = JsonObject({
        'a': JsonArray([
          JsonNumber(1),
          const JsonString('x'),
          const JsonNull(),
        ]),
        'b': const JsonBool(false),
      });
      expect(inspector.inspect(value), '{ a: [1, "x", null], b: false }');
    });

    test('cuts a JSON list after ten items', () {
      final value = JsonArray([for (var i = 0; i < 13; i++) JsonNumber(i)]);
      expect(inspector.inspect(value), endsWith(', ... 3 more items]'));
    });

    test('does not walk a value nested far deeper than it prints', () {
      JsonValue value = JsonNumber(1);
      for (var i = 0; i < 5000; i++) {
        value = JsonArray([value]);
      }
      expect(inspector.inspect(value), '[[[Array]]]');
    });
  });
}
```

Create `packages/typed_graphql_server/test/coercion/variable_coercion_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/variable_coercion.dart';
import 'package:typed_graphql_server/src/coercion/variable_coercion_result.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();

  VariableCoercionResult run(
    String query,
    String? variables, {
    int maxErrors = 50,
  }) => VariableCoercion(fx.coercion, maxCoercionErrors: maxErrors).coerce(
    fx.variables(query),
    variables == null ? null : fx.json(variables) as JsonObject,
    source: Source(query),
  );

  Map<String, Object?> valuesOf(String query, String? variables) =>
      switch (run(query, variables)) {
        CoercedVariables(:final values) => values,
        VariableCoercionFailure(:final errors) => fail(
          'failed: ${errors.map((error) => error.message).toList()}',
        ),
      };

  List<GraphQLError> errorsOf(
    String query,
    String? variables, {
    int maxErrors = 50,
  }) => switch (run(query, variables, maxErrors: maxErrors)) {
    CoercedVariables() => fail('expected errors'),
    VariableCoercionFailure(:final errors) => errors,
  };

  List<String> messagesOf(String query, String? variables) => [
    for (final error in errorsOf(query, variables)) error.message,
  ];

  group('values', () {
    test('coerces a provided value', () {
      expect(
        valuesOf(r'query ($value: Int) { a }', '{"value": 3}'),
        {'value': 3},
      );
    });

    test('omits a nullable variable that was not provided', () {
      expect(valuesOf(r'query ($value: String) { a }', '{}'), isEmpty);
    });

    test('works without any variables object', () {
      expect(valuesOf(r'query ($value: String) { a }', null), isEmpty);
    });

    test('keeps an explicit null', () {
      expect(
        valuesOf(r'query ($value: String) { a }', '{"value": null}'),
        {'value': null},
      );
    });

    test('uses the default when the variable is not provided', () {
      expect(
        valuesOf(r'query ($value: String = "default") { a }', '{}'),
        {'value': 'default'},
      );
    });

    test('uses a null default', () {
      expect(
        valuesOf(r'query ($value: String = null) { a }', '{}'),
        {'value': null},
      );
    });

    test('prefers the provided value over the default', () {
      expect(
        valuesOf(r'query ($value: String = "d") { a }', '{"value": "v"}'),
        {'value': 'v'},
      );
    });

    test('an explicit null replaces the default', () {
      expect(
        valuesOf(r'query ($value: String = "d") { a }', '{"value": null}'),
        {'value': null},
      );
    });

    test('a non-null variable is satisfied by its default', () {
      expect(
        valuesOf(r'query ($value: String! = "d") { a }', '{}'),
        {'value': 'd'},
      );
    });

    test('a single value is a list of one', () {
      expect(
        valuesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar", "c": "baz"}}',
        ),
        {
          'input': {
            'a': 'foo',
            'b': ['bar'],
            'c': 'baz',
            'd': null,
            'e': null,
          },
        },
      );
    });

    test('an object default is coerced from its literal', () {
      final values = valuesOf(
        r'query ($input: TestInputObject = {a: "foo", b: ["bar"], c: "baz"}) { a }',
        '{}',
      );
      expect((values['input']! as Map<String, Object?>)['c'], 'baz');
    });
  });

  group('invalid values', () {
    test('a missing required variable', () {
      final errors = errorsOf(r'query ($value: String!) { a }', '{}');
      expect(
        errors.single.message,
        r'Variable "$value" has invalid value: Expected a value of '
        'non-null type "String!" to be provided.',
      );
      expect(errors.single.locations.single.line, 1);
      expect(errors.single.locations.single.column, 8);
      expect(
        errors.single.extensions,
        JsonObject({
          'code': JsonString(DiagnosticCode.invalidVariableValue.id),
        }),
      );
    });

    test('null for a non-null variable', () {
      expect(messagesOf(r'query ($value: String!) { a }', '{"value": null}'), [
        r'Variable "$value" has invalid value: Expected value of non-null '
            'type "String!" not to be null.',
      ]);
    });

    test('null for a non-null list', () {
      expect(
        messagesOf(r'query ($input: [String]!) { a }', '{"input": null}'),
        [
          r'Variable "$input" has invalid value: Expected value of '
              'non-null type "[String]!" not to be null.',
        ],
      );
    });

    test('null in a list of non-null items', () {
      expect(
        messagesOf(
          r'query ($input: [String!]) { a }',
          '{"input": ["A", null, "B"]}',
        ),
        [
          r'Variable "$input" has invalid value at [1]: Expected value of '
              'non-null type "String!" not to be null.',
        ],
      );
    });

    test('a value of the wrong scalar type', () {
      expect(messagesOf(r'query ($value: String!) { a }', '{"value": 123}'), [
        r'Variable "$value" has invalid value: String cannot represent a '
            'non string value: 123',
      ]);
    });

    test('a value that is not an object', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": "foo bar"}',
        ),
        [
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestInputObject" to be an object, found: "foo bar".',
        ],
      );
    });

    test('a faulty scalar field names its path', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"c": "foo", "e": "ExternalValue"}}',
        ),
        [
          r'Variable "$input" has invalid value at .e: FaultyScalarErrorMessage',
        ],
      );
    });

    test('null for a nested non-null field', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar", "c": null}}',
        ),
        [
          r'Variable "$input" has invalid value at .c: Expected value of '
              'non-null type "String!" not to be null.',
        ],
      );
    });

    test('an omitted nested required field', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar"}}',
        ),
        [
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestInputObject" to include required field "c", found: '
              '{ a: "foo", b: "bar" }.',
        ],
      );
    });

    test('deep nested errors are all reported', () {
      expect(
        messagesOf(
          r'query ($input: TestNestedInputObject) { a }',
          '{"input": {"na": {"a": "foo"}}}',
        ),
        [
          r'Variable "$input" has invalid value at .na: Expected value of '
              'type "TestInputObject" to include required field "c", found: '
              '{ a: "foo" }.',
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestNestedInputObject" to include required field "nb", '
              'found: { na: { a: "foo" } }.',
        ],
      );
    });

    test('an unknown input field', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject) { a }',
          '{"input": {"a": "foo", "b": "bar", "c": "baz", "extra": "dog"}}',
        ),
        [
          r'Variable "$input" has invalid value: Expected value of type '
              '"TestInputObject" not to include unknown field "extra", '
              'found: { a: "foo", b: "bar", c: "baz", extra: "dog" }.',
        ],
      );
    });

    test('an enum name that does not exist', () {
      expect(messagesOf(r'query ($c: Color) { a }', '{"c": "blue"}'), [
        r'Variable "$c" has invalid value: Value "blue" does not exist in '
            '"Color" enum.',
      ]);
    });

    test('a type that is not an input type', () {
      final errors = errorsOf(r'query ($input: Query!) { a }', '{}');
      expect(
        errors.single.message,
        r'Variable "$input" expected value of type "Query!" which cannot '
        'be used as an input type.',
      );
      expect(errors.single.locations.single.column, 16);
    });

    test('an unknown type', () {
      expect(messagesOf(r'query ($input: UnknownType!) { a }', '{}'), [
        r'Variable "$input" expected value of type "UnknownType!" which '
            'cannot be used as an input type.',
      ]);
    });

    test('an error of decode keeps its extensions and has no GQL code', () {
      final errors = errorsOf(r'query ($x: Exploding) { a }', '{"x": {}}');
      expect(
        errors.single.message,
        r'Variable "$x" has invalid value: refused',
      );
      expect(
        errors.single.extensions,
        JsonObject({'reason': const JsonString('policy')}),
      );
    });

    test('an error thrown by decode is masked, coded GQL314 and reported', () {
      final result = run(
        r'query ($x: Crashing) { a }',
        '{"x": {}}',
      ) as VariableCoercionFailure;
      expect(
        result.errors.single.message,
        r'Variable "$x" has invalid value: Unexpected error.',
      );
      expect(
        result.errors.single.extensions,
        JsonObject({'code': JsonString(DiagnosticCode.inputDecodeFailed.id)}),
      );
      expect(result.unexpected.single.error, isA<StateError>());
      expect(result.unexpected.single.reported, result.errors.single);
    });
  });

  group('invalid defaults', () {
    test('a default of the wrong type is GQL311 at the definition', () {
      final errors = errorsOf(r'query ($input: String = 123) { a }', '{}');
      expect(
        errors.single.message,
        r'Variable "$input" has invalid default value: String cannot '
        'represent a non string value: 123',
      );
      expect(errors.single.locations.single.column, 8);
      expect(
        errors.single.extensions,
        JsonObject({
          'code': JsonString(DiagnosticCode.invalidVariableDefault.id),
        }),
      );
    });

    test('a default with an unknown field names it, with a suggestion', () {
      expect(
        messagesOf(
          r'query ($input: TestInputObject = {c: "ok", aa: "x"}) { a }',
          '{}',
        ),
        [
          r'Variable "$input" has invalid default value: Expected value of '
              'type "TestInputObject" not to include unknown field "aa". '
              'Did you mean "a"? Found: { c: "ok", aa: "x" }.',
        ],
      );
    });

    test('a default of a custom scalar that its codec rejects', () {
      expect(messagesOf(r'query ($v: ComplexScalar = "nope") { a }', '{}'), [
        r'Variable "$v" has invalid default value: ComplexScalar must be '
            'ExternalValue',
      ]);
    });

    test('a default is not used when the value is given and invalid', () {
      expect(
        messagesOf(r'query ($v: Int = 1) { a }', '{"v": "x"}'),
        [
          r'Variable "$v" has invalid value: Int cannot represent non-integer '
              'value: "x"',
        ],
      );
    });
  });

  group('the error limit', () {
    const query = r'query ($input: [String!]) { a }';
    final values =
        '{"input": [${List.generate(4, (i) => '${i + 1}').join(',')}]}';

    String message(int index) =>
        'Variable "\$input" has invalid value at [$index]: '
        'String cannot represent a non string value: ${index + 1}';

    test('keeps every error below the limit', () {
      expect(messagesOf(query, values), [
        for (var i = 0; i < 4; i++) message(i),
      ]);
    });

    test('keeps the errors when exactly at the limit', () {
      final errors = errorsOf(query, values, maxErrors: 4);
      expect(errors.map((error) => error.message), [
        for (var i = 0; i < 4; i++) message(i),
      ]);
    });

    test('cuts after the limit with one "Too many errors" error', () {
      final errors = errorsOf(query, values, maxErrors: 2);
      expect(errors.map((error) => error.message), [
        message(0),
        message(1),
        'Too many errors processing variables, error limit reached. '
            'Execution aborted.',
      ]);
      expect(
        errors.last.extensions,
        JsonObject({
          'code': JsonString(DiagnosticCode.tooManyVariableErrors.id),
        }),
      );
    });

    test('the limit is shared between variables', () {
      final errors = errorsOf(
        r'query ($a: Int!, $b: Int!, $c: Int!) { a }',
        '{}',
        maxErrors: 2,
      );
      expect(errors, hasLength(3));
      expect(errors.last.message, startsWith('Too many errors'));
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/graphql_exception_test.dart test/coercion/input_coercion_test.dart test/coercion/value_inspector_test.dart test/coercion/variable_coercion_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/coercion/coercion_environment.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/schema_bindings.dart';

/// What every step of input coercion reads and none changes: the core schema
/// for the types, the bindings for the Dart side (codecs, enums, `decode`),
/// and whether messages carry "Did you mean" text.
final class CoercionEnvironment(
  /// The core schema.
  final Schema schema,

  /// The Dart definitions behind the schema.
  final SchemaBindings bindings, {

  /// Whether messages suggest names, as graphql-js's do unless
  /// `hideSuggestions` is set.
  final bool includesSuggestions = true,
}) {
  /// Creates the environment.
  this;
}
```

Create `packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// One reason an input value is invalid: graphql-js's message and the path
/// to the place.
final class CoercionProblem(
  /// What is wrong, as graphql-js words it.
  final String message,

  /// The path text, ` at .a[0]`, empty for the value itself.
  final String where, {

  /// The code of this problem when it is not the caller's default code.
  final DiagnosticCode? code,

  /// The extensions of a `GraphQLException` that caused the problem.
  final JsonObject? extensions,

  /// The error user code threw and its stack trace, which the caller
  /// reports to `onError`; null when the problem is not about a throw.
  final ({Object error, StackTrace stackTrace})? thrown,
}) {
  /// Describes a problem.
  this;
}
```

Create `packages/typed_graphql_server/lib/src/coercion/coercion_problems.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_problem.dart';
import 'input_path.dart';

/// The problems found while coercing one value, up to a limit.
///
/// A problem past the limit is dropped and [hasOverflowed] is set, which
/// tells the coercion to stop looking (R0.3: the work on a hostile value
/// must not grow with its size).
final class CoercionProblems {
  /// Collects at most [limit] problems.
  CoercionProblems(this.limit);

  /// The most problems kept.
  final int limit;

  /// The problems kept, in report order.
  final List<CoercionProblem> kept = [];

  /// Whether a problem arrived after the limit was reached.
  bool hasOverflowed = false;

  /// Records [message] at [path].
  void add(
    String message,
    InputPath path, {
    DiagnosticCode? code,
    JsonObject? extensions,
    ({Object error, StackTrace stackTrace})? thrown,
  }) {
    if (kept.length >= limit) {
      hasOverflowed = true;
      return;
    }
    kept.add(
      CoercionProblem(
        message,
        path.description,
        code: code,
        extensions: extensions,
        thrown: thrown,
      ),
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/coercion_result.dart`:

```dart
import 'coercion_problem.dart';

/// The outcome of coercing one input value: the coerced Dart value, or
/// every reason it is invalid.
sealed class CoercionResult {
  const CoercionResult();
}

/// The value was valid; [value] is the Dart value (null for a GraphQL null).
final class CoercionSuccess extends CoercionResult {
  /// Wraps [value].
  const CoercionSuccess(this.value);

  /// The coerced value.
  final Object? value;
}

/// The value was invalid.
final class CoercionFailure extends CoercionResult {
  /// Creates a failure with its [problems].
  CoercionFailure(List<CoercionProblem> problems, {required this.hasOverflowed})
    : problems = List.unmodifiable(problems);

  /// The problems, in report order, at most the limit asked for.
  final List<CoercionProblem> problems;

  /// Whether more problems were found than [problems] holds.
  final bool hasOverflowed;
}
```

Create `packages/typed_graphql_server/lib/src/coercion/input_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/schema_bindings.dart';
import 'coercion_environment.dart';
import 'coercion_problem.dart';
import 'coercion_problems.dart';
import 'coercion_result.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'value_coercion.dart';

/// Coerces input values (variables, input object fields, defaults) to Dart
/// values against a core type, with the schema's scalar codecs, enum
/// definitions and input object `decode` (September2025 section 3.11,
/// graphql-js's `coerceInputValue` and `validateInputValue`; R4.7).
///
/// It never throws: an invalid value is a [CoercionFailure] with graphql-js's
/// messages and the paths of the places.
final class InputCoercion {
  /// Coerces against [schema] with the Dart definitions in [bindings].
  /// [includesSuggestions] turns "Did you mean" text on or off.
  InputCoercion(
    Schema schema,
    SchemaBindings bindings, {
    bool includesSuggestions = true,
  }) : _environment = CoercionEnvironment(
         schema,
         bindings,
         includesSuggestions: includesSuggestions,
       );

  /// The default of [maxProblems].
  static const int defaultMaxProblems = 50;

  final CoercionEnvironment _environment;

  /// Whether [type] names an input type of the schema.
  bool isInputType(TypeRef type) => _environment.schema.isInputType(type);

  /// The Dart value of the JSON [value] for [type], or at most
  /// [maxProblems] problems.
  CoercionResult coerceValue(
    JsonValue value,
    TypeRef type, {
    int maxProblems = defaultMaxProblems,
  }) {
    final problems = CoercionProblems(maxProblems);
    final coerced = ValueCoercion(
      _environment,
      problems,
    ).coerce(value, type, InputPath.root, 0);
    if (coerced is InvalidValue) {
      return CoercionFailure(
        problems.kept,
        hasOverflowed: problems.hasOverflowed,
      );
    }
    return CoercionSuccess(coerced);
  }

  /// The Dart value of the constant [literal] for [type]: the literal goes
  /// through `LiteralConverter`, then [coerceValue] (an enum literal is its
  /// name). A literal with a variable in it is a problem.
  CoercionResult coerceLiteral(
    Value literal,
    TypeRef type, {
    int maxProblems = defaultMaxProblems,
  }) => switch (const LiteralConverter().convert(literal)) {
    DecodeSuccess(:final value) => coerceValue(
      value,
      type,
      maxProblems: maxProblems,
    ),
    DecodeFailure(:final message) => CoercionFailure([
      CoercionProblem(message, ''),
    ], hasOverflowed: false),
  };
}
```

Create `packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/arguments.dart';
import '../execution/graphql_exception.dart';
import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'value_coercion.dart';
import 'value_inspector.dart';

/// Coerces a JSON object to an input object (spec 3.10) with graphql-js's
/// `validateInputValue` messages and order: the declared fields in
/// declaration order, then the unknown ones, then the `@oneOf` rule; then
/// the definition's `decode` builds the Dart value.
final class InputObjectCoercion {
  /// Coerces into [problems]; fields go back through [values].
  InputObjectCoercion(this.environment, this.problems, this.values);

  static const ValueInspector _inspector = ValueInspector();
  static const Suggestions _suggestions = Suggestions();
  static const LiteralConverter _converter = LiteralConverter();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// Coerces the values of the fields.
  final ValueCoercion values;

  /// The Dart value of [value] for [type] at [path].
  Object? coerce(
    JsonValue value,
    InputObjectType type,
    InputPath path,
    int depth,
  ) {
    if (value is! JsonObject) {
      problems.add(
        'Expected value of type "${type.name}" to be an object, '
        'found: ${_inspector.inspect(value)}.',
        path,
      );
      return InvalidValue.instance;
    }
    final coerced = <String, Object?>{};
    var isValid = _coerceFields(value, type, coerced, path, depth);
    isValid = _checkUnknown(value, type, path) && isValid;
    isValid = (!type.isOneOf || _checkOneOf(value, type, path)) && isValid;
    return isValid ? _decode(coerced, type, path) : InvalidValue.instance;
  }

  bool _coerceFields(
    JsonObject value,
    InputObjectType type,
    Map<String, Object?> coerced,
    InputPath path,
    int depth,
  ) {
    var isValid = true;
    for (final field in type.fields) {
      if (problems.hasOverflowed) {
        return false;
      }
      final given = value.fields[field.name];
      final result = given == null
          ? _absent(value, type, field, path, depth)
          : values.coerce(given, field.type, path.key(field.name), depth + 1);
      if (result is InvalidValue) {
        isValid = false;
      } else if (given != null || field.defaultValue != null) {
        coerced[field.name] = result;
      }
    }
    return isValid;
  }

  // A missing field is an error when required, its default otherwise.
  Object? _absent(
    JsonObject value,
    InputObjectType type,
    InputValue field,
    InputPath path,
    int depth,
  ) {
    final defaultValue = field.defaultValue;
    if (defaultValue != null) {
      return _default(defaultValue, field, path.key(field.name), depth);
    }
    if (field.type is NonNullType) {
      problems.add(
        'Expected value of type "${type.name}" to include required field '
        '"${field.name}", found: ${_inspector.inspect(value)}.',
        path,
      );
      return InvalidValue.instance;
    }
    return null;
  }

  Object? _default(
    Value literal,
    InputValue field,
    InputPath path,
    int depth,
  ) => switch (_converter.convert(literal)) {
    DecodeSuccess(:final value) => values.coerce(
      value,
      field.type,
      path,
      depth + 1,
    ),
    DecodeFailure(:final message) => _reject(message, path),
  };

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  bool _checkUnknown(JsonObject value, InputObjectType type, InputPath path) {
    final names = [for (final field in type.fields) field.name];
    final known = names.toSet();
    var isValid = true;
    for (final name in value.fields.keys) {
      if (known.contains(name)) {
        continue;
      }
      isValid = false;
      if (problems.hasOverflowed) {
        break;
      }
      final suggestion = environment.includesSuggestions
          ? _suggestions.didYouMean(_suggestions.listFor(name, names))
          : '';
      final lead = suggestion.isEmpty ? ', found' : '.$suggestion Found';
      problems.add(
        'Expected value of type "${type.name}" not to include unknown field '
        '"$name"$lead: ${_inspector.inspect(value)}.',
        path,
      );
    }
    return isValid;
  }

  bool _checkOneOf(JsonObject value, InputObjectType type, InputPath path) {
    final message =
        'Within OneOf Input Object type "${type.name}", exactly one field '
        'must be specified, and the value for that field must be non-null.';
    final known = {for (final field in type.fields) field.name};
    final given = [
      for (final name in value.fields.keys)
        if (known.contains(name)) name,
    ];
    var isValid = given.length == 1;
    if (!isValid) {
      problems.add(message, path);
    }
    if (given.isNotEmpty && value.fields[given.first] is JsonNull) {
      problems.add(message, path.key(given.first));
      isValid = false;
    }
    return isValid;
  }

  Object? _decode(
    Map<String, Object?> coerced,
    InputObjectType type,
    InputPath path,
  ) {
    final definition = environment.bindings.inputObjects[type.name];
    if (definition == null) {
      return _reject('Input object "${type.name}" has no definition.', path);
    }
    try {
      return definition.decode(Arguments(definition.fields, coerced));
    } on GraphQLException catch (exception) {
      problems.add(exception.message, path, extensions: exception.extensions);
    } on Object catch (error, stackTrace) {
      problems.add(
        'Unexpected error.',
        path,
        code: DiagnosticCode.inputDecodeFailed,
        thrown: (error: error, stackTrace: stackTrace),
      );
    }
    return InvalidValue.instance;
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/input_path.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Where in a value coercion is: a chain of keys and indexes that shares
/// its parents, so a deep value costs one node per level and a path is
/// built only for a problem that is reported.
final class InputPath {
  const InputPath._(this._parent, this._segment);

  /// The path of the value itself.
  static const InputPath root = InputPath._(null, null);

  final InputPath? _parent;
  final PathSegment? _segment;

  /// The path of the field [name] of the object at this path.
  InputPath key(String name) => InputPath._(this, PathKey(name));

  /// The path of the item [position] of the list at this path.
  InputPath index(int position) => InputPath._(this, PathIndex(position));

  /// The segments from the root to here; no recursion, a path can be a
  /// thousand levels long.
  List<PathSegment> get segments {
    final reversed = <PathSegment>[];
    for (InputPath? at = this; at != null; at = at._parent) {
      if (at._segment case final segment?) {
        reversed.add(segment);
      }
    }
    return reversed.reversed.toList();
  }

  /// graphql-js's `printPathArray`: ` at .a[0].b`, empty for the root.
  String get description {
    final parts = segments;
    if (parts.isEmpty) {
      return '';
    }
    final text = StringBuffer(' at ');
    for (final part in parts) {
      switch (part) {
        case PathKey(:final name):
          text.write('.$name');
        case PathIndex(:final index):
          text.write('[$index]');
      }
    }
    return '$text';
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/invalid_value.dart`:

```dart
/// What a coercion step returns, instead of a value, for an input that is
/// invalid; its problem is already recorded. It is not `null`, which is a
/// valid GraphQL value.
final class InvalidValue {
  const InvalidValue._();

  /// The only instance.
  static const InvalidValue instance = InvalidValue._();
}
```

Create `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/enum_type_def.dart';
import '../builder/scalar_type_def.dart';
import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'value_inspector.dart';

/// Coerces a JSON value to a scalar or an enum value (spec 3.5, 3.9) with
/// graphql-js's messages. A problem is recorded in [problems]; the result
/// is then [InvalidValue.instance].
final class LeafCoercion {
  /// Coerces into [problems].
  LeafCoercion(this.environment, this.problems);

  static const ValueInspector _inspector = ValueInspector();
  static const Suggestions _suggestions = Suggestions();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The Dart value of [value] for the leaf [type] at [path].
  Object? coerce(JsonValue value, SchemaType type, InputPath path) =>
      switch (type) {
        ScalarType() => _scalar(value, type, path),
        EnumType() => _enum(value, type, path),
        _ => _reject('Type "${type.name}" is not a leaf type.', path),
      };

  Object _reject(String message, InputPath path, {DiagnosticCode? code}) {
    problems.add(message, path, code: code);
    return InvalidValue.instance;
  }

  ScalarCodec<Object>? _codecOf(String name) =>
      switch (environment.bindings.leaves[name]) {
        ScalarTypeDef<Object>(:final codec) => codec,
        _ => const ScalarCodecs().codecFor(name),
      };

  Object? _scalar(JsonValue value, ScalarType type, InputPath path) {
    final codec = _codecOf(type.name);
    if (codec == null) {
      return _reject(
        'Scalar "${type.name}" has no codec to read input with.',
        path,
        code: DiagnosticCode.unexpectedError,
      );
    }
    final DecodeResult<Object> result;
    try {
      result = codec.decode(value);
    } on Object catch (error, stackTrace) {
      problems.add(
        'Unexpected error.',
        path,
        code: DiagnosticCode.unexpectedError,
        thrown: (error: error, stackTrace: stackTrace),
      );
      return InvalidValue.instance;
    }
    return switch (result) {
      DecodeSuccess(:final value) => value,
      DecodeFailure(:final message) => _reject(message, path),
    };
  }

  Object? _enum(JsonValue value, EnumType type, InputPath path) {
    final definition = environment.bindings.leaves[type.name];
    if (definition is! EnumTypeDef<Enum>) {
      return _reject('Enum "${type.name}" has no definition.', path);
    }
    if (value is! JsonString) {
      final printed = _inspector.inspect(value);
      return _reject(
        'Enum "${type.name}" cannot represent non-string value: $printed.'
        '${_didYouMean(printed, type)}',
        path,
      );
    }
    return definition.valueNamed(value.value) ??
        _reject(
          'Value "${value.value}" does not exist in "${type.name}" enum.'
          '${_didYouMean(value.value, type)}',
          path,
        );
  }

  String _didYouMean(String input, EnumType type) {
    if (!environment.includesSuggestions) {
      return '';
    }
    final names = [for (final value in type.values) value.name];
    return _suggestions.didYouMean(
      _suggestions.listFor(input, names),
      subject: 'the enum value',
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/unexpected_input_error.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// An error thrown by user code while coercing input, with the error that
/// stands for it in the response.
final class UnexpectedInputError(
  /// What was thrown.
  final Object error,

  /// Where it was thrown.
  final StackTrace stackTrace,

  /// The masked error recorded in the response.
  final GraphQLError reported,
) {
  /// Describes a thrown error.
  this;
}
```

Create `packages/typed_graphql_server/lib/src/coercion/value_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_object_coercion.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'leaf_coercion.dart';

/// Coerces a JSON value against a type: non-null, list and named types
/// (September2025 section 3.11 and graphql-js's `coerceInputValue`), handing
/// leaves and input objects to their collaborators.
///
/// It recurses along the value, as `JsonReader` does, so a value nested
/// deeper than [maxDepth] is a problem and never a stack overflow (spec
/// 4.4). Problems go to [problems]; a step that finds one returns
/// [InvalidValue.instance].
final class ValueCoercion {
  /// Coerces into [problems].
  ValueCoercion(this.environment, this.problems)
    : _leaves = LeafCoercion(environment, problems);

  /// The deepest nesting of lists and input objects coercion follows.
  static const int maxDepth = JsonReader.maxSupportedDepth;

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  final LeafCoercion _leaves;

  /// The Dart value of [value] for [type] at [path], [depth] levels of lists
  /// and input objects below the top.
  Object? coerce(JsonValue value, TypeRef type, InputPath path, int depth) {
    if (problems.hasOverflowed) {
      return InvalidValue.instance;
    }
    if (depth > maxDepth) {
      problems.add('Input value is nested too deeply.', path);
      return InvalidValue.instance;
    }
    return switch (type) {
      NonNullType(type: final wrapped) =>
        value is JsonNull
            ? _reject(
                'Expected value of non-null type "${_printer.print(type)}" '
                'not to be null.',
                path,
              )
            : coerce(value, wrapped, path, depth),
      _ when value is JsonNull => null,
      ListType(type: final item) => _list(value, item, path, depth),
      NamedType(:final name) => _named(value, name.value, path, depth),
    };
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  // A value that is not a list stands for a list of one (spec 3.11).
  Object? _list(JsonValue value, TypeRef item, InputPath path, int depth) {
    if (value is! JsonArray) {
      final single = coerce(value, item, path, depth + 1);
      return single is InvalidValue ? single : <Object?>[single];
    }
    final result = <Object?>[];
    var isValid = true;
    for (var i = 0; i < value.items.length && !problems.hasOverflowed; i++) {
      final coerced = coerce(value.items[i], item, path.index(i), depth + 1);
      if (coerced is InvalidValue) {
        isValid = false;
      } else {
        result.add(coerced);
      }
    }
    return isValid ? result : InvalidValue.instance;
  }

  Object? _named(JsonValue value, String name, InputPath path, int depth) =>
      switch (environment.schema.typeNamed(name)) {
        final InputObjectType type => InputObjectCoercion(
          environment,
          problems,
          this,
        ).coerce(value, type, path, depth),
        final ScalarType type => _leaves.coerce(value, type, path),
        final EnumType type => _leaves.coerce(value, type, path),
        _ => _reject('Type "$name" is not an input type.', path),
      };
}
```

Create `packages/typed_graphql_server/lib/src/coercion/value_inspector.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's `inspect`: how a value is printed inside an error message.
///
/// It reads a [JsonValue] or a plain Dart value (null, bool, num, String,
/// List, Map; anything else prints with `toString`). Strings are JSON
/// quoted, objects print as `{ a: 1 }`, lists as `[1, 2]` with at most ten
/// items and then `... N more items`, and a list or object nested more than
/// two levels deep prints as `[Array]` or `[Object]`, so the cost of a
/// message does not grow with the depth of a hostile value.
final class ValueInspector {
  /// Creates the inspector; it keeps no state.
  const ValueInspector();

  static const int _maxItems = 10;
  static const int _maxDepth = 2;

  /// [value] as graphql-js's `inspect` prints it.
  String inspect(Object? value) => _format(value, 0);

  String _format(Object? raw, int ancestors) {
    return switch (_plain(raw)) {
      null => 'null',
      final String text => _quote(text),
      final num number => _number(number),
      final List<Object?> items => _list(items, ancestors + 1),
      final Map<String, Object?> fields => _object(fields, ancestors + 1),
      final Map<Object?, Object?> fields => _object({
        for (final entry in fields.entries) '${entry.key}': entry.value,
      }, ancestors + 1),
      final Object other => '$other',
    };
  }

  // Unwraps a JSON value one level: its children stay JSON values, which
  // [_format] unwraps when it reaches them.
  Object? _plain(Object? raw) => switch (raw) {
    JsonNull() => null,
    JsonBool(:final value) => value,
    JsonNumber(:final value) => value,
    JsonString(:final value) => value,
    JsonArray(:final items) => items,
    JsonObject(:final fields) => fields,
    _ => raw,
  };

  // `JSON.stringify` of a string. The server may not import `dart:convert`
  // (spec 17.4), so the escapes are written here.
  String _quote(String text) {
    final quoted = StringBuffer('"');
    for (final unit in text.codeUnits) {
      quoted.write(switch (unit) {
        0x22 => r'\"',
        0x5C => r'\\',
        0x0A => r'\n',
        0x0D => r'\r',
        0x09 => r'\t',
        0x08 => r'\b',
        0x0C => r'\f',
        < 0x20 => '\\u${unit.toRadixString(16).padLeft(4, '0')}',
        _ => String.fromCharCode(unit),
      });
    }
    return '$quoted"';
  }

  // JavaScript prints 1.0 as 1 and -0 as 0.
  String _number(num number) {
    final isWhole = number.isFinite && number == number.truncateToDouble();
    return isWhole && number.abs() < 1e21 ? '${number.toInt()}' : '$number';
  }

  String _list(List<Object?> items, int depth) {
    if (items.isEmpty) {
      return '[]';
    }
    if (depth > _maxDepth) {
      return '[Array]';
    }
    final shown = items.length < _maxItems ? items.length : _maxItems;
    final remaining = items.length - shown;
    final parts = [
      for (var i = 0; i < shown; i++) _format(items[i], depth),
      if (remaining == 1) '... 1 more item',
      if (remaining > 1) '... $remaining more items',
    ];
    return '[${parts.join(', ')}]';
  }

  String _object(Map<String, Object?> fields, int depth) {
    if (fields.isEmpty) {
      return '{}';
    }
    if (depth > _maxDepth) {
      return '[Object]';
    }
    final properties = [
      for (final MapEntry(:key, :value) in fields.entries)
        '$key: ${_format(value, depth)}',
    ];
    return '{ ${properties.join(', ')} }';
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/variable_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_problem.dart';
import 'coercion_result.dart';
import 'input_coercion.dart';
import 'variable_coercion_result.dart';
import 'variable_errors.dart';

/// September2025 section 6.4.1 `CoerceVariableValues` with graphql-js 17's
/// `getVariableValues` messages: it coerces the request's variable values
/// against an operation's variable definitions (R4.7).
///
/// Errors are request errors: no data is produced. At most
/// [maxCoercionErrors] are kept, then one "Too many errors" error
/// (`GQL312`).
final class VariableCoercion {
  /// Coerces with [coercion].
  VariableCoercion(this._coercion, {this.maxCoercionErrors = 50});

  static const Printer _printer = Printer();

  final InputCoercion _coercion;

  /// The most coercion errors reported.
  final int maxCoercionErrors;

  /// Coerces [inputs] (null for none) against [definitions]. With a
  /// [source], each error has the location of its variable definition.
  VariableCoercionResult coerce(
    List<VariableDefinition> definitions,
    JsonObject? inputs, {
    Source? source,
  }) {
    final errors = VariableErrors(maxCoercionErrors, source);
    final values = <String, Object?>{};
    for (final definition in definitions) {
      if (errors.isStopped) {
        break;
      }
      _coerceOne(definition, inputs, values, errors);
    }
    if (errors.errors.isEmpty) {
      return CoercedVariables(values);
    }
    return VariableCoercionFailure(errors.errors, errors.unexpected);
  }

  void _coerceOne(
    VariableDefinition definition,
    JsonObject? inputs,
    Map<String, Object?> values,
    VariableErrors errors,
  ) {
    final name = definition.variable.name.value;
    final type = definition.type;
    if (!_coercion.isInputType(type)) {
      errors.report(
        'Variable "\$$name" expected value of type "${_printer.print(type)}" '
        'which cannot be used as an input type.',
        DiagnosticCode.invalidVariableValue,
        type.start,
      );
      return;
    }
    final given = inputs?.fields[name];
    final fallback = definition.defaultValue;
    final result = _resultFor(given, fallback, type, errors.remaining);
    final isDefault = given == null && fallback != null;
    switch (result) {
      case null:
        break;
      case CoercionSuccess(:final value):
        values[name] = value;
      case CoercionFailure():
        _report(result, definition, isDefault: isDefault, errors: errors);
    }
  }

  // Null: nothing to record, the variable is simply absent.
  CoercionResult? _resultFor(
    JsonValue? given,
    Value? fallback,
    TypeRef type,
    int maxProblems,
  ) => switch ((given, fallback)) {
    (final JsonValue value, _) => _coercion.coerceValue(
      value,
      type,
      maxProblems: maxProblems,
    ),
    (_, final Value literal) => _coercion.coerceLiteral(
      literal,
      type,
      maxProblems: maxProblems,
    ),
    _ when type is! NonNullType => null,
    _ => _missing(type),
  };

  void _report(
    CoercionFailure failure,
    VariableDefinition definition, {
    required bool isDefault,
    required VariableErrors errors,
  }) {
    final name = definition.variable.name.value;
    errors.reportFailure(
      failure,
      'Variable "\$$name" has invalid ${isDefault ? 'default value' : 'value'}',
      isDefault
          ? DiagnosticCode.invalidVariableDefault
          : DiagnosticCode.invalidVariableValue,
      definition.start,
    );
  }

  // A required variable that the request did not give.
  CoercionResult _missing(TypeRef type) => CoercionFailure([
    CoercionProblem(
      'Expected a value of non-null type "${_printer.print(type)}" '
          'to be provided.',
      '',
    ),
  ], hasOverflowed: false);
}
```

Create `packages/typed_graphql_server/lib/src/coercion/variable_coercion_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'unexpected_input_error.dart';

/// The outcome of coercing the variables of an operation.
sealed class VariableCoercionResult {
  const VariableCoercionResult();
}

/// Every variable was valid. A variable the request did not give and that
/// has no default is not in [values].
final class CoercedVariables extends VariableCoercionResult {
  /// Wraps [values], a map the caller no longer changes.
  CoercedVariables(Map<String, Object?> values)
    : values = Map.unmodifiable(values);

  /// The coerced values by variable name (without the `$`).
  final Map<String, Object?> values;
}

/// Some variable was invalid; the operation does not run.
final class VariableCoercionFailure extends VariableCoercionResult {
  /// Creates a failure with its [errors] and the [unexpected] errors user
  /// code threw on the way.
  VariableCoercionFailure(
    List<GraphQLError> errors,
    List<UnexpectedInputError> unexpected,
  ) : errors = List.unmodifiable(errors),
      unexpected = List.unmodifiable(unexpected);

  /// The request errors, each with `extensions.code`, at most the limit
  /// and then one "Too many errors" error.
  final List<GraphQLError> errors;

  /// What user code threw (an input object's `decode`, a codec) that is
  /// masked in [errors]; the caller reports each to `onError`.
  final List<UnexpectedInputError> unexpected;
}
```

Create `packages/typed_graphql_server/lib/src/coercion/variable_errors.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_problem.dart';
import 'coercion_result.dart';
import 'unexpected_input_error.dart';

/// The request errors of one variable coercion run, with the limit of
/// `maxCoercionErrors`: the errors up to the limit, then, when one more
/// would follow, graphql-js's "Too many errors" error.
final class VariableErrors {
  /// Collects at most [maxErrors] errors, located in [source] when given.
  VariableErrors(this.maxErrors, this.source);

  static const String _tooMany =
      'Too many errors processing variables, error limit reached. '
      'Execution aborted.';

  /// The most errors kept before the "Too many errors" one.
  final int maxErrors;

  /// The text of the document, for the locations; null for none.
  final Source? source;

  /// The errors, in report order.
  final List<GraphQLError> errors = [];

  /// What user code threw, for `onError`.
  final List<UnexpectedInputError> unexpected = [];

  /// Whether the limit was reached and the run must stop.
  bool isStopped = false;

  /// How many more errors fit.
  int get remaining => maxErrors - errors.length;

  /// Records one error at [offset] of the document; past the limit it
  /// records the "Too many errors" error once instead.
  void report(String message, DiagnosticCode code, int? offset) {
    if (isStopped) {
      return;
    }
    if (errors.length >= maxErrors) {
      stop();
      return;
    }
    errors.add(_error(message, code, offset, null));
  }

  /// Records the problems of a failed coercion, each worded as
  /// `[subject][where]: [message]`.
  void reportFailure(
    CoercionFailure failure,
    String subject,
    DiagnosticCode code,
    int? offset,
  ) {
    for (final problem in failure.problems) {
      if (errors.length >= maxErrors) {
        stop();
        return;
      }
      _reportProblem(problem, subject, code, offset);
    }
    if (failure.hasOverflowed) {
      stop();
    }
  }

  /// Records the "Too many errors" error, once, and stops the run.
  void stop() {
    if (isStopped) {
      return;
    }
    isStopped = true;
    errors.add(
      _error(_tooMany, DiagnosticCode.tooManyVariableErrors, null, null),
    );
  }

  void _reportProblem(
    CoercionProblem problem,
    String subject,
    DiagnosticCode code,
    int? offset,
  ) {
    final text = '$subject${problem.where}: ${problem.message}';
    final reported = _error(
      text,
      problem.code ?? code,
      offset,
      problem.extensions,
    );
    errors.add(reported);
    if (problem.thrown case (:final error, :final stackTrace)?) {
      unexpected.add(UnexpectedInputError(error, stackTrace, reported));
    }
  }

  GraphQLError _error(
    String message,
    DiagnosticCode code,
    int? offset,
    JsonObject? extensions,
  ) {
    final text = source;
    return GraphQLError(
      message,
      locations: [if (text != null && offset != null) text.locationOf(offset)],
      extensions: extensions ?? JsonObject({'code': JsonString(code.id)}),
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/graphql_exception.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// An error that a resolver, a scalar or an input object's `decode` throws
/// on purpose and that reaches the client as it is: [message] and
/// [extensions] go into the response without masking.
///
/// {@category execution}
final class GraphQLException implements Exception {
  /// Creates an exception with [message] and optional [extensions].
  const GraphQLException(this.message, {this.extensions});

  /// What the client reads.
  final String message;

  /// The `extensions` of the response error; null for none.
  final JsonObject? extensions;

  @override
  String toString() => message;
}
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -31,3 +31,4 @@ export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
 export 'src/execution/executable_schema.dart';
 export 'src/execution/field_info.dart';
+export 'src/execution/graphql_exception.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/graphql_exception_test.dart test/coercion/input_coercion_test.dart test/coercion/value_inspector_test.dart test/coercion/variable_coercion_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- `GraphQLException`: an error a resolver, scalar or input object `decode` throws on purpose; its message and extensions reach the client unmasked.
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
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/coercion/coercion_environment.dart packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart packages/typed_graphql_server/lib/src/coercion/coercion_problems.dart packages/typed_graphql_server/lib/src/coercion/coercion_result.dart packages/typed_graphql_server/lib/src/coercion/input_coercion.dart packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart packages/typed_graphql_server/lib/src/coercion/input_path.dart packages/typed_graphql_server/lib/src/coercion/invalid_value.dart packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart packages/typed_graphql_server/lib/src/coercion/unexpected_input_error.dart packages/typed_graphql_server/lib/src/coercion/value_coercion.dart packages/typed_graphql_server/lib/src/coercion/value_inspector.dart packages/typed_graphql_server/lib/src/coercion/variable_coercion.dart packages/typed_graphql_server/lib/src/coercion/variable_coercion_result.dart packages/typed_graphql_server/lib/src/coercion/variable_errors.dart packages/typed_graphql_server/lib/src/execution/graphql_exception.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/coercion/coercion_fixture.dart packages/typed_graphql_server/test/coercion/graphql_exception_test.dart packages/typed_graphql_server/test/coercion/input_coercion_test.dart packages/typed_graphql_server/test/coercion/value_inspector_test.dart packages/typed_graphql_server/test/coercion/variable_coercion_test.dart
git commit -q -m "feat(typed_graphql_server): coerce variable values" \
  -m "Input coercion turns JSON values and an operation's variables into Dart values against the schema's types: non-null, lists (a single value is a list of one), scalar codecs, enums, input objects with defaults, @oneOf and decode, with graphql-js's messages, paths, \"Did you mean\" text, an error limit (GQL310-GQL312, GQL314) and a 1000-level depth bound. GraphQLException is the error user code throws to reach the client unmasked." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Argument coercion

Add `ArgumentCoercion` (§6.4.1 `CoerceArgumentValues`) over literal walkers that substitute coerced variables and share the leaf, decode and message pieces of Task 2, and `ConditionalDirectives` for `@skip` / `@include`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/conditional_directives.dart`, `packages/typed_graphql_server/lib/src/coercion/input_messages.dart`, `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart`, `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/object_literal_coercion.dart`
- Modify: `packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart`
- Test: `packages/typed_graphql_server/test/coercion/argument_coercion_test.dart`, `packages/typed_graphql_server/test/coercion/conditional_directives_test.dart`, `packages/typed_graphql_server/test/coercion/coercion_fixture.dart`

**Interfaces:**
- Consumes: Task 2's coercion.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// coercion/argument_coercion.dart
final class ArgumentCoercion
  ArgumentCoercion(this.environment)
  CoercionResult coerce(…)

// coercion/conditional_directives.dart
final class ConditionalDirectives
  ConditionalDirectives(this.environment)
  CoercionResult isIncluded(…)

// coercion/input_messages.dart
final class InputMessages
  String notObject(String typeName, String found)
  String missingField(String typeName, String fieldName, String found)
  String unknownField(…)
  String oneOf(String typeName)

// coercion/input_object_decoder.dart
final class InputObjectDecoder
  InputObjectDecoder(this.environment, this.problems)
  Object? decode(…)

// coercion/literal_coercion.dart
final class LiteralCoercion
  LiteralCoercion(this.environment, this.problems, this.variables)
  Object? coerce(Value literal, TypeRef type, InputPath path, int depth)

// coercion/literal_leaf_coercion.dart
final class LiteralLeafCoercion
  LiteralLeafCoercion(this.environment, this.problems)
  Object? coerce(Value literal, SchemaType type, InputPath path)

// coercion/object_literal_coercion.dart
final class ObjectLiteralCoercion
  ObjectLiteralCoercion(…)
  Object? coerce(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/coercion/argument_coercion_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/argument_coercion.dart';
import 'package:typed_graphql_server/src/coercion/coercion_problems.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/coercion/input_path.dart';
import 'package:typed_graphql_server/src/coercion/invalid_value.dart';
import 'package:typed_graphql_server/src/coercion/literal_coercion.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();
  final coercion = ArgumentCoercion(fx.environment);

  Field fieldOf(String query) =>
      (const Parser().parse(Source(query)).requireDocument().definitions.single
                  as OperationDefinition)
              .selectionSet
              .selections
              .single
          as Field;

  // The result of `{ [call] }` against Query.[name]; [variables] are coerced.
  CoercionResult run(
    String name,
    String call, [
    Map<String, Object?> variables = const {},
  ]) {
    final query = fx.schema.typeNamed('Query')! as ObjectType;
    return coercion.coerce(
      'Query.$name',
      query.fieldNamed(name)!.arguments,
      fieldOf('{ $call }').arguments,
      variables,
    );
  }

  Map<String, Object?> valuesOf(
    String name,
    String call, [
    Map<String, Object?> variables = const {},
  ]) => switch (run(name, call, variables)) {
    CoercionSuccess(value: final Map<String, Object?> values) => values,
    CoercionSuccess() => fail('not a map'),
    CoercionFailure(:final problems) => fail(
      'failed: ${problems.map((p) => p.message).toList()}',
    ),
  };

  String messageOf(
    String name,
    String call, [
    Map<String, Object?> variables = const {},
  ]) => switch (run(name, call, variables)) {
    CoercionSuccess() => fail('expected a failure'),
    CoercionFailure(:final problems) => problems.single.message,
  };

  group('values', () {
    test('coerces the literals of scalars', () {
      expect(valuesOf('typed', 'typed(req: 3, opt: "x", flag: true)'), {
        'req': 3,
        'opt': 'x',
        'flag': true,
        'limit': 10,
      });
    });

    test('keeps an explicit null', () {
      expect(valuesOf('typed', 'typed(req: 1, opt: null)')['opt'], isNull);
      expect(valuesOf('typed', 'typed(req: 1, opt: null)'), contains('opt'));
    });

    test('applies the default of an argument that is not given', () {
      expect(valuesOf('typed', 'typed(req: 1)')['limit'], 10);
    });

    test('leaves out an optional argument without a default', () {
      expect(valuesOf('typed', 'typed(req: 1)'), isNot(contains('opt')));
    });

    test('maps an enum literal by name', () {
      expect(
        valuesOf('typed', 'typed(req: 1, color: green)')['color'],
        Color.green,
      );
    });

    test('wraps a single item as a list', () {
      expect(valuesOf('typed', 'typed(req: 1, ids: 7)')['ids'], [7]);
    });

    test('reads a list literal', () {
      expect(valuesOf('typed', 'typed(req: 1, ids: [1, 2])')['ids'], [1, 2]);
    });

    test('runs the codec of a custom scalar on its literal', () {
      expect(
        valuesOf('typed', 'typed(req: 1, big: "ExternalValue")')['big'],
        'InternalValue',
      );
    });

    test('decodes an input object literal', () {
      expect(
        valuesOf('probe', 'probe(input: {a: "x", c: "y"})')['input'],
        containsPair('c', 'y'),
      );
    });

    test('fills the defaults of input fields', () {
      expect(valuesOf('probe', 'probe(defaulted: {})')['defaulted'], {
        'count': 5,
        'shade': Color.green,
        'tags': isNull,
      });
    });
  });

  group('variables', () {
    test('substitutes a coerced variable', () {
      expect(
        valuesOf('typed', r'typed(req: $n)', {'n': 4})['req'],
        4,
      );
    });

    test('treats a missing optional variable as not given', () {
      expect(
        valuesOf('typed', r'typed(req: 1, limit: $l)', {})['limit'],
        10,
      );
    });

    test('keeps a variable that is null', () {
      expect(
        valuesOf('typed', r'typed(req: 1, opt: $o)', {'o': null}),
        containsPair('opt', isNull),
      );
    });

    test('substitutes a variable inside a list and an object', () {
      expect(
        valuesOf('typed', r'typed(req: 1, ids: [1, $n])', {'n': 2})['ids'],
        [1, 2],
      );
      expect(
        valuesOf('probe', r'probe(input: {c: $c})', {'c': 'v'})['input'],
        containsPair('c', 'v'),
      );
    });

    test('reads a missing variable in a list as null', () {
      expect(
        valuesOf('probe', r'probe(input: {c: "x", b: ["a", $b]})')['input'],
        containsPair('b', ['a', null]),
      );
    });

    test('uses the default of an input field for a missing variable', () {
      expect(
        valuesOf('probe', r'probe(defaulted: {count: $c})')['defaulted'],
        containsPair('count', 5),
      );
    });
  });

  group('messages', () {
    test('a required argument that was not provided', () {
      expect(
        messageOf('typed', 'typed'),
        'Argument "Query.typed(req:)" of required type "Int!" was not '
        'provided.',
      );
    });

    test('a required argument whose variable has no value', () {
      expect(
        messageOf('typed', r'typed(req: $n)'),
        'Argument "Query.typed(req:)" has invalid value: Expected variable '
        r'"$n" provided to type "Int!" to provide a runtime value.',
      );
    });

    test('a required argument whose variable is null', () {
      expect(
        messageOf('typed', r'typed(req: $n)', {'n': null}),
        'Argument "Query.typed(req:)" has invalid value: Expected variable '
        r'"$n" provided to non-null type "Int!" not to be null.',
      );
    });

    test('a null literal for a non-null argument', () {
      expect(
        messageOf('typed', 'typed(req: null)'),
        'Argument "Query.typed(req:)" has invalid value: Expected value of '
        'non-null type "Int!" not to be null.',
      );
    });

    test('a literal of the wrong kind', () {
      expect(
        messageOf('typed', 'typed(req: "x")'),
        'Argument "Query.typed(req:)" has invalid value: Int cannot '
        'represent non-integer value: "x"',
      );
    });

    test('a float literal for an Int', () {
      expect(
        messageOf('typed', 'typed(req: 1.0)'),
        'Argument "Query.typed(req:)" has invalid value: Int cannot '
        'represent non-integer value: 1.0',
      );
    });

    test('an enum literal for a String names the argument', () {
      expect(
        messageOf('typed', 'typed(req: 1, opt: RED)'),
        'Argument "Query.typed(opt:)" has invalid value: String cannot '
        'represent a non string value: RED',
      );
    });

    test('a string literal for an enum', () {
      expect(
        messageOf('typed', 'typed(req: 1, color: "green")'),
        'Argument "Query.typed(color:)" has invalid value: Enum "Color" '
        'cannot represent non-enum value: "green". Did you mean the enum value '
        '"green"?',
      );
    });

    test('an unknown enum value', () {
      expect(
        messageOf('typed', 'typed(req: 1, color: grene)'),
        'Argument "Query.typed(color:)" has invalid value: Value "grene" '
        'does not exist in "Color" enum. Did you mean the enum value '
        '"green" or "red"?',
      );
    });

    test('a path into a list', () {
      expect(
        messageOf('typed', 'typed(req: 1, ids: [1, "x"])'),
        'Argument "Query.typed(ids:)" has invalid value at [1]: Int cannot '
        'represent non-integer value: "x"',
      );
    });

    test('a value that is not an object', () {
      expect(
        messageOf('probe', 'probe(input: [1])'),
        'Argument "Query.probe(input:)" has invalid value: Expected value '
        'of type "TestInputObject" to be an object, found: [1].',
      );
    });

    test('a missing required field', () {
      expect(
        messageOf('probe', 'probe(input: {a: "x"})'),
        'Argument "Query.probe(input:)" has invalid value: Expected value '
        'of type "TestInputObject" to include required field "c", found: '
        '{ a: "x" }.',
      );
    });

    test('an unknown field with a suggestion', () {
      expect(
        messageOf('probe', 'probe(input: {c: "x", aa: "y"})'),
        'Argument "Query.probe(input:)" has invalid value: Expected value '
        'of type "TestInputObject" not to include unknown field "aa". Did '
        'you mean "a"? Found: { c: "x", aa: "y" }.',
      );
    });

    test('a faulty scalar inside an object names the path', () {
      expect(
        messageOf('probe', 'probe(input: {c: "x", e: "y"})'),
        'Argument "Query.probe(input:)" has invalid value at .e: '
        'FaultyScalarErrorMessage',
      );
    });

    test('a oneOf object with two fields', () {
      expect(
        messageOf('probe', 'probe(lookup: {id: 1, email: "a"})'),
        'Argument "Query.probe(lookup:)" has invalid value: Within OneOf '
        'Input Object type "Lookup", exactly one field must be specified, '
        'and the value for that field must be non-null.',
      );
    });

    test('a oneOf field that is a null literal', () {
      expect(
        messageOf('probe', 'probe(lookup: {id: null})'),
        'Argument "Query.probe(lookup:)" has invalid value at .id: Within '
        'OneOf Input Object type "Lookup", exactly one field must be '
        'specified, and the value for that field must be non-null.',
      );
    });

    test('a oneOf field whose variable is null', () {
      expect(
        messageOf('probe', r'probe(lookup: {id: $a})', {'a': null}),
        'Argument "Query.probe(lookup:)" has invalid value: Expected '
        r'variable "$a" provided to field "id" for OneOf Input Object type '
        '"Lookup" not to be null.',
      );
    });

    test('a oneOf field whose variable has no value', () {
      expect(
        messageOf('probe', r'probe(lookup: {id: $a})'),
        'Argument "Query.probe(lookup:)" has invalid value: Expected '
        r'variable "$a" provided to field "id" for OneOf Input Object type '
        '"Lookup" to provide a runtime value.',
      );
    });
  });

  group('failures', () {
    test('stop at the first failing argument', () {
      final result = run('typed', 'typed(req: "x", opt: RED)');
      expect(result, isA<CoercionFailure>());
      expect((result as CoercionFailure).problems, hasLength(1));
    });

    test('carry GQL313', () {
      final result = run('typed', 'typed(req: "x")') as CoercionFailure;
      expect(result.problems.single.code, DiagnosticCode.invalidArgumentValue);
    });

    test('keep the extensions of a GraphQLException from decode', () {
      final result = run('more', 'more(exploding: {})') as CoercionFailure;
      final problem = result.problems.single;
      expect(
        problem.message,
        'Argument "Query.more(exploding:)" has invalid value: refused',
      );
      expect(problem.extensions, isNotNull);
    });

    test('keep what decode threw for onError and use GQL314', () {
      final result = run('more', 'more(crashing: {})') as CoercionFailure;
      final problem = result.problems.single;
      expect(problem.code, DiagnosticCode.inputDecodeFailed);
      expect(problem.thrown?.error, isA<StateError>());
      expect(problem.message, isNot(contains('secret detail')));
    });

    test('stop a literal nested deeper than the bound', () {
      // Built in code: the parser's own depth limit would refuse it.
      Value literal = ObjectValue([]);
      for (var i = 0; i < 1100; i++) {
        literal = ObjectValue([ObjectField(const Name('next'), literal)]);
      }
      final problems = CoercionProblems(1);
      final result = LiteralCoercion(
        fx.environment,
        problems,
        const <String, Object?>{},
      ).coerce(literal, fx.type('Chain'), InputPath.root, 0);
      expect(result, InvalidValue.instance);
      expect(problems.kept.single.message, 'Input value is nested too deeply.');
    });
  });
}
```

Create `packages/typed_graphql_server/test/coercion/conditional_directives_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/coercion/conditional_directives.dart';

import 'coercion_fixture.dart';

void main() {
  final fx = CoercionFixture();
  final directives = ConditionalDirectives(fx.environment);

  CoercionResult run(
    String written, [
    Map<String, Object?> variables = const {},
  ]) {
    final operation =
        const Parser()
                .parse(Source('{ a$written }'))
                .requireDocument()
                .definitions
                .single
            as OperationDefinition;
    final field = operation.selectionSet.selections.single as Field;
    return directives.isIncluded(field.directives, variables);
  }

  Object? includedOf(
    String written, [
    Map<String, Object?> variables = const {},
  ]) => switch (run(written, variables)) {
    CoercionSuccess(:final value) => value,
    CoercionFailure(:final problems) => fail(problems.single.message),
  };

  String messageOf(String written) => switch (run(written)) {
    CoercionSuccess() => fail('expected a failure'),
    CoercionFailure(:final problems) => problems.single.message,
  };

  test('includes a selection without directives', () {
    expect(includedOf(''), isTrue);
  });

  test('skips on @skip(if: true)', () {
    expect(includedOf(' @skip(if: true)'), isFalse);
  });

  test('keeps on @skip(if: false)', () {
    expect(includedOf(' @skip(if: false)'), isTrue);
  });

  test('keeps on @include(if: true)', () {
    expect(includedOf(' @include(if: true)'), isTrue);
  });

  test('drops on @include(if: false)', () {
    expect(includedOf(' @include(if: false)'), isFalse);
  });

  test('reads the condition from a variable', () {
    expect(includedOf(r' @skip(if: $s)', {'s': true}), isFalse);
  });

  test('lets @skip win over @include', () {
    expect(includedOf(' @include(if: true) @skip(if: true)'), isFalse);
  });

  test('reports an if argument that is not a Boolean', () {
    expect(
      messageOf(' @skip(if: 1)'),
      'Argument "@skip(if:)" has invalid value: Boolean cannot represent a '
      'non boolean value: 1',
    );
  });

  test('reports a missing if argument', () {
    expect(
      messageOf(' @include'),
      'Argument "@include(if:)" of required type "Boolean!" was not '
      'provided.',
    );
  });

  test('reports a variable without a value', () {
    expect(
      messageOf(r' @skip(if: $s)'),
      'Argument "@skip(if:)" has invalid value: Expected variable '
      r'"$s" provided to type "Boolean!" to provide a runtime value.',
    );
  });
}
```

In `packages/typed_graphql_server/test/coercion/coercion_fixture.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/src/coercion/coercion_environment.dart';
 import 'package:typed_graphql_server/src/coercion/coercion_problem.dart';
 import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
 import 'package:typed_graphql_server/src/coercion/input_coercion.dart';
@@ -135,6 +136,21 @@ final class CoercionFixture {
               ],
             )
             .resolve((parent, args, context, info) => null),
+        t
+            .field(
+              'typed',
+              b.string.nullable,
+              args: [
+                Arg('req', b.int),
+                Arg('opt', b.string.nullable),
+                Arg('limit', b.int, defaultValue: 10),
+                Arg('ids', b.inputList(b.int).nullable),
+                Arg('color', color.nullable),
+                Arg('big', complex.nullable),
+                Arg('flag', b.boolean.nullable),
+              ],
+            )
+            .resolve((parent, args, context, info) => null),
         t
             .field(
               'more',
@@ -150,6 +166,7 @@ final class CoercionFixture {
     );
     final built = b.build(query: query);
     schema = built.schema.schema;
+    environment = CoercionEnvironment(schema, built.bindings);
     coercion = InputCoercion(schema, built.bindings);
     hiddenSuggestions = InputCoercion(
       schema,
@@ -159,6 +176,7 @@ final class CoercionFixture {
   }
 
   late final Schema schema;
+  late final CoercionEnvironment environment;
   late final InputCoercion coercion;
   late final InputCoercion hiddenSuggestions;
 
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/argument_coercion_test.dart test/coercion/conditional_directives_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problem.dart';
import 'coercion_problems.dart';
import 'coercion_result.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'literal_coercion.dart';

/// September2025 section 6.4.1 `CoerceArgumentValues` with graphql-js 17's
/// `getArgumentValues` messages: it coerces the arguments written on a field
/// or a directive against the arguments the schema declares (R4.7).
///
/// Like graphql-js it stops at the first argument that fails, and a failure
/// holds one problem: the message is complete (`Argument
/// "Query.user(id:)" has invalid value at .a: ...`) and the code is
/// `GQL313` unless the cause has its own. A success holds the coerced
/// values by argument name, defaults included; an argument that is not
/// there was not given.
final class ArgumentCoercion {
  /// Coerces in [environment].
  ArgumentCoercion(this.environment);

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Coerces the [nodes] written on the field or directive named [owner]
  /// (`Query.user`, `@skip`) against its [declared] arguments, reading
  /// variables from [variables] (the coerced values by name).
  CoercionResult coerce(
    String owner,
    List<InputValue> declared,
    List<Argument> nodes,
    Map<String, Object?> variables,
  ) {
    final written = {for (final node in nodes) node.name.value: node.value};
    final values = <String, Object?>{};
    for (final definition in declared) {
      final subject = 'Argument "$owner(${definition.name}:)"';
      final problem = _coerceOne(
        subject,
        definition,
        written[definition.name],
        variables,
        values,
      );
      if (problem != null) {
        return CoercionFailure([problem], hasOverflowed: false);
      }
    }
    return CoercionSuccess(values);
  }

  CoercionProblem? _coerceOne(
    String subject,
    InputValue definition,
    Value? written,
    Map<String, Object?> variables,
    Map<String, Object?> values,
  ) {
    final isRequired =
        definition.type is NonNullType && definition.defaultValue == null;
    if (written == null && isRequired) {
      return _problem(
        '$subject of required type "${_printer.print(definition.type)}" was '
        'not provided.',
      );
    }
    // A variable without a value counts as no argument unless required.
    final isAbsent =
        written == null ||
        (written is Variable &&
            !variables.containsKey(written.name.value) &&
            !isRequired);
    return isAbsent
        ? _useDefault(subject, definition, values)
        : _useLiteral(subject, definition, written, variables, values);
  }

  CoercionProblem? _useDefault(
    String subject,
    InputValue definition,
    Map<String, Object?> values,
  ) {
    final fallback = definition.defaultValue;
    if (fallback == null) {
      return null;
    }
    final problems = CoercionProblems(1);
    final coerced = LiteralCoercion(
      environment,
      problems,
      const <String, Object?>{},
    ).coerce(fallback, definition.type, InputPath.root, 0);
    if (coerced is InvalidValue) {
      return _problem(
        '$subject has invalid default value',
        problem: problems.kept.first,
      );
    }
    values[definition.name] = coerced;
    return null;
  }

  CoercionProblem? _useLiteral(
    String subject,
    InputValue definition,
    Value written,
    Map<String, Object?> variables,
    Map<String, Object?> values,
  ) {
    final problems = CoercionProblems(1);
    final coerced = LiteralCoercion(
      environment,
      problems,
      variables,
    ).coerce(written, definition.type, InputPath.root, 0);
    if (coerced is InvalidValue) {
      return _problem(
        '$subject has invalid value',
        problem: problems.kept.first,
      );
    }
    values[definition.name] = coerced;
    return null;
  }

  // Words `[lead][where]: [message]` of a cause, or a plain message.
  CoercionProblem _problem(String lead, {CoercionProblem? problem}) {
    if (problem == null) {
      return CoercionProblem(
        lead,
        '',
        code: DiagnosticCode.invalidArgumentValue,
      );
    }
    return CoercionProblem(
      '$lead${problem.where}: ${problem.message}',
      '',
      code: problem.code ?? DiagnosticCode.invalidArgumentValue,
      extensions: problem.extensions,
      thrown: problem.thrown,
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/conditional_directives.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'argument_coercion.dart';
import 'coercion_environment.dart';
import 'coercion_result.dart';

/// Reads `@skip(if:)` and `@include(if:)` for field collection (spec
/// 6.3.2 `CollectFields`, graphql-js's `getDirectiveValues`): the `if`
/// arguments are coerced like any argument, with the built-in directive
/// definitions, so `@skip(if: $v)` with a missing required variable is an
/// error and not a guess.
final class ConditionalDirectives {
  /// Reads in [environment].
  ConditionalDirectives(this.environment)
    : _arguments = ArgumentCoercion(environment);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  final ArgumentCoercion _arguments;

  /// Whether a selection written with [directives] is included: a
  /// [CoercionSuccess] holding a `bool`, or the failure of an `if` argument.
  /// `@skip(if: true)` and `@include(if: false)` exclude it.
  CoercionResult isIncluded(
    List<Directive> directives,
    Map<String, Object?> variables,
  ) {
    for (final (name, excludesWhen) in const [
      ('skip', true),
      ('include', false),
    ]) {
      final directive = _named(directives, name);
      if (directive == null) {
        continue;
      }
      switch (_condition(name, directive, variables)) {
        case CoercionSuccess(:final value) when value == excludesWhen:
          return const CoercionSuccess(false);
        case final CoercionFailure failure:
          return failure;
        case CoercionSuccess():
          break;
      }
    }
    return const CoercionSuccess(true);
  }

  Directive? _named(List<Directive> directives, String name) {
    for (final directive in directives) {
      if (directive.name.value == name) {
        return directive;
      }
    }
    return null;
  }

  // The value of the `if` argument, a `bool`.
  CoercionResult _condition(
    String name,
    Directive directive,
    Map<String, Object?> variables,
  ) {
    final definition = environment.schema.directiveNamed(name);
    if (definition == null) {
      throw StateError('The schema has no directive @$name.');
    }
    return switch (_arguments.coerce(
      '@$name',
      definition.arguments,
      directive.arguments,
      variables,
    )) {
      CoercionSuccess(value: final Map<String, Object?> values) =>
        CoercionSuccess(values['if']),
      CoercionSuccess() => throw StateError('Argument values are a map.'),
      final CoercionFailure failure => failure,
    };
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/input_messages.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's messages about the shape of an input object, shared by the
/// coercion of JSON values and of literals; only the way the offending
/// value is printed (`found`) differs between them.
final class InputMessages {
  /// Words messages with or without "Did you mean" text.
  const InputMessages({required this.includesSuggestions});

  static const Suggestions _suggestions = Suggestions();

  /// Whether messages suggest names, as graphql-js's do unless
  /// `hideSuggestions` is set.
  final bool includesSuggestions;

  /// A value that is not an object where an input object is expected.
  String notObject(String typeName, String found) =>
      'Expected value of type "$typeName" to be an object, found: $found.';

  /// An object without a required field.
  String missingField(String typeName, String fieldName, String found) =>
      'Expected value of type "$typeName" to include required field '
      '"$fieldName", found: $found.';

  /// An object with a field the type does not declare; [known] are the
  /// declared names.
  String unknownField(
    String typeName,
    String fieldName,
    List<String> known,
    String found,
  ) {
    final suggestion = includesSuggestions
        ? _suggestions.didYouMean(_suggestions.listFor(fieldName, known))
        : '';
    final lead = suggestion.isEmpty ? ', found' : '.$suggestion Found';
    return 'Expected value of type "$typeName" not to include unknown field '
        '"$fieldName"$lead: $found.';
  }

  /// A `@oneOf` object that does not have exactly one non-null field.
  String oneOf(String typeName) =>
      'Within OneOf Input Object type "$typeName", exactly one field '
      'must be specified, and the value for that field must be non-null.';
}
```

Create `packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/arguments.dart';
import '../execution/graphql_exception.dart';
import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';

/// Builds the Dart value of an input object from its coerced fields with the
/// definition's `decode`, turning what it throws into problems: a
/// `GraphQLException` keeps its message and extensions, anything else is an
/// "Unexpected error." (`GQL314`) that the caller reports to `onError`.
final class InputObjectDecoder {
  /// Decodes into [problems].
  InputObjectDecoder(this.environment, this.problems);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The Dart value of [type] with the [coerced] fields, at [path].
  Object? decode(
    Map<String, Object?> coerced,
    InputObjectType type,
    InputPath path,
  ) {
    final definition = environment.bindings.inputObjects[type.name];
    if (definition == null) {
      problems.add('Input object "${type.name}" has no definition.', path);
      return InvalidValue.instance;
    }
    try {
      return definition.decode(Arguments(definition.fields, coerced));
    } on GraphQLException catch (exception) {
      problems.add(exception.message, path, extensions: exception.extensions);
    } on Object catch (error, stackTrace) {
      problems.add(
        'Unexpected error.',
        path,
        code: DiagnosticCode.inputDecodeFailed,
        thrown: (error: error, stackTrace: stackTrace),
      );
    }
    return InvalidValue.instance;
  }
}
```

Create `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'literal_leaf_coercion.dart';
import 'object_literal_coercion.dart';
import 'value_coercion.dart';

/// Coerces a literal of a document, with variables in it, to a Dart value
/// (graphql-js's `coerceInputLiteral` with the messages of
/// `validateInputLiteral`, September2025 section 6.4.1).
///
/// A variable stands for its already coerced Dart value, so a literal
/// cannot go through JSON first. Like [ValueCoercion] it recurses along the
/// literal, and one nested deeper than [ValueCoercion.maxDepth] is a
/// problem. Problems go to [problems]; a step that finds one returns
/// [InvalidValue.instance].
final class LiteralCoercion {
  /// Coerces into [problems], reading variables from [variables] (the
  /// coerced values by name; a variable that is not a key has no value).
  LiteralCoercion(this.environment, this.problems, this.variables)
    : _leaves = LiteralLeafCoercion(environment, problems);

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The coerced variable values.
  final Map<String, Object?> variables;

  final LiteralLeafCoercion _leaves;

  /// The Dart value of [literal] for [type] at [path], [depth] levels of
  /// lists and input objects below the top.
  Object? coerce(Value literal, TypeRef type, InputPath path, int depth) {
    if (problems.hasOverflowed) {
      return InvalidValue.instance;
    }
    if (depth > ValueCoercion.maxDepth) {
      return _reject('Input value is nested too deeply.', path);
    }
    if (literal is Variable) {
      return _variable(literal, type, path);
    }
    return switch (type) {
      NonNullType(type: final wrapped) =>
        literal is NullValue
            ? _reject(
                'Expected value of non-null type "${_printer.print(type)}" '
                'not to be null.',
                path,
              )
            : coerce(literal, wrapped, path, depth),
      _ when literal is NullValue => null,
      ListType(type: final item) => _list(literal, item, path, depth),
      NamedType(:final name) => _named(literal, name.value, path, depth),
    };
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  // Not validated against its type: validation did that (spec 5.8.5).
  Object? _variable(Variable variable, TypeRef type, InputPath path) {
    final name = variable.name.value;
    if (type is NonNullType) {
      final printed = _printer.print(type);
      if (!variables.containsKey(name)) {
        return _reject(
          'Expected variable "\$$name" provided to type "$printed" to '
          'provide a runtime value.',
          path,
        );
      }
      if (variables[name] == null) {
        return _reject(
          'Expected variable "\$$name" provided to non-null type "$printed" '
          'not to be null.',
          path,
        );
      }
    }
    return variables[name];
  }

  // A value that is not a list stands for a list of one (spec 3.11); a
  // variable without a value in a list is null.
  Object? _list(Value literal, TypeRef item, InputPath path, int depth) {
    if (literal is! ListValue) {
      final single = coerce(literal, item, path, depth + 1);
      return single is InvalidValue ? single : <Object?>[single];
    }
    final result = <Object?>[];
    var isValid = true;
    for (final (index, node) in literal.values.indexed) {
      if (problems.hasOverflowed) {
        break;
      }
      final coerced = coerce(node, item, path.index(index), depth + 1);
      if (coerced is InvalidValue) {
        isValid = false;
      } else {
        result.add(coerced);
      }
    }
    return isValid ? result : InvalidValue.instance;
  }

  Object? _named(Value literal, String name, InputPath path, int depth) =>
      switch (environment.schema.typeNamed(name)) {
        final InputObjectType type => ObjectLiteralCoercion(
          environment,
          problems,
          variables,
          this,
        ).coerce(literal, type, path, depth),
        final ScalarType type => _leaves.coerce(literal, type, path),
        final EnumType type => _leaves.coerce(literal, type, path),
        _ => _reject('Type "$name" is not an input type.', path),
      };
}
```

Create `packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'leaf_coercion.dart';

/// Coerces a literal to a scalar or an enum value with graphql-js's
/// `coerceInputLiteral` rules: a literal has a kind, and the kind matters
/// where JSON does not tell (an enum literal is never a string, a string
/// literal is never an enum value, `1.0` is no `Int`).
///
/// The kinds a built-in scalar accepts are checked here; the value itself
/// goes through [LeafCoercion] as the JSON the literal stands for.
final class LiteralLeafCoercion {
  /// Coerces into [problems].
  LiteralLeafCoercion(this.environment, this.problems)
    : _leaves = LeafCoercion(environment, problems);

  static const Printer _printer = Printer();
  static const LiteralConverter _converter = LiteralConverter();

  // The message of each built-in scalar for a literal of a kind it refuses.
  static const Map<String, String> _refusals = {
    'Int': 'Int cannot represent non-integer value',
    'Float': 'Float cannot represent non numeric value',
    'String': 'String cannot represent a non string value',
    'Boolean': 'Boolean cannot represent a non boolean value',
    'ID': 'ID cannot represent a non-string and non-integer value',
  };

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  final LeafCoercion _leaves;

  /// The Dart value of the constant [literal] for the leaf [type] at
  /// [path].
  Object? coerce(Value literal, SchemaType type, InputPath path) {
    if (type is EnumType && literal is! EnumValue) {
      final printed = _printer.print(literal);
      problems.add(
        'Enum "${type.name}" cannot represent non-enum value: $printed.'
        '${_leaves.suggestEnumValue(printed, type)}',
        path,
      );
      return InvalidValue.instance;
    }
    if (type is ScalarType && !_accepts(type.name, literal)) {
      problems.add('${_refusals[type.name]}: ${_printer.print(literal)}', path);
      return InvalidValue.instance;
    }
    return switch (_converter.convert(literal)) {
      DecodeSuccess(:final value) => _leaves.coerce(value, type, path),
      DecodeFailure(:final message) => _reject(message, path),
    };
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  // A scalar that is not built in takes any literal; its codec decides.
  bool _accepts(String scalar, Value literal) => switch (scalar) {
    'Int' => literal is IntValue,
    'Float' => literal is IntValue || literal is FloatValue,
    'String' => literal is StringValue,
    'Boolean' => literal is BooleanValue,
    'ID' => literal is StringValue || literal is IntValue,
    _ => true,
  };
}
```

Create `packages/typed_graphql_server/lib/src/coercion/object_literal_coercion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_messages.dart';
import 'input_object_decoder.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'literal_coercion.dart';

/// Coerces an object literal to an input object (spec 3.10) with the
/// messages and the order of graphql-js's `validateInputLiteral`: the
/// declared fields in declaration order, then the unknown ones, then the
/// `@oneOf` rule; then the definition's `decode` builds the Dart value.
final class ObjectLiteralCoercion {
  /// Coerces into [problems], reading variables from [variables]; the
  /// values of the fields go back through [literals].
  ObjectLiteralCoercion(
    this.environment,
    this.problems,
    this.variables,
    this.literals,
  );

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The coerced variable values.
  final Map<String, Object?> variables;

  /// Coerces the values of the fields.
  final LiteralCoercion literals;

  InputMessages get _messages =>
      InputMessages(includesSuggestions: environment.includesSuggestions);

  /// The Dart value of the object [literal] for [type] at [path], [depth]
  /// levels below the top.
  Object? coerce(
    Value literal,
    InputObjectType type,
    InputPath path,
    int depth,
  ) {
    if (literal is! ObjectValue) {
      return _reject(
        _messages.notObject(type.name, _printer.print(literal)),
        path,
      );
    }
    final coerced = <String, Object?>{};
    var isValid = _coerceFields(literal, type, coerced, path, depth);
    isValid = _checkUnknown(literal, type, path) && isValid;
    isValid = (!type.isOneOf || _checkOneOf(literal, type, path)) && isValid;
    return isValid
        ? InputObjectDecoder(environment, problems).decode(coerced, type, path)
        : InvalidValue.instance;
  }

  bool _coerceFields(
    ObjectValue literal,
    InputObjectType type,
    Map<String, Object?> coerced,
    InputPath path,
    int depth,
  ) {
    final nodes = {for (final f in literal.fields) f.name.value: f.value};
    var isValid = true;
    for (final field in type.fields) {
      if (problems.hasOverflowed) {
        return false;
      }
      final result = _field(literal, type, field, nodes[field.name], (
        path,
        depth,
      ));
      if (result == null) {
        continue;
      }
      if (result.value is InvalidValue) {
        isValid = false;
      } else {
        coerced[field.name] = result.value;
      }
    }
    return isValid;
  }

  // Null: the field has no value and no default, so it is left out.
  ({Object? value})? _field(
    ObjectValue literal,
    InputObjectType type,
    InputValue field,
    Value? given,
    (InputPath, int) place,
  ) {
    final (path, depth) = place;
    if (given is Variable &&
        type.isOneOf &&
        _isOneOfVariableBad(given, type, field, path)) {
      return (value: InvalidValue.instance);
    }
    final isMissing =
        given == null ||
        (given is Variable &&
            !variables.containsKey(given.name.value) &&
            !_isRequired(field));
    if (!isMissing) {
      return (
        value: literals.coerce(
          given,
          field.type,
          path.key(field.name),
          depth + 1,
        ),
      );
    }
    return _absent(literal, type, field, (path, depth));
  }

  // The default of a field the literal does not give, or the error when it
  // is required.
  ({Object? value})? _absent(
    ObjectValue literal,
    InputObjectType type,
    InputValue field,
    (InputPath, int) place,
  ) {
    final (path, depth) = place;
    final fallback = field.defaultValue;
    if (fallback != null) {
      return (
        value: LiteralCoercion(
          environment,
          problems,
          const <String, Object?>{},
        ).coerce(fallback, field.type, path.key(field.name), depth + 1),
      );
    }
    if (_isRequired(field)) {
      final found = _printer.print(literal);
      return (
        value: _reject(
          _messages.missingField(type.name, field.name, found),
          path,
        ),
      );
    }
    return null;
  }

  bool _isRequired(InputValue field) =>
      field.type is NonNullType && field.defaultValue == null;

  // A `@oneOf` field needs a variable that has a non-null value.
  bool _isOneOfVariableBad(
    Variable variable,
    InputObjectType type,
    InputValue field,
    InputPath path,
  ) {
    final name = variable.name.value;
    final String? reason = !variables.containsKey(name)
        ? 'to provide a runtime value'
        : variables[name] == null
        ? 'not to be null'
        : null;
    if (reason == null) {
      return false;
    }
    problems.add(
      'Expected variable "\$$name" provided to field "${field.name}" for '
      'OneOf Input Object type "${type.name}" $reason.',
      path,
    );
    return true;
  }

  bool _checkUnknown(
    ObjectValue literal,
    InputObjectType type,
    InputPath path,
  ) {
    final names = [for (final field in type.fields) field.name];
    var isValid = true;
    for (final node in literal.fields) {
      if (names.contains(node.name.value)) {
        continue;
      }
      isValid = false;
      if (problems.hasOverflowed) {
        break;
      }
      problems.add(
        _messages.unknownField(
          type.name,
          node.name.value,
          names,
          _printer.print(literal),
        ),
        path,
      );
    }
    return isValid;
  }

  bool _checkOneOf(ObjectValue literal, InputObjectType type, InputPath path) {
    final names = {for (final field in type.fields) field.name};
    final known = [
      for (final node in literal.fields)
        if (names.contains(node.name.value)) node,
    ];
    if (known.length != 1) {
      problems.add(_messages.oneOf(type.name), path);
      return false;
    }
    if (known.first.value is NullValue) {
      problems.add(
        _messages.oneOf(type.name),
        path.key(known.first.name.value),
      );
      return false;
    }
    return true;
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }
}
```

In `packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,9 +1,9 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
-import '../builder/arguments.dart';
-import '../execution/graphql_exception.dart';
 import 'coercion_environment.dart';
 import 'coercion_problems.dart';
+import 'input_messages.dart';
+import 'input_object_decoder.dart';
 import 'input_path.dart';
 import 'invalid_value.dart';
 import 'value_coercion.dart';
@@ -18,7 +18,6 @@ final class InputObjectCoercion {
   InputObjectCoercion(this.environment, this.problems, this.values);
 
   static const ValueInspector _inspector = ValueInspector();
-  static const Suggestions _suggestions = Suggestions();
   static const LiteralConverter _converter = LiteralConverter();
 
   /// The schema and the definitions.
@@ -30,6 +29,9 @@ final class InputObjectCoercion {
   /// Coerces the values of the fields.
   final ValueCoercion values;
 
+  InputMessages get _messages =>
+      InputMessages(includesSuggestions: environment.includesSuggestions);
+
   /// The Dart value of [value] for [type] at [path].
   Object? coerce(
     JsonValue value,
@@ -39,8 +41,7 @@ final class InputObjectCoercion {
   ) {
     if (value is! JsonObject) {
       problems.add(
-        'Expected value of type "${type.name}" to be an object, '
-        'found: ${_inspector.inspect(value)}.',
+        _messages.notObject(type.name, _inspector.inspect(value)),
         path,
       );
       return InvalidValue.instance;
@@ -49,7 +50,9 @@ final class InputObjectCoercion {
     var isValid = _coerceFields(value, type, coerced, path, depth);
     isValid = _checkUnknown(value, type, path) && isValid;
     isValid = (!type.isOneOf || _checkOneOf(value, type, path)) && isValid;
-    return isValid ? _decode(coerced, type, path) : InvalidValue.instance;
+    return isValid
+        ? InputObjectDecoder(environment, problems).decode(coerced, type, path)
+        : InvalidValue.instance;
   }
 
   bool _coerceFields(
@@ -91,8 +94,11 @@ final class InputObjectCoercion {
     }
     if (field.type is NonNullType) {
       problems.add(
-        'Expected value of type "${type.name}" to include required field '
-        '"${field.name}", found: ${_inspector.inspect(value)}.',
+        _messages.missingField(
+          type.name,
+          field.name,
+          _inspector.inspect(value),
+        ),
         path,
       );
       return InvalidValue.instance;
@@ -132,13 +138,13 @@ final class InputObjectCoercion {
       if (problems.hasOverflowed) {
         break;
       }
-      final suggestion = environment.includesSuggestions
-          ? _suggestions.didYouMean(_suggestions.listFor(name, names))
-          : '';
-      final lead = suggestion.isEmpty ? ', found' : '.$suggestion Found';
       problems.add(
-        'Expected value of type "${type.name}" not to include unknown field '
-        '"$name"$lead: ${_inspector.inspect(value)}.',
+        _messages.unknownField(
+          type.name,
+          name,
+          names,
+          _inspector.inspect(value),
+        ),
         path,
       );
     }
@@ -146,9 +152,7 @@ final class InputObjectCoercion {
   }
 
   bool _checkOneOf(JsonObject value, InputObjectType type, InputPath path) {
-    final message =
-        'Within OneOf Input Object type "${type.name}", exactly one field '
-        'must be specified, and the value for that field must be non-null.';
+    final message = _messages.oneOf(type.name);
     final known = {for (final field in type.fields) field.name};
     final given = [
       for (final name in value.fields.keys)
@@ -164,28 +168,4 @@ final class InputObjectCoercion {
     }
     return isValid;
   }
-
-  Object? _decode(
-    Map<String, Object?> coerced,
-    InputObjectType type,
-    InputPath path,
-  ) {
-    final definition = environment.bindings.inputObjects[type.name];
-    if (definition == null) {
-      return _reject('Input object "${type.name}" has no definition.', path);
-    }
-    try {
-      return definition.decode(Arguments(definition.fields, coerced));
-    } on GraphQLException catch (exception) {
-      problems.add(exception.message, path, extensions: exception.extensions);
-    } on Object catch (error, stackTrace) {
-      problems.add(
-        'Unexpected error.',
-        path,
-        code: DiagnosticCode.inputDecodeFailed,
-        thrown: (error: error, stackTrace: stackTrace),
-      );
-    }
-    return InvalidValue.instance;
-  }
 }
```

In `packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -79,19 +79,21 @@ final class LeafCoercion {
       final printed = _inspector.inspect(value);
       return _reject(
         'Enum "${type.name}" cannot represent non-string value: $printed.'
-        '${_didYouMean(printed, type)}',
+        '${suggestEnumValue(printed, type)}',
         path,
       );
     }
     return definition.valueNamed(value.value) ??
         _reject(
           'Value "${value.value}" does not exist in "${type.name}" enum.'
-          '${_didYouMean(value.value, type)}',
+          '${suggestEnumValue(value.value, type)}',
           path,
         );
   }
 
-  String _didYouMean(String input, EnumType type) {
+  /// graphql-js's "Did you mean the enum value ..." text for [input], empty
+  /// when suggestions are off.
+  String suggestEnumValue(String input, EnumType type) {
     if (!environment.includesSuggestions) {
       return '';
     }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/argument_coercion_test.dart test/coercion/conditional_directives_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart packages/typed_graphql_server/lib/src/coercion/conditional_directives.dart packages/typed_graphql_server/lib/src/coercion/input_messages.dart packages/typed_graphql_server/lib/src/coercion/input_object_coercion.dart packages/typed_graphql_server/lib/src/coercion/input_object_decoder.dart packages/typed_graphql_server/lib/src/coercion/leaf_coercion.dart packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart packages/typed_graphql_server/lib/src/coercion/object_literal_coercion.dart packages/typed_graphql_server/test/coercion/argument_coercion_test.dart packages/typed_graphql_server/test/coercion/coercion_fixture.dart packages/typed_graphql_server/test/coercion/conditional_directives_test.dart
git commit -q -m "feat(typed_graphql_server): coerce field arguments" \
  -m "ArgumentCoercion coerces a field's or directive's arguments from literals, substituting coerced variables, with graphql-js's getArgumentValues messages (GQL313); ConditionalDirectives reads @skip/@include." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Operation plans and the plan cache

Add `OperationSelection` (`GQL320`-`GQL323`), the `OperationPlanner`, `OperationPlan`, `PlanNode`, `FieldPlan`, the explicit-stack `FieldCollector`, `ConditionKey`, `LruMap` and `PlanCache`, and `BuildOptions.planCacheSize`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/plan/condition_key.dart`, `packages/typed_graphql_server/lib/src/plan/condition_variables.dart`, `packages/typed_graphql_server/lib/src/plan/defer_directive.dart`, `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, `packages/typed_graphql_server/lib/src/plan/field_collector.dart`, `packages/typed_graphql_server/lib/src/plan/field_plan.dart`, `packages/typed_graphql_server/lib/src/plan/lru_map.dart`, `packages/typed_graphql_server/lib/src/plan/operation_plan.dart`, `packages/typed_graphql_server/lib/src/plan/operation_planner.dart`, `packages/typed_graphql_server/lib/src/plan/operation_selection.dart`, `packages/typed_graphql_server/lib/src/plan/operation_selection_result.dart`, `packages/typed_graphql_server/lib/src/plan/plan_cache.dart`, `packages/typed_graphql_server/lib/src/plan/plan_context.dart`, `packages/typed_graphql_server/lib/src/plan/plan_node.dart`, `packages/typed_graphql_server/lib/src/plan/plan_result.dart`, `packages/typed_graphql_server/lib/src/plan/value_variables.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/build_options.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/plan/field_collection_test.dart`, `packages/typed_graphql_server/test/plan/operation_selection_test.dart`, `packages/typed_graphql_server/test/plan/plan_cache_test.dart`, `packages/typed_graphql_server/test/plan/plan_fixture.dart`

**Interfaces:**
- Consumes: Tasks 2-3.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// plan/condition_key.dart
final class ConditionKey
  ConditionKey(List<bool?> values) : values = List.unmodifiable(values)
  bool operator ==(Object other)
  int get hashCode

// plan/condition_variables.dart
final class ConditionVariables
  List<String> find(…)

// plan/defer_directive.dart
final class DeferDirective
  DeferDirective(this.environment) : _arguments = ArgumentCoercion(environment)
  CoercionResult isDeferred(…)

// plan/field_accumulator.dart
final class FieldAccumulator
  FieldAccumulator(…)
  void add(…)
  FieldPlan build(PlanContext context, ObjectType parentType)

// plan/field_collector.dart
final class FieldCollector
  FieldCollector(this.context)
  PlanNode collect(…)
final class _Frame
  bool get isFinished
  Selection next()
sealed class _Step
final class _Done
final class _Descend
final class _Failed

// plan/field_plan.dart
final class FieldPlan
  FieldPlan(…)
  PlanNode childFor(ObjectType type)
  CoercionResult argumentsFor(Map<String, Object?> variables)

// plan/lru_map.dart
final class LruMap<K, V
  int get length
  V? use(K key)
  void store(K key, V value)
  bool contains(K key)

// plan/operation_plan.dart
final class OperationPlan
  OperationPlan(…)
  ConditionKey keyFor(Map<String, Object?> variables)
  PlanNode rootFor(ConditionKey key)

// plan/operation_planner.dart
final class OperationPlanner
  PlanResult plan(Document document, String? operationName)

// plan/operation_selection.dart
final class OperationSelection
  OperationSelectionResult select(Document document, String? operationName)

// plan/operation_selection_result.dart
sealed class OperationSelectionResult
final class OperationSelected
final class OperationRejected

// plan/plan_cache.dart
final class PlanCache(…)
  int get hitCount
  int get missCount
  int get length
  OperationPlan? lookup(Document document, String? operationName)
  void store(Document document, String? operationName, OperationPlan plan)

// plan/plan_context.dart
final class PlanContext
  PlanContext(this.environment, this.fragments, this.conditionValues)
  Schema get schema

// plan/plan_node.dart
final class PlanNode
  PlanNode(…)

// plan/plan_result.dart
sealed class PlanResult
final class PlanReady
final class PlanRejected

// plan/value_variables.dart
final class ValueVariables
  bool occursIn(List<Argument> arguments)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/plan/field_collection_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/plan/field_plan.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';

import 'plan_fixture.dart';

void main() {
  final fx = PlanFixture();

  group('collection', () {
    test('keeps the order of first appearance and merges by response key', () {
      final node = fx.root('{ b a: a c b: a b }');
      expect(fx.keys(node), ['b', 'a', 'c']);
      expect(node.fields.first.nodes, hasLength(3));
    });

    test('merges the nodes of one key across fragments', () {
      final node = fx.root('{ a ...F a } fragment F on Query { a b }');
      expect(fx.keys(node), ['a', 'b']);
      expect(node.fields.first.nodes, hasLength(3));
    });

    test('an alias is the response key and the field name stays', () {
      final plan = fx.root('{ x: a }').fields.single;
      expect(plan.responseKey, 'x');
      expect(plan.fieldName, 'a');
      expect(plan.field?.name, 'a');
    });

    test('__typename has no schema field', () {
      expect(fx.root('{ __typename }').fields.single.field, isNull);
    });
  });

  group('skip and include', () {
    test('literals drop and keep fields', () {
      final node = fx.root(
        '{ a @skip(if: true) b @skip(if: false) c @include(if: false) '
        'a @include(if: true) }',
      );
      expect(fx.keys(node), ['b', 'a']);
    });

    test('variables decide per request', () {
      const text = r'query ($v: Boolean!) { a @skip(if: $v) b }';
      expect(fx.keys(fx.root(text, {'v': true})), ['b']);
      expect(fx.keys(fx.root(text, {'v': false})), ['a', 'b']);
    });

    test('skip wins over include', () {
      expect(
        fx.root('{ a @skip(if: true) @include(if: true) b }').fields,
        hasLength(1),
      );
    });

    test('a skipped fragment spread and inline fragment drop their fields', () {
      final node = fx.root(
        '{ ...F @skip(if: true) ... @include(if: false) { c } b } '
        'fragment F on Query { a }',
      );
      expect(fx.keys(node), ['b']);
    });

    test('variables in fragments are condition variables', () {
      final plan = fx.plan(
        r'query ($v: Boolean!, $w: Boolean!) { ...F } '
        r'fragment F on Query { a @skip(if: $v) ... @include(if: $w) { b } }',
      );
      expect(plan.conditionVariables, ['v', 'w']);
    });

    test('a variable without a boolean is a problem of the node', () {
      final node = fx.root(r'query ($v: Boolean) { a @skip(if: $v) }');
      expect(node.fields, isEmpty);
      expect(node.problem?.message, contains('@skip(if:)'));
    });
  });

  group('type conditions', () {
    final dog = fx.objectType('Dog');
    final cat = fx.objectType('Cat');

    test('a fragment on an interface applies to its implementations', () {
      final field = fx
          .root('{ pet { ...P } } fragment P on Pet { name }')
          .fields
          .single;
      expect(fx.keys(field.childFor(dog)), ['name']);
    });

    test('a fragment on another object type does not apply', () {
      final field = fx
          .root('{ pet { ... on Cat { meows } name } }')
          .fields
          .single;
      expect(fx.keys(field.childFor(dog)), ['name']);
      expect(fx.keys(field.childFor(cat)), ['meows', 'name']);
    });

    test('fragments on a union apply to its members', () {
      final field = fx
          .root(
            '{ found { ... on Found { __typename } ... on Dog { barks } } }',
          )
          .fields
          .single;
      expect(fx.keys(field.childFor(cat)), ['__typename']);
      expect(fx.keys(field.childFor(dog)), ['__typename', 'barks']);
    });

    test('the child node is the same object for the same type', () {
      final field = fx.root('{ pet { name } }').fields.single;
      expect(field.childFor(dog), same(field.childFor(dog)));
      expect(field.childFor(dog), isNot(same(field.childFor(cat))));
    });

    test('the selection sets of merged nodes are collected together', () {
      final field = fx.root('{ pet { name } pet { barks } }').fields.single;
      expect(fx.keys(field.childFor(fx.objectType('Dog'))), ['name', 'barks']);
    });
  });

  group('fragments', () {
    test('a fragment spread twice is collected once', () {
      final node = fx.root('{ ...F ...F } fragment F on Query { a }');
      expect(node.fields.single.nodes, hasLength(1));
    });

    test('a fragment reached by two routes is collected once', () {
      final node = fx.root(
        '{ ...A ...B } fragment A on Query { ...C } '
        'fragment B on Query { ...C } fragment C on Query { a }',
      );
      expect(node.fields.single.nodes, hasLength(1));
    });

    test('an unknown fragment adds nothing', () {
      expect(fx.keys(fx.root('{ ...Nope a }')), ['a']);
    });

    test('a fan-out of 2^20 spreads is planned in linear time', () {
      const depth = 20;
      final text = StringBuffer('{ ...F0 }');
      for (var i = 0; i < depth; i++) {
        text.write(
          'fragment F$i on Query { f$i: a ...F${i + 1} ...F${i + 1} }',
        );
      }
      text.write('fragment F$depth on Query { f$depth: a }');
      final stopwatch = Stopwatch()..start();
      final node = fx.root(text.toString());
      stopwatch.stop();
      expect(node.fields, hasLength(depth + 1));
      expect(
        [for (final field in node.fields) field.nodes.length],
        everyElement(1),
        reason: 'each fragment was expanded once, not 2^20 times',
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a deeply nested selection does not overflow the stack', () {
      // Built by hand: the parser bounds nesting by `maxDepth`.
      var selectionSet = SelectionSet([Field(null, const Name('a'))]);
      for (var i = 0; i < 20000; i++) {
        selectionSet = SelectionSet([InlineFragment(null, selectionSet)]);
      }
      final document = Document([
        OperationDefinition(OperationType.query, selectionSet),
      ]);
      final plan = switch (fx.result(document)) {
        PlanReady(:final plan) => plan,
        PlanRejected() => fail('expected a plan'),
      };
      expect(fx.keys(plan.rootFor(plan.keyFor(const <String, Object?>{}))), [
        'a',
      ]);
    });
  });

  group('defer', () {
    test('fields of a deferred fragment are deferred', () {
      final node = fx.root('{ a ... @defer { b } }');
      expect([for (final f in node.fields) f.isDeferred], [false, true]);
    });

    test('a field also written outside the fragment is not deferred', () {
      final node = fx.root('{ ... @defer { a } a }');
      expect(node.fields.single.isDeferred, isFalse);
    });

    test('if: false does not defer', () {
      final node = fx.root('{ ... @defer(if: false) { a } }');
      expect(node.fields.single.isDeferred, isFalse);
    });

    test('a variable if is part of the key', () {
      const text = r'query ($d: Boolean!) { ... @defer(if: $d) { a } }';
      expect(fx.root(text, {'d': true}).fields.single.isDeferred, isTrue);
      expect(fx.root(text, {'d': false}).fields.single.isDeferred, isFalse);
    });

    test('a spread nested in a deferred fragment is deferred', () {
      final node = fx.root('{ ... @defer { ...F } } fragment F on Query { a }');
      expect(node.fields.single.isDeferred, isTrue);
    });
  });

  group('arguments', () {
    List<Object?> valuesOf(FieldPlan plan, [Map<String, Object?>? variables]) =>
        switch (plan.argumentsFor(variables ?? const {})) {
          CoercionSuccess(value: final Map<String, Object?> map) => [
            for (final entry in map.entries) '${entry.key}=${entry.value}',
          ],
          CoercionSuccess() => fail('a map'),
          CoercionFailure(:final problems) => [problems.single.message],
        };

    test('constant arguments are coerced', () {
      final plan = fx.root('{ user(id: 3) }').fields.single;
      expect(valuesOf(plan), ['id=3']);
    });

    test('constant arguments are coerced once', () {
      final plan = fx.root('{ user(id: 3) }').fields.single;
      expect(plan.argumentsFor(const {}), same(plan.argumentsFor(const {})));
    });

    test('a constant failure is the problem and is remembered', () {
      final plan = fx.root('{ user }').fields.single;
      expect(valuesOf(plan), [
        'Argument "Query.user(id:)" of required type "Int!" was not provided.',
      ]);
      expect(plan.argumentsFor(const {}), same(plan.argumentsFor(const {})));
    });

    test('arguments with variables are coerced for each request', () {
      final plan = fx.root(r'query ($i: Int!) { user(id: $i) }').fields.single;
      expect(valuesOf(plan, {'i': 1}), ['id=1']);
      expect(valuesOf(plan, {'i': 2}), ['id=2']);
    });

    test('a field with no arguments gets none', () {
      expect(valuesOf(fx.root('{ a }').fields.single), isEmpty);
    });

    test('__typename gets none', () {
      expect(valuesOf(fx.root('{ __typename }').fields.single), isEmpty);
    });
  });
}
```

Create `packages/typed_graphql_server/test/plan/operation_selection_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';

import 'plan_fixture.dart';

void main() {
  final fx = PlanFixture();

  GraphQLError rejected(String text, [String? name]) =>
      switch (fx.result(fx.parse(text), name)) {
        PlanRejected(:final error) => error,
        PlanReady() => fail('expected a request error'),
      };

  String codeOf(GraphQLError error) =>
      (error.extensions!.fields['code']! as JsonString).value;

  test('a lone anonymous operation is chosen without a name', () {
    expect(fx.plan('{ a }').operation.name, isNull);
  });

  test('the operation with the requested name is chosen', () {
    final plan = fx.plan('query One { a } query Two { b }', 'Two');
    expect(plan.operation.name?.value, 'Two');
  });

  test('a document without an operation is GQL322', () {
    final error = rejected('fragment F on Query { a }');
    expect(error.message, 'Must provide an operation.');
    expect(codeOf(error), 'GQL322');
  });

  test('several operations and no name is GQL321', () {
    final error = rejected('query One { a } query Two { b }');
    expect(
      error.message,
      'Must provide operation name if query contains multiple operations.',
    );
    expect(codeOf(error), 'GQL321');
  });

  test('an unknown operation name is GQL320', () {
    final error = rejected('query One { a }', 'Nope');
    expect(error.message, 'Unknown operation named "Nope".');
    expect(codeOf(error), 'GQL320');
  });

  test('a missing root type is GQL323', () {
    final error = rejected('mutation { a }');
    expect(
      error.message,
      'Schema is not configured to execute mutation operation.',
    );
    expect(codeOf(error), 'GQL323');
  });
}
```

Create `packages/typed_graphql_server/test/plan/plan_cache_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/plan/condition_key.dart';
import 'package:typed_graphql_server/src/plan/lru_map.dart';
import 'package:typed_graphql_server/src/plan/operation_plan.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';

import 'plan_fixture.dart';

void main() {
  OperationPlan planned(PlanFixture fx, Document document, [String? name]) =>
      switch (fx.result(document, name)) {
        PlanReady(:final plan) => plan,
        PlanRejected() => fail('expected a plan'),
      };

  group('PlanCache', () {
    test('the same document and name give the same plan', () {
      final fx = PlanFixture();
      final document = fx.parse('{ a }');
      expect(planned(fx, document), same(planned(fx, document)));
      expect(fx.cache.hitCount, 1);
      expect(fx.cache.missCount, 1);
    });

    test('an equal document that is another object has its own plan', () {
      final fx = PlanFixture();
      expect(
        planned(fx, fx.parse('{ a }')),
        isNot(same(planned(fx, fx.parse('{ a }')))),
      );
    });

    test('the operation name is part of the key', () {
      final fx = PlanFixture();
      final document = fx.parse('query One { a } query Two { b }');
      expect(
        planned(fx, document, 'One'),
        isNot(same(planned(fx, document, 'Two'))),
      );
    });

    test('a request error is not cached', () {
      final fx = PlanFixture();
      fx.result(fx.parse('{ a }'), 'Nope');
      expect(fx.cache.length, 0);
    });

    test('the least recently used plan is evicted', () {
      final fx = PlanFixture(planCacheSize: 2);
      final first = fx.parse('{ a }');
      final second = fx.parse('{ b }');
      final third = fx.parse('{ c }');
      final firstPlan = planned(fx, first);
      planned(fx, second);
      planned(fx, first); // a hit makes `second` the oldest
      planned(fx, third);
      expect(planned(fx, first), same(firstPlan));
      final missesBefore = fx.cache.missCount;
      planned(fx, second);
      expect(fx.cache.missCount, missesBefore + 1);
      expect(fx.cache.length, 2);
    });

    test('a size of zero keeps no plan', () {
      final fx = PlanFixture(planCacheSize: 0);
      final document = fx.parse('{ a }');
      expect(planned(fx, document), isNot(same(planned(fx, document))));
    });
  });

  group('LruMap', () {
    test('contains does not count as a use', () {
      final map = LruMap<int, String>(2)
        ..store(1, 'one')
        ..store(2, 'two');
      expect(map.contains(1), isTrue);
      map.store(3, 'three');
      expect(map.contains(1), isFalse);
      expect(map.contains(2), isTrue);
    });
  });

  group('condition keys', () {
    test('equal booleans give equal keys', () {
      expect(ConditionKey([true, null]), ConditionKey([true, null]));
      expect(
        ConditionKey([true, null]).hashCode,
        ConditionKey([true, null]).hashCode,
      );
      expect(ConditionKey([true]), isNot(ConditionKey([false])));
      expect(ConditionKey([true]), isNot(ConditionKey([true, true])));
    });

    test('the root node is memoised per key', () {
      final fx = PlanFixture();
      final plan = fx.plan(r'query ($v: Boolean!) { a @skip(if: $v) b }');
      final yes = plan.keyFor({'v': true});
      final no = plan.keyFor({'v': false});
      expect(plan.rootFor(yes), same(plan.rootFor(yes)));
      expect(plan.rootFor(yes), isNot(same(plan.rootFor(no))));
    });

    test('a plan remembers at most 16 keys, least recently used first', () {
      final fx = PlanFixture();
      final names = [for (var i = 0; i < 17; i++) 'v$i'];
      final plan = fx.plan(
        'query (${[for (final n in names) '\$$n: Boolean!'].join(', ')}) '
        '{ ${[for (final n in names) 'a @skip(if: \$$n)'].join(' ')} }',
      );
      ConditionKey keyWith(int index) => plan.keyFor({
        for (var i = 0; i < names.length; i++) names[i]: i == index,
      });
      final first = plan.rootFor(keyWith(0));
      for (var i = 1; i < OperationPlan.maxConditionKeys; i++) {
        plan.rootFor(keyWith(i));
      }
      expect(plan.rootFor(keyWith(0)), same(first));
      final second = plan.rootFor(keyWith(1));
      plan.rootFor(keyWith(16)); // evicts the oldest, which is key 2
      expect(plan.rootFor(keyWith(0)), same(first));
      expect(plan.rootFor(keyWith(1)), same(second));
    });
  });
}
```

Create `packages/typed_graphql_server/test/plan/plan_fixture.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_environment.dart';
import 'package:typed_graphql_server/src/plan/operation_plan.dart';
import 'package:typed_graphql_server/src/plan/operation_planner.dart';
import 'package:typed_graphql_server/src/plan/plan_cache.dart';
import 'package:typed_graphql_server/src/plan/plan_node.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Animal {
  const Animal();
}

final class Cat extends Animal {
  const Cat();
}

final class Dog extends Animal {
  const Dog();
}

/// A schema with an interface, a union and arguments, and parsing helpers.
final class PlanFixture {
  PlanFixture({int planCacheSize = 1000}) {
    final b = ExecutableSchemaBuilder<Object?>();
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
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        for (final name in ['a', 'b', 'c'])
          t.field(name, b.string).pure((_) => name),
        t.field('pet', pet).pure((_) => const Dog()),
        t.field('found', found).pure((_) => const Cat()),
        t
            .field('user', b.string, args: [Arg('id', b.int)])
            .resolve((parent, args, context, info) => 'u'),
        t
            .field('tagged', b.string, args: [Arg('tag', b.string)])
            .resolve((parent, args, context, info) => 't'),
      ],
    );
    final built = b.build(
      query: query,
      options: BuildOptions(
        includesDeferAndStream: true,
        planCacheSize: planCacheSize,
      ),
    );
    environment = CoercionEnvironment(built.schema.schema, built.bindings);
    cache = PlanCache(planCacheSize);
    planner = OperationPlanner(environment, cache);
  }

  late final CoercionEnvironment environment;
  late final PlanCache cache;
  late final OperationPlanner planner;

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  PlanResult result(Document document, [String? name]) =>
      planner.plan(document, name);

  OperationPlan plan(String text, [String? name]) =>
      switch (result(parse(text), name)) {
        PlanReady(:final plan) => plan,
        PlanRejected(:final error) => throw StateError(error.message),
      };

  /// The root node of [text] with the given boolean variables.
  PlanNode root(String text, [Map<String, Object?> variables = const {}]) {
    final operationPlan = plan(text);
    return operationPlan.rootFor(operationPlan.keyFor(variables));
  }

  /// The response keys of [node], in order.
  List<String> keys(PlanNode node) => [
    for (final field in node.fields) field.responseKey,
  ];

  ObjectType objectType(String name) =>
      environment.schema.typeNamed(name)! as ObjectType;
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/plan/field_collection_test.dart test/plan/operation_selection_test.dart test/plan/plan_cache_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/plan/condition_key.dart`:

```dart
/// The values of the variables that `@skip`, `@include` and `@defer` read in
/// one request, in the order the plan lists them: two requests with equal
/// keys collect the same fields (spec 6.3.2), so they share a plan node.
///
/// An entry is null when the request has no boolean for that variable; the
/// collection then reports the argument problem.
final class ConditionKey {
  /// Creates a key over [values].
  ConditionKey(List<bool?> values) : values = List.unmodifiable(values);

  /// The booleans, one per condition variable.
  final List<bool?> values;

  @override
  bool operator ==(Object other) {
    if (other is! ConditionKey || other.values.length != values.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      if (values[i] != other.values[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}
```

Create `packages/typed_graphql_server/lib/src/plan/condition_variables.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Finds the variables that decide which fields an operation collects: the
/// ones written as the `if` argument of `@skip`, `@include` or `@defer` in
/// the operation or in a fragment it can reach (R4.8).
final class ConditionVariables {
  /// Searches without state.
  const ConditionVariables();

  static const Set<String> _directives = {'skip', 'include', 'defer'};

  /// The names (without `$`) in order of discovery, each once. Selections
  /// are walked with an explicit stack and each fragment once, so a document
  /// of any shape costs time linear in its size.
  List<String> find(
    OperationDefinition operation,
    Map<String, FragmentDefinition> fragments,
  ) {
    final names = <String>{};
    final visitedFragments = <String>{};
    final pending = <SelectionSet>[operation.selectionSet];
    while (pending.isNotEmpty) {
      for (final selection in pending.removeLast().selections) {
        _addNames(selection, names);
        final next = _nested(selection, fragments, visitedFragments);
        if (next != null) {
          pending.add(next);
        }
      }
    }
    return List.unmodifiable(names);
  }

  // The selection set to walk next inside [selection]; a fragment only the
  // first time it is spread.
  SelectionSet? _nested(
    Selection selection,
    Map<String, FragmentDefinition> fragments,
    Set<String> visitedFragments,
  ) => switch (selection) {
    Field(:final selectionSet) => selectionSet,
    InlineFragment(:final selectionSet) => selectionSet,
    FragmentSpread(name: Name(:final value)) =>
      visitedFragments.add(value) ? fragments[value]?.selectionSet : null,
  };

  void _addNames(Selection selection, Set<String> names) {
    final directives = switch (selection) {
      Field(:final directives) => directives,
      InlineFragment(:final directives) => directives,
      FragmentSpread(:final directives) => directives,
    };
    for (final directive in directives) {
      if (!_directives.contains(directive.name.value)) {
        continue;
      }
      for (final argument in directive.arguments) {
        if (argument.name.value == 'if' && argument.value is Variable) {
          names.add((argument.value as Variable).name.value);
        }
      }
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/plan/defer_directive.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/argument_coercion.dart';
import '../coercion/coercion_environment.dart';
import '../coercion/coercion_result.dart';

/// Reads `@defer(if:)` during field collection. `@defer` runs inline in M5
/// (spec section 18), so the plan only records which fields a deferred
/// fragment holds.
final class DeferDirective {
  /// Reads in [environment].
  DeferDirective(this.environment) : _arguments = ArgumentCoercion(environment);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  final ArgumentCoercion _arguments;

  /// Whether a fragment written with [directives] is deferred: a
  /// [CoercionSuccess] holding a `bool`, or the failure of an argument. A
  /// schema without `@defer` defers nothing, and `if` defaults to true.
  CoercionResult isDeferred(
    List<Directive> directives,
    Map<String, Object?> variables,
  ) {
    final definition = environment.schema.directiveNamed('defer');
    if (definition == null) {
      return const CoercionSuccess(false);
    }
    for (final directive in directives) {
      if (directive.name.value != 'defer') {
        continue;
      }
      return switch (_arguments.coerce(
        '@defer',
        definition.arguments,
        directive.arguments,
        variables,
      )) {
        CoercionSuccess(value: final Map<String, Object?> values) =>
          CoercionSuccess(values['if'] != false),
        CoercionSuccess() => throw StateError('Argument values are a map.'),
        final CoercionFailure failure => failure,
      };
    }
    return const CoercionSuccess(false);
  }
}
```

Create `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'field_plan.dart';
import 'plan_context.dart';

/// The field nodes collected so far under one response key.
final class FieldAccumulator {
  /// Starts with the first [node] met for the key.
  FieldAccumulator(Field node, {required this.isDeferred}) : _nodes = {node};

  // Nodes compare by identity, so a node reached twice (a fragment visited
  // again after a deferred visit) is kept once.
  final Set<Field> _nodes;

  /// Whether every node added so far is deferred.
  bool isDeferred;

  /// Adds [node]; the key stays deferred only while every node is.
  void add(Field node, {required bool isDeferred}) {
    _nodes.add(node);
    this.isDeferred = this.isDeferred && isDeferred;
  }

  /// The plan of the key for [parentType].
  FieldPlan build(PlanContext context, ObjectType parentType) {
    final first = _nodes.first;
    return FieldPlan(
      responseKey: first.alias?.value ?? first.name.value,
      fieldName: first.name.value,
      nodes: _nodes.toList(),
      parentType: parentType,
      field: parentType.fieldNamed(first.name.value),
      isDeferred: isDeferred,
      context: context,
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/plan/field_collector.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_problem.dart';
import '../coercion/coercion_result.dart';
import 'field_accumulator.dart';
import 'plan_context.dart';
import 'plan_node.dart';

/// September2025 section 6.3.2 `CollectFields` and `CollectSubfields`, with
/// graphql-js 17's `collectFieldsImpl` rules for `@skip`, `@include`, type
/// conditions and fragments (R4.8).
///
/// Selections are walked with an explicit stack, so a deeply nested document
/// cannot overflow it, and each fragment is expanded once per collection (a
/// repeat adds the same fields again), so a chain of fragments that each
/// spread the next one twice costs time linear in the document.
final class FieldCollector {
  /// Collects in [context].
  FieldCollector(this.context);

  /// What collection reads.
  final PlanContext context;

  /// Collects the fields of [selectionSets] for [runtimeType] into a node.
  /// Several sets share one run, as the field nodes of one response key do.
  PlanNode collect(
    ObjectType runtimeType,
    Iterable<SelectionSet> selectionSets,
  ) {
    final groups = <String, FieldAccumulator>{};
    final visitedFragments = <String, bool>{};
    for (final selectionSet in selectionSets) {
      final problem = _walk(
        runtimeType,
        selectionSet,
        groups,
        visitedFragments,
      );
      if (problem != null) {
        return PlanNode(runtimeType, const [], problem: problem);
      }
    }
    return PlanNode(runtimeType, [
      for (final group in groups.values) group.build(context, runtimeType),
    ]);
  }

  CoercionProblem? _walk(
    ObjectType runtimeType,
    SelectionSet root,
    Map<String, FieldAccumulator> groups,
    Map<String, bool> visitedFragments,
  ) {
    final stack = [_Frame(root.selections, isDeferred: false)];
    while (stack.isNotEmpty) {
      final frame = stack.last;
      if (frame.isFinished) {
        stack.removeLast();
        continue;
      }
      final step = _visit(
        frame.next(),
        frame.isDeferred,
        runtimeType,
        groups,
        visitedFragments,
      );
      switch (step) {
        case _Descend(:final frame):
          stack.add(frame);
        case _Failed(:final problem):
          return problem;
        case _Done():
          break;
      }
    }
    return null;
  }

  _Step _visit(
    Selection selection,
    bool isDeferred,
    ObjectType runtimeType,
    Map<String, FieldAccumulator> groups,
    Map<String, bool> visitedFragments,
  ) {
    final directives = switch (selection) {
      Field(:final directives) => directives,
      InlineFragment(:final directives) => directives,
      FragmentSpread(:final directives) => directives,
    };
    switch (context.conditionals.isIncluded(
      directives,
      context.conditionValues,
    )) {
      case CoercionSuccess(value: false):
        return const _Done();
      case CoercionFailure(:final problems):
        return _Failed(problems.first);
      case CoercionSuccess():
        break;
    }
    return switch (selection) {
      final Field field => _addField(field, isDeferred, groups),
      final InlineFragment fragment => _enterInline(
        fragment,
        isDeferred,
        runtimeType,
      ),
      final FragmentSpread spread => _enterSpread(
        spread,
        isDeferred,
        runtimeType,
        visitedFragments,
      ),
    };
  }

  _Step _addField(
    Field field,
    bool isDeferred,
    Map<String, FieldAccumulator> groups,
  ) {
    final key = field.alias?.value ?? field.name.value;
    final group = groups[key];
    if (group == null) {
      groups[key] = FieldAccumulator(field, isDeferred: isDeferred);
    } else {
      group.add(field, isDeferred: isDeferred);
    }
    return const _Done();
  }

  _Step _enterInline(
    InlineFragment fragment,
    bool isDeferred,
    ObjectType runtimeType,
  ) {
    if (!_matches(fragment.typeCondition, runtimeType)) {
      return const _Done();
    }
    return switch (context.defers.isDeferred(
      fragment.directives,
      context.conditionValues,
    )) {
      CoercionSuccess(:final value) => _Descend(
        _Frame(
          fragment.selectionSet.selections,
          isDeferred: isDeferred || value == true,
        ),
      ),
      final CoercionFailure failure => _Failed(failure.problems.first),
    };
  }

  _Step _enterSpread(
    FragmentSpread spread,
    bool isDeferred,
    ObjectType runtimeType,
    Map<String, bool> visitedFragments,
  ) {
    final name = spread.name.value;
    final fragment = context.fragments[name];
    if (fragment == null || !_matches(fragment.typeCondition, runtimeType)) {
      return const _Done();
    }
    switch (context.defers.isDeferred(
      spread.directives,
      context.conditionValues,
    )) {
      case CoercionSuccess(value: final bool isNewlyDeferred):
        // graphql-js: a deferred spread is skipped once the fragment was
        // visited at all; a plain one is skipped once visited plainly, and
        // a plain visit after a deferred one expands it again.
        final visitedAsDeferred = visitedFragments[name];
        if (isNewlyDeferred
            ? visitedAsDeferred != null
            : visitedAsDeferred == false) {
          return const _Done();
        }
        visitedFragments[name] = isNewlyDeferred;
        return _Descend(
          _Frame(
            fragment.selectionSet.selections,
            isDeferred: isDeferred || isNewlyDeferred,
          ),
        );
      case CoercionSuccess():
        throw StateError('A defer condition is a boolean.');
      case final CoercionFailure failure:
        return _Failed(failure.problems.first);
    }
  }

  // Spec 6.3.2 `DoesFragmentTypeApply`: no condition always applies; an
  // object type applies to itself; an abstract type to its possible types.
  bool _matches(NamedType? condition, ObjectType runtimeType) {
    if (condition == null) {
      return true;
    }
    final type = context.schema.typeNamed(condition.name.value);
    if (type == null) {
      return false;
    }
    if (type.name == runtimeType.name) {
      return true;
    }
    return context.schema.isSubType(type, runtimeType);
  }
}

// A position in a list of selections.
final class _Frame {
  _Frame(this._selections, {required this.isDeferred});

  final List<Selection> _selections;
  final bool isDeferred;
  int _index = 0;

  bool get isFinished => _index >= _selections.length;

  Selection next() => _selections[_index++];
}

sealed class _Step {
  const _Step();
}

final class _Done extends _Step {
  const _Done();
}

final class _Descend extends _Step {
  const _Descend(this.frame);

  final _Frame frame;
}

final class _Failed extends _Step {
  const _Failed(this.problem);

  final CoercionProblem problem;
}
```

Create `packages/typed_graphql_server/lib/src/plan/field_plan.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/argument_coercion.dart';
import '../coercion/coercion_result.dart';
import 'field_collector.dart';
import 'plan_context.dart';
import 'plan_node.dart';
import 'value_variables.dart';

/// What the executor does for one response key of a [PlanNode]: the field
/// nodes merged under the key, their schema field, their arguments, and the
/// nodes of the selection they carry for each runtime type, built on first
/// use and remembered (R4.8).
final class FieldPlan {
  /// Creates the plan of [fieldName] collected for [parentType].
  FieldPlan({
    required this.responseKey,
    required this.fieldName,
    required List<Field> nodes,
    required this.parentType,
    required this.field,
    required this.isDeferred,
    required this.context,
  }) : nodes = List.unmodifiable(nodes),
       _hasConstantArguments =
           field != null &&
           !const ValueVariables().occursIn(nodes.first.arguments);

  /// The key in the response: the alias, else the field name.
  final String responseKey;

  /// The name of the field.
  final String fieldName;

  /// The field nodes of the key, in document order; they agree on name and
  /// arguments, so the first one speaks for all.
  final List<Field> nodes;

  /// The object type the field was collected for.
  final ObjectType parentType;

  /// The schema field, null for `__typename` and the other meta fields.
  final SchemaField? field;

  /// Whether every field node of the key sits in a fragment with
  /// `@defer` (and an `if` that is not false). Deferred fields run inline
  /// in M5.
  final bool isDeferred;

  /// What collection reads, kept to collect the children.
  final PlanContext context;

  final bool _hasConstantArguments;
  final Map<String, PlanNode> _children = {};
  CoercionResult? _constantArguments;

  /// The node for the selection sets of [nodes] collected for the runtime
  /// type [type], the same object for the same type.
  PlanNode childFor(ObjectType type) => _children.putIfAbsent(
    type.name,
    () => FieldCollector(context).collect(type, [
      for (final node in nodes) ?node.selectionSet,
    ]),
  );

  /// The coerced arguments of the field by name (defaults included), or the
  /// problem. Arguments without variables are coerced once and remembered,
  /// except a failure caused by an error user code threw, which the caller
  /// reports each time it happens.
  CoercionResult argumentsFor(Map<String, Object?> variables) {
    final declared = field;
    if (declared == null) {
      return const CoercionSuccess(<String, Object?>{});
    }
    if (!_hasConstantArguments) {
      return _coerce(declared, variables);
    }
    final cached = _constantArguments;
    if (cached != null) {
      return cached;
    }
    final result = _coerce(declared, const {});
    if (!_hasThrown(result)) {
      _constantArguments = result;
    }
    return result;
  }

  CoercionResult _coerce(
    SchemaField declared,
    Map<String, Object?> variables,
  ) => ArgumentCoercion(context.environment).coerce(
    '${parentType.name}.$fieldName',
    declared.arguments,
    nodes.first.arguments,
    variables,
  );

  bool _hasThrown(CoercionResult result) =>
      result is CoercionFailure &&
      result.problems.any((problem) => problem.thrown != null);
}
```

Create `packages/typed_graphql_server/lib/src/plan/lru_map.dart`:

```dart
import 'dart:collection';

/// A map that keeps at most [capacity] entries and drops the least recently
/// used one first (R4.8). A read counts as a use.
final class LruMap<K, V extends Object>(
  /// The most entries kept; zero keeps none.
  final int capacity,
) {
  /// Creates an empty map.
  this : assert(capacity >= 0, 'a capacity is not negative');

  // A LinkedHashMap iterates in insertion order, so the first key is the
  // least recently used one once a hit re-inserts its entry.
  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  /// The number of entries held.
  int get length => _entries.length;

  /// The value stored for [key], which becomes the most recently used, or
  /// null.
  V? use(K key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  /// Stores [value] for [key] as the most recently used entry and drops the
  /// least recently used one when the map is over its capacity.
  void store(K key, V value) {
    if (capacity == 0) {
      return;
    }
    _entries.remove(key);
    _entries[key] = value;
    if (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Whether [key] is held; unlike [use] it does not count as a use.
  bool contains(K key) => _entries.containsKey(key);
}
```

Create `packages/typed_graphql_server/lib/src/plan/operation_plan.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import 'condition_key.dart';
import 'condition_variables.dart';
import 'field_collector.dart';
import 'lru_map.dart';
import 'plan_context.dart';
import 'plan_node.dart';

/// Everything about one operation of one document that does not depend on
/// the request's variables, except through a few booleans (spec section 5,
/// R4.8): the operation, its root type, the fragments, the variables that
/// `@skip`, `@include` and `@defer` read, and the plan nodes collected for
/// each [ConditionKey] seen.
///
/// A plan changes only by adding memoised nodes, which depend on nothing but
/// the key, so executions may share one.
final class OperationPlan {
  /// Plans [operation] of a document whose fragments are [fragments].
  OperationPlan(
    this.operation,
    this.rootType,
    Map<String, FragmentDefinition> fragments,
    this.environment,
  ) : fragments = Map.unmodifiable(fragments),
      conditionVariables = const ConditionVariables().find(
        operation,
        fragments,
      );

  /// How many [ConditionKey]s a plan remembers the root node of.
  static const int maxConditionKeys = 16;

  /// The operation to run.
  final OperationDefinition operation;

  /// The root type of the operation's type.
  final ObjectType rootType;

  /// The fragment definitions of the document by name.
  final Map<String, FragmentDefinition> fragments;

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// The names of the variables that decide which fields are collected, in
  /// the order their booleans appear in a [ConditionKey].
  final List<String> conditionVariables;

  final LruMap<ConditionKey, PlanNode> _roots = LruMap(maxConditionKeys);

  /// The key of a request whose coerced variables are [variables].
  ConditionKey keyFor(Map<String, Object?> variables) => ConditionKey([
    for (final name in conditionVariables)
      switch (variables[name]) {
        final bool value => value,
        _ => null,
      },
  ]);

  /// The fields of the operation's root selection for [key]: the same node
  /// for equal keys while the plan remembers them.
  PlanNode rootFor(ConditionKey key) {
    final known = _roots.use(key);
    if (known != null) {
      return known;
    }
    final conditionValues = <String, Object?>{
      for (var i = 0; i < conditionVariables.length; i++)
        if (key.values[i] case final bool value) conditionVariables[i]: value,
    };
    final node = FieldCollector(
      PlanContext(environment, fragments, conditionValues),
    ).collect(rootType, [operation.selectionSet]);
    _roots.store(key, node);
    return node;
  }
}
```

Create `packages/typed_graphql_server/lib/src/plan/operation_planner.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import 'operation_plan.dart';
import 'operation_selection.dart';
import 'operation_selection_result.dart';
import 'plan_cache.dart';
import 'plan_result.dart';

/// Finds the plan of an operation: from the [PlanCache] when the same
/// `Document` object ran before, else by choosing the operation
/// (`OperationSelection`) and planning it. Only plans are cached; a request
/// error is cheap to repeat. Planning is synchronous, so two executions
/// never plan the same operation at once (R4.8).
final class OperationPlanner {
  /// Plans in [environment], remembering plans in [cache].
  const OperationPlanner(this.environment, this.cache);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// The plans made so far.
  final PlanCache cache;

  /// The plan of the operation named [operationName] in [document].
  PlanResult plan(Document document, String? operationName) {
    final known = cache.lookup(document, operationName);
    if (known != null) {
      return PlanReady(known);
    }
    final schema = environment.schema;
    switch (OperationSelection(schema).select(document, operationName)) {
      case OperationRejected(:final error):
        return PlanRejected(error);
      case OperationSelected(:final operation):
        final rootName = schema.rootTypeName(operation.operation);
        final rootType = rootName == null ? null : schema.typeNamed(rootName);
        if (rootType is! ObjectType) {
          throw StateError(
            'The root type of ${operation.operation.name} is '
            'an object type of a validated schema.',
          );
        }
        final plan = OperationPlan(
          operation,
          rootType,
          {
            for (final definition in document.definitions)
              if (definition is FragmentDefinition)
                definition.name.value: definition,
          },
          environment,
        );
        cache.store(document, operationName, plan);
        return PlanReady(plan);
    }
  }
}
```

Create `packages/typed_graphql_server/lib/src/plan/operation_selection.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'operation_selection_result.dart';

/// September2025 section 6.1 `GetOperation`, worded as graphql-js 17's
/// `buildExecutionContext` words it, plus the check that the schema has a
/// root type for the operation (graphql-js checks it when it executes).
final class OperationSelection {
  /// Selects against [schema].
  const OperationSelection(this.schema);

  /// The schema whose root types are checked.
  final Schema schema;

  /// Chooses the operation of [document] named [operationName]; without a
  /// name the document must hold exactly one operation.
  OperationSelectionResult select(Document document, String? operationName) {
    OperationDefinition? chosen;
    for (final definition in document.definitions) {
      if (definition is! OperationDefinition) {
        continue;
      }
      if (operationName == null) {
        if (chosen != null) {
          return _reject(
            'Must provide operation name if query contains multiple '
            'operations.',
            DiagnosticCode.operationNameRequired,
          );
        }
        chosen = definition;
      } else if (definition.name?.value == operationName) {
        chosen = definition;
      }
    }
    if (chosen == null) {
      return operationName == null
          ? _reject('Must provide an operation.', DiagnosticCode.noOperation)
          : _reject(
              'Unknown operation named "$operationName".',
              DiagnosticCode.unknownOperation,
            );
    }
    return _checkRoot(chosen);
  }

  OperationSelectionResult _checkRoot(OperationDefinition operation) {
    if (schema.rootTypeName(operation.operation) == null) {
      return _reject(
        'Schema is not configured to execute ${operation.operation.name} '
        'operation.',
        DiagnosticCode.unsupportedOperationType,
      );
    }
    return OperationSelected(operation);
  }

  OperationRejected _reject(String message, DiagnosticCode code) =>
      OperationRejected(
        GraphQLError(
          message,
          extensions: JsonObject({'code': JsonString(code.id)}),
        ),
      );
}
```

Create `packages/typed_graphql_server/lib/src/plan/operation_selection_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The outcome of choosing the operation to run.
sealed class OperationSelectionResult {
  const OperationSelectionResult();
}

/// The operation to execute.
final class OperationSelected extends OperationSelectionResult {
  /// Wraps [operation].
  const OperationSelected(this.operation);

  /// The chosen operation.
  final OperationDefinition operation;
}

/// No operation can run; [error] is the request error.
final class OperationRejected extends OperationSelectionResult {
  /// Wraps [error].
  const OperationRejected(this.error);

  /// The request error, with its `GQL32x` code in `extensions`.
  final GraphQLError error;
}
```

Create `packages/typed_graphql_server/lib/src/plan/plan_cache.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'lru_map.dart';
import 'operation_plan.dart';

/// The plans of an `ExecutableSchema`, at most [capacity] of them, least
/// recently used first out (R4.8). A plan is found by the identity of its
/// [Document] (syntax nodes compare by identity) and the operation name.
final class PlanCache(
  /// The most plans kept (`planCacheSize`).
  final int capacity,
) {
  /// Creates an empty cache.
  this : _plans = LruMap(capacity);

  final LruMap<(Document, String?), OperationPlan> _plans;
  int _hits = 0;
  int _misses = 0;

  /// How many lookups found a plan.
  int get hitCount => _hits;

  /// How many lookups found none.
  int get missCount => _misses;

  /// The number of plans held.
  int get length => _plans.length;

  /// The plan of [operationName] in [document], or null.
  OperationPlan? lookup(Document document, String? operationName) {
    final plan = _plans.use((document, operationName));
    if (plan == null) {
      _misses++;
    } else {
      _hits++;
    }
    return plan;
  }

  /// Keeps [plan] for [operationName] in [document].
  void store(Document document, String? operationName, OperationPlan plan) {
    _plans.store((document, operationName), plan);
  }
}
```

Create `packages/typed_graphql_server/lib/src/plan/plan_context.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import '../coercion/conditional_directives.dart';
import 'defer_directive.dart';

/// What the collection of one plan node reads and never changes: the
/// fragments of the document, the values of the condition variables of the
/// request's [ConditionKey], and the readers of the directives.
final class PlanContext {
  /// Creates a context; [conditionValues] holds the booleans that exist.
  PlanContext(this.environment, this.fragments, this.conditionValues)
    : conditionals = ConditionalDirectives(environment),
      defers = DeferDirective(environment);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// The fragment definitions of the document by name.
  final Map<String, FragmentDefinition> fragments;

  /// The variables `@skip`, `@include` and `@defer` read, by name.
  final Map<String, Object?> conditionValues;

  /// Reads `@skip` and `@include`.
  final ConditionalDirectives conditionals;

  /// Reads `@defer`.
  final DeferDirective defers;

  /// The core schema.
  Schema get schema => environment.schema;
}
```

Create `packages/typed_graphql_server/lib/src/plan/plan_node.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_problem.dart';
import 'field_plan.dart';

/// The fields one object type collects from a selection set (spec 6.3.2
/// `CollectFields`): one [FieldPlan] per response key, in collection order.
final class PlanNode {
  /// Creates a node of [objectType]; [problem] is set when collecting failed.
  PlanNode(this.objectType, List<FieldPlan> fields, {this.problem})
    : fields = List.unmodifiable(fields);

  /// The runtime type the fields were collected for.
  final ObjectType objectType;

  /// The fields by response key, in the order they first appear.
  final List<FieldPlan> fields;

  /// Why collection stopped: an `@skip`, `@include` or `@defer` argument
  /// could not be coerced (for example a variable without a boolean). The
  /// node then has no fields and the executor reports the problem.
  final CoercionProblem? problem;
}
```

Create `packages/typed_graphql_server/lib/src/plan/plan_result.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'operation_plan.dart';

/// The outcome of planning a request's operation.
sealed class PlanResult {
  const PlanResult();
}

/// The plan to execute.
final class PlanReady extends PlanResult {
  /// Wraps [plan].
  const PlanReady(this.plan);

  /// The plan, possibly from the cache.
  final OperationPlan plan;
}

/// The operation cannot run; [error] is the request error.
final class PlanRejected extends PlanResult {
  /// Wraps [error].
  const PlanRejected(this.error);

  /// The request error, with its code in `extensions`.
  final GraphQLError error;
}
```

Create `packages/typed_graphql_server/lib/src/plan/value_variables.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Whether written arguments mention a variable, so whether their coerced
/// values can be computed once for every request.
final class ValueVariables {
  /// Inspects without state.
  const ValueVariables();

  /// Whether any of [arguments] holds a variable, at any depth.
  bool occursIn(List<Argument> arguments) {
    final pending = <Value>[for (final argument in arguments) argument.value];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Variable():
          return true;
        case ListValue(:final values):
          pending.addAll(values);
        case ObjectValue(:final fields):
          pending.addAll([for (final field in fields) field.value]);
        default:
          break;
      }
    }
    return false;
  }
}
```

In `packages/typed_graphql_server/lib/src/builder/build_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,7 +12,8 @@ final class BuildOptions {
     this.directives = const [],
     this.includesDeferAndStream = false,
     this.description,
-  });
+    this.planCacheSize = 1000,
+  }) : assert(planCacheSize >= 0, 'a cache size is not negative');
 
   /// The directive definitions the schema declares besides the specified
   /// ones.
@@ -23,4 +24,8 @@ final class BuildOptions {
 
   /// The schema's description, null when it has none.
   final String? description;
+
+  /// How many operation plans the schema keeps (least recently used first
+  /// out); zero keeps none.
+  final int planCacheSize;
 }
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -55,6 +55,7 @@ final class ExecutableSchemaAssembly<C> {
     return ExecutableSchema(
       ValidSchema.assumeValid(schema),
       SchemaBindingsAssembler().assemble(definitions, possibleTypes),
+      planCacheSize: options.planCacheSize,
     );
   }
 
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../plan/plan_cache.dart';
 import 'schema_bindings.dart';
 
 /// A validated schema with the resolvers behind it: what
@@ -12,7 +13,8 @@ import 'schema_bindings.dart';
 /// {@category execution}
 final class ExecutableSchema<C> {
   /// Creates the schema from a validated [schema] and its [bindings].
-  ExecutableSchema(this.schema, this.bindings);
+  ExecutableSchema(this.schema, this.bindings, {int planCacheSize = 1000})
+    : planCache = PlanCache(planCacheSize);
 
   /// The validated schema.
   final ValidSchema schema;
@@ -20,4 +22,8 @@ final class ExecutableSchema<C> {
   /// The run-time tables the executor reads; not part of the public API.
   @internal
   final SchemaBindings bindings;
+
+  /// The operation plans made for this schema; not part of the public API.
+  @internal
+  final PlanCache planCache;
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/plan/field_collection_test.dart test/plan/operation_selection_test.dart test/plan/plan_cache_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- `BuildOptions.planCacheSize` (default 1000): operation plans (field collection per condition key, constant arguments coerced once) are cached per `ExecutableSchema`, least recently used first out.
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
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/builder/build_options.dart packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/lib/src/plan/condition_key.dart packages/typed_graphql_server/lib/src/plan/condition_variables.dart packages/typed_graphql_server/lib/src/plan/defer_directive.dart packages/typed_graphql_server/lib/src/plan/field_accumulator.dart packages/typed_graphql_server/lib/src/plan/field_collector.dart packages/typed_graphql_server/lib/src/plan/field_plan.dart packages/typed_graphql_server/lib/src/plan/lru_map.dart packages/typed_graphql_server/lib/src/plan/operation_plan.dart packages/typed_graphql_server/lib/src/plan/operation_planner.dart packages/typed_graphql_server/lib/src/plan/operation_selection.dart packages/typed_graphql_server/lib/src/plan/operation_selection_result.dart packages/typed_graphql_server/lib/src/plan/plan_cache.dart packages/typed_graphql_server/lib/src/plan/plan_context.dart packages/typed_graphql_server/lib/src/plan/plan_node.dart packages/typed_graphql_server/lib/src/plan/plan_result.dart packages/typed_graphql_server/lib/src/plan/value_variables.dart packages/typed_graphql_server/test/plan/field_collection_test.dart packages/typed_graphql_server/test/plan/operation_selection_test.dart packages/typed_graphql_server/test/plan/plan_cache_test.dart packages/typed_graphql_server/test/plan/plan_fixture.dart
git commit -q -m "feat(typed_graphql_server): plan operations and cache the plans" \
  -m "Operation selection, stack-based field collection with each fragment expanded once, per-condition-key plan nodes and an LRU plan cache sized by BuildOptions.planCacheSize." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The executor

Add `ExecutableSchema.execute`, `ExecutionOptions`, `ErrorBehavior`, `ErrorHook` and `ResponsePath` (exported) and the internal run: `OperationExecution`, `ExecutionRun`, `SelectionExecutor`, `SerialFields`, `FieldExecution`, value, leaf, list and object completion, `ErrorReporter`, `ErrorLog`, `ExecutionLimits` and `PendingValues`. `FieldInfo` gains the parent and return types, field nodes, operation, variables, schema and root value, and its path becomes a `ResponsePath`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart`, `packages/typed_graphql_server/lib/src/execution/completion_site.dart`, `packages/typed_graphql_server/lib/src/execution/error_behavior.dart`, `packages/typed_graphql_server/lib/src/execution/error_hook.dart`, `packages/typed_graphql_server/lib/src/execution/error_log.dart`, `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`, `packages/typed_graphql_server/lib/src/execution/execution_limits.dart`, `packages/typed_graphql_server/lib/src/execution/execution_options.dart`, `packages/typed_graphql_server/lib/src/execution/execution_run.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/leaf_completion.dart`, `packages/typed_graphql_server/lib/src/execution/list_completion.dart`, `packages/typed_graphql_server/lib/src/execution/object_completion.dart`, `packages/typed_graphql_server/lib/src/execution/operation_execution.dart`, `packages/typed_graphql_server/lib/src/execution/pending_values.dart`, `packages/typed_graphql_server/lib/src/execution/response_path.dart`, `packages/typed_graphql_server/lib/src/execution/selection_executor.dart`, `packages/typed_graphql_server/lib/src/execution/serial_fields.dart`, `packages/typed_graphql_server/lib/src/execution/value_completion.dart`
- Modify: `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/lib/src/execution/field_info.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/execution.md`
- Test: `packages/typed_graphql_server/test/execution/error_reporting_test.dart`, `packages/typed_graphql_server/test/execution/execute_test.dart`, `packages/typed_graphql_server/test/execution/execution_fixture.dart`, `packages/typed_graphql_server/test/execution/limits_and_order_test.dart`, `packages/typed_graphql_server/test/execution/null_propagation_test.dart`, `packages/typed_graphql_server/test/builder/fields_test.dart`

**Interfaces:**
- Consumes: Tasks 2-4 and M5a's `ExecutableSchema`, `SchemaBindings` and `FieldInfo`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// execution/abstract_resolution.dart
final class AbstractResolution
  AbstractResolution(this._run)
  ObjectType? resolve(SchemaType type, Object value, CompletionSite site)

// execution/completion_site.dart
final class CompletionSite
  CompletionSite itemAt(int position)
  String get fieldLabel

// execution/error_behavior.dart
enum ErrorBehavior

// execution/error_hook.dart
typedef ErrorHook = GraphQLError? Function(…)

// execution/error_log.dart
final class ErrorLog
  ErrorLog(this.behavior)
  bool get isHalted
  void record(GraphQLError error)
  void halt(GraphQLError error)

// execution/error_reporter.dart
final class ErrorReporter
  ErrorReporter(this.options) : log = ErrorLog(options.errorBehavior)
  void fieldError(DiagnosticCode code, String message, CompletionSite site)
  void halt(DiagnosticCode code, String message, CompletionSite site)
  void problem(…)
  void thrown(Object error, StackTrace stackTrace, CompletionSite site)
  GraphQLError hooked(…)

// execution/execution_limits.dart
final class ExecutionLimits
  ExecutionLimits(this._options, this._reporter)
  bool admits(CompletionSite site)

// execution/execution_options.dart
final class ExecutionOptions

// execution/execution_run.dart
final class ExecutionRun
  ExecutionRun(…)
  FutureOr<JsonValue?> settle(TypeRef type, FutureOr<JsonValue?> completed)

// execution/field_execution.dart
final class FieldExecution
  FieldExecution(this._run)
  FutureOr<JsonValue?> execute(…)

// execution/leaf_completion.dart
final class LeafCompletion
  LeafCompletion(this._run)
  JsonValue? complete(SchemaType type, Object value, CompletionSite site)
class _Unrepresentable

// execution/list_completion.dart
final class ListCompletion
  ListCompletion(this._run)
  FutureOr<JsonValue?> complete(…)

// execution/object_completion.dart
final class ObjectCompletion
  ObjectCompletion(this._run) : _abstract = AbstractResolution(_run)
  FutureOr<JsonValue?> complete(…)
  FutureOr<JsonValue?> completeAbstract(…)

// execution/operation_execution.dart
final class OperationExecution
  OperationExecution(…)
  FutureOr<ResponsePayload> execute(…)

// execution/pending_values.dart
final class PendingValues
  int get length
  void add(FutureOr<JsonValue?> value)

// execution/response_path.dart
final class ResponsePath
  ResponsePath key(String name)
  ResponsePath index(int position)
  List<PathSegment> toList()
  String toString()

// execution/selection_executor.dart
final class SelectionExecutor
  SelectionExecutor(this._run)
  FutureOr<JsonObject?> execute(…)
  FutureOr<JsonObject?> executeSerially(…)
  static JsonObject assemble(PlanNode node, List<JsonValue> values)

// execution/serial_fields.dart
final class SerialFields
  SerialFields(this._run, this._parent, this._node, this._path, this._depth)
  FutureOr<JsonObject?> from(int index)

// execution/value_completion.dart
final class ValueCompletion
  ValueCompletion(this._run)
  FutureOr<JsonValue?> complete(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/execution/error_reporting_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();
  const errorsOf = ExecutionFixture.errorsOf;

  group('masking', () {
    test('an unexpected error is masked with GQL330', () async {
      final json = await f.json('{ fail }');
      expect(errorsOf(json).single, {
        'message': 'Unexpected error.',
        'path': ['fail'],
        'extensions': {'code': 'GQL330'},
      });
    });

    test('maskErrors false shows the error text', () async {
      final json = await f.json(
        '{ failNonNull hello }',
        options: const ExecutionOptions(
          maskErrors: false,
          errorBehavior: ErrorBehavior.nullValue,
        ),
      );
      final error = errorsOf(json).single! as Map<String, Object?>;
      expect(error['message'], contains('secret detail'));
    });

    test('a GraphQLException reaches the client as it is', () async {
      final json = await f.json('{ exception }');
      expect(errorsOf(json).single, {
        'message': 'custom',
        'path': ['exception'],
        'extensions': {'k': 'v'},
      });
    });

    test('an async failure is masked too', () async {
      final json = await f.json('{ failLater }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Unexpected error.',
      );
    });
  });

  group('onError', () {
    test(
      'sees the raw error, its stack trace and the reported error',
      () async {
        final seen = <(Object, StackTrace, GraphQLError)>[];
        await f.json(
          '{ fail }',
          options: ExecutionOptions(
            onError: (error, stackTrace, reported) {
              seen.add((error, stackTrace, reported));
              return null;
            },
          ),
        );
        expect(seen, hasLength(1));
        expect(seen.single.$1, isA<StateError>());
        expect(seen.single.$3.message, 'Unexpected error.');
      },
    );

    test('a replacement is recorded instead', () async {
      final json = await f.json(
        '{ fail }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) =>
              GraphQLError('replaced', path: reported.path),
        ),
      );
      expect(errorsOf(json).single, {
        'message': 'replaced',
        'path': ['fail'],
      });
    });

    test('a throwing hook records the masked error', () async {
      final json = await f.json(
        '{ exception }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) => throw StateError('hook'),
        ),
      );
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Unexpected error.',
      );
    });

    test('is called for an async failure', () async {
      var calls = 0;
      await f.json(
        '{ failLater }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            calls++;
            return null;
          },
        ),
      );
      expect(calls, 1);
    });

    test('is not called for the library own errors', () async {
      var calls = 0;
      await f.json(
        '{ forced }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            calls++;
            return null;
          },
        ),
      );
      expect(calls, 0);
    });
  });

  group('locations', () {
    test('are given with the source', () async {
      const text = '{\n  fail\n}';
      final json = await f.json(
        text,
        options: ExecutionOptions(source: Source(text)),
      );
      expect((errorsOf(json).single! as Map<String, Object?>)['locations'], [
        {'line': 2, 'column': 3},
      ]);
    });

    test('are absent without the source', () async {
      final json = await f.json('{ fail }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>).containsKey(
          'locations',
        ),
        isFalse,
      );
    });
  });

  group('leaf values', () {
    test('an Int past 32 bits is GQL332', () async {
      final json = await f.json('{ overflow }');
      expect(json['data'], equals({'overflow': null}));
      expect(errorsOf(json).single, {
        'message':
            'Int cannot represent non 32-bit signed integer value: 3000000000',
        'path': ['overflow'],
        'extensions': {'code': 'GQL332'},
      });
    });

    test('a Float that is not finite is GQL332', () async {
      final json = await f.json('{ nan }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Float cannot represent non numeric value: NaN',
      );
    });

    test('an enum value the schema does not declare is GQL332', () async {
      final json = await f.json('{ mood }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Enum "Mood" cannot represent value: Mood.sad',
      );
    });
  });

  group('abstract types', () {
    test('an interface value resolves to the first accepting type', () async {
      expect(
        await f.json(
          '{ pet { name } found { ... on Dog { name } ... on Cat { name } } }',
        ),
        equals({
          'data': {
            'pet': {'name': 'rex'},
            'found': [
              {'name': 'rex'},
              {'name': 'tom'},
            ],
          },
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_server/test/execution/execute_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();

  group('execute', () {
    test('a query of synchronous resolvers returns a non-future', () {
      final result = f.run('{ hello greet strings }');
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        (result as ExecutionResult).toJson().toJson(),
        equals({
          'data': {
            'hello': 'world',
            'greet': 'hi you',
            'strings': ['a', 'b'],
          },
        }),
      );
    });

    test('an async resolver makes the result a future', () async {
      final result = f.run('{ hello slow }');
      expect(result, isA<Future<Object?>>());
      expect(
        (await result).toJson().toJson(),
        equals({
          'data': {'hello': 'world', 'slow': 'slow'},
        }),
      );
    });

    test('async siblings keep the order of the document', () async {
      expect(
        await f.json('{ slow quick hello }'),
        equals({
          'data': {'slow': 'slow', 'quick': 'quick', 'hello': 'world'},
        }),
      );
      final data = (await f.json('{ slow quick hello }'))['data'];
      expect((data! as Map<String, Object?>).keys, ['slow', 'quick', 'hello']);
    });

    test('a single async sibling among sync ones completes', () async {
      expect(
        await f.json('{ hello quick greet }'),
        equals({
          'data': {'hello': 'world', 'quick': 'quick', 'greet': 'hi you'},
        }),
      );
    });

    test('aliases are the response keys', () async {
      expect(
        await f.json('{ a: hello b: hello }'),
        equals({
          'data': {'a': 'world', 'b': 'world'},
        }),
      );
    });

    test('__typename is answered by the executor', () async {
      expect(
        await f.json('{ __typename pet { __typename } }'),
        equals({
          'data': {
            '__typename': 'Query',
            'pet': {'__typename': 'Dog'},
          },
        }),
      );
    });

    test('arguments reach the resolver, defaults included', () async {
      expect(
        await f.json('{ a: greet(name: "ann") b: greet }'),
        equals({
          'data': {'a': 'hi ann', 'b': 'hi you'},
        }),
      );
    });

    test('variables are coerced and used', () async {
      expect(
        await f.json(
          r'query ($n: String) { greet(name: $n) }',
          variables: JsonObject({'n': const JsonString('bob')}),
        ),
        equals({
          'data': {'greet': 'hi bob'},
        }),
      );
    });

    test('the resolver sees its path, parent type and field', () async {
      expect(
        await f.json('{ x: where self { where } }'),
        equals({
          'data': {
            'x': 'x|Query|where',
            'self': {'where': 'self.where|Query|where'},
          },
        }),
      );
    });

    test('the context reaches the resolver', () async {
      final context = Ctx()..log.addAll(['a', 'b']);
      expect(
        await f.json('{ useContext }', context: context),
        equals({
          'data': {'useContext': 'a,b'},
        }),
      );
    });

    test('an operation name picks the operation', () async {
      final payload = await f.run(
        'query A { hello } query B { greet }',
        operationName: 'B',
      );
      expect(
        payload.toJson().toJson(),
        equals({
          'data': {'greet': 'hi you'},
        }),
      );
    });
  });

  group('request errors', () {
    test('an unknown operation name is a request error', () {
      final result = f.run('query A { hello }', operationName: 'Z');
      expect(result, isA<RequestErrorResult>());
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL320'),
      );
    });

    test('several operations without a name is a request error', () {
      final result = f.run('query A { hello } query B { hello }');
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL321'),
      );
    });

    test('a document without operation is a request error', () {
      final result = f.run('fragment F on Query { hello }');
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL322'),
      );
    });

    test('an operation type the schema lacks is a request error', () {
      final result = f.run('subscription { hello }');
      expect(
        (result as RequestErrorResult).errors.single.extensions?['code'],
        const JsonString('GQL323'),
      );
    });

    test('an invalid variable value is a request error with no data', () {
      final result = f.run(
        r'query ($n: Int) { hello }',
        variables: JsonObject({'n': const JsonString('x')}),
      );
      expect(result, isA<RequestErrorResult>());
      expect(
        (result as RequestErrorResult).errors.single.message,
        r'Variable "$n" has invalid value: Int cannot represent non-integer '
        'value: "x"',
      );
    });
  });

  group('programmer errors', () {
    test('a document validated against another schema is an ArgumentError', () {
      final other = ExecutionFixture();
      expect(
        () => f.built.execute(
          other.validDocument('{ hello }'),
          context: Ctx(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a root value the root type does not accept is an ArgumentError', () {
      final b = ExecutableSchemaBuilder<Ctx>();
      final query = b.object<Ctx>(
        'Query',
        fields: (t) => [t.field('x', b.int).pure((_) => 1)],
      );
      final built = b.build(query: query);
      final document = ValidDocument.assumeValid(
        built.schema,
        f.parse('{ x }'),
      );
      expect(
        () => built.execute(document, context: Ctx()),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        built.execute(
          document,
          context: Ctx(),
          options: ExecutionOptions(rootValue: Ctx()),
        ),
        isA<ExecutionResult>(),
      );
    });
  });
}
```

Create `packages/typed_graphql_server/test/execution/execution_fixture.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Mood { happy, sad }

sealed class Animal {
  const Animal();
}

final class Dog extends Animal {
  const Dog();
}

final class Cat extends Animal {
  const Cat();
}

final class Item {
  const Item(this.id);
  final int id;
}

final class Ctx {
  final List<String> log = [];
}

final class WeirdCodec implements ScalarCodec<String> {
  const WeirdCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => const DecodeFailure('no');

  @override
  JsonValue encode(String value) => const JsonNull();
}

/// A reference with the GraphQL type [typeRef] whatever the Dart value is,
/// to reach the errors a typed resolver cannot cause.
final class UncheckedRef implements OutputRef<Object?> {
  UncheckedRef(this.typeRef, this.namedType);

  @override
  final TypeRef typeRef;

  @override
  final NamedTypeDef namedType;

  @override
  OutputRef<Object?> get nullable => throw UnimplementedError();
}

/// A schema of resolvers that succeed, fail, wait and nest, and helpers to
/// run queries against it.
final class ExecutionFixture {
  ExecutionFixture() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final name = Arg('name', b.string, defaultValue: 'you');
    final weird = b.scalar<String>('Weird', const WeirdCodec());
    final mood = b.enumType<Mood>('Mood', [Mood.happy]);
    final pet = b.interface<Animal>(
      'Pet',
      fields: (t) => [t.field('name', b.string).declareOnly()],
    );
    final dog = b.object<Dog>(
      'Dog',
      interfaces: [pet],
      fields: (t) => [t.field('name', b.string).pure((_) => 'rex')],
    );
    final cat = b.object<Cat>(
      'Cat',
      interfaces: [pet],
      fields: (t) => [t.field('name', b.string).pure((_) => 'tom')],
    );
    final found = b.union<Animal>('Found', members: [dog, cat]);
    final item = b.object<Item>(
      'Item',
      fields: (t) => [
        t.field('id', b.int).pure((item) => item.id),
        t
            .field('label', b.string)
            .pure((item) => item.id == 2 ? throw StateError('bad') : 'i'),
        t
            .field('maybe', b.string.nullable)
            .pure((item) => item.id == 2 ? throw StateError('bad') : 'm'),
      ],
    );
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('hello', b.string).pure((_) => 'world'),
        t
            .field(
              'greet',
              b.string,
              args: [name],
            )
            .resolve((parent, args, context, info) => 'hi ${args.get(name)}'),
        t.field('slow', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'slow';
        }),
        t
            .field('quick', b.string)
            .resolve((parent, args, context, info) => Future.value('quick')),
        t.field('fail', b.string.nullable).pure((_) => throw StateError('x')),
        t
            .field('failNonNull', b.string)
            .pure((_) => throw StateError('secret detail')),
        t
            .field('failLater', b.string.nullable)
            .resolve(
              (parent, args, context, info) =>
                  Future<String?>.error(StateError('later')),
            ),
        t
            .field('failLaterNonNull', b.string)
            .resolve(
              (parent, args, context, info) =>
                  Future<String>.error(StateError('later')),
            ),
        t
            .field('exception', b.string.nullable)
            .pure(
              (_) => throw GraphQLException(
                'custom',
                extensions: JsonObject({'k': const JsonString('v')}),
              ),
            ),
        t
            .field(
              'forced',
              UncheckedRef(
                const NonNullType(NamedType(Name('String'))),
                b.string,
              ),
            )
            .pure((_) => null),
        t.field('weird', weird).pure((_) => 'x'),
        t.field('strings', b.list(b.string)).pure((_) => ['a', 'b']),
        t
            .field('items', b.list(item))
            .pure((_) => const [Item(1), Item(2), Item(3)]),
        t
            .field('numbers', b.list(b.int.nullable).nullable)
            .pure((_) => [1, null, 3]),
        t.field('lazy', b.list(b.int).nullable).pure((_) => throwingIterable()),
        t
            .field(
              'notAList',
              UncheckedRef(
                const ListType(NonNullType(NamedType(Name('Int')))),
                b.int,
              ),
            )
            .pure((_) => 'text'),
        t.field('overflow', b.int.nullable).pure((_) => 3000000000),
        t.field('nan', b.float.nullable).pure((_) => double.nan),
        t.field('mood', mood.nullable).pure((_) => Mood.sad),
        t.field('pet', pet).pure((_) => const Dog()),
        t
            .field('found', b.list(found))
            .pure((_) => const <Animal>[Dog(), Cat()]),
        t.field('self', query).pure((_) => const Object()),
        t
            .field('selfNullable', query.nullable)
            .pure((parent) => throw StateError('no')),
        t
            .field('useContext', b.string)
            .resolve((parent, args, context, info) => context.log.join(',')),
        t
            .field('where', b.string)
            .resolve(
              (parent, args, context, info) =>
                  '${info.path}|${info.parentTypeName}|${info.fieldName}',
            ),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('first', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          context.log.add('first');
          return 'first';
        }),
        t.field('second', b.string).resolve((parent, args, context, info) {
          context.log.add('second');
          return 'second';
        }),
        t.field('third', b.string).resolve((parent, args, context, info) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          context.log.add('third');
          return 'third';
        }),
        t.field('boom', b.string).resolve((parent, args, context, info) {
          context.log.add('boom');
          throw StateError('boom');
        }),
      ],
    );
    built = b.build(query: query, mutation: mutation);
  }

  late final ExecutableSchema<Ctx> built;

  static List<Object?> errorsOf(Map<String, Object?> json) =>
      json['errors']! as List<Object?>;

  static String codeOf(Object? error) =>
      ((error! as Map<String, Object?>)['extensions']!
              as Map<String, Object?>)['code']!
          as String;

  static Iterable<int> throwingIterable() sync* {
    yield 1;
    throw StateError('lazy');
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  ValidDocument validDocument(String text) => ValidDocument.assumeValid(
    built.schema,
    parse(text),
  );

  /// Executes [text]; the result is a future only when a resolver waited.
  FutureOr<ResponsePayload> run(
    String text, {
    Ctx? context,
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) => built.execute(
    validDocument(text),
    context: context ?? Ctx(),
    operationName: operationName,
    variables: variables,
    options: options,
  );

  /// The JSON of the response to [text].
  Future<Map<String, Object?>> json(
    String text, {
    Ctx? context,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final payload = await run(
      text,
      context: context,
      variables: variables,
      options: options,
    );
    return payload.toJson().toJson();
  }
}
```

Create `packages/typed_graphql_server/test/execution/limits_and_order_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/execution/pending_values.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();
  const errorsOf = ExecutionFixture.errorsOf;
  const codeOf = ExecutionFixture.codeOf;

  group('mutations', () {
    test('root fields run one after another', () async {
      final context = Ctx();
      final json = await f.json(
        'mutation { first second third }',
        context: context,
      );
      expect(context.log, ['first', 'second', 'third']);
      expect(
        json['data'],
        equals({'first': 'first', 'second': 'second', 'third': 'third'}),
      );
    });

    test('queries start async fields together', () async {
      final context = Ctx();
      final result = f.run('{ slow quick }', context: context);
      expect(result, isA<Future<Object?>>());
      await result;
    });

    test('a failing non-null mutation field stops the next', () async {
      final context = Ctx();
      final json = await f.json(
        'mutation { boom second }',
        context: context,
      );
      expect(context.log, ['boom']);
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });
  });

  group('limits', () {
    test('maxDepth ends a branch with GQL336', () async {
      final json = await f.json(
        '{ self { self { self { hello } } } }',
        options: const ExecutionOptions(maxDepth: 3),
      );
      expect(codeOf(errorsOf(json).single), 'GQL336');
      expect(json['data'], isNull);
    });

    test('a query within maxDepth is unaffected', () async {
      final json = await f.json(
        '{ self { self { hello } } }',
        options: const ExecutionOptions(maxDepth: 3),
      );
      expect(json.containsKey('errors'), isFalse);
    });

    test('maxDepth counts list levels', () async {
      final json = await f.json(
        '{ strings }',
        options: const ExecutionOptions(maxDepth: 1),
      );
      expect(codeOf(errorsOf(json).first), 'GQL336');
    });

    test('maxSteps halts with GQL337 and null data', () async {
      final json = await f.json(
        '{ hello strings }',
        options: const ExecutionOptions(maxSteps: 2),
      );
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
      expect(codeOf(errorsOf(json).single), 'GQL337');
    });
  });

  group('PendingValues', () {
    test('builds at once when nothing is pending', () {
      final pending = PendingValues()
        ..add(JsonNumber(1))
        ..add(JsonNumber(2));
      final result = pending.finishWith(JsonArray.new);
      expect(result, isNot(isA<Future<Object?>>()));
      expect(result, JsonArray([JsonNumber(1), JsonNumber(2)]));
    });

    test('chains one pending value', () async {
      final pending = PendingValues()
        ..add(JsonNumber(1))
        ..add(Future<JsonValue?>.value(JsonNumber(2)));
      final result = pending.finishWith(JsonArray.new);
      expect(result, isA<Future<Object?>>());
      expect(
        await result,
        JsonArray([JsonNumber(1), JsonNumber(2)]),
      );
    });

    test('waits for several pending values in order', () async {
      final pending = PendingValues()
        ..add(
          Future<JsonValue?>.delayed(
            const Duration(milliseconds: 10),
            () => JsonNumber(1),
          ),
        )
        ..add(Future<JsonValue?>.value(JsonNumber(2)))
        ..add(JsonNumber(3));
      expect(
        await pending.finishWith(JsonArray.new),
        JsonArray([
          JsonNumber(1),
          JsonNumber(2),
          JsonNumber(3),
        ]),
      );
    });

    test('a failed value gives null', () {
      final pending = PendingValues()
        ..add(JsonNumber(1))
        ..add(null);
      expect(pending.finishWith(JsonArray.new), isNull);
    });

    test('abandon waits for the pending values', () async {
      var done = false;
      final pending = PendingValues()
        ..add(
          Future<JsonValue?>.delayed(const Duration(milliseconds: 10), () {
            done = true;
            return null;
          }),
        );
      expect(await pending.abandon<JsonArray>(), isNull);
      expect(done, isTrue);
    });
  });
}
```

Create `packages/typed_graphql_server/test/execution/null_propagation_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();
  const errorsOf = ExecutionFixture.errorsOf;
  const codeOf = ExecutionFixture.codeOf;

  group('null propagation', () {
    test('a failing nullable field is null with an error', () async {
      final json = await f.json('{ hello fail }');
      expect(json['data'], equals({'hello': 'world', 'fail': null}));
      expect(errorsOf(json), [
        {
          'message': 'Unexpected error.',
          'path': ['fail'],
          'extensions': {'code': 'GQL330'},
        },
      ]);
    });

    test('a failing non-null field nulls the whole data at the root', () async {
      final json = await f.json('{ hello failNonNull }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });

    test('null propagates to the nearest nullable parent', () async {
      final json = await f.json('{ selfNullable { hello } hello }');
      expect(json['data'], equals({'selfNullable': null, 'hello': 'world'}));
    });

    test('null in a non-null field is GQL331 with the field named', () async {
      final json = await f.json('{ forced }');
      expect(json['data'], isNull);
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Cannot return null for non-nullable field Query.forced.',
      );
      expect(codeOf(errorsOf(json).single), 'GQL331');
    });

    test('a codec that encodes null breaks a non-null field', () async {
      final json = await f.json('{ weird }');
      expect(json['data'], isNull);
      expect(codeOf(errorsOf(json).single), 'GQL331');
    });

    test('a failing nullable item leaves the others', () async {
      final json = await f.json('{ items { id maybe } }');
      expect(
        json['data'],
        equals({
          'items': [
            {'id': 1, 'maybe': 'm'},
            {'id': 2, 'maybe': null},
            {'id': 3, 'maybe': 'm'},
          ],
        }),
      );
      expect(
        ((errorsOf(json).single! as Map<String, Object?>)['path']!),
        ['items', 1, 'maybe'],
      );
    });

    test(
      'a failing non-null field in an item nulls the non-null list',
      () async {
        final json = await f.json('{ items { label } }');
        expect(json['data'], isNull);
        expect(
          (errorsOf(json).single! as Map<String, Object?>)['path'],
          ['items', 1, 'label'],
        );
      },
    );

    test('a null item of a nullable item type is null', () async {
      final json = await f.json('{ numbers }');
      expect(
        json['data'],
        equals({
          'numbers': [1, null, 3],
        }),
      );
      expect(json.containsKey('errors'), isFalse);
    });

    test('a non-iterable for a list is GQL335', () async {
      final json = await f.json('{ notAList }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Expected Iterable, but did not find one for field "Query.notAList".',
      );
      expect(codeOf(errorsOf(json).single), 'GQL335');
    });

    test('a lazy iterable that throws is a field error', () async {
      final json = await f.json('{ lazy }');
      expect(json['data'], equals({'lazy': null}));
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('an async failure of a non-null field propagates', () async {
      final json = await f.json('{ hello failLaterNonNull }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });

    test('an async failure of a nullable field is null', () async {
      final json = await f.json('{ hello failLater }');
      expect(json['data'], equals({'hello': 'world', 'failLater': null}));
    });

    test('siblings after a sync non-null failure are not started', () async {
      final json = await f.json('{ failNonNull fail }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });
  });

  group('error behaviour', () {
    const nullValue = ExecutionOptions(errorBehavior: ErrorBehavior.nullValue);

    test('nullValue stops a non-null failure at its field', () async {
      final json = await f.json(
        '{ hello failNonNull }',
        options: nullValue,
      );
      expect(json['data'], equals({'hello': 'world', 'failNonNull': null}));
      expect(errorsOf(json), hasLength(1));
    });

    test('nullValue nulls a non-null violation at its field', () async {
      final json = await f.json('{ forced hello }', options: nullValue);
      expect(json['data'], equals({'forced': null, 'hello': 'world'}));
      expect(codeOf(errorsOf(json).single), 'GQL331');
    });

    test('nullValue keeps the other items of a list', () async {
      final json = await f.json('{ items { id label } }', options: nullValue);
      expect(
        json['data'],
        equals({
          'items': [
            {'id': 1, 'label': 'i'},
            {'id': 2, 'label': null},
            {'id': 3, 'label': 'i'},
          ],
        }),
      );
    });

    test('halt ends with null data and the first error only', () async {
      final json = await f.json(
        '{ fail failNonNull hello }',
        options: const ExecutionOptions(errorBehavior: ErrorBehavior.halt),
      );
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });

    test('halt ignores the errors of async siblings after the first', () async {
      final json = await f.json(
        '{ failLater fail }',
        options: const ExecutionOptions(errorBehavior: ErrorBehavior.halt),
      );
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['path'],
        ['fail'],
      );
    });
  });
}
```

In `packages/typed_graphql_server/test/builder/fields_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,8 +20,16 @@ final class AppContext {
 void main() {
   FieldInfo infoOf(String field) => FieldInfo(
     fieldName: field,
-    parentTypeName: 'User',
-    path: [PathKey(field)],
+    parentType: ObjectType('User'),
+    returnType: const NamedType(Name('String')),
+    path: ResponsePath.root.key(field),
+    fieldNodes: const [],
+    operation: OperationDefinition(
+      OperationType.query,
+      SelectionSet([]),
+    ),
+    variables: JsonObject({}),
+    schema: ValidSchema.assumeValid(Schema(types: [])),
   );
 
   final b = ExecutableSchemaBuilder<AppContext>();
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/error_reporting_test.dart test/execution/execute_test.dart test/execution/limits_and_order_test.dart test/execution/null_propagation_test.dart test/builder/fields_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/object_type_def.dart';
import 'completion_site.dart';
import 'execution_run.dart';

/// Finds the object type of a value of an interface or union (September2025
/// 6.4.3 "ResolveAbstractType"): the abstract type's `resolveType`, else the
/// first possible type that accepts the value.
final class AbstractResolution {
  /// Resolves for [_run].
  AbstractResolution(this._run);

  final ExecutionRun _run;

  /// The object type of [value] for the abstract [type], or null after
  /// reporting why there is none.
  ObjectType? resolve(SchemaType type, Object value, CompletionSite site) {
    final binding = _run.bindings.abstractTypes[type.name];
    if (binding == null) {
      throw StateError('"${type.name}" has no abstract type binding.');
    }
    final ObjectTypeDef<Object?>? chosen;
    try {
      chosen = _choose(binding.resolveType, binding.possibleTypes, value);
    } on Object catch (error, stackTrace) {
      _run.reporter.thrown(error, stackTrace, site);
      return null;
    }
    if (chosen == null) {
      _run.reporter.fieldError(
        DiagnosticCode.unresolvedAbstractType,
        'Abstract type "${type.name}" must resolve to an Object type at '
        'runtime for field "${site.fieldLabel}". Either the "${type.name}" '
        'type should provide a "resolveType" function or each possible type '
        'should provide an "isTypeOf" function.',
        site,
      );
      return null;
    }
    if (!binding.possibleTypes.contains(chosen)) {
      _run.reporter.fieldError(
        DiagnosticCode.impossibleRuntimeType,
        'Runtime Object type "${chosen.name}" is not a possible type for '
        '"${type.name}".',
        site,
      );
      return null;
    }
    return switch (_run.schema.schema.typeNamed(chosen.name)) {
      final ObjectType objectType => objectType,
      _ => throw StateError('"${chosen.name}" is not an object type.'),
    };
  }

  ObjectTypeDef<Object?>? _choose(
    ObjectTypeDef<Object?> Function(Object? value)? explicit,
    List<ObjectTypeDef<Object?>> possible,
    Object value,
  ) {
    if (explicit != null) {
      return explicit(value);
    }
    for (final candidate in possible) {
      if (candidate.accepts(value)) {
        return candidate;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/completion_site.dart`:

```dart
import '../plan/field_plan.dart';
import 'response_path.dart';

/// Where a value is completed: the field it belongs to, its place in the
/// response and how deep that place is. Immutable.
final class CompletionSite {
  /// A place of the field [plan] at [path], [depth] levels down.
  const CompletionSite(this.plan, this.path, this.depth);

  /// The field being answered.
  final FieldPlan plan;

  /// The response path of the value.
  final ResponsePath path;

  /// How many fields and list levels lie between the root and the value.
  final int depth;

  /// The place of the list item at [position].
  CompletionSite itemAt(int position) =>
      CompletionSite(plan, path.index(position), depth + 1);

  /// The name of the field with its object type, as messages write it.
  String get fieldLabel => '${plan.parentType.name}.${plan.fieldName}';
}
```

Create `packages/typed_graphql_server/lib/src/execution/error_behavior.dart`:

```dart
/// What the executor does when a field fails (spec 6, the `onError`
/// proposal).
///
/// {@category execution}
enum ErrorBehavior {
  /// A field error makes the field null; at a non-null position the null
  /// propagates to the nearest nullable parent (September2025 section
  /// 6.4.4). This is the specified behaviour.
  propagate,

  /// A field error makes the field null and stops there, even when the
  /// field is non-null: nothing propagates.
  nullValue,

  /// The first error ends the execution: the response has `data: null` and
  /// that error only.
  halt,
}
```

Create `packages/typed_graphql_server/lib/src/execution/error_hook.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Sees an error user code threw, before it is recorded.
///
/// [reported] is the error that would be recorded: masked, or the
/// `GraphQLException` as it is, with its path and locations. A non-null
/// result replaces it; null keeps it. A hook that throws makes the masked
/// error the recorded one.
///
/// {@category execution}
typedef ErrorHook = GraphQLError? Function(
  Object error,
  StackTrace stackTrace,
  GraphQLError reported,
);
```

Create `packages/typed_graphql_server/lib/src/execution/error_log.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'error_behavior.dart';

/// The errors of one execution in the order they were recorded, and whether
/// the execution has halted.
final class ErrorLog {
  /// Creates an empty log that applies [behavior].
  ErrorLog(this.behavior);

  /// What an error does to the execution.
  final ErrorBehavior behavior;

  /// The errors recorded so far.
  final List<GraphQLError> errors = [];

  /// The error that ended the execution; null while it runs on.
  GraphQLError? haltError;

  /// Whether the execution has ended: nothing more is started or recorded.
  bool get isHalted => haltError != null;

  /// Records [error]; under [ErrorBehavior.halt] it also ends the execution.
  void record(GraphQLError error) {
    if (isHalted) {
      return;
    }
    errors.add(error);
    if (behavior == ErrorBehavior.halt) {
      haltError = error;
    }
  }

  /// Ends the execution with [error], whatever the behaviour.
  void halt(GraphQLError error) {
    if (isHalted) {
      return;
    }
    errors.add(error);
    haltError = error;
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_problem.dart';
import 'completion_site.dart';
import 'error_log.dart';
import 'execution_options.dart';
import 'graphql_exception.dart';
import 'response_path.dart';

/// Makes the errors of an execution (spec 7): the library's own, with their
/// `GQL3xx` code, and those user code threw, masked or not and offered to
/// `ExecutionOptions.onError`; then records them in the [log].
final class ErrorReporter {
  /// Reports under [options].
  ErrorReporter(this.options) : log = ErrorLog(options.errorBehavior);

  /// The settings of the execution.
  final ExecutionOptions options;

  /// Where errors go.
  final ErrorLog log;

  /// Records an error the library makes at [site].
  void fieldError(DiagnosticCode code, String message, CompletionSite site) =>
      log.record(_coded(code, message, site.path, site.plan.nodes));

  /// Ends the execution with an error the library makes at [site].
  void halt(DiagnosticCode code, String message, CompletionSite site) =>
      log.halt(_coded(code, message, site.path, site.plan.nodes));

  /// Records a coercion [problem] found at [path], about the field [nodes].
  void problem(
    CoercionProblem problem,
    ResponsePath? path,
    List<Field> nodes,
  ) {
    final code = problem.code ?? DiagnosticCode.invalidArgumentValue;
    final reported = GraphQLError(
      '${problem.message}${problem.where}',
      locations: _locations(nodes),
      path: path?.toList(),
      extensions: problem.extensions ?? _codeOf(code),
    );
    final thrown = problem.thrown;
    log.record(
      thrown == null
          ? reported
          : hooked(thrown.error, thrown.stackTrace, reported),
    );
  }

  /// Records [error], thrown by user code at [site].
  void thrown(Object error, StackTrace stackTrace, CompletionSite site) {
    final path = site.path;
    final nodes = site.plan.nodes;
    log.record(hooked(error, stackTrace, _reportedFor(error, path, nodes)));
  }

  /// [reported] after `ExecutionOptions.onError` has seen it: the hook's
  /// replacement, [reported] itself, or the masked error when the hook
  /// throws.
  GraphQLError hooked(
    Object error,
    StackTrace stackTrace,
    GraphQLError reported,
  ) {
    final hook = options.onError;
    if (hook == null) {
      return reported;
    }
    try {
      return hook(error, stackTrace, reported) ?? reported;
    } on Object {
      return GraphQLError(
        _masked,
        locations: reported.locations,
        path: reported.path,
        extensions: _codeOf(DiagnosticCode.unexpectedError),
      );
    }
  }

  static const String _masked = 'Unexpected error.';

  GraphQLError _reportedFor(
    Object error,
    ResponsePath path,
    List<Field> nodes,
  ) => switch (error) {
    GraphQLException(:final message, :final extensions) => GraphQLError(
      message,
      locations: _locations(nodes),
      path: path.toList(),
      extensions: extensions,
    ),
    _ => _coded(
      DiagnosticCode.unexpectedError,
      options.maskErrors ? _masked : error.toString(),
      path,
      nodes,
    ),
  };

  GraphQLError _coded(
    DiagnosticCode code,
    String message,
    ResponsePath path,
    List<Field> nodes,
  ) => GraphQLError(
    message,
    locations: _locations(nodes),
    path: path.toList(),
    extensions: _codeOf(code),
  );

  JsonObject _codeOf(DiagnosticCode code) =>
      JsonObject({'code': JsonString(code.id)});

  List<SourceLocation> _locations(List<Field> nodes) {
    final source = options.source;
    if (source == null) {
      return const [];
    }
    return [for (final node in nodes) source.locationOf(node.start)];
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/execution_limits.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'completion_site.dart';
import 'error_reporter.dart';
import 'execution_options.dart';

/// Counts the values an execution completes and refuses the ones past
/// `ExecutionOptions.maxDepth` or `maxSteps` (spec 16).
final class ExecutionLimits {
  /// Counts for one execution under [options].
  ExecutionLimits(this._options, this._reporter);

  final ExecutionOptions _options;
  final ErrorReporter _reporter;
  int _steps = 0;

  /// Whether the value at [site] may be completed. A refusal is already
  /// reported: a field error for depth, a halt for steps.
  bool admits(CompletionSite site) {
    if (_reporter.log.isHalted) {
      return false;
    }
    _steps++;
    if (_steps > _options.maxSteps) {
      _reporter.halt(
        DiagnosticCode.maxExecutionStepsExceeded,
        'Execution exceeds the limit of ${_options.maxSteps} completed '
        'values.',
        site,
      );
      return false;
    }
    if (site.depth > _options.maxDepth) {
      _reporter.fieldError(
        DiagnosticCode.maxExecutionDepthExceeded,
        'Execution exceeds the maximum depth of ${_options.maxDepth}.',
        site,
      );
      return false;
    }
    return true;
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/execution_options.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'error_behavior.dart';
import 'error_hook.dart';

/// The settings of one call of `ExecutableSchema.execute`.
///
/// A pipeline builds one value per request from its configuration and the
/// request.
///
/// {@category execution}
@immutable
final class ExecutionOptions {
  /// Creates options; the defaults are the specified behaviour with masked
  /// errors.
  const ExecutionOptions({
    this.rootValue,
    this.source,
    this.errorBehavior = ErrorBehavior.propagate,
    this.maskErrors = true,
    this.onError,
    this.includesSuggestions = true,
    this.maxCoercionErrors = 50,
    this.maxDepth = 256,
    this.maxSteps = 10000000,
  });

  /// The parent value of the root fields; the root type's Dart type must
  /// accept it.
  final Object? rootValue;

  /// The text the document was parsed from: with it, errors carry
  /// `locations`.
  final Source? source;

  /// What a field error does to the response.
  final ErrorBehavior errorBehavior;

  /// Whether an error that is not a `GraphQLException` reaches the client as
  /// `Unexpected error.` (`GQL330`) instead of its `toString()`.
  final bool maskErrors;

  /// Sees every error user code throws, before it is recorded.
  final ErrorHook? onError;

  /// Whether input messages carry "Did you mean" text.
  final bool includesSuggestions;

  /// The most variable errors reported before "Too many errors".
  final int maxCoercionErrors;

  /// The deepest response level (fields and list levels) that completes;
  /// past it a field error (`GQL336`) ends the branch.
  final int maxDepth;

  /// The most values the execution completes; past it the execution halts
  /// (`GQL337`).
  final int maxSteps;
}
```

Create `packages/typed_graphql_server/lib/src/execution/execution_run.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/operation_plan.dart';
import 'error_behavior.dart';
import 'error_reporter.dart';
import 'execution_limits.dart';
import 'execution_options.dart';
import 'field_execution.dart';
import 'leaf_completion.dart';
import 'list_completion.dart';
import 'object_completion.dart';
import 'schema_bindings.dart';
import 'selection_executor.dart';
import 'value_completion.dart';

/// The state of one execution and its collaborators (spec 6): what the
/// request asked for, the coerced variables, the errors so far. One per
/// call of `ExecutableSchema.execute`; it is never shared.
final class ExecutionRun {
  /// Prepares the execution of [plan] against [schema].
  ExecutionRun({
    required this.plan,
    required this.bindings,
    required this.schema,
    required this.context,
    required this.variables,
    required this.rawVariables,
    required this.options,
  }) : reporter = ErrorReporter(options);

  /// The operation to run.
  final OperationPlan plan;

  /// The Dart definitions behind the schema.
  final SchemaBindings bindings;

  /// The schema being executed.
  final ValidSchema schema;

  /// The context value every resolver receives.
  final Object? context;

  /// The coerced variables by name.
  final Map<String, Object?> variables;

  /// The variables as the request sent them.
  final JsonObject rawVariables;

  /// The settings of the call.
  final ExecutionOptions options;

  /// Makes and records the errors.
  final ErrorReporter reporter;

  // The collaborators below read the run, so they are made on first use,
  // after the run exists.

  /// Counts steps and depth.
  late final ExecutionLimits limits = ExecutionLimits(options, reporter);

  /// Runs the fields of a selection.
  late final SelectionExecutor selection = SelectionExecutor(this);

  /// Resolves and completes one field.
  late final FieldExecution fields = FieldExecution(this);

  /// Completes a value by its type.
  late final ValueCompletion values = ValueCompletion(this);

  /// Completes the value of a scalar or enum.
  late final LeafCompletion leaves = LeafCompletion(this);

  /// Completes the items of a list.
  late final ListCompletion lists = ListCompletion(this);

  /// Completes the value of an object, interface or union.
  late final ObjectCompletion objects = ObjectCompletion(this);

  /// A completed value at a position of type [type], after the position's
  /// own rule for failure (spec 6.4.4): a failed value (Dart `null`) becomes
  /// `null` in the response unless the position is non-null and errors
  /// propagate, when it stays the failure.
  FutureOr<JsonValue?> settle(TypeRef type, FutureOr<JsonValue?> completed) =>
      completed is Future<JsonValue?>
      ? completed.then((value) => _settled(type, value))
      : _settled(type, completed);

  JsonValue? _settled(TypeRef type, JsonValue? value) {
    if (value != null) {
      return value;
    }
    final propagates =
        options.errorBehavior == ErrorBehavior.propagate && type is NonNullType;
    return propagates ? null : const JsonNull();
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/field_execution.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../builder/arguments.dart';
import '../builder/field_def.dart';
import '../builder/field_lane.dart';
import '../coercion/coercion_result.dart';
import '../plan/field_plan.dart';
import 'completion_site.dart';
import 'execution_run.dart';
import 'field_info.dart';
import 'response_path.dart';

/// Resolves one field (September2025 6.4 "Executing Fields"): answers the
/// meta field `__typename`, or calls the field's pure getter or resolver, then
/// hands the value to the completion. Errors become null and an entry in the
/// log; nothing here throws.
final class FieldExecution {
  /// Executes for [_run].
  FieldExecution(this._run);

  final ExecutionRun _run;

  /// The response value of [plan] on [parent], with the parent's response
  /// path [parentPath] and the field's [depth]. Dart `null` when the field
  /// failed at a non-null position, `JsonNull` for a null that stays.
  FutureOr<JsonValue?> execute(
    Object? parent,
    FieldPlan plan,
    ResponsePath parentPath,
    int depth,
  ) {
    final site = CompletionSite(plan, parentPath.key(plan.responseKey), depth);
    final field = plan.field;
    if (field == null) {
      return _metaField(plan, site);
    }
    final definition =
        _run.bindings.fields[plan.parentType.name]?[plan.fieldName];
    if (definition == null) {
      _run.reporter.fieldError(
        DiagnosticCode.unexpectedError,
        'Field "${site.fieldLabel}" has no definition to run.',
        site,
      );
      return _run.settle(field.type, null);
    }
    return _resolve(parent, definition, field.type, site);
  }

  FutureOr<JsonValue?> _metaField(FieldPlan plan, CompletionSite site) {
    if (plan.fieldName == '__typename') {
      return JsonString(plan.parentType.name);
    }
    _run.reporter.fieldError(
      DiagnosticCode.unexpectedError,
      'The introspection field "${plan.fieldName}" is not available.',
      site,
    );
    return const JsonNull();
  }

  FutureOr<JsonValue?> _resolve(
    Object? parent,
    FieldDef<Object?, Object?> definition,
    TypeRef type,
    CompletionSite site,
  ) {
    final arguments = _argumentsOf(definition, site);
    if (arguments == null) {
      return _run.settle(type, null);
    }
    final FutureOr<Object?> raw;
    try {
      raw = _call(parent, definition, arguments, (type, site));
    } on Object catch (error, stackTrace) {
      return _failed(error, stackTrace, type, site);
    }
    if (raw is Future<Object?>) {
      return raw.then<JsonValue?>(
        (value) => _complete(type, value, site),
        onError: (Object error, StackTrace stackTrace) =>
            _failed(error, stackTrace, type, site),
      );
    }
    return _complete(type, raw, site);
  }

  FutureOr<JsonValue?> _complete(
    TypeRef type,
    Object? value,
    CompletionSite site,
  ) => _run.settle(type, _run.values.complete(type, value, site));

  FutureOr<JsonValue?> _failed(
    Object error,
    StackTrace stackTrace,
    TypeRef type,
    CompletionSite site,
  ) {
    _run.reporter.thrown(error, stackTrace, site);
    return _run.settle(type, null);
  }

  // The arguments of a resolver field; null after a coercion problem has
  // been reported. A pure field has none.
  Arguments? _argumentsOf(
    FieldDef<Object?, Object?> definition,
    CompletionSite site,
  ) {
    if (definition.lane is! ResolverLane) {
      return Arguments.empty;
    }
    switch (site.plan.argumentsFor(_run.variables)) {
      case CoercionSuccess(:final value):
        return Arguments(definition.args, value as Map<String, Object?>);
      case CoercionFailure(:final problems):
        for (final problem in problems) {
          _run.reporter.problem(problem, site.path, site.plan.nodes);
        }
        return null;
    }
  }

  // The one place a field's value is asked for.
  FutureOr<Object?> _call(
    Object? parent,
    FieldDef<Object?, Object?> definition,
    Arguments arguments,
    (TypeRef, CompletionSite) where,
  ) => switch (definition.lane) {
    PureLane(:final read) => read(parent),
    ResolverLane(:final resolve) => resolve(
      parent,
      arguments,
      _run.context,
      _infoOf(where.$1, where.$2),
    ),
    DeclaredOnlyLane() => throw StateError(
      'Field "${where.$2.fieldLabel}" is declared without a resolver.',
    ),
  };

  FieldInfo _infoOf(TypeRef type, CompletionSite site) {
    final plan = site.plan;
    return FieldInfo(
      fieldName: plan.fieldName,
      parentType: plan.parentType,
      returnType: type,
      path: site.path,
      fieldNodes: plan.nodes,
      operation: _run.plan.operation,
      variables: _run.rawVariables,
      schema: _run.schema,
      rootValue: _run.options.rootValue,
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/leaf_completion.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../builder/enum_type_def.dart';
import '../builder/scalar_type_def.dart';
import '../coercion/value_inspector.dart';
import 'completion_site.dart';
import 'execution_run.dart';

/// Completes the value of a scalar or an enum (September2025 6.4.3, "Result
/// Coercion"): the Int range, Float finiteness, the enum's names, the codec's
/// `encode`; the messages are graphql-js's.
final class LeafCompletion {
  /// Completes for [_run].
  LeafCompletion(this._run);

  static const ValueInspector _inspector = ValueInspector();

  final ExecutionRun _run;

  /// The JSON of [value] for the leaf [type], or null after reporting why
  /// the value cannot be written.
  JsonValue? complete(SchemaType type, Object value, CompletionSite site) {
    try {
      return switch (type) {
        ScalarType() => _scalar(type, value),
        EnumType() => _enum(type, value),
        _ => throw StateError('"${type.name}" is not a leaf type.'),
      };
    } on _Unrepresentable catch (problem) {
      _run.reporter.fieldError(
        DiagnosticCode.unserializableValue,
        problem.message,
        site,
      );
    } on Object catch (error, stackTrace) {
      if (error is ArgumentError) {
        _run.reporter.fieldError(
          DiagnosticCode.unserializableValue,
          '${error.message}',
          site,
        );
      } else {
        _run.reporter.thrown(error, stackTrace, site);
      }
    }
    return null;
  }

  JsonValue _scalar(ScalarType type, Object value) {
    switch (type.name) {
      case 'Int':
        return _int(value);
      case 'Float':
        return _float(value);
    }
    final codec = switch (_run.bindings.leaves[type.name]) {
      ScalarTypeDef<Object>(:final codec) => codec,
      _ => const ScalarCodecs().codecFor(type.name),
    };
    if (codec == null) {
      throw StateError('Scalar "${type.name}" has no codec.');
    }
    return codec.encode(value);
  }

  JsonValue _int(Object value) {
    if (value is! int) {
      throw _Unrepresentable(
        'Int cannot represent non-integer value: ${_inspector.inspect(value)}',
      );
    }
    if (value < -2147483648 || value > 2147483647) {
      throw _Unrepresentable(
        'Int cannot represent non 32-bit signed integer value: $value',
      );
    }
    return JsonNumber(value);
  }

  JsonValue _float(Object value) {
    if (value is! num || !value.isFinite) {
      throw _Unrepresentable(
        'Float cannot represent non numeric value: '
        '${_inspector.inspect(value)}',
      );
    }
    return JsonNumber(value);
  }

  JsonValue _enum(EnumType type, Object value) {
    final definition = _run.bindings.leaves[type.name];
    try {
      if (definition is EnumTypeDef<Enum>) {
        return JsonString(definition.nameOf(value as Enum));
      }
    } on Object {
      // Not a value of the enum: the message below says so.
    }
    throw _Unrepresentable(
      'Enum "${type.name}" cannot represent value: '
      '${_inspector.inspect(value)}',
    );
  }
}

class _Unrepresentable implements Exception {
  _Unrepresentable(this.message);

  final String message;
}
```

Create `packages/typed_graphql_server/lib/src/execution/list_completion.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'completion_site.dart';
import 'execution_run.dart';
import 'pending_values.dart';

/// Completes the value of a list type (September2025 6.4.3): each item by
/// the list's item type, at the item's index.
final class ListCompletion {
  /// Completes for [_run].
  ListCompletion(this._run);

  final ExecutionRun _run;

  /// The array of the items of [value] for [type], or Dart `null` when an
  /// item fails at a non-null position or [value] is not an [Iterable].
  FutureOr<JsonValue?> complete(
    ListType type,
    Object value,
    CompletionSite site,
  ) {
    if (value is! Iterable<Object?>) {
      _run.reporter.fieldError(
        DiagnosticCode.unexpectedValue,
        'Expected Iterable, but did not find one for field '
        '"${site.fieldLabel}".',
        site,
      );
      return null;
    }
    final pending = PendingValues();
    try {
      var index = 0;
      for (final item in value) {
        final completed = _run.settle(
          type.type,
          _run.values.complete(type.type, item, site.itemAt(index)),
        );
        if (completed == null || _run.reporter.log.isHalted) {
          return pending.abandon();
        }
        pending.add(completed);
        index++;
      }
    } on Object catch (error, stackTrace) {
      // A lazy iterable throws while it is walked.
      _run.reporter.thrown(error, stackTrace, site);
      return pending.abandon();
    }
    return pending.finishWith(JsonArray.new);
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/object_completion.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'abstract_resolution.dart';
import 'completion_site.dart';
import 'execution_run.dart';

/// Completes the value of an object, interface or union type (September2025
/// 6.4.3): collects the fields of the runtime type from the field's
/// selection sets and executes them on the value.
final class ObjectCompletion {
  /// Completes for [_run].
  ObjectCompletion(this._run) : _abstract = AbstractResolution(_run);

  final ExecutionRun _run;
  final AbstractResolution _abstract;

  /// The object of the selection on [value], an object of [type].
  FutureOr<JsonValue?> complete(
    ObjectType type,
    Object value,
    CompletionSite site,
  ) {
    final node = site.plan.childFor(type);
    if (node.problem case final problem?) {
      _run.reporter.problem(problem, site.path, site.plan.nodes);
      return null;
    }
    return _run.selection.execute(value, node, site.path, site.depth + 1);
  }

  /// The object of the selection on [value], an object of the type that
  /// [type], an interface or union, resolves for it.
  FutureOr<JsonValue?> completeAbstract(
    SchemaType type,
    Object value,
    CompletionSite site,
  ) {
    final runtimeType = _abstract.resolve(type, value, site);
    return runtimeType == null ? null : complete(runtimeType, value, site);
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/operation_execution.dart`:

```dart
import 'dart:async';

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
import 'response_path.dart';
import 'schema_bindings.dart';

/// One call of `ExecutableSchema.execute` (September2025 6.1 "Executing
/// Requests"): plans the operation, coerces the variables, runs the root
/// selection and builds the response. Request errors (no operation,
/// unusable variables) end as a `RequestErrorResult`; everything after is
/// an `ExecutionResult`.
final class OperationExecution {
  /// Prepares a call against [_schema] with [_options].
  OperationExecution(
    this._schema,
    this._bindings,
    this._planCache,
    this._options,
  );

  final ValidSchema _schema;
  final SchemaBindings _bindings;
  final PlanCache _planCache;
  final ExecutionOptions _options;

  /// Runs the operation named [operationName] of [document] with the
  /// request's [variables] and the resolvers' [context].
  FutureOr<ResponsePayload> execute(
    Document document,
    Object? context, {
    String? operationName,
    JsonObject? variables,
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
        return RequestErrorResult(errors: [error]);
      case PlanReady(:final plan):
        _checkRootValue(plan);
        return _coerceAndRun(plan, context, variables ?? JsonObject({}));
    }
  }

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

  FutureOr<ResponsePayload> _coerceAndRun(
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
        return RequestErrorResult(
          errors: _reportUnexpected(errors, unexpected),
        );
      case CoercedVariables(:final values):
        return _run(plan, context, values, variables);
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

  FutureOr<ResponsePayload> _run(
    OperationPlan plan,
    Object? context,
    Map<String, Object?> values,
    JsonObject rawVariables,
  ) {
    final run = ExecutionRun(
      plan: plan,
      bindings: _bindings,
      schema: _schema,
      context: context,
      variables: values,
      rawVariables: rawVariables,
      options: _options,
    );
    final root = plan.rootFor(plan.keyFor(values));
    if (root.problem case final problem?) {
      run.reporter.problem(problem, null, const []);
      return _response(run, null);
    }
    final rootValue = _options.rootValue;
    final data = plan.operation.operation == OperationType.mutation
        ? run.selection.executeSerially(rootValue, root, ResponsePath.root, 1)
        : run.selection.execute(rootValue, root, ResponsePath.root, 1);
    return data is Future<JsonObject?>
        ? data.then((resolved) => _response(run, resolved))
        : _response(run, data);
  }

  ExecutionResult _response(ExecutionRun run, JsonObject? data) {
    final log = run.reporter.log;
    if (log.haltError case final halted?) {
      return ExecutionResult(null, errors: [halted]);
    }
    return ExecutionResult(data, errors: log.errors);
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/pending_values.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

/// The completed values of an object's fields or a list's items, some of
/// them still pending (R4.9).
///
/// A value is a [JsonValue], Dart `null` (a failure that propagates) or a
/// `Future` of one of those. A `Future` here never fails: errors are handled
/// where they happen. With no pending value the result is built at once;
/// with one it chains `then`; with several it waits for all of them once.
final class PendingValues {
  final List<FutureOr<JsonValue?>> _values = [];

  /// How many values were added.
  int get length => _values.length;

  /// Adds the next value.
  void add(FutureOr<JsonValue?> value) => _values.add(value);

  /// [build] applied to the values once every one has completed, or null
  /// when any of them is a propagating failure.
  FutureOr<R?> finishWith<R extends JsonValue>(
    R Function(List<JsonValue> values) build,
  ) {
    final positions = <int>[];
    final futures = <Future<JsonValue?>>[];
    for (var i = 0; i < _values.length; i++) {
      if (_values[i] case final Future<JsonValue?> future) {
        positions.add(i);
        futures.add(future);
      }
    }
    if (futures.isEmpty) {
      return _build(build);
    }
    if (futures.length == 1) {
      return futures.first.then((value) {
        _values[positions.first] = value;
        return _build(build);
      });
    }
    return Future.wait(futures).then((results) {
      for (var i = 0; i < results.length; i++) {
        _values[positions[i]] = results[i];
      }
      return _build(build);
    });
  }

  /// Null once every pending value has completed: the result of a
  /// propagating failure, which still lets started work finish so that the
  /// errors it records are in the response.
  FutureOr<R?> abandon<R extends JsonValue>() {
    final futures = <Future<JsonValue?>>[
      for (final value in _values)
        if (value is Future<JsonValue?>) value,
    ];
    if (futures.isEmpty) {
      return null;
    }
    return Future.wait(futures).then<R?>((_) => null);
  }

  R? _build<R extends JsonValue>(R Function(List<JsonValue> values) build) {
    final values = <JsonValue>[];
    for (final value in _values) {
      if (value == null) {
        return null;
      }
      values.add(value as JsonValue);
    }
    return build(values);
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/response_path.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The response path of a field: response names and list indexes from the
/// root of `data`. Extending a path costs one object, so the executor builds
/// one per field without copying; [toList] makes the list an error needs.
///
/// {@category execution}
final class ResponsePath {
  const ResponsePath._(this._parent, this._segment, this.length);

  /// The empty path, the root of `data`.
  static const ResponsePath root = ResponsePath._(null, null, 0);

  final ResponsePath? _parent;
  final PathSegment? _segment;

  /// How many segments the path has.
  final int length;

  /// This path followed by the response name [name].
  ResponsePath key(String name) =>
      ResponsePath._(this, PathKey(name), length + 1);

  /// This path followed by the list index [position].
  ResponsePath index(int position) =>
      ResponsePath._(this, PathIndex(position), length + 1);

  /// The segments from the root.
  List<PathSegment> toList() {
    final segments = <PathSegment>[];
    for (ResponsePath? step = this; step != null; step = step._parent) {
      if (step._segment case final segment?) {
        segments.add(segment);
      }
    }
    return segments.reversed.toList(growable: false);
  }

  @override
  String toString() => toList().join('.');
}
```

Create `packages/typed_graphql_server/lib/src/execution/selection_executor.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_node.dart';
import 'execution_run.dart';
import 'pending_values.dart';
import 'response_path.dart';
import 'serial_fields.dart';

/// Executes the fields collected for an object (September2025 6.2.2
/// "Executing a Selection Set"): in parallel, or one after another for the
/// root fields of a mutation.
final class SelectionExecutor {
  /// Executes for [_run].
  SelectionExecutor(this._run);

  final ExecutionRun _run;

  /// The object of the fields of [node] on [parent], started in order. The
  /// result is null when a field fails at a non-null position: the null
  /// propagates and the fields after it are not started.
  FutureOr<JsonObject?> execute(
    Object? parent,
    PlanNode node,
    ResponsePath path,
    int depth,
  ) {
    final pending = PendingValues();
    for (final field in node.fields) {
      if (_run.reporter.log.isHalted) {
        return pending.abandon();
      }
      final result = _run.fields.execute(parent, field, path, depth);
      if (result == null) {
        return pending.abandon();
      }
      pending.add(result);
    }
    return pending.finishWith((values) => assemble(node, values));
  }

  /// Like [execute], but each field completes before the next one starts.
  FutureOr<JsonObject?> executeSerially(
    Object? parent,
    PlanNode node,
    ResponsePath path,
    int depth,
  ) => SerialFields(_run, parent, node, path, depth).from(0);

  /// The object holding [values] under the response keys of [node].
  static JsonObject assemble(PlanNode node, List<JsonValue> values) =>
      JsonObject({
        for (var i = 0; i < values.length; i++)
          node.fields[i].responseKey: values[i],
      });
}
```

Create `packages/typed_graphql_server/lib/src/execution/serial_fields.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/plan_node.dart';
import 'execution_run.dart';
import 'pending_values.dart';
import 'response_path.dart';
import 'selection_executor.dart';

/// Runs the fields of one node one after another (September2025 6.2.2,
/// "Executing a Selection Set Serially"): a field starts when the one before
/// it has completed.
final class SerialFields {
  /// Prepares the serial run of [node] on [parent].
  SerialFields(this._run, this._parent, this._node, this._path, this._depth);

  final ExecutionRun _run;
  final Object? _parent;
  final PlanNode _node;
  final ResponsePath _path;
  final int _depth;
  final PendingValues _values = PendingValues();

  /// Runs the fields from position [index]; synchronous while the fields
  /// are. Null when a field fails at a non-null position or the execution
  /// halts: the fields after it are not started.
  FutureOr<JsonObject?> from(int index) {
    final fields = _node.fields;
    for (var i = index; i < fields.length; i++) {
      if (_run.reporter.log.isHalted) {
        return null;
      }
      final result = _run.fields.execute(_parent, fields[i], _path, _depth);
      if (result is Future<JsonValue?>) {
        return result.then((resolved) => _after(i, resolved));
      }
      if (result == null) {
        return null;
      }
      _values.add(result);
    }
    return _values.finishWith((values) {
      return SelectionExecutor.assemble(_node, values);
    });
  }

  FutureOr<JsonObject?> _after(int index, JsonValue? resolved) {
    if (resolved == null) {
      return null;
    }
    _values.add(resolved);
    return from(index + 1);
  }
}
```

Create `packages/typed_graphql_server/lib/src/execution/value_completion.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import 'completion_site.dart';
import 'execution_run.dart';

/// Completes a resolved value by its type (September2025 6.4.3 "Value
/// Completion"). The result is a `JsonValue`, or Dart `null` when the value
/// failed and the failure propagates to the position that can hold a null
/// (6.4.4); `JsonNull` is a real null.
final class ValueCompletion {
  /// Completes for [_run].
  ValueCompletion(this._run);

  final ExecutionRun _run;

  /// The response value of [value] at a place of type [type].
  FutureOr<JsonValue?> complete(
    TypeRef type,
    Object? value,
    CompletionSite site,
  ) {
    if (!_run.limits.admits(site)) {
      return null;
    }
    final isNonNull = type is NonNullType;
    final inner = type is NonNullType ? type.type : type;
    if (value == null) {
      return isNonNull ? _nullViolation(site) : const JsonNull();
    }
    final completed = switch (inner) {
      ListType() => _run.lists.complete(inner, value, site),
      NamedType(:final name) => _named(name.value, value, site),
      NonNullType() => throw StateError('A non-null type wraps another.'),
    };
    return isNonNull ? _guardNull(completed, site) : completed;
  }

  FutureOr<JsonValue?> _named(
    String name,
    Object value,
    CompletionSite site,
  ) => switch (_run.schema.schema.typeNamed(name)) {
    final ScalarType type => _run.leaves.complete(type, value, site),
    final EnumType type => _run.leaves.complete(type, value, site),
    final ObjectType type => _run.objects.complete(type, value, site),
    final InterfaceType type => _run.objects.completeAbstract(
      type,
      value,
      site,
    ),
    final UnionType type => _run.objects.completeAbstract(type, value, site),
    _ => throw StateError('"$name" is not an output type of the schema.'),
  };

  // A non-null position refuses the null a codec may encode to, as it
  // refuses the null a resolver returns.
  FutureOr<JsonValue?> _guardNull(
    FutureOr<JsonValue?> completed,
    CompletionSite site,
  ) {
    if (completed is Future<JsonValue?>) {
      return completed.then((value) => _guardSettled(value, site));
    }
    return _guardSettled(completed, site);
  }

  JsonValue? _guardSettled(JsonValue? value, CompletionSite site) =>
      value is JsonNull ? _nullViolation(site) : value;

  JsonValue? _nullViolation(CompletionSite site) {
    _run.reporter.fieldError(
      DiagnosticCode.nullNonNullField,
      'Cannot return null for non-nullable field ${site.fieldLabel}.',
      site,
    );
    return null;
  }
}
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,7 +1,11 @@
+import 'dart:async';
+
 import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../plan/plan_cache.dart';
+import 'execution_options.dart';
+import 'operation_execution.dart';
 import 'schema_bindings.dart';
 
 /// A validated schema with the resolvers behind it: what
@@ -26,4 +30,42 @@ final class ExecutableSchema<C> {
   /// The operation plans made for this schema; not part of the public API.
   @internal
   final PlanCache planCache;
+
+  /// Runs the operation named [operationName] of [document] (the only one
+  /// when null) with the request's [variables].
+  ///
+  /// The result is an [ExecutionResult], or a [RequestErrorResult] when the
+  /// operation cannot run: no such operation, no root type for its kind,
+  /// unusable variables. It is a `Future` only when a resolver answered
+  /// with one: a query of synchronous resolvers returns at once.
+  ///
+  /// [document] must have been validated against this schema's [schema]
+  /// (the same object), and [ExecutionOptions.rootValue] must be accepted
+  /// by the root type; either mismatch is an [ArgumentError].
+  FutureOr<ResponsePayload> execute(
+    ValidDocument document, {
+    required C context,
+    String? operationName,
+    JsonObject? variables,
+    ExecutionOptions options = const ExecutionOptions(),
+  }) {
+    if (!identical(document.schema, schema)) {
+      throw ArgumentError.value(
+        document,
+        'document',
+        'was validated against another schema',
+      );
+    }
+    return OperationExecution(
+      schema,
+      bindings,
+      planCache,
+      options,
+    ).execute(
+      document.document,
+      context,
+      operationName: operationName,
+      variables: variables,
+    );
+  }
 }
```

In `packages/typed_graphql_server/lib/src/execution/field_info.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,22 +1,52 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'response_path.dart';
+
 /// What a resolver knows about the call it answers.
 ///
 /// {@category execution}
 final class FieldInfo {
-  /// Describes the call of [fieldName] on [parentTypeName] at [path].
+  /// Describes the call of [fieldName] on [parentType] at [path].
   FieldInfo({
     required this.fieldName,
-    required this.parentTypeName,
-    required List<PathSegment> path,
-  }) : path = List.unmodifiable(path);
+    required this.parentType,
+    required this.returnType,
+    required this.path,
+    required this.fieldNodes,
+    required this.operation,
+    required this.variables,
+    required this.schema,
+    this.rootValue,
+  });
 
   /// The field's name in the schema.
   final String fieldName;
 
-  /// The name of the object type the field is selected on.
-  final String parentTypeName;
+  /// The object type the field is selected on.
+  final ObjectType parentType;
+
+  /// The field's declared type.
+  final TypeRef returnType;
 
   /// The response path of the field, from the root.
-  final List<PathSegment> path;
+  final ResponsePath path;
+
+  /// The field nodes merged under the response key, in document order; do
+  /// not change the list.
+  final List<Field> fieldNodes;
+
+  /// The operation being executed.
+  final OperationDefinition operation;
+
+  /// The request's variable values as sent, before coercion.
+  final JsonObject variables;
+
+  /// The schema being executed.
+  final ValidSchema schema;
+
+  /// The root value of the execution.
+  final Object? rootValue;
+
+  /// The name of the object type the field is selected on.
+  String get parentTypeName => parentType.name;
 }
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,8 +2,8 @@
 /// engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws
 /// and graphql-sse handlers.
 ///
-/// Under construction: the typed schema builder works (M5a); execution
-/// arrives in M5b. See the package README.
+/// Under construction: the typed schema builder (M5a) and query execution
+/// (M5b) work. See the package README.
 library;
 
 export 'src/builder/arg.dart';
@@ -29,6 +29,10 @@ export 'src/builder/output_ref.dart';
 export 'src/builder/scalar_type_def.dart';
 export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
+export 'src/execution/error_behavior.dart';
+export 'src/execution/error_hook.dart';
 export 'src/execution/executable_schema.dart';
+export 'src/execution/execution_options.dart';
 export 'src/execution/field_info.dart';
 export 'src/execution/graphql_exception.dart';
+export 'src/execution/response_path.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/error_reporting_test.dart test/execution/execute_test.dart test/execution/limits_and_order_test.dart test/execution/null_propagation_test.dart test/builder/fields_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- `ExecutableSchema.execute` runs a `ValidDocument` and returns
  `FutureOr<ResponsePayload>`: a query of synchronous resolvers returns an
  `ExecutionResult` at once. Request errors (`GQL320`-`GQL323`, bad
  variables) are a `RequestErrorResult`. Mutation root fields run one after
  another.
- Field errors follow the specified null propagation; errors the library
  makes carry `extensions.code` (`GQL330`-`GQL337`). Unexpected errors are
  masked (`Unexpected error.`) unless `maskErrors` is off; `GraphQLException`
  reaches the client as it is.
- `ExecutionOptions` (`rootValue`, `source`, `errorBehavior`, `maskErrors`,
  `onError`, `includesSuggestions`, `maxCoercionErrors`, `maxDepth`,
  `maxSteps`), `ErrorBehavior` (`propagate`, `nullValue`, `halt`) and the
  `ErrorHook` typedef. `maxDepth` (256) and `maxSteps` (10 000 000) end
  runaway executions with `GQL336` and `GQL337`.
- **Breaking:** `FieldInfo` carries the parent `ObjectType`, `returnType`,
  `fieldNodes`, `operation`, `variables`, `schema` and `rootValue`, and its
  `path` is a `ResponsePath` (`toList()` gives the segments).
```

In `packages/typed_graphql_server/doc/execution.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,7 +1,8 @@
 # Execution
 
-Execution of requests arrives in M5b. The package holds, today, the two
-types the builder hands to it.
+`ExecutableSchema.execute` runs a validated document (the full Execution
+guide arrives with the rest of M5b). The package holds the two types the
+builder hands to it.
 
 `ExecutableSchema<C>` is what `ExecutableSchemaBuilder.build` returns: the
 validated core `ValidSchema` (`schema`) and the run-time tables of the
@@ -11,8 +12,10 @@ receive. The schema's SDL is
 
 `FieldInfo` is the last argument of a `resolve` closure: the field's name
 (`fieldName`), the name of the object type it is selected on
-(`parentTypeName`) and its response `path` from the root, a list of the
-core's `PathSegment`s.
+(`parentTypeName`) and its response `path` from the root, a `ResponsePath`
+whose `toList()` gives the core's `PathSegment`s. It also carries the
+parent `ObjectType`, the `returnType`, the `fieldNodes`, the `operation`, the
+raw `variables`, the `schema` and the `rootValue`.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
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
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/execution.md packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart packages/typed_graphql_server/lib/src/execution/completion_site.dart packages/typed_graphql_server/lib/src/execution/error_behavior.dart packages/typed_graphql_server/lib/src/execution/error_hook.dart packages/typed_graphql_server/lib/src/execution/error_log.dart packages/typed_graphql_server/lib/src/execution/error_reporter.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/lib/src/execution/execution_limits.dart packages/typed_graphql_server/lib/src/execution/execution_options.dart packages/typed_graphql_server/lib/src/execution/execution_run.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/field_info.dart packages/typed_graphql_server/lib/src/execution/leaf_completion.dart packages/typed_graphql_server/lib/src/execution/list_completion.dart packages/typed_graphql_server/lib/src/execution/object_completion.dart packages/typed_graphql_server/lib/src/execution/operation_execution.dart packages/typed_graphql_server/lib/src/execution/pending_values.dart packages/typed_graphql_server/lib/src/execution/response_path.dart packages/typed_graphql_server/lib/src/execution/selection_executor.dart packages/typed_graphql_server/lib/src/execution/serial_fields.dart packages/typed_graphql_server/lib/src/execution/value_completion.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/fields_test.dart packages/typed_graphql_server/test/execution/error_reporting_test.dart packages/typed_graphql_server/test/execution/execute_test.dart packages/typed_graphql_server/test/execution/execution_fixture.dart packages/typed_graphql_server/test/execution/limits_and_order_test.dart packages/typed_graphql_server/test/execution/null_propagation_test.dart
git commit -q -m "feat(typed_graphql_server): execute queries" \
  -m "ExecutableSchema.execute runs a validated document with null propagation, error masking, error behaviours and depth and step limits. FieldInfo now carries the full call context and a persistent ResponsePath." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Abstract types at run time

Complete `AbstractResolution` with the check that a `resolveType` result accepts the value (`GQL334`), test interface and union resolution end to end, and key the plan cache by `includesSuggestions` too, so cached argument messages follow each call's setting.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart`, `packages/typed_graphql_server/lib/src/plan/operation_planner.dart`, `packages/typed_graphql_server/lib/src/plan/plan_cache.dart`
- Test: `packages/typed_graphql_server/test/execution/abstract_types_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/execution/abstract_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Mood { happy, sad }

abstract class Shape {
  const Shape();
  int get sides;
}

final class Circle extends Shape {
  const Circle();
  @override
  int get sides => 0;
}

final class Square extends Shape {
  const Square();
  @override
  int get sides => 4;
}

final class Blob extends Shape {
  const Blob();
  @override
  int get sides => -1;
}

sealed class Fruit {
  const Fruit();
}

final class Apple extends Fruit {
  const Apple();
}

final class Pear extends Fruit {
  const Pear();
}

final class AbstractFixture {
  AbstractFixture() {
    final b = ExecutableSchemaBuilder<Object?>();
    final mood = b.enumType<Mood>('Mood', Mood.values);
    final moodArg = Arg('m', mood);
    final shape = b.interface<Shape>(
      'Shape',
      fields: (t) => [
        t
            .field('describe', b.string)
            .resolve((parent, args, context, info) => 'sides ${parent.sides}'),
      ],
    );
    final circle = b.object<Circle>(
      'Circle',
      interfaces: [shape],
      fields: (t) => [t.field('round', b.boolean).pure((_) => true)],
    );
    final square = b.object<Square>(
      'Square',
      interfaces: [shape],
      fields: (t) => [t.field('corners', b.int).pure((_) => 4)],
    );
    final blob = b.object<Blob>(
      'Blob',
      fields: (t) => [t.field('wobble', b.int).pure((_) => 1)],
    );
    final union = b.union<Shape>('Either', members: [circle, square]);
    final wrong = b.union<Shape>(
      'Wrong',
      members: [circle, square],
      resolveType: (_) => circle,
    );
    final outside = b.union<Shape>(
      'Outside',
      members: [circle, square],
      resolveType: (_) => blob,
    );
    late final ObjectTypeDef<Apple> apple;
    late final ObjectTypeDef<Pear> pear;
    final fruit = b.interface<Fruit>(
      'Fruit',
      fields: (t) => [t.field('name', b.string).declareOnly()],
      resolveType: (value) => switch (value) {
        Apple() => apple,
        Pear() => pear,
      },
    );
    apple = b.object<Apple>(
      'Apple',
      interfaces: [fruit],
      fields: (t) => [t.field('name', b.string).pure((_) => 'apple')],
    );
    pear = b.object<Pear>(
      'Pear',
      interfaces: [fruit],
      fields: (t) => [t.field('name', b.string).pure((_) => 'pear')],
    );
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('shape', shape).pure((_) => const Square()),
        t
            .field('shapes', b.list(shape))
            .pure((_) => const [Circle(), Square()]),
        t.field('either', union).pure((_) => const Circle()),
        t.field('lost', shape).pure((_) => const Blob()),
        t.field('wrong', wrong).pure((_) => const Square()),
        t.field('outside', outside).pure((_) => const Circle()),
        t
            .field('fruits', b.list(fruit))
            .pure((_) => const <Fruit>[Pear(), Apple()]),
        t
            .field('moodName', b.string, args: [moodArg])
            .resolve((parent, args, context, info) => 'ok'),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Object?> built;

  Future<Map<String, Object?>> json(
    String text, {
    Document? document,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final parsed = document ?? parse(text);
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, parsed),
      context: null,
      options: options,
    );
    return payload.toJson().toJson();
  }

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();
}

void main() {
  final f = AbstractFixture();

  Object? codeOf(Map<String, Object?> json) =>
      (((json['errors']! as List<Object?>).single!
              as Map<String, Object?>)['extensions']!
          as Map<String, Object?>)['code'];

  String messageOf(Map<String, Object?> json) =>
      ((json['errors']! as List<Object?>).single!
              as Map<String, Object?>)['message']!
          as String;

  group('abstract types at run time', () {
    test('an interface resolves to the first accepting object type', () async {
      expect(
        await f.json(
          '{ shape { __typename ... on Square { corners } } '
          'shapes { __typename } }',
        ),
        equals({
          'data': {
            'shape': {'__typename': 'Square', 'corners': 4},
            'shapes': [
              {'__typename': 'Circle'},
              {'__typename': 'Square'},
            ],
          },
        }),
      );
    });

    test('a union resolves by default', () async {
      expect(
        await f.json('{ either { __typename ... on Circle { round } } }'),
        equals({
          'data': {
            'either': {'__typename': 'Circle', 'round': true},
          },
        }),
      );
    });

    test('an inherited interface field runs with the object value', () async {
      expect(
        await f.json('{ shapes { describe } }'),
        equals({
          'data': {
            'shapes': [
              {'describe': 'sides 0'},
              {'describe': 'sides 4'},
            ],
          },
        }),
      );
    });

    test('an explicit resolveType can switch over a sealed class', () async {
      expect(
        await f.json('{ fruits { __typename name } }'),
        equals({
          'data': {
            'fruits': [
              {'__typename': 'Pear', 'name': 'pear'},
              {'__typename': 'Apple', 'name': 'apple'},
            ],
          },
        }),
      );
    });

    test('no accepting possible type is GQL333', () async {
      final json = await f.json('{ lost { __typename } }');
      expect(codeOf(json), 'GQL333');
      expect(
        messageOf(json),
        'Abstract type "Shape" must resolve to an Object type at runtime for '
        'field "Query.lost". Either the "Shape" type should provide a '
        '"resolveType" function or each possible type should provide an '
        '"isTypeOf" function.',
      );
      expect(json['data'], isNull);
    });

    test('a resolved type that is not possible is GQL334', () async {
      final json = await f.json('{ outside { __typename } }');
      expect(codeOf(json), 'GQL334');
      expect(
        messageOf(json),
        'Runtime Object type "Blob" is not a possible type for "Outside".',
      );
    });

    test('a resolved type that cannot hold the value is GQL334', () async {
      final json = await f.json('{ wrong { __typename } }');
      expect(codeOf(json), 'GQL334');
      expect(
        messageOf(json),
        'Runtime Object type "Circle" cannot hold the value of Dart type '
        'Square for "Wrong": it expects Circle.',
      );
    });
  });

  group('plan cache and suggestions', () {
    test('different suggestion flags get their own messages', () async {
      final document = f.parse('{ moodName(m: hapy) }');
      final withHint = await f.json('', document: document);
      final withoutHint = await f.json(
        '',
        document: document,
        options: const ExecutionOptions(includesSuggestions: false),
      );
      expect(messageOf(withHint), contains('Did you mean'));
      expect(messageOf(withoutHint), isNot(contains('Did you mean')));
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/abstract_types_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../builder/object_type_def.dart';
+import 'abstract_type_binding.dart';
 import 'completion_site.dart';
 import 'execution_run.dart';
 
@@ -38,11 +39,11 @@ final class AbstractResolution {
       );
       return null;
     }
-    if (!binding.possibleTypes.contains(chosen)) {
+    final problem = _impossibility(binding, chosen, type, value);
+    if (problem != null) {
       _run.reporter.fieldError(
         DiagnosticCode.impossibleRuntimeType,
-        'Runtime Object type "${chosen.name}" is not a possible type for '
-        '"${type.name}".',
+        problem,
         site,
       );
       return null;
@@ -53,6 +54,26 @@ final class AbstractResolution {
     };
   }
 
+  // The message of a GQL334, else null: [chosen] must be a possible type and,
+  // when it came from `resolveType`, must hold the value.
+  String? _impossibility(
+    AbstractTypeBinding binding,
+    ObjectTypeDef<Object?> chosen,
+    SchemaType type,
+    Object value,
+  ) {
+    if (!binding.possibleTypes.contains(chosen)) {
+      return 'Runtime Object type "${chosen.name}" is not a possible type '
+          'for "${type.name}".';
+    }
+    if (binding.resolveType != null && !chosen.accepts(value)) {
+      return 'Runtime Object type "${chosen.name}" cannot hold the value of '
+          'Dart type ${value.runtimeType} for "${type.name}": it expects '
+          '${chosen.dartTypeName}.';
+    }
+    return null;
+  }
+
   ObjectTypeDef<Object?>? _choose(
     ObjectTypeDef<Object?> Function(Object? value)? explicit,
     List<ObjectTypeDef<Object?>> possible,
```

In `packages/typed_graphql_server/lib/src/plan/operation_planner.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,7 +24,11 @@ final class OperationPlanner {
 
   /// The plan of the operation named [operationName] in [document].
   PlanResult plan(Document document, String? operationName) {
-    final known = cache.lookup(document, operationName);
+    final known = cache.lookup(
+      document,
+      operationName,
+      includesSuggestions: environment.includesSuggestions,
+    );
     if (known != null) {
       return PlanReady(known);
     }
@@ -33,26 +37,36 @@ final class OperationPlanner {
       case OperationRejected(:final error):
         return PlanRejected(error);
       case OperationSelected(:final operation):
-        final rootName = schema.rootTypeName(operation.operation);
-        final rootType = rootName == null ? null : schema.typeNamed(rootName);
-        if (rootType is! ObjectType) {
-          throw StateError(
-            'The root type of ${operation.operation.name} is '
-            'an object type of a validated schema.',
-          );
-        }
-        final plan = OperationPlan(
-          operation,
-          rootType,
-          {
-            for (final definition in document.definitions)
-              if (definition is FragmentDefinition)
-                definition.name.value: definition,
-          },
-          environment,
+        final plan = _build(document, operation);
+        cache.store(
+          document,
+          operationName,
+          plan,
+          includesSuggestions: environment.includesSuggestions,
         );
-        cache.store(document, operationName, plan);
         return PlanReady(plan);
     }
   }
+
+  OperationPlan _build(Document document, OperationDefinition operation) {
+    final schema = environment.schema;
+    final rootName = schema.rootTypeName(operation.operation);
+    final rootType = rootName == null ? null : schema.typeNamed(rootName);
+    if (rootType is! ObjectType) {
+      throw StateError(
+        'The root type of ${operation.operation.name} is '
+        'an object type of a validated schema.',
+      );
+    }
+    return OperationPlan(
+      operation,
+      rootType,
+      {
+        for (final definition in document.definitions)
+          if (definition is FragmentDefinition)
+            definition.name.value: definition,
+      },
+      environment,
+    );
+  }
 }
```

In `packages/typed_graphql_server/lib/src/plan/plan_cache.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,7 +5,9 @@ import 'operation_plan.dart';
 
 /// The plans of an `ExecutableSchema`, at most [capacity] of them, least
 /// recently used first out (R4.8). A plan is found by the identity of its
-/// [Document] (syntax nodes compare by identity) and the operation name.
+/// [Document] (syntax nodes compare by identity), the operation name and
+/// whether messages carry suggestions (a plan holds constant-argument
+/// problems, whose text depends on it).
 final class PlanCache(
   /// The most plans kept (`planCacheSize`).
   final int capacity,
@@ -13,7 +15,7 @@ final class PlanCache(
   /// Creates an empty cache.
   this : _plans = LruMap(capacity);
 
-  final LruMap<(Document, String?), OperationPlan> _plans;
+  final LruMap<(Document, String?, bool), OperationPlan> _plans;
   int _hits = 0;
   int _misses = 0;
 
@@ -27,8 +29,12 @@ final class PlanCache(
   int get length => _plans.length;
 
   /// The plan of [operationName] in [document], or null.
-  OperationPlan? lookup(Document document, String? operationName) {
-    final plan = _plans.use((document, operationName));
+  OperationPlan? lookup(
+    Document document,
+    String? operationName, {
+    required bool includesSuggestions,
+  }) {
+    final plan = _plans.use((document, operationName, includesSuggestions));
     if (plan == null) {
       _misses++;
     } else {
@@ -38,7 +44,12 @@ final class PlanCache(
   }
 
   /// Keeps [plan] for [operationName] in [document].
-  void store(Document document, String? operationName, OperationPlan plan) {
-    _plans.store((document, operationName), plan);
+  void store(
+    Document document,
+    String? operationName,
+    OperationPlan plan, {
+    required bool includesSuggestions,
+  }) {
+    _plans.store((document, operationName, includesSuggestions), plan);
   }
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/abstract_types_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart packages/typed_graphql_server/lib/src/plan/operation_planner.dart packages/typed_graphql_server/lib/src/plan/plan_cache.dart packages/typed_graphql_server/test/execution/abstract_types_test.dart
git commit -q -m "feat(typed_graphql_server): resolve abstract types at run time" \
  -m "A resolveType result must be a possible type and hold the value (GQL334, naming the Dart type); interface and union execution is tested end to end. Also fixes a Task 5 concern: the plan cache is keyed by includesSuggestions too, so cached constant-argument problems follow the call's flag." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Field middleware

Add `FieldResolver<C>`, `FieldMiddleware<C>`, `DirectiveMiddleware<C>` and `FieldSite`, `FieldStub.withMiddleware`, and `FieldMiddlewareComposer`, which composes global, field and directive middleware once per field at build. `BuildOptions` becomes `BuildOptions<C>` to hold the global middleware.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart`, `packages/typed_graphql_server/lib/src/execution/directive_middleware.dart`, `packages/typed_graphql_server/lib/src/execution/field_middleware.dart`, `packages/typed_graphql_server/lib/src/execution/field_resolver.dart`, `packages/typed_graphql_server/lib/src/execution/field_site.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/build_options.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, `packages/typed_graphql_server/lib/src/builder/field_def.dart`, `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/execution/middleware_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// builder/field_middleware_composer.dart
final class FieldMiddlewareComposer<C>
  FieldMiddlewareComposer(this._schema, this._options)
  SchemaBindings compose(SchemaBindings bindings)

// execution/directive_middleware.dart
typedef DirectiveMiddleware<C> = FieldResolver<C> Function(…)

// execution/field_middleware.dart
typedef FieldMiddleware<C> = FieldResolver<C> Function(…)

// execution/field_resolver.dart
typedef FieldResolver<C> = FutureOr<Object?> Function(…)

// execution/field_site.dart
final class FieldSite
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/execution/middleware_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/field_lane.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Log {
  final List<String> entries = [];
}

final tag = SchemaDirective(
  'tag',
  locations: const [DirectiveLocation.fieldDefinition],
);

void main() {
  final b = ExecutableSchemaBuilder<Log>();

  /// A middleware that logs [label] before and after the resolver it wraps.
  FieldMiddleware<Log> logging(String label) =>
      (next, site) => (parent, args, context, info) async {
        context.entries.add('>$label');
        final value = await next(parent, args, context, info);
        context.entries.add('<$label');
        return value;
      };

  Future<Map<String, Object?>> run(
    ExecutableSchema<Log> built,
    String text, [
    Log? log,
  ]) async {
    final document = ValidDocument.assumeValid(
      built.schema,
      const Parser(
        options: ParserOptions(maxTokens: null, maxDepth: null),
      ).parse(Source(text)).requireDocument(),
    );
    final payload = await built.execute(document, context: log ?? Log());
    return payload.toJson().toJson();
  }

  ExecutableSchema<Log> buildWith(
    List<FieldDef<Object?, Log>> Function(FieldsBuilder<Object?, Log> t) fields,
    BuildOptions<Log> options,
  ) {
    final c = ExecutableSchemaBuilder<Log>();
    return c.build(
      query: c.object<Object?>('Query', fields: fields),
      options: options,
    );
  }

  group('field middleware', () {
    test(
      'chains run global, field, directive slots, outermost first',
      () async {
        final log = Log();
        final built = buildWith(
          (t) => [
            t
                .field('a', b.string)
                .withMiddleware([logging('f1'), logging('f2')])
                .withDirectives([AppliedDirective('tag')])
                .resolve((parent, args, context, info) {
                  context.entries.add('resolve');
                  return 'a';
                }),
          ],
          BuildOptions(
            directives: [tag],
            middleware: [logging('g1'), logging('g2')],
            directiveMiddleware: {
              'tag': (next, directive) => logging('d')(next, _site),
            },
          ),
        );
        expect(await run(built, '{ a }', log), {
          'data': {'a': 'a'},
        });
        expect(log.entries, [
          '>g1',
          '>g2',
          '>f1',
          '>f2',
          '>d',
          'resolve',
          '<d',
          '<f2',
          '<f1',
          '<g2',
          '<g1',
        ]);
      },
    );

    test('an empty chain stores the resolver itself', () {
      final c = ExecutableSchemaBuilder<Log>();
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [
          t.field('a', c.string).resolve((p, args, context, info) => 'a'),
        ],
      );
      final built = c.build(query: query);
      final original = (query.fields.single.lane as ResolverLane).resolve;
      final stored = built.bindings.fields['Query']!['a']!.lane as ResolverLane;
      expect(identical(stored.resolve, original), isTrue);
    });

    test('a middleware that returns next costs nothing', () {
      final c = ExecutableSchemaBuilder<Log>();
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('a', c.string)
              .withMiddleware([(next, site) => next])
              .resolve((p, args, context, info) => 'a'),
        ],
      );
      final built = c.build(
        query: query,
        options: BuildOptions(middleware: [(next, site) => next]),
      );
      final original = (query.fields.single.lane as ResolverLane).resolve;
      final stored = built.bindings.fields['Query']!['a']!.lane as ResolverLane;
      expect(identical(stored.resolve, original), isTrue);
    });

    test(
      'a directive slot applies only to fields with the directive',
      () async {
        final log = Log();
        final built = buildWith(
          (t) => [
            t
                .field('tagged', b.string)
                .withDirectives([AppliedDirective('tag')])
                .resolve((parent, args, context, info) => 'x'),
            t
                .field('plain', b.string)
                .resolve(
                  (parent, args, context, info) => 'y',
                ),
          ],
          BuildOptions(
            directives: [tag],
            directiveMiddleware: {
              'tag': (next, directive) => (parent, args, context, info) {
                context.entries.add('${directive.name}:${info.fieldName}');
                return next(parent, args, context, info);
              },
            },
          ),
        );
        await run(built, '{ tagged plain }', log);
        expect(log.entries, ['tag:tagged']);
      },
    );

    test('a middleware sees the site of each field', () async {
      final seen = <String>[];
      final built = buildWith(
        (t) => [
          t.field('a', b.string).resolve((parent, args, context, info) => 'a'),
        ],
        BuildOptions(
          middleware: [
            (next, site) {
              seen.add('${site.parentType.name}.${site.field.name}');
              return next;
            },
          ],
        ),
      );
      expect(built, isNotNull);
      expect(seen, ['Query.a']);
    });

    test('a middleware changes results and recovers from errors', () async {
      final built = buildWith(
        (t) => [
          t
              .field('word', b.string)
              .withMiddleware([
                (next, site) => (parent, args, context, info) async {
                  final value = await next(parent, args, context, info);
                  return '${value! as String}!';
                },
              ])
              .resolve((parent, args, context, info) => 'hey'),
          t
              .field('broken', b.string)
              .withMiddleware([
                (next, site) => (parent, args, context, info) async {
                  try {
                    return await next(parent, args, context, info);
                  } on FormatException {
                    return 'recovered';
                  }
                },
              ])
              .resolve(
                (parent, args, context, info) =>
                    throw const FormatException('x'),
              ),
          t
              .field('denied', b.string.nullable)
              .withMiddleware([
                (next, site) =>
                    (parent, args, context, info) =>
                        throw const GraphQLException('denied'),
              ])
              .resolve((parent, args, context, info) => 'never'),
        ],
        const BuildOptions(),
      );
      final response = await run(built, '{ word broken denied }');
      expect(response['data'], {
        'word': 'hey!',
        'broken': 'recovered',
        'denied': null,
      });
      expect(
        ((response['errors']! as List<Object?>).single!
            as Map<String, Object?>)['message'],
        'denied',
      );
    });

    test('the pure lane has no chain', () async {
      var calls = 0;
      final built = buildWith(
        (t) => [t.field('p', b.string).pure((_) => 'pure')],
        BuildOptions(
          middleware: [
            (next, site) {
              calls++;
              return next;
            },
          ],
        ),
      );
      expect(await run(built, '{ p }'), {
        'data': {'p': 'pure'},
      });
      expect(calls, 0);
    });

    test('pure with field middleware is an ArgumentError', () {
      final stub = FieldsBuilder<Object?, Log>()
          .field('p', b.string)
          .withMiddleware([(next, site) => next]);
      expect(() => stub.pure((_) => 'x'), throwsArgumentError);
    });

    test('a slot for an undefined directive is an ArgumentError', () {
      expect(
        () => buildWith(
          (t) => [
            t.field('a', b.string).resolve((p, args, context, info) => 'a'),
          ],
          BuildOptions(
            directiveMiddleware: {'missing': (next, directive) => next},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('an inherited field is composed for each implementing object', () {
      final sites = <String>[];
      final c = ExecutableSchemaBuilder<Log>();
      final node = c.interface<Object?>(
        'Node',
        fields: (t) => [
          t
              .field('id', c.string)
              .resolve((parent, args, context, info) => 'id'),
        ],
      );
      final one = c.object<Object?>(
        'One',
        interfaces: [node],
        fields: (t) => [],
      );
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [t.field('one', one).pure((_) => 1)],
      );
      c.build(
        query: query,
        options: BuildOptions(
          middleware: [
            (next, site) {
              sites.add('${site.parentType.name}.${site.field.name}');
              return next;
            },
          ],
        ),
      );
      expect(sites, ['One.id']);
    });

    test('a definition reads through a wider static type', () {
      final c = ExecutableSchemaBuilder<Log>();
      final query = c.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('a', c.string)
              .withMiddleware([(next, site) => next])
              .resolve((p, args, context, info) => 'a'),
        ],
      );
      final FieldDef<Object?, Object?> wide = query.fields.single;
      expect(wide.middleware, hasLength(1));
    });
  });
}

final _site = FieldSite(
  ObjectType('Query'),
  SchemaField('a', const NamedType(Name('String'))),
);
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/middleware_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/field_middleware.dart';
import '../execution/field_resolver.dart';
import '../execution/field_site.dart';
import '../execution/schema_bindings.dart';
import 'build_options.dart';
import 'field_def.dart';
import 'field_lane.dart';

/// Composes the middleware chain of every resolver field once, when the
/// schema is built (spec 8), so the executor calls a single function.
final class FieldMiddlewareComposer<C> {
  /// Composes over [_schema] with the middleware in [_options].
  ///
  /// A directive slot for a directive the schema does not define is an
  /// [ArgumentError]: it is a programmer error, not input.
  FieldMiddlewareComposer(this._schema, this._options) {
    for (final name in _options.directiveMiddleware.keys) {
      if (_schema.directiveNamed(name) == null) {
        throw ArgumentError.value(
          name,
          'directiveMiddleware',
          'the schema defines no directive with this name',
        );
      }
    }
  }

  final Schema _schema;
  final BuildOptions<C> _options;

  /// [bindings] with each field replaced by its composed form. A field with
  /// an empty chain, or whose middleware all returned `next`, stays the
  /// very same definition.
  SchemaBindings compose(SchemaBindings bindings) => bindings.withFields({
    for (final MapEntry(key: typeName, value: fields)
        in bindings.fields.entries)
      typeName: _composeType(typeName, fields),
  });

  Map<String, FieldDef<Object?, Object?>> _composeType(
    String typeName,
    Map<String, FieldDef<Object?, Object?>> fields,
  ) {
    final parent = _schema.typeNamed(typeName);
    if (parent is! ObjectType) return fields;
    return {
      for (final MapEntry(key: name, value: field) in fields.entries)
        name: _composeField(parent, field),
    };
  }

  FieldDef<Object?, Object?> _composeField(
    ObjectType parent,
    FieldDef<Object?, Object?> definition,
  ) {
    final lane = definition.lane;
    final schemaField = parent.fieldNamed(definition.name);
    if (lane is! ResolverLane || schemaField == null) return definition;
    final site = FieldSite(parent, schemaField);
    final FieldResolver<C> base = lane.resolve;
    var resolver = base;
    for (final middleware in _chainOf(definition, schemaField).reversed) {
      resolver = middleware(resolver, site);
    }
    if (identical(resolver, base)) return definition;
    final composed = resolver;
    return definition.withLane(
      ResolverLane(
        (parent, arguments, context, info) =>
            composed(parent, arguments, context as C, info),
      ),
    );
  }

  // Global, then the field's own, then the directive slots in the order the
  // directives are applied; the first is outermost.
  List<FieldMiddleware<C>> _chainOf(
    FieldDef<Object?, Object?> definition,
    SchemaField schemaField,
  ) => [
    ..._options.middleware,
    for (final middleware in definition.middleware)
      middleware as FieldMiddleware<C>,
    for (final directive in schemaField.appliedDirectives)
      if (_options.directiveMiddleware[directive.name] case final slot?)
        (next, site) => slot(next, directive),
  ];
}
```

Create `packages/typed_graphql_server/lib/src/execution/directive_middleware.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'field_resolver.dart';

/// Wraps the resolver [next] of a field that carries the applied [directive].
///
/// Registered by directive name in `BuildOptions.directiveMiddleware`.
///
/// {@category execution}
typedef DirectiveMiddleware<C> = FieldResolver<C> Function(
  FieldResolver<C> next,
  AppliedDirective directive,
);
```

Create `packages/typed_graphql_server/lib/src/execution/field_middleware.dart`:

```dart
import 'field_resolver.dart';
import 'field_site.dart';

/// Wraps the resolver [next] of the field at [site] and returns the resolver
/// to run instead; returning [next] itself costs nothing at run time.
///
/// Composed once per field when the schema is built (spec 8).
///
/// {@category execution}
typedef FieldMiddleware<C> = FieldResolver<C> Function(
  FieldResolver<C> next,
  FieldSite site,
);
```

Create `packages/typed_graphql_server/lib/src/execution/field_resolver.dart`:

```dart
import 'dart:async';

import '../builder/arguments.dart';
import 'field_info.dart';

/// The function that produces a field's value: the parent, the coerced
/// arguments, the context and what is known about the field.
///
/// This is the shape of a resolver as the middleware chain sees it
/// (spec 8).
///
/// {@category execution}
typedef FieldResolver<C> = FutureOr<Object?> Function(
  Object? parent,
  Arguments args,
  C context,
  FieldInfo info,
);
```

Create `packages/typed_graphql_server/lib/src/execution/field_site.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Where a middleware is composed: an object type and one of its fields.
///
/// An inherited interface field is composed once per implementing object
/// type, so [parentType] is always the object type.
///
/// {@category execution}
final class FieldSite {
  /// Names the [field] of [parentType].
  const FieldSite(this.parentType, this.field);

  /// The object type that has the field.
  final ObjectType parentType;

  /// The field in the built schema.
  final SchemaField field;
}
```

In `packages/typed_graphql_server/lib/src/builder/build_options.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,18 +1,23 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../execution/directive_middleware.dart';
+import '../execution/field_middleware.dart';
+
 /// The settings of `ExecutableSchemaBuilder.build` besides the root types.
 ///
 /// Grouped in one object to keep `build` within five parameters; later
-/// stages add their settings here (plan cache size, middleware).
+/// stages add their settings here. `C` is the builder's context type.
 ///
 /// {@category builder}
-final class BuildOptions {
+final class BuildOptions<C> {
   /// Creates the options.
   const BuildOptions({
     this.directives = const [],
     this.includesDeferAndStream = false,
     this.description,
     this.planCacheSize = 1000,
+    this.middleware = const [],
+    this.directiveMiddleware = const {},
   }) : assert(planCacheSize >= 0, 'a cache size is not negative');
 
   /// The directive definitions the schema declares besides the specified
@@ -28,4 +33,13 @@ final class BuildOptions {
   /// How many operation plans the schema keeps (least recently used first
   /// out); zero keeps none.
   final int planCacheSize;
+
+  /// The global middleware, outermost first; each sees every resolver field
+  /// and returns `next` for those it ignores.
+  final List<FieldMiddleware<C>> middleware;
+
+  /// Middleware by directive name, applied to the fields that carry the
+  /// directive. A name the schema does not define is an [ArgumentError] when
+  /// the schema is built.
+  final Map<String, DirectiveMiddleware<C>> directiveMiddleware;
 }
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 import '../execution/executable_schema.dart';
 import 'build_options.dart';
 import 'builder_checks.dart';
+import 'field_middleware_composer.dart';
 import 'input_value_assembler.dart';
 import 'literal_writer.dart';
 import 'named_type_def.dart';
@@ -37,7 +38,7 @@ final class ExecutableSchemaAssembly<C> {
   final ObjectTypeDef<Object?>? subscription;
 
   /// The other settings.
-  final BuildOptions options;
+  final BuildOptions<C> options;
 
   /// Assembles the schema; throws [SchemaBuildError] on any problem.
   ExecutableSchema<C> assemble() {
@@ -52,9 +53,13 @@ final class ExecutableSchemaAssembly<C> {
     if (problems.any((problem) => problem.isError)) {
       throw SchemaBuildError(problems);
     }
+    final bindings = SchemaBindingsAssembler().assemble(
+      definitions,
+      possibleTypes,
+    );
     return ExecutableSchema(
       ValidSchema.assumeValid(schema),
-      SchemaBindingsAssembler().assemble(definitions, possibleTypes),
+      FieldMiddlewareComposer<C>(schema, options).compose(bindings),
       planCacheSize: options.planCacheSize,
     );
   }
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -192,12 +192,12 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
     required ObjectTypeDef<Object?> query,
     ObjectTypeDef<Object?>? mutation,
     ObjectTypeDef<Object?>? subscription,
-    BuildOptions options = const BuildOptions(),
+    BuildOptions<C>? options,
   }) => ExecutableSchemaAssembly<C>(
     definitions: definitions,
     query: query,
     mutation: mutation,
     subscription: subscription,
-    options: options,
+    options: options ?? BuildOptions<C>(),
   ).assemble();
 }
```

In `packages/typed_graphql_server/lib/src/builder/field_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,8 +20,10 @@ final class FieldDef<P, C> {
     required this.lane,
     this.description,
     this.deprecationReason,
+    List<Object> middleware = const [],
   }) : args = List.unmodifiable(args),
-       directives = List.unmodifiable(directives);
+       directives = List.unmodifiable(directives),
+       middleware = List.unmodifiable(middleware);
 
   /// The field's name in the schema.
   final String name;
@@ -43,4 +45,21 @@ final class FieldDef<P, C> {
 
   /// How the field produces its value.
   final FieldLane lane;
+
+  /// The `FieldMiddleware<C>` values of the field, erased to [Object]: a
+  /// definition read as `FieldDef<Object?, Object?>` must not hold a
+  /// `C`-typed function. The build casts them back where `C` is known.
+  final List<Object> middleware;
+
+  /// The same field with [lane] and no middleware of its own: the build
+  /// stores the composed chain this way.
+  FieldDef<P, C> withLane(FieldLane lane) => FieldDef(
+    name: name,
+    type: type,
+    args: args,
+    directives: directives,
+    lane: lane,
+    description: description,
+    deprecationReason: deprecationReason,
+  );
 }
```

In `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,7 @@ import 'dart:async';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../execution/field_info.dart';
+import '../execution/field_middleware.dart';
 import 'arg.dart';
 import 'arguments.dart';
 import 'arguments_def.dart';
@@ -24,7 +25,7 @@ final class FieldStub<P, R, C> {
     OutputRef<R> type, {
     List<Arg<Object?>> args = const [],
     String? description,
-  }) : this._(name, type, args, description, null, const []);
+  }) : this._(name, type, args, description, null, const [], const []);
 
   FieldStub._(
     this.name,
@@ -33,6 +34,7 @@ final class FieldStub<P, R, C> {
     this.description,
     this._deprecationReason,
     this._directives,
+    this._middleware,
   );
 
   /// The field's name.
@@ -47,17 +49,41 @@ final class FieldStub<P, R, C> {
   final List<Arg<Object?>> _args;
   final String? _deprecationReason;
   final List<AppliedDirective> _directives;
+  final List<FieldMiddleware<C>> _middleware;
 
   /// The same field, deprecated for [reason].
-  FieldStub<P, R, C> deprecated(String reason) =>
-      FieldStub._(name, type, _args, description, reason, _directives);
+  FieldStub<P, R, C> deprecated(String reason) => FieldStub._(
+    name,
+    type,
+    _args,
+    description,
+    reason,
+    _directives,
+    _middleware,
+  );
 
   /// The same field with [directives] applied after the ones already given.
   FieldStub<P, R, C> withDirectives(List<AppliedDirective> directives) =>
       FieldStub._(name, type, _args, description, _deprecationReason, [
         ..._directives,
         ...directives,
-      ]);
+      ], _middleware);
+
+  /// The same field with [middleware] after the ones already given.
+  ///
+  /// They run inside the global middleware and outside the directive ones,
+  /// the first of the list outermost (spec 8). A pure field has no chain:
+  /// combining it with middleware is an [ArgumentError].
+  FieldStub<P, R, C> withMiddleware(List<FieldMiddleware<C>> middleware) =>
+      FieldStub._(
+        name,
+        type,
+        _args,
+        description,
+        _deprecationReason,
+        _directives,
+        [..._middleware, ...middleware],
+      );
 
   /// Completes the field with a synchronous getter (the pure lane, R4.2).
   ///
@@ -70,6 +96,12 @@ final class FieldStub<P, R, C> {
         'arguments, use resolve or resolveWith.',
       );
     }
+    if (_middleware.isNotEmpty) {
+      throw ArgumentError(
+        'Field "$name" gives middleware and pure; a pure getter has no '
+        'middleware chain, use resolve.',
+      );
+    }
     return _define(PureLane((parent) => read(parent as P)), _args);
   }
 
@@ -125,5 +157,6 @@ final class FieldStub<P, R, C> {
     deprecationReason: _deprecationReason,
     directives: _directives,
     lane: lane,
+    middleware: _middleware,
   );
 }
```

In `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,17 @@ final class SchemaBindings {
        leaves = Map.unmodifiable(leaves),
        inputObjects = Map.unmodifiable(inputObjects);
 
+  /// The same tables with [fields] in place of the field tables.
+  SchemaBindings withFields(
+    Map<String, Map<String, FieldDef<Object?, Object?>>> fields,
+  ) => SchemaBindings(
+    objects: objects,
+    fields: fields,
+    abstractTypes: abstractTypes,
+    leaves: leaves,
+    inputObjects: inputObjects,
+  );
+
   /// The object types.
   final Map<String, ObjectTypeDef<Object?>> objects;
 
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -29,10 +29,14 @@ export 'src/builder/output_ref.dart';
 export 'src/builder/scalar_type_def.dart';
 export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
+export 'src/execution/directive_middleware.dart';
 export 'src/execution/error_behavior.dart';
 export 'src/execution/error_hook.dart';
 export 'src/execution/executable_schema.dart';
 export 'src/execution/execution_options.dart';
 export 'src/execution/field_info.dart';
+export 'src/execution/field_middleware.dart';
+export 'src/execution/field_resolver.dart';
+export 'src/execution/field_site.dart';
 export 'src/execution/graphql_exception.dart';
 export 'src/execution/response_path.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/middleware_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- Field middleware: `FieldResolver<C>`, `FieldMiddleware<C>`, `DirectiveMiddleware<C>` and `FieldSite`; `FieldStub.withMiddleware`, `BuildOptions.middleware` and
  `BuildOptions.directiveMiddleware`. Chains are composed once per field at
  build time (global, field, directive slots; outermost first); the pure lane
  and an empty chain are called directly. A slot for an undefined directive is
  an `ArgumentError`.
- **Breaking:** `BuildOptions` is generic (`BuildOptions<C>`) and `build` takes `BuildOptions<C>?`.
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
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/builder/build_options.dart packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart packages/typed_graphql_server/lib/src/builder/field_def.dart packages/typed_graphql_server/lib/src/builder/field_middleware_composer.dart packages/typed_graphql_server/lib/src/builder/field_stub.dart packages/typed_graphql_server/lib/src/execution/directive_middleware.dart packages/typed_graphql_server/lib/src/execution/field_middleware.dart packages/typed_graphql_server/lib/src/execution/field_resolver.dart packages/typed_graphql_server/lib/src/execution/field_site.dart packages/typed_graphql_server/lib/src/execution/schema_bindings.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/execution/middleware_test.dart
git commit -q -m "feat(typed_graphql_server): compose field middleware at build time" \
  -m "Global, field and directive-slot middleware are composed once per resolver field into the stored lane, so the executor still calls one function; the pure lane and an empty chain are untouched. BuildOptions becomes generic to carry the typed middleware." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Conformance: the executor suites

Add `ExecutionPort` and `UncheckedRef` to the conformance support, the `mapping/execution.csv` table, and port `executor-test.ts`, `resolve-test.ts`, `sync-test.ts` and `schema-test.ts`. The port found that fields an object type does not define were answered in an unvalidated document; the planner now skips them, as graphql-js does.

**Files:**
- Create: `packages/typed_graphql_conformance/mapping/execution.csv`
- Modify: `packages/typed_graphql_conformance/pubspec.yaml`, `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, `packages/typed_graphql_server/lib/src/plan/field_collector.dart`
- Test: `packages/typed_graphql_conformance/test/execution/executor_errors_test.dart`, `packages/typed_graphql_conformance/test/execution/executor_operations_test.dart`, `packages/typed_graphql_conformance/test/execution/executor_rest_test.dart`, `packages/typed_graphql_conformance/test/execution/executor_test.dart`, `packages/typed_graphql_conformance/test/execution/resolve_test.dart`, `packages/typed_graphql_conformance/test/execution/schema_test.dart`, `packages/typed_graphql_conformance/test/execution/sync_test.dart`, `packages/typed_graphql_conformance/test/support/execution_port.dart`, `packages/typed_graphql_conformance/test/support/unchecked_ref.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_server/test/execution/execute_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/execution/executor_errors_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/unchecked_ref.dart';

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles basic execution tasks', () {
    test('nulls out error subtrees', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('sync', b.string.nullable).pure((_) => 'sync'),
            t
                .field('syncError', b.string.nullable)
                .pure(
                  (_) =>
                      throw const GraphQLException('Error getting syncError'),
                ),
            t
                .field('async', b.string.nullable)
                .resolve((_, args, context, info) => Future.value('async')),
            t
                .field('asyncReject', b.string.nullable)
                .resolve(
                  (_, args, context, info) => Future<String?>.error(
                    const GraphQLException('Error getting asyncReject'),
                  ),
                ),
            t.field('asyncError', b.string.nullable).resolve((
              _,
              args,
              context,
              info,
            ) async {
              await Future<void>.value();
              throw const GraphQLException('Error getting asyncError');
            }),
            t
                .field('asyncErrorWithExtensions', b.string.nullable)
                .resolve(
                  (_, args, context, info) => Future<String?>.error(
                    GraphQLException(
                      'Error getting asyncErrorWithExtensions',
                      extensions: JsonObject({'foo': const JsonString('bar')}),
                    ),
                  ),
                ),
          ],
        ),
      );

      final result = await port.json(schema, '''

      {
        sync
        syncError
        async
        asyncReject
        asyncError
        asyncErrorWithExtensions
      }
    ''');

      expect(
        result,
        equals({
          'data': {
            'sync': 'sync',
            'syncError': null,
            'async': 'async',
            'asyncReject': null,
            'asyncError': null,
            'asyncErrorWithExtensions': null,
          },
          'errors': [
            {
              'message': 'Error getting syncError',
              'locations': [
                {'line': 4, 'column': 9},
              ],
              'path': ['syncError'],
            },
            {
              'message': 'Error getting asyncReject',
              'locations': [
                {'line': 6, 'column': 9},
              ],
              'path': ['asyncReject'],
            },
            {
              'message': 'Error getting asyncError',
              'locations': [
                {'line': 7, 'column': 9},
              ],
              'path': ['asyncError'],
            },
            {
              'message': 'Error getting asyncErrorWithExtensions',
              'locations': [
                {'line': 8, 'column': 9},
              ],
              'path': ['asyncErrorWithExtensions'],
              'extensions': {'foo': 'bar'},
            },
          ],
        }),
      );
    });

    test('nulls error subtree for promise rejection #1071', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final food = b.object<Object?>(
        'Food',
        fields: (t) => [
          t.field('name', b.string.nullable).pure((_) => null),
        ],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field('foods', b.list(food.nullable).nullable)
                .resolve(
                  (_, args, context, info) => Future<List<Object?>>.error(
                    const GraphQLException('Oops'),
                  ),
                ),
          ],
        ),
      );

      final result = await port.json(schema, '''

      query {
        foods {
          name
        }
      }
    ''');

      expect(
        result,
        equals({
          'data': {'foods': null},
          'errors': [
            {
              'locations': [
                {'column': 9, 'line': 3},
              ],
              'message': 'Oops',
              'path': ['foods'],
            },
          ],
        }),
      );
    });

    test('handles sync errors combined with rejections', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      var isAsyncResolverFinished = false;
      final nonNullString = UncheckedRef(
        const NonNullType(NamedType(Name('String'))),
        b.string,
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('syncNullError', nonNullString).pure((_) => null),
            t.field('asyncNullError', nonNullString).resolve((
              _,
              args,
              context,
              info,
            ) async {
              await Future<void>.value();
              await Future<void>.value();
              await Future<void>.value();
              isAsyncResolverFinished = true;
              return null;
            }),
          ],
        ),
      );

      // Order is important here, as the promise has to be created before the
      // synchronous error is thrown.
      final result = port.json(schema, '''

      {
        asyncNullError
        syncNullError
      }
    ''');

      expect(
        await result,
        equals({
          'data': null,
          'errors': [
            {
              'message':
                  'Cannot return null for non-nullable field '
                  'Query.syncNullError.',
              'locations': [
                {'line': 4, 'column': 9},
              ],
              'path': ['syncNullError'],
            },
            {
              'message':
                  'Cannot return null for non-nullable field '
                  'Query.asyncNullError.',
              'locations': [
                {'line': 3, 'column': 9},
              ],
              'path': ['asyncNullError'],
            },
          ],
        }),
      );
      // graphql-js answers before the started resolver is done and drops its
      // error; this executor waits for it, so no late error is lost.
      expect(isAsyncResolverFinished, isTrue);
    });

    test(
      'handles async bubbling errors combined with non-bubbling errors',
      () async {
        final b = ExecutableSchemaBuilder<Object?>();
        final nonNullString = UncheckedRef(
          const NonNullType(NamedType(Name('String'))),
          b.string,
        );
        final schema = b.build(
          query: b.object<Object?>(
            'Query',
            fields: (t) => [
              t.field('asyncNonNullError', nonNullString).resolve((
                _,
                args,
                context,
                info,
              ) async {
                await Future<void>.value();
                return null;
              }),
              t.field('asyncError', b.string.nullable).resolve((
                _,
                args,
                context,
                info,
              ) async {
                await Future<void>.value();
                throw const GraphQLException('Oops');
              }),
            ],
          ),
        );

        // Order is important here, as the nullable error should resolve
        // first.
        final result = await port.json(schema, '''

      {
        asyncError
        asyncNonNullError
      }
    ''');

        expect(
          result,
          equals({
            'data': null,
            'errors': [
              {
                'message': 'Oops',
                'locations': [
                  {'line': 3, 'column': 9},
                ],
                'path': ['asyncError'],
              },
              {
                'message':
                    'Cannot return null for non-nullable field '
                    'Query.asyncNonNullError.',
                'locations': [
                  {'line': 4, 'column': 9},
                ],
                'path': ['asyncNonNullError'],
              },
            ],
          }),
        );
      },
    );

    test('Full response path is included for non-nullable fields', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<Object?> a;
      a = b.object<Object?>(
        'A',
        fields: (t) => [
          t.field('nullableA', a.nullable).pure((_) => const Object()),
          t.field('nonNullA', a).pure((_) => const Object()),
          t
              .field('throws', b.string)
              .pure((_) => throw const GraphQLException('Catch me if you can')),
        ],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'query',
          fields: (t) => [
            t.field('nullableA', a.nullable).pure((_) => const Object()),
          ],
        ),
      );

      final result = await port.json(schema, '''

      query {
        nullableA {
          aliasedA: nullableA {
            nonNullA {
              anotherA: nonNullA {
                throws
              }
            }
          }
        }
      }
    ''');

      expect(
        result,
        equals({
          'data': {
            'nullableA': {'aliasedA': null},
          },
          'errors': [
            {
              'message': 'Catch me if you can',
              'locations': [
                {'line': 7, 'column': 17},
              ],
              'path': [
                'nullableA',
                'aliasedA',
                'nonNullA',
                'anotherA',
                'throws',
              ],
            },
          ],
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/executor_operations_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  // A root whose field `name` reads the key of the root value.
  ObjectTypeDef<Object?> root(
    ExecutableSchemaBuilder<Object?> b,
    String typeName,
    List<String> names,
  ) => b.object<Object?>(
    typeName,
    fields: (t) => [
      for (final name in names)
        t
            .field(name, b.string.nullable)
            .pure((rootValue) => (rootValue as Map<String, String>?)?[name]),
    ],
  );

  ExecutableSchema<Object?> querySchema() {
    final b = ExecutableSchemaBuilder<Object?>();
    return b.build(query: root(b, 'Type', ['a']));
  }

  const rootValue = ExecutionOptions(
    maskErrors: false,
    rootValue: <String, String>{'a': 'b', 'c': 'd'},
  );

  group('Execute: Handles basic execution tasks', () {
    test(
      'uses the inline operation if no operation name is provided',
      () async {
        expect(
          await port.json(
            querySchema(),
            '{ a }',
            options: const ExecutionOptions(
              maskErrors: false,
              rootValue: <String, String>{'a': 'b'},
            ),
          ),
          equals({
            'data': {'a': 'b'},
          }),
        );
      },
    );

    test('uses the only operation if no operation name is provided', () async {
      expect(
        await port.json(
          querySchema(),
          'query Example { a }',
          options: const ExecutionOptions(
            maskErrors: false,
            rootValue: <String, String>{'a': 'b'},
          ),
        ),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('uses the named operation if operation name is provided', () async {
      expect(
        await port.json(
          querySchema(),
          '''
      query Example { first: a }
      query OtherExample { second: a }
    ''',
          operationName: 'OtherExample',
          options: const ExecutionOptions(
            maskErrors: false,
            rootValue: <String, String>{'a': 'b'},
          ),
        ),
        equals({
          'data': {'second': 'b'},
        }),
      );
    });

    test('provides error if no operation is provided', () async {
      expect(
        await port.json(querySchema(), 'fragment Example on Type { a }'),
        equals({
          'errors': [
            {'message': 'Must provide an operation.'},
          ],
        }),
      );
    });

    test(
      'errors if no op name is provided with multiple operations',
      () async {
        expect(
          await port.json(querySchema(), '''
      query Example { a }
      query OtherExample { a }
    '''),
          equals({
            'errors': [
              {
                'message':
                    'Must provide operation name if query contains multiple '
                    'operations.',
              },
            ],
          }),
        );
      },
    );

    test('errors if unknown operation name is provided', () async {
      expect(
        await port.json(
          querySchema(),
          '''
      query Example { a }
      query OtherExample { a }
    ''',
          operationName: 'UnknownExample',
        ),
        equals({
          'errors': [
            {'message': 'Unknown operation named "UnknownExample".'},
          ],
        }),
      );
    });

    test('errors if empty string is provided as operation name', () async {
      expect(
        await port.json(querySchema(), '{ a }', operationName: ''),
        equals({
          'errors': [
            {'message': 'Unknown operation named "".'},
          ],
        }),
      );
    });

    test('uses the query schema for queries', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: root(b, 'Q', ['a']),
        mutation: root(b, 'M', ['c']),
        subscription: root(b, 'S', ['a']),
      );
      expect(
        await port.json(
          schema,
          '''
      query Q { a }
      mutation M { c }
      subscription S { a }
    ''',
          operationName: 'Q',
          options: rootValue,
        ),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('uses the mutation schema for mutations', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: root(b, 'Q', ['a']),
        mutation: root(b, 'M', ['c']),
      );
      expect(
        await port.json(
          schema,
          '''
      query Q { a }
      mutation M { c }
    ''',
          operationName: 'M',
          options: rootValue,
        ),
        equals({
          'data': {'c': 'd'},
        }),
      );
    });

    test('uses the subscription schema for subscriptions', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: root(b, 'Q', ['a']),
        subscription: root(b, 'S', ['a']),
      );
      expect(
        await port.json(
          schema,
          '''
      query Q { a }
      subscription S { a }
    ''',
          operationName: 'S',
          options: rootValue,
        ),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('resolves to an error if schema does not support operation', () async {
      final schema = querySchema();
      const text = '''

      query Q { __typename }
      mutation M { __typename }
      subscription S { __typename }
    ''';

      expect(
        await port.json(schema, text, operationName: 'Q'),
        equals({
          'data': {'__typename': 'Type'},
        }),
      );
      expect(
        await port.json(schema, text, operationName: 'M'),
        equals({
          'errors': [
            {
              'message':
                  'Schema is not configured to execute mutation operation.',
            },
          ],
        }),
      );
      expect(
        await port.json(schema, text, operationName: 'S'),
        equals({
          'errors': [
            {
              'message':
                  'Schema is not configured to execute subscription operation.',
            },
          ],
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/executor_rest_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles basic execution tasks', () {
    test('correct field ordering despite execution order', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('a', b.string.nullable).pure((_) => 'a'),
            t
                .field('b', b.string.nullable)
                .resolve((_, args, context, info) => Future.value('b')),
            t.field('c', b.string.nullable).pure((_) => 'c'),
            t
                .field('d', b.string.nullable)
                .resolve((_, args, context, info) => Future.value('d')),
            t.field('e', b.string.nullable).pure((_) => 'e'),
          ],
        ),
      );

      final result = await port.json(schema, '{ a, b, c, d, e }');

      expect(
        result,
        equals({
          'data': {'a': 'a', 'b': 'b', 'c': 'c', 'd': 'd', 'e': 'e'},
        }),
      );
      expect((result['data']! as Map<String, Object?>).keys, [
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
    });

    test('Avoids recursion', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [t.field('a', b.string.nullable).pure((_) => 'b')],
        ),
      );

      final result = port.run(schema, '''
      {
        a
        ...Frag
        ...Frag
      }

      fragment Frag on Type {
        a,
        ...Frag
      }
    ''');

      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'data': {'a': 'b'},
        }),
      );
    });

    test('ignores missing sub selections on fields', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final someType = b.object<Object?>(
        'SomeType',
        fields: (t) => [t.field('b', b.string.nullable).pure((_) => 'c')],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('a', someType.nullable).pure((_) => const Object()),
          ],
        ),
      );

      expect(
        await port.json(schema, '{ a }'),
        equals({
          'data': {'a': <String, Object?>{}},
        }),
      );
    });

    test('does not include illegal fields in output', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Q',
          fields: (t) => [t.field('a', b.string.nullable).pure((_) => null)],
        ),
      );

      expect(
        await port.json(schema, '{ thisIsIllegalDoNotIncludeMe }'),
        equals({'data': <String, Object?>{}}),
      );
    });

    test('does not include arguments that were not set', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final a = Arg.optional('a', b.boolean.nullable);
      final bArg = Arg.optional('b', b.boolean.nullable);
      final c = Arg.optional('c', b.boolean.nullable);
      final d = Arg.optional('d', b.int.nullable);
      final e = Arg.optional('e', b.int.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t
                .field('field', b.string.nullable, args: [a, bArg, c, d, e])
                .resolve((_, args, context, info) {
                  final given = [
                    for (final (name, arg) in [
                      ('a', a),
                      ('b', bArg),
                      ('c', c),
                      ('d', d),
                      ('e', e),
                    ])
                      if (args.get(arg) case Present(:final value))
                        '$name: $value',
                  ];
                  return '{ ${given.join(', ')} }';
                }),
          ],
        ),
      );

      expect(
        await port.json(schema, '{ field(a: true, c: false, e: 0) }'),
        equals({
          'data': {'field': '{ a: true, c: false, e: 0 }'},
        }),
      );
    });

    test('executes ignoring invalid non-executable definitions', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [t.field('foo', b.string.nullable).pure((_) => null)],
        ),
      );

      expect(
        await port.json(schema, '''
      { foo }

      type Query { bar: String }
    '''),
        equals({
          'data': {'foo': null},
        }),
      );
    });

    test('uses a custom type resolver', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<Object?> fooObject;
      final fooInterface = b.interface<Object?>(
        'FooInterface',
        fields: (t) => [t.field('bar', b.string.nullable).declareOnly()],
        resolveType: (_) => fooObject,
      );
      fooObject = b.object<Object?>(
        'FooObject',
        interfaces: [fooInterface],
        fields: (t) => [t.field('bar', b.string.nullable).pure((_) => 'bar')],
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('foo', fooInterface.nullable).pure((_) => const Object()),
          ],
        ),
      );

      expect(
        await port.json(schema, '{ foo { bar } }'),
        equals({
          'data': {
            'foo': {'bar': 'bar'},
          },
        }),
      );
      expect(
        [
          for (final type in schema.schema.schema.possibleTypes(
            schema.schema.schema.typeNamed('FooInterface')!,
          ))
            type.name,
        ],
        ['FooObject'],
      );
    });

    test('uses a different number of max coercion errors', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final email = Arg('email', b.string);
      final user = b.inputObject<Map<String, Object?>>(
        'User',
        fields: () => [email],
        decode: (values) => {'email': values.get(email)},
      );
      final data = Arg('data', user.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('dummy', b.string.nullable).pure((_) => null),
          ],
        ),
        mutation: b.object<Object?>(
          'Mutation',
          fields: (t) => [
            t
                .field('updateUser', b.string.nullable, args: [data])
                .resolve((_, args, context, info) => null),
          ],
        ),
      );
      const options = ExecutionOptions(maskErrors: false, maxCoercionErrors: 1);

      final result = await port.json(
        schema,
        r'''

      mutation ($data: User) {
        updateUser(data: $data)
      }
    ''',
        variables: JsonObject({
          'data': JsonObject({
            'email': const JsonString(''),
            'wrongArg': const JsonString('wrong'),
            'wrongArg2': const JsonString('wrong'),
            'wrongArg3': const JsonString('wrong'),
          }),
        }),
        options: options,
      );

      // Returns at least 2 errors, one for the first 'wrongArg', and one for
      // coercion limit.
      expect((result['errors']! as List<Object?>), hasLength(2));
      expect(
        result,
        equals({
          'errors': [
            {
              'message':
                  r'Variable "$data" has invalid value: Expected value of '
                  'type "User" not to include unknown field "wrongArg", '
                  'found: { email: "", wrongArg: "wrong", wrongArg2: '
                  '"wrong", wrongArg3: "wrong" }.',
              'locations': [
                {'line': 2, 'column': 17},
              ],
            },
            {
              'message':
                  'Too many errors processing variables, error limit '
                  'reached. Execution aborted.',
            },
          ],
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/executor_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Data {
  String a() => 'Apple';

  String b() => 'Banana';

  String c() => 'Cookie';

  String d() => 'Donut';

  String e() => 'Egg';

  String get f => 'Fish';

  String pic(int? size) => 'Pic of size: $size';

  _DeepData get deep => _DeepData(this);

  Future<_Data> get promise => Future.value(this);
}

final class _DeepData {
  _DeepData(this.data);

  final _Data data;

  String a() => 'Already Been Done';

  String b() => 'Boring';

  List<String?> c() => ['Contrived', null, 'Confusing'];

  List<_Data?> deeper() => [data, null, data];
}

// Ported from graphql-js src/execution/__tests__/executor-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles basic execution tasks', () {
    test('executes arbitrary code', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final size = Arg('size', b.int.nullable);
      late final ObjectTypeDef<_Data> dataType;
      final deepDataType = b.object<_DeepData>(
        'DeepDataType',
        fields: (t) => [
          t.field('a', b.string.nullable).pure((deep) => deep.a()),
          t.field('b', b.string.nullable).pure((deep) => deep.b()),
          t
              .field('c', b.list(b.string.nullable).nullable)
              .pure((deep) => deep.c()),
          t
              .field('deeper', b.list(dataType.nullable).nullable)
              .pure((deep) => deep.deeper()),
        ],
      );
      dataType = b.object<_Data>(
        'DataType',
        fields: (t) => [
          t.field('a', b.string.nullable).pure((data) => data.a()),
          t.field('b', b.string.nullable).pure((data) => data.b()),
          t.field('c', b.string.nullable).pure((data) => data.c()),
          t.field('d', b.string.nullable).pure((data) => data.d()),
          t.field('e', b.string.nullable).pure((data) => data.e()),
          t.field('f', b.string.nullable).pure((data) => data.f),
          t
              .field('pic', b.string.nullable, args: [size])
              .resolve((data, args, context, info) => data.pic(args.get(size))),
          t.field('deep', deepDataType.nullable).pure((data) => data.deep),
          t
              .field('promise', dataType.nullable)
              .resolve((data, args, context, info) => data.promise),
        ],
      );
      final schema = b.build(query: dataType);

      final result = await port.json(
        schema,
        r'''
      query ($size: Int) {
        a,
        b,
        x: c
        ...c
        f
        ...on DataType {
          pic(size: $size)
          promise {
            a
          }
        }
        deep {
          a
          b
          c
          deeper {
            a
            b
          }
        }
      }

      fragment c on DataType {
        d
        e
      }
    ''',
        variables: JsonObject({'size': JsonNumber(100)}),
        options: ExecutionOptions(maskErrors: false, rootValue: _Data()),
      );

      expect(
        result,
        equals({
          'data': {
            'a': 'Apple',
            'b': 'Banana',
            'x': 'Cookie',
            'd': 'Donut',
            'e': 'Egg',
            'f': 'Fish',
            'pic': 'Pic of size: 100',
            'promise': {'a': 'Apple'},
            'deep': {
              'a': 'Already Been Done',
              'b': 'Boring',
              'c': ['Contrived', null, 'Confusing'],
              'deeper': [
                {'a': 'Apple', 'b': 'Banana'},
                null,
                {'a': 'Apple', 'b': 'Banana'},
              ],
            },
          },
        }),
      );
    });

    test('merges parallel fragments', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<Object?> type;
      type = b.object<Object?>(
        'Type',
        fields: (t) => [
          t.field('a', b.string.nullable).pure((_) => 'Apple'),
          t.field('b', b.string.nullable).pure((_) => 'Banana'),
          t.field('c', b.string.nullable).pure((_) => 'Cherry'),
          t.field('deep', type.nullable).pure((_) => const Object()),
        ],
      );
      final schema = b.build(query: type);

      final result = port.run(schema, '''
      { a, ...FragOne, ...FragTwo }

      fragment FragOne on Type {
        b
        deep { b, deeper: deep { b } }
      }

      fragment FragTwo on Type {
        c
        deep { c, deeper: deep { c } }
      }
    ''');
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'data': {
            'a': 'Apple',
            'b': 'Banana',
            'c': 'Cherry',
            'deep': {
              'b': 'Banana',
              'c': 'Cherry',
              'deeper': {'b': 'Banana', 'c': 'Cherry'},
            },
          },
        }),
      );
    });

    test('provides info about current execution state', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final completer = Completer<String?>();
      FieldInfo? resolvedInfo;
      final testType = b.object<Object?>(
        'Test',
        fields: (t) => [
          t.field('test', b.string.nullable).resolve((
            value,
            args,
            context,
            info,
          ) {
            resolvedInfo = info;
            return completer.future;
          }),
        ],
      );
      final schema = b.build(query: testType);
      const rootValue = <String, Object?>{'root': 'val'};

      final result = port.run(
        schema,
        r'query ($var: String) { result: test }',
        variables: JsonObject({'var': const JsonString('abc')}),
        options: const ExecutionOptions(
          maskErrors: false,
          rootValue: rootValue,
        ),
      );

      final info = resolvedInfo!;
      expect(info.fieldName, 'test');
      expect(const Printer().print(info.returnType), 'String');
      expect(info.parentType.name, 'Test');
      expect(info.path.toString(), 'result');
      expect(info.schema, same(schema.schema));
      expect(info.rootValue, same(rootValue));
      expect(info.operation.operation, OperationType.query);
      expect(info.fieldNodes.single.alias?.value, 'result');
      expect(info.variables, JsonObject({'var': const JsonString('abc')}));

      completer.complete('done');
      await result;
    });

    test('populates path correctly with complex types', () {
      final b = ExecutableSchemaBuilder<Object?>();
      String? path;
      final someObject = b.object<Object?>(
        'SomeObject',
        fields: (t) => [
          t.field('test', b.string.nullable).resolve((
            value,
            args,
            context,
            info,
          ) {
            path = info.path.toString();
            return null;
          }),
        ],
      );
      final someUnion = b.union<Object?>(
        'SomeUnion',
        members: [someObject],
        resolveType: (_) => someObject,
      );
      final schema = b.build(
        query: b.object<Object?>(
          'SomeQuery',
          fields: (t) => [
            t.field('test', b.list(someUnion)).pure((_) => const [Object()]),
          ],
        ),
      );

      port.run(schema, '''
      query {
        l1: test {
          ... on SomeObject {
            l2: test
          }
        }
      }
    ''');

      expect(path, 'l1.0.l2');
    });

    test('threads root value context correctly', () {
      final b = ExecutableSchemaBuilder<Object?>();
      Object? resolvedRootValue;
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('a', b.string.nullable).pure((rootValue) {
              resolvedRootValue = rootValue;
              return null;
            }),
          ],
        ),
      );
      const rootValue = <String, Object?>{'contextThing': 'thing'};

      port.run(
        schema,
        'query Example { a }',
        options: const ExecutionOptions(rootValue: rootValue),
      );

      expect(resolvedRootValue, same(rootValue));
    });

    test('correctly threads arguments', () {
      final b = ExecutableSchemaBuilder<Object?>();
      final numArg = Arg('numArg', b.int.nullable);
      final stringArg = Arg('stringArg', b.string.nullable);
      (int?, String?)? resolvedArgs;
      final schema = b.build(
        query: b.object<Object?>(
          'Type',
          fields: (t) => [
            t.field('b', b.string.nullable, args: [numArg, stringArg]).resolve((
              _,
              args,
              context,
              info,
            ) {
              resolvedArgs = (args.get(numArg), args.get(stringArg));
              return null;
            }),
          ],
        ),
      );

      port.run(schema, '''
      query Example {
        b(numArg: 123, stringArg: "foo")
      }
    ''');

      expect(resolvedArgs, (123, 'foo'));
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/resolve_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/resolve-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: resolve function', () {
    test('default function accesses properties', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final schema = b.build(
        query: b.object<Map<String, Object?>>(
          'Query',
          fields: (t) => [
            t.field('test', b.string.nullable).pure((root) {
              return root['test'] as String?;
            }),
          ],
        ),
      );
      final result = await port.json(
        schema,
        '{ test }',
        options: const ExecutionOptions(
          maskErrors: false,
          rootValue: <String, Object?>{'test': 'testValue'},
        ),
      );
      expect(
        result,
        equals({
          'data': {'test': 'testValue'},
        }),
      );
    });

    test('default function passes args and context', () async {
      final b = ExecutableSchemaBuilder<int>();
      final addend1 = Arg('addend1', b.int.nullable);
      final schema = b.build(
        query: b.object<int>(
          'Query',
          fields: (t) => [
            t.field('test', b.int.nullable, args: [addend1]).resolve((
              base,
              args,
              addend2,
              info,
            ) {
              final int addend1Value = args.get(addend1)!;
              return base + addend1Value + addend2;
            }),
          ],
        ),
      );
      final result = await port.payload<int>(
        schema,
        '{ test(addend1: 80) }',
        context: 9,
        options: const ExecutionOptions(maskErrors: false, rootValue: 700),
      );
      expect(
        port.withoutCodes(result),
        equals({
          'data': {'test': 789},
        }),
      );
    });

    test('uses provided resolve function', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final aStr = Arg.optional('aStr', b.string.nullable);
      final aInt = Arg.optional('aInt', b.int.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('test', b.string.nullable, args: [aStr, aInt]).resolve((
              source,
              args,
              context,
              info,
            ) {
              final given = <String, Object?>{
                if (args.get(aStr) case Present(:final value)) 'aStr': value,
                if (args.get(aInt) case Present(:final value)) 'aInt': value,
              };
              return jsonEncode([source, given]);
            }),
          ],
        ),
      );

      Future<Map<String, Object?>> executeQuery(
        String query, [
        Object? rootValue,
      ]) => port.json(
        schema,
        query,
        options: ExecutionOptions(maskErrors: false, rootValue: rootValue),
      );

      expect(
        await executeQuery('{ test }'),
        equals({
          'data': {'test': '[null,{}]'},
        }),
      );
      expect(
        await executeQuery('{ test }', 'Source!'),
        equals({
          'data': {'test': '["Source!",{}]'},
        }),
      );
      expect(
        await executeQuery('{ test(aStr: "String!") }', 'Source!'),
        equals({
          'data': {'test': '["Source!",{"aStr":"String!"}]'},
        }),
      );
      expect(
        await executeQuery('{ test(aInt: -123, aStr: "String!") }', 'Source!'),
        equals({
          'data': {'test': '["Source!",{"aStr":"String!","aInt":-123}]'},
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

final class _Pic {
  const _Pic(this.url, this.width, this.height);

  final String url;
  final int? width;
  final int? height;
}

final class _Author {
  const _Author();

  _Pic pic(int? width, int? height) => _Pic('cdn://123', width, height);

  _Article recentArticle() => const _Article(1);
}

final class _Article {
  const _Article(this.id);

  final int id;

  _Author get author => const _Author();

  String get title => 'My Article $id';
}

// Ported from graphql-js src/execution/__tests__/schema-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: Handles execution with a complex schema', () {
    test('executes using a schema', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final width = Arg('width', b.int.nullable);
      final height = Arg('height', b.int.nullable);
      final image = b.object<_Pic>(
        'Image',
        fields: (t) => [
          t.field('url', b.string.nullable).pure((pic) => pic.url),
          t.field('width', b.int.nullable).pure((pic) => pic.width),
          t.field('height', b.int.nullable).pure((pic) => pic.height),
        ],
      );
      late final ObjectTypeDef<_Author> author;
      late final ObjectTypeDef<_Article> article;
      author = b.object<_Author>(
        'Author',
        fields: (t) => [
          t.field('id', b.string.nullable).pure((_) => '123'),
          t.field('name', b.string.nullable).pure((_) => 'John Smith'),
          t
              .field('pic', image.nullable, args: [width, height])
              .resolve(
                (obj, args, context, info) =>
                    obj.pic(args.get(width), args.get(height)),
              ),
          t
              .field('recentArticle', article.nullable)
              .pure((obj) => obj.recentArticle()),
        ],
      );
      article = b.object<_Article>(
        'Article',
        fields: (t) => [
          t.field('id', b.string).pure((article) => '${article.id}'),
          t.field('isPublished', b.boolean.nullable).pure((_) => true),
          t.field('author', author.nullable).pure((article) => article.author),
          t.field('title', b.string.nullable).pure((article) => article.title),
          t.field('body', b.string.nullable).pure((_) => 'This is a post'),
          t
              .field('keywords', b.list(b.string.nullable).nullable)
              .pure((_) => ['foo', 'bar', '1', 'true', null]),
        ],
      );
      final articleId = Arg('id', b.id.nullable);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field('article', article.nullable, args: [articleId])
                .resolve(
                  (_, args, context, info) =>
                      _Article(int.parse(args.get(articleId)!)),
                ),
            t
                .field('feed', b.list(article.nullable).nullable)
                .pure(
                  (_) => [for (var id = 1; id <= 10; id++) _Article(id)],
                ),
          ],
        ),
      );

      // Note: this is intentionally not validating to ensure appropriate
      // behavior occurs when executing an invalid query.
      final result = await port.json(schema, '''
      {
        feed {
          id,
          title
        },
        article(id: "1") {
          ...articleFields,
          author {
            id,
            name,
            pic(width: 640, height: 480) {
              url,
              width,
              height
            },
            recentArticle {
              ...articleFields,
              keywords
            }
          }
        }
      }

      fragment articleFields on Article {
        id,
        isPublished,
        title,
        body,
        hidden,
        notDefined
      }
    ''');
      expect(
        result,
        equals({
          'data': {
            'feed': [
              for (var id = 1; id <= 10; id++)
                {'id': '$id', 'title': 'My Article $id'},
            ],
            'article': {
              'id': '1',
              'isPublished': true,
              'title': 'My Article 1',
              'body': 'This is a post',
              'author': {
                'id': '123',
                'name': 'John Smith',
                'pic': {'url': 'cdn://123', 'width': 640, 'height': 480},
                'recentArticle': {
                  'id': '1',
                  'isPublished': true,
                  'title': 'My Article 1',
                  'body': 'This is a post',
                  'keywords': ['foo', 'bar', '1', 'true', null],
                },
              },
            },
          },
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/sync_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/sync-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  final b = ExecutableSchemaBuilder<Object?>();
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('syncField', b.string.nullable)
            .pure((rootValue) => rootValue as String?),
        t
            .field('asyncField', b.string.nullable)
            .resolve(
              (rootValue, args, context, info) =>
                  Future.value(rootValue as String?),
            ),
      ],
    ),
    mutation: b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t
            .field('syncMutationField', b.string.nullable)
            .pure((rootValue) => rootValue as String?),
      ],
    ),
    options: const BuildOptions<Object?>(includesDeferAndStream: true),
  );
  const withRoot = ExecutionOptions(maskErrors: false, rootValue: 'rootValue');

  group('Execute: synchronously when possible', () {
    test('does not return a Promise for initial errors', () {
      final result = port.run(
        schema,
        'fragment Example on Query { syncField }',
        options: withRoot,
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'errors': [
            {'message': 'Must provide an operation.'},
          ],
        }),
      );
    });

    test('does not return a Promise if fields are all synchronous', () {
      final result = port.run(
        schema,
        'query Example { syncField }',
        options: withRoot,
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({
          'data': {'syncField': 'rootValue'},
        }),
      );
    });

    test(
      'does not return a Promise if mutation fields are all synchronous',
      () {
        final result = port.run(
          schema,
          'mutation Example { syncMutationField }',
          options: withRoot,
        );
        expect(result, isNot(isA<Future<Object?>>()));
        expect(
          port.withoutCodes(result as ResponsePayload),
          equals({
            'data': {'syncMutationField': 'rootValue'},
          }),
        );
      },
    );

    test('returns a Promise if any field is asynchronous', () async {
      final result = port.run(
        schema,
        'query Example { syncField, asyncField }',
        options: withRoot,
      );
      expect(result, isA<Future<Object?>>());
      expect(
        port.withoutCodes(await result),
        equals({
          'data': {'syncField': 'rootValue', 'asyncField': 'rootValue'},
        }),
      );
    });

    group('executeSync', () {
      test('does not return a Promise for sync execution', () {
        final result = port.run(
          schema,
          'query Example { syncField }',
          options: withRoot,
        );
        expect(result, isNot(isA<Future<Object?>>()));
        expect(
          port.withoutCodes(result as ResponsePayload),
          equals({
            'data': {'syncField': 'rootValue'},
          }),
        );
      });

      test('throws if encountering async execution', () {
        final result = port.run(
          schema,
          'query Example { syncField, asyncField }',
          options: withRoot,
        );
        expect(result, isA<Future<Object?>>());
      });

      test('throws if encountering async iterable execution', () {
        final result = port.run(
          schema,
          '''
        query Example {
          ...deferFrag @defer(label: "deferLabel")
        }
        fragment deferFrag on Query {
          syncField
        }
      ''',
          options: withRoot,
        );
        expect(result, isNot(isA<Future<Object?>>()));
        expect(
          port.withoutCodes(result as ResponsePayload),
          equals({
            'data': {'syncField': 'rootValue'},
          }),
        );
      });
    });

    group('graphqlSync', () {
      test('does not return a Promise for syntax errors', () async {
        expect(
          await port.respond(
            schema,
            'fragment Example on Query { { { syncField }',
          ),
          equals({
            'errors': [
              {
                'message': 'Syntax Error: Expected Name, found "{".',
                'locations': [
                  {'line': 1, 'column': 29},
                ],
              },
            ],
          }),
        );
      });

      test('does not return a Promise for validation errors', () async {
        const text = 'fragment Example on Query { unknownField }';
        final validationErrors = const DocumentValidator()
            .validate(schema.schema, port.parse(text), source: Source(text))
            .diagnostics;
        expect(
          await port.respond(schema, text),
          equals(port.problems(validationErrors)),
        );
      });

      test('does not return a Promise for sync execution', () async {
        expect(
          await port.respond(
            schema,
            'query Example { syncField }',
            rootValue: 'rootValue',
          ),
          equals({
            'data': {'syncField': 'rootValue'},
          }),
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/support/execution_port.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// graphql-js's `execute`, `executeSync` and `graphqlSync` as the ported
/// execution tests use them: the text is parsed with its [Source] (so
/// locations match), run, and the response is compared as JSON with the
/// codes the library adds to `extensions` dropped (spec 18.7 of M5).
///
/// A multi-line Dart literal drops the line break right after its opening
/// quotes, which a graphql-js template literal keeps: a test that checks
/// locations starts its literal with `\n` to restore the line count.
final class ExecutionPort {
  /// Creates the helpers; they keep no state.
  const ExecutionPort();

  /// The options every run starts from: error messages are not masked, as
  /// graphql-js's are not.
  static const ExecutionOptions unmasked = ExecutionOptions(maskErrors: false);

  /// The document of [text], which may be invalid: graphql-js's tests run
  /// documents that were never validated.
  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  /// Executes [text] in [schema] without validating it; the result is a
  /// future only when a resolver waited.
  FutureOr<ResponsePayload> payload<C>(
    ExecutableSchema<C> schema,
    String text, {
    required C context,
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = unmasked,
  }) => schema.execute(
    ValidDocument.assumeValid(schema.schema, parse(text)),
    context: context,
    operationName: operationName,
    variables: variables,
    options: ExecutionOptions(
      rootValue: options.rootValue,
      source: Source(text),
      errorBehavior: options.errorBehavior,
      maskErrors: options.maskErrors,
      onError: options.onError,
      maxCoercionErrors: options.maxCoercionErrors,
      maxDepth: options.maxDepth,
      maxSteps: options.maxSteps,
    ),
  );

  /// [payload] for a schema whose context is not read.
  FutureOr<ResponsePayload> run(
    ExecutableSchema<Object?> schema,
    String text, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = unmasked,
  }) => payload<Object?>(
    schema,
    text,
    context: null,
    operationName: operationName,
    variables: variables,
    options: options,
  );

  /// The response of [run] as JSON, awaited.
  Future<Map<String, Object?>> json(
    ExecutableSchema<Object?> schema,
    String text, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = unmasked,
  }) async => withoutCodes(
    await run(
      schema,
      text,
      operationName: operationName,
      variables: variables,
      options: options,
    ),
  );

  /// The JSON of [response] with every `extensions.code` dropped, and an
  /// `extensions` object that held nothing else.
  Map<String, Object?> withoutCodes(ResponsePayload response) {
    final json = response.toJson().toJson();
    final errors = json['errors'];
    if (errors is! List<Object?>) {
      return json;
    }
    return {
      ...json,
      'errors': [for (final error in errors) _withoutCode(error)],
    };
  }

  Object? _withoutCode(Object? error) {
    if (error is! Map<String, Object?>) {
      return error;
    }
    final extensions = error['extensions'];
    if (extensions is! Map<String, Object?>) {
      return error;
    }
    final rest = {...extensions}..remove('code');
    return {
      for (final entry in error.entries)
        if (entry.key != 'extensions') entry.key: entry.value,
      if (rest.isNotEmpty) 'extensions': rest,
    };
  }

  /// graphql-js's `graphqlSync`: parse, validate and execute [text], with
  /// each syntax or validation problem as an error with its locations.
  Future<Map<String, Object?>> respond(
    ExecutableSchema<Object?> schema,
    String text, {
    Object? rootValue,
  }) async {
    final source = Source(text);
    final parsed = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source);
    if (parsed is ParseFailure) {
      return problems(parsed.diagnostics, prefix: 'Syntax Error: ');
    }
    final validated = const DocumentValidator().validate(
      schema.schema,
      (parsed as ParseSuccess).document,
      source: source,
    );
    if (validated is InvalidDocument) {
      return problems(validated.diagnostics);
    }
    return withoutCodes(
      await schema.execute(
        validated as ValidDocument,
        context: null,
        options: ExecutionOptions(
          rootValue: rootValue,
          source: source,
          maskErrors: false,
        ),
      ),
    );
  }

  /// [diagnostics] as graphql-js's errors JSON, each message after
  /// [prefix] and with the line and column of its place.
  Map<String, Object?> problems(
    List<Diagnostic> diagnostics, {
    String prefix = '',
  }) => {
    'errors': [
      for (final diagnostic in diagnostics)
        {
          'message': '$prefix${diagnostic.message}',
          if (diagnostic.span case final span?)
            'locations': [
              {'line': span.location.line, 'column': span.location.column},
            ],
        },
    ],
  };
}
```

Create `packages/typed_graphql_conformance/test/support/unchecked_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// A reference with the GraphQL type [typeRef] whatever the Dart value is:
/// graphql-js's tests make a non-null field return `null`, which a typed
/// resolver cannot do.
final class UncheckedRef implements OutputRef<Object?> {
  /// A reference of GraphQL type [typeRef] over the named type [namedType].
  UncheckedRef(this.typeRef, this.namedType);

  @override
  final TypeRef typeRef;

  @override
  final NamedTypeDef namedType;

  @override
  OutputRef<Object?> get nullable => throw UnimplementedError();
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -90,6 +90,16 @@ void main() {
         'utilities/__tests__/resolveSchemaCoordinate-test.ts',
       ],
     ),
+    (
+      path: 'mapping/execution.csv',
+      prefix: '',
+      covered: const [
+        'execution/__tests__/executor-test.ts',
+        'execution/__tests__/resolve-test.ts',
+        'execution/__tests__/schema-test.ts',
+        'execution/__tests__/sync-test.ts',
+      ],
+    ),
     (
       path: 'mapping/validation.csv',
       prefix: '',
```

In `packages/typed_graphql_server/test/execution/execute_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,6 +56,21 @@ void main() {
       );
     });
 
+    test(
+      'a field the type does not define is left out of the response',
+      () async {
+        expect(
+          await f.json('{ hello nope: missing pet { name gone } }'),
+          equals({
+            'data': {
+              'hello': 'world',
+              'pet': {'name': 'rex'},
+            },
+          }),
+        );
+      },
+    );
+
     test('aliases are the response keys', () async {
       expect(
         await f.json('{ a: hello b: hello }'),
```

- [ ] **Step 2: Write the implementation**

Create `packages/typed_graphql_conformance/mapping/execution.csv`:

```csv
graphql_js_file,group,test,status,dart_file,reason
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,executes arbitrary code,adapted,test/execution/executor_test.dart,There are no default resolvers: each field of the typed schema declares a getter over Dart classes whose methods stand for the JavaScript functions.
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,merges parallel fragments,ported,test/execution/executor_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,provides info about current execution state,adapted,test/execution/executor_test.dart,"FieldInfo has no fragments, variableValues sources, getAbortSignal or getAsyncHelpers (cancellation is M5d); the fields it has are checked."
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,populates path correctly with complex types,adapted,test/execution/executor_test.dart,ResponsePath holds keys and indexes without the typename of each step; the path is compared as l1.0.l2.
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,threads root value context correctly,ported,test/execution/executor_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,correctly threads arguments,ported,test/execution/executor_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,nulls out error subtrees,adapted,test/execution/executor_errors_test.dart,"Errors are thrown or rejected as GraphQLException; a returned Error object, a thrown non-Error value and an empty rejection are JavaScript-only (a Dart value is never an error), so their fields are not ported."
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,nulls error subtree for promise rejection #1071,ported,test/execution/executor_errors_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,handles sync errors combined with rejections,adapted,test/execution/executor_errors_test.dart,"The executor waits for the resolvers that already started before it answers, so the late non-null error of asyncNullError is in the response (graphql-js answers first and drops it)."
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,handles async bubbling errors combined with non-bubbling errors,ported,test/execution/executor_errors_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,Full response path is included for non-nullable fields,ported,test/execution/executor_errors_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the inline operation if no operation name is provided,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the only operation if no operation name is provided,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the named operation if operation name is provided,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,provides error if no operation is provided,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,errors if no op name is provided with multiple operations,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,errors if unknown operation name is provided,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,errors if empty string is provided as operation name,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the query schema for queries,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the mutation schema for mutations,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the subscription schema for subscriptions,ported,test/execution/executor_operations_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,resolves to an error if schema does not support operation,adapted,test/execution/executor_operations_test.dart,"A built schema always has a query root, so the query operation of a schema without roots cannot be run; the mutation and subscription requests are request errors (a RequestErrorResult has no data: null, and an operation error carries no locations)."
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,correct field ordering despite execution order,ported,test/execution/executor_rest_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,Avoids recursion,ported,test/execution/executor_rest_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,ignores missing sub selections on fields,ported,test/execution/executor_rest_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,does not include illegal fields in output,ported,test/execution/executor_rest_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,does not include arguments that were not set,adapted,test/execution/executor_rest_test.dart,The resolver reads Arg.optional values and prints the Present ones itself; inspect(args) is JavaScript-only.
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,fails when an isTypeOf check is not met,skipped,,A field of object type returns that type's Dart class and is never checked against isTypeOf; isTypeOf only picks the type of an abstract value (abstract types are ported in M5b Task 11).
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,fails when coerceOutputValue of custom scalar does not return a value,skipped,,ScalarCodec.encode returns a JsonValue and cannot return undefined.
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,executes ignoring invalid non-executable definitions,ported,test/execution/executor_rest_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses a custom field resolver,skipped,,There is no default field resolver to replace: every field declares its resolver.
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses a custom type resolver,adapted,test/execution/executor_rest_test.dart,"The type resolver is the resolveType of the interface definition; it cannot reach info.schema, so the possible types are checked on the schema."
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses a different number of max coercion errors,ported,test/execution/executor_rest_test.dart,
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,memoizes collectSubfields results,skipped,,Tests a graphql-js internal function; the plan cache memoises collection (server plan tests).
execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,memoizes getStreamUsage results,skipped,,Tests a graphql-js internal function; @stream runs inline in execute.
execution/__tests__/resolve-test.ts,Execute: resolve function,default function accesses properties,adapted,test/execution/resolve_test.dart,No default resolvers: the field declares a getter over the root value.
execution/__tests__/resolve-test.ts,Execute: resolve function,default function calls methods,skipped,,JavaScript-only: a method found by name and called with this.
execution/__tests__/resolve-test.ts,Execute: resolve function,default function passes args and context,adapted,test/execution/resolve_test.dart,"No default resolvers: the field declares a resolver that reads the root value, the argument and the context."
execution/__tests__/resolve-test.ts,Execute: resolve function,uses provided resolve function,adapted,test/execution/resolve_test.dart,The arguments are Arg.optional values that the resolver prints as JSON.
execution/__tests__/schema-test.ts,Execute: Handles execution with a complex schema,executes using a schema,adapted,test/execution/schema_test.dart,"Values are typed Dart values (no number-to-string coercion by default resolvers); the document is not validated, as in graphql-js."
execution/__tests__/sync-test.ts,Execute: synchronously when possible,does not return a Promise for initial errors,ported,test/execution/sync_test.dart,
execution/__tests__/sync-test.ts,Execute: synchronously when possible,does not return a Promise if fields are all synchronous,ported,test/execution/sync_test.dart,
execution/__tests__/sync-test.ts,Execute: synchronously when possible,does not return a Promise if mutation fields are all synchronous,ported,test/execution/sync_test.dart,
execution/__tests__/sync-test.ts,Execute: synchronously when possible,returns a Promise if any field is asynchronous,ported,test/execution/sync_test.dart,
execution/__tests__/sync-test.ts,Execute: synchronously when possible > executeSync,does not return a Promise for sync execution,ported,test/execution/sync_test.dart,
execution/__tests__/sync-test.ts,Execute: synchronously when possible > executeSync,throws if encountering async execution,adapted,test/execution/sync_test.dart,"There is no executeSync: execute returns a Future when a resolver waited, and the test checks that."
execution/__tests__/sync-test.ts,Execute: synchronously when possible > executeSync,throws if encountering async iterable execution,adapted,test/execution/sync_test.dart,"@defer runs inline in execute (spec 18.8), so the result is a non-Future with the whole data."
execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,report errors raised during schema validation,skipped,,"build rejects an invalid schema (SchemaBuildError) and requires a query root, so there is no schema to run."
execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,does not return a Promise for syntax errors,adapted,test/execution/sync_test.dart,"There is no graphqlSync before the request pipeline (M6): the port parses, validates and executes, and the syntax error is the parser diagnostic."
execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,does not return a Promise for validation errors,adapted,test/execution/sync_test.dart,The port compares with the diagnostics of DocumentValidator as errors with locations.
execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,does not return a Promise for sync execution,adapted,test/execution/sync_test.dart,"The port parses, validates and executes."
execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,throws if encountering async execution,skipped,,There is no graphqlSync: the port is asynchronous (the request pipeline is M6).
```

In `packages/typed_graphql_conformance/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,6 +8,7 @@ environment:
 
 dependencies:
   typed_graphql: any
+  typed_graphql_server: any
 
 dev_dependencies:
   test: ^1.31.0
```

In `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,6 +21,14 @@ final class FieldAccumulator {
     this.isDeferred = this.isDeferred && isDeferred;
   }
 
+  /// Whether the field exists on [parentType] (or is a meta field).
+  /// September2025 section 6.4 (Executing Fields) skips a field without a
+  /// definition, which only a document that was not validated can name.
+  bool isDefinedOn(ObjectType parentType) {
+    final name = _nodes.first.name.value;
+    return name.startsWith('__') || parentType.fieldNamed(name) != null;
+  }
+
   /// The plan of the key for [parentType].
   FieldPlan build(PlanContext context, ObjectType parentType) {
     final first = _nodes.first;
```

In `packages/typed_graphql_server/lib/src/plan/field_collector.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -41,7 +41,8 @@ final class FieldCollector {
       }
     }
     return PlanNode(runtimeType, [
-      for (final group in groups.values) group.build(context, runtimeType),
+      for (final group in groups.values)
+        if (group.isDefinedOn(runtimeType)) group.build(context, runtimeType),
     ]);
   }
 
```

Then run `dart pub get` at the repository root (`ulimit -v 8000000; timeout 300 dart pub get`).

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/executor_errors_test.dart test/execution/executor_operations_test.dart test/execution/executor_rest_test.dart test/execution/executor_test.dart test/execution/resolve_test.dart test/execution/schema_test.dart test/execution/sync_test.dart test/mapping_test.dart)
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/execute_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/pubspec.yaml packages/typed_graphql_conformance/test/execution/executor_errors_test.dart packages/typed_graphql_conformance/test/execution/executor_operations_test.dart packages/typed_graphql_conformance/test/execution/executor_rest_test.dart packages/typed_graphql_conformance/test/execution/executor_test.dart packages/typed_graphql_conformance/test/execution/resolve_test.dart packages/typed_graphql_conformance/test/execution/schema_test.dart packages/typed_graphql_conformance/test/execution/sync_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/execution_port.dart packages/typed_graphql_conformance/test/support/unchecked_ref.dart packages/typed_graphql_server/lib/src/plan/field_accumulator.dart packages/typed_graphql_server/lib/src/plan/field_collector.dart packages/typed_graphql_server/test/execution/execute_test.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js executor suites" \
  -m "Ports executor, resolve, sync and schema tests with an ExecutionPort and the execution mapping table. Server fix: the planner skips a field its object type does not define (spec 6.4) instead of reporting an error, with a server test." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Conformance: null propagation, lists and mutations

Port `nonnull-test.ts`, `lists-test.ts`, `errorPropagation-test.ts` and `mutations-test.ts`. The port found that an invalid argument value was located at the field; `CoercionProblem.node` now locates it at the value, as graphql-js does.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`, `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart`, `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`
- Test: `packages/typed_graphql_conformance/test/execution/error_propagation_test.dart`, `packages/typed_graphql_conformance/test/execution/lists_nullability_test.dart`, `packages/typed_graphql_conformance/test/execution/lists_test.dart`, `packages/typed_graphql_conformance/test/execution/mutations_test.dart`, `packages/typed_graphql_conformance/test/execution/nonnull_arguments_test.dart`, `packages/typed_graphql_conformance/test/execution/nonnull_multiple_test.dart`, `packages/typed_graphql_conformance/test/execution/nonnull_test.dart`, `packages/typed_graphql_conformance/test/support/list_field_schema.dart`, `packages/typed_graphql_conformance/test/support/non_null_schema.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_server/test/execution/error_reporting_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/execution/error_propagation_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/errorPropagation-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('foo', b.int).pure((_) => throw const GraphQLException('bar')),
      ],
    ),
  );

  group('Execute: handles errors', () {
    test(
      'with `@experimental_disableErrorPropagation returns null',
      () async {
        // The directive is not supported; ErrorBehavior.nullValue is the
        // same behaviour for the whole request.
        final result = await port.json(
          schema,
          '''

      query getFoo @experimental_disableErrorPropagation {
        foo
      }
    ''',
          options: const ExecutionOptions(
            errorBehavior: ErrorBehavior.nullValue,
            maskErrors: false,
          ),
        );

        expect(
          result,
          equals({
            'data': {'foo': null},
            'errors': [
              {
                'message': 'bar',
                'path': ['foo'],
                'locations': [
                  {'line': 3, 'column': 9},
                ],
              },
            ],
          }),
        );
      },
    );

    test(
      'without `experimental_disableErrorPropagation` propagates the error',
      () async {
        final result = await port.json(schema, '''

      query getFoo {
        foo
      }
    ''');

        expect(
          result,
          equals({
            'data': null,
            'errors': [
              {
                'message': 'bar',
                'path': ['foo'],
                'locations': [
                  {'line': 3, 'column': 9},
                ],
              },
            ],
          }),
        );
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/lists_nullability_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/list_field_schema.dart';

// Ported from graphql-js src/execution/__tests__/lists-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  const schemas = ListFieldSchema();
  const int_ = NamedType(Name('Int'));
  final types = {
    '[Int]': const ListType(int_),
    '[Int]!': const NonNullType(ListType(int_)),
    '[Int!]': const ListType(NonNullType(int_)),
    '[Int!]!': const NonNullType(ListType(NonNullType(int_))),
  };

  Map<String, Object?> error(String message, List<Object> path) => {
    'message': message,
    'locations': [
      {'line': 1, 'column': 3},
    ],
    'path': path,
  };

  Future<Map<String, Object?>> executeQuery(
    TypeRef type,
    FutureOr<Object?> Function() read,
  ) => port.json(schemas.build(type, read), '{ listField }');

  // The value as the resolver gives it, then in a future: both must give
  // the same response (graphql-js also wraps every item in a promise, which
  // a typed list cannot hold). A GraphQLException stands for the Error.
  Future<Map<String, Object?>> complete(Object? listField, String as) async {
    final type = types[as]!;
    final result = await executeQuery(type, () {
      if (listField is GraphQLException) {
        throw listField;
      }
      return listField;
    });
    final fromFuture = await executeQuery(
      type,
      () => listField is GraphQLException
          ? Future<Object?>.error(listField)
          : Future<Object?>.value(listField),
    );
    expect(fromFuture, equals(result));
    return result;
  }

  group('Execute: Handles list nullability', () {
    test('Contains values', () async {
      const listField = [1, 2];

      for (final as in types.keys) {
        expect(
          await complete(listField, as),
          equals({
            'data': {'listField': listField},
          }),
          reason: as,
        );
      }
    });

    test('Contains null', () async {
      const listField = [1, null, 2];
      final errors = [
        error('Cannot return null for non-nullable field Query.listField.', [
          'listField',
          1,
        ]),
      ];

      expect(
        await complete(listField, '[Int]'),
        equals({
          'data': {'listField': listField},
        }),
      );
      expect(
        await complete(listField, '[Int]!'),
        equals({
          'data': {'listField': listField},
        }),
      );
      expect(
        await complete(listField, '[Int!]'),
        equals({
          'data': {'listField': null},
          'errors': errors,
        }),
      );
      expect(
        await complete(listField, '[Int!]!'),
        equals({'data': null, 'errors': errors}),
      );
    });

    test('Returns null', () async {
      const Object? listField = null;
      final errors = [
        error('Cannot return null for non-nullable field Query.listField.', [
          'listField',
        ]),
      ];

      expect(
        await complete(listField, '[Int]'),
        equals({
          'data': {'listField': null},
        }),
      );
      expect(
        await complete(listField, '[Int]!'),
        equals({'data': null, 'errors': errors}),
      );
      expect(
        await complete(listField, '[Int!]'),
        equals({
          'data': {'listField': null},
        }),
      );
      expect(
        await complete(listField, '[Int!]!'),
        equals({'data': null, 'errors': errors}),
      );
    });

    test('Results in error', () async {
      const listField = GraphQLException('bad');
      final errors = [
        error('bad', ['listField']),
      ];

      expect(
        await complete(listField, '[Int]'),
        equals({
          'data': {'listField': null},
          'errors': errors,
        }),
      );
      expect(
        await complete(listField, '[Int]!'),
        equals({'data': null, 'errors': errors}),
      );
      expect(
        await complete(listField, '[Int!]'),
        equals({
          'data': {'listField': null},
          'errors': errors,
        }),
      );
      expect(
        await complete(listField, '[Int!]!'),
        equals({'data': null, 'errors': errors}),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/lists_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/list_field_schema.dart';
import '../support/unchecked_ref.dart';

// An iterable that counts how often its iterator is advanced, standing in for
// the hand-written JavaScript iterators of the graphql-js tests.
class _CountingIterable extends Iterable<Object?> {
  _CountingIterable(this._step);

  final ({bool isDone, Object? value}) Function(int call) _step;

  int calls = 0;

  @override
  Iterator<Object?> get iterator => _CountingIterator(this);
}

class _CountingIterator implements Iterator<Object?> {
  _CountingIterator(this._owner);

  final _CountingIterable _owner;

  Object? _current;

  @override
  Object? get current => _current;

  @override
  bool moveNext() {
    _owner.calls++;
    final step = _owner._step(_owner.calls);
    if (step.isDone) {
      return false;
    }
    _current = step.value;
    return true;
  }
}

class _Indexed {
  const _Indexed(this.index);

  final int index;
}

// Ported from graphql-js src/execution/__tests__/lists-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  const schemas = ListFieldSchema();
  const listOfString = ListType(NamedType(Name('String')));
  const listOfInt = ListType(NamedType(Name('Int')));
  const listOfNonNullInt = ListType(NonNullType(NamedType(Name('Int'))));
  const nullBubbled = {
    'message': 'Cannot return null for non-nullable field Query.listField.',
    'locations': [
      {'line': 1, 'column': 3},
    ],
    'path': ['listField', 1],
  };

  Map<String, Object?> badAtListField(String message) => {
    'data': {'listField': null},
    'errors': [
      {
        'message': message,
        'locations': [
          {'line': 1, 'column': 3},
        ],
        'path': ['listField'],
      },
    ],
  };

  Future<Map<String, Object?>> complete(
    Object? Function() read, {
    TypeRef type = listOfString,
    String scalarName = 'String',
  }) => port.json(
    schemas.build(type, read, scalarName: scalarName),
    '{ listField }',
  );

  Future<void> delayedReject(String message) async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    throw GraphQLException(message);
  }

  group('Execute: Accepts any iterable as list value', () {
    // graphql-js's executeSync: the response must not wait.
    Map<String, Object?> completeSync(Object? listField) {
      final result = port.payload<Object?>(
        schemas.build(listOfString, () => listField, scalarName: 'String'),
        '{ listField }',
        context: null,
      );
      expect(result, isNot(isA<Future<Object?>>()));
      return port.withoutCodes(result as ResponsePayload);
    }

    test('Accepts a Set as a List value', () {
      const items = ['apple', 'banana', 'apple', 'coconut'];
      final listField = {...items};

      expect(
        completeSync(listField),
        equals({
          'data': {
            'listField': ['apple', 'banana', 'coconut'],
          },
        }),
      );
    });

    test('Accepts a Generator function as a List value', () {
      Iterable<String> listField() sync* {
        yield 'one';
        yield '2';
        yield 'true';
      }

      expect(
        completeSync(listField()),
        equals({
          'data': {
            'listField': ['one', '2', 'true'],
          },
        }),
      );
    });

    test('Does not accept (Iterable) String-literal as a List value', () {
      expect(
        completeSync('Singular'),
        equals(
          badAtListField(
            'Expected Iterable, but did not find one for field '
            '"Query.listField".',
          ),
        ),
      );
    });

    test('Does not call iterator `return` when iteration throws', () {
      final listField = _CountingIterable(
        (call) => call == 1
            ? throw const GraphQLException('bad')
            : (isDone: true, value: null),
      );

      expect(completeSync(listField), equals(badAtListField('bad')));
      expect(listField.calls, 1);
    });
  });

  group('Execute: Handles abrupt completion in synchronous iterables', () {
    test('drains the iterator when `next` throws', () async {
      final listField = _CountingIterable(
        (call) => switch (call) {
          1 => (isDone: false, value: 'ok'),
          2 => throw const GraphQLException('bad'),
          _ => (isDone: true, value: null),
        },
      );

      expect(await complete(() => listField), equals(badAtListField('bad')));
      expect(listField.calls, 2);
    });

    test(
      'drains the iterator when a null bubbles up from a non-null item',
      () async {
        const values = [1, null, 2];
        final listField = _CountingIterable(
          (call) => call > values.length
              ? (isDone: true, value: null)
              : (isDone: false, value: values[call - 1]),
        );

        expect(
          await complete(
            () => listField,
            type: listOfNonNullInt,
            scalarName: 'Int',
          ),
          equals({
            'data': {'listField': null},
            'errors': [nullBubbled],
          }),
        );
        expect(listField.calls, 2);
      },
    );
  });

  group('Execute: Accepts async iterables as list value', () {
    Future<Map<String, Object?>> completeObjectList(
      FutureOr<String> Function(_Indexed item) resolve, {
      bool isNonNullable = false,
    }) {
      final b = ExecutableSchemaBuilder<Object?>();
      final wrapper = b.object<_Indexed>(
        'ObjectWrapper',
        fields: (t) => [
          t
              .field('index', b.string)
              .resolve((item, args, context, info) => resolve(item)),
        ],
      );
      const wrapperType = NamedType(Name('ObjectWrapper'));
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field(
                  'listField',
                  UncheckedRef(
                    ListType(
                      isNonNullable
                          ? const NonNullType(wrapperType)
                          : wrapperType,
                    ),
                    wrapper,
                  ),
                )
                .pure((_) => const [_Indexed(0), _Indexed(1), _Indexed(2)]),
          ],
        ),
      );
      return port.json(schema, '{ listField { index } }');
    }

    test('Handles promises from `completeValue` in AsyncIterables', () async {
      expect(
        await completeObjectList((item) => Future.value('${item.index}')),
        equals({
          'data': {
            'listField': [
              {'index': '0'},
              {'index': '1'},
              {'index': '2'},
            ],
          },
        }),
      );
    });

    test(
      'Handles rejected promises from `completeValue` in AsyncIterables',
      () async {
        expect(
          await completeObjectList((item) {
            if (item.index == 2) {
              return Future.error(const GraphQLException('bad'));
            }
            return Future.value('${item.index}');
          }),
          equals({
            'data': {
              'listField': [
                {'index': '0'},
                {'index': '1'},
                null,
              ],
            },
            'errors': [
              {
                'message': 'bad',
                'locations': [
                  {'line': 1, 'column': 15},
                ],
                'path': ['listField', 2, 'index'],
              },
            ],
          }),
        );
      },
    );

    test(
      'handles mixture of sync and async errors in AsyncIterables',
      () async {
        final uncaught = <Object>[];
        final result = await runZonedGuarded(
          () => completeObjectList((item) {
            if (item.index == 0) {
              return delayedReject('bad').then((_) => 'x');
            }
            throw const GraphQLException('also bad');
          }, isNonNullable: true),
          (error, stackTrace) => uncaught.add(error),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          result,
          equals({
            'data': {'listField': null},
            'errors': [
              {
                'message': 'also bad',
                'locations': [
                  {'line': 1, 'column': 15},
                ],
                'path': ['listField', 1, 'index'],
              },
              // The executor waits for the resolver that had started, so its
              // late error is in the response (graphql-js drops it).
              {
                'message': 'bad',
                'locations': [
                  {'line': 1, 'column': 15},
                ],
                'path': ['listField', 0, 'index'],
              },
            ],
          }),
        );
        expect(uncaught, isEmpty);
      },
    );

    test('Handles nulls yielded by async generator', () async {
      Iterable<int?> listField() sync* {
        yield 1;
        yield null;
        yield 2;
      }

      Future<Map<String, Object?>> run(TypeRef type) =>
          complete(listField, type: type, scalarName: 'Int');

      expect(
        await run(listOfInt),
        equals({
          'data': {
            'listField': [1, null, 2],
          },
        }),
      );
      expect(
        await run(const NonNullType(listOfInt)),
        equals({
          'data': {
            'listField': [1, null, 2],
          },
        }),
      );
      expect(
        await run(listOfNonNullInt),
        equals({
          'data': {'listField': null},
          'errors': [nullBubbled],
        }),
      );
      expect(
        await run(const NonNullType(listOfNonNullInt)),
        equals({
          'data': null,
          'errors': [nullBubbled],
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/mutations_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

class _NumberHolder {
  _NumberHolder(this.theNumber);

  int theNumber;
}

class _Root {
  _Root(int originalNumber) : numberHolder = _NumberHolder(originalNumber);

  final _NumberHolder numberHolder;

  _NumberHolder immediatelyChangeTheNumber(int? newNumber) {
    numberHolder.theNumber = newNumber!;
    return numberHolder;
  }

  Future<_NumberHolder> promiseToChangeTheNumber(int? newNumber) async {
    await Future<void>.delayed(Duration.zero);
    return immediatelyChangeTheNumber(newNumber);
  }

  _NumberHolder failToChangeTheNumber() =>
      throw const GraphQLException('Cannot change the number');

  Future<_NumberHolder> promiseAndFailToChangeTheNumber() async {
    await Future<void>.delayed(Duration.zero);
    throw const GraphQLException('Cannot change the number');
  }
}

// Ported from graphql-js src/execution/__tests__/mutations-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final newNumber = Arg('newNumber', b.int.nullable);
  final numberHolderType = b.object<_NumberHolder>(
    'NumberHolder',
    fields: (t) => [
      t.field('theNumber', b.int.nullable).pure((holder) => holder.theNumber),
      t.field('promiseToGetTheNumber', b.int.nullable).resolve((
        holder,
        args,
        context,
        info,
      ) async {
        await Future<void>.delayed(Duration.zero);
        return holder.theNumber;
      }),
    ],
  );
  final schema = b.build(
    query: b.object<_Root>(
      'Query',
      fields: (t) => [
        t
            .field('numberHolder', numberHolderType.nullable)
            .pure((root) => root.numberHolder),
      ],
    ),
    mutation: b.object<_Root>(
      'Mutation',
      fields: (t) => [
        t
            .field(
              'immediatelyChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) =>
                  root.immediatelyChangeTheNumber(args.get(newNumber)),
            ),
        t
            .field(
              'promiseToChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) =>
                  root.promiseToChangeTheNumber(args.get(newNumber)),
            ),
        t
            .field(
              'failToChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) => root.failToChangeTheNumber(),
            ),
        t
            .field(
              'promiseAndFailToChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) =>
                  root.promiseAndFailToChangeTheNumber(),
            ),
      ],
    ),
  );

  group('Execute: Handles mutation execution ordering', () {
    test('evaluates mutations serially', () async {
      final result = await port.json(
        schema,
        '''
      mutation M {
        first: immediatelyChangeTheNumber(newNumber: 1) {
          theNumber
        },
        second: promiseToChangeTheNumber(newNumber: 2) {
          theNumber
        },
        third: immediatelyChangeTheNumber(newNumber: 3) {
          theNumber
        }
        fourth: promiseToChangeTheNumber(newNumber: 4) {
          theNumber
        },
        fifth: immediatelyChangeTheNumber(newNumber: 5) {
          theNumber
        }
      }
    ''',
        options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
      );

      expect(
        result,
        equals({
          'data': {
            'first': {'theNumber': 1},
            'second': {'theNumber': 2},
            'third': {'theNumber': 3},
            'fourth': {'theNumber': 4},
            'fifth': {'theNumber': 5},
          },
        }),
      );
    });

    test('does not include illegal mutation fields in output', () {
      final result = port.payload<Object?>(
        schema,
        'mutation { thisIsIllegalDoNotIncludeMe }',
        context: null,
        options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
      );

      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({'data': <String, Object?>{}}),
      );
    });

    test(
      'evaluates mutations correctly in the presence of a failed mutation',
      () async {
        final result = await port.json(
          schema,
          '''

      mutation M {
        first: immediatelyChangeTheNumber(newNumber: 1) {
          theNumber
        },
        second: promiseToChangeTheNumber(newNumber: 2) {
          theNumber
        },
        third: failToChangeTheNumber(newNumber: 3) {
          theNumber
        }
        fourth: promiseToChangeTheNumber(newNumber: 4) {
          theNumber
        },
        fifth: immediatelyChangeTheNumber(newNumber: 5) {
          theNumber
        }
        sixth: promiseAndFailToChangeTheNumber(newNumber: 6) {
          theNumber
        }
      }
    ''',
          options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
        );

        expect(
          result,
          equals({
            'data': {
              'first': {'theNumber': 1},
              'second': {'theNumber': 2},
              'third': null,
              'fourth': {'theNumber': 4},
              'fifth': {'theNumber': 5},
              'sixth': null,
            },
            'errors': [
              {
                'message': 'Cannot change the number',
                'locations': [
                  {'line': 9, 'column': 9},
                ],
                'path': ['third'],
              },
              {
                'message': 'Cannot change the number',
                'locations': [
                  {'line': 18, 'column': 9},
                ],
                'path': ['sixth'],
              },
            ],
          }),
        );
      },
    );

    test('Mutation inside of a fragment', () async {
      final result = await port.json(
        schema,
        '''
      mutation M {
        ...MutationFragment
        second: immediatelyChangeTheNumber(newNumber: 2) {
          theNumber
        }
      }
      fragment MutationFragment on Mutation {
        first: promiseToChangeTheNumber(newNumber: 1) {
          theNumber
        },
      }
    ''',
        options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
      );

      expect(
        result,
        equals({
          'data': {
            'first': {'theNumber': 1},
            'second': {'theNumber': 2},
          },
        }),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/nonnull_arguments_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/nonnull-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  group('Execute: handles non-nullable types', () {
    group('Handles non-null argument', () {
      final b = ExecutableSchemaBuilder<Object?>();
      final cannotBeNull = Arg('cannotBeNull', b.string);
      final schemaWithNonNullArg = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field(
                  'withNonNullArg',
                  b.string.nullable,
                  args: [cannotBeNull],
                )
                .resolve(
                  (_, args, context, info) =>
                      'Passed: ${args.get(cannotBeNull)}',
                ),
          ],
        ),
      );

      Future<Map<String, Object?>> run(
        String query, {
        JsonObject? variables,
      }) => port.json(schemaWithNonNullArg, query, variables: variables);

      Map<String, Object?> fieldError(String message, int line, int column) => {
        'data': {'withNonNullArg': null},
        'errors': [
          {
            'message': message,
            'locations': [
              {'line': line, 'column': column},
            ],
            'path': ['withNonNullArg'],
          },
        ],
      };

      test('succeeds when passed non-null literal value', () async {
        final result = await run('''

          query {
            withNonNullArg (cannotBeNull: "literal value")
          }
        ''');

        expect(
          result,
          equals({
            'data': {'withNonNullArg': 'Passed: literal value'},
          }),
        );
      });

      test('succeeds when passed non-null variable value', () async {
        final result = await run(
          r'''

          query ($testVar: String!) {
            withNonNullArg (cannotBeNull: $testVar)
          }
        ''',
          variables: JsonObject({
            'testVar': const JsonString('variable value'),
          }),
        );

        expect(
          result,
          equals({
            'data': {'withNonNullArg': 'Passed: variable value'},
          }),
        );
      });

      test('succeeds when missing variable has default value', () async {
        final result = await run(
          r'''

          query ($testVar: String = "default value") {
            withNonNullArg (cannotBeNull: $testVar)
          }
        ''',
          variables: JsonObject({}),
        );

        expect(
          result,
          equals({
            'data': {'withNonNullArg': 'Passed: default value'},
          }),
        );
      });

      test('field error when missing non-null arg', () async {
        // Validation should identify this issue first (missing args rule)
        // however execution should still protect against this.
        final result = await run('''

          query {
            withNonNullArg
          }
        ''');

        expect(
          result,
          equals(
            fieldError(
              'Argument "Query.withNonNullArg(cannotBeNull:)" of required '
              'type "String!" was not provided.',
              3,
              13,
            ),
          ),
        );
      });

      test('field error when non-null arg provided null', () async {
        // Validation should identify this issue first (values of correct
        // type rule) however execution should still protect against this.
        final result = await run('''

          query {
            withNonNullArg(cannotBeNull: null)
          }
        ''');

        expect(
          result,
          equals(
            fieldError(
              'Argument "Query.withNonNullArg(cannotBeNull:)" has invalid '
              'value: Expected value of non-null type "String!" not to be '
              'null.',
              3,
              42,
            ),
          ),
        );
      });

      test(
        'field error when non-null arg not provided variable value',
        () async {
          // Validation should identify this issue first (variables in allowed
          // position rule) however execution should still protect against this.
          final result = await run(
            r'''

          query ($testVar: String) {
            withNonNullArg(cannotBeNull: $testVar)
          }
        ''',
            variables: JsonObject({}),
          );

          expect(
            result,
            equals(
              fieldError(
                'Argument "Query.withNonNullArg(cannotBeNull:)" has invalid '
                r'value: Expected variable "$testVar" provided to type '
                '"String!" to provide a runtime value.',
                3,
                42,
              ),
            ),
          );
        },
      );

      test(
        'field error when non-null arg provided variable with explicit null value',
        () async {
          final result = await run(
            r'''

          query ($testVar: String = "default value") {
            withNonNullArg (cannotBeNull: $testVar)
          }
        ''',
            variables: JsonObject({'testVar': const JsonNull()}),
          );

          expect(
            result,
            equals(
              fieldError(
                'Argument "Query.withNonNullArg(cannotBeNull:)" has invalid '
                r'value: Expected variable "$testVar" provided to non-null '
                'type "String!" not to be null.',
                3,
                43,
              ),
            ),
          );
        },
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/nonnull_multiple_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/non_null_schema.dart';

// Ported from graphql-js src/execution/__tests__/nonnull-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final schema = const NonNullSchema().build();
  const throwingData = NonNullData(isThrowing: true);

  Map<String, Object?> error(
    String message,
    List<Object> path,
    int line,
    int column,
  ) => {
    'message': message,
    'path': path,
    'locations': [
      {'line': line, 'column': column},
    ],
  };

  Future<Map<String, Object?>> executeQuery(
    String query,
    NonNullData data,
  ) => port.json(schema, query, options: ExecutionOptions(rootValue: data));

  group('Execute: handles non-nullable types', () {
    group('Handles multiple errors for a single response position', () {
      test(
        'nullable and non-nullable root fields throw nested errors',
        () async {
          final result = await executeQuery('''

        {
          promiseNonNullNest {
            syncNonNull
          }
          promiseNest {
            syncNonNull
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': null,
              'errors': [
                error(
                  'syncNonNull',
                  ['promiseNonNullNest', 'syncNonNull'],
                  4,
                  13,
                ),
                error('syncNonNull', ['promiseNest', 'syncNonNull'], 7, 13),
              ],
            }),
          );
        },
      );

      test(
        'a nullable root field throws a slower nested error after a non-nullable root field throws a nested error',
        () async {
          final result = await executeQuery('''

        {
          promiseNonNullNest {
            syncNonNull
          }
          promiseNest {
            promiseNonNull
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': null,
              'errors': [
                error(
                  'syncNonNull',
                  ['promiseNonNullNest', 'syncNonNull'],
                  4,
                  13,
                ),
                error(
                  'promiseNonNull',
                  ['promiseNest', 'promiseNonNull'],
                  7,
                  13,
                ),
              ],
            }),
          );
        },
      );

      test(
        'nullable and non-nullable nested fields throw nested errors',
        () async {
          final result = await executeQuery('''

        {
          syncNest {
            promiseNonNullNest {
              syncNonNull
            }
            promiseNest {
              syncNonNull
            }
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': {'syncNest': null},
              'errors': [
                error(
                  'syncNonNull',
                  ['syncNest', 'promiseNonNullNest', 'syncNonNull'],
                  5,
                  15,
                ),
                error(
                  'syncNonNull',
                  ['syncNest', 'promiseNest', 'syncNonNull'],
                  8,
                  15,
                ),
              ],
            }),
          );
        },
      );

      test(
        'a nullable nested field throws a slower nested error after a non-nullable nested field throws a nested error',
        () async {
          final result = await executeQuery('''

        {
          syncNest {
            promiseNonNullNest {
              syncNonNull
            }
            promiseNest {
              promiseNest {
                promiseNest {
                  promiseNonNull
                }
              }
            }
          }
        }
      ''', throwingData);

          expect(
            result,
            equals({
              'data': {'syncNest': null},
              'errors': [
                error(
                  'syncNonNull',
                  ['syncNest', 'promiseNonNullNest', 'syncNonNull'],
                  5,
                  15,
                ),
                error(
                  'promiseNonNull',
                  [
                    'syncNest',
                    'promiseNest',
                    'promiseNest',
                    'promiseNest',
                    'promiseNonNull',
                  ],
                  10,
                  19,
                ),
              ],
            }),
          );
        },
      );

      test('suppresses a later error after a parent has been nulled', () async {
        final nonNullDeferred = Completer<Object?>();
        final promiseDeferred = Completer<String?>();
        final data = NonNullData(
          isThrowing: false,
          syncNonNullOverride: () => nonNullDeferred.future,
          promiseOverride: () => promiseDeferred.future,
        );

        final resultPromise = executeQuery('''

        {
          syncNest {
            syncNonNull
            promise
          }
        }
      ''', data);

        nonNullDeferred.completeError(const GraphQLException('syncNonNull'));

        // Give the first error a chance to null out the parent position.
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        promiseDeferred.completeError(const GraphQLException('promise'));

        expect(
          await resultPromise,
          equals({
            'data': {'syncNest': null},
            'errors': [
              error('syncNonNull', ['syncNest', 'syncNonNull'], 4, 13),
              error('promise', ['syncNest', 'promise'], 5, 13),
            ],
          }),
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/nonnull_test.dart`:

```dart
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/non_null_schema.dart';

// Ported from graphql-js src/execution/__tests__/nonnull-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final schema = const NonNullSchema().build();
  const nullingData = NonNullData(isThrowing: false);
  const throwingData = NonNullData(isThrowing: true);

  Map<String, Object?> error(
    String message,
    List<Object> path,
    int line,
    int column,
  ) => {
    'message': message,
    'path': path,
    'locations': [
      {'line': line, 'column': column},
    ],
  };

  String patch(String text) => text
      .replaceAll(RegExp(r'\bsync\b'), 'promise')
      .replaceAll(RegExp(r'\bsyncNonNull\b'), 'promiseNonNull');

  Future<Map<String, Object?>> executeQuery(String query, NonNullData data) =>
      port.json(schema, query, options: ExecutionOptions(rootValue: data));

  // graphql-js's executeSync: the first run must not wait; the second run,
  // with every sync leaf as a promise, must give the same response.
  Future<Map<String, Object?>> executeSyncAndAsync(
    String query,
    NonNullData data,
  ) async {
    final syncResult = port.payload<Object?>(
      schema,
      query,
      context: null,
      options: ExecutionOptions(rootValue: data, maskErrors: false),
    );
    expect(syncResult, isA<ResponsePayload>());
    final syncJson = port.withoutCodes(syncResult as ResponsePayload);
    final asyncResult = await executeQuery(patch(query), data);
    expect(asyncResult, equals(jsonDecode(patch(jsonEncode(syncJson)))));
    return syncJson;
  }

  group('Execute: handles non-nullable types', () {
    group('nulls a nullable field', () {
      const query = '''

      {
        sync
      }
    ''';

      test('that returns null', () async {
        final result = await executeSyncAndAsync(query, nullingData);
        expect(
          result,
          equals({
            'data': {'sync': null},
          }),
        );
      });

      test('that throws', () async {
        final result = await executeSyncAndAsync(query, throwingData);
        expect(
          result,
          equals({
            'data': {'sync': null},
            'errors': [
              error('sync', ['sync'], 3, 9),
            ],
          }),
        );
      });
    });

    group('nulls a returned object that contains a non-nullable field', () {
      const query = '''

      {
        syncNest {
          syncNonNull,
        }
      }
    ''';

      test('that returns null', () async {
        final result = await executeSyncAndAsync(query, nullingData);
        expect(
          result,
          equals({
            'data': {'syncNest': null},
            'errors': [
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                ['syncNest', 'syncNonNull'],
                4,
                11,
              ),
            ],
          }),
        );
      });

      test('that throws', () async {
        final result = await executeSyncAndAsync(query, throwingData);
        expect(
          result,
          equals({
            'data': {'syncNest': null},
            'errors': [
              error('syncNonNull', ['syncNest', 'syncNonNull'], 4, 11),
            ],
          }),
        );
      });
    });

    group('nulls a complex tree of nullable fields, each', () {
      const query = '''

      {
        syncNest {
          sync
          promise
          syncNest { sync promise }
          promiseNest { sync promise }
        }
        promiseNest {
          sync
          promise
          syncNest { sync promise }
          promiseNest { sync promise }
        }
      }
    ''';
      const leaves = {'sync': null, 'promise': null};
      const nest = {
        'sync': null,
        'promise': null,
        'syncNest': leaves,
        'promiseNest': leaves,
      };
      const data = {'syncNest': nest, 'promiseNest': nest};

      test('that returns null', () async {
        final result = await executeQuery(query, nullingData);
        expect(result, equals({'data': data}));
      });

      test('that throws', () async {
        final result = await executeQuery(query, throwingData);
        expect(
          result,
          equals({
            'data': data,
            'errors': [
              error('sync', ['syncNest', 'sync'], 4, 11),
              error('sync', ['syncNest', 'syncNest', 'sync'], 6, 22),
              error('promise', ['syncNest', 'promise'], 5, 11),
              error('promise', ['syncNest', 'syncNest', 'promise'], 6, 27),
              error('sync', ['syncNest', 'promiseNest', 'sync'], 7, 25),
              error('sync', ['promiseNest', 'sync'], 10, 11),
              error('sync', ['promiseNest', 'syncNest', 'sync'], 12, 22),
              error('promise', ['syncNest', 'promiseNest', 'promise'], 7, 30),
              error('promise', ['promiseNest', 'promise'], 11, 11),
              error('promise', ['promiseNest', 'syncNest', 'promise'], 12, 27),
              error('sync', ['promiseNest', 'promiseNest', 'sync'], 13, 25),
              error(
                'promise',
                ['promiseNest', 'promiseNest', 'promise'],
                13,
                30,
              ),
            ],
          }),
        );
      });
    });

    group('nulls the first nullable object after a field in a long chain of non-null fields', () {
      const query = '''

      {
        syncNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  syncNonNull
                }
              }
            }
          }
        }
        promiseNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  syncNonNull
                }
              }
            }
          }
        }
        anotherNest: syncNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  promiseNonNull
                }
              }
            }
          }
        }
        anotherPromiseNest: promiseNest {
          syncNonNullNest {
            promiseNonNullNest {
              syncNonNullNest {
                promiseNonNullNest {
                  promiseNonNull
                }
              }
            }
          }
        }
      }
    ''';
      const data = {
        'syncNest': null,
        'promiseNest': null,
        'anotherNest': null,
        'anotherPromiseNest': null,
      };

      List<Object> chain(String root, String leaf) => [
        root,
        'syncNonNullNest',
        'promiseNonNullNest',
        'syncNonNullNest',
        'promiseNonNullNest',
        leaf,
      ];

      test('that returns null', () async {
        final result = await executeQuery(query, nullingData);
        expect(
          result,
          equals({
            'data': data,
            'errors': [
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                chain('syncNest', 'syncNonNull'),
                8,
                19,
              ),
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                chain('promiseNest', 'syncNonNull'),
                19,
                19,
              ),
              error(
                'Cannot return null for non-nullable field '
                'DataType.promiseNonNull.',
                chain('anotherNest', 'promiseNonNull'),
                30,
                19,
              ),
              error(
                'Cannot return null for non-nullable field '
                'DataType.promiseNonNull.',
                chain('anotherPromiseNest', 'promiseNonNull'),
                41,
                19,
              ),
            ],
          }),
        );
      });

      test('that throws', () async {
        final result = await executeQuery(query, throwingData);
        expect(
          result,
          equals({
            'data': data,
            'errors': [
              error('syncNonNull', chain('syncNest', 'syncNonNull'), 8, 19),
              error('syncNonNull', chain('promiseNest', 'syncNonNull'), 19, 19),
              error(
                'promiseNonNull',
                chain('anotherNest', 'promiseNonNull'),
                30,
                19,
              ),
              error(
                'promiseNonNull',
                chain('anotherPromiseNest', 'promiseNonNull'),
                41,
                19,
              ),
            ],
          }),
        );
      });
    });

    group('nulls the top level if non-nullable field', () {
      const query = '''

      {
        syncNonNull
      }
    ''';

      test('that returns null', () async {
        final result = await executeSyncAndAsync(query, nullingData);
        expect(
          result,
          equals({
            'data': null,
            'errors': [
              error(
                'Cannot return null for non-nullable field '
                'DataType.syncNonNull.',
                ['syncNonNull'],
                3,
                9,
              ),
            ],
          }),
        );
      });

      test('that throws', () async {
        final result = await executeSyncAndAsync(query, throwingData);
        expect(
          result,
          equals({
            'data': null,
            'errors': [
              error('syncNonNull', ['syncNonNull'], 3, 9),
            ],
          }),
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/support/list_field_schema.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'unchecked_ref.dart';

/// graphql-js's `buildSchema('type Query { listField: <as> }')` of the list
/// tests: one field whose GraphQL type is [type] and whose Dart value is
/// whatever [read] returns, since a typed resolver could not return the
/// values those tests use.
final class ListFieldSchema {
  /// Creates the builder of the schema; it keeps no state.
  const ListFieldSchema();

  /// The schema with `listField` of type [type] over the scalar named
  /// [scalarName] (`Int` or `String`).
  ExecutableSchema<Object?> build(
    TypeRef type,
    FutureOr<Object?> Function() read, {
    String scalarName = 'Int',
  }) {
    final b = ExecutableSchemaBuilder<Object?>();
    final scalar = scalarName == 'Int' ? b.int : b.string;
    return b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('listField', UncheckedRef(type, scalar))
              .resolve((_, args, context, info) => read()),
        ],
      ),
    );
  }
}
```

Create `packages/typed_graphql_conformance/test/support/non_null_schema.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'unchecked_ref.dart';

/// graphql-js's `throwingData` and `nullingData` of `nonnull-test.ts`: an
/// object whose fields return `null` or throw, each one sync or in a
/// future, and whose nested fields return the object itself.
final class NonNullData {
  /// Data whose leaf fields throw when [isThrowing], else return `null`.
  ///
  /// [syncNonNullOverride] and [promiseOverride] replace the answers of the
  /// `syncNonNull` and `promise` leaves.
  const NonNullData({
    required this.isThrowing,
    this.syncNonNullOverride,
    this.promiseOverride,
  });

  /// Whether a leaf throws instead of returning `null`.
  final bool isThrowing;

  /// The answer of `syncNonNull`, when the test controls it.
  final Future<Object?> Function()? syncNonNullOverride;

  /// The answer of `promise`, when the test controls it.
  final Future<String?> Function()? promiseOverride;

  /// The `sync` field.
  String? sync() => isThrowing ? throw const GraphQLException('sync') : null;

  /// The `syncNonNull` field.
  FutureOr<Object?> syncNonNull() {
    if (syncNonNullOverride case final override?) {
      return override();
    }
    return isThrowing ? throw const GraphQLException('syncNonNull') : null;
  }

  /// The `promise` field.
  Future<String?> promise() {
    if (promiseOverride case final override?) {
      return override();
    }
    return isThrowing
        ? Future<String?>.error(const GraphQLException('promise'))
        : Future<String?>.value();
  }

  /// The `promiseNonNull` field.
  Future<Object?> promiseNonNull() => isThrowing
      ? Future<Object?>.error(const GraphQLException('promiseNonNull'))
      : Future<Object?>.value();

  /// The `promiseNest` field.
  Future<NonNullData> asFuture() => Future.value(this);
}

/// The schema of `nonnull-test.ts`: `DataType` is the query type.
final class NonNullSchema {
  /// Creates the builder of the schema; it keeps no state.
  const NonNullSchema();

  /// The schema.
  ExecutableSchema<Object?> build() {
    final b = ExecutableSchemaBuilder<Object?>();
    final nonNullString = UncheckedRef(
      const NonNullType(NamedType(Name('String'))),
      b.string,
    );
    // The fields refer to their own type; the thunk runs after the
    // assignment.
    late final ObjectTypeDef<NonNullData> dataType;
    dataType = b.object<NonNullData>(
      'DataType',
      fields: (t) => [
        t.field('sync', b.string.nullable).pure((data) => data.sync()),
        t
            .field('syncNonNull', nonNullString)
            .resolve((data, args, context, info) => data.syncNonNull()),
        t
            .field('promise', b.string.nullable)
            .resolve((data, args, context, info) => data.promise()),
        t
            .field('promiseNonNull', nonNullString)
            .resolve((data, args, context, info) => data.promiseNonNull()),
        t.field('syncNest', dataType.nullable).pure((data) => data),
        t.field('syncNonNullNest', dataType).pure((data) => data),
        t
            .field('promiseNest', dataType.nullable)
            .resolve((data, args, context, info) => data.asFuture()),
        t
            .field('promiseNonNullNest', dataType)
            .resolve((data, args, context, info) => data.asFuture()),
      ],
    );
    return b.build(query: dataType);
  }
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -94,7 +94,11 @@ void main() {
       path: 'mapping/execution.csv',
       prefix: '',
       covered: const [
+        'execution/__tests__/errorPropagation-test.ts',
         'execution/__tests__/executor-test.ts',
+        'execution/__tests__/lists-test.ts',
+        'execution/__tests__/mutations-test.ts',
+        'execution/__tests__/nonnull-test.ts',
         'execution/__tests__/resolve-test.ts',
         'execution/__tests__/schema-test.ts',
         'execution/__tests__/sync-test.ts',
```

In `packages/typed_graphql_server/test/execution/error_reporting_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -136,6 +136,17 @@ void main() {
       ]);
     });
 
+    test('of an invalid argument value are those of the value', () async {
+      const text = '{\n  greet(name: null)\n}';
+      final json = await f.json(
+        text,
+        options: ExecutionOptions(source: Source(text)),
+      );
+      expect((errorsOf(json).single! as Map<String, Object?>)['locations'], [
+        {'line': 2, 'column': 15},
+      ]);
+    });
+
     test('are absent without the source', () async {
       final json = await f.json('{ fail }');
       expect(
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -51,3 +51,57 @@ execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlS
 execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,does not return a Promise for validation errors,adapted,test/execution/sync_test.dart,The port compares with the diagnostics of DocumentValidator as errors with locations.
 execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,does not return a Promise for sync execution,adapted,test/execution/sync_test.dart,"The port parses, validates and executes."
 execution/__tests__/sync-test.ts,Execute: synchronously when possible > graphqlSync,throws if encountering async execution,skipped,,There is no graphqlSync: the port is asynchronous (the request pipeline is M6).
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls a nullable field,that returns null,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls a nullable field,that throws,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls a returned object that contains a non-nullable field,that returns null,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls a returned object that contains a non-nullable field,that throws,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,"Execute: handles non-nullable types > nulls a complex tree of nullable fields, each",that returns null,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,"Execute: handles non-nullable types > nulls a complex tree of nullable fields, each",that throws,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the first nullable object after a field in a long chain of non-null fields,that returns null,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the first nullable object after a field in a long chain of non-null fields,that throws,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the top level if non-nullable field,that returns null,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the top level if non-nullable field,that throws,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles multiple errors for a single response position,nullable and non-nullable root fields throw nested errors,adapted,test/execution/nonnull_multiple_test.dart,Both errors are in the response in document order; graphql-js orders them by completion time.
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles multiple errors for a single response position,a nullable root field throws a slower nested error after a non-nullable root field throws a nested error,adapted,test/execution/nonnull_multiple_test.dart,"The executor waits for the resolvers that already started before it answers, so the late error of the nullable branch is in the response (graphql-js answers first and drops it)."
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles multiple errors for a single response position,nullable and non-nullable nested fields throw nested errors,adapted,test/execution/nonnull_multiple_test.dart,Both errors are in the response in document order; graphql-js orders them by completion time.
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles multiple errors for a single response position,a nullable nested field throws a slower nested error after a non-nullable nested field throws a nested error,adapted,test/execution/nonnull_multiple_test.dart,"The executor waits for the resolvers that already started before it answers, so the late error of the nullable branch is in the response (graphql-js answers first and drops it)."
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles multiple errors for a single response position,suppresses a later error after a parent has been nulled,adapted,test/execution/nonnull_multiple_test.dart,"The executor waits for the resolvers that already started before it answers, so the late error of the nullable branch is in the response (graphql-js answers first and drops it)."
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,succeeds when passed non-null literal value,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,succeeds when passed non-null variable value,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,succeeds when missing variable has default value,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,field error when missing non-null arg,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,field error when non-null arg provided null,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,field error when non-null arg not provided variable value,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > Handles non-null argument,field error when non-null arg provided variable with explicit null value,ported,test/execution/nonnull_arguments_test.dart,
+execution/__tests__/lists-test.ts,Execute: Accepts any iterable as list value,Accepts a Set as a List value,ported,test/execution/lists_test.dart,
+execution/__tests__/lists-test.ts,Execute: Accepts any iterable as list value,Accepts a Generator function as a List value,adapted,test/execution/lists_test.dart,Items are Strings: graphql-js coerces the number and the boolean the generator yields to strings.
+execution/__tests__/lists-test.ts,Execute: Accepts any iterable as list value,Accepts function arguments as a List value,skipped,,JavaScript-only: the arguments object is an array-like iterable.
+execution/__tests__/lists-test.ts,Execute: Accepts any iterable as list value,Does not accept (Iterable) String-literal as a List value,ported,test/execution/lists_test.dart,
+execution/__tests__/lists-test.ts,Execute: Accepts any iterable as list value,Does not call iterator `return` when iteration throws,adapted,test/execution/lists_test.dart,Dart has no iterator return/drain protocol: completion stops at the first failure and the iterator is not advanced further; the response is the same.
+execution/__tests__/lists-test.ts,Execute: Handles abrupt completion in synchronous iterables,drains the iterator when `next` throws,adapted,test/execution/lists_test.dart,Dart has no iterator return/drain protocol: completion stops at the first failure and the iterator is not advanced further; the response is the same.
+execution/__tests__/lists-test.ts,Execute: Handles abrupt completion in synchronous iterables,drains the iterator when a null bubbles up from a non-null item,adapted,test/execution/lists_test.dart,A null at a non-null item ends completion: the rest of the iterable is not drained (graphql-js reads it to the end); the response is the same.
+execution/__tests__/lists-test.ts,Execute: Handles abrupt completion in synchronous iterables,handles iterator errors with later pending promises without calling `return`,skipped,,"Items cannot be futures in a typed list (Iterable of the item type), and a Dart iterator has no return/drain protocol, so there is no pending promise left unhandled."
+execution/__tests__/lists-test.ts,Execute: Handles abrupt completion in synchronous iterables,handles sync errors with later pending promises without calling `return`,skipped,,"Items cannot be futures in a typed list (Iterable of the item type), and a Dart iterator has no return/drain protocol, so there is no pending promise left unhandled."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Accepts an AsyncGenerator function as a List value,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles an AsyncGenerator function that throws,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles an AsyncGenerator function where an intermediate value triggers an error,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles errors from `completeValue` in AsyncIterables,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles promises from `completeValue` in AsyncIterables,adapted,test/execution/lists_test.dart,The list is a sync Iterable of objects (async iterables are not list values) and the String field returns the index as text (no number-to-string coercion).
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles rejected promises from `completeValue` in AsyncIterables,adapted,test/execution/lists_test.dart,The list is a sync Iterable of objects (async iterables are not list values) and the String field returns the index as text (no number-to-string coercion).
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,handles mixture of sync and async errors in AsyncIterables,adapted,test/execution/lists_test.dart,"The list is a sync Iterable of objects, the index is returned as text, and the late error of the first item is in the response (the executor waits for started resolvers)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles nulls yielded by async generator,adapted,test/execution/lists_test.dart,"The values come from a sync Iterable generator, not an async one."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Returns async iterable when list nulls,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Ignores error on return method when async iterator nulls,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
+execution/__tests__/lists-test.ts,Execute: Handles list nullability,Contains values,adapted,test/execution/lists_nullability_test.dart,"A typed list holds values, not futures or errors: the variants that wrap each item in a promise are dropped (item errors are covered by the object list tests); the plain and the future-of-list forms are compared."
+execution/__tests__/lists-test.ts,Execute: Handles list nullability,Contains null,adapted,test/execution/lists_nullability_test.dart,"A typed list holds values, not futures or errors: the variants that wrap each item in a promise are dropped (item errors are covered by the object list tests); the plain and the future-of-list forms are compared."
+execution/__tests__/lists-test.ts,Execute: Handles list nullability,Returns null,adapted,test/execution/lists_nullability_test.dart,"A typed list holds values, not futures or errors: the variants that wrap each item in a promise are dropped (item errors are covered by the object list tests); the plain and the future-of-list forms are compared."
+execution/__tests__/lists-test.ts,Execute: Handles list nullability,Contains error,skipped,,"A list item cannot be a returned Error or a future in a typed list; a failing item is covered by the object list tests (""Handles rejected promises"")."
+execution/__tests__/lists-test.ts,Execute: Handles list nullability,Results in error,adapted,test/execution/lists_nullability_test.dart,"A typed list holds values, not futures or errors: the variants that wrap each item in a promise are dropped (item errors are covered by the object list tests); the plain and the future-of-list forms are compared."
+execution/__tests__/errorPropagation-test.ts,Execute: handles errors,with `@experimental_disableErrorPropagation returns null,adapted,test/execution/error_propagation_test.dart,The directive is not supported; ErrorBehavior.nullValue gives the same result for the whole request.
+execution/__tests__/errorPropagation-test.ts,Execute: handles errors,without `experimental_disableErrorPropagation` propagates the error,ported,test/execution/error_propagation_test.dart,
+execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,evaluates mutations serially,ported,test/execution/mutations_test.dart,
+execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,does not include illegal mutation fields in output,ported,test/execution/mutations_test.dart,
+execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,evaluates mutations correctly in the presence of a failed mutation,ported,test/execution/mutations_test.dart,
+execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,Mutation fields with @defer do not block next mutation,skipped,,Incremental delivery of @defer patches is executeIncrementally (M14); execute runs @defer inline.
+execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,Mutation inside of a fragment,ported,test/execution/mutations_test.dart,
+execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,Mutation with @defer is not executed serially,skipped,,Incremental delivery of @defer patches is executeIncrementally (M14); execute runs @defer inline.
```

In `packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -122,6 +122,7 @@ final class ArgumentCoercion {
       return _problem(
         '$subject has invalid value',
         problem: problems.kept.first,
+        node: written,
       );
     }
     values[definition.name] = coerced;
@@ -129,7 +130,11 @@ final class ArgumentCoercion {
   }
 
   // Words `[lead][where]: [message]` of a cause, or a plain message.
-  CoercionProblem _problem(String lead, {CoercionProblem? problem}) {
+  CoercionProblem _problem(
+    String lead, {
+    CoercionProblem? problem,
+    Node? node,
+  }) {
     if (problem == null) {
       return CoercionProblem(
         lead,
@@ -143,6 +148,7 @@ final class ArgumentCoercion {
       code: problem.code ?? DiagnosticCode.invalidArgumentValue,
       extensions: problem.extensions,
       thrown: problem.thrown,
+      node: node,
     );
   }
 }
```

In `packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -18,6 +18,10 @@ final class CoercionProblem(
   /// The error user code threw and its stack trace, which the caller
   /// reports to `onError`; null when the problem is not about a throw.
   final ({Object error, StackTrace stackTrace})? thrown,
+
+  /// The value node an argument problem points at, as graphql-js locates
+  /// it; null when the problem is about the field.
+  final Node? node,
 }) {
   /// Describes a problem.
   this;
```

In `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -37,7 +37,10 @@ final class ErrorReporter {
     final code = problem.code ?? DiagnosticCode.invalidArgumentValue;
     final reported = GraphQLError(
       '${problem.message}${problem.where}',
-      locations: _locations(nodes),
+      locations: switch (problem.node) {
+        final node? => _locations([node]),
+        null => _locations(nodes),
+      },
       path: path?.toList(),
       extensions: problem.extensions ?? _codeOf(code),
     );
@@ -116,7 +119,7 @@ final class ErrorReporter {
   JsonObject _codeOf(DiagnosticCode code) =>
       JsonObject({'code': JsonString(code.id)});
 
-  List<SourceLocation> _locations(List<Field> nodes) {
+  List<SourceLocation> _locations(List<Node> nodes) {
     final source = options.source;
     if (source == null) {
       return const [];
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/error_propagation_test.dart test/execution/lists_nullability_test.dart test/execution/lists_test.dart test/execution/mutations_test.dart test/execution/nonnull_arguments_test.dart test/execution/nonnull_multiple_test.dart test/execution/nonnull_test.dart test/mapping_test.dart)
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/error_reporting_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/error_propagation_test.dart packages/typed_graphql_conformance/test/execution/lists_nullability_test.dart packages/typed_graphql_conformance/test/execution/lists_test.dart packages/typed_graphql_conformance/test/execution/mutations_test.dart packages/typed_graphql_conformance/test/execution/nonnull_arguments_test.dart packages/typed_graphql_conformance/test/execution/nonnull_multiple_test.dart packages/typed_graphql_conformance/test/execution/nonnull_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/list_field_schema.dart packages/typed_graphql_conformance/test/support/non_null_schema.dart packages/typed_graphql_server/lib/src/coercion/argument_coercion.dart packages/typed_graphql_server/lib/src/coercion/coercion_problem.dart packages/typed_graphql_server/lib/src/execution/error_reporter.dart packages/typed_graphql_server/test/execution/error_reporting_test.dart
git commit -q -m "test(typed_graphql_conformance): port the null, list and mutation suites" \
  -m "Ports nonnull, lists, errorPropagation and mutations with the mapping rows. Server fix: an invalid argument value is located at the value node, as graphql-js does, with a server test." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: graphql-js `inspect` in scalar messages (core)

Add the core's `JsonInspector` and use it in the five built-in scalar codecs' messages, so a list or object prints as graphql-js prints it (`[1, 2, 3]`, `{ a: 1 }`).

**Files:**
- Create: `packages/typed_graphql/lib/src/protocol/json_inspector.dart`
- Modify: `packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/float_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/id_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/int_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/string_codec.dart`, `packages/typed_graphql/CHANGELOG.md`
- Test: `packages/typed_graphql/test/protocol/json_inspector_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// protocol/json_inspector.dart
final class const JsonInspector()
  String inspect(JsonValue value)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/protocol/json_inspector_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/protocol/json_inspector.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const inspector = JsonInspector();

  JsonValue json(String text) => switch (const JsonReader().parse(text)) {
    DecodeSuccess(:final value) => value,
    final DecodeFailure failure => fail('$failure'),
  };

  test('quotes a string as JSON', () {
    expect(inspector.inspect(json(r'"a\"b\n"')), r'"a\"b\n"');
  });

  test('prints a list with spaces after the commas', () {
    expect(inspector.inspect(json('[1,2,3]')), '[1, 2, 3]');
  });

  test('prints an object as braces around its fields', () {
    expect(inspector.inspect(json('{"a":1,"b":["x"]}')), '{ a: 1, b: ["x"] }');
  });

  test('prints empty containers without spaces', () {
    expect(inspector.inspect(json('[]')), '[]');
    expect(inspector.inspect(json('{}')), '{}');
  });

  test('prints a whole float as an integer', () {
    expect(inspector.inspect(json('1.0')), '1');
    expect(inspector.inspect(json('1.5')), '1.5');
  });

  test('prints null and booleans', () {
    expect(inspector.inspect(json('[null,true,false]')), '[null, true, false]');
  });

  test('shows ten items of a list and counts the rest', () {
    expect(
      inspector.inspect(json('[1,2,3,4,5,6,7,8,9,10,11,12]')),
      '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ... 2 more items]',
    );
  });

  test('says one more item in the singular', () {
    expect(
      inspector.inspect(json('[1,2,3,4,5,6,7,8,9,10,11]')),
      '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, ... 1 more item]',
    );
  });

  test('cuts containers nested more than two levels deep', () {
    expect(inspector.inspect(json('[[[1]]]')), '[[[Array]]]');
    expect(
      inspector.inspect(json('{"a":{"b":{"c":1}}}')),
      '{ a: { b: [Object] } }',
    );
  });

  test('is used by the messages of the built-in scalars', () {
    expect(
      const StringCodec().decode(json('[1,2,3]')),
      const DecodeFailure(
        'String cannot represent a non string value: [1, 2, 3]',
      ),
    );
    expect(
      const IntCodec().decode(json('{"a":1}')),
      const DecodeFailure('Int cannot represent non-integer value: { a: 1 }'),
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/protocol/json_inspector_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/protocol/json_inspector.dart`:

```dart
import 'dart:convert';

import 'json_value.dart';

/// graphql-js's `inspect` for a [JsonValue]: how a value is printed inside
/// a scalar's error message.
///
/// Strings are JSON-quoted, an object prints as `{ a: 1 }`, a list as
/// `[1, 2]` with at most ten items and then `... N more items`, and a list
/// or object nested more than two levels deep prints as `[Array]` or
/// `[Object]`, so the size of a message does not grow with a hostile value.
///
/// {@category protocol}
final class const JsonInspector() {
  /// Creates the inspector; it keeps no state.
  this;

  static const int _maxItems = 10;
  static const int _maxDepth = 2;

  /// [value] as graphql-js's `inspect` prints it.
  String inspect(JsonValue value) => _format(value, 0);

  String _format(JsonValue value, int ancestors) => switch (value) {
    JsonNull() => 'null',
    JsonBool(:final value) => '$value',
    JsonNumber(:final value) => _number(value),
    JsonString(:final value) => jsonEncode(value),
    JsonArray(:final items) => _list(items, ancestors + 1),
    JsonObject(:final fields) => _object(fields, ancestors + 1),
  };

  // JavaScript prints 1.0 as 1 and -0 as 0.
  String _number(num number) {
    final isWhole = number.isFinite && number == number.truncateToDouble();
    return isWhole && number.abs() < 1e21 ? '${number.toInt()}' : '$number';
  }

  String _list(List<JsonValue> items, int depth) {
    if (items.isEmpty) {
      return '[]';
    }
    if (depth > _maxDepth) {
      return '[Array]';
    }
    final shown = items.length < _maxItems ? items.length : _maxItems;
    final remaining = items.length - shown;
    final parts = [
      for (var i = 0; i < shown; i++) _format(items[i], depth),
      if (remaining == 1) '... 1 more item',
      if (remaining > 1) '... $remaining more items',
    ];
    return '[${parts.join(', ')}]';
  }

  String _object(Map<String, JsonValue> fields, int depth) {
    if (fields.isEmpty) {
      return '{}';
    }
    if (depth > _maxDepth) {
      return '[Object]';
    }
    final properties = [
      for (final MapEntry(:key, :value) in fields.entries)
        '$key: ${_format(value, depth)}',
    ];
    return '{ ${properties.join(', ')} }';
  }
}
```

In `packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../protocol/decode_result.dart';
+import '../../protocol/json_inspector.dart';
 import '../../protocol/json_value.dart';
 import 'scalar_codec.dart';
 
@@ -12,7 +13,9 @@ final class const BooleanCodec() implements ScalarCodec<bool> {
   @override
   DecodeResult<bool> decode(JsonValue json) => switch (json) {
     JsonBool(:final value) => DecodeSuccess(value),
-    _ => DecodeFailure('Boolean cannot represent a non boolean value: $json'),
+    _ => DecodeFailure(
+      'Boolean cannot represent a non boolean value: ${const JsonInspector().inspect(json)}',
+    ),
   };
 
   @override
```

In `packages/typed_graphql/lib/src/schema/scalars/float_codec.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../protocol/decode_result.dart';
+import '../../protocol/json_inspector.dart';
 import '../../protocol/json_value.dart';
 import 'scalar_codec.dart';
 
@@ -13,7 +14,9 @@ final class const FloatCodec() implements ScalarCodec<double> {
   @override
   DecodeResult<double> decode(JsonValue json) => switch (json) {
     JsonNumber(:final value) => DecodeSuccess(value.toDouble()),
-    _ => DecodeFailure('Float cannot represent non numeric value: $json'),
+    _ => DecodeFailure(
+      'Float cannot represent non numeric value: ${const JsonInspector().inspect(json)}',
+    ),
   };
 
   @override
```

In `packages/typed_graphql/lib/src/schema/scalars/id_codec.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../protocol/decode_result.dart';
+import '../../protocol/json_inspector.dart';
 import '../../protocol/json_value.dart';
 import 'scalar_codec.dart';
 
@@ -15,7 +16,9 @@ final class const IdCodec() implements ScalarCodec<String> {
   DecodeResult<String> decode(JsonValue json) => switch (json) {
     JsonString(:final value) => DecodeSuccess(value),
     JsonNumber(:final asInt?) => DecodeSuccess('$asInt'),
-    _ => DecodeFailure('ID cannot represent value: $json'),
+    _ => DecodeFailure(
+      'ID cannot represent value: ${const JsonInspector().inspect(json)}',
+    ),
   };
 
   @override
```

In `packages/typed_graphql/lib/src/schema/scalars/int_codec.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../protocol/decode_result.dart';
+import '../../protocol/json_inspector.dart';
 import '../../protocol/json_value.dart';
 import 'scalar_codec.dart';
 
@@ -22,13 +23,15 @@ final class const IntCodec() implements ScalarCodec<int> {
   @override
   DecodeResult<int> decode(JsonValue json) => switch (json) {
     JsonNumber(:final value) when value % 1 != 0 => DecodeFailure(
-      'Int cannot represent non-integer value: $json',
+      'Int cannot represent non-integer value: ${const JsonInspector().inspect(json)}',
     ),
     JsonNumber(:final value) when value < min || value > max => DecodeFailure(
-      'Int cannot represent non 32-bit signed integer value: $json',
+      'Int cannot represent non 32-bit signed integer value: ${const JsonInspector().inspect(json)}',
     ),
     JsonNumber(:final value) => DecodeSuccess(value.toInt()),
-    _ => DecodeFailure('Int cannot represent non-integer value: $json'),
+    _ => DecodeFailure(
+      'Int cannot represent non-integer value: ${const JsonInspector().inspect(json)}',
+    ),
   };
 
   @override
```

In `packages/typed_graphql/lib/src/schema/scalars/string_codec.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../protocol/decode_result.dart';
+import '../../protocol/json_inspector.dart';
 import '../../protocol/json_value.dart';
 import 'scalar_codec.dart';
 
@@ -12,7 +13,9 @@ final class const StringCodec() implements ScalarCodec<String> {
   @override
   DecodeResult<String> decode(JsonValue json) => switch (json) {
     JsonString(:final value) => DecodeSuccess(value),
-    _ => DecodeFailure('String cannot represent a non string value: $json'),
+    _ => DecodeFailure(
+      'String cannot represent a non string value: ${const JsonInspector().inspect(json)}',
+    ),
   };
 
   @override
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/protocol/json_inspector_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The messages of the built-in scalar codecs print an offending list or object as graphql-js does (`[1, 2, 3]`, `{ a: 1 }`, at most ten items, nested containers cut at depth two), not as compact JSON.
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/protocol/json_inspector.dart packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart packages/typed_graphql/lib/src/schema/scalars/float_codec.dart packages/typed_graphql/lib/src/schema/scalars/id_codec.dart packages/typed_graphql/lib/src/schema/scalars/int_codec.dart packages/typed_graphql/lib/src/schema/scalars/string_codec.dart packages/typed_graphql/test/protocol/json_inspector_test.dart
git commit -q -m "fix(typed_graphql): print values in scalar messages as graphql-js does" \
  -m "The built-in scalar codecs print an offending list or object with graphql-js's inspect (\`[1, 2, 3]\`, \`{ a: 1 }\`, ten items, depth two) instead of compact JSON." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Variables inside custom scalar literals

Substitute a variable's raw JSON inside a custom scalar's literal argument (`f(json: {a: $v})`) before the codec decodes it, as graphql-js does (`VariableLiteralJson`).

**Files:**
- Create: `packages/typed_graphql_server/lib/src/coercion/variable_literal_json.dart`
- Modify: `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart`, `packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart`
- Test: `packages/typed_graphql_server/test/coercion/variable_literal_json_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// coercion/variable_literal_json.dart
final class VariableLiteralJson
  VariableLiteralJson(this.variables)
  DecodeResult<JsonValue> convert(Value literal)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/coercion/variable_literal_json_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/variable_literal_json.dart';

enum Mood { happy }

void main() {
  Value literal(String text) => switch (const Parser().parseValue(
    Source(text),
  )) {
    ParseElementSuccess<Value>(:final value) => value,
    _ => fail('did not parse: $text'),
  };

  DecodeResult<JsonValue> convert(
    String text, [
    Map<String, Object?> variables = const {},
  ]) => VariableLiteralJson(variables).convert(literal(text));

  JsonValue json(Object? plain) => switch (plain) {
    null => const JsonNull(),
    final bool flag => JsonBool(flag),
    final num number => JsonNumber(number),
    final String text => JsonString(text),
    final List<Object?> items => JsonArray([for (final i in items) json(i)]),
    final Map<String, Object?> fields => JsonObject({
      for (final e in fields.entries) e.key: json(e.value),
    }),
    _ => fail('not JSON'),
  };

  test('substitutes a variable inside an object', () {
    expect(
      convert(r'{ a: $v, b: ["bar"], c: "baz" }', {'v': 'foo'}),
      DecodeSuccess(
        json({
          'a': 'foo',
          'b': ['bar'],
          'c': 'baz',
        }),
      ),
    );
  });

  test('keeps an explicit null variable in an object', () {
    expect(
      convert(r'{ a: $v }', {'v': null}),
      DecodeSuccess(json({'a': null})),
    );
  });

  test('leaves a variable without a value out of an object', () {
    expect(convert(r'{ a: $v, b: 1 }'), DecodeSuccess(json({'b': 1})));
  });

  test('reads a variable without a value in a list as null', () {
    expect(convert(r'[1, $v]'), DecodeSuccess(json([1, null])));
  });

  test('substitutes a list and a map value', () {
    expect(
      convert(r'[$v]', {
        'v': [
          1,
          {'k': true},
        ],
      }),
      DecodeSuccess(
        json([
          [
            1,
            {'k': true},
          ],
        ]),
      ),
    );
  });

  test('refuses a coerced value that is not plain data', () {
    expect(
      convert(r'{ a: $v }', {'v': Mood.happy}),
      const DecodeFailure(
        r'The value of the variable "$v" cannot be written as JSON here.',
        path: [PathKey('a')],
      ),
    );
  });

  test('converts a literal without variables as LiteralConverter does', () {
    expect(
      convert('{ a: ENUM, b: 1.5 }'),
      DecodeSuccess(json({'a': 'ENUM', 'b': 1.5})),
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/variable_literal_json_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/coercion/variable_literal_json.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Converts the literal of a custom scalar to the JSON its codec decodes
/// when the literal holds variables, as graphql-js's `valueFromASTUntyped`
/// does with the variable values (a non-specified graphql-js behaviour).
///
/// A variable stands for the JSON its already coerced value is made of:
/// null, a boolean, a number, a string, or a list or map of those. A
/// variable without a value is left out of an object and is `null` in a
/// list. A coerced value of any other kind (an enum, an input object
/// decoded to a class) cannot be written back without its type, and is a
/// failure.
///
/// Like [LiteralConverter] it recurses along the literal, and one nested
/// deeper than [JsonReader.maxSupportedDepth] is a failure.
final class VariableLiteralJson {
  /// Converts reading variables from [variables] (the coerced values by
  /// name).
  VariableLiteralJson(this.variables);

  static const LiteralConverter _constants = LiteralConverter();

  /// The coerced variable values.
  final Map<String, Object?> variables;

  /// [literal] as JSON, or a failure.
  DecodeResult<JsonValue> convert(Value literal) => _convert(literal, 0);

  DecodeResult<JsonValue> _convert(Value literal, int depth) {
    if (depth >= JsonReader.maxSupportedDepth) {
      return const DecodeFailure(
        'arrays and objects are nested deeper than '
        '${JsonReader.maxSupportedDepth}',
      );
    }
    return switch (literal) {
      Variable(:final name) => _variable(name.value),
      ListValue(:final values) => _list(values, depth),
      ObjectValue(:final fields) => _object(fields, depth),
      _ => _constants.convert(literal),
    };
  }

  // An absent variable is dropped by the list and the object; reaching
  // here, it is a null, as in a list.
  DecodeResult<JsonValue> _variable(String name) => variables.containsKey(name)
      ? _json(variables[name], name)
      : const DecodeSuccess(JsonNull());

  DecodeResult<JsonValue> _json(Object? value, String name) {
    final converted = _plain(value);
    return converted == null
        ? DecodeFailure(
            'The value of the variable "\$$name" cannot be written as JSON '
            'here.',
          )
        : DecodeSuccess(converted);
  }

  // Null for a value that is not plain data; a Dart null is a JsonNull.
  JsonValue? _plain(Object? value) => switch (value) {
    null => const JsonNull(),
    final bool flag => JsonBool(flag),
    final num number when number.isFinite => JsonNumber(number),
    final String text => JsonString(text),
    final List<Object?> items => _plainList(items),
    final Map<String, Object?> fields => _plainMap(fields),
    _ => null,
  };

  JsonValue? _plainList(List<Object?> items) {
    final converted = <JsonValue>[];
    for (final item in items) {
      final json = _plain(item);
      if (json == null) {
        return null;
      }
      converted.add(json);
    }
    return JsonArray(converted);
  }

  JsonValue? _plainMap(Map<String, Object?> fields) {
    final converted = <String, JsonValue>{};
    for (final MapEntry(:key, :value) in fields.entries) {
      final json = _plain(value);
      if (json == null) {
        return null;
      }
      converted[key] = json;
    }
    return JsonObject(converted);
  }

  DecodeResult<JsonValue> _list(List<Value> values, int depth) {
    final items = <JsonValue>[];
    for (final (index, value) in values.indexed) {
      switch (_convert(value, depth + 1).inside(PathIndex(index))) {
        case DecodeSuccess(value: final item):
          items.add(item);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonArray(items));
  }

  DecodeResult<JsonValue> _object(List<ObjectField> fields, int depth) {
    final converted = <String, JsonValue>{};
    for (final field in fields) {
      final name = field.name.value;
      final value = field.value;
      if (value is Variable && !variables.containsKey(value.name.value)) {
        continue;
      }
      switch (_convert(value, depth + 1).inside(PathKey(name))) {
        case DecodeSuccess(value: final item):
          converted[name] = item;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(converted));
  }
}
```

In `packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,7 +21,7 @@ final class LiteralCoercion {
   /// Coerces into [problems], reading variables from [variables] (the
   /// coerced values by name; a variable that is not a key has no value).
   LiteralCoercion(this.environment, this.problems, this.variables)
-    : _leaves = LiteralLeafCoercion(environment, problems);
+    : _leaves = LiteralLeafCoercion(environment, problems, variables);
 
   static const Printer _printer = Printer();
 
```

In `packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,6 +5,7 @@ import 'coercion_problems.dart';
 import 'input_path.dart';
 import 'invalid_value.dart';
 import 'leaf_coercion.dart';
+import 'variable_literal_json.dart';
 
 /// Coerces a literal to a scalar or an enum value with graphql-js's
 /// `coerceInputLiteral` rules: a literal has a kind, and the kind matters
@@ -15,11 +16,10 @@ import 'leaf_coercion.dart';
 /// goes through [LeafCoercion] as the JSON the literal stands for.
 final class LiteralLeafCoercion {
   /// Coerces into [problems].
-  LiteralLeafCoercion(this.environment, this.problems)
+  LiteralLeafCoercion(this.environment, this.problems, this.variables)
     : _leaves = LeafCoercion(environment, problems);
 
   static const Printer _printer = Printer();
-  static const LiteralConverter _converter = LiteralConverter();
 
   // The message of each built-in scalar for a literal of a kind it refuses.
   static const Map<String, String> _refusals = {
@@ -36,6 +36,9 @@ final class LiteralLeafCoercion {
   /// Where problems go.
   final CoercionProblems problems;
 
+  /// The coerced variable values a custom scalar's literal may hold.
+  final Map<String, Object?> variables;
+
   final LeafCoercion _leaves;
 
   /// The Dart value of the constant [literal] for the leaf [type] at
@@ -54,7 +57,7 @@ final class LiteralLeafCoercion {
       problems.add('${_refusals[type.name]}: ${_printer.print(literal)}', path);
       return InvalidValue.instance;
     }
-    return switch (_converter.convert(literal)) {
+    return switch (VariableLiteralJson(variables).convert(literal)) {
       DecodeSuccess(:final value) => _leaves.coerce(value, type, path),
       DecodeFailure(:final message) => _reject(message, path),
     };
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/coercion/variable_literal_json_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/coercion/literal_coercion.dart packages/typed_graphql_server/lib/src/coercion/literal_leaf_coercion.dart packages/typed_graphql_server/lib/src/coercion/variable_literal_json.dart packages/typed_graphql_server/test/coercion/variable_literal_json_test.dart
git commit -q -m "fix(typed_graphql_server): substitute variables in custom scalar literals" \
  -m "A variable inside the literal of a custom scalar (\`json: { a: \$v }\`) is replaced by the JSON of its coerced value before the codec decodes it, as graphql-js does; a value that is not plain data is still a problem." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: Conformance: variables and input coercion

Port `variables-test.ts`, `oneof-test.ts`, and the cases of `coerceInputValue-test.ts` and `validateInputValue-test.ts` reachable through `execute`.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`
- Test: `packages/typed_graphql_conformance/test/execution/coerce_input_literal_test.dart`, `packages/typed_graphql_conformance/test/execution/coerce_input_value_test.dart`, `packages/typed_graphql_conformance/test/execution/oneof_test.dart`, `packages/typed_graphql_conformance/test/execution/validate_input_literal_oneof_test.dart`, `packages/typed_graphql_conformance/test/execution/validate_input_literal_test.dart`, `packages/typed_graphql_conformance/test/execution/validate_input_value_test.dart`, `packages/typed_graphql_conformance/test/execution/variables_lists_test.dart`, `packages/typed_graphql_conformance/test/execution/variables_objects_test.dart`, `packages/typed_graphql_conformance/test/execution/variables_scalars_test.dart`, `packages/typed_graphql_conformance/test/support/input_probe.dart`, `packages/typed_graphql_conformance/test/support/js_inspect.dart`, `packages/typed_graphql_conformance/test/support/variables_schema.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/execution_port.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/execution/coerce_input_literal_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/coerceInputValue-test.ts
// (coerceInputLiteral); each case writes the literal as the argument of a
// field and reads what the field received. mapping/execution.csv says which
// tests are adapted or skipped, and why.
void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final anyScalar = b.scalar<JsonValue>('AnyScalar', const JsonScalarCodec());
  final refusing = b.scalar<JsonValue>(
    'ThrowScalar',
    const RefusingScalarCodec(),
  );
  final color = b.enumType<ProbeColor>(
    'TestColor',
    ProbeColor.values,
    mapping: EnumValueMapping<ProbeColor>(
      nameOf: (value) => switch (value) {
        ProbeColor.red => 'RED',
        ProbeColor.green => 'GREEN',
        ProbeColor.blue => 'BLUE',
        ProbeColor.nullValue => 'NULL',
        ProbeColor.nan => 'NAN',
        ProbeColor.noCustomValue => 'NO_CUSTOM_VALUE',
      },
    ),
  );
  final defaultInt = Arg('int', b.int.nullable, defaultValue: 42);
  final defaultFloat = Arg('float', b.float.nullable, defaultValue: 3.14);
  final defaults = b.inputObject<Map<String, Object?>>(
    'TestDefaults',
    fields: () => [defaultInt, defaultFloat],
    decode: (v) => {
      'int': v.get(defaultInt),
      'float': v.get(defaultFloat),
    },
  );
  final intField = Arg('int', b.int.nullable, defaultValue: 42);
  final boolField = Arg.optional('bool', b.boolean.nullable);
  final requiredBool = Arg('requiredBool', b.boolean);
  final testInput = b.inputObject<Map<String, Object?>>(
    'TestInput',
    fields: () => [intField, boolField, requiredBool],
    decode: (v) => {
      'int': v.get(intField),
      if (v.get(boolField) case Present(:final value)) 'bool': value,
      'requiredBool': v.get(requiredBool),
    },
  );
  final a = Arg.optional('a', b.string.nullable);
  final bString = Arg.optional('b', b.string.nullable);
  final oneOf = b.oneOfInputObject<Map<String, Object?>>(
    'TestOneOfInput',
    fields: () => [a, bString],
    decode: (v) => {
      if (v.get(a) case Present(:final value)) 'a': value,
      if (v.get(bString) case Present(:final value)) 'b': value,
    },
  );
  final probe = InputProbe(b, [
    ('bool', 'Boolean', b.boolean.nullable),
    ('int', 'Int', b.int.nullable),
    ('float', 'Float', b.float.nullable),
    ('string', 'String', b.string.nullable),
    ('id', 'ID', b.id.nullable),
    ('anyScalar', 'AnyScalar', anyScalar.nullable),
    ('throwScalar', 'ThrowScalar', refusing.nullable),
    ('color', 'TestColor', color.nullable),
    ('colorNonNull', 'TestColor!', color),
    ('nonNullBool', 'Boolean!', b.boolean),
    ('listOfBool', '[Boolean]', b.inputList(b.boolean.nullable).nullable),
    ('listOfNonNullBool', '[Boolean!]', b.inputList(b.boolean).nullable),
    ('nonNullListOfBool', '[Boolean]!', b.inputList(b.boolean.nullable)),
    ('nonNullListOfNonNullBool', '[Boolean!]!', b.inputList(b.boolean)),
    ('defaults', 'TestDefaults', defaults.nullable),
    ('testInput', 'TestInput', testInput.nullable),
    ('oneOf', 'TestOneOfInput', oneOf.nullable),
  ]);

  group('coerceInputLiteral', () {
    test('converts according to input coercion rules', () async {
      expect(await probe.literal('bool', 'true'), 'true');
      expect(await probe.literal('bool', 'false'), 'false');
      expect(await probe.literal('int', '123'), '123');
      expect(await probe.literal('float', '123'), '123');
      expect(await probe.literal('float', '123.456'), '123.456');
      expect(await probe.literal('string', '"abc123"'), '"abc123"');
      expect(await probe.literal('id', '123456'), '"123456"');
      expect(await probe.literal('id', '"123456"'), '"123456"');
    });

    test('does not convert when input coercion rules reject a value', () async {
      expect(await probe.literal('bool', '123'), isNull);
      expect(await probe.literal('int', '123.456'), isNull);
      expect(await probe.literal('int', 'true'), isNull);
      expect(await probe.literal('int', '"123"'), isNull);
      expect(await probe.literal('float', '"123"'), isNull);
      expect(await probe.literal('string', '123'), isNull);
      expect(await probe.literal('string', 'true'), isNull);
      expect(await probe.literal('string', '123.456'), isNull);
      expect(await probe.literal('id', '123.456'), isNull);
    });

    test(
      'convert using coerceInputLiteral from a custom scalar type',
      () async {
        expect(await probe.literal('anyScalar', '"value"'), '"value"');
        expect(
          await probe.literal(
            'anyScalar',
            r'{ field: $var }',
            definitions: r'($var: String)',
            variables: {'var': 'value'},
          ),
          '{ field: "value" }',
        );
        expect(await probe.literal('throwScalar', 'value'), isNull);
      },
    );

    test('converts enum values according to input coercion rules', () async {
      expect(await probe.literal('color', 'RED'), '1');
      expect(await probe.literal('color', 'BLUE'), '3');
      expect(await probe.literal('color', '3'), isNull);
      expect(await probe.literal('color', '"BLUE"'), isNull);
      expect(await probe.literal('color', 'null'), 'null');
      expect(await probe.literal('color', 'NULL'), 'null');
      expect(await probe.literal('colorNonNull', 'NULL'), 'null');
      expect(await probe.literal('color', 'NAN'), 'NaN');
      expect(
        await probe.literal('color', 'NO_CUSTOM_VALUE'),
        '"NO_CUSTOM_VALUE"',
      );
    });

    test('coerces to null unless non-null', () async {
      expect(await probe.literal('bool', 'null'), 'null');
      expect(await probe.literal('nonNullBool', 'null'), isNull);
    });

    test('coerces lists of values', () async {
      expect(await probe.literal('listOfBool', 'true'), '[true]');
      expect(await probe.literal('listOfBool', '123'), isNull);
      expect(await probe.literal('listOfBool', 'null'), 'null');
      expect(
        await probe.literal('listOfBool', '[true, false]'),
        '[true, false]',
      );
      expect(await probe.literal('listOfBool', '[true, 123]'), isNull);
      expect(
        await probe.literal('listOfBool', '[true, null]'),
        '[true, null]',
      );
      expect(await probe.literal('listOfBool', '{ true: true }'), isNull);
    });

    test('coerces non-null lists of values', () async {
      const field = 'nonNullListOfBool';
      expect(await probe.literal(field, 'true'), '[true]');
      expect(await probe.literal(field, '123'), isNull);
      expect(await probe.literal(field, 'null'), isNull);
      expect(await probe.literal(field, '[true, false]'), '[true, false]');
      expect(await probe.literal(field, '[true, 123]'), isNull);
      expect(await probe.literal(field, '[true, null]'), '[true, null]');
    });

    test('coerces lists of non-null values', () async {
      const field = 'listOfNonNullBool';
      expect(await probe.literal(field, 'true'), '[true]');
      expect(await probe.literal(field, '123'), isNull);
      expect(await probe.literal(field, 'null'), 'null');
      expect(await probe.literal(field, '[true, false]'), '[true, false]');
      expect(await probe.literal(field, '[true, 123]'), isNull);
      expect(await probe.literal(field, '[true, null]'), isNull);
    });

    test('coerces non-null lists of non-null values', () async {
      const field = 'nonNullListOfNonNullBool';
      expect(await probe.literal(field, 'true'), '[true]');
      expect(await probe.literal(field, '123'), isNull);
      expect(await probe.literal(field, 'null'), isNull);
      expect(await probe.literal(field, '[true, false]'), '[true, false]');
      expect(await probe.literal(field, '[true, 123]'), isNull);
      expect(await probe.literal(field, '[true, null]'), isNull);
    });

    test('uses default values for unprovided fields', () async {
      expect(
        await probe.literal('defaults', '{}'),
        '{ int: 42, float: 3.14 }',
      );
    });

    test('coerces input objects according to input coercion rules', () async {
      Future<String?> input(String text) => probe.literal('testInput', text);
      Future<String?> oneOf(String text) => probe.literal('oneOf', text);

      expect(await input('null'), 'null');
      expect(await input('123'), isNull);
      expect(await input('[]'), isNull);
      expect(
        await input('{ requiredBool: true }'),
        '{ int: 42, requiredBool: true }',
      );
      expect(
        await input('{ int: null, requiredBool: true }'),
        '{ int: null, requiredBool: true }',
      );
      expect(
        await input('{ int: 123, requiredBool: false }'),
        '{ int: 123, requiredBool: false }',
      );
      expect(
        await input('{ bool: true, requiredBool: false }'),
        '{ int: 42, bool: true, requiredBool: false }',
      );
      expect(await input('{ int: true, requiredBool: true }'), isNull);
      expect(await input('{ requiredBool: null }'), isNull);
      expect(await input('{ bool: true }'), isNull);
      expect(await input('{ requiredBool: true, unknown: 123 }'), isNull);
      expect(await oneOf('{ a: "abc" }'), '{ a: "abc" }');
      expect(await oneOf('{ b: "def" }'), '{ b: "def" }');
      expect(await oneOf('{ a: "abc", b: null }'), isNull);
      expect(await oneOf('{ a: null }'), isNull);
      expect(await oneOf('{ a: 1 }'), isNull);
      expect(await oneOf('{ a: "abc", b: "def" }'), isNull);
      expect(await oneOf('{ a: "abc", c: "def" }'), isNull);
      expect(await oneOf('{}'), isNull);
      expect(await oneOf('{ c: "abc" }'), isNull);
    });

    test('accepts variable values assuming already coerced', () async {
      expect(await probe.literal('bool', r'$var'), isNull);
      expect(
        await probe.literal(
          'bool',
          r'$var',
          definitions: r'($var: Boolean)',
          variables: {'var': true},
        ),
        'true',
      );
      expect(
        await probe.literal(
          'bool',
          r'$var',
          definitions: r'($var: Boolean)',
          variables: {'var': null},
        ),
        'null',
      );
      expect(
        await probe.literal(
          'nonNullBool',
          r'$var',
          definitions: r'($var: Boolean)',
          variables: {'var': null},
        ),
        isNull,
      );
    });

    test('asserts variables are provided as items in lists', () async {
      expect(
        await probe.literal('listOfBool', r'[ $foo ]'),
        '[null]',
      );
      expect(await probe.literal('listOfNonNullBool', r'[ $foo ]'), isNull);
      expect(
        await probe.literal(
          'listOfNonNullBool',
          r'[ $foo ]',
          definitions: r'($foo: Boolean)',
          variables: {'foo': true},
        ),
        '[true]',
      );
      expect(
        await probe.literal(
          'listOfNonNullBool',
          r'$foo',
          definitions: r'($foo: Boolean)',
          variables: {'foo': true},
        ),
        // graphql-js returns the variable's value as it is; the executor
        // refuses a Boolean variable where a list is expected.
        isNull,
      );
      expect(
        await probe.literal(
          'listOfNonNullBool',
          r'$foo',
          definitions: r'($foo: [Boolean])',
          variables: {
            'foo': [true],
          },
        ),
        '[true]',
      );
    });

    test('omits input object fields for unprovided variables', () async {
      expect(
        await probe.literal(
          'testInput',
          r'{ int: $foo, bool: $foo, requiredBool: true }',
        ),
        '{ int: 42, requiredBool: true }',
      );
      expect(
        await probe.literal('testInput', r'{ requiredBool: $foo }'),
        isNull,
      );
      expect(
        await probe.literal(
          'testInput',
          r'{ requiredBool: $foo }',
          definitions: r'($foo: Boolean)',
          variables: {'foo': true},
        ),
        '{ int: 42, requiredBool: true }',
      );
    });

    test(
      'rejects multiple oneOf fields when one variable is unprovided',
      () async {
        expect(
          await probe.literal(
            'oneOf',
            r'{ a: $a, b: $b }',
            definitions: r'($a: String, $b: String)',
            variables: {'a': 'abc'},
          ),
          isNull,
        );
      },
    );

    test('rejects oneOf field when variable is null', () async {
      expect(
        await probe.literal(
          'oneOf',
          r'{ a: $a }',
          definitions: r'($a: String)',
          variables: {'a': null},
        ),
        isNull,
      );
    });

    test('preserves explicit null variables in input object fields', () async {
      expect(
        await probe.literal(
          'testInput',
          r'{ int: $foo, requiredBool: true }',
          definitions: r'($foo: Boolean)',
          variables: {'foo': null},
        ),
        '{ int: null, requiredBool: true }',
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/coerce_input_value_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/coerceInputValue-test.ts
// (coerceInputValue); each case sends the value as a variable and reads what
// the field received. mapping/execution.csv says which tests are adapted or
// skipped, and why.
void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final testScalar = b.scalar<JsonValue>(
    'TestScalar',
    const ProbeScalarCodec(),
  );
  final anyScalar = b.scalar<JsonValue>('AnyScalar', const JsonScalarCodec());
  final testEnum = b.enumType<ProbeEnum>(
    'TestEnum',
    ProbeEnum.values,
    mapping: EnumValueMapping<ProbeEnum>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final foo = Arg('foo', b.int);
  final bar = Arg.optional('bar', b.int.nullable);
  final nested = Arg.optional('nestedObject', b.int.nullable);
  final testObject = b.inputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [foo, bar, nested],
    decode: (v) => {
      'foo': v.get(foo),
      if (v.get(bar) case Present(:final value)) 'bar': value,
      if (v.get(nested) case Present(:final value)) 'nestedObject': value,
    },
  );
  final oneOfFoo = Arg.optional('foo', b.int.nullable);
  final oneOfBar = Arg.optional('bar', b.int.nullable);
  final oneOf = b.oneOfInputObject<Map<String, Object?>>(
    'TestOneOfObject',
    fields: () => [oneOfFoo, oneOfBar],
    decode: (v) => {
      if (v.get(oneOfFoo) case Present(:final value)) 'foo': value,
      if (v.get(oneOfBar) case Present(:final value)) 'bar': value,
    },
  );
  final sevenFoo = Arg('foo', anyScalar, defaultValue: JsonNumber(7));
  final seven = b.inputObject<Map<String, Object?>>(
    'DefaultSevenObject',
    fields: () => [sevenFoo],
    decode: (v) => {'foo': v.get(sevenFoo)},
  );
  final length = Arg.optional('length', b.int.nullable);
  final listItem = b.inputObject<Map<String, Object?>>(
    'ListItemObject',
    fields: () => [length],
    decode: (v) => {
      if (v.get(length) case Present(:final value)) 'length': value,
    },
  );
  final probe = InputProbe(b, [
    ('nonNull', 'Int!', b.int),
    ('scalar', 'TestScalar', testScalar.nullable),
    ('enumValue', 'TestEnum', testEnum.nullable),
    ('object', 'TestInputObject', testObject.nullable),
    ('oneOf', 'TestOneOfObject', oneOf.nullable),
    ('sevenDefault', 'DefaultSevenObject', seven.nullable),
    ('list', '[Int]', b.inputList(b.int.nullable).nullable),
    ('objectList', '[ListItemObject]', b.inputList(listItem).nullable),
    (
      'nestedList',
      '[[Int]]',
      b.inputList(b.inputList(b.int.nullable).nullable).nullable,
    ),
  ]);

  group('coerceInputValue', () {
    group('for GraphQLNonNull', () {
      test('returns for a non-null value', () async {
        expect(await probe.value('nonNull', 1), '1');
      });

      test('invalid for undefined value', () async {
        expect(await probe.value('nonNull', null, isOmitted: true), isNull);
      });

      test('invalid for null value', () async {
        expect(await probe.value('nonNull', null), isNull);
      });
    });

    group('for GraphQLScalar', () {
      test('returns for valid input', () async {
        expect(
          await probe.value('scalar', {'value': 1}),
          '1',
        );
      });

      test('returns for null result', () async {
        expect(await probe.value('scalar', {'value': null}), 'null');
      });

      test('invalid for undefined result', () async {
        expect(await probe.value('scalar', <String, Object?>{}), isNull);
      });

      test('invalid for undefined result', () async {
        expect(
          await probe.value('scalar', {'error': 'Some error message'}),
          isNull,
        );
      });
    });

    group('for GraphQLEnum', () {
      test('returns no error for a known enum name', () async {
        expect(await probe.value('enumValue', 'FOO'), '"InternalFoo"');
        expect(await probe.value('enumValue', 'BAR'), '123456789');
      });

      test('invalid for misspelled enum value', () async {
        expect(await probe.value('enumValue', 'foo'), isNull);
      });

      test('invalid for incorrect value type', () async {
        expect(await probe.value('enumValue', 123), isNull);
        expect(await probe.value('enumValue', {'field': 'value'}), isNull);
      });
    });

    group('for GraphQLInputObject', () {
      test('returns no error for a valid input', () async {
        expect(await probe.value('object', {'foo': 123}), '{ foo: 123 }');
      });

      test('invalid for a non-object type', () async {
        expect(await probe.value('object', 123), isNull);
      });

      test('invalid for an invalid field', () async {
        expect(await probe.value('object', {'foo': 1.5}), isNull);
      });

      test('invalid for multiple invalid fields', () async {
        expect(
          await probe.value('object', {'foo': 'abc', 'bar': 'def'}),
          isNull,
        );
      });

      test('invalid for a missing required field', () async {
        expect(await probe.value('object', {'bar': 123}), isNull);
      });

      test('invalid for an unknown field', () async {
        expect(
          await probe.value('object', {'foo': 123, 'unknownField': 123}),
          isNull,
        );
      });

      test('ignores unknown fields with undefined values', () async {
        expect(await probe.value('object', {'foo': 123}), '{ foo: 123 }');
      });

      test('invalid when supplied with an array', () async {
        expect(
          await probe.value('object', [
            {'foo': 123},
            {'bar': 456},
          ]),
          isNull,
        );
      });

      test(
        'invalid when a nested input object is supplied with an array',
        () async {
          expect(
            await probe.value('object', {
              'foo': 123,
              'nested': [
                {'foo': 123},
                {'bar': 456},
              ],
            }),
            isNull,
          );
        },
      );
    });

    group('for GraphQLInputObject that isOneOf', () {
      test('returns for valid input', () async {
        expect(await probe.value('oneOf', {'foo': 123}), '{ foo: 123 }');
      });

      test('invalid if more than one field is specified', () async {
        expect(await probe.value('oneOf', {'foo': 123, 'bar': null}), isNull);
      });

      test('invalid if the one field is null', () async {
        expect(await probe.value('oneOf', {'bar': null}), isNull);
      });

      test('invalid for an invalid field', () async {
        expect(await probe.value('oneOf', {'foo': 1.5}), isNull);
      });

      test('invalid for an unknown field', () async {
        expect(
          await probe.value('oneOf', {'foo': 123, 'unknownField': 123}),
          isNull,
        );
      });
    });

    group('for GraphQLInputObject with default value', () {
      test('returns no errors for valid input value', () async {
        expect(await probe.value('sevenDefault', {'foo': 5}), '{ foo: 5 }');
      });

      test('returns object with default value', () async {
        expect(
          await probe.value('sevenDefault', <String, Object?>{}),
          '{ foo: 7 }',
        );
      });
    });

    group('for GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(await probe.value('list', [1, 2, 3]), '[1, 2, 3]');
      });

      test('invalid for an invalid input', () async {
        expect(await probe.value('list', [1, 'b', true, 4]), isNull);
      });

      test('returns a list for a non-list value', () async {
        expect(await probe.value('list', 42), '[42]');
      });

      test('returns a list for a non-list object value', () async {
        expect(
          await probe.value('objectList', {'length': 100500}),
          '[{ length: 100500 }]',
        );
      });

      test('invalid for a non-list invalid value', () async {
        expect(await probe.value('list', 'INVALID'), isNull);
      });

      test('returns null for a null value', () async {
        expect(await probe.value('list', null), 'null');
      });
    });

    group('for nested GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(
          await probe.value('nestedList', [
            [1],
            [2, 3],
          ]),
          '[[1], [2, 3]]',
        );
      });

      test('returns a list for a non-list value', () async {
        expect(await probe.value('nestedList', 42), '[[42]]');
      });

      test('returns null for a null value', () async {
        expect(await probe.value('nestedList', null), 'null');
      });

      test('returns nested lists for nested non-list values', () async {
        expect(await probe.value('nestedList', [1, 2, 3]), '[[1], [2], [3]]');
      });

      test('returns nested null for nested null values', () async {
        expect(
          await probe.value('nestedList', [
            42,
            [null],
            null,
          ]),
          '[[42], [null], null]',
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/oneof_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/oneof-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();

  // The schema of graphql-js's `buildSchema`, rebuilt with the builder; the
  // field `test` answers its input as an object of the same fields.
  final b = ExecutableSchemaBuilder<Object?>();
  final inputA = Arg.optional('a', b.string.nullable);
  final inputB = Arg.optional('b', b.int.nullable);
  final testInput = b.oneOfInputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [inputA, inputB],
    decode: (values) => {
      if (values.get(inputA) case Present(:final value)) 'a': value,
      if (values.get(inputB) case Present(:final value)) 'b': value,
    },
  );
  final testObject = b.object<Map<String, Object?>>(
    'TestObject',
    fields: (t) => [
      t.field('a', b.string.nullable).pure((parent) => parent['a'] as String?),
      t.field('b', b.int.nullable).pure((parent) => parent['b'] as int?),
    ],
  );
  final input = Arg('input', testInput);
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('test', testObject.nullable, args: [input])
            .resolve((parent, args, context, info) => args.get(input)),
      ],
    ),
  );

  Future<Map<String, Object?>> run(
    String query, [
    Map<String, Object?>? variables,
  ]) => port.json(
    schema,
    query,
    variables: variables == null ? null : port.variablesOf(variables),
  );

  const badOneOf =
      'Within OneOf Input Object type "TestInputObject", exactly one field must be specified, and the value for that field must be non-null.';

  group('Execute: Handles OneOf Input Objects', () {
    group('OneOf Input Objects', () {
      const operation = r'''

        query ($input: TestInputObject!) {
          test(input: $input) {
            a
            b
          }
        }
      ''';

      Map<String, Object?> variableError(String where, String message) => {
        'errors': [
          {
            'message': 'Variable "\$input" has invalid value$where: $message',
            'locations': [
              {'line': 2, 'column': 16},
            ],
          },
        ],
      };

      test('accepts a good default value', () async {
        final result = await run(r'''
        query ($input: TestInputObject! = {a: "abc"}) {
          test(input: $input) {
            a
            b
          }
        }
      ''');

        expect(result, {
          'data': {
            'test': {'a': 'abc', 'b': null},
          },
        });
      });

      test('rejects a bad default value', () async {
        final result = await run(r'''

        query ($input: TestInputObject! = {a: "abc", b: 123}) {
          test(input: $input) {
            a
            b
          }
        }
      ''');

        expect(result, {
          'errors': [
            {
              'locations': [
                {'column': 16, 'line': 2},
              ],
              'message':
                  'Variable "\$input" has invalid default value: $badOneOf',
            },
          ],
        });
      });

      test('accepts a good variable', () async {
        final result = await run(operation, {
          'input': {'a': 'abc'},
        });

        expect(result, {
          'data': {
            'test': {'a': 'abc', 'b': null},
          },
        });
      });

      test('accepts a good variable with an undefined key', () async {
        final result = await run(operation, {
          'input': {'a': 'abc'},
        });

        expect(result, {
          'data': {
            'test': {'a': 'abc', 'b': null},
          },
        });
      });

      test('rejects a variable with a nulled key', () async {
        final result = await run(operation, {
          'input': {'a': null},
        });

        expect(result, variableError(' at .a', badOneOf));
      });

      test('rejects a variable with multiple non-null keys', () async {
        final result = await run(operation, {
          'input': {'a': 'abc', 'b': 123},
        });

        expect(result, variableError('', badOneOf));
      });

      test('rejects a variable with multiple nullable keys', () async {
        final result = await run(operation, {
          'input': {'a': 'abc', 'b': null},
        });

        expect(result, variableError('', badOneOf));
      });

      Map<String, Object?> fieldError(String message, int line) => {
        'data': {'test': null},
        'errors': [
          {
            'message':
                'Argument "Query.test(input:)" has invalid value: $message',
            'locations': [
              {'line': line, 'column': 23},
            ],
            'path': ['test'],
          },
        ],
      };

      test('errors with nulled variable for field', () async {
        final result = await run(
          r'''

        query ($a: String) {
          test(input: { a: $a }) {
            a
            b
          }
        }
      ''',
          {'a': null},
        );

        expect(
          result,
          fieldError(
            r'Expected variable "$a" provided to field "a" for OneOf Input Object type "TestInputObject" not to be null.',
            3,
          ),
        );
      });

      test('errors with missing variable for field', () async {
        final result = await run(r'''

        query ($a: String) {
          test(input: { a: $a }) {
            a
            b
          }
        }
      ''');

        expect(
          result,
          fieldError(
            r'Expected variable "$a" provided to field "a" for OneOf Input Object type "TestInputObject" to provide a runtime value.',
            3,
          ),
        );
      });

      test('errors with missing variable as an additional field', () async {
        final result = await run(
          r'''

        query ($a: String, $b: Int) {
          test(input: { a: $a, b: $b }) {
            a
            b
          }
        }
      ''',
          {'a': 'abc'},
        );

        expect(
          result,
          fieldError(
            r'Expected variable "$b" provided to field "b" for OneOf Input Object type "TestInputObject" to provide a runtime value.',
            3,
          ),
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/validate_input_literal_oneof_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';

// Ported from graphql-js src/utilities/__tests__/validateInputValue-test.ts
// (validateInputLiteral, the OneOf Input Object cases); each case writes the
// literal as the argument of a field and compares the errors of the
// response. mapping/execution.csv says which tests are adapted or skipped,
// and why.
void main() {
  final ob = ExecutableSchemaBuilder<Object?>();
  final oneOfFoo = Arg.optional('foo', ob.int.nullable);
  final oneOfBar = Arg.optional('bar', ob.int.nullable);
  final oneOf = ob.oneOfInputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [oneOfFoo, oneOfBar],
    decode: (v) => {
      if (v.get(oneOfFoo) case Present(:final value)) 'foo': value,
      if (v.get(oneOfBar) case Present(:final value)) 'bar': value,
    },
  );
  final oneOfProbe = InputProbe(ob, [
    ('oneOf', 'TestInputObject', oneOf.nullable),
  ]);
  const badOneOf =
      'Within OneOf Input Object type "TestInputObject", exactly one field must be specified, and the value for that field must be non-null.';
  const wrongObject =
      'Expected value of type "TestInputObject" to be an object, found: ';
  const unknown =
      'Expected value of type "TestInputObject" not to include unknown field';
  const intVariable = r'($var: Int)';

  group('validateInputLiteral', () {
    group('for GraphQLInputObject that isOneOf', () {
      Future<List<String>> literal(
        String text, {
        String definitions = '',
        Map<String, Object?> variables = const {},
      }) => oneOfProbe.literalErrors(
        'oneOf',
        text,
        definitions: definitions,
        variables: variables,
      );
      String error(String message, [String path = '']) =>
          oneOfProbe.argumentError('oneOf', message, path);

      test('returns no error for a valid input', () async {
        expect(await literal('{ foo: 123 }'), isEmpty);
      });

      test('returns an error if more than one field is specified', () async {
        expect(await literal('{ foo: 123, bar: null }'), [error(badOneOf)]);
      });

      test('returns an error if the one field is null', () async {
        expect(await literal('{ bar: null }'), [error(badOneOf, '.bar')]);
      });

      test('returns an error for a non-object type', () async {
        expect(await literal('123'), [error('${wrongObject}123.')]);
      });

      test('returns an error for an invalid field', () async {
        expect(await literal('{ foo: 1.5 }'), [
          error('Int cannot represent non-integer value: 1.5', '.foo'),
        ]);
      });

      test('returns error for an unknown field', () async {
        expect(await literal('{ foo: 123, unknownField: 123 }'), [
          error(
            '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
          ),
        ]);
      });

      test('returns error for a misspelled field', () async {
        expect(await literal('{ foo: 123, bart: 123 }'), [
          error(
            '$unknown "bart". Did you mean "bar"? Found: { foo: 123, bart: 123 }.',
          ),
        ]);
      });

      test('allows variables in an object, statically', () async {
        expect(
          await literal(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 1},
          ),
          isEmpty,
        );
      });

      test('allows correct use of variables', () async {
        expect(
          await literal(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 123},
          ),
          isEmpty,
        );
      });

      test('returns error with variable provided a value of null', () async {
        expect(
          await literal(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            error(
              r'Expected variable "$var" provided to field "foo" for OneOf Input Object type "TestInputObject" not to be null.',
            ),
          ],
        );
      });

      test('errors with missing variables as the additional field', () async {
        const missing =
            r'Expected variable "$var" provided to field "bar" for OneOf Input Object type "TestInputObject" to provide a runtime value.';
        // An argument reports its first problem only; graphql-js reports
        // every one.
        expect(await literal(r'{ foo: 123, bar: $var }'), [error(missing)]);
        expect(
          await literal(r'{ foo: 123, bar: $var }', definitions: intVariable),
          [error(missing)],
        );
      });

      test('errors with multiple variables when one is missing', () async {
        expect(
          await literal(
            r'{ foo: $foo, bar: $bar }',
            definitions: r'($foo: Int, $bar: Int)',
            variables: {'foo': 123},
          ),
          [
            error(
              r'Expected variable "$bar" provided to field "bar" for OneOf Input Object type "TestInputObject" to provide a runtime value.',
            ),
          ],
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/validate_input_literal_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/validateInputValue-test.ts
// (validateInputLiteral); each case writes the literal as the argument of a
// field and compares the errors of the response. mapping/execution.csv says
// which tests are adapted or skipped, and why.
void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final testScalar = b.scalar<JsonValue>(
    'TestScalar',
    const ProbeScalarCodec(),
  );
  final anyScalar = b.scalar<JsonValue>('AnyScalar', const JsonScalarCodec());
  final testEnum = b.enumType<ProbeEnum>(
    'TestEnum',
    ProbeEnum.values,
    mapping: EnumValueMapping<ProbeEnum>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final foo = Arg('foo', b.int);
  final bar = Arg.optional('bar', b.int.nullable);
  final optional = Arg('optional', b.int, defaultValue: 42);
  final testObject = b.inputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [foo, bar, optional],
    decode: (v) => {
      'foo': v.get(foo),
      if (v.get(bar) case Present(:final value)) 'bar': value,
      'optional': v.get(optional),
    },
  );
  final sevenFoo = Arg('foo', anyScalar, defaultValue: JsonNumber(7));
  final seven = b.inputObject<Map<String, Object?>>(
    'DefaultSevenObject',
    fields: () => [sevenFoo],
    decode: (v) => {'foo': v.get(sevenFoo)},
  );
  final probe = InputProbe(b, [
    ('nonNull', 'Int!', b.int),
    ('scalar', 'TestScalar', testScalar.nullable),
    ('enumValue', 'TestEnum', testEnum.nullable),
    ('object', 'TestInputObject', testObject.nullable),
    ('sevenDefault', 'DefaultSevenObject', seven.nullable),
    ('list', '[Int]', b.inputList(b.int.nullable).nullable),
    ('listNonNull', '[Int!]', b.inputList(b.int).nullable),
    (
      'nestedList',
      '[[Int]]',
      b.inputList(b.inputList(b.int.nullable).nullable).nullable,
    ),
  ]);

  const wrongObject =
      'Expected value of type "TestInputObject" to be an object, found: ';
  const unknown =
      'Expected value of type "TestInputObject" not to include unknown field';
  const intVariable = r'($var: Int)';

  Future<List<String>> object(
    String text, {
    String definitions = '',
    Map<String, Object?> variables = const {},
  }) => probe.literalErrors(
    'object',
    text,
    definitions: definitions,
    variables: variables,
  );

  group('validateInputLiteral', () {
    test(
      'returns an error for null variables for non-nullable types',
      () async {
        expect(
          await probe.literalErrors(
            'nonNull',
            r'$var',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            probe.argumentError(
              'nonNull',
              r'Expected variable "$var" provided to non-null type "Int!" not to be null.',
            ),
          ],
        );
      },
    );

    group('for GraphQLNonNull', () {
      test('returns no error for non-null value', () async {
        expect(await probe.literalErrors('nonNull', '1'), isEmpty);
      });

      test('returns an error for null value', () async {
        expect(await probe.literalErrors('nonNull', 'null'), [
          probe.argumentError(
            'nonNull',
            'Expected value of non-null type "Int!" not to be null.',
          ),
        ]);
      });
    });

    group('for GraphQLScalar', () {
      test('returns no error for valid input', () async {
        expect(await probe.literalErrors('scalar', '{ value: 1 }'), isEmpty);
      });

      test('returns no error for null result', () async {
        expect(await probe.literalErrors('scalar', '{ value: null }'), isEmpty);
      });

      test('returns no error for NaN result', () async {
        expect(await probe.literalErrors('scalar', '{ value: NaN }'), isEmpty);
      });

      test('returns an error for undefined result', () async {
        expect(await probe.literalErrors('scalar', '{}'), [
          probe.argumentError('scalar', ProbeScalarCodec.missingValue),
        ]);
      });

      test('returns an error for undefined result', () async {
        expect(
          await probe.literalErrors(
            'scalar',
            '{ error: "Some error message." }',
          ),
          [probe.argumentError('scalar', 'Some error message.')],
        );
      });
    });

    group('for GraphQLEnum', () {
      test('returns no error for a known enum name', () async {
        expect(await probe.literalErrors('enumValue', 'FOO'), isEmpty);
        expect(await probe.literalErrors('enumValue', 'BAR'), isEmpty);
      });

      test('returns an error for unknown enum value', () async {
        expect(await probe.literalErrors('enumValue', 'UNKNOWN'), [
          probe.argumentError(
            'enumValue',
            'Value "UNKNOWN" does not exist in "TestEnum" enum.',
          ),
        ]);
      });

      test('returns an error for misspelled enum value', () async {
        expect(await probe.literalErrors('enumValue', 'foo'), [
          probe.argumentError(
            'enumValue',
            'Value "foo" does not exist in "TestEnum" enum. Did you mean the enum value "FOO"?',
          ),
        ]);
      });

      test(
        'returns an error for misspelled enum value (no suggestions)',
        () async {
          expect(
            await probe.literalErrors(
              'enumValue',
              'foo',
              isShowingSuggestions: false,
            ),
            [
              probe.argumentError(
                'enumValue',
                'Value "foo" does not exist in "TestEnum" enum.',
              ),
            ],
          );
        },
      );

      test('returns an error for incorrect value type', () async {
        Future<List<String>> literal(
          String text, {
          bool isShowingSuggestions = true,
        }) => probe.literalErrors(
          'enumValue',
          text,
          isShowingSuggestions: isShowingSuggestions,
        );

        expect(await literal('"FOO"'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: "FOO". Did you mean the enum value "FOO"?',
          ),
        ]);
        expect(await literal('"FOO"', isShowingSuggestions: false), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: "FOO".',
          ),
        ]);
        expect(await literal('"UNKNOWN"'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: "UNKNOWN".',
          ),
        ]);
        expect(await literal('123'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: 123.',
          ),
        ]);
        expect(await literal('{ field: "value" }'), [
          probe.argumentError(
            'enumValue',
            'Enum "TestEnum" cannot represent non-enum value: { field: "value" }.',
          ),
        ]);
      });
    });

    group('for GraphQLInputObject', () {
      test('returns no error for a valid input', () async {
        expect(await object('{ foo: 123 }'), isEmpty);
      });

      test('returns an error for a non-object type', () async {
        expect(await object('123'), [
          probe.argumentError('object', '${wrongObject}123.'),
        ]);
      });

      test('returns an error for an invalid field', () async {
        expect(await object('{ foo: 1.5 }'), [
          probe.argumentError(
            'object',
            'Int cannot represent non-integer value: 1.5',
            '.foo',
          ),
        ]);
      });

      test('returns multiple errors for multiple invalid fields', () async {
        // An argument reports its first problem only; graphql-js reports
        // every one.
        expect(await object('{ foo: "abc", bar: "def" }'), [
          probe.argumentError(
            'object',
            'Int cannot represent non-integer value: "abc"',
            '.foo',
          ),
        ]);
      });

      test('returns error for a missing required field', () async {
        expect(await object('{ bar: 123 }'), [
          probe.argumentError(
            'object',
            'Expected value of type "TestInputObject" to include required field "foo", found: { bar: 123 }.',
          ),
        ]);
      });

      test('returns error for an unknown field', () async {
        expect(await object('{ foo: 123, unknownField: 123 }'), [
          probe.argumentError(
            'object',
            '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
          ),
        ]);
      });

      test('returns error for a misspelled field', () async {
        expect(await object('{ foo: 123, bart: 123 }'), [
          probe.argumentError(
            'object',
            '$unknown "bart". Did you mean "bar"? Found: { foo: 123, bart: 123 }.',
          ),
        ]);
      });

      test('allows variables in an object, statically', () async {
        expect(
          await object(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 1},
          ),
          isEmpty,
        );
      });

      test('allows correct use of variables', () async {
        expect(
          await object(
            r'{ foo: $var }',
            definitions: intVariable,
            variables: {'var': 123},
          ),
          isEmpty,
        );
      });

      test('allows missing variables in an nullable field', () async {
        expect(await object(r'{ foo: 123, bar: $var }'), isEmpty);
        expect(
          await object(r'{ foo: 123, bar: $var }', definitions: intVariable),
          isEmpty,
        );
      });

      test('allows missing variables in an optional field', () async {
        expect(
          await object(
            r'{ foo: 123, optional: $var }',
            definitions: intVariable,
          ),
          isEmpty,
        );
      });

      test('errors on missing variable in an required field', () async {
        expect(
          await object(r'{ foo: $var }', definitions: intVariable),
          [
            probe.argumentError(
              'object',
              r'Expected variable "$var" provided to type "Int!" to provide a runtime value.',
              '.foo',
            ),
          ],
        );
      });

      test('errors on null variable in an non-null field', () async {
        expect(
          await object(
            r'{ foo: 123, optional: $var }',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            probe.argumentError(
              'object',
              r'Expected variable "$var" provided to non-null type "Int!" not to be null.',
              '.optional',
            ),
          ],
        );
      });
    });

    group('for GraphQLInputObject with default value', () {
      test('no error for no errors for valid input value', () async {
        expect(
          await probe.literalErrors('sevenDefault', '{ foo: 5 }'),
          isEmpty,
        );
      });

      test('no error for object with default value', () async {
        expect(await probe.literalErrors('sevenDefault', '{}'), isEmpty);
      });
    });

    group('for GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(await probe.literalErrors('list', '[1, 2, 3]'), isEmpty);
      });

      test('returns an error for an invalid input', () async {
        expect(await probe.literalErrors('list', '[1, "b", true, 4]'), [
          probe.argumentError(
            'list',
            'Int cannot represent non-integer value: "b"',
            '[1]',
          ),
        ]);
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.literalErrors('list', '42'), isEmpty);
      });

      test('returns an error for a non-list invalid value', () async {
        expect(await probe.literalErrors('list', '"INVALID"'), [
          probe.argumentError(
            'list',
            'Int cannot represent non-integer value: "INVALID"',
          ),
        ]);
      });

      test('no error for null for a null value', () async {
        expect(await probe.literalErrors('list', 'null'), isEmpty);
      });

      test('allows variables in a list, statically', () async {
        expect(
          await probe.literalErrors(
            'list',
            r'[1, $var, 3]',
            definitions: intVariable,
            variables: {'var': 2},
          ),
          isEmpty,
        );
      });

      test(
        'allows missing variables in a list (which coerce to null)',
        () async {
          expect(
            await probe.literalErrors(
              'list',
              r'[1, $var, 3]',
              definitions: intVariable,
            ),
            isEmpty,
          );
        },
      );

      test('errors on missing variables in a list of non-null', () async {
        expect(
          await probe.literalErrors(
            'listNonNull',
            r'[1, $var, 3]',
            definitions: intVariable,
          ),
          [
            probe.argumentError(
              'listNonNull',
              r'Expected variable "$var" provided to type "Int!" to provide a runtime value.',
              '[1]',
            ),
          ],
        );
      });

      test('errors on null variables in a list of non-null', () async {
        expect(
          await probe.literalErrors(
            'listNonNull',
            r'[1, $var, 3]',
            definitions: intVariable,
            variables: {'var': null},
          ),
          [
            probe.argumentError(
              'listNonNull',
              r'Expected variable "$var" provided to non-null type "Int!" not to be null.',
              '[1]',
            ),
          ],
        );
      });
    });

    group('for nested GraphQLList', () {
      test('no error for a valid input', () async {
        expect(
          await probe.literalErrors('nestedList', '[[1], [2, 3]]'),
          isEmpty,
        );
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.literalErrors('nestedList', '42'), isEmpty);
      });

      test('no error for null for a null value', () async {
        expect(await probe.literalErrors('nestedList', 'null'), isEmpty);
      });

      test('no error for nested lists for nested non-list values', () async {
        expect(await probe.literalErrors('nestedList', '[1, 2, 3]'), isEmpty);
      });

      test('no error for nested null for nested null values', () async {
        expect(
          await probe.literalErrors('nestedList', '[42, [null], null]'),
          isEmpty,
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/validate_input_value_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/input_probe.dart';
import '../support/variables_schema.dart';

// Ported from graphql-js src/utilities/__tests__/validateInputValue-test.ts
// (validateInputValue); each case sends the value as a variable and compares
// the errors of the response. mapping/execution.csv says which tests are
// adapted or skipped, and why.
void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final testScalar = b.scalar<JsonValue>(
    'TestScalar',
    const ProbeScalarCodec(),
  );
  final anyScalar = b.scalar<JsonValue>('AnyScalar', const JsonScalarCodec());
  final testEnum = b.enumType<ProbeEnum>(
    'TestEnum',
    ProbeEnum.values,
    mapping: EnumValueMapping<ProbeEnum>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final foo = Arg('foo', b.int);
  final bar = Arg.optional('bar', b.int.nullable);
  // Late because the type refers to itself: assigned below, read by `fields`
  // only when the schema is built.
  late final Arg<Optional<Map<String, Object?>?>> nested;
  final testObject = b.inputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [foo, bar, nested],
    decode: (v) => {
      'foo': v.get(foo),
      if (v.get(bar) case Present(:final value)) 'bar': value,
      if (v.get(nested) case Present(:final value)) 'nested': value,
    },
  );
  nested = Arg.optional('nested', testObject.nullable);
  final sevenFoo = Arg('foo', anyScalar, defaultValue: JsonNumber(7));
  final seven = b.inputObject<Map<String, Object?>>(
    'DefaultSevenObject',
    fields: () => [sevenFoo],
    decode: (v) => {'foo': v.get(sevenFoo)},
  );
  final probe = InputProbe(b, [
    ('nonNull', 'Int!', b.int),
    ('scalar', 'TestScalar', testScalar.nullable),
    ('enumValue', 'TestEnum', testEnum.nullable),
    ('object', 'TestInputObject', testObject.nullable),
    ('sevenDefault', 'DefaultSevenObject', seven.nullable),
    ('list', '[Int]', b.inputList(b.int.nullable).nullable),
    (
      'nestedList',
      '[[Int]]',
      b.inputList(b.inputList(b.int.nullable).nullable).nullable,
    ),
  ]);

  final ob = ExecutableSchemaBuilder<Object?>();
  final oneOfFoo = Arg.optional('foo', ob.int.nullable);
  final oneOfBar = Arg.optional('bar', ob.int.nullable);
  final oneOf = ob.oneOfInputObject<Map<String, Object?>>(
    'TestInputObject',
    fields: () => [oneOfFoo, oneOfBar],
    decode: (v) => {
      if (v.get(oneOfFoo) case Present(:final value)) 'foo': value,
      if (v.get(oneOfBar) case Present(:final value)) 'bar': value,
    },
  );
  final oneOfProbe = InputProbe(ob, [
    ('oneOf', 'TestInputObject', oneOf.nullable),
  ]);
  const badOneOf =
      'Within OneOf Input Object type "TestInputObject", exactly one field must be specified, and the value for that field must be non-null.';
  const wrongObject =
      'Expected value of type "TestInputObject" to be an object, found: ';
  const unknown =
      'Expected value of type "TestInputObject" not to include unknown field';

  group('validateInputValue', () {
    group('for GraphQLNonNull', () {
      test('returns no error for non-null value', () async {
        expect(await probe.valueErrors('nonNull', 1), isEmpty);
      });

      test('returns an error for undefined value', () async {
        expect(await probe.valueErrors('nonNull', null, isOmitted: true), [
          probe.variableError(
            'Expected a value of non-null type "Int!" to be provided.',
          ),
        ]);
      });

      test('returns an error for null value', () async {
        expect(await probe.valueErrors('nonNull', null), [
          probe.variableError(
            'Expected value of non-null type "Int!" not to be null.',
          ),
        ]);
      });
    });

    group('for GraphQLScalar', () {
      test('returns no error for valid input', () async {
        expect(await probe.valueErrors('scalar', {'value': 1}), isEmpty);
      });

      test('returns no error for null result', () async {
        expect(await probe.valueErrors('scalar', {'value': null}), isEmpty);
      });

      test('returns an error for undefined result', () async {
        expect(await probe.valueErrors('scalar', <String, Object?>{}), [
          probe.variableError(ProbeScalarCodec.missingValue),
        ]);
      });

      test('returns an error for undefined result', () async {
        expect(
          await probe.valueErrors('scalar', {'error': 'Some error message.'}),
          [probe.variableError('Some error message.')],
        );
      });
    });

    group('for GraphQLEnum', () {
      test('returns no error for a known enum name', () async {
        expect(await probe.valueErrors('enumValue', 'FOO'), isEmpty);
        expect(await probe.valueErrors('enumValue', 'BAR'), isEmpty);
      });

      test('returns an error for unknown enum value', () async {
        expect(await probe.valueErrors('enumValue', 'UNKNOWN'), [
          probe.variableError(
            'Value "UNKNOWN" does not exist in "TestEnum" enum.',
          ),
        ]);
      });

      test('returns an error for misspelled enum value', () async {
        expect(await probe.valueErrors('enumValue', 'foo'), [
          probe.variableError(
            'Value "foo" does not exist in "TestEnum" enum. Did you mean the enum value "FOO"?',
          ),
        ]);
      });

      test(
        'returns an error for misspelled enum value (no suggestions)',
        () async {
          expect(
            await probe.valueErrors(
              'enumValue',
              'foo',
              isShowingSuggestions: false,
            ),
            [
              probe.variableError(
                'Value "foo" does not exist in "TestEnum" enum.',
              ),
            ],
          );
        },
      );

      test('returns an error for incorrect value type', () async {
        expect(await probe.valueErrors('enumValue', 123), [
          probe.variableError(
            'Enum "TestEnum" cannot represent non-string value: 123.',
          ),
        ]);
        expect(await probe.valueErrors('enumValue', {'field': 'value'}), [
          probe.variableError(
            'Enum "TestEnum" cannot represent non-string value: { field: "value" }.',
          ),
        ]);
      });
    });

    group('for GraphQLInputObject', () {
      test('returns no error for a valid input', () async {
        expect(await probe.valueErrors('object', {'foo': 123}), isEmpty);
      });

      test('returns an error for a non-object type', () async {
        expect(await probe.valueErrors('object', 123), [
          probe.variableError('${wrongObject}123.'),
        ]);
      });

      test('returns an error for an invalid field', () async {
        expect(await probe.valueErrors('object', {'foo': 1.5}), [
          probe.variableError(
            'Int cannot represent non-integer value: 1.5',
            '.foo',
          ),
        ]);
      });

      test('returns multiple errors for multiple invalid fields', () async {
        expect(
          await probe.valueErrors('object', {'foo': 'abc', 'bar': 'def'}),
          [
            probe.variableError(
              'Int cannot represent non-integer value: "abc"',
              '.foo',
            ),
            probe.variableError(
              'Int cannot represent non-integer value: "def"',
              '.bar',
            ),
          ],
        );
      });

      test('returns error for a missing required field', () async {
        expect(await probe.valueErrors('object', {'bar': 123}), [
          probe.variableError(
            'Expected value of type "TestInputObject" to include required field "foo", found: { bar: 123 }.',
          ),
        ]);
      });

      test('returns error for an unknown field', () async {
        expect(
          await probe.valueErrors('object', {'foo': 123, 'unknownField': 123}),
          [
            probe.variableError(
              '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
            ),
          ],
        );
      });

      test('ignores unknown fields with undefined values', () async {
        expect(await probe.valueErrors('object', {'foo': 123}), isEmpty);
      });

      test('returns error when supplied with an array', () async {
        expect(
          await probe.valueErrors('object', [
            {'foo': 123},
            {'bar': 456},
          ]),
          [
            probe.variableError(
              '$wrongObject[{ foo: 123 }, { bar: 456 }].',
            ),
          ],
        );
      });

      test(
        'returns error when a nested input object is supplied with an array',
        () async {
          expect(
            await probe.valueErrors('object', {
              'foo': 123,
              'nested': [
                {'foo': 123},
                {'bar': 456},
              ],
            }),
            [
              probe.variableError(
                '$wrongObject[{ foo: 123 }, { bar: 456 }].',
                '.nested',
              ),
            ],
          );
        },
      );

      test('returns error for a misspelled field', () async {
        expect(await probe.valueErrors('object', {'foo': 123, 'bart': 123}), [
          probe.variableError(
            '$unknown "bart". Did you mean "bar"? Found: { foo: 123, bart: 123 }.',
          ),
        ]);
      });

      test('returns error for a misspelled field (no suggestions)', () async {
        expect(
          await probe.valueErrors(
            'object',
            {'foo': 123, 'bart': 123},
            isShowingSuggestions: false,
          ),
          [
            probe.variableError(
              '$unknown "bart", found: { foo: 123, bart: 123 }.',
            ),
          ],
        );
      });
    });

    group('for GraphQLInputObject with default value', () {
      test('no error for no errors for valid input value', () async {
        expect(await probe.valueErrors('sevenDefault', {'foo': 5}), isEmpty);
      });

      test('no error for object with default value', () async {
        expect(
          await probe.valueErrors('sevenDefault', <String, Object?>{}),
          isEmpty,
        );
      });
    });

    group('for GraphQLInputObject that isOneOf', () {
      test('no error for a valid input', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'foo': 123}), isEmpty);
      });

      test('returns error if more than one field is specified', () async {
        expect(
          await oneOfProbe.valueErrors('oneOf', {'foo': 123, 'bar': null}),
          [oneOfProbe.variableError(badOneOf)],
        );
      });

      test('does not count undefined keys as provided', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'foo': 123}), isEmpty);
      });

      test('returns error if the one field is null', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'bar': null}), [
          oneOfProbe.variableError(badOneOf, '.bar'),
        ]);
      });

      test('returns error for an invalid field', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'foo': 1.5}), [
          oneOfProbe.variableError(
            'Int cannot represent non-integer value: 1.5',
            '.foo',
          ),
        ]);
      });

      test('returns multiple errors for multiple invalid fields', () async {
        expect(
          await oneOfProbe.valueErrors('oneOf', {'foo': 'abc', 'bar': 'def'}),
          [
            oneOfProbe.variableError(
              'Int cannot represent non-integer value: "abc"',
              '.foo',
            ),
            oneOfProbe.variableError(
              'Int cannot represent non-integer value: "def"',
              '.bar',
            ),
            oneOfProbe.variableError(badOneOf),
          ],
        );
      });

      test('returns error for an unknown field', () async {
        expect(
          await oneOfProbe.valueErrors('oneOf', {
            'foo': 123,
            'unknownField': 123,
          }),
          [
            oneOfProbe.variableError(
              '$unknown "unknownField", found: { foo: 123, unknownField: 123 }.',
            ),
          ],
        );
      });

      test('returns error for a misspelled field', () async {
        expect(await oneOfProbe.valueErrors('oneOf', {'bart': 123}), [
          oneOfProbe.variableError(
            '$unknown "bart". Did you mean "bar"? Found: { bart: 123 }.',
          ),
          oneOfProbe.variableError(badOneOf),
        ]);
      });

      test('returns error for a misspelled field (no suggestions)', () async {
        expect(
          await oneOfProbe.valueErrors(
            'oneOf',
            {'bart': 123},
            isShowingSuggestions: false,
          ),
          [
            oneOfProbe.variableError(
              '$unknown "bart", found: { bart: 123 }.',
            ),
            oneOfProbe.variableError(badOneOf),
          ],
        );
      });
    });

    group('for GraphQLList', () {
      test('returns no error for a valid input', () async {
        expect(await probe.valueErrors('list', [1, 2, 3]), isEmpty);
      });

      test('returns an error for an invalid input', () async {
        expect(await probe.valueErrors('list', [1, 'b', true, 4]), [
          probe.variableError(
            'Int cannot represent non-integer value: "b"',
            '[1]',
          ),
          probe.variableError(
            'Int cannot represent non-integer value: true',
            '[2]',
          ),
        ]);
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.valueErrors('list', 42), isEmpty);
      });

      test('returns an error for a non-list invalid value', () async {
        expect(await probe.valueErrors('list', 'INVALID'), [
          probe.variableError(
            'Int cannot represent non-integer value: "INVALID"',
          ),
        ]);
      });

      test('no error for null for a null value', () async {
        expect(await probe.valueErrors('list', null), isEmpty);
      });
    });

    group('for nested GraphQLList', () {
      test('no error for a valid input', () async {
        expect(
          await probe.valueErrors('nestedList', [
            [1],
            [2, 3],
          ]),
          isEmpty,
        );
      });

      test('no error for a list for a non-list value', () async {
        expect(await probe.valueErrors('nestedList', 42), isEmpty);
      });

      test('no error for null for a null value', () async {
        expect(await probe.valueErrors('nestedList', null), isEmpty);
      });

      test('no error for nested lists for nested non-list values', () async {
        expect(await probe.valueErrors('nestedList', [1, 2, 3]), isEmpty);
      });

      test('no error for nested null for nested null values', () async {
        expect(
          await probe.valueErrors('nestedList', [
            42,
            [null],
            null,
          ]),
          isEmpty,
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/variables_lists_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/variables_schema.dart';

// Ported from graphql-js src/execution/__tests__/variables-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  final fixture = VariablesSchema();
  final run = fixture.execute;

  Map<String, Object?> invalidVariable(String where, String message) => {
    'errors': [
      {
        'message': 'Variable "\$input" has invalid value$where: $message',
        'locations': [
          {'line': 2, 'column': 16},
        ],
      },
    ],
  };

  group('Execute: Handles inputs', () {
    group('Handles lists and nullability', () {
      const listDoc = r'''
        query ($input: [String]) {
          list(input: $input)
        }
      ''';
      const nnListDoc = r'''

        query ($input: [String]!) {
          nnList(input: $input)
        }
      ''';
      const listNNDoc = r'''

        query ($input: [String!]) {
          listNN(input: $input)
        }
      ''';
      const nnListNNDoc = r'''

        query ($input: [String!]!) {
          nnListNN(input: $input)
        }
      ''';

      test('allows lists to be null', () async {
        final result = await run(listDoc, variables: {'input': null});

        expect(result, {
          'data': {'list': 'null'},
        });
      });

      test('allows lists to contain values', () async {
        final result = await run(
          listDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'list': '["A"]'},
        });
      });

      test('allows lists to contain null', () async {
        final result = await run(
          listDoc,
          variables: {
            'input': ['A', null, 'B'],
          },
        );

        expect(result, {
          'data': {'list': '["A", null, "B"]'},
        });
      });

      test('does not allow non-null lists to be null', () async {
        final result = await run(nnListDoc, variables: {'input': null});

        expect(
          result,
          invalidVariable(
            '',
            'Expected value of non-null type "[String]!" not to be null.',
          ),
        );
      });

      test('allows non-null lists to contain values', () async {
        final result = await run(
          nnListDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'nnList': '["A"]'},
        });
      });

      test('allows non-null lists to contain null', () async {
        final result = await run(
          nnListDoc,
          variables: {
            'input': ['A', null, 'B'],
          },
        );

        expect(result, {
          'data': {'nnList': '["A", null, "B"]'},
        });
      });

      test('allows lists of non-nulls to be null', () async {
        final result = await run(listNNDoc, variables: {'input': null});

        expect(result, {
          'data': {'listNN': 'null'},
        });
      });

      test('allows lists of non-nulls to contain values', () async {
        final result = await run(
          listNNDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'listNN': '["A"]'},
        });
      });

      test('does not allow lists of non-nulls to contain null', () async {
        final result = await run(
          listNNDoc,
          variables: {
            'input': ['A', null, 'B'],
          },
        );

        expect(
          result,
          invalidVariable(
            ' at [1]',
            'Expected value of non-null type "String!" not to be null.',
          ),
        );
      });

      test('does not allow non-null lists of non-nulls to be null', () async {
        final result = await run(nnListNNDoc, variables: {'input': null});

        expect(
          result,
          invalidVariable(
            '',
            'Expected value of non-null type "[String!]!" not to be null.',
          ),
        );
      });

      test('allows non-null lists of non-nulls to contain values', () async {
        final result = await run(
          nnListNNDoc,
          variables: {
            'input': ['A'],
          },
        );

        expect(result, {
          'data': {'nnListNN': '["A"]'},
        });
      });

      test(
        'does not allow non-null lists of non-nulls to contain null',
        () async {
          final result = await run(
            nnListNNDoc,
            variables: {
              'input': ['A', null, 'B'],
            },
          );

          expect(
            result,
            invalidVariable(
              ' at [1]',
              'Expected value of non-null type "String!" not to be null.',
            ),
          );
        },
      );

      test('does not allow invalid types to be used as values', () async {
        final result = await run(
          r'''

        query ($input: TestType!) {
          fieldWithObjectInput(input: $input)
        }
      ''',
          variables: {
            'input': {
              'list': ['A', 'B'],
            },
          },
        );

        expect(result, {
          'errors': [
            {
              'message': r'Variable "$input" expected value of type "TestType!" which cannot be used as an input type.',
              'locations': [
                {'line': 2, 'column': 24},
              ],
            },
          ],
        });
      });

      test('does not allow unknown types to be used as values', () async {
        final result = await run(
          r'''

        query ($input: UnknownType!) {
          fieldWithObjectInput(input: $input)
        }
      ''',
          variables: {'input': 'WhoKnows'},
        );

        expect(result, {
          'errors': [
            {
              'message': r'Variable "$input" expected value of type "UnknownType!" which cannot be used as an input type.',
              'locations': [
                {'line': 2, 'column': 24},
              ],
            },
          ],
        });
      });
    });

    group('Execute: Uses argument default values', () {
      test('when no argument provided', () async {
        final result = await run('{ fieldWithDefaultArgumentValue }');

        expect(result, {
          'data': {'fieldWithDefaultArgumentValue': '"Hello World"'},
        });
      });

      test('when omitted variable provided', () async {
        final result = await run(r'''
        query ($optional: String) {
          fieldWithDefaultArgumentValue(input: $optional)
        }
      ''');

        expect(result, {
          'data': {'fieldWithDefaultArgumentValue': '"Hello World"'},
        });
      });

      test('not when argument cannot be coerced', () async {
        final result = await run('''

        {
          fieldWithDefaultArgumentValue(input: WRONG_TYPE)
        }
      ''');

        expect(result, {
          'data': {'fieldWithDefaultArgumentValue': null},
          'errors': [
            {
              'message': 'Argument "TestType.fieldWithDefaultArgumentValue(input:)" has invalid value: String cannot represent a non string value: WRONG_TYPE',
              'locations': [
                {'line': 3, 'column': 48},
              ],
              'path': ['fieldWithDefaultArgumentValue'],
            },
          ],
        });
      });

      test(
        'when no runtime value is provided to a non-null argument',
        () async {
          final result = await run(r'''
        query optionalVariable($optional: String) {
          fieldWithNonNullableStringInputAndDefaultArgumentValue(input: $optional)
        }
      ''');

          expect(result, {
            'data': {
              'fieldWithNonNullableStringInputAndDefaultArgumentValue':
                  '"Hello World"',
            },
          });
        },
      );

      test('does not expose prototype argument names when omitted', () async {
        final result = await run('''
        {
          fieldWithPrototypeNamedArgument
        }
      ''');

        expect(result, {
          'data': {'fieldWithPrototypeNamedArgument': 'missing'},
        });
      });
    });

    group('getVariableValues: limit maximum number of coercion errors', () {
      const doc = r'''

      query ($input: [String!]) {
        listNN(input: $input)
      }
    ''';
      const input = {
        'input': [0, 1, 2],
      };

      Map<String, Object?> invalidValueError(int value, int index) => {
        'message':
            'Variable "\$input" has invalid value at [$index]: String cannot represent a non string value: $value',
        'locations': [
          {'line': 2, 'column': 14},
        ],
      };

      test('return all errors by default', () async {
        final result = await run(doc, variables: input);

        expect(result, {
          'errors': [
            invalidValueError(0, 0),
            invalidValueError(1, 1),
            invalidValueError(2, 2),
          ],
        });
      });

      test('when maxErrors is equal to number of errors', () async {
        final result = await run(
          doc,
          variables: input,
          options: const ExecutionOptions(
            maskErrors: false,
            maxCoercionErrors: 3,
          ),
        );

        expect(result, {
          'errors': [
            invalidValueError(0, 0),
            invalidValueError(1, 1),
            invalidValueError(2, 2),
          ],
        });
      });

      test('when maxErrors is less than number of errors', () async {
        final result = await run(
          doc,
          variables: input,
          options: const ExecutionOptions(
            maskErrors: false,
            maxCoercionErrors: 2,
          ),
        );

        expect(result, {
          'errors': [
            invalidValueError(0, 0),
            invalidValueError(1, 1),
            {
              'message': 'Too many errors processing variables, error limit reached. Execution aborted.',
            },
          ],
        });
      });
    });

    group('getVariableValues: own-property names', () {
      const doc = r'''
      query ($toString: String) {
        fieldWithNullableStringInput(input: $toString)
      }
    ''';

      test('does not expose prototype variable names when omitted', () async {
        final result = await run(doc, variables: {});

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });

      test(
        'still returns provided variables with colliding names',
        () async {
          final result = await run(doc, variables: {'toString': 'value'});

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"value"'},
          });
        },
      );
    });

    group('getVariableValues: explicit undefined values', () {
      test('treats explicit undefined values as omitted', () async {
        final result = await run(r'''
      query ($input: String) {
        fieldWithNullableStringInput(input: $input)
      }
    ''', variables: {});

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/variables_objects_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/variables_schema.dart';

// Ported from graphql-js src/execution/__tests__/variables-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  final fixture = VariablesSchema();
  final run = fixture.execute;

  group('Execute: Handles inputs', () {
    group('Handles objects and nullability', () {
      group('using inline structs', () {
        test('executes with complex input', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {a: "foo", b: ["bar"], c: "baz"})
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('properly parses single value to list', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {a: "foo", b: "bar", c: "baz"})
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('properly parses null value to null', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {a: null, b: null, c: "C", d: null})
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: null, b: null, c: "C", d: null }',
            },
          });
        });

        test('properly parses null value in list', () async {
          final result = await run('''
          {
            fieldWithObjectInput(input: {b: ["A",null,"C"], c: "C"})
          }
        ''');

          expect(result, {
            'data': {'fieldWithObjectInput': '{ b: ["A", null, "C"], c: "C" }'},
          });
        });

        test('does not use incorrect value', () async {
          final result = await run('''

          {
            fieldWithObjectInput(input: ["foo", "bar", "baz"])
          }
        ''');

          expect(result, {
            'data': {'fieldWithObjectInput': null},
            'errors': [
              {
                'message': 'Argument "TestType.fieldWithObjectInput(input:)" has invalid value: Expected value of type "TestInputObject" to be an object, found: ["foo", "bar", "baz"].',
                'path': ['fieldWithObjectInput'],
                'locations': [
                  {'line': 3, 'column': 41},
                ],
              },
            ],
          });
        });

        test(
          'properly runs coerceInputLiteral on complex scalar types',
          () async {
            final result = await run('''
          {
            fieldWithObjectInput(input: {c: "foo", d: "ExternalValue"})
          }
        ''');

            expect(result, {
              'data': {
                'fieldWithObjectInput': '{ c: "foo", d: "InternalValue" }',
              },
            });
          },
        );

        test('errors on faulty scalar type input', () async {
          final result = await run('''

          {
            fieldWithObjectInput(input: {c: "foo", e: "bar"})
          }
        ''');

          expect(result, {
            'data': {'fieldWithObjectInput': null},
            'errors': [
              {
                'message': 'Argument "TestType.fieldWithObjectInput(input:)" has invalid value at .e: FaultyScalarErrorMessage',
                'path': ['fieldWithObjectInput'],
                'locations': [
                  {'line': 3, 'column': 41},
                ],
              },
            ],
          });
        });
      });

      group('using variables', () {
        const doc = r'''

        query ($input: TestInputObject) {
          fieldWithObjectInput(input: $input)
        }
      ''';

        test('executes with complex input', () async {
          final result = await run(
            doc,
            variables: {
              'input': {
                'a': 'foo',
                'b': ['bar'],
                'c': 'baz',
              },
            },
          );

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('uses undefined when variable not provided', () async {
          final result = await run(r'''
          query q($input: String) {
            fieldWithNullableStringInput(input: $input)
          }''', variables: {});

          expect(result, {
            'data': {'fieldWithNullableStringInput': null},
          });
        });

        test('uses null when variable provided explicit null value', () async {
          final result = await run(
            r'''
          query q($input: String) {
            fieldWithNullableStringInput(input: $input)
          }''',
            variables: {'input': null},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        });

        test(
          'preserves explicit null variables within input object literals',
          () async {
            final result = await run(
              r'''
          query q($input: String) {
            fieldWithObjectInput(input: { a: $input, c: "baz" })
          }''',
              variables: {'input': null},
            );

            expect(result, {
              'data': {'fieldWithObjectInput': '{ a: null, c: "baz" }'},
            });
          },
        );

        test(
          'treats explicitly undefined variable values as omitted',
          () async {
            final result = await run(r'''
          query q($input: String = "Default value") {
            fieldWithNullableStringInput(input: $input)
          }''', variables: {});

            expect(result, {
              'data': {'fieldWithNullableStringInput': '"Default value"'},
            });
          },
        );

        test('uses default value when not provided', () async {
          final result = await run(r'''
          query ($input: TestInputObject = {a: "foo", b: ["bar"], c: "baz"}) {
            fieldWithObjectInput(input: $input)
          }
        ''');

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test(
          'reports invalid default values with variable definition locations',
          () async {
            final result = await run(
              r'query ($input: String = 123) { fieldWithNullableStringInput(input: $input) }',
            );

            expect(result, {
              'errors': [
                {
                  'message': r'Variable "$input" has invalid default value: String cannot represent a non string value: 123',
                  'locations': [
                    {'line': 1, 'column': 8},
                  ],
                },
              ],
            });
          },
        );

        test('includes suggestions for invalid default values', () async {
          final result = await run(
            r'query ($input: TestInputObject = { c: "ok", aa: "x" }) { fieldWithObjectInput(input: $input) }',
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid default value: Expected value of type "TestInputObject" not to include unknown field "aa". Did you mean "a"? Found: { c: "ok", aa: "x" }.',
                'locations': [
                  {'line': 1, 'column': 8},
                ],
              },
            ],
          });
        });

        test(
          'hides suggestions for invalid default values when specified',
          () async {
            final result = await run(
              r'query ($input: TestInputObject = { c: "ok", aa: "x" }) { fieldWithObjectInput(input: $input) }',
              options: const ExecutionOptions(
                maskErrors: false,
                includesSuggestions: false,
              ),
            );

            expect(result, {
              'errors': [
                {
                  'message': r'Variable "$input" has invalid default value: Expected value of type "TestInputObject" not to include unknown field "aa", found: { c: "ok", aa: "x" }.',
                  'locations': [
                    {'line': 1, 'column': 8},
                  ],
                },
              ],
            });
          },
        );

        test('does not use default value when provided', () async {
          final result = await run(
            r'''
            query q($input: String = "Default value") {
              fieldWithNullableStringInput(input: $input)
            }
          ''',
            variables: {'input': 'Variable value'},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"Variable value"'},
          });
        });

        test('uses explicit null value instead of default value', () async {
          final result = await run(
            r'''
          query q($input: String = "Default value") {
            fieldWithNullableStringInput(input: $input)
          }''',
            variables: {'input': null},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        });

        test('uses null default value when not provided', () async {
          final result = await run(r'''
          query q($input: String = null) {
            fieldWithNullableStringInput(input: $input)
          }''', variables: {});

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        });

        test('properly parses single value to list', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar', 'c': 'baz'},
            },
          );

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ a: "foo", b: ["bar"], c: "baz" }',
            },
          });
        });

        test('executes with complex scalar input', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'c': 'foo', 'd': 'ExternalValue'},
            },
          );

          expect(result, {
            'data': {
              'fieldWithObjectInput': '{ c: "foo", d: "InternalValue" }',
            },
          });
        });

        test('errors on faulty scalar type input', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'c': 'foo', 'e': 'ExternalValue'},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value at .e: FaultyScalarErrorMessage',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on null for nested non-null', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar', 'c': null},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value at .c: Expected value of non-null type "String!" not to be null.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on incorrect type', () async {
          final result = await run(
            doc,
            variables: {'input': 'foo bar'},
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestInputObject" to be an object, found: "foo bar".',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on omission of nested non-null', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar'},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestInputObject" to include required field "c", found: { a: "foo", b: "bar" }.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });

        test('errors on deep nested errors and with many errors', () async {
          final result = await run(
            r'''

          query ($input: TestNestedInputObject) {
            fieldWithNestedObjectInput(input: $input)
          }
        ''',
            variables: {
              'input': {
                'na': {'a': 'foo'},
              },
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value at .na: Expected value of type "TestInputObject" to include required field "c", found: { a: "foo" }.',
                'locations': [
                  {'line': 2, 'column': 18},
                ],
              },
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestNestedInputObject" to include required field "nb", found: { na: { a: "foo" } }.',
                'locations': [
                  {'line': 2, 'column': 18},
                ],
              },
            ],
          });
        });

        test('errors on addition of unknown input field', () async {
          final result = await run(
            doc,
            variables: {
              'input': {'a': 'foo', 'b': 'bar', 'c': 'baz', 'extra': 'dog'},
            },
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$input" has invalid value: Expected value of type "TestInputObject" not to include unknown field "extra", found: { a: "foo", b: "bar", c: "baz", extra: "dog" }.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        });
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/variables_scalars_test.dart`:

```dart
import 'package:test/test.dart';

import '../support/variables_schema.dart';

// Ported from graphql-js src/execution/__tests__/variables-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  final fixture = VariablesSchema();
  final run = fixture.execute;

  group('Execute: Handles inputs', () {
    group('Handles custom enum values', () {
      test('allows custom enum values as inputs', () async {
        final result = await run('''
        {
          null: fieldWithEnumInput(input: NULL)
          NaN: fieldWithEnumInput(input: NAN)
          false: fieldWithEnumInput(input: FALSE)
          customValue: fieldWithEnumInput(input: CUSTOM)
          defaultValue: fieldWithEnumInput(input: DEFAULT_VALUE)
        }
      ''');

        expect(result, {
          'data': {
            'null': 'null',
            'NaN': 'NaN',
            'false': 'false',
            'customValue': '"custom value"',
            'defaultValue': '"DEFAULT_VALUE"',
          },
        });
      });

      test(
        'allows non-nullable inputs to have null as enum custom value',
        () async {
          final result = await run('''
        {
          fieldWithNonNullableEnumInput(input: NULL)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableEnumInput': 'null'},
          });
        },
      );
    });

    group('Handles nullable scalars', () {
      test('allows nullable inputs to be omitted', () async {
        final result = await run('''
        {
          fieldWithNullableStringInput
        }
      ''');

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });

      test('allows nullable inputs to be omitted in a variable', () async {
        final result = await run(r'''
        query ($value: String) {
          fieldWithNullableStringInput(input: $value)
        }
      ''');

        expect(result, {
          'data': {'fieldWithNullableStringInput': null},
        });
      });

      test(
        'allows nullable inputs to be omitted in an unlisted variable',
        () async {
          final result = await run(r'''
        query {
          fieldWithNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNullableStringInput': null},
          });
        },
      );

      test(
        'allows nullable inputs to be set to null in a variable',
        () async {
          final result = await run(
            r'''
        query ($value: String) {
          fieldWithNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': null},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': 'null'},
          });
        },
      );

      test(
        'allows nullable inputs to be set to a value in a variable',
        () async {
          final result = await run(
            r'''
        query ($value: String) {
          fieldWithNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': 'a'},
          );

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"a"'},
          });
        },
      );

      test('allows nullable inputs to be set to a value directly', () async {
        final result = await run('''
        {
          fieldWithNullableStringInput(input: "a")
        }
      ''');

        expect(result, {
          'data': {'fieldWithNullableStringInput': '"a"'},
        });
      });
    });

    group('Handles non-nullable scalars', () {
      test(
        'allows non-nullable variable to be omitted given a default',
        () async {
          final result = await run(r'''
        query ($value: String! = "default") {
          fieldWithNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNullableStringInput': '"default"'},
          });
        },
      );

      test(
        'allows non-nullable inputs to be omitted given a default',
        () async {
          final result = await run(r'''
        query ($value: String = "default") {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': '"default"'},
          });
        },
      );

      test(
        'does not allow non-nullable inputs to be omitted in a variable',
        () async {
          final result = await run(r'''

        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''');

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$value" has invalid value: Expected a value of non-null type "String!" to be provided.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        },
      );

      test(
        'does not allow non-nullable inputs to be set to null in a variable',
        () async {
          final result = await run(
            r'''

        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': null},
          );

          expect(result, {
            'errors': [
              {
                'message': r'Variable "$value" has invalid value: Expected value of non-null type "String!" not to be null.',
                'locations': [
                  {'line': 2, 'column': 16},
                ],
              },
            ],
          });
        },
      );

      test(
        'allows non-nullable inputs to be set to a value in a variable',
        () async {
          final result = await run(
            r'''
        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''',
            variables: {'value': 'a'},
          );

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': '"a"'},
          });
        },
      );

      test(
        'allows non-nullable inputs to be set to a value directly',
        () async {
          final result = await run('''
        {
          fieldWithNonNullableStringInput(input: "a")
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': '"a"'},
          });
        },
      );

      test('reports error for missing non-nullable inputs', () async {
        final result = await run('{ fieldWithNonNullableStringInput }');

        expect(result, {
          'data': {'fieldWithNonNullableStringInput': null},
          'errors': [
            {
              'message': 'Argument "TestType.fieldWithNonNullableStringInput(input:)" of required type "String!" was not provided.',
              'locations': [
                {'line': 1, 'column': 3},
              ],
              'path': ['fieldWithNonNullableStringInput'],
            },
          ],
        });
      });

      test('reports error for array passed into string input', () async {
        final result = await run(
          r'''

        query ($value: String!) {
          fieldWithNonNullableStringInput(input: $value)
        }
      ''',
          variables: {
            'value': [1, 2, 3],
          },
        );

        expect(result, {
          'errors': [
            {
              'message': r'Variable "$value" has invalid value: String cannot represent a non string value: [1, 2, 3]',
              'locations': [
                {'line': 2, 'column': 16},
              ],
            },
          ],
        });
      });

      test(
        'reports error for non-provided variables for non-nullable inputs',
        () async {
          // Note: this test would typically fail validation before
          // encountering this execution error, however for queries which
          // previously validated and are being run against a new schema which
          // have introduced a breaking change to make a formerly non-required
          // argument required, this asserts failure before allowing the
          // underlying code to receive a non-null value.
          final result = await run(r'''

        {
          fieldWithNonNullableStringInput(input: $foo)
        }
      ''');

          expect(result, {
            'data': {'fieldWithNonNullableStringInput': null},
            'errors': [
              {
                'message': r'Argument "TestType.fieldWithNonNullableStringInput(input:)" has invalid value: Expected variable "$foo" provided to type "String!" to provide a runtime value.',
                'locations': [
                  {'line': 3, 'column': 50},
                ],
                'path': ['fieldWithNonNullableStringInput'],
              },
            ],
          });
        },
      );
    });

    // Note: the below is non-specified custom graphql-js behavior.
    group('Handles custom scalars with embedded variables', () {
      test('allows custom scalars', () async {
        final result = await run('''
        {
          fieldWithJSONScalarInput(input: { a: "foo", b: ["bar"], c: "baz" })
        }
      ''');

        expect(result, {
          'data': {
            'fieldWithJSONScalarInput': '{ a: "foo", b: ["bar"], c: "baz" }',
          },
        });
      });

      test('allows custom scalars with non-embedded variables', () async {
        final result = await run(
          r'''
          query ($input: JSONScalar) {
            fieldWithJSONScalarInput(input: $input)
          }
        ''',
          variables: {
            'input': {
              'a': 'foo',
              'b': ['bar'],
              'c': 'baz',
            },
          },
        );

        expect(result, {
          'data': {
            'fieldWithJSONScalarInput': '{ a: "foo", b: ["bar"], c: "baz" }',
          },
        });
      });

      test('allows custom scalars with embedded operation variables', () async {
        final result = await run(
          r'''
          query ($input: String) {
            fieldWithJSONScalarInput(input: { a: $input, b: ["bar"], c: "baz" })
          }
        ''',
          variables: {'input': 'foo'},
        );

        expect(result, {
          'data': {
            'fieldWithJSONScalarInput': '{ a: "foo", b: ["bar"], c: "baz" }',
          },
        });
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/support/input_probe.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_port.dart';
import 'js_inspect.dart';

/// The `TestEnum` of graphql-js's input utility suites: `FOO` stands for the
/// JavaScript string `InternalFoo` and `BAR` for the number `123456789`.
enum ProbeEnum {
  /// `FOO`, whose JavaScript value is the string `InternalFoo`.
  foo('"InternalFoo"'),

  /// `BAR`, whose JavaScript value is the number `123456789`.
  bar('123456789');

  const ProbeEnum(this.shown);

  /// How `inspect` prints the JavaScript value.
  final String shown;

  @override
  String toString() => shown;
}

/// The `TestColor` of `coerceInput-test`: values that Dart enums cannot hold
/// (`null`, `NaN`) print as the JavaScript value would.
enum ProbeColor {
  /// `RED`, the number 1.
  red('1'),

  /// `GREEN`, the number 2.
  green('2'),

  /// `BLUE`, the number 3.
  blue('3'),

  /// `NULL`, whose value is `null`.
  nullValue('null'),

  /// `NAN`, whose value is `NaN`.
  nan('NaN'),

  /// `NO_CUSTOM_VALUE`, whose value is its name.
  noCustomValue('"NO_CUSTOM_VALUE"');

  const ProbeColor(this.shown);

  /// How `inspect` prints the JavaScript value.
  final String shown;

  @override
  String toString() => shown;
}

/// graphql-js's `TestScalar` of the input suites: it takes `{ value: x }` and
/// gives `x`; `{ error: "m" }` fails with `m` and a missing `value` fails.
final class ProbeScalarCodec implements ScalarCodec<JsonValue> {
  /// Creates the codec.
  const ProbeScalarCodec();

  /// The message of an object that has no `value`.
  static const String missingValue = 'TestScalar input has no value.';

  @override
  DecodeResult<JsonValue> decode(JsonValue json) => switch (json) {
    JsonObject(:final fields) => switch ((fields['error'], fields['value'])) {
      (JsonString(:final value), _) => DecodeFailure(value),
      (_, final JsonValue found) => DecodeSuccess(found),
      _ => const DecodeFailure(missingValue),
    },
    _ => const DecodeFailure(missingValue),
  };

  @override
  JsonValue encode(JsonValue value) => value;
}

/// A scalar that refuses every input, graphql-js's `ThrowScalar`.
final class RefusingScalarCodec implements ScalarCodec<JsonValue> {
  /// Creates the codec.
  const RefusingScalarCodec();

  @override
  DecodeResult<JsonValue> decode(JsonValue json) => const DecodeFailure('Test');

  @override
  JsonValue encode(JsonValue value) => value;
}

/// A schema whose query has one field per probed input type; each field
/// takes `input` and answers `inspect(input)`, or null when none was given.
/// This is how the ported `coerceInputValue` and `validateInputValue` suites
/// reach the coercion code: through [execute].
final class InputProbe {
  /// Builds the query type of [builder] from [fields]: a name, the type as
  /// written in a variable definition, and the input type.
  InputProbe(
    ExecutableSchemaBuilder<Object?> builder,
    List<(String, String, InputRef<Object?>)> fields,
  ) : _typeTexts = {for (final (name, text, _) in fields) name: text} {
    schema = builder.build(
      query: builder.object<Object?>(
        'Query',
        fields: (t) => [
          for (final (name, _, type) in fields) _field(builder, t, name, type),
        ],
      ),
    );
  }

  static const ExecutionPort _port = ExecutionPort();
  static const JsInspect _inspect = JsInspect();

  final Map<String, String> _typeTexts;

  /// The executable schema.
  late final ExecutableSchema<Object?> schema; // Set by the constructor body.

  FieldDef<Object?, Object?> _field(
    ExecutableSchemaBuilder<Object?> builder,
    FieldsBuilder<Object?, Object?> t,
    String name,
    InputRef<Object?> type,
  ) {
    final input = Arg.optional<Object?>('input', type);
    return t
        .field(name, builder.string.nullable, args: [input])
        .resolve(
          (_, args, context, info) => switch (args.get(input)) {
            Present(:final value) => _inspect(value),
            _ => null,
          },
        );
  }

  Future<Map<String, Object?>> _run(
    String query,
    Map<String, Object?>? variables,
    bool isShowingSuggestions,
  ) => _port.json(
    schema,
    query,
    variables: variables == null ? null : _port.variablesOf(variables),
    options: ExecutionOptions(
      maskErrors: false,
      includesSuggestions: isShowingSuggestions,
    ),
  );

  /// The message of every error of [response].
  List<String> messagesOf(Map<String, Object?> response) => [
    for (final error in (response['errors'] as List<Object?>? ?? const []))
      (error! as Map<String, Object?>)['message']! as String,
  ];

  String? _answer(Map<String, Object?> response, String field) {
    if (response['errors'] != null) {
      return null;
    }
    return (response['data']! as Map<String, Object?>)[field] as String?;
  }

  /// The variable response of [field] given [json] (nothing when
  /// [isOmitted]).
  Future<Map<String, Object?>> _valueResponse(
    String field,
    Object? json,
    bool isOmitted,
    bool isShowingSuggestions,
  ) => _run(
    'query (\$input: ${_typeTexts[field]}) { $field(input: \$input) }',
    isOmitted ? <String, Object?>{} : {'input': json},
    isShowingSuggestions,
  );

  /// `inspect` of what [field] received for the variable [json], or null when
  /// coercion failed (graphql-js's `undefined`).
  Future<String?> value(
    String field,
    Object? json, {
    bool isOmitted = false,
  }) async =>
      _answer(await _valueResponse(field, json, isOmitted, true), field);

  /// The errors of coercing the variable [json] for [field].
  Future<List<String>> valueErrors(
    String field,
    Object? json, {
    bool isOmitted = false,
    bool isShowingSuggestions = true,
  }) async => messagesOf(
    await _valueResponse(field, json, isOmitted, isShowingSuggestions),
  );

  Future<Map<String, Object?>> _literalResponse(
    String field,
    String literal,
    String definitions,
    Map<String, Object?>? variables,
    bool isShowingSuggestions,
  ) => _run(
    'query $definitions { $field(input: $literal) }',
    variables,
    isShowingSuggestions,
  );

  /// `inspect` of what [field] received for the [literal], or null when
  /// coercion failed. [definitions] is a variable definition list such as
  /// `($var: Int)`.
  Future<String?> literal(
    String field,
    String literal, {
    String definitions = '',
    Map<String, Object?> variables = const {},
  }) async => _answer(
    await _literalResponse(field, literal, definitions, variables, true),
    field,
  );

  /// The errors of coercing the [literal] for [field].
  Future<List<String>> literalErrors(
    String field,
    String literal, {
    String definitions = '',
    Map<String, Object?> variables = const {},
    bool isShowingSuggestions = true,
  }) async => messagesOf(
    await _literalResponse(
      field,
      literal,
      definitions,
      variables,
      isShowingSuggestions,
    ),
  );

  /// The message of a variable `$input` that has an invalid value at [path].
  String variableError(String message, [String path = '']) {
    final where = path.isEmpty ? '' : ' at $path';
    return 'Variable "\$input" has invalid value$where: $message';
  }

  /// The message of an argument `input` of [field] with an invalid value at
  /// [path].
  String argumentError(String field, String message, [String path = '']) {
    final where = path.isEmpty ? '' : ' at $path';
    return 'Argument "Query.$field(input:)" has invalid value$where: $message';
  }
}
```

Create `packages/typed_graphql_conformance/test/support/js_inspect.dart`:

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's `inspect` for the Dart values a coerced argument holds, as
/// the ported variable tests print them: strings JSON-quoted, `{ a: 1 }`,
/// `[1, 2]`, ten items at most, nesting cut at depth two. A [JsonValue] is
/// printed as the plain value it stands for and any other object with its
/// `toString`.
final class JsInspect {
  /// Creates the inspector; it keeps no state.
  const JsInspect();

  /// [value] as `inspect` prints it.
  String call(Object? value) => _format(value, 0);

  String _format(Object? value, int ancestors) => switch (value) {
    null || JsonNull() => 'null',
    final JsonValue json => _format(json.toJson(), ancestors),
    final String text => jsonEncode(text),
    final num number => _number(number),
    final List<Object?> items => _list(items, ancestors + 1),
    final Map<Object?, Object?> fields => _object(fields, ancestors + 1),
    _ => '$value',
  };

  String _number(num number) {
    final isWhole = number.isFinite && number == number.truncateToDouble();
    return isWhole && number.abs() < 1e21 ? '${number.toInt()}' : '$number';
  }

  String _list(List<Object?> items, int depth) {
    if (items.isEmpty) {
      return '[]';
    }
    if (depth > 2) {
      return '[Array]';
    }
    final shown = items.length < 10 ? items.length : 10;
    final remaining = items.length - shown;
    return '[${[
      for (var i = 0; i < shown; i++) _format(items[i], depth),
      if (remaining == 1) '... 1 more item',
      if (remaining > 1) '... $remaining more items',
    ].join(', ')}]';
  }

  String _object(Map<Object?, Object?> fields, int depth) {
    if (fields.isEmpty) {
      return '{}';
    }
    if (depth > 2) {
      return '[Object]';
    }
    return '{ ${[
      for (final MapEntry(:key, :value) in fields.entries) '$key: ${_format(value, depth)}',
    ].join(', ')} }';
  }
}
```

Create `packages/typed_graphql_conformance/test/support/variables_schema.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_port.dart';
import 'js_inspect.dart';

/// The values of graphql-js's `TestEnum`, which has JavaScript values that
/// Dart enums cannot hold (`null`, `NaN`, `false`): each prints as the
/// JavaScript value would.
enum TestEnumValue {
  /// `NULL`, whose JavaScript value is `null`.
  nullValue('null'),

  /// `NAN`, whose JavaScript value is `NaN`.
  nan('NaN'),

  /// `FALSE`, whose JavaScript value is `false`.
  falseValue('false'),

  /// `CUSTOM`, whose JavaScript value is the string `custom value`.
  custom('"custom value"'),

  /// `DEFAULT_VALUE`, which has no value of its own: its name is the value.
  defaultValue('"DEFAULT_VALUE"');

  const TestEnumValue(this.shown);

  /// How `inspect` prints the JavaScript value.
  final String shown;

  @override
  String toString() => shown;
}

/// Any JSON, the codec of graphql-js's `JSONScalar`.
final class JsonScalarCodec implements ScalarCodec<JsonValue> {
  /// Creates the codec.
  const JsonScalarCodec();

  @override
  DecodeResult<JsonValue> decode(JsonValue json) => DecodeSuccess(json);

  @override
  JsonValue encode(JsonValue value) => value;
}

/// graphql-js's `ComplexScalar`: only `ExternalValue` is a value, and it
/// becomes `InternalValue`.
final class ComplexScalarCodec implements ScalarCodec<String> {
  /// Creates the codec.
  const ComplexScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(value: 'ExternalValue') => const DecodeSuccess('InternalValue'),
    _ => const DecodeFailure('ComplexScalar must be ExternalValue'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}

/// graphql-js's `FaultyScalar`: every input is refused with one message.
final class FaultyScalarCodec implements ScalarCodec<String> {
  /// Creates the codec.
  const FaultyScalarCodec();

  @override
  DecodeResult<String> decode(JsonValue json) =>
      const DecodeFailure('FaultyScalarErrorMessage');

  @override
  JsonValue encode(String value) => JsonString(value);
}

/// The `TestType` schema of graphql-js's `variables-test.ts`: every field
/// answers `inspect(args.input)`, or null when `input` was not given.
final class VariablesSchema {
  /// Builds the schema.
  VariablesSchema() {
    final b = _builder;
    final complex = b.scalar<String>(
      'ComplexScalar',
      const ComplexScalarCodec(),
    );
    final faulty = b.scalar<String>('FaultyScalar', const FaultyScalarCodec());
    final json = b.scalar<JsonValue>('JSONScalar', const JsonScalarCodec());
    final testEnum = b.enumType<TestEnumValue>(
      'TestEnum',
      TestEnumValue.values,
      mapping: EnumValueMapping<TestEnumValue>(
        nameOf: (value) => switch (value) {
          TestEnumValue.nullValue => 'NULL',
          TestEnumValue.nan => 'NAN',
          TestEnumValue.falseValue => 'FALSE',
          TestEnumValue.custom => 'CUSTOM',
          TestEnumValue.defaultValue => 'DEFAULT_VALUE',
        },
      ),
    );
    final objectA = Arg.optional('a', b.string.nullable);
    final objectB = Arg.optional(
      'b',
      b.inputList(b.string.nullable).nullable,
    );
    final objectC = Arg('c', b.string);
    final objectD = Arg.optional('d', complex.nullable);
    final objectE = Arg.optional('e', faulty.nullable);
    final testInput = b.inputObject<Map<String, Object?>>(
      'TestInputObject',
      fields: () => [objectA, objectB, objectC, objectD, objectE],
      decode: (values) => {
        if (values.get(objectA) case Present(:final value)) 'a': value,
        if (values.get(objectB) case Present(:final value)) 'b': value,
        'c': values.get(objectC),
        if (values.get(objectD) case Present(:final value)) 'd': value,
        if (values.get(objectE) case Present(:final value)) 'e': value,
      },
    );
    final oneOfA = Arg.optional('a', b.string.nullable);
    final oneOfB = Arg.optional('b', b.string.nullable);
    final testOneOf = b.oneOfInputObject<Map<String, Object?>>(
      'TestOneOfInputObject',
      fields: () => [oneOfA, oneOfB],
      decode: (values) => {
        if (values.get(oneOfA) case Present(:final value)) 'a': value,
        if (values.get(oneOfB) case Present(:final value)) 'b': value,
      },
    );
    final nestedNa = Arg('na', testInput);
    final nestedNb = Arg('nb', b.string);
    final testNested = b.inputObject<Map<String, Object?>>(
      'TestNestedInputObject',
      fields: () => [nestedNa, nestedNb],
      decode: (values) => {
        'na': values.get(nestedNa),
        'nb': values.get(nestedNb),
      },
    );
    final nestedType = b.object<Object?>(
      'NestedType',
      fields: (t) => [echo(t, 'echo', b.string.nullable)],
    );
    final nonNullString = Arg('input', b.string);
    final prototypeArg = Arg.optional('toString', b.string.nullable);
    final defaulted = Arg(
      'input',
      b.string.nullable,
      defaultValue: 'Hello World',
    );
    final nonNullDefaulted = Arg(
      'input',
      b.string,
      defaultValue: 'Hello World',
    );
    final testType = b.object<Object?>(
      'TestType',
      fields: (t) => [
        echo(t, 'fieldWithEnumInput', testEnum.nullable),
        echo(t, 'fieldWithNonNullableEnumInput', testEnum),
        echo(t, 'fieldWithObjectInput', testInput.nullable),
        echo(t, 'fieldWithOneOfObjectInput', testOneOf.nullable),
        echo(t, 'fieldWithNullableStringInput', b.string.nullable),
        t
            .field(
              'fieldWithNonNullableStringInput',
              b.string.nullable,
              args: [nonNullString],
            )
            .resolve(
              (_, args, context, info) => inspect(args.get(nonNullString)),
            ),
        t
            .field(
              'fieldWithDefaultArgumentValue',
              b.string.nullable,
              args: [defaulted],
            )
            .resolve((_, args, context, info) => inspect(args.get(defaulted))),
        t
            .field(
              'fieldWithNonNullableStringInputAndDefaultArgumentValue',
              b.string.nullable,
              args: [nonNullDefaulted],
            )
            .resolve(
              (_, args, context, info) => inspect(args.get(nonNullDefaulted)),
            ),
        echo(t, 'fieldWithNestedInputObject', testNested.nullable),
        echo(t, 'fieldWithJSONScalarInput', json.nullable),
        t
            .field(
              'fieldWithPrototypeNamedArgument',
              b.string.nullable,
              args: [prototypeArg],
            )
            .resolve(
              (_, args, context, info) => switch (args.get(prototypeArg)) {
                Present(:final value) => inspect(value),
                _ => 'missing',
              },
            ),
        echo(t, 'list', b.inputList(b.string.nullable).nullable),
        t.field('nested', nestedType).pure((_) => Object()),
        echo(t, 'nnList', b.inputList(b.string.nullable)),
        echo(t, 'listNN', b.inputList(b.string).nullable),
        echo(t, 'nnListNN', b.inputList(b.string)),
      ],
    );
    schema = b.build(query: testType);
  }

  static const ExecutionPort _port = ExecutionPort();

  /// graphql-js's `inspect`, which the fields print their input with.
  static const JsInspect inspect = JsInspect();

  final ExecutableSchemaBuilder<Object?> _builder =
      ExecutableSchemaBuilder<Object?>();

  /// The executable schema.
  late final ExecutableSchema<Object?> schema;

  /// graphql-js's `executeSync` of [query] with [variables] (the object
  /// `jsonDecode` would give), as response JSON.
  Future<Map<String, Object?>> execute(
    String query, {
    Map<String, Object?>? variables,
    ExecutionOptions options = ExecutionPort.unmasked,
  }) => _port.json(
    schema,
    query,
    variables: variables == null ? null : _port.variablesOf(variables),
    options: options,
  );

  /// A field `name` with one optional argument `input` of [type], which
  /// answers `inspect(input)` or null when `input` was not given.
  FieldDef<Object?, Object?> echo(
    FieldsBuilder<Object?, Object?> t,
    String name,
    InputRef<Object?> type,
  ) {
    final input = Arg.optional<Object?>('input', type);
    return t
        .field(name, _builder.string.nullable, args: [input])
        .resolve(
          (_, args, context, info) => switch (args.get(input)) {
            Present(:final value) => inspect(value),
            _ => null,
          },
        );
  }
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -102,6 +102,10 @@ void main() {
         'execution/__tests__/resolve-test.ts',
         'execution/__tests__/schema-test.ts',
         'execution/__tests__/sync-test.ts',
+        'execution/__tests__/variables-test.ts',
+        'execution/__tests__/oneof-test.ts',
+        'utilities/__tests__/coerceInputValue-test.ts',
+        'utilities/__tests__/validateInputValue-test.ts',
       ],
     ),
     (
```

In `packages/typed_graphql_conformance/test/support/execution_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -44,6 +44,7 @@ final class ExecutionPort {
       source: Source(text),
       errorBehavior: options.errorBehavior,
       maskErrors: options.maskErrors,
+      includesSuggestions: options.includesSuggestions,
       onError: options.onError,
       maxCoercionErrors: options.maxCoercionErrors,
       maxDepth: options.maxDepth,
@@ -67,6 +68,14 @@ final class ExecutionPort {
     options: options,
   );
 
+  /// The request variables for [plain], the object `jsonDecode` would give
+  /// (maps, lists, strings, numbers, booleans and null).
+  JsonObject variablesOf(Map<String, Object?> plain) =>
+      switch (const JsonReader().read(plain)) {
+        DecodeSuccess(value: final JsonObject object) => object,
+        _ => throw ArgumentError.value(plain, 'plain', 'is not a JSON object'),
+      };
+
   /// The response of [run] as JSON, awaited.
   Future<Map<String, Object?>> json(
     ExecutableSchema<Object?> schema,
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -105,3 +105,281 @@ execution/__tests__/mutations-test.ts,Execute: Handles mutation execution orderi
 execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,Mutation fields with @defer do not block next mutation,skipped,,Incremental delivery of @defer patches is executeIncrementally (M14); execute runs @defer inline.
 execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,Mutation inside of a fragment,ported,test/execution/mutations_test.dart,
 execution/__tests__/mutations-test.ts,Execute: Handles mutation execution ordering,Mutation with @defer is not executed serially,skipped,,Incremental delivery of @defer patches is executeIncrementally (M14); execute runs @defer inline.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,executes with complex input,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,properly parses single value to list,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,properly parses null value to null,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,properly parses null value in list,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,does not use incorrect value,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,properly runs coerceInputLiteral on complex scalar types,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,errors on faulty scalar type input,adapted,test/execution/variables_objects_test.dart,"The error is located at the argument value, not at the field, and a codec failure carries no extensions code."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,executes with complex input,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses undefined when variable not provided,adapted,test/execution/variables_objects_test.dart,JSON has no undefined: the variable is left out of the map.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses null when variable provided explicit null value,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,preserves explicit null variables within input object literals,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,treats explicitly undefined variable values as omitted,adapted,test/execution/variables_objects_test.dart,JSON has no undefined: the variable is left out of the map.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses default value when not provided,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,reports invalid default values with variable definition locations,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,includes suggestions for invalid default values,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,hides suggestions for invalid default values when specified,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,does not use default value when provided,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses explicit null value instead of default value,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses null default value when not provided,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,properly parses single value to list,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,executes with complex scalar input,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,errors on faulty scalar type input,adapted,test/execution/variables_objects_test.dart,"A codec failure message is reported as it is, without a second graphql-js wrapper."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,errors on null for nested non-null,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,errors on incorrect type,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,errors on omission of nested non-null,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,errors on deep nested errors and with many errors,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,errors on addition of unknown input field,ported,test/execution/variables_objects_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom enum values,allows custom enum values as inputs,adapted,test/execution/variables_scalars_test.dart,"The values null, NaN and false are Dart enum values that print as the JavaScript value."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom enum values,allows non-nullable inputs to have null as enum custom value,adapted,test/execution/variables_scalars_test.dart,"The values null, NaN and false are Dart enum values that print as the JavaScript value."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles nullable scalars,allows nullable inputs to be omitted,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles nullable scalars,allows nullable inputs to be omitted in a variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles nullable scalars,allows nullable inputs to be omitted in an unlisted variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles nullable scalars,allows nullable inputs to be set to null in a variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles nullable scalars,allows nullable inputs to be set to a value in a variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles nullable scalars,allows nullable inputs to be set to a value directly,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,allows non-nullable variable to be omitted given a default,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,allows non-nullable inputs to be omitted given a default,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,does not allow non-nullable inputs to be omitted in a variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,does not allow non-nullable inputs to be set to null in a variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,allows non-nullable inputs to be set to a value in a variable,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,allows non-nullable inputs to be set to a value directly,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,reports error for missing non-nullable inputs,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,reports error for array passed into string input,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles non-nullable scalars,reports error for non-provided variables for non-nullable inputs,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom scalars with embedded variables,allows custom scalars,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom scalars with embedded variables,allows custom scalars with non-embedded variables,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom scalars with embedded variables,allows custom scalars with embedded operation variables,ported,test/execution/variables_scalars_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom scalars with embedded variables,allows custom scalars with embedded fragment variables,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles custom scalars with embedded variables,allows custom scalars with embedded nested fragment variables,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows lists to be null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows lists to contain values,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows lists to contain null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,does not allow non-null lists to be null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows non-null lists to contain values,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows non-null lists to contain null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows lists of non-nulls to be null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows lists of non-nulls to contain values,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,does not allow lists of non-nulls to contain null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,does not allow non-null lists of non-nulls to be null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,allows non-null lists of non-nulls to contain values,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,does not allow non-null lists of non-nulls to contain null,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,does not allow invalid types to be used as values,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles lists and nullability,does not allow unknown types to be used as values,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,when no argument provided,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,when omitted variable provided,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,not when argument cannot be coerced,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,when no runtime value is provided to a non-null argument,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,does not expose prototype argument names when omitted,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,localizes invalid default value errors during execution,skipped,,"An invalid default value is a GQL123 schema build error in the typed builder, so it cannot reach execution."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Execute: Uses argument default values,localizes nested invalid field default value errors during execution,skipped,,"An invalid default value is a GQL123 schema build error in the typed builder, so it cannot reach execution."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > getVariableValues: limit maximum number of coercion errors,return all errors by default,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > getVariableValues: limit maximum number of coercion errors,when maxErrors is equal to number of errors,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > getVariableValues: limit maximum number of coercion errors,when maxErrors is less than number of errors,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when there are no fragment arguments,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a value is required and provided,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a value is required and not provided,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when the definition has a default and is provided,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when the definition has a default and is not provided,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when the definition has an invalid default and is not provided,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,does not allow invalid types to be used as fragment variables,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,"when a definition has a default, is not provided, and spreads another fragment",skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when the definition has a non-nullable default and is provided null,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when the definition has no default and is not provided,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when an argument is shadowed by an operation variable,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a nullable argument without a field default is not provided and shadowed by an operation variable,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a nullable argument with a field default is not provided and shadowed by an operation variable,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a fragment-variable is shadowed by an intermediate fragment-spread but defined in the operation-variables,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a fragment is used with different args,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when the argument variable is nested in a complex type,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when argument variables are used recursively,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when argument variables with the same name are used directly and recursively,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when argument passed in as list,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when argument passed to a directive,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when argument passed to a directive on a nested field,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > using fragment arguments,when a nullable argument to a directive with a field default is not provided and shadowed by an operation variable,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/variables-test.ts,Execute: Handles inputs > getVariableValues: own-property names,does not expose prototype variable names when omitted,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > getVariableValues: own-property names,still returns provided variables with colliding names,ported,test/execution/variables_lists_test.dart,
+execution/__tests__/variables-test.ts,Execute: Handles inputs > getVariableValues: explicit undefined values,treats explicit undefined values as omitted,adapted,test/execution/variables_lists_test.dart,JSON has no undefined: the variable is left out of the map.
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,accepts a good default value,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,rejects a bad default value,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,accepts a good variable,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,accepts a good variable with an undefined key,adapted,test/execution/oneof_test.dart,JSON has no undefined: the key is left out.
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,rejects a variable with a nulled key,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,rejects a variable with multiple non-null keys,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,rejects a variable with multiple nullable keys,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,errors with nulled variable for field,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,errors with missing variable for field,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,errors with missing variable as an additional field,ported,test/execution/oneof_test.dart,
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,errors with nulled fragment variable for field,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+execution/__tests__/oneof-test.ts,Execute: Handles OneOf Input Objects > OneOf Input Objects,errors with missing fragment variable for field,skipped,,Fragment arguments are not implemented; the executor has no fragment variable definitions.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLNonNull,returns for a non-null value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLNonNull,invalid for undefined value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLNonNull,invalid for null value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLScalar,returns for valid input,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLScalar,returns for null result,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLScalar,returns for NaN result,skipped,,"JSON has no NaN, so the case cannot be written."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLScalar,invalid for undefined result,adapted,test/execution/coerce_input_value_test.dart,JSON has no undefined: a missing value is a codec failure.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLEnum,returns no error for a known enum name,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLEnum,invalid for misspelled enum value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLEnum,invalid for incorrect value type,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue,converts BigInt values for numeric scalars,skipped,,JSON has no BigInt.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,returns no error for a valid input,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid for a non-object type,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid for an invalid field,adapted,test/execution/coerce_input_value_test.dart,JSON has no NaN: the invalid field value is 1.5.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid for multiple invalid fields,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid for a missing required field,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid for an unknown field,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,ignores unknown fields with undefined values,adapted,test/execution/coerce_input_value_test.dart,JSON has no undefined: the key is left out.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid when supplied with an array,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject,invalid when a nested input object is supplied with an array,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,returns for valid input,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,invalid if more than one field is specified,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,invalid if the one field is null,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,invalid if an omitted field would be filled by a default,skipped,,"The builder refuses the schema (a OneOf field with a default, or a null default of a non-null type) when it is built, so the case cannot be run."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,invalid if an undefined field would be filled by a default,skipped,,"The builder refuses the schema (a OneOf field with a default, or a null default of a non-null type) when it is built, so the case cannot be run."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,invalid for an invalid field,adapted,test/execution/coerce_input_value_test.dart,JSON has no NaN: the invalid field value is 1.5.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject that isOneOf,invalid for an unknown field,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject with default value,returns no errors for valid input value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject with default value,returns object with default value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject with default value,returns null as value,skipped,,"A null default of a non-null scalar is refused when the schema is built (GQL123), and a nullable argument cannot have a null default (null means no default)."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject with default value,returns NaN as value,skipped,,"JSON has no NaN, so the case cannot be written."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLInputObject with default value,invalid when coercing an invalid field default throws,skipped,,"An invalid default value is a GQL123 build error in the typed builder, so it cannot reach execution."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,returns no error for a valid input,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,returns no error for a valid iterable input,skipped,,JSON has no iterables.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,invalid for an invalid input,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,returns a list for a non-list value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,returns a list for a non-list object value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,invalid for a non-list invalid value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for GraphQLList,returns null for a null value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for nested GraphQLList,returns no error for a valid input,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for nested GraphQLList,returns a list for a non-list value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for nested GraphQLList,returns null for a null value,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for nested GraphQLList,returns nested lists for nested non-list values,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputValue > for nested GraphQLList,returns nested null for nested null values,ported,test/execution/coerce_input_value_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,converts according to input coercion rules,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,does not convert when input coercion rules reject a value,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,convert using coerceInputLiteral from a custom scalar type,adapted,test/execution/coerce_input_literal_test.dart,"A ScalarCodec decodes JSON and has no coerceInputLiteral (R2.9): the pass-through scalar and the variable inside an object literal are checked with the JSON scalar, the throwing and undefined scalars with a refusing codec."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,converts enum values according to input coercion rules,adapted,test/execution/coerce_input_literal_test.dart,The values null and NaN are Dart enum values that print as the JavaScript value.
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,coerces to null unless non-null,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,coerces lists of values,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,coerces non-null lists of values,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,coerces lists of non-null values,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,coerces non-null lists of non-null values,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,uses default values for unprovided fields,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,invalid when coercing an invalid literal default throws,skipped,,"An invalid default value is a GQL123 build error in the typed builder, so it cannot reach execution."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,coerces input objects according to input coercion rules,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,accepts variable values assuming already coerced,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,asserts variables are provided as items in lists,adapted,test/execution/coerce_input_literal_test.dart,"A Boolean variable used where a list is expected is refused, where graphql-js passes the value through (the variable is assumed coerced)."
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,omits input object fields for unprovided variables,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,rejects multiple oneOf fields when one variable is unprovided,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,rejects oneOf field when variable is null,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceInputLiteral,preserves explicit null variables in input object fields,ported,test/execution/coerce_input_literal_test.dart,
+utilities/__tests__/coerceInputValue-test.ts,coerceDefaultValue,memoizes coercion,skipped,,"Default values are typed Dart values of the builder, coerced once when the schema is built; there is no coerceDefaultValue to memoise."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLNonNull,returns no error for non-null value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLNonNull,returns an error for undefined value,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLNonNull,returns an error for null value,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLScalar,returns no error for valid input,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLScalar,returns no error for null result,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLScalar,returns no error for NaN result,skipped,,"JSON has no NaN, so the case cannot be written."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLScalar,returns an error for undefined result,adapted,test/execution/validate_input_value_test.dart,"A codec failure message is reported as it is, without the graphql-js wrapper 'Expected value of type ""TestScalar"", ...'; the test checks the codec message. The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLEnum,returns no error for a known enum name,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLEnum,returns an error for unknown enum value,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLEnum,returns an error for misspelled enum value,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLEnum,returns an error for misspelled enum value (no suggestions),adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLEnum,returns an error for incorrect value type,adapted,test/execution/validate_input_value_test.dart,"The value of a JavaScript object with toJSON is not JSON, so that case is left out. The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLEnum,reports thrown non-error,skipped,,A codec returns a DecodeFailure; it cannot throw a non-error value.
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns no error for a valid input,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns an error for a non-object type,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns an error for an invalid field,adapted,test/execution/validate_input_value_test.dart,"JSON has no NaN: the invalid field value is 1.5. The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns multiple errors for multiple invalid fields,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns error for a missing required field,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns error for an unknown field,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,ignores unknown fields with undefined values,adapted,test/execution/validate_input_value_test.dart,JSON has no undefined: the key is left out.
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns error when supplied with an array,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns error when a nested input object is supplied with an array,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns error for a misspelled field,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject,returns error for a misspelled field (no suggestions),adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject with default value,no error for no errors for valid input value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject with default value,no error for object with default value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject with default value,no error for null as value,skipped,,A null default of a non-null scalar is refused when the schema is built (GQL123).
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject with default value,no error for NaN as value,skipped,,"JSON has no NaN, so the case cannot be written."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,no error for a valid input,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns error if more than one field is specified,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,does not count undefined keys as provided,adapted,test/execution/validate_input_value_test.dart,JSON has no undefined: the key is left out.
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns error if the one field is null,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns error for an invalid field,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns multiple errors for multiple invalid fields,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns error for an unknown field,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns error for a misspelled field,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLInputObject that isOneOf,returns error for a misspelled field (no suggestions),adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLList,returns no error for a valid input,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLList,returns no error for a valid iterable input,skipped,,JSON has no iterables.
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLList,returns an error for an invalid input,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLList,no error for a list for a non-list value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLList,returns an error for a non-list invalid value,adapted,test/execution/validate_input_value_test.dart,"The response carries one error per problem as a variable error with the path in the message (""Variable \""$input\"" has invalid value at <path>: <message>"") instead of (message, path) pairs; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for GraphQLList,no error for null for a null value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for nested GraphQLList,no error for a valid input,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for nested GraphQLList,no error for a list for a non-list value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for nested GraphQLList,no error for null for a null value,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for nested GraphQLList,no error for nested lists for nested non-list values,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputValue > for nested GraphQLList,no error for nested null for nested null values,ported,test/execution/validate_input_value_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral,ignores variables statically,skipped,,"Whether a variable fits its position is decided statically by the validation rules (VariablesInAllowedPosition), not by execution."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral,returns an error for null variables for non-nullable types,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLNonNull,returns no error for non-null value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLNonNull,returns an error for null value,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLScalar,returns no error for valid input,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLScalar,returns no error for null result,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLScalar,returns no error for NaN result,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLScalar,returns an error for undefined result,adapted,test/execution/validate_input_literal_test.dart,"A codec failure message is reported as it is, without the graphql-js wrapper 'Expected value of type ""TestScalar"", ...'; the test checks the codec message. The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLScalar,reports thrown non-error,skipped,,A codec returns a DecodeFailure; it cannot throw a non-error value.
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLEnum,returns no error for a known enum name,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLEnum,returns an error for unknown enum value,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLEnum,returns an error for misspelled enum value,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLEnum,returns an error for misspelled enum value (no suggestions),adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLEnum,returns an error for incorrect value type,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns no error for a valid input,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns an error for a non-object type,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns an error for an invalid field,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns multiple errors for multiple invalid fields,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's. An argument reports its first problem only, so a case with several errors checks the first."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns error for a missing required field,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns error for an unknown field,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,returns error for a misspelled field,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,"allows variables in an object, statically",adapted,test/execution/validate_input_literal_test.dart,Run with the variable provided: whether a variable fits is not decided statically by execution.
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,allows correct use of variables,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,allows missing variables in an nullable field,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,allows missing variables in an optional field,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,errors on missing variable in an required field,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject,errors on null variable in an non-null field,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject with default value,no error for no errors for valid input value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject with default value,no error for object with default value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject with default value,no error for null as value,skipped,,A null default of a non-null scalar is refused when the schema is built (GQL123).
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject with default value,no error for NaN as value,skipped,,"JSON has no NaN, so the case cannot be written."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns no error for a valid input,ported,test/execution/validate_input_literal_oneof_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns an error if more than one field is specified,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns an error if the one field is null,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns an error for a non-object type,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns an error for an invalid field,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns error for an unknown field,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns error for a misspelled field,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,"allows variables in an object, statically",adapted,test/execution/validate_input_literal_oneof_test.dart,Run with the variable provided: whether a variable fits is not decided statically by execution.
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,allows correct use of variables,ported,test/execution/validate_input_literal_oneof_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,returns error with variable provided a value of null,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,errors with missing variables as the additional field,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's. An argument reports its first problem only, so a case with several errors checks the first."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLInputObject that isOneOf,errors with multiple variables when one is missing,adapted,test/execution/validate_input_literal_oneof_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's. An argument reports its first problem only, so a case with several errors checks the first."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,returns no error for a valid input,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,returns an error for an invalid input,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's. An argument reports its first problem only, so a case with several errors checks the first."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,no error for a list for a non-list value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,returns an error for a non-list invalid value,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,no error for null for a null value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,"allows variables in a list, statically",adapted,test/execution/validate_input_literal_test.dart,Run with the variable provided: whether a variable fits is not decided statically by execution.
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,allows missing variables in a list (which coerce to null),ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,errors on missing variables in a list of non-null,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for GraphQLList,errors on null variables in a list of non-null,adapted,test/execution/validate_input_literal_test.dart,"The response carries the problem as an argument error (""Argument \""Query.f(input:)\"" has invalid value at <path>: <message>"") instead of a (message, path) pair; the message and the path are graphql-js's."
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for a valid input,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for a list for a non-list value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for null for a null value,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for nested lists for nested non-list values,ported,test/execution/validate_input_literal_test.dart,
+utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for nested null for nested null values,ported,test/execution/validate_input_literal_test.dart,
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/coerce_input_literal_test.dart test/execution/coerce_input_value_test.dart test/execution/oneof_test.dart test/execution/validate_input_literal_oneof_test.dart test/execution/validate_input_literal_test.dart test/execution/validate_input_value_test.dart test/execution/variables_lists_test.dart test/execution/variables_objects_test.dart test/execution/variables_scalars_test.dart test/mapping_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/coerce_input_literal_test.dart packages/typed_graphql_conformance/test/execution/coerce_input_value_test.dart packages/typed_graphql_conformance/test/execution/oneof_test.dart packages/typed_graphql_conformance/test/execution/validate_input_literal_oneof_test.dart packages/typed_graphql_conformance/test/execution/validate_input_literal_test.dart packages/typed_graphql_conformance/test/execution/validate_input_value_test.dart packages/typed_graphql_conformance/test/execution/variables_lists_test.dart packages/typed_graphql_conformance/test/execution/variables_objects_test.dart packages/typed_graphql_conformance/test/execution/variables_scalars_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/execution_port.dart packages/typed_graphql_conformance/test/support/input_probe.dart packages/typed_graphql_conformance/test/support/js_inspect.dart packages/typed_graphql_conformance/test/support/variables_schema.dart
git commit -q -m "test(typed_graphql_conformance): port the variable and input coercion suites" \
  -m "Ports variables-test, oneof-test, coerceInputValue-test and validateInputValue-test through execute, with one mapping row per test. No server bug was found beyond the two fixes already committed." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 13: Conformance: directives, abstract types and enums

Port `directives-test.ts`, `union-interface-test.ts`, `abstract-test.ts`, `collectFields-test.ts` and the execution tests of `enumType-test.ts`; introspection cases wait for M5c.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`
- Test: `packages/typed_graphql_conformance/test/execution/abstract_test.dart`, `packages/typed_graphql_conformance/test/execution/directives_test.dart`, `packages/typed_graphql_conformance/test/execution/enum_type_test.dart`, `packages/typed_graphql_conformance/test/execution/union_interface_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/execution_port.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/execution/abstract_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

class _Dog {
  _Dog(this.name, this.woofs);

  final String name;
  final bool woofs;
}

class _Cat {
  _Cat(this.name, this.meows);

  final String name;
  final bool meows;
}

typedef _Source = Map<String, Object?>;

const _petsQuery = '''

      {
        pets {
          name
          ... on Dog {
            woofs
          }
          ... on Cat {
            meows
          }
        }
      }
    ''';

const _petQuery = '''

      {
        pet {
          name
        }
      }
    ''';

const _unresolvedMessage =
    'Abstract type "Pet" must resolve to an Object type at runtime for field '
    '"Query.pet". Either the "Pet" type should provide a "resolveType" '
    'function or each possible type should provide an "isTypeOf" function.';

// Ported from graphql-js src/execution/__tests__/abstract-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final odieAndGarfield = <Map<String, Object?>>[
    {'name': 'Odie', 'woofs': true},
    {'name': 'Garfield', 'meows': false},
  ];
  final bothFailed = <String, Object?>{
    'data': {
      'pets': [null, null],
    },
    'errors': [
      for (final index in [0, 1])
        {
          'message': 'We are testing this error',
          'locations': [
            {'line': 3, 'column': 9},
          ],
          'path': ['pets', index],
        },
    ],
  };
  Map<String, Object?> petFailure(String message) => {
    'data': {'pet': null},
    'errors': [
      {
        'message': message,
        'locations': [
          {'line': 3, 'column': 9},
        ],
        'path': ['pet'],
      },
    ],
  };

  // Query.pets: [Pet] over a Dog and a Cat.
  ExecutableSchema<Object?> petsSchema(
    ExecutableSchemaBuilder<Object?> b,
    OutputRef<Object?> pet,
  ) => b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field('pets', b.list(pet.nullable).nullable)
            .pure(
              (_) => <Object>[_Dog('Odie', true), _Cat('Garfield', false)],
            ),
      ],
    ),
  );

  FieldDef<_Dog, Object?> dogName(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Dog, Object?> t,
  ) => t.field('name', b.string.nullable).pure((dog) => dog.name);

  FieldDef<_Cat, Object?> catName(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Cat, Object?> t,
  ) => t.field('name', b.string.nullable).pure((cat) => cat.name);

  List<FieldDef<_Dog, Object?>> dogFields(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Dog, Object?> t,
  ) => [
    dogName(b, t),
    t.field('woofs', b.boolean.nullable).pure((dog) => dog.woofs),
  ];

  List<FieldDef<_Cat, Object?>> catFields(
    ExecutableSchemaBuilder<Object?> b,
    FieldsBuilder<_Cat, Object?> t,
  ) => [
    catName(b, t),
    t.field('meows', b.boolean.nullable).pure((cat) => cat.meows),
  ];

  InterfaceTypeDef<Object?> petInterface(
    ExecutableSchemaBuilder<Object?> b, {
    ObjectTypeDef<Object?> Function(Object? value)? resolveType,
  }) => b.interface<Object?>(
    'Pet',
    resolveType: resolveType,
    fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
  );

  group('Execute: Handles execution of abstract types', () {
    test('isTypeOf used to resolve runtime type for Interface', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        options: ObjectOptions(isTypeOf: (value) => value is _Dog),
        fields: (t) => dogFields(b, t),
      );
      b.object<_Cat>(
        'Cat',
        interfaces: [pet],
        options: ObjectOptions(isTypeOf: (value) => value is _Cat),
        fields: (t) => catFields(b, t),
      );

      expect(await port.json(petsSchema(b, pet), _petsQuery), {
        'data': {'pets': odieAndGarfield},
      });
    });

    test('isTypeOf can throw', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        options: ObjectOptions(
          isTypeOf: (value) {
            throw const GraphQLException('We are testing this error');
          },
        ),
        fields: (t) => dogFields(b, t),
      );
      b.object<_Cat>(
        'Cat',
        interfaces: [pet],
        fields: (t) => catFields(b, t),
      );

      expect(await port.json(petsSchema(b, pet), _petsQuery), bothFailed);
    });

    test('isTypeOf can return false', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        options: ObjectOptions(isTypeOf: (value) => false),
        fields: (t) => dogFields(b, t),
      );
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [t.field('pet', pet.nullable).pure((_) => Object())],
        ),
      );

      expect(
        await port.json(schema, _petQuery),
        petFailure(_unresolvedMessage),
      );
    });

    test('isTypeOf used to resolve runtime type for Union', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final dog = b.object<_Dog>(
        'Dog',
        options: ObjectOptions(isTypeOf: (value) => value is _Dog),
        fields: (t) => dogFields(b, t),
      );
      final cat = b.object<_Cat>(
        'Cat',
        options: ObjectOptions(isTypeOf: (value) => value is _Cat),
        fields: (t) => catFields(b, t),
      );
      final pet = b.union<Object?>('Pet', members: [dog, cat]);

      expect(
        await port.json(petsSchema(b, pet), '''
{
      pets {
        ... on Dog {
          name
          woofs
        }
        ... on Cat {
          name
          meows
        }
      }
    }'''),
        {
          'data': {'pets': odieAndGarfield},
        },
      );
    });

    test('resolveType can throw', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(
        b,
        resolveType: (value) {
          throw const GraphQLException('We are testing this error');
        },
      );
      b.object<_Dog>(
        'Dog',
        interfaces: [pet],
        fields: (t) => dogFields(b, t),
      );
      b.object<_Cat>(
        'Cat',
        interfaces: [pet],
        fields: (t) => catFields(b, t),
      );

      expect(await port.json(petsSchema(b, pet), _petsQuery), bothFailed);
    });

    // The two __typename tests share their sources and differ in the type.
    ExecutableSchema<Object?> typenameSchema(
      ExecutableSchemaBuilder<Object?> b, {
      required bool isUnion,
    }) {
      late final ObjectTypeDef<_Source> cat;
      late final ObjectTypeDef<_Source> dog;
      ObjectTypeDef<Object?> pick(_Source m) =>
          m['__typename'] == 'Dog' ? dog : cat;
      void declareMembers(List<InterfaceTypeDef<Object?>> interfaces) {
        cat = b.object<_Source>(
          'Cat',
          interfaces: interfaces,
          fields: (t) => [
            t
                .field('name', b.string.nullable)
                .pure((m) => m['name'] as String?),
            t
                .field('meows', b.boolean.nullable)
                .pure((m) => m['meows'] as bool?),
          ],
        );
        dog = b.object<_Source>(
          'Dog',
          interfaces: interfaces,
          fields: (t) => [
            t
                .field('name', b.string.nullable)
                .pure((m) => m['name'] as String?),
            t
                .field('woofs', b.boolean.nullable)
                .pure((m) => m['woofs'] as bool?),
          ],
        );
      }

      final OutputRef<_Source> pet;
      if (isUnion) {
        declareMembers([]);
        pet = b.union<_Source>('Pet', members: [cat, dog], resolveType: pick);
      } else {
        final interface = b.interface<_Source>(
          'Pet',
          resolveType: pick,
          fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
        );
        declareMembers([interface]);
        pet = interface;
      }
      return b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field('pets', b.list(pet.nullable).nullable)
                .pure(
                  (_) => <_Source>[
                    {'__typename': 'Dog', 'name': 'Odie', 'woofs': true},
                    {'__typename': 'Cat', 'name': 'Garfield', 'meows': false},
                  ],
                ),
          ],
        ),
      );
    }

    test('resolve Union type using __typename on source object', () async {
      final schema = typenameSchema(
        ExecutableSchemaBuilder<Object?>(),
        isUnion: true,
      );

      expect(await port.json(schema, _petsQuery), {
        'data': {'pets': odieAndGarfield},
      });
    });

    test('resolve Interface type using __typename on source object', () async {
      final schema = typenameSchema(
        ExecutableSchemaBuilder<Object?>(),
        isUnion: false,
      );

      expect(await port.json(schema, _petsQuery), {
        'data': {'pets': odieAndGarfield},
      });
    });

    test('resolveType on Interface yields useful error', () async {
      final b = ExecutableSchemaBuilder<Object?>();
      final pet = petInterface(b);
      b.object<_Cat>('Cat', interfaces: [pet], fields: (t) => [catName(b, t)]);
      b.object<_Dog>('Dog', interfaces: [pet], fields: (t) => [dogName(b, t)]);
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [t.field('pet', pet.nullable).pure((_) => Object())],
        ),
      );
      expect(
        await port.json(schema, _petQuery),
        petFailure(_unresolvedMessage),
      );

      final other = ExecutableSchemaBuilder<Object?>();
      late final ObjectTypeDef<_Dog> human;
      final otherPet = petInterface(other, resolveType: (value) => human);
      other.object<_Cat>(
        'Cat',
        interfaces: [otherPet],
        fields: (t) => [catName(other, t)],
      );
      human = other.object<_Dog>('Human', fields: (t) => [dogName(other, t)]);
      final otherSchema = other.build(
        query: other.object<Object?>(
          'Query',
          fields: (t) => [
            t.field('pet', otherPet.nullable).pure((_) => _Dog('Rex', true)),
          ],
        ),
      );
      expect(
        await port.json(otherSchema, _petQuery),
        petFailure(
          'Runtime Object type "Human" is not a possible type for "Pet".',
        ),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/directives_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/directives-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final schema = b.build(
    query: b.object<Object?>(
      'TestType',
      fields: (t) => [
        t.field('a', b.string.nullable).pure((_) => 'a'),
        t.field('b', b.string.nullable).pure((_) => 'b'),
      ],
    ),
  );
  const both = {'a': 'a', 'b': 'b'};
  const onlyA = {'a': 'a'};

  group('Execute: handles directives', () {
    group('works without directives', () {
      test('basic query works', () async {
        expect(
          await port.json(schema, '{ a, b }'),
          {'data': both},
        );
      });
    });

    group('works on scalars', () {
      test('if true includes scalar', () async {
        expect(
          await port.json(schema, '{ a, b @include(if: true) }'),
          {'data': both},
        );
      });

      test('if false omits on scalar', () async {
        expect(
          await port.json(schema, '{ a, b @include(if: false) }'),
          {'data': onlyA},
        );
      });

      test('unless false includes scalar', () async {
        expect(
          await port.json(schema, '{ a, b @skip(if: false) }'),
          {'data': both},
        );
      });

      test('unless true omits scalar', () async {
        expect(
          await port.json(schema, '{ a, b @skip(if: true) }'),
          {'data': onlyA},
        );
      });
    });

    group('works on fragment spreads', () {
      test('if false omits fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @include(if: false)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': onlyA},
        );
      });

      test('if true includes fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @include(if: true)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': both},
        );
      });

      test('unless false includes fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @skip(if: false)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': both},
        );
      });

      test('unless true omits fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @skip(if: true)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': onlyA},
        );
      });
    });

    group('works on inline fragment', () {
      test('if false omits inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @include(if: false) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });

      test('if true includes inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @include(if: true) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless false includes inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @skip(if: false) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless true includes inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @skip(if: true) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });
    });

    group('works on anonymous inline fragment', () {
      test('if false omits anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... @include(if: false) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });

      test('if true includes anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... @include(if: true) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless false includes anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query Q {
          a
          ... @skip(if: false) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless true includes anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... @skip(if: true) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });
    });

    group('works with skip and include directives', () {
      test('include and no skip', () async {
        expect(
          await port.json(schema, '''
        {
          a
          b @include(if: true) @skip(if: false)
        }
      '''),
          {'data': both},
        );
      });

      test('include and skip', () async {
        expect(
          await port.json(schema, '''
        {
          a
          b @include(if: true) @skip(if: true)
        }
      '''),
          {'data': onlyA},
        );
      });

      test('no include or skip', () async {
        expect(
          await port.json(schema, '''
        {
          a
          b @include(if: false) @skip(if: false)
        }
      '''),
          {'data': onlyA},
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/enum_type_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

enum _Color { red, green, blue }

enum _Complex { one, two }

enum _ThunkValues { a, b }

// Ported from the execution tests of graphql-js
// src/type/__tests__/enumType-test.ts; mapping/execution.csv says which
// tests are adapted or skipped, and why. A Dart enum has no internal value:
// where graphql-js's resolvers read or return the internal integers, these
// map the enum's index.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final color = b.enumType<_Color>(
    'Color',
    _Color.values,
    mapping: EnumValueMapping<_Color>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final complex = b.enumType<_Complex>(
    'Complex',
    _Complex.values,
    mapping: EnumValueMapping<_Complex>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final thunkValues = b.enumType<_ThunkValues>(
    'ThunkValues',
    _ThunkValues.values,
    mapping: EnumValueMapping<_ThunkValues>(
      nameOf: (value) => value.name.toUpperCase(),
    ),
  );
  final fromEnum = Arg('fromEnum', color.nullable);
  final fromInt = Arg('fromInt', b.int.nullable);
  final complexFromEnum = Arg(
    'fromEnum',
    complex,
    defaultValue: _Complex.one,
  );
  final provideGoodValue = Arg('provideGoodValue', b.boolean.nullable);
  final thunkFromEnum = Arg('fromEnum', thunkValues.nullable);
  final colorArg = Arg('color', color.nullable);
  final schema = b.build(
    query: b.object<Object?>(
      'Query',
      fields: (t) => [
        t
            .field(
              'colorEnum',
              color.nullable,
              args: [fromEnum, fromInt],
            )
            .resolve((_, args, context, info) {
              final index = args.get(fromInt);
              return index == null ? args.get(fromEnum) : _Color.values[index];
            }),
        t
            .field('colorInt', b.int.nullable, args: [fromEnum])
            .resolve((_, args, context, info) => args.get(fromEnum)?.index),
        t
            .field(
              'complexEnum',
              complex.nullable,
              args: [complexFromEnum, provideGoodValue],
            )
            .resolve(
              (_, args, context, info) => args.get(provideGoodValue) == true
                  ? _Complex.two
                  : args.get(complexFromEnum),
            ),
        t
            .field(
              'complexEnumWithLegacyDefault',
              complex.nullable,
              args: [complexFromEnum],
            )
            .resolve((_, args, context, info) => args.get(complexFromEnum)),
        t
            .field(
              'thunkValuesString',
              b.string.nullable,
              args: [thunkFromEnum],
            )
            .resolve(
              (_, args, context, info) => args.get(thunkFromEnum)?.name,
            ),
      ],
    ),
    mutation: b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t
            .field('favoriteEnum', color.nullable, args: [colorArg])
            .resolve((_, args, context, info) => args.get(colorArg)),
      ],
    ),
  );

  Future<Map<String, Object?>> respond(
    String query, {
    Map<String, Object?>? variables,
    bool includesSuggestions = true,
  }) => port.respond(
    schema,
    query,
    variables: variables == null ? null : port.variablesOf(variables),
    includesSuggestions: includesSuggestions,
  );

  Map<String, Object?> failure(String message, int line, int column) => {
    'errors': [
      {
        'message': message,
        'locations': [
          {'line': line, 'column': column},
        ],
      },
    ],
  };

  group('Type System: Enum Values', () {
    test('accepts enum literals as input', () async {
      expect(await respond('{ colorInt(fromEnum: GREEN) }'), {
        'data': {'colorInt': 1},
      });
    });

    test('enum may be output type', () async {
      expect(await respond('{ colorEnum(fromInt: 1) }'), {
        'data': {'colorEnum': 'GREEN'},
      });
    });

    test('enum may be both input and output type', () async {
      expect(await respond('{ colorEnum(fromEnum: GREEN) }'), {
        'data': {'colorEnum': 'GREEN'},
      });
    });

    test('does not accept string literals', () async {
      expect(
        await respond('{ colorEnum(fromEnum: "GREEN") }'),
        failure(
          'Enum "Color" cannot represent non-enum value: "GREEN". '
          'Did you mean the enum value "GREEN"?',
          1,
          23,
        ),
      );
    });

    test('does not accept values not in the enum', () async {
      expect(
        await respond('{ colorEnum(fromEnum: GREENISH) }'),
        failure(
          'Value "GREENISH" does not exist in "Color" enum. '
          'Did you mean the enum value "GREEN"?',
          1,
          23,
        ),
      );
    });

    test('does not accept values not in the enum (no suggestions)', () async {
      expect(
        await respond(
          '{ colorEnum(fromEnum: GREENISH) }',
          includesSuggestions: false,
        ),
        failure('Value "GREENISH" does not exist in "Color" enum.', 1, 23),
      );
    });

    test('does not accept values with incorrect casing', () async {
      expect(
        await respond('{ colorEnum(fromEnum: green) }'),
        failure(
          'Value "green" does not exist in "Color" enum. '
          'Did you mean the enum value "GREEN" or "RED"?',
          1,
          23,
        ),
      );
    });

    test('does not accept internal value in place of enum literal', () async {
      expect(
        await respond('{ colorEnum(fromEnum: 1) }'),
        failure('Enum "Color" cannot represent non-enum value: 1.', 1, 23),
      );
    });

    test('does not accept enum literal in place of int', () async {
      expect(
        await respond('{ colorEnum(fromInt: GREEN) }'),
        failure('Int cannot represent non-integer value: GREEN', 1, 22),
      );
    });

    test('accepts JSON string as enum variable', () async {
      expect(
        await respond(
          r'query ($color: Color!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 'BLUE'},
        ),
        {
          'data': {'colorEnum': 'BLUE'},
        },
      );
    });

    test('accepts enum literals as input arguments to mutations', () async {
      expect(
        await respond(
          r'mutation ($color: Color!) { favoriteEnum(color: $color) }',
          variables: {'color': 'GREEN'},
        ),
        {
          'data': {'favoriteEnum': 'GREEN'},
        },
      );
    });

    test('does not accept internal value as enum variable', () async {
      expect(
        await respond(
          r'query ($color: Color!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 2},
        ),
        failure(
          r'Variable "$color" has invalid value: '
          'Enum "Color" cannot represent non-string value: 2.',
          1,
          8,
        ),
      );
    });

    test('does not accept string variables as enum input', () async {
      expect(
        await respond(
          r'query ($color: String!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 'BLUE'},
        ),
        {
          'errors': [
            {
              'message':
                  r'Variable "$color" of type "String!" used in position '
                  'expecting type "Color".',
              'locations': [
                {'line': 1, 'column': 8},
                {'line': 1, 'column': 47},
              ],
            },
          ],
        },
      );
    });

    test('does not accept internal value variable as enum input', () async {
      expect(
        await respond(
          r'query ($color: Int!) { colorEnum(fromEnum: $color) }',
          variables: {'color': 2},
        ),
        {
          'errors': [
            {
              'message':
                  r'Variable "$color" of type "Int!" used in position '
                  'expecting type "Color".',
              'locations': [
                {'line': 1, 'column': 8},
                {'line': 1, 'column': 44},
              ],
            },
          ],
        },
      );
    });

    test('enum value may have an internal value of 0', () async {
      expect(
        await respond('''
      {
        colorEnum(fromEnum: RED)
        colorInt(fromEnum: RED)
      }
    '''),
        {
          'data': {'colorEnum': 'RED', 'colorInt': 0},
        },
      );
    });

    test('enum inputs may be nullable', () async {
      expect(
        await respond('''
      {
        colorEnum
        colorInt
      }
    '''),
        {
          'data': {'colorEnum': null, 'colorInt': null},
        },
      );
    });

    test('may be internally represented with complex values', () async {
      expect(
        await respond('''
      {
        first: complexEnum
        second: complexEnum(fromEnum: TWO)
        good: complexEnum(provideGoodValue: true)
      }
    '''),
        {
          'data': {'first': 'ONE', 'second': 'TWO', 'good': 'TWO'},
        },
      );
    });

    test(
      'may be internally represented with complex values using legacy internal defaults',
      () async {
        expect(
          await respond('''
      {
        complexEnumWithLegacyDefault
      }
    '''),
          {
            'data': {'complexEnumWithLegacyDefault': 'ONE'},
          },
        );
      },
    );

    test('may have values specified via a callback', () async {
      expect(await respond('{ thunkValuesString(fromEnum: B) }'), {
        'data': {'thunkValuesString': 'b'},
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/execution/union_interface_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

class _Dog {
  _Dog(this.name, this.barks);

  final String name;
  final bool barks;
  _Dog? mother;
  _Dog? father;
  List<_Dog> progeny = [];
}

class _Cat {
  _Cat(this.name, this.meows);

  final String name;
  final bool meows;
  _Cat? mother;
  _Cat? father;
  List<_Cat> progeny = [];
}

class _Plant {
  _Plant(this.name);

  final String name;
}

class _Person {
  _Person(this.name, [this.pets, this.friends, this.responsibilities]);

  final String name;
  final List<Object>? pets;
  final List<Object>? friends;
  final List<Object>? responsibilities;
  _Person? mother;
  _Person? father;
  List<_Person> progeny = [];
}

// Ported from graphql-js src/execution/__tests__/union-interface-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  late final InterfaceTypeDef<Object?> life;
  late final InterfaceTypeDef<Object?> mammal;
  late final ObjectTypeDef<_Dog> dog;
  late final ObjectTypeDef<_Cat> cat;
  late final ObjectTypeDef<_Person> person;
  final named = b.interface<Object?>(
    'Named',
    fields: (t) => [t.field('name', b.string.nullable).declareOnly()],
  );
  life = b.interface<Object?>(
    'Life',
    fields: (t) => [
      t.field('progeny', b.list(life.nullable).nullable).declareOnly(),
    ],
  );
  mammal = b.interface<Object?>(
    'Mammal',
    interfaces: [life],
    fields: (t) => [
      t.field('progeny', b.list(mammal.nullable).nullable).declareOnly(),
      t.field('mother', mammal.nullable).declareOnly(),
      t.field('father', mammal.nullable).declareOnly(),
    ],
  );
  dog = b.object<_Dog>(
    'Dog',
    interfaces: [mammal, life, named],
    options: ObjectOptions(isTypeOf: (value) => value is _Dog),
    fields: (t) => [
      t.field('name', b.string.nullable).pure((d) => d.name),
      t.field('barks', b.boolean.nullable).pure((d) => d.barks),
      t.field('progeny', b.list(dog.nullable).nullable).pure((d) => d.progeny),
      t.field('mother', dog.nullable).pure((d) => d.mother),
      t.field('father', dog.nullable).pure((d) => d.father),
    ],
  );
  cat = b.object<_Cat>(
    'Cat',
    interfaces: [mammal, life, named],
    options: ObjectOptions(isTypeOf: (value) => value is _Cat),
    fields: (t) => [
      t.field('name', b.string.nullable).pure((c) => c.name),
      t.field('meows', b.boolean.nullable).pure((c) => c.meows),
      t.field('progeny', b.list(cat.nullable).nullable).pure((c) => c.progeny),
      t.field('mother', cat.nullable).pure((c) => c.mother),
      t.field('father', cat.nullable).pure((c) => c.father),
    ],
  );
  final plant = b.object<_Plant>(
    'Plant',
    interfaces: [named],
    options: ObjectOptions(isTypeOf: (value) => value is _Plant),
    fields: (t) => [t.field('name', b.string.nullable).pure((p) => p.name)],
  );
  final pet = b.union<Object?>(
    'Pet',
    members: [dog, cat],
    resolveType: (value) => value is _Dog ? dog : cat,
  );
  final petOrPlant = b.union<Object?>(
    'PetOrPlantType',
    members: [plant, dog, cat],
  );
  person = b.object<_Person>(
    'Person',
    interfaces: [named, mammal, life],
    options: ObjectOptions(isTypeOf: (value) => value is _Person),
    fields: (t) => [
      t.field('name', b.string.nullable).pure((p) => p.name),
      t.field('pets', b.list(pet.nullable).nullable).pure((p) => p.pets),
      t
          .field('friends', b.list(named.nullable).nullable)
          .pure((p) => p.friends),
      t
          .field('responsibilities', b.list(petOrPlant.nullable).nullable)
          .pure((p) => p.responsibilities),
      t
          .field('progeny', b.list(person.nullable).nullable)
          .pure((p) => p.progeny),
      t.field('mother', person.nullable).pure((p) => p.mother),
      t.field('father', person.nullable).pure((p) => p.father),
    ],
  );
  final schema = b.build(query: person);

  final garfield = _Cat('Garfield', false);
  garfield.mother = _Cat("Garfield's Mom", false);
  garfield.mother!.progeny = [garfield];
  final odie = _Dog('Odie', true);
  odie.mother = _Dog("Odie's Mom", true);
  odie.mother!.progeny = [odie];
  final fern = _Plant('Fern');
  final liz = _Person('Liz');
  final john = _Person('John', [garfield, odie], [liz, odie], [garfield, fern]);

  Future<Map<String, Object?>> run(String query, {Object? rootValue}) =>
      port.json(
        schema,
        query,
        options: ExecutionOptions(rootValue: rootValue, maskErrors: false),
      );

  final garfieldAndOdie = <Map<String, Object?>>[
    {'__typename': 'Cat', 'name': 'Garfield', 'meows': false},
    {'__typename': 'Dog', 'name': 'Odie', 'barks': true},
  ];
  final lizAndOdie = <Map<String, Object?>>[
    {'__typename': 'Person', 'name': 'Liz'},
    {'__typename': 'Dog', 'name': 'Odie', 'barks': true},
  ];

  group('Execute: Union and intersection types', () {
    test('executes using union types', () async {
      expect(
        await run('''
      {
        __typename
        name
        pets {
          __typename
          name
          barks
          meows
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'pets': garfieldAndOdie,
          },
        },
      );
    });

    test('executes union types with inline fragments', () async {
      expect(
        await run('''
      {
        __typename
        name
        pets {
          __typename
          ... on Dog {
            name
            barks
          }
          ... on Cat {
            name
            meows
          }
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'pets': garfieldAndOdie,
          },
        },
      );
    });

    test('executes using interface types', () async {
      expect(
        await run('''
      {
        __typename
        name
        friends {
          __typename
          name
          barks
          meows
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'friends': lizAndOdie,
          },
        },
      );
    });

    test('executes interface types with inline fragments', () async {
      expect(
        await run('''
      {
        __typename
        name
        friends {
          __typename
          name
          ... on Dog {
            barks
          }
          ... on Cat {
            meows
          }

          ... on Mammal {
            mother {
              __typename
              ... on Dog {
                name
                barks
              }
              ... on Cat {
                name
                meows
              }
            }
          }
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'friends': [
              {'__typename': 'Person', 'name': 'Liz', 'mother': null},
              {
                '__typename': 'Dog',
                'name': 'Odie',
                'barks': true,
                'mother': {
                  '__typename': 'Dog',
                  'name': "Odie's Mom",
                  'barks': true,
                },
              },
            ],
          },
        },
      );
    });

    test('executes interface types with named fragments', () async {
      expect(
        await run('''
      {
        __typename
        name
        friends {
          __typename
          name
          ...DogBarks
          ...CatMeows
        }
      }

      fragment  DogBarks on Dog {
        barks
      }

      fragment  CatMeows on Cat {
        meows
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'friends': lizAndOdie,
          },
        },
      );
    });

    test('allows fragment conditions to be abstract types', () async {
      expect(
        await run('''
      {
        __typename
        name
        pets {
          ...PetFields,
          ...on Mammal {
            mother {
              ...ProgenyFields
            }
          }
        }
        friends { ...FriendFields }
      }

      fragment PetFields on Pet {
        __typename
        ... on Dog {
          name
          barks
        }
        ... on Cat {
          name
          meows
        }
      }

      fragment FriendFields on Named {
        __typename
        name
        ... on Dog {
          barks
        }
        ... on Cat {
          meows
        }
      }

      fragment ProgenyFields on Life {
        progeny {
          __typename
        }
      }
    ''', rootValue: john),
        {
          'data': {
            '__typename': 'Person',
            'name': 'John',
            'pets': [
              {
                '__typename': 'Cat',
                'name': 'Garfield',
                'meows': false,
                'mother': {
                  'progeny': [
                    {'__typename': 'Cat'},
                  ],
                },
              },
              {
                '__typename': 'Dog',
                'name': 'Odie',
                'barks': true,
                'mother': {
                  'progeny': [
                    {'__typename': 'Dog'},
                  ],
                },
              },
            ],
            'friends': lizAndOdie,
          },
        },
      );
    });
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -94,6 +94,9 @@ void main() {
       path: 'mapping/execution.csv',
       prefix: '',
       covered: const [
+        'execution/__tests__/abstract-test.ts',
+        'execution/__tests__/collectFields-test.ts',
+        'execution/__tests__/directives-test.ts',
         'execution/__tests__/errorPropagation-test.ts',
         'execution/__tests__/executor-test.ts',
         'execution/__tests__/lists-test.ts',
@@ -102,8 +105,10 @@ void main() {
         'execution/__tests__/resolve-test.ts',
         'execution/__tests__/schema-test.ts',
         'execution/__tests__/sync-test.ts',
+        'execution/__tests__/union-interface-test.ts',
         'execution/__tests__/variables-test.ts',
         'execution/__tests__/oneof-test.ts',
+        'type/__tests__/enumType-test.ts',
         'utilities/__tests__/coerceInputValue-test.ts',
         'utilities/__tests__/validateInputValue-test.ts',
       ],
```

In `packages/typed_graphql_conformance/test/support/execution_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -129,6 +129,8 @@ final class ExecutionPort {
     ExecutableSchema<Object?> schema,
     String text, {
     Object? rootValue,
+    JsonObject? variables,
+    bool includesSuggestions = true,
   }) async {
     final source = Source(text);
     final parsed = const Parser(
@@ -137,11 +139,12 @@ final class ExecutionPort {
     if (parsed is ParseFailure) {
       return problems(parsed.diagnostics, prefix: 'Syntax Error: ');
     }
-    final validated = const DocumentValidator().validate(
-      schema.schema,
-      (parsed as ParseSuccess).document,
-      source: source,
-    );
+    final validated =
+        DocumentValidator(includesSuggestions: includesSuggestions).validate(
+          schema.schema,
+          (parsed as ParseSuccess).document,
+          source: source,
+        );
     if (validated is InvalidDocument) {
       return problems(validated.diagnostics);
     }
@@ -149,9 +152,11 @@ final class ExecutionPort {
       await schema.execute(
         validated as ValidDocument,
         context: null,
+        variables: variables,
         options: ExecutionOptions(
           rootValue: rootValue,
           source: source,
+          includesSuggestions: includesSuggestions,
           maskErrors: false,
         ),
       ),
@@ -168,9 +173,10 @@ final class ExecutionPort {
       for (final diagnostic in diagnostics)
         {
           'message': '$prefix${diagnostic.message}',
-          if (diagnostic.span case final span?)
+          if (diagnostic.span != null)
             'locations': [
-              {'line': span.location.line, 'column': span.location.column},
+              for (final place in [?diagnostic.span, ...diagnostic.related])
+                {'line': place.location.line, 'column': place.location.column},
             ],
         },
     ],
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -383,3 +383,70 @@ utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested
 utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for null for a null value,ported,test/execution/validate_input_literal_test.dart,
 utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for nested lists for nested non-list values,ported,test/execution/validate_input_literal_test.dart,
 utilities/__tests__/validateInputValue-test.ts,validateInputLiteral > for nested GraphQLList,no error for nested null for nested null values,ported,test/execution/validate_input_literal_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works without directives,basic query works,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on scalars,if true includes scalar,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on scalars,if false omits on scalar,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on scalars,unless false includes scalar,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on scalars,unless true omits scalar,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on fragment spreads,if false omits fragment spread,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on fragment spreads,if true includes fragment spread,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on fragment spreads,unless false includes fragment spread,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on fragment spreads,unless true omits fragment spread,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on inline fragment,if false omits inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on inline fragment,if true includes inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on inline fragment,unless false includes inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on inline fragment,unless true includes inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on anonymous inline fragment,if false omits anonymous inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on anonymous inline fragment,if true includes anonymous inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on anonymous inline fragment,unless false includes anonymous inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works on anonymous inline fragment,unless true includes anonymous inline fragment,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works with skip and include directives,include and no skip,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works with skip and include directives,include and skip,ported,test/execution/directives_test.dart,
+execution/__tests__/directives-test.ts,Execute: handles directives > works with skip and include directives,no include or skip,ported,test/execution/directives_test.dart,
+execution/__tests__/collectFields-test.ts,collectFields > overlapping fragment spreads,should not collect a deferred spread after a non-deferred spread has been collected,skipped,,"collectFields is internal to graphql-js and about @defer usages; the planner is internal, and @defer runs inline until M14 (executeIncrementally)."
+execution/__tests__/collectFields-test.ts,collectFields > overlapping fragment spreads,should not collect a deferred spread after a deferred spread has been collected,skipped,,"collectFields is internal to graphql-js and about @defer usages; the planner is internal, and @defer runs inline until M14 (executeIncrementally)."
+execution/__tests__/collectFields-test.ts,collectFields > overlapping fragment spreads,should collect a non-deferred spread after a deferred spread has been collected,skipped,,"collectFields is internal to graphql-js and about @defer usages; the planner is internal, and @defer runs inline until M14 (executeIncrementally)."
+execution/__tests__/collectFields-test.ts,collectFields > overlapping fragment spreads,should not collect a non-deferred spread after a non-deferred spread has been collected,skipped,,"collectFields is internal to graphql-js and about @defer usages; the planner is internal, and @defer runs inline until M14 (executeIncrementally)."
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,isTypeOf used to resolve runtime type for Interface,adapted,test/execution/abstract_test.dart,"isTypeOf is a synchronous predicate without context: the Promise variant of the run is not repeated, one run is compared."
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,isTypeOf can throw,adapted,test/execution/abstract_test.dart,"isTypeOf is synchronous and takes no context, so only the throwing form runs, with a GraphQLException; the rejected-Promise run is not repeated."
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,isTypeOf can return false,adapted,test/execution/abstract_test.dart,"isTypeOf is a synchronous predicate without context: the Promise variant of the run is not repeated, one run is compared."
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,isTypeOf used to resolve runtime type for Union,adapted,test/execution/abstract_test.dart,"isTypeOf is a synchronous predicate without context: the Promise variant of the run is not repeated, one run is compared."
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolveType can throw,adapted,test/execution/abstract_test.dart,"resolveType is synchronous and takes no context, so only the throwing form runs, with a GraphQLException; the rejected-Promise run is not repeated."
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolve Union type using __typename on source object,adapted,test/execution/abstract_test.dart,There is no default resolveType reading __typename from the source: the union gets a resolveType over Map sources that reads the key.
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolve Interface type using __typename on source object,adapted,test/execution/abstract_test.dart,There is no default resolveType reading __typename from the source: the interface gets a resolveType over Map sources that reads the key.
+execution/__tests__/abstract-test.ts,Execute: Handles execution of abstract types,resolveType on Interface yields useful error,adapted,test/execution/abstract_test.dart,"resolveType returns an object type definition, never a name: only the ""no type accepts the value"" error and the ""not a possible type"" error (GQL334) can happen; the messages for an undefined, unknown, non-object or wrongly typed name cannot be reached."
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,can introspect on union and intersection types,skipped,,M5c
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes using union types,ported,test/execution/union_interface_test.dart,
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes union types with inline fragments,ported,test/execution/union_interface_test.dart,
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes using interface types,ported,test/execution/union_interface_test.dart,
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes interface types with inline fragments,ported,test/execution/union_interface_test.dart,
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,executes interface types with named fragments,ported,test/execution/union_interface_test.dart,
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,allows fragment conditions to be abstract types,ported,test/execution/union_interface_test.dart,
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,gets execution info in resolver,skipped,,"resolveType receives only the value: it has no context, schema or root value argument to record."
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,it handles rejections from isTypeOf after after an isTypeOf returns true,skipped,,"isTypeOf is a synchronous predicate and cannot return a Promise; the test is about unhandled promise rejections, which Dart has no equivalent of."
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,handles promises from isTypeOf correctly when a later type matches synchronously,skipped,,"isTypeOf is a synchronous predicate and cannot return a Promise; the test is about unhandled promise rejections, which Dart has no equivalent of."
+execution/__tests__/union-interface-test.ts,Execute: Union and intersection types,handles pending isTypeOf rejections when a later isTypeOf throws synchronously,skipped,,"isTypeOf is a synchronous predicate and cannot return a Promise; the test is about unhandled promise rejections, which Dart has no equivalent of (a synchronous throw is covered by abstract-test)."
+type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input,adapted,test/execution/enum_type_test.dart,A Dart enum has no internal integer: colorInt returns the index of the enum value.
+type/__tests__/enumType-test.ts,Type System: Enum Values,enum may be output type,adapted,test/execution/enum_type_test.dart,A Dart enum has no internal integer: the resolver maps the fromInt argument to the enum by index.
+type/__tests__/enumType-test.ts,Type System: Enum Values,enum may be both input and output type,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept string literals,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept values not in the enum,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept values not in the enum (no suggestions),ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept values with incorrect casing,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept incorrect internal value,skipped,,A Dart enum field cannot return a string: the resolver result type is checked at compile time.
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept internal value in place of enum literal,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept enum literal in place of int,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,accepts JSON string as enum variable,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input arguments to mutations,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,accepts enum literals as input arguments to subscriptions,skipped,,M5c (subscriptions).
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept internal value as enum variable,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept string variables as enum input,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,does not accept internal value variable as enum input,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,enum value may have an internal value of 0,adapted,test/execution/enum_type_test.dart,A Dart enum has no internal integer: colorInt returns the index of the enum value.
+type/__tests__/enumType-test.ts,Type System: Enum Values,enum inputs may be nullable,ported,test/execution/enum_type_test.dart,
+type/__tests__/enumType-test.ts,Type System: Enum Values,presents a getValues() API for complex enums,skipped,,"Tests the graphql-js GraphQLEnumType API (parentEnum, astNode, extensions); EnumTypeDef.values has its own server test."
+type/__tests__/enumType-test.ts,Type System: Enum Values,presents a getValue() API for complex enums,skipped,,Tests the graphql-js GraphQLEnumType API; EnumTypeDef.valueNamed has its own server test.
+type/__tests__/enumType-test.ts,Type System: Enum Values,may be internally represented with complex values,adapted,test/execution/enum_type_test.dart,"The ""bad"" field (a value equal to but not the same as an internal value) cannot be written with a typed enum and is not ported; the other three fields are."
+type/__tests__/enumType-test.ts,Type System: Enum Values,may be internally represented with complex values using legacy internal defaults,adapted,test/execution/enum_type_test.dart,"Defaults are Dart enum values; graphql-js's legacy internal-value default has no counterpart, so the default is the enum value itself."
+type/__tests__/enumType-test.ts,Type System: Enum Values,may have values specified via a callback,adapted,test/execution/enum_type_test.dart,"Enum values are given as a list, not a callback; the resolver returns the enum value's name."
+type/__tests__/enumType-test.ts,Type System: Enum Values,can be introspected without error,skipped,,M5c (introspection).
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/abstract_test.dart test/execution/directives_test.dart test/execution/enum_type_test.dart test/execution/union_interface_test.dart test/mapping_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/abstract_test.dart packages/typed_graphql_conformance/test/execution/directives_test.dart packages/typed_graphql_conformance/test/execution/enum_type_test.dart packages/typed_graphql_conformance/test/execution/union_interface_test.dart packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/execution_port.dart
git commit -q -m "test(typed_graphql_conformance): port the directive, abstract type and enum suites" \
  -m "Ports directives, abstract, union-interface and the execution tests of enumType; collectFields and the introspection and subscription tests are recorded as skipped. ExecutionPort.respond now takes variables and includesSuggestions, and lists related spans as locations like graphql-js." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 14: The deviations in the spec

Record in the spec's section 18 every behaviour difference the ports found, each with its reason and the conformance file that shows it.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-m5-execution-design.md`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Update the documents**

In `docs/superpowers/specs/2026-10-15-m5-execution-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -608,6 +608,60 @@ depends on the other). These constraints keep that possible:
     each, so core and server commits stay apart (the task's rule); the
     catalog test still sees each code used by a test before the stage
     ends.
+13. The executor waits for the resolvers that already started before it
+    answers, so a late error of a branch that a sibling's null already
+    discarded is still in the response; graphql-js answers first and drops
+    it. Waiting keeps `onError` and the error log complete and never
+    leaves work running behind a finished response
+    (`executor_errors_test.dart`, `nonnull_multiple_test.dart`).
+14. Operation request errors (`GQL320`-`GQL323`) carry no `locations`, and
+    a `RequestErrorResult` has no `data: null`: the type says "no data"
+    (`executor_operations_test.dart`).
+15. A resolver reports an error by throwing or failing its future. A
+    returned error value, a thrown value that is not an `Error` or
+    `Exception` and an empty rejection are JavaScript-only: a Dart value
+    is never an error, and anything thrown is masked like any other
+    unexpected error (`executor_errors_test.dart`).
+16. When two errors both reach the response they come in document order;
+    graphql-js orders them by completion time, which a deterministic
+    response must not depend on (`nonnull_multiple_test.dart`).
+17. A typed list holds values, not futures or errors; a field may return
+    a `Future` of the whole list. A list stops at its first failing or
+    null item without draining the iterable, and an async iterable is not
+    a list value (M14 brings streams of items)
+    (`lists_nullability_test.dart`, `lists_test.dart`).
+18. A `String` field takes a Dart `String`: there is no number-to-string
+    serialization, because the builder fixes the result type at compile
+    time (`lists_test.dart`).
+19. An argument reports only its first problem, where graphql-js lists all
+    of them (a field fails at its first bad argument); a variable
+    reports every problem, up to `maxCoercionErrors`. The
+    problems arrive as one variable or argument error each, with the path
+    in the message, not as (message, path) pairs
+    (`validate_input_value_test.dart`, `validate_input_literal_test.dart`).
+20. A codec's failure message is reported as it is, without graphql-js's
+    "Expected value of type X" wrapper, so a codec owns its message
+    (`validate_input_value_test.dart`).
+21. A custom scalar has no literal parser (R2.9): a literal is converted
+    to JSON and decoded by the codec, and a Boolean variable used where a
+    list is expected is refused, where graphql-js passes it through
+    (`coerce_input_literal_test.dart`).
+22. JSON has no `undefined` and no `NaN`: a missing value is a key left
+    out, and a test that needs `NaN` uses another invalid value
+    (`variables_lists_test.dart`, `coerce_input_value_test.dart`).
+23. Fragment arguments (experimental in graphql-js) and
+    `@experimental_disableErrorPropagation` are not supported; the second
+    is `ErrorBehavior.nullValue` for the whole request. The tests are
+    `skipped` in `mapping/execution.csv`
+    (`error_propagation_test.dart`).
+24. `resolveType` and `isTypeOf` are synchronous and take only the value
+    (no context, info or promise), and `resolveType` returns a definition,
+    never a name, so graphql-js's messages for an unknown or misspelled
+    type name are unreachable. There is no default `__typename`-key
+    resolution (`abstract_test.dart`).
+25. Enum values are Dart enum values, with no internal values: the tests
+    with a "bad" complex internal value or a string given for an enum
+    cannot be written (`enum_type_test.dart`).
 
 ## 19. Conformance (R0.7, R10.3)
 
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add docs/superpowers/specs/2026-10-15-m5-execution-design.md
git commit -q -m "docs: record the M5b deviations in the M5 spec" \
  -m "Section 18 lists, with the reason and the conformance file that shows each, every behaviour difference from graphql-js found while porting the M5b suites." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 15: The Execution guide and the example

Write `doc/execution.md`, `example/example.dart` (identical to the README's first program, checked by `example_test.dart`), the README status, `docs/discovery.md`, `llms.txt`, the root and core READMEs, the CHANGELOG, the `CLAUDE.md` Server paragraph and the HANDOFF line.

**Files:**
- Create: `packages/typed_graphql_server/example/example.dart`
- Modify: `CLAUDE.md`, `README.md`, `docs/discovery.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql/README.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/README.md`, `packages/typed_graphql_server/doc/execution.md`, `packages/typed_graphql_server/doc/schema_builder.md`
- Test: `packages/typed_graphql_server/test/doc/example_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/doc/example_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/doc_snippet.dart';

/// The package README shows `example/example.dart` as its quick tour: the
/// two must not drift apart (R11.2).
void main() {
  test('the first program in the README is example/example.dart', () {
    final readme = File('README.md').readAsStringSync();
    final first = const DocSnippets().of('README.md', readme).first;
    final example = File('example/example.dart').readAsStringSync();
    expect(first.code.trimRight(), example.trimRight());
  });
}
```

- [ ] **Step 2: Write the implementation**

Create `packages/typed_graphql_server/example/example.dart`:

```dart
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Book {
  const Book(this.title, this.pages);

  final String title;
  final int? pages;
}

Future<void> main() async {
  // Declare the schema in typed Dart: a wrong result type does not compile.
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<Book>(
    'Book',
    fields: (t) => [
      t.field('title', b.string).pure((book) => book.title),
      t.field('pages', b.int.nullable).pure((book) => book.pages),
    ],
  );
  final limit = Arg('limit', b.int, defaultValue: 10);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('books', b.list(book), args: [limit])
          .resolve(
            (parent, args, context, info) =>
                const [Book('Dune', 412), Book('Emma', null)].take(
                  args.get(limit),
                ),
          ),
    ],
  );
  final schema = b.build(query: query);

  // Parse and validate a request against the schema: a problem is a
  // diagnostic, never an exception.
  final source = Source('{ books(limit: 2) { title pages } }');
  final document = const Parser().parse(source).requireDocument();
  final checked = const DocumentValidator().validate(
    schema.schema,
    document,
    source: source,
  );
  if (checked case final ValidDocument valid) {
    // Execute it: the response is a value that writes itself as JSON.
    final response = await schema.execute(
      valid,
      context: null,
      options: ExecutionOptions(source: source),
    );
    stdout.writeln(response.toJson());
  }
}
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc/example_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,7 +45,13 @@ cost directives (`includesCostDirectives`, `GQL156`-`GQL161`), `CostAnalysis`,
 fuzzers and the guide sections on limits and cost. M5a (typed schema
 builder) delivers `ExecutableSchemaBuilder`, the typed refs, fields and
 arguments, `build` and `SchemaBuildError` (`GQL300`-`GQL302`) in
-`typed_graphql_server`, and the Schema Builder guide; execution is M5b.
+`typed_graphql_server`, and the Schema Builder guide. M5b (execution) delivers
+variable and argument coercion, the operation plan and its cache, the
+executor with specified null propagation, error behaviours, masking and
+`onError`, field middleware, abstract-type resolution at run time
+(`GQL310`-`GQL337`), the graphql-js execution, variables, directives,
+abstract-type, enum and input-coercion suites, and the Execution guide and
+example.
 
 ## Documents
 
@@ -393,9 +399,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 
 **Server** (`packages/typed_graphql_server/lib/src/`; M5). Imports the core
 only through its barrel. One folder per concern, with no import order
-(`builder/` and `execution/` import each other): `builder/` (M5a), then
-`coercion/`, `plan/`, `introspection/`, `subscription/`, `lookahead/`,
-`authorization/` and `cancellation/` in later sub-stages. The package is
+(`builder/` and `execution/` import each other): `builder/` (M5a),
+`coercion/`, `plan/` and `execution/` (M5b), then `introspection/`,
+`subscription/`, `lookahead/`, `authorization/` and `cancellation/` in later
+sub-stages. The package is
 transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
 or web framework, only `dart:async`, `dart:collection`, `dart:core`,
 `dart:math`, `meta` and the core (`test/quality/imports_test.dart`), and the
@@ -407,6 +414,22 @@ result type is fixed before the closure); methods take at most five
 parameters, so options travel in `ObjectOptions`, `EnumValueMapping` and
 `BuildOptions`. `build` runs `GQL300`-`GQL302` and the core validator and
 throws `SchemaBuildError`. Its guides are in `packages/typed_graphql_server/doc/`.
+`ExecutableSchema.execute(ValidDocument, context:, ...)` returns
+`FutureOr<ResponsePayload>` (a synchronous query is an `ExecutionResult`, not a
+`Future`). `coercion/`: `InputCoercion` (JSON values), `VariableCoercion`,
+`ArgumentCoercion` (one problem per argument, graphql-js's messages) and
+`LiteralCoercion` (substitutes variables); a `CoercionProblem` carries its
+code and the `GraphQLException` extensions. `plan/`: `OperationPlanner` turns
+a document into an `OperationPlan` (fields per `ConditionKey`, constant
+arguments coerced once) kept in `ExecutableSchema.planCache`; request errors
+are never cached. `execution/`: `OperationExecution` runs a plan through
+`ExecutionRun`, `SelectionExecutor`/`SerialFields`, `FieldExecution` (the one
+place a resolver lane is called, where middleware composed at build time
+lives) and `ValueCompletion` with its leaf, list, object and abstract
+variants; null propagation is a returned sentinel, not an exception, and
+`ErrorReporter` applies `ErrorBehavior`, masking (`GQL330`) and `onError`.
+`ExecutionOptions` holds every per-call setting, `maxDepth` and `maxSteps`
+bound the work (`GQL336`, `GQL337`).
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
@@ -604,11 +627,12 @@ README that leaves the package folder is an absolute URL.
   `packages/typed_graphql/test/doc/`.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
 - Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`,
-  `mapping/schema.csv` and `mapping/validation.csv`, checked by
+  `mapping/schema.csv`, `mapping/validation.csv` and `mapping/execution.csv`, checked by
   `test/mapping_test.dart` there; port helpers in its `test/support/`
   (`SchemaPort` for the schema suites, `ValidationPort` for
   `validateSchema`, `IntrospectionPort` for `buildClientSchema`,
-  `RulePort` for the validation rule suites).
+  `RulePort` for the validation rule suites, `ExecutionPort` for the
+  execution, variables and input-coercion suites).
 - Hostile-document tests: `packages/typed_graphql/test/validation/hostile_*_test.dart`.
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
   round trip, hostile SDL, introspection round trip, hostile
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -25,8 +25,9 @@ What it is built to be (see the [roadmap](docs/roadmap.md)):
 
 What works today: the language (parse, print, visit and transform queries and
 SDL), the schema (build it from SDL, extend, print and validate it, introspection
-both ways, schema coordinates), the wire protocol types, scalar codecs and the
-diagnostics model.
+both ways, schema coordinates), operation validation, the wire protocol types,
+scalar codecs and the diagnostics model; and, in `typed_graphql_server`, a
+typed schema builder and the execution of a validated operation.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
@@ -99,8 +100,7 @@ approaches:
 - **Conformance is measured.** The graphql-js v17 language and schema suites
   are ported with a mapping table (`typed_graphql_conformance`), and the core
   tests also run AOT-compiled and in the browser (dart2js and dart2wasm). The
-  validation suites are ported too; the execution suites will be ported
-  with their stage.
+  validation and execution suites are ported too.
 - **Independent.** The core is pure Dart and depends only on `meta`.
 
 ## Packages
@@ -110,12 +110,12 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder (M5a) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder and query execution (M5a, M5b) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
-| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema and introspection suites, fuzzers (M2, M3) |
+| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema, introspection, validation and execution suites, fuzzers (M2-M5b) |
 
 ## Install
 
````

In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,7 +39,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | GraphQL introspection query schema dart | M3 | yes |
 | validate a GraphQL operation dart | M4 | yes |
 | limit GraphQL query depth or cost dart | M4 | yes |
-| execute a GraphQL query dart | M5 | no |
+| execute a GraphQL query dart | M5 | yes |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | no |
 
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
-| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: typed schema builder | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide; next is M5b (execution) |
+| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: typed schema builder; M5b: execution | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide. M5b is done on the same branch: variable and argument coercion, the operation plan and cache, the executor (null propagation, error behaviours, masking, `onError`, limits), field middleware, abstract types at run time (`GQL310`-`GQL337`), the graphql-js execution, variables, directives, abstract-type, enum and input-coercion suites in `mapping/execution.csv`, the deviations in spec §18 items 13-25, the Execution guide and `example/example.dart`; next is M5c (introspection, subscriptions) |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. Execution (stage M5) and the server, client and code generation packages are not built yet, and nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. The server package typed_graphql_server declares a schema in typed Dart and executes a validated operation against it, with variables, specified null propagation, error masking and field middleware; its transports (stages M6, M7), the client and code generation packages are not built yet, and nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): skeleton; code generator and its CLI, not usable yet (M8, M10)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder works, execution not yet (M5b), then transport handlers (M6, M7)
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder and query execution work (guides: Schema Builder and Execution in its doc folder, runnable example in its example folder); introspection resolvers and subscriptions (M5c) and transport handlers (M6, M7) come later
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -17,8 +17,9 @@ of [typed_graphql](https://github.com/4akloon/graphql_dart).
 > extending it from SDL, printing it, scalar codecs, validating it,
 > introspection both ways, resolving schema coordinates) and the validation
 > of executable documents by the specification's 30 rules, with opt-in
-> limit rules and cost analysis. Execution
-> arrives in M5 (see the
+> limit rules and cost analysis. Execution is in
+> [typed_graphql_server](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_server)
+> (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 ## Contents
@@ -54,8 +55,9 @@ dependencies:
   [Operation validation](doc/validation.md#validating-a-document),
   [Diagnostics](doc/diagnostics.md#reading-a-diagnostic)).
 - **You do not need it when** you only send a query string to a server and
-  read the JSON back. Today it also does not execute an operation:
-  execution arrives in `typed_graphql_server` (M5).
+  read the JSON back. It does not execute an operation either:
+  that is `typed_graphql_server`, which declares a schema in typed Dart and
+  executes a validated document against it.
 - **What it replaces**: matching GraphQL text with regular expressions or
   string splitting, and reading responses as `Map<String, dynamic>`. A regular
   expression does not see comments, block strings or nested selections, and
```

In `packages/typed_graphql_server/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,7 +5,6 @@
 - Package skeleton.
 - `repository` points at the package folder; pub.dev is expected to rewrite
   relative README links from it (to confirm at M16).
-- The README says the package cannot execute requests yet.
 - Typed refs: `OutputRef<T>` and `InputRef<T>`, `LeafRef<T>` for scalars and
   enums, `.nullable`, `b.list` and `b.inputList`; the built-in scalars
   `b.int`, `b.float`, `b.string`, `b.boolean` and `b.id`.
@@ -23,8 +22,9 @@
   `Absent`, `Arguments`, `ArgumentsDef` for an arguments class.
 - `ExecutableSchemaBuilder.build` assembles the declared types into a
   validated `ExecutableSchema<C>`; the builder's own checks (`GQL300`-`GQL302`)
-  and the core validator report through `SchemaBuildError`. `BuildOptions`
-  holds the directives, `includesDeferAndStream` and the description.
+  and the core validator report through `SchemaBuildError`. `BuildOptions<C>`
+  holds the directives, `includesDeferAndStream`, the description, the plan
+  cache size and the middleware.
 - `FieldInfo` (field name, parent type name, response path) is the last
   argument of a resolver.
 - The Schema Builder and Execution guides, with the dartdoc categories
@@ -59,4 +59,9 @@
   build time (global, field, directive slots; outermost first); the pure lane
   and an empty chain are called directly. A slot for an undefined directive is
   an `ArgumentError`.
-- **Breaking:** `BuildOptions` is generic (`BuildOptions<C>`) and `build` takes `BuildOptions<C>?`.
+- Variables and arguments are coerced with graphql-js's messages (all problems
+  of a variable, `GQL310`-`GQL314`); literals substitute variables; the
+  operation plan caches field collection per `@skip`/`@include`/`@defer`
+  condition.
+- The README shows a working program, `example/example.dart`, which a test
+  keeps identical to it.
```

In `packages/typed_graphql_server/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -6,16 +6,135 @@
 
 **A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: under construction.** The typed schema builder works (stage M5a):
-> you can declare a schema in typed Dart code, build it, check it and print
-> its SDL. Execution arrives in M5b, see the
+> **Status: under construction.** The typed schema builder (M5a) and query
+> execution (M5b) work: you can declare a schema in typed Dart code, parse and
+> validate a request with the core, and execute it, with variables, specified
+> null propagation, error behaviours, masking and field middleware. Introspection
+> resolvers and subscriptions arrive in M5c; look-ahead, authorization and
+> cancellation in M5d; the request pipeline and the HTTP, graphql-ws and
+> graphql-sse handlers later. See the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
-**Not usable yet.** This package cannot execute a request yet; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql), and the schema builder of this one.
+## Contents
 
-Today: `ExecutableSchemaBuilder` declares scalars, enums, input objects, objects with typed fields and arguments, interfaces and unions, and `build` returns a validated `ExecutableSchema` or throws a `SchemaBuildError` with diagnostics. The [Schema Builder guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/doc/schema_builder.md) shows each step.
+- [Install](#install)
+- [Should I use this?](#should-i-use-this)
+- [A quick tour](#a-quick-tour)
+- [Guides](#guides)
+- [License](#license)
 
-Planned: execution (M5b), introspection and subscriptions (M5c), look-ahead, authorization and cancellation (M5d), the `GraphQLServer` pipeline with APQ, trusted documents and DataLoader (M6), and the GraphQL over HTTP, graphql-ws and graphql-sse handlers (M7).
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
+```
+
+## Should I use this?
+
+- **Use it when** you want to serve GraphQL from Dart and have the compiler
+  check resolvers: a field's result type is fixed by its declaration, an
+  argument is read with its type, and a bad request or a bad resolver result
+  is a value in the response, not an exception
+  ([Schema Builder](doc/schema_builder.md#objects-and-fields),
+  [Execution](doc/execution.md#executing-a-request)).
+- **You do not need it when** you only call a GraphQL server: that is the
+  client package, not usable yet. Today it also has no HTTP handler or
+  subscriptions: you call `ExecutableSchema.execute` yourself with a parsed
+  and validated document.
+- **What it replaces**: resolvers written against `Map<String, dynamic>`, where
+  a wrong result type or a misspelled argument name fails at run time in the
+  middle of a request. Here the wrong type does not compile, and every error
+  that does happen reaches the client as a coded `GraphQLError`
+  ([errors and masking](doc/execution.md#field-errors-and-masking)).
+- **Which package**: this one for the server side. It needs the core,
+  [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql),
+  to parse and validate documents.
+
+## A quick tour
+
+Declare the schema, validate a request, execute it. Every resolver here is
+synchronous; a resolver may also return a `Future`. The same program is in
+[example/example.dart](example/example.dart).
+
+```dart
+import 'dart:io';
+
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+final class Book {
+  const Book(this.title, this.pages);
+
+  final String title;
+  final int? pages;
+}
+
+Future<void> main() async {
+  // Declare the schema in typed Dart: a wrong result type does not compile.
+  final b = ExecutableSchemaBuilder<Object?>();
+  final book = b.object<Book>(
+    'Book',
+    fields: (t) => [
+      t.field('title', b.string).pure((book) => book.title),
+      t.field('pages', b.int.nullable).pure((book) => book.pages),
+    ],
+  );
+  final limit = Arg('limit', b.int, defaultValue: 10);
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t
+          .field('books', b.list(book), args: [limit])
+          .resolve(
+            (parent, args, context, info) =>
+                const [Book('Dune', 412), Book('Emma', null)].take(
+                  args.get(limit),
+                ),
+          ),
+    ],
+  );
+  final schema = b.build(query: query);
+
+  // Parse and validate a request against the schema: a problem is a
+  // diagnostic, never an exception.
+  final source = Source('{ books(limit: 2) { title pages } }');
+  final document = const Parser().parse(source).requireDocument();
+  final checked = const DocumentValidator().validate(
+    schema.schema,
+    document,
+    source: source,
+  );
+  if (checked case final ValidDocument valid) {
+    // Execute it: the response is a value that writes itself as JSON.
+    final response = await schema.execute(
+      valid,
+      context: null,
+      options: ExecutionOptions(source: source),
+    );
+    stdout.writeln(response.toJson());
+  }
+}
+```
+
+It prints:
+
+```text
+{"data":{"books":[{"title":"Dune","pages":412},{"title":"Emma","pages":null}]}}
+```
+
+## Guides
+
+- [Schema Builder](doc/schema_builder.md): refs, objects, fields, arguments,
+  scalars, enums, input objects, interfaces and unions, building the schema.
+- [Execution](doc/execution.md): executing a request, variables, request errors
+  and field errors, error behaviours, masking and `onError`, middleware,
+  abstract types, limits and the plan cache.
 
 ## License
 
````

In `packages/typed_graphql_server/doc/execution.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,46 +1,578 @@
 # Execution
 
-`ExecutableSchema.execute` runs a validated document (the full Execution
-guide arrives with the rest of M5b). The package holds the two types the
-builder hands to it.
+`ExecutableSchema<C>.execute` runs a validated document against the schema
+the builder made and answers with a response value. It builds on the Schema
+Builder guide's schemas and on the core's parsing and validation: `execute` takes a `ValidDocument`, the typestate that
+`DocumentValidator` returns for a document it accepted, so an unchecked
+document cannot reach it.
 
-`ExecutableSchema<C>` is what `ExecutableSchemaBuilder.build` returns: the
-validated core `ValidSchema` (`schema`) and the run-time tables of the
-resolvers behind it (`bindings`). `C` is the context type the resolvers
-receive. The schema's SDL is
-`const SchemaPrinter().print(executable.schema.schema)`.
+## Executing a request
 
-`FieldInfo` is the last argument of a `resolve` closure: the field's name
-(`fieldName`), the name of the object type it is selected on
-(`parentTypeName`) and its response `path` from the root, a `ResponsePath`
-whose `toList()` gives the core's `PathSegment`s. It also carries the
-parent `ObjectType`, the `returnType`, the `fieldNodes`, the `operation`, the
-raw `variables`, the `schema` and the `rootValue`.
+`execute(document, {required context, operationName, variables, options})`
+returns a `FutureOr<ResponsePayload>`. A query whose resolvers all return
+values at once completes synchronously: you get the `ExecutionResult`
+itself, not a `Future`. As soon as one resolver returns a `Future`, so does
+`execute`. A `pure` field (a getter over the parent, with no arguments or
+context) is the fast path: it has no middleware chain and nothing to wait
+for.
+
+`ResponsePayload` is sealed. An `ExecutionResult` holds `data` and `errors`
+(field errors, next to the data that could still be produced); a
+`RequestErrorResult` holds only `errors`, for a request that could not start.
+Both write themselves with `toJson()`. The `context` is the `C` of the
+schema, handed to every resolver. A `ValidDocument` made against another
+schema, or a `rootValue` the root type does not accept, is an `ArgumentError`:
+that is a programmer's mistake, not bad input.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
+    const DocumentValidator().validate(
+      schema.schema,
+      const Parser().parse(Source(text)).requireDocument(),
+    ) as ValidDocument;
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('now', b.string).pure((_) => 'today'),
+      t.field('later', b.string).resolve((p, args, c, info) async => 'soon'),
+    ],
+  );
+  final schema = b.build(query: query);
+
+  final fast = schema.execute(check(schema, '{ now }'), context: null);
+  print(fast is ExecutionResult);
+  final slow = schema.execute(check(schema, '{ now later }'), context: null);
+  print(slow is Future<ResponsePayload>);
+  print((await slow).toJson());
+}
+```
+
+It prints:
+
+```text
+true
+true
+{"data":{"now":"today","later":"soon"}}
+```
+
+`ExecutionOptions` holds everything else, per call: `rootValue` (the parent
+of the root fields), `source` (the text the document was parsed from, which
+gives errors their `locations`), `errorBehavior`, `maskErrors`, `onError`,
+`includesSuggestions` ("Did you mean" in messages), `maxCoercionErrors`
+(50), `maxDepth` (256) and `maxSteps` (10 000 000). The examples below leave
+`source` out to keep their output short.
+
+Mutation root fields run one after another, as the specification asks. In
+every other selection set the fields are started in document order, and the
+ones that wait are waited for together.
+
+## Variables and request errors
+
+Variable values arrive as a `JsonObject` and are coerced against the
+operation's variable definitions before anything runs: defaults apply, a
+missing required variable is refused, and an input object or custom scalar
+goes through its `decode`. Arguments are coerced afterwards, per field, with
+the variables substituted; constant arguments are coerced once and kept in
+the plan.
+
+A request that cannot start is a `RequestErrorResult` with no `data`: an
+unknown `operationName`, no operation, a `subscription` the schema does not
+have, or a variable that does not coerce. Its errors carry a code (`GQL320`
+to `GQL323` for the operation, `GQL310` to `GQL312` for variables) and have
+no `locations`. A variable error is reported for each problem, up to
+`maxCoercionErrors`. A problem inside one field's arguments is different: it
+is a field error, so the other fields still run.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
+    const DocumentValidator().validate(
+      schema.schema,
+      const Parser().parse(Source(text)).requireDocument(),
+    ) as ValidDocument;
+
+Future<void> show(
+  ExecutableSchema<Object?> schema,
+  String text, {
+  JsonObject? variables,
+  String? operationName,
+  ExecutionOptions options = const ExecutionOptions(),
+}) async {
+  final response = await schema.execute(
+    check(schema, text),
+    context: null,
+    variables: variables,
+    operationName: operationName,
+    options: options,
+  );
+  print(response.toJson());
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final name = Arg('name', b.string);
+  final times = Arg('times', b.int, defaultValue: 1);
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t
+          .field('greet', b.string, args: [name, times])
+          .resolve(
+            (p, args, c, info) =>
+                'Hello, ${args.get(name)}! ' * args.get(times),
+          ),
+    ],
+  );
+  final schema = b.build(query: query);
+  const text =
+      r'query Hi($who: String!, $n: Int) { greet(name: $who, times: $n) }';
+
+  await show(
+    schema,
+    text,
+    variables: JsonObject({'who': const JsonString('Ann')}),
+  );
+  await show(
+    schema,
+    text,
+    variables: JsonObject({'who': const JsonString('Ann'), 'n': JsonNumber(2)}),
+  );
+  await show(schema, text, variables: JsonObject({'who': JsonNumber(7)}));
+  await show(schema, text, operationName: 'Other');
+}
+```
+
+It prints:
+
+```text
+{"data":{"greet":"Hello, Ann! "}}
+{"data":{"greet":"Hello, Ann! Hello, Ann! "}}
+{"errors":[{"message":"Variable \"$who\" has invalid value: String cannot represent a non string value: 7","extensions":{"code":"GQL310"}}]}
+{"errors":[{"message":"Unknown operation named \"Other\".","extensions":{"code":"GQL320"}}]}
+```
+
+## Field errors and masking
+
+A resolver reports an error by throwing, or by returning a failed `Future`;
+both are caught. The error becomes a `GraphQLError` with the field's `path`
+and, when `options.source` is given, its `locations`, and the field is null.
+If the field is non-null, the null propagates to the nearest nullable parent,
+as the specification asks (section 6.4.4); the executor does this with a
+returned sentinel, not by unwinding the stack. When a root field is non-null,
+`data` itself is null.
+
+What the client sees depends on what was thrown:
+
+- A `GraphQLException(message, {extensions})` is meant for the client: its
+  message and extensions are sent as they are.
+- Anything else is a bug as far as the client is concerned and is masked:
+  the message is `Unexpected error.` with `extensions.code` `GQL330`, so a
+  database address or a stack trace never leaves the server. Set
+  `maskErrors: false` in development to see the error's `toString()`.
+- An error the library makes (a value of the wrong kind, a null for a
+  non-null field, an abstract type it cannot resolve) carries its code too,
+  `GQL331` to `GQL337`.
 
 ```dart
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_server/typed_graphql_server.dart';
 
-void main() {
+ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
+    const DocumentValidator().validate(
+      schema.schema,
+      const Parser().parse(Source(text)).requireDocument(),
+    ) as ValidDocument;
+
+Future<void> show(
+  ExecutableSchema<Object?> schema,
+  String text, {
+  ExecutionOptions options = const ExecutionOptions(),
+}) async {
+  final response = await schema.execute(
+    check(schema, text),
+    context: null,
+    options: options,
+  );
+  print(response.toJson());
+}
+
+Future<void> main() async {
   final b = ExecutableSchemaBuilder<Object?>();
   final query = b.object<Object?>(
     'Query',
     fields: (t) => [
+      t.field('ok', b.string).pure((_) => 'fine'),
       t
-          .field('where', b.string)
+          .field('broken', b.string.nullable)
+          .resolve((p, args, c, info) => throw StateError('hunter2')),
+      t
+          .field('forbidden', b.string.nullable)
           .resolve(
-            (parent, args, context, info) =>
-                '${info.parentTypeName}.${info.fieldName}',
+            (p, args, c, info) => throw GraphQLException(
+              'Not allowed.',
+              extensions: JsonObject({'code': const JsonString('FORBIDDEN')}),
+            ),
           ),
+      t
+          .field('required', b.string)
+          .resolve((p, args, c, info) => throw StateError('lost')),
     ],
   );
-  final executable = b.build(query: query);
-  print(executable.schema.schema.queryTypeName);
+  final schema = b.build(query: query);
+
+  await show(schema, '{ ok broken forbidden }');
+  await show(
+    schema,
+    '{ ok broken }',
+    options: const ExecutionOptions(maskErrors: false),
+  );
+  await show(schema, '{ ok required }');
+}
+```
+
+It prints:
+
+```text
+{"errors":[{"message":"Unexpected error.","path":["broken"],"extensions":{"code":"GQL330"}},{"message":"Not allowed.","path":["forbidden"],"extensions":{"code":"FORBIDDEN"}}],"data":{"ok":"fine","broken":null,"forbidden":null}}
+{"errors":[{"message":"Bad state: hunter2","path":["broken"],"extensions":{"code":"GQL330"}}],"data":{"ok":"fine","broken":null}}
+{"errors":[{"message":"Unexpected error.","path":["required"],"extensions":{"code":"GQL330"}}],"data":null}
+```
+
+## Error behaviours
+
+`ExecutionOptions.errorBehavior` chooses what an error does to the data:
+
+- `ErrorBehavior.propagate` (the default) follows the specification: a null
+  that reaches a non-null position nulls its parent, up to the nearest
+  nullable field.
+- `ErrorBehavior.nullValue` stops an error at its own field, even when the
+  field is non-null: the response holds a null where a non-null was
+  declared. A client that reads `errors` and tolerates nulls wants this.
+- `ErrorBehavior.halt` ends the execution at the first error: `data` is null
+  and `errors` holds that error.
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
+      t.field('id', b.int).pure((_) => 7),
+      t
+          .field('name', b.string)
+          .resolve((p, args, c, info) => throw GraphQLException('No name.')),
+    ],
+  );
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('user', user.nullable).pure((_) => 1),
+      t.field('other', b.string).pure((_) => 'still here'),
+    ],
+  );
+  final schema = b.build(query: query);
+  final document = const DocumentValidator().validate(
+    schema.schema,
+    const Parser()
+        .parse(Source('{ user { id name } other }'))
+        .requireDocument(),
+  ) as ValidDocument;
+
+  for (final behavior in ErrorBehavior.values) {
+    final response = await schema.execute(
+      document,
+      context: null,
+      options: ExecutionOptions(errorBehavior: behavior),
+    );
+    print('${behavior.name}: ${response.toJson()}');
+  }
+}
+```
+
+It prints:
+
+```text
+propagate: {"errors":[{"message":"No name.","path":["user","name"]}],"data":{"user":null,"other":"still here"}}
+nullValue: {"errors":[{"message":"No name.","path":["user","name"]}],"data":{"user":{"id":7,"name":null},"other":"still here"}}
+halt: {"errors":[{"message":"No name.","path":["user","name"]}],"data":null}
+```
+
+## Reporting errors with onError
+
+`ExecutionOptions.onError(error, stackTrace, reported)` runs for every error
+thrown by user code (resolvers, middleware, `decode`, codecs), before the
+masked or raw error is recorded. `reported` is what would be recorded;
+return a `GraphQLError` to replace it, or `null` to keep it. This is where a
+host logs the stack trace that the client never sees, and maps its own
+exception types to codes. A hook that throws is recorded as the masked
+error, so it cannot break the response.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t
+          .field('lookup', b.string.nullable)
+          .resolve((p, args, c, info) => throw ArgumentError('no such row')),
+    ],
+  );
+  final schema = b.build(query: query);
+  final document = const DocumentValidator().validate(
+    schema.schema,
+    const Parser().parse(Source('{ lookup }')).requireDocument(),
+  ) as ValidDocument;
+
+  final response = await schema.execute(
+    document,
+    context: null,
+    options: ExecutionOptions(
+      onError: (error, stackTrace, reported) {
+        print('logged: $error');
+        return GraphQLError(
+          'The lookup failed.',
+          path: reported.path,
+          extensions: JsonObject({'code': const JsonString('LOOKUP_FAILED')}),
+        );
+      },
+    ),
+  );
+  print(response.toJson());
+}
+```
+
+It prints:
+
+```text
+logged: Invalid argument(s): no such row
+{"errors":[{"message":"The lookup failed.","path":["lookup"],"extensions":{"code":"LOOKUP_FAILED"}}],"data":{"lookup":null}}
+```
+
+## Middleware
+
+A middleware wraps resolvers. A `FieldMiddleware<C>` takes the `next`
+resolver and a `FieldSite` (the parent `ObjectType` and the `SchemaField`)
+and returns a resolver. Chains are composed once, when the schema is built,
+in the order global (`BuildOptions.middleware`), then field
+(`FieldStub.withMiddleware`), then directive (`BuildOptions.directiveMiddleware`,
+keyed by the directive's name and applied to the fields that carry it); the
+outermost runs first. A middleware that does not care about a field returns
+`next` unchanged, which costs nothing per request, and a field with no
+middleware is called directly. There is no slot for a whole type: a global
+middleware looks at `site.parentType` and returns `next` for the others. A
+`pure` field has no chain, so combining it with middleware is an
+`ArgumentError`.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+Future<void> main() async {
+  final log = <String>[];
+  final b = ExecutableSchemaBuilder<String>();
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('hello', b.string.nullable).resolve((p, args, c, info) => 'hi'),
+      t
+          .field('secret', b.string.nullable)
+          .withMiddleware([
+            (next, site) =>
+                (parent, args, role, info) => role == 'admin'
+                ? next(parent, args, role, info)
+                : throw GraphQLException('Admins only.'),
+          ])
+          .resolve((p, args, c, info) => 'the code'),
+    ],
+  );
+  final schema = b.build(
+    query: query,
+    options: BuildOptions<String>(
+      middleware: [
+        (next, site) => (parent, args, role, info) {
+          log.add('${site.parentType.name}.${site.field.name}');
+          return next(parent, args, role, info);
+        },
+      ],
+    ),
+  );
+  final document = const DocumentValidator().validate(
+    schema.schema,
+    const Parser().parse(Source('{ hello secret }')).requireDocument(),
+  ) as ValidDocument;
+
+  for (final role in ['guest', 'admin']) {
+    final response = await schema.execute(document, context: role);
+    print('$role: ${response.toJson()}');
+  }
+  print(log);
+}
+```
+
+It prints:
+
+```text
+guest: {"errors":[{"message":"Admins only.","path":["secret"]}],"data":{"hello":"hi","secret":null}}
+admin: {"data":{"hello":"hi","secret":"the code"}}
+[Query.hello, Query.secret, Query.hello, Query.secret]
+```
+
+## Abstract types
+
+The object type of an interface or union value is chosen at run time.
+Without help, the first possible type whose `accepts` takes the value wins,
+which is enough when the Dart types differ. Pass `resolveType` to `interface`
+or `union` to choose yourself: it is synchronous, takes the value and returns
+the object type definition, so a misspelled type name cannot happen. Give
+both object types an `isTypeOf` (in `ObjectOptions`) instead when they
+overlap in Dart and you prefer to keep the choice with the types. A value no
+type accepts is `GQL333`; a `resolveType` result that cannot hold the value
+is `GQL334`.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+final class Item {
+  const Item(this.title, {required this.isFilm});
+
+  final String title;
+  final bool isFilm;
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  final book = b.object<Item>(
+    'Book',
+    fields: (t) => [t.field('title', b.string).pure((item) => item.title)],
+  );
+  final film = b.object<Item>(
+    'Film',
+    fields: (t) => [t.field('title', b.string).pure((item) => item.title)],
+  );
+  final media = b.union<Item>(
+    'Media',
+    members: [book, film],
+    resolveType: (item) => item.isFilm ? film : book,
+  );
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t
+          .field('shelf', b.list(media))
+          .pure(
+            (_) => const [
+              Item('Dune', isFilm: false),
+              Item('Alien', isFilm: true),
+            ],
+          ),
+    ],
+  );
+  final schema = b.build(query: query);
+  final document = const DocumentValidator().validate(
+    schema.schema,
+    const Parser()
+        .parse(Source('{ shelf { __typename ... on Film { title } } }'))
+        .requireDocument(),
+  ) as ValidDocument;
+
+  print((await schema.execute(document, context: null)).toJson());
+}
+```
+
+It prints:
+
+```text
+{"data":{"shelf":[{"__typename":"Book"},{"__typename":"Film","title":"Alien"}]}}
+```
+
+## Limits and the plan cache
+
+Two options end runaway executions with an error instead of a hung process.
+`maxDepth` (256) bounds how deep completion nests: a value below it is a
+field error `GQL336` and that branch ends. `maxSteps` (10 000 000) bounds the
+work, one step per completed value: past it the execution halts with
+`GQL337` and no data. The parser bounds documents before they get here;
+these two bound what the data makes of them (long lists, a recursive type).
+
+The first run of a document plans it: it collects the fields for each
+combination of `@skip`, `@include` and `@defer` conditions, expands every
+fragment once, and coerces constant arguments once. The plan is cached per
+schema, least recently used first out, by document and operation name.
+`BuildOptions.planCacheSize` sets how many (1000; 0 keeps none). A request
+error is never cached.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+import 'package:typed_graphql_server/typed_graphql_server.dart';
+
+final class Node {
+  const Node(this.next);
+
+  final Node? next;
+}
+
+Future<void> main() async {
+  final b = ExecutableSchemaBuilder<Object?>();
+  late final ObjectTypeDef<Node> node;
+  node = b.object<Node>(
+    'Node',
+    fields: (t) => [
+      t.field('next', node.nullable).pure((parent) => parent.next),
+      t.field('id', b.int).pure((_) => 1),
+    ],
+  );
+  final query = b.object<Object?>(
+    'Query',
+    fields: (t) => [
+      t.field('head', node).pure((_) => const Node(Node(Node(null)))),
+    ],
+  );
+  final schema = b.build(
+    query: query,
+    options: const BuildOptions<Object?>(planCacheSize: 100),
+  );
+  final document = const DocumentValidator().validate(
+    schema.schema,
+    const Parser()
+        .parse(Source('{ head { next { next { id } } } }'))
+        .requireDocument(),
+  ) as ValidDocument;
+
+  for (final options in const [
+    ExecutionOptions(),
+    ExecutionOptions(maxDepth: 3),
+    ExecutionOptions(maxSteps: 3),
+  ]) {
+    final response = await schema.execute(
+      document,
+      context: null,
+      options: options,
+    );
+    print(response.toJson());
+  }
 }
 ```
 
 It prints:
 
 ```text
-Query
+{"data":{"head":{"next":{"next":{"id":1}}}}}
+{"errors":[{"message":"Execution exceeds the maximum depth of 3.","path":["head","next","next","id"],"extensions":{"code":"GQL336"}}],"data":{"head":{"next":{"next":null}}}}
+{"errors":[{"message":"Execution exceeds the limit of 3 completed values.","path":["head","next","next","id"],"extensions":{"code":"GQL337"}}],"data":null}
 ```
````

In `packages/typed_graphql_server/doc/schema_builder.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,8 +7,8 @@ creation order; `build` checks them and returns an `ExecutableSchema<C>`
 (`typed_graphql`'s own `SchemaBuilder` builds a schema from SDL text, hence
 the different name).
 
-The package cannot execute a request yet: execution arrives in M5b. What
-works today is declaring, checking and printing a schema.
+Declaring, checking and printing a schema is this guide; running a request
+against it is the Execution guide.
 
 ## Refs and nullability
 
```

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md README.md docs/discovery.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql/README.md packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/README.md packages/typed_graphql_server/doc/execution.md packages/typed_graphql_server/doc/schema_builder.md packages/typed_graphql_server/example/example.dart packages/typed_graphql_server/test/doc/example_test.dart
git commit -q -m "docs(typed_graphql_server): add the Execution guide and the example" \
  -m "The Execution guide shows each M5b capability with a program and its exact output, and the README's first program is example/example.dart, kept identical by a test. The README, discovery page, llms.txt, root README, CLAUDE.md, HANDOFF and CHANGELOG say that execution works." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 16: A mapping reason

Correct the reason of one `adapted` row: the error carries its code, and only its location differs from graphql-js.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -111,7 +111,7 @@ execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects
 execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,properly parses null value in list,ported,test/execution/variables_objects_test.dart,
 execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,does not use incorrect value,ported,test/execution/variables_objects_test.dart,
 execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,properly runs coerceInputLiteral on complex scalar types,ported,test/execution/variables_objects_test.dart,
-execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,errors on faulty scalar type input,adapted,test/execution/variables_objects_test.dart,"The error is located at the argument value, not at the field, and a codec failure carries no extensions code."
+execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using inline structs,errors on faulty scalar type input,adapted,test/execution/variables_objects_test.dart,"The error is located at the argument value, where graphql-js locates it at the field."
 execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,executes with complex input,ported,test/execution/variables_objects_test.dart,
 execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses undefined when variable not provided,adapted,test/execution/variables_objects_test.dart,JSON has no undefined: the variable is left out of the map.
 execution/__tests__/variables-test.ts,Execute: Handles inputs > Handles objects and nullability > using variables,uses null when variable provided explicit null value,ported,test/execution/variables_objects_test.dart,
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add packages/typed_graphql_conformance/mapping/execution.csv
git commit -q -m "test(typed_graphql_conformance): correct the reason of the faulty scalar row" \
  -m "The error carries its code; only its location differs from graphql-js." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 17: The review fixes

Apply the review of Tasks 1-16: a throw during completion (`isTypeOf`, a codec, an iterable) becomes a field error instead of escaping `execute`; errors are sorted into document order by a position key; a codec's `ArgumentError` (not a `RangeError`) is `GQL332`, anything else is masked; `maxDepth` is checked before the resolver runs and reported once per list; the `__schema` / `__type` placeholder settles like any error; the guide states that decoded input objects must be immutable and that `maxSteps` keeps only its own error.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/execution.csv`, `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart`, `packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart`, `packages/typed_graphql_server/lib/src/execution/error_log.dart`, `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`, `packages/typed_graphql_server/lib/src/execution/execution_limits.dart`, `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, `packages/typed_graphql_server/lib/src/execution/leaf_completion.dart`, `packages/typed_graphql_server/lib/src/execution/list_completion.dart`, `packages/typed_graphql_server/lib/src/execution/pending_values.dart`, `packages/typed_graphql_server/lib/src/execution/response_path.dart`, `packages/typed_graphql_server/lib/src/execution/selection_executor.dart`, `packages/typed_graphql_server/lib/src/execution/serial_fields.dart`, `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, `packages/typed_graphql_server/lib/src/plan/field_plan.dart`, `packages/typed_graphql_server/lib/src/plan/plan_cache.dart`, `CLAUDE.md`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/execution.md`
- Test: `packages/typed_graphql_server/test/execution/completion_failures_test.dart`, `packages/typed_graphql_conformance/test/execution/executor_errors_test.dart`, `packages/typed_graphql_conformance/test/execution/lists_test.dart`, `packages/typed_graphql_conformance/test/execution/nonnull_test.dart`, `packages/typed_graphql_server/test/builder/fields_test.dart`, `packages/typed_graphql_server/test/execution/limits_and_order_test.dart`

**Interfaces:**
- Consumes: Tasks 2-15.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/execution/completion_failures_test.dart`:

```dart
import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

final class Crate {
  const Crate();
}

final class FailingCodec implements ScalarCodec<String> {
  const FailingCodec(this.failure);

  final Error failure;

  @override
  DecodeResult<String> decode(JsonValue json) => const DecodeFailure('no');

  @override
  JsonValue encode(String value) => throw failure;
}

final class Counter {
  int calls = 0;
}

final class FailureFixture {
  FailureFixture() {
    final b = ExecutableSchemaBuilder<Counter>();
    final crate = b.object<Crate>(
      'Crate',
      fields: (t) => [t.field('size', b.int).pure((_) => 1)],
      options: ObjectOptions(isTypeOf: (_) => throw StateError('isTypeOf')),
    );
    final explicit = b.union<Object>(
      'Explicit',
      members: [crate],
      resolveType: (_) => crate,
    );
    final byDefault = b.union<Object>('Default', members: [crate]);
    final argument = b.scalar<String>(
      'ArgumentFailure',
      FailingCodec(ArgumentError('cannot show it')),
    );
    final emptyArgument = b.scalar<String>(
      'EmptyArgumentFailure',
      FailingCodec(ArgumentError()),
    );
    final range = b.scalar<String>(
      'RangeFailure',
      FailingCodec(RangeError('secret range')),
    );
    final state = b.scalar<String>(
      'StateFailure',
      FailingCodec(StateError('secret state')),
    );
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('explicit', explicit.nullable).pure((_) => const Crate()),
        t
            .field('explicitLater', explicit.nullable)
            .resolve((parent, args, context, info) async => const Crate()),
        t.field('byDefault', byDefault.nullable).pure((_) => const Crate()),
        t
            .field('lazyLater', b.list(b.int).nullable)
            .resolve((parent, args, context, info) async => _lazy()),
        t.field('argument', argument.nullable).pure((_) => 'x'),
        t.field('emptyArgument', emptyArgument.nullable).pure((_) => 'x'),
        t.field('range', range.nullable).pure((_) => 'x'),
        t.field('state', state.nullable).pure((_) => 'x'),
        t.field('slowFail', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          throw StateError('slow');
        }),
        t.field('quickFail', b.string.nullable).resolve((
          parent,
          args,
          context,
          info,
        ) async {
          throw StateError('quick');
        }),
        t.field('self', query).pure((_) => const Object()),
        t.field('counted', b.string).resolve((parent, args, context, info) {
          context.calls++;
          return 'counted';
        }),
      ],
    );
    built = b.build(query: query);
  }

  late final ExecutableSchema<Counter> built;

  static Iterable<int> _lazy() sync* {
    yield 1;
    throw StateError('lazy');
  }

  Future<Map<String, Object?>> json(
    String text, {
    Counter? context,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument();
    final payload = await built.execute(
      ValidDocument.assumeValid(built.schema, document),
      context: context ?? Counter(),
      options: options,
    );
    return payload.toJson().toJson();
  }
}

void main() {
  final f = FailureFixture();
  const errorsOf = ExecutionFixture.errorsOf;
  const codeOf = ExecutionFixture.codeOf;

  String messageOf(Object? error) =>
      (error! as Map<String, Object?>)['message']! as String;

  List<Object?> pathsOf(Map<String, Object?> json) => [
    for (final error in errorsOf(json))
      (error! as Map<String, Object?>)['path'],
  ];

  group('a throw during completion', () {
    test('isTypeOf after an explicit resolveType is a field error', () async {
      final json = await f.json('{ explicit { size } }');
      expect(json['data'], {'explicit': null});
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('isTypeOf after an async resolver is a field error', () async {
      final json = await f.json('{ explicitLater { size } }');
      expect(json['data'], {'explicitLater': null});
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('isTypeOf in the default resolution is a field error', () async {
      final json = await f.json('{ byDefault { size } }');
      expect(json['data'], {'byDefault': null});
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('a throwing iterable behind a future is a field error', () async {
      final json = await f.json('{ lazyLater }');
      expect(json['data'], {'lazyLater': null});
      expect(errorsOf(json), hasLength(1));
    });

    test('the message is masked', () async {
      final json = await f.json('{ explicit { size } }');
      expect(messageOf(errorsOf(json).single), 'Unexpected error.');
    });
  });

  group('a codec failure', () {
    test('an ArgumentError is GQL332 with its message', () async {
      final json = await f.json('{ argument }');
      final error = errorsOf(json).single;
      expect(codeOf(error), 'GQL332');
      expect(messageOf(error), 'cannot show it');
    });

    test('an ArgumentError without a message never prints null', () async {
      final json = await f.json('{ emptyArgument }');
      final error = errorsOf(json).single;
      expect(codeOf(error), 'GQL332');
      expect(messageOf(error), isNot(contains('null')));
    });

    test('a RangeError is an unexpected, masked error', () async {
      final json = await f.json('{ range }');
      final error = errorsOf(json).single;
      expect(codeOf(error), 'GQL330');
      expect(messageOf(error), 'Unexpected error.');
    });

    test('another error is an unexpected, masked error', () async {
      final json = await f.json('{ state }');
      expect(messageOf(errorsOf(json).single), 'Unexpected error.');
    });

    test('a RangeError reaches onError', () async {
      Object? seen;
      await f.json(
        '{ range }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            seen = error;
            return null;
          },
        ),
      );
      expect(seen, isA<RangeError>());
    });
  });

  group('error order', () {
    test('errors follow the document, not the completion', () async {
      final json = await f.json('{ slowFail quickFail }');
      expect(pathsOf(json), [
        ['slowFail'],
        ['quickFail'],
      ]);
    });

    test('a later field that finishes first is listed last', () async {
      final json = await f.json('{ quickFail slowFail }');
      expect(pathsOf(json), [
        ['quickFail'],
        ['slowFail'],
      ]);
    });
  });

  group('depth', () {
    test('a too-deep field runs no resolver', () async {
      final counter = Counter();
      final json = await f.json(
        '{ self { self { counted } } }',
        context: counter,
        options: const ExecutionOptions(maxDepth: 2),
      );
      expect(counter.calls, 0);
      expect(codeOf(errorsOf(json).single), 'GQL336');
    });

    test('a field within the depth runs its resolver', () async {
      final counter = Counter();
      await f.json(
        '{ self { counted } }',
        context: counter,
        options: const ExecutionOptions(maxDepth: 2),
      );
      expect(counter.calls, 1);
    });
  });

  group('introspection placeholder', () {
    test('a non-null __schema propagates its error', () async {
      final json = await f.json('{ __schema { queryType { name } } }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });
  });
}
```

In `packages/typed_graphql_conformance/test/execution/executor_errors_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -209,23 +209,24 @@ void main() {
         equals({
           'data': null,
           'errors': [
+            // Document order; graphql-js lists them by completion time.
             {
               'message':
                   'Cannot return null for non-nullable field '
-                  'Query.syncNullError.',
+                  'Query.asyncNullError.',
               'locations': [
-                {'line': 4, 'column': 9},
+                {'line': 3, 'column': 9},
               ],
-              'path': ['syncNullError'],
+              'path': ['asyncNullError'],
             },
             {
               'message':
                   'Cannot return null for non-nullable field '
-                  'Query.asyncNullError.',
+                  'Query.syncNullError.',
               'locations': [
-                {'line': 3, 'column': 9},
+                {'line': 4, 'column': 9},
               ],
-              'path': ['asyncNullError'],
+              'path': ['syncNullError'],
             },
           ],
         }),
```

In `packages/typed_graphql_conformance/test/execution/lists_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -305,21 +305,21 @@ void main() {
           equals({
             'data': {'listField': null},
             'errors': [
+              // The executor waits for the resolver that had started, so its
+              // late error is in the response (graphql-js drops it).
               {
-                'message': 'also bad',
+                'message': 'bad',
                 'locations': [
                   {'line': 1, 'column': 15},
                 ],
-                'path': ['listField', 1, 'index'],
+                'path': ['listField', 0, 'index'],
               },
-              // The executor waits for the resolver that had started, so its
-              // late error is in the response (graphql-js drops it).
               {
-                'message': 'bad',
+                'message': 'also bad',
                 'locations': [
                   {'line': 1, 'column': 15},
                 ],
-                'path': ['listField', 0, 'index'],
+                'path': ['listField', 1, 'index'],
               },
             ],
           }),
```

In `packages/typed_graphql_conformance/test/execution/nonnull_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -169,15 +169,17 @@ void main() {
           equals({
             'data': data,
             'errors': [
+              // graphql-js lists these by completion time; this executor
+              // lists them in document order.
               error('sync', ['syncNest', 'sync'], 4, 11),
-              error('sync', ['syncNest', 'syncNest', 'sync'], 6, 22),
               error('promise', ['syncNest', 'promise'], 5, 11),
+              error('sync', ['syncNest', 'syncNest', 'sync'], 6, 22),
               error('promise', ['syncNest', 'syncNest', 'promise'], 6, 27),
               error('sync', ['syncNest', 'promiseNest', 'sync'], 7, 25),
-              error('sync', ['promiseNest', 'sync'], 10, 11),
-              error('sync', ['promiseNest', 'syncNest', 'sync'], 12, 22),
               error('promise', ['syncNest', 'promiseNest', 'promise'], 7, 30),
+              error('sync', ['promiseNest', 'sync'], 10, 11),
               error('promise', ['promiseNest', 'promise'], 11, 11),
+              error('sync', ['promiseNest', 'syncNest', 'sync'], 12, 22),
               error('promise', ['promiseNest', 'syncNest', 'promise'], 12, 27),
               error('sync', ['promiseNest', 'promiseNest', 'sync'], 13, 25),
               error(
```

In `packages/typed_graphql_server/test/builder/fields_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,7 +22,7 @@ void main() {
     fieldName: field,
     parentType: ObjectType('User'),
     returnType: const NamedType(Name('String')),
-    path: ResponsePath.root.key(field),
+    path: ResponsePath.root.key(field, 0),
     fieldNodes: const [],
     operation: OperationDefinition(
       OperationType.query,
```

In `packages/typed_graphql_server/test/execution/limits_and_order_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -71,6 +71,16 @@ void main() {
       expect(codeOf(errorsOf(json).first), 'GQL336');
     });
 
+    test('a list that is too deep reports once, not per item', () async {
+      final json = await f.json(
+        '{ numbers }',
+        options: const ExecutionOptions(maxDepth: 1),
+      );
+      expect(errorsOf(json), hasLength(1));
+      expect(codeOf(errorsOf(json).single), 'GQL336');
+      expect(json['data'], {'numbers': null});
+    });
+
     test('maxSteps halts with GQL337 and null data', () async {
       final json = await f.json(
         '{ hello strings }',
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_conformance/mapping/execution.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,7 +7,7 @@ execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,thre
 execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,correctly threads arguments,ported,test/execution/executor_test.dart,
 execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,nulls out error subtrees,adapted,test/execution/executor_errors_test.dart,"Errors are thrown or rejected as GraphQLException; a returned Error object, a thrown non-Error value and an empty rejection are JavaScript-only (a Dart value is never an error), so their fields are not ported."
 execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,nulls error subtree for promise rejection #1071,ported,test/execution/executor_errors_test.dart,
-execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,handles sync errors combined with rejections,adapted,test/execution/executor_errors_test.dart,"The executor waits for the resolvers that already started before it answers, so the late non-null error of asyncNullError is in the response (graphql-js answers first and drops it)."
+execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,handles sync errors combined with rejections,adapted,test/execution/executor_errors_test.dart,"The executor waits for the resolvers that already started before it answers, so the late non-null error of asyncNullError is in the response (graphql-js answers first and drops it). The errors are in document order, not completion order."
 execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,handles async bubbling errors combined with non-bubbling errors,ported,test/execution/executor_errors_test.dart,
 execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,Full response path is included for non-nullable fields,ported,test/execution/executor_errors_test.dart,
 execution/__tests__/executor-test.ts,Execute: Handles basic execution tasks,uses the inline operation if no operation name is provided,ported,test/execution/executor_operations_test.dart,
@@ -56,7 +56,7 @@ execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls
 execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls a returned object that contains a non-nullable field,that returns null,ported,test/execution/nonnull_test.dart,
 execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls a returned object that contains a non-nullable field,that throws,ported,test/execution/nonnull_test.dart,
 execution/__tests__/nonnull-test.ts,"Execute: handles non-nullable types > nulls a complex tree of nullable fields, each",that returns null,ported,test/execution/nonnull_test.dart,
-execution/__tests__/nonnull-test.ts,"Execute: handles non-nullable types > nulls a complex tree of nullable fields, each",that throws,ported,test/execution/nonnull_test.dart,
+execution/__tests__/nonnull-test.ts,"Execute: handles non-nullable types > nulls a complex tree of nullable fields, each",that throws,adapted,test/execution/nonnull_test.dart,"The errors are in document order; graphql-js orders them by completion time."
 execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the first nullable object after a field in a long chain of non-null fields,that returns null,ported,test/execution/nonnull_test.dart,
 execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the first nullable object after a field in a long chain of non-null fields,that throws,ported,test/execution/nonnull_test.dart,
 execution/__tests__/nonnull-test.ts,Execute: handles non-nullable types > nulls the top level if non-nullable field,that returns null,ported,test/execution/nonnull_test.dart,
@@ -88,7 +88,7 @@ execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value
 execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles errors from `completeValue` in AsyncIterables,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
 execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles promises from `completeValue` in AsyncIterables,adapted,test/execution/lists_test.dart,The list is a sync Iterable of objects (async iterables are not list values) and the String field returns the index as text (no number-to-string coercion).
 execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles rejected promises from `completeValue` in AsyncIterables,adapted,test/execution/lists_test.dart,The list is a sync Iterable of objects (async iterables are not list values) and the String field returns the index as text (no number-to-string coercion).
-execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,handles mixture of sync and async errors in AsyncIterables,adapted,test/execution/lists_test.dart,"The list is a sync Iterable of objects, the index is returned as text, and the late error of the first item is in the response (the executor waits for started resolvers)."
+execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,handles mixture of sync and async errors in AsyncIterables,adapted,test/execution/lists_test.dart,"The list is a sync Iterable of objects, the index is returned as text, and the late error of the first item is in the response (the executor waits for started resolvers). The errors are in document order, not completion order."
 execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Handles nulls yielded by async generator,adapted,test/execution/lists_test.dart,"The values come from a sync Iterable generator, not an async one."
 execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Returns async iterable when list nulls,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
 execution/__tests__/lists-test.ts,Execute: Accepts async iterables as list value,Ignores error on return method when async iterator nulls,skipped,,"Async iterables are not list values: a list completes from an Iterable (streams are @stream territory, M14)."
```

In `packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,24 +22,21 @@ final class AbstractResolution {
       throw StateError('"${type.name}" has no abstract type binding.');
     }
     final ObjectTypeDef<Object?>? chosen;
+    final String? problem;
     try {
       chosen = _choose(binding.resolveType, binding.possibleTypes, value);
+      // `isTypeOf` runs here too, so it is inside the guard.
+      problem = chosen == null
+          ? null
+          : _impossibility(binding, chosen, type, value);
     } on Object catch (error, stackTrace) {
       _run.reporter.thrown(error, stackTrace, site);
       return null;
     }
     if (chosen == null) {
-      _run.reporter.fieldError(
-        DiagnosticCode.unresolvedAbstractType,
-        'Abstract type "${type.name}" must resolve to an Object type at '
-        'runtime for field "${site.fieldLabel}". Either the "${type.name}" '
-        'type should provide a "resolveType" function or each possible type '
-        'should provide an "isTypeOf" function.',
-        site,
-      );
+      _unresolved(type, site);
       return null;
     }
-    final problem = _impossibility(binding, chosen, type, value);
     if (problem != null) {
       _run.reporter.fieldError(
         DiagnosticCode.impossibleRuntimeType,
@@ -54,6 +51,16 @@ final class AbstractResolution {
     };
   }
 
+  void _unresolved(SchemaType type, CompletionSite site) =>
+      _run.reporter.fieldError(
+        DiagnosticCode.unresolvedAbstractType,
+        'Abstract type "${type.name}" must resolve to an Object type at '
+        'runtime for field "${site.fieldLabel}". Either the "${type.name}" '
+        'type should provide a "resolveType" function or each possible type '
+        'should provide an "isTypeOf" function.',
+        site,
+      );
+
   // The message of a GQL334, else null: [chosen] must be a possible type and,
   // when it came from `resolveType`, must hold the value.
   String? _impossibility(
@@ -62,7 +69,7 @@ final class AbstractResolution {
     SchemaType type,
     Object value,
   ) {
-    if (!binding.possibleTypes.contains(chosen)) {
+    if (!binding.isPossible(chosen)) {
       return 'Runtime Object type "${chosen.name}" is not a possible type '
           'for "${type.name}".';
     }
```

In `packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,15 +8,21 @@ final class AbstractTypeBinding {
     this.name,
     this.resolveType,
     List<ObjectTypeDef<Object?>> possibleTypes,
-  ) : possibleTypes = List.unmodifiable(possibleTypes);
+  ) : possibleTypes = List.unmodifiable(possibleTypes),
+      _possibleSet = Set.identity()..addAll(possibleTypes);
 
   /// The abstract type's name.
   final String name;
 
+  final Set<ObjectTypeDef<Object?>> _possibleSet;
+
   /// The explicit type resolution, null for the default (the first possible
   /// type that accepts the value).
   final ObjectTypeDef<Object?> Function(Object? value)? resolveType;
 
   /// The object types that can be a value, in schema order.
   final List<ObjectTypeDef<Object?>> possibleTypes;
+
+  /// Whether [type] is one of the [possibleTypes].
+  bool isPossible(ObjectTypeDef<Object?> type) => _possibleSet.contains(type);
 }
```

In `packages/typed_graphql_server/lib/src/execution/error_log.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,8 +11,15 @@ final class ErrorLog {
   /// What an error does to the execution.
   final ErrorBehavior behavior;
 
-  /// The errors recorded so far.
-  final List<GraphQLError> errors = [];
+  final List<_Entry> _entries = [];
+
+  /// The errors recorded so far in document order: by the position of their
+  /// path (see `ResponsePath.orderKey`), the order of recording for equal
+  /// positions.
+  List<GraphQLError> get errors {
+    final sorted = [..._entries]..sort(_Entry.compare);
+    return [for (final entry in sorted) entry.error];
+  }
 
   /// The error that ended the execution; null while it runs on.
   GraphQLError? haltError;
@@ -20,12 +27,13 @@ final class ErrorLog {
   /// Whether the execution has ended: nothing more is started or recorded.
   bool get isHalted => haltError != null;
 
-  /// Records [error]; under [ErrorBehavior.halt] it also ends the execution.
-  void record(GraphQLError error) {
+  /// Records [error] found at the document position [order]; under
+  /// [ErrorBehavior.halt] it also ends the execution.
+  void record(GraphQLError error, [List<int> order = const []]) {
     if (isHalted) {
       return;
     }
-    errors.add(error);
+    _entries.add(_Entry(error, order, _entries.length));
     if (behavior == ErrorBehavior.halt) {
       haltError = error;
     }
@@ -36,7 +44,31 @@ final class ErrorLog {
     if (isHalted) {
       return;
     }
-    errors.add(error);
+    _entries.add(_Entry(error, const [], _entries.length));
     haltError = error;
   }
 }
+
+class _Entry {
+  _Entry(this.error, this.order, this.sequence);
+
+  final GraphQLError error;
+  final List<int> order;
+  final int sequence;
+
+  // Sort is not stable, so the sequence breaks ties.
+  static int compare(_Entry a, _Entry b) {
+    final shared = a.order.length < b.order.length
+        ? a.order.length
+        : b.order.length;
+    for (var i = 0; i < shared; i++) {
+      if (a.order[i] != b.order[i]) {
+        return a.order[i].compareTo(b.order[i]);
+      }
+    }
+    if (a.order.length != b.order.length) {
+      return a.order.length.compareTo(b.order.length);
+    }
+    return a.sequence.compareTo(b.sequence);
+  }
+}
```

In `packages/typed_graphql_server/lib/src/execution/error_reporter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,7 +22,10 @@ final class ErrorReporter {
 
   /// Records an error the library makes at [site].
   void fieldError(DiagnosticCode code, String message, CompletionSite site) =>
-      log.record(_coded(code, message, site.path, site.plan.nodes));
+      log.record(
+        _coded(code, message, site.path, site.plan.nodes),
+        site.path.orderKey(),
+      );
 
   /// Ends the execution with an error the library makes at [site].
   void halt(DiagnosticCode code, String message, CompletionSite site) =>
@@ -49,6 +52,7 @@ final class ErrorReporter {
       thrown == null
           ? reported
           : hooked(thrown.error, thrown.stackTrace, reported),
+      path?.orderKey() ?? const [],
     );
   }
 
@@ -56,7 +60,10 @@ final class ErrorReporter {
   void thrown(Object error, StackTrace stackTrace, CompletionSite site) {
     final path = site.path;
     final nodes = site.plan.nodes;
-    log.record(hooked(error, stackTrace, _reportedFor(error, path, nodes)));
+    log.record(
+      hooked(error, stackTrace, _reportedFor(error, path, nodes)),
+      path.orderKey(),
+    );
   }
 
   /// [reported] after `ExecutionOptions.onError` has seen it: the hook's
```

In `packages/typed_graphql_server/lib/src/execution/execution_limits.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -30,14 +30,21 @@ final class ExecutionLimits {
       );
       return false;
     }
-    if (site.depth > _options.maxDepth) {
-      _reporter.fieldError(
-        DiagnosticCode.maxExecutionDepthExceeded,
-        'Execution exceeds the maximum depth of ${_options.maxDepth}.',
-        site,
-      );
-      return false;
+    return admitsDepth(site);
+  }
+
+  /// Whether the place [site] is within `maxDepth`; a refusal is already
+  /// reported as a field error. Costs no step, so a field can be refused
+  /// before its resolver runs.
+  bool admitsDepth(CompletionSite site) {
+    if (site.depth <= _options.maxDepth) {
+      return true;
     }
-    return true;
+    _reporter.fieldError(
+      DiagnosticCode.maxExecutionDepthExceeded,
+      'Execution exceeds the maximum depth of ${_options.maxDepth}.',
+      site,
+    );
+    return false;
   }
 }
```

In `packages/typed_graphql_server/lib/src/execution/field_execution.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -23,15 +23,21 @@ final class FieldExecution {
   final ExecutionRun _run;
 
   /// The response value of [plan] on [parent], with the parent's response
-  /// path [parentPath] and the field's [depth]. Dart `null` when the field
-  /// failed at a non-null position, `JsonNull` for a null that stays.
+  /// path [parentPath], the field's [depth] and its [position] among the
+  /// object's fields. Dart `null` when the field failed at a non-null
+  /// position, `JsonNull` for a null that stays.
   FutureOr<JsonValue?> execute(
     Object? parent,
     FieldPlan plan,
     ResponsePath parentPath,
     int depth,
+    int position,
   ) {
-    final site = CompletionSite(plan, parentPath.key(plan.responseKey), depth);
+    final site = CompletionSite(
+      plan,
+      parentPath.key(plan.responseKey, position),
+      depth,
+    );
     final field = plan.field;
     if (field == null) {
       return _metaField(plan, site);
@@ -58,15 +64,23 @@ final class FieldExecution {
       'The introspection field "${plan.fieldName}" is not available.',
       site,
     );
-    return const JsonNull();
+    return _run.settle(_metaFieldType(plan.fieldName), null);
   }
 
+  // `__schema` is non-null, `__type` nullable (September2025 4.1.4).
+  TypeRef _metaFieldType(String fieldName) => fieldName == '__schema'
+      ? const NonNullType(NamedType(Name('__Schema')))
+      : const NamedType(Name('__Type'));
+
   FutureOr<JsonValue?> _resolve(
     Object? parent,
     FieldDef<Object?, Object?> definition,
     TypeRef type,
     CompletionSite site,
   ) {
+    if (!_run.limits.admitsDepth(site)) {
+      return _run.settle(type, null);
+    }
     final arguments = _argumentsOf(definition, site);
     if (arguments == null) {
       return _run.settle(type, null);
@@ -91,7 +105,14 @@ final class FieldExecution {
     TypeRef type,
     Object? value,
     CompletionSite site,
-  ) => _run.settle(type, _run.values.complete(type, value, site));
+  ) {
+    try {
+      return _run.settle(type, _run.values.complete(type, value, site));
+    } on Object catch (error, stackTrace) {
+      // User code runs during completion too (isTypeOf, resolveType, codecs).
+      return _failed(error, stackTrace, type, site);
+    }
+  }
 
   FutureOr<JsonValue?> _failed(
     Object error,
```

In `packages/typed_graphql_server/lib/src/execution/leaf_completion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -33,10 +33,13 @@ final class LeafCompletion {
         site,
       );
     } on Object catch (error, stackTrace) {
-      if (error is ArgumentError) {
+      // A codec says "cannot represent" with an `ArgumentError` (R2.9), and
+      // its message reaches the client. A `RangeError` is an `ArgumentError`
+      // too, but a bug in the codec, so it stays masked.
+      if (error is ArgumentError && error is! RangeError) {
         _run.reporter.fieldError(
           DiagnosticCode.unserializableValue,
-          '${error.message}',
+          '${error.message ?? error}',
           site,
         );
       } else {
```

In `packages/typed_graphql_server/lib/src/execution/list_completion.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,21 +22,21 @@ final class ListCompletion {
     CompletionSite site,
   ) {
     if (value is! Iterable<Object?>) {
-      _run.reporter.fieldError(
-        DiagnosticCode.unexpectedValue,
-        'Expected Iterable, but did not find one for field '
-        '"${site.fieldLabel}".',
-        site,
-      );
-      return null;
+      return _notIterable(site);
     }
     final pending = PendingValues();
     try {
       var index = 0;
       for (final item in value) {
+        final itemSite = site.itemAt(index);
+        // Items are one level deeper than the list and all alike: the first
+        // one refuses for the whole list, once, instead of one error each.
+        if (index == 0 && !_run.limits.admitsDepth(itemSite)) {
+          return null;
+        }
         final completed = _run.settle(
           type.type,
-          _run.values.complete(type.type, item, site.itemAt(index)),
+          _run.values.complete(type.type, item, itemSite),
         );
         if (completed == null || _run.reporter.log.isHalted) {
           return pending.abandon();
@@ -51,4 +51,14 @@ final class ListCompletion {
     }
     return pending.finishWith(JsonArray.new);
   }
+
+  JsonValue? _notIterable(CompletionSite site) {
+    _run.reporter.fieldError(
+      DiagnosticCode.unexpectedValue,
+      'Expected Iterable, but did not find one for field '
+      '"${site.fieldLabel}".',
+      site,
+    );
+    return null;
+  }
 }
```

In `packages/typed_graphql_server/lib/src/execution/pending_values.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,9 +12,6 @@ import 'package:typed_graphql/typed_graphql.dart';
 final class PendingValues {
   final List<FutureOr<JsonValue?>> _values = [];
 
-  /// How many values were added.
-  int get length => _values.length;
-
   /// Adds the next value.
   void add(FutureOr<JsonValue?> value) => _values.add(value);
 
```

In `packages/typed_graphql_server/lib/src/execution/response_path.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,24 +6,26 @@ import 'package:typed_graphql/typed_graphql.dart';
 ///
 /// {@category execution}
 final class ResponsePath {
-  const ResponsePath._(this._parent, this._segment, this.length);
+  const ResponsePath._(this._parent, this._segment, this.length, this._order);
 
   /// The empty path, the root of `data`.
-  static const ResponsePath root = ResponsePath._(null, null, 0);
+  static const ResponsePath root = ResponsePath._(null, null, 0, 0);
 
   final ResponsePath? _parent;
   final PathSegment? _segment;
+  final int _order;
 
   /// How many segments the path has.
   final int length;
 
-  /// This path followed by the response name [name].
-  ResponsePath key(String name) =>
-      ResponsePath._(this, PathKey(name), length + 1);
+  /// This path followed by the response name [name], the field at
+  /// [position] among the fields collected for the object (document order).
+  ResponsePath key(String name, int position) =>
+      ResponsePath._(this, PathKey(name), length + 1, position);
 
   /// This path followed by the list index [position].
   ResponsePath index(int position) =>
-      ResponsePath._(this, PathIndex(position), length + 1);
+      ResponsePath._(this, PathIndex(position), length + 1, position);
 
   /// The segments from the root.
   List<PathSegment> toList() {
@@ -36,6 +38,20 @@ final class ResponsePath {
     return segments.reversed.toList(growable: false);
   }
 
+  /// The place of the path in document order: the position of each segment
+  /// from the root. Comparing two of them lexicographically orders the
+  /// errors of a response (September2025 7.1.2 asks for none; the library
+  /// answers in document order so a response does not depend on timing).
+  List<int> orderKey() {
+    final positions = <int>[];
+    for (ResponsePath? step = this; step != null; step = step._parent) {
+      if (step._segment != null) {
+        positions.add(step._order);
+      }
+    }
+    return positions.reversed.toList(growable: false);
+  }
+
   @override
   String toString() => toList().join('.');
 }
```

In `packages/typed_graphql_server/lib/src/execution/selection_executor.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -27,11 +27,17 @@ final class SelectionExecutor {
     int depth,
   ) {
     final pending = PendingValues();
-    for (final field in node.fields) {
+    for (var i = 0; i < node.fields.length; i++) {
       if (_run.reporter.log.isHalted) {
         return pending.abandon();
       }
-      final result = _run.fields.execute(parent, field, path, depth);
+      final result = _run.fields.execute(
+        parent,
+        node.fields[i],
+        path,
+        depth,
+        i,
+      );
       if (result == null) {
         return pending.abandon();
       }
```

In `packages/typed_graphql_server/lib/src/execution/serial_fields.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -31,7 +31,13 @@ final class SerialFields {
       if (_run.reporter.log.isHalted) {
         return null;
       }
-      final result = _run.fields.execute(_parent, fields[i], _path, _depth);
+      final result = _run.fields.execute(
+        _parent,
+        fields[i],
+        _path,
+        _depth,
+        i,
+      );
       if (result is Future<JsonValue?>) {
         return result.then((resolved) => _after(i, resolved));
       }
```

In `packages/typed_graphql_server/lib/src/plan/field_accumulator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,7 +12,8 @@ final class FieldAccumulator {
   // again after a deferred visit) is kept once.
   final Set<Field> _nodes;
 
-  /// Whether every node added so far is deferred.
+  /// Whether every node added so far is deferred (read by M14, incremental
+  /// delivery, through `FieldPlan.isDeferred`).
   bool isDeferred;
 
   /// Adds [node]; the key stays deferred only while every node is.
```

In `packages/typed_graphql_server/lib/src/plan/field_plan.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -44,7 +44,7 @@ final class FieldPlan {
 
   /// Whether every field node of the key sits in a fragment with
   /// `@defer` (and an `if` that is not false). Deferred fields run inline
-  /// in M5.
+  /// in M5; incremental delivery (M14) reads this.
   final bool isDeferred;
 
   /// What collection reads, kept to collect the children.
```

In `packages/typed_graphql_server/lib/src/plan/plan_cache.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'lru_map.dart';
@@ -20,9 +21,11 @@ final class PlanCache(
   int _misses = 0;
 
   /// How many lookups found a plan.
+  @visibleForTesting
   int get hitCount => _hits;
 
   /// How many lookups found none.
+  @visibleForTesting
   int get missCount => _misses;
 
   /// The number of plans held.
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/execution/completion_failures_test.dart test/builder/fields_test.dart test/execution/limits_and_order_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/execution/executor_errors_test.dart test/execution/lists_test.dart test/execution/nonnull_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -626,9 +626,11 @@ README that leaves the package folder is an absolute URL.
   `packages/typed_graphql/example/example.dart`. The documentation suite is
   `packages/typed_graphql/test/doc/`.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
-- Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`,
-  `mapping/schema.csv`, `mapping/validation.csv` and `mapping/execution.csv`, checked by
-  `test/mapping_test.dart` there; port helpers in its `test/support/`
+- Conformance mapping tables:
+  `packages/typed_graphql_conformance/mapping/language.csv`,
+  `mapping/schema.csv`, `mapping/validation.csv` and
+  `mapping/execution.csv`, checked by `test/mapping_test.dart` there; port
+  helpers in its `test/support/`
   (`SchemaPort` for the schema suites, `ValidationPort` for
   `validateSchema`, `IntrospectionPort` for `buildClientSchema`,
   `RulePort` for the validation rule suites, `ExecutionPort` for the
```

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- The errors of a response come in document order whatever finished first. A
  throw while completing a value (`isTypeOf`, `resolveType`, a codec, a lazy
  iterable) is a field error, never a thrown `execute`. A codec's
  `ArgumentError` is `GQL332` with its message; a `RangeError` is masked. A
  too-deep field runs no resolver, and a too-deep list reports `GQL336` once.
```

In `packages/typed_graphql_server/doc/execution.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,9 +2,9 @@
 
 `ExecutableSchema<C>.execute` runs a validated document against the schema
 the builder made and answers with a response value. It builds on the Schema
-Builder guide's schemas and on the core's parsing and validation: `execute` takes a `ValidDocument`, the typestate that
-`DocumentValidator` returns for a document it accepted, so an unchecked
-document cannot reach it.
+Builder guide's schemas and on the core's parsing and validation: `execute`
+takes a `ValidDocument`, the typestate that `DocumentValidator` returns for
+a document it accepted, so an unchecked document cannot reach it.
 
 ## Executing a request
 
@@ -70,14 +70,17 @@ gives errors their `locations`), `errorBehavior`, `maskErrors`, `onError`,
 
 Mutation root fields run one after another, as the specification asks. In
 every other selection set the fields are started in document order, and the
-ones that wait are waited for together.
+ones that wait are waited for together. The `errors` of the response are in
+document order too, whichever field finished first.
 
 ## Variables and request errors
 
 Variable values arrive as a `JsonObject` and are coerced against the
 operation's variable definitions before anything runs: defaults apply, a
 missing required variable is refused, and an input object or custom scalar
-goes through its `decode`. Arguments are coerced afterwards, per field, with
+goes through its `decode`. An `InputObjectDef.decode` must return an
+immutable value: constant arguments are decoded once per plan and the value
+is shared across requests. Arguments are coerced afterwards, per field, with
 the variables substituted; constant arguments are coerced once and kept in
 the plan.
 
@@ -312,7 +315,11 @@ halt: {"errors":[{"message":"No name.","path":["user","name"]}],"data":null}
 
 `ExecutionOptions.onError(error, stackTrace, reported)` runs for every error
 thrown by user code (resolvers, middleware, `decode`, codecs), before the
-masked or raw error is recorded. `reported` is what would be recorded;
+masked or raw error is recorded. One exception is by design: a codec's
+`encode` signals "cannot represent this value" (R2.9) with an
+`ArgumentError`, and its message reaches the client as a `GQL332` field
+error, unmasked, so write it for clients. A `RangeError` or any other error
+from a codec is unexpected and stays masked. `reported` is what would be recorded;
 return a `GraphQLError` to replace it, or `null` to keep it. This is where a
 host logs the stack trace that the client never sees, and maps its own
 exception types to codes. A hook that throws is recorded as the masked
@@ -507,8 +514,10 @@ Two options end runaway executions with an error instead of a hung process.
 `maxDepth` (256) bounds how deep completion nests: a value below it is a
 field error `GQL336` and that branch ends. `maxSteps` (10 000 000) bounds the
 work, one step per completed value: past it the execution halts with
-`GQL337` and no data. The parser bounds documents before they get here;
-these two bound what the data makes of them (long lists, a recursive type).
+`data: null` and only the `GQL337` error, dropping the field errors found
+before. A list nested too deep reports `GQL336` once for the list, not for
+each item. The parser bounds documents before they get here; these two
+bound what the data makes of them (long lists and deep list nesting).
 
 The first run of a document plans it: it collects the fields for each
 combination of `@skip`, `@include` and `@defer` conditions, expands every
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
git add CLAUDE.md packages/typed_graphql_conformance/mapping/execution.csv packages/typed_graphql_conformance/test/execution/executor_errors_test.dart packages/typed_graphql_conformance/test/execution/lists_test.dart packages/typed_graphql_conformance/test/execution/nonnull_test.dart packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/execution.md packages/typed_graphql_server/lib/src/execution/abstract_resolution.dart packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart packages/typed_graphql_server/lib/src/execution/error_log.dart packages/typed_graphql_server/lib/src/execution/error_reporter.dart packages/typed_graphql_server/lib/src/execution/execution_limits.dart packages/typed_graphql_server/lib/src/execution/field_execution.dart packages/typed_graphql_server/lib/src/execution/leaf_completion.dart packages/typed_graphql_server/lib/src/execution/list_completion.dart packages/typed_graphql_server/lib/src/execution/pending_values.dart packages/typed_graphql_server/lib/src/execution/response_path.dart packages/typed_graphql_server/lib/src/execution/selection_executor.dart packages/typed_graphql_server/lib/src/execution/serial_fields.dart packages/typed_graphql_server/lib/src/plan/field_accumulator.dart packages/typed_graphql_server/lib/src/plan/field_plan.dart packages/typed_graphql_server/lib/src/plan/plan_cache.dart packages/typed_graphql_server/test/builder/fields_test.dart packages/typed_graphql_server/test/execution/completion_failures_test.dart packages/typed_graphql_server/test/execution/limits_and_order_test.dart
git commit -q -m "fix(typed_graphql_server): address the M5b review" \
  -m "Completion failures from user code (isTypeOf, resolveType, codecs) become field errors, errors come in document order, and a too-deep field runs no resolver." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

- The full list, with recommendations, is section 21 of the spec. M5b follows these recommendations: `extensions.code` on every library-made error (question 4), `@defer` / `@stream` run inline (question 5), `maxSteps` 10 000 000 by default (question 7), and the codes added in one core commit at the start of the sub-stage (question 9).
- `resolveType` and `isTypeOf` are synchronous and take only the value (found in M5b). The alternative is `FutureOr<ObjectTypeDef> Function(P, C)`, at the cost of a future per abstract value.

## Self-review

- Spec coverage: sections 4 (coercion) by Tasks 2-3 and 11; 5 (plans) by Task 4; 6-7 (execution, errors) by Tasks 5-6; 8 (middleware) by Task 7; 15 (codes) by Tasks 1-7; 19 (conformance) by Tasks 8-9 and 12-13; 18 (deviations) by Task 14; 20 (documents) by Task 15. Task 17 is the review round, kept as its own commit so the plan's code is the code that was verified.
- Every code block is the committed text that passed the green check; no placeholder remains. Tasks 8, 9 and 11 hold the server fixes the ports found, kept with the port that found them.
- Names are consistent across tasks: `VariableCoercion`, `ArgumentCoercion`, `CoercionProblem`, `OperationPlanner`, `OperationPlan`, `PlanNode`, `FieldPlan`, `PlanCache`, `ExecutionOptions`, `ErrorBehavior`, `ResponsePath`, `FieldMiddleware`.

## After the plan

M5c (`2026-10-15-m5c-introspection-and-subscriptions.md`) answers `__schema` / `__type` (which give a `GQL330` field error until then) and adds `subscribe`. Merging `m5-final` into `main` and pushing need the owner's explicit yes.
