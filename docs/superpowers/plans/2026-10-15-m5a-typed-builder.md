# M5a Typed Schema Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start `typed_graphql_server` with the typed schema builder (R4.1, R4.2, R0.2, R0.3): `ExecutableSchemaBuilder<C>` and its typed refs (`OutputRef`, `InputRef`, `LeafRef`), scalars, enums, typed arguments and input objects (`Arg`, `Arguments`, `Optional`, `@oneOf`), object types with two-step typed fields (`t.field(name, ref).pure|resolve|resolveWith|declareOnly`), interfaces and unions with inheritance and `resolveType` / `isTypeOf`, and `build`, which runs the builder checks `GQL300`-`GQL302` and the core `SchemaValidator` and returns an `ExecutableSchema<C>` or throws `SchemaBuildError`. Compile-failure fixtures prove that a wrong resolver type does not compile. The Schema Builder guide, the server documentation suite, CHANGELOG, README, `llms.txt` and `CLAUDE.md` describe it.

**Architecture:** The core gains three codes and exports `Suggestions` in its own commit (Task 1); everything else lives in `packages/typed_graphql_server/lib/src/builder/` (definitions, refs, the field stub, the assemblers that turn definitions into a core `Schema` through SDL-free model construction) and `lib/src/execution/` (`ExecutableSchema<C>`, `SchemaBindings`, `FieldInfo`), which import each other. A field is declared in two steps so the result type is fixed by the ref before the closure is typed: `t.field('name', b.string).pure((p) => ...)` is a compile error when the closure returns `String?`. Field lanes take `Object?` and cast inside the stub, so a definition holds no contravariant `C`-typed member and `FieldDef<P, C>` stays covariant-safe. Interfaces and objects collect inherited fields with an explicit stack. `build` assembles the core `Schema`, runs `BuilderChecks` (`GQL300` incompatible implementation, `GQL301` ambiguous type resolution, `GQL302` unencodable default) and `SchemaValidator`, and binds every field, abstract type, leaf and input object by name for the M5b executor. The package imports no `dart:io` or web framework (spec section 17), and the builder never instantiates services: closures read them from the context `C`.

**Tech Stack:** Dart 3.13 (formatted with 3.13.5), `package:test`, `package:meta`, the core `typed_graphql`. graphql-js 17.0.2 in `reference/graphql-js` for the schema-building semantics the builder mirrors.

**Spec:** `docs/superpowers/specs/2026-10-15-m5-execution-design.md` (sections 2, 3, 15, 17, 18), `docs/requirements.md` R4.1 and R4.2.

**Base:** `main` at `57f85e8` (M4 merged) plus the M5 spec commits. The plan was verified by applying its tasks in order on branch `m5-final`, one commit per task, with the green check after each and the server suite on exe at the end.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters, named ones included (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`.
- The server imports the core only through `package:typed_graphql/typed_graphql.dart`, and `lib/` imports no platform library but `dart:async`, `dart:collection`, `dart:core` and `dart:math` (spec section 17; `test/quality/imports_test.dart`).
- Core changes stay minimal and in their own commit (Task 1). New codes go into `DiagnosticCode` in id order, in the `GQL3xx` range, with a doc comment.
- No new package dependency besides the workspace core and `meta`.
- Public API goes through the barrel `lib/typed_graphql_server.dart`, each exported type tagged `/// {@category builder}` or `/// {@category execution}`; internal collaborators stay out of it.
- Wrong use of the builder (a duplicate name, a bad default, a type that cannot be resolved) is a programmer error: `build` throws `SchemaBuildError` with diagnostics, and the builder methods throw `ArgumentError` / `StateError`.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time. Chrome cannot start under `ulimit -v`; bound the browser runs by resident memory with `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action. Do not touch `packages/typed_graphql_codegen`.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.

## Review Focus

1. A resolver whose result type does not match the field's ref, a nullable getter on a non-null ref, a union member that is not a subtype of the union's Dart type, and a wrong argument read are compile errors. Task 7 (`compile_failures_test.dart` and its fixtures).
2. `FieldDef<P, C>` and `InterfaceTypeDef<P>` read through a wider static type (`Object?`) do not throw a `TypeError`: lanes take `Object?`, and `resolveType` is read through `hasResolveType` / `untypedResolveType`. Tasks 4 and 5.
3. Field inheritance through interfaces that implement interfaces: preorder, repeats ignored, declared-only fields do not reserve the name, no recursion. Task 5 (`field_inheritance_test.dart`).
4. `GQL301` is reported unless both overlapping object types have `isTypeOf`, once per abstract type; `GQL302` turns a default that the ref cannot encode into a diagnostic, not an exception. Task 6 (`builder_checks_test.dart`).
5. `Arg.read`: absent optional argument is `Absent()`, a present one `Present(value)`, a missing required one its default. Task 3 (`arg_test.dart`).

## File map

| File | Change | Task |
|---|---|---|
| `packages/typed_graphql_server/lib/src/builder/built_in_scalar_definitions.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/definition_registry.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/enum_type_def.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/enum_value_def.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart` | Create | 2, 6, 11 |
| `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart` | Create | 2, 3, 4, 5, 6 |
| `packages/typed_graphql_server/lib/src/builder/input_list_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/input_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/leaf_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/named_type_def.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/nullable_input_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/nullable_leaf_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/nullable_output_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/optional.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/output_list_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/output_ref.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/scalar_type_def.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/type_ref_wrapping.dart` | Create | 2 |
| `packages/typed_graphql_server/test/builder/enum_and_optional_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/builder/refs_test.dart` | Create | 2 |
| `packages/typed_graphql_server/test/quality/import_rule.dart` | Create | 2 |
| `packages/typed_graphql_server/test/quality/imports_test.dart` | Create | 2 |
| `packages/typed_graphql_server/lib/src/builder/arg.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/builder/arguments.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/builder/arguments_def.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/builder/input_object_def.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/builder/optional_input_ref.dart` | Create | 3 |
| `packages/typed_graphql_server/test/builder/arguments_test.dart` | Create | 3 |
| `packages/typed_graphql_server/lib/src/builder/field_def.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/builder/field_lane.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/builder/field_stub.dart` | Create | 4, 11 |
| `packages/typed_graphql_server/lib/src/builder/fields_builder.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/builder/object_options.dart` | Create | 4 |
| `packages/typed_graphql_server/lib/src/builder/object_type_def.dart` | Create | 4, 5, 6 |
| `packages/typed_graphql_server/lib/src/execution/field_info.dart` | Create | 4 |
| `packages/typed_graphql_server/test/builder/fields_test.dart` | Create | 4, 11 |
| `packages/typed_graphql_server/lib/src/builder/field_inheritance.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/builder/interface_type_def.dart` | Create | 5, 6 |
| `packages/typed_graphql_server/lib/src/builder/union_type_def.dart` | Create | 5, 6 |
| `packages/typed_graphql_server/test/builder/interfaces_and_unions_test.dart` | Create | 5 |
| `packages/typed_graphql_server/lib/src/builder/build_options.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/builder/builder_checks.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/lib/src/builder/directive_nodes.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/builder/field_assembler.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/lib/src/builder/literal_writer.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/lib/src/builder/possible_types.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/lib/src/builder/schema_build_error.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/builder/type_assembler.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart` | Create | 6 |
| `packages/typed_graphql_server/lib/src/execution/executable_schema.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart` | Create | 6 |
| `packages/typed_graphql_server/test/builder/build_errors_test.dart` | Create | 6, 11 |
| `packages/typed_graphql_server/test/builder/build_test.dart` | Create | 6 |
| `packages/typed_graphql_server/test/builder/literal_writer_test.dart` | Create | 6 |
| `packages/typed_graphql_server/test/compile/compile_failures_test.dart` | Create | 7, 11 |
| `packages/typed_graphql_server/test/compile/fixtures/nullable_for_non_null.dart.txt` | Create | 7 |
| `packages/typed_graphql_server/test/compile/fixtures/ok.dart.txt` | Create | 7 |
| `packages/typed_graphql_server/test/compile/fixtures/unrelated_union_member.dart.txt` | Create | 7 |
| `packages/typed_graphql_server/test/compile/fixtures/wrong_argument_read.dart.txt` | Create | 7 |
| `packages/typed_graphql_server/test/compile/fixtures/wrong_result_type.dart.txt` | Create | 7 |
| `packages/typed_graphql_server/dartdoc_options.yaml` | Create | 8 |
| `packages/typed_graphql_server/doc/execution.md` | Create | 8 |
| `packages/typed_graphql_server/doc/schema_builder.md` | Create | 8, 11 |
| `packages/typed_graphql_server/test/doc/category_tags_test.dart` | Create | 8 |
| `packages/typed_graphql_server/test/doc/doc_links_test.dart` | Create | 8 |
| `packages/typed_graphql_server/test/doc/doc_snippets_test.dart` | Create | 8 |
| `packages/typed_graphql_server/test/builder/assembly_test.dart` | Create | 11 |
| `packages/typed_graphql/CHANGELOG.md` | Modify | 1 |
| `packages/typed_graphql/doc/diagnostics.md` | Modify | 1 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modify | 1, 10 |
| `packages/typed_graphql/lib/src/diagnostics/suggestions.dart` | Modify | 1 |
| `packages/typed_graphql/lib/typed_graphql.dart` | Modify | 1 |
| `packages/typed_graphql/test/diagnostics/diagnostic_test.dart` | Modify | 1 |
| `packages/typed_graphql_server/lib/typed_graphql_server.dart` | Modify | 2, 3, 4, 5, 6, 9 |
| `packages/typed_graphql_server/CHANGELOG.md` | Modify | 6, 8, 11 |
| `CLAUDE.md` | Modify | 8 |
| `README.md` | Modify | 8 |
| `docs/superpowers/HANDOFF.md` | Modify | 8 |
| `llms.txt` | Modify | 8 |
| `packages/typed_graphql_server/README.md` | Modify | 8 |
| `packages/typed_graphql_server/pubspec.yaml` | Modify | 11 |

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

### Task 1: The M5a diagnostic codes and the `Suggestions` export (core)

Add `GQL300` (`incompatibleImplementation`), `GQL301` (`ambiguousTypeResolution`) and `GQL302` (`unencodableDefaultValue`) to the catalog, export `Suggestions` (the builder's "Did you mean" hints), and record both in the core's diagnostics guide and CHANGELOG. This is the only core change of M5a.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/diagnostics/suggestions.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/diagnostics.md`
- Test: `packages/typed_graphql/test/diagnostics/diagnostic_test.dart`

**Interfaces:**
- Consumes: the core as on `main`.
- Produces:
- Diagnostic codes: `GQL300` (`incompatibleImplementation`), `GQL301` (`ambiguousTypeResolution`), `GQL302` (`unencodableDefaultValue`).

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql/test/diagnostics/diagnostic_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,6 +9,10 @@ void main() {
       }
     });
 
