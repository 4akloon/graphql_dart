# M10c Operations and Fragments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The selection planner (field collection, applicability, variants, fragment accessors, conditions) and the code it drives: data and fragment classes (R7.3, R7.4), sealed classes for abstract selections (R7.5), variables classes (R7.7), operation classes with the minified document and its SHA-256 (R7.9), the persisted-operations manifest, the name checks of operations and fragments (`GQL507`, `GQL504` at a subscription root), the guide; then the fixes of the M10c review (`GQL511`, class sharing, `JsonMerger`, conditional `__typename`, `__schema`/`__type`).

**Architecture:** The planner works on the validated project document with explicit stacks. `FieldCollector` merges the fields of a selection by response name with the fragments and `@include`/`@skip` conditions that apply (`Applicability` decides, per possible type, whether a type condition applies to a base or narrows); `ShapePlanner` turns an operation or fragment into a flat list of `PlannedClass`es, once per definition, sharing a nested class when its type, selection nodes and conditions are the same (`ClassRegistry`), and stops at 10000 classes (`GQL511`). A selection on an abstract type that tells types apart plans a sealed base, a class per reached type and an `…Unknown` one. The emitters (`DataClassEmitter`, `PolymorphicBaseEmitter`, `FragmentHolderEmitter`, `OperationEmitter`, `VariablesEmitter`, `DocumentLibraryEmitter`) write a library per document; `OperationText` adds `__typename` and minifies; `PersistedManifest` writes Apollo's manifest.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`; in the codegen package `yaml`, `crypto`, `path`, and in its command line `args`, `glob` and `dart:io`. No `analyzer`, no `dart_style`, no `package:gql`.

**Spec:** `docs/superpowers/specs/2026-10-15-m10-client-codegen-design.md` (sections 6, 7, 9, 10, 11, 16), `docs/requirements.md` R7.3-R7.5, R7.7, R7.9.

**Base:** the M10a and M10b plans applied on `main` at `57f85e8`. M10d (`2026-10-15-m10d-command-line.md`) follows.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` or `bin/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one, examples included.
- Layering (spec section 2): the core gains only `protocol/optional.dart` and the `GQL5xx` codes and still imports no platform library and no package but `meta` (R0.6); `typed_graphql_client` imports only the core; `typed_graphql_codegen` imports the core, `yaml`, `crypto`, `glob`, `path` and `args`.
- **The codegen engine has no `dart:io`.** Only `lib/src/cli/` and `bin/` import it; the engine takes `ProjectFile`s (path and text) and returns diagnostics and `GeneratedFile`s, so the CLI and M9's builder produce the same files. `test/quality/engine_imports_test.dart` checks it, and the barrel exports nothing that reaches `dart:io`.
- **No `analyzer`, no `dart_style`** (R6.5): the emitter lays the code out itself (`DartWriter`, 80 columns, `// dart format off` in the header).
- **Generated code passes strict analysis.** Every golden case compiles and passes `dart analyze --fatal-infos` with this repository's `analysis_options.yaml` plus `strict-casts` in a temporary package, and its decode / `toJson` round trip runs (`generated_code_test.dart`, tag `analysis`). Generated code silences no lint.
- Bad input never throws (R0.3): configuration, schema, documents, HTTP responses and files become diagnostics with a stable code and a place, or a `DecodeFailure` with a path. Only programmer errors throw (`ArgumentError`, `RangeError`, `StateError`).
- **No recursion over a document, a type or a plan.** Every walk uses an explicit stack (deep input overflows the stack on the web long before the VM); generated decoders nest one call per selection level, bounded by the parser's depth limit.
- **Deterministic output** (R7.10): inputs sorted by path, declarations in document order, schema types, imports and manifest entries sorted; no hash-ordered collection is iterated for output.
- New codes go into `DiagnosticCode` in id order, with a doc comment, in their own `feat(typed_graphql)` commit before the commit that first reports them. The final numbering is `GQL500`-`GQL511` (spec section 9).
- Public API goes through each package's barrel, each exported type tagged with its dartdoc category (`codegen`, `operations` for the client, `protocol` for `Optional`); internal collaborators stay out of it.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart test`, `dart analyze`, `dart format`, `dart doc` and `dart pub` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time; the M10 suites are the core's, `typed_graphql_client`'s and `typed_graphql_codegen`'s, and the codegen analysis test starts `dart pub get`, `dart analyze` and `dart run` in a temporary package. Chrome cannot start under `ulimit -v`; bound the browser runs (core and client only) by resident memory: `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome …`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each is the content of a commit on the branch `m10-final` that passed the green check. A CHANGELOG change is "Append to". If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- Golden files (`test/goldens/<case>/`: `*.dart.golden`, `*.txt`, inputs and support files) are test files; `UPDATE_GOLDENS=1 dart test test/golden_test.dart` rewrites the outputs, but the plan gives them as committed.

## Review Focus

1. Deep input never overflows the stack: Task 1, `field_collector_test.dart` "a selection set 1000 inline fragments deep collects"; Task 2, `shape_planner_test.dart` "a selection 500 levels deep plans without overflowing"; Task 6, `operation_text_test.dart` "a chain of 500 fragments does not overflow the stack".
2. A document whose unshared variant fields would give R^depth classes finishes fast: equal nested classes are shared, and past 10000 classes the run stops with `GQL511` (Task 11, `class_sharing_test.dart` "a document that needs more than the limit is cut off", `document_names_test.dart` "an operation that needs too many classes is a GQL511").
3. A class and its fragments selecting overlapping nested fields write all of them in `toJson` (Task 10, `json_merger_test.dart` "merges the fields of nested objects with one key"; the round-trip golden case in Task 11).
4. A user's `__typename` under `@include`/`@skip` is a nullable member and never replaces the one the generator adds (Task 11, `typename_generation_test.dart` "a conditional __typename is a nullable member", `operation_text_test.dart` "a __typename under @include does not stand in for the added one").
5. Unsupported shapes are diagnostics, not broken output: `__schema` (Task 11, `client_generator_test.dart` "__schema is not supported yet"), a sealed fragment at a subscription root (Task 11, `document_names_test.dart` "a sealed fragment is a GQL504 at the spread"), two documents writing one file (Task 7, `generated_names_test.dart` "a file written twice is a GQL507 at the second writer").

## File map

| File | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql_codegen/lib/src/plan/applicability.dart` | Decides how a type condition relates to a parent type (spec §6) | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/collected_selection.dart` | What one level of a selection holds for a parent type | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/condition.dart` | A variable `@include` or `@skip` condition on a selection (spec §3.13) | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/directive_conditions.dart` | Reads the `@include` and `@skip` directives of one selection | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart` | Collects the fields, fragment uses and narrowing conditions of selection sets for a parent type (spec §6) | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/field_group.dart` | Every field node of one response name at one level of a selection | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart` | A named fragment selected at one level of a selection | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/narrowing.dart` | A type condition that narrows an abstract parent | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/selection_source.dart` | A selection set to collect, with the variable conditions it sits under | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/type_condition_match.dart` | How a type condition relates to the parent type it is written in | 1 |
| `packages/typed_graphql_codegen/test/plan/applicability_test.dart` | Tests | 1 |
| `packages/typed_graphql_codegen/test/plan/directive_conditions_test.dart` | Tests | 1 |
| `packages/typed_graphql_codegen/test/plan/field_collector_test.dart` | Tests | 1 |
| `packages/typed_graphql_codegen/test/plan/plan_schema.dart` | Test support | 1 |
| `packages/typed_graphql_codegen/test/support/plan_fixture.dart` | A schema and a valid document, for the planner tests | 1 |
| `packages/typed_graphql_codegen/lib/src/plan/class_names.dart` | Names the classes generated for operations, fragments and selections | 2 |
| `packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart` | What a planned data class is the shape of | 2 |
| `packages/typed_graphql_codegen/lib/src/plan/planned_class.dart` | A class to generate, which refers to other classes by name | 2 |
| `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart` | A field of a planned data class | 2 |
| `packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart` | A fragment a data class spreads, as a member of its holder | 2 |
| `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart` | Plans the classes of an operation or a fragment definition, in emission order, with one work stack and no recursion (spec §6) | 2 |
| `packages/typed_graphql_codegen/test/plan/shape_planner_test.dart` | Tests | 2 |
| `packages/typed_graphql_codegen/test/support/plan_description.dart` | Renders a plan list as text, for tests to compare whole | 2 |
| `packages/typed_graphql_codegen/lib/src/plan/plan_work.dart` | An item of the planner's work stack | 3 |
| `packages/typed_graphql_codegen/lib/src/plan/variant_context.dart` | What a variant class takes from its sealed base | 3 |
| `packages/typed_graphql_codegen/lib/src/plan/variant_reference.dart` | A concrete type of a polymorphic selection and the class generated for it | 3 |
| `packages/typed_graphql_codegen/lib/src/plan/variant_sharing.dart` | Decides what the sealed base of a polymorphic selection declares | 3 |
| `packages/typed_graphql_codegen/test/plan/variant_planner_test.dart` | Tests | 3 |
| `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart` | Writes the doc comment sentence of a planned data class | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart` | Writes the data class of a fragment or of a composite field (spec §7 "Data classes", R7.3) | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart` | A field of a generated data class as it is written | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart` | Writes the library of one document file | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart` | Writes the class that holds the fragments spread on a selection (spec §7 "Data classes", R7.4) | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart` | Records the imports of a generated document library (spec §7 "Files") | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/reader_factory_writer.dart` | Writes the `_read` factory of a generated class | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart` | Writes the `toJson` override of a generated class | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/value_member.dart` | A member that takes part in the value semantics of a generated class | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/value_members.dart` | Writes `==`, `hashCode` and `toString` of a generated class from its [ValueMember]s | 4 |
| `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart` | Generates the library of every document file of a project (spec §7 "Files") | 4 |
| `packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart` | Tests | 4 |
| `packages/typed_graphql_codegen/test/support/class_emission.dart` | Plans the first operation (or the first fragment) of a document and emits one of its classes, for the emitter tests | 4 |
| `packages/typed_graphql_codegen/test/goldens/fragments/` | Golden case (12 new files) | 4 |
| `packages/typed_graphql_codegen/test/goldens/schema_types/` | Golden case (1 new files) | 4 |
| `packages/typed_graphql_codegen/lib/src/emit/fragment_decode_writer.dart` | Writes the static `decode` of a fragment class, the entry point for a fragment read outside an operation | 5 |
| `packages/typed_graphql_codegen/lib/src/emit/polymorphic_base_emitter.dart` | Writes the sealed base of a selection on an abstract type (spec §7 "Data classes", R7.5) | 5 |
| `packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart` | Tests | 5 |
| `packages/typed_graphql_codegen/test/goldens/polymorphic/` | Golden case (10 new files) | 5 |
| `packages/typed_graphql_codegen/lib/src/emit/input_field_members.dart` | Writes the members that input objects and operation variables share | 6 |
| `packages/typed_graphql_codegen/lib/src/emit/operation_decode_writer.dart` | Writes the static `decode` of an operation's data class, the entry point for the `data` of a response | 6 |
| `packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart` | Writes the class of an operation (spec §7 "Operation classes and metadata", R7.9) | 6 |
| `packages/typed_graphql_codegen/lib/src/emit/variables_emitter.dart` | Writes the variables class of an operation (spec §7 "Input objects and variables", R7.7) | 6 |
| `packages/typed_graphql_codegen/lib/src/plan/flag_defaults.dart` | The defaults of the Boolean variables of an operation, which decide a fragment under `@include` or `@skip` when the variable is not sent (spec §6 "Fragments") | 6 |
| `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart` | Writes the document text an operation is sent with (R7.9) | 6 |
| `packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart` | Appends an unaliased `__typename` to the selection set of every field that has one and lacks it (R7.9) | 6 |
| `packages/typed_graphql_codegen/test/emit/operation_emitter_test.dart` | Tests | 6 |
| `packages/typed_graphql_codegen/test/emit/variables_emitter_test.dart` | Tests | 6 |
| `packages/typed_graphql_codegen/test/plan/operation_text_test.dart` | Tests | 6 |
| `packages/typed_graphql_codegen/test/support/operation_fixture.dart` | Test support | 6 |
| `packages/typed_graphql_codegen/test/goldens/operations/` | Golden case (12 new files) | 6 |
| `packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart` | Registers every class the operations and fragments of a project declare in [GeneratedNames], with the members of each (spec §7 "Names") | 7 |
| `packages/typed_graphql_codegen/lib/src/generator/persisted_manifest.dart` | Writes the persisted-operations manifest (R7.9) | 7 |
| `packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart` | `GQL504` | 7 |
| `packages/typed_graphql_codegen/lib/src/plan/root_typename.dart` | Finds out whether the top level of an operation reads an abstract type (R7.9) | 7 |
| `packages/typed_graphql_codegen/test/generator/document_names_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/generator/persisted_manifest_test.dart` | Tests | 7 |
| `packages/typed_graphql_codegen/test/goldens/operations/` | Golden case (1 new files) | 7 |
| `packages/typed_graphql_client/lib/src/operation/json_merger.dart` | Merges the JSON that several generated classes write for one response object (R7.3) | 10 |
| `packages/typed_graphql_client/test/operation/json_merger_test.dart` | Tests | 10 |
| `packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_introspection_rule.dart` | `GQL504` | 11 |
| `packages/typed_graphql_codegen/lib/src/plan/class_registry.dart` | The nested classes planned so far in one run, so that two fields of one type with the same selection nodes share one class | 11 |
| `packages/typed_graphql_codegen/lib/src/plan/field_planner.dart` | Plans one field of a data class, and queues the class of a composite field unless a field of the same type and selection nodes already has one | 11 |
| `packages/typed_graphql_codegen/lib/src/plan/plan_scope.dart` | What planning one class needs besides the class | 11 |
| `packages/typed_graphql_codegen/test/generator/typename_generation_test.dart` | Tests | 11 |
| `packages/typed_graphql_codegen/test/plan/class_sharing_test.dart` | Tests | 11 |
| `packages/typed_graphql_codegen/test/goldens/fragments/` | Golden case (2 new files) | 11 |
| `packages/typed_graphql_codegen/CHANGELOG.md` | Modified | 4, 5, 6, 7, 8, 11 |
| `packages/typed_graphql_codegen/doc/client_codegen.md` | Modified | 4, 5, 6, 7, 8, 11 |
| `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart` | Modified | 4, 7, 11 |
| `packages/typed_graphql_codegen/pubspec.yaml` | Modified | 4, 6 |
| `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart` | Modified | 4, 6, 11 |
| `packages/typed_graphql_codegen/lib/src/emit/input_field.dart` | Modified | 6 |
| `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart` | Modified | 6 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modified | 7, 9 |
| `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart` | Modified | 7, 11 |
| `packages/typed_graphql_codegen/test/generator/client_generator_test.dart` | Modified | 7, 11 |
| `packages/typed_graphql_codegen/test/generator/generated_names_test.dart` | Modified | 7, 11 |
| `packages/typed_graphql_codegen/test/golden_test.dart` | Modified | 7 |
| `llms.txt` | Modified | 8 |
| `packages/typed_graphql_codegen/README.md` | Modified | 8 |
| `packages/typed_graphql/CHANGELOG.md` | Modified | 9 |
| `packages/typed_graphql_client/CHANGELOG.md` | Modified | 10 |
| `packages/typed_graphql_client/doc/operations.md` | Modified | 10 |
| `packages/typed_graphql_client/lib/typed_graphql_client.dart` | Modified | 10 |
| `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart` | Modified | 11 |

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

Run a new test file alone first under the same limits. The core, client and codegen suites include the documentation tests, which run each guide program as a `dart` process; the codegen suite also runs the analysis test (tag `analysis`), which creates a temporary package per golden case. If a run is killed (exit 137) or times out (exit 124), find the cause before going on.

After the last task, also run the M10 packages on every compiler (Chrome only for the core; the client's Chrome runs are deferred to M11 and the codegen package is VM-only):

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 900 dart test --compiler exe test/protocol test/diagnostics)
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js test/protocol)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm test/protocol)
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 900 dart test --compiler exe)
```

Under `--compiler exe` the codegen tests that start the `dart` tool (the analysis test, the CLI exit-code test) skip themselves with a reason: `Platform.resolvedExecutable` is the compiled test, not `dart`.

---

### Task 1: Collect the fields of a selection

The planner's field collection (spec section 6): `Condition` and `DirectiveConditions` read `@include`/`@skip`, `Applicability` decides how a type condition relates to a parent (applies, narrows, never), and `FieldCollector` walks selection sources with an explicit stack, merging fields by response name and recording fragment uses and narrowings.

Commit on the branch: `ab5e1a0`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/plan/applicability.dart`, `packages/typed_graphql_codegen/lib/src/plan/collected_selection.dart`, `packages/typed_graphql_codegen/lib/src/plan/condition.dart`, `packages/typed_graphql_codegen/lib/src/plan/directive_conditions.dart`, `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart`, `packages/typed_graphql_codegen/lib/src/plan/field_group.dart`, `packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart`, `packages/typed_graphql_codegen/lib/src/plan/narrowing.dart`, `packages/typed_graphql_codegen/lib/src/plan/selection_source.dart`, `packages/typed_graphql_codegen/lib/src/plan/type_condition_match.dart`
- Test: `packages/typed_graphql_codegen/test/plan/applicability_test.dart`, `packages/typed_graphql_codegen/test/plan/directive_conditions_test.dart`, `packages/typed_graphql_codegen/test/plan/field_collector_test.dart`, `packages/typed_graphql_codegen/test/plan/plan_schema.dart`, `packages/typed_graphql_codegen/test/support/plan_fixture.dart`

**Interfaces:**
- Consumes: The core `Schema` relations (`possibleTypes`, `isSubType`) and the language nodes; M10a `ProjectDocuments`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// plan/applicability.dart
final class const Applicability(…)
  TypeConditionMatch match(String condition, SchemaType parent)
  List<ObjectType> reach(String condition, SchemaType parent)

// plan/collected_selection.dart
final class CollectedSelection(…)

// plan/condition.dart
final class const Condition(…)
  int get hashCode
  String toString()

// plan/directive_conditions.dart
final class DirectiveConditions
  const DirectiveConditions()
  List<Condition>? of(List<Directive> directives)

// plan/field_collector.dart
final class const FieldCollector(…)
  CollectedSelection collect(SchemaType parent, List<SelectionSource> sources)
final class _GroupBuilder
  final String fieldName
  final SchemaField definition
final class _Run
  final Schema schema
  final Map<String, FragmentDefinition> fragments
  final SchemaType parent
  final Applicability applicability
  CollectedSelection result()
  void visit(SelectionSource source)

// plan/field_group.dart
final class FieldGroup(…)

// plan/fragment_use.dart
final class FragmentUse(…)
  bool get isConditional
  FragmentUse merge(List<Condition> conditions)

// plan/narrowing.dart
final class const Narrowing(…)

// plan/selection_source.dart
final class const SelectionSource(…)

// plan/type_condition_match.dart
enum TypeConditionMatch
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/plan/applicability_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/plan/applicability.dart';
import 'package:typed_graphql_codegen/src/plan/type_condition_match.dart';

import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  final fixture = PlanFixture(planSchema, planNoop);
  final applicability = Applicability(fixture.schema);

  TypeConditionMatch match(String condition, String parent) =>
      applicability.match(condition, fixture.type(parent));

  group('object parent', () {
    test('applies for itself', () {
      expect(match('User', 'User'), TypeConditionMatch.applies);
    });

    test('applies for an interface it implements', () {
      expect(match('Node', 'User'), TypeConditionMatch.applies);
    });

    test('applies for a union it belongs to', () {
      expect(match('Actor', 'User'), TypeConditionMatch.applies);
    });

    test('never for another object', () {
      expect(match('Bot', 'User'), TypeConditionMatch.never);
    });

    test('never for an interface it does not implement', () {
      expect(match('Entity', 'User'), TypeConditionMatch.never);
    });

    test('never for a union it is not in', () {
      expect(match('Thing', 'Bot'), TypeConditionMatch.never);
    });
  });

  group('interface parent', () {
    test('applies for itself', () {
      expect(match('Node', 'Node'), TypeConditionMatch.applies);
    });

    test('applies for an interface it implements', () {
      expect(match('Node', 'Entity'), TypeConditionMatch.applies);
    });

    test('narrows for an implementer', () {
      expect(match('User', 'Node'), TypeConditionMatch.narrows);
    });

    test('narrows for a sibling interface with common implementers', () {
      expect(match('Named', 'Node'), TypeConditionMatch.narrows);
    });

    test('narrows for an interface that implements it', () {
      expect(match('Entity', 'Node'), TypeConditionMatch.narrows);
    });

    test('never for an interface with no common implementer', () {
      expect(match('Entity', 'Named'), TypeConditionMatch.never);
    });
  });

  group('union parent', () {
    test('applies for itself', () {
      expect(match('Actor', 'Actor'), TypeConditionMatch.applies);
    });

    test('narrows for a member', () {
      expect(match('User', 'Actor'), TypeConditionMatch.narrows);
    });

    test('narrows for an interface all its members implement', () {
      expect(match('Node', 'Actor'), TypeConditionMatch.narrows);
    });

    test('narrows for an interface some members implement', () {
      expect(match('Named', 'Actor'), TypeConditionMatch.narrows);
    });

    test('never for a disjoint object', () {
      expect(match('Group', 'Actor'), TypeConditionMatch.never);
    });
  });

  test('reach lists the parent types the condition covers, in order', () {
    expect(
      [
        for (final type in applicability.reach('Named', fixture.type('Node')))
          type.name,
      ],
      ['User'],
    );
  });

  test('reach of a union condition within a union parent', () {
    expect(
      [
        for (final type in applicability.reach('Thing', fixture.type('Actor')))
          type.name,
      ],
      ['User'],
    );
  });

  test('reach of an unknown condition is empty', () {
    expect(applicability.reach('Nope', fixture.type('Node')), isEmpty);
  });
}
```

Create `packages/typed_graphql_codegen/test/plan/directive_conditions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/condition.dart';
import 'package:typed_graphql_codegen/src/plan/directive_conditions.dart';

void main() {
  List<Condition>? read(String directives) {
    final document = const Parser()
        .parse(
          Source(
            r'query ($v: Boolean!, $w: Boolean!) { a '
            '$directives }',
          ),
        )
        .requireDocument();
    final field =
        (document.definitions.single as OperationDefinition)
                .selectionSet
                .selections
                .single
            as Field;
    return const DirectiveConditions().of(field.directives);
  }

  test('no directive adds nothing', () {
    expect(read(''), <Condition>[]);
  });

  test('include(if: false) excludes the selection', () {
    expect(read('@include(if: false)'), isNull);
  });

  test('include(if: true) adds nothing', () {
    expect(read('@include(if: true)'), <Condition>[]);
  });

  test('skip(if: true) excludes the selection', () {
    expect(read('@skip(if: true)'), isNull);
  });

  test('skip(if: false) adds nothing', () {
    expect(read('@skip(if: false)'), <Condition>[]);
  });

  test(r'include(if: $v) is an include condition', () {
    expect(read(r'@include(if: $v)'), [const Condition('v', true)]);
  });

  test(r'skip(if: $v) is a skip condition', () {
    expect(read(r'@skip(if: $v)'), [const Condition('v', false)]);
  });

  test('two variable directives keep their order', () {
    expect(read(r'@skip(if: $w) @include(if: $v)'), [
      const Condition('w', false),
      const Condition('v', true),
    ]);
  });

  test('a literal that excludes wins over a variable', () {
    expect(read(r'@include(if: $v) @skip(if: true)'), isNull);
  });

  test('another directive is ignored', () {
    expect(read('@other'), <Condition>[]);
  });

  test('a condition prints with a bang for skip', () {
    expect(
      [const Condition('v', true), const Condition('v', false)].join(' '),
      r'$v !$v',
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/plan/field_collector_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/collected_selection.dart';
import 'package:typed_graphql_codegen/src/plan/condition.dart';

import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  CollectedSelection collect(
    String body,
    String parent, {
    String field = 'user',
    String fragments = '',
  }) {
    final declared = [
      for (final name in ['v', 'w'])
        if (body.contains('\$$name')) '\$$name: Boolean!',
    ];
    final variables = declared.isEmpty ? '' : '(${declared.join(', ')})';
    final fixture = PlanFixture(
      planSchema,
      'query $variables { $body }\n$fragments',
    );
    return fixture.collector.collect(fixture.type(parent), [
      fixture.sourceOf(field),
    ]);
  }

  List<String> fieldsOf(CollectedSelection selection) => [
    for (final group in selection.fields)
      '${group.responseName}:${group.fieldName}'
          '${group.isConditional ? '?' : ''}x${group.nodes.length}',
  ];

  test('fields merge by response name in first-occurrence order', () {
    final selection = collect('user { name id name }', 'User');
    expect(fieldsOf(selection), ['name:namex2', 'id:idx1']);
  });

  test('an alias keeps a field apart', () {
    final selection = collect('user { name other: name }', 'User');
    expect(fieldsOf(selection), ['name:namex1', 'other:namex1']);
  });

  test('a group knows its schema field', () {
    final selection = collect('user { friend { id } }', 'User');
    expect(selection.fields.single.definition.name, 'friend');
  });

  test('a field with a variable condition is conditional', () {
    final selection = collect(r'user { name @include(if: $v) }', 'User');
    expect(fieldsOf(selection), ['name:name?x1']);
  });

  test('a group is conditional only when every node is', () {
    final selection = collect(
      r'user { name @include(if: $v) name }',
      'User',
    );
    expect(fieldsOf(selection), ['name:namex2']);
  });

  test('a group of conditional nodes is conditional', () {
    final selection = collect(
      r'user { name @include(if: $v) name @skip(if: $w) }',
      'User',
    );
    expect(fieldsOf(selection), ['name:name?x2']);
  });

  test('a field in a conditional inline fragment is conditional', () {
    final selection = collect(
      r'user { ... @include(if: $v) { name } }',
      'User',
    );
    expect(fieldsOf(selection), ['name:name?x1']);
  });

  test('inline fragments without a condition and on the parent merge', () {
    final selection = collect(
      'user { id ... { name } ... on User { name model: id } }',
      'User',
    );
    expect(fieldsOf(selection), ['id:idx1', 'name:namex2', 'model:idx1']);
  });

  test('a condition on an implemented interface applies', () {
    final selection = collect('user { ... on Node { id } }', 'User');
    expect(fieldsOf(selection), ['id:idx1']);
  });

  test('a nested User inside Node under a union narrows', () {
    final selection = collect(
      'actor { ... on Node { id ... on User { name } } }',
      'Actor',
      field: 'actor',
    );
    expect(fieldsOf(selection), isEmpty);
    expect(selection.narrowings.map((n) => n.typeCondition), ['Node']);
  });

  test('a narrowing inside an applied fragment is recorded', () {
    final selection = collect(
      'node { id ... on Node { ... on User { name } } }',
      'Node',
      field: 'node',
    );
    expect(fieldsOf(selection), ['id:idx1']);
    expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
  });

  test('a narrowing inline fragment holds its source', () {
    final selection = collect(
      r'node { ... on User @include(if: $v) { name } }',
      'Node',
      field: 'node',
    );
    final narrowing = selection.narrowings.single;
    expect(narrowing.source!.isConditional, isTrue);
    expect(narrowing.source!.conditions, [const Condition('v', true)]);
  });

  test('a disjoint condition is dropped', () {
    final selection = collect(
      'node { ... on Bot { model } }',
      'User',
      field: 'node',
    );
    expect(selection.narrowings, isEmpty);
    expect(fieldsOf(selection), isEmpty);
  });

  test('a spread becomes a use, not fields', () {
    final selection = collect(
      'user { ...F }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(fieldsOf(selection), isEmpty);
    expect(selection.fragments.single.fragmentName, 'F');
    expect(selection.fragments.single.whenAny, [<Condition>[]]);
    expect(selection.fragments.single.isConditional, isFalse);
  });

  test('a spread of a narrowing fragment is a narrowing', () {
    final selection = collect(
      r'node { ...F @skip(if: $w) }',
      'Node',
      field: 'node',
      fragments: 'fragment F on User { name }',
    );
    final narrowing = selection.narrowings.single;
    expect(narrowing.fragmentName, 'F');
    expect(narrowing.conditions, [const Condition('w', false)]);
    expect(selection.fragments, isEmpty);
  });

  test('a spread inherits the conditions of an inline fragment', () {
    final selection = collect(
      r'user { ... @include(if: $v) { ...F @skip(if: $w) } }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.fragments.single.whenAny, [
      [const Condition('v', true), const Condition('w', false)],
    ]);
  });

  test(
    'a fragment spread twice, unconditional and conditional, is unconditional',
    () {
      final selection = collect(
        r'user { ...F @include(if: $v) ...F }',
        'User',
        fragments: 'fragment F on User { name }',
      );
      expect(selection.fragments.single.whenAny, [<Condition>[]]);
    },
  );

  test('a fragment spread twice under two conditions keeps both', () {
    final selection = collect(
      r'user { ...F @include(if: $v) ...F @skip(if: $w) }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.fragments.single.whenAny, [
      [const Condition('v', true)],
      [const Condition('w', false)],
    ]);
    expect(selection.fragments.single.isConditional, isTrue);
  });

  test('the same condition twice is not repeated', () {
    final selection = collect(
      r'user { ...F @include(if: $v) ...F @include(if: $v) }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.fragments.single.whenAny, [
      [const Condition('v', true)],
    ]);
  });

  test('include(if: false) drops a field, a spread and a fragment', () {
    final selection = collect(
      'user { name @include(if: false) ...F @skip(if: true) '
          '... @include(if: false) { id } }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(fieldsOf(selection), isEmpty);
    expect(selection.fragments, isEmpty);
  });

  test('an aliased __typename is an ordinary String! field', () {
    final selection = collect('user { kind: __typename }', 'User');
    expect(fieldsOf(selection), ['kind:__typenamex1']);
    expect(
      const Printer().print(selection.fields.single.definition.type),
      'String!',
    );
    expect(selection.selectsTypename, isFalse);
  });

  test('an unaliased __typename only sets selectsTypename', () {
    final selection = collect('user { __typename id }', 'User');
    expect(fieldsOf(selection), ['id:idx1']);
    expect(selection.selectsTypename, isTrue);
  });

  test('__typename on a union parent is found', () {
    final selection = collect('actor { __typename }', 'Actor', field: 'actor');
    expect(selection.selectsTypename, isTrue);
  });

  test('a field sub-selection is not walked', () {
    final selection = collect('user { friend { name } }', 'User');
    expect(fieldsOf(selection), ['friend:friendx1']);
  });

  test('several sources collect in order', () {
    final fixture = PlanFixture(
      planSchema,
      'query { user { id } node { id } }',
    );
    final selection = fixture.collector.collect(fixture.type('User'), [
      fixture.sourceOf('user'),
      fixture.sourceOf('node'),
    ]);
    expect(fieldsOf(selection), ['id:idx2']);
  });

  test('a selection set 1000 inline fragments deep collects', () {
    const depth = 1000;
    final body = '${'... on User { ' * depth}name${' }' * depth}';
    final fixture = PlanFixture(
      planSchema,
      'query { user { $body } }',
      maxDepth: null,
    );
    final selection = fixture.collector.collect(fixture.type('User'), [
      fixture.sourceOf('user'),
    ]);
    expect(fieldsOf(selection), ['name:namex1']);
  });
}
```

Create `packages/typed_graphql_codegen/test/plan/plan_schema.dart`:

```dart
/// The schema the planner tests share.
const planSchema = '''
interface Node { id: ID! }
interface Named { name: String }
interface Entity implements Node { id: ID! }
type User implements Node & Named { id: ID!, name: String, friend: User }
type Bot implements Node { id: ID!, model: String }
type Group implements Named { name: String }
type Admin implements Entity & Node { id: ID!, level: Int }
union Actor = User | Bot
union Thing = User | Group
type Query {
  node: Node
  actor: Actor
  user: User
  named: Named
  thing: Thing
}
''';

/// A query that makes the fixture valid whatever the test needs.
const planNoop = 'query { user { id } }';
```

Create `packages/typed_graphql_codegen/test/support/plan_fixture.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/field_collector.dart';
import 'package:typed_graphql_codegen/src/plan/selection_source.dart';

/// A schema and a valid document, for the planner tests.
final class PlanFixture {
  PlanFixture(String sdl, String documentText, {int? maxDepth}) {
    final built = const SchemaBuilder().fromSdl(
      const Parser().parse(Source(sdl)).requireDocument(),
    );
    schema = (built as BuildSuccess).schema;
    document = Parser(
      options: ParserOptions(maxDepth: maxDepth, maxTokens: null),
    ).parse(Source(documentText)).requireDocument();
    final result = const DocumentValidator().validate(
      ValidSchema.assumeValid(schema),
      document,
    );
    if (result is InvalidDocument) {
      throw StateError('Invalid fixture: ${result.diagnostics}');
    }
    for (final definition in document.definitions) {
      if (definition is FragmentDefinition) {
        fragments[definition.name.value] = definition;
      }
    }
  }

  // Assigned in the constructor body, before any use.
  late final Schema schema;
  late final Document document;
  final Map<String, FragmentDefinition> fragments = {};

  FieldCollector get collector => FieldCollector(schema, fragments);

  SchemaType type(String name) => schema.typeNamed(name)!;

  /// The selection set of the first operation.
  SelectionSet get operationSelection =>
      document.definitions.whereType<OperationDefinition>().first.selectionSet;

  /// The selection set of the field `name` in the first operation's set.
  SelectionSet selectionOf(String name) =>
      (operationSelection.selections.whereType<Field>().firstWhere(
        (field) => field.name.value == name,
      )).selectionSet!;

  SelectionSource sourceOf(String name) => SelectionSource(selectionOf(name));
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/plan/applicability_test.dart test/plan/directive_conditions_test.dart test/plan/field_collector_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_codegen/lib/src/plan/applicability.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'type_condition_match.dart';

/// Decides how a type condition relates to a parent type (spec §6).
final class const Applicability(
  /// The schema the types are looked up in.
  final Schema schema,
) {
  /// Creates the decision for [schema].
  this;

  /// How [condition] relates to [parent].
  ///
  /// For an abstract parent only a condition that names it, or an interface
  /// it implements, applies: a condition on a union member or on an
  /// interface the current members happen to implement narrows, so a type
  /// added to the schema later is still covered by the shared fields.
  TypeConditionMatch match(String condition, SchemaType parent) {
    if (condition == parent.name) {
      return TypeConditionMatch.applies;
    }
    final target = schema.typeNamed(condition);
    if (target == null) {
      return TypeConditionMatch.never;
    }
    return switch (parent) {
      ObjectType() =>
        schema.possibleTypes(target).any((type) => identical(type, parent))
            ? TypeConditionMatch.applies
            : TypeConditionMatch.never,
      InterfaceType()
          when target is InterfaceType && schema.isSubType(target, parent) =>
        TypeConditionMatch.applies,
      InterfaceType() || UnionType() =>
        schema.typesOverlap(target, parent)
            ? TypeConditionMatch.narrows
            : TypeConditionMatch.never,
      _ => TypeConditionMatch.never,
    };
  }

  /// The possible types of [parent], in `possibleTypes` order, that are
  /// possible types of [condition].
  List<ObjectType> reach(String condition, SchemaType parent) {
    final target = schema.typeNamed(condition);
    if (target == null) {
      return const [];
    }
    final reached = schema.possibleTypes(target);
    return [
      for (final type in schema.possibleTypes(parent))
        if (reached.any((other) => identical(other, type))) type,
    ];
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/collected_selection.dart`:

```dart
import 'field_group.dart';
import 'fragment_use.dart';
import 'narrowing.dart';

/// What one level of a selection holds for a parent type.
final class CollectedSelection(
  /// The fields by response name, in first-occurrence order.
  List<FieldGroup> fields,

  /// The fragments selected, in first-occurrence order.
  List<FragmentUse> fragments,

  /// The conditions that narrow an abstract parent, in document order.
  List<Narrowing> narrowings, {

  /// Whether an unaliased `__typename` was selected at this level; it is
  /// not a [FieldGroup].
  final bool selectsTypename = false,
}) {
  /// Creates a collected selection.
  this;

  /// The fields by response name, in first-occurrence order.
  final List<FieldGroup> fields = List.unmodifiable(fields);

  /// The fragments selected, in first-occurrence order.
  final List<FragmentUse> fragments = List.unmodifiable(fragments);

  /// The conditions that narrow an abstract parent, in document order.
  final List<Narrowing> narrowings = List.unmodifiable(narrowings);
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/condition.dart`:

```dart
/// A variable `@include` or `@skip` condition on a selection (spec §3.13).
final class const Condition(
  /// The variable name, without the `$`.
  final String variable,

  /// Whether it is `@include(if: $variable)`: selected when the variable is
  /// true. False for `@skip`, selected when the variable is false.
  final bool isInclude,
) {
  /// Creates a condition.
  this;

  @override
  bool operator ==(Object other) =>
      other is Condition &&
      other.variable == variable &&
      other.isInclude == isInclude;

  @override
  int get hashCode => Object.hash(variable, isInclude);

  @override
  String toString() => isInclude ? '\$$variable' : '!\$$variable';
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/directive_conditions.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'condition.dart';

/// Reads the `@include` and `@skip` directives of one selection.
final class DirectiveConditions {
  /// Creates the reader.
  const DirectiveConditions();

  /// The variable conditions of [directives], in directive order; null when
  /// a literal argument excludes the selection (`@include(if: false)`,
  /// `@skip(if: true)`). A literal that keeps the selection adds nothing.
  List<Condition>? of(List<Directive> directives) {
    final conditions = <Condition>[];
    for (final directive in directives) {
      final name = directive.name.value;
      if (name != 'include' && name != 'skip') {
        continue;
      }
      final isInclude = name == 'include';
      switch (_ifArgument(directive)) {
        case BooleanValue(:final value):
          if (value != isInclude) {
            return null;
          }
        case Variable(:final name):
          conditions.add(Condition(name.value, isInclude));
        case _:
          break;
      }
    }
    return conditions;
  }

  Value? _ifArgument(Directive directive) {
    for (final argument in directive.arguments) {
      if (argument.name.value == 'if') {
        return argument.value;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'applicability.dart';
import 'collected_selection.dart';
import 'condition.dart';
import 'directive_conditions.dart';
import 'field_group.dart';
import 'fragment_use.dart';
import 'narrowing.dart';
import 'selection_source.dart';
import 'type_condition_match.dart';

/// Collects the fields, fragment uses and narrowing conditions of selection
/// sets for a parent type (spec §6). It walks with an explicit stack.
final class const FieldCollector(
  /// The schema the fields are looked up in.
  final Schema schema,

  /// The fragment definitions of the project, by name.
  final Map<String, FragmentDefinition> fragments,
) {
  /// Creates a collector.
  this;

  /// Collects [sources], in order, for [parent].
  CollectedSelection collect(SchemaType parent, List<SelectionSource> sources) {
    final run = _Run(schema, fragments, parent);
    for (final source in sources) {
      run.visit(source);
    }
    return run.result();
  }
}

typedef _Pending = (Selection, bool, List<Condition>);

final class _GroupBuilder {
  _GroupBuilder(this.fieldName, this.definition);

  final String fieldName;
  final SchemaField definition;
  final List<Field> nodes = [];
  bool isConditional = true;
}

final class _Run {
  _Run(this.schema, this.fragments, this.parent)
    : applicability = Applicability(schema);

  static const _conditions = DirectiveConditions();

  final Schema schema;
  final Map<String, FragmentDefinition> fragments;
  final SchemaType parent;
  final Applicability applicability;
  final Map<String, _GroupBuilder> groups = {};
  final Map<String, FragmentUse> uses = {};
  final List<Narrowing> narrowings = [];
  bool selectsTypename = false;

  CollectedSelection result() => CollectedSelection(
    [
      for (final MapEntry(key: responseName, value: group) in groups.entries)
        FieldGroup(
          responseName,
          group.fieldName,
          group.nodes,
          isConditional: group.isConditional,
          definition: group.definition,
        ),
    ],
    uses.values.toList(),
    narrowings,
    selectsTypename: selectsTypename,
  );

  void visit(SelectionSource source) {
    final stack = <_Pending>[];
    void push(SelectionSet set, bool isConditional, List<Condition> held) {
      for (final selection in set.selections.reversed) {
        stack.add((selection, isConditional, held));
      }
    }

    push(source.selectionSet, source.isConditional, source.conditions);
    while (stack.isNotEmpty) {
      final (selection, isConditional, held) = stack.removeLast();
      final own = _conditions.of(switch (selection) {
        Field(:final directives) ||
        FragmentSpread(:final directives) ||
        InlineFragment(:final directives) => directives,
      });
      if (own == null) {
        continue;
      }
      final all = [...held, ...own];
      final isNowConditional = isConditional || own.isNotEmpty;
      switch (selection) {
        case Field():
          _field(selection, isNowConditional);
        case InlineFragment():
          final inner = _inline(selection, isNowConditional, all);
          if (inner != null) {
            push(inner.selectionSet, isNowConditional, all);
          }
        case FragmentSpread():
          _spread(selection, all);
      }
    }
  }

  /// The inline fragment's source when it applies to the parent; a
  /// narrowing is recorded here, a `never` fragment is dropped.
  SelectionSource? _inline(
    InlineFragment fragment,
    bool isConditional,
    List<Condition> conditions,
  ) {
    final name = fragment.typeCondition?.name.value ?? parent.name;
    final source = SelectionSource(
      fragment.selectionSet,
      isConditional: isConditional,
      conditions: conditions,
    );
    switch (applicability.match(name, parent)) {
      case TypeConditionMatch.applies:
        return source;
      case TypeConditionMatch.narrows:
        narrowings.add(Narrowing(name, source: source));
      case TypeConditionMatch.never:
        break;
    }
    return null;
  }

  void _field(Field field, bool isConditional) {
    final fieldName = field.name.value;
    final responseName = field.alias?.value ?? fieldName;
    if (field.alias == null && fieldName == '__typename') {
      selectsTypename = true;
      return;
    }
    final definition = _definition(fieldName);
    if (definition == null) {
      return;
    }
    final group = groups[responseName] ??= _GroupBuilder(
      fieldName,
      definition,
    );
    group.nodes.add(field);
    group.isConditional = group.isConditional && isConditional;
  }

  void _spread(FragmentSpread spread, List<Condition> conditions) {
    final name = spread.name.value;
    final definition = fragments[name];
    if (definition == null) {
      return;
    }
    final condition = definition.typeCondition.name.value;
    switch (applicability.match(condition, parent)) {
      case TypeConditionMatch.applies:
        final existing = uses[name];
        uses[name] = existing == null
            ? FragmentUse(name, [conditions])
            : existing.merge(conditions);
      case TypeConditionMatch.narrows:
        narrowings.add(
          Narrowing(condition, fragmentName: name, conditions: conditions),
        );
      case TypeConditionMatch.never:
        break;
    }
  }

  /// Null for a field the parent lacks, which validation rules out.
  SchemaField? _definition(String fieldName) {
    if (fieldName == '__typename') {
      return _typename;
    }
    return switch (parent) {
      final ObjectType type => type.fieldNamed(fieldName),
      final InterfaceType type => type.fieldNamed(fieldName),
      _ => null,
    };
  }

  static final SchemaField _typename = SchemaField(
    '__typename',
    const NonNullType(NamedType(Name('String'))),
  );
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/field_group.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Every field node of one response name at one level of a selection.
final class FieldGroup(
  /// The key in the response: the alias, or the field name.
  final String responseName,

  /// The name of the field in the schema.
  final String fieldName,

  /// Every node with this response name, in document order.
  List<Field> nodes, {

  /// The schema field, looked up on the parent type.
  required final SchemaField definition,

  /// Whether every node is under a variable condition, its own or an
  /// enclosing inline fragment's.
  final bool isConditional = false,
}) {
  /// Creates a group.
  this;

  /// The nodes, in document order.
  final List<Field> nodes = List.unmodifiable(nodes);
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart`:

```dart
import 'condition.dart';

/// A named fragment selected at one level of a selection.
final class FragmentUse(
  /// The fragment's name.
  final String fragmentName,

  /// The spread is selected when all conditions of any one list hold; one
  /// empty list means it is unconditional.
  List<List<Condition>> whenAny,
) {
  /// Creates a use.
  this;

  /// The alternatives, in first-occurrence order.
  final List<List<Condition>> whenAny = List.unmodifiable([
    for (final conditions in whenAny) List<Condition>.unmodifiable(conditions),
  ]);

  /// Whether the fragment is selected only when some variable says so.
  bool get isConditional =>
      whenAny.every((conditions) => conditions.isNotEmpty);

  /// This use merged with another spread of the same fragment under
  /// [conditions]: unconditional if either is, otherwise both alternatives
  /// with duplicates removed.
  FragmentUse merge(List<Condition> conditions) {
    if (whenAny.any((existing) => existing.isEmpty)) {
      return this;
    }
    if (conditions.isEmpty) {
      return FragmentUse(fragmentName, [const <Condition>[]]);
    }
    if (whenAny.any((existing) => _same(existing, conditions))) {
      return this;
    }
    return FragmentUse(fragmentName, [...whenAny, conditions]);
  }

  static bool _same(List<Condition> a, List<Condition> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/narrowing.dart`:

```dart
import 'condition.dart';
import 'selection_source.dart';

/// A type condition that narrows an abstract parent: only the types it
/// reaches matter to the planner.
final class const Narrowing(
  /// The name of the type condition.
  final String typeCondition, {

  /// The inline fragment's selection set, with the inherited and own
  /// conditions; null for a fragment spread.
  final SelectionSource? source,

  /// The spread fragment's name; null for an inline fragment.
  final String? fragmentName,

  /// The conditions a fragment spread sits under.
  final List<Condition> conditions = const [],
}) {
  /// Creates a narrowing.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/selection_source.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'condition.dart';

/// A selection set to collect, with the variable conditions it sits under.
final class const SelectionSource(
  /// The selection set.
  final SelectionSet selectionSet, {

  /// Whether a variable `@include` or `@skip` on an enclosing inline
  /// fragment or field makes everything in the set conditional.
  final bool isConditional = false,

  /// Those conditions, which a fragment spread in the set inherits.
  final List<Condition> conditions = const [],
}) {
  /// Creates a source.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/type_condition_match.dart`:

```dart
/// How a type condition relates to the parent type it is written in.
enum TypeConditionMatch {
  /// The condition covers every value of the parent, now and later.
  applies,

  /// The parent is abstract and the condition selects some of its values.
  narrows,

  /// No value of the parent can satisfy the condition.
  never,
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/plan/applicability_test.dart test/plan/directive_conditions_test.dart test/plan/field_collector_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/plan/applicability.dart packages/typed_graphql_codegen/lib/src/plan/collected_selection.dart packages/typed_graphql_codegen/lib/src/plan/condition.dart packages/typed_graphql_codegen/lib/src/plan/directive_conditions.dart packages/typed_graphql_codegen/lib/src/plan/field_collector.dart packages/typed_graphql_codegen/lib/src/plan/field_group.dart packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart packages/typed_graphql_codegen/lib/src/plan/narrowing.dart packages/typed_graphql_codegen/lib/src/plan/selection_source.dart packages/typed_graphql_codegen/lib/src/plan/type_condition_match.dart packages/typed_graphql_codegen/test/plan/applicability_test.dart packages/typed_graphql_codegen/test/plan/directive_conditions_test.dart packages/typed_graphql_codegen/test/plan/field_collector_test.dart packages/typed_graphql_codegen/test/plan/plan_schema.dart packages/typed_graphql_codegen/test/support/plan_fixture.dart
git commit -q -m "feat(typed_graphql_codegen): collect the fields of a selection" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Plan the classes of an operation or fragment

`ShapePlanner` turns an operation or fragment definition into a flat list of `PlannedClass`es (with `PlannedField`, `PlannedFragment`, `ClassNames`, `DataClassRole`) in depth-first pre-order, with one work stack and no recursion. Narrowings are left to the next task.

Commit on the branch: `19f54de`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/plan/class_names.dart`, `packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_class.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart`, `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`
- Test: `packages/typed_graphql_codegen/test/plan/shape_planner_test.dart`, `packages/typed_graphql_codegen/test/support/plan_description.dart`

**Interfaces:**
- Consumes: Task 1 (`FieldCollector`, `CollectedSelection`); M10b `DartNames`, `TypeMapper`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// plan/class_names.dart
final class ClassNames
  const ClassNames()
  String operationData(String operationName)
  String fragment(String fragmentName)
  String nested(String owner, String memberName)
  String holder(String owner)

// plan/data_class_role.dart
enum DataClassRole

// plan/planned_class.dart
sealed class PlannedClass
  const PlannedClass(this.name)
  final String name
final class DataClassPlan extends PlannedClass
  const DataClassPlan({
  final DataClassRole role
  final String typeName
  final List<PlannedField> fields
  final String? holderName
  final String? ownerName
  final String? ownerMember
final class FragmentHolderPlan extends PlannedClass
  const FragmentHolderPlan({
  final String ownerName
  final List<PlannedFragment> fragments

// plan/planned_field.dart
final class PlannedField
  const PlannedField({
  final String responseName
  final String memberName
  final TypeRef type
  final bool isConditional
  final SchemaField? definition
  final String? className

// plan/planned_fragment.dart
final class PlannedFragment
  PlannedFragment(FragmentUse use)
  final String fragmentName
  final String className
  final String memberName
  final List<List<Condition>> whenAny
  final bool isConditional

// plan/shape_planner.dart
final class ShapePlanner
  ShapePlanner(this.schema, this.fragments)
  final Schema schema
  final Map<String, FragmentDefinition> fragments
  List<PlannedClass> planOperation(OperationDefinition operation)
  List<PlannedClass> planFragment(FragmentDefinition fragment)
sealed class _Work
final class _Ready extends _Work
  final PlannedClass plan
final class _ClassWork extends _Work
  final String name
  final SchemaType parent
  final List<SelectionSource> sources
  final DataClassRole role
  final String? ownerName
  final String? ownerMember
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/plan/shape_planner_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_description.dart';
import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  const description = PlanDescription();

  String plan(String document, {String schema = planSchema, int? maxDepth}) {
    final fixture = PlanFixture(schema, document, maxDepth: maxDepth);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .first;
    return description.describe(planner.planOperation(operation));
  }

  String planFragment(String document) {
    final fixture = PlanFixture(planSchema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final fragment = fixture.document.definitions
        .whereType<FragmentDefinition>()
        .first;
    return description.describe(planner.planFragment(fragment));
  }

  test('the target GetUser plans its classes in order', () {
    final target = Directory('../../.superpowers/m10-target');
    final schema = File('${target.path}/schema.graphql').readAsStringSync();
    final document = File('${target.path}/user.graphql').readAsStringSync();
    expect(
      plan(document, schema: schema),
      r'''
GetUserData (operationData on Query)
  user: User <- user -> GetUserDataUser
GetUserDataUser (nested on User, of GetUserData.user)
  role: Role! <- role
  createdAt: DateTime <- createdAt
  cursor: Cursor <- cursor
  friends: [User!]! <- friends -> GetUserDataUserFriends (conditional)
  fragments: GetUserDataUserFragments
GetUserDataUserFriends (nested on User, of GetUserDataUser.friends)
  id: ID! <- id
  name: String! <- name
GetUserDataUserFragments (holder of GetUserDataUser)
  userCard: UserCard? when $full''',
    );
  });

  test('a fragment plans as its own class', () {
    expect(
      planFragment(
        'query { user { ...UserCard } }\nfragment UserCard on User { id name }',
      ),
      '''
UserCard (fragment on User)
  id: ID! <- id
  name: String <- name''',
    );
  });

  test('an alias and a merged field keep the sub-selections of both nodes', () {
    expect(
      plan(
        'query Q { user { friend { id } other: friend { id } friend { name } } }',
      ),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  friend: User <- friend -> QDataUserFriend
  other: User <- other -> QDataUserOther
QDataUserFriend (nested on User, of QDataUser.friend)
  id: ID! <- id
  name: String <- name
QDataUserOther (nested on User, of QDataUser.other)
  id: ID! <- id''',
    );
  });

  test('a field in a conditional inline fragment is conditional', () {
    expect(
      plan(
        r'query Q($v: Boolean!) { user { ... @include(if: $v) { name } id } }',
      ),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  name: String <- name (conditional)
  id: ID! <- id''',
    );
  });

  test('a field conditional on one node only is not conditional', () {
    expect(
      plan(r'query Q($v: Boolean!) { user { name @include(if: $v) name } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  name: String <- name''',
    );
  });

  test('a selected __typename comes first as typename', () {
    expect(
      plan('query Q { user { id __typename } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  typename: String! <- __typename
  id: ID! <- id''',
    );
  });

  test('an aliased __typename is an ordinary String field', () {
    expect(
      plan('query Q { user { kind: __typename } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  kind: String! <- kind''',
    );
  });

  test('reserved member names get a dollar suffix', () {
    expect(
      plan('query Q { user { hashCode: id typename: name } }'),
      r'''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  hashCode$: ID! <- hashCode
  typename$: String <- typename''',
    );
  });

  test('a fragment spread twice lists both conditions', () {
    expect(
      plan(r'''
query Q($v: Boolean!, $w: Boolean!) {
  user { ...UserCard @include(if: $v) ...UserCard @skip(if: $w) }
}
fragment UserCard on User { id }'''),
      r'''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  fragments: QDataUserFragments
QDataUserFragments (holder of QDataUser)
  userCard: UserCard? when $v | !$w''',
    );
  });

  test('nested classes plan in depth-first pre-order', () {
    expect(
      plan('query Q { user { friend { friend { id } } name } }'),
      '''
QData (operationData on Query)
  user: User <- user -> QDataUser
QDataUser (nested on User, of QData.user)
  friend: User <- friend -> QDataUserFriend
  name: String <- name
QDataUserFriend (nested on User, of QDataUser.friend)
  friend: User <- friend -> QDataUserFriendFriend
QDataUserFriendFriend (nested on User, of QDataUserFriend.friend)
  id: ID! <- id''',
    );
  });

  test('a selection 500 levels deep plans without overflowing', () {
    const depth = 500;
    final document =
        'query Q { user { ${'friend { ' * (depth - 1)}id${' }' * depth} }';
    final lines = plan(document, maxDepth: 2000).split('\n');
    expect(lines.where((line) => line.contains('(nested')), hasLength(depth));
  });

  test('a mutation plans on the mutation root', () {
    expect(
      plan(
        'mutation M { make { id } }',
        schema:
            '$planSchema\ntype Mutation { make: User }\n'
            'schema { query: Query mutation: Mutation }',
      ),
      '''
MData (operationData on Mutation)
  make: User <- make -> MDataMake
MDataMake (nested on User, of MData.make)
  id: ID! <- id''',
    );
  });

  test('a subscription plans on the subscription root', () {
    expect(
      plan(
        'subscription S { born { id } }',
        schema:
            '$planSchema\ntype Subscription { born: User }\n'
            'schema { query: Query subscription: Subscription }',
      ),
      '''
SData (operationData on Subscription)
  born: User <- born -> SDataBorn
SDataBorn (nested on User, of SData.born)
  id: ID! <- id''',
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/support/plan_description.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/planned_class.dart';

/// Renders a plan list as text, for tests to compare whole.
final class PlanDescription {
  const PlanDescription();

  String describe(List<PlannedClass> plan) {
    final lines = <String>[];
    for (final planned in plan) {
      switch (planned) {
        case DataClassPlan():
          final owner = planned.ownerName == null
              ? ''
              : ', of ${planned.ownerName}.${planned.ownerMember}';
          lines.add(
            '${planned.name} (${planned.role.name} on ${planned.typeName}'
            '$owner)',
          );
          for (final field in planned.fields) {
            final marks = field.isConditional ? ' (conditional)' : '';
            final target = field.className == null
                ? ''
                : ' -> ${field.className}';
            lines.add(
              '  ${field.memberName}: ${const Printer().print(field.type)}'
              ' <- ${field.responseName}$target$marks',
            );
          }
          if (planned.holderName case final holder?) {
            lines.add('  fragments: $holder');
          }
        case FragmentHolderPlan():
          lines.add('${planned.name} (holder of ${planned.ownerName})');
          for (final fragment in planned.fragments) {
            final when = fragment.whenAny.every((list) => list.isEmpty)
                ? ''
                : ' when ${fragment.whenAny.map((list) => list.join(' & ')).join(' | ')}';
            lines.add(
              '  ${fragment.memberName}: ${fragment.className}'
              '${fragment.isConditional ? '?' : ''}$when',
            );
          }
      }
    }
    return lines.join('\n');
  }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/plan/shape_planner_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_codegen/lib/src/plan/class_names.dart`:

```dart
import '../emit/dart_names.dart';

/// Names the classes generated for operations, fragments and selections.
final class ClassNames {
  /// Creates the class namer.
  const ClassNames();

  static const DartNames _names = DartNames();

  /// The class of an operation's data: `GetUser` is `GetUserData`.
  String operationData(String operationName) =>
      '${_names.typeName(operationName)}Data';

  /// The class of a fragment definition.
  String fragment(String fragmentName) => _names.typeName(fragmentName);

  /// The class of the field [memberName] of the class [owner].
  String nested(String owner, String memberName) =>
      '$owner${_names.capitalized(memberName)}';

  /// The class that holds the fragments spread on the class [owner].
  String holder(String owner) => '${owner}Fragments';
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart`:

```dart
/// What a planned data class is the shape of.
enum DataClassRole {
  /// The `data` of an operation.
  operationData,

  /// A fragment definition.
  fragment,

  /// The selection of a composite field.
  nested,
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/planned_class.dart`:

```dart
import 'data_class_role.dart';
import 'planned_field.dart';
import 'planned_fragment.dart';

/// A class to generate, which refers to other classes by name.
sealed class PlannedClass {
  /// Creates a plan.
  const PlannedClass(this.name);

  /// The class name.
  final String name;
}

/// A class with the fields of a selection.
final class DataClassPlan extends PlannedClass {
  /// Creates a data class plan.
  const DataClassPlan({
    required String name,
    required this.role,
    required this.typeName,
    required this.fields,
    this.holderName,
    this.ownerName,
    this.ownerMember,
  }) : super(name);

  /// What the class is the shape of.
  final DataClassRole role;

  /// The GraphQL type the selection is on.
  final String typeName;

  /// The fields, `__typename` first.
  final List<PlannedField> fields;

  /// The fragment holder class, when the selection spreads fragments.
  final String? holderName;

  /// For a nested class, the class that has the field.
  final String? ownerName;

  /// For a nested class, the member of the owner it is the class of.
  final String? ownerMember;
}

/// The class that holds the fragments spread on [ownerName].
final class FragmentHolderPlan extends PlannedClass {
  /// Creates a holder plan.
  const FragmentHolderPlan({
    required String name,
    required this.ownerName,
    required this.fragments,
  }) : super(name);

  /// The class whose selection spreads the fragments.
  final String ownerName;

  /// The fragments, in first-occurrence order.
  final List<PlannedFragment> fragments;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';

/// A field of a planned data class.
final class PlannedField {
  /// Creates a planned field.
  const PlannedField({
    required this.responseName,
    required this.memberName,
    required this.type,
    required this.isConditional,
    this.definition,
    this.className,
  });

  /// Members a data class cannot use for a field: the members of every
  /// generated class and the `typename` getter of a sealed class.
  static const Set<String> reservedMembers = <String>{
    ...DartNames.objectMembers,
    'typename',
  };

  /// The key in the JSON response; `__typename` for a selected one.
  final String responseName;

  /// The Dart member the field is read through.
  final String memberName;

  /// The field's schema type.
  final TypeRef type;

  /// Whether the field may be absent because of a variable condition.
  final bool isConditional;

  /// The schema field, for doc comments; null for `__typename`.
  final SchemaField? definition;

  /// The generated class of a composite field, null for a leaf.
  final String? className;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart`:

```dart
import '../emit/dart_names.dart';
import 'condition.dart';
import 'fragment_use.dart';

/// A fragment a data class spreads, as a member of its holder.
final class PlannedFragment {
  /// Plans [use].
  PlannedFragment(FragmentUse use)
    : fragmentName = use.fragmentName,
      className = const DartNames().typeName(use.fragmentName),
      memberName = const DartNames().memberName(
        use.fragmentName,
        reservedMembers: DartNames.objectMembers,
      ),
      whenAny = use.whenAny,
      isConditional = use.isConditional;

  /// The fragment's name.
  final String fragmentName;

  /// The class generated for the fragment.
  final String className;

  /// The holder member the fragment is read through.
  final String memberName;

  /// The spread is selected when all conditions of any one list hold.
  final List<List<Condition>> whenAny;

  /// Whether the fragment may be absent.
  final bool isConditional;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import 'class_names.dart';
import 'data_class_role.dart';
import 'field_collector.dart';
import 'field_group.dart';
import 'planned_class.dart';
import 'planned_field.dart';
import 'planned_fragment.dart';
import 'selection_source.dart';

/// Plans the classes of an operation or a fragment definition, in emission
/// order, with one work stack and no recursion (spec §6).
final class ShapePlanner {
  /// Creates a planner for [schema] and the project's [fragments] by name.
  ShapePlanner(this.schema, this.fragments)
    : _collector = FieldCollector(schema, fragments);

  static const ClassNames _classNames = ClassNames();
  static const DartNames _dartNames = DartNames();
  static const TypeRef _typenameType = NonNullType(NamedType(Name('String')));

  /// The schema the selections are on.
  final Schema schema;

  /// The project's fragment definitions, by name.
  final Map<String, FragmentDefinition> fragments;

  final FieldCollector _collector;

  /// The classes of [operation]: its data class, then everything under it.
  /// Empty when the schema has no root for the operation type.
  List<PlannedClass> planOperation(OperationDefinition operation) {
    final rootName = schema.rootTypeName(operation.operation);
    final root = rootName == null ? null : schema.typeNamed(rootName);
    if (root == null) {
      return const [];
    }
    return _plan(
      _ClassWork(
        _classNames.operationData(operation.name?.value ?? ''),
        root,
        [SelectionSource(operation.selectionSet)],
        DataClassRole.operationData,
      ),
    );
  }

  /// The classes of [fragment]: its class, then everything under it.
  /// Empty when its type condition is unknown.
  List<PlannedClass> planFragment(FragmentDefinition fragment) {
    final parent = schema.typeNamed(fragment.typeCondition.name.value);
    if (parent == null) {
      return const [];
    }
    return _plan(
      _ClassWork(
        _classNames.fragment(fragment.name.value),
        parent,
        [SelectionSource(fragment.selectionSet)],
        DataClassRole.fragment,
      ),
    );
  }

  List<PlannedClass> _plan(_ClassWork first) {
    final planned = <PlannedClass>[];
    final stack = <_Work>[first];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case _Ready(:final plan):
          planned.add(plan);
        case final _ClassWork work:
          final children = <_Work>[];
          planned.add(_dataClass(work, children));
          stack.addAll(children.reversed);
      }
    }
    return planned;
  }

  /// Plans [work] and adds the work under it to [children], in the order
  /// it is emitted: field classes, then the holder.
  DataClassPlan _dataClass(_ClassWork work, List<_Work> children) {
    final collected = _collector.collect(work.parent, work.sources);
    final fields = <PlannedField>[
      if (collected.selectsTypename)
        const PlannedField(
          responseName: '__typename',
          memberName: 'typename',
          type: _typenameType,
          isConditional: false,
        ),
    ];
    for (final group in collected.fields) {
      fields.add(_field(work, group, children));
    }
    String? holderName;
    if (collected.fragments.isNotEmpty) {
      holderName = _classNames.holder(work.name);
      children.add(
        _Ready(
          FragmentHolderPlan(
            name: holderName,
            ownerName: work.name,
            fragments: [
              for (final use in collected.fragments) PlannedFragment(use),
            ],
          ),
        ),
      );
    }
    return DataClassPlan(
      name: work.name,
      role: work.role,
      typeName: work.parent.name,
      fields: fields,
      holderName: holderName,
      ownerName: work.ownerName,
      ownerMember: work.ownerMember,
    );
  }

  PlannedField _field(_ClassWork work, FieldGroup group, List<_Work> children) {
    final memberName = _dartNames.memberName(
      group.responseName,
      reservedMembers: PlannedField.reservedMembers,
    );
    final type = group.definition.type;
    final named = schema.namedTypeOf(type);
    final isComposite =
        named is ObjectType || named is InterfaceType || named is UnionType;
    String? className;
    if (named != null && isComposite) {
      className = _classNames.nested(work.name, memberName);
      children.add(
        _ClassWork(
          className,
          named,
          [
            for (final node in group.nodes)
              if (node.selectionSet case final set?) SelectionSource(set),
          ],
          DataClassRole.nested,
          ownerName: work.name,
          ownerMember: memberName,
        ),
      );
    }
    return PlannedField(
      responseName: group.responseName,
      memberName: memberName,
      type: type,
      isConditional: group.isConditional,
      definition: group.fieldName == '__typename' ? null : group.definition,
      className: className,
    );
  }
}

sealed class _Work {
  const _Work();
}

final class _Ready extends _Work {
  const _Ready(this.plan);

  final PlannedClass plan;
}

final class _ClassWork extends _Work {
  const _ClassWork(
    this.name,
    this.parent,
    this.sources,
    this.role, {
    this.ownerName,
    this.ownerMember,
  });

  final String name;
  final SchemaType parent;
  final List<SelectionSource> sources;
  final DataClassRole role;
  final String? ownerName;
  final String? ownerMember;
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/plan/shape_planner_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/plan/class_names.dart packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart packages/typed_graphql_codegen/lib/src/plan/planned_class.dart packages/typed_graphql_codegen/lib/src/plan/planned_field.dart packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart packages/typed_graphql_codegen/test/plan/shape_planner_test.dart packages/typed_graphql_codegen/test/support/plan_description.dart
git commit -q -m "feat(typed_graphql_codegen): plan the classes of an operation or fragment" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Plan variants of selections on abstract types

A narrowed selection on an interface or union plans a sealed base, a class per reached concrete type and an `…Unknown` one (R7.5; spec deviation 5). A field or the fragment holder is declared on the base only when every variant selects the same nodes (`VariantSharing`); a field a variant re-selects with more gets its own class in every variant, because a class that overrides `==` may not be implemented (spec deviation 7).

Commit on the branch: `dfed1e6`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/plan/plan_work.dart`, `packages/typed_graphql_codegen/lib/src/plan/variant_context.dart`, `packages/typed_graphql_codegen/lib/src/plan/variant_reference.dart`, `packages/typed_graphql_codegen/lib/src/plan/variant_sharing.dart`
- Modify: `packages/typed_graphql_codegen/lib/src/plan/class_names.dart`, `packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_class.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart`, `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`
- Test: `packages/typed_graphql_codegen/test/plan/variant_planner_test.dart`, `packages/typed_graphql_codegen/test/support/plan_description.dart`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// plan/class_names.dart
  String variant(String base, String typeName)
  String unknownVariant(String base)

// plan/plan_work.dart
sealed class PlanWork
  const PlanWork()
final class ReadyWork extends PlanWork
  const ReadyWork(this.plan)
  final PlannedClass plan
final class ClassWork extends PlanWork
  const ClassWork(
  final String name
  final SchemaType parent
  final List<SelectionSource> sources
  final DataClassRole role
  final String? ownerName
  final String? ownerMember
  final VariantContext? variant

// plan/planned_class.dart
  final String? baseName
  final String? variantTypeName
  final bool holderOverridesBase
final class PolymorphicBasePlan extends PlannedClass
  const PolymorphicBasePlan({
  final DataClassRole role
  final String typeName
  final List<PlannedField> sharedFields
  final String? holderName
  final List<VariantReference> variants
  final String unknownName
  final String? ownerName
  final String? ownerMember

// plan/planned_field.dart
  final bool overridesBase
  PlannedField overriding()

// plan/variant_context.dart
final class const VariantContext(…)

// plan/variant_reference.dart
final class const VariantReference(…)

// plan/variant_sharing.dart
final class VariantSharing
  VariantSharing(CollectedSelection base, List<CollectedSelection> variants)
  final Set<String> sharedFields
  final bool hasSharedHolder
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/plan/variant_planner_test.dart`:

```dart
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_description.dart';
import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  const description = PlanDescription();

  String plan(String document, {String schema = planSchema}) {
    final fixture = PlanFixture(schema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .first;
    return description.describe(planner.planOperation(operation));
  }

  test('the target FindNode plans a base, two variants and Unknown', () {
    final target = Directory('../../.superpowers/m10-target');
    final schema = File('${target.path}/schema.graphql').readAsStringSync();
    final document = File('${target.path}/user.graphql').readAsStringSync();
    expect(
      plan(
        document.substring(document.indexOf('query FindNode')) +
            document.substring(
              document.indexOf('fragment UserCard'),
              document.indexOf('query FindNode'),
            ),
        schema: schema,
      ),
      '''
FindNodeData (operationData on Query)
  node: Node <- node -> FindNodeDataNode
FindNodeDataNode (sealed nested on Node, of FindNodeData.node)
  id: ID! <- id
  variants: User=FindNodeDataNodeUser, Bot=FindNodeDataNodeBot, unknown=FindNodeDataNodeUnknown
FindNodeDataNodeUser (variant on User, implements FindNodeDataNode)
  @override id: ID! <- id
  name: String! <- name
  fragments: FindNodeDataNodeUserFragments
FindNodeDataNodeUserFragments (holder of FindNodeDataNodeUser)
  userCard: UserCard
FindNodeDataNodeBot (variant on Bot, implements FindNodeDataNode)
  @override id: ID! <- id
  model: String <- model
FindNodeDataNodeUnknown (unknownVariant on Node, implements FindNodeDataNode)
  @override id: ID! <- id''',
    );
  });

  test('a union without shared fields plans one class per narrowing', () {
    expect(
      plan('query { actor { ... on User { name } ... on Bot { model } } }'),
      '''
Data (operationData on Query)
  actor: Actor <- actor -> DataActor
DataActor (sealed nested on Actor, of Data.actor)
  variants: User=DataActorUser, Bot=DataActorBot, unknown=DataActorUnknown
DataActorUser (variant on User, implements DataActor)
  name: String <- name
DataActorBot (variant on Bot, implements DataActor)
  model: String <- model
DataActorUnknown (unknownVariant on Actor, implements DataActor)''',
    );
  });

  group('a base field a variant re-selects', () {
    const schema = '''
interface Node { owner: Owner }
type Owner { id: ID!, name: String }
type User implements Node { owner: Owner }
type Bot implements Node { owner: Owner }
type Query { node: Node }
''';

    test('is dropped from the base, with a class per variant', () {
      expect(
        plan(
          'query { node { owner { id } ... on User { owner { name } } } }',
          schema: schema,
        ),
        '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  owner: Owner <- owner -> DataNodeUserOwner
DataNodeUserOwner (nested on Owner, of DataNodeUser.owner)
  id: ID! <- id
  name: String <- name
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  owner: Owner <- owner -> DataNodeUnknownOwner
DataNodeUnknownOwner (nested on Owner, of DataNodeUnknown.owner)
  id: ID! <- id''',
      );
    });

    test('stays shared when no variant re-selects it', () {
      expect(
        plan(
          'query { node { owner { id } ... on User { __typename } } }',
          schema: schema,
        ),
        '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  owner: Owner <- owner -> DataNodeOwner
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeOwner (nested on Owner, of DataNode.owner)
  id: ID! <- id
DataNodeUser (variant on User, implements DataNode)
  @override owner: Owner <- owner -> DataNodeOwner
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  @override owner: Owner <- owner -> DataNodeOwner''',
      );
    });
  });

  test('a narrowing inside a narrowing reaches only the inner types', () {
    expect(
      plan('query { actor { ... on Node { ... on User { name } } } }'),
      '''
Data (operationData on Query)
  actor: Actor <- actor -> DataActor
DataActor (sealed nested on Actor, of Data.actor)
  variants: User=DataActorUser, Bot=DataActorBot, unknown=DataActorUnknown
DataActorUser (variant on User, implements DataActor)
  name: String <- name
DataActorBot (variant on Bot, implements DataActor)
DataActorUnknown (unknownVariant on Actor, implements DataActor)''',
    );
  });

  test('a narrowing under @include makes its fields conditional', () {
    expect(
      plan(
        r'query($x: Boolean!) { actor { ... on User @include(if: $x) { name } } }',
      ),
      '''
Data (operationData on Query)
  actor: Actor <- actor -> DataActor
DataActor (sealed nested on Actor, of Data.actor)
  variants: User=DataActorUser, unknown=DataActorUnknown
DataActorUser (variant on User, implements DataActor)
  name: String <- name (conditional)
DataActorUnknown (unknownVariant on Actor, implements DataActor)''',
    );
  });

  test('a fragment spread on the interface is a shared holder', () {
    expect(
      plan(
        'query { node { ...NodeCard ... on User { name } } }\n'
        'fragment NodeCard on Node { id }',
      ),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  fragments: DataNodeFragments
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeFragments (holder of DataNode)
  nodeCard: NodeCard
DataNodeUser (variant on User, implements DataNode)
  name: String <- name
  fragments: DataNodeFragments (override)
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  fragments: DataNodeFragments (override)''',
    );
  });

  test('a variant that adds a fragment drops the base holder', () {
    expect(
      plan(
        'query { node { ...NodeCard ... on User { ...NodeCard @include(if: true) ...UserCard } } }\n'
        'fragment NodeCard on Node { id }\nfragment UserCard on User { name }',
      ),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  fragments: DataNodeUserFragments
DataNodeUserFragments (holder of DataNodeUser)
  nodeCard: NodeCard
  userCard: UserCard
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  fragments: DataNodeUnknownFragments
DataNodeUnknownFragments (holder of DataNodeUnknown)
  nodeCard: NodeCard''',
    );
  });

  test('an abstract selection without narrowings stays a plain class', () {
    expect(
      plan('query { node { id } }'),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (nested on Node, of Data.node)
  id: ID! <- id''',
    );
  });

  test(
    'a condition on an interface the parent implements is not a variant',
    () {
      const schema = '''
interface Node { id: ID! }
interface Entity implements Node { id: ID!, label: String }
type Admin implements Entity & Node { id: ID!, label: String }
type Query { entity: Entity }
''';
      expect(
        plan('query { entity { ... on Node { id } label } }', schema: schema),
        '''
Data (operationData on Query)
  entity: Entity <- entity -> DataEntity
DataEntity (nested on Entity, of Data.entity)
  id: ID! <- id
  label: String <- label''',
      );
    },
  );

  test('a fragment on an interface with variants is a polymorphic fragment', () {
    final fixture = PlanFixture(
      planSchema,
      'query { node { ...F } }\nfragment F on Node { id ... on User { name } }',
    );
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    expect(
      description.describe(planner.planFragment(fixture.fragments['F']!)),
      '''
F (sealed fragment on Node)
  id: ID! <- id
  variants: User=FUser, unknown=FUnknown
FUser (variant on User, implements F)
  @override id: ID! <- id
  name: String <- name
FUnknown (unknownVariant on Node, implements F)
  @override id: ID! <- id''',
    );
  });

  test('an aliased __typename stays a field of a polymorphic shape', () {
    expect(
      plan('query { node { ... on User { name } kind: __typename } }'),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  kind: String! <- kind
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  name: String <- name
  @override kind: String! <- kind
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  @override kind: String! <- kind''',
    );
  });

  test('a selected __typename is not a field of a polymorphic shape', () {
    expect(
      plan('query { node { __typename ... on User { name } } }'),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  name: String <- name
DataNodeUnknown (unknownVariant on Node, implements DataNode)''',
    );
  });

  test('fifty possible types plan fifty variants in schema order', () {
    final names = [for (var i = 0; i < 50; i++) 'T$i'];
    final schema = [
      'interface Node { id: ID! }',
      for (final name in names) 'type $name implements Node { id: ID! }',
      'type Query { node: Node }',
    ].join('\n');
    final lines = plan(
      'query { node { ${[for (final name in names.reversed) '... on $name { id }'].join(' ')} } }',
      schema: schema,
    ).split('\n');
    final variants = lines.firstWhere((line) => line.startsWith('  variants:'));
    expect(
      variants,
      '  variants: ${[for (final name in names) '$name=DataNode$name'].join(', ')}'
      ', unknown=DataNodeUnknown',
    );
  });
}
```

In `packages/typed_graphql_codegen/test/support/plan_description.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_codegen/src/plan/planned_class.dart';
+import 'package:typed_graphql_codegen/src/plan/planned_field.dart';
 
 /// Renders a plan list as text, for tests to compare whole.
 final class PlanDescription {
@@ -9,26 +10,41 @@ final class PlanDescription {
     final lines = <String>[];
     for (final planned in plan) {
       switch (planned) {
+        case PolymorphicBasePlan():
+          final owner = planned.ownerName == null
+              ? ''
+              : ', of ${planned.ownerName}.${planned.ownerMember}';
+          lines.add(
+            '${planned.name} (sealed ${planned.role.name} on '
+            '${planned.typeName}$owner)',
+          );
+          for (final field in planned.sharedFields) {
+            lines.add('  ${_field(field)}');
+          }
+          if (planned.holderName case final holder?) {
+            lines.add('  fragments: $holder');
+          }
+          lines.add(
+            '  variants: ${planned.variants.map((v) => '${v.typeName}=${v.className}').join(', ')}'
+            ', unknown=${planned.unknownName}',
+          );
         case DataClassPlan():
           final owner = planned.ownerName == null
               ? ''
               : ', of ${planned.ownerName}.${planned.ownerMember}';
+          final base = planned.baseName == null
+              ? ''
+              : ', implements ${planned.baseName}';
           lines.add(
             '${planned.name} (${planned.role.name} on ${planned.typeName}'
-            '$owner)',
+            '$owner$base)',
           );
           for (final field in planned.fields) {
-            final marks = field.isConditional ? ' (conditional)' : '';
-            final target = field.className == null
-                ? ''
-                : ' -> ${field.className}';
-            lines.add(
-              '  ${field.memberName}: ${const Printer().print(field.type)}'
-              ' <- ${field.responseName}$target$marks',
-            );
+            lines.add('  ${_field(field)}');
           }
           if (planned.holderName case final holder?) {
-            lines.add('  fragments: $holder');
+            final marks = planned.holderOverridesBase ? ' (override)' : '';
+            lines.add('  fragments: $holder$marks');
           }
         case FragmentHolderPlan():
           lines.add('${planned.name} (holder of ${planned.ownerName})');
@@ -45,4 +61,13 @@ final class PlanDescription {
     }
     return lines.join('\n');
   }
+
+  String _field(PlannedField field) {
+    final marks = field.isConditional ? ' (conditional)' : '';
+    final target = field.className == null ? '' : ' -> ${field.className}';
+    final override = field.overridesBase ? '@override ' : '';
+    return '$override${field.memberName}: '
+        '${const Printer().print(field.type)}'
+        ' <- ${field.responseName}$target$marks';
+  }
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/plan/variant_planner_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/plan/class_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,4 +20,13 @@ final class ClassNames {
 
   /// The class that holds the fragments spread on the class [owner].
   String holder(String owner) => '${owner}Fragments';
+
+  /// The class of the concrete type [typeName] in the polymorphic class
+  /// [base].
+  String variant(String base, String typeName) =>
+      '$base${_names.typeName(typeName)}';
+
+  /// The class for every type the polymorphic class [base] does not tell
+  /// apart.
+  String unknownVariant(String base) => '${base}Unknown';
 }
```

In `packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,4 +8,10 @@ enum DataClassRole {
 
   /// The selection of a composite field.
   nested,
+
+  /// The class of one concrete type of a polymorphic selection.
+  variant,
+
+  /// The class of every other type of a polymorphic selection.
+  unknownVariant,
 }
```

Create `packages/typed_graphql_codegen/lib/src/plan/plan_work.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'data_class_role.dart';
import 'planned_class.dart';
import 'selection_source.dart';
import 'variant_context.dart';

/// An item of the planner's work stack.
sealed class PlanWork {
  /// Creates an item.
  const PlanWork();
}

/// A class plan that is already complete.
final class ReadyWork extends PlanWork {
  /// Wraps [plan].
  const ReadyWork(this.plan);

  /// The plan to emit when the item is popped.
  final PlannedClass plan;
}

/// A selection to plan as a class.
final class ClassWork extends PlanWork {
  /// Creates the work for the class [name].
  const ClassWork(
    this.name,
    this.parent,
    this.sources,
    this.role, {
    this.ownerName,
    this.ownerMember,
    this.variant,
  });

  /// The class name.
  final String name;

  /// The type the selection is on.
  final SchemaType parent;

  /// The selection sets, in document order.
  final List<SelectionSource> sources;

  /// What the class is the shape of.
  final DataClassRole role;

  /// For a nested class, the class that has the field.
  final String? ownerName;

  /// For a nested class, the member of the owner it is the class of.
  final String? ownerMember;

  /// What a variant takes from its sealed base; null for any other class.
  final VariantContext? variant;
}
```

In `packages/typed_graphql_codegen/lib/src/plan/planned_class.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'data_class_role.dart';
 import 'planned_field.dart';
 import 'planned_fragment.dart';
+import 'variant_reference.dart';
 
 /// A class to generate, which refers to other classes by name.
 sealed class PlannedClass {
@@ -22,6 +23,9 @@ final class DataClassPlan extends PlannedClass {
     this.holderName,
     this.ownerName,
     this.ownerMember,
+    this.baseName,
+    this.variantTypeName,
+    this.holderOverridesBase = false,
   }) : super(name);
 
   /// What the class is the shape of.
@@ -41,6 +45,60 @@ final class DataClassPlan extends PlannedClass {
 
   /// For a nested class, the member of the owner it is the class of.
   final String? ownerMember;
+
+  /// For a variant, the sealed base it implements.
+  final String? baseName;
+
+  /// For a [DataClassRole.variant], the concrete type it is the class of;
+  /// null for the other roles.
+  final String? variantTypeName;
+
+  /// Whether [holderName] is the base's shared holder, which `fragments`
+  /// overrides.
+  final bool holderOverridesBase;
+}
+
+/// The sealed base of a selection on an abstract type that tells types
+/// apart: a class per reached type, and one for any other.
+final class PolymorphicBasePlan extends PlannedClass {
+  /// Creates a base plan.
+  const PolymorphicBasePlan({
+    required String name,
+    required this.role,
+    required this.typeName,
+    required this.sharedFields,
+    required this.variants,
+    required this.unknownName,
+    this.holderName,
+    this.ownerName,
+    this.ownerMember,
+  }) : super(name);
+
+  /// What the class is the shape of: a fragment or a nested class.
+  final DataClassRole role;
+
+  /// The abstract GraphQL type the selection is on.
+  final String typeName;
+
+  /// The fields every variant has with the same selection; the base
+  /// declares them.
+  final List<PlannedField> sharedFields;
+
+  /// The shared fragment holder class, when every variant has the base's
+  /// fragments.
+  final String? holderName;
+
+  /// The classes of the reached types, in possible-types order.
+  final List<VariantReference> variants;
+
+  /// The class for every other `__typename`.
+  final String unknownName;
+
+  /// For a nested class, the class that has the field.
+  final String? ownerName;
+
+  /// For a nested class, the member of the owner it is the class of.
+  final String? ownerMember;
 }
 
 /// The class that holds the fragments spread on [ownerName].
```

In `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,6 +12,7 @@ final class PlannedField {
     required this.isConditional,
     this.definition,
     this.className,
+    this.overridesBase = false,
   });
 
   /// Members a data class cannot use for a field: the members of every
@@ -38,4 +39,19 @@ final class PlannedField {
 
   /// The generated class of a composite field, null for a leaf.
   final String? className;
+
+  /// Whether the field is a shared field of the sealed base, which the
+  /// class overrides.
+  final bool overridesBase;
+
+  /// This field as a variant's override of the base's declaration.
+  PlannedField overriding() => PlannedField(
+    responseName: responseName,
+    memberName: memberName,
+    type: type,
+    isConditional: isConditional,
+    definition: definition,
+    className: className,
+    overridesBase: true,
+  );
 }
```

In `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,14 +1,21 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../emit/dart_names.dart';
+import 'applicability.dart';
 import 'class_names.dart';
+import 'collected_selection.dart';
 import 'data_class_role.dart';
 import 'field_collector.dart';
 import 'field_group.dart';
+import 'fragment_use.dart';
+import 'plan_work.dart';
 import 'planned_class.dart';
 import 'planned_field.dart';
 import 'planned_fragment.dart';
 import 'selection_source.dart';
+import 'variant_context.dart';
+import 'variant_reference.dart';
+import 'variant_sharing.dart';
 
 /// Plans the classes of an operation or a fragment definition, in emission
 /// order, with one work stack and no recursion (spec §6).
@@ -38,7 +45,7 @@ final class ShapePlanner {
       return const [];
     }
     return _plan(
-      _ClassWork(
+      ClassWork(
         _classNames.operationData(operation.name?.value ?? ''),
         root,
         [SelectionSource(operation.selectionSet)],
@@ -55,7 +62,7 @@ final class ShapePlanner {
       return const [];
     }
     return _plan(
-      _ClassWork(
+      ClassWork(
         _classNames.fragment(fragment.name.value),
         parent,
         [SelectionSource(fragment.selectionSet)],
@@ -64,28 +71,160 @@ final class ShapePlanner {
     );
   }
 
-  List<PlannedClass> _plan(_ClassWork first) {
+  List<PlannedClass> _plan(ClassWork first) {
     final planned = <PlannedClass>[];
-    final stack = <_Work>[first];
+    final stack = <PlanWork>[first];
     while (stack.isNotEmpty) {
       switch (stack.removeLast()) {
-        case _Ready(:final plan):
+        case ReadyWork(:final plan):
           planned.add(plan);
-        case final _ClassWork work:
-          final children = <_Work>[];
-          planned.add(_dataClass(work, children));
+        case final ClassWork work:
+          final children = <PlanWork>[];
+          final collected =
+              work.variant?.collected ??
+              _collector.collect(work.parent, work.sources);
+          final reached = work.variant == null
+              ? _reached(work.parent, collected)
+              : const <ObjectType>[];
+          planned.add(
+            reached.isEmpty
+                ? _dataClass(work, collected, children)
+                : _polymorphic(work, collected, reached, children),
+          );
           stack.addAll(children.reversed);
       }
     }
     return planned;
   }
 
+  /// The object types the narrowings of an abstract [parent] reach, in
+  /// possible-types order.
+  List<ObjectType> _reached(SchemaType parent, CollectedSelection collected) {
+    if (parent is! InterfaceType && parent is! UnionType) {
+      return const [];
+    }
+    final reached = <ObjectType>{
+      for (final narrowing in collected.narrowings)
+        ...Applicability(schema).reach(narrowing.typeCondition, parent),
+    };
+    return [
+      for (final type in schema.possibleTypes(parent))
+        if (reached.contains(type)) type,
+    ];
+  }
+
+  /// Plans the sealed base of [work] and queues its variants, in the order
+  /// they are emitted: shared field classes, the shared holder, each
+  /// variant, then the unknown one.
+  PolymorphicBasePlan _polymorphic(
+    ClassWork work,
+    CollectedSelection collected,
+    List<ObjectType> reached,
+    List<PlanWork> children,
+  ) {
+    final collections = [
+      for (final type in reached) _collector.collect(type, work.sources),
+    ];
+    final sharing = VariantSharing(collected, collections);
+    final shared = <String, PlannedField>{
+      for (final group in collected.fields)
+        if (sharing.sharedFields.contains(group.responseName))
+          group.responseName: _field(work.name, group, children),
+    };
+    final holderName = sharing.hasSharedHolder
+        ? _ownHolder(work.name, collected.fragments, children)
+        : null;
+    final contexts = [
+      for (final selection in [...collections, collected])
+        VariantContext(work.name, selection, shared, holderName),
+    ];
+    final variants = _queueVariants(work, reached, contexts, children);
+    final unknownName = _classNames.unknownVariant(work.name);
+    children.add(
+      _variantWork(work, unknownName, work.parent, contexts.last),
+    );
+    return PolymorphicBasePlan(
+      name: work.name,
+      role: work.role,
+      typeName: work.parent.name,
+      sharedFields: shared.values.toList(),
+      variants: variants,
+      unknownName: unknownName,
+      holderName: holderName,
+      ownerName: work.ownerName,
+      ownerMember: work.ownerMember,
+    );
+  }
+
+  /// Queues a class per reached type, each with its context in [contexts].
+  List<VariantReference> _queueVariants(
+    ClassWork base,
+    List<ObjectType> reached,
+    List<VariantContext> contexts,
+    List<PlanWork> children,
+  ) {
+    final variants = <VariantReference>[];
+    for (final (index, type) in reached.indexed) {
+      final name = _classNames.variant(base.name, type.name);
+      variants.add(VariantReference(type.name, name));
+      children.add(_variantWork(base, name, type, contexts[index]));
+    }
+    return variants;
+  }
+
+  /// The work for a variant of [base]: the unknown one when [parent] is the
+  /// base's own abstract type.
+  ClassWork _variantWork(
+    ClassWork base,
+    String name,
+    SchemaType parent,
+    VariantContext context,
+  ) => ClassWork(
+    name,
+    parent,
+    base.sources,
+    identical(parent, base.parent)
+        ? DataClassRole.unknownVariant
+        : DataClassRole.variant,
+    variant: context,
+  );
+
+  FragmentHolderPlan _holder(
+    String name,
+    String ownerName,
+    List<FragmentUse> uses,
+  ) => FragmentHolderPlan(
+    name: name,
+    ownerName: ownerName,
+    fragments: [for (final use in uses) PlannedFragment(use)],
+  );
+
+  /// Queues a holder class named after [owner] and returns its name; null
+  /// when [uses] is empty.
+  String? _ownHolder(
+    String owner,
+    List<FragmentUse> uses,
+    List<PlanWork> children,
+  ) {
+    if (uses.isEmpty) {
+      return null;
+    }
+    final name = _classNames.holder(owner);
+    children.add(ReadyWork(_holder(name, owner, uses)));
+    return name;
+  }
+
   /// Plans [work] and adds the work under it to [children], in the order
   /// it is emitted: field classes, then the holder.
-  DataClassPlan _dataClass(_ClassWork work, List<_Work> children) {
-    final collected = _collector.collect(work.parent, work.sources);
+  DataClassPlan _dataClass(
+    ClassWork work,
+    CollectedSelection collected,
+    List<PlanWork> children,
+  ) {
+    final variant = work.variant;
     final fields = <PlannedField>[
-      if (collected.selectsTypename)
+      // A polymorphic class has `typename` whether or not it was selected.
+      if (collected.selectsTypename && variant == null)
         const PlannedField(
           responseName: '__typename',
           memberName: 'typename',
@@ -94,23 +233,12 @@ final class ShapePlanner {
         ),
     ];
     for (final group in collected.fields) {
-      fields.add(_field(work, group, children));
-    }
-    String? holderName;
-    if (collected.fragments.isNotEmpty) {
-      holderName = _classNames.holder(work.name);
-      children.add(
-        _Ready(
-          FragmentHolderPlan(
-            name: holderName,
-            ownerName: work.name,
-            fragments: [
-              for (final use in collected.fragments) PlannedFragment(use),
-            ],
-          ),
-        ),
-      );
+      final base = variant?.sharedFields[group.responseName];
+      fields.add(base?.overriding() ?? _field(work.name, group, children));
     }
+    final sharedHolder = variant?.sharedHolderName;
+    final holderName =
+        sharedHolder ?? _ownHolder(work.name, collected.fragments, children);
     return DataClassPlan(
       name: work.name,
       role: work.role,
@@ -119,10 +247,15 @@ final class ShapePlanner {
       holderName: holderName,
       ownerName: work.ownerName,
       ownerMember: work.ownerMember,
+      baseName: variant?.baseName,
+      variantTypeName: work.role == DataClassRole.variant
+          ? work.parent.name
+          : null,
+      holderOverridesBase: sharedHolder != null,
     );
   }
 
-  PlannedField _field(_ClassWork work, FieldGroup group, List<_Work> children) {
+  PlannedField _field(String owner, FieldGroup group, List<PlanWork> children) {
     final memberName = _dartNames.memberName(
       group.responseName,
       reservedMembers: PlannedField.reservedMembers,
@@ -133,9 +266,9 @@ final class ShapePlanner {
         named is ObjectType || named is InterfaceType || named is UnionType;
     String? className;
     if (named != null && isComposite) {
-      className = _classNames.nested(work.name, memberName);
+      className = _classNames.nested(owner, memberName);
       children.add(
-        _ClassWork(
+        ClassWork(
           className,
           named,
           [
@@ -143,7 +276,7 @@ final class ShapePlanner {
               if (node.selectionSet case final set?) SelectionSource(set),
           ],
           DataClassRole.nested,
-          ownerName: work.name,
+          ownerName: owner,
           ownerMember: memberName,
         ),
       );
@@ -158,31 +291,3 @@ final class ShapePlanner {
     );
   }
 }
-
-sealed class _Work {
-  const _Work();
-}
-
-final class _Ready extends _Work {
-  const _Ready(this.plan);
-
-  final PlannedClass plan;
-}
-
-final class _ClassWork extends _Work {
-  const _ClassWork(
-    this.name,
-    this.parent,
-    this.sources,
-    this.role, {
-    this.ownerName,
-    this.ownerMember,
-  });
-
-  final String name;
-  final SchemaType parent;
-  final List<SelectionSource> sources;
-  final DataClassRole role;
-  final String? ownerName;
-  final String? ownerMember;
-}
```

Create `packages/typed_graphql_codegen/lib/src/plan/variant_context.dart`:

```dart
import 'collected_selection.dart';
import 'planned_field.dart';

/// What a variant class takes from its sealed base.
final class const VariantContext(
  /// The sealed base.
  final String baseName,

  /// The variant's own collection, already made for the sharing decision.
  final CollectedSelection collected,

  /// The base's shared fields, by response name.
  final Map<String, PlannedField> sharedFields,

  /// The base's shared holder, null when the base declares none.
  final String? sharedHolderName,
) {
  /// Creates a context.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/variant_reference.dart`:

```dart
/// A concrete type of a polymorphic selection and the class generated for it.
final class const VariantReference(
  /// The GraphQL object type.
  final String typeName,

  /// The generated class.
  final String className,
) {
  /// Creates a reference.
  this;
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/variant_sharing.dart`:

```dart
import 'collected_selection.dart';
import 'condition.dart';
import 'field_group.dart';
import 'fragment_use.dart';

/// Decides what the sealed base of a polymorphic selection declares: a base
/// field or fragment holder is shared when every variant selects exactly
/// what the base does (spec §6, "Variants").
final class VariantSharing {
  /// Compares [base] with the collection of each of [variants].
  VariantSharing(CollectedSelection base, List<CollectedSelection> variants)
    : sharedFields = _sharedFields(base, variants),
      hasSharedHolder =
          base.fragments.isNotEmpty &&
          variants.every((v) => _sameFragments(base.fragments, v.fragments));

  /// The response names of the shared base fields.
  final Set<String> sharedFields;

  /// Whether the base declares the fragment holder.
  final bool hasSharedHolder;

  static Set<String> _sharedFields(
    CollectedSelection base,
    List<CollectedSelection> variants,
  ) {
    final byVariant = [
      for (final variant in variants)
        {for (final group in variant.fields) group.responseName: group},
    ];
    return {
      for (final group in base.fields)
        if (byVariant.every(
          (groups) => _sameNodes(group, groups[group.responseName]),
        ))
          group.responseName,
    };
  }

  static bool _sameNodes(FieldGroup base, FieldGroup? other) {
    if (other == null || other.nodes.length != base.nodes.length) {
      return false;
    }
    for (var index = 0; index < base.nodes.length; index++) {
      if (!identical(base.nodes[index], other.nodes[index])) {
        return false;
      }
    }
    return true;
  }

  static bool _sameFragments(List<FragmentUse> base, List<FragmentUse> other) {
    if (base.length != other.length) {
      return false;
    }
    for (var index = 0; index < base.length; index++) {
      final left = base[index];
      final right = other[index];
      if (left.fragmentName != right.fragmentName ||
          !_sameAlternatives(left.whenAny, right.whenAny)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameAlternatives(
    List<List<Condition>> a,
    List<List<Condition>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index].length != b[index].length) {
        return false;
      }
      for (var inner = 0; inner < a[index].length; inner++) {
        if (a[index][inner] != b[index][inner]) {
          return false;
        }
      }
    }
    return true;
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/plan/variant_planner_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_codegen/lib/src/plan/class_names.dart packages/typed_graphql_codegen/lib/src/plan/data_class_role.dart packages/typed_graphql_codegen/lib/src/plan/plan_work.dart packages/typed_graphql_codegen/lib/src/plan/planned_class.dart packages/typed_graphql_codegen/lib/src/plan/planned_field.dart packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart packages/typed_graphql_codegen/lib/src/plan/variant_context.dart packages/typed_graphql_codegen/lib/src/plan/variant_reference.dart packages/typed_graphql_codegen/lib/src/plan/variant_sharing.dart packages/typed_graphql_codegen/test/plan/variant_planner_test.dart packages/typed_graphql_codegen/test/support/plan_description.dart
git commit -q -m "feat(typed_graphql_codegen): plan variants of selections on abstract types" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Generate fragment classes in a library per document

The data classes and fragment holders of each fragment definition are emitted in a library per document file (its path plus `.dart`; `DocumentLibraries`, `DocumentLibraryEmitter`, `DataClassEmitter`, `FragmentHolderEmitter`, `ToJsonWriter`, `ReaderFactoryWriter`) with the imports it needs (`LibraryImports`: runtime, custom scalars, schema types, other documents by relative path). The `fragments` golden case with a decode round trip and the guide section come with it.

Commit on the branch: `c71d74e`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart`, `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart`, `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart`, `packages/typed_graphql_codegen/lib/src/emit/reader_factory_writer.dart`, `packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart`, `packages/typed_graphql_codegen/lib/src/emit/value_member.dart`, `packages/typed_graphql_codegen/lib/src/emit/value_members.dart`, `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, `packages/typed_graphql_codegen/pubspec.yaml`
- Test: `packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_card.graphql`, `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_card_query.graphql`, `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_name.graphql`, `packages/typed_graphql_codegen/test/goldens/fragments/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/fragments/input/typed_graphql.yaml`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_name.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt`, `packages/typed_graphql_codegen/test/goldens/fragments/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt`, `packages/typed_graphql_codegen/test/goldens/fragments/support/packages/scalar_codecs/pubspec.yaml.txt`, `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden`, `packages/typed_graphql_codegen/test/support/class_emission.dart`

**Interfaces:**
- Consumes: Tasks 1-3; M10b `DartWriter`, `Imports`, `TypeMapper`, `GeneratedNames`, the golden harness.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/class_documentation.dart
final class ClassDocumentation
  const ClassDocumentation(this.classes)
  final List<PlannedClass> classes
  String of(DataClassPlan plan,

// emit/data_class_emitter.dart
final class DataClassEmitter
  const DataClassEmitter(this.mapper)
  final TypeMapper mapper
  void emit(

// emit/data_class_field.dart
final class DataClassField
  factory DataClassField.of(
  DataClassField._(this._field, this.type)
  final DartType type
  String get member
  String get responseName
  bool get isConditional
  bool get isNullable
  String get codecName
  ValueMember get valueMember
  String get keyLiteral
  String get doc

// emit/document_library_emitter.dart
final class DocumentLibraryEmitter
  const DocumentLibraryEmitter(this.planner, this.mapper, this.libraryImports)
  final ShapePlanner planner
  final TypeMapper mapper
  final LibraryImports libraryImports
  String libraryPathOf(String documentPath)
  String emit(String documentPath, List<FragmentDefinition> fragments)

// emit/fragment_holder_emitter.dart
final class FragmentHolderEmitter
  const FragmentHolderEmitter()
  void emit(FragmentHolderPlan plan, DartWriter writer)

// emit/library_imports.dart
final class LibraryImports
  const LibraryImports(
  final Schema schema
  final String schemaTypesPath
  final Map<String, String> fragmentLibraries
  void record(

// emit/reader_factory_writer.dart
final class ReaderFactoryWriter
  const ReaderFactoryWriter()
  void write(

// emit/to_json_writer.dart
final class ToJsonWriter
  const ToJsonWriter()
  void write(DartWriter writer, List<String> entries)

// emit/value_member.dart
final class const ValueMember(…)
  String get otherRead
  String get ownRead
  String get interpolation

// emit/value_members.dart
final class ValueMembers
  const ValueMembers()
  void write(

// generator/document_libraries.dart
final class DocumentLibraries
  const DocumentLibraries(this.project, this.mapper, this.schemaTypesPath)
  final ClientProject project
  final TypeMapper mapper
  final String schemaTypesPath
  List<GeneratedFile> generate()
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/data_class_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/plan/data_class_role.dart';
import 'package:typed_graphql_codegen/src/plan/planned_class.dart';

import '../support/class_emission.dart';

const _schema = '''
enum Role { ADMIN }
scalar DateTime
scalar Cursor
interface Node { id: ID! }
type User implements Node {
  id: ID!
  "The display name."
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}
type Query { user(id: ID!): User }
''';

void main() {
  final fragments = ClassEmission(_schema, r'''
query GetUser($withFriends: Boolean!, $full: Boolean!) {
  user(id: "1") {
    ...UserCard @include(if: $full)
    role
    createdAt
    cursor
    friends(first: 2) @include(if: $withFriends) {
      id
      name
    }
  }
}
fragment UserCard on User { id name }
''');

  test('a nested class of a list field', () {
    expect(fragments.emit('GetUserDataUserFriends'), r'''
/// The items of the field `friends` of [GetUserDataUser].
final class GetUserDataUserFriends implements client.DataObject {
  /// Creates the value.
  const GetUserDataUserFriends({required this.id, required this.name});

  factory GetUserDataUserFriends._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUserFriends(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUserFriends> codec =
      client.ObjectDataCodec(GetUserDataUserFriends._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The display name.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUserFriends && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'GetUserDataUserFriends(id: $id, name: $name)';
}
''');
  });

  test('a class with conditional fields and a fragment holder', () {
    expect(fragments.emit('GetUserDataUser'), r'''
/// The field `user` of [GetUserData].
final class GetUserDataUser implements client.DataObject {
  /// Creates the value.
  const GetUserDataUser({
    required this.role,
    required this.fragments,
    this.createdAt,
    this.cursor,
    this.friends,
  });

  factory GetUserDataUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUser(
    role: _roleCodec.field(json, 'role', context),
    createdAt: _createdAtCodec.field(json, 'createdAt', context),
    cursor: _cursorCodec.field(json, 'cursor', context),
    friends: _friendsCodec.field(json, 'friends', context),
    fragments: GetUserDataUserFragments._read(json, context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUser> codec =
      client.ObjectDataCodec(GetUserDataUser._read);

  static const client.DataCodec<Role> _roleCodec = Role.codec;

  static const client.DataCodec<graphql.JsonValue?> _createdAtCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  static const client.DataCodec<graphql.JsonValue?> _cursorCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  static const client.DataCodec<List<GetUserDataUserFriends>?> _friendsCodec =
      client.NullableDataCodec(
        client.ListDataCodec(GetUserDataUserFriends.codec),
      );

  /// The field `role`.
  final Role role;

  /// The field `createdAt`.
  final graphql.JsonValue? createdAt;

  /// The field `cursor`.
  final graphql.JsonValue? cursor;

  /// The field `friends`; null when `@include` or `@skip` left it out.
  final List<GetUserDataUserFriends>? friends;

  /// The fragments spread on this value.
  final GetUserDataUserFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    'role': _roleCodec.write(role),
    'createdAt': _createdAtCodec.write(createdAt),
    'cursor': _cursorCodec.write(cursor),
    'friends': _friendsCodec.write(friends),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUser &&
      other.role == role &&
      other.createdAt == createdAt &&
      other.cursor == cursor &&
      const client.DataEquality().equals(other.friends, friends) &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([
    role,
    createdAt,
    cursor,
    const client.DataEquality().hash(friends),
    fragments,
  ]);

  @override
  String toString() =>
      'GetUserDataUser(role: $role, createdAt: $createdAt, cursor: $cursor, friends: $friends, fragments: $fragments)';
}
''');
  });

  test('a fragment class has decode', () {
    expect(fragments.emitFragment('UserCard', 'UserCard'), r'''
/// The fragment `UserCard` on `User`.
final class UserCard implements client.DataObject {
  /// Creates the fragment.
  const UserCard({required this.id, required this.name});

  factory UserCard._read(graphql.JsonObject json, client.DataContext context) =>
      UserCard(
        id: _idCodec.field(json, 'id', context),
        name: _nameCodec.field(json, 'name', context),
      );

  /// Reads and writes the fragment.
  static const client.DataCodec<UserCard> codec =
      client.ObjectDataCodec(UserCard._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The display name.
  final String name;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is UserCard && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'UserCard(id: $id, name: $name)';
}
''');
  });

  test('a class without members', () {
    final writer = DartWriter();
    const plan = DataClassPlan(
      name: 'Empty',
      role: DataClassRole.nested,
      typeName: 'User',
      fields: [],
    );
    final mapper = TypeMapper(
      (const SchemaBuilder().fromSdl(
        const Parser().parse(Source(_schema)).requireDocument(),
      ) as BuildSuccess).schema,
      const {},
    );
    DataClassEmitter(mapper).emit(plan, 'Nothing.', writer, Imports());
    expect(writer.text, '''
/// Nothing.
final class Empty implements client.DataObject {
  /// Creates the value.
  const Empty();

  factory Empty._read(graphql.JsonObject json, client.DataContext context) =>
      const Empty();

  /// Reads and writes the value.
  static const client.DataCodec<Empty> codec =
      client.ObjectDataCodec(Empty._read);

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({});

  @override
  bool operator ==(Object other) => other is Empty;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Empty()';
}
''');
  });

  test('a class that is not a fragment or a field is a programmer error', () {
    const plan = DataClassPlan(
      name: 'GetData',
      role: DataClassRole.operationData,
      typeName: 'Query',
      fields: [],
    );
    expect(
      () => DataClassEmitter(
        TypeMapper(
          (const SchemaBuilder().fromSdl(
            const Parser().parse(Source(_schema)).requireDocument(),
          ) as BuildSuccess).schema,
          const {},
        ),
      ).emit(plan, 'Data.', DartWriter(), Imports()),
      throwsStateError,
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/document_library_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/library_imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_fixture.dart';

const _schema = '''
enum Role { ADMIN }
type User { id: ID!, role: Role! }
type Query { user: User }
''';

const _document = '''
query Q { user { ...Outer ...WithRole } }
fragment Outer on User { id ...Inner }
fragment Inner on User { id }
fragment WithRole on User { role }
''';

void main() {
  final fixture = PlanFixture(_schema, _document);
  final emitter = DocumentLibraryEmitter(
    ShapePlanner(fixture.schema, fixture.fragments),
    TypeMapper(fixture.schema, const {}),
    LibraryImports(fixture.schema, 'lib/schema.graphql.dart', const {
      'Outer': 'lib/a/b.graphql.dart',
      'Inner': 'lib/c.graphql.dart',
      'WithRole': 'lib/a/b.graphql.dart',
    }),
  );

  List<String> importsOf(String text) => [
    for (final line in text.split('\n'))
      if (line.startsWith('import ')) line,
  ];

  test('a document without fragments is a header only', () {
    expect(emitter.emit('lib/q.graphql', const []), '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/q.graphql.
// dart format off
''');
  });

  test('the library of a document file is its path plus .dart', () {
    expect(emitter.libraryPathOf('lib/a/b.graphql'), 'lib/a/b.graphql.dart');
  });

  test('imports reach the other document and the schema types', () {
    final text = emitter.emit('lib/a/b.graphql', [
      fixture.fragments['Outer']!,
      fixture.fragments['WithRole']!,
    ]);
    expect(importsOf(text), [
      "import 'package:typed_graphql/typed_graphql.dart' as graphql;",
      "import 'package:typed_graphql_client/typed_graphql_client.dart' "
          'as client;',
      "import '../c.graphql.dart';",
      "import '../schema.graphql.dart';",
    ]);
  });

  test('schema types are imported only when a field needs them', () {
    final text = emitter.emit('lib/a/b.graphql', [fixture.fragments['Outer']!]);
    expect(importsOf(text), [
      "import 'package:typed_graphql/typed_graphql.dart' as graphql;",
      "import 'package:typed_graphql_client/typed_graphql_client.dart' "
          'as client;',
      "import '../c.graphql.dart';",
    ]);
  });

  test('a fragment defined in the same library is not imported', () {
    final text = emitter.emit('lib/c.graphql', [fixture.fragments['Inner']!]);
    expect(importsOf(text), [
      "import 'package:typed_graphql/typed_graphql.dart' as graphql;",
      "import 'package:typed_graphql_client/typed_graphql_client.dart' "
          'as client;',
    ]);
  });

  test('the classes of the fragments follow in document order', () {
    final text = emitter.emit('lib/a/b.graphql', [
      fixture.fragments['Outer']!,
      fixture.fragments['WithRole']!,
    ]);
    expect(
      [
        for (final line in text.split('\n'))
          if (line.startsWith('final class ')) line.split(' ')[2],
      ],
      ['Outer', 'OuterFragments', 'WithRole'],
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart`:

```dart
import 'package:test/test.dart';

import '../support/class_emission.dart';

const _schema = '''
type User { id: ID! }
type Query { user: User }
''';

void main() {
  test('an unconditional and a conditional fragment', () {
    final emission = ClassEmission(_schema, r'''
query Q($a: Boolean!) {
  user {
    ...F1
    ...F2 @include(if: $a)
  }
}
fragment F1 on User { id }
fragment F2 on User { id }
''');
    expect(emission.emit('QDataUserFragments'), r'''
/// The fragments spread on [QDataUser].
final class QDataUserFragments implements client.DataObject {
  /// Creates the fragments.
  const QDataUserFragments({required this.f1, this.f2});

  factory QDataUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => QDataUserFragments(
    f1: F1.codec.read(json, context),
    f2: context.flag('a') ? F2.codec.read(json, context) : null,
  );

  /// The fragment `F1`.
  final F1 f1;

  /// The fragment `F2`; null when `@include` or `@skip` left it out.
  final F2? f2;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...f1.toJson().fields,
    ...?f2?.toJson().fields,
  });

  @override
  bool operator ==(Object other) =>
      other is QDataUserFragments && other.f1 == f1 && other.f2 == f2;

  @override
  int get hashCode => Object.hashAll([f1, f2]);

  @override
  String toString() => 'QDataUserFragments(f1: $f1, f2: $f2)';
}
''');
  });

  test('a single skipped fragment', () {
    final emission = ClassEmission(_schema, r'''
query Q($b: Boolean!) { user { ...F1 @skip(if: $b) } }
fragment F1 on User { id }
''');
    expect(emission.emit('QDataUserFragments'), r'''
/// The fragments spread on [QDataUser].
final class QDataUserFragments implements client.DataObject {
  /// Creates the fragments.
  const QDataUserFragments({this.f1});

  factory QDataUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => QDataUserFragments(
    f1: !context.flag('b') ? F1.codec.read(json, context) : null,
  );

  /// The fragment `F1`; null when `@include` or `@skip` left it out.
  final F1? f1;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({...?f1?.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is QDataUserFragments && other.f1 == f1;

  @override
  int get hashCode => f1.hashCode;

  @override
  String toString() => 'QDataUserFragments(f1: $f1)';
}
''');
  });

  test('a fragment spread under two conditions joins them with ||', () {
    final emission = ClassEmission(_schema, r'''
query Q($a: Boolean!, $b: Boolean!, $c: Boolean!) {
  user {
    ...F1 @include(if: $c)
    ... @include(if: $a) { ...F1 @skip(if: $b) }
    ...F2 @include(if: $c)
    ... @include(if: $a) { ...F2 @skip(if: $b) }
  }
}
fragment F1 on User { id }
fragment F2 on User { id }
''');
    final text = emission.emit('QDataUserFragments');
    expect(
      text,
      contains(
        "f1: context.flag('c') || (context.flag('a') && !context.flag('b'))\n",
      ),
    );
  });
}
```

In `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -28,9 +28,7 @@ void main() {
     );
     expect(
       [for (final file in result.files) file.path],
-      [
-        'lib/schema.graphql.dart',
-      ],
+      ['lib/schema.graphql.dart', 'lib/a.graphql.dart'],
     );
   });
 
@@ -38,7 +36,7 @@ void main() {
     final result = ClientGenerator(
       configOf('schema: schema.graphql\nschema_types: lib/src/types.dart\n'),
     ).generate(schema: _schema, documents: const [_document]);
-    expect(result.files.single.path, 'lib/src/types.dart');
+    expect(result.files.first.path, 'lib/src/types.dart');
   });
 
   test('a project with one enum writes that enum', () {
@@ -46,7 +44,7 @@ void main() {
       schema: _schema,
       documents: const [_document],
     );
-    expect(result.files.single.text, r'''
+    expect(result.files.first.text, r'''
 // GENERATED CODE - DO NOT MODIFY BY HAND.
 // Generated by typed_graphql_codegen from schema.graphql.
 // dart format off
@@ -174,11 +172,50 @@ type Query {
     );
     expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
     expect(
-      result.files.single.text,
+      result.files.first.text,
       allOf(
         contains(r'sealed class $$TypeKind'),
         contains(r'enum $$TypeKindKnown'),
       ),
     );
   });
+
+  test('a library per document file follows, sorted by path', () {
+    final result = generator.generate(
+      schema: _schema,
+      documents: const [
+        ProjectFile('lib/z.graphql', 'query Z { role }'),
+        ProjectFile('lib/b/b.graphql', 'fragment B on Query { role }'),
+        ProjectFile('lib/a.graphql', 'query A { ...B }'),
+      ],
+    );
+    expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
+    expect(
+      [for (final file in result.files) file.path],
+      [
+        'lib/schema.graphql.dart',
+        'lib/a.graphql.dart',
+        'lib/b/b.graphql.dart',
+        'lib/z.graphql.dart',
+      ],
+    );
+  });
+
+  test('a fragment is generated in the library of its file', () {
+    final result = generator.generate(
+      schema: _schema,
+      documents: const [
+        ProjectFile('lib/b/b.graphql', 'fragment B on Query { role }'),
+        ProjectFile('lib/a.graphql', 'query A { ...B }'),
+      ],
+    );
+    final byPath = {for (final file in result.files) file.path: file.text};
+    expect(
+      byPath['lib/b/b.graphql.dart'],
+      allOf(
+        contains('final class B implements client.DataObject'),
+      ),
+    );
+    expect(byPath['lib/a.graphql.dart'], isNot(contains('final class')));
+  });
 }
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_card.graphql`:

```graphql
fragment UserCard on User {
  __typename
  _id: id
  default: name
  role
  createdAt
  cursor
  friends(first: 2) {
    id
    ...UserName
  }
  ...UserName @include(if: $full)
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_card_query.graphql`:

```graphql
query CardQuery($full: Boolean!) {
  user(id: "1") {
    ...UserCard
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_name.graphql`:

```graphql
fragment UserName on User {
  name
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/input/schema.graphql`:

```graphql
"A user role."
enum Role {
  ADMIN
  EDITOR
  VIEWER @deprecated(reason: "Use EDITOR.")
}

enum Unused {
  A
}

scalar DateTime

scalar Cursor

input UserFilter {
  role: Role
  name: String = "x"
  ids: [ID!]!
  nested: UserFilter
  since: DateTime
  matrix: [[Int]]
}

input SearchBy @oneOf {
  name: String
  id: ID
  ids: [ID!]
}

"Names that Dart reserves or that the generated class already has."
input Paging {
  default: Int
  other: String!
  after: Cursor
  client: Int
}

input Unreached {
  value: Int
}

interface Node {
  id: ID!
}

type User implements Node {
  id: ID!
  "The display name."
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}

type Bot implements Node {
  id: ID!
  model: String
}

union SearchResult = User | Bot

type Query {
  user(id: ID!): User
  node(id: ID!): Node
  search(by: SearchBy!, filter: UserFilter, paging: Paging): [SearchResult!]!
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/input/typed_graphql.yaml`:

```yaml
schema: schema.graphql
scalars:
  DateTime:
    type: DateTime
    codec: package:scalar_codecs/scalar_codecs.dart#DateTimeCodec
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/schema.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off

import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// A user role.
sealed class Role implements client.DataEnum {
  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
  /// this code does not know.
  factory Role.parse(String raw) {
    for (final value in RoleKnown.values) {
      if (value.raw == raw) return value;
    }
    return RoleUnknown(raw);
  }

  /// Reads and writes the values of `Role`.
  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
}

/// The values of [Role] this code knows.
enum RoleKnown implements Role {
  /// `ADMIN`.
  admin('ADMIN'),

  /// `EDITOR`.
  editor('EDITOR'),

  /// `VIEWER`.
  @Deprecated('Use EDITOR.')
  viewer('VIEWER');

  const RoleKnown(this.raw);

  @override
  final String raw;
}

/// A value of [Role] this code does not know, such as one added to the
/// schema after the code was generated.
final class RoleUnknown implements Role {
  /// Creates the value named [raw].
  const RoleUnknown(this.raw);

  @override
  final String raw;

  @override
  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'RoleUnknown($raw)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_card.graphql.
// dart format off

import 'package:scalar_codecs/scalar_codecs.dart' as scalar_0;
import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

import 'schema.graphql.dart';
import 'user_name.graphql.dart';

/// The fragment `UserCard` on `User`.
final class UserCard implements client.DataObject {
  /// Creates the fragment.
  const UserCard({
    required this.typename,
    required this.$id,
    required this.default$,
    required this.role,
    required this.friends,
    required this.fragments,
    this.createdAt,
    this.cursor,
  });

  factory UserCard._read(graphql.JsonObject json, client.DataContext context) =>
      UserCard(
        typename: _typenameCodec.field(json, '__typename', context),
        $id: _$idCodec.field(json, '_id', context),
        default$: _default$Codec.field(json, 'default', context),
        role: _roleCodec.field(json, 'role', context),
        createdAt: _createdAtCodec.field(json, 'createdAt', context),
        cursor: _cursorCodec.field(json, 'cursor', context),
        friends: _friendsCodec.field(json, 'friends', context),
        fragments: UserCardFragments._read(json, context),
      );

  /// Reads and writes the fragment.
  static const client.DataCodec<UserCard> codec =
      client.ObjectDataCodec(UserCard._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _$idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _default$Codec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<Role> _roleCodec = Role.codec;

  static const client.DataCodec<DateTime?> _createdAtCodec =
      client.NullableDataCodec(
        client.ScalarDataCodec(scalar_0.DateTimeCodec()),
      );

  static const client.DataCodec<graphql.JsonValue?> _cursorCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  static const client.DataCodec<List<UserCardFriends>> _friendsCodec =
      client.ListDataCodec(UserCardFriends.codec);

  /// The field `__typename`.
  final String typename;

  /// The field `_id`.
  final String $id;

  /// The display name.
  final String default$;

  /// The field `role`.
  final Role role;

  /// The field `createdAt`.
  final DateTime? createdAt;

  /// The field `cursor`.
  final graphql.JsonValue? cursor;

  /// The field `friends`.
  final List<UserCardFriends> friends;

  /// The fragments spread on this value.
  final UserCardFragments fragments;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': _typenameCodec.write(typename),
    '_id': _$idCodec.write($id),
    'default': _default$Codec.write(default$),
    'role': _roleCodec.write(role),
    'createdAt': _createdAtCodec.write(createdAt),
    'cursor': _cursorCodec.write(cursor),
    'friends': _friendsCodec.write(friends),
  });

  @override
  bool operator ==(Object other) =>
      other is UserCard &&
      other.typename == typename &&
      other.$id == $id &&
      other.default$ == default$ &&
      other.role == role &&
      other.createdAt == createdAt &&
      other.cursor == cursor &&
      const client.DataEquality().equals(other.friends, friends) &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([
    typename,
    $id,
    default$,
    role,
    createdAt,
    cursor,
    const client.DataEquality().hash(friends),
    fragments,
  ]);

  @override
  String toString() =>
      'UserCard(typename: $typename, \$id: ${$id}, default\$: ${default$}, role: $role, createdAt: $createdAt, cursor: $cursor, friends: $friends, fragments: $fragments)';
}

/// The items of the field `friends` of [UserCard].
final class UserCardFriends implements client.DataObject {
  /// Creates the value.
  const UserCardFriends({required this.id, required this.fragments});

  factory UserCardFriends._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserCardFriends(
    id: _idCodec.field(json, 'id', context),
    fragments: UserCardFriendsFragments._read(json, context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<UserCardFriends> codec =
      client.ObjectDataCodec(UserCardFriends._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The field `id`.
  final String id;

  /// The fragments spread on this value.
  final UserCardFriendsFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is UserCardFriends &&
      other.id == id &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([id, fragments]);

  @override
  String toString() => 'UserCardFriends(id: $id, fragments: $fragments)';
}

/// The fragments spread on [UserCardFriends].
final class UserCardFriendsFragments implements client.DataObject {
  /// Creates the fragments.
  const UserCardFriendsFragments({required this.userName});

  factory UserCardFriendsFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserCardFriendsFragments(userName: UserName.codec.read(json, context));

  /// The fragment `UserName`.
  final UserName userName;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...userName.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is UserCardFriendsFragments && other.userName == userName;

  @override
  int get hashCode => userName.hashCode;

  @override
  String toString() => 'UserCardFriendsFragments(userName: $userName)';
}

/// The fragments spread on [UserCard].
final class UserCardFragments implements client.DataObject {
  /// Creates the fragments.
  const UserCardFragments({this.userName});

  factory UserCardFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserCardFragments(
    userName: context.flag('full') ? UserName.codec.read(json, context) : null,
  );

  /// The fragment `UserName`; null when `@include` or `@skip` left it out.
  final UserName? userName;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...?userName?.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is UserCardFragments && other.userName == userName;

  @override
  int get hashCode => userName.hashCode;

  @override
  String toString() => 'UserCardFragments(userName: $userName)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_card_query.graphql.
// dart format off
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_name.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_name.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The fragment `UserName` on `User`.
final class UserName implements client.DataObject {
  /// Creates the fragment.
  const UserName({required this.name});

  factory UserName._read(graphql.JsonObject json, client.DataContext context) =>
      UserName(name: _nameCodec.field(json, 'name', context));

  /// Reads and writes the fragment.
  static const client.DataCodec<UserName> codec =
      client.ObjectDataCodec(UserName._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The display name.
  final String name;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserName> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'name': _nameCodec.write(name)});

  @override
  bool operator ==(Object other) => other is UserName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'UserName(name: $name)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt`:

```text
import 'dart:io';

import 'package:generated_fragments/schema.graphql.dart';
import 'package:generated_fragments/user_card.graphql.dart';
import 'package:typed_graphql/typed_graphql.dart';

const String _response = '''
{
  "__typename": "User",
  "_id": "1",
  "default": "Ada",
  "role": "ADMIN",
  "createdAt": "2026-10-15T00:00:00.000Z",
  "cursor": 7,
  "friends": [
    {"id": "2", "name": "Bob"},
    {"id": "3", "name": "Cy"}
  ],
  "name": "Ada"
}
''';

void main() {
  final JsonObject json = _json(_response);
  final UserCard withName = _decode(json, full: true);
  final UserCard withoutName = _decode(json, full: false);
  if (withName.fragments.userName?.name != 'Ada') {
    _fail('the included fragment was not read: ${withName.fragments}');
  }
  if (withoutName.fragments.userName != null) {
    _fail('the excluded fragment was read: ${withoutName.fragments}');
  }
  if (withName.friends.first.fragments.userName.name != 'Bob') {
    _fail('a nested fragment was not read: ${withName.friends}');
  }
  if (withName.createdAt != DateTime.utc(2026, 10, 15)) {
    _fail('createdAt is ${withName.createdAt}');
  }
  if (withName.role != RoleKnown.admin || withName.$id != '1') {
    _fail('typed reads are wrong: $withName');
  }
  _roundTrips(withName, full: true);
  _roundTrips(withoutName, full: false);
  if (withName == withoutName) {
    _fail('values that differ in a fragment are equal');
  }
  _wrongType(json);
}

JsonObject _json(String text) =>
    (const JsonReader().parse(text) as DecodeSuccess<JsonValue>).value
        as JsonObject;

UserCard _decode(JsonObject json, {required bool full}) {
  final DecodeResult<UserCard> result = UserCard.decode(
    json,
    variables: JsonObject({'full': JsonBool(full)}),
  );
  if (result is! DecodeSuccess<UserCard>) {
    _fail('decode failed: $result');
  }
  return (result as DecodeSuccess<UserCard>).value;
}

void _roundTrips(UserCard card, {required bool full}) {
  final UserCard again = _decode(card.toJson(), full: full);
  if (again != card || again.hashCode != card.hashCode) {
    _fail('decode(toJson()) is $again, not $card');
  }
}

void _wrongType(JsonObject json) {
  final JsonObject wrong = JsonObject({
    ...json.fields,
    'friends': JsonArray([
      JsonObject({'id': const JsonString('2'), 'name': const JsonBool(true)}),
    ]),
  });
  final DecodeResult<UserCard> result = UserCard.decode(wrong);
  if (result is! DecodeFailure) {
    _fail('a boolean for a String was accepted: $result');
  }
  final List<PathSegment> expected = [
    const PathKey('friends'),
    const PathIndex(0),
    const PathKey('name'),
  ];
  if ((result as DecodeFailure).path.toString() != expected.toString()) {
    _fail('the failure path is ${result.path}');
  }
}

void _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt`:

```text
import 'package:typed_graphql/typed_graphql.dart';

/// Reads and writes a `DateTime` as an ISO 8601 string.
final class const DateTimeCodec() implements ScalarCodec<DateTime> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<DateTime> decode(JsonValue json) => switch (json) {
    JsonString(:final value) when DateTime.tryParse(value) != null =>
      DecodeSuccess(DateTime.parse(value)),
    _ => DecodeFailure('Expected an ISO 8601 date, got: $json'),
  };

  @override
  JsonValue encode(DateTime value) => JsonString(value.toIso8601String());
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/support/packages/scalar_codecs/pubspec.yaml.txt`:

```text
name: scalar_codecs
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  typed_graphql: ^0.0.1
```

Create `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The fragment `UserCard` on `User`.
final class UserCard implements client.DataObject {
  /// Creates the fragment.
  const UserCard({required this.id, required this.name});

  factory UserCard._read(graphql.JsonObject json, client.DataContext context) =>
      UserCard(
        id: _idCodec.field(json, 'id', context),
        name: _nameCodec.field(json, 'name', context),
      );

  /// Reads and writes the fragment.
  static const client.DataCodec<UserCard> codec =
      client.ObjectDataCodec(UserCard._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is UserCard && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'UserCard(id: $id, name: $name)';
}
```

Create `packages/typed_graphql_codegen/test/support/class_emission.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/class_documentation.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/data_class_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/fragment_holder_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/plan/planned_class.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import 'plan_fixture.dart';

/// Plans the first operation (or the first fragment) of a document and
/// emits one of its classes, for the emitter tests.
final class ClassEmission(
  /// The schema SDL.
  final String schema,

  /// A valid document.
  final String document,
) {
  this;

  /// The text of the class named [name] of the first operation.
  String emit(String name) {
    final fixture = PlanFixture(schema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .first;
    return emitFrom(fixture, planner.planOperation(operation), name);
  }

  /// The text of the class named [name] of the fragment [fragmentName].
  String emitFragment(String fragmentName, String name) {
    final fixture = PlanFixture(schema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final plan = planner.planFragment(fixture.fragments[fragmentName]!);
    return emitFrom(fixture, plan, name, fragmentName: fragmentName);
  }

  /// The text of [name] among [plan].
  String emitFrom(
    PlanFixture fixture,
    List<PlannedClass> plan,
    String name, {
    String? fragmentName,
  }) {
    final writer = DartWriter();
    final imports = Imports();
    final mapper = TypeMapper(fixture.schema, const {});
    switch (plan.firstWhere((planned) => planned.name == name)) {
      case final DataClassPlan data:
        final doc = ClassDocumentation(
          plan,
        ).of(data, fragmentName: fragmentName);
        DataClassEmitter(mapper).emit(data, doc, writer, imports);
      case final FragmentHolderPlan holder:
        const FragmentHolderEmitter().emit(holder, writer);
      case PolymorphicBasePlan():
        throw StateError('not emitted by these tests');
    }
    return writer.text;
  }
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/data_class_emitter_test.dart test/emit/document_library_emitter_test.dart test/emit/fragment_holder_emitter_test.dart test/generator/client_generator_generate_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Update the package files**

In `packages/typed_graphql_codegen/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,6 +10,7 @@ environment:
   sdk: ^3.13.0
 
 dependencies:
+  path: ^1.9.0
   typed_graphql: ^0.0.1
   yaml: ^3.1.3
 
```

- [ ] **Step 4: Write the implementation**

Create `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/data_class_role.dart';
import '../plan/planned_class.dart';
import '../plan/planned_field.dart';

/// Writes the doc comment sentence of a planned data class.
///
/// {@category codegen}
final class ClassDocumentation {
  /// Creates the writer; [classes] are the plan the classes belong to, in
  /// which an owner is looked up by name.
  const ClassDocumentation(this.classes);

  /// The planned classes of one fragment or operation.
  final List<PlannedClass> classes;

  /// The doc of [plan].
  ///
  /// [fragmentName] is the GraphQL name of the fragment a
  /// [DataClassRole.fragment] class is the shape of. A role this stage does
  /// not generate, or a nested class whose owner is not in [classes], is a
  /// [StateError].
  String of(DataClassPlan plan, {String? fragmentName}) => switch (plan.role) {
    DataClassRole.fragment =>
      'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`.',
    DataClassRole.nested => _nested(plan),
    _ => throw StateError('${plan.name} is a ${plan.role.name} class.'),
  };

  String _nested(DataClassPlan plan) {
    final String? ownerName = plan.ownerName;
    final String? member = plan.ownerMember;
    final PlannedField? field = ownerName == null || member == null
        ? null
        : _fieldOf(ownerName, member);
    if (field == null) {
      throw StateError('The owner field of ${plan.name} is not planned.');
    }
    final String subject = '`${field.responseName}` of [$ownerName]';
    return _isList(field.type)
        ? 'The items of the field $subject.'
        : 'The field $subject.';
  }

  PlannedField? _fieldOf(String ownerName, String member) {
    for (final PlannedClass candidate in classes) {
      if (candidate.name != ownerName) continue;
      final List<PlannedField> fields = switch (candidate) {
        DataClassPlan(:final fields) => fields,
        PolymorphicBasePlan(:final sharedFields) => sharedFields,
        FragmentHolderPlan() => const [],
      };
      for (final PlannedField field in fields) {
        if (field.memberName == member) return field;
      }
    }
    return null;
  }

  bool _isList(TypeRef type) => switch (type) {
    NonNullType(type: final inner) => _isList(inner),
    ListType() => true,
    NamedType() => false,
  };
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`:

```dart
import '../plan/data_class_role.dart';
import '../plan/planned_class.dart';
import 'dart_writer.dart';
import 'data_class_field.dart';
import 'imports.dart';
import 'reader_factory_writer.dart';
import 'to_json_writer.dart';
import 'type_mapper.dart';
import 'value_member.dart';
import 'value_members.dart';

/// Writes the data class of a fragment or of a composite field (spec §7
/// "Data classes", R7.3).
///
/// {@category codegen}
final class DataClassEmitter {
  /// Creates the emitter; [mapper] maps the field types.
  const DataClassEmitter(this.mapper);

  /// The mapper of field types.
  final TypeMapper mapper;

  /// Writes [plan] with the class doc comment [doc].
  ///
  /// Only the roles [DataClassRole.fragment] and [DataClassRole.nested] are
  /// written here; any other is a [StateError].
  void emit(
    DataClassPlan plan,
    String doc,
    DartWriter writer,
    Imports imports,
  ) {
    if (plan.role != DataClassRole.fragment &&
        plan.role != DataClassRole.nested) {
      throw StateError('${plan.name} is a ${plan.role.name} class.');
    }
    final fields = [
      for (final field in plan.fields)
        DataClassField.of(field, mapper, imports),
    ];
    final String noun = plan.role == DataClassRole.fragment
        ? 'fragment'
        : 'value';
    writer.doc(doc);
    writer.block('final class ${plan.name} implements client.DataObject', () {
      _members(writer, plan, fields, noun);
    });
  }

  void _members(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
    String noun,
  ) {
    final String name = plan.name;
    _constructor(writer, plan, fields, noun);
    writer.line();
    _reader(writer, plan, fields);
    writer.line();
    writer.doc('Reads and writes the $noun.');
    writer.assign(
      'static const client.DataCodec<$name> codec',
      'client.ObjectDataCodec($name._read)',
    );
    for (final field in fields) {
      writer.line();
      writer.assign(
        'static const client.DataCodec<${field.type.type}> ${field.codecName}',
        field.type.codec,
      );
    }
    _fields(writer, plan, fields);
    if (plan.role == DataClassRole.fragment) {
      writer.line();
      _decode(writer, name);
    }
    writer.line();
    _toJson(writer, plan, fields);
    writer.line();
    const ValueMembers().write(writer, name, [
      for (final field in fields) field.valueMember,
      if (plan.holderName != null) const ValueMember('fragments', false),
    ]);
  }

  void _constructor(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
    String noun,
  ) {
    final bool hasHolder = plan.holderName != null;
    writer.doc('Creates the $noun.');
    if (fields.isEmpty && !hasHolder) {
      writer.line('const ${plan.name}();');
      return;
    }
    writer.items('const ${plan.name}({', [
      for (final field in fields)
        if (!field.isNullable) 'required this.${field.member}',
      if (hasHolder) 'required this.fragments',
      for (final field in fields)
        if (field.isNullable) 'this.${field.member}',
    ], '});');
  }

  void _reader(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    const ReaderFactoryWriter().write(writer, plan.name, [
      for (final field in fields)
        (
          field.member,
          '${field.codecName}.field(json, ${field.keyLiteral}, context)',
        ),
      if (plan.holderName case final holder?)
        ('fragments', '$holder._read(json, context)'),
    ]);
  }

  void _fields(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    for (final field in fields) {
      writer.line();
      writer.doc(field.doc);
      writer.line('final ${field.type.type} ${field.member};');
    }
    if (plan.holderName case final holder?) {
      writer.line();
      writer.doc('The fragments spread on this value.');
      writer.line('final $holder fragments;');
    }
  }

  void _decode(DartWriter writer, String name) {
    writer
      ..doc(
        'Reads [json], an object the fragment was spread on, in the response\n'
        'to an operation sent with [variables].',
      )
      ..line('static graphql.DecodeResult<$name> decode(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json, {')
          ..line('graphql.JsonObject? variables,');
      })
      ..line('}) => codec.decode(json, client.DataContext(variables));');
  }

  void _toJson(
    DartWriter writer,
    DataClassPlan plan,
    List<DataClassField> fields,
  ) {
    const ToJsonWriter().write(writer, [
      if (plan.holderName != null) '...fragments.toJson().fields',
      for (final field in fields)
        '${field.keyLiteral}: ${field.codecName}.write(${field.member})',
    ]);
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/planned_field.dart';
import 'dart_string_literal.dart';
import 'dart_type.dart';
import 'imports.dart';
import 'type_mapper.dart';
import 'value_member.dart';

/// A field of a generated data class as it is written: its Dart type, codec,
/// doc comment and the expressions that read and write it.
final class DataClassField {
  /// Maps [field] with [mapper], recording the imports its type needs.
  ///
  /// A conditional field is nullable: when its condition leaves it out the
  /// JSON has no key and the codec reads null.
  factory DataClassField.of(
    PlannedField field,
    TypeMapper mapper,
    Imports imports,
  ) {
    final TypeRef declared = field.type;
    final TypeRef shown = field.isConditional && declared is NonNullType
        ? declared.type
        : declared;
    return DataClassField._(
      field,
      mapper.of(shown, imports, objectClass: field.className),
    );
  }

  DataClassField._(this._field, this.type);

  static const String _leftOut = '`@include` or `@skip` left it out.';

  final PlannedField _field;

  /// The Dart type and codec.
  final DartType type;

  /// The Dart member name.
  String get member => _field.memberName;

  /// The key in the JSON response.
  String get responseName => _field.responseName;

  /// Whether the field may be absent because of a variable condition.
  bool get isConditional => _field.isConditional;

  /// Whether the Dart type is nullable.
  bool get isNullable => type.type.endsWith('?');

  /// The name of the private codec constant.
  String get codecName => '_${member}Codec';

  /// The field as a part of the class's value.
  ValueMember get valueMember =>
      ValueMember(member, type.type.startsWith('List<'));

  /// The JSON key as a Dart string literal.
  String get keyLiteral => const DartStringLiteral().of(responseName);

  /// The doc comment: the schema description, else a default sentence.
  String get doc {
    final String description = _field.definition?.description?.trim() ?? '';
    if (description.isNotEmpty) {
      return isConditional
          ? '$description\n\nNull when $_leftOut'
          : description;
    }
    return isConditional
        ? 'The field `$responseName`; null when $_leftOut'
        : 'The field `$responseName`.';
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/planned_class.dart';
import '../plan/shape_planner.dart';
import 'class_documentation.dart';
import 'dart_writer.dart';
import 'data_class_emitter.dart';
import 'fragment_holder_emitter.dart';
import 'generated_header.dart';
import 'imports.dart';
import 'library_imports.dart';
import 'type_mapper.dart';

/// Writes the library of one document file: the classes of its fragments
/// (spec §7 "Files").
///
/// {@category codegen}
final class DocumentLibraryEmitter {
  /// Creates the emitter; [planner] plans the classes, [mapper] maps their
  /// types and [libraryImports] decides the imports.
  const DocumentLibraryEmitter(this.planner, this.mapper, this.libraryImports);

  /// The class planner.
  final ShapePlanner planner;

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The recorder of the imports.
  final LibraryImports libraryImports;

  /// The path of the library generated from the document file [documentPath].
  String libraryPathOf(String documentPath) => '$documentPath.dart';

  /// The text of the library of [documentPath], which defines [fragments] in
  /// document order.
  String emit(String documentPath, List<FragmentDefinition> fragments) {
    final imports = Imports();
    final body = DartWriter();
    final String libraryPath = libraryPathOf(documentPath);
    final plans = [
      for (final fragment in fragments)
        (fragment, planner.planFragment(fragment)),
    ];
    final all = [for (final (_, classes) in plans) ...classes];
    libraryImports.record(imports, libraryPath, all);
    var isFirst = true;
    for (final (fragment, classes) in plans) {
      for (final planned in classes) {
        if (!isFirst) body.line();
        isFirst = false;
        _write(planned, classes, fragment.name.value, body, imports);
      }
    }
    final head = DartWriter();
    const GeneratedHeader().write(head, source: documentPath);
    imports.write(head);
    head.line();
    return all.isEmpty ? head.text : '${head.text}\n${body.text}';
  }

  void _write(
    PlannedClass planned,
    List<PlannedClass> classes,
    String fragmentName,
    DartWriter body,
    Imports imports,
  ) {
    switch (planned) {
      case final DataClassPlan plan:
        final doc = ClassDocumentation(
          classes,
        ).of(plan, fragmentName: fragmentName);
        DataClassEmitter(mapper).emit(plan, doc, body, imports);
      case final FragmentHolderPlan plan:
        const FragmentHolderEmitter().emit(plan, body);
      case PolymorphicBasePlan():
        throw StateError('${planned.name} needs the polymorphic emitter.');
    }
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart`:

```dart
import '../plan/condition.dart';
import '../plan/planned_class.dart';
import '../plan/planned_fragment.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'reader_factory_writer.dart';
import 'to_json_writer.dart';
import 'value_member.dart';
import 'value_members.dart';

/// Writes the class that holds the fragments spread on a selection (spec §7
/// "Data classes", R7.4).
///
/// {@category codegen}
final class FragmentHolderEmitter {
  /// Creates the emitter.
  const FragmentHolderEmitter();

  static const String _leftOut = '`@include` or `@skip` left it out.';

  /// Writes [plan].
  void emit(FragmentHolderPlan plan, DartWriter writer) {
    final fragments = plan.fragments;
    writer.doc('The fragments spread on [${plan.ownerName}].');
    writer.block('final class ${plan.name} implements client.DataObject', () {
      writer.doc('Creates the fragments.');
      writer.items('const ${plan.name}({', [
        for (final fragment in fragments)
          if (!fragment.isConditional) 'required this.${fragment.memberName}',
        for (final fragment in fragments)
          if (fragment.isConditional) 'this.${fragment.memberName}',
      ], '});');
      writer.line();
      const ReaderFactoryWriter().write(writer, plan.name, [
        for (final fragment in fragments)
          (fragment.memberName, _read(fragment)),
      ]);
      for (final fragment in fragments) {
        writer.line();
        writer.doc(
          fragment.isConditional
              ? 'The fragment `${fragment.fragmentName}`; null when $_leftOut'
              : 'The fragment `${fragment.fragmentName}`.',
        );
        final String question = fragment.isConditional ? '?' : '';
        writer.line(
          'final ${fragment.className}$question ${fragment.memberName};',
        );
      }
      writer.line();
      const ToJsonWriter().write(writer, [
        for (final fragment in fragments) _spread(fragment),
      ]);
      writer.line();
      const ValueMembers().write(writer, plan.name, [
        for (final fragment in fragments)
          ValueMember(fragment.memberName, false),
      ]);
    });
  }

  String _spread(PlannedFragment fragment) => fragment.isConditional
      ? '...?${fragment.memberName}?.toJson().fields'
      : '...${fragment.memberName}.toJson().fields';

  String _read(PlannedFragment fragment) {
    final String read = '${fragment.className}.codec.read(json, context)';
    if (!fragment.isConditional) {
      return read;
    }
    return '${_condition(fragment.whenAny)} ? $read : null';
  }

  // The spread is selected when all conditions of any one list hold.
  String _condition(List<List<Condition>> whenAny) {
    final bool isSeveral = whenAny.length > 1;
    return [
      for (final conditions in whenAny)
        _conjunction(conditions, isParenthesized: isSeveral),
    ].join(' || ');
  }

  String _conjunction(
    List<Condition> conditions, {
    required bool isParenthesized,
  }) {
    final String text = [
      for (final condition in conditions)
        '${condition.isInclude ? '' : '!'}context.flag('
            '${const DartStringLiteral().of(condition.variable)})',
    ].join(' && ');
    return isParenthesized && conditions.length > 1 ? '($text)' : text;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/planned_class.dart';
import 'imports.dart';

/// Records the imports of a generated document library (spec §7 "Files").
///
/// {@category codegen}
final class LibraryImports {
  /// Creates the recorder.
  ///
  /// [schemaTypesPath] is the schema-types library and [fragmentLibraries]
  /// the library of each fragment, by fragment name; all paths are relative
  /// to the configuration file.
  const LibraryImports(
    this.schema,
    this.schemaTypesPath,
    this.fragmentLibraries,
  );

  /// The schema the field types belong to.
  final Schema schema;

  /// The path of the schema-types library.
  final String schemaTypesPath;

  /// The library path that defines each fragment, by fragment name.
  final Map<String, String> fragmentLibraries;

  /// Records into [imports] what the library at [libraryPath] needs for
  /// [classes]. The imports of custom scalars are recorded while the classes
  /// are written.
  void record(
    Imports imports,
    String libraryPath,
    List<PlannedClass> classes,
  ) {
    if (classes.isEmpty) {
      return;
    }
    imports.package(
      'package:typed_graphql/typed_graphql.dart',
      prefix: 'graphql',
    );
    imports.package(
      'package:typed_graphql_client/typed_graphql_client.dart',
      prefix: 'client',
    );
    final targets = <String>{
      if (_usesSchemaTypes(classes)) schemaTypesPath,
      for (final fragment in _spreadFragments(classes))
        ?fragmentLibraries[fragment],
    }..remove(libraryPath);
    for (final target in targets) {
      imports.relative(
        p.posix.relative(target, from: p.posix.dirname(libraryPath)),
      );
    }
  }

  bool _usesSchemaTypes(List<PlannedClass> classes) => classes.any(
    (planned) =>
        planned is DataClassPlan &&
        planned.fields.any(
          (field) => switch (schema.namedTypeOf(field.type)) {
            EnumType() || InputObjectType() => true,
            _ => false,
          },
        ),
  );

  Iterable<String> _spreadFragments(List<PlannedClass> classes) => [
    for (final planned in classes)
      if (planned is FragmentHolderPlan)
        for (final fragment in planned.fragments) fragment.fragmentName,
  ];
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/reader_factory_writer.dart`:

```dart
import 'dart_writer.dart';

/// Writes the `_read` factory of a generated class: the class built from the
/// JSON and the context.
///
/// {@category codegen}
final class ReaderFactoryWriter {
  /// Creates the writer.
  const ReaderFactoryWriter();

  static const List<String> _parameters = <String>[
    'graphql.JsonObject json',
    'client.DataContext context',
  ];

  /// Writes `factory [className]._read(...)` that builds the class from the
  /// named [arguments], pairs of label and value expression.
  ///
  /// The parameters stay on the head's line when they fit; a conditional
  /// value breaks before its `?` and `:`.
  void write(
    DartWriter writer,
    String className,
    List<(String, String)> arguments,
  ) {
    // A call without arguments is constant, or `prefer_const_constructors`
    // fires on the generated code.
    final String callee = arguments.isEmpty ? 'const $className' : className;
    final String head = 'factory $className._read(${_parameters.join(', ')})';
    final List<String> labelled = [
      for (final (String label, String value) in arguments) '$label: $value',
    ];
    if (!writer.fits('$head =>')) {
      writer.line('factory $className._read(');
      writer.indented(() {
        for (final String parameter in _parameters) {
          writer.line('$parameter,');
        }
      });
      _call(writer, ') => $callee(', labelled, arguments);
      return;
    }
    if (writer.fits('$head => $callee(${labelled.join(', ')});')) {
      writer.line('$head => $callee(${labelled.join(', ')});');
      return;
    }
    writer.line('$head =>');
    writer.indented(
      () => writer.indented(
        () => _call(writer, '$callee(', labelled, arguments),
      ),
    );
  }

  void _call(
    DartWriter writer,
    String open,
    List<String> labelled,
    List<(String, String)> arguments,
  ) {
    if (writer.fits('$open${labelled.join(', ')});')) {
      writer.line('$open${labelled.join(', ')});');
      return;
    }
    writer.line(open);
    writer.indented(() {
      for (final (int index, String argument) in labelled.indexed) {
        _argument(writer, argument, arguments[index].$2);
      }
    });
    writer.line(');');
  }

  void _argument(DartWriter writer, String argument, String value) {
    final int question = value.indexOf(' ? ');
    if (writer.fits('$argument,') || question < 0) {
      writer.line('$argument,');
      return;
    }
    final int colon = value.lastIndexOf(' : ');
    final String label = argument.substring(0, argument.length - value.length);
    writer.line('$label${value.substring(0, question)}');
    writer.indented(() {
      writer.indented(() {
        writer.line(value.substring(question + 1, colon));
        writer.line('${value.substring(colon + 1)},');
      });
    });
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart`:

```dart
import 'dart_writer.dart';

/// Writes the `toJson` override of a generated class.
///
/// {@category codegen}
final class ToJsonWriter {
  /// Creates the writer.
  const ToJsonWriter();

  static const String _head = 'graphql.JsonObject toJson()';

  /// Writes `toJson` returning an object of the map [entries]: `'key': value`
  /// pairs and `...spreads`.
  ///
  /// One entry may move to the next line; several are written one per line
  /// once they do not fit on the head's line.
  void write(DartWriter writer, List<String> entries) {
    writer.line('@override');
    final String map = '{${entries.join(', ')}}';
    final String single = '$_head => graphql.JsonObject($map);';
    if (writer.fits(single)) {
      writer.line(single);
      return;
    }
    if (entries.length == 1) {
      writer.line('$_head =>');
      writer.indented(
        () => writer.indented(() => writer.line('graphql.JsonObject($map);')),
      );
      return;
    }
    writer.line('$_head => graphql.JsonObject({');
    writer.indented(() {
      for (final String entry in entries) {
        writer.line('$entry,');
      }
    });
    writer.line('});');
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/value_member.dart`:

```dart
/// A member that takes part in the value semantics of a generated class.
final class const ValueMember(
  /// The Dart member name.
  final String name,

  /// Whether its value is a `List`, which `==` and `hashCode` compare by
  /// content through `DataEquality`.
  final bool isList,
) {
  /// Creates a member.
  this;

  /// How `==` reads the member of the compared object.
  String get otherRead => 'other.$name';

  /// How `==` reads the member of this object: a member named `other` would
  /// be shadowed by the parameter.
  String get ownRead => name == 'other' ? 'this.other' : name;

  /// The member read inside a string literal: `$name`, or `${name}` when the
  /// name has a `$` that would end the short form early.
  String get interpolation => name.contains(r'$') ? '\${$name}' : '\$$name';
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/value_members.dart`:

```dart
import 'dart_writer.dart';
import 'value_member.dart';

/// Writes `==`, `hashCode` and `toString` of a generated class from its
/// [ValueMember]s.
///
/// {@category codegen}
final class ValueMembers {
  /// Creates the writer.
  const ValueMembers();

  /// Writes the three members for the class [className], separated by blank
  /// lines.
  void write(
    DartWriter writer,
    String className,
    List<ValueMember> members,
  ) {
    _equality(writer, className, members);
    writer.line();
    _hashCode(writer, members);
    writer.line();
    _toString(writer, className, members);
  }

  void _equality(
    DartWriter writer,
    String className,
    List<ValueMember> members,
  ) {
    writer.line('@override');
    const String head = 'bool operator ==(Object other)';
    final List<String> operands = [
      'other is $className',
      for (final member in members) _comparison(member),
    ];
    final String joined = operands.join(' && ');
    var isOneLineAfterBreak = false;
    writer.indented(
      () => writer.indented(
        () => isOneLineAfterBreak = writer.fits('$joined;'),
      ),
    );
    if (!writer.fits('$head => $joined;') && isOneLineAfterBreak) {
      writer.line('$head =>');
      writer.indented(() => writer.indented(() => writer.line('$joined;')));
      return;
    }
    writer.arrowJoined(head, operands, '&&');
  }

  String _comparison(ValueMember member) => member.isList
      ? 'const client.DataEquality().equals('
            '${member.otherRead}, ${member.ownRead})'
      : '${member.otherRead} == ${member.ownRead}';

  String _hashOf(ValueMember member) => member.isList
      ? 'const client.DataEquality().hash(${member.name})'
      : member.name;

  // The label is text, so its `$` is escaped; the value is read.
  String _label(ValueMember member) =>
      '${_escaped(member.name)}: ${member.interpolation}';

  String _escaped(String text) => text.replaceAll(r'$', r'\$');

  void _hashCode(DartWriter writer, List<ValueMember> members) {
    writer.line('@override');
    final List<String> parts = [for (final member in members) _hashOf(member)];
    switch (members) {
      case []:
        writer.line('int get hashCode => 0;');
      case [ValueMember(isList: false)]:
        writer.line('int get hashCode => ${members.single.name}.hashCode;');
      case [ValueMember(isList: true)]:
        writer.line('int get hashCode => ${parts.single};');
      case _:
        writer.items('int get hashCode => Object.hashAll([', parts, ']);');
    }
  }

  void _toString(
    DartWriter writer,
    String className,
    List<ValueMember> members,
  ) {
    final String parts = [for (final member in members) _label(member)]
        .join(', ');
    writer
      ..line('@override')
      ..arrow('String toString()', "'${_escaped(className)}($parts)'");
  }
}
```

In `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,6 +7,7 @@ import '../project/project_file.dart';
 import 'client_project.dart';
 import 'client_project_loader.dart';
 import 'client_project_result.dart';
+import 'document_libraries.dart';
 import 'generated_file.dart';
 import 'generated_names.dart';
 import 'generation_result.dart';
@@ -76,8 +77,9 @@ final class const ClientGenerator(final CodegenConfig config) {
   /// reported. With any error the result has no files.
   ///
   /// [schema] is the schema file and [documents] the files the configuration's
-  /// `documents` globs matched; nothing is written. For now the only file is
-  /// the schema-types library at [CodegenConfig.schemaTypes].
+  /// `documents` globs matched; nothing is written. The files
+  /// are the schema-types library at [CodegenConfig.schemaTypes], then a
+  /// library per document file, at its path plus `.dart`, sorted by path.
   GenerationResult generate({
     required ProjectFile schema,
     required List<ProjectFile> documents,
@@ -117,11 +119,11 @@ final class const ClientGenerator(final CodegenConfig config) {
     if (names.diagnostics.isNotEmpty) {
       return GenerationResult(const [], [...warnings, ...names.diagnostics]);
     }
-    final text = SchemaTypesEmitter(
-      TypeMapper(project.schema.schema, config.scalars),
-    ).emit(types, source: schemaPath);
+    final mapper = TypeMapper(project.schema.schema, config.scalars);
+    final text = SchemaTypesEmitter(mapper).emit(types, source: schemaPath);
     return GenerationResult([
       GeneratedFile(config.schemaTypes, text),
+      ...DocumentLibraries(project, mapper, config.schemaTypes).generate(),
     ], warnings);
   }
 }
```

Create `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../emit/document_library_emitter.dart';
import '../emit/library_imports.dart';
import '../emit/type_mapper.dart';
import '../plan/shape_planner.dart';
import 'client_project.dart';
import 'generated_file.dart';

/// Generates the library of every document file of a project (spec §7
/// "Files").
final class DocumentLibraries {
  /// Creates the generator for [project]; [schemaTypesPath] is the
  /// schema-types library its libraries import.
  const DocumentLibraries(this.project, this.mapper, this.schemaTypesPath);

  /// The project whose document files are generated.
  final ClientProject project;

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The path of the schema-types library.
  final String schemaTypesPath;

  /// A library per document file, sorted by path.
  List<GeneratedFile> generate() {
    final files = project.documents.files;
    final map = project.documents.sourceMap;
    final fragmentsByFile = <int, List<FragmentDefinition>>{};
    final fragmentsByName = <String, FragmentDefinition>{};
    final libraryOf = <String, String>{};
    for (final definition in project.document.document.definitions) {
      if (definition is! FragmentDefinition) continue;
      final index = map.fileIndexAt(definition.start);
      fragmentsByFile.putIfAbsent(index, () => []).add(definition);
      fragmentsByName[definition.name.value] = definition;
      libraryOf[definition.name.value] = '${files[index].path}.dart';
    }
    final emitter = DocumentLibraryEmitter(
      ShapePlanner(project.schema.schema, fragmentsByName),
      mapper,
      LibraryImports(project.schema.schema, schemaTypesPath, libraryOf),
    );
    return [
      for (final (int index, file) in files.indexed)
        GeneratedFile(
          emitter.libraryPathOf(file.path),
          emitter.emit(file.path, fragmentsByFile[index] ?? const []),
        ),
    ];
  }
}
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/data_class_emitter_test.dart test/emit/document_library_emitter_test.dart test/emit/fragment_holder_emitter_test.dart test/generator/client_generator_generate_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `ClientGenerator.generate` writes a library per document file, at the file's
  path plus `.dart`: the classes of the file's fragments (a data class with
  `decode`, `toJson`, value equality and a private codec per field, and a
  `...Fragments` holder per selection that spreads fragments) and the imports
  they need. Depends on `package:path`.
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -209,8 +209,45 @@ final class RoleUnknown implements Role {
   @override
   String toString() => 'RoleUnknown($raw)';
 }
+
+// role.graphql.dart
+// GENERATED CODE - DO NOT MODIFY BY HAND.
+// Generated by typed_graphql_codegen from role.graphql.
+// dart format off
+```
+
+## Document libraries
+
+Each document file gets a library at its own path plus `.dart`
+(`lib/user.graphql` becomes `lib/user.graphql.dart`), in path order after the
+schema-types library. A document without a fragment gets a library with only
+the header. The library of a file holds the classes of the fragments defined
+in it, in document order, and imports only what they use: the runtime, custom
+scalar libraries, the schema types when a field is an enum or an input object,
+and the library of another file when a fragment spreads one defined there.
+Imports of generated libraries are relative and unprefixed, which is safe
+because generated names are unique in the project.
+
+A fragment `UserCard` is the class `UserCard`. Each composite field of its
+selection is a class named after the field (`UserCardFriends`), and the
+fragments spread on a selection are the members of a `...Fragments` class
+that the value holds as `fragments`:
+
+```text
+final class UserCardFragments implements client.DataObject {
+  const UserCardFragments({this.userName});
+
+  /// The fragment `UserName`; null when `@include` or `@skip` left it out.
+  final UserName? userName;
+}
 ```
 
+A spread under `@include` or `@skip` is nullable; the context of a read says
+which variables are true. `UserCard.decode(json, variables: ...)` reads a
+fragment on its own, and `toJson` writes it back; `==` compares lists by
+content. The golden `test/goldens/fragments` is analyzed and run like the
+other goldens.
+
 ## Schema types
 
 The file at `schema_types` holds what the documents reach: the enums and
````

- [ ] **Step 7: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart packages/typed_graphql_codegen/lib/src/emit/library_imports.dart packages/typed_graphql_codegen/lib/src/emit/reader_factory_writer.dart packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart packages/typed_graphql_codegen/lib/src/emit/value_member.dart packages/typed_graphql_codegen/lib/src/emit/value_members.dart packages/typed_graphql_codegen/lib/src/generator/client_generator.dart packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart packages/typed_graphql_codegen/pubspec.yaml packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_card.graphql packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_card_query.graphql packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_name.graphql packages/typed_graphql_codegen/test/goldens/fragments/input/schema.graphql packages/typed_graphql_codegen/test/goldens/fragments/input/typed_graphql.yaml packages/typed_graphql_codegen/test/goldens/fragments/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_name.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt packages/typed_graphql_codegen/test/goldens/fragments/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt packages/typed_graphql_codegen/test/goldens/fragments/support/packages/scalar_codecs/pubspec.yaml.txt packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden packages/typed_graphql_codegen/test/support/class_emission.dart
git commit -q -m "feat(typed_graphql_codegen): generate fragment classes in a library per document" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Generate sealed classes for abstract selections

A selection that plans variants generates a sealed class that reads `__typename` (`PolymorphicBaseEmitter`), a final class per type and an unknown class for any other type; shared fields and the shared fragment holder are declared by the sealed class and overridden by the variants. A fragment's own `decode` goes through `FragmentDecodeWriter`. The `polymorphic` golden case.

Commit on the branch: `8621d87`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/fragment_decode_writer.dart`, `packages/typed_graphql_codegen/lib/src/emit/polymorphic_base_emitter.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart`, `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart`, `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart`
- Test: `packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart`, `packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_node.graphql`, `packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_query.graphql`, `packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_result.graphql`, `packages/typed_graphql_codegen/test/goldens/polymorphic/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/polymorphic/input/typed_graphql.yaml`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_node.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_result.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/support/bin/round_trip.dart.txt`, `packages/typed_graphql_codegen/test/support/class_emission.dart`

**Interfaces:**
- Consumes: Tasks 3-4.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/class_documentation.dart
  String of(DataClassPlan plan,
  String ofBase(PolymorphicBasePlan plan,

// emit/data_class_field.dart
  bool get overridesBase

// emit/fragment_decode_writer.dart
final class FragmentDecodeWriter
  const FragmentDecodeWriter()
  void write(DartWriter writer, String className)

// emit/polymorphic_base_emitter.dart
final class PolymorphicBaseEmitter
  const PolymorphicBaseEmitter(this.mapper)
  final TypeMapper mapper
  void emit(
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart`:

```dart
import 'package:test/test.dart';

import '../support/class_emission.dart';

const _schema = '''
interface Node { id: ID! }
type User implements Node { id: ID! name: String! owner: User friends(first: Int): [User!]! }
type Bot implements Node { id: ID! model: String }
type Query { node(id: ID!): Node }
''';

void main() {
  test('the sealed base of a fragment on an interface', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...NodeCard } }
fragment NodeCard on Node { id ... on User { name } ... on Bot { model } }
''');
    expect(emission.emitFragment('NodeCard', 'NodeCard'), '''
/// The fragment `NodeCard` on `Node`: a class per type the selection tells
/// apart, and [NodeCardUnknown] for any other type.
sealed class NodeCard implements client.DataObject {
  factory NodeCard._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => NodeCardUser._read(json, context),
    'Bot' => NodeCardBot._read(json, context),
    _ => NodeCardUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<NodeCard> codec =
      client.ObjectDataCodec(NodeCard._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<NodeCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The field `id`.
  String get id;
}
''');
  });

  test('a variant has the fields it overrides from the base', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...NodeCard } }
fragment NodeCard on Node { id ... on User { name } ... on Bot { model } }
''');
    expect(emission.emitFragment('NodeCard', 'NodeCardBot'), r'''
/// [NodeCard] when its type is `Bot`.
final class NodeCardBot implements NodeCard {
  /// Creates the value.
  const NodeCardBot({required this.id, this.model});

  factory NodeCardBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardBot(
    id: _idCodec.field(json, 'id', context),
    model: _modelCodec.field(json, 'model', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  @override
  final String id;

  /// The field `model`.
  final String? model;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardBot && other.id == id && other.model == model;

  @override
  int get hashCode => Object.hashAll([id, model]);

  @override
  String toString() => 'NodeCardBot(id: $id, model: $model)';
}
''');
  });

  test('the unknown variant holds the type name', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...NodeCard } }
fragment NodeCard on Node { id ... on User { name } ... on Bot { model } }
''');
    expect(emission.emitFragment('NodeCard', 'NodeCardUnknown'), r'''
/// [NodeCard] when its type is none of those the selection tells apart.
final class NodeCardUnknown implements NodeCard {
  /// Creates the value.
  const NodeCardUnknown({required this.typename, required this.id});

  factory NodeCardUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    id: _idCodec.field(json, 'id', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  @override
  final String typename;

  @override
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': _typenameCodec.write(typename),
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardUnknown && other.typename == typename && other.id == id;

  @override
  int get hashCode => Object.hashAll([typename, id]);

  @override
  String toString() => 'NodeCardUnknown(typename: $typename, id: $id)';
}
''');
  });

  test('a base with a shared holder declares the fragments', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...Held } }
fragment Held on Node { ...Idf ... on User { name } ... on Bot { model } }
fragment Idf on Node { id }
''');
    expect(emission.emitFragment('Held', 'Held'), '''
/// The fragment `Held` on `Node`: a class per type the selection tells apart,
/// and [HeldUnknown] for any other type.
sealed class Held implements client.DataObject {
  factory Held._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => HeldUser._read(json, context),
    'Bot' => HeldBot._read(json, context),
    _ => HeldUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<Held> codec =
      client.ObjectDataCodec(Held._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<Held> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The fragments spread on this value.
  HeldFragments get fragments;
}
''');
  });

  test('a variant overrides the shared holder', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...Held } }
fragment Held on Node { ...Idf ... on User { name } ... on Bot { model } }
fragment Idf on Node { id }
''');
    expect(emission.emitFragment('Held', 'HeldUser'), r'''
/// [Held] when its type is `User`.
final class HeldUser implements Held {
  /// Creates the value.
  const HeldUser({required this.name, required this.fragments});

  factory HeldUser._read(graphql.JsonObject json, client.DataContext context) =>
      HeldUser(
        name: _nameCodec.field(json, 'name', context),
        fragments: HeldFragments._read(json, context),
      );

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  /// The field `name`.
  final String name;

  @override
  final HeldFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is HeldUser && other.name == name && other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([name, fragments]);

  @override
  String toString() => 'HeldUser(name: $name, fragments: $fragments)';
}
''');
  });

  test('a variant with a holder of its own does not override', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...Own } }
fragment Own on Node { ... on User { ...U } ... on Bot { model } }
fragment U on User { name }
''');
    expect(emission.emitFragment('Own', 'OwnUser'), r'''
/// [Own] when its type is `User`.
final class OwnUser implements Own {
  /// Creates the value.
  const OwnUser({required this.fragments});

  factory OwnUser._read(graphql.JsonObject json, client.DataContext context) =>
      OwnUser(fragments: OwnUserFragments._read(json, context));

  @override
  String get typename => 'User';

  /// The fragments spread on this value.
  final OwnUserFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
  });

  @override
  bool operator ==(Object other) =>
      other is OwnUser && other.fragments == fragments;

  @override
  int get hashCode => fragments.hashCode;

  @override
  String toString() => 'OwnUser(fragments: $fragments)';
}
''');
  });
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_node.graphql`:

```graphql
fragment NodeCard on Node {
  id
  ... on User {
    name
    ...UserName
  }
  ... on Bot {
    model
  }
}

fragment UserName on User {
  name
}

fragment Reselect on Node {
  id
  ... on User {
    id
    friends(first: 1) {
      name
    }
  }
}

fragment Owned on Node {
  id
  owner {
    name
  }
  ... on User {
    name
  }
  ... on Bot {
    model
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_query.graphql`:

```graphql
query FindNode($id: ID!) {
  node(id: $id) {
    ...NodeCard
    ...Owned
    ...Reselect
    ...Labelled
  }
  search {
    ...Result
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_result.graphql`:

```graphql
fragment Result on SearchResult {
  __typename
  ... on User {
    id
    friends(first: 1) {
      id
    }
  }
  ... on Bot {
    id
  }
}

fragment Labelled on Node {
  ...NodeId
  ... on User {
    name
  }
  ... on Bot {
    model
  }
}

fragment NodeId on Node {
  id
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/input/schema.graphql`:

```graphql
interface Node {
  id: ID!
  owner: User
}

type User implements Node {
  id: ID!
  "The display name."
  name: String!
  owner: User
  friends(first: Int): [User!]!
}

type Bot implements Node {
  id: ID!
  model: String
  owner: User
}

union SearchResult = User | Bot

type Query {
  node(id: ID!): Node
  search: [SearchResult!]!
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/input/typed_graphql.yaml`:

```yaml
schema: schema.graphql
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/schema.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_node.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_node.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The fragment `NodeCard` on `Node`: a class per type the selection tells
/// apart, and [NodeCardUnknown] for any other type.
sealed class NodeCard implements client.DataObject {
  factory NodeCard._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => NodeCardUser._read(json, context),
    'Bot' => NodeCardBot._read(json, context),
    _ => NodeCardUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<NodeCard> codec =
      client.ObjectDataCodec(NodeCard._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<NodeCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The field `id`.
  String get id;
}

/// [NodeCard] when its type is `User`.
final class NodeCardUser implements NodeCard {
  /// Creates the value.
  const NodeCardUser({
    required this.id,
    required this.name,
    required this.fragments,
  });

  factory NodeCardUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardUser(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
    fragments: NodeCardUserFragments._read(json, context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  @override
  final String id;

  /// The display name.
  final String name;

  /// The fragments spread on this value.
  final NodeCardUserFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardUser &&
      other.id == id &&
      other.name == name &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([id, name, fragments]);

  @override
  String toString() =>
      'NodeCardUser(id: $id, name: $name, fragments: $fragments)';
}

/// The fragments spread on [NodeCardUser].
final class NodeCardUserFragments implements client.DataObject {
  /// Creates the fragments.
  const NodeCardUserFragments({required this.userName});

  factory NodeCardUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardUserFragments(userName: UserName.codec.read(json, context));

  /// The fragment `UserName`.
  final UserName userName;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...userName.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is NodeCardUserFragments && other.userName == userName;

  @override
  int get hashCode => userName.hashCode;

  @override
  String toString() => 'NodeCardUserFragments(userName: $userName)';
}

/// [NodeCard] when its type is `Bot`.
final class NodeCardBot implements NodeCard {
  /// Creates the value.
  const NodeCardBot({required this.id, this.model});

  factory NodeCardBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardBot(
    id: _idCodec.field(json, 'id', context),
    model: _modelCodec.field(json, 'model', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  @override
  final String id;

  /// The field `model`.
  final String? model;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardBot && other.id == id && other.model == model;

  @override
  int get hashCode => Object.hashAll([id, model]);

  @override
  String toString() => 'NodeCardBot(id: $id, model: $model)';
}

/// [NodeCard] when its type is none of those the selection tells apart.
final class NodeCardUnknown implements NodeCard {
  /// Creates the value.
  const NodeCardUnknown({required this.typename, required this.id});

  factory NodeCardUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    id: _idCodec.field(json, 'id', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  @override
  final String typename;

  @override
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': _typenameCodec.write(typename),
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardUnknown && other.typename == typename && other.id == id;

  @override
  int get hashCode => Object.hashAll([typename, id]);

  @override
  String toString() => 'NodeCardUnknown(typename: $typename, id: $id)';
}

/// The fragment `UserName` on `User`.
final class UserName implements client.DataObject {
  /// Creates the fragment.
  const UserName({required this.name});

  factory UserName._read(graphql.JsonObject json, client.DataContext context) =>
      UserName(name: _nameCodec.field(json, 'name', context));

  /// Reads and writes the fragment.
  static const client.DataCodec<UserName> codec =
      client.ObjectDataCodec(UserName._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The display name.
  final String name;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserName> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'name': _nameCodec.write(name)});

  @override
  bool operator ==(Object other) => other is UserName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'UserName(name: $name)';
}

/// The fragment `Reselect` on `Node`: a class per type the selection tells
/// apart, and [ReselectUnknown] for any other type.
sealed class Reselect implements client.DataObject {
  factory Reselect._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => ReselectUser._read(json, context),
    _ => ReselectUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<Reselect> codec =
      client.ObjectDataCodec(Reselect._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<Reselect> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;
}

/// [Reselect] when its type is `User`.
final class ReselectUser implements Reselect {
  /// Creates the value.
  const ReselectUser({required this.id, required this.friends});

  factory ReselectUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ReselectUser(
    id: _idCodec.field(json, 'id', context),
    friends: _friendsCodec.field(json, 'friends', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<List<ReselectUserFriends>> _friendsCodec =
      client.ListDataCodec(ReselectUserFriends.codec);

  @override
  String get typename => 'User';

  /// The field `id`.
  final String id;

  /// The field `friends`.
  final List<ReselectUserFriends> friends;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('User'),
    'id': _idCodec.write(id),
    'friends': _friendsCodec.write(friends),
  });

  @override
  bool operator ==(Object other) =>
      other is ReselectUser &&
      other.id == id &&
      const client.DataEquality().equals(other.friends, friends);

  @override
  int get hashCode => Object.hashAll([
    id,
    const client.DataEquality().hash(friends),
  ]);

  @override
  String toString() => 'ReselectUser(id: $id, friends: $friends)';
}

/// The items of the field `friends` of [ReselectUser].
final class ReselectUserFriends implements client.DataObject {
  /// Creates the value.
  const ReselectUserFriends({required this.name});

  factory ReselectUserFriends._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ReselectUserFriends(name: _nameCodec.field(json, 'name', context));

  /// Reads and writes the value.
  static const client.DataCodec<ReselectUserFriends> codec =
      client.ObjectDataCodec(ReselectUserFriends._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The display name.
  final String name;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'name': _nameCodec.write(name)});

  @override
  bool operator ==(Object other) =>
      other is ReselectUserFriends && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'ReselectUserFriends(name: $name)';
}

/// [Reselect] when its type is none of those the selection tells apart.
final class ReselectUnknown implements Reselect {
  /// Creates the value.
  const ReselectUnknown({required this.typename, required this.id});

  factory ReselectUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ReselectUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    id: _idCodec.field(json, 'id', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  @override
  final String typename;

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': _typenameCodec.write(typename),
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is ReselectUnknown && other.typename == typename && other.id == id;

  @override
  int get hashCode => Object.hashAll([typename, id]);

  @override
  String toString() => 'ReselectUnknown(typename: $typename, id: $id)';
}

/// The fragment `Owned` on `Node`: a class per type the selection tells apart,
/// and [OwnedUnknown] for any other type.
sealed class Owned implements client.DataObject {
  factory Owned._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => OwnedUser._read(json, context),
    'Bot' => OwnedBot._read(json, context),
    _ => OwnedUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<Owned> codec =
      client.ObjectDataCodec(Owned._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<Owned> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The field `id`.
  String get id;

  /// The field `owner`.
  OwnedOwner? get owner;
}

/// The field `owner` of [Owned].
final class OwnedOwner implements client.DataObject {
  /// Creates the value.
  const OwnedOwner({required this.name});

  factory OwnedOwner._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => OwnedOwner(name: _nameCodec.field(json, 'name', context));

  /// Reads and writes the value.
  static const client.DataCodec<OwnedOwner> codec =
      client.ObjectDataCodec(OwnedOwner._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The display name.
  final String name;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'name': _nameCodec.write(name)});

  @override
  bool operator ==(Object other) => other is OwnedOwner && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'OwnedOwner(name: $name)';
}

/// [Owned] when its type is `User`.
final class OwnedUser implements Owned {
  /// Creates the value.
  const OwnedUser({required this.id, required this.name, this.owner});

  factory OwnedUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => OwnedUser(
    id: _idCodec.field(json, 'id', context),
    owner: _ownerCodec.field(json, 'owner', context),
    name: _nameCodec.field(json, 'name', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<OwnedOwner?> _ownerCodec =
      client.NullableDataCodec(OwnedOwner.codec);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  @override
  final String id;

  @override
  final OwnedOwner? owner;

  /// The display name.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('User'),
    'id': _idCodec.write(id),
    'owner': _ownerCodec.write(owner),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is OwnedUser &&
      other.id == id &&
      other.owner == owner &&
      other.name == name;

  @override
  int get hashCode => Object.hashAll([id, owner, name]);

  @override
  String toString() => 'OwnedUser(id: $id, owner: $owner, name: $name)';
}

/// [Owned] when its type is `Bot`.
final class OwnedBot implements Owned {
  /// Creates the value.
  const OwnedBot({required this.id, this.owner, this.model});

  factory OwnedBot._read(graphql.JsonObject json, client.DataContext context) =>
      OwnedBot(
        id: _idCodec.field(json, 'id', context),
        owner: _ownerCodec.field(json, 'owner', context),
        model: _modelCodec.field(json, 'model', context),
      );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<OwnedOwner?> _ownerCodec =
      client.NullableDataCodec(OwnedOwner.codec);

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  @override
  final String id;

  @override
  final OwnedOwner? owner;

  /// The field `model`.
  final String? model;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
    'owner': _ownerCodec.write(owner),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is OwnedBot &&
      other.id == id &&
      other.owner == owner &&
      other.model == model;

  @override
  int get hashCode => Object.hashAll([id, owner, model]);

  @override
  String toString() => 'OwnedBot(id: $id, owner: $owner, model: $model)';
}

/// [Owned] when its type is none of those the selection tells apart.
final class OwnedUnknown implements Owned {
  /// Creates the value.
  const OwnedUnknown({required this.typename, required this.id, this.owner});

  factory OwnedUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => OwnedUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    id: _idCodec.field(json, 'id', context),
    owner: _ownerCodec.field(json, 'owner', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<OwnedOwner?> _ownerCodec =
      client.NullableDataCodec(OwnedOwner.codec);

  @override
  final String typename;

  @override
  final String id;

  @override
  final OwnedOwner? owner;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': _typenameCodec.write(typename),
    'id': _idCodec.write(id),
    'owner': _ownerCodec.write(owner),
  });

  @override
  bool operator ==(Object other) =>
      other is OwnedUnknown &&
      other.typename == typename &&
      other.id == id &&
      other.owner == owner;

  @override
  int get hashCode => Object.hashAll([typename, id, owner]);

  @override
  String toString() =>
      'OwnedUnknown(typename: $typename, id: $id, owner: $owner)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_query.graphql.
// dart format off
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_result.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_result.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The fragment `Result` on `SearchResult`: a class per type the selection
/// tells apart, and [ResultUnknown] for any other type.
sealed class Result implements client.DataObject {
  factory Result._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => ResultUser._read(json, context),
    'Bot' => ResultBot._read(json, context),
    _ => ResultUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<Result> codec =
      client.ObjectDataCodec(Result._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<Result> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;
}

/// [Result] when its type is `User`.
final class ResultUser implements Result {
  /// Creates the value.
  const ResultUser({required this.id, required this.friends});

  factory ResultUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ResultUser(
    id: _idCodec.field(json, 'id', context),
    friends: _friendsCodec.field(json, 'friends', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<List<ResultUserFriends>> _friendsCodec =
      client.ListDataCodec(ResultUserFriends.codec);

  @override
  String get typename => 'User';

  /// The field `id`.
  final String id;

  /// The field `friends`.
  final List<ResultUserFriends> friends;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('User'),
    'id': _idCodec.write(id),
    'friends': _friendsCodec.write(friends),
  });

  @override
  bool operator ==(Object other) =>
      other is ResultUser &&
      other.id == id &&
      const client.DataEquality().equals(other.friends, friends);

  @override
  int get hashCode => Object.hashAll([
    id,
    const client.DataEquality().hash(friends),
  ]);

  @override
  String toString() => 'ResultUser(id: $id, friends: $friends)';
}

/// The items of the field `friends` of [ResultUser].
final class ResultUserFriends implements client.DataObject {
  /// Creates the value.
  const ResultUserFriends({required this.id});

  factory ResultUserFriends._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ResultUserFriends(id: _idCodec.field(json, 'id', context));

  /// Reads and writes the value.
  static const client.DataCodec<ResultUserFriends> codec =
      client.ObjectDataCodec(ResultUserFriends._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({'id': _idCodec.write(id)});

  @override
  bool operator ==(Object other) =>
      other is ResultUserFriends && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ResultUserFriends(id: $id)';
}

/// [Result] when its type is `Bot`.
final class ResultBot implements Result {
  /// Creates the value.
  const ResultBot({required this.id});

  factory ResultBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ResultBot(id: _idCodec.field(json, 'id', context));

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  @override
  String get typename => 'Bot';

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is ResultBot && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ResultBot(id: $id)';
}

/// [Result] when its type is none of those the selection tells apart.
final class ResultUnknown implements Result {
  /// Creates the value.
  const ResultUnknown({required this.typename});

  factory ResultUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => ResultUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  final String typename;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'__typename': _typenameCodec.write(typename)});

  @override
  bool operator ==(Object other) =>
      other is ResultUnknown && other.typename == typename;

  @override
  int get hashCode => typename.hashCode;

  @override
  String toString() => 'ResultUnknown(typename: $typename)';
}

/// The fragment `Labelled` on `Node`: a class per type the selection tells
/// apart, and [LabelledUnknown] for any other type.
sealed class Labelled implements client.DataObject {
  factory Labelled._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => LabelledUser._read(json, context),
    'Bot' => LabelledBot._read(json, context),
    _ => LabelledUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<Labelled> codec =
      client.ObjectDataCodec(Labelled._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<Labelled> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The fragments spread on this value.
  LabelledFragments get fragments;
}

/// The fragments spread on [Labelled].
final class LabelledFragments implements client.DataObject {
  /// Creates the fragments.
  const LabelledFragments({required this.nodeId});

  factory LabelledFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => LabelledFragments(nodeId: NodeId.codec.read(json, context));

  /// The fragment `NodeId`.
  final NodeId nodeId;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...nodeId.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is LabelledFragments && other.nodeId == nodeId;

  @override
  int get hashCode => nodeId.hashCode;

  @override
  String toString() => 'LabelledFragments(nodeId: $nodeId)';
}

/// [Labelled] when its type is `User`.
final class LabelledUser implements Labelled {
  /// Creates the value.
  const LabelledUser({required this.name, required this.fragments});

  factory LabelledUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => LabelledUser(
    name: _nameCodec.field(json, 'name', context),
    fragments: LabelledFragments._read(json, context),
  );

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  /// The display name.
  final String name;

  @override
  final LabelledFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is LabelledUser &&
      other.name == name &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([name, fragments]);

  @override
  String toString() => 'LabelledUser(name: $name, fragments: $fragments)';
}

/// [Labelled] when its type is `Bot`.
final class LabelledBot implements Labelled {
  /// Creates the value.
  const LabelledBot({required this.fragments, this.model});

  factory LabelledBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => LabelledBot(
    model: _modelCodec.field(json, 'model', context),
    fragments: LabelledFragments._read(json, context),
  );

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  /// The field `model`.
  final String? model;

  @override
  final LabelledFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('Bot'),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is LabelledBot &&
      other.model == model &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([model, fragments]);

  @override
  String toString() => 'LabelledBot(model: $model, fragments: $fragments)';
}

/// [Labelled] when its type is none of those the selection tells apart.
final class LabelledUnknown implements Labelled {
  /// Creates the value.
  const LabelledUnknown({required this.typename, required this.fragments});

  factory LabelledUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => LabelledUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    fragments: LabelledFragments._read(json, context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  final String typename;

  @override
  final LabelledFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': _typenameCodec.write(typename),
  });

  @override
  bool operator ==(Object other) =>
      other is LabelledUnknown &&
      other.typename == typename &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([typename, fragments]);

  @override
  String toString() =>
      'LabelledUnknown(typename: $typename, fragments: $fragments)';
}

/// The fragment `NodeId` on `Node`.
final class NodeId implements client.DataObject {
  /// Creates the fragment.
  const NodeId({required this.id});

  factory NodeId._read(graphql.JsonObject json, client.DataContext context) =>
      NodeId(id: _idCodec.field(json, 'id', context));

  /// Reads and writes the fragment.
  static const client.DataCodec<NodeId> codec =
      client.ObjectDataCodec(NodeId._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The field `id`.
  final String id;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<NodeId> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({'id': _idCodec.write(id)});

  @override
  bool operator ==(Object other) => other is NodeId && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'NodeId(id: $id)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/polymorphic/support/bin/round_trip.dart.txt`:

```text
import 'dart:io';

import 'package:generated_polymorphic/user_node.graphql.dart';
import 'package:generated_polymorphic/user_result.graphql.dart';
import 'package:typed_graphql/typed_graphql.dart';

JsonObject _json(String text) =>
    (const JsonReader().parse(text) as DecodeSuccess<JsonValue>).value
        as JsonObject;

final JsonObject _user = _json('''
{"__typename": "User", "id": "1", "name": "Ada", "owner": {"name": "Zed"},
 "friends": [{"id": "2", "name": "Bob"}]}
''');
final JsonObject _bot = _json('''
{"__typename": "Bot", "id": "3", "model": null, "owner": null}
''');
final JsonObject _robot = _json('''
{"__typename": "Robot", "id": "4", "owner": null}
''');

void main() {
  _nodeCard();
  _result();
  _labelled();
  _owned();
  _reselect();
  _missingTypename();
}

void _nodeCard() {
  final NodeCard user = _decode(NodeCard.decode, _user);
  final String userLabel = switch (user) {
    NodeCardUser(:final name, :final fragments) =>
      '$name ${fragments.userName.name}',
    NodeCardBot() => 'bot',
    NodeCardUnknown() => 'unknown',
  };
  _expect(userLabel, 'Ada Ada');
  _expect(user.typename, 'User');
  _expect(user.id, '1');
  final NodeCard bot = _decode(NodeCard.decode, _bot);
  _expect(bot is NodeCardBot && bot.model == null, true);
  final NodeCard robot = _decode(NodeCard.decode, _robot);
  _expect(robot is NodeCardUnknown && robot.typename == 'Robot', true);
  _expect(robot.id, '4');
  for (final NodeCard value in [user, bot, robot]) {
    _roundTrips(NodeCard.decode, value, value.toJson());
  }
  _expect(user == bot, false);
}

void _result() {
  final Result user = _decode(Result.decode, _user);
  _expect(user is ResultUser && user.friends.single.id == '2', true);
  final Result bot = _decode(Result.decode, _bot);
  _expect(bot is ResultBot && bot.id == '3', true);
  final Result robot = _decode(Result.decode, _robot);
  _expect(robot is ResultUnknown && robot.typename == 'Robot', true);
  for (final Result value in [user, bot, robot]) {
    _roundTrips(Result.decode, value, value.toJson());
  }
}

void _labelled() {
  final Labelled user = _decode(Labelled.decode, _user);
  _expect(user.fragments.nodeId.id, '1');
  final Labelled robot = _decode(Labelled.decode, _robot);
  _expect(robot.fragments.nodeId.id, '4');
  _expect(user is LabelledUser && user.name == 'Ada', true);
  for (final Labelled value in [user, robot]) {
    _roundTrips(Labelled.decode, value, value.toJson());
  }
}

void _owned() {
  final Owned user = _decode(Owned.decode, _user);
  _expect(user.owner?.name, 'Zed');
  final Owned bot = _decode(Owned.decode, _bot);
  _expect(bot.owner, null);
  _roundTrips(Owned.decode, user, user.toJson());
  _roundTrips(Owned.decode, bot, bot.toJson());
}

void _reselect() {
  final Reselect user = _decode(Reselect.decode, _user);
  _expect(user is ReselectUser && user.friends.single.name == 'Bob', true);
  final Reselect bot = _decode(Reselect.decode, _bot);
  _expect(bot is ReselectUnknown && bot.typename == 'Bot', true);
  _roundTrips(Reselect.decode, user, user.toJson());
  _roundTrips(Reselect.decode, bot, bot.toJson());
}

void _missingTypename() {
  final JsonObject json = _json('{"id": "1"}');
  if (NodeCard.decode(json) is! DecodeFailure) {
    _fail('a missing __typename was accepted');
  }
}

T _decode<T>(
  DecodeResult<T> Function(JsonObject json) decode,
  JsonObject json,
) {
  final DecodeResult<T> result = decode(json);
  if (result is! DecodeSuccess<T>) {
    _fail('decode failed: $result');
  }
  return (result as DecodeSuccess<T>).value;
}

void _roundTrips<T extends Object>(
  DecodeResult<T> Function(JsonObject json) decode,
  T value,
  JsonObject json,
) {
  final T again = _decode(decode, json);
  if (again != value || again.hashCode != value.hashCode) {
    _fail('decode(toJson()) is $again, not $value');
  }
}

void _expect(Object? actual, Object? expected) {
  if (actual != expected) {
    _fail('expected $expected, got $actual');
  }
}

void _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
```

In `packages/typed_graphql_codegen/test/support/class_emission.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
 import 'package:typed_graphql_codegen/src/emit/data_class_emitter.dart';
 import 'package:typed_graphql_codegen/src/emit/fragment_holder_emitter.dart';
 import 'package:typed_graphql_codegen/src/emit/imports.dart';
+import 'package:typed_graphql_codegen/src/emit/polymorphic_base_emitter.dart';
 import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
 import 'package:typed_graphql_codegen/src/plan/planned_class.dart';
 import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';
@@ -57,8 +58,11 @@ final class ClassEmission(
         DataClassEmitter(mapper).emit(data, doc, writer, imports);
       case final FragmentHolderPlan holder:
         const FragmentHolderEmitter().emit(holder, writer);
-      case PolymorphicBasePlan():
-        throw StateError('not emitted by these tests');
+      case final PolymorphicBasePlan base:
+        final doc = ClassDocumentation(
+          plan,
+        ).ofBase(base, fragmentName: fragmentName);
+        PolymorphicBaseEmitter(mapper).emit(base, doc, writer, imports);
     }
     return writer.text;
   }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/polymorphic_base_emitter_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -18,29 +18,65 @@ final class ClassDocumentation {
   /// The doc of [plan].
   ///
   /// [fragmentName] is the GraphQL name of the fragment a
-  /// [DataClassRole.fragment] class is the shape of. A role this stage does
-  /// not generate, or a nested class whose owner is not in [classes], is a
-  /// [StateError].
-  String of(DataClassPlan plan, {String? fragmentName}) => switch (plan.role) {
-    DataClassRole.fragment =>
-      'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`.',
-    DataClassRole.nested => _nested(plan),
-    _ => throw StateError('${plan.name} is a ${plan.role.name} class.'),
-  };
+  /// [DataClassRole.fragment] class is the shape of. An operation's data
+  /// class is not documented here, and a nested class whose owner is not in
+  /// [classes] is a [StateError].
+  String of(DataClassPlan plan, {String? fragmentName}) =>
+      _wrapped(_sentence(plan, fragmentName));
+
+  String _sentence(DataClassPlan plan, String? fragmentName) =>
+      switch (plan.role) {
+        DataClassRole.fragment =>
+          'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`.',
+        DataClassRole.nested => '${_field(plan.ownerName, plan.ownerMember)}.',
+        DataClassRole.variant =>
+          '[${plan.baseName}] when its type is `${plan.variantTypeName}`.',
+        DataClassRole.unknownVariant =>
+          '[${plan.baseName}] when its type is none of those the selection '
+              'tells apart.',
+        DataClassRole.operationData => throw StateError(
+          '${plan.name} is a ${plan.role.name} class.',
+        ),
+      };
+
+  /// The doc of the sealed base [plan]; see [of] for [fragmentName].
+  String ofBase(PolymorphicBasePlan plan, {String? fragmentName}) {
+    final String subject = plan.role == DataClassRole.fragment
+        ? 'The fragment `${fragmentName ?? plan.name}` on `${plan.typeName}`'
+        : _field(plan.ownerName, plan.ownerMember);
+    return _wrapped(
+      '$subject: a class per type the selection tells apart, and '
+      '[${plan.unknownName}] for any other type.',
+    );
+  }
+
+  // A comment line is `/// ` and up to 76 characters.
+  String _wrapped(String text) {
+    final lines = <String>[];
+    var current = '';
+    for (final String word in text.split(' ')) {
+      if (current.isNotEmpty && current.length + 1 + word.length > 76) {
+        lines.add(current);
+        current = word;
+      } else {
+        current = current.isEmpty ? word : '$current $word';
+      }
+    }
+    return [...lines, current].join('\n');
+  }
 
-  String _nested(DataClassPlan plan) {
-    final String? ownerName = plan.ownerName;
-    final String? member = plan.ownerMember;
+  // The sentence without its end: it names the field of the owner.
+  String _field(String? ownerName, String? member) {
     final PlannedField? field = ownerName == null || member == null
         ? null
         : _fieldOf(ownerName, member);
     if (field == null) {
-      throw StateError('The owner field of ${plan.name} is not planned.');
+      throw StateError('The owner field $member of $ownerName is not planned.');
     }
     final String subject = '`${field.responseName}` of [$ownerName]';
     return _isList(field.type)
-        ? 'The items of the field $subject.'
-        : 'The field $subject.';
+        ? 'The items of the field $subject'
+        : 'The field $subject';
   }
 
   PlannedField? _fieldOf(String ownerName, String member) {
```

In `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,7 +1,12 @@
+import 'package:typed_graphql/typed_graphql.dart';
+
 import '../plan/data_class_role.dart';
 import '../plan/planned_class.dart';
+import '../plan/planned_field.dart';
+import 'dart_string_literal.dart';
 import 'dart_writer.dart';
 import 'data_class_field.dart';
+import 'fragment_decode_writer.dart';
 import 'imports.dart';
 import 'reader_factory_writer.dart';
 import 'to_json_writer.dart';
@@ -22,31 +27,43 @@ final class DataClassEmitter {
 
   /// Writes [plan] with the class doc comment [doc].
   ///
-  /// Only the roles [DataClassRole.fragment] and [DataClassRole.nested] are
-  /// written here; any other is a [StateError].
+  /// A variant implements its sealed base, which reads it and declares its
+  /// shared members; [DataClassRole.operationData] is not written here and
+  /// is a [StateError].
   void emit(
     DataClassPlan plan,
     String doc,
     DartWriter writer,
     Imports imports,
   ) {
-    if (plan.role != DataClassRole.fragment &&
-        plan.role != DataClassRole.nested) {
+    if (plan.role == DataClassRole.operationData) {
       throw StateError('${plan.name} is a ${plan.role.name} class.');
     }
     final fields = [
+      // The unknown variant holds the type name it was read with.
+      if (plan.role == DataClassRole.unknownVariant)
+        DataClassField.of(_typenameField, mapper, imports),
       for (final field in plan.fields)
         DataClassField.of(field, mapper, imports),
     ];
     final String noun = plan.role == DataClassRole.fragment
         ? 'fragment'
         : 'value';
+    final String implemented = plan.baseName ?? 'client.DataObject';
     writer.doc(doc);
-    writer.block('final class ${plan.name} implements client.DataObject', () {
+    writer.block('final class ${plan.name} implements $implemented', () {
       _members(writer, plan, fields, noun);
     });
   }
 
+  static const PlannedField _typenameField = PlannedField(
+    responseName: '__typename',
+    memberName: 'typename',
+    type: NonNullType(NamedType(Name('String'))),
+    isConditional: false,
+    overridesBase: true,
+  );
+
   void _members(
     DartWriter writer,
     DataClassPlan plan,
@@ -57,12 +74,15 @@ final class DataClassEmitter {
     _constructor(writer, plan, fields, noun);
     writer.line();
     _reader(writer, plan, fields);
-    writer.line();
-    writer.doc('Reads and writes the $noun.');
-    writer.assign(
-      'static const client.DataCodec<$name> codec',
-      'client.ObjectDataCodec($name._read)',
-    );
+    // The sealed base reads a variant.
+    if (plan.baseName == null) {
+      writer.line();
+      writer.doc('Reads and writes the $noun.');
+      writer.assign(
+        'static const client.DataCodec<$name> codec',
+        'client.ObjectDataCodec($name._read)',
+      );
+    }
     for (final field in fields) {
       writer.line();
       writer.assign(
@@ -70,10 +90,11 @@ final class DataClassEmitter {
         field.type.codec,
       );
     }
+    _typename(writer, plan);
     _fields(writer, plan, fields);
     if (plan.role == DataClassRole.fragment) {
       writer.line();
-      _decode(writer, name);
+      const FragmentDecodeWriter().write(writer, name);
     }
     writer.line();
     _toJson(writer, plan, fields);
@@ -128,29 +149,41 @@ final class DataClassEmitter {
   ) {
     for (final field in fields) {
       writer.line();
-      writer.doc(field.doc);
+      _documentation(writer, field.doc, isOverride: field.overridesBase);
       writer.line('final ${field.type.type} ${field.member};');
     }
     if (plan.holderName case final holder?) {
       writer.line();
-      writer.doc('The fragments spread on this value.');
+      _documentation(
+        writer,
+        'The fragments spread on this value.',
+        isOverride: plan.holderOverridesBase,
+      );
       writer.line('final $holder fragments;');
     }
   }
 
-  void _decode(DartWriter writer, String name) {
-    writer
-      ..doc(
-        'Reads [json], an object the fragment was spread on, in the response\n'
-        'to an operation sent with [variables].',
-      )
-      ..line('static graphql.DecodeResult<$name> decode(')
-      ..indented(() {
-        writer
-          ..line('graphql.JsonObject json, {')
-          ..line('graphql.JsonObject? variables,');
-      })
-      ..line('}) => codec.decode(json, client.DataContext(variables));');
+  // An overriding member inherits the doc comment of the base's declaration.
+  void _documentation(
+    DartWriter writer,
+    String doc, {
+    required bool isOverride,
+  }) {
+    if (isOverride) {
+      writer.line('@override');
+    } else {
+      writer.doc(doc);
+    }
+  }
+
+  void _typename(DartWriter writer, DataClassPlan plan) {
+    if (plan.variantTypeName case final typeName?) {
+      writer.line();
+      writer.line('@override');
+      writer.line(
+        'String get typename => ${const DartStringLiteral().of(typeName)};',
+      );
+    }
   }
 
   void _toJson(
@@ -160,6 +193,9 @@ final class DataClassEmitter {
   ) {
     const ToJsonWriter().write(writer, [
       if (plan.holderName != null) '...fragments.toJson().fields',
+      if (plan.variantTypeName case final typeName?)
+        "'__typename': const graphql.JsonString("
+            '${const DartStringLiteral().of(typeName)})',
       for (final field in fields)
         '${field.keyLiteral}: ${field.codecName}.write(${field.member})',
     ]);
```

In `packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -47,6 +47,10 @@ final class DataClassField {
   /// Whether the field may be absent because of a variable condition.
   bool get isConditional => _field.isConditional;
 
+  /// Whether the field is declared by the sealed base, which this class
+  /// overrides.
+  bool get overridesBase => _field.overridesBase;
+
   /// Whether the Dart type is nullable.
   bool get isNullable => type.type.endsWith('?');
 
```

In `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,6 +9,7 @@ import 'fragment_holder_emitter.dart';
 import 'generated_header.dart';
 import 'imports.dart';
 import 'library_imports.dart';
+import 'polymorphic_base_emitter.dart';
 import 'type_mapper.dart';
 
 /// Writes the library of one document file: the classes of its fragments
@@ -74,8 +75,11 @@ final class DocumentLibraryEmitter {
         DataClassEmitter(mapper).emit(plan, doc, body, imports);
       case final FragmentHolderPlan plan:
         const FragmentHolderEmitter().emit(plan, body);
-      case PolymorphicBasePlan():
-        throw StateError('${planned.name} needs the polymorphic emitter.');
+      case final PolymorphicBasePlan plan:
+        final doc = ClassDocumentation(
+          classes,
+        ).ofBase(plan, fragmentName: fragmentName);
+        PolymorphicBaseEmitter(mapper).emit(plan, doc, body, imports);
     }
   }
 }
```

Create `packages/typed_graphql_codegen/lib/src/emit/fragment_decode_writer.dart`:

```dart
import 'dart_writer.dart';

/// Writes the static `decode` of a fragment class, the entry point for a
/// fragment read outside an operation.
///
/// {@category codegen}
final class FragmentDecodeWriter {
  /// Creates the writer.
  const FragmentDecodeWriter();

  /// Writes `decode` for the class [className].
  void write(DartWriter writer, String className) {
    writer
      ..doc(
        'Reads [json], an object the fragment was spread on, in the response\n'
        'to an operation sent with [variables].',
      )
      ..line('static graphql.DecodeResult<$className> decode(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json, {')
          ..line('graphql.JsonObject? variables,');
      })
      ..line('}) => codec.decode(json, client.DataContext(variables));');
  }
}
```

In `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -60,14 +60,16 @@ final class LibraryImports {
   }
 
   bool _usesSchemaTypes(List<PlannedClass> classes) => classes.any(
-    (planned) =>
-        planned is DataClassPlan &&
-        planned.fields.any(
-          (field) => switch (schema.namedTypeOf(field.type)) {
-            EnumType() || InputObjectType() => true,
-            _ => false,
-          },
-        ),
+    (planned) => switch (planned) {
+      DataClassPlan(:final fields) ||
+      PolymorphicBasePlan(sharedFields: final fields) => fields.any(
+        (field) => switch (schema.namedTypeOf(field.type)) {
+          EnumType() || InputObjectType() => true,
+          _ => false,
+        },
+      ),
+      FragmentHolderPlan() => false,
+    },
   );
 
   Iterable<String> _spreadFragments(List<PlannedClass> classes) => [
```

Create `packages/typed_graphql_codegen/lib/src/emit/polymorphic_base_emitter.dart`:

```dart
import '../plan/data_class_role.dart';
import '../plan/planned_class.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'data_class_field.dart';
import 'fragment_decode_writer.dart';
import 'imports.dart';
import 'type_mapper.dart';

/// Writes the sealed base of a selection on an abstract type (spec §7 "Data
/// classes", R7.5): it reads the `__typename` and hands the JSON to the
/// class of that type.
///
/// {@category codegen}
final class PolymorphicBaseEmitter {
  /// Creates the emitter; [mapper] maps the shared field types.
  const PolymorphicBaseEmitter(this.mapper);

  static const String _switchHead =
      "switch (_typenameCodec.field(json, '__typename', context)) {";

  /// The mapper of field types.
  final TypeMapper mapper;

  /// Writes [plan] with the class doc comment [doc].
  void emit(
    PolymorphicBasePlan plan,
    String doc,
    DartWriter writer,
    Imports imports,
  ) {
    final fields = [
      for (final field in plan.sharedFields)
        DataClassField.of(field, mapper, imports),
    ];
    writer.doc(doc);
    writer.block('sealed class ${plan.name} implements client.DataObject', () {
      _reader(writer, plan);
      writer.line();
      _codecs(writer, plan);
      writer.line();
      writer.doc("The name of the value's type, `__typename`.");
      writer.line('String get typename;');
      for (final field in fields) {
        writer.line();
        writer.doc(field.doc);
        writer.line('${field.type.type} get ${field.member};');
      }
      if (plan.holderName case final holder?) {
        writer.line();
        writer.doc('The fragments spread on this value.');
        writer.line('$holder get fragments;');
      }
    });
  }

  void _reader(DartWriter writer, PolymorphicBasePlan plan) {
    final String name = plan.name;
    final List<String> parameters = [
      'graphql.JsonObject json',
      'client.DataContext context',
    ];
    final String head = 'factory $name._read(${parameters.join(', ')})';
    if (writer.fits('$head => $_switchHead')) {
      writer.line('$head => $_switchHead');
    } else {
      writer.line('factory $name._read(');
      writer.indented(() {
        for (final String parameter in parameters) {
          writer.line('$parameter,');
        }
      });
      writer.line(') => $_switchHead');
    }
    writer.indented(() {
      for (final variant in plan.variants) {
        _case(
          writer,
          const DartStringLiteral().of(variant.typeName),
          variant.className,
        );
      }
      _case(writer, '_', plan.unknownName);
    });
    writer.line('};');
  }

  void _case(DartWriter writer, String pattern, String className) {
    final String call = '$className._read(json, context),';
    if (writer.fits('$pattern => $call')) {
      writer.line('$pattern => $call');
      return;
    }
    writer.line('$pattern =>');
    writer.indented(() => writer.indented(() => writer.line(call)));
  }

  void _codecs(DartWriter writer, PolymorphicBasePlan plan) {
    final String noun = plan.role == DataClassRole.fragment
        ? 'fragment'
        : 'value';
    writer.doc('Reads and writes the $noun.');
    writer.assign(
      'static const client.DataCodec<${plan.name}> codec',
      'client.ObjectDataCodec(${plan.name}._read)',
    );
    writer.line();
    writer.assign(
      'static const client.DataCodec<String> _typenameCodec',
      'client.ScalarDataCodec(graphql.StringCodec())',
    );
    if (plan.role == DataClassRole.fragment) {
      writer.line();
      const FragmentDecodeWriter().write(writer, plan.name);
    }
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/polymorphic_base_emitter_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- A selection on an interface or union that tells types apart (`... on User`)
  generates a sealed class that reads `__typename`, a final class per type
  and an unknown class for any other type; fields every class selects the same
  way are declared by the sealed class.
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -248,6 +248,16 @@ fragment on its own, and `toJson` writes it back; `==` compares lists by
 content. The golden `test/goldens/fragments` is analyzed and run like the
 other goldens.
 
+A selection on an interface or a union that spreads inline fragments or
+fragments on other types generates a sealed class. `NodeCard` on `Node`
+with `... on User` and `... on Bot` is a sealed `NodeCard` that reads the
+`__typename`, `NodeCardUser` and `NodeCardBot`, and `NodeCardUnknown` for any
+other type, which a server may add later. A `switch` over the sealed class is
+exhaustive. The sealed class declares `typename` and every field that all
+classes select in the same way, and `fragments` when they all spread the same
+fragments; `NodeCardUnknown` keeps the `typename` it was read with. The golden
+`test/goldens/polymorphic` is analyzed and run like the other goldens.
+
 ## Schema types
 
 The file at `schema_types` holds what the documents reach: the enums and
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart packages/typed_graphql_codegen/lib/src/emit/data_class_field.dart packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart packages/typed_graphql_codegen/lib/src/emit/fragment_decode_writer.dart packages/typed_graphql_codegen/lib/src/emit/library_imports.dart packages/typed_graphql_codegen/lib/src/emit/polymorphic_base_emitter.dart packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_node.graphql packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_query.graphql packages/typed_graphql_codegen/test/goldens/polymorphic/input/lib/user_result.graphql packages/typed_graphql_codegen/test/goldens/polymorphic/input/schema.graphql packages/typed_graphql_codegen/test/goldens/polymorphic/input/typed_graphql.yaml packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_node.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_result.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/support/bin/round_trip.dart.txt packages/typed_graphql_codegen/test/support/class_emission.dart
git commit -q -m "feat(typed_graphql_codegen): generate sealed classes for abstract selections" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Generate operation classes, variables and documents

Each document library now holds its operations and fragments in document order: the operation class (`OperationEmitter`) with its `OperationDocument` (the minified text with `__typename` added by `TypenameAdder` and every fragment it uses, and its SHA-256; `OperationText`), the variables class (`VariablesEmitter`, member writers shared with input objects through `InputFieldMembers`), and the data class with `decode` and the operation's Boolean variable defaults (`FlagDefaults`, read by `DataContext.flag`). Adds the `crypto` dependency and the `operations` golden case.

Commit on the branch: `decf106`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/emit/input_field_members.dart`, `packages/typed_graphql_codegen/lib/src/emit/operation_decode_writer.dart`, `packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/variables_emitter.dart`, `packages/typed_graphql_codegen/lib/src/plan/flag_defaults.dart`, `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart`, `packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart`, `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/input_field.dart`, `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart`, `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart`, `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`, `packages/typed_graphql_codegen/lib/src/plan/class_names.dart`, `packages/typed_graphql_codegen/pubspec.yaml`
- Test: `packages/typed_graphql_codegen/test/emit/operation_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/variables_emitter_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/input/lib/user.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/input/lib/user_mutations.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/input/lib/user_subscriptions.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/operations/input/typed_graphql.yaml`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_mutations.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_subscriptions.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/support/bin/round_trip.dart.txt`, `packages/typed_graphql_codegen/test/goldens/operations/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt`, `packages/typed_graphql_codegen/test/goldens/operations/support/packages/scalar_codecs/pubspec.yaml.txt`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden`, `packages/typed_graphql_codegen/test/plan/operation_text_test.dart`, `packages/typed_graphql_codegen/test/support/operation_fixture.dart`

**Interfaces:**
- Consumes: Tasks 1-5; M10b `InputField`, `RegularInputEmitter`; the client `GraphQLOperation`, `DataContext`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/class_documentation.dart
  String ofOperation(OperationDefinition operation)

// emit/document_library_emitter.dart
  String emit(String documentPath, List<ExecutableDefinition> definitions)

// emit/input_field.dart
  factory InputField.variable(

// emit/input_field_members.dart
final class InputFieldMembers
  const InputFieldMembers()
  void constructor(
  void codecs(List<InputField> fields, DartWriter writer)
  void declarations(List<InputField> fields, DartWriter writer)
  void valueMembers(String name, List<InputField> fields, DartWriter writer)
  void toJson(List<InputField> fields, DartWriter writer)
  void equality(String name, List<InputField> fields, DartWriter writer)
  void toStringMember(String name, List<InputField> fields, DartWriter writer)

// emit/operation_decode_writer.dart
final class OperationDecodeWriter
  const OperationDecodeWriter()
  void write(

// emit/operation_emitter.dart
final class OperationEmitter
  const OperationEmitter(this.text)
  final OperationText text
  void emit(OperationDefinition operation, String dataName, DartWriter writer)

// emit/variables_emitter.dart
final class VariablesEmitter
  const VariablesEmitter(this.mapper)
  final TypeMapper mapper
  void emit(OperationDefinition operation, DartWriter writer, Imports imports)

// plan/class_names.dart
  String operation(String operationName, OperationType type)
  String variables(String operationName)

// plan/flag_defaults.dart
final class FlagDefaults
  const FlagDefaults()
  Map<String, bool> of(OperationDefinition operation)

// plan/operation_text.dart
final class OperationText
  const OperationText(this.schema, this.fragments)
  final Schema schema
  final Map<String, FragmentDefinition> fragments
  String of(OperationDefinition operation)
final class _SpreadCollector extends AstVisitor
  VisitAction enter(Node node)

// plan/typename_adder.dart
final class TypenameAdder extends AstTransformer
  const TypenameAdder()
  Node? rewrite(Node node)
  SelectionSet appendTo(SelectionSet selectionSet)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_codegen/test/emit/operation_emitter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/operation_emitter.dart';
import 'package:typed_graphql_codegen/src/plan/operation_text.dart';

import '../support/operation_fixture.dart';
import '../support/plan_fixture.dart';

void main() {
  String emit(String operationName) {
    final fixture = PlanFixture(operationSchema, operationDocument);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .firstWhere((operation) => operation.name?.value == operationName);
    final writer = DartWriter();
    OperationEmitter(
      OperationText(fixture.schema, fixture.fragments),
    ).emit(operation, '${operationName}Data', writer);
    return writer.text;
  }

  test('a query with variables', () {
    expect(emit('GetUser'), r'''
/// The query `GetUser`.
final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
  /// Creates the query with its [variables].
  const GetUserQuery(this.variables);

  /// The document of `GetUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'GetUser',
        type: graphql.OperationType.query,
        text: r'query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){user(id:$id){...UserCard@include(if:$full)role createdAt cursor friends(first:2)@include(if:$withFriends){id name __typename}__typename}}fragment UserCard on User{id name}',
        sha256:
          '198ab8e735cf86b04b66c1094135e3e63cfae5a89e4b793ae58982ff95891f8e',
      );

  /// The variables the query is sent with.
  final GetUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
      GetUserData.decode(data, variables: variablesJson);
}
''');
  });

  test('a query whose document has a fragment and type tests', () {
    expect(emit('FindNode'), r'''
/// The query `FindNode`.
final class FindNodeQuery extends client.GraphQLQuery<FindNodeData> {
  /// Creates the query with its [variables].
  const FindNodeQuery(this.variables);

  /// The document of `FindNode` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'FindNode',
        type: graphql.OperationType.query,
        text: r'query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}...on Bot{model}__typename}}fragment UserCard on User{id name}',
        sha256:
          '7a6b96aae12daef4bcd220864fe9f9d5e3f606c6cde72b347b4c985a3939b1e0',
      );

  /// The variables the query is sent with.
  final FindNodeVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<FindNodeData> decodeData(graphql.JsonObject data) =>
      FindNodeData.decode(data, variables: variablesJson);
}
''');
  });

  test('a query without variables', () {
    expect(emit('Everyone'), '''
/// The query `Everyone`.
final class EveryoneQuery extends client.GraphQLQuery<EveryoneData> {
  /// Creates the query.
  const EveryoneQuery();

  /// The document of `Everyone` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'Everyone',
        type: graphql.OperationType.query,
        text: 'query Everyone{node(id:"1"){id __typename}}',
        sha256:
          '5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61',
      );

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => graphql.JsonObject(const {});

  @override
  graphql.DecodeResult<EveryoneData> decodeData(graphql.JsonObject data) =>
      EveryoneData.decode(data);
}
''');
  });

  test('a mutation', () {
    expect(emit('RenameUser'), r'''
/// The mutation `RenameUser`.
final class RenameUserMutation extends client.GraphQLMutation<RenameUserData> {
  /// Creates the mutation with its [variables].
  const RenameUserMutation(this.variables);

  /// The document of `RenameUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'RenameUser',
        type: graphql.OperationType.mutation,
        text: r'mutation RenameUser($id:ID!$name:String!){renameUser(id:$id name:$name){...UserCard __typename}}fragment UserCard on User{id name}',
        sha256:
          '99b64c8c80d6d3ed8be8cababb9cdafc092f7b125db944902fe6d172681f3020',
      );

  /// The variables the mutation is sent with.
  final RenameUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<RenameUserData> decodeData(graphql.JsonObject data) =>
      RenameUserData.decode(data, variables: variablesJson);
}
''');
  });

  test('a subscription with a header that wraps', () {
    expect(emit('UserChanged'), r'''
/// The subscription `UserChanged`.
final class UserChangedSubscription
    extends client.GraphQLSubscription<UserChangedData> {
  /// Creates the subscription with its [variables].
  const UserChangedSubscription(this.variables);

  /// The document of `UserChanged` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'UserChanged',
        type: graphql.OperationType.subscription,
        text: r'subscription UserChanged($id:ID!){userChanged(id:$id){id name __typename}}',
        sha256:
          '7a4a1e850c31f8be22e726ba1e15417b48ca868176bc43c36a64fa305be990b2',
      );

  /// The variables the subscription is sent with.
  final UserChangedVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<UserChangedData> decodeData(graphql.JsonObject data) =>
      UserChangedData.decode(data, variables: variablesJson);
}
''');
  });

  test('the document carries the SHA-256 of its text', () {
    // printf '%s' 'query Everyone{node(id:"1"){id __typename}}' | sha256sum
    expect(
      emit('Everyone'),
      contains(
        "'5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61'",
      ),
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/emit/variables_emitter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/emit/variables_emitter.dart';

import '../support/operation_fixture.dart';
import '../support/plan_fixture.dart';

void main() {
  String emit(String operationName) {
    final fixture = PlanFixture(operationSchema, operationDocument);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .firstWhere((operation) => operation.name?.value == operationName);
    final writer = DartWriter();
    VariablesEmitter(
      TypeMapper(fixture.schema, const {}),
    ).emit(operation, writer, Imports());
    return writer.text;
  }

  test('required, defaulted and required variables', () {
    expect(emit('GetUser'), r'''
/// The variables of the query `GetUser`.
final class GetUserVariables implements client.DataObject {
  /// Creates the variables.
  const GetUserVariables({
    required this.id,
    required this.full,
    this.withFriends = const graphql.Optional.absent(),
  });

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<bool?> _withFriendsCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.BooleanCodec()));

  static const client.DataCodec<bool> _fullCodec =
      client.ScalarDataCodec(graphql.BooleanCodec());

  /// The variable `$id`.
  final String id;

  /// The variable `$withFriends`; its default is `false`.
  final graphql.Optional<bool?> withFriends;

  /// The variable `$full`.
  final bool full;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    if (withFriends case graphql.Present(:final value))
      'withFriends': _withFriendsCodec.write(value),
    'full': _fullCodec.write(full),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserVariables &&
      other.id == id &&
      other.withFriends == withFriends &&
      other.full == full;

  @override
  int get hashCode => Object.hashAll([
    id.hashCode,
    withFriends.hashCode,
    full.hashCode,
  ]);

  @override
  String toString() =>
      'GetUserVariables(id: $id, withFriends: $withFriends, full: $full)';
}
''');
  });

  test('a single required variable', () {
    expect(emit('FindNode'), r'''
/// The variables of the query `FindNode`.
final class FindNodeVariables implements client.DataObject {
  /// Creates the variables.
  const FindNodeVariables({required this.id});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The variable `$id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is FindNodeVariables &&
      other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FindNodeVariables(id: $id)';
}
''');
  });

  test('an optional list variable compares by item', () {
    expect(
      emit('SearchAll'),
      allOf(
        contains('  final graphql.Optional<List<String>?> tags;\n'),
        contains(
          '      const client.DataEquality().equals(other.tags, tags);\n',
        ),
      ),
    );
  });
}
```

In `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -216,6 +216,36 @@ type Query {
         contains('final class B implements client.DataObject'),
       ),
     );
-    expect(byPath['lib/a.graphql.dart'], isNot(contains('final class')));
+    expect(
+      byPath['lib/a.graphql.dart'],
+      allOf(
+        contains('final class AQuery extends client.GraphQLQuery<AData>'),
+        isNot(contains('final class B ')),
+      ),
+    );
+  });
+
+  test('an operation is generated in the library of its file', () {
+    final result = generator.generate(
+      schema: _schema,
+      documents: const [
+        ProjectFile(
+          'lib/a.graphql',
+          r'query A($f: Boolean = false) { role @include(if: $f) }',
+        ),
+      ],
+    );
+    final text = {
+      for (final file in result.files) file.path: file.text,
+    }['lib/a.graphql.dart'];
+    expect(
+      text,
+      allOf(
+        contains('final class AQuery extends client.GraphQLQuery<AData>'),
+        contains('final class AVariables implements client.DataObject'),
+        contains('final class AData implements client.DataObject'),
+        contains("import 'schema.graphql.dart';"),
+      ),
+    );
   });
 }
```

In `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,169 @@
 // GENERATED CODE - DO NOT MODIFY BY HAND.
 // Generated by typed_graphql_codegen from lib/user_card_query.graphql.
 // dart format off
+
+import 'package:typed_graphql/typed_graphql.dart' as graphql;
+import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
+
+import 'user_card.graphql.dart';
+
+/// The query `CardQuery`.
+final class CardQueryQuery extends client.GraphQLQuery<CardQueryData> {
+  /// Creates the query with its [variables].
+  const CardQueryQuery(this.variables);
+
+  /// The document of `CardQuery` as it is sent.
+  static const client.OperationDocument operationDocument =
+      client.OperationDocument(
+        name: 'CardQuery',
+        type: graphql.OperationType.query,
+        text: r'query CardQuery($full:Boolean!){user(id:"1"){...UserCard __typename}}fragment UserCard on User{__typename _id:id default:name role createdAt cursor friends(first:2){id ...UserName __typename}...UserName@include(if:$full)}fragment UserName on User{name}',
+        sha256:
+          '22f227554fa01ad95bff220bbfd9effe3053fd24a1d2fff11e364f9bd5dc4079',
+      );
+
+  /// The variables the query is sent with.
+  final CardQueryVariables variables;
+
+  @override
+  client.OperationDocument get document => operationDocument;
+
+  @override
+  graphql.JsonObject get variablesJson => variables.toJson();
+
+  @override
+  graphql.DecodeResult<CardQueryData> decodeData(graphql.JsonObject data) =>
+      CardQueryData.decode(data, variables: variablesJson);
+}
+
+/// The variables of the query `CardQuery`.
+final class CardQueryVariables implements client.DataObject {
+  /// Creates the variables.
+  const CardQueryVariables({required this.full});
+
+  static const client.DataCodec<bool> _fullCodec =
+      client.ScalarDataCodec(graphql.BooleanCodec());
+
+  /// The variable `$full`.
+  final bool full;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'full': _fullCodec.write(full),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is CardQueryVariables &&
+      other.full == full;
+
+  @override
+  int get hashCode => full.hashCode;
+
+  @override
+  String toString() => 'CardQueryVariables(full: $full)';
+}
+
+/// The data of the query `CardQuery`.
+final class CardQueryData implements client.DataObject {
+  /// Creates the data.
+  const CardQueryData({this.user});
+
+  factory CardQueryData._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => CardQueryData(user: _userCodec.field(json, 'user', context));
+
+  /// Reads and writes the data.
+  static const client.DataCodec<CardQueryData> codec =
+      client.ObjectDataCodec(CardQueryData._read);
+
+  static const client.DataCodec<CardQueryDataUser?> _userCodec =
+      client.NullableDataCodec(CardQueryDataUser.codec);
+
+  /// The field `user`.
+  final CardQueryDataUser? user;
+
+  /// Reads [json], the `data` of a response to the query sent with
+  /// [variables].
+  static graphql.DecodeResult<CardQueryData> decode(
+    graphql.JsonObject json, {
+    graphql.JsonObject? variables,
+  }) => codec.decode(json, client.DataContext(variables));
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({'user': _userCodec.write(user)});
+
+  @override
+  bool operator ==(Object other) =>
+      other is CardQueryData && other.user == user;
+
+  @override
+  int get hashCode => user.hashCode;
+
+  @override
+  String toString() => 'CardQueryData(user: $user)';
+}
+
+/// The field `user` of [CardQueryData].
+final class CardQueryDataUser implements client.DataObject {
+  /// Creates the value.
+  const CardQueryDataUser({required this.fragments});
+
+  factory CardQueryDataUser._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => CardQueryDataUser(
+    fragments: CardQueryDataUserFragments._read(json, context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<CardQueryDataUser> codec =
+      client.ObjectDataCodec(CardQueryDataUser._read);
+
+  /// The fragments spread on this value.
+  final CardQueryDataUserFragments fragments;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...fragments.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is CardQueryDataUser && other.fragments == fragments;
+
+  @override
+  int get hashCode => fragments.hashCode;
+
+  @override
+  String toString() => 'CardQueryDataUser(fragments: $fragments)';
+}
+
+/// The fragments spread on [CardQueryDataUser].
+final class CardQueryDataUserFragments implements client.DataObject {
+  /// Creates the fragments.
+  const CardQueryDataUserFragments({required this.userCard});
+
+  factory CardQueryDataUserFragments._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => CardQueryDataUserFragments(userCard: UserCard.codec.read(json, context));
+
+  /// The fragment `UserCard`.
+  final UserCard userCard;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...userCard.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is CardQueryDataUserFragments && other.userCard == userCard;
+
+  @override
+  int get hashCode => userCard.hashCode;
+
+  @override
+  String toString() => 'CardQueryDataUserFragments(userCard: $userCard)';
+}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/input/lib/user.graphql`:

```graphql
query GetUser($id: ID!, $withFriends: Boolean = false, $full: Boolean!) {
  user(id: $id) {
    ...UserCard @include(if: $full)
    role
    createdAt
    cursor
    friends(first: 2) @include(if: $withFriends) {
      id
      name
    }
  }
}

fragment UserCard on User {
  id
  name
}

query FindNode($id: ID!) {
  node(id: $id) {
    id
    ... on User {
      name
      ...UserCard
    }
    ... on Bot {
      model
    }
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/input/lib/user_mutations.graphql`:

```graphql
mutation SearchAll(
  $by: SearchBy!
  $filter: UserFilter
  $tags: [String!]
) {
  search(by: $by, filter: $filter, tags: $tags) {
    ... on User {
      id
      name
    }
    ... on Bot {
      id
      model
    }
  }
}

mutation RenameUser($id: ID!, $name: String!) {
  renameUser(id: $id, name: $name) {
    ...UserCard
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/input/lib/user_subscriptions.graphql`:

```graphql
subscription UserChanged($id: ID!) {
  userChanged(id: $id) {
    id
    name
  }
}

query Everyone {
  node(id: "1") {
    id
  }
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql`:

```graphql
"A user role."
enum Role {
  ADMIN
  EDITOR
  VIEWER @deprecated(reason: "Use EDITOR.")
}

enum Unused {
  A
}

scalar DateTime

scalar Cursor

input UserFilter {
  role: Role
  name: String = "x"
  ids: [ID!]!
  nested: UserFilter
  since: DateTime
  matrix: [[Int]]
}

input SearchBy @oneOf {
  name: String
  id: ID
  ids: [ID!]
}

"Names that Dart reserves or that the generated class already has."
input Paging {
  default: Int
  other: String!
  after: Cursor
  client: Int
}

input Unreached {
  value: Int
}

interface Node {
  id: ID!
}

type User implements Node {
  id: ID!
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}

type Bot implements Node {
  id: ID!
  model: String
}

union SearchResult = User | Bot

type Query {
  user(id: ID!): User
  node(id: ID!): Node
  search(by: SearchBy!, filter: UserFilter, paging: Paging): [SearchResult!]!
}

type Mutation {
  renameUser(id: ID!, name: String!): User
  search(by: SearchBy!, filter: UserFilter, tags: [String!]): [SearchResult!]!
}

type Subscription {
  userChanged(id: ID!): User
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/input/typed_graphql.yaml`:

```yaml
schema: schema.graphql
scalars:
  DateTime:
    type: DateTime
    codec: package:scalar_codecs/scalar_codecs.dart#DateTimeCodec
```

Create `packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off

import 'package:scalar_codecs/scalar_codecs.dart' as scalar_0;
import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// A user role.
sealed class Role implements client.DataEnum {
  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
  /// this code does not know.
  factory Role.parse(String raw) {
    for (final value in RoleKnown.values) {
      if (value.raw == raw) return value;
    }
    return RoleUnknown(raw);
  }

  /// Reads and writes the values of `Role`.
  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
}

/// The values of [Role] this code knows.
enum RoleKnown implements Role {
  /// `ADMIN`.
  admin('ADMIN'),

  /// `EDITOR`.
  editor('EDITOR'),

  /// `VIEWER`.
  @Deprecated('Use EDITOR.')
  viewer('VIEWER');

  const RoleKnown(this.raw);

  @override
  final String raw;
}

/// A value of [Role] this code does not know, such as one added to the
/// schema after the code was generated.
final class RoleUnknown implements Role {
  /// Creates the value named [raw].
  const RoleUnknown(this.raw);

  @override
  final String raw;

  @override
  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'RoleUnknown($raw)';
}

/// The input object `SearchBy`: exactly one of its fields is given.
sealed class SearchBy implements client.DataObject {
  factory SearchBy._read(graphql.JsonObject json, client.DataContext context) =>
      switch (json.fields.keys.toList()) {
        ['name'] => SearchByName(_nameCodec.field(json, 'name', context)),
        ['id'] => SearchById(_idCodec.field(json, 'id', context)),
        ['ids'] => SearchByIds(_idsCodec.field(json, 'ids', context)),
        _ => throw const client.DataFormatException(
          'Expected exactly one of the fields name, id, ids.',
        ),
      };

  /// Reads and writes the values of `SearchBy`.
  static const client.DataCodec<SearchBy> codec =
      client.ObjectDataCodec(SearchBy._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<List<String>> _idsCodec =
      client.ListDataCodec(client.ScalarDataCodec(graphql.IdCodec()));
}

/// [SearchBy] with its field `name`.
final class SearchByName implements SearchBy {
  /// Creates the input object with its field `name`.
  const SearchByName(this.name);

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'name': SearchBy._nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) => other is SearchByName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SearchByName($name)';
}

/// [SearchBy] with its field `id`.
final class SearchById implements SearchBy {
  /// Creates the input object with its field `id`.
  const SearchById(this.id);

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': SearchBy._idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is SearchById && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SearchById($id)';
}

/// [SearchBy] with its field `ids`.
final class SearchByIds implements SearchBy {
  /// Creates the input object with its field `ids`.
  const SearchByIds(this.ids);

  /// The field `ids`.
  final List<String> ids;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'ids': SearchBy._idsCodec.write(ids),
  });

  @override
  bool operator ==(Object other) =>
      other is SearchByIds &&
      const client.DataEquality().equals(other.ids, ids);

  @override
  int get hashCode => const client.DataEquality().hash(ids);

  @override
  String toString() => 'SearchByIds($ids)';
}

/// The input object `UserFilter`.
final class UserFilter implements client.DataObject {
  /// Creates the input object.
  const UserFilter({
    required this.ids,
    this.role = const graphql.Optional.absent(),
    this.name = const graphql.Optional.absent(),
    this.nested = const graphql.Optional.absent(),
    this.since = const graphql.Optional.absent(),
    this.matrix = const graphql.Optional.absent(),
  });

  factory UserFilter._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserFilter(
    role: _roleCodec.optionalField(json, 'role', context),
    name: _nameCodec.optionalField(json, 'name', context),
    ids: _idsCodec.field(json, 'ids', context),
    nested: _nestedCodec.optionalField(json, 'nested', context),
    since: _sinceCodec.optionalField(json, 'since', context),
    matrix: _matrixCodec.optionalField(json, 'matrix', context),
  );

  /// Reads and writes the values of `UserFilter`.
  static const client.DataCodec<UserFilter> codec =
      client.ObjectDataCodec(UserFilter._read);

  static const client.DataCodec<Role?> _roleCodec =
      client.NullableDataCodec(Role.codec);

  static const client.DataCodec<String?> _nameCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<List<String>> _idsCodec =
      client.ListDataCodec(client.ScalarDataCodec(graphql.IdCodec()));

  static const client.DataCodec<UserFilter?> _nestedCodec =
      client.NullableDataCodec(UserFilter.codec);

  static const client.DataCodec<DateTime?> _sinceCodec =
      client.NullableDataCodec(
        client.ScalarDataCodec(scalar_0.DateTimeCodec()),
      );

  static const client.DataCodec<List<List<int?>?>?> _matrixCodec =
      client.NullableDataCodec(
        client.ListDataCodec(
          client.NullableDataCodec(
            client.ListDataCodec(
              client.NullableDataCodec(
                client.ScalarDataCodec(graphql.IntCodec()),
              ),
            ),
          ),
        ),
      );

  /// The field `role`.
  final graphql.Optional<Role?> role;

  /// The field `name`. Its default is `"x"`.
  final graphql.Optional<String?> name;

  /// The field `ids`.
  final List<String> ids;

  /// The field `nested`.
  final graphql.Optional<UserFilter?> nested;

  /// The field `since`.
  final graphql.Optional<DateTime?> since;

  /// The field `matrix`.
  final graphql.Optional<List<List<int?>?>?> matrix;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (role case graphql.Present(:final value))
      'role': _roleCodec.write(value),
    if (name case graphql.Present(:final value))
      'name': _nameCodec.write(value),
    'ids': _idsCodec.write(ids),
    if (nested case graphql.Present(:final value))
      'nested': _nestedCodec.write(value),
    if (since case graphql.Present(:final value))
      'since': _sinceCodec.write(value),
    if (matrix case graphql.Present(:final value))
      'matrix': _matrixCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is UserFilter &&
      other.role == role &&
      other.name == name &&
      const client.DataEquality().equals(other.ids, ids) &&
      other.nested == nested &&
      other.since == since &&
      const client.DataEquality().equals(other.matrix, matrix);

  @override
  int get hashCode => Object.hashAll([
    role.hashCode,
    name.hashCode,
    const client.DataEquality().hash(ids),
    nested.hashCode,
    since.hashCode,
    const client.DataEquality().hash(matrix),
  ]);

  @override
  String toString() =>
      'UserFilter(role: $role, name: $name, ids: $ids, nested: $nested, '
      'since: $since, matrix: $matrix)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user.graphql.
// dart format off

import 'package:scalar_codecs/scalar_codecs.dart' as scalar_0;
import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

import 'schema.graphql.dart';

/// The query `GetUser`.
final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
  /// Creates the query with its [variables].
  const GetUserQuery(this.variables);

  /// The document of `GetUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'GetUser',
        type: graphql.OperationType.query,
        text: r'query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){user(id:$id){...UserCard@include(if:$full)role createdAt cursor friends(first:2)@include(if:$withFriends){id name __typename}__typename}}fragment UserCard on User{id name}',
        sha256:
          '198ab8e735cf86b04b66c1094135e3e63cfae5a89e4b793ae58982ff95891f8e',
      );

  /// The variables the query is sent with.
  final GetUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
      GetUserData.decode(data, variables: variablesJson);
}

/// The variables of the query `GetUser`.
final class GetUserVariables implements client.DataObject {
  /// Creates the variables.
  const GetUserVariables({
    required this.id,
    required this.full,
    this.withFriends = const graphql.Optional.absent(),
  });

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<bool?> _withFriendsCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.BooleanCodec()));

  static const client.DataCodec<bool> _fullCodec =
      client.ScalarDataCodec(graphql.BooleanCodec());

  /// The variable `$id`.
  final String id;

  /// The variable `$withFriends`; its default is `false`.
  final graphql.Optional<bool?> withFriends;

  /// The variable `$full`.
  final bool full;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    if (withFriends case graphql.Present(:final value))
      'withFriends': _withFriendsCodec.write(value),
    'full': _fullCodec.write(full),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserVariables &&
      other.id == id &&
      other.withFriends == withFriends &&
      other.full == full;

  @override
  int get hashCode => Object.hashAll([
    id.hashCode,
    withFriends.hashCode,
    full.hashCode,
  ]);

  @override
  String toString() =>
      'GetUserVariables(id: $id, withFriends: $withFriends, full: $full)';
}

/// The data of the query `GetUser`.
final class GetUserData implements client.DataObject {
  /// Creates the data.
  const GetUserData({this.user});

  factory GetUserData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserData(user: _userCodec.field(json, 'user', context));

  /// Reads and writes the data.
  static const client.DataCodec<GetUserData> codec =
      client.ObjectDataCodec(GetUserData._read);

  static const client.DataCodec<GetUserDataUser?> _userCodec =
      client.NullableDataCodec(GetUserDataUser.codec);

  static const Map<String, bool> _flagDefaults = {'withFriends': false};

  /// The field `user`.
  final GetUserDataUser? user;

  /// Reads [json], the `data` of a response to the query sent with
  /// [variables].
  static graphql.DecodeResult<GetUserData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables, _flagDefaults));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'user': _userCodec.write(user)});

  @override
  bool operator ==(Object other) => other is GetUserData && other.user == user;

  @override
  int get hashCode => user.hashCode;

  @override
  String toString() => 'GetUserData(user: $user)';
}

/// The field `user` of [GetUserData].
final class GetUserDataUser implements client.DataObject {
  /// Creates the value.
  const GetUserDataUser({
    required this.role,
    required this.fragments,
    this.createdAt,
    this.cursor,
    this.friends,
  });

  factory GetUserDataUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUser(
    role: _roleCodec.field(json, 'role', context),
    createdAt: _createdAtCodec.field(json, 'createdAt', context),
    cursor: _cursorCodec.field(json, 'cursor', context),
    friends: _friendsCodec.field(json, 'friends', context),
    fragments: GetUserDataUserFragments._read(json, context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUser> codec =
      client.ObjectDataCodec(GetUserDataUser._read);

  static const client.DataCodec<Role> _roleCodec = Role.codec;

  static const client.DataCodec<DateTime?> _createdAtCodec =
      client.NullableDataCodec(
        client.ScalarDataCodec(scalar_0.DateTimeCodec()),
      );

  static const client.DataCodec<graphql.JsonValue?> _cursorCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  static const client.DataCodec<List<GetUserDataUserFriends>?> _friendsCodec =
      client.NullableDataCodec(
        client.ListDataCodec(GetUserDataUserFriends.codec),
      );

  /// The field `role`.
  final Role role;

  /// The field `createdAt`.
  final DateTime? createdAt;

  /// The field `cursor`.
  final graphql.JsonValue? cursor;

  /// The field `friends`; null when `@include` or `@skip` left it out.
  final List<GetUserDataUserFriends>? friends;

  /// The fragments spread on this value.
  final GetUserDataUserFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    'role': _roleCodec.write(role),
    'createdAt': _createdAtCodec.write(createdAt),
    'cursor': _cursorCodec.write(cursor),
    'friends': _friendsCodec.write(friends),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUser &&
      other.role == role &&
      other.createdAt == createdAt &&
      other.cursor == cursor &&
      const client.DataEquality().equals(other.friends, friends) &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([
    role,
    createdAt,
    cursor,
    const client.DataEquality().hash(friends),
    fragments,
  ]);

  @override
  String toString() =>
      'GetUserDataUser(role: $role, createdAt: $createdAt, cursor: $cursor, friends: $friends, fragments: $fragments)';
}

/// The items of the field `friends` of [GetUserDataUser].
final class GetUserDataUserFriends implements client.DataObject {
  /// Creates the value.
  const GetUserDataUserFriends({required this.id, required this.name});

  factory GetUserDataUserFriends._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUserFriends(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUserFriends> codec =
      client.ObjectDataCodec(GetUserDataUserFriends._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUserFriends && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'GetUserDataUserFriends(id: $id, name: $name)';
}

/// The fragments spread on [GetUserDataUser].
final class GetUserDataUserFragments implements client.DataObject {
  /// Creates the fragments.
  const GetUserDataUserFragments({this.userCard});

  factory GetUserDataUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUserFragments(
    userCard: context.flag('full') ? UserCard.codec.read(json, context) : null,
  );

  /// The fragment `UserCard`; null when `@include` or `@skip` left it out.
  final UserCard? userCard;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...?userCard?.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUserFragments && other.userCard == userCard;

  @override
  int get hashCode => userCard.hashCode;

  @override
  String toString() => 'GetUserDataUserFragments(userCard: $userCard)';
}

/// The fragment `UserCard` on `User`.
final class UserCard implements client.DataObject {
  /// Creates the fragment.
  const UserCard({required this.id, required this.name});

  factory UserCard._read(graphql.JsonObject json, client.DataContext context) =>
      UserCard(
        id: _idCodec.field(json, 'id', context),
        name: _nameCodec.field(json, 'name', context),
      );

  /// Reads and writes the fragment.
  static const client.DataCodec<UserCard> codec =
      client.ObjectDataCodec(UserCard._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is UserCard && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'UserCard(id: $id, name: $name)';
}

/// The query `FindNode`.
final class FindNodeQuery extends client.GraphQLQuery<FindNodeData> {
  /// Creates the query with its [variables].
  const FindNodeQuery(this.variables);

  /// The document of `FindNode` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'FindNode',
        type: graphql.OperationType.query,
        text: r'query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}...on Bot{model}__typename}}fragment UserCard on User{id name}',
        sha256:
          '7a6b96aae12daef4bcd220864fe9f9d5e3f606c6cde72b347b4c985a3939b1e0',
      );

  /// The variables the query is sent with.
  final FindNodeVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<FindNodeData> decodeData(graphql.JsonObject data) =>
      FindNodeData.decode(data, variables: variablesJson);
}

/// The variables of the query `FindNode`.
final class FindNodeVariables implements client.DataObject {
  /// Creates the variables.
  const FindNodeVariables({required this.id});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The variable `$id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is FindNodeVariables &&
      other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FindNodeVariables(id: $id)';
}

/// The data of the query `FindNode`.
final class FindNodeData implements client.DataObject {
  /// Creates the data.
  const FindNodeData({this.node});

  factory FindNodeData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => FindNodeData(node: _nodeCodec.field(json, 'node', context));

  /// Reads and writes the data.
  static const client.DataCodec<FindNodeData> codec =
      client.ObjectDataCodec(FindNodeData._read);

  static const client.DataCodec<FindNodeDataNode?> _nodeCodec =
      client.NullableDataCodec(FindNodeDataNode.codec);

  /// The field `node`.
  final FindNodeDataNode? node;

  /// Reads [json], the `data` of a response to the query sent with
  /// [variables].
  static graphql.DecodeResult<FindNodeData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'node': _nodeCodec.write(node)});

  @override
  bool operator ==(Object other) => other is FindNodeData && other.node == node;

  @override
  int get hashCode => node.hashCode;

  @override
  String toString() => 'FindNodeData(node: $node)';
}

/// The field `node` of [FindNodeData]: a class per type the selection tells
/// apart, and [FindNodeDataNodeUnknown] for any other type.
sealed class FindNodeDataNode implements client.DataObject {
  factory FindNodeDataNode._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => FindNodeDataNodeUser._read(json, context),
    'Bot' => FindNodeDataNodeBot._read(json, context),
    _ => FindNodeDataNodeUnknown._read(json, context),
  };

  /// Reads and writes the value.
  static const client.DataCodec<FindNodeDataNode> codec =
      client.ObjectDataCodec(FindNodeDataNode._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The field `id`.
  String get id;
}

/// [FindNodeDataNode] when its type is `User`.
final class FindNodeDataNodeUser implements FindNodeDataNode {
  /// Creates the value.
  const FindNodeDataNodeUser({
    required this.id,
    required this.name,
    required this.fragments,
  });

  factory FindNodeDataNodeUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => FindNodeDataNodeUser(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
    fragments: FindNodeDataNodeUserFragments._read(json, context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  @override
  final String id;

  /// The field `name`.
  final String name;

  /// The fragments spread on this value.
  final FindNodeDataNodeUserFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is FindNodeDataNodeUser &&
      other.id == id &&
      other.name == name &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([id, name, fragments]);

  @override
  String toString() =>
      'FindNodeDataNodeUser(id: $id, name: $name, fragments: $fragments)';
}

/// The fragments spread on [FindNodeDataNodeUser].
final class FindNodeDataNodeUserFragments implements client.DataObject {
  /// Creates the fragments.
  const FindNodeDataNodeUserFragments({required this.userCard});

  factory FindNodeDataNodeUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => FindNodeDataNodeUserFragments(
    userCard: UserCard.codec.read(json, context),
  );

  /// The fragment `UserCard`.
  final UserCard userCard;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...userCard.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is FindNodeDataNodeUserFragments && other.userCard == userCard;

  @override
  int get hashCode => userCard.hashCode;

  @override
  String toString() => 'FindNodeDataNodeUserFragments(userCard: $userCard)';
}

/// [FindNodeDataNode] when its type is `Bot`.
final class FindNodeDataNodeBot implements FindNodeDataNode {
  /// Creates the value.
  const FindNodeDataNodeBot({required this.id, this.model});

  factory FindNodeDataNodeBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => FindNodeDataNodeBot(
    id: _idCodec.field(json, 'id', context),
    model: _modelCodec.field(json, 'model', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  @override
  final String id;

  /// The field `model`.
  final String? model;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is FindNodeDataNodeBot && other.id == id && other.model == model;

  @override
  int get hashCode => Object.hashAll([id, model]);

  @override
  String toString() => 'FindNodeDataNodeBot(id: $id, model: $model)';
}

/// [FindNodeDataNode] when its type is none of those the selection tells apart.
final class FindNodeDataNodeUnknown implements FindNodeDataNode {
  /// Creates the value.
  const FindNodeDataNodeUnknown({required this.typename, required this.id});

  factory FindNodeDataNodeUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => FindNodeDataNodeUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    id: _idCodec.field(json, 'id', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  @override
  final String typename;

  @override
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': _typenameCodec.write(typename),
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is FindNodeDataNodeUnknown &&
      other.typename == typename &&
      other.id == id;

  @override
  int get hashCode => Object.hashAll([typename, id]);

  @override
  String toString() => 'FindNodeDataNodeUnknown(typename: $typename, id: $id)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_mutations.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_mutations.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

import 'schema.graphql.dart';
import 'user.graphql.dart';

/// The mutation `SearchAll`.
final class SearchAllMutation extends client.GraphQLMutation<SearchAllData> {
  /// Creates the mutation with its [variables].
  const SearchAllMutation(this.variables);

  /// The document of `SearchAll` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'SearchAll',
        type: graphql.OperationType.mutation,
        text: r'mutation SearchAll($by:SearchBy!$filter:UserFilter$tags:[String!]){search(by:$by filter:$filter tags:$tags){...on User{id name}...on Bot{id model}__typename}}',
        sha256:
          'b004d7118cec818f35b49f580a3891bfda5ae2d8168e1e1cea48eb1ed2e8e246',
      );

  /// The variables the mutation is sent with.
  final SearchAllVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<SearchAllData> decodeData(graphql.JsonObject data) =>
      SearchAllData.decode(data, variables: variablesJson);
}

/// The variables of the mutation `SearchAll`.
final class SearchAllVariables implements client.DataObject {
  /// Creates the variables.
  const SearchAllVariables({
    required this.by,
    this.filter = const graphql.Optional.absent(),
    this.tags = const graphql.Optional.absent(),
  });

  static const client.DataCodec<SearchBy> _byCodec = SearchBy.codec;

  static const client.DataCodec<UserFilter?> _filterCodec =
      client.NullableDataCodec(UserFilter.codec);

  static const client.DataCodec<List<String>?> _tagsCodec =
      client.NullableDataCodec(
        client.ListDataCodec(client.ScalarDataCodec(graphql.StringCodec())),
      );

  /// The variable `$by`.
  final SearchBy by;

  /// The variable `$filter`.
  final graphql.Optional<UserFilter?> filter;

  /// The variable `$tags`.
  final graphql.Optional<List<String>?> tags;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'by': _byCodec.write(by),
    if (filter case graphql.Present(:final value))
      'filter': _filterCodec.write(value),
    if (tags case graphql.Present(:final value))
      'tags': _tagsCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is SearchAllVariables &&
      other.by == by &&
      other.filter == filter &&
      const client.DataEquality().equals(other.tags, tags);

  @override
  int get hashCode => Object.hashAll([
    by.hashCode,
    filter.hashCode,
    const client.DataEquality().hash(tags),
  ]);

  @override
  String toString() =>
      'SearchAllVariables(by: $by, filter: $filter, tags: $tags)';
}

/// The data of the mutation `SearchAll`.
final class SearchAllData implements client.DataObject {
  /// Creates the data.
  const SearchAllData({required this.search});

  factory SearchAllData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => SearchAllData(search: _searchCodec.field(json, 'search', context));

  /// Reads and writes the data.
  static const client.DataCodec<SearchAllData> codec =
      client.ObjectDataCodec(SearchAllData._read);

  static const client.DataCodec<List<SearchAllDataSearch>> _searchCodec =
      client.ListDataCodec(SearchAllDataSearch.codec);

  /// The field `search`.
  final List<SearchAllDataSearch> search;

  /// Reads [json], the `data` of a response to the mutation sent with
  /// [variables].
  static graphql.DecodeResult<SearchAllData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'search': _searchCodec.write(search)});

  @override
  bool operator ==(Object other) =>
      other is SearchAllData &&
      const client.DataEquality().equals(other.search, search);

  @override
  int get hashCode => const client.DataEquality().hash(search);

  @override
  String toString() => 'SearchAllData(search: $search)';
}

/// The items of the field `search` of [SearchAllData]: a class per type the
/// selection tells apart, and [SearchAllDataSearchUnknown] for any other type.
sealed class SearchAllDataSearch implements client.DataObject {
  factory SearchAllDataSearch._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => SearchAllDataSearchUser._read(json, context),
    'Bot' => SearchAllDataSearchBot._read(json, context),
    _ => SearchAllDataSearchUnknown._read(json, context),
  };

  /// Reads and writes the value.
  static const client.DataCodec<SearchAllDataSearch> codec =
      client.ObjectDataCodec(SearchAllDataSearch._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The name of the value's type, `__typename`.
  String get typename;
}

/// [SearchAllDataSearch] when its type is `User`.
final class SearchAllDataSearchUser implements SearchAllDataSearch {
  /// Creates the value.
  const SearchAllDataSearchUser({required this.id, required this.name});

  factory SearchAllDataSearchUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => SearchAllDataSearchUser(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('User'),
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is SearchAllDataSearchUser && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'SearchAllDataSearchUser(id: $id, name: $name)';
}

/// [SearchAllDataSearch] when its type is `Bot`.
final class SearchAllDataSearchBot implements SearchAllDataSearch {
  /// Creates the value.
  const SearchAllDataSearchBot({required this.id, this.model});

  factory SearchAllDataSearchBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => SearchAllDataSearchBot(
    id: _idCodec.field(json, 'id', context),
    model: _modelCodec.field(json, 'model', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  /// The field `id`.
  final String id;

  /// The field `model`.
  final String? model;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is SearchAllDataSearchBot && other.id == id && other.model == model;

  @override
  int get hashCode => Object.hashAll([id, model]);

  @override
  String toString() => 'SearchAllDataSearchBot(id: $id, model: $model)';
}

/// [SearchAllDataSearch] when its type is none of those the selection tells
/// apart.
final class SearchAllDataSearchUnknown implements SearchAllDataSearch {
  /// Creates the value.
  const SearchAllDataSearchUnknown({required this.typename});

  factory SearchAllDataSearchUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => SearchAllDataSearchUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  final String typename;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'__typename': _typenameCodec.write(typename)});

  @override
  bool operator ==(Object other) =>
      other is SearchAllDataSearchUnknown && other.typename == typename;

  @override
  int get hashCode => typename.hashCode;

  @override
  String toString() => 'SearchAllDataSearchUnknown(typename: $typename)';
}

/// The mutation `RenameUser`.
final class RenameUserMutation extends client.GraphQLMutation<RenameUserData> {
  /// Creates the mutation with its [variables].
  const RenameUserMutation(this.variables);

  /// The document of `RenameUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'RenameUser',
        type: graphql.OperationType.mutation,
        text: r'mutation RenameUser($id:ID!$name:String!){renameUser(id:$id name:$name){...UserCard __typename}}fragment UserCard on User{id name}',
        sha256:
          '99b64c8c80d6d3ed8be8cababb9cdafc092f7b125db944902fe6d172681f3020',
      );

  /// The variables the mutation is sent with.
  final RenameUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<RenameUserData> decodeData(graphql.JsonObject data) =>
      RenameUserData.decode(data, variables: variablesJson);
}

/// The variables of the mutation `RenameUser`.
final class RenameUserVariables implements client.DataObject {
  /// Creates the variables.
  const RenameUserVariables({required this.id, required this.name});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The variable `$id`.
  final String id;

  /// The variable `$name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is RenameUserVariables &&
      other.id == id &&
      other.name == name;

  @override
  int get hashCode => Object.hashAll([id.hashCode, name.hashCode]);

  @override
  String toString() => 'RenameUserVariables(id: $id, name: $name)';
}

/// The data of the mutation `RenameUser`.
final class RenameUserData implements client.DataObject {
  /// Creates the data.
  const RenameUserData({this.renameUser});

  factory RenameUserData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => RenameUserData(
    renameUser: _renameUserCodec.field(json, 'renameUser', context),
  );

  /// Reads and writes the data.
  static const client.DataCodec<RenameUserData> codec =
      client.ObjectDataCodec(RenameUserData._read);

  static const client.DataCodec<RenameUserDataRenameUser?> _renameUserCodec =
      client.NullableDataCodec(RenameUserDataRenameUser.codec);

  /// The field `renameUser`.
  final RenameUserDataRenameUser? renameUser;

  /// Reads [json], the `data` of a response to the mutation sent with
  /// [variables].
  static graphql.DecodeResult<RenameUserData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'renameUser': _renameUserCodec.write(renameUser)});

  @override
  bool operator ==(Object other) =>
      other is RenameUserData && other.renameUser == renameUser;

  @override
  int get hashCode => renameUser.hashCode;

  @override
  String toString() => 'RenameUserData(renameUser: $renameUser)';
}

/// The field `renameUser` of [RenameUserData].
final class RenameUserDataRenameUser implements client.DataObject {
  /// Creates the value.
  const RenameUserDataRenameUser({required this.fragments});

  factory RenameUserDataRenameUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => RenameUserDataRenameUser(
    fragments: RenameUserDataRenameUserFragments._read(json, context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<RenameUserDataRenameUser> codec =
      client.ObjectDataCodec(RenameUserDataRenameUser._read);

  /// The fragments spread on this value.
  final RenameUserDataRenameUserFragments fragments;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...fragments.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is RenameUserDataRenameUser && other.fragments == fragments;

  @override
  int get hashCode => fragments.hashCode;

  @override
  String toString() => 'RenameUserDataRenameUser(fragments: $fragments)';
}

/// The fragments spread on [RenameUserDataRenameUser].
final class RenameUserDataRenameUserFragments implements client.DataObject {
  /// Creates the fragments.
  const RenameUserDataRenameUserFragments({required this.userCard});

  factory RenameUserDataRenameUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => RenameUserDataRenameUserFragments(
    userCard: UserCard.codec.read(json, context),
  );

  /// The fragment `UserCard`.
  final UserCard userCard;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...userCard.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is RenameUserDataRenameUserFragments && other.userCard == userCard;

  @override
  int get hashCode => userCard.hashCode;

  @override
  String toString() => 'RenameUserDataRenameUserFragments(userCard: $userCard)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_subscriptions.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_subscriptions.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The subscription `UserChanged`.
final class UserChangedSubscription
    extends client.GraphQLSubscription<UserChangedData> {
  /// Creates the subscription with its [variables].
  const UserChangedSubscription(this.variables);

  /// The document of `UserChanged` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'UserChanged',
        type: graphql.OperationType.subscription,
        text: r'subscription UserChanged($id:ID!){userChanged(id:$id){id name __typename}}',
        sha256:
          '7a4a1e850c31f8be22e726ba1e15417b48ca868176bc43c36a64fa305be990b2',
      );

  /// The variables the subscription is sent with.
  final UserChangedVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<UserChangedData> decodeData(graphql.JsonObject data) =>
      UserChangedData.decode(data, variables: variablesJson);
}

/// The variables of the subscription `UserChanged`.
final class UserChangedVariables implements client.DataObject {
  /// Creates the variables.
  const UserChangedVariables({required this.id});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The variable `$id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is UserChangedVariables &&
      other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'UserChangedVariables(id: $id)';
}

/// The data of the subscription `UserChanged`.
final class UserChangedData implements client.DataObject {
  /// Creates the data.
  const UserChangedData({this.userChanged});

  factory UserChangedData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserChangedData(
    userChanged: _userChangedCodec.field(json, 'userChanged', context),
  );

  /// Reads and writes the data.
  static const client.DataCodec<UserChangedData> codec =
      client.ObjectDataCodec(UserChangedData._read);

  static const client.DataCodec<UserChangedDataUserChanged?> _userChangedCodec =
      client.NullableDataCodec(UserChangedDataUserChanged.codec);

  /// The field `userChanged`.
  final UserChangedDataUserChanged? userChanged;

  /// Reads [json], the `data` of a response to the subscription sent with
  /// [variables].
  static graphql.DecodeResult<UserChangedData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'userChanged': _userChangedCodec.write(userChanged)});

  @override
  bool operator ==(Object other) =>
      other is UserChangedData && other.userChanged == userChanged;

  @override
  int get hashCode => userChanged.hashCode;

  @override
  String toString() => 'UserChangedData(userChanged: $userChanged)';
}

/// The field `userChanged` of [UserChangedData].
final class UserChangedDataUserChanged implements client.DataObject {
  /// Creates the value.
  const UserChangedDataUserChanged({required this.id, required this.name});

  factory UserChangedDataUserChanged._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserChangedDataUserChanged(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<UserChangedDataUserChanged> codec =
      client.ObjectDataCodec(UserChangedDataUserChanged._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is UserChangedDataUserChanged &&
      other.id == id &&
      other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'UserChangedDataUserChanged(id: $id, name: $name)';
}

/// The query `Everyone`.
final class EveryoneQuery extends client.GraphQLQuery<EveryoneData> {
  /// Creates the query.
  const EveryoneQuery();

  /// The document of `Everyone` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'Everyone',
        type: graphql.OperationType.query,
        text: 'query Everyone{node(id:"1"){id __typename}}',
        sha256:
          '5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61',
      );

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => graphql.JsonObject(const {});

  @override
  graphql.DecodeResult<EveryoneData> decodeData(graphql.JsonObject data) =>
      EveryoneData.decode(data);
}

/// The data of the query `Everyone`.
final class EveryoneData implements client.DataObject {
  /// Creates the data.
  const EveryoneData({this.node});

  factory EveryoneData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => EveryoneData(node: _nodeCodec.field(json, 'node', context));

  /// Reads and writes the data.
  static const client.DataCodec<EveryoneData> codec =
      client.ObjectDataCodec(EveryoneData._read);

  static const client.DataCodec<EveryoneDataNode?> _nodeCodec =
      client.NullableDataCodec(EveryoneDataNode.codec);

  /// The field `node`.
  final EveryoneDataNode? node;

  /// Reads [json], the `data` of a response to the query sent with
  /// [variables].
  static graphql.DecodeResult<EveryoneData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'node': _nodeCodec.write(node)});

  @override
  bool operator ==(Object other) => other is EveryoneData && other.node == node;

  @override
  int get hashCode => node.hashCode;

  @override
  String toString() => 'EveryoneData(node: $node)';
}

/// The field `node` of [EveryoneData].
final class EveryoneDataNode implements client.DataObject {
  /// Creates the value.
  const EveryoneDataNode({required this.id});

  factory EveryoneDataNode._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => EveryoneDataNode(id: _idCodec.field(json, 'id', context));

  /// Reads and writes the value.
  static const client.DataCodec<EveryoneDataNode> codec =
      client.ObjectDataCodec(EveryoneDataNode._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({'id': _idCodec.write(id)});

  @override
  bool operator ==(Object other) => other is EveryoneDataNode && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EveryoneDataNode(id: $id)';
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/support/bin/round_trip.dart.txt`:

```text
import 'dart:io';

import 'package:generated_operations/schema.graphql.dart';
import 'package:generated_operations/user.graphql.dart';
import 'package:generated_operations/user_mutations.graphql.dart';
import 'package:generated_operations/user_subscriptions.graphql.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

JsonObject _json(String text) =>
    (const JsonReader().parse(text) as DecodeSuccess<JsonValue>).value
        as JsonObject;

void main() {
  _request();
  _optionals();
  _getUser();
  _findNode();
  _searchAll();
  _otherOperations();
  _badMember();
}

void _request() {
  const query = GetUserQuery(GetUserVariables(id: '1', full: true));
  final GraphQLRequest request = query.toRequest();
  _expect(request.query, GetUserQuery.operationDocument.text);
  _expect(request.operationName, 'GetUser');
  _expect(request.variables, _json('{"id": "1", "full": true}'));
  _expect(GetUserQuery.operationDocument.sha256.length, 64);
  _expect(const EveryoneQuery().variablesJson, _json('{}'));
  _expect(const EveryoneQuery().toRequest().operationName, 'Everyone');
}

void _optionals() {
  const sent = GetUserVariables(
    id: '1',
    full: false,
    withFriends: Optional.present(null),
  );
  _expect(sent.toJson(), _json('{"id": "1", "full": false, "withFriends": null}'));
  _expect(
    sent == const GetUserVariables(id: '1', full: false),
    false,
  );
  const search = SearchAllVariables(
    by: SearchByName('Ada'),
    tags: Optional.present(['a', 'b']),
  );
  _expect(search.toJson(), _json('{"by": {"name": "Ada"}, "tags": ["a", "b"]}'));
  _expect(
    search ==
        const SearchAllVariables(
          by: SearchByName('Ada'),
          tags: Optional.present(['a', 'b']),
        ),
    true,
  );
}

void _getUser() {
  const withUser = GetUserVariables(
    id: '1',
    full: true,
    withFriends: Optional.present(true),
  );
  final GetUserData full = _decode(
    const GetUserQuery(withUser),
    _json('''
{"user": {"id": "1", "name": "Ada", "role": "ADMIN",
  "createdAt": "2026-10-15T00:00:00.000Z", "cursor": "c",
  "friends": [{"id": "2", "name": "Bob", "__typename": "User"}],
  "__typename": "User"}}
'''),
  );
  _expect(full.user?.fragments.userCard?.name, 'Ada');
  _expect(full.user?.friends?.single.name, 'Bob');
  _expect(full.user?.role, RoleKnown.admin);
  _roundTrips(const GetUserQuery(withUser), full);
  const hidden = GetUserVariables(id: '1', full: false);
  final GetUserData lean = _decode(
    const GetUserQuery(hidden),
    _json('{"user": {"role": "VIEWER", "createdAt": null, "cursor": null}}'),
  );
  _expect(lean.user?.fragments.userCard, null);
  _expect(lean.user?.friends, null);
  _roundTrips(const GetUserQuery(hidden), lean);
  final GetUserData none = _decode(
    const GetUserQuery(hidden),
    _json('{"user": null}'),
  );
  _expect(none.user, null);
  _roundTrips(const GetUserQuery(hidden), none);
}

void _findNode() {
  const query = FindNodeQuery(FindNodeVariables(id: '1'));
  final FindNodeData user = _decode(
    query,
    _json('{"node": {"__typename": "User", "id": "1", "name": "Ada"}}'),
  );
  _expect(
    switch (user.node) {
      FindNodeDataNodeUser(:final name, :final fragments) =>
        '$name ${fragments.userCard.id}',
      FindNodeDataNodeBot() || FindNodeDataNodeUnknown() || null => 'other',
    },
    'Ada 1',
  );
  final FindNodeData bot = _decode(
    query,
    _json('{"node": {"__typename": "Bot", "id": "2", "model": null}}'),
  );
  _expect(bot.node is FindNodeDataNodeBot, true);
  final FindNodeData robot = _decode(
    query,
    _json('{"node": {"__typename": "Robot", "id": "3"}}'),
  );
  _expect(robot.node is FindNodeDataNodeUnknown, true);
  for (final FindNodeData data in [user, bot, robot]) {
    _roundTrips(query, data);
  }
}

void _searchAll() {
  const query = SearchAllMutation(SearchAllVariables(by: SearchByName('A')));
  final SearchAllData data = _decode(
    query,
    _json('''
{"search": [{"__typename": "User", "id": "1", "name": "Ada"},
  {"__typename": "Bot", "id": "2", "model": "m"},
  {"__typename": "Other"}]}
'''),
  );
  _expect(data.search.length, 3);
  _expect(data.search.last is SearchAllDataSearchUnknown, true);
  _roundTrips(query, data);
  _expect(query.toRequest().variables, _json('{"by": {"name": "A"}}'));
  _expect(query.document.type, OperationType.mutation);
}

void _otherOperations() {
  const rename = RenameUserMutation(RenameUserVariables(id: '1', name: 'Z'));
  final RenameUserData renamed = _decode(
    rename,
    _json('{"renameUser": {"id": "1", "name": "Z"}}'),
  );
  _expect(renamed.renameUser?.fragments.userCard.name, 'Z');
  _roundTrips(rename, renamed);
  const changed = UserChangedSubscription(UserChangedVariables(id: '1'));
  final UserChangedData event = _decode(
    changed,
    _json('{"userChanged": {"id": "1", "name": "Ada"}}'),
  );
  _expect(event.userChanged?.name, 'Ada');
  _roundTrips(changed, event);
  _expect(changed.document.type, OperationType.subscription);
  final EveryoneData everyone = _decode(
    const EveryoneQuery(),
    _json('{"node": {"id": "9"}}'),
  );
  _roundTrips(const EveryoneQuery(), everyone);
}

void _badMember() {
  const query = GetUserQuery(GetUserVariables(id: '1', full: false));
  final DecodeResult<GetUserData> result = query.decodeData(
    _json('{"user": {"role": 7, "createdAt": null, "cursor": null}}'),
  );
  if (result is! DecodeFailure) {
    _fail('a bad role was accepted');
  } else {
    _expect('${result.path}', '[user, role]');
  }
}

T _decode<T extends Object>(GraphQLOperation<T> operation, JsonObject data) {
  final DecodeResult<T> result = operation.decodeData(data);
  if (result is! DecodeSuccess<T>) {
    _fail('decode failed: $result');
  }
  return (result as DecodeSuccess<T>).value;
}

void _roundTrips<T extends Object>(GraphQLOperation<T> operation, T value) {
  final T again = _decode(operation, (value as DataObject).toJson());
  if (again != value || again.hashCode != value.hashCode) {
    _fail('decode(toJson()) is $again, not $value');
  }
}

void _expect(Object? actual, Object? expected) {
  if (actual != expected) {
    _fail('expected $expected, got $actual');
  }
}

void _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt`:

```text
import 'package:typed_graphql/typed_graphql.dart';

/// Reads and writes a `DateTime` as an ISO 8601 string.
final class const DateTimeCodec() implements ScalarCodec<DateTime> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<DateTime> decode(JsonValue json) => switch (json) {
    JsonString(:final value) when DateTime.tryParse(value) != null =>
      DecodeSuccess(DateTime.parse(value)),
    _ => DecodeFailure('Expected an ISO 8601 date, got: $json'),
  };

  @override
  JsonValue encode(DateTime value) => JsonString(value.toIso8601String());
}
```

Create `packages/typed_graphql_codegen/test/goldens/operations/support/packages/scalar_codecs/pubspec.yaml.txt`:

```text
name: scalar_codecs
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
  typed_graphql: ^0.0.1
```

In `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,276 @@
 // GENERATED CODE - DO NOT MODIFY BY HAND.
 // Generated by typed_graphql_codegen from lib/user_query.graphql.
 // dart format off
+
+import 'package:typed_graphql/typed_graphql.dart' as graphql;
+import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
+
+import 'user_node.graphql.dart';
+import 'user_result.graphql.dart';
+
+/// The query `FindNode`.
+final class FindNodeQuery extends client.GraphQLQuery<FindNodeData> {
+  /// Creates the query with its [variables].
+  const FindNodeQuery(this.variables);
+
+  /// The document of `FindNode` as it is sent.
+  static const client.OperationDocument operationDocument =
+      client.OperationDocument(
+        name: 'FindNode',
+        type: graphql.OperationType.query,
+        text: r'query FindNode($id:ID!){node(id:$id){...NodeCard ...Owned ...Reselect ...Labelled __typename}search{...Result __typename}}fragment Labelled on Node{...NodeId ...on User{name}...on Bot{model}}fragment NodeCard on Node{id ...on User{name ...UserName}...on Bot{model}}fragment NodeId on Node{id}fragment Owned on Node{id owner{name __typename}...on User{name}...on Bot{model}}fragment Reselect on Node{id ...on User{id friends(first:1){name __typename}}}fragment Result on SearchResult{__typename ...on User{id friends(first:1){id __typename}}...on Bot{id}}fragment UserName on User{name}',
+        sha256:
+          'd41cfe4b13d7d80e8acd5b55ee1e6867772b8fd260a2996b8c913b84fc986f99',
+      );
+
+  /// The variables the query is sent with.
+  final FindNodeVariables variables;
+
+  @override
+  client.OperationDocument get document => operationDocument;
+
+  @override
+  graphql.JsonObject get variablesJson => variables.toJson();
+
+  @override
+  graphql.DecodeResult<FindNodeData> decodeData(graphql.JsonObject data) =>
+      FindNodeData.decode(data, variables: variablesJson);
+}
+
+/// The variables of the query `FindNode`.
+final class FindNodeVariables implements client.DataObject {
+  /// Creates the variables.
+  const FindNodeVariables({required this.id});
+
+  static const client.DataCodec<String> _idCodec =
+      client.ScalarDataCodec(graphql.IdCodec());
+
+  /// The variable `$id`.
+  final String id;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'id': _idCodec.write(id),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is FindNodeVariables &&
+      other.id == id;
+
+  @override
+  int get hashCode => id.hashCode;
+
+  @override
+  String toString() => 'FindNodeVariables(id: $id)';
+}
+
+/// The data of the query `FindNode`.
+final class FindNodeData implements client.DataObject {
+  /// Creates the data.
+  const FindNodeData({required this.search, this.node});
+
+  factory FindNodeData._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => FindNodeData(
+    node: _nodeCodec.field(json, 'node', context),
+    search: _searchCodec.field(json, 'search', context),
+  );
+
+  /// Reads and writes the data.
+  static const client.DataCodec<FindNodeData> codec =
+      client.ObjectDataCodec(FindNodeData._read);
+
+  static const client.DataCodec<FindNodeDataNode?> _nodeCodec =
+      client.NullableDataCodec(FindNodeDataNode.codec);
+
+  static const client.DataCodec<List<FindNodeDataSearch>> _searchCodec =
+      client.ListDataCodec(FindNodeDataSearch.codec);
+
+  /// The field `node`.
+  final FindNodeDataNode? node;
+
+  /// The field `search`.
+  final List<FindNodeDataSearch> search;
+
+  /// Reads [json], the `data` of a response to the query sent with
+  /// [variables].
+  static graphql.DecodeResult<FindNodeData> decode(
+    graphql.JsonObject json, {
+    graphql.JsonObject? variables,
+  }) => codec.decode(json, client.DataContext(variables));
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'node': _nodeCodec.write(node),
+    'search': _searchCodec.write(search),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is FindNodeData &&
+      other.node == node &&
+      const client.DataEquality().equals(other.search, search);
+
+  @override
+  int get hashCode => Object.hashAll([
+    node,
+    const client.DataEquality().hash(search),
+  ]);
+
+  @override
+  String toString() => 'FindNodeData(node: $node, search: $search)';
+}
+
+/// The field `node` of [FindNodeData].
+final class FindNodeDataNode implements client.DataObject {
+  /// Creates the value.
+  const FindNodeDataNode({required this.fragments});
+
+  factory FindNodeDataNode._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => FindNodeDataNode(
+    fragments: FindNodeDataNodeFragments._read(json, context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<FindNodeDataNode> codec =
+      client.ObjectDataCodec(FindNodeDataNode._read);
+
+  /// The fragments spread on this value.
+  final FindNodeDataNodeFragments fragments;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...fragments.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is FindNodeDataNode && other.fragments == fragments;
+
+  @override
+  int get hashCode => fragments.hashCode;
+
+  @override
+  String toString() => 'FindNodeDataNode(fragments: $fragments)';
+}
+
+/// The fragments spread on [FindNodeDataNode].
+final class FindNodeDataNodeFragments implements client.DataObject {
+  /// Creates the fragments.
+  const FindNodeDataNodeFragments({
+    required this.nodeCard,
+    required this.owned,
+    required this.reselect,
+    required this.labelled,
+  });
+
+  factory FindNodeDataNodeFragments._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => FindNodeDataNodeFragments(
+    nodeCard: NodeCard.codec.read(json, context),
+    owned: Owned.codec.read(json, context),
+    reselect: Reselect.codec.read(json, context),
+    labelled: Labelled.codec.read(json, context),
+  );
+
+  /// The fragment `NodeCard`.
+  final NodeCard nodeCard;
+
+  /// The fragment `Owned`.
+  final Owned owned;
+
+  /// The fragment `Reselect`.
+  final Reselect reselect;
+
+  /// The fragment `Labelled`.
+  final Labelled labelled;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    ...nodeCard.toJson().fields,
+    ...owned.toJson().fields,
+    ...reselect.toJson().fields,
+    ...labelled.toJson().fields,
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is FindNodeDataNodeFragments &&
+      other.nodeCard == nodeCard &&
+      other.owned == owned &&
+      other.reselect == reselect &&
+      other.labelled == labelled;
+
+  @override
+  int get hashCode => Object.hashAll([nodeCard, owned, reselect, labelled]);
+
+  @override
+  String toString() =>
+      'FindNodeDataNodeFragments(nodeCard: $nodeCard, owned: $owned, reselect: $reselect, labelled: $labelled)';
+}
+
+/// The items of the field `search` of [FindNodeData].
+final class FindNodeDataSearch implements client.DataObject {
+  /// Creates the value.
+  const FindNodeDataSearch({required this.fragments});
+
+  factory FindNodeDataSearch._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => FindNodeDataSearch(
+    fragments: FindNodeDataSearchFragments._read(json, context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<FindNodeDataSearch> codec =
+      client.ObjectDataCodec(FindNodeDataSearch._read);
+
+  /// The fragments spread on this value.
+  final FindNodeDataSearchFragments fragments;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...fragments.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is FindNodeDataSearch && other.fragments == fragments;
+
+  @override
+  int get hashCode => fragments.hashCode;
+
+  @override
+  String toString() => 'FindNodeDataSearch(fragments: $fragments)';
+}
+
+/// The fragments spread on [FindNodeDataSearch].
+final class FindNodeDataSearchFragments implements client.DataObject {
+  /// Creates the fragments.
+  const FindNodeDataSearchFragments({required this.result});
+
+  factory FindNodeDataSearchFragments._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => FindNodeDataSearchFragments(result: Result.codec.read(json, context));
+
+  /// The fragment `Result`.
+  final Result result;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...result.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is FindNodeDataSearchFragments && other.result == result;
+
+  @override
+  int get hashCode => result.hashCode;
+
+  @override
+  String toString() => 'FindNodeDataSearchFragments(result: $result)';
+}
```

In `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,9 +2,302 @@
 // Generated by typed_graphql_codegen from lib/user.graphql.
 // dart format off
 
+import 'package:scalar_codecs/scalar_codecs.dart' as scalar_0;
 import 'package:typed_graphql/typed_graphql.dart' as graphql;
 import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
 
+import 'schema.graphql.dart';
+
+/// The query `GetUser`.
+final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
+  /// Creates the query with its [variables].
+  const GetUserQuery(this.variables);
+
+  /// The document of `GetUser` as it is sent.
+  static const client.OperationDocument operationDocument =
+      client.OperationDocument(
+        name: 'GetUser',
+        type: graphql.OperationType.query,
+        text: r'query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){user(id:$id){...UserCard@include(if:$full)role createdAt cursor friends(first:2)@include(if:$withFriends){id name __typename}__typename}}fragment UserCard on User{id name}',
+        sha256:
+          '198ab8e735cf86b04b66c1094135e3e63cfae5a89e4b793ae58982ff95891f8e',
+      );
+
+  /// The variables the query is sent with.
+  final GetUserVariables variables;
+
+  @override
+  client.OperationDocument get document => operationDocument;
+
+  @override
+  graphql.JsonObject get variablesJson => variables.toJson();
+
+  @override
+  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
+      GetUserData.decode(data, variables: variablesJson);
+}
+
+/// The variables of the query `GetUser`.
+final class GetUserVariables implements client.DataObject {
+  /// Creates the variables.
+  const GetUserVariables({
+    required this.id,
+    required this.full,
+    this.withFriends = const graphql.Optional.absent(),
+  });
+
+  static const client.DataCodec<String> _idCodec =
+      client.ScalarDataCodec(graphql.IdCodec());
+
+  static const client.DataCodec<bool?> _withFriendsCodec =
+      client.NullableDataCodec(client.ScalarDataCodec(graphql.BooleanCodec()));
+
+  static const client.DataCodec<bool> _fullCodec =
+      client.ScalarDataCodec(graphql.BooleanCodec());
+
+  /// The variable `$id`.
+  final String id;
+
+  /// The variable `$withFriends`; its default is `false`.
+  final graphql.Optional<bool?> withFriends;
+
+  /// The variable `$full`.
+  final bool full;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'id': _idCodec.write(id),
+    if (withFriends case graphql.Present(:final value))
+      'withFriends': _withFriendsCodec.write(value),
+    'full': _fullCodec.write(full),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is GetUserVariables &&
+      other.id == id &&
+      other.withFriends == withFriends &&
+      other.full == full;
+
+  @override
+  int get hashCode => Object.hashAll([
+    id.hashCode,
+    withFriends.hashCode,
+    full.hashCode,
+  ]);
+
+  @override
+  String toString() =>
+      'GetUserVariables(id: $id, withFriends: $withFriends, full: $full)';
+}
+
+/// The data of the query `GetUser`.
+final class GetUserData implements client.DataObject {
+  /// Creates the data.
+  const GetUserData({this.user});
+
+  factory GetUserData._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserData(user: _userCodec.field(json, 'user', context));
+
+  /// Reads and writes the data.
+  static const client.DataCodec<GetUserData> codec =
+      client.ObjectDataCodec(GetUserData._read);
+
+  static const client.DataCodec<GetUserDataUser?> _userCodec =
+      client.NullableDataCodec(GetUserDataUser.codec);
+
+  static const Map<String, bool> _flagDefaults = {'withFriends': false};
+
+  /// The field `user`.
+  final GetUserDataUser? user;
+
+  /// Reads [json], the `data` of a response to the query sent with
+  /// [variables].
+  static graphql.DecodeResult<GetUserData> decode(
+    graphql.JsonObject json, {
+    graphql.JsonObject? variables,
+  }) => codec.decode(json, client.DataContext(variables, _flagDefaults));
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({'user': _userCodec.write(user)});
+
+  @override
+  bool operator ==(Object other) => other is GetUserData && other.user == user;
+
+  @override
+  int get hashCode => user.hashCode;
+
+  @override
+  String toString() => 'GetUserData(user: $user)';
+}
+
+/// The field `user` of [GetUserData].
+final class GetUserDataUser implements client.DataObject {
+  /// Creates the value.
+  const GetUserDataUser({
+    required this.role,
+    required this.fragments,
+    this.createdAt,
+    this.cursor,
+    this.friends,
+  });
+
+  factory GetUserDataUser._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserDataUser(
+    role: _roleCodec.field(json, 'role', context),
+    createdAt: _createdAtCodec.field(json, 'createdAt', context),
+    cursor: _cursorCodec.field(json, 'cursor', context),
+    friends: _friendsCodec.field(json, 'friends', context),
+    fragments: GetUserDataUserFragments._read(json, context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<GetUserDataUser> codec =
+      client.ObjectDataCodec(GetUserDataUser._read);
+
+  static const client.DataCodec<Role> _roleCodec = Role.codec;
+
+  static const client.DataCodec<DateTime?> _createdAtCodec =
+      client.NullableDataCodec(
+        client.ScalarDataCodec(scalar_0.DateTimeCodec()),
+      );
+
+  static const client.DataCodec<graphql.JsonValue?> _cursorCodec =
+      client.NullableDataCodec(client.JsonDataCodec());
+
+  static const client.DataCodec<List<GetUserDataUserFriends>?> _friendsCodec =
+      client.NullableDataCodec(
+        client.ListDataCodec(GetUserDataUserFriends.codec),
+      );
+
+  /// The field `role`.
+  final Role role;
+
+  /// The field `createdAt`.
+  final DateTime? createdAt;
+
+  /// The field `cursor`.
+  final graphql.JsonValue? cursor;
+
+  /// The field `friends`; null when `@include` or `@skip` left it out.
+  final List<GetUserDataUserFriends>? friends;
+
+  /// The fragments spread on this value.
+  final GetUserDataUserFragments fragments;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    ...fragments.toJson().fields,
+    'role': _roleCodec.write(role),
+    'createdAt': _createdAtCodec.write(createdAt),
+    'cursor': _cursorCodec.write(cursor),
+    'friends': _friendsCodec.write(friends),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is GetUserDataUser &&
+      other.role == role &&
+      other.createdAt == createdAt &&
+      other.cursor == cursor &&
+      const client.DataEquality().equals(other.friends, friends) &&
+      other.fragments == fragments;
+
+  @override
+  int get hashCode => Object.hashAll([
+    role,
+    createdAt,
+    cursor,
+    const client.DataEquality().hash(friends),
+    fragments,
+  ]);
+
+  @override
+  String toString() =>
+      'GetUserDataUser(role: $role, createdAt: $createdAt, cursor: $cursor, friends: $friends, fragments: $fragments)';
+}
+
+/// The items of the field `friends` of [GetUserDataUser].
+final class GetUserDataUserFriends implements client.DataObject {
+  /// Creates the value.
+  const GetUserDataUserFriends({required this.id, required this.name});
+
+  factory GetUserDataUserFriends._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserDataUserFriends(
+    id: _idCodec.field(json, 'id', context),
+    name: _nameCodec.field(json, 'name', context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<GetUserDataUserFriends> codec =
+      client.ObjectDataCodec(GetUserDataUserFriends._read);
+
+  static const client.DataCodec<String> _idCodec =
+      client.ScalarDataCodec(graphql.IdCodec());
+
+  static const client.DataCodec<String> _nameCodec =
+      client.ScalarDataCodec(graphql.StringCodec());
+
+  /// The field `id`.
+  final String id;
+
+  /// The field `name`.
+  final String name;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'id': _idCodec.write(id),
+    'name': _nameCodec.write(name),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is GetUserDataUserFriends && other.id == id && other.name == name;
+
+  @override
+  int get hashCode => Object.hashAll([id, name]);
+
+  @override
+  String toString() => 'GetUserDataUserFriends(id: $id, name: $name)';
+}
+
+/// The fragments spread on [GetUserDataUser].
+final class GetUserDataUserFragments implements client.DataObject {
+  /// Creates the fragments.
+  const GetUserDataUserFragments({this.userCard});
+
+  factory GetUserDataUserFragments._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserDataUserFragments(
+    userCard: context.flag('full') ? UserCard.codec.read(json, context) : null,
+  );
+
+  /// The fragment `UserCard`; null when `@include` or `@skip` left it out.
+  final UserCard? userCard;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...?userCard?.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is GetUserDataUserFragments && other.userCard == userCard;
+
+  @override
+  int get hashCode => userCard.hashCode;
+
+  @override
+  String toString() => 'GetUserDataUserFragments(userCard: $userCard)';
+}
+
 /// The fragment `UserCard` on `User`.
 final class UserCard implements client.DataObject {
   /// Creates the fragment.
@@ -55,3 +348,166 @@ final class UserCard implements client.DataObject {
   @override
   String toString() => 'UserCard(id: $id, name: $name)';
 }
+
+/// The query `Search`.
+final class SearchQuery extends client.GraphQLQuery<SearchData> {
+  /// Creates the query with its [variables].
+  const SearchQuery(this.variables);
+
+  /// The document of `Search` as it is sent.
+  static const client.OperationDocument operationDocument =
+      client.OperationDocument(
+        name: 'Search',
+        type: graphql.OperationType.query,
+        text: r'query Search($by:SearchBy!$filter:UserFilter$paging:Paging){search(by:$by filter:$filter paging:$paging){__typename}}',
+        sha256:
+          'f3ea82e5d99ddba932a1e84fac4ef51e6d231dfdfd0b84a93dd2803d879b0387',
+      );
+
+  /// The variables the query is sent with.
+  final SearchVariables variables;
+
+  @override
+  client.OperationDocument get document => operationDocument;
+
+  @override
+  graphql.JsonObject get variablesJson => variables.toJson();
+
+  @override
+  graphql.DecodeResult<SearchData> decodeData(graphql.JsonObject data) =>
+      SearchData.decode(data, variables: variablesJson);
+}
+
+/// The variables of the query `Search`.
+final class SearchVariables implements client.DataObject {
+  /// Creates the variables.
+  const SearchVariables({
+    required this.by,
+    this.filter = const graphql.Optional.absent(),
+    this.paging = const graphql.Optional.absent(),
+  });
+
+  static const client.DataCodec<SearchBy> _byCodec = SearchBy.codec;
+
+  static const client.DataCodec<UserFilter?> _filterCodec =
+      client.NullableDataCodec(UserFilter.codec);
+
+  static const client.DataCodec<Paging?> _pagingCodec =
+      client.NullableDataCodec(Paging.codec);
+
+  /// The variable `$by`.
+  final SearchBy by;
+
+  /// The variable `$filter`.
+  final graphql.Optional<UserFilter?> filter;
+
+  /// The variable `$paging`.
+  final graphql.Optional<Paging?> paging;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'by': _byCodec.write(by),
+    if (filter case graphql.Present(:final value))
+      'filter': _filterCodec.write(value),
+    if (paging case graphql.Present(:final value))
+      'paging': _pagingCodec.write(value),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is SearchVariables &&
+      other.by == by &&
+      other.filter == filter &&
+      other.paging == paging;
+
+  @override
+  int get hashCode => Object.hashAll([
+    by.hashCode,
+    filter.hashCode,
+    paging.hashCode,
+  ]);
+
+  @override
+  String toString() =>
+      'SearchVariables(by: $by, filter: $filter, paging: $paging)';
+}
+
+/// The data of the query `Search`.
+final class SearchData implements client.DataObject {
+  /// Creates the data.
+  const SearchData({required this.search});
+
+  factory SearchData._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => SearchData(search: _searchCodec.field(json, 'search', context));
+
+  /// Reads and writes the data.
+  static const client.DataCodec<SearchData> codec =
+      client.ObjectDataCodec(SearchData._read);
+
+  static const client.DataCodec<List<SearchDataSearch>> _searchCodec =
+      client.ListDataCodec(SearchDataSearch.codec);
+
+  /// The field `search`.
+  final List<SearchDataSearch> search;
+
+  /// Reads [json], the `data` of a response to the query sent with
+  /// [variables].
+  static graphql.DecodeResult<SearchData> decode(
+    graphql.JsonObject json, {
+    graphql.JsonObject? variables,
+  }) => codec.decode(json, client.DataContext(variables));
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({'search': _searchCodec.write(search)});
+
+  @override
+  bool operator ==(Object other) =>
+      other is SearchData &&
+      const client.DataEquality().equals(other.search, search);
+
+  @override
+  int get hashCode => const client.DataEquality().hash(search);
+
+  @override
+  String toString() => 'SearchData(search: $search)';
+}
+
+/// The items of the field `search` of [SearchData].
+final class SearchDataSearch implements client.DataObject {
+  /// Creates the value.
+  const SearchDataSearch({required this.typename});
+
+  factory SearchDataSearch._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => SearchDataSearch(
+    typename: _typenameCodec.field(json, '__typename', context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<SearchDataSearch> codec =
+      client.ObjectDataCodec(SearchDataSearch._read);
+
+  static const client.DataCodec<String> _typenameCodec =
+      client.ScalarDataCodec(graphql.StringCodec());
+
+  /// The field `__typename`.
+  final String typename;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({'__typename': _typenameCodec.write(typename)});
+
+  @override
+  bool operator ==(Object other) =>
+      other is SearchDataSearch && other.typename == typename;
+
+  @override
+  int get hashCode => typename.hashCode;
+
+  @override
+  String toString() => 'SearchDataSearch(typename: $typename)';
+}
```

Create `packages/typed_graphql_codegen/test/plan/operation_text_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/operation_text.dart';

import '../support/operation_fixture.dart';
import '../support/plan_fixture.dart';

const _schema = '''
interface Root { id: ID! }
type User { id: ID! name: String }
type Query implements Root {
  id: ID!
  user: User
  users: [User!]!
}
type Subscription implements Root {
  id: ID!
  user: User
}
''';

void main() {
  String textOf(String schema, String document, [String? operationName]) {
    final fixture = PlanFixture(schema, document);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .firstWhere(
          (operation) =>
              operationName == null || operation.name?.value == operationName,
        );
    return OperationText(fixture.schema, fixture.fragments).of(operation);
  }

  test('GetUser: fields get __typename, the fragment does not', () {
    expect(
      textOf(operationSchema, operationDocument, 'GetUser'),
      r'query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){'
      r'user(id:$id){...UserCard@include(if:$full)role createdAt cursor '
      r'friends(first:2)@include(if:$withFriends){id name __typename}'
      '__typename}}fragment UserCard on User{id name}',
    );
  });

  test('FindNode: the abstract field has __typename, inline fragments not', () {
    expect(
      textOf(operationSchema, operationDocument, 'FindNode'),
      r'query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}'
      '...on Bot{model}__typename}}fragment UserCard on User{id name}',
    );
  });

  test('fragments are sorted by name and written once', () {
    expect(
      textOf(_schema, '''
query { user { ...Zeta ...Mid } }
fragment Zeta on User { ...Alpha ...Mid }
fragment Mid on User { name ...Alpha }
fragment Alpha on User { id }
'''),
      '{user{...Zeta ...Mid __typename}}'
      'fragment Alpha on User{id}'
      'fragment Mid on User{name ...Alpha}'
      'fragment Zeta on User{...Alpha ...Mid}',
    );
  });

  test('a fragment another operation spreads is not part of the text', () {
    expect(
      textOf(_schema, '''
query A { user { ...X } }
query B { user { ...Y } }
fragment X on User { id }
fragment Y on User { name }
''', 'A'),
      'query A{user{...X __typename}}fragment X on User{id}',
    );
  });

  test('a chain of 500 fragments does not overflow the stack', () {
    final document = StringBuffer('query { user { ...F0 } }\n');
    for (var index = 0; index < 499; index++) {
      document.writeln('fragment F$index on User { ...F${index + 1} }');
    }
    document.writeln('fragment F499 on User { id }');
    final String text = textOf(_schema, document.toString());
    expect(RegExp('fragment ').allMatches(text), hasLength(500));
    expect(text, endsWith('fragment F99 on User{...F100}'));
  });

  test('an existing unaliased __typename is not repeated', () {
    expect(
      textOf(_schema, 'query { user { __typename id } }'),
      '{user{__typename id}}',
    );
  });

  test('an aliased __typename does not count', () {
    expect(
      textOf(_schema, 'query { user { kind: __typename id } }'),
      '{user{kind:__typename id __typename}}',
    );
  });

  test('a fragment on an abstract type at the root adds __typename', () {
    expect(
      textOf(_schema, '''
query { ...Identified user { id } }
fragment Identified on Root { id }
'''),
      '{...Identified user{id __typename}__typename}'
      'fragment Identified on Root{id}',
    );
  });

  test('an inline fragment on an abstract type at the root adds it', () {
    expect(
      textOf(_schema, 'query { ... on Root { id } }'),
      '{...on Root{id}__typename}',
    );
  });

  test('an abstract fragment inside a root fragment adds it', () {
    expect(
      textOf(_schema, '''
query { ...Outer }
fragment Outer on Query { ...Identified }
fragment Identified on Root { id }
'''),
      '{...Outer __typename}'
      'fragment Identified on Root{id}fragment Outer on Query{...Identified}',
    );
  });

  test('an object fragment at the root adds nothing', () {
    expect(
      textOf(_schema, '''
query { ...Everything }
fragment Everything on Query { id }
'''),
      '{...Everything}fragment Everything on Query{id}',
    );
  });

  test('a subscription root is left as written', () {
    expect(
      textOf(_schema, '''
subscription { ...Identified }
fragment Identified on Root { id }
'''),
      'subscription{...Identified}fragment Identified on Root{id}',
    );
  });

  test('a mutation root gets __typename like a query', () {
    expect(
      textOf(operationSchema, operationDocument, 'RenameUser'),
      r'mutation RenameUser($id:ID!$name:String!){renameUser(id:$id name:$name)'
      '{...UserCard __typename}}fragment UserCard on User{id name}',
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/support/operation_fixture.dart`:

```dart
/// The schema SDL of the operation emitter tests.
const String operationSchema = '''
enum Role { ADMIN }
scalar DateTime
scalar Cursor
interface Node { id: ID! }
type User implements Node {
  id: ID!
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}
type Bot implements Node {
  id: ID!
  model: String
}
union SearchResult = User | Bot
input SearchBy @oneOf {
  name: String
  id: ID
}
input UserFilter {
  role: Role
  ids: [ID!]!
}
type Mutation {
  renameUser(id: ID!, name: String!): User
}
type Subscription {
  userChanged(id: ID!): User
}
type Query {
  user(id: ID!): User
  node(id: ID!): Node
  search(by: SearchBy!, filter: UserFilter, tags: [String!]): [SearchResult!]!
}
''';

/// A valid document: `GetUser`, `UserCard`, `FindNode`, `SearchAll`,
/// `RenameUser`, `UserChanged` and `Everyone`.
const String operationDocument = r'''
query GetUser($id: ID!, $withFriends: Boolean = false, $full: Boolean!) {
  user(id: $id) {
    ...UserCard @include(if: $full)
    role
    createdAt
    cursor
    friends(first: 2) @include(if: $withFriends) {
      id
      name
    }
  }
}

fragment UserCard on User {
  id
  name
}

query FindNode($id: ID!) {
  node(id: $id) {
    id
    ... on User {
      name
      ...UserCard
    }
    ... on Bot {
      model
    }
  }
}

query SearchAll($by: SearchBy!, $filter: UserFilter, $tags: [String!]) {
  search(by: $by, filter: $filter, tags: $tags) {
    __typename
  }
}

mutation RenameUser($id: ID!, $name: String!) {
  renameUser(id: $id, name: $name) {
    ...UserCard
  }
}

subscription UserChanged($id: ID!) {
  userChanged(id: $id) {
    id
    name
  }
}

query Everyone {
  node(id: "1") {
    id
  }
}
''';
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/operation_emitter_test.dart test/emit/variables_emitter_test.dart test/generator/client_generator_generate_test.dart test/plan/operation_text_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Update the package files**

In `packages/typed_graphql_codegen/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,6 +10,7 @@ environment:
   sdk: ^3.13.0
 
 dependencies:
+  crypto: ^3.0.6
   path: ^1.9.0
   typed_graphql: ^0.0.1
   yaml: ^3.1.3
```

- [ ] **Step 4: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,6 +24,12 @@ final class ClassDocumentation {
   String of(DataClassPlan plan, {String? fragmentName}) =>
       _wrapped(_sentence(plan, fragmentName));
 
+  /// The doc of the data class of [operation]: ``The data of the query
+  /// `GetUser`.``
+  String ofOperation(OperationDefinition operation) =>
+      'The data of the ${operation.operation.name} '
+      '`${operation.name?.value ?? ''}`.';
+
   String _sentence(DataClassPlan plan, String? fragmentName) =>
       switch (plan.role) {
         DataClassRole.fragment =>
```

In `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../plan/data_class_role.dart';
+import '../plan/flag_defaults.dart';
 import '../plan/planned_class.dart';
 import '../plan/planned_field.dart';
 import 'dart_string_literal.dart';
@@ -8,6 +9,7 @@ import 'dart_writer.dart';
 import 'data_class_field.dart';
 import 'fragment_decode_writer.dart';
 import 'imports.dart';
+import 'operation_decode_writer.dart';
 import 'reader_factory_writer.dart';
 import 'to_json_writer.dart';
 import 'type_mapper.dart';
@@ -28,15 +30,16 @@ final class DataClassEmitter {
   /// Writes [plan] with the class doc comment [doc].
   ///
   /// A variant implements its sealed base, which reads it and declares its
-  /// shared members; [DataClassRole.operationData] is not written here and
-  /// is a [StateError].
+  /// shared members. The data class of an operation needs the [operation];
+  /// without it, it is a [StateError].
   void emit(
     DataClassPlan plan,
     String doc,
     DartWriter writer,
-    Imports imports,
-  ) {
-    if (plan.role == DataClassRole.operationData) {
+    Imports imports, {
+    OperationDefinition? operation,
+  }) {
+    if (plan.role == DataClassRole.operationData && operation == null) {
       throw StateError('${plan.name} is a ${plan.role.name} class.');
     }
     final fields = [
@@ -46,13 +49,15 @@ final class DataClassEmitter {
       for (final field in plan.fields)
         DataClassField.of(field, mapper, imports),
     ];
-    final String noun = plan.role == DataClassRole.fragment
-        ? 'fragment'
-        : 'value';
+    final String noun = switch (plan.role) {
+      DataClassRole.fragment => 'fragment',
+      DataClassRole.operationData => 'data',
+      _ => 'value',
+    };
     final String implemented = plan.baseName ?? 'client.DataObject';
     writer.doc(doc);
     writer.block('final class ${plan.name} implements $implemented', () {
-      _members(writer, plan, fields, noun);
+      _members(writer, plan, fields, noun, operation);
     });
   }
 
@@ -69,18 +74,53 @@ final class DataClassEmitter {
     DataClassPlan plan,
     List<DataClassField> fields,
     String noun,
+    OperationDefinition? operation,
   ) {
     final String name = plan.name;
     _constructor(writer, plan, fields, noun);
     writer.line();
     _reader(writer, plan, fields);
+    _codecs(writer, plan, fields, noun);
+    final Map<String, bool> flagDefaults = operation == null
+        ? const {}
+        : const FlagDefaults().of(operation);
+    _flagDefaults(writer, flagDefaults);
+    _typename(writer, plan);
+    _fields(writer, plan, fields);
+    if (plan.role == DataClassRole.fragment) {
+      writer.line();
+      const FragmentDecodeWriter().write(writer, name);
+    } else if (operation != null) {
+      writer.line();
+      const OperationDecodeWriter().write(
+        writer,
+        name,
+        operation,
+        flagDefaults,
+      );
+    }
+    writer.line();
+    _toJson(writer, plan, fields);
+    writer.line();
+    const ValueMembers().write(writer, name, [
+      for (final field in fields) field.valueMember,
+      if (plan.holderName != null) const ValueMember('fragments', false),
+    ]);
+  }
+
+  void _codecs(
+    DartWriter writer,
+    DataClassPlan plan,
+    List<DataClassField> fields,
+    String noun,
+  ) {
     // The sealed base reads a variant.
     if (plan.baseName == null) {
       writer.line();
       writer.doc('Reads and writes the $noun.');
       writer.assign(
-        'static const client.DataCodec<$name> codec',
-        'client.ObjectDataCodec($name._read)',
+        'static const client.DataCodec<${plan.name}> codec',
+        'client.ObjectDataCodec(${plan.name}._read)',
       );
     }
     for (final field in fields) {
@@ -90,19 +130,6 @@ final class DataClassEmitter {
         field.type.codec,
       );
     }
-    _typename(writer, plan);
-    _fields(writer, plan, fields);
-    if (plan.role == DataClassRole.fragment) {
-      writer.line();
-      const FragmentDecodeWriter().write(writer, name);
-    }
-    writer.line();
-    _toJson(writer, plan, fields);
-    writer.line();
-    const ValueMembers().write(writer, name, [
-      for (final field in fields) field.valueMember,
-      if (plan.holderName != null) const ValueMember('fragments', false),
-    ]);
   }
 
   void _constructor(
@@ -176,6 +203,19 @@ final class DataClassEmitter {
     }
   }
 
+  void _flagDefaults(DartWriter writer, Map<String, bool> defaults) {
+    if (defaults.isEmpty) return;
+    final entries = [
+      for (final MapEntry(:key, :value) in defaults.entries)
+        '${const DartStringLiteral().of(key)}: $value',
+    ];
+    writer.line();
+    writer.assign(
+      'static const Map<String, bool> _flagDefaults',
+      '{${entries.join(', ')}}',
+    );
+  }
+
   void _typename(DartWriter writer, DataClassPlan plan) {
     if (plan.variantTypeName case final typeName?) {
       writer.line();
```

In `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,7 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../plan/data_class_role.dart';
+import '../plan/operation_text.dart';
 import '../plan/planned_class.dart';
 import '../plan/shape_planner.dart';
 import 'class_documentation.dart';
@@ -9,8 +11,10 @@ import 'fragment_holder_emitter.dart';
 import 'generated_header.dart';
 import 'imports.dart';
 import 'library_imports.dart';
+import 'operation_emitter.dart';
 import 'polymorphic_base_emitter.dart';
 import 'type_mapper.dart';
+import 'variables_emitter.dart';
 
 /// Writes the library of one document file: the classes of its fragments
 /// (spec §7 "Files").
@@ -33,24 +37,40 @@ final class DocumentLibraryEmitter {
   /// The path of the library generated from the document file [documentPath].
   String libraryPathOf(String documentPath) => '$documentPath.dart';
 
-  /// The text of the library of [documentPath], which defines [fragments] in
-  /// document order.
-  String emit(String documentPath, List<FragmentDefinition> fragments) {
+  /// The text of the library of [documentPath], which defines
+  /// [definitions] in document order.
+  String emit(String documentPath, List<ExecutableDefinition> definitions) {
     final imports = Imports();
     final body = DartWriter();
     final String libraryPath = libraryPathOf(documentPath);
     final plans = [
-      for (final fragment in fragments)
-        (fragment, planner.planFragment(fragment)),
+      for (final definition in definitions) (definition, _plan(definition)),
     ];
     final all = [for (final (_, classes) in plans) ...classes];
-    libraryImports.record(imports, libraryPath, all);
+    libraryImports.record(imports, libraryPath, all, [
+      for (final (definition, classes) in plans)
+        if (definition is OperationDefinition && classes.isNotEmpty) definition,
+    ]);
+    final text = OperationText(planner.schema, planner.fragments);
     var isFirst = true;
-    for (final (fragment, classes) in plans) {
-      for (final planned in classes) {
+    for (final (definition, classes) in plans) {
+      if (classes.isEmpty) continue;
+      void separate() {
         if (!isFirst) body.line();
         isFirst = false;
-        _write(planned, classes, fragment.name.value, body, imports);
+      }
+
+      if (definition case final OperationDefinition operation) {
+        separate();
+        OperationEmitter(text).emit(operation, classes.first.name, body);
+        if (operation.variableDefinitions.isNotEmpty) {
+          separate();
+          VariablesEmitter(mapper).emit(operation, body, imports);
+        }
+      }
+      for (final planned in classes) {
+        separate();
+        _write(planned, classes, definition, body, imports);
       }
     }
     final head = DartWriter();
@@ -60,25 +80,41 @@ final class DocumentLibraryEmitter {
     return all.isEmpty ? head.text : '${head.text}\n${body.text}';
   }
 
+  List<PlannedClass> _plan(ExecutableDefinition definition) =>
+      switch (definition) {
+        OperationDefinition() => planner.planOperation(definition),
+        FragmentDefinition() => planner.planFragment(definition),
+      };
+
   void _write(
     PlannedClass planned,
     List<PlannedClass> classes,
-    String fragmentName,
+    ExecutableDefinition definition,
     DartWriter body,
     Imports imports,
   ) {
+    final documentation = ClassDocumentation(classes);
+    final String? fragmentName = switch (definition) {
+      FragmentDefinition(:final name) => name.value,
+      OperationDefinition() => null,
+    };
     switch (planned) {
+      case DataClassPlan(role: DataClassRole.operationData)
+          when definition is OperationDefinition:
+        DataClassEmitter(mapper).emit(
+          planned,
+          documentation.ofOperation(definition),
+          body,
+          imports,
+          operation: definition,
+        );
       case final DataClassPlan plan:
-        final doc = ClassDocumentation(
-          classes,
-        ).of(plan, fragmentName: fragmentName);
+        final doc = documentation.of(plan, fragmentName: fragmentName);
         DataClassEmitter(mapper).emit(plan, doc, body, imports);
       case final FragmentHolderPlan plan:
         const FragmentHolderEmitter().emit(plan, body);
       case final PolymorphicBasePlan plan:
-        final doc = ClassDocumentation(
-          classes,
-        ).ofBase(plan, fragmentName: fragmentName);
+        final doc = documentation.ofBase(plan, fragmentName: fragmentName);
         PolymorphicBaseEmitter(mapper).emit(plan, doc, body, imports);
     }
   }
```

In `packages/typed_graphql_codegen/lib/src/emit/input_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,6 +42,27 @@ final class const InputField({
     );
   }
 
+  /// The plan of the operation variable [variable]: optional when it is
+  /// nullable or has a default value.
+  factory InputField.variable(
+    VariableDefinition variable,
+    TypeMapper mapper,
+    Imports imports,
+  ) {
+    final String name = variable.variable.name.value;
+    final Value? defaultValue = variable.defaultValue;
+    final String printed = defaultValue == null
+        ? ''
+        : '; its default is `${_printed(defaultValue)}`';
+    return InputField(
+      graphQLName: name,
+      dartName: dartNameOf(name),
+      value: mapper.of(variable.type, imports),
+      isOptional: variable.type is! NonNullType || defaultValue != null,
+      doc: 'The variable `\$$name`$printed.',
+    );
+  }
+
   /// The plan of a field of a `@oneOf` input object: always given, with the
   /// non-null type, because the variant that holds it says which is given.
   factory InputField.exclusive(
@@ -82,14 +103,15 @@ final class const InputField({
     reservedMembers: DartNames.objectMembers,
   );
 
+  static String _printed(Value value) =>
+      const Printer().print(value).replaceAll(RegExp(r'\s*\n\s*'), ' ');
+
   static String _doc(InputValue input) {
     final String base = input.description ?? 'The field `${input.name}`.';
     final StringBuffer out = StringBuffer(base);
     final Value? defaultValue = input.defaultValue;
     if (defaultValue != null) {
-      final String printed = const Printer()
-          .print(defaultValue)
-          .replaceAll(RegExp(r'\s*\n\s*'), ' ');
+      final String printed = _printed(defaultValue);
       out
         ..write(base.contains('\n') ? '\n\n' : ' ')
         ..write('Its default is `$printed`.');
```

Create `packages/typed_graphql_codegen/lib/src/emit/input_field_members.dart`:

```dart
import 'dart_string_literal.dart';
import 'dart_writer.dart';
import 'input_field.dart';

/// Writes the members that input objects and operation variables share: the
/// constructor, the codecs, the fields, `toJson`, `==`, `hashCode` and
/// `toString` (spec §7 "Input objects and variables", R7.7).
///
/// {@category codegen}
final class InputFieldMembers {
  /// Creates the writer.
  const InputFieldMembers();

  static const DartStringLiteral _literal = DartStringLiteral();

  /// Writes the constructor of [name], documented with [doc]: required
  /// fields first, then the optional ones, absent by default.
  void constructor(
    String doc,
    String name,
    List<InputField> fields,
    DartWriter writer,
  ) {
    final List<String> parameters = <String>[
      for (final InputField field in fields)
        if (!field.isOptional) 'required this.${field.dartName}',
      for (final InputField field in fields)
        if (field.isOptional)
          'this.${field.dartName} = const graphql.Optional.absent()',
    ];
    writer
      ..doc(doc)
      ..items('const $name({', parameters, '});');
  }

  /// Writes the private codec of each of [fields], each followed by a blank
  /// line.
  void codecs(List<InputField> fields, DartWriter writer) {
    for (final InputField field in fields) {
      writer
        ..assign(
          'static const client.DataCodec<${field.value.type}> '
          '${field.codecName}',
          field.value.codec,
        )
        ..line();
    }
  }

  /// Writes the documented declaration of each of [fields], each followed by
  /// a blank line.
  void declarations(List<InputField> fields, DartWriter writer) {
    for (final InputField field in fields) {
      writer
        ..doc(field.docText)
        ..line('final ${field.fieldType} ${field.dartName};')
        ..line();
    }
  }

  /// Writes `toJson`, `==`, `hashCode` and `toString`, apart by blank lines.
  void valueMembers(String name, List<InputField> fields, DartWriter writer) {
    toJson(fields, writer);
    writer.line();
    equality(name, fields, writer);
    writer.line();
    toStringMember(name, fields, writer);
  }

  /// Writes `toJson`, which writes only the optional values that are present.
  void toJson(List<InputField> fields, DartWriter writer) {
    writer
      ..line('@override')
      ..line('graphql.JsonObject toJson() => graphql.JsonObject({')
      ..indented(() {
        for (final InputField field in fields) {
          final String key = _literal.of(field.graphQLName);
          final String write = '$key: ${field.codecName}.write';
          if (!field.isOptional) {
            writer.line('$write(${field.dartName}),');
            continue;
          }
          final String test =
              'if (${field.dartName} case '
              'graphql.Present(:final value))';
          final String entry = '$write(value),';
          if (writer.fits('$test $entry')) {
            writer.line('$test $entry');
          } else {
            writer.line(test);
            writer.indented(() => writer.line(entry));
          }
        }
      })
      ..line('});');
  }

  /// Writes `==` and `hashCode`; lists compare by item.
  void equality(String name, List<InputField> fields, DartWriter writer) {
    // The parameter keeps the name `other` (avoid_renaming_method_parameters);
    // a field of that name is read through `this`.
    String own(InputField field) =>
        field.dartName == 'other' ? 'this.other' : field.dartName;
    writer
      ..line('@override')
      ..arrowJoined('bool operator ==(Object other)', <String>[
        'other is $name',
        for (final InputField field in fields)
          if (field.holdsList)
            'const client.DataEquality().equals(other.${field.dartName}, '
                '${own(field)})'
          else
            'other.${field.dartName} == ${own(field)}',
      ], '&&')
      ..line()
      ..line('@override');
    final List<String> hashes = <String>[
      for (final InputField field in fields)
        if (field.holdsList)
          'const client.DataEquality().hash(${field.dartName})'
        else
          '${field.dartName}.hashCode',
    ];
    if (hashes.length == 1) {
      writer.arrow('int get hashCode', hashes.single);
    } else {
      writer.items('int get hashCode => Object.hashAll([', hashes, ']);');
    }
  }

  /// Writes `toString`, wrapped at 80 columns.
  void toStringMember(String name, List<InputField> fields, DartWriter writer) {
    final String escaped = name.replaceAll(r'$', r'\$');
    final List<String> tokens = <String>[
      for (final InputField field in fields)
        '${field.dartName.replaceAll(r'$', r'\$')}: ${field.interpolation}',
    ];
    writer.line('@override');
    final String single = "'$escaped(${tokens.join(', ')})'";
    if (writer.fits('String toString() => $single;')) {
      writer.line('String toString() => $single;');
      return;
    }
    writer.line('String toString() =>');
    writer.indented(() {
      writer.indented(() => _writeSplitLiteral(escaped, tokens, writer));
    });
  }

  void _writeSplitLiteral(String name, List<String> tokens, DartWriter writer) {
    StringBuffer current = StringBuffer('$name(');
    final List<String> lines = <String>[];
    for (final (int index, String token) in tokens.indexed) {
      final String piece = '$token${index == tokens.length - 1 ? ')' : ', '}';
      if (!writer.fits("'$current$piece';") && current.isNotEmpty) {
        lines.add('$current');
        current = StringBuffer();
      }
      current.write(piece);
    }
    lines.add('$current');
    for (final (int index, String text) in lines.indexed) {
      writer.line("'$text'${index == lines.length - 1 ? ';' : ''}");
    }
  }
}
```

In `packages/typed_graphql_codegen/lib/src/emit/library_imports.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -29,12 +29,13 @@ final class LibraryImports {
   final Map<String, String> fragmentLibraries;
 
   /// Records into [imports] what the library at [libraryPath] needs for
-  /// [classes]. The imports of custom scalars are recorded while the classes
-  /// are written.
+  /// [classes] and the variables of [operations]. The imports of custom
+  /// scalars are recorded while the classes are written.
   void record(
     Imports imports,
     String libraryPath,
     List<PlannedClass> classes,
+    List<OperationDefinition> operations,
   ) {
     if (classes.isEmpty) {
       return;
@@ -48,7 +49,8 @@ final class LibraryImports {
       prefix: 'client',
     );
     final targets = <String>{
-      if (_usesSchemaTypes(classes)) schemaTypesPath,
+      if (_usesSchemaTypes(classes) || _variablesUseSchemaTypes(operations))
+        schemaTypesPath,
       for (final fragment in _spreadFragments(classes))
         ?fragmentLibraries[fragment],
     }..remove(libraryPath);
@@ -59,14 +61,23 @@ final class LibraryImports {
     }
   }
 
+  bool _variablesUseSchemaTypes(List<OperationDefinition> operations) =>
+      operations.any(
+        (operation) => operation.variableDefinitions.any(
+          (variable) => _isSchemaType(variable.type),
+        ),
+      );
+
+  bool _isSchemaType(TypeRef type) => switch (schema.namedTypeOf(type)) {
+    EnumType() || InputObjectType() => true,
+    _ => false,
+  };
+
   bool _usesSchemaTypes(List<PlannedClass> classes) => classes.any(
     (planned) => switch (planned) {
       DataClassPlan(:final fields) ||
       PolymorphicBasePlan(sharedFields: final fields) => fields.any(
-        (field) => switch (schema.namedTypeOf(field.type)) {
-          EnumType() || InputObjectType() => true,
-          _ => false,
-        },
+        (field) => _isSchemaType(field.type),
       ),
       FragmentHolderPlan() => false,
     },
```

Create `packages/typed_graphql_codegen/lib/src/emit/operation_decode_writer.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'dart_writer.dart';

/// Writes the static `decode` of an operation's data class, the entry point
/// for the `data` of a response.
///
/// {@category codegen}
final class OperationDecodeWriter {
  /// Creates the writer.
  const OperationDecodeWriter();

  /// Writes `decode` for the class [className], the data of [operation]; a
  /// non-empty [flagDefaults] is passed to the context.
  void write(
    DartWriter writer,
    String className,
    OperationDefinition operation,
    Map<String, bool> flagDefaults,
  ) {
    final String context = flagDefaults.isEmpty
        ? 'client.DataContext(variables)'
        : 'client.DataContext(variables, _flagDefaults)';
    writer
      ..doc(
        'Reads [json], the `data` of a response to the '
        '${operation.operation.name} sent with\n[variables].',
      )
      ..line('static graphql.DecodeResult<$className> decode(')
      ..indented(() {
        writer
          ..line('graphql.JsonObject json, {')
          ..line('graphql.JsonObject? variables,');
      })
      ..line('}) => codec.decode(json, $context);');
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart`:

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/class_names.dart';
import '../plan/operation_text.dart';
import 'dart_names.dart';
import 'dart_string_literal.dart';
import 'dart_writer.dart';

/// Writes the class of an operation (spec §7 "Operation classes and
/// metadata", R7.9): its document, its variables and how it reads its data.
///
/// {@category codegen}
final class OperationEmitter {
  /// Creates the emitter; [text] writes the documents sent.
  const OperationEmitter(this.text);

  /// The writer of document texts.
  final OperationText text;

  static const ClassNames _names = ClassNames();

  /// Writes the class of [operation], whose data class is named
  /// [dataName], to [writer].
  void emit(OperationDefinition operation, String dataName, DartWriter writer) {
    final String operationName = operation.name?.value ?? '';
    final String kind = operation.operation.name;
    final String name = _names.operation(operationName, operation.operation);
    final String base = 'client.GraphQL${const DartNames().capitalized(kind)}';
    final bool hasVariables = operation.variableDefinitions.isNotEmpty;
    writer.doc('The $kind `$operationName`.');
    final String header = 'final class $name';
    final String extension = 'extends $base<$dataName> {';
    if (writer.fits('$header $extension')) {
      writer.line('$header $extension');
    } else {
      writer.line(header);
      writer.indented(() => writer.indented(() => writer.line(extension)));
    }
    writer.indented(() {
      _constructor(writer, name, kind, hasVariables);
      writer.line();
      _document(writer, operation, operationName);
      if (hasVariables) {
        writer.line();
        writer.doc('The variables the $kind is sent with.');
        writer.line('final ${_names.variables(operationName)} variables;');
      }
      _overrides(writer, dataName, hasVariables);
    });
    writer.line('}');
  }

  void _overrides(DartWriter writer, String dataName, bool hasVariables) {
    final overrides = [
      (
        'client.OperationDocument get document',
        'operationDocument',
      ),
      (
        'graphql.JsonObject get variablesJson',
        hasVariables ? 'variables.toJson()' : 'graphql.JsonObject(const {})',
      ),
      (
        'graphql.DecodeResult<$dataName> decodeData(graphql.JsonObject data)',
        hasVariables
            ? '$dataName.decode(data, variables: variablesJson)'
            : '$dataName.decode(data)',
      ),
    ];
    for (final (head, expression) in overrides) {
      writer.line();
      writer.line('@override');
      writer.arrow(head, expression);
    }
  }

  void _constructor(
    DartWriter writer,
    String name,
    String kind,
    bool hasVariables,
  ) {
    if (hasVariables) {
      writer.doc('Creates the $kind with its [variables].');
      writer.line('const $name(this.variables);');
    } else {
      writer.doc('Creates the $kind.');
      writer.line('const $name();');
    }
  }

  void _document(
    DartWriter writer,
    OperationDefinition operation,
    String operationName,
  ) {
    const literal = DartStringLiteral();
    final String document = text.of(operation);
    final String hash = sha256.convert(utf8.encode(document)).toString();
    writer.doc('The document of `$operationName` as it is sent.');
    writer.line('static const client.OperationDocument operationDocument =');
    writer.indented(() {
      writer.indented(() {
        writer.line('client.OperationDocument(');
        writer.indented(() {
          writer.line('name: ${literal.of(operationName)},');
          writer.line(
            'type: graphql.OperationType.${operation.operation.name},',
          );
          writer.line('text: ${literal.of(document)},');
          writer.line('sha256:');
          writer.indented(() => writer.line('${literal.of(hash)},'));
        });
        writer.line(');');
      });
    });
  }
}
```

In `packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import 'dart_string_literal.dart';
 import 'dart_writer.dart';
 import 'imports.dart';
 import 'input_field.dart';
+import 'input_field_members.dart';
 import 'type_mapper.dart';
 
 /// Writes the class of an input object that is not `@oneOf`.
@@ -32,15 +33,16 @@ final class RegularInputEmitter {
     writer
       ..doc(type.description ?? 'The input object `${type.name}`.')
       ..block('final class $name implements client.DataObject', () {
-        _writeConstructor(name, fields, writer);
+        const InputFieldMembers().constructor(
+          'Creates the input object.',
+          name,
+          fields,
+          writer,
+        );
         writer.line();
         _writeReader(name, fields, writer);
         _writeDeclarations(type, name, fields, writer);
-        _writeToJson(fields, writer);
-        writer.line();
-        _writeEquality(name, fields, writer);
-        writer.line();
-        _writeToString(name, fields, writer);
+        const InputFieldMembers().valueMembers(name, fields, writer);
       });
   }
 
@@ -58,38 +60,9 @@ final class RegularInputEmitter {
         'client.ObjectDataCodec($name._read)',
       )
       ..line();
-    for (final InputField field in fields) {
-      writer
-        ..assign(
-          'static const client.DataCodec<${field.value.type}> '
-          '${field.codecName}',
-          field.value.codec,
-        )
-        ..line();
-    }
-    for (final InputField field in fields) {
-      writer
-        ..doc(field.docText)
-        ..line('final ${field.fieldType} ${field.dartName};')
-        ..line();
-    }
-  }
-
-  void _writeConstructor(
-    String name,
-    List<InputField> fields,
-    DartWriter writer,
-  ) {
-    final List<String> parameters = <String>[
-      for (final InputField field in fields)
-        if (!field.isOptional) 'required this.${field.dartName}',
-      for (final InputField field in fields)
-        if (field.isOptional)
-          'this.${field.dartName} = const graphql.Optional.absent()',
-    ];
-    writer
-      ..doc('Creates the input object.')
-      ..items('const $name({', parameters, '});');
+    const InputFieldMembers()
+      ..codecs(fields, writer)
+      ..declarations(fields, writer);
   }
 
   void _writeReader(String name, List<InputField> fields, DartWriter writer) {
@@ -140,98 +113,4 @@ final class RegularInputEmitter {
     });
     writer.line(');');
   }
-
-  void _writeToJson(List<InputField> fields, DartWriter writer) {
-    writer
-      ..line('@override')
-      ..line('graphql.JsonObject toJson() => graphql.JsonObject({')
-      ..indented(() {
-        for (final InputField field in fields) {
-          final String key = _literal.of(field.graphQLName);
-          final String write = '$key: ${field.codecName}.write';
-          if (!field.isOptional) {
-            writer.line('$write(${field.dartName}),');
-            continue;
-          }
-          final String test =
-              'if (${field.dartName} case '
-              'graphql.Present(:final value))';
-          final String entry = '$write(value),';
-          if (writer.fits('$test $entry')) {
-            writer.line('$test $entry');
-          } else {
-            writer.line(test);
-            writer.indented(() => writer.line(entry));
-          }
-        }
-      })
-      ..line('});');
-  }
-
-  void _writeEquality(String name, List<InputField> fields, DartWriter writer) {
-    // The parameter keeps the name `other` (avoid_renaming_method_parameters);
-    // a field of that name is read through `this`.
-    String own(InputField field) =>
-        field.dartName == 'other' ? 'this.other' : field.dartName;
-    writer
-      ..line('@override')
-      ..arrowJoined('bool operator ==(Object other)', <String>[
-        'other is $name',
-        for (final InputField field in fields)
-          if (field.holdsList)
-            'const client.DataEquality().equals(other.${field.dartName}, '
-                '${own(field)})'
-          else
-            'other.${field.dartName} == ${own(field)}',
-      ], '&&')
-      ..line()
-      ..line('@override');
-    final List<String> hashes = <String>[
-      for (final InputField field in fields)
-        if (field.holdsList)
-          'const client.DataEquality().hash(${field.dartName})'
-        else
-          '${field.dartName}.hashCode',
-    ];
-    if (hashes.length == 1) {
-      writer.arrow('int get hashCode', hashes.single);
-    } else {
-      writer.items('int get hashCode => Object.hashAll([', hashes, ']);');
-    }
-  }
-
-  void _writeToString(String name, List<InputField> fields, DartWriter writer) {
-    final String escaped = name.replaceAll(r'$', r'\$');
-    final List<String> tokens = <String>[
-      for (final InputField field in fields)
-        '${field.dartName.replaceAll(r'$', r'\$')}: ${field.interpolation}',
-    ];
-    writer.line('@override');
-    final String single = "'$escaped(${tokens.join(', ')})'";
-    if (writer.fits('String toString() => $single;')) {
-      writer.line('String toString() => $single;');
-      return;
-    }
-    writer.line('String toString() =>');
-    writer.indented(() {
-      writer.indented(() => _writeSplitLiteral(escaped, tokens, writer));
-    });
-  }
-
-  void _writeSplitLiteral(String name, List<String> tokens, DartWriter writer) {
-    StringBuffer current = StringBuffer('$name(');
-    final List<String> lines = <String>[];
-    for (final (int index, String token) in tokens.indexed) {
-      final String piece = '$token${index == tokens.length - 1 ? ')' : ', '}';
-      if (!writer.fits("'$current$piece';") && current.isNotEmpty) {
-        lines.add('$current');
-        current = StringBuffer();
-      }
-      current.write(piece);
-    }
-    lines.add('$current');
-    for (final (int index, String text) in lines.indexed) {
-      writer.line("'$text'${index == lines.length - 1 ? ';' : ''}");
-    }
-  }
 }
```

Create `packages/typed_graphql_codegen/lib/src/emit/variables_emitter.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/class_names.dart';
import 'dart_writer.dart';
import 'imports.dart';
import 'input_field.dart';
import 'input_field_members.dart';
import 'type_mapper.dart';

/// Writes the variables class of an operation (spec §7 "Input objects and
/// variables", R7.7): only written, never read.
///
/// {@category codegen}
final class VariablesEmitter {
  /// Creates the emitter; [mapper] maps the variable types.
  const VariablesEmitter(this.mapper);

  /// The mapper of variable types.
  final TypeMapper mapper;

  /// Writes the variables class of [operation] to [writer].
  void emit(OperationDefinition operation, DartWriter writer, Imports imports) {
    final String operationName = operation.name?.value ?? '';
    final String name = const ClassNames().variables(operationName);
    final fields = [
      for (final definition in operation.variableDefinitions)
        InputField.variable(definition, mapper, imports),
    ];
    const members = InputFieldMembers();
    writer.doc(
      'The variables of the ${operation.operation.name} `$operationName`.',
    );
    writer.block('final class $name implements client.DataObject', () {
      members.constructor('Creates the variables.', name, fields, writer);
      writer.line();
      members.codecs(fields, writer);
      members.declarations(fields, writer);
      members.valueMembers(name, fields, writer);
    });
  }
}
```

In `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -27,13 +27,14 @@ final class DocumentLibraries {
   List<GeneratedFile> generate() {
     final files = project.documents.files;
     final map = project.documents.sourceMap;
-    final fragmentsByFile = <int, List<FragmentDefinition>>{};
+    final definitionsByFile = <int, List<ExecutableDefinition>>{};
     final fragmentsByName = <String, FragmentDefinition>{};
     final libraryOf = <String, String>{};
     for (final definition in project.document.document.definitions) {
-      if (definition is! FragmentDefinition) continue;
+      if (definition is! ExecutableDefinition) continue;
       final index = map.fileIndexAt(definition.start);
-      fragmentsByFile.putIfAbsent(index, () => []).add(definition);
+      definitionsByFile.putIfAbsent(index, () => []).add(definition);
+      if (definition is! FragmentDefinition) continue;
       fragmentsByName[definition.name.value] = definition;
       libraryOf[definition.name.value] = '${files[index].path}.dart';
     }
@@ -46,7 +47,7 @@ final class DocumentLibraries {
       for (final (int index, file) in files.indexed)
         GeneratedFile(
           emitter.libraryPathOf(file.path),
-          emitter.emit(file.path, fragmentsByFile[index] ?? const []),
+          emitter.emit(file.path, definitionsByFile[index] ?? const []),
         ),
     ];
   }
```

In `packages/typed_graphql_codegen/lib/src/plan/class_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,5 @@
+import 'package:typed_graphql/typed_graphql.dart';
+
 import '../emit/dart_names.dart';
 
 /// Names the classes generated for operations, fragments and selections.
@@ -11,6 +13,15 @@ final class ClassNames {
   String operationData(String operationName) =>
       '${_names.typeName(operationName)}Data';
 
+  /// The class of an operation: `GetUser` is `GetUserQuery`, or
+  /// `GetUserMutation` or `GetUserSubscription`.
+  String operation(String operationName, OperationType type) =>
+      '${_names.typeName(operationName)}${_names.capitalized(type.name)}';
+
+  /// The class of an operation's variables: `GetUser` is `GetUserVariables`.
+  String variables(String operationName) =>
+      '${_names.typeName(operationName)}Variables';
+
   /// The class of a fragment definition.
   String fragment(String fragmentName) => _names.typeName(fragmentName);
 
```

Create `packages/typed_graphql_codegen/lib/src/plan/flag_defaults.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The defaults of the Boolean variables of an operation, which decide a
/// fragment under `@include` or `@skip` when the variable is not sent
/// (spec §6 "Fragments").
final class FlagDefaults {
  /// Creates the reader.
  const FlagDefaults();

  /// The `true` or `false` default of each `Boolean` or `Boolean!` variable
  /// of [operation] that has one, by variable name, in definition order.
  Map<String, bool> of(OperationDefinition operation) => {
    for (final definition in operation.variableDefinitions)
      if (_isBoolean(definition.type))
        if (definition.defaultValue case BooleanValue(:final value))
          definition.variable.name.value: value,
  };

  bool _isBoolean(TypeRef type) => switch (type) {
    NonNullType(type: final inner) => _isBoolean(inner),
    NamedType(name: Name(value: 'Boolean')) => true,
    ListType() || NamedType() => false,
  };
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'typename_adder.dart';

/// Writes the document text an operation is sent with (R7.9): the operation
/// and every fragment it spreads, minified, with `__typename` added.
final class OperationText {
  /// Creates the writer for the project's [schema] and [fragments] by name.
  const OperationText(this.schema, this.fragments);

  /// The schema, which tells abstract types from object types.
  final Schema schema;

  /// The project's fragment definitions, by name.
  final Map<String, FragmentDefinition> fragments;

  /// The minified text of [operation] followed by the fragments it spreads,
  /// directly or not, sorted by name.
  ///
  /// The operation's own selection set gets `__typename` when it reads the
  /// type of an abstract selection; a subscription cannot select it and is
  /// left as written.
  String of(OperationDefinition operation) {
    const adder = TypenameAdder();
    final OperationDefinition root = _withRootTypename(operation, adder);
    final document = Document([root, ..._spread(operation)]);
    final Node transformed = adder.transform(document) ?? document;
    return const Printer(isMinified: true).print(transformed);
  }

  List<FragmentDefinition> _spread(OperationDefinition operation) {
    final visited = <String>{};
    final found = <FragmentDefinition>[];
    final pending = _spreadNames(operation);
    while (pending.isNotEmpty) {
      final String name = pending.removeLast();
      final FragmentDefinition? fragment = fragments[name];
      if (fragment == null || !visited.add(name)) continue;
      found.add(fragment);
      pending.addAll(_spreadNames(fragment));
    }
    return found..sort((a, b) => a.name.value.compareTo(b.name.value));
  }

  List<String> _spreadNames(Node definition) {
    final collector = _SpreadCollector();
    const AstWalker().walk(definition, collector);
    return collector.names;
  }

  OperationDefinition _withRootTypename(
    OperationDefinition operation,
    TypenameAdder adder,
  ) {
    if (operation.operation == OperationType.subscription ||
        !_readsAbstractType(operation.selectionSet)) {
      return operation;
    }
    return OperationDefinition(
      operation.operation,
      adder.appendTo(operation.selectionSet),
      description: operation.description,
      name: operation.name,
      variableDefinitions: operation.variableDefinitions,
      directives: operation.directives,
      start: operation.start,
      end: operation.end,
    );
  }

  // Whether the top level of [root] spreads a fragment, or has an inline
  // fragment, on an abstract type, through spread fragments too.
  bool _readsAbstractType(SelectionSet root) {
    final visited = <String>{};
    final pending = [...root.selections];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Field():
          continue;
        case InlineFragment(:final typeCondition, :final selectionSet):
          if (_isAbstract(typeCondition?.name.value)) return true;
          pending.addAll(selectionSet.selections);
        case FragmentSpread(:final name):
          final FragmentDefinition? fragment = fragments[name.value];
          if (fragment == null || !visited.add(name.value)) continue;
          if (_isAbstract(fragment.typeCondition.name.value)) return true;
          pending.addAll(fragment.selectionSet.selections);
      }
    }
    return false;
  }

  bool _isAbstract(String? typeName) =>
      switch (typeName == null ? null : schema.typeNamed(typeName)) {
        InterfaceType() || UnionType() => true,
        _ => false,
      };
}

// Collects the names of the fragments a definition spreads.
final class _SpreadCollector extends AstVisitor {
  final List<String> names = [];

  @override
  VisitAction enter(Node node) {
    if (node is FragmentSpread) names.add(node.name.value);
    return VisitAction.next;
  }
}
```

Create `packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Appends an unaliased `__typename` to the selection set of every field
/// that has one and lacks it (R7.9): the client reads the type of every
/// object from it.
///
/// Inline fragments and fragment definitions get none; the field around
/// them has it.
final class TypenameAdder extends AstTransformer {
  /// Creates the transformer.
  const TypenameAdder();

  @override
  Node? rewrite(Node node) {
    if (node case Field(:final selectionSet?)
        when !_hasTypename(selectionSet)) {
      return Field(
        node.alias,
        node.name,
        arguments: node.arguments,
        directives: node.directives,
        selectionSet: appendTo(selectionSet),
        start: node.start,
        end: node.end,
      );
    }
    return node;
  }

  /// [selectionSet] with `__typename` last.
  SelectionSet appendTo(SelectionSet selectionSet) => SelectionSet(
    [
      ...selectionSet.selections,
      Field(null, const Name('__typename')),
    ],
    start: selectionSet.start,
    end: selectionSet.end,
  );

  bool _hasTypename(SelectionSet selectionSet) => selectionSet.selections.any(
    (selection) =>
        selection is Field &&
        selection.alias == null &&
        selection.name.value == '__typename',
  );
}
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/operation_emitter_test.dart test/emit/variables_emitter_test.dart test/generator/client_generator_generate_test.dart test/plan/operation_text_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- `ClientGenerator.generate` writes the operations of each document file, in
  document order with its fragments: the operation class (`GetUserQuery`,
  `...Mutation`, `...Subscription`) with its `operationDocument` (minified
  text of the operation and the fragments it spreads, with `__typename` added
  to every field with a selection, and its SHA-256), the variables class
  (`required` or `Optional` per variable, written only), and the data class
  with `decode(json, variables:)` and the defaults of its Boolean variables.
  Depends on `package:crypto`.
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -144,9 +144,12 @@ enum Role {
 '''),
     documents: const [ProjectFile('role.graphql', 'query GetRole { role }')],
   );
+  final declaration = RegExp(r'^(?:final|sealed) class (\w+)', multiLine: true);
   for (final file in generation.files) {
-    print('// ${file.path}');
-    print(file.text);
+    final names = [
+      for (final match in declaration.allMatches(file.text)) match[1],
+    ];
+    print('${file.path}: ${names.join(', ')}');
   }
 }
 ```
@@ -154,77 +157,21 @@ enum Role {
 It prints:
 
 ```text
-// lib/schema.graphql.dart
-// GENERATED CODE - DO NOT MODIFY BY HAND.
-// Generated by typed_graphql_codegen from schema.graphql.
-// dart format off
-
-import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
-
-/// The enum `Role`.
-sealed class Role implements client.DataEnum {
-  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
-  /// this code does not know.
-  factory Role.parse(String raw) {
-    for (final value in RoleKnown.values) {
-      if (value.raw == raw) return value;
-    }
-    return RoleUnknown(raw);
-  }
-
-  /// Reads and writes the values of `Role`.
-  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
-}
-
-/// The values of [Role] this code knows.
-enum RoleKnown implements Role {
-  /// `ADMIN`.
-  admin('ADMIN'),
-
-  /// `GUEST`.
-  @Deprecated('Use ADMIN.')
-  guest('GUEST');
-
-  const RoleKnown(this.raw);
-
-  @override
-  final String raw;
-}
-
-/// A value of [Role] this code does not know, such as one added to the
-/// schema after the code was generated.
-final class RoleUnknown implements Role {
-  /// Creates the value named [raw].
-  const RoleUnknown(this.raw);
-
-  @override
-  final String raw;
-
-  @override
-  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;
-
-  @override
-  int get hashCode => raw.hashCode;
-
-  @override
-  String toString() => 'RoleUnknown($raw)';
-}
-
-// role.graphql.dart
-// GENERATED CODE - DO NOT MODIFY BY HAND.
-// Generated by typed_graphql_codegen from role.graphql.
-// dart format off
+lib/schema.graphql.dart: Role, RoleUnknown
+role.graphql.dart: GetRoleQuery, GetRoleData
 ```
 
 ## Document libraries
 
 Each document file gets a library at its own path plus `.dart`
 (`lib/user.graphql` becomes `lib/user.graphql.dart`), in path order after the
-schema-types library. A document without a fragment gets a library with only
-the header. The library of a file holds the classes of the fragments defined
-in it, in document order, and imports only what they use: the runtime, custom
+schema-types library. A document without an operation or a fragment gets a
+library with only the header. The library of a file holds the classes of the
+operations and fragments defined in it, in document order, and imports only
+what they use: the runtime, custom
 scalar libraries, the schema types when a field is an enum or an input object,
-and the library of another file when a fragment spreads one defined there.
+and the library of another file when a selection spreads a fragment defined
+there.
 Imports of generated libraries are relative and unprefixed, which is safe
 because generated names are unique in the project.
 
@@ -258,6 +205,53 @@ classes select in the same way, and `fragments` when they all spread the same
 fragments; `NodeCardUnknown` keeps the `typename` it was read with. The golden
 `test/goldens/polymorphic` is analyzed and run like the other goldens.
 
+## Operations
+
+An operation `GetUser` is four things, in this order in its file: the class
+`GetUserQuery` (`GetUserMutation`, `GetUserSubscription`), the class
+`GetUserVariables` when the operation has variables, the class
+`GetUserData`, and the classes under the data.
+
+```text
+final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
+  const GetUserQuery(this.variables);
+
+  static const client.OperationDocument operationDocument =
+      client.OperationDocument(
+        name: 'GetUser',
+        type: graphql.OperationType.query,
+        text: r'query GetUser($id:ID!){user(id:$id){id __typename}}',
+        sha256: '...',
+      );
+
+  final GetUserVariables variables;
+}
+```
+
+`GetUserQuery(GetUserVariables(id: '1')).toRequest()` is the request to
+send. The `operationDocument` is the text as it is sent: the operation and
+every fragment it spreads, transitively, sorted by name and minified. It
+adds `__typename` to the selection set of every field that has one, so the
+client can read the type of any object; fragment definitions and inline
+fragments get none, because the field around them has it. The operation's
+own selection set gets it only when a fragment on an interface or a union is
+spread at its top level, as the sealed class that reads it needs. A
+subscription cannot select `__typename` at its root, so it is left as
+written. The `sha256` is the SHA-256 of the text in UTF-8, in lowercase
+hexadecimal: the id of a persisted query.
+
+The variables class has a field per variable, like an input object without a
+reader: a non-null variable without a default is `required`, any other is an
+`Optional` that is absent unless given, and `toJson` writes only the present
+ones. An operation without variables has a `const` constructor without
+arguments and no variables class.
+
+`GetUserData.decode(json, variables: ...)` reads the `data` of a response.
+The variables matter only for the fragments spread under `@include` and
+`@skip`; the defaults of the operation's `Boolean` variables fill those that
+were not sent. `GetUserQuery.decodeData` passes them. The golden
+`test/goldens/operations` is analyzed and run like the other goldens.
+
 ## Schema types
 
 The file at `schema_types` holds what the documents reach: the enums and
````

- [ ] **Step 7: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/emit/class_documentation.dart packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart packages/typed_graphql_codegen/lib/src/emit/input_field.dart packages/typed_graphql_codegen/lib/src/emit/input_field_members.dart packages/typed_graphql_codegen/lib/src/emit/library_imports.dart packages/typed_graphql_codegen/lib/src/emit/operation_decode_writer.dart packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart packages/typed_graphql_codegen/lib/src/emit/regular_input_emitter.dart packages/typed_graphql_codegen/lib/src/emit/variables_emitter.dart packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart packages/typed_graphql_codegen/lib/src/plan/class_names.dart packages/typed_graphql_codegen/lib/src/plan/flag_defaults.dart packages/typed_graphql_codegen/lib/src/plan/operation_text.dart packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart packages/typed_graphql_codegen/pubspec.yaml packages/typed_graphql_codegen/test/emit/operation_emitter_test.dart packages/typed_graphql_codegen/test/emit/variables_emitter_test.dart packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/input/lib/user.graphql packages/typed_graphql_codegen/test/goldens/operations/input/lib/user_mutations.graphql packages/typed_graphql_codegen/test/goldens/operations/input/lib/user_subscriptions.graphql packages/typed_graphql_codegen/test/goldens/operations/input/schema.graphql packages/typed_graphql_codegen/test/goldens/operations/input/typed_graphql.yaml packages/typed_graphql_codegen/test/goldens/operations/output/lib/schema.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/output/lib/user.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_mutations.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_subscriptions.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/support/bin/round_trip.dart.txt packages/typed_graphql_codegen/test/goldens/operations/support/packages/scalar_codecs/lib/scalar_codecs.dart.txt packages/typed_graphql_codegen/test/goldens/operations/support/packages/scalar_codecs/pubspec.yaml.txt packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden packages/typed_graphql_codegen/test/plan/operation_text_test.dart packages/typed_graphql_codegen/test/support/operation_fixture.dart
git commit -q -m "feat(typed_graphql_codegen): generate operation classes, variables and documents" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Check generated names and write the persisted-operations manifest

Classes, members and file paths of operations and fragments are registered with the schema types (`DocumentNameChecker`), so a collision is a `GQL507` at its place. A subscription whose root needs `__typename` is a `GQL504` (`SubscriptionRootRule`; the predicate `RootTypename` is shared with the document text). `persisted_operations` writes the Apollo manifest (`PersistedManifest`) as the last file.

Commit on the branch: `69273de`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart`, `packages/typed_graphql_codegen/lib/src/generator/persisted_manifest.dart`, `packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart`, `packages/typed_graphql_codegen/lib/src/plan/root_typename.dart`
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`, `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart`, `packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart`, `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart`, `packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart`, `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`
- Test: `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, `packages/typed_graphql_codegen/test/generator/document_names_test.dart`, `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, `packages/typed_graphql_codegen/test/generator/persisted_manifest_test.dart`, `packages/typed_graphql_codegen/test/golden_test.dart`, `packages/typed_graphql_codegen/test/goldens/operations/input/typed_graphql.yaml`, `packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden`

**Interfaces:**
- Consumes: Tasks 1-6; M10b `GeneratedNames`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// generator/document_libraries.dart
  DocumentLibraries(this.project, this.mapper, this.schemaTypesPath)
  final ShapePlanner planner
  OperationText get operationText

// generator/document_name_checker.dart
final class DocumentNameChecker
  const DocumentNameChecker(this.project, this.planner, this.names)
  final ClientProject project
  final ShapePlanner planner
  final GeneratedNames names
  void check()

// generator/generated_names.dart
  List<Diagnostic> get diagnostics
  void registerFile(String path, String declarer, SourceSpan? span)
  void registerMembers(

// generator/persisted_manifest.dart
final class PersistedManifest
  const PersistedManifest(this.text)
  final OperationText text
  String of(Document document)

// generator/rules/subscription_root_rule.dart
final class const SubscriptionRootRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _SubscriptionRoot(final ValidationContext context)
  VisitAction enter(Node node)

// plan/operation_text.dart
  String hashOf(String text)

// plan/planned_field.dart
  final Field? node

// plan/planned_fragment.dart
  final FragmentSpread? spread

// plan/root_typename.dart
final class RootTypename
  const RootTypename(this.schema, this.fragmentNamed)
  final Schema schema
  final FragmentDefinition? Function(String name) fragmentNamed
  bool isNeededBy(SelectionSet root)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:test/test.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_codegen/src/generator/rules/named_operations_rule.dart';
+import 'package:typed_graphql_codegen/src/generator/rules/subscription_root_rule.dart';
 import 'package:typed_graphql_codegen/src/generator/rules/unsupported_directives_rule.dart';
 import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
 
@@ -246,6 +247,7 @@ scalars:
             if (!dropped.contains(rule.runtimeType)) rule.runtimeType,
           NamedOperationsRule,
           UnsupportedDirectivesRule,
+          SubscriptionRootRule,
         ],
       );
     });
```

Create `packages/typed_graphql_codegen/test/generator/document_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
interface Node { id: ID! }
type Query implements Node {
  id: ID!
  hello: String
  user(a: ID, b: ID): User
}
type Subscription implements Node {
  id: ID!
  changed: User
}
type User {
  id: ID!
  name: String
}
''');

void main() {
  List<String> check(
    List<ProjectFile> documents, {
    String config = 'schema: schema.graphql\n',
  }) {
    final parsed = CodegenConfig.parse(config, path: 'typed_graphql.yaml');
    if (parsed is! ConfigSuccess) fail('expected success, got $parsed');
    final diagnostics = ClientGenerator(
      parsed.config,
    ).check(schema: _schema, documents: documents);
    return [
      for (final diagnostic in diagnostics)
        [
          '$diagnostic',
          for (final place in diagnostic.related) 'also $place',
        ].join(' | '),
    ];
  }

  group('class names', () {
    test('an operation class and a fragment class with one name', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', 'query A { hello }'),
          ProjectFile('lib/b.graphql', 'fragment AQuery on Query { hello }'),
        ]),
        [
          "lib/b.graphql:1:10: error GQL507: The generated name 'AQuery' is "
              "declared twice: by the operation 'A' and by the fragment "
              "'AQuery'. | also lib/a.graphql:1:7",
        ],
      );
    });

    test('a nested class and a fragment class with one name', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', 'query Get { data: user { id } }'),
          ProjectFile('lib/b.graphql', 'fragment GetDataData on User { id }'),
        ]),
        [
          'lib/b.graphql:1:10: error GQL507: The generated name '
              "'GetDataData' is declared twice: by the operation 'Get' and by "
              "the fragment 'GetDataData'. | also lib/a.graphql:1:13",
        ],
      );
    });

    test('a variables class and a fragment class with one name', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            r'query A($a: ID) { user(a: $a) { id } }',
          ),
          ProjectFile('lib/b.graphql', 'fragment AVariables on User { id }'),
        ]).single,
        startsWith('lib/b.graphql:1:10: error GQL507: The generated name '),
      );
    });
  });

  group('members', () {
    test('two fields of one data class with one Dart name', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'query Get { user { user_name: name userName: name } }',
          ),
        ]),
        [
          'lib/a.graphql:1:36: error GQL507: The generated member '
              "'userName' of 'GetDataUser' is declared twice: by the field "
              "'user_name' and by the field 'userName'. | also "
              'lib/a.graphql:1:20',
        ],
      );
    });

    test('two fragments of one holder with one accessor, and as classes', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'query Get { user { ...UserCard ...userCard } }',
          ),
          ProjectFile(
            'lib/b.graphql',
            'fragment UserCard on User { id }\n'
                'fragment userCard on User { id }',
          ),
        ]),
        [
          'lib/a.graphql:1:32: error GQL507: The generated member '
              "'userCard' of 'GetDataUserFragments' is declared twice: by the "
              "fragment 'UserCard' and by the fragment 'userCard'. | also "
              'lib/a.graphql:1:20',
          "lib/b.graphql:2:10: error GQL507: The generated name 'UserCard' "
              "is declared twice: by the fragment 'UserCard' and by the "
              "fragment 'userCard'. | also lib/b.graphql:1:10",
        ],
      );
    });

    test('two variables with one Dart name', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            r'query Get($a_b: ID, $aB: ID) { user(a: $a_b, b: $aB) { id } }',
          ),
        ]),
        [
          "lib/a.graphql:1:21: error GQL507: The generated member 'aB' of "
              "'GetVariables' is declared twice: by the variable 'a_b' and by "
              "the variable 'aB'. | also lib/a.graphql:1:11",
        ],
      );
    });
  });

  group('files', () {
    test('a document library at the path of the schema types', () {
      expect(
        check(const [
          ProjectFile('lib/schema.graphql', 'query A { hello }'),
        ]),
        [
          'lib/schema.graphql:1:1: error GQL507: The generated file '
              "'lib/schema.graphql.dart' is written twice: by the schema "
              "types and by the document 'lib/schema.graphql'.",
        ],
      );
    });
  });

  group('the subscription root', () {
    const document = ProjectFile('lib/a.graphql', '''
subscription OnNode { ...NodeCard }
fragment NodeCard on Node { id }
''');

    test('a fragment on an abstract type is a GQL504 at the spread', () {
      expect(check(const [document]), [
        "lib/a.graphql:1:23: error GQL504: The subscription 'OnNode' spreads "
            "the fragment 'NodeCard' on the abstract type 'Node' at its root, "
            "where '__typename' cannot be selected.",
      ]);
    });

    test('an inline fragment on an abstract type is a GQL504 too', () {
      expect(
        check(const [
          ProjectFile(
            'lib/a.graphql',
            'subscription OnNode { ... on Node { id } }',
          ),
        ]).single,
        contains("has an inline fragment on the abstract type 'Node'"),
      );
    });

    test('the same spread in a query is fine', () {
      expect(
        check(const [
          ProjectFile('lib/a.graphql', '''
query Q { ...NodeCard }
fragment NodeCard on Node { id }
'''),
        ]),
        isEmpty,
      );
    });
  });
}
```

In `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -50,6 +50,44 @@ void main() {
     expect(names.diagnostics.single.code, DiagnosticCode.reservedTypeName);
   });
 
+  test(
+    'problems are ordered by file and offset, those without a place last',
+    () {
+      final other = Source('0123456789', name: 'a.graphql');
+      final names = GeneratedNames()
+        ..register('A', 'the first', null)
+        ..register('A', 'the second', null)
+        ..register('B', 'the first', second)
+        ..register('B', 'the second', second)
+        ..register('C', 'the first', SourceSpan(other, 9, 9))
+        ..register('C', 'the second', SourceSpan(other, 9, 9))
+        ..register('D', 'the first', first)
+        ..register('D', 'the second', first);
+      expect(
+        [
+          for (final diagnostic in names.diagnostics)
+            diagnostic.message.split(' ')[3],
+        ],
+        ["'C'", "'D'", "'B'", "'A'"],
+      );
+    },
+  );
+
+  test('a file written twice is a GQL507 at the second writer', () {
+    final names = GeneratedNames()
+      ..registerFile('lib/a.dart', 'the schema types', null)
+      ..registerFile('lib/a.dart', "the document 'lib/a'", first);
+    expect(names.diagnostics, [
+      Diagnostic(
+        .generatedNameCollision,
+        .error,
+        "The generated file 'lib/a.dart' is written twice: by the schema "
+        "types and by the document 'lib/a'.",
+        span: first,
+      ),
+    ]);
+  });
+
   test('distinct ordinary names are fine', () {
     final names = GeneratedNames()
       ..register('Role', "the enum 'Role'", first)
@@ -101,7 +139,7 @@ type Query { a: Int }
           'enum Status { NOT_FOUND notFound OK }\ntype Query { a: Int }',
         ),
         [
-          "The generated member name 'notFound' of the enum 'Status' is "
+          "The generated member 'notFound' of the enum 'Status' is "
               "declared twice: by the value 'NOT_FOUND' and by the value "
               "'notFound'.",
         ],
@@ -129,7 +167,7 @@ type Query { a: Int }
       expect(diagnostic.code, DiagnosticCode.generatedNameCollision);
       expect(
         diagnostic.message,
-        "The generated member name 'firstName' of the input object 'In' is "
+        "The generated member 'firstName' of the input object 'In' is "
         "declared twice: by the field 'first_name' and by the field "
         "'firstName'.",
       );
```

Create `packages/typed_graphql_codegen/test/generator/persisted_manifest_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
type Query {
  hello: String
  user(id: ID!): User
}
type User {
  id: ID!
}
''');

const _documents = [
  ProjectFile(
    'lib/b.graphql',
    r'query UserById($id: ID!) { user(id: $id) { id } }',
  ),
  ProjectFile('lib/a.graphql', 'query Hello { hello }'),
];

void main() {
  CodegenConfig configOf(String text) {
    final result = CodegenConfig.parse(text, path: 'typed_graphql.yaml');
    if (result is! ConfigSuccess) fail('expected success, got $result');
    return result.config;
  }

  GenerationResult generate(String config) => ClientGenerator(
    configOf(config),
  ).generate(schema: _schema, documents: _documents);

  test('the manifest lists the operations sorted by name', () {
    final result = generate(
      'schema: schema.graphql\n'
      'persisted_operations: build/manifest.json\n',
    );
    expect(result.diagnostics, isEmpty);
    expect(
      result.files.last,
      const GeneratedFile('build/manifest.json', r'''
{
  "format": "apollo-persisted-query-manifest",
  "version": 1,
  "operations": [
    {
      "id": "f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623",
      "name": "Hello",
      "type": "query",
      "body": "query Hello{hello}"
    },
    {
      "id": "929f61823015722c0a8fcfd21c9d6ac0bb9d13a9fb519c13355294cf48357ce6",
      "name": "UserById",
      "type": "query",
      "body": "query UserById($id:ID!){user(id:$id){id __typename}}"
    }
  ]
}
'''),
    );
  });

  test('the manifest ids are the hashes the operation classes carry', () {
    final result = generate(
      'schema: schema.graphql\n'
      'persisted_operations: build/manifest.json\n',
    );
    final manifest = result.files.last.text;
    for (final file in result.files.where((f) => f.path.endsWith('.dart'))) {
      for (final match in RegExp(
        r'sha256:\s*\n?\s*\x27([0-9a-f]{64})\x27',
      ).allMatches(file.text)) {
        expect(manifest, contains(match.group(1)));
      }
    }
  });

  test('the files keep their order: schema types, libraries, manifest', () {
    final result = generate(
      'schema: schema.graphql\n'
      'persisted_operations: build/manifest.json\n',
    );
    expect(
      [for (final file in result.files) file.path],
      [
        'lib/schema.graphql.dart',
        'lib/a.graphql.dart',
        'lib/b.graphql.dart',
        'build/manifest.json',
      ],
    );
  });

  test('without the key no manifest is written', () {
    final result = generate('schema: schema.graphql\n');
    expect(
      result.files.where((file) => file.path.endsWith('.json')),
      isEmpty,
    );
  });

  test('the manifest path must end with .json', () {
    final result = CodegenConfig.parse(
      'schema: schema.graphql\npersisted_operations: build/manifest.txt\n',
      path: 'typed_graphql.yaml',
    );
    expect(
      (result as ConfigFailure).diagnostics.single.message,
      "'persisted_operations' must end with '.json'.",
    );
  });
}
```

In `packages/typed_graphql_codegen/test/golden_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -22,9 +22,12 @@ void main() {
       });
 
       test('writes the files of the goldens', () {
-        expect([
-          for (final file in result.files) file.path,
-        ], golden.goldens.keys.toList()..sort());
+        expect(
+          [
+            for (final file in result.files) file.path,
+          ]..sort(),
+          golden.goldens.keys.toList()..sort(),
+        );
       });
 
       for (final file in result.files) {
```

In `packages/typed_graphql_codegen/test/goldens/operations/input/typed_graphql.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 schema: schema.graphql
+persisted_operations: build/persisted_operations.json
 scalars:
   DateTime:
     type: DateTime
```

Create `packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden`:

```text
{
  "format": "apollo-persisted-query-manifest",
  "version": 1,
  "operations": [
    {
      "id": "5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61",
      "name": "Everyone",
      "type": "query",
      "body": "query Everyone{node(id:\"1\"){id __typename}}"
    },
    {
      "id": "7a6b96aae12daef4bcd220864fe9f9d5e3f606c6cde72b347b4c985a3939b1e0",
      "name": "FindNode",
      "type": "query",
      "body": "query FindNode($id:ID!){node(id:$id){id ...on User{name ...UserCard}...on Bot{model}__typename}}fragment UserCard on User{id name}"
    },
    {
      "id": "198ab8e735cf86b04b66c1094135e3e63cfae5a89e4b793ae58982ff95891f8e",
      "name": "GetUser",
      "type": "query",
      "body": "query GetUser($id:ID!$withFriends:Boolean=false$full:Boolean!){user(id:$id){...UserCard@include(if:$full)role createdAt cursor friends(first:2)@include(if:$withFriends){id name __typename}__typename}}fragment UserCard on User{id name}"
    },
    {
      "id": "99b64c8c80d6d3ed8be8cababb9cdafc092f7b125db944902fe6d172681f3020",
      "name": "RenameUser",
      "type": "mutation",
      "body": "mutation RenameUser($id:ID!$name:String!){renameUser(id:$id name:$name){...UserCard __typename}}fragment UserCard on User{id name}"
    },
    {
      "id": "b004d7118cec818f35b49f580a3891bfda5ae2d8168e1e1cea48eb1ed2e8e246",
      "name": "SearchAll",
      "type": "mutation",
      "body": "mutation SearchAll($by:SearchBy!$filter:UserFilter$tags:[String!]){search(by:$by filter:$filter tags:$tags){...on User{id name}...on Bot{id model}__typename}}"
    },
    {
      "id": "7a4a1e850c31f8be22e726ba1e15417b48ca868176bc43c36a64fa305be990b2",
      "name": "UserChanged",
      "type": "subscription",
      "body": "subscription UserChanged($id:ID!){userChanged(id:$id){id name __typename}}"
    }
  ]
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/generator/client_generator_test.dart test/generator/document_names_test.dart test/generator/generated_names_test.dart test/generator/persisted_manifest_test.dart test/golden_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -527,8 +527,9 @@ enum DiagnosticCode(
   /// reads; its classes are named after the operation.
   anonymousOperation('GQL503'),
 
-  /// `GQL504`: a construct the code generator does not support yet: `@defer`
-  /// or `@stream`.
+  /// `GQL504`: a construct the code generator does not support yet: `@defer`,
+  /// `@stream`, or a fragment on an abstract type spread at the root of a
+  /// subscription.
   unsupportedInDocument('GQL504'),
 
   /// `GQL505`: the configuration maps a scalar the schema does not have as a
```

In `packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,3 @@
-import 'dart:convert';
-
-import 'package:crypto/crypto.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../plan/class_names.dart';
@@ -99,7 +96,7 @@ final class OperationEmitter {
   ) {
     const literal = DartStringLiteral();
     final String document = text.of(operation);
-    final String hash = sha256.convert(utf8.encode(document)).toString();
+    final String hash = text.hashOf(document);
     writer.doc('The document of `$operationName` as it is sent.');
     writer.line('static const client.OperationDocument operationDocument =');
     writer.indented(() {
```

In `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,10 +8,13 @@ import 'client_project.dart';
 import 'client_project_loader.dart';
 import 'client_project_result.dart';
 import 'document_libraries.dart';
+import 'document_name_checker.dart';
 import 'generated_file.dart';
 import 'generated_names.dart';
 import 'generation_result.dart';
+import 'persisted_manifest.dart';
 import 'rules/named_operations_rule.dart';
+import 'rules/subscription_root_rule.dart';
 import 'rules/unsupported_directives_rule.dart';
 import 'schema_type_usage.dart';
 
@@ -59,6 +62,7 @@ final class const ClientGenerator(final CodegenConfig config) {
     UniqueInputFieldNamesRule(),
     NamedOperationsRule(),
     UnsupportedDirectivesRule(),
+    SubscriptionRootRule(),
   ];
 
   /// Checks the schema and the documents as `generate` will read them;
@@ -116,14 +120,51 @@ final class const ClientGenerator(final CodegenConfig config) {
       ],
     );
     types.forEach(names.registerSchemaType);
+    final mapper = TypeMapper(project.schema.schema, config.scalars);
+    final libraries = DocumentLibraries(project, mapper, config.schemaTypes);
+    _registerFiles(names, project);
+    DocumentNameChecker(project, libraries.planner, names).check();
     if (names.diagnostics.isNotEmpty) {
       return GenerationResult(const [], [...warnings, ...names.diagnostics]);
     }
-    final mapper = TypeMapper(project.schema.schema, config.scalars);
     final text = SchemaTypesEmitter(mapper).emit(types, source: schemaPath);
+    final manifest = config.persistedOperations;
     return GenerationResult([
       GeneratedFile(config.schemaTypes, text),
-      ...DocumentLibraries(project, mapper, config.schemaTypes).generate(),
+      ...libraries.generate(),
+      if (manifest != null)
+        GeneratedFile(
+          manifest,
+          PersistedManifest(
+            libraries.operationText,
+          ).of(project.document.document),
+        ),
     ], warnings);
   }
+
+  // Two writers of one path would overwrite each other.
+  void _registerFiles(GeneratedNames names, ClientProject project) {
+    names.registerFile(config.schemaTypes, 'the schema types', null);
+    final map = project.documents.sourceMap;
+    final firstDefinitions = <int, SourceSpan>{};
+    for (final definition in project.document.document.definitions) {
+      firstDefinitions.putIfAbsent(
+        map.fileIndexAt(definition.start),
+        () => map.translate(
+          SourceSpan(map.source, definition.start, definition.end),
+        ),
+      );
+    }
+    for (final (index, file) in project.documents.files.indexed) {
+      names.registerFile(
+        '${file.path}.dart',
+        "the document '${file.path}'",
+        firstDefinitions[index],
+      );
+    }
+    final manifest = config.persistedOperations;
+    if (manifest != null) {
+      names.registerFile(manifest, 'the persisted-operations manifest', null);
+    }
+  }
 }
```

In `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 import '../emit/document_library_emitter.dart';
 import '../emit/library_imports.dart';
 import '../emit/type_mapper.dart';
+import '../plan/operation_text.dart';
 import '../plan/shape_planner.dart';
 import 'client_project.dart';
 import 'generated_file.dart';
@@ -12,7 +13,12 @@ import 'generated_file.dart';
 final class DocumentLibraries {
   /// Creates the generator for [project]; [schemaTypesPath] is the
   /// schema-types library its libraries import.
-  const DocumentLibraries(this.project, this.mapper, this.schemaTypesPath);
+  DocumentLibraries(this.project, this.mapper, this.schemaTypesPath)
+    : planner = ShapePlanner(project.schema.schema, {
+        for (final definition in project.document.document.definitions)
+          if (definition is FragmentDefinition)
+            definition.name.value: definition,
+      });
 
   /// The project whose document files are generated.
   final ClientProject project;
@@ -23,23 +29,28 @@ final class DocumentLibraries {
   /// The path of the schema-types library.
   final String schemaTypesPath;
 
+  /// The planner of the project's classes.
+  final ShapePlanner planner;
+
+  /// The writer of the document texts the operations are sent with.
+  OperationText get operationText =>
+      OperationText(planner.schema, planner.fragments);
+
   /// A library per document file, sorted by path.
   List<GeneratedFile> generate() {
     final files = project.documents.files;
     final map = project.documents.sourceMap;
     final definitionsByFile = <int, List<ExecutableDefinition>>{};
-    final fragmentsByName = <String, FragmentDefinition>{};
     final libraryOf = <String, String>{};
     for (final definition in project.document.document.definitions) {
       if (definition is! ExecutableDefinition) continue;
       final index = map.fileIndexAt(definition.start);
       definitionsByFile.putIfAbsent(index, () => []).add(definition);
       if (definition is! FragmentDefinition) continue;
-      fragmentsByName[definition.name.value] = definition;
       libraryOf[definition.name.value] = '${files[index].path}.dart';
     }
     final emitter = DocumentLibraryEmitter(
-      ShapePlanner(project.schema.schema, fragmentsByName),
+      planner,
       mapper,
       LibraryImports(project.schema.schema, schemaTypesPath, libraryOf),
     );
```

Create `packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../emit/input_field.dart';
import '../plan/class_names.dart';
import '../plan/planned_class.dart';
import '../plan/planned_field.dart';
import '../plan/shape_planner.dart';
import 'client_project.dart';
import 'generated_names.dart';

/// Registers every class the operations and fragments of a project declare
/// in [GeneratedNames], with the members of each (spec §7 "Names").
final class DocumentNameChecker {
  /// Creates the checker of [project]'s documents, planning with [planner].
  const DocumentNameChecker(this.project, this.planner, this.names);

  /// The project whose documents are checked.
  final ClientProject project;

  /// The class planner.
  final ShapePlanner planner;

  /// The registry the names are recorded in.
  final GeneratedNames names;

  static const ClassNames _classNames = ClassNames();

  /// Registers the classes of every operation and fragment.
  void check() {
    for (final definition in project.document.document.definitions) {
      switch (definition) {
        case OperationDefinition():
          _operation(definition);
        case FragmentDefinition():
          _plans(
            "the fragment '${definition.name.value}'",
            definition.name,
            planner.planFragment(definition),
          );
        default:
      }
    }
  }

  void _operation(OperationDefinition operation) {
    final String name = operation.name?.value ?? '';
    final String declarer = "the operation '$name'";
    final SourceSpan? span = _spanOf(operation.name ?? operation);
    final classes = planner.planOperation(operation);
    if (classes.isEmpty) return;
    names.register(
      _classNames.operation(name, operation.operation),
      declarer,
      span,
    );
    if (operation.variableDefinitions.isNotEmpty) {
      final String variables = _classNames.variables(name);
      names.register(variables, declarer, span);
      names.registerMembers("'$variables'", [
        for (final definition in operation.variableDefinitions)
          (
            InputField.dartNameOf(definition.variable.name.value),
            "the variable '${definition.variable.name.value}'",
            _spanOf(definition),
          ),
      ]);
    }
    _plans(declarer, operation.name ?? operation, classes);
  }

  void _plans(String declarer, Node definitionName, List<PlannedClass> plans) {
    final SourceSpan? definitionSpan = _spanOf(definitionName);
    final spans = _fieldClassSpans(plans);
    for (final plan in plans) {
      names.register(
        plan.name,
        declarer,
        spans[plan.name] ??
            (switch (plan) {
              DataClassPlan(:final baseName?) => spans[baseName],
              FragmentHolderPlan(:final ownerName) => spans[ownerName],
              _ => null,
            }) ??
            definitionSpan,
      );
      names.registerMembers("'${plan.name}'", _membersOf(plan));
    }
  }

  // The span of the first field node each nested class is the class of.
  Map<String, SourceSpan?> _fieldClassSpans(List<PlannedClass> plans) {
    final spans = <String, SourceSpan?>{};
    for (final plan in plans) {
      final fields = switch (plan) {
        DataClassPlan(:final fields) => fields,
        PolymorphicBasePlan(:final sharedFields) => sharedFields,
        FragmentHolderPlan() => const <PlannedField>[],
      };
      for (final field in fields) {
        final className = field.className;
        final node = field.node;
        if (className != null && node != null) {
          spans.putIfAbsent(className, () => _spanOf(node));
        }
      }
    }
    return spans;
  }

  List<(String, String, SourceSpan?)> _membersOf(PlannedClass plan) =>
      switch (plan) {
        DataClassPlan(:final fields) => _fieldMembers(fields),
        PolymorphicBasePlan(:final sharedFields) => _fieldMembers(sharedFields),
        FragmentHolderPlan(:final fragments) => [
          for (final fragment in fragments)
            (
              fragment.memberName,
              "the fragment '${fragment.fragmentName}'",
              fragment.spread == null ? null : _spanOf(fragment.spread),
            ),
        ],
      };

  List<(String, String, SourceSpan?)> _fieldMembers(
    List<PlannedField> fields,
  ) => [
    for (final field in fields)
      (
        field.memberName,
        "the field '${field.responseName}'",
        field.node == null ? null : _spanOf(field.node),
      ),
  ];

  SourceSpan? _spanOf(Node? node) {
    if (node == null) return null;
    final map = project.documents.sourceMap;
    return map.translate(SourceSpan(map.source, node.start, node.end));
  }
}
```

In `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,10 +39,33 @@ final class GeneratedNames {
 
   final Set<String> _reserved;
   final Map<String, (String, SourceSpan?)> _declared = {};
+  final Map<String, (String, SourceSpan?)> _files = {};
   final List<Diagnostic> _diagnostics = [];
 
-  /// The problems found so far, in registration order.
-  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);
+  /// The problems found so far, each once: by file, then offset; the ones
+  /// without a place last, in registration order.
+  List<Diagnostic> get diagnostics {
+    final unique = <Diagnostic>[];
+    for (final diagnostic in _diagnostics) {
+      if (!unique.contains(diagnostic)) unique.add(diagnostic);
+    }
+    final indexed = unique.indexed.toList()
+      ..sort((a, b) {
+        final first = a.$2.span;
+        final second = b.$2.span;
+        if (first == null || second == null) {
+          if (first == second) return a.$1.compareTo(b.$1);
+          return first == null ? 1 : -1;
+        }
+        final byFile = first.source.name.compareTo(second.source.name);
+        if (byFile != 0) return byFile;
+        final byOffset = first.start.compareTo(second.start);
+        return byOffset != 0 ? byOffset : a.$1.compareTo(b.$1);
+      });
+    return List.unmodifiable([
+      for (final (_, diagnostic) in indexed) diagnostic,
+    ]);
+  }
 
   /// Records that [declarer] (such as `the enum 'Role'`) declares [name].
   void register(String name, String declarer, SourceSpan? span) {
@@ -74,6 +97,26 @@ final class GeneratedNames {
     );
   }
 
+  /// Records that [declarer] writes the file at [path]; a second writer is a
+  /// problem.
+  void registerFile(String path, String declarer, SourceSpan? span) {
+    final first = _files[path];
+    if (first == null) {
+      _files[path] = (declarer, span);
+      return;
+    }
+    _diagnostics.add(
+      Diagnostic(
+        .generatedNameCollision,
+        .error,
+        "The generated file '$path' is written twice: by ${first.$1} and by "
+        '$declarer.',
+        span: span,
+        related: [?first.$2],
+      ),
+    );
+  }
+
   /// Records every name the classes of the enum or input object [type]
   /// declare; any other type declares none.
   void registerSchemaType(SchemaType type) {
@@ -93,7 +136,7 @@ final class GeneratedNames {
     for (final name in [base, '${base}Known', '${base}Unknown']) {
       register(name, declarer, type.span);
     }
-    _registerMembers(declarer, [
+    registerMembers(declarer, [
       for (final value in type.values)
         (
           names.memberName(value.name, reservedMembers: DartNames.enumMembers),
@@ -115,7 +158,7 @@ final class GeneratedNames {
       }
       return;
     }
-    _registerMembers(declarer, [
+    registerMembers(declarer, [
       for (final field in type.fields)
         (
           InputField.dartNameOf(field.name),
@@ -125,9 +168,12 @@ final class GeneratedNames {
     ]);
   }
 
-  // Several GraphQL names can give one Dart member name (`RED` and `red`,
-  // `first_name` and `firstName`), which would not compile.
-  void _registerMembers(
+  /// Records the [members] (Dart name, declarer, span) of the class that
+  /// [owner] describes; two with one Dart name are a problem.
+  ///
+  /// Several GraphQL names can give one Dart member name (`RED` and `red`,
+  /// `first_name` and `firstName`), which would not compile.
+  void registerMembers(
     String owner,
     List<(String, String, SourceSpan?)> members,
   ) {
@@ -142,7 +188,7 @@ final class GeneratedNames {
         Diagnostic(
           .generatedNameCollision,
           .error,
-          "The generated member name '$name' of $owner is declared twice: "
+          "The generated member '$name' of $owner is declared twice: "
           'by ${first.$1} and by $declarer.',
           span: span,
           related: [?first.$2],
```

Create `packages/typed_graphql_codegen/lib/src/generator/persisted_manifest.dart`:

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

import '../plan/operation_text.dart';

/// Writes the persisted-operations manifest (R7.9): every operation's id,
/// name, type and the text its class sends.
final class PersistedManifest {
  /// Creates the writer; [text] gives the documents and their hashes.
  const PersistedManifest(this.text);

  /// The writer of document texts, shared with the operation classes.
  final OperationText text;

  /// The manifest of the operations in [document], sorted by name, with a
  /// final line break.
  String of(Document document) {
    final operations = [
      for (final definition in document.definitions)
        if (definition is OperationDefinition) definition,
    ]..sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
    final manifest = <String, Object?>{
      'format': 'apollo-persisted-query-manifest',
      'version': 1,
      'operations': [
        for (final operation in operations) _entry(operation),
      ],
    };
    return '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  }

  Map<String, Object?> _entry(OperationDefinition operation) {
    final String body = text.of(operation);
    return {
      'id': text.hashOf(body),
      'name': _nameOf(operation),
      'type': operation.operation.name,
      'body': body,
    };
  }

  String _nameOf(OperationDefinition operation) => operation.name?.value ?? '';
}
```

Create `packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../../plan/root_typename.dart';

/// `GQL504`: a subscription whose root reads an abstract type would need
/// `__typename` at its root, which a subscription cannot select.
final class const SubscriptionRootRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _SubscriptionRoot(context);
}

final class _SubscriptionRoot(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(operation: .subscription):
        _check(node);
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }

  void _check(OperationDefinition operation) {
    final found = RootTypename(
      context.schema,
      context.fragmentNamed,
    ).find(operation.selectionSet);
    if (found == null) return;
    final String what = found.fragmentName == null
        ? 'has an inline fragment on'
        : "spreads the fragment '${found.fragmentName}' on";
    context.report(
      .unsupportedInDocument,
      "The subscription '${operation.name?.value}' $what the abstract type "
      "'${found.typeName}' at its root, where '__typename' cannot be "
      'selected.',
      [found.selection],
    );
  }
}
```

In `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -163,7 +163,7 @@ final class _Run {
       case TypeConditionMatch.applies:
         final existing = uses[name];
         uses[name] = existing == null
-            ? FragmentUse(name, [conditions])
+            ? FragmentUse(name, [conditions], spread: spread)
             : existing.merge(conditions);
       case TypeConditionMatch.narrows:
         narrowings.add(
```

In `packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,5 @@
+import 'package:typed_graphql/typed_graphql.dart';
+
 import 'condition.dart';
 
 /// A named fragment selected at one level of a selection.
@@ -7,8 +9,11 @@ final class FragmentUse(
 
   /// The spread is selected when all conditions of any one list hold; one
   /// empty list means it is unconditional.
-  List<List<Condition>> whenAny,
-) {
+  List<List<Condition>> whenAny, {
+
+  /// The first spread node of the fragment, for diagnostics.
+  final FragmentSpread? spread,
+}) {
   /// Creates a use.
   this;
 
@@ -29,12 +34,12 @@ final class FragmentUse(
       return this;
     }
     if (conditions.isEmpty) {
-      return FragmentUse(fragmentName, [const <Condition>[]]);
+      return FragmentUse(fragmentName, [const <Condition>[]], spread: spread);
     }
     if (whenAny.any((existing) => _same(existing, conditions))) {
       return this;
     }
-    return FragmentUse(fragmentName, [...whenAny, conditions]);
+    return FragmentUse(fragmentName, [...whenAny, conditions], spread: spread);
   }
 
   static bool _same(List<Condition> a, List<Condition> b) {
```

In `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,9 @@
+import 'dart:convert';
+
+import 'package:crypto/crypto.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'root_typename.dart';
 import 'typename_adder.dart';
 
 /// Writes the document text an operation is sent with (R7.9): the operation
@@ -14,6 +18,12 @@ final class OperationText {
   /// The project's fragment definitions, by name.
   final Map<String, FragmentDefinition> fragments;
 
+  RootTypename get _rootTypename =>
+      RootTypename(schema, (name) => fragments[name]);
+
+  /// The SHA-256 of a document [text], in lower-case hexadecimal.
+  String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();
+
   /// The minified text of [operation] followed by the fragments it spreads,
   /// directly or not, sorted by name.
   ///
@@ -53,7 +63,7 @@ final class OperationText {
     TypenameAdder adder,
   ) {
     if (operation.operation == OperationType.subscription ||
-        !_readsAbstractType(operation.selectionSet)) {
+        !_rootTypename.isNeededBy(operation.selectionSet)) {
       return operation;
     }
     return OperationDefinition(
@@ -67,34 +77,6 @@ final class OperationText {
       end: operation.end,
     );
   }
-
-  // Whether the top level of [root] spreads a fragment, or has an inline
-  // fragment, on an abstract type, through spread fragments too.
-  bool _readsAbstractType(SelectionSet root) {
-    final visited = <String>{};
-    final pending = [...root.selections];
-    while (pending.isNotEmpty) {
-      switch (pending.removeLast()) {
-        case Field():
-          continue;
-        case InlineFragment(:final typeCondition, :final selectionSet):
-          if (_isAbstract(typeCondition?.name.value)) return true;
-          pending.addAll(selectionSet.selections);
-        case FragmentSpread(:final name):
-          final FragmentDefinition? fragment = fragments[name.value];
-          if (fragment == null || !visited.add(name.value)) continue;
-          if (_isAbstract(fragment.typeCondition.name.value)) return true;
-          pending.addAll(fragment.selectionSet.selections);
-      }
-    }
-    return false;
-  }
-
-  bool _isAbstract(String? typeName) =>
-      switch (typeName == null ? null : schema.typeNamed(typeName)) {
-        InterfaceType() || UnionType() => true,
-        _ => false,
-      };
 }
 
 // Collects the names of the fragments a definition spreads.
```

In `packages/typed_graphql_codegen/lib/src/plan/planned_field.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,6 +12,7 @@ final class PlannedField {
     required this.isConditional,
     this.definition,
     this.className,
+    this.node,
     this.overridesBase = false,
   });
 
@@ -40,6 +41,10 @@ final class PlannedField {
   /// The generated class of a composite field, null for a leaf.
   final String? className;
 
+  /// The first field node of the response name, for diagnostics; null for a
+  /// `__typename` the planner added.
+  final Field? node;
+
   /// Whether the field is a shared field of the sealed base, which the
   /// class overrides.
   final bool overridesBase;
@@ -52,6 +57,7 @@ final class PlannedField {
     isConditional: isConditional,
     definition: definition,
     className: className,
+    node: node,
     overridesBase: true,
   );
 }
```

In `packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,5 @@
+import 'package:typed_graphql/typed_graphql.dart';
+
 import '../emit/dart_names.dart';
 import 'condition.dart';
 import 'fragment_use.dart';
@@ -12,6 +14,7 @@ final class PlannedFragment {
         use.fragmentName,
         reservedMembers: DartNames.objectMembers,
       ),
+      spread = use.spread,
       whenAny = use.whenAny,
       isConditional = use.isConditional;
 
@@ -24,6 +27,9 @@ final class PlannedFragment {
   /// The holder member the fragment is read through.
   final String memberName;
 
+  /// The first spread node of the fragment.
+  final FragmentSpread? spread;
+
   /// The spread is selected when all conditions of any one list hold.
   final List<List<Condition>> whenAny;
 
```

Create `packages/typed_graphql_codegen/lib/src/plan/root_typename.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Finds out whether the top level of an operation reads an abstract type
/// (R7.9): then the document selects `__typename` there, which a
/// subscription's root cannot.
final class RootTypename {
  /// Creates the finder for [schema]; [fragmentNamed] looks a fragment
  /// definition up by name.
  const RootTypename(this.schema, this.fragmentNamed);

  /// The schema, which tells abstract types from object types.
  final Schema schema;

  /// The project's fragment definitions by name.
  final FragmentDefinition? Function(String name) fragmentNamed;

  /// Whether the top level of [root] reads an abstract type.
  bool isNeededBy(SelectionSet root) => find(root) != null;

  /// The first top-level selection of [root] that reads an abstract type,
  /// through spread fragments too, with the abstract type's name and, when a
  /// fragment definition is on it, the fragment's name; null when none does.
  ({Node selection, String typeName, String? fragmentName})? find(
    SelectionSet root,
  ) {
    final visited = <String>{};
    for (final top in root.selections) {
      final found = _search(top, visited);
      if (found != null) {
        return (
          selection: top,
          typeName: found.typeName,
          fragmentName: found.fragmentName,
        );
      }
    }
    return null;
  }

  // The abstract type [top] reads, through spread fragments; [visited] holds
  // the fragments already searched in vain.
  ({String typeName, String? fragmentName})? _search(
    Selection top,
    Set<String> visited,
  ) {
    final pending = <Selection>[top];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Field():
          continue;
        case InlineFragment(:final typeCondition, :final selectionSet):
          final String? typeName = typeCondition?.name.value;
          if (typeName != null && _isAbstract(typeName)) {
            return (typeName: typeName, fragmentName: null);
          }
          pending.addAll(selectionSet.selections);
        case FragmentSpread(:final name):
          final FragmentDefinition? fragment = fragmentNamed(name.value);
          if (fragment == null || !visited.add(name.value)) continue;
          final String typeName = fragment.typeCondition.name.value;
          if (_isAbstract(typeName)) {
            return (typeName: typeName, fragmentName: name.value);
          }
          pending.addAll(fragment.selectionSet.selections);
      }
    }
    return null;
  }

  bool _isAbstract(String typeName) => switch (schema.typeNamed(typeName)) {
    InterfaceType() || UnionType() => true,
    _ => false,
  };
}
```

In `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -288,6 +288,7 @@ final class ShapePlanner {
       isConditional: group.isConditional,
       definition: group.fieldName == '__typename' ? null : group.definition,
       className: className,
+      node: group.nodes.first,
     );
   }
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/generator/client_generator_test.dart test/generator/document_names_test.dart test/generator/generated_names_test.dart test/generator/persisted_manifest_test.dart test/golden_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- Names are checked over operations and fragments too: classes, the members of
  every class (fields, variables, fragment accessors) and file paths, as
  `GQL507`/`GQL508`, in file and offset order. A subscription that spreads a
  fragment on an abstract type at its root is a `GQL504`.
- `persisted_operations` writes the persisted-operations manifest (ids, names,
  types and minified bodies, sorted by name) as the last generated file.
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -236,8 +236,8 @@ client can read the type of any object; fragment definitions and inline
 fragments get none, because the field around them has it. The operation's
 own selection set gets it only when a fragment on an interface or a union is
 spread at its top level, as the sealed class that reads it needs. A
-subscription cannot select `__typename` at its root, so it is left as
-written. The `sha256` is the SHA-256 of the text in UTF-8, in lowercase
+subscription cannot select `__typename` at its root, so a subscription that
+needs it there (`GQL504`) cannot be generated. The `sha256` is the SHA-256 of the text in UTF-8, in lowercase
 hexadecimal: the id of a persisted query.
 
 The variables class has a field per variable, like an input object without a
@@ -252,6 +252,17 @@ The variables matter only for the fragments spread under `@include` and
 were not sent. `GetUserQuery.decodeData` passes them. The golden
 `test/goldens/operations` is analyzed and run like the other goldens.
 
+With `persisted_operations` set, `generate` also writes that file last: a
+JSON manifest with the `id` (the `sha256`), `name`, `type` and `body` (the
+minified text) of every operation, sorted by name, the same values the
+operation classes carry.
+
+Before anything is written, every class and member the generator would
+declare is checked: two classes with one name, two members of one class with
+one Dart name (`user_name` and `userName`, two fragments `UserCard` and
+`userCard`) and two files with one path are a `GQL507`, whatever declares
+them.
+
 ## Schema types
 
 The file at `schema_types` holds what the documents reach: the enums and
@@ -412,10 +423,10 @@ and are never reused.
 | `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
 | `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
 | `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
-| `GQL504` | error | A document uses `@defer` or `@stream`, which the generator does not support yet. |
+| `GQL504` | error | A document uses `@defer`, `@stream`, or a fragment on an abstract type at the root of a subscription, which the generator does not support yet. |
 | `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
 | `GQL506` | warning | No document matches `documents`. |
-| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`). |
+| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class, or write one file twice. |
 | `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
 
 The problems of the schema and of the documents keep the codes of the core:
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/emit/operation_emitter.dart packages/typed_graphql_codegen/lib/src/generator/client_generator.dart packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart packages/typed_graphql_codegen/lib/src/generator/generated_names.dart packages/typed_graphql_codegen/lib/src/generator/persisted_manifest.dart packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart packages/typed_graphql_codegen/lib/src/plan/field_collector.dart packages/typed_graphql_codegen/lib/src/plan/fragment_use.dart packages/typed_graphql_codegen/lib/src/plan/operation_text.dart packages/typed_graphql_codegen/lib/src/plan/planned_field.dart packages/typed_graphql_codegen/lib/src/plan/planned_fragment.dart packages/typed_graphql_codegen/lib/src/plan/root_typename.dart packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart packages/typed_graphql_codegen/test/generator/client_generator_test.dart packages/typed_graphql_codegen/test/generator/document_names_test.dart packages/typed_graphql_codegen/test/generator/generated_names_test.dart packages/typed_graphql_codegen/test/generator/persisted_manifest_test.dart packages/typed_graphql_codegen/test/golden_test.dart packages/typed_graphql_codegen/test/goldens/operations/input/typed_graphql.yaml packages/typed_graphql_codegen/test/goldens/operations/output/build/persisted_operations.json.golden
git commit -q -m "feat(typed_graphql_codegen): check generated names and write the persisted-operations manifest" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Document generated operations and fragments

The guide gains a runnable program that generates a document's library and sections on names, data masking, abstract types, `@include`/`@skip`, variables, the document text and manifest, decoding, `GQL504` and `GQL507`; the README, `llms.txt` and the CHANGELOG follow.

Commit on the branch: `2a475a2`.

**Files:**
- Modify: `llms.txt`, `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/README.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`

**Interfaces:**
- Consumes: Tasks 1-7.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Update the documents**

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,7 +7,7 @@
 - [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation with opt-in limits and cost analysis, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): under construction; the contract generated code compiles against (operations and data codecs), the client and cache are not built yet (M11, M12)
-- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; reads typed_graphql.yaml and checks a project's schema and .graphql documents, does not generate code yet (M8, M10)
+- [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): under construction; reads typed_graphql.yaml, checks a project's schema and .graphql documents, and generates the schema types and the operation and fragment classes of each document, no CLI yet (M8, M10)
 - [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): skeleton; typed schema builder, executor and transport handlers, not usable yet (M5 to M7)
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
```

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- The guide documents the generated operations and fragments: a program that
  generates a document's library, the class names, data masking, sealed
  classes for abstract types, `@include` and `@skip`, variables, the
  document text and the persisted-operations manifest, decoding, and the
  `GQL504` subscription case and `GQL507` for members and files.
```

In `packages/typed_graphql_codegen/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,19 +4,19 @@
 ![Role](https://img.shields.io/badge/role-codegen-blue)
 ![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)
 
-**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** So far it generates the library of the enums and input objects the operations use; operation classes are not generated yet. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
+**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** It generates the library of the enums and input objects the operations use and, per document, the classes of its operations, variables, data and fragments, with the minified document, its SHA-256 and the persisted-operations manifest. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
 > **Status: under construction.** This release reads the project's
 > configuration, `typed_graphql.yaml` (`CodegenConfig`), and checks a project:
 > `ClientGenerator.check` loads the schema, parses and validates the
 > `.graphql` documents as one fragment graph, and reports every problem with
 > its file, line and column. `ClientGenerator.generate` also writes the
-> schema-types library; operation classes and the CLI arrive in M10 and the SDL-first server generator in M8 (see the
+> schema-types library and a library per document; the CLI arrives in M10 and the SDL-first server generator in M8 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 It does not depend on `analyzer`. The
 [Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
-lists the configuration keys, shows a check and a generation, describes the generated enums, input objects and scalars, and lists the codes `GQL500` to
+lists the configuration keys, shows a check and a generation, describes the generated enums, input objects, scalars, operations and fragments, and lists the codes `GQL500` to
 `GQL508`.
 
 ## License
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -1,14 +1,15 @@
 # Client Code Generation
 
 `typed_graphql_codegen` turns a GraphQL schema and the `.graphql` operations
-of a Dart project into typed client code. This version checks a project and
-generates the library of the schema's types: the enums and input objects the
-documents use, with the scalars mapped to Dart types. It reads the
-configuration file, loads the schema, parses and validates every document as
-one fragment graph, and reports each problem as a diagnostic at
-`file:line:column`; classes for operations and fragments arrive next. Bad
-input never throws: a problem is a diagnostic with a stable code, in a sealed
-result or a list.
+of a Dart project into typed client code. It reads the configuration file,
+loads the schema, parses and validates every document as one fragment graph,
+and reports each problem as a diagnostic at `file:line:column`. It generates
+the schema-types library (the enums and input objects the documents use,
+with the scalars mapped to Dart types) and a library per document: the
+classes of its operations, variables, data and fragments, the minified
+document with its SHA-256, and the persisted-operations manifest. The command
+line arrives next. Bad input never throws: a problem is a diagnostic with a
+stable code, in a sealed result or a list.
 
 ## Configuration
 
@@ -207,62 +208,446 @@ fragments; `NodeCardUnknown` keeps the `typename` it was read with. The golden
 
 ## Operations
 
-An operation `GetUser` is four things, in this order in its file: the class
-`GetUserQuery` (`GetUserMutation`, `GetUserSubscription`), the class
-`GetUserVariables` when the operation has variables, the class
-`GetUserData`, and the classes under the data.
+Each document file gets a library at its own path plus `.dart` with the
+classes of its operations and fragments, in document order. This program
+generates the library of one document, a query with a variable and a
+fragment, from a schema with a `User` that has a nullable `email`:
+
+```dart
+import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
+
+void main() {
+  final result = CodegenConfig.parse(
+    'schema: schema.graphql\n',
+    path: 'typed_graphql.yaml',
+  );
+  if (result is! ConfigSuccess) {
+    throw StateError('the configuration is valid');
+  }
+  final generation = ClientGenerator(result.config).generate(
+    schema: const ProjectFile('schema.graphql', '''
+type Query {
+  user(id: ID!): User
+}
+
+type User {
+  id: ID!
+  name: String!
+  email: String
+}
+'''),
+    documents: const [
+      ProjectFile('lib/user.graphql', '''
+query GetUser(\$id: ID!) {
+  user(id: \$id) {
+    ...UserCard
+    email
+  }
+}
+
+fragment UserCard on User {
+  id
+  name
+}
+'''),
+    ],
+  );
+  for (final file in generation.files) {
+    if (file.path == 'lib/user.graphql.dart') print(file.text);
+  }
+}
+```
+
+It prints:
 
 ```text
+// GENERATED CODE - DO NOT MODIFY BY HAND.
+// Generated by typed_graphql_codegen from lib/user.graphql.
+// dart format off
+
+import 'package:typed_graphql/typed_graphql.dart' as graphql;
+import 'package:typed_graphql_client/typed_graphql_client.dart' as client;
+
+/// The query `GetUser`.
 final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
+  /// Creates the query with its [variables].
   const GetUserQuery(this.variables);
 
+  /// The document of `GetUser` as it is sent.
   static const client.OperationDocument operationDocument =
       client.OperationDocument(
         name: 'GetUser',
         type: graphql.OperationType.query,
-        text: r'query GetUser($id:ID!){user(id:$id){id __typename}}',
-        sha256: '...',
+        text: r'query GetUser($id:ID!){user(id:$id){...UserCard email __typename}}fragment UserCard on User{id name}',
+        sha256:
+          '5fce2865ff25bb570a05850d6426f8ef67cb5f50f27cf6919cbfadf5f7566f36',
       );
 
+  /// The variables the query is sent with.
   final GetUserVariables variables;
+
+  @override
+  client.OperationDocument get document => operationDocument;
+
+  @override
+  graphql.JsonObject get variablesJson => variables.toJson();
+
+  @override
+  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
+      GetUserData.decode(data, variables: variablesJson);
+}
+
+/// The variables of the query `GetUser`.
+final class GetUserVariables implements client.DataObject {
+  /// Creates the variables.
+  const GetUserVariables({required this.id});
+
+  static const client.DataCodec<String> _idCodec =
+      client.ScalarDataCodec(graphql.IdCodec());
+
+  /// The variable `$id`.
+  final String id;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'id': _idCodec.write(id),
+  });
+
+  @override
+  bool operator ==(Object other) => other is GetUserVariables && other.id == id;
+
+  @override
+  int get hashCode => id.hashCode;
+
+  @override
+  String toString() => 'GetUserVariables(id: $id)';
+}
+
+/// The data of the query `GetUser`.
+final class GetUserData implements client.DataObject {
+  /// Creates the data.
+  const GetUserData({this.user});
+
+  factory GetUserData._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserData(user: _userCodec.field(json, 'user', context));
+
+  /// Reads and writes the data.
+  static const client.DataCodec<GetUserData> codec =
+      client.ObjectDataCodec(GetUserData._read);
+
+  static const client.DataCodec<GetUserDataUser?> _userCodec =
+      client.NullableDataCodec(GetUserDataUser.codec);
+
+  /// The field `user`.
+  final GetUserDataUser? user;
+
+  /// Reads [json], the `data` of a response to the query sent with
+  /// [variables].
+  static graphql.DecodeResult<GetUserData> decode(
+    graphql.JsonObject json, {
+    graphql.JsonObject? variables,
+  }) => codec.decode(json, client.DataContext(variables));
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({'user': _userCodec.write(user)});
+
+  @override
+  bool operator ==(Object other) => other is GetUserData && other.user == user;
+
+  @override
+  int get hashCode => user.hashCode;
+
+  @override
+  String toString() => 'GetUserData(user: $user)';
+}
+
+/// The field `user` of [GetUserData].
+final class GetUserDataUser implements client.DataObject {
+  /// Creates the value.
+  const GetUserDataUser({required this.fragments, this.email});
+
+  factory GetUserDataUser._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserDataUser(
+    email: _emailCodec.field(json, 'email', context),
+    fragments: GetUserDataUserFragments._read(json, context),
+  );
+
+  /// Reads and writes the value.
+  static const client.DataCodec<GetUserDataUser> codec =
+      client.ObjectDataCodec(GetUserDataUser._read);
+
+  static const client.DataCodec<String?> _emailCodec =
+      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));
+
+  /// The field `email`.
+  final String? email;
+
+  /// The fragments spread on this value.
+  final GetUserDataUserFragments fragments;
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    ...fragments.toJson().fields,
+    'email': _emailCodec.write(email),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is GetUserDataUser &&
+      other.email == email &&
+      other.fragments == fragments;
+
+  @override
+  int get hashCode => Object.hashAll([email, fragments]);
+
+  @override
+  String toString() => 'GetUserDataUser(email: $email, fragments: $fragments)';
+}
+
+/// The fragments spread on [GetUserDataUser].
+final class GetUserDataUserFragments implements client.DataObject {
+  /// Creates the fragments.
+  const GetUserDataUserFragments({required this.userCard});
+
+  factory GetUserDataUserFragments._read(
+    graphql.JsonObject json,
+    client.DataContext context,
+  ) => GetUserDataUserFragments(userCard: UserCard.codec.read(json, context));
+
+  /// The fragment `UserCard`.
+  final UserCard userCard;
+
+  @override
+  graphql.JsonObject toJson() =>
+      graphql.JsonObject({...userCard.toJson().fields});
+
+  @override
+  bool operator ==(Object other) =>
+      other is GetUserDataUserFragments && other.userCard == userCard;
+
+  @override
+  int get hashCode => userCard.hashCode;
+
+  @override
+  String toString() => 'GetUserDataUserFragments(userCard: $userCard)';
+}
+
+/// The fragment `UserCard` on `User`.
+final class UserCard implements client.DataObject {
+  /// Creates the fragment.
+  const UserCard({required this.id, required this.name});
+
+  factory UserCard._read(graphql.JsonObject json, client.DataContext context) =>
+      UserCard(
+        id: _idCodec.field(json, 'id', context),
+        name: _nameCodec.field(json, 'name', context),
+      );
+
+  /// Reads and writes the fragment.
+  static const client.DataCodec<UserCard> codec =
+      client.ObjectDataCodec(UserCard._read);
+
+  static const client.DataCodec<String> _idCodec =
+      client.ScalarDataCodec(graphql.IdCodec());
+
+  static const client.DataCodec<String> _nameCodec =
+      client.ScalarDataCodec(graphql.StringCodec());
+
+  /// The field `id`.
+  final String id;
+
+  /// The field `name`.
+  final String name;
+
+  /// Reads [json], an object the fragment was spread on, in the response
+  /// to an operation sent with [variables].
+  static graphql.DecodeResult<UserCard> decode(
+    graphql.JsonObject json, {
+    graphql.JsonObject? variables,
+  }) => codec.decode(json, client.DataContext(variables));
+
+  @override
+  graphql.JsonObject toJson() => graphql.JsonObject({
+    'id': _idCodec.write(id),
+    'name': _nameCodec.write(name),
+  });
+
+  @override
+  bool operator ==(Object other) =>
+      other is UserCard && other.id == id && other.name == name;
+
+  @override
+  int get hashCode => Object.hashAll([id, name]);
+
+  @override
+  String toString() => 'UserCard(id: $id, name: $name)';
 }
 ```
 
-`GetUserQuery(GetUserVariables(id: '1')).toRequest()` is the request to
-send. The `operationDocument` is the text as it is sent: the operation and
-every fragment it spreads, transitively, sorted by name and minified. It
-adds `__typename` to the selection set of every field that has one, so the
-client can read the type of any object; fragment definitions and inline
-fragments get none, because the field around them has it. The operation's
-own selection set gets it only when a fragment on an interface or a union is
-spread at its top level, as the sealed class that reads it needs. A
-subscription cannot select `__typename` at its root, so a subscription that
-needs it there (`GQL504`) cannot be generated. The `sha256` is the SHA-256 of the text in UTF-8, in lowercase
-hexadecimal: the id of a persisted query.
+The sections below describe the parts of that output.
+
+### Names
+
+An operation `GetUser` is four things, in this order in its file: the class
+`GetUserQuery` (`GetUserMutation`, `GetUserSubscription`), the class
+`GetUserVariables` when the operation has variables, the class `GetUserData`,
+and the classes under the data. A fragment `UserCard` is the class `UserCard`.
+
+| Class | Name |
+|---|---|
+| Operation | operation name and kind: `GetUserQuery` |
+| Variables | `GetUserVariables` |
+| Data | `GetUserData` |
+| A composite field | the owner's name and the field's: `GetUserDataUser`, then `GetUserDataUserFriends` |
+| Fragments holder | the owner's name and `Fragments`: `GetUserDataUserFragments` |
+| A variant of an abstract selection | the base's name and the type's: `FindNodeDataNodeUser`; `FindNodeDataNodeUnknown` for any other type |
+
+A GraphQL name is turned into a Dart one: classes in upper camel case
+(`get_user` is `GetUser`), members in lower camel case. A name that Dart
+reserves (`default`) or that the generated class already has (`toJson`,
+`fragments`) gets a `$` suffix (`default$`); the JSON key stays as written.
+GraphQL names cannot contain `$`, so the suffix never collides with another
+name. When two names would still be one, the project is not generated (see
+`GQL507` below).
+
+### Fragments and masking
+
+A fragment spread is not merged into the fields around it: the spread
+fragment is a member of a `...Fragments` class that the value holds as
+`fragments`. A component reads the fields of its own fragment and nothing
+else (data masking, R7.4):
+
+```text
+final data = GetUserData.decode(json, variables: variables);
+final card = data.user?.fragments.userCard; // a UserCard
+final email = data.user?.email; // selected by the query itself
+```
+
+The fields of the fragment are not on `data.user`, so a change in the
+fragment cannot break a reader that does not use it. `UserCard.decode` reads
+a fragment on its own.
+
+### Abstract types
+
+A selection on an interface or a union that tells types apart is a sealed
+class, as `FindNodeDataNode` in the golden `test/goldens/operations`: one
+class per type the selection tells apart, and `…Unknown` for any other type,
+which a server may add later. The sealed class declares `typename` and every
+field that all its classes select in the same way, with the same type, and
+`fragments` when they all spread the same fragments; a class that selects
+more than that declares the rest. A `switch` over it is exhaustive:
+
+```text
+String describe(FindNodeDataNode node) => switch (node) {
+  FindNodeDataNodeUser(:final name) => 'user $name',
+  FindNodeDataNodeBot(:final model) => 'bot $model',
+  FindNodeDataNodeUnknown(:final typename) => 'something else: $typename',
+};
+```
+
+### `@include` and `@skip`
+
+A field under `@include` or `@skip` is nullable, whatever its type in the
+schema, and a fragment spread under them is a nullable member of the
+`...Fragments` class. Which of them are present is decided when the data is
+read, from the variables of the request: `GetUserQuery.decodeData` passes
+them, and the defaults of the operation's `Boolean` variables fill those that
+were not sent. `GetUserData.decode(json, variables: ...)` does the same for a
+caller that has the JSON and the variables.
+
+```text
+/// The field `friends`; null when `@include` or `@skip` left it out.
+final List<GetUserDataUserFriends>? friends;
+```
+
+### Variables
 
 The variables class has a field per variable, like an input object without a
 reader: a non-null variable without a default is `required`, any other is an
 `Optional` that is absent unless given, and `toJson` writes only the present
-ones. An operation without variables has a `const` constructor without
-arguments and no variables class.
+values. An absent variable is not sent, so the server applies the
+variable's default; `Optional.present(null)` sends an explicit `null`. An
+operation without variables has a `const` constructor without arguments and
+no variables class.
+
+```text
+const GetUserVariables({
+  required this.id,
+  required this.full,
+  this.withFriends = const graphql.Optional.absent(),
+});
+```
+
+`GetUserQuery(GetUserVariables(id: '1', full: true)).toRequest()` is the
+request to send.
+
+### The document text and the manifest
+
+The `operationDocument` is the text as it is sent: the operation and every
+fragment it spreads, transitively, sorted by name and minified. It adds
+`__typename` to the selection set of every field that has one, so the client
+can read the type of any object; fragment definitions and inline fragments
+get none, because the field around them has it. The operation's own
+selection set gets it only when a fragment on an interface or a union is
+spread at its top level, as the sealed class that reads it needs. A
+subscription cannot select `__typename` at its root, so a subscription that
+reads an abstract type there (`GQL504`) cannot be generated. The `sha256` is
+the SHA-256 of the text in UTF-8, in lowercase hexadecimal: the id of a
+persisted query.
+
+With `persisted_operations` set, `generate` also writes that file, last: a
+JSON manifest in the format of Apollo's persisted-query manifest, with the
+`id` (the `sha256`), `name`, `type` and `body` (the minified text) of every
+operation, sorted by name, the same values the operation classes carry:
+
+```text
+{
+  "format": "apollo-persisted-query-manifest",
+  "version": 1,
+  "operations": [
+    {
+      "id": "5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61",
+      "name": "Everyone",
+      "type": "query",
+      "body": "query Everyone{node(id:\"1\"){id __typename}}"
+    }
+  ]
+}
+```
 
-`GetUserData.decode(json, variables: ...)` reads the `data` of a response.
-The variables matter only for the fragments spread under `@include` and
-`@skip`; the defaults of the operation's `Boolean` variables fill those that
-were not sent. `GetUserQuery.decodeData` passes them. The golden
-`test/goldens/operations` is analyzed and run like the other goldens.
+### Decoding
 
-With `persisted_operations` set, `generate` also writes that file last: a
-JSON manifest with the `id` (the `sha256`), `name`, `type` and `body` (the
-minified text) of every operation, sorted by name, the same values the
-operation classes carry.
+`GetUserData.decode(json, variables: ...)` reads the `data` of a response and
+never throws: a value of the wrong shape, a missing required field or an
+unreadable scalar is a `DecodeFailure` with a message and the path of the
+value in the response. `toJson` writes the data back, so a value that was
+read writes the JSON it was read from (with `__typename` where the selection
+reads it), and `==` compares by value, lists by content.
+
+```text
+switch (GetUserData.decode(json, variables: variables)) {
+  case DecodeSuccess(:final value):
+    print(value.user?.email);
+  case DecodeFailure(:final message, :final path):
+    print('$message at $path');
+}
+```
+
+### Checked names
 
 Before anything is written, every class and member the generator would
 declare is checked: two classes with one name, two members of one class with
-one Dart name (`user_name` and `userName`, two fragments `UserCard` and
-`userCard`) and two files with one path are a `GQL507`, whatever declares
+one Dart name and two files with one path are a `GQL507`, whatever declares
 them.
 
+The goldens `test/goldens/fragments`, `test/goldens/polymorphic` and
+`test/goldens/operations` are regenerated, analyzed and run by the tests.
+
 ## Schema types
 
 The file at `schema_types` holds what the documents reach: the enums and
@@ -423,10 +808,10 @@ and are never reused.
 | `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
 | `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
 | `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
-| `GQL504` | error | A document uses `@defer`, `@stream`, or a fragment on an abstract type at the root of a subscription, which the generator does not support yet. |
+| `GQL504` | error | A document uses `@defer` or `@stream`, which the generator does not support yet, or a subscription reads an abstract type at its root (a fragment on an interface or a union, or an inline fragment): the sealed class would need `__typename` there, and a subscription cannot select it. |
 | `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
 | `GQL506` | warning | No document matches `documents`. |
-| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class, or write one file twice. |
+| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class (such as the fields `user_name` and `userName`, or two fragments `UserCard` and `userCard`), or two files at one path. |
 | `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
 
 The problems of the schema and of the documents keep the codes of the core:
````

- [ ] **Step 2: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add llms.txt packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/README.md packages/typed_graphql_codegen/doc/client_codegen.md
git commit -q -m "docs(typed_graphql_codegen): document generated operations and fragments" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Add GQL511 and widen the GQL504 and GQL507 docs

First commit of the M10c review fixes (`.superpowers/m10-reports/m10c-review.md`, ruling 2 and minor 8): the core catalog gains `GQL511` tooManyGeneratedClasses (an operation or fragment that would generate more classes than the limit), and the `GQL504` and `GQL507` doc comments name inline fragments, introspection fields, member collisions and file paths.

Commit on the branch: `bb9a7d7`.

**Files:**
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: The core `DiagnosticCode`.
- Produces:
- Diagnostic codes: `GQL511`.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -528,8 +528,8 @@ enum DiagnosticCode(
   anonymousOperation('GQL503'),
 
   /// `GQL504`: a construct the code generator does not support yet: `@defer`,
-  /// `@stream`, or a fragment on an abstract type spread at the root of a
-  /// subscription.
+  /// `@stream`, an introspection field (`__schema`, `__type`), or a spread or
+  /// inline fragment that makes the root of a subscription polymorphic.
   unsupportedInDocument('GQL504'),
 
   /// `GQL505`: the configuration maps a scalar the schema does not have as a
@@ -541,12 +541,18 @@ enum DiagnosticCode(
   noDocuments('GQL506'),
 
   /// `GQL507`: the code generator would declare one Dart name twice, such as
-  /// an enum `Role` and an input object `RoleKnown`; reported at the second
-  /// declaration, related to the first.
+  /// an enum `Role` and an input object `RoleKnown`, two members of one
+  /// generated class, or two generated files at one path; reported at the
+  /// second declaration, related to the first.
   generatedNameCollision('GQL507'),
 
   /// `GQL508`: a name the code generator would declare hides a Dart type the
   /// generated code uses, such as `List` or a `dart:core` type a scalar is
   /// mapped to.
   reservedTypeName('GQL508'),
+
+  /// `GQL511`: an operation or fragment whose selections would make the code
+  /// generator declare more classes than its fixed limit (10000); reported at
+  /// the operation or fragment name.
+  tooManyGeneratedClasses('GQL511'),
 }
```

- [ ] **Step 2: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The catalog adds `GQL511` (an operation or fragment that would generate
  too many classes).
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
git commit -q -m "feat(typed_graphql): add GQL511 and widen the GQL504 and GQL507 docs" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Add JsonMerger for the JSON of a class and its fragments

Review finding 1 (important): `toJson` of a class that spreads fragments let the last writer of a response name win, so a nested field selected by the class and by a fragment lost subfields. `JsonMerger` (a const class in the client contract) merges `JsonObject`s by key recursively and lists by index, so generated `toJson` keeps every field.

Commit on the branch: `b3d24c2`.

**Files:**
- Create: `packages/typed_graphql_client/lib/src/operation/json_merger.dart`
- Modify: `packages/typed_graphql_client/CHANGELOG.md`, `packages/typed_graphql_client/doc/operations.md`, `packages/typed_graphql_client/lib/typed_graphql_client.dart`
- Test: `packages/typed_graphql_client/test/operation/json_merger_test.dart`

**Interfaces:**
- Consumes: M10b client contract (`DataObject`); the core `JsonValue`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// operation/json_merger.dart
final class const JsonMerger()
  JsonObject merge(List<JsonObject?> objects)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_client/test/operation/json_merger_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

void main() {
  const merger = JsonMerger();

  test('merges the fields of nested objects with one key', () {
    final JsonObject merged = merger.merge([
      JsonObject({
        'avatar': JsonObject({'url': const JsonString('u')}),
      }),
      JsonObject({
        'avatar': JsonObject({'size': JsonNumber(2)}),
      }),
    ]);
    expect(
      merged,
      JsonObject({
        'avatar': JsonObject({
          'url': const JsonString('u'),
          'size': JsonNumber(2),
        }),
      }),
    );
  });

  test('merges arrays by index', () {
    final JsonObject merged = merger.merge([
      JsonObject({
        'friends': JsonArray([
          JsonObject({'a': JsonNumber(1)}),
        ]),
      }),
      JsonObject({
        'friends': JsonArray([
          JsonObject({'b': JsonNumber(2)}),
          const JsonNull(),
        ]),
      }),
    ]);
    expect(
      merged,
      JsonObject({
        'friends': JsonArray([
          JsonObject({'a': JsonNumber(1), 'b': JsonNumber(2)}),
          const JsonNull(),
        ]),
      }),
    );
  });

  test('skips a null entry', () {
    expect(
      merger.merge([
        null,
        JsonObject({'a': JsonNumber(1)}),
      ]),
      JsonObject({'a': JsonNumber(1)}),
    );
  });

  test('lets the later value win for other pairs', () {
    expect(
      merger.merge([
        JsonObject({'a': JsonNumber(1)}),
        JsonObject({'a': const JsonNull()}),
      ]),
      JsonObject({'a': const JsonNull()}),
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/operation/json_merger_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_client/lib/src/operation/json_merger.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Merges the JSON that several generated classes write for one response
/// object (R7.3).
///
/// A class and the fragments it spreads, or two fragments, may select the
/// same response name with different sub-selections; the written object
/// must hold the fields of both. Objects merge by key, recursively; arrays
/// merge by index, as the reader reads the same list once per selection;
/// for any other pair the later value wins.
///
/// {@category operations}
final class const JsonMerger() {
  /// Creates the merger.
  this;

  /// The merge of [objects] in order; a null entry (a fragment that was not
  /// selected) is skipped.
  JsonObject merge(List<JsonObject?> objects) {
    var merged = JsonObject(const <String, JsonValue>{});
    for (final JsonObject? object in objects) {
      if (object != null) {
        merged = _mergeObjects(merged, object);
      }
    }
    return merged;
  }

  JsonObject _mergeObjects(JsonObject base, JsonObject extra) {
    final fields = <String, JsonValue>{...base.fields};
    for (final MapEntry<String, JsonValue> entry in extra.fields.entries) {
      final JsonValue? existing = fields[entry.key];
      fields[entry.key] = existing == null
          ? entry.value
          : _mergeValues(existing, entry.value);
    }
    return JsonObject(fields);
  }

  JsonValue _mergeValues(JsonValue base, JsonValue extra) =>
      switch ((base, extra)) {
        (final JsonObject base, final JsonObject extra) => _mergeObjects(
          base,
          extra,
        ),
        (final JsonArray base, final JsonArray extra) => _mergeArrays(
          base,
          extra,
        ),
        _ => extra,
      };

  JsonArray _mergeArrays(JsonArray base, JsonArray extra) {
    final int length = base.items.length > extra.items.length
        ? base.items.length
        : extra.items.length;
    return JsonArray([
      for (var index = 0; index < length; index++)
        if (index >= base.items.length)
          extra.items[index]
        else if (index >= extra.items.length)
          base.items[index]
        else
          _mergeValues(base.items[index], extra.items[index]),
    ]);
  }
}
```

In `packages/typed_graphql_client/lib/typed_graphql_client.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,6 +16,7 @@ export 'src/operation/data_object.dart';
 export 'src/operation/enum_data_codec.dart';
 export 'src/operation/graphql_operation.dart';
 export 'src/operation/json_data_codec.dart';
+export 'src/operation/json_merger.dart';
 export 'src/operation/list_data_codec.dart';
 export 'src/operation/nullable_data_codec.dart';
 export 'src/operation/object_data_codec.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/operation/json_merger_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_client/CHANGELOG.md`:

```markdown
- `JsonMerger` merges the JSON of a class and its fragments deeply (objects by
  key, arrays by index), so generated `toJson` keeps every field of
  overlapping nested selections.
```

In `packages/typed_graphql_client/doc/operations.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -27,7 +27,8 @@ Generated code composes them as constants:
 
 `DataContext` carries the variables, which decide whether a fragment under
 `@include` or `@skip` was selected. `DataEquality` compares the members of
-generated classes that hold lists or optionals.
+generated classes that hold lists or optionals. `JsonMerger` merges the JSON
+of a class and its fragments when they select the same response name.
 
 ## Failures
 
```

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_client && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_client/CHANGELOG.md packages/typed_graphql_client/doc/operations.md packages/typed_graphql_client/lib/src/operation/json_merger.dart packages/typed_graphql_client/lib/typed_graphql_client.dart packages/typed_graphql_client/test/operation/json_merger_test.dart
git commit -q -m "feat(typed_graphql_client): add JsonMerger for the JSON of a class and its fragments" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Apply the review of operations and fragments

The remaining M10c review findings: `toJson` merges a class and its fragments with `JsonMerger` (finding 1); nested classes with the same type, selection nodes and conditions are shared, each definition is planned once (`PlanScope`, `ClassRegistry`, `FieldPlanner`), and more than 10000 classes is `GQL511` (finding 2, minor 11); a `__typename` under `@include`/`@skip` is a nullable member and does not replace the added one (finding 3); `__schema` and `__type` are `GQL504` (`UnsupportedIntrospectionRule`, finding 4); only a spread of a fragment that plans as a sealed base needs `__typename` at the root (minor 12); name problems are limited like every other run (minor 9); `Applicability` uses the schema's O(1) relations (minor 10); `Narrowing`, `DartNames.freeName` and the manifest file registration are reduced or removed (minors 5-7); the guide and tests follow (minors 13-15).

Commit on the branch: `941599b`.

**Files:**
- Create: `packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_introspection_rule.dart`, `packages/typed_graphql_codegen/lib/src/plan/class_registry.dart`, `packages/typed_graphql_codegen/lib/src/plan/field_planner.dart`, `packages/typed_graphql_codegen/lib/src/plan/plan_scope.dart`
- Modify: `packages/typed_graphql_codegen/CHANGELOG.md`, `packages/typed_graphql_codegen/doc/client_codegen.md`, `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart`, `packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart`, `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`, `packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart`, `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, `packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart`, `packages/typed_graphql_codegen/lib/src/plan/applicability.dart`, `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart`, `packages/typed_graphql_codegen/lib/src/plan/narrowing.dart`, `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart`, `packages/typed_graphql_codegen/lib/src/plan/root_typename.dart`, `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`, `packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart`
- Test: `packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart`, `packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, `packages/typed_graphql_codegen/test/generator/document_names_test.dart`, `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, `packages/typed_graphql_codegen/test/generator/typename_generation_test.dart`, `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_avatar.graphql`, `packages/typed_graphql_codegen/test/goldens/fragments/input/schema.graphql`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_avatar.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_mutations.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_node.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_result.graphql.dart.golden`, `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden`, `packages/typed_graphql_codegen/test/plan/class_sharing_test.dart`, `packages/typed_graphql_codegen/test/plan/field_collector_test.dart`, `packages/typed_graphql_codegen/test/plan/operation_text_test.dart`, `packages/typed_graphql_codegen/test/plan/shape_planner_test.dart`

**Interfaces:**
- Consumes: Tasks 1-10.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// emit/document_library_emitter.dart
  const DocumentLibraryEmitter(
  final OperationText text

// emit/to_json_writer.dart
  void writeMerged(

// generator/generated_names.dart
  void reportTooManyClasses(String declarer, int limit, SourceSpan? span)

// generator/rules/subscription_root_rule.dart
  AstVisitor createVisitor(ValidationContext context)
final class _SubscriptionRoot(…)

// generator/rules/unsupported_introspection_rule.dart
final class const UnsupportedIntrospectionRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UnsupportedIntrospection(final ValidationContext context)
  VisitAction enter(Node node)

// plan/applicability.dart
  List<ObjectType> reachedBy(SchemaType parent, List<Narrowing> narrowings)

// plan/class_registry.dart
final class ClassRegistry
  ClassRegistry()
  String? classOf(String typeName, List<Field> nodes)
  void record(String typeName, List<Field> nodes, String className)

// plan/field_planner.dart
final class const FieldPlanner(…)
  PlannedField plan(String owner, FieldGroup group, PlanScope scope)

// plan/operation_text.dart
  OperationText(this.schema, this.fragments)
  String of(OperationDefinition operation)

// plan/plan_scope.dart
final class PlanScope
  PlanScope(this.registry)
  final ClassRegistry registry

// plan/root_typename.dart
  const RootTypename(this.schema, this.fragments)
  final Map<String, FragmentDefinition> fragments

// plan/shape_planner.dart
  bool exceedsLimit(ExecutableDefinition definition)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -150,13 +150,15 @@ final class GetUserDataUser implements client.DataObject {
   final GetUserDataUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    'role': _roleCodec.write(role),
-    'createdAt': _createdAtCodec.write(createdAt),
-    'cursor': _cursorCodec.write(cursor),
-    'friends': _friendsCodec.write(friends),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      'role': _roleCodec.write(role),
+      'createdAt': _createdAtCodec.write(createdAt),
+      'cursor': _cursorCodec.write(cursor),
+      'friends': _friendsCodec.write(friends),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,7 @@ import 'package:test/test.dart';
 import 'package:typed_graphql_codegen/src/emit/document_library_emitter.dart';
 import 'package:typed_graphql_codegen/src/emit/library_imports.dart';
 import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
+import 'package:typed_graphql_codegen/src/plan/operation_text.dart';
 import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';
 
 import '../support/plan_fixture.dart';
@@ -23,6 +24,7 @@ void main() {
   final fixture = PlanFixture(_schema, _document);
   final emitter = DocumentLibraryEmitter(
     ShapePlanner(fixture.schema, fixture.fragments),
+    OperationText(fixture.schema, fixture.fragments),
     TypeMapper(fixture.schema, const {}),
     LibraryImports(fixture.schema, 'lib/schema.graphql.dart', const {
       'Outer': 'lib/a/b.graphql.dart',
```

In `packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,10 +40,10 @@ final class QDataUserFragments implements client.DataObject {
   final F2? f2;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...f1.toJson().fields,
-    ...?f2?.toJson().fields,
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    f1.toJson(),
+    f2?.toJson(),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -228,11 +228,13 @@ final class HeldUser implements Held {
   final HeldFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': const graphql.JsonString('User'),
-    'name': _nameCodec.write(name),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      '__typename': const graphql.JsonString('User'),
+      'name': _nameCodec.write(name),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -269,10 +271,10 @@ final class OwnUser implements Own {
   final OwnUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': const graphql.JsonString('User'),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({'__typename': const graphql.JsonString('User')}),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -154,7 +154,7 @@ type Query {
     expect(result.files, hasLength(1));
   });
 
-  test('an introspection enum reached through __type is generated', () {
+  test('a document that selects __type is not generated', () {
     final built = const SchemaBuilder().fromSdl(
       const Parser().parse(Source(_schema.text)).requireDocument(),
     ) as BuildSuccess;
@@ -170,13 +170,12 @@ type Query {
         ),
       ],
     );
-    expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
+    expect(result.files, isEmpty);
     expect(
-      result.files.first.text,
-      allOf(
-        contains(r'sealed class $$TypeKind'),
-        contains(r'enum $$TypeKindKnown'),
-      ),
+      [for (final d in result.diagnostics) d.code],
+      [
+        DiagnosticCode.unsupportedInDocument,
+      ],
     );
   });
 
```

In `packages/typed_graphql_codegen/test/generator/client_generator_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 import 'package:typed_graphql_codegen/src/generator/rules/named_operations_rule.dart';
 import 'package:typed_graphql_codegen/src/generator/rules/subscription_root_rule.dart';
 import 'package:typed_graphql_codegen/src/generator/rules/unsupported_directives_rule.dart';
+import 'package:typed_graphql_codegen/src/generator/rules/unsupported_introspection_rule.dart';
 import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';
 
 const _schema = ProjectFile('schema.graphql', '''
@@ -118,6 +119,38 @@ void main() {
       );
     });
 
+    test('__schema is not supported yet', () {
+      expect(
+        check(const [
+          ProjectFile(
+            'a.graphql',
+            'query A {\n  __schema { queryType { name } }\n}\n',
+          ),
+        ]),
+        [
+          'a.graphql:2:3: error GQL504: The document selects the '
+              "introspection field '__schema', which the code generator "
+              'does not support yet.',
+        ],
+      );
+    });
+
+    test('__type is not supported yet', () {
+      expect(
+        check(const [
+          ProjectFile(
+            'a.graphql',
+            'query A {\n  __type(name: "User") { name }\n}\n',
+          ),
+        ]),
+        [
+          'a.graphql:2:3: error GQL504: The document selects the '
+              "introspection field '__type', which the code generator does "
+              'not support yet.',
+        ],
+      );
+    });
+
     test('@stream is not supported yet', () {
       final schema = ProjectFile(
         'schema.graphql',
@@ -247,6 +280,7 @@ scalars:
             if (!dropped.contains(rule.runtimeType)) rule.runtimeType,
           NamedOperationsRule,
           UnsupportedDirectivesRule,
+          UnsupportedIntrospectionRule,
           SubscriptionRootRule,
         ],
       );
```

In `packages/typed_graphql_codegen/test/generator/document_names_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,7 @@ interface Node { id: ID! }
 type Query implements Node {
   id: ID!
   hello: String
+  node: Node
   user(a: ID, b: ID): User
 }
 type Subscription implements Node {
@@ -16,18 +17,22 @@ type User {
   id: ID!
   name: String
 }
+type Unknown implements Node {
+  id: ID!
+}
 ''');
 
 void main() {
   List<String> check(
     List<ProjectFile> documents, {
     String config = 'schema: schema.graphql\n',
+    ProjectFile schema = _schema,
   }) {
     final parsed = CodegenConfig.parse(config, path: 'typed_graphql.yaml');
     if (parsed is! ConfigSuccess) fail('expected success, got $parsed');
     final diagnostics = ClientGenerator(
       parsed.config,
-    ).check(schema: _schema, documents: documents);
+    ).check(schema: schema, documents: documents);
     return [
       for (final diagnostic in diagnostics)
         [
@@ -140,6 +145,85 @@ void main() {
     });
   });
 
+  group('reserved names', () {
+    test('a fragment named List hides the Dart type', () {
+      expect(
+        check(const [
+          ProjectFile('lib/a.graphql', 'fragment List on User { id }'),
+        ]),
+        [
+          "lib/a.graphql:1:10: error GQL508: The generated name 'List' would "
+              "hide the Dart type 'List' the generated code uses.",
+        ],
+      );
+    });
+
+    test('an operation named List has no class of that name', () {
+      expect(
+        check(const [ProjectFile('lib/a.graphql', 'query List { hello }')]),
+        isEmpty,
+      );
+    });
+  });
+
+  group('variants', () {
+    test('a type named Unknown collides with the unknown class', () {
+      expect(
+        check(const [
+          ProjectFile(
+            'lib/a.graphql',
+            'query Q { node { id ... on Unknown { id } } }',
+          ),
+        ]),
+        [
+          'lib/a.graphql:1:11: error GQL507: The generated name '
+              "'QDataNodeUnknown' is declared twice: by the class for the "
+              "type 'Unknown' in the operation 'Q' and by the class for any "
+              "other type in the operation 'Q'. | also lib/a.graphql:1:11",
+        ],
+      );
+    });
+  });
+
+  group('limits', () {
+    // Every alias reaches all the types that implement `Many`: a class per
+    // type and alias from a few tokens.
+    final schema = ProjectFile('schema.graphql', '''
+interface Many { id: ID! }
+interface Reached { id: ID! }
+${[for (var i = 0; i < 1000; i++) 'type T$i implements Many & Reached { id: ID! }'].join('\n')}
+type Query { many: Many }
+''');
+    final fields = [
+      for (var index = 0; index < 11; index++)
+        'f$index: many { ... on Reached { id } }',
+    ].join(' ');
+
+    test('an operation that needs too many classes is a GQL511', () {
+      expect(
+        check([
+          ProjectFile('lib/a.graphql', 'query Q { $fields }'),
+        ], schema: schema),
+        [
+          'lib/a.graphql:1:7: error GQL511: The code generator would declare '
+              "more than 10000 classes for the operation 'Q'.",
+        ],
+      );
+    });
+
+    test('a fragment that needs too many classes is a GQL511', () {
+      expect(
+        check([
+          ProjectFile('lib/a.graphql', 'fragment F on Query { $fields }'),
+        ], schema: schema),
+        [
+          'lib/a.graphql:1:10: error GQL511: The code generator would declare '
+              "more than 10000 classes for the fragment 'F'.",
+        ],
+      );
+    });
+  });
+
   group('files', () {
     test('a document library at the path of the schema types', () {
       expect(
@@ -158,26 +242,70 @@ void main() {
   group('the subscription root', () {
     const document = ProjectFile('lib/a.graphql', '''
 subscription OnNode { ...NodeCard }
-fragment NodeCard on Node { id }
+fragment NodeCard on Node { id ... on Query { hello } }
 ''');
 
-    test('a fragment on an abstract type is a GQL504 at the spread', () {
+    test('a sealed fragment is a GQL504 at the spread', () {
       expect(check(const [document]), [
         "lib/a.graphql:1:23: error GQL504: The subscription 'OnNode' spreads "
-            "the fragment 'NodeCard' on the abstract type 'Node' at its root, "
-            "where '__typename' cannot be selected.",
+            "'...NodeCard' at its root, which reads the fragment 'NodeCard' on "
+            "the abstract type 'Node'; the root would need '__typename', which "
+            'a subscription cannot select.',
       ]);
     });
 
-    test('an inline fragment on an abstract type is a GQL504 too', () {
+    test('a sealed fragment behind another spread names both', () {
+      expect(
+        check(const [
+          ProjectFile('lib/a.graphql', '''
+subscription OnNode { ...Outer }
+fragment Outer on Subscription { ...NodeCard }
+fragment NodeCard on Node { id ... on Query { hello } }
+'''),
+        ]).single,
+        "lib/a.graphql:1:23: error GQL504: The subscription 'OnNode' spreads "
+        "'...Outer' at its root, which reads the fragment 'NodeCard' on the "
+        "abstract type 'Node'; the root would need '__typename', which a "
+        'subscription cannot select.',
+      );
+    });
+
+    test('a fragment on an abstract type without narrowing is fine', () {
+      expect(
+        check(const [
+          ProjectFile('lib/a.graphql', '''
+subscription OnNode { ...NodeCard }
+fragment NodeCard on Node { id }
+'''),
+        ]),
+        isEmpty,
+      );
+    });
+
+    test('an inline fragment on an abstract type is fine', () {
       expect(
         check(const [
           ProjectFile(
             'lib/a.graphql',
             'subscription OnNode { ... on Node { id } }',
           ),
-        ]).single,
-        contains("has an inline fragment on the abstract type 'Node'"),
+        ]),
+        isEmpty,
+      );
+    });
+
+    test('an anonymous subscription is only a GQL503', () {
+      expect(
+        check(const [
+          ProjectFile('lib/a.graphql', '''
+subscription { ...NodeCard }
+fragment NodeCard on Node { id ... on Query { hello } }
+'''),
+        ]),
+        [
+          'lib/a.graphql:1:1: error GQL503: An operation needs a name: its '
+              'classes are named after it.',
+        ],
       );
     });
 
@@ -186,7 +314,7 @@ fragment NodeCard on Node { id }
         check(const [
           ProjectFile('lib/a.graphql', '''
 query Q { ...NodeCard }
-fragment NodeCard on Node { id }
+fragment NodeCard on Node { id ... on Query { hello } }
 '''),
         ]),
         isEmpty,
```

In `packages/typed_graphql_codegen/test/generator/generated_names_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -175,4 +175,16 @@ type Query { a: Int }
       expect(diagnostic.related, hasLength(1));
     });
   });
+
+  test('the problems stop after 100 errors with one GQL000', () {
+    final names = GeneratedNames();
+    for (var index = 0; index < 150; index++) {
+      names
+        ..register('A$index', 'the first', null)
+        ..register('A$index', 'the second', null);
+    }
+    final diagnostics = names.diagnostics;
+    expect(diagnostics, hasLength(101));
+    expect(diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
+  });
 }
```

Create `packages/typed_graphql_codegen/test/generator/typename_generation_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

const _schema = ProjectFile('schema.graphql', '''
interface Node { id: ID! }
type User implements Node { id: ID!, name: String }
type Bot implements Node { id: ID! }
type Query { me: User, node: Node }
''');

void main() {
  String generated(String document) {
    final parsed = CodegenConfig.parse(
      'schema: schema.graphql\n',
      path: 'typed_graphql.yaml',
    );
    if (parsed is! ConfigSuccess) fail('expected success, got $parsed');
    final result = ClientGenerator(parsed.config).generate(
      schema: _schema,
      documents: [ProjectFile('lib/a.graphql', document)],
    );
    expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
    return result.files.last.text;
  }

  test('a conditional __typename is a nullable member', () {
    expect(
      generated(r'''
query A($on: Boolean!) { me { __typename @include(if: $on) id } }
'''),
      contains('final String? typename;'),
    );
  });

  test('a conditional __typename does not replace the added one', () {
    expect(
      generated(r'''
query A($on: Boolean!) { me { __typename @include(if: $on) id } }
'''),
      contains(r'me{__typename@include(if:$on)id __typename}'),
    );
  });

  test('a conditional __typename on an abstract type still dispatches', () {
    expect(
      generated(r'''
query A($on: Boolean!) { node { __typename @include(if: $on) id ... on User { name } } }
'''),
      allOf(
        contains('sealed class ADataNode'),
        contains(
          r'node{__typename@include(if:$on)id ...on User{name}__typename}',
        ),
      ),
    );
  });
}
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_avatar.graphql`:

```graphql
fragment AvatarUrl on User {
  avatar {
    url
  }
}

fragment AvatarSize on User {
  avatar {
    size
  }
}

fragment WithAvatars on User {
  avatar {
    url
  }
  ...AvatarUrl
  ...AvatarSize
}
```

In `packages/typed_graphql_codegen/test/goldens/fragments/input/schema.graphql`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -44,8 +44,14 @@ interface Node {
   id: ID!
 }
 
+type Avatar {
+  url: String!
+  size: Int!
+}
+
 type User implements Node {
   id: ID!
+  avatar: Avatar
   "The display name."
   name: String!
   role: Role!
```

Create `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_avatar.graphql.dart.golden`:

```dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user_avatar.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The fragment `AvatarUrl` on `User`.
final class AvatarUrl implements client.DataObject {
  /// Creates the fragment.
  const AvatarUrl({this.avatar});

  factory AvatarUrl._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => AvatarUrl(avatar: _avatarCodec.field(json, 'avatar', context));

  /// Reads and writes the fragment.
  static const client.DataCodec<AvatarUrl> codec =
      client.ObjectDataCodec(AvatarUrl._read);

  static const client.DataCodec<AvatarUrlAvatar?> _avatarCodec =
      client.NullableDataCodec(AvatarUrlAvatar.codec);

  /// The field `avatar`.
  final AvatarUrlAvatar? avatar;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<AvatarUrl> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'avatar': _avatarCodec.write(avatar)});

  @override
  bool operator ==(Object other) =>
      other is AvatarUrl && other.avatar == avatar;

  @override
  int get hashCode => avatar.hashCode;

  @override
  String toString() => 'AvatarUrl(avatar: $avatar)';
}

/// The field `avatar` of [AvatarUrl].
final class AvatarUrlAvatar implements client.DataObject {
  /// Creates the value.
  const AvatarUrlAvatar({required this.url});

  factory AvatarUrlAvatar._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => AvatarUrlAvatar(url: _urlCodec.field(json, 'url', context));

  /// Reads and writes the value.
  static const client.DataCodec<AvatarUrlAvatar> codec =
      client.ObjectDataCodec(AvatarUrlAvatar._read);

  static const client.DataCodec<String> _urlCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `url`.
  final String url;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'url': _urlCodec.write(url)});

  @override
  bool operator ==(Object other) =>
      other is AvatarUrlAvatar && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'AvatarUrlAvatar(url: $url)';
}

/// The fragment `AvatarSize` on `User`.
final class AvatarSize implements client.DataObject {
  /// Creates the fragment.
  const AvatarSize({this.avatar});

  factory AvatarSize._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => AvatarSize(avatar: _avatarCodec.field(json, 'avatar', context));

  /// Reads and writes the fragment.
  static const client.DataCodec<AvatarSize> codec =
      client.ObjectDataCodec(AvatarSize._read);

  static const client.DataCodec<AvatarSizeAvatar?> _avatarCodec =
      client.NullableDataCodec(AvatarSizeAvatar.codec);

  /// The field `avatar`.
  final AvatarSizeAvatar? avatar;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<AvatarSize> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'avatar': _avatarCodec.write(avatar)});

  @override
  bool operator ==(Object other) =>
      other is AvatarSize && other.avatar == avatar;

  @override
  int get hashCode => avatar.hashCode;

  @override
  String toString() => 'AvatarSize(avatar: $avatar)';
}

/// The field `avatar` of [AvatarSize].
final class AvatarSizeAvatar implements client.DataObject {
  /// Creates the value.
  const AvatarSizeAvatar({required this.size});

  factory AvatarSizeAvatar._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => AvatarSizeAvatar(size: _sizeCodec.field(json, 'size', context));

  /// Reads and writes the value.
  static const client.DataCodec<AvatarSizeAvatar> codec =
      client.ObjectDataCodec(AvatarSizeAvatar._read);

  static const client.DataCodec<int> _sizeCodec =
      client.ScalarDataCodec(graphql.IntCodec());

  /// The field `size`.
  final int size;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'size': _sizeCodec.write(size)});

  @override
  bool operator ==(Object other) =>
      other is AvatarSizeAvatar && other.size == size;

  @override
  int get hashCode => size.hashCode;

  @override
  String toString() => 'AvatarSizeAvatar(size: $size)';
}

/// The fragment `WithAvatars` on `User`.
final class WithAvatars implements client.DataObject {
  /// Creates the fragment.
  const WithAvatars({required this.fragments, this.avatar});

  factory WithAvatars._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => WithAvatars(
    avatar: _avatarCodec.field(json, 'avatar', context),
    fragments: WithAvatarsFragments._read(json, context),
  );

  /// Reads and writes the fragment.
  static const client.DataCodec<WithAvatars> codec =
      client.ObjectDataCodec(WithAvatars._read);

  static const client.DataCodec<WithAvatarsAvatar?> _avatarCodec =
      client.NullableDataCodec(WithAvatarsAvatar.codec);

  /// The field `avatar`.
  final WithAvatarsAvatar? avatar;

  /// The fragments spread on this value.
  final WithAvatarsFragments fragments;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<WithAvatars> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => const client.JsonMerger().merge([
    fragments.toJson(),
    graphql.JsonObject({'avatar': _avatarCodec.write(avatar)}),
  ]);

  @override
  bool operator ==(Object other) =>
      other is WithAvatars &&
      other.avatar == avatar &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([avatar, fragments]);

  @override
  String toString() => 'WithAvatars(avatar: $avatar, fragments: $fragments)';
}

/// The field `avatar` of [WithAvatars].
final class WithAvatarsAvatar implements client.DataObject {
  /// Creates the value.
  const WithAvatarsAvatar({required this.url});

  factory WithAvatarsAvatar._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => WithAvatarsAvatar(url: _urlCodec.field(json, 'url', context));

  /// Reads and writes the value.
  static const client.DataCodec<WithAvatarsAvatar> codec =
      client.ObjectDataCodec(WithAvatarsAvatar._read);

  static const client.DataCodec<String> _urlCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `url`.
  final String url;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'url': _urlCodec.write(url)});

  @override
  bool operator ==(Object other) =>
      other is WithAvatarsAvatar && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'WithAvatarsAvatar(url: $url)';
}

/// The fragments spread on [WithAvatars].
final class WithAvatarsFragments implements client.DataObject {
  /// Creates the fragments.
  const WithAvatarsFragments({
    required this.avatarUrl,
    required this.avatarSize,
  });

  factory WithAvatarsFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => WithAvatarsFragments(
    avatarUrl: AvatarUrl.codec.read(json, context),
    avatarSize: AvatarSize.codec.read(json, context),
  );

  /// The fragment `AvatarUrl`.
  final AvatarUrl avatarUrl;

  /// The fragment `AvatarSize`.
  final AvatarSize avatarSize;

  @override
  graphql.JsonObject toJson() => const client.JsonMerger().merge([
    avatarUrl.toJson(),
    avatarSize.toJson(),
  ]);

  @override
  bool operator ==(Object other) =>
      other is WithAvatarsFragments &&
      other.avatarUrl == avatarUrl &&
      other.avatarSize == avatarSize;

  @override
  int get hashCode => Object.hashAll([avatarUrl, avatarSize]);

  @override
  String toString() =>
      'WithAvatarsFragments(avatarUrl: $avatarUrl, avatarSize: $avatarSize)';
}
```

In `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -93,16 +93,18 @@ final class UserCard implements client.DataObject {
   }) => codec.decode(json, client.DataContext(variables));
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': _typenameCodec.write(typename),
-    '_id': _$idCodec.write($id),
-    'default': _default$Codec.write(default$),
-    'role': _roleCodec.write(role),
-    'createdAt': _createdAtCodec.write(createdAt),
-    'cursor': _cursorCodec.write(cursor),
-    'friends': _friendsCodec.write(friends),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      '__typename': _typenameCodec.write(typename),
+      '_id': _$idCodec.write($id),
+      'default': _default$Codec.write(default$),
+      'role': _roleCodec.write(role),
+      'createdAt': _createdAtCodec.write(createdAt),
+      'cursor': _cursorCodec.write(cursor),
+      'friends': _friendsCodec.write(friends),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -160,10 +162,10 @@ final class UserCardFriends implements client.DataObject {
   final UserCardFriendsFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    'id': _idCodec.write(id),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({'id': _idCodec.write(id)}),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -126,8 +126,7 @@ final class CardQueryDataUser implements client.DataObject {
   final CardQueryDataUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() =>
-      graphql.JsonObject({...fragments.toJson().fields});
+  graphql.JsonObject toJson() => fragments.toJson();
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'dart:io';
 
 import 'package:generated_fragments/schema.graphql.dart';
+import 'package:generated_fragments/user_avatar.graphql.dart';
 import 'package:generated_fragments/user_card.graphql.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
@@ -45,6 +46,27 @@ void main() {
     _fail('values that differ in a fragment are equal');
   }
   _wrongType(json);
+  _overlappingSelections();
+}
+
+// A class and the fragments it spreads select `avatar` with different
+// sub-fields: toJson keeps the sub-fields of each.
+void _overlappingSelections() {
+  final JsonObject json = _json(
+    '{"avatar": {"url": "u", "size": 3}}',
+  );
+  final DecodeResult<WithAvatars> result = WithAvatars.decode(json);
+  if (result is! DecodeSuccess<WithAvatars>) {
+    _fail('decode failed: $result');
+  }
+  final WithAvatars value = (result as DecodeSuccess<WithAvatars>).value;
+  if (value.toJson() != json) {
+    _fail('toJson lost a sub-field: ${value.toJson()}');
+  }
+  final DecodeResult<WithAvatars> again = WithAvatars.decode(value.toJson());
+  if (again is! DecodeSuccess<WithAvatars> || again.value != value) {
+    _fail('decode(toJson()) is $again, not $value');
+  }
 }
 
 JsonObject _json(String text) =>
```

In `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -191,13 +191,15 @@ final class GetUserDataUser implements client.DataObject {
   final GetUserDataUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    'role': _roleCodec.write(role),
-    'createdAt': _createdAtCodec.write(createdAt),
-    'cursor': _cursorCodec.write(cursor),
-    'friends': _friendsCodec.write(friends),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      'role': _roleCodec.write(role),
+      'createdAt': _createdAtCodec.write(createdAt),
+      'cursor': _cursorCodec.write(cursor),
+      'friends': _friendsCodec.write(friends),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -510,12 +512,14 @@ final class FindNodeDataNodeUser implements FindNodeDataNode {
   final FindNodeDataNodeUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': const graphql.JsonString('User'),
-    'id': _idCodec.write(id),
-    'name': _nameCodec.write(name),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      '__typename': const graphql.JsonString('User'),
+      'id': _idCodec.write(id),
+      'name': _nameCodec.write(name),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_mutations.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -414,8 +414,7 @@ final class RenameUserDataRenameUser implements client.DataObject {
   final RenameUserDataRenameUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() =>
-      graphql.JsonObject({...fragments.toJson().fields});
+  graphql.JsonObject toJson() => fragments.toJson();
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_node.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -75,12 +75,14 @@ final class NodeCardUser implements NodeCard {
   final NodeCardUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': const graphql.JsonString('User'),
-    'id': _idCodec.write(id),
-    'name': _nameCodec.write(name),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      '__typename': const graphql.JsonString('User'),
+      'id': _idCodec.write(id),
+      'name': _nameCodec.write(name),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -143,8 +143,7 @@ final class FindNodeDataNode implements client.DataObject {
   final FindNodeDataNodeFragments fragments;
 
   @override
-  graphql.JsonObject toJson() =>
-      graphql.JsonObject({...fragments.toJson().fields});
+  graphql.JsonObject toJson() => fragments.toJson();
 
   @override
   bool operator ==(Object other) =>
@@ -190,12 +189,12 @@ final class FindNodeDataNodeFragments implements client.DataObject {
   final Labelled labelled;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...nodeCard.toJson().fields,
-    ...owned.toJson().fields,
-    ...reselect.toJson().fields,
-    ...labelled.toJson().fields,
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    nodeCard.toJson(),
+    owned.toJson(),
+    reselect.toJson(),
+    labelled.toJson(),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -233,8 +232,7 @@ final class FindNodeDataSearch implements client.DataObject {
   final FindNodeDataSearchFragments fragments;
 
   @override
-  graphql.JsonObject toJson() =>
-      graphql.JsonObject({...fragments.toJson().fields});
+  graphql.JsonObject toJson() => fragments.toJson();
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_result.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -275,11 +275,13 @@ final class LabelledUser implements Labelled {
   final LabelledFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': const graphql.JsonString('User'),
-    'name': _nameCodec.write(name),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      '__typename': const graphql.JsonString('User'),
+      'name': _nameCodec.write(name),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -320,11 +322,13 @@ final class LabelledBot implements Labelled {
   final LabelledFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': const graphql.JsonString('Bot'),
-    'model': _modelCodec.write(model),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      '__typename': const graphql.JsonString('Bot'),
+      'model': _modelCodec.write(model),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -362,10 +366,10 @@ final class LabelledUnknown implements Labelled {
   final LabelledFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    '__typename': _typenameCodec.write(typename),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({'__typename': _typenameCodec.write(typename)}),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

In `packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -191,13 +191,15 @@ final class GetUserDataUser implements client.DataObject {
   final GetUserDataUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    'role': _roleCodec.write(role),
-    'createdAt': _createdAtCodec.write(createdAt),
-    'cursor': _cursorCodec.write(cursor),
-    'friends': _friendsCodec.write(friends),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({
+      'role': _roleCodec.write(role),
+      'createdAt': _createdAtCodec.write(createdAt),
+      'cursor': _cursorCodec.write(cursor),
+      'friends': _friendsCodec.write(friends),
+    }),
+  ]);
 
   @override
   bool operator ==(Object other) =>
```

Create `packages/typed_graphql_codegen/test/plan/class_sharing_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_description.dart';
import '../support/plan_fixture.dart';

const _schema = '''
interface Node { id: ID! }
interface Named { tag: Tag }
type Tag { label: String }
type A implements Node & Named { id: ID!, tag: Tag }
type B implements Node & Named { id: ID!, tag: Tag }
type C implements Node { id: ID! }
type Query { node: Node, a: Node }
''';

void main() {
  const description = PlanDescription();

  ShapePlanner plannerOf(PlanFixture fixture) =>
      ShapePlanner(fixture.schema, fixture.fragments);

  OperationDefinition firstOperation(PlanFixture fixture) =>
      fixture.document.definitions.whereType<OperationDefinition>().first;

  test('variants that select a field with the same nodes share its class', () {
    final fixture = PlanFixture(
      _schema,
      'query { node { id ... on Named { tag { label } } } }',
    );
    final plan = plannerOf(fixture).planOperation(firstOperation(fixture));
    expect(
      description.describe(plan),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  id: ID! <- id
  variants: A=DataNodeA, B=DataNodeB, unknown=DataNodeUnknown
DataNodeA (variant on A, implements DataNode)
  @override id: ID! <- id
  tag: Tag <- tag -> DataNodeATag
DataNodeATag (nested on Tag, of DataNodeA.tag)
  label: String <- label
DataNodeB (variant on B, implements DataNode)
  @override id: ID! <- id
  tag: Tag <- tag -> DataNodeATag
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  @override id: ID! <- id''',
    );
  });

  test('a document that needs more than the limit is cut off', () {
    final fields = [
      for (var index = 0; index <= ShapePlanner.maxClasses; index++)
        'f$index: a { id }',
    ].join(' ');
    final fixture = PlanFixture(_schema, 'query { $fields }');
    final planner = plannerOf(fixture);
    final operation = firstOperation(fixture);
    expect(planner.planOperation(operation), isEmpty);
    expect(planner.exceedsLimit(operation), isTrue);
  });

  test('a document at the limit is planned', () {
    final fields = [
      for (var index = 0; index < ShapePlanner.maxClasses - 3; index++)
        'f$index: a { id }',
    ].join(' ');
    final fixture = PlanFixture(_schema, 'query { $fields }');
    final planner = plannerOf(fixture);
    final operation = firstOperation(fixture);
    expect(planner.planOperation(operation), hasLength(greaterThan(9990)));
    expect(planner.exceedsLimit(operation), isFalse);
  });

  test('a definition is planned once', () {
    final fixture = PlanFixture(_schema, 'query { node { id } }');
    final planner = plannerOf(fixture);
    final operation = firstOperation(fixture);
    expect(
      identical(
        planner.planOperation(operation),
        planner.planOperation(operation),
      ),
      isTrue,
    );
  });

  test(
    'a field every variant selects differently is planned once per list',
    () {
      // At each level the base `z` has the next level inside, and each type
      // adds a `z` of its own: the base `z` is not shared by the variants, so
      // planned per variant the classes would number (types + 1) to the power
      // of the depth, from a document of linear size.
      const types = 5;
      const depth = 4;
      final schema = StringBuffer('interface N { id: ID!, z: N }\n')
        ..writeln('type Query { n: N }');
      for (var type = 0; type < types; type++) {
        schema.writeln('type T$type implements N { id: ID!, z: N }');
      }
      final own = [
        for (var type = 0; type < types; type++) '... on T$type { z { id } }',
      ].join(' ');
      var body = 'id';
      for (var level = 0; level < depth; level++) {
        body = 'id z { $body } $own';
      }
      final fixture = PlanFixture('$schema', 'query { n { $body } }');
      final planner = plannerOf(fixture);
      final operation = firstOperation(fixture);
      final classes = planner.planOperation(operation);
      expect(planner.exceedsLimit(operation), isFalse);
      expect(classes.length, lessThan(200));
    },
  );
}
```

In `packages/typed_graphql_codegen/test/plan/field_collector_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -110,15 +110,13 @@ void main() {
     expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
   });
 
-  test('a narrowing inline fragment holds its source', () {
+  test('a narrowing inline fragment under @include is recorded', () {
     final selection = collect(
       r'node { ... on User @include(if: $v) { name } }',
       'Node',
       field: 'node',
     );
-    final narrowing = selection.narrowings.single;
-    expect(narrowing.source!.isConditional, isTrue);
-    expect(narrowing.source!.conditions, [const Condition('v', true)]);
+    expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
   });
 
   test('a disjoint condition is dropped', () {
@@ -150,9 +148,7 @@ void main() {
       field: 'node',
       fragments: 'fragment F on User { name }',
     );
-    final narrowing = selection.narrowings.single;
-    expect(narrowing.fragmentName, 'F');
-    expect(narrowing.conditions, [const Condition('w', false)]);
+    expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
     expect(selection.fragments, isEmpty);
   });
 
@@ -265,4 +261,41 @@ void main() {
     ]);
     expect(fieldsOf(selection), ['name:namex1']);
   });
+
+  group('__typename', () {
+    test('an unconditional one on an object is not a field group', () {
+      final selection = collect('user { __typename id }', 'User');
+      expect(selection.selectsTypename, isTrue);
+      expect(fieldsOf(selection), ['id:idx1']);
+    });
+
+    test('a conditional one on an object is a conditional field', () {
+      final selection = collect(
+        r'user { __typename @include(if: $v) id }',
+        'User',
+      );
+      expect(selection.selectsTypename, isFalse);
+      expect(fieldsOf(selection), ['__typename:__typename?x1', 'id:idx1']);
+      expect(selection.fields.first.isConditional, isTrue);
+    });
+
+    test('an unconditional one beside a conditional one wins', () {
+      final selection = collect(
+        r'user { __typename @include(if: $v) __typename id }',
+        'User',
+      );
+      expect(selection.selectsTypename, isTrue);
+      expect(fieldsOf(selection), ['id:idx1']);
+    });
+
+    test('a conditional one on an abstract type is always read', () {
+      final selection = collect(
+        r'node { __typename @include(if: $v) id }',
+        'Node',
+        field: 'node',
+      );
+      expect(selection.selectsTypename, isTrue);
+      expect(fieldsOf(selection), ['id:idx1']);
+    });
+  });
 }
```

In `packages/typed_graphql_codegen/test/plan/operation_text_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -101,33 +101,44 @@ fragment Y on User { name }
     );
   });
 
-  test('a fragment on an abstract type at the root adds __typename', () {
+  test('a sealed fragment at the root adds __typename', () {
     expect(
       textOf(_schema, '''
 query { ...Identified user { id } }
-fragment Identified on Root { id }
+fragment Identified on Root { id ... on Query { user { id } } }
 '''),
       '{...Identified user{id __typename}__typename}'
-      'fragment Identified on Root{id}',
+      'fragment Identified on Root{id ...on Query{user{id __typename}}}',
     );
   });
 
-  test('an inline fragment on an abstract type at the root adds it', () {
+  test('a fragment on an abstract type without narrowing adds nothing', () {
+    expect(
+      textOf(_schema, '''
+query { ...Identified }
+fragment Identified on Root { id }
+'''),
+      '{...Identified}fragment Identified on Root{id}',
+    );
+  });
+
+  test('an inline fragment on an abstract type at the root adds nothing', () {
     expect(
       textOf(_schema, 'query { ... on Root { id } }'),
-      '{...on Root{id}__typename}',
+      '{...on Root{id}}',
     );
   });
 
-  test('an abstract fragment inside a root fragment adds it', () {
+  test('a sealed fragment inside a root fragment adds it', () {
     expect(
       textOf(_schema, '''
 query { ...Outer }
 fragment Outer on Query { ...Identified }
-fragment Identified on Root { id }
+fragment Identified on Root { id ... on Query { id } }
 '''),
       '{...Outer __typename}'
-      'fragment Identified on Root{id}fragment Outer on Query{...Identified}',
+      'fragment Identified on Root{id ...on Query{id}}'
+      'fragment Outer on Query{...Identified}',
     );
   });
 
@@ -145,9 +156,10 @@ fragment Everything on Query { id }
     expect(
       textOf(_schema, '''
 subscription { ...Identified }
-fragment Identified on Root { id }
+fragment Identified on Root { id ... on Subscription { id } }
 '''),
-      'subscription{...Identified}fragment Identified on Root{id}',
+      'subscription{...Identified}'
+      'fragment Identified on Root{id ...on Subscription{id}}',
     );
   });
 
@@ -158,4 +170,24 @@ fragment Identified on Root { id }
       '{...UserCard __typename}}fragment UserCard on User{id name}',
     );
   });
+
+  test('a __typename under @include does not stand in for the added one', () {
+    expect(
+      textOf(
+        _schema,
+        r'query ($on: Boolean!) { user { __typename @include(if: $on) id } }',
+      ),
+      r'query($on:Boolean!){user{__typename@include(if:$on)id __typename}}',
+    );
+  });
+
+  test('a __typename under @skip does not stand in for it either', () {
+    expect(
+      textOf(
+        _schema,
+        r'query ($off: Boolean!) { user { __typename @skip(if: $off) id } }',
+      ),
+      r'query($off:Boolean!){user{__typename@skip(if:$off)id __typename}}',
+    );
+  });
 }
```

In `packages/typed_graphql_codegen/test/plan/shape_planner_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -215,4 +215,30 @@ SDataBorn (nested on User, of SData.born)
   id: ID! <- id''',
     );
   });
+
+  test('a __typename under @include is a nullable field', () {
+    expect(
+      plan(
+        r'query ($on: Boolean!) { user { __typename @include(if: $on) id } }',
+      ),
+      '''
+Data (operationData on Query)
+  user: User <- user -> DataUser
+DataUser (nested on User, of Data.user)
+  typename: String! <- __typename (conditional)
+  id: ID! <- id''',
+    );
+  });
+
+  test('an unconditional __typename is a required field', () {
+    expect(
+      plan('query { user { __typename id } }'),
+      '''
+Data (operationData on Query)
+  user: User <- user -> DataUser
+DataUser (nested on User, of Data.user)
+  typename: String! <- __typename
+  id: ID! <- id''',
+    );
+  });
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/data_class_emitter_test.dart test/emit/document_library_emitter_test.dart test/emit/fragment_holder_emitter_test.dart test/emit/polymorphic_base_emitter_test.dart test/generator/client_generator_generate_test.dart test/generator/client_generator_test.dart test/generator/document_names_test.dart test/generator/generated_names_test.dart test/generator/typename_generation_test.dart test/plan/class_sharing_test.dart test/plan/field_collector_test.dart test/plan/operation_text_test.dart test/plan/shape_planner_test.dart)
```

Expected: FAIL. The new and changed tests fail on the behaviour this task fixes (assertion failures; a test that uses a name the next step adds does not compile).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql_codegen/lib/src/emit/dart_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -113,16 +113,6 @@ final class DartNames {
     return result;
   }
 
-  /// [preferred], or the first of it with `$` appended until it is not in
-  /// [taken]: a parameter name that cannot hide a member.
-  String freeName(String preferred, Iterable<String> taken) {
-    int count = 0;
-    while (taken.contains('$preferred${r'$' * count}')) {
-      count++;
-    }
-    return '$preferred${r'$' * count}';
-  }
-
   /// [memberName] with its first character upper-cased, `$` kept.
   String capitalized(String memberName) => _upperFirst(memberName);
 
```

In `packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -231,13 +231,21 @@ final class DataClassEmitter {
     DataClassPlan plan,
     List<DataClassField> fields,
   ) {
-    const ToJsonWriter().write(writer, [
-      if (plan.holderName != null) '...fragments.toJson().fields',
+    final entries = [
       if (plan.variantTypeName case final typeName?)
         "'__typename': const graphql.JsonString("
             '${const DartStringLiteral().of(typeName)})',
       for (final field in fields)
         '${field.keyLiteral}: ${field.codecName}.write(${field.member})',
-    ]);
+    ];
+    if (plan.holderName == null) {
+      const ToJsonWriter().write(writer, entries);
+    } else {
+      const ToJsonWriter().writeMerged(
+        writer,
+        const ['fragments.toJson()'],
+        entries: entries,
+      );
+    }
   }
 }
```

In `packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,13 +21,22 @@ import 'variables_emitter.dart';
 ///
 /// {@category codegen}
 final class DocumentLibraryEmitter {
-  /// Creates the emitter; [planner] plans the classes, [mapper] maps their
-  /// types and [libraryImports] decides the imports.
-  const DocumentLibraryEmitter(this.planner, this.mapper, this.libraryImports);
+  /// Creates the emitter; [planner] plans the classes, [text] writes the
+  /// documents, [mapper] maps their types and [libraryImports] decides the
+  /// imports.
+  const DocumentLibraryEmitter(
+    this.planner,
+    this.text,
+    this.mapper,
+    this.libraryImports,
+  );
 
   /// The class planner.
   final ShapePlanner planner;
 
+  /// The writer of the document texts the operations are sent with.
+  final OperationText text;
+
   /// The mapper of field types.
   final TypeMapper mapper;
 
@@ -51,7 +60,6 @@ final class DocumentLibraryEmitter {
       for (final (definition, classes) in plans)
         if (definition is OperationDefinition && classes.isNotEmpty) definition,
     ]);
-    final text = OperationText(planner.schema, planner.fragments);
     var isFirst = true;
     for (final (definition, classes) in plans) {
       if (classes.isEmpty) continue;
```

In `packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -48,9 +48,7 @@ final class FragmentHolderEmitter {
         );
       }
       writer.line();
-      const ToJsonWriter().write(writer, [
-        for (final fragment in fragments) _spread(fragment),
-      ]);
+      _toJson(writer, fragments);
       writer.line();
       const ValueMembers().write(writer, plan.name, [
         for (final fragment in fragments)
@@ -59,9 +57,27 @@ final class FragmentHolderEmitter {
     });
   }
 
-  String _spread(PlannedFragment fragment) => fragment.isConditional
-      ? '...?${fragment.memberName}?.toJson().fields'
-      : '...${fragment.memberName}.toJson().fields';
+  // One fragment writes its JSON as it is; several may select the same
+  // response name, so their JSON is merged deeply.
+  void _toJson(DartWriter writer, List<PlannedFragment> fragments) {
+    if (fragments.length > 1) {
+      const ToJsonWriter().writeMerged(writer, [
+        for (final fragment in fragments) _json(fragment),
+      ]);
+      return;
+    }
+    const ToJsonWriter().write(writer, [
+      for (final fragment in fragments)
+        if (fragment.isConditional)
+          '...?${fragment.memberName}?.toJson().fields'
+        else
+          '...${fragment.memberName}.toJson().fields',
+    ]);
+  }
+
+  String _json(PlannedFragment fragment) => fragment.isConditional
+      ? '${fragment.memberName}?.toJson()'
+      : '${fragment.memberName}.toJson()';
 
   String _read(PlannedFragment fragment) {
     final String read = '${fragment.className}.codec.read(json, context)';
```

In `packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -37,4 +37,43 @@ final class ToJsonWriter {
     });
     writer.line('});');
   }
+
+  /// Writes `toJson` returning the deep merge of the JSON of [merged] (such
+  /// as `fragments.toJson()`) and an object of the map [entries].
+  ///
+  /// Shallow `...spreads` would let one side's value for a response name
+  /// replace the other's, losing the sub-fields it selected; `JsonMerger`
+  /// merges them. Without [entries] and with one expression, it is that
+  /// expression.
+  void writeMerged(
+    DartWriter writer,
+    List<String> merged, {
+    List<String> entries = const [],
+  }) {
+    writer.line('@override');
+    final parts = [
+      ...merged,
+      if (entries.isNotEmpty) 'graphql.JsonObject({${entries.join(', ')}})',
+    ];
+    if (parts.length == 1) {
+      writer.arrow(_head, parts.single);
+      return;
+    }
+    const String call = 'const client.JsonMerger().merge(';
+    final String single = '$_head => $call[${parts.join(', ')}]);';
+    if (writer.fits(single)) {
+      writer.line(single);
+      return;
+    }
+    writer.line('$_head => $call[');
+    writer.indented(() {
+      for (final String expression in merged) {
+        writer.line('$expression,');
+      }
+      if (entries.isNotEmpty) {
+        writer.items('graphql.JsonObject({', entries, '}),');
+      }
+    });
+    writer.line(']);');
+  }
 }
```

In `packages/typed_graphql_codegen/lib/src/generator/client_generator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,6 +16,7 @@ import 'persisted_manifest.dart';
 import 'rules/named_operations_rule.dart';
 import 'rules/subscription_root_rule.dart';
 import 'rules/unsupported_directives_rule.dart';
+import 'rules/unsupported_introspection_rule.dart';
 import 'schema_type_usage.dart';
 
 /// Generates typed Dart client code from a schema and `.graphql` documents.
@@ -62,6 +63,7 @@ final class const ClientGenerator(final CodegenConfig config) {
     UniqueInputFieldNamesRule(),
     NamedOperationsRule(),
     UnsupportedDirectivesRule(),
+    UnsupportedIntrospectionRule(),
     SubscriptionRootRule(),
   ];
 
@@ -124,8 +126,9 @@ final class const ClientGenerator(final CodegenConfig config) {
     final libraries = DocumentLibraries(project, mapper, config.schemaTypes);
     _registerFiles(names, project);
     DocumentNameChecker(project, libraries.planner, names).check();
-    if (names.diagnostics.isNotEmpty) {
-      return GenerationResult(const [], [...warnings, ...names.diagnostics]);
+    final problems = names.diagnostics;
+    if (problems.isNotEmpty) {
+      return GenerationResult(const [], [...warnings, ...problems]);
     }
     final text = SchemaTypesEmitter(mapper).emit(types, source: schemaPath);
     final manifest = config.persistedOperations;
@@ -162,9 +165,5 @@ final class const ClientGenerator(final CodegenConfig config) {
         firstDefinitions[index],
       );
     }
-    final manifest = config.persistedOperations;
-    if (manifest != null) {
-      names.registerFile(manifest, 'the persisted-operations manifest', null);
-    }
   }
 }
```

In `packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -32,9 +32,13 @@ final class DocumentLibraries {
   /// The planner of the project's classes.
   final ShapePlanner planner;
 
-  /// The writer of the document texts the operations are sent with.
-  OperationText get operationText =>
-      OperationText(planner.schema, planner.fragments);
+  /// The writer of the document texts the operations are sent with, shared
+  /// by the operation classes and the manifest.
+  // late: its initializer reads [planner], which a field initializer cannot.
+  late final OperationText operationText = OperationText(
+    planner.schema,
+    planner.fragments,
+  );
 
   /// A library per document file, sorted by path.
   List<GeneratedFile> generate() {
@@ -51,6 +55,7 @@ final class DocumentLibraries {
     }
     final emitter = DocumentLibraryEmitter(
       planner,
+      operationText,
       mapper,
       LibraryImports(project.schema.schema, schemaTypesPath, libraryOf),
     );
```

In `packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,7 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../emit/input_field.dart';
 import '../plan/class_names.dart';
+import '../plan/data_class_role.dart';
 import '../plan/planned_class.dart';
 import '../plan/planned_field.dart';
 import '../plan/shape_planner.dart';
@@ -32,21 +33,39 @@ final class DocumentNameChecker {
         case OperationDefinition():
           _operation(definition);
         case FragmentDefinition():
-          _plans(
-            "the fragment '${definition.name.value}'",
-            definition.name,
-            planner.planFragment(definition),
-          );
+          _fragment(definition);
         default:
       }
     }
   }
 
+  void _fragment(FragmentDefinition fragment) {
+    final String declarer = "the fragment '${fragment.name.value}'";
+    final classes = planner.planFragment(fragment);
+    if (planner.exceedsLimit(fragment)) {
+      _tooMany(declarer, fragment.name);
+      return;
+    }
+    _plans(declarer, fragment.name, classes);
+  }
+
+  void _tooMany(String declarer, Node definitionName) {
+    names.reportTooManyClasses(
+      declarer,
+      ShapePlanner.maxClasses,
+      _spanOf(definitionName),
+    );
+  }
+
   void _operation(OperationDefinition operation) {
     final String name = operation.name?.value ?? '';
     final String declarer = "the operation '$name'";
     final SourceSpan? span = _spanOf(operation.name ?? operation);
     final classes = planner.planOperation(operation);
+    if (planner.exceedsLimit(operation)) {
+      _tooMany(declarer, operation.name ?? operation);
+      return;
+    }
     if (classes.isEmpty) return;
     names.register(
       _classNames.operation(name, operation.operation),
@@ -74,7 +93,7 @@ final class DocumentNameChecker {
     for (final plan in plans) {
       names.register(
         plan.name,
-        declarer,
+        _declarerOf(plan, declarer),
         spans[plan.name] ??
             (switch (plan) {
               DataClassPlan(:final baseName?) => spans[baseName],
@@ -87,6 +106,17 @@ final class DocumentNameChecker {
     }
   }
 
+  // A variant for the type `Unknown` and the class for any other type of one
+  // selection have one name; saying "the operation" twice would not tell them
+  // apart.
+  String _declarerOf(PlannedClass plan, String declarer) => switch (plan) {
+    DataClassPlan(role: DataClassRole.variant, :final typeName) =>
+      "the class for the type '$typeName' in $declarer",
+    DataClassPlan(role: DataClassRole.unknownVariant) =>
+      'the class for any other type in $declarer',
+    _ => declarer,
+  };
+
   // The span of the first field node each nested class is the class of.
   Map<String, SourceSpan?> _fieldClassSpans(List<PlannedClass> plans) {
     final spans = <String, SourceSpan?>{};
```

In `packages/typed_graphql_codegen/lib/src/generator/generated_names.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,5 @@
+import 'dart:collection';
+
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../emit/dart_names.dart';
@@ -43,28 +45,32 @@ final class GeneratedNames {
   final List<Diagnostic> _diagnostics = [];
 
   /// The problems found so far, each once: by file, then offset; the ones
-  /// without a place last, in registration order.
+  /// without a place last, in registration order. Like every other run, the
+  /// list stops after [DiagnosticSink.defaultMaxErrors] errors with one
+  /// `GQL000`.
+  ///
+  /// It is computed on each call: read it once.
   List<Diagnostic> get diagnostics {
-    final unique = <Diagnostic>[];
-    for (final diagnostic in _diagnostics) {
-      if (!unique.contains(diagnostic)) unique.add(diagnostic);
+    final indexed = LinkedHashSet<Diagnostic>.of(_diagnostics).indexed.toList()
+      ..sort(_byPlace);
+    final sink = DiagnosticSink();
+    for (final (_, diagnostic) in indexed) {
+      sink.report(diagnostic);
     }
-    final indexed = unique.indexed.toList()
-      ..sort((a, b) {
-        final first = a.$2.span;
-        final second = b.$2.span;
-        if (first == null || second == null) {
-          if (first == second) return a.$1.compareTo(b.$1);
-          return first == null ? 1 : -1;
-        }
-        final byFile = first.source.name.compareTo(second.source.name);
-        if (byFile != 0) return byFile;
-        final byOffset = first.start.compareTo(second.start);
-        return byOffset != 0 ? byOffset : a.$1.compareTo(b.$1);
-      });
-    return List.unmodifiable([
-      for (final (_, diagnostic) in indexed) diagnostic,
-    ]);
+    return sink.diagnostics;
+  }
+
+  static int _byPlace((int, Diagnostic) a, (int, Diagnostic) b) {
+    final first = a.$2.span;
+    final second = b.$2.span;
+    if (first == null || second == null) {
+      if (first == second) return a.$1.compareTo(b.$1);
+      return first == null ? 1 : -1;
+    }
+    final byFile = first.source.name.compareTo(second.source.name);
+    if (byFile != 0) return byFile;
+    final byOffset = first.start.compareTo(second.start);
+    return byOffset != 0 ? byOffset : a.$1.compareTo(b.$1);
   }
 
   /// Records that [declarer] (such as `the enum 'Role'`) declares [name].
@@ -97,6 +103,20 @@ final class GeneratedNames {
     );
   }
 
+  /// Records that [declarer] (such as `the operation 'A'`) would generate
+  /// more than [limit] classes.
+  void reportTooManyClasses(String declarer, int limit, SourceSpan? span) {
+    _diagnostics.add(
+      Diagnostic(
+        .tooManyGeneratedClasses,
+        .error,
+        'The code generator would declare more than $limit classes for '
+        '$declarer.',
+        span: span,
+      ),
+    );
+  }
+
   /// Records that [declarer] writes the file at [path]; a second writer is a
   /// problem.
   void registerFile(String path, String declarer, SourceSpan? span) {
```

In `packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,19 +2,27 @@ import 'package:typed_graphql/typed_graphql.dart';
 
 import '../../plan/root_typename.dart';
 
-/// `GQL504`: a subscription whose root reads an abstract type would need
-/// `__typename` at its root, which a subscription cannot select.
+/// `GQL504`: a subscription whose root spreads a fragment that plans as a
+/// sealed class would need `__typename` at its root, which a subscription
+/// cannot select.
 final class const SubscriptionRootRule() extends ValidationRule {
   /// Creates the rule.
   this;
 
   @override
-  AstVisitor createVisitor(ValidationContext context) =>
-      _SubscriptionRoot(context);
+  AstVisitor createVisitor(ValidationContext context) => _SubscriptionRoot(
+    context,
+    RootTypename(context.schema, {
+      for (final definition in context.document.definitions)
+        if (definition is FragmentDefinition) definition.name.value: definition,
+    }),
+  );
 }
 
-final class _SubscriptionRoot(final ValidationContext context)
-    extends AstVisitor {
+final class _SubscriptionRoot(
+  final ValidationContext context,
+  final RootTypename rootTypename,
+) extends AstVisitor {
   @override
   VisitAction enter(Node node) {
     switch (node) {
@@ -28,20 +36,20 @@ final class _SubscriptionRoot(final ValidationContext context)
     }
   }
 
+  // An anonymous subscription is a GQL503 already.
   void _check(OperationDefinition operation) {
-    final found = RootTypename(
-      context.schema,
-      context.fragmentNamed,
-    ).find(operation.selectionSet);
-    if (found == null) return;
-    final String what = found.fragmentName == null
-        ? 'has an inline fragment on'
-        : "spreads the fragment '${found.fragmentName}' on";
+    final String? name = operation.name?.value;
+    final found = rootTypename.find(operation.selectionSet);
+    if (name == null || found == null) return;
+    final String where = switch (found.selection) {
+      FragmentSpread(:final name) => "spreads '...${name.value}' at its root",
+      _ => 'has an inline fragment at its root',
+    };
     context.report(
       .unsupportedInDocument,
-      "The subscription '${operation.name?.value}' $what the abstract type "
-      "'${found.typeName}' at its root, where '__typename' cannot be "
-      'selected.',
+      "The subscription '$name' $where, which reads the fragment "
+      "'${found.fragmentName}' on the abstract type '${found.typeName}'; the "
+      "root would need '__typename', which a subscription cannot select.",
       [found.selection],
     );
   }
```

Create `packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_introspection_rule.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// `GQL504`: `__schema` and `__type` are not generated yet (`__typename` is).
///
/// The fields are valid at the root of a query, but the planner has no schema
/// type for them: without this rule a document that asks for one would get a
/// class without it.
final class const UnsupportedIntrospectionRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UnsupportedIntrospection(context);
}

final class _UnsupportedIntrospection(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case Field(name: Name(:final value))
        when value == '__schema' || value == '__type') {
      context.report(
        .unsupportedInDocument,
        "The document selects the introspection field '$value', which the "
        'code generator does not support yet.',
        [node],
      );
      return .skip;
    }
    return .next;
  }
}
```

In `packages/typed_graphql_codegen/lib/src/plan/applicability.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'narrowing.dart';
 import 'type_condition_match.dart';
 
 /// Decides how a type condition relates to a parent type (spec §6).
@@ -26,7 +27,7 @@ final class const Applicability(
     }
     return switch (parent) {
       ObjectType() =>
-        schema.possibleTypes(target).any((type) => identical(type, parent))
+        _isPossible(target, parent)
             ? TypeConditionMatch.applies
             : TypeConditionMatch.never,
       InterfaceType()
@@ -47,10 +48,30 @@ final class const Applicability(
     if (target == null) {
       return const [];
     }
-    final reached = schema.possibleTypes(target);
     return [
       for (final type in schema.possibleTypes(parent))
-        if (reached.any((other) => identical(other, type))) type,
+        if (_isPossible(target, type)) type,
     ];
   }
+
+  /// The possible types of [parent], in `possibleTypes` order, that any of
+  /// [narrowings] reaches; empty unless [parent] is abstract.
+  List<ObjectType> reachedBy(SchemaType parent, List<Narrowing> narrowings) {
+    if (parent is! InterfaceType && parent is! UnionType) {
+      return const [];
+    }
+    final reached = <ObjectType>{
+      for (final narrowing in narrowings)
+        ...reach(narrowing.typeCondition, parent),
+    };
+    return [
+      for (final type in schema.possibleTypes(parent))
+        if (reached.contains(type)) type,
+    ];
+  }
+
+  // Whether [type] is among the possible types of [target].
+  bool _isPossible(SchemaType target, ObjectType type) => target is ObjectType
+      ? identical(target, type)
+      : schema.isSubType(target, type);
 }
```

Create `packages/typed_graphql_codegen/lib/src/plan/class_registry.dart`:

```dart
import 'dart:collection';

import 'package:typed_graphql/typed_graphql.dart';

/// The nested classes planned so far in one run, so that two fields of one
/// type with the same selection nodes share one class.
///
/// Without it a field that every variant of a sealed class selects, but not
/// identically, would be planned again with its whole sub-tree for each
/// variant: the class count would grow with the depth to the power of the
/// variant count.
final class ClassRegistry {
  /// Creates an empty registry.
  ClassRegistry();

  final Map<Field, int> _ids = HashMap<Field, int>.identity();
  final Map<String, String> _classes = {};

  /// The class planned for the type named [typeName] and the field [nodes],
  /// compared by identity; null when there is none yet.
  String? classOf(String typeName, List<Field> nodes) =>
      _classes[_key(typeName, nodes)];

  /// Records that [className] is the class of [typeName] and [nodes].
  void record(String typeName, List<Field> nodes, String className) {
    _classes[_key(typeName, nodes)] = className;
  }

  String _key(String typeName, List<Field> nodes) => [
    typeName,
    for (final node in nodes) _ids.putIfAbsent(node, () => _ids.length),
  ].join(',');
}
```

In `packages/typed_graphql_codegen/lib/src/plan/field_collector.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -61,13 +61,15 @@ final class _Run {
   CollectedSelection result() => CollectedSelection(
     [
       for (final MapEntry(key: responseName, value: group) in groups.entries)
-        FieldGroup(
-          responseName,
-          group.fieldName,
-          group.nodes,
-          isConditional: group.isConditional,
-          definition: group.definition,
-        ),
+        // An unconditional `__typename` makes the conditional one redundant.
+        if (!(selectsTypename && responseName == '__typename'))
+          FieldGroup(
+            responseName,
+            group.fieldName,
+            group.nodes,
+            isConditional: group.isConditional,
+            definition: group.definition,
+          ),
     ],
     uses.values.toList(),
     narrowings,
@@ -126,7 +128,7 @@ final class _Run {
       case TypeConditionMatch.applies:
         return source;
       case TypeConditionMatch.narrows:
-        narrowings.add(Narrowing(name, source: source));
+        narrowings.add(Narrowing(name));
       case TypeConditionMatch.never:
         break;
     }
@@ -136,7 +138,10 @@ final class _Run {
   void _field(Field field, bool isConditional) {
     final fieldName = field.name.value;
     final responseName = field.alias?.value ?? fieldName;
-    if (field.alias == null && fieldName == '__typename') {
+    if (field.alias == null &&
+        fieldName == '__typename' &&
+        (!isConditional || parent is! ObjectType)) {
+      // An abstract parent has `typename` whether or not it was selected.
       selectsTypename = true;
       return;
     }
@@ -166,9 +171,7 @@ final class _Run {
             ? FragmentUse(name, [conditions], spread: spread)
             : existing.merge(conditions);
       case TypeConditionMatch.narrows:
-        narrowings.add(
-          Narrowing(condition, fragmentName: name, conditions: conditions),
-        );
+        narrowings.add(Narrowing(condition));
       case TypeConditionMatch.never:
         break;
     }
```

Create `packages/typed_graphql_codegen/lib/src/plan/field_planner.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../emit/dart_names.dart';
import 'class_names.dart';
import 'data_class_role.dart';
import 'field_group.dart';
import 'plan_scope.dart';
import 'plan_work.dart';
import 'planned_field.dart';
import 'selection_source.dart';

/// Plans one field of a data class, and queues the class of a composite field
/// unless a field of the same type and selection nodes already has one.
final class const FieldPlanner(
  /// The schema the field types are looked up in.
  final Schema schema,
) {
  /// Creates a planner.
  this;

  static const ClassNames _classNames = ClassNames();
  static const DartNames _dartNames = DartNames();

  /// The field [group] of the class [owner]; its class, if any, is added to
  /// [scope].
  PlannedField plan(String owner, FieldGroup group, PlanScope scope) {
    final memberName = _dartNames.memberName(
      group.responseName,
      reservedMembers: PlannedField.reservedMembers,
    );
    final type = group.definition.type;
    final named = schema.namedTypeOf(type);
    final isComposite =
        named is ObjectType || named is InterfaceType || named is UnionType;
    String? className;
    if (named != null && isComposite) {
      className = _classOf(owner, memberName, named, group, scope);
    }
    return PlannedField(
      responseName: group.responseName,
      memberName: memberName,
      type: type,
      isConditional: group.isConditional,
      definition: group.fieldName == '__typename' ? null : group.definition,
      className: className,
      node: group.nodes.first,
    );
  }

  String _classOf(
    String owner,
    String memberName,
    SchemaType named,
    FieldGroup group,
    PlanScope scope,
  ) {
    final nodes = [
      for (final node in group.nodes)
        if (node.selectionSet != null) node,
    ];
    final String? shared = scope.registry.classOf(named.name, nodes);
    if (shared != null) {
      return shared;
    }
    final String className = _classNames.nested(owner, memberName);
    scope.registry.record(named.name, nodes, className);
    scope.children.add(
      ClassWork(
        className,
        named,
        [
          for (final node in nodes)
            if (node.selectionSet case final set?) SelectionSource(set),
        ],
        DataClassRole.nested,
        ownerName: owner,
        ownerMember: memberName,
      ),
    );
    return className;
  }
}
```

In `packages/typed_graphql_codegen/lib/src/plan/narrowing.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,22 +1,9 @@
-import 'condition.dart';
-import 'selection_source.dart';
-
 /// A type condition that narrows an abstract parent: only the types it
 /// reaches matter to the planner.
 final class const Narrowing(
   /// The name of the type condition.
-  final String typeCondition, {
-
-  /// The inline fragment's selection set, with the inherited and own
-  /// conditions; null for a fragment spread.
-  final SelectionSource? source,
-
-  /// The spread fragment's name; null for an inline fragment.
-  final String? fragmentName,
-
-  /// The conditions a fragment spread sits under.
-  final List<Condition> conditions = const [],
-}) {
+  final String typeCondition,
+) {
   /// Creates a narrowing.
   this;
 }
```

In `packages/typed_graphql_codegen/lib/src/plan/operation_text.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import 'dart:collection';
 import 'dart:convert';
 
 import 'package:crypto/crypto.dart';
@@ -10,7 +11,7 @@ import 'typename_adder.dart';
 /// and every fragment it spreads, minified, with `__typename` added.
 final class OperationText {
   /// Creates the writer for the project's [schema] and [fragments] by name.
-  const OperationText(this.schema, this.fragments);
+  OperationText(this.schema, this.fragments);
 
   /// The schema, which tells abstract types from object types.
   final Schema schema;
@@ -18,8 +19,11 @@ final class OperationText {
   /// The project's fragment definitions, by name.
   final Map<String, FragmentDefinition> fragments;
 
-  RootTypename get _rootTypename =>
-      RootTypename(schema, (name) => fragments[name]);
+  // The operation class and the persisted-operations manifest both ask.
+  final Map<OperationDefinition, String> _texts =
+      HashMap<OperationDefinition, String>.identity();
+
+  RootTypename get _rootTypename => RootTypename(schema, fragments);
 
   /// The SHA-256 of a document [text], in lower-case hexadecimal.
   String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();
@@ -30,7 +34,10 @@ final class OperationText {
   /// The operation's own selection set gets `__typename` when it reads the
   /// type of an abstract selection; a subscription cannot select it and is
   /// left as written.
-  String of(OperationDefinition operation) {
+  String of(OperationDefinition operation) =>
+      _texts.putIfAbsent(operation, () => _write(operation));
+
+  String _write(OperationDefinition operation) {
     const adder = TypenameAdder();
     final OperationDefinition root = _withRootTypename(operation, adder);
     final document = Document([root, ..._spread(operation)]);
```

Create `packages/typed_graphql_codegen/lib/src/plan/plan_scope.dart`:

```dart
import 'class_registry.dart';
import 'plan_work.dart';

/// What planning one class needs besides the class: the [registry] of the
/// whole run and the list its nested work is added to.
final class PlanScope {
  /// Creates the scope of one class in a run that shares [registry].
  PlanScope(this.registry);

  /// The nested classes the run has planned so far.
  final ClassRegistry registry;

  /// The work under the class, in the order it is emitted.
  final List<PlanWork> children = [];
}
```

In `packages/typed_graphql_codegen/lib/src/plan/root_typename.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,26 +1,36 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
-/// Finds out whether the top level of an operation reads an abstract type
-/// (R7.9): then the document selects `__typename` there, which a
-/// subscription's root cannot.
+import 'applicability.dart';
+import 'field_collector.dart';
+import 'selection_source.dart';
+
+/// Finds out whether the top level of an operation spreads a fragment that
+/// plans as a sealed class (R7.9): the class reads the type of the root
+/// object, so the document selects `__typename` there, which a subscription's
+/// root cannot.
+///
+/// The root is an object type, so an inline fragment, or a fragment on an
+/// abstract type without narrowing inside, flattens into the root class and
+/// needs nothing.
 final class RootTypename {
-  /// Creates the finder for [schema]; [fragmentNamed] looks a fragment
-  /// definition up by name.
-  const RootTypename(this.schema, this.fragmentNamed);
+  /// Creates the finder for [schema]; [fragments] are the project's fragment
+  /// definitions by name.
+  const RootTypename(this.schema, this.fragments);
 
   /// The schema, which tells abstract types from object types.
   final Schema schema;
 
-  /// The project's fragment definitions by name.
-  final FragmentDefinition? Function(String name) fragmentNamed;
+  /// The project's fragment definitions, by name.
+  final Map<String, FragmentDefinition> fragments;
 
-  /// Whether the top level of [root] reads an abstract type.
+  /// Whether the top level of [root] spreads a sealed fragment.
   bool isNeededBy(SelectionSet root) => find(root) != null;
 
-  /// The first top-level selection of [root] that reads an abstract type,
-  /// through spread fragments too, with the abstract type's name and, when a
-  /// fragment definition is on it, the fragment's name; null when none does.
-  ({Node selection, String typeName, String? fragmentName})? find(
+  /// The first top-level selection of [root] that leads, through inline
+  /// fragments and spread fragments, to a fragment that plans as a sealed
+  /// class, with that fragment's name and its abstract type's name; null when
+  /// none does.
+  ({Node selection, String typeName, String fragmentName})? find(
     SelectionSet root,
   ) {
     final visited = <String>{};
@@ -37,9 +47,9 @@ final class RootTypename {
     return null;
   }
 
-  // The abstract type [top] reads, through spread fragments; [visited] holds
-  // the fragments already searched in vain.
-  ({String typeName, String? fragmentName})? _search(
+  // The sealed fragment [top] reaches; [visited] holds the fragments already
+  // searched in vain.
+  ({String typeName, String fragmentName})? _search(
     Selection top,
     Set<String> visited,
   ) {
@@ -48,18 +58,16 @@ final class RootTypename {
       switch (pending.removeLast()) {
         case Field():
           continue;
-        case InlineFragment(:final typeCondition, :final selectionSet):
-          final String? typeName = typeCondition?.name.value;
-          if (typeName != null && _isAbstract(typeName)) {
-            return (typeName: typeName, fragmentName: null);
-          }
+        case InlineFragment(:final selectionSet):
           pending.addAll(selectionSet.selections);
         case FragmentSpread(:final name):
-          final FragmentDefinition? fragment = fragmentNamed(name.value);
+          final FragmentDefinition? fragment = fragments[name.value];
           if (fragment == null || !visited.add(name.value)) continue;
-          final String typeName = fragment.typeCondition.name.value;
-          if (_isAbstract(typeName)) {
-            return (typeName: typeName, fragmentName: name.value);
+          if (_isSealed(fragment)) {
+            return (
+              typeName: fragment.typeCondition.name.value,
+              fragmentName: name.value,
+            );
           }
           pending.addAll(fragment.selectionSet.selections);
       }
@@ -67,8 +75,19 @@ final class RootTypename {
     return null;
   }
 
-  bool _isAbstract(String typeName) => switch (schema.typeNamed(typeName)) {
-    InterfaceType() || UnionType() => true,
-    _ => false,
-  };
+  // Whether the planner makes [fragment] a sealed class: its type is
+  // abstract and a narrowing inside reaches an object type.
+  bool _isSealed(FragmentDefinition fragment) {
+    final SchemaType? type = schema.typeNamed(
+      fragment.typeCondition.name.value,
+    );
+    if (type == null) return false;
+    final collected = FieldCollector(
+      schema,
+      fragments,
+    ).collect(type, [SelectionSource(fragment.selectionSet)]);
+    return Applicability(schema)
+        .reachedBy(type, collected.narrowings)
+        .isNotEmpty;
+  }
 }
```

In `packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,13 +1,16 @@
+import 'dart:collection';
+
 import 'package:typed_graphql/typed_graphql.dart';
 
-import '../emit/dart_names.dart';
 import 'applicability.dart';
 import 'class_names.dart';
+import 'class_registry.dart';
 import 'collected_selection.dart';
 import 'data_class_role.dart';
 import 'field_collector.dart';
-import 'field_group.dart';
+import 'field_planner.dart';
 import 'fragment_use.dart';
+import 'plan_scope.dart';
 import 'plan_work.dart';
 import 'planned_class.dart';
 import 'planned_field.dart';
@@ -22,10 +25,10 @@ import 'variant_sharing.dart';
 final class ShapePlanner {
   /// Creates a planner for [schema] and the project's [fragments] by name.
   ShapePlanner(this.schema, this.fragments)
-    : _collector = FieldCollector(schema, fragments);
+    : _collector = FieldCollector(schema, fragments),
+      _fieldPlanner = FieldPlanner(schema);
 
   static const ClassNames _classNames = ClassNames();
-  static const DartNames _dartNames = DartNames();
   static const TypeRef _typenameType = NonNullType(NamedType(Name('String')));
 
   /// The schema the selections are on.
@@ -35,16 +38,35 @@ final class ShapePlanner {
   final Map<String, FragmentDefinition> fragments;
 
   final FieldCollector _collector;
+  final FieldPlanner _fieldPlanner;
+
+  // Each definition is planned once, whoever asks (name check, emission).
+  final Map<ExecutableDefinition, List<PlannedClass>?> _plans =
+      HashMap<ExecutableDefinition, List<PlannedClass>?>.identity();
+
+  /// The most classes one operation or fragment may generate; a selection
+  /// that needs more is reported as `GQL511` instead of planned.
+  static const int maxClasses = 10000;
+
+  /// Whether the plan of [definition] was cut off at [maxClasses]: it is
+  /// planned, and empty, once something asked for it.
+  bool exceedsLimit(ExecutableDefinition definition) =>
+      _plans.containsKey(definition) && _plans[definition] == null;
 
   /// The classes of [operation]: its data class, then everything under it.
-  /// Empty when the schema has no root for the operation type.
+  /// Empty when the schema has no root for the operation type, or when the
+  /// operation needs more than [maxClasses] ([exceedsLimit]).
   List<PlannedClass> planOperation(OperationDefinition operation) {
+    if (_plans.containsKey(operation)) {
+      return _plans[operation] ?? const [];
+    }
     final rootName = schema.rootTypeName(operation.operation);
     final root = rootName == null ? null : schema.typeNamed(rootName);
     if (root == null) {
       return const [];
     }
-    return _plan(
+    return _remember(
+      operation,
       ClassWork(
         _classNames.operationData(operation.name?.value ?? ''),
         root,
@@ -55,13 +77,18 @@ final class ShapePlanner {
   }
 
   /// The classes of [fragment]: its class, then everything under it.
-  /// Empty when its type condition is unknown.
+  /// Empty when its type condition is unknown, or when the fragment needs
+  /// more than [maxClasses] ([exceedsLimit]).
   List<PlannedClass> planFragment(FragmentDefinition fragment) {
+    if (_plans.containsKey(fragment)) {
+      return _plans[fragment] ?? const [];
+    }
     final parent = schema.typeNamed(fragment.typeCondition.name.value);
     if (parent == null) {
       return const [];
     }
-    return _plan(
+    return _remember(
+      fragment,
       ClassWork(
         _classNames.fragment(fragment.name.value),
         parent,
@@ -71,48 +98,48 @@ final class ShapePlanner {
     );
   }
 
-  List<PlannedClass> _plan(ClassWork first) {
+  List<PlannedClass> _remember(
+    ExecutableDefinition definition,
+    ClassWork first,
+  ) {
+    final plan = _plan(first);
+    _plans[definition] = plan;
+    return plan ?? const [];
+  }
+
+  // Null when the selection needs more than [maxClasses] classes.
+  List<PlannedClass>? _plan(ClassWork first) {
     final planned = <PlannedClass>[];
+    final registry = ClassRegistry();
     final stack = <PlanWork>[first];
     while (stack.isNotEmpty) {
+      if (planned.length >= maxClasses) {
+        return null;
+      }
       switch (stack.removeLast()) {
         case ReadyWork(:final plan):
           planned.add(plan);
         case final ClassWork work:
-          final children = <PlanWork>[];
+          final scope = PlanScope(registry);
           final collected =
               work.variant?.collected ??
               _collector.collect(work.parent, work.sources);
           final reached = work.variant == null
-              ? _reached(work.parent, collected)
+              ? Applicability(
+                  schema,
+                ).reachedBy(work.parent, collected.narrowings)
               : const <ObjectType>[];
           planned.add(
             reached.isEmpty
-                ? _dataClass(work, collected, children)
-                : _polymorphic(work, collected, reached, children),
+                ? _dataClass(work, collected, scope)
+                : _polymorphic(work, collected, reached, scope),
           );
-          stack.addAll(children.reversed);
+          stack.addAll(scope.children.reversed);
       }
     }
     return planned;
   }
 
-  /// The object types the narrowings of an abstract [parent] reach, in
-  /// possible-types order.
-  List<ObjectType> _reached(SchemaType parent, CollectedSelection collected) {
-    if (parent is! InterfaceType && parent is! UnionType) {
-      return const [];
-    }
-    final reached = <ObjectType>{
-      for (final narrowing in collected.narrowings)
-        ...Applicability(schema).reach(narrowing.typeCondition, parent),
-    };
-    return [
-      for (final type in schema.possibleTypes(parent))
-        if (reached.contains(type)) type,
-    ];
-  }
-
   /// Plans the sealed base of [work] and queues its variants, in the order
   /// they are emitted: shared field classes, the shared holder, each
   /// variant, then the unknown one.
@@ -120,7 +147,7 @@ final class ShapePlanner {
     ClassWork work,
     CollectedSelection collected,
     List<ObjectType> reached,
-    List<PlanWork> children,
+    PlanScope scope,
   ) {
     final collections = [
       for (final type in reached) _collector.collect(type, work.sources),
@@ -129,18 +156,18 @@ final class ShapePlanner {
     final shared = <String, PlannedField>{
       for (final group in collected.fields)
         if (sharing.sharedFields.contains(group.responseName))
-          group.responseName: _field(work.name, group, children),
+          group.responseName: _fieldPlanner.plan(work.name, group, scope),
     };
     final holderName = sharing.hasSharedHolder
-        ? _ownHolder(work.name, collected.fragments, children)
+        ? _ownHolder(work.name, collected.fragments, scope)
         : null;
     final contexts = [
       for (final selection in [...collections, collected])
         VariantContext(work.name, selection, shared, holderName),
     ];
-    final variants = _queueVariants(work, reached, contexts, children);
+    final variants = _queueVariants(work, reached, contexts, scope);
     final unknownName = _classNames.unknownVariant(work.name);
-    children.add(
+    scope.children.add(
       _variantWork(work, unknownName, work.parent, contexts.last),
     );
     return PolymorphicBasePlan(
@@ -161,13 +188,13 @@ final class ShapePlanner {
     ClassWork base,
     List<ObjectType> reached,
     List<VariantContext> contexts,
-    List<PlanWork> children,
+    PlanScope scope,
   ) {
     final variants = <VariantReference>[];
     for (final (index, type) in reached.indexed) {
       final name = _classNames.variant(base.name, type.name);
       variants.add(VariantReference(type.name, name));
-      children.add(_variantWork(base, name, type, contexts[index]));
+      scope.children.add(_variantWork(base, name, type, contexts[index]));
     }
     return variants;
   }
@@ -204,22 +231,20 @@ final class ShapePlanner {
   String? _ownHolder(
     String owner,
     List<FragmentUse> uses,
-    List<PlanWork> children,
+    PlanScope scope,
   ) {
     if (uses.isEmpty) {
       return null;
     }
     final name = _classNames.holder(owner);
-    children.add(ReadyWork(_holder(name, owner, uses)));
+    scope.children.add(ReadyWork(_holder(name, owner, uses)));
     return name;
   }
 
-  /// Plans [work] and adds the work under it to [children], in the order
-  /// it is emitted: field classes, then the holder.
-  DataClassPlan _dataClass(
+  List<PlannedField> _fields(
     ClassWork work,
     CollectedSelection collected,
-    List<PlanWork> children,
+    PlanScope scope,
   ) {
     final variant = work.variant;
     final fields = <PlannedField>[
@@ -233,12 +258,28 @@ final class ShapePlanner {
         ),
     ];
     for (final group in collected.fields) {
+      // A variant reads its `typename` from the class itself.
+      if (variant != null && group.responseName == '__typename') continue;
       final base = variant?.sharedFields[group.responseName];
-      fields.add(base?.overriding() ?? _field(work.name, group, children));
+      fields.add(
+        base?.overriding() ?? _fieldPlanner.plan(work.name, group, scope),
+      );
     }
+    return fields;
+  }
+
+  /// Plans [work] and adds the work under it to [scope], in the order
+  /// it is emitted: field classes, then the holder.
+  DataClassPlan _dataClass(
+    ClassWork work,
+    CollectedSelection collected,
+    PlanScope scope,
+  ) {
+    final variant = work.variant;
+    final fields = _fields(work, collected, scope);
     final sharedHolder = variant?.sharedHolderName;
     final holderName =
-        sharedHolder ?? _ownHolder(work.name, collected.fragments, children);
+        sharedHolder ?? _ownHolder(work.name, collected.fragments, scope);
     return DataClassPlan(
       name: work.name,
       role: work.role,
@@ -254,41 +295,4 @@ final class ShapePlanner {
       holderOverridesBase: sharedHolder != null,
     );
   }
-
-  PlannedField _field(String owner, FieldGroup group, List<PlanWork> children) {
-    final memberName = _dartNames.memberName(
-      group.responseName,
-      reservedMembers: PlannedField.reservedMembers,
-    );
-    final type = group.definition.type;
-    final named = schema.namedTypeOf(type);
-    final isComposite =
-        named is ObjectType || named is InterfaceType || named is UnionType;
-    String? className;
-    if (named != null && isComposite) {
-      className = _classNames.nested(owner, memberName);
-      children.add(
-        ClassWork(
-          className,
-          named,
-          [
-            for (final node in group.nodes)
-              if (node.selectionSet case final set?) SelectionSource(set),
-          ],
-          DataClassRole.nested,
-          ownerName: owner,
-          ownerMember: memberName,
-        ),
-      );
-    }
-    return PlannedField(
-      responseName: group.responseName,
-      memberName: memberName,
-      type: type,
-      isConditional: group.isConditional,
-      definition: group.fieldName == '__typename' ? null : group.definition,
-      className: className,
-      node: group.nodes.first,
-    );
-  }
 }
```

In `packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -37,10 +37,17 @@ final class TypenameAdder extends AstTransformer {
     end: selectionSet.end,
   );
 
+  // A `__typename` under `@include` or `@skip` may be missing from the
+  // response, so it does not stand in for the added one.
   bool _hasTypename(SelectionSet selectionSet) => selectionSet.selections.any(
     (selection) =>
         selection is Field &&
         selection.alias == null &&
-        selection.name.value == '__typename',
+        selection.name.value == '__typename' &&
+        !selection.directives.any(
+          (directive) =>
+              directive.name.value == 'include' ||
+              directive.name.value == 'skip',
+        ),
   );
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/emit/data_class_emitter_test.dart test/emit/document_library_emitter_test.dart test/emit/fragment_holder_emitter_test.dart test/emit/polymorphic_base_emitter_test.dart test/generator/client_generator_generate_test.dart test/generator/client_generator_test.dart test/generator/document_names_test.dart test/generator/generated_names_test.dart test/generator/typename_generation_test.dart test/plan/class_sharing_test.dart test/plan/field_collector_test.dart test/plan/operation_text_test.dart test/plan/shape_planner_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_codegen/CHANGELOG.md`:

```markdown
- Fixes after the review of the operations and fragments: `toJson` merges the
  JSON of a class and its fragments deeply (`JsonMerger`); a field of one type
  and one list of selection nodes shares its class, each definition is planned
  once and one that needs more than 10000 classes is a `GQL511`; a
  `__typename` under `@include` or `@skip` is a nullable member and the
  unconditional one is still added to the document; `__schema` and `__type`
  are a `GQL504`; only a spread of a fragment that becomes a sealed class
  needs `__typename` at the root of an operation (and is a `GQL504` in a
  subscription); name problems are limited like every other run; `GQL507`
  names the two classes of a variant for a type called `Unknown`.
```

In `packages/typed_graphql_codegen/doc/client_codegen.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -252,14 +252,31 @@ fragment UserCard on User {
 '''),
     ],
   );
+  final declaration = RegExp(r'^(?:final|sealed) class (\w+)', multiLine: true);
   for (final file in generation.files) {
-    if (file.path == 'lib/user.graphql.dart') print(file.text);
+    if (file.path != 'lib/user.graphql.dart') continue;
+    final names = [
+      for (final match in declaration.allMatches(file.text)) match[1],
+    ];
+    print(names.join('\n'));
   }
 }
 ```
 
 It prints:
 
+```text
+GetUserQuery
+GetUserVariables
+GetUserData
+GetUserDataUser
+GetUserDataUserFragments
+UserCard
+```
+
+The library starts with the header and the operation class, whose document is
+what is sent; the full text of the library is:
+
 ```text
 // GENERATED CODE - DO NOT MODIFY BY HAND.
 // Generated by typed_graphql_codegen from lib/user.graphql.
@@ -391,10 +408,10 @@ final class GetUserDataUser implements client.DataObject {
   final GetUserDataUserFragments fragments;
 
   @override
-  graphql.JsonObject toJson() => graphql.JsonObject({
-    ...fragments.toJson().fields,
-    'email': _emailCodec.write(email),
-  });
+  graphql.JsonObject toJson() => const client.JsonMerger().merge([
+    fragments.toJson(),
+    graphql.JsonObject({'email': _emailCodec.write(email)}),
+  ]);
 
   @override
   bool operator ==(Object other) =>
@@ -488,7 +505,6 @@ final class UserCard implements client.DataObject {
   String toString() => 'UserCard(id: $id, name: $name)';
 }
 ```
-
 The sections below describe the parts of that output.
 
 ### Names
@@ -593,10 +609,13 @@ fragment it spreads, transitively, sorted by name and minified. It adds
 `__typename` to the selection set of every field that has one, so the client
 can read the type of any object; fragment definitions and inline fragments
 get none, because the field around them has it. The operation's own
-selection set gets it only when a fragment on an interface or a union is
-spread at its top level, as the sealed class that reads it needs. A
-subscription cannot select `__typename` at its root, so a subscription that
-reads an abstract type there (`GQL504`) cannot be generated. The `sha256` is
+selection set gets it only when a fragment that becomes a sealed class (a
+fragment on an interface or a union with an inline fragment or spread on
+other types inside) is spread at its top level, as that class needs to read
+it; inline fragments at the root never need it. A `__typename` under
+`@include` or `@skip` does not count: the unconditional one is added next to
+it. A subscription cannot select `__typename` at its root, so a subscription
+that spreads such a fragment at its top level (`GQL504`) cannot be generated. The `sha256` is
 the SHA-256 of the text in UTF-8, in lowercase hexadecimal: the id of a
 persisted query.
 
@@ -625,9 +644,16 @@ operation, sorted by name, the same values the operation classes carry:
 `GetUserData.decode(json, variables: ...)` reads the `data` of a response and
 never throws: a value of the wrong shape, a missing required field or an
 unreadable scalar is a `DecodeFailure` with a message and the path of the
-value in the response. `toJson` writes the data back, so a value that was
-read writes the JSON it was read from (with `__typename` where the selection
-reads it), and `==` compares by value, lists by content.
+value in the response. `toJson` writes the data back: the fields the value
+holds, under their response names, with `__typename` where the selection
+reads it, and `null` for a conditional field that was absent. A class and the
+fragments it spreads may select the same field with different sub-fields;
+`toJson` merges their JSON deeply (`JsonMerger` of the client), so each
+side's sub-fields are written. `==` compares by value, lists by content.
+
+A fragment's own `decode` has no operation around it: a Boolean variable that
+`variables` lacks counts as false, not as its default in the operation (an
+operation's `decode` passes its own defaults).
 
 ```text
 switch (GetUserData.decode(json, variables: variables)) {
@@ -808,11 +834,12 @@ and are never reused.
 | `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
 | `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
 | `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
-| `GQL504` | error | A document uses `@defer` or `@stream`, which the generator does not support yet, or a subscription reads an abstract type at its root (a fragment on an interface or a union, or an inline fragment): the sealed class would need `__typename` there, and a subscription cannot select it. |
+| `GQL504` | error | A document uses `@defer` or `@stream`, or selects an introspection field (`__schema`, `__type`), which the generator does not support yet; or a subscription spreads, at its root, a fragment that becomes a sealed class (directly or through other fragments or inline fragments): the sealed class would need `__typename` there, and a subscription cannot select it. |
 | `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
 | `GQL506` | warning | No document matches `documents`. |
 | `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class (such as the fields `user_name` and `userName`, or two fragments `UserCard` and `userCard`), or two files at one path. |
 | `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
+| `GQL511` | error | An operation or fragment would generate more than 10000 classes, for instance a selection on an interface that reaches many types, repeated under many aliases. |
 
 The problems of the schema and of the documents keep the codes of the core:
 the schema's `GQL1xx` and the operation rules' `GQL2xx`.
````

- [ ] **Step 6: Run the documentation checks**

```sh
(cd packages/typed_graphql_codegen && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add packages/typed_graphql_codegen/CHANGELOG.md packages/typed_graphql_codegen/doc/client_codegen.md packages/typed_graphql_codegen/lib/src/emit/dart_names.dart packages/typed_graphql_codegen/lib/src/emit/data_class_emitter.dart packages/typed_graphql_codegen/lib/src/emit/document_library_emitter.dart packages/typed_graphql_codegen/lib/src/emit/fragment_holder_emitter.dart packages/typed_graphql_codegen/lib/src/emit/to_json_writer.dart packages/typed_graphql_codegen/lib/src/generator/client_generator.dart packages/typed_graphql_codegen/lib/src/generator/document_libraries.dart packages/typed_graphql_codegen/lib/src/generator/document_name_checker.dart packages/typed_graphql_codegen/lib/src/generator/generated_names.dart packages/typed_graphql_codegen/lib/src/generator/rules/subscription_root_rule.dart packages/typed_graphql_codegen/lib/src/generator/rules/unsupported_introspection_rule.dart packages/typed_graphql_codegen/lib/src/plan/applicability.dart packages/typed_graphql_codegen/lib/src/plan/class_registry.dart packages/typed_graphql_codegen/lib/src/plan/field_collector.dart packages/typed_graphql_codegen/lib/src/plan/field_planner.dart packages/typed_graphql_codegen/lib/src/plan/narrowing.dart packages/typed_graphql_codegen/lib/src/plan/operation_text.dart packages/typed_graphql_codegen/lib/src/plan/plan_scope.dart packages/typed_graphql_codegen/lib/src/plan/root_typename.dart packages/typed_graphql_codegen/lib/src/plan/shape_planner.dart packages/typed_graphql_codegen/lib/src/plan/typename_adder.dart packages/typed_graphql_codegen/test/emit/data_class_emitter_test.dart packages/typed_graphql_codegen/test/emit/document_library_emitter_test.dart packages/typed_graphql_codegen/test/emit/fragment_holder_emitter_test.dart packages/typed_graphql_codegen/test/emit/polymorphic_base_emitter_test.dart packages/typed_graphql_codegen/test/generator/client_generator_generate_test.dart packages/typed_graphql_codegen/test/generator/client_generator_test.dart packages/typed_graphql_codegen/test/generator/document_names_test.dart packages/typed_graphql_codegen/test/generator/generated_names_test.dart packages/typed_graphql_codegen/test/generator/typename_generation_test.dart packages/typed_graphql_codegen/test/goldens/fragments/input/lib/user_avatar.graphql packages/typed_graphql_codegen/test/goldens/fragments/input/schema.graphql packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_avatar.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/output/lib/user_card_query.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/fragments/support/bin/round_trip.dart.txt packages/typed_graphql_codegen/test/goldens/operations/output/lib/user.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/operations/output/lib/user_mutations.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_node.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_query.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/polymorphic/output/lib/user_result.graphql.dart.golden packages/typed_graphql_codegen/test/goldens/schema_types/output/lib/user.graphql.dart.golden packages/typed_graphql_codegen/test/plan/class_sharing_test.dart packages/typed_graphql_codegen/test/plan/field_collector_test.dart packages/typed_graphql_codegen/test/plan/operation_text_test.dart packages/typed_graphql_codegen/test/plan/shape_planner_test.dart
git commit -q -m "fix(typed_graphql_codegen): apply the review of operations and fragments" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

With the choice this plan makes (`.superpowers/m10-open-questions.md`):

- Question 2: nested classes are named parent + capitalised member (`GetUserDataUserFriends`), variants append the type name, holders `Fragments`; collisions are `GQL507`, never renamed.
- Question 4: the manifest is Apollo's `apollo-persisted-query-manifest` version 1, sorted by name.
- Question 8 (spec deviation 7): a base getter only for fields every variant selects with the same nodes; no `implements` between classes with `==`.
- Question 9 (spec deviation 8): a type condition reaches the base only when it is the parent or an interface the parent implements.
- Question 10: a selection on an abstract type without narrowings is a plain class.
- Question 12: `__typename` is added to every field selection set that lacks an unconditional one, and to the root only for a spread of a fragment that plans as a sealed base; at a subscription root that is `GQL504`.

## Self-review

- Spec coverage: section 6 (Tasks 1-3, 11), section 7 "Data classes", "Operation classes and metadata", "Names" (Tasks 4-7, 11), section 9 `GQL504`, `GQL507`, `GQL511` (Tasks 7, 9, 11), section 10 (Tasks 1, 2, 6, 11), section 11 goldens (Tasks 4-7, 11).
- Every code block in this plan is the content of a commit that passed the green check; no placeholder remains.
- Type consistency: each task's Produces block is extracted from its commit, and later tasks consume those names.

## After the plan

M10d (`2026-10-15-m10d-command-line.md`) follows on the same branch.