+    test('Suggestions is reachable from the barrel', () {
+      expect(const Suggestions().didYouMean(['a']), ' Did you mean "a"?');
+    });
+
     test('ids are unique and sorted', () {
       final ids = [for (final code in DiagnosticCode.values) code.id];
       expect(ids.toSet(), hasLength(ids.length));
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -510,4 +510,18 @@ enum DiagnosticCode(
   /// `GQL238`: an operation whose field cost or type cost is more than the
   /// maximum `MaxCostRule` allows.
   maxCostExceeded('GQL238'),
+
+  /// `GQL300`: an object type built with `ExecutableSchemaBuilder` lists an
+  /// interface whose Dart type is not a supertype of the object's Dart type.
+  incompatibleImplementation('GQL300'),
+
+  /// `GQL301`: two possible types of an abstract type have Dart types where
+  /// one is a subtype of the other (or equal), the abstract type has no
+  /// `resolveType`, and not both have `isTypeOf`.
+  ambiguousTypeResolution('GQL301'),
+
+  /// `GQL302`: a default value of an argument or input field built with
+  /// `ExecutableSchemaBuilder` cannot be written as a literal (the codec's
+  /// `encode` throws, or an input object has no `encode`).
+  unencodableDefaultValue('GQL302'),
 }
```

In `packages/typed_graphql/lib/src/diagnostics/suggestions.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,6 +3,8 @@ import 'lexical_distance.dart';
 /// graphql-js's "Did you mean" text: `suggestionList`, `didYouMean`,
 /// `orList` and `naturalCompare`, shared by the messages that suggest a
 /// name.
+///
+/// {@category diagnostics}
 final class const Suggestions() {
   /// Creates the helper; it keeps no state.
   this;
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -17,6 +17,7 @@ export 'src/diagnostics/source.dart';
 export 'src/diagnostics/source_excerpt.dart';
 export 'src/diagnostics/source_location.dart';
 export 'src/diagnostics/source_span.dart';
+export 'src/diagnostics/suggestions.dart';
 export 'src/language/ast/argument.dart';
 export 'src/language/ast/definition.dart';
 export 'src/language/ast/directive.dart';
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/diagnostics/diagnostic_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `GQL300`-`GQL302`: the diagnostics of the executable schema builder (incompatible implementation, ambiguous type resolution, unencodable default value).
- `Suggestions` is exported: graphql-js's "Did you mean" text for messages that suggest a name.
```

In `packages/typed_graphql/doc/diagnostics.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -110,7 +110,7 @@ digit is the area:
 | `GQL0xx` | lexer and syntax |
 | `GQL1xx` | type system: building, validating and introspecting a schema |
 | `GQL2xx` | operation validation |
-| `GQL3xx` | coercion and execution |
+| `GQL3xx` | coercion, execution and the executable schema builder |
 | `GQL4xx` | transports and protocols |
 | `GQL5xx` | code generation |
 
```

- [ ] **Step 5: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/diagnostics.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/diagnostics/suggestions.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/diagnostics/diagnostic_test.dart
git commit -q -m "feat(typed_graphql): add the M5a diagnostic codes and export Suggestions" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Refs, scalars, enums and `Optional`

Create the package's type references (`NamedTypeDef`, `OutputRef`, `InputRef`, `LeafRef` and their nullable and list forms), custom scalars over a `ScalarCodec`, Dart-enum-backed enum types with `EnumValueMapping`, `Optional` (`Present` / `Absent`), the built-in scalar getters, the `DefinitionRegistry` and the `ExecutableSchemaBuilder<C>` entry point. Add the server's external-imports quality test.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/builder/built_in_scalar_definitions.dart`, `packages/typed_graphql_server/lib/src/builder/definition_registry.dart`, `packages/typed_graphql_server/lib/src/builder/enum_type_def.dart`, `packages/typed_graphql_server/lib/src/builder/enum_value_def.dart`, `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, `packages/typed_graphql_server/lib/src/builder/input_list_ref.dart`, `packages/typed_graphql_server/lib/src/builder/input_ref.dart`, `packages/typed_graphql_server/lib/src/builder/leaf_ref.dart`, `packages/typed_graphql_server/lib/src/builder/named_type_def.dart`, `packages/typed_graphql_server/lib/src/builder/nullable_input_ref.dart`, `packages/typed_graphql_server/lib/src/builder/nullable_leaf_ref.dart`, `packages/typed_graphql_server/lib/src/builder/nullable_output_ref.dart`, `packages/typed_graphql_server/lib/src/builder/optional.dart`, `packages/typed_graphql_server/lib/src/builder/output_list_ref.dart`, `packages/typed_graphql_server/lib/src/builder/output_ref.dart`, `packages/typed_graphql_server/lib/src/builder/scalar_type_def.dart`, `packages/typed_graphql_server/lib/src/builder/type_ref_wrapping.dart`
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Test: `packages/typed_graphql_server/test/builder/enum_and_optional_test.dart`, `packages/typed_graphql_server/test/builder/refs_test.dart`, `packages/typed_graphql_server/test/quality/import_rule.dart`, `packages/typed_graphql_server/test/quality/imports_test.dart`

**Interfaces:**
- Consumes: the core barrel (`ScalarCodec`, `JsonValue`, `Suggestions`).
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// builder/built_in_scalar_definitions.dart
mixin BuiltInScalarDefinitions

// builder/definition_registry.dart
final class DefinitionRegistry()
  List<NamedTypeDef> get snapshot

// builder/enum_type_def.dart
final class EnumTypeDef<E
  EnumTypeDef(…)
  String nameOf(E value)
  E? valueNamed(String valueName)
  NamedTypeDef get namedType
  LeafRef<E?> get nullable
  E adapt(Object? coerced)
  JsonValue jsonOf(E value)

// builder/enum_value_def.dart
final class const EnumValueDef<E

// builder/enum_value_mapping.dart
final class const EnumValueMapping<E
  EnumValueDef<E> define(E value)

// builder/executable_schema_builder.dart
final class ExecutableSchemaBuilder<C>(…)
  List<NamedTypeDef> get definitions

// builder/input_list_ref.dart
final class InputListRef<T>(…)
  InputRef<List<T>?> get nullable
  List<T> adapt(Object? coerced)
  JsonValue jsonOf(List<T> value)

// builder/input_ref.dart
abstract interface class InputRef<T>
  TypeRef get typeRef
  NamedTypeDef get namedType
  InputRef<T?> get nullable
  T adapt(Object? coerced)
  JsonValue jsonOf(T value)

// builder/leaf_ref.dart
abstract interface class LeafRef<T>
  LeafRef<T?> get nullable

// builder/named_type_def.dart
abstract base class const NamedTypeDef(…)

// builder/nullable_input_ref.dart
final class NullableInputRef<T>(…)
  InputRef<T?> get nullable
  T? adapt(Object? coerced)
  JsonValue jsonOf(T? value)

// builder/nullable_leaf_ref.dart
final class NullableLeafRef<T>(…)
  LeafRef<T?> get nullable
  T? adapt(Object? coerced)
  JsonValue jsonOf(T? value)

// builder/nullable_output_ref.dart
final class NullableOutputRef<R>(…)
  OutputRef<R?> get nullable

// builder/optional.dart
sealed class const Optional<T>()
final class const Present<T>(…)
  bool operator ==(Object other)
  int get hashCode
  String toString()
final class const Absent(…)
  bool operator ==(Object other)
  int get hashCode
  String toString()

// builder/output_list_ref.dart
final class OutputListRef<R>(OutputRef<R> item)
  OutputRef<Iterable<R>?> get nullable

// builder/output_ref.dart
abstract interface class OutputRef<R>
  TypeRef get typeRef
  NamedTypeDef get namedType
  OutputRef<R?> get nullable

// builder/scalar_type_def.dart
final class ScalarTypeDef<T
  NamedTypeDef get namedType
  LeafRef<T?> get nullable
  T adapt(Object? coerced)
  JsonValue jsonOf(T value)

// builder/type_ref_wrapping.dart
extension TypeRefWrapping on TypeRef
  TypeRef get withoutNonNull
  TypeRef get asNonNullList
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/enum_and_optional_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Color { red, green, blue }

void main() {
  final b = ExecutableSchemaBuilder<Object?>();

  group('enums', () {
    final color = b.enumType<Color>(
      'Color',
      Color.values,
      mapping: EnumValueMapping(
        descriptionOf: (value) => value == Color.red ? 'Warm.' : null,
        deprecationReasonOf: (value) =>
            value == Color.blue ? 'Too cold.' : null,
      ),
      description: 'A colour.',
    );

    test('names default to Enum.name', () {
      expect(color.nameOf(Color.green), 'green');
      expect(color.valueNamed('green'), Color.green);
    });

    test('values keep declaration order with their metadata', () {
      expect(color.values.map((v) => v.name), ['red', 'green', 'blue']);
      expect(color.values.first.description, 'Warm.');
      expect(color.values.last.deprecationReason, 'Too cold.');
      expect(color.description, 'A colour.');
    });

    test('an unknown name has no value', () {
      expect(color.valueNamed('pink'), isNull);
    });

    test('nameOf can be replaced', () {
      final shouting = b.enumType<Color>(
        'Shout',
        Color.values,
        mapping: EnumValueMapping(nameOf: (value) => value.name.toUpperCase()),
      );
      expect(shouting.nameOf(Color.red), 'RED');
      expect(shouting.valueNamed('RED'), Color.red);
    });

    test('a value outside the definition is an ArgumentError', () {
      final partial = b.enumType<Color>('Partial', [Color.red]);
      expect(() => partial.nameOf(Color.blue), throwsArgumentError);
    });

    test('as an input, jsonOf writes the name and adapt casts', () {
      expect(color.jsonOf(Color.red), const JsonString('red'));
      expect(color.adapt(Color.red), Color.red);
      expect(color.nullable.adapt(null), isNull);
    });

    test('refs print as named types', () {
      expect(const Printer().print(color.typeRef), 'Color!');
      expect(const Printer().print(color.nullable.typeRef), 'Color');
    });

    test('the builder records the definition', () {
      expect(b.definitions, contains(color));
    });
  });

  group('Optional', () {
    test('Present values compare by value', () {
      expect(const Present(1), const Present(1));
      expect(const Present(1).hashCode, const Present(1).hashCode);
      expect(const Present(1), isNot(const Present(2)));
    });

    test('Present equality ignores the static type', () {
      const Optional<int?> a = Present<int?>(1);
      const Optional<num> c = Present<num>(1);
      expect(a, c);
    });

    test('Absent equals Absent and nothing else', () {
      expect(const Absent(), const Absent());
      expect(const Absent().hashCode, const Absent().hashCode);
      expect(const Absent(), isNot(const Present<Object?>(null)));
    });

    test('Absent fits every Optional', () {
      const Optional<String> value = Absent();
      expect(value, isA<Absent>());
    });
  });
}
```

Create `packages/typed_graphql_server/test/builder/refs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  String print(TypeRef typeRef) => const Printer().print(typeRef);

  group('output refs', () {
    test('a built-in scalar is non-null', () {
      expect(print(b.string.typeRef), 'String!');
    });

    test('nullable drops the non-null wrapper', () {
      expect(print(b.int.nullable.typeRef), 'Int');
    });

    test('a list is non-null around its item', () {
      expect(print(b.list(b.int).typeRef), '[Int!]!');
    });

    test('a nullable list of nullable items', () {
      expect(print(b.list(b.int.nullable).nullable.typeRef), '[Int]');
    });

    test('the named type is found through wrappers', () {
      expect(b.list(b.boolean).namedType.name, 'Boolean');
    });

    test('nullable of nullable is the same ref', () {
      final once = b.id.nullable;
      expect(once.nullable, same(once));
    });
  });

  group('input refs', () {
    test('an input list prints like an output list', () {
      expect(print(b.inputList(b.float).typeRef), '[Float!]!');
    });

    test('adapt gives a real List<int>', () {
      final adapted = b.inputList(b.int).adapt(<Object?>[1, 2]);
      expect(adapted, isA<List<int>>());
      expect(adapted, [1, 2]);
    });

    test('adapt keeps null in a nullable item list', () {
      final adapted = b.inputList(b.int.nullable).adapt(<Object?>[1, null]);
      expect(adapted, isA<List<int?>>());
      expect(adapted, [1, null]);
    });

    test('adapt of a nullable ref gives null for null', () {
      expect(b.string.nullable.adapt(null), isNull);
    });

    test('jsonOf writes a leaf through its codec', () {
      expect(b.int.jsonOf(3), JsonNumber(3));
    });

    test('jsonOf writes a list as an array and null as JsonNull', () {
      expect(
        b.inputList(b.string.nullable).jsonOf(['a', null]),
        JsonArray([const JsonString('a'), const JsonNull()]),
      );
    });

    test('jsonOf of a value the codec cannot write is an ArgumentError', () {
      expect(() => b.int.jsonOf(1 << 40), throwsArgumentError);
    });
  });

  group('scalars', () {
    test('a custom scalar keeps its codec and url', () {
      final date = b.scalar<String>(
        'Date',
        const StringCodec(),
        description: 'A day.',
        specifiedByUrl: 'https://example.com/date',
      );
      expect(date.name, 'Date');
      expect(date.description, 'A day.');
      expect(date.specifiedByUrl, 'https://example.com/date');
      expect(print(date.typeRef), 'Date!');
    });

    test('built-in scalars are not declared types', () {
      final fresh = ExecutableSchemaBuilder<Object?>();
      fresh.scalar<String>('Date', const StringCodec());
      expect(fresh.definitions.map((d) => d.name), ['Date']);
    });

    test('a builder has one instance of each built-in scalar', () {
      expect(b.int, same(b.int));
      expect(b.int.name, 'Int');
      expect(b.float.name, 'Float');
      expect(b.boolean.name, 'Boolean');
      expect(b.id.name, 'ID');
    });
  });
}
```

Create `packages/typed_graphql_server/test/quality/import_rule.dart`:

```dart
/// The server's import rules (spec 2 and 17.4, R0.6), checked on the text of
/// one library under `lib/`.
///
/// The server runs on the VM, AOT, dart2js and dart2wasm, so it imports pure
/// Dart, `meta`, the core's barrel and its own files, never `src/` of the
/// core and never a web framework.
final class ImportRule {
  /// Creates the rule.
  const ImportRule();

  /// The libraries that run on every platform the server supports.
  static const Set<String> _pureDart = {
    'dart:async',
    'dart:collection',
    'dart:core',
    'dart:math',
  };

  static const String _coreBarrel = 'package:typed_graphql/typed_graphql.dart';

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
          : '$filePath imports $target: the server is platform independent';
    }
    if (target.startsWith('package:meta/') || target == _coreBarrel) {
      return null;
    }
    if (target.startsWith('package:')) {
      return '$filePath imports $target: only meta and the core barrel '
          '($_coreBarrel) are allowed';
    }
    return null;
  }
}
```

Create `packages/typed_graphql_server/test/quality/imports_test.dart`:

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
          'lib/src/builder/a.dart',
          "import 'dart:async';\n"
              "import 'dart:core' as core;\n"
              "import 'package:meta/meta.dart';\n"
              "import 'package:typed_graphql/typed_graphql.dart';\n"
              "import '../execution/b.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects dart:io', () {
      expect(
        rule.check('lib/src/builder/a.dart', "import 'dart:io';\n"),
        hasLength(1),
      );
    });

    test('rejects the core src folder', () {
      expect(
        rule.check(
          'lib/src/builder/a.dart',
          "import 'package:typed_graphql/src/schema/schema.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('rejects shelf', () {
      expect(
        rule.check(
          'lib/src/builder/a.dart',
          "import 'package:shelf/shelf.dart';\n",
        ),
        hasLength(1),
      );
    });
  });

  test('lib follows the import rule', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      startsWith('name: typed_graphql_server\n'),
      reason: 'run from packages/typed_graphql_server',
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

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/enum_and_optional_test.dart test/builder/refs_test.dart test/quality/imports_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/builder/built_in_scalar_definitions.dart`:

```dart
import 'dart:core';
import 'dart:core' as core;

import 'package:typed_graphql/typed_graphql.dart';

import 'scalar_type_def.dart';

/// The five built-in scalars of an `ExecutableSchemaBuilder`.
///
/// A member named `int` hides the type `int` in its class, which is why
/// these live in their own mixin and spell `core.int`. The scalars are not
/// declared types: the core's `BuiltIns` provides them.
mixin BuiltInScalarDefinitions {
  /// `Int`: a signed 32-bit integer.
  final ScalarTypeDef<core.int> int = ScalarTypeDef('Int', const IntCodec());

  /// `Float`: a double-precision number.
  final ScalarTypeDef<double> float = ScalarTypeDef(
    'Float',
    const FloatCodec(),
  );

  /// `String`: UTF-8 text.
  final ScalarTypeDef<String> string = ScalarTypeDef(
    'String',
    const StringCodec(),
  );

  /// `Boolean`: true or false.
  final ScalarTypeDef<bool> boolean = ScalarTypeDef(
    'Boolean',
    const BooleanCodec(),
  );

  /// `ID`: a unique identifier, held as a string.
  final ScalarTypeDef<String> id = ScalarTypeDef('ID', const IdCodec());
}
```

Create `packages/typed_graphql_server/lib/src/builder/definition_registry.dart`:

```dart
import 'named_type_def.dart';

/// The definitions an `ExecutableSchemaBuilder` created, in creation order.
final class DefinitionRegistry() {
  /// Creates an empty registry.
  this;

  final List<NamedTypeDef> _definitions = <NamedTypeDef>[];

  /// A snapshot of the definitions, so one made after a build does not
  /// change a schema already built.
  List<NamedTypeDef> get snapshot => List.unmodifiable(_definitions);

  /// Records [definition] and returns it.
  D add<D extends NamedTypeDef>(D definition) {
    _definitions.add(definition);
    return definition;
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/enum_type_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'enum_value_def.dart';
import 'leaf_ref.dart';
import 'named_type_def.dart';
import 'nullable_leaf_ref.dart';

/// An enum type that maps the Dart enum [E] to GraphQL value names and back.
///
/// It is its own output and input reference. The coerced value of an enum
/// input is the Dart value itself.
///
/// {@category builder}
final class EnumTypeDef<E extends Enum> extends NamedTypeDef
    implements LeafRef<E> {
  /// Declares the enum [name] with [values], in declaration order.
  EnumTypeDef(super.name, List<EnumValueDef<E>> values, {super.description})
    : values = List.unmodifiable(values),
      _namesByValue = {for (final entry in values) entry.value: entry.name},
      _valuesByName = {for (final entry in values) entry.name: entry.value},
      typeRef = NonNullType(NamedType(Name(name)));

  /// The values in declaration order (the order the schema lists them).
  final List<EnumValueDef<E>> values;

  // Lookup only: output follows [values], never these maps.
  final Map<E, String> _namesByValue;
  final Map<String, E> _valuesByName;

  /// The schema name of [value]; an [ArgumentError] when this enum does not
  /// declare it.
  String nameOf(E value) =>
      _namesByValue[value] ??
      (throw ArgumentError.value(value, 'value', 'is not a value of $name'));

  /// The value named [valueName] in the schema; null when there is none.
  E? valueNamed(String valueName) => _valuesByName[valueName];

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  LeafRef<E?> get nullable => NullableLeafRef(this);

  @override
  E adapt(Object? coerced) => coerced as E;

  @override
  JsonValue jsonOf(E value) => JsonString(nameOf(value));
}
```

Create `packages/typed_graphql_server/lib/src/builder/enum_value_def.dart`:

```dart
/// One value of an `EnumTypeDef`: the Dart value and what the schema says
/// about it.
///
/// {@category builder}
final class const EnumValueDef<E extends Enum>(
  /// The Dart value.
  final E value,

  /// The value's name in the schema.
  final String name, {

  /// The value's description, null when it has none.
  final String? description,

  /// Why the value is deprecated, null when it is not.
  final String? deprecationReason,
}) {
  /// Describes [value], named [name] in the schema.
  this;
}
```

Create `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart`:

```dart
import 'enum_value_def.dart';

/// How the values of a Dart enum appear in the schema: their names,
/// descriptions and deprecations.
///
/// Passed to `ExecutableSchemaBuilder.enumType`; the defaults are
/// [Enum.name] and no description or deprecation.
///
/// {@category builder}
final class const EnumValueMapping<E extends Enum>({
  /// The schema name of a value; null means [Enum.name].
  final String Function(E value)? nameOf,

  /// The description of a value, null for none.
  final String? Function(E value)? descriptionOf,

  /// The deprecation reason of a value, null when it is not deprecated.
  final String? Function(E value)? deprecationReasonOf,
}) {
  /// Describes how enum values appear in the schema.
  this;

  /// The definition of [value] under this mapping.
  EnumValueDef<E> define(E value) => EnumValueDef(
    value,
    nameOf == null ? value.name : nameOf!(value),
    description: descriptionOf?.call(value),
    deprecationReason: deprecationReasonOf?.call(value),
  );
}
```

Create `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'built_in_scalar_definitions.dart';
import 'definition_registry.dart';
import 'enum_type_def.dart';
import 'enum_value_mapping.dart';
import 'input_list_ref.dart';
import 'input_ref.dart';
import 'named_type_def.dart';
import 'output_list_ref.dart';
import 'output_ref.dart';
import 'scalar_type_def.dart';

/// Declares the types of a schema in typed Dart code; `C` is the context
/// type every resolver receives (R4.1).
///
/// Every definition made through a builder is part of the schema it builds,
/// in creation order. The core already exports `SchemaBuilder` (SDL to
/// schema), hence the name.
///
/// {@category builder}
final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
  /// Creates a builder with no definitions.
  this;

  final DefinitionRegistry _registry = DefinitionRegistry();

  /// The definitions made so far, in creation order.
  List<NamedTypeDef> get definitions => _registry.snapshot;

  /// Declares the custom scalar [name] over [codec].
  ScalarTypeDef<T> scalar<T extends Object>(
    String name,
    ScalarCodec<T> codec, {
    String? description,
    String? specifiedByUrl,
  }) => _registry.add(
    ScalarTypeDef(
      name,
      codec,
      description: description,
      specifiedByUrl: specifiedByUrl,
    ),
  );

  /// Declares the enum [name] over the Dart enum [values].
  ///
  /// [mapping] gives the names, descriptions and deprecations of the values
  /// (a value's name defaults to [Enum.name]); the parameters of the three
  /// callbacks are grouped in one object to keep the signature short.
  EnumTypeDef<E> enumType<E extends Enum>(
    String name,
    List<E> values, {
    EnumValueMapping<E>? mapping,
    String? description,
  }) {
    final effective = mapping ?? EnumValueMapping<E>();
    return _registry.add(
      EnumTypeDef(name, [
        for (final value in values) effective.define(value),
      ], description: description),
    );
  }

  /// The non-null list of [item] as an output type.
  OutputRef<Iterable<R>> list<R>(OutputRef<R> item) => OutputListRef(item);

  /// The non-null list of [item] as an input type.
  InputRef<List<T>> inputList<T>(InputRef<T> item) => InputListRef(item);
}
```

Create `packages/typed_graphql_server/lib/src/builder/input_list_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'named_type_def.dart';
import 'nullable_input_ref.dart';
import 'type_ref_wrapping.dart';

/// A non-null list of items; its Dart value is a `List<T>`.
final class InputListRef<T>(InputRef<T> item) implements InputRef<List<T>> {
  /// Makes the list type of [item].
  this;

  final InputRef<T> _item = item;

  @override
  final TypeRef typeRef = item.typeRef.asNonNullList;

  @override
  final NamedTypeDef namedType = item.namedType;

  @override
  InputRef<List<T>?> get nullable => NullableInputRef(this);

  @override
  List<T> adapt(Object? coerced) {
    // The coercion wraps a single value where a list is expected (spec
    // 3.11), so only a real list reaches this method.
    final items = coerced as List<Object?>;
    return <T>[for (final element in items) _item.adapt(element)];
  }

  @override
  JsonValue jsonOf(List<T> value) =>
      JsonArray([for (final element in value) _item.jsonOf(element)]);
}
```

Create `packages/typed_graphql_server/lib/src/builder/input_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';

/// A GraphQL input type decoded to the Dart value [T] (spec 3.3).
///
/// Non-null by default; [nullable] gives the nullable form.
///
/// {@category builder}
abstract interface class InputRef<T> {
  /// The type as a language node, such as `NonNullType(NamedType(...))`.
  TypeRef get typeRef;

  /// The named type this reference ends in, through lists and nullability.
  NamedTypeDef get namedType;

  /// This type without the non-null wrapper.
  InputRef<T?> get nullable;

  /// The typed value of [coerced], a value the input coercion produced.
  ///
  /// Lists are rebuilt as a real `List<X>` (generics are reified, so a
  /// `List<Object?>` would not do) and leaves are cast. A value of the wrong
  /// type is a `TypeError`: coercion already checked it, so it is a bug.
  T adapt(Object? coerced);

  /// The JSON form of [value], used to write default values: a leaf goes
  /// through its codec or its enum name, a list becomes an array and null
  /// becomes [JsonNull]. A value the type cannot write is an [ArgumentError]
  /// or a [StateError].
  JsonValue jsonOf(T value);
}
```

Create `packages/typed_graphql_server/lib/src/builder/leaf_ref.dart`:

```dart
import 'input_ref.dart';
import 'output_ref.dart';

/// A reference to a scalar or enum type, which serves as an output and as
/// an input type (spec 3.3).
///
/// {@category builder}
abstract interface class LeafRef<T> implements OutputRef<T>, InputRef<T> {
  /// This type without the non-null wrapper.
  @override
  LeafRef<T?> get nullable;
}
```

Create `packages/typed_graphql_server/lib/src/builder/named_type_def.dart`:

```dart
/// A named GraphQL type declared through `ExecutableSchemaBuilder`.
///
/// Holds the name and description only; what a definition can do at run time
/// lives in the subclasses and in the schema binding tables.
///
/// {@category builder}
abstract base class const NamedTypeDef(
  /// The type's name.
  final String name, {

  /// The type's description, null when it has none.
  final String? description,
}) {
  /// Creates a definition named [name].
  this;
}
```

Create `packages/typed_graphql_server/lib/src/builder/nullable_input_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'named_type_def.dart';
import 'type_ref_wrapping.dart';

/// The nullable form of an input reference.
final class NullableInputRef<T>(InputRef<T> inner) implements InputRef<T?> {
  /// Wraps [inner].
  this;

  final InputRef<T> _inner = inner;

  @override
  final TypeRef typeRef = inner.typeRef.withoutNonNull;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  InputRef<T?> get nullable => this;

  @override
  T? adapt(Object? coerced) => coerced == null ? null : _inner.adapt(coerced);

  @override
  JsonValue jsonOf(T? value) =>
      value == null ? const JsonNull() : _inner.jsonOf(value);
}
```

Create `packages/typed_graphql_server/lib/src/builder/nullable_leaf_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'leaf_ref.dart';
import 'named_type_def.dart';
import 'type_ref_wrapping.dart';

/// The nullable form of a scalar or enum reference.
final class NullableLeafRef<T>(LeafRef<T> inner) implements LeafRef<T?> {
  /// Wraps [inner].
  this;

  final LeafRef<T> _inner = inner;

  @override
  final TypeRef typeRef = inner.typeRef.withoutNonNull;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  LeafRef<T?> get nullable => this;

  @override
  T? adapt(Object? coerced) => coerced == null ? null : _inner.adapt(coerced);

  @override
  JsonValue jsonOf(T? value) =>
      value == null ? const JsonNull() : _inner.jsonOf(value);
}
```

Create `packages/typed_graphql_server/lib/src/builder/nullable_output_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';
import 'output_ref.dart';
import 'type_ref_wrapping.dart';

/// The nullable form of an output reference.
final class NullableOutputRef<R>(OutputRef<R> inner) implements OutputRef<R?> {
  /// Wraps [inner].
  this;

  @override
  final TypeRef typeRef = inner.typeRef.withoutNonNull;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  OutputRef<R?> get nullable => this;
}
```

Create `packages/typed_graphql_server/lib/src/builder/optional.dart`:

```dart
/// A value that may be absent, for inputs where absence differs from `null`
/// (partial updates; R4.4).
///
/// {@category builder}
sealed class const Optional<T>() {
  /// Creates an optional value.
  this;
}

/// A value that was given, possibly `null` when [T] allows it.
///
/// {@category builder}
final class const Present<T>(
  /// The given value.
  final T value,
) extends Optional<T> {
  /// Holds [value].
  this;

  // Checks `Present<Object?>`, not `Present<T>`: two equal values with
  // different static types must stay equal.
  @override
  bool operator ==(Object other) =>
      other is Present<Object?> && other.value == value;

  @override
  int get hashCode => Object.hash(Present, value);

  @override
  String toString() => 'Present($value)';
}

/// A value that was not given.
///
/// It is an `Optional<Never>`, so it fits every `Optional<T>`.
///
/// {@category builder}
final class const Absent() extends Optional<Never> {
  /// The absent value.
  this;

  @override
  bool operator ==(Object other) => other is Absent;

  @override
  int get hashCode => (Absent).hashCode;

  @override
  String toString() => 'Absent()';
}
```

Create `packages/typed_graphql_server/lib/src/builder/output_list_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'output_ref.dart';
import 'type_ref_wrapping.dart';

/// A non-null list of items; its Dart value is an [Iterable] of [R].
final class OutputListRef<R>(OutputRef<R> item)
    implements OutputRef<Iterable<R>> {
  /// Makes the list type of [item].
  this;

  @override
  final TypeRef typeRef = item.typeRef.asNonNullList;

  @override
  final NamedTypeDef namedType = item.namedType;

  @override
  OutputRef<Iterable<R>?> get nullable => NullableOutputRef(this);
}
```

Create `packages/typed_graphql_server/lib/src/builder/output_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';

/// A GraphQL output type whose Dart value is [R] (spec 3.3).
///
/// Non-null by default; [nullable] gives the nullable form. Implemented by
/// the type definitions and by the wrappers `ExecutableSchemaBuilder.list`
/// and [nullable] make.
///
/// {@category builder}
abstract interface class OutputRef<R> {
  /// The type as a language node, such as `NonNullType(NamedType(...))`.
  TypeRef get typeRef;

  /// The named type this reference ends in, through lists and nullability.
  NamedTypeDef get namedType;

  /// This type without the non-null wrapper.
  OutputRef<R?> get nullable;
}
```

Create `packages/typed_graphql_server/lib/src/builder/scalar_type_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'leaf_ref.dart';
import 'named_type_def.dart';
import 'nullable_leaf_ref.dart';

/// A scalar type: a name, a [ScalarCodec] and the Dart type [T] it holds.
///
/// It is its own output and input reference.
///
/// {@category builder}
final class ScalarTypeDef<T extends Object>(
  super.name,

  /// Reads and writes the values of this scalar.
  final ScalarCodec<T> codec, {
  super.description,

  /// The URL of the scalar's specification, written as `@specifiedBy`.
  final String? specifiedByUrl,
}) extends NamedTypeDef implements LeafRef<T> {
  /// Declares the scalar [name] over [codec].
  this;

  @override
  final TypeRef typeRef = NonNullType(NamedType(Name(name)));

  @override
  NamedTypeDef get namedType => this;

  @override
  LeafRef<T?> get nullable => NullableLeafRef(this);

  @override
  T adapt(Object? coerced) => coerced as T;

  @override
  JsonValue jsonOf(T value) => codec.encode(value);
}
```

Create `packages/typed_graphql_server/lib/src/builder/type_ref_wrapping.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The wrapping the refs apply to language type nodes.
extension TypeRefWrapping on TypeRef {
  /// This type without its non-null wrapper.
  TypeRef get withoutNonNull => switch (this) {
    NonNullType(:final type) => type,
    _ => this,
  };

  /// The non-null list whose items are this type.
  TypeRef get asNonNullList => NonNullType(ListType(this));
}
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,5 +2,17 @@
 /// engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws
 /// and graphql-sse handlers.
 ///
-/// Under construction: nothing is exported yet; see the package README.
+/// Under construction: the typed schema builder is partly in place (refs,
+/// scalars, enums); see the package README.
 library;
+
+export 'src/builder/enum_type_def.dart';
+export 'src/builder/enum_value_def.dart';
+export 'src/builder/enum_value_mapping.dart';
+export 'src/builder/executable_schema_builder.dart';
+export 'src/builder/input_ref.dart';
+export 'src/builder/leaf_ref.dart';
+export 'src/builder/named_type_def.dart';
+export 'src/builder/optional.dart';
+export 'src/builder/output_ref.dart';
+export 'src/builder/scalar_type_def.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/enum_and_optional_test.dart test/builder/refs_test.dart test/quality/imports_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/builder/built_in_scalar_definitions.dart packages/typed_graphql_server/lib/src/builder/definition_registry.dart packages/typed_graphql_server/lib/src/builder/enum_type_def.dart packages/typed_graphql_server/lib/src/builder/enum_value_def.dart packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart packages/typed_graphql_server/lib/src/builder/input_list_ref.dart packages/typed_graphql_server/lib/src/builder/input_ref.dart packages/typed_graphql_server/lib/src/builder/leaf_ref.dart packages/typed_graphql_server/lib/src/builder/named_type_def.dart packages/typed_graphql_server/lib/src/builder/nullable_input_ref.dart packages/typed_graphql_server/lib/src/builder/nullable_leaf_ref.dart packages/typed_graphql_server/lib/src/builder/nullable_output_ref.dart packages/typed_graphql_server/lib/src/builder/optional.dart packages/typed_graphql_server/lib/src/builder/output_list_ref.dart packages/typed_graphql_server/lib/src/builder/output_ref.dart packages/typed_graphql_server/lib/src/builder/scalar_type_def.dart packages/typed_graphql_server/lib/src/builder/type_ref_wrapping.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/enum_and_optional_test.dart packages/typed_graphql_server/test/builder/refs_test.dart packages/typed_graphql_server/test/quality/import_rule.dart packages/typed_graphql_server/test/quality/imports_test.dart
git commit -q -m "feat(typed_graphql_server): add the output and input refs, scalars and enums" \
  -m "Refs, scalar and enum definitions, Optional, the first ExecutableSchemaBuilder members and the server import-rule test." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Typed arguments and input objects

Add `Arg<T>` (required, optional, with default), `Arguments` (reads both field arguments and input fields from coerced values), `ArgumentsDef`, and `InputObjectDef<T>` with `inputObject` and `oneOfInputObject` on the builder; `OptionalInputRef` (internal) maps an optional argument to `Optional<T>`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/builder/arg.dart`, `packages/typed_graphql_server/lib/src/builder/arguments.dart`, `packages/typed_graphql_server/lib/src/builder/arguments_def.dart`, `packages/typed_graphql_server/lib/src/builder/input_object_def.dart`, `packages/typed_graphql_server/lib/src/builder/optional_input_ref.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Test: `packages/typed_graphql_server/test/builder/arguments_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// builder/arg.dart
final class Arg<T>
  Arg(…)
  JsonValue? get defaultJson
  T read(Map<String, Object?> coerced)

// builder/arguments.dart
final class Arguments

// builder/arguments_def.dart
final class ArgumentsDef<A>
  ArgumentsDef(List<Arg<Object?>> args, this.decode)

// builder/input_object_def.dart
final class InputObjectDef<T
  InputObjectDef(…)
  NamedTypeDef get namedType
  InputRef<T?> get nullable
  T adapt(Object? coerced)
  JsonValue jsonOf(T value)

// builder/optional_input_ref.dart
final class OptionalInputRef<T>(InputRef<T> inner)
  InputRef<Optional<T>?> get nullable
  Optional<T> adapt(Object? coerced)
  JsonValue jsonOf(Optional<T> value)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/arguments_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final first = Arg('first', b.int, defaultValue: 10);
  final after = Arg('after', b.string.nullable);
  final note = Arg.optional('note', b.string.nullable);
  final declared = <Arg<Object?>>[first, after, note];

  Arguments argumentsOf(Map<String, Object?> coerced) =>
      Arguments(declared, coerced);

  group('Arguments', () {
    test('reads a present value', () {
      expect(argumentsOf({'first': 3}).get(first), 3);
    });

    test('reads the default of a missing argument', () {
      expect(argumentsOf({}).get(first), 10);
    });

    test('reads null for a missing nullable argument', () {
      expect(argumentsOf({}).get(after), isNull);
    });

    test('reads an explicit null of a nullable argument', () {
      expect(argumentsOf({'after': null}).get(after), isNull);
    });

    test('an optional argument is absent when missing', () {
      expect(argumentsOf({}).get(note), const Absent());
    });

    test('an optional argument is present when given, even as null', () {
      expect(
        argumentsOf({'note': null}).get(note),
        const Present<String?>(null),
      );
    });

    test('an argument that was not declared is a StateError', () {
      final other = Arg('first', b.int);
      expect(() => argumentsOf({'first': 1}).get(other), throwsStateError);
    });

    test('empty declares nothing', () {
      expect(() => Arguments.empty.get(first), throwsStateError);
    });

    test('a list argument is a real List', () {
      final ids = Arg('ids', b.inputList(b.int));
      final values = Arguments(
        [ids],
        {
          'ids': <Object?>[1, 2],
        },
      );
      expect(values.get(ids), isA<List<int>>());
    });
  });

  group('Arg', () {
    test('has no default JSON without a default', () {
      expect(after.defaultJson, isNull);
    });

    test('writes its default as JSON', () {
      expect(first.defaultJson, JsonNumber(10));
    });

    test('an optional argument keeps the type of its inner reference', () {
      expect(const Printer().print(note.type.typeRef), 'String');
    });
  });

  group('ArgumentsDef', () {
    test('decodes the arguments into a class', () {
      final def = ArgumentsDef<int>([first], (a) => a.get(first) * 2);
      expect(def.decode(Arguments(def.args, {'first': 4})), 8);
    });
  });

  group('InputObjectDef', () {
    late Arg<int> x;
    late Arg<int> y;
    InputObjectDef<Point> make({bool withEncode = false}) {
      x = Arg('x', b.int);
      y = Arg('y', b.int);
      return b.inputObject<Point>(
        'PointInput',
        fields: () => [x, y],
        decode: (v) => Point(v.get(x), v.get(y)),
        encode: withEncode
            ? (p) => JsonObject({'x': JsonNumber(p.x), 'y': JsonNumber(p.y)})
            : null,
      );
    }

    test('decodes its fields', () {
      final def = make();
      final point = def.decode(Arguments(def.fields, {'x': 1, 'y': 2}));
      expect(point.y, 2);
    });

    test('is a non-null reference to itself', () {
      expect(const Printer().print(make().typeRef), 'PointInput!');
    });

    test('evaluates the fields thunk once', () {
      var calls = 0;
      final def = b.inputObject<Point>(
        'Counted',
        fields: () {
          calls++;
          return const <Arg<Object?>>[];
        },
        decode: (v) => const Point(0, 0),
      );
      expect(def.fields, same(def.fields));
      expect(calls, 1);
    });

    test('writes a value as JSON through encode', () {
      expect(
        make(withEncode: true).jsonOf(const Point(1, 2)),
        JsonObject({'x': JsonNumber(1), 'y': JsonNumber(2)}),
      );
    });

    test('a oneOf input object says so', () {
      final def = b.oneOfInputObject<Point>(
        'Either',
        fields: () => const <Arg<Object?>>[],
        decode: (v) => const Point(0, 0),
      );
      expect([def.isOneOf, make().isOneOf], [true, false]);
    });

    test('without encode a value cannot be written', () {
      expect(() => make().jsonOf(const Point(1, 2)), throwsStateError);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/arguments_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/builder/arg.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'optional.dart';
import 'optional_input_ref.dart';

/// A typed argument of a field, or a field of an input object (R4.3).
///
/// A null [defaultValue] means "no default" (spec 3.5): a nullable argument
/// without a value is `null` anyway, and [Arg.optional] tells absence apart.
///
/// {@category builder}
final class Arg<T> {
  /// Declares the argument [name] of type [type].
  Arg(
    this.name,
    this.type, {
    this.defaultValue,
    this.description,
    this.deprecationReason,
  }) : _absentValue = null;

  Arg._optional(
    this.name,
    this.type, {
    this.description,
    this.deprecationReason,
  }) : defaultValue = null,
       _absentValue = const Absent() as T;

  /// Declares an argument whose absence differs from `null`: its value is
  /// [Present] when the request gave one and [Absent] when it did not (R4.4).
  static Arg<Optional<T>> optional<T>(
    String name,
    InputRef<T> type, {
    String? description,
    String? deprecationReason,
  }) => Arg<Optional<T>>._optional(
    name,
    OptionalInputRef(type),
    description: description,
    deprecationReason: deprecationReason,
  );

  /// The argument's name in the schema.
  final String name;

  /// The argument's type.
  final InputRef<T> type;

  /// The value used when the request gives none; null when there is no
  /// default.
  final T? defaultValue;

  /// The description, null when there is none.
  final String? description;

  /// Why the argument is deprecated, null when it is not.
  final String? deprecationReason;

  // What a missing key reads as, before the default is considered.
  final T? _absentValue;

  /// The default value as JSON for the schema, null when there is no default.
  ///
  /// A value the type cannot write is an [ArgumentError] or a [StateError].
  JsonValue? get defaultJson {
    final value = defaultValue;
    return value == null ? null : type.jsonOf(value);
  }

  /// The typed value of this argument in [coerced], a map of coerced values
  /// whose absent keys are absent.
  ///
  /// A required argument cannot be missing once coercion has run, so a
  /// missing one without a default or an absent form is a bug (a `TypeError`
  /// when [T] does not allow null).
  T read(Map<String, Object?> coerced) {
    if (coerced.containsKey(name)) {
      return type.adapt(coerced[name]);
    }
    return (_absentValue ?? defaultValue) as T;
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/arguments.dart`:

```dart
import 'arg.dart';

/// The coerced values of one field call, or of one input object, read
/// through the [Arg]s the field or object declared (R4.3).
///
/// {@category builder}
final class Arguments {
  /// Reads [coerced], keyed by name, for the [declared] arguments. A key the
  /// request did not give is absent from the map.
  const Arguments(this.declared, this.coerced);

  /// No arguments.
  static const Arguments empty = Arguments(
    <Arg<Object?>>[],
    <String, Object?>{},
  );

  /// The arguments the field or input object declares.
  final List<Arg<Object?>> declared;

  /// The coerced values by argument name.
  final Map<String, Object?> coerced;

  /// The typed value of [arg].
  ///
  /// A [StateError] when [arg] is not one of the [declared] arguments (the
  /// same object, not only the same name).
  T get<T>(Arg<T> arg) {
    for (final candidate in declared) {
      if (identical(candidate, arg)) {
        return arg.read(coerced);
      }
    }
    throw StateError('Argument "${arg.name}" is not declared by this field.');
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/arguments_def.dart`:

```dart
import 'arg.dart';
import 'arguments.dart';

/// A list of arguments and how to decode them into the class [A] (R4.3).
///
/// {@category builder}
final class ArgumentsDef<A> {
  /// Declares [args] and the [decode] function that builds [A] from them.
  ArgumentsDef(List<Arg<Object?>> args, this.decode)
    : args = List.unmodifiable(args);

  /// The arguments, in declaration order.
  final List<Arg<Object?>> args;

  /// Builds the arguments class from the coerced values.
  final A Function(Arguments arguments) decode;
}
```

Create `packages/typed_graphql_server/lib/src/builder/input_object_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'arguments.dart';
import 'input_ref.dart';
import 'named_type_def.dart';
import 'nullable_input_ref.dart';

/// An input object type decoded to the Dart class [T] (R4.4).
///
/// It is its own input reference. The coerced value of an input object is the
/// result of [decode].
///
/// {@category builder}
final class InputObjectDef<T extends Object> extends NamedTypeDef
    implements InputRef<T> {
  /// Declares the input object [name].
  ///
  /// [fieldsThunk] runs on first use, so types may refer to each other.
  InputObjectDef(
    super.name,
    List<Arg<Object?>> Function() fieldsThunk,
    this.decode, {
    this.encode,
    this.isOneOf = false,
    super.description,
  }) : _fieldsThunk = fieldsThunk,
       typeRef = NonNullType(NamedType(Name(name)));

  final List<Arg<Object?>> Function() _fieldsThunk;

  /// The fields, as arguments in all but name.
  // Set on first read, so recursive input types can refer to each other
  // while their definitions are made.
  late final List<Arg<Object?>> fields = List.unmodifiable(_fieldsThunk());

  /// Builds [T] from the coerced field values.
  final T Function(Arguments values) decode;

  /// Writes a value as a JSON object; needed only to print a default value
  /// of this type.
  final JsonObject Function(T value)? encode;

  /// Whether this is a `@oneOf` input object.
  final bool isOneOf;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  InputRef<T?> get nullable => NullableInputRef(this);

  @override
  T adapt(Object? coerced) => coerced as T;

  @override
  JsonValue jsonOf(T value) {
    final write = encode;
    if (write == null) {
      throw StateError(
        'Input object "$name" has no encode function, so a default value of '
        'this type cannot be written.',
      );
    }
    return write(value);
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/optional_input_ref.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'input_ref.dart';
import 'named_type_def.dart';
import 'nullable_input_ref.dart';
import 'optional.dart';

/// The input reference of an `Arg.optional`: the schema type of [inner],
/// whose Dart value tells a given value from an absent one.
final class OptionalInputRef<T>(InputRef<T> inner)
    implements InputRef<Optional<T>> {
  /// Wraps [inner].
  this;

  final InputRef<T> _inner = inner;

  @override
  final TypeRef typeRef = inner.typeRef;

  @override
  final NamedTypeDef namedType = inner.namedType;

  @override
  InputRef<Optional<T>?> get nullable => NullableInputRef(this);

  @override
  Optional<T> adapt(Object? coerced) => Present(_inner.adapt(coerced));

  @override
  JsonValue jsonOf(Optional<T> value) => switch (value) {
    Present(:final value) => _inner.jsonOf(value),
    Absent() => throw StateError('An absent value has no JSON form.'),
  };
}
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,10 +1,13 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import 'arg.dart';
+import 'arguments.dart';
 import 'built_in_scalar_definitions.dart';
 import 'definition_registry.dart';
 import 'enum_type_def.dart';
 import 'enum_value_mapping.dart';
 import 'input_list_ref.dart';
+import 'input_object_def.dart';
 import 'input_ref.dart';
 import 'named_type_def.dart';
 import 'output_list_ref.dart';
@@ -67,4 +70,45 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
 
   /// The non-null list of [item] as an input type.
   InputRef<List<T>> inputList<T>(InputRef<T> item) => InputListRef(item);
+
+  /// Declares the input object [name] decoded to [T].
+  ///
+  /// [fields] runs once, on first use. [decode] builds [T] from the coerced
+  /// values; [encode] is needed only when a default value of this type is
+  /// declared.
+  InputObjectDef<T> inputObject<T extends Object>(
+    String name, {
+    required List<Arg<Object?>> Function() fields,
+    required T Function(Arguments values) decode,
+    JsonObject Function(T value)? encode,
+    String? description,
+  }) => _registry.add(
+    InputObjectDef(
+      name,
+      fields,
+      decode,
+      encode: encode,
+      description: description,
+    ),
+  );
+
+  /// Declares the `@oneOf` input object [name]: exactly one of its fields is
+  /// given. The parameters are those of [inputObject]; this is a separate
+  /// method to keep each signature within five parameters.
+  InputObjectDef<T> oneOfInputObject<T extends Object>(
+    String name, {
+    required List<Arg<Object?>> Function() fields,
+    required T Function(Arguments values) decode,
+    JsonObject Function(T value)? encode,
+    String? description,
+  }) => _registry.add(
+    InputObjectDef(
+      name,
+      fields,
+      decode,
+      encode: encode,
+      isOneOf: true,
+      description: description,
+    ),
+  );
 }
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,13 +3,17 @@
 /// and graphql-sse handlers.
 ///
 /// Under construction: the typed schema builder is partly in place (refs,
-/// scalars, enums); see the package README.
+/// scalars, enums, arguments, input objects); see the package README.
 library;
 
+export 'src/builder/arg.dart';
+export 'src/builder/arguments.dart';
+export 'src/builder/arguments_def.dart';
 export 'src/builder/enum_type_def.dart';
 export 'src/builder/enum_value_def.dart';
 export 'src/builder/enum_value_mapping.dart';
 export 'src/builder/executable_schema_builder.dart';
+export 'src/builder/input_object_def.dart';
 export 'src/builder/input_ref.dart';
 export 'src/builder/leaf_ref.dart';
 export 'src/builder/named_type_def.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/arguments_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/builder/arg.dart packages/typed_graphql_server/lib/src/builder/arguments.dart packages/typed_graphql_server/lib/src/builder/arguments_def.dart packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart packages/typed_graphql_server/lib/src/builder/input_object_def.dart packages/typed_graphql_server/lib/src/builder/optional_input_ref.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/arguments_test.dart
git commit -q -m "feat(typed_graphql_server): add typed arguments and input objects" \
  -m "Arg, Arg.optional, Arguments (also used for input object fields), ArgumentsDef, InputObjectDef and ExecutableSchemaBuilder.inputObject/oneOfInputObject." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Object types and typed fields

Add `ObjectTypeDef<P>`, `ObjectOptions`, `FieldInfo`, `FieldDef<P, C>` and the two-step `FieldStub` (`pure`, `resolve`, `resolveWith`, `declareOnly`, and the modifiers `deprecated` / `withDirectives`), with the internal sealed `FieldLane` (`PureLane`, `ResolverLane`, `DeclaredOnlyLane`) whose functions take `Object?` so no `C`-typed member makes the definition invariant.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/builder/field_def.dart`, `packages/typed_graphql_server/lib/src/builder/field_lane.dart`, `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, `packages/typed_graphql_server/lib/src/builder/fields_builder.dart`, `packages/typed_graphql_server/lib/src/builder/object_options.dart`, `packages/typed_graphql_server/lib/src/builder/object_type_def.dart`, `packages/typed_graphql_server/lib/src/execution/field_info.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Test: `packages/typed_graphql_server/test/builder/fields_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// builder/field_def.dart
final class FieldDef<P, C>
  FieldDef(…)

// builder/field_lane.dart
sealed class FieldLane
final class PureLane
final class ResolverLane
final class DeclaredOnlyLane

// builder/field_stub.dart
final class FieldStub<P, R, C>
  FieldStub(…)
  FieldStub<P, R, C> deprecated(String reason)
  FieldStub<P, R, C> withDirectives(List<AppliedDirective> directives)
  FieldDef<P, C> pure(R Function(P parent) read)
  FieldDef<P, C> resolve(…)
  FieldDef<P, C> declareOnly()

// builder/fields_builder.dart
final class FieldsBuilder<P, C>()

// builder/object_options.dart
final class ObjectOptions

// builder/object_type_def.dart
final class ObjectTypeDef<P>
  ObjectTypeDef(…)
  bool accepts(Object? value)
  NamedTypeDef get namedType
  OutputRef<P?> get nullable

// execution/field_info.dart
final class FieldInfo
  FieldInfo(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/fields_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/field_lane.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class User {
  const User(this.name);
  final String name;
}

final class Admin extends User {
  const Admin(super.name);
}

final class AppContext {
  const AppContext(this.greeting);
  final String greeting;
}

void main() {
  FieldInfo infoOf(String field) => FieldInfo(
    fieldName: field,
    parentTypeName: 'User',
    path: [PathKey(field)],
  );

  final b = ExecutableSchemaBuilder<AppContext>();
  final times = Arg('times', b.int, defaultValue: 1);

  FieldDef<User, AppContext> fieldOf(
    FieldDef<User, AppContext> Function(FieldsBuilder<User, AppContext> t) make,
  ) => make(FieldsBuilder<User, AppContext>());

  group('fields', () {
    test('pure reads the parent through the pure lane', () {
      final field = fieldOf(
        (t) => t.field('name', b.string).pure((user) => user.name),
      );
      final lane = field.lane as PureLane;
      expect(lane.read(const User('Ada')), 'Ada');
    });

    test('pure casts the parent to P', () {
      final field = fieldOf(
        (t) => t.field('name', b.string).pure((user) => user.name),
      );
      final lane = field.lane as PureLane;
      expect(() => lane.read('not a user'), throwsA(isA<TypeError>()));
    });

    test('resolve passes the parent, arguments, context and info', () {
      final field = fieldOf(
        (t) => t
            .field('shout', b.string, args: [times])
            .resolve(
              (user, args, ctx, info) =>
                  '${ctx.greeting} ${user.name} ${args.get(times)} '
                  '${info.fieldName}',
            ),
      );
      final lane = field.lane as ResolverLane;
      final result = lane.resolve(
        const User('Ada'),
        Arguments(field.args, {'times': 2}),
        const AppContext('hi'),
        infoOf('shout'),
      );
      expect(result, 'hi Ada 2 shout');
    });

    test('resolveWith decodes the arguments class', () {
      final field = fieldOf(
        (t) => t
            .field('repeat', b.string)
            .resolveWith<int>(
              ArgumentsDef([times], (arguments) => arguments.get(times) * 10),
              (user, count, ctx, info) => '${user.name}$count',
            ),
      );
      final lane = field.lane as ResolverLane;
      final result = lane.resolve(
        const User('Ada'),
        Arguments(field.args, {'times': 3}),
        const AppContext('hi'),
        infoOf('repeat'),
      );
      expect(result, 'Ada30');
      expect(field.args, hasLength(1));
    });

    test('args together with resolveWith is an ArgumentError', () {
      expect(
        () => fieldOf(
          (t) => t
              .field('repeat', b.string, args: [times])
              .resolveWith<int>(
                ArgumentsDef([times], (arguments) => 1),
                (user, count, ctx, info) => '',
              ),
        ),
        throwsArgumentError,
      );
    });

    test('declareOnly has the declared-only lane', () {
      final field = fieldOf((t) => t.field('name', b.string).declareOnly());
      expect(field.lane, isA<DeclaredOnlyLane>());
    });

    test('modifiers keep the other settings', () {
      final directive = AppliedDirective('tag');
      final field = fieldOf(
        (t) => t
            .field('name', b.string, description: 'The name.')
            .deprecated('Use nick.')
            .withDirectives([directive])
            .pure((user) => user.name),
      );
      expect(field.description, 'The name.');
      expect(field.deprecationReason, 'Use nick.');
      expect(field.directives, [directive]);
    });
  });

  group('object types', () {
    test('accepts a value of the Dart type or a subtype', () {
      final user = b.object<User>('User', fields: (t) => []);
      expect(user.accepts(const Admin('Ada')), isTrue);
      expect(user.accepts('text'), isFalse);
    });

    test('isTypeOf replaces the Dart type test', () {
      final admin = b.object<User>(
        'Admin',
        fields: (t) => [],
        options: ObjectOptions(isTypeOf: (value) => value is Admin),
      );
      expect(admin.accepts(const User('Ada')), isFalse);
      expect(admin.accepts(const Admin('Ada')), isTrue);
    });

    test('fields run once, on first read', () {
      var calls = 0;
      final user = b.object<User>(
        'Counted',
        fields: (t) {
          calls++;
          return [t.field('name', b.string).pure((u) => u.name)];
        },
      );
      expect(calls, 0);
      expect(user.fields.map((field) => field.name), ['name']);
      expect(user.fields, hasLength(1));
      expect(calls, 1);
    });

    test('the builder records the object', () {
      final fresh = ExecutableSchemaBuilder<AppContext>();
      final user = fresh.object<User>('User', fields: (t) => []);
      expect(fresh.definitions, [user]);
    });

    test('typeRef prints as a non-null named type', () {
      final user = b.object<User>('User', fields: (t) => []);
      expect(const Printer().print(user.typeRef), 'User!');
      expect(const Printer().print(user.nullable.typeRef), 'User');
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/fields_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/builder/field_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'field_lane.dart';
import 'output_ref.dart';

/// A field of an object or interface type, with the way it is resolved.
///
/// `P` is the parent's Dart type and `C` the context type; both are checked
/// where the resolver is wrapped, so a definition carries no cast target.
///
/// {@category builder}
final class FieldDef<P, C> {
  /// Declares the field [name] of type [type].
  FieldDef({
    required this.name,
    required this.type,
    required List<Arg<Object?>> args,
    required List<AppliedDirective> directives,
    required this.lane,
    this.description,
    this.deprecationReason,
  }) : args = List.unmodifiable(args),
       directives = List.unmodifiable(directives);

  /// The field's name in the schema.
  final String name;

  /// The field's output type.
  final OutputRef<Object?> type;

  /// The declared arguments, in declaration order.
  final List<Arg<Object?>> args;

  /// The field's description, null when it has none.
  final String? description;

  /// Why the field is deprecated, null when it is not.
  final String? deprecationReason;

  /// The directives applied to the field, besides `@deprecated`.
  final List<AppliedDirective> directives;

  /// How the field produces its value.
  final FieldLane lane;
}
```

Create `packages/typed_graphql_server/lib/src/builder/field_lane.dart`:

```dart
import 'dart:async';

import '../execution/field_info.dart';
import 'arguments.dart';

/// How a field produces its value. The executor switches over the lane.
///
/// The functions take `Object?` for the parent and the context: the wrappers
/// made by `FieldStub` cast them where the types `P` and `C` are known.
sealed class FieldLane {
  const FieldLane();
}

/// A synchronous getter: no arguments, no middleware, no `FieldInfo` (R4.2).
final class PureLane extends FieldLane {
  /// Creates a lane that calls [read].
  const PureLane(this.read);

  /// Reads the value from the parent.
  final Object? Function(Object? parent) read;
}

/// A resolver that gets the arguments, the context and a `FieldInfo`.
final class ResolverLane extends FieldLane {
  /// Creates a lane that calls [resolve].
  const ResolverLane(this.resolve);

  /// Resolves the value, synchronously or not.
  final FutureOr<Object?> Function(
    Object? parent,
    Arguments arguments,
    Object? context,
    FieldInfo info,
  )
  resolve;
}

/// An interface field without a resolver: implementations declare it.
final class DeclaredOnlyLane extends FieldLane {
  /// Creates the lane.
  const DeclaredOnlyLane();
}
```

Create `packages/typed_graphql_server/lib/src/builder/field_stub.dart`:

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';

import '../execution/field_info.dart';
import 'arg.dart';
import 'arguments.dart';
import 'arguments_def.dart';
import 'field_def.dart';
import 'field_lane.dart';
import 'output_ref.dart';

/// A field whose type is fixed and whose resolver is still to come.
///
/// Fixing `R` here, before the resolver closure is inferred, is what makes a
/// closure that returns the wrong type a compile error (spec 3.2). A stub is
/// not a [FieldDef], so a field without a resolver does not compile.
///
/// {@category builder}
final class FieldStub<P, R, C> {
  /// Creates the stub of the field [name] of type [type].
  FieldStub(
    String name,
    OutputRef<R> type, {
    List<Arg<Object?>> args = const [],
    String? description,
  }) : this._(name, type, args, description, null, const []);

  FieldStub._(
    this.name,
    this.type,
    this._args,
    this.description,
    this._deprecationReason,
    this._directives,
  );

  /// The field's name.
  final String name;

  /// The field's type.
  final OutputRef<R> type;

  /// The field's description.
  final String? description;

  final List<Arg<Object?>> _args;
  final String? _deprecationReason;
  final List<AppliedDirective> _directives;

  /// The same field, deprecated for [reason].
  FieldStub<P, R, C> deprecated(String reason) =>
      FieldStub._(name, type, _args, description, reason, _directives);

  /// The same field with [directives] applied after the ones already given.
  FieldStub<P, R, C> withDirectives(List<AppliedDirective> directives) =>
      FieldStub._(name, type, _args, description, _deprecationReason, [
        ..._directives,
        ...directives,
      ]);

  /// Completes the field with a synchronous getter (the pure lane, R4.2).
  FieldDef<P, C> pure(R Function(P parent) read) =>
      _define(PureLane((parent) => read(parent as P)), _args);

  /// Completes the field with a resolver.
  FieldDef<P, C> resolve(
    FutureOr<R> Function(P parent, Arguments args, C context, FieldInfo info)
    resolve,
  ) => _define(
    ResolverLane(
      (parent, arguments, context, info) =>
          resolve(parent as P, arguments, context as C, info),
    ),
    _args,
  );

  /// Completes the field with a resolver that gets an arguments class built
  /// by [definition] (R4.3).
  ///
  /// The field's arguments are those of [definition]: giving `args` to the
  /// field as well is an [ArgumentError].
  FieldDef<P, C> resolveWith<A>(
    ArgumentsDef<A> definition,
    FutureOr<R> Function(P parent, A args, C context, FieldInfo info) resolve,
  ) {
    if (_args.isNotEmpty) {
      throw ArgumentError(
        'Field "$name" gives args and resolveWith; resolveWith declares the '
        'arguments through its ArgumentsDef.',
      );
    }
    return _define(
      ResolverLane(
        (parent, arguments, context, info) => resolve(
          parent as P,
          definition.decode(arguments),
          context as C,
          info,
        ),
      ),
      definition.args,
    );
  }

  /// Completes an interface field that has no resolver: every implementing
  /// object declares it.
  FieldDef<P, C> declareOnly() => _define(const DeclaredOnlyLane(), _args);

  FieldDef<P, C> _define(FieldLane lane, List<Arg<Object?>> args) => FieldDef(
    name: name,
    type: type,
    args: args,
    description: description,
    deprecationReason: _deprecationReason,
    directives: _directives,
    lane: lane,
  );
}
```

Create `packages/typed_graphql_server/lib/src/builder/fields_builder.dart`:

```dart
import 'arg.dart';
import 'field_stub.dart';
import 'output_ref.dart';

/// The `t` of an object type's `fields` thunk: starts the field declarations.
///
/// {@category builder}
final class FieldsBuilder<P, C>() {
  /// Creates a builder; `ExecutableSchemaBuilder.object` does.
  this;

  /// Starts the field [name] of type [type]; finish it with `pure`,
  /// `resolve`, `resolveWith` or `declareOnly`.
  ///
  /// Two steps, so `R` is fixed by [type] before a resolver closure is
  /// inferred (spec 3.2).
  FieldStub<P, R, C> field<R>(
    String name,
    OutputRef<R> type, {
    List<Arg<Object?>> args = const [],
    String? description,
  }) => FieldStub(name, type, args: args, description: description);
}
```

Create `packages/typed_graphql_server/lib/src/builder/object_options.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The rarer settings of an object type.
///
/// {@category builder}
final class ObjectOptions {
  /// Creates the options.
  const ObjectOptions({this.isTypeOf, this.directives = const []});

  /// Tells whether a value belongs to the type, when `value is P` is not
  /// enough (for example two types over one Dart class).
  final bool Function(Object? value)? isTypeOf;

  /// The directives applied to the type.
  final List<AppliedDirective> directives;
}
```

Create `packages/typed_graphql_server/lib/src/builder/object_type_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'field_def.dart';
import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'object_options.dart';
import 'output_ref.dart';

/// An object type whose values are the Dart class [P] (R4.1).
///
/// It is its own output reference. The context type is known only to the
/// builder that made it, which closes over it in the fields thunk.
///
/// {@category builder}
final class ObjectTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
  /// Declares the object type [name].
  ///
  /// [fieldsThunk] runs on first use, so types may refer to each other.
  ObjectTypeDef(
    super.name,
    List<FieldDef<P, Object?>> Function() fieldsThunk, {
    super.description,
    this.options = const ObjectOptions(),
  }) : _fieldsThunk = fieldsThunk,
       typeRef = NonNullType(NamedType(Name(name)));

  final List<FieldDef<P, Object?>> Function() _fieldsThunk;

  /// The type's own fields, in declaration order.
  // Set on first read, so types that refer to each other can be made before
  // either one's fields are built.
  late final List<FieldDef<P, Object?>> fields = List.unmodifiable(
    _fieldsThunk(),
  );

  /// The rarer settings.
  final ObjectOptions options;

  /// Whether [value] belongs to this type: [ObjectOptions.isTypeOf] when
  /// given, else `value is P`.
  bool accepts(Object? value) => options.isTypeOf?.call(value) ?? value is P;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
```

Create `packages/typed_graphql_server/lib/src/execution/field_info.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// What a resolver knows about the call it answers.
///
/// {@category execution}
final class FieldInfo {
  /// Describes the call of [fieldName] on [parentTypeName] at [path].
  FieldInfo({
    required this.fieldName,
    required this.parentTypeName,
    required List<PathSegment> path,
  }) : path = List.unmodifiable(path);

  /// The field's name in the schema.
  final String fieldName;

  /// The name of the object type the field is selected on.
  final String parentTypeName;

  /// The response path of the field, from the root.
  final List<PathSegment> path;
}
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,10 +6,14 @@ import 'built_in_scalar_definitions.dart';
 import 'definition_registry.dart';
 import 'enum_type_def.dart';
 import 'enum_value_mapping.dart';
+import 'field_def.dart';
+import 'fields_builder.dart';
 import 'input_list_ref.dart';
 import 'input_object_def.dart';
 import 'input_ref.dart';
 import 'named_type_def.dart';
+import 'object_options.dart';
+import 'object_type_def.dart';
 import 'output_list_ref.dart';
 import 'output_ref.dart';
 import 'scalar_type_def.dart';
@@ -65,6 +69,24 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
     );
   }
 
+  /// Declares the object type [name] whose values are [P].
+  ///
+  /// [fields] runs once, on first use (by the build), so types may refer to
+  /// each other through `late final` variables or class fields.
+  ObjectTypeDef<P> object<P>(
+    String name, {
+    required List<FieldDef<P, C>> Function(FieldsBuilder<P, C> t) fields,
+    String? description,
+    ObjectOptions options = const ObjectOptions(),
+  }) => _registry.add(
+    ObjectTypeDef(
+      name,
+      () => fields(FieldsBuilder<P, C>()),
+      description: description,
+      options: options,
+    ),
+  );
+
   /// The non-null list of [item] as an output type.
   OutputRef<Iterable<R>> list<R>(OutputRef<R> item) => OutputListRef(item);
 
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,10 +13,16 @@ export 'src/builder/enum_type_def.dart';
 export 'src/builder/enum_value_def.dart';
 export 'src/builder/enum_value_mapping.dart';
 export 'src/builder/executable_schema_builder.dart';
+export 'src/builder/field_def.dart';
+export 'src/builder/field_stub.dart';
+export 'src/builder/fields_builder.dart';
 export 'src/builder/input_object_def.dart';
 export 'src/builder/input_ref.dart';
 export 'src/builder/leaf_ref.dart';
 export 'src/builder/named_type_def.dart';
+export 'src/builder/object_options.dart';
+export 'src/builder/object_type_def.dart';
 export 'src/builder/optional.dart';
 export 'src/builder/output_ref.dart';
 export 'src/builder/scalar_type_def.dart';
+export 'src/execution/field_info.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/fields_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart packages/typed_graphql_server/lib/src/builder/field_def.dart packages/typed_graphql_server/lib/src/builder/field_lane.dart packages/typed_graphql_server/lib/src/builder/field_stub.dart packages/typed_graphql_server/lib/src/builder/fields_builder.dart packages/typed_graphql_server/lib/src/builder/object_options.dart packages/typed_graphql_server/lib/src/builder/object_type_def.dart packages/typed_graphql_server/lib/src/execution/field_info.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/fields_test.dart
git commit -q -m "feat(typed_graphql_server): add object types and typed fields" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Interfaces and unions

Add `InterfaceTypeDef<P>` and `UnionTypeDef<P>` with `resolveType`, read through `hasResolveType` / `untypedResolveType`, and `FieldInheritance`, which collects fields from implemented interfaces (and their interfaces) with an explicit stack.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/builder/field_inheritance.dart`, `packages/typed_graphql_server/lib/src/builder/interface_type_def.dart`, `packages/typed_graphql_server/lib/src/builder/union_type_def.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, `packages/typed_graphql_server/lib/src/builder/object_type_def.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`
- Test: `packages/typed_graphql_server/test/builder/interfaces_and_unions_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// builder/field_inheritance.dart
final class FieldInheritance()
  List<FieldDef<Object?, Object?>> collect(…)

// builder/interface_type_def.dart
final class InterfaceTypeDef<P>
  InterfaceTypeDef(…)
  NamedTypeDef get namedType
  OutputRef<P?> get nullable

// builder/union_type_def.dart
final class UnionTypeDef<P>
  UnionTypeDef(…)
  NamedTypeDef get namedType
  OutputRef<P?> get nullable
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/interfaces_and_unions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql_server/src/builder/field_inheritance.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Pet {
  const Pet();
}

final class Cat extends Pet {
  const Cat();
}

final class Dog extends Pet {
  const Dog();
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();

  FieldDef<Object?, Object?> pure(
    FieldsBuilder<Object?, Object?> t,
    String name,
  ) => t.field(name, b.string).pure((parent) => name);

  group('interfaces', () {
    final named = b.interface<Pet>(
      'Named',
      fields: (t) => [t.field('name', b.string).declareOnly()],
    );

    test('isSupertypeOf accepts subtypes and rejects others', () {
      expect(named.isSupertypeOf<Cat>(), isTrue);
      expect(named.isSupertypeOf<Pet>(), isTrue);
      expect(named.isSupertypeOf<String>(), isFalse);
    });

    test('an object keeps the interfaces it lists', () {
      final cat = b.object<Cat>(
        'Cat',
        fields: (t) => [t.field('name', b.string).pure((_) => 'c')],
        interfaces: [named],
      );
      expect(cat.interfaces, [named]);
    });
  });

  group('unions', () {
    test('members of subtypes compile and are kept in order', () {
      final cat = b.object<Cat>('Cat', fields: (t) => []);
      final dog = b.object<Dog>('Dog', fields: (t) => []);
      final union = b.union<Pet>('PetUnion', members: [cat, dog]);
      expect(union.members, [cat, dog]);
      expect(cat.accepts(const Cat()), isTrue);
      expect(cat.accepts(const Dog()), isFalse);
    });
  });

  group('inheritance', () {
    final node = b.interface<Object?>(
      'Node',
      fields: (t) => [pure(t, 'id'), pure(t, 'extra')],
    );
    final entity = b.interface<Object?>(
      'Entity',
      fields: (t) => [pure(t, 'created')],
      interfaces: [node],
    );
    final ownFields = b
        .object<Object?>('Own', fields: (t) => [pure(t, 'extra')])
        .fields;

    test('adds interface fields after the own, transitively, in order', () {
      final result = FieldInheritance().collect(ownFields, [entity]);
      expect([for (final f in result) f.name], ['extra', 'created', 'id']);
    });

    test('an own field overrides the interface field of the same name', () {
      final result = FieldInheritance().collect(ownFields, [node]);
      expect(result.first, same(ownFields.first));
      expect(result.where((f) => f.name == 'extra'), hasLength(1));
    });

    test('a declareOnly field is not inherited', () {
      final declared = b.interface<Object?>(
        'Declared',
        fields: (t) => [t.field('x', b.string).declareOnly()],
      );
      expect(FieldInheritance().collect([], [declared]), isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/interfaces_and_unions_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/builder/field_inheritance.dart`:

```dart
import 'field_def.dart';
import 'field_lane.dart';
import 'interface_type_def.dart';

/// Collects the fields an object or interface type has: its own, then those
/// it inherits from its interfaces (spec 3.7).
final class FieldInheritance() {
  /// Creates the collaborator.
  this;

  /// The fields of a type with [own] fields that lists [interfaces].
  ///
  /// An interface field the type does not declare by name is added after the
  /// own fields, interfaces in listed order, each followed by the interfaces
  /// it lists. A declare-only field is not inherited: the core validator
  /// reports the missing implementation. Walks with its own stack, so an
  /// interface cycle ends (the core validator reports it).
  List<FieldDef<Object?, Object?>> collect(
    List<FieldDef<Object?, Object?>> own,
    List<InterfaceTypeDef<Object?>> interfaces,
  ) {
    final result = <FieldDef<Object?, Object?>>[...own];
    final names = {for (final field in own) field.name};
    final visited = Set<InterfaceTypeDef<Object?>>.identity();
    final pending = interfaces.reversed.toList();
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (!visited.add(next)) continue;
      for (final field in next.fields) {
        if (field.lane is DeclaredOnlyLane) continue;
        if (names.add(field.name)) result.add(field);
      }
      pending.addAll(next.interfaces.reversed);
    }
    return List.unmodifiable(result);
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/interface_type_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'field_def.dart';
import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'object_type_def.dart';
import 'output_ref.dart';

/// An interface type whose implementing values are subtypes of [P] (R4.5).
///
/// {@category builder}
final class InterfaceTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
  /// Declares the interface [name].
  ///
  /// [fieldsThunk] runs on first use, so types may refer to each other.
  InterfaceTypeDef(
    super.name,
    List<FieldDef<P, Object?>> Function() fieldsThunk, {
    List<InterfaceTypeDef<Object?>> interfaces = const [],
    super.description,
    this.resolveType,
  }) : _fieldsThunk = fieldsThunk,
       interfaces = List.unmodifiable(interfaces),
       typeRef = NonNullType(NamedType(Name(name)));

  final List<FieldDef<P, Object?>> Function() _fieldsThunk;

  /// The interface's own fields, in declaration order.
  // Set on first read, so types that refer to each other can be made before
  // either one's fields are built.
  late final List<FieldDef<P, Object?>> fields = List.unmodifiable(
    _fieldsThunk(),
  );

  /// The interfaces this one implements, as listed (not transitive).
  final List<InterfaceTypeDef<Object?>> interfaces;

  /// Picks the object type of a value, null for the default (the first
  /// possible type that accepts it).
  final ObjectTypeDef<Object?> Function(P value)? resolveType;

  /// Whether a value of Dart type [X] is a value of this interface.
  ///
  /// Dart has no contravariant type parameter, so `GQL300` is checked at
  /// build with this test.
  bool isSupertypeOf<X>() => <X>[] is List<P>;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
```

Create `packages/typed_graphql_server/lib/src/builder/union_type_def.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'named_type_def.dart';
import 'nullable_output_ref.dart';
import 'object_type_def.dart';
import 'output_ref.dart';

/// A union type whose members are object types over subtypes of [P] (R4.5).
///
/// {@category builder}
final class UnionTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
  /// Declares the union [name] of [members].
  UnionTypeDef(
    super.name,
    List<ObjectTypeDef<P>> members, {
    super.description,
    this.resolveType,
  }) : members = List.unmodifiable(members),
       typeRef = NonNullType(NamedType(Name(name)));

  /// The member object types, in declaration order.
  final List<ObjectTypeDef<P>> members;

  /// Picks the object type of a value, null for the default (the first
  /// member that accepts it).
  final ObjectTypeDef<Object?> Function(P value)? resolveType;

  @override
  final TypeRef typeRef;

  @override
  NamedTypeDef get namedType => this;

  @override
  OutputRef<P?> get nullable => NullableOutputRef(this);
}
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,12 +11,14 @@ import 'fields_builder.dart';
 import 'input_list_ref.dart';
 import 'input_object_def.dart';
 import 'input_ref.dart';
+import 'interface_type_def.dart';
 import 'named_type_def.dart';
 import 'object_options.dart';
 import 'object_type_def.dart';
 import 'output_list_ref.dart';
 import 'output_ref.dart';
 import 'scalar_type_def.dart';
+import 'union_type_def.dart';
 
 /// Declares the types of a schema in typed Dart code; `C` is the context
 /// type every resolver receives (R4.1).
@@ -76,6 +78,7 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
   ObjectTypeDef<P> object<P>(
     String name, {
     required List<FieldDef<P, C>> Function(FieldsBuilder<P, C> t) fields,
+    List<InterfaceTypeDef<Object?>> interfaces = const [],
     String? description,
     ObjectOptions options = const ObjectOptions(),
   }) => _registry.add(
@@ -83,10 +86,50 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
       name,
       () => fields(FieldsBuilder<P, C>()),
       description: description,
+      interfaces: interfaces,
       options: options,
     ),
   );
 
+  /// Declares the interface [name] whose values are [P].
+  ///
+  /// An object type that lists it inherits the fields it does not declare.
+  /// [resolveType] picks the object type of a value; without it the first
+  /// possible type that accepts the value is used.
+  InterfaceTypeDef<P> interface<P>(
+    String name, {
+    required List<FieldDef<P, C>> Function(FieldsBuilder<P, C> t) fields,
+    List<InterfaceTypeDef<Object?>> interfaces = const [],
+    String? description,
+    ObjectTypeDef<Object?> Function(P value)? resolveType,
+  }) => _registry.add(
+    InterfaceTypeDef(
+      name,
+      () => fields(FieldsBuilder<P, C>()),
+      interfaces: interfaces,
+      description: description,
+      resolveType: resolveType,
+    ),
+  );
+
+  /// Declares the union [name] of the object types [members].
+  ///
+  /// Covariance checks the members at compile time: an `ObjectTypeDef<Cat>`
+  /// is an `ObjectTypeDef<Pet>`.
+  UnionTypeDef<P> union<P>(
+    String name, {
+    required List<ObjectTypeDef<P>> members,
+    ObjectTypeDef<Object?> Function(P value)? resolveType,
+    String? description,
+  }) => _registry.add(
+    UnionTypeDef(
+      name,
+      members,
+      resolveType: resolveType,
+      description: description,
+    ),
+  );
+
   /// The non-null list of [item] as an output type.
   OutputRef<Iterable<R>> list<R>(OutputRef<R> item) => OutputListRef(item);
 
```

In `packages/typed_graphql_server/lib/src/builder/object_type_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'field_def.dart';
+import 'interface_type_def.dart';
 import 'named_type_def.dart';
 import 'nullable_output_ref.dart';
 import 'object_options.dart';
@@ -20,8 +21,10 @@ final class ObjectTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
     super.name,
     List<FieldDef<P, Object?>> Function() fieldsThunk, {
     super.description,
+    List<InterfaceTypeDef<Object?>> interfaces = const [],
     this.options = const ObjectOptions(),
   }) : _fieldsThunk = fieldsThunk,
+       interfaces = List.unmodifiable(interfaces),
        typeRef = NonNullType(NamedType(Name(name)));
 
   final List<FieldDef<P, Object?>> Function() _fieldsThunk;
@@ -33,6 +36,9 @@ final class ObjectTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
     _fieldsThunk(),
   );
 
+  /// The interfaces the type implements, as listed (not transitive).
+  final List<InterfaceTypeDef<Object?>> interfaces;
+
   /// The rarer settings.
   final ObjectOptions options;
 
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -18,6 +18,7 @@ export 'src/builder/field_stub.dart';
 export 'src/builder/fields_builder.dart';
 export 'src/builder/input_object_def.dart';
 export 'src/builder/input_ref.dart';
+export 'src/builder/interface_type_def.dart';
 export 'src/builder/leaf_ref.dart';
 export 'src/builder/named_type_def.dart';
 export 'src/builder/object_options.dart';
@@ -25,4 +26,5 @@ export 'src/builder/object_type_def.dart';
 export 'src/builder/optional.dart';
 export 'src/builder/output_ref.dart';
 export 'src/builder/scalar_type_def.dart';
+export 'src/builder/union_type_def.dart';
 export 'src/execution/field_info.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/interfaces_and_unions_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart packages/typed_graphql_server/lib/src/builder/field_inheritance.dart packages/typed_graphql_server/lib/src/builder/interface_type_def.dart packages/typed_graphql_server/lib/src/builder/object_type_def.dart packages/typed_graphql_server/lib/src/builder/union_type_def.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/interfaces_and_unions_test.dart
git commit -q -m "feat(typed_graphql_server): add interfaces and unions" \
  -m "InterfaceTypeDef, UnionTypeDef, interface and union on the builder, interfaces on objects, FieldInheritance." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: `build`, `ExecutableSchema` and `SchemaBuildError`

Assemble the core `Schema` from the definitions (`ExecutableSchemaAssembly` and its type, field, input-value and literal collaborators), run `BuilderChecks` (`GQL300`-`GQL302`) and the core `SchemaValidator`, and bind every field, abstract type, leaf and input object by name in `SchemaBindings` for the executor. `build` takes the roots and `BuildOptions` and returns `ExecutableSchema<C>` or throws `SchemaBuildError`.

**Files:**
- Create: `packages/typed_graphql_server/lib/src/builder/build_options.dart`, `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`, `packages/typed_graphql_server/lib/src/builder/directive_nodes.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`, `packages/typed_graphql_server/lib/src/builder/field_assembler.dart`, `packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart`, `packages/typed_graphql_server/lib/src/builder/literal_writer.dart`, `packages/typed_graphql_server/lib/src/builder/possible_types.dart`, `packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart`, `packages/typed_graphql_server/lib/src/builder/schema_build_error.dart`, `packages/typed_graphql_server/lib/src/builder/type_assembler.dart`, `packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart`, `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart`
- Modify: `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart`, `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, `packages/typed_graphql_server/lib/src/builder/interface_type_def.dart`, `packages/typed_graphql_server/lib/src/builder/object_type_def.dart`, `packages/typed_graphql_server/lib/src/builder/union_type_def.dart`, `packages/typed_graphql_server/lib/typed_graphql_server.dart`, `packages/typed_graphql_server/CHANGELOG.md`
- Test: `packages/typed_graphql_server/test/builder/build_errors_test.dart`, `packages/typed_graphql_server/test/builder/build_test.dart`, `packages/typed_graphql_server/test/builder/literal_writer_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// builder/build_options.dart
final class BuildOptions

// builder/builder_checks.dart
final class BuilderChecks
  BuilderChecks(this.problems)
  void check(List<NamedTypeDef> definitions, PossibleTypes possibleTypes)

// builder/directive_nodes.dart
final class const DirectiveNodes()
  AppliedDirective deprecated(String reason)
  AppliedDirective specifiedBy(String url)
  AppliedDirective oneOf()
  List<AppliedDirective> withDeprecation(…)

// builder/executable_schema_assembly.dart
final class ExecutableSchemaAssembly<C>
  ExecutableSchemaAssembly(…)
  ExecutableSchema<C> assemble()

// builder/field_assembler.dart
final class FieldAssembler
  FieldAssembler(this._inputs)
  SchemaField assemble(FieldDef<Object?, Object?> field, String typeName)

// builder/input_value_assembler.dart
final class InputValueAssembler
  InputValueAssembler(this._literals, this.problems)
  InputValue assemble(Arg<Object?> arg, String coordinate)

// builder/literal_writer.dart
final class LiteralWriter
  LiteralWriter(Iterable<NamedTypeDef> definitions)
  Value write(JsonValue json, TypeRef? type)

// builder/possible_types.dart
final class PossibleTypes
  PossibleTypes(Iterable<NamedTypeDef> definitions)
  List<ObjectTypeDef<Object?>> of(NamedTypeDef abstractType)

// builder/schema_bindings_assembler.dart
final class SchemaBindingsAssembler
  SchemaBindingsAssembler()
  SchemaBindings assemble(…)

// builder/schema_build_error.dart
final class SchemaBuildError
  SchemaBuildError(List<Diagnostic> diagnostics)
  String toString()

// builder/type_assembler.dart
final class TypeAssembler
  TypeAssembler(this._inputs) : _fields = FieldAssembler(_inputs)
  SchemaType assemble(NamedTypeDef definition)

// execution/abstract_type_binding.dart
final class AbstractTypeBinding
  AbstractTypeBinding(…)

// execution/executable_schema.dart
final class ExecutableSchema<C>
  ExecutableSchema(this.schema, this.bindings)

// execution/schema_bindings.dart
final class SchemaBindings
  SchemaBindings(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/build_errors_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

base class Pet {
  const Pet();
}

final class Cat extends Pet {
  const Cat();
}

final class Plain {}

final class Named {}

final class Box {
  const Box();
}

void main() {
  late ExecutableSchemaBuilder<Object?> b;

  setUp(() => b = ExecutableSchemaBuilder<Object?>());

  ObjectTypeDef<Object?> queryWith(
    List<FieldDef<Object?, Object?>> Function(
      FieldsBuilder<Object?, Object?> t,
    )
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  ObjectTypeDef<Object?> anyQuery() => queryWith(
    (t) => [t.field('ok', b.boolean).pure((_) => true)],
  );

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

  List<DiagnosticCode> codesOf(void Function() build) => [
    for (final problem in problemsOf(build)) problem.code,
  ];

  group('GQL300', () {
    test('an object whose Dart type is not a subtype of the interface', () {
      final named = b.interface<Named>(
        'Node',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Plain>(
        'Thing',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.map((problem) => problem.message), [
        'Type "Thing" (Dart type Plain) cannot implement interface "Node": '
            'Plain is not a subtype of Named.',
      ]);
      expect(problems.single.code, DiagnosticCode.incompatibleImplementation);
    });

    test('an interface that lists an interface of an unrelated type', () {
      final named = b.interface<Named>(
        'Node',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.interface<Plain>(
        'Other',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      expect(
        codesOf(() => b.build(query: query)),
        contains(DiagnosticCode.incompatibleImplementation),
      );
    });

    test('a subtype of the interface type is accepted', () {
      final pet = b.interface<Pet>(
        'Pet',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Cat>(
        'Kitty',
        interfaces: [pet],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      expect(() => b.build(query: query), returnsNormally);
    });
  });

  group('GQL301', () {
    ObjectTypeDef<Pet> pet({bool hasTypeTest = false}) => b.object<Pet>(
      'Animal',
      options: ObjectOptions(isTypeOf: hasTypeTest ? (v) => v is Pet : null),
      fields: (t) => [t.field('id', b.id).pure((_) => '1')],
    );

    ObjectTypeDef<Cat> cat({bool hasTypeTest = false}) => b.object<Cat>(
      'Kitty',
      options: ObjectOptions(isTypeOf: hasTypeTest ? (v) => v is Cat : null),
      fields: (t) => [t.field('id', b.id).pure((_) => '1')],
    );

    test('members whose Dart types overlap, without a resolveType', () {
      final members = [pet(), cat()];
      b.union<Pet>('Either', members: members);
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.code, DiagnosticCode.ambiguousTypeResolution);
      expect(
        problems.single.message,
        'The possible types "Animal" (Dart type Pet) and "Kitty" (Dart type '
        'Cat) of "Either" have overlapping Dart types, so a value cannot be '
        'matched to one of them: give "Either" a resolveType, or give both '
        'types an isTypeOf.',
      );
    });

    test('an interface counts its implementations', () {
      final named = b.interface<Pet>(
        'Named',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      for (final name in ['A', 'B']) {
        b.object<Pet>(
          name,
          interfaces: [named],
          fields: (t) => [t.field('id', b.id).pure((_) => '1')],
        );
      }
      b.object<Cat>(
        'C',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final query = anyQuery();
      expect(
        codesOf(() => b.build(query: query)),
        [DiagnosticCode.ambiguousTypeResolution],
      );
    });

    test('a resolveType settles it', () {
      final members = [pet(), cat()];
      b.union<Pet>('Either', members: members, resolveType: (_) => members[0]);
      final query = anyQuery();
      final binding = b.build(query: query).bindings.abstractTypes['Either']!;
      expect(binding.resolveType!(const Cat()), same(members[0]));
    });

    test('an isTypeOf on both types settles it', () {
      final members = [pet(hasTypeTest: true), cat(hasTypeTest: true)];
      b.union<Pet>('Either', members: members);
      final query = anyQuery();
      expect(() => b.build(query: query), returnsNormally);
    });

    test('an isTypeOf on one type does not', () {
      final members = [pet(hasTypeTest: true), cat()];
      b.union<Pet>('Either', members: members);
      final query = anyQuery();
      expect(
        codesOf(() => b.build(query: query)),
        [DiagnosticCode.ambiguousTypeResolution],
      );
    });
  });

  group('GQL302', () {
    test('an input object default without encode names the coordinate', () {
      final box = b.inputObject<Box>(
        'BoxInput',
        fields: () => [Arg('size', b.int, defaultValue: 1)],
        decode: (_) => const Box(),
      );
      final query = queryWith(
        (t) => [
          t
              .field(
                'open',
                b.boolean,
                args: [Arg('box', box, defaultValue: const Box())],
              )
              .pure((_) => true),
        ],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.code, DiagnosticCode.unencodableDefaultValue);
      expect(
        problems.single.message,
        'The default value of "Query.open(box:)" cannot be written as a '
        'literal: Input object "BoxInput" has no encode function, so a '
        'default value of this type cannot be written.',
      );
    });

    test('a default the codec rejects, on an input field', () {
      final box = b.inputObject<Box>(
        'BoxInput',
        fields: () => [Arg('size', b.int, defaultValue: 4294967296)],
        decode: (_) => const Box(),
      );
      final query = queryWith(
        (t) => [
          t.field('open', b.boolean, args: [Arg('box', box)]).pure((_) => true),
        ],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.code, DiagnosticCode.unencodableDefaultValue);
      expect(problems.single.message, contains('"BoxInput.size"'));
    });
  });

  group('core validation', () {
    test('two types with one name come back in the error', () {
      b.object<Object?>(
        'User',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Object?>(
        'User',
        fields: (t) => [t.field('name', b.string).pure((_) => 'a')],
      );
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.message, contains('"User"'));
      expect(problems.single.code.id, startsWith('GQL1'));
    });

    test('a union without members is reported', () {
      b.union<Object?>('Empty', members: const []);
      final query = anyQuery();
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.single.message, contains('Empty'));
    });

    test('builder problems come before the validator problems', () {
      final named = b.interface<Named>(
        'Node',
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.object<Plain>(
        'Thing',
        interfaces: [named],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      b.union<Object?>('Empty', members: const []);
      final query = anyQuery();
      final codes = codesOf(() => b.build(query: query));
      expect(codes.first, DiagnosticCode.incompatibleImplementation);
      expect(codes, hasLength(2));
    });
  });

  group('SchemaBuildError', () {
    test('lists one diagnostic per line', () {
      final error = SchemaBuildError([
        Diagnostic(DiagnosticCode.incompatibleImplementation, .error, 'one'),
        Diagnostic(DiagnosticCode.ambiguousTypeResolution, .error, 'two'),
      ]);
      expect(
        error.toString(),
        'SchemaBuildError:\nGQL300: one\nGQL301: two',
      );
    });

    test('keeps its diagnostics unmodifiable', () {
      final error = SchemaBuildError([]);
      expect(
        () => error.diagnostics.add(
          Diagnostic(DiagnosticCode.diagnosticLimitReached, .error, 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
```

Create `packages/typed_graphql_server/test/builder/build_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Role { admin, member }

final class UrlCodec implements ScalarCodec<Uri> {
  const UrlCodec();

  @override
  DecodeResult<Uri> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(Uri.parse(value)),
    _ => const DecodeFailure('Url must be a string'),
  };

  @override
  JsonValue encode(Uri value) => JsonString('$value');
}

base class Entity {
  const Entity(this.id);
  final String id;
}

final class Account extends Entity {
  const Account(super.id, this.name);
  final String name;
}

final class Team extends Entity {
  const Team(super.id);
}

final class Filter {
  const Filter(this.role, this.tags);
  final Role role;
  final List<String> tags;
}

final class Lookup {
  const Lookup();
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();

  final url = b.scalar<Uri>(
    'Url',
    const UrlCodec(),
    description: 'A web address.',
    specifiedByUrl: 'https://url.spec.whatwg.org/',
  );
  final role = b.enumType<Role>(
    'Role',
    Role.values,
    description: 'What an account may do.',
    mapping: EnumValueMapping<Role>(
      nameOf: (value) => value.name.toUpperCase(),
      descriptionOf: (value) => value == Role.admin ? 'Can do all.' : null,
      deprecationReasonOf: (value) =>
          value == Role.member ? 'Use ADMIN.' : null,
    ),
  );
  final roleField = Arg('role', role, defaultValue: Role.member);
  final tagsField = Arg(
    'tags',
    b.inputList(b.string),
    defaultValue: ['a', 'b'],
  );
  final filter = b.inputObject<Filter>(
    'Filter',
    description: 'Narrows a list.',
    fields: () => [roleField, tagsField],
    decode: (values) => Filter(values.get(roleField), values.get(tagsField)),
    encode: (value) => JsonObject({
      'role': JsonString(value.role.name.toUpperCase()),
      'tags': JsonArray([for (final tag in value.tags) JsonString(tag)]),
    }),
  );
  final lookupId = Arg('id', b.id.nullable);
  final lookupEmail = Arg('email', b.string.nullable);
  final lookup = b.oneOfInputObject<Lookup>(
    'Lookup',
    fields: () => [lookupId, lookupEmail],
    decode: (_) => const Lookup(),
  );
  final entity = b.interface<Entity>(
    'Entity',
    description: 'Something with an id.',
    fields: (t) => [
      t.field('id', b.id).pure((value) => value.id),
      t.field('label', b.string).declareOnly(),
    ],
  );
  final account = b.object<Account>(
    'Account',
    interfaces: [entity],
    fields: (t) => [
      t.field('name', b.string).pure((value) => value.name),
      t.field('label', b.string).pure((value) => value.name),
    ],
  );
  final team = b.object<Team>(
    'Team',
    interfaces: [entity],
    fields: (t) => [
      t.field('label', b.string).pure((value) => value.id),
      t.field('id', b.id, description: 'The team id.').pure((v) => v.id),
    ],
  );
  final searchResult = b.union<Entity>(
    'SearchResult',
    description: 'Anything a search finds.',
    members: [account, team],
  );
  final first = Arg(
    'first',
    b.int,
    defaultValue: 10,
    description: 'Page size.',
  );
  final minimumRole = Arg(
    'minimumRole',
    role.nullable,
    defaultValue: Role.admin,
  );
  final filterArg = Arg(
    'filter',
    filter,
    defaultValue: const Filter(Role.member, ['x']),
  );
  final legacyArg = Arg(
    'legacy',
    b.boolean.nullable,
    deprecationReason: 'Not used.',
  );
  final after = Arg.optional('after', b.string.nullable);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field(
            'accounts',
            b.list(account),
            args: [first, minimumRole, filterArg, legacyArg, after],
            description: 'All accounts.',
          )
          .resolve((parent, args, context, info) => const <Account>[]),
      t
          .field('legacy', b.string.nullable)
          .deprecated('Use accounts.')
          .pure((parent) => null),
      t
          .field('search', b.list(searchResult))
          .pure((_) => const <Entity>[Team('t')]),
      t.field('home', url).pure((_) => Uri.parse('https://example.com')),
      t
          .field('find', account.nullable, args: [Arg('by', lookup)])
          .resolve((parent, args, context, info) => null),
      t.field('node', entity).pure((_) => const Account('1', 'a')),
    ],
  );
  final mutation = b.object<Object?>(
    'Mutation',
    fields: (t) => [t.field('ping', b.boolean).pure((_) => true)],
  );

  group('build', () {
    test('prints the SDL of every kind of definition', () {
      final built = b.build(query: query, mutation: mutation);
      expect(const SchemaPrinter().print(built.schema.schema), '''
"""A web address."""
scalar Url @specifiedBy(url: "https://url.spec.whatwg.org/")

"""What an account may do."""
enum Role {
  """Can do all."""
  ADMIN
  MEMBER @deprecated(reason: "Use ADMIN.")
}

"""Narrows a list."""
input Filter {
  role: Role! = MEMBER
  tags: [String!]! = ["a", "b"]
}

input Lookup @oneOf {
  id: ID
  email: String
}

"""Something with an id."""
interface Entity {
  id: ID!
  label: String!
}

type Account implements Entity {
  name: String!
  label: String!
  id: ID!
}

type Team implements Entity {
  label: String!

  """The team id."""
  id: ID!
}

"""Anything a search finds."""
union SearchResult = Account | Team

type Query {
  """All accounts."""
  accounts(
    """Page size."""
    first: Int! = 10
    minimumRole: Role = ADMIN
    filter: Filter! = { role: MEMBER, tags: ["x"] }
    legacy: Boolean @deprecated(reason: "Not used.")
    after: String
  ): [Account!]!
  legacy: String @deprecated(reason: "Use accounts.")
  search: [SearchResult!]!
  home: Url!
  find(by: Lookup!): Account
  node: Entity!
}

type Mutation {
  ping: Boolean!
}''');
    });

    test('the schema carries the roots and the options', () {
      final built = b.build(
        query: query,
        subscription: mutation,
        options: const BuildOptions(
          description: 'The API.',
          includesDeferAndStream: true,
        ),
      );
      final schema = built.schema.schema;
      expect(schema.queryTypeName, 'Query');
      expect(schema.mutationTypeName, isNull);
      expect(schema.subscriptionTypeName, 'Mutation');
      expect(schema.description, 'The API.');
      expect(schema.includesDeferAndStream, isTrue);
    });

    test('declared directives are part of the schema', () {
      final built = b.build(
        query: query,
        options: BuildOptions(
          directives: [
            SchemaDirective(
              'audited',
              locations: const [DirectiveLocation.fieldDefinition],
            ),
          ],
        ),
      );
      expect(built.schema.schema.directiveNamed('audited'), isNotNull);
    });

    test('the built-in scalars are not declared types', () {
      final built = b.build(query: query);
      final names = [for (final type in built.schema.schema.types) type.name];
      expect(names, isNot(contains('Int')));
      expect(names, isNot(contains('String')));
    });

    test('a definition made after a build does not change that schema', () {
      final own = ExecutableSchemaBuilder<Object?>();
      final root = own.object<Object?>(
        'Query',
        fields: (t) => [t.field('a', own.int).pure((_) => 1)],
      );
      final first = own.build(query: root);
      own.object<Object?>(
        'Extra',
        fields: (t) => [t.field('b', own.int).pure((_) => 1)],
      );
      final second = own.build(query: root);
      expect(first.schema.schema.typeNamed('Extra'), isNull);
      expect(second.schema.schema.typeNamed('Extra'), isNotNull);
    });
  });

  group('bindings', () {
    final bindings = b.build(query: query, mutation: mutation).bindings;
    List<String> namesOf(String abstractName) => [
      for (final type in bindings.abstractTypes[abstractName]!.possibleTypes)
        type.name,
    ];

    test('keep the object types and their fields, inherited ones last', () {
      expect(bindings.objects.keys, ['Account', 'Team', 'Query', 'Mutation']);
      expect(bindings.fields['Account']!.keys, ['name', 'label', 'id']);
      expect(bindings.fields['Team']!.keys, ['label', 'id']);
    });

    test('inherit the interface field with its resolver', () {
      final inherited = bindings.fields['Account']!['id']!;
      expect(inherited, same(entity.fields.first));
    });

    test('list the possible types of abstract types in schema order', () {
      expect(bindings.abstractTypes.keys, ['Entity', 'SearchResult']);
      expect(namesOf('Entity'), ['Account', 'Team']);
      expect(namesOf('SearchResult'), ['Account', 'Team']);
    });

    test('keep the leaves and the input objects', () {
      expect(bindings.leaves.keys, ['Url', 'Role']);
      expect(bindings.inputObjects.keys, ['Filter', 'Lookup']);
    });
  });
}
```

Create `packages/typed_graphql_server/test/builder/literal_writer_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/literal_writer.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Color { red, green }

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final color = b.enumType<Color>('Color', Color.values);
  final x = Arg('x', b.int);
  b.inputObject<Object>(
    'Point',
    fields: () => [x, Arg('colors', b.inputList(color))],
    decode: (_) => const Object(),
  );
  final writer = LiteralWriter(b.definitions);

  String write(JsonValue json, String type) {
    final node = switch (const Parser().parseTypeRef(Source(type))) {
      ParseElementSuccess(:final value) => value,
      _ => throw StateError('bad type $type'),
    };
    return const Printer().print(writer.write(json, node));
  }

  group('LiteralWriter', () {
    test('writes an integral number as an Int, even for a Float', () {
      expect(write(JsonNumber(3), 'Float'), '3');
      expect(write(JsonNumber(3.0), 'Float'), '3');
    });

    test('writes a fraction as a Float', () {
      expect(write(JsonNumber(1.5), 'Float'), '1.5');
    });

    test('writes a number beyond the safe integers as a Float', () {
      expect(write(JsonNumber(1e21), 'Float'), '1e+21');
    });

    test('writes a string, a boolean and null', () {
      expect(write(const JsonString('a"b'), 'String'), r'"a\"b"');
      expect(write(const JsonBool(true), 'Boolean!'), 'true');
      expect(write(const JsonNull(), 'String'), 'null');
    });

    test('writes an enum name as an enum value', () {
      expect(write(const JsonString('red'), 'Color!'), 'red');
    });

    test('writes a string for an unknown type as a string', () {
      expect(write(const JsonString('red'), 'Other'), '"red"');
    });

    test('writes a list through the item type', () {
      final json = JsonArray([
        const JsonString('red'),
        const JsonString('green'),
      ]);
      expect(write(json, '[Color!]!'), '[red, green]');
    });

    test('writes a single value for a list type as the item', () {
      expect(write(const JsonString('red'), '[Color]'), 'red');
    });

    test('writes an input object field by the type of the field', () {
      final json = JsonObject({
        'x': JsonNumber(1),
        'colors': JsonArray([const JsonString('green')]),
      });
      expect(write(json, 'Point'), '{ x: 1, colors: [green] }');
    });

    test('writes a field the input object does not declare by its shape', () {
      final json = JsonObject({'extra': const JsonString('red')});
      expect(write(json, 'Point'), '{ extra: "red" }');
    });

    test('writes by shape without a type', () {
      final json = JsonObject({
        'a': JsonArray([JsonNumber(1), const JsonBool(false)]),
      });
      expect(
        const Printer().print(writer.write(json, null)),
        '{ a: [1, false] }',
      );
    });

    test('the first definition of a name wins', () {
      final other = ExecutableSchemaBuilder<Object?>();
      final first = other.enumType<Color>('Pick', Color.values);
      other.scalar<String>('Pick', const StringCodec());
      expect(
        const Printer().print(
          LiteralWriter(other.definitions).write(
            const JsonString('red'),
            const NamedType(Name('Pick')),
          ),
        ),
        'red',
      );
      expect(first.name, 'Pick');
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/build_errors_test.dart test/builder/build_test.dart test/builder/literal_writer_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql_server/lib/src/builder/build_options.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The settings of `ExecutableSchemaBuilder.build` besides the root types.
///
/// Grouped in one object to keep `build` within five parameters; later
/// stages add their settings here (plan cache size, middleware).
///
/// {@category builder}
final class BuildOptions {
  /// Creates the options.
  const BuildOptions({
    this.directives = const [],
    this.includesDeferAndStream = false,
    this.description,
  });

  /// The directive definitions the schema declares besides the specified
  /// ones.
  final List<SchemaDirective> directives;

  /// Whether the schema has the `@defer` and `@stream` definitions.
  final bool includesDeferAndStream;

  /// The schema's description, null when it has none.
  final String? description;
}
```

Create `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'possible_types.dart';
import 'union_type_def.dart';

/// The checks only the builder can make, because they are about Dart types:
/// `GQL300` (implementations) and `GQL301` (type resolution). The core
/// validator runs after them.
final class BuilderChecks {
  /// Creates the checks; they add problems to [problems].
  BuilderChecks(this.problems);

  /// The diagnostics found so far; the checks add to them.
  final List<Diagnostic> problems;

  /// Runs both checks over [definitions].
  void check(List<NamedTypeDef> definitions, PossibleTypes possibleTypes) {
    for (final definition in definitions) {
      switch (definition) {
        case ObjectTypeDef<Object?>():
          _checkInterfaces(
            definition.name,
            definition.dartTypeName,
            definition.interfaces,
            definition.isDartSubtypeOfInterface,
          );
        case InterfaceTypeDef<Object?>():
          _checkInterfaces(
            definition.name,
            definition.dartTypeName,
            definition.interfaces,
            definition.isDartSubtypeOf,
          );
        default:
      }
    }
    _checkTypeResolution(definitions, possibleTypes);
  }

  void _checkInterfaces(
    String name,
    String dartTypeName,
    List<InterfaceTypeDef<Object?>> interfaces,
    bool Function(InterfaceTypeDef<Object?> interface) isSubtype,
  ) {
    for (final interface in interfaces) {
      if (isSubtype(interface)) continue;
      problems.add(
        Diagnostic(
          .incompatibleImplementation,
          .error,
          'Type "$name" (Dart type $dartTypeName) cannot implement '
          'interface "${interface.name}": $dartTypeName is not a subtype of '
          '${interface.dartTypeName}.',
        ),
      );
    }
  }

  void _checkTypeResolution(
    List<NamedTypeDef> definitions,
    PossibleTypes possibleTypes,
  ) {
    for (final definition in definitions) {
      final hasResolveType = switch (definition) {
        InterfaceTypeDef<Object?>(:final hasResolveType) => hasResolveType,
        UnionTypeDef<Object?>(:final hasResolveType) => hasResolveType,
        _ => true,
      };
      if (hasResolveType) continue;
      _checkPairs(definition.name, possibleTypes.of(definition));
    }
  }

  // Reports the first ambiguous pair only: a pair per overlap would be
  // quadratic output for a large interface.
  void _checkPairs(String abstractName, List<ObjectTypeDef<Object?>> types) {
    for (var i = 0; i < types.length; i++) {
      for (var j = i + 1; j < types.length; j++) {
        if (!_isAmbiguous(types[i], types[j])) continue;
        problems.add(_ambiguity(abstractName, types[i], types[j]));
        return;
      }
    }
  }

  // Spec 3.7: the default decision is `value is P` in order, so it guesses
  // when one Dart type holds the other's values, unless both types decide
  // with an explicit isTypeOf.
  bool _isAmbiguous(ObjectTypeDef<Object?> a, ObjectTypeDef<Object?> b) {
    final hasBothTests =
        a.options.isTypeOf != null && b.options.isTypeOf != null;
    return !hasBothTests && (a.isDartSubtypeOf(b) || b.isDartSubtypeOf(a));
  }

  Diagnostic _ambiguity(
    String abstractName,
    ObjectTypeDef<Object?> a,
    ObjectTypeDef<Object?> b,
  ) => Diagnostic(
    .ambiguousTypeResolution,
    .error,
    'The possible types "${a.name}" (Dart type ${a.dartTypeName}) and '
    '"${b.name}" (Dart type ${b.dartTypeName}) of "$abstractName" have '
    'overlapping Dart types, so a value cannot be matched to one of them: '
    'give "$abstractName" a resolveType, or give both types an isTypeOf.',
  );
}
```

Create `packages/typed_graphql_server/lib/src/builder/directive_nodes.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The applied directives the builder writes for what a definition says:
/// deprecation, a scalar's specification URL and the one-of flag, in the
/// shape the core reads them back.
final class const DirectiveNodes() {
  /// Creates the factory.
  this;

  /// `@deprecated(reason: "...")`.
  AppliedDirective deprecated(String reason) =>
      AppliedDirective('deprecated', arguments: [_string('reason', reason)]);

  /// `@specifiedBy(url: "...")`.
  AppliedDirective specifiedBy(String url) =>
      AppliedDirective('specifiedBy', arguments: [_string('url', url)]);

  /// `@oneOf`.
  AppliedDirective oneOf() => AppliedDirective('oneOf');

  /// [directives] followed by `@deprecated` when [reason] is not null.
  List<AppliedDirective> withDeprecation(
    List<AppliedDirective> directives,
    String? reason,
  ) => [...directives, if (reason != null) deprecated(reason)];

  Argument _string(String name, String value) =>
      Argument(Name(name), StringValue(value));
}
```

Create `packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/executable_schema.dart';
import 'build_options.dart';
import 'builder_checks.dart';
import 'input_value_assembler.dart';
import 'literal_writer.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'possible_types.dart';
import 'schema_bindings_assembler.dart';
import 'schema_build_error.dart';
import 'type_assembler.dart';

/// One run of `ExecutableSchemaBuilder.build`: definitions to a core schema,
/// the builder's checks, the core validator, then the binding tables.
final class ExecutableSchemaAssembly<C> {
  /// Prepares a run over [definitions] with the given root types.
  ExecutableSchemaAssembly({
    required this.definitions,
    required this.query,
    required this.mutation,
    required this.subscription,
    required this.options,
  });

  /// The definitions, in creation order.
  final List<NamedTypeDef> definitions;

  /// The query root.
  final ObjectTypeDef<Object?> query;

  /// The mutation root, null when there is none.
  final ObjectTypeDef<Object?>? mutation;

  /// The subscription root, null when there is none.
  final ObjectTypeDef<Object?>? subscription;

  /// The other settings.
  final BuildOptions options;

  /// Assembles the schema; throws [SchemaBuildError] on any problem.
  ExecutableSchema<C> assemble() {
    final problems = <Diagnostic>[];
    final possibleTypes = PossibleTypes(definitions);
    BuilderChecks(problems).check(definitions, possibleTypes);
    final schema = _schemaOf(problems);
    final result = const SchemaValidator().validate(schema);
    if (result case InvalidSchema(:final diagnostics)) {
      problems.addAll(diagnostics);
    }
    if (problems.any((problem) => problem.isError)) {
      throw SchemaBuildError(problems);
    }
    return ExecutableSchema(
      ValidSchema.assumeValid(schema),
      SchemaBindingsAssembler().assemble(definitions, possibleTypes),
    );
  }

  Schema _schemaOf(List<Diagnostic> problems) {
    final assembler = TypeAssembler(
      InputValueAssembler(LiteralWriter(definitions), problems),
    );
    return Schema(
      types: [
        for (final definition in definitions) assembler.assemble(definition),
      ],
      directives: options.directives,
      queryTypeName: query.name,
      mutationTypeName: mutation?.name,
      subscriptionTypeName: subscription?.name,
      description: options.description,
      includesDeferAndStream: options.includesDeferAndStream,
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/field_assembler.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'directive_nodes.dart';
import 'field_def.dart';
import 'input_value_assembler.dart';

/// Turns a [FieldDef] into a core [SchemaField].
final class FieldAssembler {
  /// Creates the assembler; argument defaults go through [_inputs].
  FieldAssembler(this._inputs);

  final InputValueAssembler _inputs;

  /// The schema field for [field] of the type named [typeName].
  SchemaField assemble(FieldDef<Object?, Object?> field, String typeName) =>
      SchemaField(
        field.name,
        field.type.typeRef,
        description: field.description,
        arguments: [
          for (final arg in field.args)
            _inputs.assemble(arg, '$typeName.${field.name}(${arg.name}:)'),
        ],
        appliedDirectives: const DirectiveNodes().withDeprecation(
          field.directives,
          field.deprecationReason,
        ),
      );
}
```

Create `packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'arg.dart';
import 'directive_nodes.dart';
import 'literal_writer.dart';

/// Turns an [Arg] into a core [InputValue], with its default value written as
/// a literal; a default that cannot be written is a `GQL302` problem.
final class InputValueAssembler {
  /// Creates the assembler; it adds problems to [problems].
  InputValueAssembler(this._literals, this.problems);

  final LiteralWriter _literals;

  /// The diagnostics found so far; this assembler adds to them.
  final List<Diagnostic> problems;

  /// The input value for [arg]; [coordinate] names it in messages.
  InputValue assemble(Arg<Object?> arg, String coordinate) => InputValue(
    arg.name,
    arg.type.typeRef,
    description: arg.description,
    defaultValue: _defaultOf(arg, coordinate),
    appliedDirectives: const DirectiveNodes().withDeprecation(
      const [],
      arg.deprecationReason,
    ),
  );

  Value? _defaultOf(Arg<Object?> arg, String coordinate) {
    try {
      final json = arg.defaultJson;
      return json == null ? null : _literals.write(json, arg.type.typeRef);
    } on Object catch (error) {
      // The core's codecs and `jsonOf` signal an unwritable value with an
      // ArgumentError or a StateError; `avoid_catching_errors` forbids naming
      // them, so anything else is rethrown.
      if (error is! ArgumentError && error is! StateError) rethrow;
      _report(coordinate, _reasonOf(error));
    }
    return null;
  }

  String _reasonOf(Object error) => switch (error) {
    ArgumentError(:final message) => '$message',
    StateError(:final message) => message,
    _ => '$error',
  };

  void _report(String coordinate, String reason) {
    problems.add(
      Diagnostic(
        .unencodableDefaultValue,
        .error,
        'The default value of "$coordinate" cannot be written as a '
        'literal: $reason',
      ),
    );
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/literal_writer.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'enum_type_def.dart';
import 'input_object_def.dart';
import 'named_type_def.dart';

/// Writes a [JsonValue] as a constant language [Value], as graphql-js's
/// `astFromValue` does: an enum type gives an enum value, a list a list, an
/// input object an object, a number an `Int` when it is integral.
///
/// Guided by the language type and the definitions of the named types it
/// meets. The definitions are used, not the assembled schema types, because
/// default values are part of the schema types being assembled. Recursion
/// depth follows the nesting of a default value written in code.
final class LiteralWriter {
  /// Creates a writer that looks named types up in [definitions].
  LiteralWriter(Iterable<NamedTypeDef> definitions)
    : _definitions = {
        for (final definition in definitions.toList().reversed)
          definition.name: definition,
      };

  // Lookup only: never iterated. Built from the end so the first definition
  // of a name wins, as in the schema.
  final Map<String, NamedTypeDef> _definitions;

  /// Writes [json] as a value of [type]; a null [type] writes the value by
  /// its shape alone.
  Value write(JsonValue json, TypeRef? type) {
    if (json is JsonNull) return const NullValue();
    return switch (type) {
      NonNullType(type: final inner) => write(json, inner),
      ListType(type: final item) => _list(json, item),
      NamedType(:final name) => _named(json, name.value),
      null => _byShape(json),
    };
  }

  Value _list(JsonValue json, TypeRef item) {
    // A single value stands for a list of one (spec 3.11 input coercion).
    if (json is! JsonArray) return write(json, item);
    return ListValue([for (final entry in json.items) write(entry, item)]);
  }

  Value _named(JsonValue json, String name) {
    final definition = _definitions[name];
    if (definition is EnumTypeDef<Enum> && json is JsonString) {
      return EnumValue(json.value);
    }
    if (definition is InputObjectDef<Object> && json is JsonObject) {
      return _object(json, definition);
    }
    return _byShape(json);
  }

  Value _object(JsonObject json, InputObjectDef<Object> definition) {
    final types = {
      for (final field in definition.fields) field.name: field.type.typeRef,
    };
    return ObjectValue([
      for (final MapEntry(:key, :value) in json.fields.entries)
        ObjectField(Name(key), write(value, types[key])),
    ]);
  }

  Value _byShape(JsonValue json) => switch (json) {
    JsonNull() => const NullValue(),
    JsonBool(:final value) => BooleanValue(value),
    JsonNumber() => _number(json),
    JsonString(:final value) => StringValue(value),
    JsonArray(:final items) => ListValue([
      for (final entry in items) _byShape(entry),
    ]),
    JsonObject(:final fields) => ObjectValue([
      for (final MapEntry(:key, :value) in fields.entries)
        ObjectField(Name(key), _byShape(value)),
    ]),
  };

  Value _number(JsonNumber json) {
    final number = json.value;
    if (number is int || json.asInt != null) {
      return IntValue('${number.toInt()}');
    }
    return FloatValue('$number');
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/possible_types.dart`:

```dart
import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'union_type_def.dart';

/// The object types each interface and union can have as a value, in the
/// order the objects were created (the order of the schema).
final class PossibleTypes {
  /// Collects the possible types of every abstract type in [definitions].
  ///
  /// An object counts for each interface it lists and for the interfaces
  /// those list, walked with an explicit stack.
  PossibleTypes(Iterable<NamedTypeDef> definitions) {
    for (final definition in definitions) {
      if (definition is! ObjectTypeDef<Object?>) continue;
      final visited = Set<InterfaceTypeDef<Object?>>.identity();
      final pending = [...definition.interfaces];
      while (pending.isNotEmpty) {
        final next = pending.removeLast();
        if (!visited.add(next)) continue;
        (_implementations[next] ??= []).add(definition);
        pending.addAll(next.interfaces);
      }
    }
  }

  // Lookup only, by identity: never iterated.
  final Map<NamedTypeDef, List<ObjectTypeDef<Object?>>> _implementations =
      Map.identity();

  /// The possible object types of [abstractType]; empty for any other kind.
  List<ObjectTypeDef<Object?>> of(NamedTypeDef abstractType) =>
      switch (abstractType) {
        UnionTypeDef<Object?>(:final members) => members,
        InterfaceTypeDef<Object?>() => _implementations[abstractType] ?? [],
        _ => const [],
      };
}
```

Create `packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart`:

```dart
import '../execution/abstract_type_binding.dart';
import '../execution/schema_bindings.dart';
import 'enum_type_def.dart';
import 'field_def.dart';
import 'field_inheritance.dart';
import 'input_object_def.dart';
import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'possible_types.dart';
import 'scalar_type_def.dart';
import 'union_type_def.dart';

/// Builds the [SchemaBindings] of a set of definitions.
final class SchemaBindingsAssembler {
  /// Creates the assembler.
  SchemaBindingsAssembler();

  final Map<String, ObjectTypeDef<Object?>> _objects = {};
  final Map<String, Map<String, FieldDef<Object?, Object?>>> _fields = {};
  final Map<String, AbstractTypeBinding> _abstractTypes = {};
  final Map<String, NamedTypeDef> _leaves = {};
  final Map<String, InputObjectDef<Object>> _inputObjects = {};

  /// The tables for [definitions], with [possibleTypes] for the abstract
  /// ones. The first definition of a name wins, as in the schema.
  ///
  /// An assembler is used for one call.
  SchemaBindings assemble(
    List<NamedTypeDef> definitions,
    PossibleTypes possibleTypes,
  ) {
    for (final definition in definitions) {
      switch (definition) {
        case ObjectTypeDef<Object?>():
          _addObject(definition);
        case InterfaceTypeDef<Object?>(:final untypedResolveType) ||
            UnionTypeDef<Object?>(:final untypedResolveType):
          _abstractTypes.putIfAbsent(
            definition.name,
            () => AbstractTypeBinding(
              definition.name,
              untypedResolveType,
              possibleTypes.of(definition),
            ),
          );
        case ScalarTypeDef<Object>() || EnumTypeDef<Enum>():
          _leaves.putIfAbsent(definition.name, () => definition);
        case InputObjectDef<Object>():
          _inputObjects.putIfAbsent(definition.name, () => definition);
        default:
      }
    }
    return SchemaBindings(
      objects: _objects,
      fields: _fields,
      abstractTypes: _abstractTypes,
      leaves: _leaves,
      inputObjects: _inputObjects,
    );
  }

  void _addObject(ObjectTypeDef<Object?> definition) {
    _objects.putIfAbsent(definition.name, () => definition);
    _fields.putIfAbsent(definition.name, () {
      final collected = FieldInheritance().collect(
        definition.fields,
        definition.interfaces,
      );
      return {for (final field in collected) field.name: field};
    });
  }
}
```

Create `packages/typed_graphql_server/lib/src/builder/schema_build_error.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Thrown by `ExecutableSchemaBuilder.build` when the declared schema has
/// problems. A schema is code, so this is a programmer error, not bad input.
///
/// {@category builder}
final class SchemaBuildError extends Error {
  /// Creates the error for [diagnostics].
  SchemaBuildError(List<Diagnostic> diagnostics)
    : diagnostics = List.unmodifiable(diagnostics);

  /// Every problem found, the builder's checks first, then the core
  /// validator's.
  final List<Diagnostic> diagnostics;

  @override
  String toString() => [
    'SchemaBuildError:',
    for (final diagnostic in diagnostics)
      '${diagnostic.code.id}: ${diagnostic.message}',
  ].join('\n');
}
```

Create `packages/typed_graphql_server/lib/src/builder/type_assembler.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'directive_nodes.dart';
import 'enum_type_def.dart';
import 'field_assembler.dart';
import 'field_def.dart';
import 'field_inheritance.dart';
import 'input_object_def.dart';
import 'input_value_assembler.dart';
import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'scalar_type_def.dart';
import 'union_type_def.dart';

/// Turns a definition made through the builder into a core [SchemaType].
final class TypeAssembler {
  /// Creates the assembler; it writes arguments through [_inputs].
  TypeAssembler(this._inputs) : _fields = FieldAssembler(_inputs);

  final InputValueAssembler _inputs;
  final FieldAssembler _fields;

  static const DirectiveNodes _nodes = DirectiveNodes();

  /// The schema type for [definition].
  SchemaType assemble(NamedTypeDef definition) => switch (definition) {
    ScalarTypeDef<Object>() => _scalar(definition),
    EnumTypeDef<Enum>() => _enum(definition),
    ObjectTypeDef<Object?>() => _object(definition),
    InterfaceTypeDef<Object?>() => _interface(definition),
    UnionTypeDef<Object?>() => _union(definition),
    InputObjectDef<Object>() => _inputObject(definition),
    _ => throw StateError(
      'Unknown definition kind ${definition.runtimeType} for '
      '"${definition.name}".',
    ),
  };

  SchemaType _scalar(ScalarTypeDef<Object> definition) => ScalarType(
    definition.name,
    description: definition.description,
    appliedDirectives: [
      if (definition.specifiedByUrl case final url?) _nodes.specifiedBy(url),
    ],
  );

  SchemaType _enum(EnumTypeDef<Enum> definition) => EnumType(
    definition.name,
    description: definition.description,
    values: [
      for (final value in definition.values)
        SchemaEnumValue(
          value.name,
          description: value.description,
          appliedDirectives: _nodes.withDeprecation(
            const [],
            value.deprecationReason,
          ),
        ),
    ],
  );

  SchemaType _object(ObjectTypeDef<Object?> definition) => ObjectType(
    definition.name,
    description: definition.description,
    interfaces: _references(definition.interfaces),
    appliedDirectives: definition.options.directives,
    fields: _fieldsOf(
      definition.name,
      definition.fields,
      definition.interfaces,
    ),
  );

  SchemaType _interface(InterfaceTypeDef<Object?> definition) => InterfaceType(
    definition.name,
    description: definition.description,
    interfaces: _references(definition.interfaces),
    fields: _fieldsOf(
      definition.name,
      definition.fields,
      definition.interfaces,
    ),
  );

  SchemaType _union(UnionTypeDef<Object?> definition) => UnionType(
    definition.name,
    description: definition.description,
    memberTypes: _references(definition.members),
  );

  SchemaType _inputObject(InputObjectDef<Object> definition) => InputObjectType(
    definition.name,
    description: definition.description,
    appliedDirectives: [if (definition.isOneOf) _nodes.oneOf()],
    fields: [
      for (final field in definition.fields)
        _inputs.assemble(field, '${definition.name}.${field.name}'),
    ],
  );

  List<NamedTypeReference> _references(List<NamedTypeDef> definitions) => [
    for (final definition in definitions) NamedTypeReference(definition.name),
  ];

  // Own fields first, then those inherited from the listed interfaces.
  List<SchemaField> _fieldsOf(
    String typeName,
    List<FieldDef<Object?, Object?>> own,
    List<InterfaceTypeDef<Object?>> interfaces,
  ) => [
    for (final field in FieldInheritance().collect(own, interfaces))
      _fields.assemble(field, typeName),
  ];
}
```

Create `packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart`:

```dart
import '../builder/object_type_def.dart';

/// How the executor resolves the runtime object type of a value of an
/// interface or union.
final class AbstractTypeBinding {
  /// Creates the binding of the abstract type [name].
  AbstractTypeBinding(
    this.name,
    this.resolveType,
    List<ObjectTypeDef<Object?>> possibleTypes,
  ) : possibleTypes = List.unmodifiable(possibleTypes);

  /// The abstract type's name.
  final String name;

  /// The explicit type resolution, null for the default (the first possible
  /// type that accepts the value).
  final ObjectTypeDef<Object?> Function(Object? value)? resolveType;

  /// The object types that can be a value, in schema order.
  final List<ObjectTypeDef<Object?>> possibleTypes;
}
```

Create `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'schema_bindings.dart';

/// A validated schema with the resolvers behind it: what
/// `ExecutableSchemaBuilder.build` returns. `C` is the context type the
/// resolvers receive.
///
/// The SDL is `const SchemaPrinter().print(schema.schema)`.
///
/// {@category execution}
final class ExecutableSchema<C> {
  /// Creates the schema from a validated [schema] and its [bindings].
  ExecutableSchema(this.schema, this.bindings);

  /// The validated schema.
  final ValidSchema schema;

  /// The run-time tables the executor reads.
  final SchemaBindings bindings;
}
```

Create `packages/typed_graphql_server/lib/src/execution/schema_bindings.dart`:

```dart
import '../builder/field_def.dart';
import '../builder/input_object_def.dart';
import '../builder/named_type_def.dart';
import '../builder/object_type_def.dart';
import 'abstract_type_binding.dart';

/// What the executor needs at run time, by type name: the Dart-side
/// counterpart of the core schema.
final class SchemaBindings {
  /// Creates the tables; each is copied unmodifiable.
  SchemaBindings({
    required Map<String, ObjectTypeDef<Object?>> objects,
    required Map<String, Map<String, FieldDef<Object?, Object?>>> fields,
    required Map<String, AbstractTypeBinding> abstractTypes,
    required Map<String, NamedTypeDef> leaves,
    required Map<String, InputObjectDef<Object>> inputObjects,
  }) : objects = Map.unmodifiable(objects),
       fields = Map.unmodifiable(fields),
       abstractTypes = Map.unmodifiable(abstractTypes),
       leaves = Map.unmodifiable(leaves),
       inputObjects = Map.unmodifiable(inputObjects);

  /// The object types.
  final Map<String, ObjectTypeDef<Object?>> objects;

  /// The fields of each object type by field name, inherited ones included.
  final Map<String, Map<String, FieldDef<Object?, Object?>>> fields;

  /// The interfaces and unions.
  final Map<String, AbstractTypeBinding> abstractTypes;

  /// The scalar and enum definitions (`ScalarTypeDef`, `EnumTypeDef`).
  final Map<String, NamedTypeDef> leaves;

  /// The input objects.
  final Map<String, InputObjectDef<Object>> inputObjects;
}
```

In `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,11 +4,11 @@ import 'enum_value_def.dart';
 /// descriptions and deprecations.
 ///
 /// Passed to `ExecutableSchemaBuilder.enumType`; the defaults are
-/// [Enum.name] and no description or deprecation.
+/// `Enum.name` and no description or deprecation.
 ///
 /// {@category builder}
 final class const EnumValueMapping<E extends Enum>({
-  /// The schema name of a value; null means [Enum.name].
+  /// The schema name of a value; null means `Enum.name`.
   final String Function(E value)? nameOf,
 
   /// The description of a value, null for none.
```

In `packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,11 +1,14 @@
 import 'package:typed_graphql/typed_graphql.dart';
 
+import '../execution/executable_schema.dart';
 import 'arg.dart';
 import 'arguments.dart';
+import 'build_options.dart';
 import 'built_in_scalar_definitions.dart';
 import 'definition_registry.dart';
 import 'enum_type_def.dart';
 import 'enum_value_mapping.dart';
+import 'executable_schema_assembly.dart';
 import 'field_def.dart';
 import 'fields_builder.dart';
 import 'input_list_ref.dart';
@@ -55,7 +58,7 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
   /// Declares the enum [name] over the Dart enum [values].
   ///
   /// [mapping] gives the names, descriptions and deprecations of the values
-  /// (a value's name defaults to [Enum.name]); the parameters of the three
+  /// (a value's name defaults to `Enum.name`); the parameters of the three
   /// callbacks are grouped in one object to keep the signature short.
   EnumTypeDef<E> enumType<E extends Enum>(
     String name,
@@ -176,4 +179,25 @@ final class ExecutableSchemaBuilder<C>() with BuiltInScalarDefinitions {
       description: description,
     ),
   );
+
+  /// Builds the schema from the definitions made so far, rooted at [query],
+  /// [mutation] and [subscription].
+  ///
+  /// Every definition made through this builder is part of the schema, in
+  /// creation order. The builder's own checks (`GQL300`-`GQL302`) and the
+  /// core validator run; any problem throws a `SchemaBuildError` with all
+  /// of them. Each call assembles anew: a definition made after a build does
+  /// not change the schema already built.
+  ExecutableSchema<C> build({
+    required ObjectTypeDef<Object?> query,
+    ObjectTypeDef<Object?>? mutation,
+    ObjectTypeDef<Object?>? subscription,
+    BuildOptions options = const BuildOptions(),
+  }) => ExecutableSchemaAssembly<C>(
+    definitions: definitions,
+    query: query,
+    mutation: mutation,
+    subscription: subscription,
+    options: options,
+  ).assemble();
 }
```

In `packages/typed_graphql_server/lib/src/builder/interface_type_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,12 +39,30 @@ final class InterfaceTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
   /// possible type that accepts it).
   final ObjectTypeDef<Object?> Function(P value)? resolveType;
 
+  /// Whether [resolveType] is given.
+  bool get hasResolveType => resolveType != null;
+
+  /// [resolveType] taking any value: the cast to [P] is made here, where
+  /// [P] is known, because reading [resolveType] through a supertype
+  /// instance fails its function-type check. Null without [resolveType].
+  ObjectTypeDef<Object?> Function(Object? value)? get untypedResolveType {
+    final resolve = resolveType;
+    return resolve == null ? null : (value) => resolve(value as P);
+  }
+
   /// Whether a value of Dart type [X] is a value of this interface.
   ///
   /// Dart has no contravariant type parameter, so `GQL300` is checked at
   /// build with this test.
   bool isSupertypeOf<X>() => <X>[] is List<P>;
 
+  /// The Dart type [P] as written, for messages.
+  String get dartTypeName => '$P';
+
+  /// Whether [P] is a subtype of the Dart type of [other] (`GQL300`).
+  bool isDartSubtypeOf(InterfaceTypeDef<Object?> other) =>
+      other.isSupertypeOf<P>();
+
   @override
   final TypeRef typeRef;
 
```

In `packages/typed_graphql_server/lib/src/builder/object_type_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -46,6 +46,21 @@ final class ObjectTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
   /// given, else `value is P`.
   bool accepts(Object? value) => options.isTypeOf?.call(value) ?? value is P;
 
+  /// The Dart type [P] as written, for messages.
+  String get dartTypeName => '$P';
+
+  /// Whether [P] is a subtype of the Dart type of [interface] (`GQL300`).
+  bool isDartSubtypeOfInterface(InterfaceTypeDef<Object?> interface) =>
+      interface.isSupertypeOf<P>();
+
+  /// Whether [P] is a subtype of the Dart type of [other].
+  bool isDartSubtypeOf(ObjectTypeDef<Object?> other) =>
+      other._isDartSupertypeOf<P>();
+
+  // Dart has no contravariant type parameter: the test needs the type of the
+  // other object as `P`, so it runs inside that object.
+  bool _isDartSupertypeOf<X>() => <X>[] is List<P>;
+
   @override
   final TypeRef typeRef;
 
```

In `packages/typed_graphql_server/lib/src/builder/union_type_def.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -25,6 +25,17 @@ final class UnionTypeDef<P> extends NamedTypeDef implements OutputRef<P> {
   /// member that accepts it).
   final ObjectTypeDef<Object?> Function(P value)? resolveType;
 
+  /// Whether [resolveType] is given.
+  bool get hasResolveType => resolveType != null;
+
+  /// [resolveType] taking any value: the cast to [P] is made here, where
+  /// [P] is known, because reading [resolveType] through a supertype
+  /// instance fails its function-type check. Null without [resolveType].
+  ObjectTypeDef<Object?> Function(Object? value)? get untypedResolveType {
+    final resolve = resolveType;
+    return resolve == null ? null : (value) => resolve(value as P);
+  }
+
   @override
   final TypeRef typeRef;
 
```

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,6 +9,7 @@ library;
 export 'src/builder/arg.dart';
 export 'src/builder/arguments.dart';
 export 'src/builder/arguments_def.dart';
+export 'src/builder/build_options.dart';
 export 'src/builder/enum_type_def.dart';
 export 'src/builder/enum_value_def.dart';
 export 'src/builder/enum_value_mapping.dart';
@@ -26,5 +27,7 @@ export 'src/builder/object_type_def.dart';
 export 'src/builder/optional.dart';
 export 'src/builder/output_ref.dart';
 export 'src/builder/scalar_type_def.dart';
+export 'src/builder/schema_build_error.dart';
 export 'src/builder/union_type_def.dart';
+export 'src/execution/executable_schema.dart';
 export 'src/execution/field_info.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/build_errors_test.dart test/builder/build_test.dart test/builder/literal_writer_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- `ExecutableSchemaBuilder.build` assembles the declared types into a
  validated `ExecutableSchema<C>`; the builder's own checks (`GQL300`-`GQL302`)
  and the core validator report through `SchemaBuildError`. `BuildOptions`
  holds the directives, `includesDeferAndStream` and the description.
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
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/lib/src/builder/build_options.dart packages/typed_graphql_server/lib/src/builder/builder_checks.dart packages/typed_graphql_server/lib/src/builder/directive_nodes.dart packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart packages/typed_graphql_server/lib/src/builder/executable_schema_assembly.dart packages/typed_graphql_server/lib/src/builder/executable_schema_builder.dart packages/typed_graphql_server/lib/src/builder/field_assembler.dart packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart packages/typed_graphql_server/lib/src/builder/interface_type_def.dart packages/typed_graphql_server/lib/src/builder/literal_writer.dart packages/typed_graphql_server/lib/src/builder/object_type_def.dart packages/typed_graphql_server/lib/src/builder/possible_types.dart packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart packages/typed_graphql_server/lib/src/builder/schema_build_error.dart packages/typed_graphql_server/lib/src/builder/type_assembler.dart packages/typed_graphql_server/lib/src/builder/union_type_def.dart packages/typed_graphql_server/lib/src/execution/abstract_type_binding.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/lib/src/execution/schema_bindings.dart packages/typed_graphql_server/lib/typed_graphql_server.dart packages/typed_graphql_server/test/builder/build_errors_test.dart packages/typed_graphql_server/test/builder/build_test.dart packages/typed_graphql_server/test/builder/literal_writer_test.dart
git commit -q -m "feat(typed_graphql_server): build executable schemas" \
  -m "build() assembles every definition into a core schema, runs the GQL300-GQL302 checks and the core validator, and returns an ExecutableSchema with its binding tables; problems throw SchemaBuildError." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Compile-time type checks

Prove the typed API with fixtures compiled by `dart compile kernel` in a test: one fixture compiles, and four (nullable getter for a non-null ref, wrong result type, unrelated union member, wrong argument read) fail with the expected messages.

**Files:**
- Test: `packages/typed_graphql_server/test/compile/compile_failures_test.dart`, `packages/typed_graphql_server/test/compile/fixtures/nullable_for_non_null.dart.txt`, `packages/typed_graphql_server/test/compile/fixtures/ok.dart.txt`, `packages/typed_graphql_server/test/compile/fixtures/unrelated_union_member.dart.txt`, `packages/typed_graphql_server/test/compile/fixtures/wrong_argument_read.dart.txt`, `packages/typed_graphql_server/test/compile/fixtures/wrong_result_type.dart.txt`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/compile/compile_failures_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Compiles fixtures with the front end, as a user's build would.
class FixtureCompiler {
  /// Creates the compiler.
  const FixtureCompiler();

  /// Compiles one fixture, checks that it passed or failed as expected and
  /// returns the compiler output.
  Future<String> compile(String name, {required bool isExpected}) async {
    final directory = Directory('.dart_tool/compile_fixtures')
      ..createSync(recursive: true);
    final source = File('test/compile/fixtures/$name.dart.txt');
    final target = File('${directory.path}/$name.dart')
      ..writeAsStringSync(source.readAsStringSync());
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      target.path,
      '-o',
      '${directory.path}/$name.dill',
    ]).timeout(const Duration(seconds: 150));
    final output = '${result.stdout}${result.stderr}';
    expect(result.exitCode == 0, isExpected, reason: output);
    return output;
  }
}

void main() {
  const compiler = FixtureCompiler();
  const timeout = Timeout(Duration(minutes: 3));

  test('a correct program compiles', () async {
    await compiler.compile('ok', isExpected: true);
  }, timeout: timeout);

  const failing = {
    'nullable_for_non_null': "can't be returned from",
    'wrong_result_type': "can't be returned from",
    'unrelated_union_member':
        "'ObjectTypeDef<Rock>' can't be assigned to a variable of type "
        "'ObjectTypeDef<Animal>'",
    'wrong_argument_read':
        "'Arg<int>' can't be assigned to the parameter type 'Arg<String>'",
  };
  failing.forEach((name, text) {
    test('$name does not compile', () async {
      final output = await compiler.compile(name, isExpected: false);
      expect(output, contains(text));
    }, timeout: timeout);
  });
}
```

Create `packages/typed_graphql_server/test/compile/fixtures/nullable_for_non_null.dart.txt`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Pet {
  const Pet(this.name);
  final String? name;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  b.object<Pet>(
    'Pet',
    fields: (t) => [t.field('name', b.string).pure((Pet p) => p.name)],
  );
}
```

Create `packages/typed_graphql_server/test/compile/fixtures/ok.dart.txt`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Pet {
  const Pet(this.name);
  final String? name;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final times = Arg('times', b.int, defaultValue: 1);
  final pet = b.object<Pet>(
    'Pet',
    fields: (t) => [
      t.field('name', b.string.nullable).pure((Pet p) => p.name),
      t
          .field('twice', b.int, args: [times])
          .resolve((Pet p, Arguments args, Object? ctx, FieldInfo info) {
            final int value = args.get(times);
            return value * 2;
          }),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('pet', pet).pure((Object? _) => const Pet('x'))],
  );
  b.union<Pet>('PetUnion', members: [pet]);
  b.build(query: query);
}
```

Create `packages/typed_graphql_server/test/compile/fixtures/unrelated_union_member.dart.txt`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Animal {}

final class Cat extends Animal {}

final class Rock {}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final cat = b.object<Cat>('Cat', fields: (t) => []);
  final rock = b.object<Rock>('Rock', fields: (t) => []);
  b.union<Animal>('Thing', members: [cat, rock]);
}
```

Create `packages/typed_graphql_server/test/compile/fixtures/wrong_argument_read.dart.txt`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final times = Arg('times', b.int);
  b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('x', b.string, args: [times])
          .resolve((Object? p, Arguments args, Object? ctx, FieldInfo info) {
            final String value = args.get(times);
            return value;
          }),
    ],
  );
}
```

Create `packages/typed_graphql_server/test/compile/fixtures/wrong_result_type.dart.txt`:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Pet {
  const Pet(this.age);
  final int age;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  b.object<Pet>(
    'Pet',
    fields: (t) => [t.field('name', b.string).pure((Pet p) => p.age)],
  );
}
```

- [ ] **Step 2: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/compile/compile_failures_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 3: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 4: Commit**

```sh
git add packages/typed_graphql_server/test/compile/compile_failures_test.dart packages/typed_graphql_server/test/compile/fixtures/nullable_for_non_null.dart.txt packages/typed_graphql_server/test/compile/fixtures/ok.dart.txt packages/typed_graphql_server/test/compile/fixtures/unrelated_union_member.dart.txt packages/typed_graphql_server/test/compile/fixtures/wrong_argument_read.dart.txt packages/typed_graphql_server/test/compile/fixtures/wrong_result_type.dart.txt
git commit -q -m "test(typed_graphql_server): check that wrong resolver types do not compile" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: The Schema Builder guide

Write `doc/schema_builder.md` (programs that print what they build) and a short `doc/execution.md`, the dartdoc categories, the server's documentation suite (snippets, links, category tags, reusing the core's helpers), the README banner, the CHANGELOG, `llms.txt`, the root README, the `CLAUDE.md` Server paragraph and the HANDOFF line.

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/README.md`
- Create (documents): `packages/typed_graphql_server/dartdoc_options.yaml`, `packages/typed_graphql_server/doc/execution.md`, `packages/typed_graphql_server/doc/schema_builder.md`
- Test: `packages/typed_graphql_server/test/doc/category_tags_test.dart`, `packages/typed_graphql_server/test/doc/doc_links_test.dart`, `packages/typed_graphql_server/test/doc/doc_snippets_test.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/doc/category_tags_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/public_type.dart';

/// Every exported type is in the dartdoc category of its folder, and
/// `dartdoc_options.yaml` declares those categories, each with a guide
/// (R11.2).
void main() {
  final barrel = File('lib/typed_graphql_server.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();
  final declared = [
    for (final match in RegExp(
      r'^ {4}([a-z-]+):$',
      multiLine: true,
    ).allMatches(options))
      match[1]!,
  ];

  /// The category of the types in the library file [path], from `lib/`.
  String categoryOf(String path) => switch (path.split('/')) {
    ['src', final folder, ...] => folder,
    _ => throw ArgumentError.value(path, 'path', 'is not under lib/src'),
  };

  test('every category used is declared, and every one declared is used', () {
    expect(declared.toSet(), exported.map(categoryOf).toSet());
  });

  test('every declared category has its guide', () {
    for (final match in RegExp(r'markdown: (doc/\S+)').allMatches(options)) {
      expect(File(match[1]!).existsSync(), isTrue, reason: match[1]);
    }
    expect(
      RegExp('markdown: doc').allMatches(options),
      hasLength(declared.length),
    );
  });

  test('the category order lists every declared category once', () {
    final order = [
      for (final match in RegExp(
        r'^ {4}- ([a-z-]+)$',
        multiLine: true,
      ).allMatches(options))
        match[1]!,
    ];
    expect(order, declared);
  });

  group('exported types', () {
    for (final path in exported) {
      test(path, () {
        final tag = '{@category ${categoryOf(path)}}';
        final source = File('lib/$path').readAsStringSync();
        final untagged = [
          for (final type in const PublicTypes().declaredIn(source))
            if (type.countOf(tag) != 1) type.name,
        ];
        expect(
          untagged,
          isEmpty,
          reason: 'give each exactly one $tag in its doc comment',
        );
      });
    }
  });
}
```

Create `packages/typed_graphql_server/test/doc/doc_links_test.dart`:

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

Create `packages/typed_graphql_server/test/doc/doc_snippets_test.dart`:

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
  final files = const DocFiles().all();
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

- [ ] **Step 2: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc/category_tags_test.dart test/doc/doc_links_test.dart test/doc/doc_snippets_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 3: Update the documents**

Create `packages/typed_graphql_server/dartdoc_options.yaml`:

```yaml
dartdoc:
  categories:
    builder:
      markdown: doc/schema_builder.md
      displayName: Schema Builder
    execution:
      markdown: doc/execution.md
      displayName: Execution
  categoryOrder:
    - builder
    - execution
  showUndocumentedCategories: true
```

Create `packages/typed_graphql_server/doc/execution.md`:

````markdown
# Execution

Execution of requests arrives in M5b. The package holds, today, the two
types the builder hands to it.

`ExecutableSchema<C>` is what `ExecutableSchemaBuilder.build` returns: the
validated core `ValidSchema` (`schema`) and the run-time tables of the
resolvers behind it (`bindings`). `C` is the context type the resolvers
receive. The schema's SDL is
`const SchemaPrinter().print(executable.schema.schema)`.

`FieldInfo` is the last argument of a `resolve` closure: the field's name
(`fieldName`), the name of the object type it is selected on
(`parentTypeName`) and its response `path` from the root, a list of the
core's `PathSegment`s.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('where', b.string)
          .resolve(
            (parent, args, context, info) =>
                '${info.parentTypeName}.${info.fieldName}',
          ),
    ],
  );
  final executable = b.build(query: query);
  print(executable.schema.schema.queryTypeName);
}
```

It prints:

```text
Query
```
````

Create `packages/typed_graphql_server/doc/schema_builder.md`:

````markdown
# Schema Builder

`ExecutableSchemaBuilder<C>` declares a GraphQL schema in typed Dart code.
`C` is the type of the per-request context every resolver receives. Every
definition you make through a builder belongs to the schema it builds, in
creation order; `build` checks them and returns an `ExecutableSchema<C>`
(`typed_graphql`'s own `SchemaBuilder` builds a schema from SDL text, hence
the different name).

The package cannot execute a request yet: execution arrives in M5b. What
works today is declaring, checking and printing a schema.

## Refs and nullability

Every type you declare, and the five built-in scalars (`b.int`, `b.float`,
`b.string`, `b.boolean`, `b.id`), is a ref, and a ref carries its Dart type.
A ref is non-null by default, as a Dart type is: `b.string` is `String!` and
stands for a Dart `String`. `.nullable` gives `String` and a Dart `String?`.
`b.list(item)` is a non-null list of `item`, so `b.list(b.string.nullable)`
is `[String]!` and `b.list(b.string).nullable` is `[String!]`.

## Objects and fields

A field is declared in two steps: `t.field(name, type, ...)` fixes the Dart
result type from the ref, and `pure` or `resolve` then takes the closure.
Because the type is known before the closure is inferred, a getter that
returns a `String?` for a `b.string` field, or an `int` for a `String`
field, does not compile, and a field without a resolver is not a field at
all.

- `pure((parent) => value)` reads a value from the parent object, with no
  arguments, no context and no waiting.
- `resolve((parent, args, context, info) => result)` may return a value or a
  `Future` of one, and reads the field's arguments and the context.
- `declareOnly()` completes an interface field: every implementing object
  declares its own resolver.
- `.deprecated(reason)` and `.withDirectives(...)` modify the stub before
  it is completed.

An object's `fields` thunk runs once, when the schema is built or first
used, so two types may refer to each other through `late final` variables
or class fields.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Book {
  const Book(this.title, this.pages);

  final String title;
  final int? pages;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<Book>(
    'Book',
    description: 'A book on the shelf.',
    fields: (t) => [
      t.field('title', b.string).pure((book) => book.title),
      t.field('pages', b.int.nullable).pure((book) => book.pages),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('books', b.list(book)).pure((_) => const [Book('Dune', 412)]),
      t
          .field('motto', b.string.nullable)
          .deprecated('Not used.')
          .pure((_) => null),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
"""A book on the shelf."""
type Book {
  title: String!
  pages: Int
}

type Query {
  books: [Book!]!
  motto: String @deprecated(reason: "Not used.")
}
```

## Scalars and enums

`b.scalar<T>(name, codec)` declares a custom scalar over a `ScalarCodec<T>`
of the core. `b.enumType<E>(name, values)` declares an enum over a Dart
enum: the value of an enum field is the Dart enum value itself. An
`EnumValueMapping` renames values and gives them descriptions and
deprecations; the default name is `Enum.name`.

## Arguments

An `Arg<T>` declares a field argument: `Arg('first', b.int, defaultValue: 10)`.
Pass the arguments to the field with `args:` and read them in `resolve`
through `args.get(arg)`, which returns a `T`, so the read is checked at
compile time like the result. A default value is written into the schema.

`Arg.optional('after', b.string.nullable)` is for an argument whose absence
differs from `null`, as in a partial update: its value is an `Optional<T>`,
`Present(value)` when the request gave one and `Absent()` when it did not.
`Arg.optional` keeps the nullability of the ref it is given, so a non-null
ref makes a required argument; `b.string.nullable` is the usual choice.

When a field has many arguments, `resolveWith(definition, resolve)` takes an
`ArgumentsDef<A>`: the arguments and a function that builds your own
arguments class from them, so the resolver gets an `A`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

enum Genre { fantasy, scienceFiction }

final class Search {
  const Search(this.genre, this.limit);

  final Genre? genre;
  final int limit;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final genre = b.enumType<Genre>(
    'Genre',
    Genre.values,
    mapping: EnumValueMapping<Genre>(
      nameOf: (value) => switch (value) {
        Genre.fantasy => 'FANTASY',
        Genre.scienceFiction => 'SCIENCE_FICTION',
      },
    ),
  );
  final genreArg = Arg('genre', genre.nullable);
  final limitArg = Arg('limit', b.int, defaultValue: 10);
  final afterArg = Arg.optional('after', b.string.nullable);
  final search = ArgumentsDef<Search>([
    genreArg,
    limitArg,
  ], (args) => Search(args.get(genreArg), args.get(limitArg)));
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('count', b.int, args: [limitArg, afterArg]).resolve((
        parent,
        args,
        context,
        info,
      ) {
        final limit = args.get(limitArg);
        return switch (args.get(afterArg)) {
          Present() => limit,
          Absent() => limit * 2,
        };
      }),
      t
          .field('titles', b.list(b.string))
          .resolveWith(
            search,
            (parent, args, context, info) => [
              'at most ${args.limit} of ${args.genre}',
            ],
          ),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
enum Genre {
  FANTASY
  SCIENCE_FICTION
}

type Query {
  count(limit: Int! = 10, after: String): Int!
  titles(genre: Genre, limit: Int! = 10): [String!]!
}
```

## Input objects

`b.inputObject<T>(name, fields: ..., decode: ...)` declares an input object
decoded to your class `T`. Its fields are `Arg`s, read in `decode` through
the same `Arguments`. `encode` is needed only when an `Arg` of this type has
a default value, which the schema writes as a literal.
`b.oneOfInputObject` declares an input object with `@oneOf`: exactly one of
its fields is given. `b.inputList(item)` is the list type for inputs.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Range {
  const Range(this.from, this.to);

  final int from;
  final int to;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final from = Arg('from', b.int, defaultValue: 0);
  final to = Arg('to', b.int);
  final range = b.inputObject<Range>(
    'Range',
    fields: () => [from, to],
    decode: (values) => Range(values.get(from), values.get(to)),
  );
  final byId = Arg('id', b.id.nullable);
  final byName = Arg('name', b.string.nullable);
  final lookup = b.oneOfInputObject<String>(
    'Lookup',
    fields: () => [byId, byName],
    decode: (values) => values.get(byId) ?? values.get(byName) ?? '',
  );
  final rangeArg = Arg('range', range);
  final lookupArg = Arg('by', lookup);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('width', b.int, args: [rangeArg]).resolve((
        parent,
        args,
        context,
        info,
      ) {
        final value = args.get(rangeArg);
        return value.to - value.from;
      }),
      t
          .field('find', b.string.nullable, args: [lookupArg])
          .resolve((parent, args, context, info) => args.get(lookupArg)),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
input Range {
  from: Int! = 0
  to: Int!
}

input Lookup @oneOf {
  id: ID
  name: String
}

type Query {
  width(range: Range!): Int!
  find(by: Lookup!): String
}
```

## Interfaces and unions

`b.interface<P>(name, fields: ...)` declares an interface over the Dart type
`P`. An object that lists it in `interfaces:` inherits the fields it does
not declare itself (an interface field completed with `declareOnly` is
never inherited), and the build checks that the object's Dart type is a
subtype of `P`. `b.union<P>(name, members: [...])` takes object types whose
Dart types are subtypes of `P`; the compiler checks that, because an
`ObjectTypeDef<Cat>` is an `ObjectTypeDef<Pet>`.

Both pick the object type of a value at run time. Give `resolveType` to
choose it yourself; without it the first possible type whose `accepts` takes
the value is used, which is enough when the Dart types differ. When two
possible types overlap in Dart, the build asks for an explicit `isTypeOf`
on both (`ObjectOptions`), or for `resolveType`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

sealed class Pet {
  const Pet(this.name);

  final String name;
}

final class Cat extends Pet {
  const Cat(super.name);
}

final class Dog extends Pet {
  const Dog(super.name, this.goodBoy);

  final bool goodBoy;
}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final named = b.interface<Pet>(
    'Named',
    fields: (t) => [t.field('name', b.string).pure((pet) => pet.name)],
  );
  final cat = b.object<Cat>('Cat', interfaces: [named], fields: (t) => []);
  final dog = b.object<Dog>(
    'Dog',
    interfaces: [named],
    fields: (t) => [t.field('goodBoy', b.boolean).pure((dog) => dog.goodBoy)],
  );
  final animal = b.union<Pet>('Animal', members: [cat, dog]);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('pets', b.list(named)).pure((_) => const <Pet>[Cat('Tom')]),
      t.field('animal', animal).pure((_) => const Dog('Rex', true)),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
interface Named {
  name: String!
}

type Cat implements Named {
  name: String!
}

type Dog implements Named {
  goodBoy: Boolean!
  name: String!
}

union Animal = Cat | Dog

type Query {
  pets: [Named!]!
  animal: Animal!
}
```

## Building and SchemaBuildError

`build({required query, mutation, subscription, options})` assembles every
definition made through the builder, in creation order. It runs the
builder's own checks and then the core's schema validator over the result.
A schema is code, so a problem is a programmer error: `build` throws one
`SchemaBuildError` holding every diagnostic, the builder's first. The
builder's own codes are `GQL300` (an object's Dart type is not a subtype of
the interface it lists), `GQL301` (two possible types of an abstract type
overlap in Dart without an explicit `isTypeOf` on both) and `GQL302` (a
default value cannot be written as a literal). `BuildOptions` holds the extra
directive definitions, `includesDeferAndStream` and the schema description.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Named {}

final class Thing {}

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final node = b.interface<Named>(
    'Node',
    fields: (t) => [t.field('id', b.id).pure((_) => '1')],
  );
  b.object<Thing>(
    'Thing',
    interfaces: [node],
    fields: (t) => [t.field('id', b.id).pure((_) => '1')],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
  );
  try {
    b.build(query: query);
  } on Object catch (error) {
    if (error is! SchemaBuildError) rethrow;
    for (final diagnostic in error.diagnostics) {
      print('${diagnostic.code.id}: ${diagnostic.message}');
    }
  }
}
```

It prints:

```text
GQL300: Type "Thing" (Dart type Thing) cannot implement interface "Node": Thing is not a subtype of Named.
```

## Services in the context

The builder never creates your resolvers or services: it takes closures.
Whatever a resolver needs comes from the context `C`, which the caller
supplies for each request, so a dependency injection container, a service
locator or a plain class all fit, and a host framework keeps ownership of
its objects. The context type is a parameter of the builder, so a resolver
that reads `context.library` is checked by the compiler.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Library {
  String titleOf(String id) => 'Title $id';
}

final class Services {
  Services(this.library);

  final Library library;
}

void main() {
  final b = ExecutableSchemaBuilder<Services>();
  final id = Arg('id', b.id);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('title', b.string, args: [id])
          .resolve(
            (parent, args, context, info) =>
                context.library.titleOf(args.get(id)),
          ),
    ],
  );
  final schema = b.build(query: query);
  print(const SchemaPrinter().print(schema.schema.schema));
}
```

It prints:

```text
type Query {
  title(id: ID!): String!
}
```
````

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -42,7 +42,10 @@ guide. M4b (limits and cost) delivers the opt-in limit rules (depth, aliases,
 directives, introspection: `GQL232`-`GQL236`), `recommendedRules`, the IBM
 cost directives (`includesCostDirectives`, `GQL156`-`GQL161`), `CostAnalysis`,
 `SlicingArgumentsRule` and `MaxCostRule` (`GQL237`, `GQL238`), the operation
-fuzzers and the guide sections on limits and cost.
+fuzzers and the guide sections on limits and cost. M5a (typed schema
+builder) delivers `ExecutableSchemaBuilder`, the typed refs, fields and
+arguments, `build` and `SchemaBuildError` (`GQL300`-`GQL302`) in
+`typed_graphql_server`, and the Schema Builder guide; execution is M5b.
 
 ## Documents
 
@@ -388,6 +391,23 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `MaxCostRule` (`GQL238`) and `SlicingArgumentsRule` (`GQL237`) are
   opt-in rules.
 
+**Server** (`packages/typed_graphql_server/lib/src/`; M5). Imports the core
+only through its barrel. One folder per concern, with no import order
+(`builder/` and `execution/` import each other): `builder/` (M5a), then
+`coercion/`, `plan/`, `introspection/`, `subscription/`, `lookahead/`,
+`authorization/` and `cancellation/` in later sub-stages. The package is
+transport-agnostic: `lib/` imports no `dart:io`, `dart:html`, `dart:isolate`
+or web framework, only `dart:async`, `dart:collection`, `dart:core`,
+`dart:math`, `meta` and the core (`test/quality/imports_test.dart`), and the
+builder never instantiates resolvers or services: closures get them from the
+context `C`. `ExecutableSchemaBuilder<C>` makes `OutputRef`/`InputRef`/
+`LeafRef` types and definitions in creation order; a field is
+`t.field(name, ref).pure|resolve|resolveWith|declareOnly` (two steps, so the
+result type is fixed before the closure); methods take at most five
+parameters, so options travel in `ObjectOptions`, `EnumValueMapping` and
+`BuildOptions`. `build` runs `GQL300`-`GQL302` and the core validator and
+throws `SchemaBuildError`. Its guides are in `packages/typed_graphql_server/doc/`.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -110,7 +110,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 | Package | Role | Status |
 |---|---|---|
 | [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
-| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
+| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder (M5a) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,6 +16,7 @@ needed.
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
 | M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete and merged into `main` locally (not pushed); the final opus review and two fix rounds are done. M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging (near-linear; a fan-out through parts that repeat a response name can still reach the step budget, spec §14 item 15), the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is M5 (execution) |
+| M5 Execution | [spec](specs/2026-10-15-m5-execution-design.md) | M5a: typed schema builder | M5a is done on branch `m5-final` (not merged, not pushed): `ExecutableSchemaBuilder`, typed refs, fields, arguments, `build`, `SchemaBuildError` (`GQL300`-`GQL302`) and the Schema Builder guide; next is M5b (execution) |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,7 +8,7 @@
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): skeleton; code generator and its CLI, not usable yet (M8, M10)
-- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): skeleton; typed schema builder, executor and transport handlers, not usable yet (M5 to M7)
+- [typed_graphql_server](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/README.md): under construction; the typed schema builder works, execution not yet (M5b), then transport handlers (M6, M7)
 - [typed_graphql_shelf](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_shelf/README.md): skeleton; the shelf adapter, not usable yet (M7)
 
 ## Guides
```

In `packages/typed_graphql_server/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,8 +5,27 @@
 - Package skeleton.
 - `repository` points at the package folder; pub.dev is expected to rewrite
   relative README links from it (to confirm at M16).
-- The README says the package is not usable yet.
+- The README says the package cannot execute requests yet.
+- Typed refs: `OutputRef<T>` and `InputRef<T>`, `LeafRef<T>` for scalars and
+  enums, `.nullable`, `b.list` and `b.inputList`; the built-in scalars
+  `b.int`, `b.float`, `b.string`, `b.boolean` and `b.id`.
+- `ExecutableSchemaBuilder<C>` declares custom scalars over a core
+  `ScalarCodec` (`scalar`), enums over Dart enums (`enumType`,
+  `EnumValueMapping`), input objects (`inputObject`, `oneOfInputObject`),
+  object types (`object`, `ObjectOptions`), interfaces and unions
+  (`interface`, `union`, `resolveType`, field inheritance through listed
+  interfaces).
+- Typed fields in two steps: `t.field(name, type, ...)` fixes the result
+  type, then `pure`, `resolve`, `resolveWith` or `declareOnly`; `deprecated`
+  and `withDirectives` modify the stub. A resolver of the wrong type does
+  not compile (checked by the compile-failure tests).
+- Typed arguments: `Arg`, `Arg.optional` with `Optional`, `Present` and
+  `Absent`, `Arguments`, `ArgumentsDef` for an arguments class.
 - `ExecutableSchemaBuilder.build` assembles the declared types into a
   validated `ExecutableSchema<C>`; the builder's own checks (`GQL300`-`GQL302`)
   and the core validator report through `SchemaBuildError`. `BuildOptions`
   holds the directives, `includesDeferAndStream` and the description.
+- `FieldInfo` (field name, parent type name, response path) is the last
+  argument of a resolver.
+- The Schema Builder and Execution guides, with the dartdoc categories
+  `builder` and `execution`.
```

In `packages/typed_graphql_server/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,13 +6,16 @@
 
 **A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
-> **Status: skeleton.** The package exists so the workspace, CI and the
-> code rules cover it from the start. Its code arrives in stage M5 of the
-> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md); nothing is exported yet.
+> **Status: under construction.** The typed schema builder works (stage M5a):
+> you can declare a schema in typed Dart code, build it, check it and print
+> its SDL. Execution arrives in M5b, see the
+> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).
 
-**Not usable yet.** This package exports nothing; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql).
+**Not usable yet.** This package cannot execute a request yet; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql), and the schema builder of this one.
 
-Planned: `SchemaBuilder` and `ExecutableSchema` (M5), the `GraphQLServer` pipeline with APQ, trusted documents and DataLoader (M6), and the GraphQL over HTTP, graphql-ws and graphql-sse handlers (M7).
+Today: `ExecutableSchemaBuilder` declares scalars, enums, input objects, objects with typed fields and arguments, interfaces and unions, and `build` returns a validated `ExecutableSchema` or throws a `SchemaBuildError` with diagnostics. The [Schema Builder guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/doc/schema_builder.md) shows each step.
+
+Planned: execution (M5b), introspection and subscriptions (M5c), look-ahead, authorization and cancellation (M5d), the `GraphQLServer` pipeline with APQ, trusted documents and DataLoader (M6), and the GraphQL over HTTP, graphql-ws and graphql-sse handlers (M7).
 
 ## License
 
```

- [ ] **Step 4: Run the documentation checks**

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add CLAUDE.md README.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/README.md packages/typed_graphql_server/dartdoc_options.yaml packages/typed_graphql_server/doc/execution.md packages/typed_graphql_server/doc/schema_builder.md packages/typed_graphql_server/test/doc/category_tags_test.dart packages/typed_graphql_server/test/doc/doc_links_test.dart packages/typed_graphql_server/test/doc/doc_snippets_test.dart
git commit -q -m "docs(typed_graphql_server): add the Schema Builder guide" \
  -m "Guides, dartdoc categories, documentation tests, README status, llms.txt, CHANGELOG, CLAUDE.md Server paragraph." \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: The library doc comment

Say in the library doc comment that the builder works and that execution arrives in M5b.

**Files:**
- Modify: `packages/typed_graphql_server/lib/typed_graphql_server.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql_server/lib/typed_graphql_server.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,8 +2,8 @@
 /// engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws
 /// and graphql-sse handlers.
 ///
-/// Under construction: the typed schema builder is partly in place (refs,
-/// scalars, enums, arguments, input objects); see the package README.
+/// Under construction: the typed schema builder works (M5a); execution
+/// arrives in M5b. See the package README.
 library;
 
 export 'src/builder/arg.dart';
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add packages/typed_graphql_server/lib/typed_graphql_server.dart
git commit -q -m "docs(typed_graphql_server): say in the library doc that the builder works" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: `GQL300` covers interfaces (core)

The review of Tasks 1-9 found that `GQL300` is also reported for an interface that lists an incompatible interface; widen its doc comment in the catalog.

**Files:**
- Modify: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`

**Interfaces:**
- Consumes: the earlier tasks of this plan.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -511,8 +511,9 @@ enum DiagnosticCode(
   /// maximum `MaxCostRule` allows.
   maxCostExceeded('GQL238'),
 
-  /// `GQL300`: an object type built with `ExecutableSchemaBuilder` lists an
-  /// interface whose Dart type is not a supertype of the object's Dart type.
+  /// `GQL300`: an object type or an interface type built with
+  /// `ExecutableSchemaBuilder` lists an interface whose Dart type is not a
+  /// supertype of its own Dart type.
   incompatibleImplementation('GQL300'),
 
   /// `GQL301`: two possible types of an abstract type have Dart types where
```

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart
git commit -q -m "docs(typed_graphql): say that GQL300 also covers interfaces" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: The review fixes

Apply the review of Tasks 1-9: report an unencodable default on an inherited interface field once (the `InputValueAssembler` remembers the reported `Arg`s); count only direct implementers in `PossibleTypes`, as graphql-js does; make `FieldStub.pure` reject declared arguments, which a getter cannot read; keep an `ArgumentError.value`'s name and value in the `GQL302` reason; mark `ExecutableSchema.bindings` `@internal` (adds `meta`); skip the compile fixtures when the suite runs as an AOT executable, which has no `dart` tool; add direct tests for applied directives in the printed SDL and a `Subscription` root.

**Files:**
- Modify: `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`, `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart`, `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, `packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart`, `packages/typed_graphql_server/lib/src/builder/literal_writer.dart`, `packages/typed_graphql_server/lib/src/builder/possible_types.dart`, `packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart`, `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, `packages/typed_graphql_server/pubspec.yaml`, `packages/typed_graphql_server/CHANGELOG.md`, `packages/typed_graphql_server/doc/schema_builder.md`
- Test: `packages/typed_graphql_server/test/builder/assembly_test.dart`, `packages/typed_graphql_server/test/builder/build_errors_test.dart`, `packages/typed_graphql_server/test/builder/fields_test.dart`, `packages/typed_graphql_server/test/compile/compile_failures_test.dart`

**Interfaces:**
- Consumes: Tasks 2-8.
- Produces: no new declaration; the steps change existing code, tests or documents.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_server/test/builder/assembly_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/builder/possible_types.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Box {
  const Box();
}

final class PickyCodec implements ScalarCodec<Box> {
  const PickyCodec();

  @override
  DecodeResult<Box> decode(JsonValue json) => const DecodeSuccess(Box());

  @override
  JsonValue encode(Box value) =>
      throw ArgumentError.value(value, 'box', 'Not writable');
}

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

  ObjectTypeDef<Object?> queryOf(
    List<FieldDef<Object?, Object?>> Function(
      FieldsBuilder<Object?, Object?> t,
    )
    fields,
  ) => b.object<Object?>('Query', fields: fields);

  String sdlOf(ObjectTypeDef<Object?> query) {
    final tag = SchemaDirective(
      'tag',
      locations: const [
        DirectiveLocation.fieldDefinition,
        DirectiveLocation.object,
      ],
    );
    final built = b.build(
      query: query,
      options: BuildOptions(directives: [tag]),
    );
    return const SchemaPrinter().print(built.schema.schema);
  }

  group('default values', () {
    test('a bad default on an inherited interface field is reported once', () {
      final picky = b.scalar<Box>('Picky', const PickyCodec());
      final node = b.interface<Object?>(
        'Node',
        fields: (t) => [
          t
              .field(
                'open',
                b.boolean,
                args: [Arg('box', picky, defaultValue: const Box())],
              )
              .resolve((parent, args, context, info) => true),
        ],
      );
      b.object<Object?>('First', interfaces: [node], fields: (t) => []);
      b.object<Object?>('Second', interfaces: [node], fields: (t) => []);
      final query = queryOf(
        (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(
        problems.where(
          (problem) => problem.code == DiagnosticCode.unencodableDefaultValue,
        ),
        hasLength(1),
      );
    });

    test('the reason keeps the value and name of an ArgumentError.value', () {
      final picky = b.scalar<Box>('Picky', const PickyCodec());
      final query = queryOf(
        (t) => [
          t
              .field(
                'open',
                b.boolean,
                args: [Arg('box', picky, defaultValue: const Box())],
              )
              .resolve((parent, args, context, info) => true),
        ],
      );
      final message = problemsOf(() => b.build(query: query)).single.message;
      expect(message, contains('Not writable'));
      expect(message, contains('"box"'));
      expect(message, contains("Instance of 'Box'"));
    });
  });

  group('directives', () {
    test('withDirectives on a field is printed', () {
      final query = queryOf(
        (t) => [
          t
              .field('ok', b.boolean)
              .withDirectives([AppliedDirective('tag')])
              .pure((_) => true),
        ],
      );
      expect(sdlOf(query), contains('ok: Boolean! @tag'));
    });

    test('ObjectOptions.directives on a type is printed', () {
      final query = b.object<Object?>(
        'Query',
        options: ObjectOptions(directives: [AppliedDirective('tag')]),
        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      expect(sdlOf(query), contains('type Query @tag'));
    });
  });

  group('roots', () {
    test('a Subscription object type becomes the subscription root', () {
      final query = queryOf(
        (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final subscription = b.object<Object?>(
        'Subscription',
        fields: (t) => [t.field('ticks', b.int).pure((_) => 1)],
      );
      final schema = b
          .build(query: query, subscription: subscription)
          .schema
          .schema;
      expect(schema.subscriptionTypeName, 'Subscription');
      expect(schema.typeNamed('Subscription'), isA<ObjectType>());
    });
  });

  group('PossibleTypes', () {
    test('counts the interfaces an object lists, not those they list', () {
      final node = b.interface<Object?>(
        'Node',
        fields: (t) => [t.field('id', b.id).declareOnly()],
      );
      final entity = b.interface<Object?>(
        'Entity',
        interfaces: [node],
        fields: (t) => [t.field('id', b.id).declareOnly()],
      );
      final thing = b.object<Object?>(
        'Thing',
        interfaces: [entity],
        fields: (t) => [t.field('id', b.id).pure((_) => '1')],
      );
      final possible = PossibleTypes(b.definitions);
      expect(possible.of(entity), [thing]);
      expect(possible.of(node), isEmpty);
    });
  });
}
```

In `packages/typed_graphql_server/test/builder/build_errors_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -194,7 +194,7 @@ void main() {
                 b.boolean,
                 args: [Arg('box', box, defaultValue: const Box())],
               )
-              .pure((_) => true),
+              .resolve((parent, args, context, info) => true),
         ],
       );
       final problems = problemsOf(() => b.build(query: query));
@@ -215,7 +215,9 @@ void main() {
       );
       final query = queryWith(
         (t) => [
-          t.field('open', b.boolean, args: [Arg('box', box)]).pure((_) => true),
+          t
+              .field('open', b.boolean, args: [Arg('box', box)])
+              .resolve((parent, args, context, info) => true),
         ],
       );
       final problems = problemsOf(() => b.build(query: query));
```

In `packages/typed_graphql_server/test/builder/fields_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,6 +40,15 @@ void main() {
       expect(lane.read(const User('Ada')), 'Ada');
     });
 
+    test('pure with args is an ArgumentError', () {
+      final stub = FieldsBuilder<User, AppContext>().field(
+        'name',
+        b.string,
+        args: [times],
+      );
+      expect(() => stub.pure((user) => user.name), throwsArgumentError);
+    });
+
     test('pure casts the parent to P', () {
       final field = fieldOf(
         (t) => t.field('name', b.string).pure((user) => user.name),
```

In `packages/typed_graphql_server/test/compile/compile_failures_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -34,10 +34,20 @@ class FixtureCompiler {
 void main() {
   const compiler = FixtureCompiler();
   const timeout = Timeout(Duration(minutes: 3));
+  // Under `--compiler exe` the executable is the test binary, not `dart`.
+  final executable = Platform.resolvedExecutable.split(Platform.pathSeparator);
+  final String? skip = const ['dart', 'dart.exe'].contains(executable.last)
+      ? null
+      : 'needs the dart tool; the VM run covers it';
 
-  test('a correct program compiles', () async {
-    await compiler.compile('ok', isExpected: true);
-  }, timeout: timeout);
+  test(
+    'a correct program compiles',
+    () async {
+      await compiler.compile('ok', isExpected: true);
+    },
+    timeout: timeout,
+    skip: skip,
+  );
 
   const failing = {
     'nullable_for_non_null': "can't be returned from",
@@ -49,9 +59,14 @@ void main() {
         "'Arg<int>' can't be assigned to the parameter type 'Arg<String>'",
   };
   failing.forEach((name, text) {
-    test('$name does not compile', () async {
-      final output = await compiler.compile(name, isExpected: false);
-      expect(output, contains(text));
-    }, timeout: timeout);
+    test(
+      '$name does not compile',
+      () async {
+        final output = await compiler.compile(name, isExpected: false);
+        expect(output, contains(text));
+      },
+      timeout: timeout,
+      skip: skip,
+    );
   });
 }
```

- [ ] **Step 2: Write the implementation**

In `packages/typed_graphql_server/lib/src/builder/builder_checks.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -34,6 +34,7 @@ final class BuilderChecks {
             definition.interfaces,
             definition.isDartSubtypeOf,
           );
+        // `NamedTypeDef` is not sealed, so the switch needs a default.
         default:
       }
     }
```

In `packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -23,7 +23,7 @@ final class const EnumValueMapping<E extends Enum>({
   /// The definition of [value] under this mapping.
   EnumValueDef<E> define(E value) => EnumValueDef(
     value,
-    nameOf == null ? value.name : nameOf!(value),
+    nameOf?.call(value) ?? value.name,
     description: descriptionOf?.call(value),
     deprecationReason: deprecationReasonOf?.call(value),
   );
```

In `packages/typed_graphql_server/lib/src/builder/field_stub.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -60,8 +60,18 @@ final class FieldStub<P, R, C> {
       ]);
 
   /// Completes the field with a synchronous getter (the pure lane, R4.2).
-  FieldDef<P, C> pure(R Function(P parent) read) =>
-      _define(PureLane((parent) => read(parent as P)), _args);
+  ///
+  /// A pure field has no arguments: giving `args` to the field as well is an
+  /// [ArgumentError].
+  FieldDef<P, C> pure(R Function(P parent) read) {
+    if (_args.isNotEmpty) {
+      throw ArgumentError(
+        'Field "$name" gives args and pure; a pure getter reads no '
+        'arguments, use resolve or resolveWith.',
+      );
+    }
+    return _define(PureLane((parent) => read(parent as P)), _args);
+  }
 
   /// Completes the field with a resolver.
   FieldDef<P, C> resolve(
```

In `packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,6 +12,10 @@ final class InputValueAssembler {
 
   final LiteralWriter _literals;
 
+  // An inherited interface field is assembled once per implementing type
+  // with the same Arg; its bad default is reported once.
+  final Set<Arg<Object?>> _reported = Set.identity();
+
   /// The diagnostics found so far; this assembler adds to them.
   final List<Diagnostic> problems;
 
@@ -36,13 +40,16 @@ final class InputValueAssembler {
       // ArgumentError or a StateError; `avoid_catching_errors` forbids naming
       // them, so anything else is rethrown.
       if (error is! ArgumentError && error is! StateError) rethrow;
-      _report(coordinate, _reasonOf(error));
+      if (_reported.add(arg)) _report(coordinate, _reasonOf(error));
     }
     return null;
   }
 
   String _reasonOf(Object error) => switch (error) {
-    ArgumentError(:final message) => '$message',
+    ArgumentError(:final message, :final name, :final invalidValue) =>
+      '$message'
+          '${name == null ? '' : ' (argument "$name")'}'
+          '${invalidValue == null ? '' : ' (value: $invalidValue)'}',
     StateError(:final message) => message,
     _ => '$error',
   };
```

In `packages/typed_graphql_server/lib/src/builder/literal_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,10 +4,14 @@ import 'enum_type_def.dart';
 import 'input_object_def.dart';
 import 'named_type_def.dart';
 
-/// Writes a [JsonValue] as a constant language [Value], as graphql-js's
-/// `astFromValue` does: an enum type gives an enum value, a list a list, an
+/// Writes a [JsonValue] as a constant language [Value], like graphql-js's
+/// `astFromValue`: an enum type gives an enum value, a list a list, an
 /// input object an object, a number an `Int` when it is integral.
 ///
+/// One difference: an `ID` default is always written as a string, where
+/// graphql-js writes an integer-looking one as an `Int`; both coerce to the
+/// same value.
+///
 /// Guided by the language type and the definitions of the named types it
 /// meets. The definitions are used, not the assembled schema types, because
 /// default values are part of the schema types being assembled. Recursion
```

In `packages/typed_graphql_server/lib/src/builder/possible_types.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,18 +8,16 @@ import 'union_type_def.dart';
 final class PossibleTypes {
   /// Collects the possible types of every abstract type in [definitions].
   ///
-  /// An object counts for each interface it lists and for the interfaces
-  /// those list, walked with an explicit stack.
+  /// An object counts for each interface it lists itself, as in graphql-js
+  /// and the core `Schema`; an object must list the interfaces of its
+  /// interfaces too, and the core validator reports one that does not.
   PossibleTypes(Iterable<NamedTypeDef> definitions) {
     for (final definition in definitions) {
       if (definition is! ObjectTypeDef<Object?>) continue;
-      final visited = Set<InterfaceTypeDef<Object?>>.identity();
-      final pending = [...definition.interfaces];
-      while (pending.isNotEmpty) {
-        final next = pending.removeLast();
-        if (!visited.add(next)) continue;
-        (_implementations[next] ??= []).add(definition);
-        pending.addAll(next.interfaces);
+      final listed = Set<InterfaceTypeDef<Object?>>.identity()
+        ..addAll(definition.interfaces);
+      for (final interface in listed) {
+        (_implementations[interface] ??= []).add(definition);
       }
     }
   }
```

In `packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -48,6 +48,7 @@ final class SchemaBindingsAssembler {
           _leaves.putIfAbsent(definition.name, () => definition);
         case InputObjectDef<Object>():
           _inputObjects.putIfAbsent(definition.name, () => definition);
+        // `NamedTypeDef` is not sealed, so the switch needs a default.
         default:
       }
     }
```

In `packages/typed_graphql_server/lib/src/execution/executable_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import 'package:meta/meta.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import 'schema_bindings.dart';
@@ -16,6 +17,7 @@ final class ExecutableSchema<C> {
   /// The validated schema.
   final ValidSchema schema;
 
-  /// The run-time tables the executor reads.
+  /// The run-time tables the executor reads; not part of the public API.
+  @internal
   final SchemaBindings bindings;
 }
```

In `packages/typed_graphql_server/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -10,6 +10,7 @@ environment:
   sdk: ^3.13.0
 
 dependencies:
+  meta: ^1.15.0
   typed_graphql: ^0.0.1
 
 dev_dependencies:
```

Then run `dart pub get` at the repository root (`ulimit -v 8000000; timeout 300 dart pub get`).

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_server && ulimit -v 8000000 && timeout 600 dart test test/builder/assembly_test.dart test/builder/build_errors_test.dart test/builder/fields_test.dart test/compile/compile_failures_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Update the documents**

Append to `packages/typed_graphql_server/CHANGELOG.md`:

```markdown
- A bad default on an interface field argument is reported once (`GQL302`),
  not once per implementing type; the reason keeps the value and name of an
  `ArgumentError.value`.
- An interface counts only the objects that list it themselves as possible
  types, as graphql-js does.
- `pure` on a field that was given `args` is an `ArgumentError`.
```

In `packages/typed_graphql_server/doc/schema_builder.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -15,7 +15,7 @@ works today is declaring, checking and printing a schema.
 Every type you declare, and the five built-in scalars (`b.int`, `b.float`,
 `b.string`, `b.boolean`, `b.id`), is a ref, and a ref carries its Dart type.
 A ref is non-null by default, as a Dart type is: `b.string` is `String!` and
-stands for a Dart `String`. `.nullable` gives `String` and a Dart `String?`.
+stands for a Dart `String`. `.nullable` gives `String` (no `!`) and a Dart `String?`.
 `b.list(item)` is a non-null list of `item`, so `b.list(b.string.nullable)`
 is `[String]!` and `b.list(b.string).nullable` is `[String!]`.
 
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
git add packages/typed_graphql_server/CHANGELOG.md packages/typed_graphql_server/doc/schema_builder.md packages/typed_graphql_server/lib/src/builder/builder_checks.dart packages/typed_graphql_server/lib/src/builder/enum_value_mapping.dart packages/typed_graphql_server/lib/src/builder/field_stub.dart packages/typed_graphql_server/lib/src/builder/input_value_assembler.dart packages/typed_graphql_server/lib/src/builder/literal_writer.dart packages/typed_graphql_server/lib/src/builder/possible_types.dart packages/typed_graphql_server/lib/src/builder/schema_bindings_assembler.dart packages/typed_graphql_server/lib/src/execution/executable_schema.dart packages/typed_graphql_server/pubspec.yaml packages/typed_graphql_server/test/builder/assembly_test.dart packages/typed_graphql_server/test/builder/build_errors_test.dart packages/typed_graphql_server/test/builder/fields_test.dart packages/typed_graphql_server/test/compile/compile_failures_test.dart
git commit -q -m "fix(typed_graphql_server): address the M5a review" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

- The full list, with recommendations, is section 21 of the spec. M5a follows these recommendations: the builder is `ExecutableSchemaBuilder<C>` (question 1), fields are declared in two steps (question 2), and enum values keep `Enum.name` unless `nameOf:` renames them (question 3).
- `GQL301` (found in M5a): it is reported unless both overlapping object types have an explicit `isTypeOf`, and only the first pair per abstract type is reported. The looser alternative is a warning, or no report when either type has `isTypeOf`.
- `Arg.optional` keeps the ref's nullability (found in M5a): `Arg.optional('x', b.string)` is `String!` in the SDL. The guides show `b.string.nullable`. The alternative is to make the ref nullable inside `Arg.optional`.

## Self-review

- Spec coverage: sections 3 (builder), 15 (codes `GQL300`-`GQL302`) and 17 (no transport import, no resolver instantiation) are implemented by Tasks 1-7; section 20's M5a documents by Tasks 8-9; Tasks 10-11 are the review round, kept as their own commits so the plan's code is the code that was verified.
- Every code block is the committed text that passed the green check; no placeholder remains.
- Names are consistent across tasks: `ExecutableSchemaBuilder`, `FieldStub`, `FieldDef`, `ObjectTypeDef`, `InterfaceTypeDef`, `UnionTypeDef`, `InputObjectDef`, `Arg`, `Arguments`, `BuildOptions`, `ExecutableSchema`, `SchemaBindings`, `SchemaBuildError`.

## After the plan

M5b (`2026-10-15-m5b-execution-core.md`) adds input coercion, the executor, error masking and middleware on top of `ExecutableSchema` and `SchemaBindings`. Merging `m5-final` into `main` and pushing need the owner's explicit yes.
