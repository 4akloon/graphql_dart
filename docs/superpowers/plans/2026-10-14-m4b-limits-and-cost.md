# M4b Limits and Cost Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish M4: the opt-in limit rules (`MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule`; `GQL232`–`GQL236`) and `DocumentValidator.recommendedRules`; the IBM draft's `@cost` / `@listSize` as opt-in built-in directives with their schema checks (`GQL156`–`GQL161`); `CostAnalysis`, `SlicingArgumentsRule` (`GQL237`) and `MaxCostRule` (`GQL238`); the operation-validation fuzzers; the guide's Limits and Cost sections (R3.5, R3.8, R0.3, R10.4, R11.1–R11.3).

**Architecture:** The limit rules live in `validation/limits/` and share `SelectionMeasure`, an explicit-stack fold over an operation's selections with every spread expanded, memoised per fragment, combining by sum or maximum per `MeasuredQuantity`. The cost directives follow `includesDeferAndStream` through the schema layer (`includesCostDirectives`), and `SchemaValidator` runs `CostDirectiveRules` / `ListSizeRules` only with the flag. `CostAnalysis` (`validation/cost/`) is const and makes a `CostWalk` per call, with `CostWeights` caches and a fragment memo keyed by fragment and sized context, so it is linear even when fragments expand exponentially. The cost rules use it.

**Tech Stack:** Dart 3.13, `package:test`, `package:meta`. graphql-js 17 in `reference/graphql-js` for `NoSchemaIntrospectionCustomRule` and `MaxIntrospectionDepthRule`; the IBM GraphQL Cost Directives draft (<https://ibm.github.io/graphql-specs/cost-spec.html>) for cost.

**Spec:** `docs/superpowers/specs/2026-10-14-m4-operation-validation-design.md` (sections 4, 10–13, 15), `docs/requirements.md` R3.5 and R3.8.

**Base:** the M4a plan (`2026-10-14-m4a-operation-validation.md`) applied: its twelve tasks on `main` at `1a5c135`. The plan was verified by applying its eight tasks in order after M4a, one commit per task, with the green check after each and the validation and cost-directive tests on exe, dart2js and dart2wasm at the end.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one, examples included.
- Layering (spec section 2): `validation/` imports every lower core layer and nothing else; the core imports no platform library and no package but `meta` (R0.6). `test/quality/layers_test.dart` checks it.
- No new package dependency in this stage.
- Bad input never throws (R0.3): an invalid document is an `InvalidDocument` with diagnostics; only programmer errors throw (`ArgumentError`, `RangeError`, `StateError`).
- **No recursion over a document, a value or a fragment graph.** Every walk uses an explicit stack (a deep structure overflows the stack on the web long before the VM); work that grows faster than the document is charged to the step budget (`ValidationContext.spend`) or memoised per fragment.
- New codes go into `DiagnosticCode` in id order, with a doc comment, in the commit that first reports them.
- Messages are graphql-js's text where graphql-js has the same check, character for character, so the ported suites compare them unchanged.
- Output is deterministic: no hash-ordered collection is iterated for output.
- Public API goes through the barrel `lib/typed_graphql.dart`, each exported type tagged `/// {@category validation}` (`schema` for schema types); internal collaborators stay out of it.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- **Memory and time limits when running the suites.** Run every `dart test`, `dart analyze`, `dart format`, `dart doc` and `dart pub` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time. Chrome cannot start under `ulimit -v`; bound the browser runs by resident memory: `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome …`.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise; use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree the earlier tasks leave; each was applied in that order while the plan was verified. A CHANGELOG change is "Append to". If a hunk does not apply, the tree has drifted: save the diff to a file and apply it with `git apply --3way`; if that fails, stop and report it.
- `reference/` (git-ignored) holds graphql-js and the specifications; fetch it with `tool/fetch_reference.sh` before the conformance tasks. Never `git add` it.

## Review Focus

1. A fragment chain that expands 2^60 times under a limit rule, `MaxIntrospectionDepthRule` or `CostAnalysis`: linear time, saturated counts, no hang. Tasks 1, 2 and 5 (`max_aliases_rule_test.dart`, `max_introspection_depth_rule_test.dart`, `cost_analysis_test.dart`).
2. A huge cost prints the same text on the VM, dart2js and dart2wasm (`1.152921504606847e+18`; JavaScript prints large doubles differently). Task 6, `max_cost_rule_test.dart`.
3. A schema without `includesCostDirectives` behaves exactly as before: `@cost` is an unknown directive and no cost check runs. Tasks 3 and 4 (`cost_directives_test.dart`, `cost_directive_rules_test.dart`).
4. A slicing argument given by a variable, as `null`, or twice. Task 6, `slicing_arguments_rule_test.dart`; the variable's value and default in Task 5.
5. A negative limit, list size or maximum is a programmer error (`RangeError` / `ArgumentError`), not a silent pass. Tasks 1, 5 and 6.

## File map

| File | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/validation/limits/limit_visitor.dart` | The visitor of a limit rule | 1 |
| `packages/typed_graphql/lib/src/validation/limits/max_aliases_rule.dart` | Limits the aliases of an operation (R3.5, `GQL233`) | 1 |
| `packages/typed_graphql/lib/src/validation/limits/max_depth_rule.dart` | Limits the depth of an operation (R3.5, `GQL232`) | 1 |
| `packages/typed_graphql/lib/src/validation/limits/max_directives_rule.dart` | Limits the directives of an operation (R3.5, `GQL234`) | 1 |
| `packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart` | What a limit rule counts in an operation, and how a node contributes to it (R3.5) | 1 |
| `packages/typed_graphql/lib/src/validation/limits/operation_subject.dart` | How the messages of the limit rules name an operation | 1 |
| `packages/typed_graphql/lib/src/validation/limits/selection_measure.dart` | Measures one [MeasuredQuantity] of operations with their fragments expanded, in time linear in the document (R3.5) | 1 |
| `packages/typed_graphql/test/validation/limits/max_aliases_rule_test.dart` | Tests | 1 |
| `packages/typed_graphql/test/validation/limits/max_depth_rule_test.dart` | Tests | 1 |
| `packages/typed_graphql/test/validation/limits/max_directives_rule_test.dart` | Tests | 1 |
| `packages/typed_graphql/lib/src/validation/limits/max_introspection_depth_rule.dart` | Limits the nesting of the lists of the introspection types (R3.5, `GQL236`) | 2 |
| `packages/typed_graphql/lib/src/validation/limits/no_introspection_rule.dart` | Disables introspection (R3.5, `GQL235`) | 2 |
| `packages/typed_graphql/test/validation/limits/max_introspection_depth_rule_test.dart` | Tests | 2 |
| `packages/typed_graphql/test/validation/limits/no_introspection_rule_test.dart` | Tests | 2 |
| `packages/typed_graphql_conformance/test/validation/max_introspection_depth_test.dart` | Tests | 2 |
| `packages/typed_graphql_conformance/test/validation/no_introspection_test.dart` | Tests | 2 |
| `packages/typed_graphql/lib/src/schema/build/cost_directive_sdl.dart` | The SDL of the IBM GraphQL Cost Directives draft's `@cost` and `@listSize` (https://ibm.github.io/graphql-specs/cost-spec.html) | 3 |
| `packages/typed_graphql/test/schema/cost_directives_test.dart` | Tests | 3 |
| `packages/typed_graphql/lib/src/schema/validation/cost_directive_rules.dart` | The IBM cost draft's rules for `@cost` and `@listSize`, run only for a schema that includes the cost directives | 4 |
| `packages/typed_graphql/lib/src/schema/validation/list_size_rules.dart` | The rules of an applied `@listSize` (IBM cost draft) | 4 |
| `packages/typed_graphql/test/schema/validation/cost_directive_rules_test.dart` | Tests | 4 |
| `packages/typed_graphql/lib/src/validation/cost/argument_cost.dart` | The cost of the arguments written on a field or a directive (IBM cost draft) | 5 |
| `packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart` | Computes the static cost of an operation by the IBM cost directives draft (`@cost` and `@listSize` | 5 |
| `packages/typed_graphql/lib/src/validation/cost/cost_walk.dart` | One computation of an operation's cost | 5 |
| `packages/typed_graphql/lib/src/validation/cost/cost_weights.dart` | The `@cost` weights and `@listSize` settings of a schema's elements, each parsed once | 5 |
| `packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart` | The arguments of one applied `@listSize`, read once | 5 |
| `packages/typed_graphql/lib/src/validation/cost/list_sizes.dart` | How many items a field node is assumed to return (IBM cost draft), and which of its children `sizedFields` sizes | 5 |
| `packages/typed_graphql/lib/src/validation/cost/operation_cost.dart` | The static cost of one operation by the IBM cost directives draft | 5 |
| `packages/typed_graphql/lib/src/validation/cost/sized_context.dart` | The size a field's `sizedFields` give to the fields directly in its selection set | 5 |
| `packages/typed_graphql/test/validation/cost/cost_analysis_test.dart` | Tests | 5 |
| `packages/typed_graphql/lib/src/validation/cost/cost_number.dart` | A cost as the messages print it | 6 |
| `packages/typed_graphql/lib/src/validation/cost/max_cost_rule.dart` | Limits the static cost of an operation (R3.5, R3.8, `GQL238`) | 6 |
| `packages/typed_graphql/lib/src/validation/cost/slicing_arguments_rule.dart` | The IBM cost directives draft's operation rule (R3.8, `GQL237`) | 6 |
| `packages/typed_graphql/test/validation/cost/max_cost_rule_test.dart` | Tests | 6 |
| `packages/typed_graphql/test/validation/cost/slicing_arguments_rule_test.dart` | Tests | 6 |
| `packages/typed_graphql_conformance/test/fuzz/hostile_operation_fuzz_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/fuzz/hostile_rules.dart` | The validator the hostile operation fuzzers run | 7 |
| `packages/typed_graphql_conformance/test/fuzz/hostile_shape_fuzz_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/fuzz/random_operation.dart` | Random operations that are valid against a schema by construction (R3.1, R10.4) | 7 |
| `packages/typed_graphql_conformance/test/fuzz/random_valid_schema.dart` | A random schema that is valid by construction, and the SDL it was built from (R10.4) | 7 |
| `packages/typed_graphql_conformance/test/fuzz/valid_operation_fuzz_test.dart` | Tests | 7 |
| `packages/typed_graphql/CHANGELOG.md` | Modified | 1, 2, 3, 4, 5, 6, 8 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modified | 1, 2, 4, 6 |
| `packages/typed_graphql/lib/typed_graphql.dart` | Modified | 1, 2, 5, 6 |
| `packages/typed_graphql/lib/src/validation/document_validator.dart` | Modified | 2 |
| `packages/typed_graphql_conformance/mapping/validation.csv` | Modified | 2 |
| `packages/typed_graphql_conformance/test/mapping_test.dart` | Modified | 2 |
| `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart` | Modified | 2 |
| `packages/typed_graphql/doc/introspection.md` | Modified | 3 |
| `packages/typed_graphql/doc/schema.md` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/build/built_ins.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/build/schema_builder.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/build/unique_definitions.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/print/schema_printer.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/schema.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart` | Modified | 3 |
| `packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart` | Modified | 3 |
| `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart` | Modified | 4 |
| `packages/typed_graphql/test/validation/checked.dart` | Modified | 6 |
| `packages/typed_graphql_conformance/CHANGELOG.md` | Modified | 7 |
| `packages/typed_graphql_conformance/README.md` | Modified | 7 |
| `CLAUDE.md` | Modified | 8 |
| `README.md` | Modified | 8 |
| `docs/superpowers/HANDOFF.md` | Modified | 8 |
| `llms.txt` | Modified | 8 |
| `packages/typed_graphql/README.md` | Modified | 8 |
| `packages/typed_graphql/doc/validation.md` | Modified | 8 |

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

Run a new test file alone first under the same limits. The core suite includes the documentation tests, which run each guide program as a `dart` process. If a run is killed (exit 137) or times out (exit 124), find the cause before going on.

After the last task, also run the core suite on every compiler:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 900 dart test --compiler exe test/validation test/schema)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js test/validation)
(cd packages/typed_graphql && systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm test/validation)
```

---

### Task 1: The depth, alias and directive limit rules

`MaxDepthRule`, `MaxAliasesRule` and `MaxDirectivesRule` (`GQL232`–`GQL234`; spec section 10) over the shared `SelectionMeasure`, `MeasuredQuantity`, `LimitVisitor` and `OperationSubject`.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/limits/limit_visitor.dart`, `packages/typed_graphql/lib/src/validation/limits/max_aliases_rule.dart`, `packages/typed_graphql/lib/src/validation/limits/max_depth_rule.dart`, `packages/typed_graphql/lib/src/validation/limits/max_directives_rule.dart`, `packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart`, `packages/typed_graphql/lib/src/validation/limits/operation_subject.dart`, `packages/typed_graphql/lib/src/validation/limits/selection_measure.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/validation/limits/max_aliases_rule_test.dart`, `packages/typed_graphql/test/validation/limits/max_depth_rule_test.dart`, `packages/typed_graphql/test/validation/limits/max_directives_rule_test.dart`

**Interfaces:**
- Consumes: M4a: `ValidationRule`, `ValidationContext` (`spend`, `fragmentNamed`), `OperationVisitor`, `DocumentValidator`.
- Produces:
- Diagnostic codes: `GQL232`, `GQL233`, `GQL234`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/limits/limit_visitor.dart
abstract base class LimitVisitor(…)
  DiagnosticCode get code
  String message(OperationDefinition operation, int value)
  void checkOperation(OperationDefinition operation)

// validation/limits/max_aliases_rule.dart
final class const MaxAliasesRule
  AstVisitor createVisitor(ValidationContext context)
final class _MaxAliases extends LimitVisitor
  DiagnosticCode get code
  String message(OperationDefinition operation, int value)

// validation/limits/max_depth_rule.dart
final class const MaxDepthRule
  AstVisitor createVisitor(ValidationContext context)
final class _MaxDepth extends LimitVisitor
  DiagnosticCode get code
  String message(OperationDefinition operation, int value)

// validation/limits/max_directives_rule.dart
final class const MaxDirectivesRule
  AstVisitor createVisitor(ValidationContext context)
final class _MaxDirectives extends LimitVisitor
  DiagnosticCode get code
  String message(OperationDefinition operation, int value)

// validation/limits/measured_quantity.dart
enum MeasuredQuantity
  directives
  bool get isAdditive
  int ofSelection(Selection selection)
  int ofFragment(FragmentDefinition fragment)
  int ofOperation(OperationDefinition operation)

// validation/limits/operation_subject.dart
final class OperationSubject(final OperationDefinition operation)
  String get text

// validation/limits/selection_measure.dart
final class SelectionMeasure(…)
  int? measure(OperationDefinition operation)
final class _Frame(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/limits/max_aliases_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text, int maxAliases) =>
      checked.errors(text, [MaxAliasesRule(maxAliases: maxAliases)]);

  test('an operation at the limit is valid', () {
    expect(errors('{ x: b y: b z: a { w: b } }', 4), isEmpty);
  });

  test('an anonymous operation one over reports', () {
    expect(errors('{ x: b y: b z: b }', 2), [
      '1:1 GQL233 The anonymous operation has more than 2 aliases.',
    ]);
  });

  test('a named operation is named in the message', () {
    expect(errors('query Q { x: b y: b }', 1), [
      '1:1 GQL233 The operation "Q" has more than 1 aliases.',
    ]);
  });

  test('a fragment counts once per spread', () {
    const text = '{ ...F ...F } fragment F on Query { x: b }';
    expect(errors(text, 2), isEmpty);
    expect(errors(text, 1), hasLength(1));
  });

  test('a fragment cycle counts its edge as 0', () {
    expect(errors('{ ...F } fragment F on Query { x: b ...F }', 1), isEmpty);
  });

  test('a negative limit is a RangeError', () {
    expect(() => errors('{ b }', -1), throwsRangeError);
  });

  test('two operations report each on its own', () {
    expect(errors('query A { x: b } query B { y: b z: b }', 1), [
      '1:18 GQL233 The operation "B" has more than 1 aliases.',
    ]);
  });

  test('2^60 expansions saturate quickly', () {
    final fragments = [
      for (var index = 0; index < 60; index++)
        'fragment F$index on Query { ...F${index + 1} ...F${index + 1} }',
      'fragment F60 on Query { x: b }',
    ];
    final stopwatch = Stopwatch()..start();
    final result = errors('{ ...F0 } ${fragments.join(' ')}', 10);
    expect(result, [
      '1:1 GQL233 The anonymous operation has more than 10 aliases.',
    ]);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
```

Create `packages/typed_graphql/test/validation/limits/max_depth_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text, int maxDepth) =>
      checked.errors(text, [MaxDepthRule(maxDepth: maxDepth)]);

  test('an operation at the limit is valid', () {
    expect(errors('{ a { a { a { b } } } }', 4), isEmpty);
  });

  test('an anonymous operation one over reports its depth', () {
    expect(errors('{ a { a { a { b } } } }', 3), [
      '1:1 GQL232 The anonymous operation has a depth of 4, more than the '
          'maximum of 3.',
    ]);
  });

  test('a named operation is named in the message', () {
    expect(errors('query Q { a { b } }', 1), [
      '1:1 GQL232 The operation "Q" has a depth of 2, more than the maximum '
          'of 1.',
    ]);
  });

  test('inline fragments add no depth', () {
    expect(errors('{ a { ... on Query { a { b } } } }', 3), isEmpty);
  });

  test('a fragment defined after the operation adds its depth', () {
    expect(errors('{ a { ...F } } fragment F on Query { a { b } }', 2), [
      '1:1 GQL232 The anonymous operation has a depth of 3, more than the '
          'maximum of 2.',
    ]);
  });

  test('a fragment cycle does not hang and its edge adds nothing', () {
    expect(
      errors('{ a { ...F } } fragment F on Query { a { ...F } }', 2),
      isEmpty,
    );
  });

  test('a negative limit is a RangeError', () {
    expect(() => errors('{ b }', -1), throwsRangeError);
  });

  test('two operations report each on its own', () {
    expect(errors('query A { a { a { b } } } query B { a { a { b } } }', 2), [
      '1:1 GQL232 The operation "A" has a depth of 3, more than the maximum '
          'of 2.',
      '1:27 GQL232 The operation "B" has a depth of 3, more than the maximum '
          'of 2.',
    ]);
  });

  test('selections nested 100000 deep measure 100000', () {
    const depth = 100000;
    Selection field = Field(null, const Name('b'));
    for (var level = 1; level < depth; level++) {
      field = Field(null, const Name('a'), selectionSet: SelectionSet([field]));
    }
    final document = Document([
      OperationDefinition(.query, SelectionSet([field])),
    ]);
    List<Diagnostic> run(int limit) => DocumentValidator(
      rules: [MaxDepthRule(maxDepth: limit)],
    ).validate(checked.schema, document).diagnostics;

    expect(run(depth), isEmpty);
    expect(run(depth - 1).single.message, contains('a depth of $depth,'));
  });
}
```

Create `packages/typed_graphql/test/validation/limits/max_directives_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text, int maxDirectives) => checked.errors(text, [
    MaxDirectivesRule(maxDirectives: maxDirectives),
  ]);

  // The operation, a variable definition, a field and an inline fragment
  // have one directive each; the spread adds the two of the fragment.
  const text =
      r'query Q($v: Int = 1 @a) @b { a @c { ... @d { b } ...F } } '
      'fragment F on Query @e { b @f }';

  test('an operation at the limit is valid', () {
    expect(errors(text, 6), isEmpty);
  });

  test('a named operation one over reports', () {
    expect(errors(text, 5), [
      '1:1 GQL234 The operation "Q" has more than 5 directives.',
    ]);
  });

  test('an anonymous operation is named in the message', () {
    expect(errors('{ b @x b @y }', 1), [
      '1:1 GQL234 The anonymous operation has more than 1 directives.',
    ]);
  });

  test('each spread counts its fragment definition directives again', () {
    const twice = '{ ...F @s ...F } fragment F on Query @e { b }';
    expect(errors(twice, 3), isEmpty);
    expect(errors(twice, 2), hasLength(1));
  });

  test('a fragment cycle counts its edge as 0', () {
    expect(errors('{ ...F } fragment F on Query { b @x ...F }', 1), isEmpty);
  });

  test('a negative limit is a RangeError', () {
    expect(() => errors('{ b }', -1), throwsRangeError);
  });

  test('two operations report each on its own', () {
    expect(errors('query A { b @x } query B { b @x b @y }', 1), [
      '1:18 GQL234 The operation "B" has more than 1 directives.',
    ]);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/limits/max_aliases_rule_test.dart test/validation/limits/max_depth_rule_test.dart test/validation/limits/max_directives_rule_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -452,5 +452,17 @@ enum DiagnosticCode(
 
   /// `GQL231`: a problem a custom validation rule reports (R3.6); its
   /// message says what the rule checks.
-  customRuleViolation('GQL231');
+  customRuleViolation('GQL231'),
+
+  /// `GQL232`: an operation whose deepest field, fragments expanded, is
+  /// deeper than the maximum `MaxDepthRule` allows.
+  maxDepthExceeded('GQL232'),
+
+  /// `GQL233`: an operation with more aliased fields, fragments expanded,
+  /// than the maximum `MaxAliasesRule` allows.
+  maxAliasesExceeded('GQL233'),
+
+  /// `GQL234`: an operation with more directives, fragments expanded, than
+  /// the maximum `MaxDirectivesRule` allows.
+  maxDirectivesExceeded('GQL234');
 }
```

Create `packages/typed_graphql/lib/src/validation/limits/limit_visitor.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../rules/operation_visitor.dart';
import '../validation_context.dart';
import 'selection_measure.dart';

/// The visitor of a limit rule: measures each operation and reports it at
/// most once, at the operation, when it is over the limit.
abstract base class LimitVisitor(
  final ValidationContext context,
  final SelectionMeasure measure,
) extends OperationVisitor {
  /// Creates the visitor of a rule that measures with [measure].
  this;

  /// The code of the report.
  DiagnosticCode get code;

  /// The message for [operation], whose measured [value] is over the limit.
  String message(OperationDefinition operation, int value);

  @override
  void checkOperation(OperationDefinition operation) {
    final value = measure.measure(operation);
    if (value != null && value > measure.limit) {
      context.report(code, message(operation, value), [operation]);
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/limits/max_aliases_rule.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'limit_visitor.dart';
import 'operation_subject.dart';
import 'selection_measure.dart';

/// Limits the aliases of an operation (R3.5, `GQL233`).
///
/// Counts the fields written with an alias; each spread counts the aliases
/// of its fragment again. The rule is opt-in: it is not one of the
/// specified rules.
///
/// {@category validation}
final class const MaxAliasesRule({
  /// The most aliases an operation may have.
  required final int maxAliases,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws a [RangeError] when [maxAliases] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    RangeError.checkNotNegative(maxAliases, 'maxAliases');
    return _MaxAliases(
      context,
      SelectionMeasure(context, .aliases, maxAliases),
    );
  }
}

final class _MaxAliases extends LimitVisitor {
  _MaxAliases(super.context, super.measure);

  @override
  DiagnosticCode get code => .maxAliasesExceeded;

  @override
  String message(OperationDefinition operation, int value) =>
      '${OperationSubject(operation).text} has more than ${measure.limit} '
      'aliases.';
}
```

Create `packages/typed_graphql/lib/src/validation/limits/max_depth_rule.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'limit_visitor.dart';
import 'operation_subject.dart';
import 'selection_measure.dart';

/// Limits the depth of an operation (R3.5, `GQL232`).
///
/// A field directly in the operation has depth 1, a field in its selection
/// set depth 2, and so on; inline fragments and fragment spreads add no
/// depth, and a spread counts as if its fragment were written there.
/// Introspection fields count like any field. The rule is opt-in: it is
/// not one of the specified rules.
///
/// {@category validation}
final class const MaxDepthRule({
  /// The deepest field an operation may have.
  required final int maxDepth,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws a [RangeError] when [maxDepth] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    RangeError.checkNotNegative(maxDepth, 'maxDepth');
    return _MaxDepth(context, SelectionMeasure(context, .depth, maxDepth));
  }
}

final class _MaxDepth extends LimitVisitor {
  _MaxDepth(super.context, super.measure);

  @override
  DiagnosticCode get code => .maxDepthExceeded;

  @override
  String message(OperationDefinition operation, int value) =>
      '${OperationSubject(operation).text} has a depth of $value, more than '
      'the maximum of ${measure.limit}.';
}
```

Create `packages/typed_graphql/lib/src/validation/limits/max_directives_rule.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'limit_visitor.dart';
import 'operation_subject.dart';
import 'selection_measure.dart';

/// Limits the directives of an operation (R3.5, `GQL234`).
///
/// Counts the directives on the operation, its variable definitions, its
/// fields, inline fragments and spreads; each spread also counts the
/// directives of its fragment's definition and of its content again. The
/// rule is opt-in: it is not one of the specified rules.
///
/// {@category validation}
final class const MaxDirectivesRule({
  /// The most directives an operation may have.
  required final int maxDirectives,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws a [RangeError] when [maxDirectives] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    RangeError.checkNotNegative(maxDirectives, 'maxDirectives');
    return _MaxDirectives(
      context,
      SelectionMeasure(context, .directives, maxDirectives),
    );
  }
}

final class _MaxDirectives extends LimitVisitor {
  _MaxDirectives(super.context, super.measure);

  @override
  DiagnosticCode get code => .maxDirectivesExceeded;

  @override
  String message(OperationDefinition operation, int value) =>
      '${OperationSubject(operation).text} has more than ${measure.limit} '
      'directives.';
}
```

Create `packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';

/// What a limit rule counts in an operation, and how a node contributes to
/// it (R3.5).
///
/// A node's value is its own contribution plus the combination of its
/// children's values: the sum for a count, the maximum for the depth.
enum MeasuredQuantity {
  /// The nesting of fields; a field adds one level, fragments none.
  depth,

  /// The fields written with an alias.
  aliases,

  /// The directives, wherever they are applied.
  directives;

  /// Whether children combine by sum (a count) rather than by maximum.
  bool get isAdditive => this != depth;

  /// What [selection] adds, not counting what it contains.
  int ofSelection(Selection selection) => switch (this) {
    depth => selection is Field ? 1 : 0,
    aliases => selection is Field && selection.alias != null ? 1 : 0,
    directives => switch (selection) {
      Field(directives: final applied) ||
      FragmentSpread(directives: final applied) ||
      InlineFragment(directives: final applied) => applied.length,
    },
  };

  /// What a spread of [fragment] adds besides its selections: the
  /// directives on its definition.
  int ofFragment(FragmentDefinition fragment) =>
      this == directives ? fragment.directives.length : 0;

  /// What [operation] adds besides its selections: its directives and
  /// those of its variable definitions.
  int ofOperation(OperationDefinition operation) {
    if (this != directives) {
      return 0;
    }
    var total = operation.directives.length;
    for (final definition in operation.variableDefinitions) {
      total += definition.directives.length;
    }
    return total;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/limits/operation_subject.dart`:

```dart
import '../../language/ast/executable_definition.dart';

/// How the messages of the limit rules name an operation.
final class OperationSubject(final OperationDefinition operation) {
  /// Creates the subject of [operation].
  this;

  /// `The operation "Q"`, or `The anonymous operation`.
  String get text => switch (operation.name) {
    final name? => 'The operation "${name.value}"',
    null => 'The anonymous operation',
  };
}
```

Create `packages/typed_graphql/lib/src/validation/limits/selection_measure.dart`:

```dart
import 'dart:math';

import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';
import '../validation_context.dart';
import 'measured_quantity.dart';

/// Measures one [MeasuredQuantity] of operations with their fragments
/// expanded, in time linear in the document (R3.5).
///
/// A fragment's value is computed once and reused by every spread, so a
/// chain of fragments that expands exponentially costs one visit each.
/// The walk uses an explicit stack. A fragment on the stack when it is
/// spread again is a cycle (`NoFragmentCyclesRule` reports it) and counts
/// 0, like an unknown fragment. Counts saturate at one over the [limit]:
/// they cannot overflow and an excess is all a rule needs.
final class SelectionMeasure(
  final ValidationContext context,
  final MeasuredQuantity quantity,

  /// The most the rule allows.
  final int limit,
) {
  /// Creates a measure of [quantity] for a rule with [limit].
  this;

  final Map<String, int> _fragmentValues = {};

  int? get _cap => quantity.isAdditive ? limit + 1 : null;

  /// The value of [operation], or null once the context's step budget is
  /// spent.
  int? measure(OperationDefinition operation) {
    final inProgress = <String>{};
    final stack = [
      _Frame(
        operation.selectionSet.selections,
        quantity.ofOperation(operation),
      ),
    ];
    while (true) {
      final frame = stack.last;
      if (frame.index < frame.selections.length) {
        if (!context.spend(1)) {
          return null;
        }
        final child = _visit(
          frame.selections[frame.index++],
          frame,
          inProgress,
        );
        if (child != null) {
          stack.add(child);
        }
        continue;
      }
      stack.removeLast();
      final value = _add(frame.own, frame.accumulated);
      if (frame.fragmentName case final name?) {
        inProgress.remove(name);
        _fragmentValues[name] = value;
      }
      final passed = _add(frame.spreadOwn, value);
      if (stack.isEmpty) {
        return passed;
      }
      _fold(stack.last, passed);
    }
  }

  // Folds the value of [selection] into [frame] when it is known, else
  // returns the frame that computes it.
  _Frame? _visit(Selection selection, _Frame frame, Set<String> inProgress) {
    final own = quantity.ofSelection(selection);
    switch (selection) {
      case Field(selectionSet: null):
        _fold(frame, own);
      case Field(:final selectionSet?) || InlineFragment(:final selectionSet):
        return _Frame(selectionSet.selections, own);
      case FragmentSpread(:final name):
        final fragment = context.fragmentNamed(name.value);
        final known = _fragmentValues[name.value];
        if (known != null) {
          _fold(frame, _add(own, known));
        } else if (fragment == null || inProgress.contains(name.value)) {
          _fold(frame, own);
        } else {
          inProgress.add(name.value);
          return _Frame(
            fragment.selectionSet.selections,
            quantity.ofFragment(fragment),
            fragmentName: name.value,
            spreadOwn: own,
          );
        }
    }
    return null;
  }

  void _fold(_Frame frame, int value) {
    frame.accumulated = quantity.isAdditive
        ? _add(frame.accumulated, value)
        : max(frame.accumulated, value);
  }

  int _add(int first, int second) {
    final sum = first + second;
    return switch (_cap) {
      final cap? => min(sum, cap),
      null => sum,
    };
  }
}

final class _Frame(
  final List<Selection> selections,
  final int own, {
  final String? fragmentName,
  final int spreadOwn = 0,
}) {
  this;

  int index = 0;
  int accumulated = 0;
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -89,6 +89,9 @@ export 'src/schema/validation/schema_validation_result.dart';
 export 'src/schema/validation/schema_validator.dart';
 export 'src/validation/document_validation_result.dart';
 export 'src/validation/document_validator.dart';
+export 'src/validation/limits/max_aliases_rule.dart';
+export 'src/validation/limits/max_depth_rule.dart';
+export 'src/validation/limits/max_directives_rule.dart';
 export 'src/validation/rules/directives_in_valid_locations_rule.dart';
 export 'src/validation/rules/executable_definitions_rule.dart';
 export 'src/validation/rules/fields_on_correct_type_rule.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/limits/max_aliases_rule_test.dart test/validation/limits/max_depth_rule_test.dart test/validation/limits/max_directives_rule_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `MaxDepthRule`, `MaxAliasesRule` and `MaxDirectivesRule` limit an operation's depth, aliases and directives, fragments expanded (`GQL232`-`GQL234`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/limits/limit_visitor.dart packages/typed_graphql/lib/src/validation/limits/max_aliases_rule.dart packages/typed_graphql/lib/src/validation/limits/max_depth_rule.dart packages/typed_graphql/lib/src/validation/limits/max_directives_rule.dart packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart packages/typed_graphql/lib/src/validation/limits/operation_subject.dart packages/typed_graphql/lib/src/validation/limits/selection_measure.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/limits/max_aliases_rule_test.dart packages/typed_graphql/test/validation/limits/max_depth_rule_test.dart packages/typed_graphql/test/validation/limits/max_directives_rule_test.dart
git commit -q -m "feat(typed_graphql): add the depth, alias and directive limit rules" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: The introspection rules

`NoIntrospectionRule` (`GQL235`) and `MaxIntrospectionDepthRule` (`GQL236`), graphql-js's rules and messages; the depth rule reuses `SelectionMeasure` with `MeasuredQuantity.introspectionLists`, so it is linear. `DocumentValidator.recommendedRules`. The two ported suites; the coverage test now includes every file (the suite reader also reads double-quoted test names, which surfaces three more `skipped` stream rows).

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/limits/max_introspection_depth_rule.dart`, `packages/typed_graphql/lib/src/validation/limits/no_introspection_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart`, `packages/typed_graphql/lib/src/validation/limits/selection_measure.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/limits/max_introspection_depth_rule_test.dart`, `packages/typed_graphql/test/validation/limits/no_introspection_rule_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`, `packages/typed_graphql_conformance/test/validation/max_introspection_depth_test.dart`, `packages/typed_graphql_conformance/test/validation/no_introspection_test.dart`

**Interfaces:**
- Consumes: Task 1 (`SelectionMeasure`, `MeasuredQuantity`).
- Produces:
- Diagnostic codes: `GQL235`, `GQL236`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/limits/max_introspection_depth_rule.dart
final class const MaxIntrospectionDepthRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _MaxIntrospectionDepth(…)
  VisitAction enter(Node node)

// validation/limits/measured_quantity.dart
  introspectionLists
  bool get isAdditive

// validation/limits/no_introspection_rule.dart
final class const NoIntrospectionRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _NoIntrospection(final ValidationContext context)
  VisitAction enter(Node node)

// validation/limits/selection_measure.dart
  int? measure(OperationDefinition operation)
  int? measureSelections(List<Selection> selections,
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/limits/max_introspection_depth_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text) =>
      checked.errors(text, const [MaxIntrospectionDepthRule()]);

  test('the code id is GQL236', () {
    expect(DiagnosticCode.maxIntrospectionDepthExceeded.id, 'GQL236');
  });

  test('two lists deep is valid, three reports at the field', () {
    expect(
      errors('{ __schema { types { fields { type { fields { n } } } } } }'),
      isEmpty,
    );
    expect(
      errors(
        '{ __schema { types { fields { type { interfaces { '
        'possibleTypes { n } } } } } } }',
      ),
      ['1:3 GQL236 Maximum introspection depth exceeded'],
    );
  });

  test('a fragment defined after its use counts', () {
    const text =
        '{ __type(name: "Query") { ...F } } '
        'fragment F on __Type { fields { type { fields { type { '
        'inputFields { n } } } } } }';
    expect(errors(text), ['1:3 GQL236 Maximum introspection depth exceeded']);
  });

  test('a cycle and an unknown fragment count 0', () {
    expect(
      errors(
        '{ __schema { ...F ...Missing } } fragment F on __Schema { ...F }',
      ),
      isEmpty,
    );
  });

  test('a 2^60-expanding fragment chain finishes fast', () {
    final fragments = [
      for (var index = 0; index < 60; index++)
        'fragment F$index on __Type { ...F${index + 1} ...F${index + 1} }',
      'fragment F60 on __Type { fields { fields { fields { n } } } }',
    ];
    final stopwatch = Stopwatch()..start();
    final result = errors(
      '{ __schema { types { ...F0 } } } ${fragments.join(' ')}',
    );
    expect(result, ['1:3 GQL236 Maximum introspection depth exceeded']);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('recommendedRules is the specified rules and this one', () {
    expect(DocumentValidator.recommendedRules, hasLength(31));
    expect(
      DocumentValidator.recommendedRules.last,
      isA<MaxIntrospectionDepthRule>(),
    );
  });
}
```

Create `packages/typed_graphql/test/validation/limits/no_introspection_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('type Query { a: Query b: Int }');

  List<String> errors(String text) =>
      checked.errors(text, const [NoIntrospectionRule()]);

  test('the code id is GQL235', () {
    expect(DiagnosticCode.introspectionDisabled.id, 'GQL235');
  });

  test('__typename stays allowed', () {
    expect(errors('{ __typename a { __typename b } }'), isEmpty);
  });

  test('__schema and the fields below it report', () {
    expect(errors('{ __schema { queryType { name } } }'), [
      '1:3 GQL235 GraphQL introspection has been disabled, but the requested '
          'query contained the field "__schema".',
      '1:14 GQL235 GraphQL introspection has been disabled, but the '
          'requested query contained the field "queryType".',
    ]);
  });

  test('__type reports', () {
    expect(errors('{ __type(name: "Query") { name } }'), hasLength(1));
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -44,8 +44,12 @@ void main() {
     test('ported and adapted rows name a Dart test that exists', () {
       // `name(` and the quoted argument, with any whitespace between: the
       // formatter moves a long name to its own line.
-      RegExp call(String name, String argument) =>
-          RegExp('$name\\(\\s*${RegExp.escape("'$argument'")}');
+      // A name with an apostrophe is written in double quotes.
+      RegExp call(String name, String argument) {
+        final escaped = RegExp.escape(argument);
+        return RegExp('$name\\(\\s*(?:\'$escaped\'|"$escaped")');
+      }
+
       for (final row in table.rows.where((row) => row['status'] != 'skipped')) {
         final file = File('${row['dart_file']}');
         expect(file.existsSync(), isTrue, reason: '$row');
@@ -60,11 +64,6 @@ void main() {
 
   // A row names its graphql-js file relative to `prefix`, under `src/`;
   // `covered` lists the files whose every test must have a row.
-  // The suites of the limit rules, which M4b ports.
-  const waitingForM4b = {
-    'MaxIntrospectionDepthRule-test.ts',
-    'NoSchemaIntrospectionCustomRule-test.ts',
-  };
   final tables = [
     (
       path: 'mapping/language.csv',
@@ -90,7 +89,7 @@ void main() {
       prefix: '',
       covered: [
         for (final file in GraphqlJsSuite.filesIn('validation/__tests__'))
-          if (!waitingForM4b.contains(file)) 'validation/__tests__/$file',
+          'validation/__tests__/$file',
       ],
     ),
   ];
```

In `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,11 +16,9 @@ final class GraphqlJsSuite {
     final tests = <(String, String)>[];
     for (final line in source.split('\n')) {
       final match = _block.firstMatch(line);
-      if (match?.groups([1, 2, 3]) case [
-        final indent?,
-        final kind?,
-        final name?,
-      ]) {
+      final name = match?.group(3) ?? match?.group(4);
+      if (match?.groups([1, 2]) case [final indent?, final kind?]
+          when name != null) {
         groups.removeWhere((group) => group.$1 >= indent.length);
         if (kind == 'describe') {
           groups.add((indent.length, name));
@@ -54,7 +52,10 @@ final class GraphqlJsSuite {
     ]..sort();
   }
 
-  static final RegExp _block = RegExp(r"^(\s*)(describe|it)\('([^']*)'");
+  // A name with an apostrophe is written in double quotes.
+  static final RegExp _block = RegExp(
+    r'''^(\s*)(describe|it)\((?:'([^']*)'|"([^"]*)")''',
+  );
 
   /// Each test as its group path and its name, in file order.
   final List<(String, String)> tests;
```

Create `packages/typed_graphql_conformance/test/validation/max_introspection_depth_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/MaxIntrospectionDepthRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const MaxIntrospectionDepthRule());

  group('Validate: Max introspection nodes rule', () {
    test('default introspection query', () {
      expect(port.errors(const IntrospectionQuery().text), isEmpty);
    });

    test('all options introspection query', () {
      expect(
        port.errors(
          const IntrospectionQuery(
            includesSpecifiedByUrl: true,
            includesDirectiveIsRepeatable: true,
            includesSchemaDescription: true,
            includesInputValueDeprecation: true,
          ).text,
        ),
        isEmpty,
      );
    });

    test('3 flat fields introspection query', () {
      expect(
        port.errors('''
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
    '''),
        isEmpty,
      );
    });

    test('3 fields deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 interfaces deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          interfaces {
            interfaces {
              interfaces {
                name
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 possibleTypes deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          possibleTypes {
            possibleTypes {
              possibleTypes {
                name
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 inputFields deep introspection query from __schema', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          inputFields {
            type {
              inputFields {
                type {
                  inputFields {
                    type {
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query from multiple __schema', () {
      expect(
        port.errors('''
    {
      one: __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      two: __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      three: __schema {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
          'Maximum introspection depth exceeded @ 18:7',
          'Maximum introspection depth exceeded @ 33:7',
        ],
      );
    });

    test('3 fields deep introspection query from __type', () {
      expect(
        port.errors('''
    {
      __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query from multiple __type', () {
      expect(
        port.errors('''
    {
      one: __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      two: __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
      three: __type(name: "Query") {
        types {
          fields {
            type {
              fields {
                type {
                  fields {
                    name
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
          'Maximum introspection depth exceeded @ 18:7',
          'Maximum introspection depth exceeded @ 33:7',
        ],
      );
    });

    test('1 fields deep with 3 fields introspection query', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          fields {
            type {
              oneFields: fields {
                name
              }
              twoFields: fields {
                name
              }
              threeFields: fields {
                name
              }
            }
          }
        }
      }
    }
    '''),
        isEmpty,
      );
    });

    test('3 fields deep from varying parents introspection query', () {
      expect(
        port.errors('''
    {
      __schema {
        types {
          fields {
            type {
              fields {
                type {
                  ofType {
                    fields {
                      name
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query with inline fragments', () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ... on __Type {
            fields {
              type {
                ... on __Type {
                  ofType {
                    fields {
                      type {
                        ... on __Type {
                          fields {
                            name
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep introspection query with fragments', () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ...One
        }
      }
    }

    fragment One on __Type {
      fields {
        type {
          ...Two
        }
      }
    }

    fragment Two on __Type {
      fields {
        type {
          ...Three
        }
      }
    }

    fragment Three on __Type {
      fields {
        name
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 3:7',
        ],
      );
    });

    test('3 fields deep inside inline fragment on query', () {
      expect(
        port.errors('''
    {
      ... {
        __schema { types { fields { type { fields { type { fields { name } } } } } } }
      }
    }
    '''),
        [
          'Maximum introspection depth exceeded @ 4:9',
        ],
      );
    });

    test('opts out if fragment is missing', () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ...Missing
        }
      }
    }
    '''),
        isEmpty,
      );
    });

    test("doesn't infinitely recurse on fragment cycle", () {
      expect(
        port.errors('''
    query test {
      __schema {
        types {
          ...Cycle
        }
      }
    }
    fragment Cycle on __Type {
      ...Cycle
    }
    '''),
        isEmpty,
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/no_introspection_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoIntrospectionRule()).withSchema('''
    type Query {
      someQuery: SomeType
    }

    type SomeType {
      someField: String
      introspectionField: __EnumValue
    }
  ''');

  group('Validate: Prohibit introspection queries', () {
    test('ignores valid fields including __typename', () {
      expect(
        port.errors('''
      {
        someQuery {
          __typename
          someField
        }
      }
    '''),
        isEmpty,
      );
    });

    test('ignores fields not in the schema', () {
      expect(
        port.errors('''
      {
        __introspect
      }
    '''),
        isEmpty,
      );
    });

    test(
      'reports error when a field with an introspection type is requested',
      () {
        expect(
          port.errors('''
      {
        __schema {
          queryType {
            name
          }
        }
      }
    '''),
          [
            'GraphQL introspection has been disabled, but the requested query contained the field "__schema". @ 3:9',
            'GraphQL introspection has been disabled, but the requested query contained the field "queryType". @ 4:11',
          ],
        );
      },
    );

    test('reports error when a field with an introspection type is requested and aliased', () {
      expect(
        port.errors('''
      {
        s: __schema {
          queryType {
            name
          }
        }
      }
      '''),
        [
          'GraphQL introspection has been disabled, but the requested query contained the field "__schema". @ 3:9',
          'GraphQL introspection has been disabled, but the requested query contained the field "queryType". @ 4:11',
        ],
      );
    });

    test('reports error when using a fragment with a field with an introspection type', () {
      expect(
        port.errors('''
      {
        ...QueryFragment
      }

      fragment QueryFragment on Query {
        __schema {
          queryType {
            name
          }
        }
      }
    '''),
        [
          'GraphQL introspection has been disabled, but the requested query contained the field "__schema". @ 7:9',
          'GraphQL introspection has been disabled, but the requested query contained the field "queryType". @ 8:11',
        ],
      );
    });

    test('reports error for non-standard introspection fields', () {
      expect(
        port.errors('''
      {
        someQuery {
          introspectionField
        }
      }
    '''),
        [
          'GraphQL introspection has been disabled, but the requested query contained the field "introspectionField". @ 4:11',
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/limits/max_introspection_depth_rule_test.dart test/validation/limits/no_introspection_rule_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/max_introspection_depth_test.dart test/validation/no_introspection_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -464,5 +464,14 @@ enum DiagnosticCode(
 
   /// `GQL234`: an operation with more directives, fragments expanded, than
   /// the maximum `MaxDirectivesRule` allows.
-  maxDirectivesExceeded('GQL234');
+  maxDirectivesExceeded('GQL234'),
+
+  /// `GQL235`: a field that returns an introspection type, such as
+  /// `__schema`, in a document checked by `NoIntrospectionRule`.
+  introspectionDisabled('GQL235'),
+
+  /// `GQL236`: a `__schema` or `__type` field with a path through three or
+  /// more of `fields`, `interfaces`, `possibleTypes` and `inputFields`,
+  /// fragments expanded (`MaxIntrospectionDepthRule`).
+  maxIntrospectionDepthExceeded('GQL236');
 }
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import '../language/ast/document.dart';
 import '../language/visitor/ast_walker.dart';
 import '../schema/validation/schema_validation_result.dart';
 import 'document_validation_result.dart';
+import 'limits/max_introspection_depth_rule.dart';
 import 'rules/directives_in_valid_locations_rule.dart';
 import 'rules/executable_definitions_rule.dart';
 import 'rules/fields_on_correct_type_rule.dart';
@@ -105,6 +106,16 @@ final class const DocumentValidator({
     UniqueInputFieldNamesRule(),
   ];
 
+  /// [specifiedRules] and [MaxIntrospectionDepthRule], graphql-js's
+  /// `recommendedRules`.
+  ///
+  /// The default of [rules] stays [specifiedRules]; whether it should
+  /// become this list is an open decision.
+  static const List<ValidationRule> recommendedRules = [
+    ...specifiedRules,
+    MaxIntrospectionDepthRule(),
+  ];
+
   /// Validates [document] against [schema]; diagnostics point into
   /// [source] when it is given, the text [document] was parsed from.
   DocumentValidationResult validate(
```

Create `packages/typed_graphql/lib/src/validation/limits/max_introspection_depth_rule.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'selection_measure.dart';

/// Limits the nesting of the lists of the introspection types (R3.5,
/// `GQL236`): below a `__schema` or `__type` field, no path may pass
/// through three fields named `fields`, `interfaces`, `possibleTypes` or
/// `inputFields`, fragments expanded.
///
/// A port of graphql-js's `MaxIntrospectionDepthRule`. Where it walks the
/// fragments again for each path, this rule measures each fragment once, so
/// its time is linear in the document. The error is reported at the
/// `__schema` or `__type` field, whose subtree the rule then skips. The rule
/// is in [DocumentValidator.recommendedRules], not in the specified rules.
///
/// {@category validation}
final class const MaxIntrospectionDepthRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => _MaxIntrospectionDepth(
    context,
    SelectionMeasure(context, .introspectionLists, _maxListsDepth - 1),
  );
}

// graphql-js's MAX_LISTS_DEPTH: a path with this many lists is too deep.
const int _maxListsDepth = 3;

final class _MaxIntrospectionDepth(
  final ValidationContext context,
  final SelectionMeasure measure,
) extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is! Field) {
      return .next;
    }
    final name = node.name.value;
    final selectionSet = node.selectionSet;
    if ((name != '__schema' && name != '__type') || selectionSet == null) {
      return .next;
    }
    final value = measure.measureSelections(selectionSet.selections);
    if (value != null && value > measure.limit) {
      context.report(
        .maxIntrospectionDepthExceeded,
        'Maximum introspection depth exceeded',
        [node],
      );
      return .skip;
    }
    return .next;
  }
}
```

In `packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,14 +14,30 @@ enum MeasuredQuantity {
   aliases,
 
   /// The directives, wherever they are applied.
-  directives;
+  directives,
+
+  /// The fields named `fields`, `interfaces`, `possibleTypes` or
+  /// `inputFields` on a path, as graphql-js's `MaxIntrospectionDepthRule`
+  /// counts them.
+  introspectionLists;
+
+  static const Set<String> _listFieldNames = {
+    'fields',
+    'interfaces',
+    'possibleTypes',
+    'inputFields',
+  };
 
   /// Whether children combine by sum (a count) rather than by maximum.
-  bool get isAdditive => this != depth;
+  bool get isAdditive => this == aliases || this == directives;
 
   /// What [selection] adds, not counting what it contains.
   int ofSelection(Selection selection) => switch (this) {
     depth => selection is Field ? 1 : 0,
+    introspectionLists =>
+      selection is Field && _listFieldNames.contains(selection.name.value)
+          ? 1
+          : 0,
     aliases => selection is Field && selection.alias != null ? 1 : 0,
     directives => switch (selection) {
       Field(directives: final applied) ||
```

Create `packages/typed_graphql/lib/src/validation/limits/no_introspection_rule.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Disables introspection (R3.5, `GQL235`): a field whose named output
/// type is an introspection type, such as `__schema` or `__type`, is an
/// error. `__typename` stays allowed.
///
/// A port of graphql-js's `NoSchemaIntrospectionCustomRule`. Disabling
/// introspection is not a best practice; use it only when it is needed. The
/// rule is opt-in: it is not one of the specified rules.
///
/// {@category validation}
final class const NoIntrospectionRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoIntrospection(context);
}

final class _NoIntrospection(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      final type = context.typeInfo.type;
      // Names starting with "__" are reserved to the introspection types.
      if (type != null &&
          (context.schema.namedTypeOf(type)?.name.startsWith('__') ?? false)) {
        context.report(
          .introspectionDisabled,
          'GraphQL introspection has been disabled, but the requested query '
          'contained the field "${node.name.value}".',
          [node],
        );
      }
    }
    return .next;
  }
}
```

In `packages/typed_graphql/lib/src/validation/limits/selection_measure.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -30,14 +30,19 @@ final class SelectionMeasure(
 
   /// The value of [operation], or null once the context's step budget is
   /// spent.
-  int? measure(OperationDefinition operation) {
+  int? measure(OperationDefinition operation) => measureSelections(
+    operation.selectionSet.selections,
+    own: quantity.ofOperation(operation),
+  );
+
+  /// The value of [selections], fragments expanded, plus [own], or null once
+  /// the context's step budget is spent.
+  ///
+  /// Fragment values are memoised for the life of the measure, so asking
+  /// for the selections of many fields still visits each fragment once.
+  int? measureSelections(List<Selection> selections, {int own = 0}) {
     final inProgress = <String>{};
-    final stack = [
-      _Frame(
-        operation.selectionSet.selections,
-        quantity.ofOperation(operation),
-      ),
-    ];
+    final stack = [_Frame(selections, own)];
     while (true) {
       final frame = stack.last;
       if (frame.index < frame.selections.length) {
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -92,6 +92,8 @@ export 'src/validation/document_validator.dart';
 export 'src/validation/limits/max_aliases_rule.dart';
 export 'src/validation/limits/max_depth_rule.dart';
 export 'src/validation/limits/max_directives_rule.dart';
+export 'src/validation/limits/max_introspection_depth_rule.dart';
+export 'src/validation/limits/no_introspection_rule.dart';
 export 'src/validation/rules/directives_in_valid_locations_rule.dart';
 export 'src/validation/rules/executable_definitions_rule.dart';
 export 'src/validation/rules/fields_on_correct_type_rule.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -671,3 +671,29 @@ validation/__tests__/diagnostics-test.ts,validate diagnostics channel,emits star
 validation/__tests__/diagnostics-test.ts,validate diagnostics channel,emits start and end for a document with validation errors,skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
 validation/__tests__/diagnostics-test.ts,validate diagnostics channel,"emits start, error, and end when validate throws on an invalid schema",skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
 validation/__tests__/diagnostics-test.ts,validate diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
+validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts,Validate: Prohibit introspection queries,ignores valid fields including __typename,ported,test/validation/no_introspection_test.dart,
+validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts,Validate: Prohibit introspection queries,ignores fields not in the schema,ported,test/validation/no_introspection_test.dart,
+validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts,Validate: Prohibit introspection queries,reports error when a field with an introspection type is requested,ported,test/validation/no_introspection_test.dart,
+validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts,Validate: Prohibit introspection queries,reports error when a field with an introspection type is requested and aliased,ported,test/validation/no_introspection_test.dart,
+validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts,Validate: Prohibit introspection queries,reports error when using a fragment with a field with an introspection type,ported,test/validation/no_introspection_test.dart,
+validation/__tests__/NoSchemaIntrospectionCustomRule-test.ts,Validate: Prohibit introspection queries,reports error for non-standard introspection fields,ported,test/validation/no_introspection_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,default introspection query,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,all options introspection query,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 flat fields introspection query,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep introspection query from __schema,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 interfaces deep introspection query from __schema,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 possibleTypes deep introspection query from __schema,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 inputFields deep introspection query from __schema,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep introspection query from multiple __schema,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep introspection query from __type,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep introspection query from multiple __type,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,1 fields deep with 3 fields introspection query,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep from varying parents introspection query,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep introspection query with inline fragments,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep introspection query with fragments,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,3 fields deep inside inline fragment on query,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,opts out if fragment is missing,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/MaxIntrospectionDepthRule-test.ts,Validate: Max introspection nodes rule,doesn't infinitely recurse on fragment cycle,ported,test/validation/max_introspection_depth_test.dart,
+validation/__tests__/StreamDirectiveOnListFieldRule-test.ts,Validate: Stream directive on list field,Doesn't validate other directives on list fields,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/StreamDirectiveOnListFieldRule-test.ts,Validate: Stream directive on list field,Doesn't validate other directives on non-list fields,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/StreamDirectiveOnListFieldRule-test.ts,Validate: Stream directive on list field,Doesn't validate misplaced stream directives,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/limits/max_introspection_depth_rule_test.dart test/validation/limits/no_introspection_rule_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/max_introspection_depth_test.dart test/validation/no_introspection_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `NoIntrospectionRule` (`GQL235`) and `MaxIntrospectionDepthRule` (`GQL236`), graphql-js's introspection rules; the depth rule is linear in the document with fragments expanded.
- `DocumentValidator.recommendedRules`: the specified rules and `MaxIntrospectionDepthRule`.
```

- [ ] **Step 7: Run the documentation checks**

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc && timeout 600 dart doc && rm -rf doc/api)
```

Expected: `All tests passed!`, and `dart doc` prints `Found 0 warnings and 0 errors.`

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/limits/max_introspection_depth_rule.dart packages/typed_graphql/lib/src/validation/limits/measured_quantity.dart packages/typed_graphql/lib/src/validation/limits/no_introspection_rule.dart packages/typed_graphql/lib/src/validation/limits/selection_measure.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/limits/max_introspection_depth_rule_test.dart packages/typed_graphql/test/validation/limits/no_introspection_rule_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/graphql_js_suite.dart packages/typed_graphql_conformance/test/validation/max_introspection_depth_test.dart packages/typed_graphql_conformance/test/validation/no_introspection_test.dart
git commit -q -m "feat(typed_graphql): add the introspection rules" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: The opt-in cost directives

`includesCostDirectives` on `Schema` and `SchemaBuilder`, everywhere `includesDeferAndStream` goes: `@cost` and `@listSize` as opt-in built-ins (`CostDirectiveSdl`), `directiveNamed`, extension, printing with built-ins, the redefinition check, introspection both ways.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/cost_directive_sdl.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/introspection.md`, `packages/typed_graphql/doc/schema.md`, `packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart`, `packages/typed_graphql/lib/src/schema/build/built_ins.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`, `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart`, `packages/typed_graphql/lib/src/schema/build/unique_definitions.dart`, `packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart`, `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart`, `packages/typed_graphql/lib/src/schema/print/schema_printer.dart`, `packages/typed_graphql/lib/src/schema/schema.dart`, `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`
- Test: `packages/typed_graphql/test/schema/cost_directives_test.dart`, `packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart`

**Interfaces:**
- Consumes: M3: `BuiltIns`, `BuiltInSdl`, `SchemaAssembly`, `SchemaPrinter`, `IntrospectionReader` / `IntrospectionWriter`.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// schema/build/built_in_sdl.dart
  String get text

// schema/build/built_ins.dart
  SchemaDirective get cost
  SchemaDirective get listSize

// schema/build/cost_directive_sdl.dart
final class const CostDirectiveSdl()
  String get text
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/schema/cost_directives_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'built.dart';

const _sdl = '''
type Query {
  items(first: Int @cost(weight: "1")): [Item!] @listSize(assumedSize: 10)
}

type Item @cost(weight: "2") {
  id: ID
}
''';

const _builder = SchemaBuilder(includesCostDirectives: true);

void main() {
  test('treats @cost as an unknown directive without the flag', () {
    final schema = Built(_sdl).schema;
    final result = const SchemaValidator().validate(schema);
    expect(result, isA<InvalidSchema>());
    expect(
      (result as InvalidSchema).diagnostics.map((d) => d.code),
      everyElement(DiagnosticCode.unknownDirective),
    );
    expect(schema.directiveNamed('cost'), isNull);
  });

  test('builds and validates a schema with both directives', () {
    final schema = Built(_sdl, builder: _builder).schema;
    expect(schema.includesCostDirectives, isTrue);
    expect(const SchemaValidator().validate(schema), isA<ValidSchema>());
  });

  test('finds the definitions by name only with the flag', () {
    final schema = Schema(includesCostDirectives: true);
    expect(schema.directiveNamed('cost'), isNotNull);
    expect(schema.directiveNamed('listSize')?.arguments, hasLength(4));
    expect(Schema().directiveNamed('listSize'), isNull);
  });

  test('prints the two definitions among the built-ins', () {
    final text = const SchemaPrinter(
      includesBuiltIns: true,
    ).print(Schema(includesCostDirectives: true));
    expect(
      text,
      contains(
        'directive @cost(\n'
        '  """The weight, a decimal number written as a string."""\n'
        '  weight: String!\n'
        ') on ARGUMENT_DEFINITION | ENUM | FIELD_DEFINITION | '
        'INPUT_FIELD_DEFINITION | OBJECT | SCALAR',
      ),
    );
    expect(text, contains('requireOneSlicingArgument: Boolean = true'));
    expect(text, contains(') on FIELD_DEFINITION'));
    expect(
      const SchemaPrinter(includesBuiltIns: true).print(Schema()),
      isNot(contains('@cost')),
    );
  });

  test('rejects a redefined @cost only with the flag', () {
    const sdl = 'directive @cost(weight: String!) on OBJECT';
    expect(Built(sdl).schema.directives.single.name, 'cost');
    expect(Built(sdl, builder: _builder).errors, [
      '1:12 GQL103 The built-in directive "@cost" cannot be redefined.',
    ]);
  });

  test('keeps the flag when extending a schema', () {
    final base = Schema(includesCostDirectives: true);
    final built = Built.extending(base, 'directive @listSize on FIELD');
    expect(built.errors.single, contains('GQL103'));
    expect(built.partial.includesCostDirectives, isTrue);
    final extended = Built.extending(base, 'type Query { a: Int }').schema;
    expect(extended.includesCostDirectives, isTrue);
  });

  test('writes the directives to introspection and reads the flag back', () {
    final schema = Built(_sdl, builder: _builder).schema;
    final json = schema.toIntrospection().toJson();
    final root = json['__schema']! as Map<String, Object?>;
    final directives = (root['directives']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(
      directives.map((directive) => directive['name']),
      containsAll(['cost', 'listSize']),
    );
    final value = switch (const JsonReader().read(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure() => fail('not JSON'),
    };
    final result = const SchemaBuilder().fromIntrospection(value);
    final rebuilt = (result as BuildSuccess).schema;
    expect(rebuilt.includesCostDirectives, isTrue);
    expect(rebuilt.directives, isEmpty);
  });

  test('tells the cost directives as built-ins by the flag', () {
    const builtIns = BuiltIns();
    expect(
      builtIns.isBuiltInDirective(
        'cost',
        includesDeferAndStream: false,
        includesCostDirectives: true,
      ),
      isTrue,
    );
    expect(
      builtIns.isBuiltInDirective('listSize', includesDeferAndStream: true),
      isFalse,
    );
  });
}
```

In `packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,6 +45,7 @@ final class SchemaMapper {
     description: schema.description,
     appliedDirectives: directives(schema),
     includesDeferAndStream: schema.includesDeferAndStream,
+    includesCostDirectives: schema.includesCostDirectives,
   );
 
   SchemaType _type(SchemaType type) => switch (type) {
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/cost_directives_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,9 @@
+import 'cost_directive_sdl.dart';
+
 /// The SDL of the built-in definitions: the definitions of the September2025
 /// spec (Appendix D) with graphql-js 17's descriptions, then `@defer` and
-/// `@stream` as graphql-js defines them.
+/// `@stream` as graphql-js defines them, then the IBM draft's `@cost` and
+/// `@listSize`.
 ///
 /// graphql-js 17 also has working-draft additions (deprecated directives,
 /// fragment variables, `includeDeprecated` on `__Schema.directives`,
@@ -12,8 +15,9 @@ final class const BuiltInSdl() {
   this;
 
   /// The built-in scalars, directives and introspection types, in the
-  /// order of Appendix D, then `@defer` and `@stream`.
-  String get text => _text;
+  /// order of Appendix D, then `@defer`, `@stream`, `@cost` and `@listSize`.
+  /// The last two come from [CostDirectiveSdl].
+  String get text => '$_text${const CostDirectiveSdl().text}';
 
   static const String _text = '''
 """
```

In `packages/typed_graphql/lib/src/schema/build/built_ins.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,7 +12,8 @@ import 'type_reader.dart';
 
 /// The definitions every schema has without declaring them (spec §3.5,
 /// §3.13, §4.5; R2.6): the five scalars, the five directives and the
-/// introspection types, and the opt-in `@defer` and `@stream`.
+/// introspection types, and the opt-in `@defer`, `@stream`, `@cost` and
+/// `@listSize`.
 ///
 /// They are read once from [BuiltInSdl] and have no spans. `Schema` finds
 /// the scalars and directives by name; the SDL printer prints them only
@@ -51,14 +52,25 @@ final class const BuiltIns() {
 
   static final SchemaDirective _stream = _directiveNamed('stream');
 
-  // The five specified directives are all but the two opt-in ones, so the
-  // SDL order of `@defer` and `@stream` cannot swap them.
+  static final SchemaDirective _cost = _directiveNamed('cost');
+
+  static final SchemaDirective _listSize = _directiveNamed('listSize');
+
+  // The five specified directives are all but the opt-in ones, so the SDL
+  // order of the opt-in ones cannot swap them.
   static final List<SchemaDirective> _directives = List.unmodifiable(
     _allDirectives.where(
-      (directive) => directive != _defer && directive != _stream,
+      (directive) => !_optIn.contains(directive),
     ),
   );
 
+  static final Set<SchemaDirective> _optIn = {
+    _defer,
+    _stream,
+    _cost,
+    _listSize,
+  };
+
   static SchemaDirective _directiveNamed(String name) =>
       _allDirectives.singleWhere((directive) => directive.name == name);
 
@@ -79,6 +91,12 @@ final class const BuiltIns() {
   /// `@stream`, added to a schema only by an opt-in.
   SchemaDirective get stream => _stream;
 
+  /// `@cost` of the IBM draft, added to a schema only by an opt-in.
+  SchemaDirective get cost => _cost;
+
+  /// `@listSize` of the IBM draft, added to a schema only by an opt-in.
+  SchemaDirective get listSize => _listSize;
+
   /// `__Schema`, `__Type`, `__TypeKind`, `__Field`, `__InputValue`,
   /// `__EnumValue`, `__Directive` and `__DirectiveLocation`, in that order.
   List<SchemaType> get introspectionTypes => _introspectionTypes;
@@ -116,11 +134,14 @@ final class const BuiltIns() {
   }
 
   /// Whether [name] is a built-in directive: one of [directives], or
-  /// `defer` or `stream` when [includesDeferAndStream].
+  /// `defer` or `stream` when [includesDeferAndStream], `cost` or
+  /// `listSize` when [includesCostDirectives].
   bool isBuiltInDirective(
     String name, {
     required bool includesDeferAndStream,
+    bool includesCostDirectives = false,
   }) =>
       directiveNamed(name) != null ||
-      (includesDeferAndStream && (name == 'defer' || name == 'stream'));
+      (includesDeferAndStream && (name == 'defer' || name == 'stream')) ||
+      (includesCostDirectives && (name == 'cost' || name == 'listSize'));
 }
```

Create `packages/typed_graphql/lib/src/schema/build/cost_directive_sdl.dart`:

```dart
/// The SDL of the IBM GraphQL Cost Directives draft's `@cost` and
/// `@listSize` (https://ibm.github.io/graphql-specs/cost-spec.html).
///
/// Kept apart from `BuiltInSdl` because the draft is not part of the
/// specification: a schema has these directives only by an opt-in.
final class const CostDirectiveSdl() {
  /// Creates the text holder.
  this;

  /// The two directive definitions, led by a blank line.
  String get text => _text;

  static const String _text = '''

"""
The IBM draft's weight of a schema element in a cost analysis.
"""
directive @cost(
  """The weight, a decimal number written as a string."""
  weight: String!
) on ARGUMENT_DEFINITION | ENUM | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | OBJECT | SCALAR

"""
The IBM draft's size hints for a list field in a cost analysis.
"""
directive @listSize(
  """The size assumed for the list when no slicing argument is given."""
  assumedSize: Int

  """Arguments that limit the size of the list."""
  slicingArguments: [String!]

  """Fields of the returned object that are lists limited like the field."""
  sizedFields: [String!]

  """Whether exactly one slicing argument must be given."""
  requireOneSlicingArgument: Boolean = true
) on FIELD_DEFINITION
''';
}
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -28,8 +28,12 @@ final class SchemaAssembly(
   Schema fromSdl(
     DocumentDefinitions definitions, {
     required bool includesDeferAndStream,
+    bool includesCostDirectives = false,
   }) => _apply(
-    Schema(includesDeferAndStream: includesDeferAndStream),
+    Schema(
+      includesDeferAndStream: includesDeferAndStream,
+      includesCostDirectives: includesCostDirectives,
+    ),
     definitions,
     appliesDefaultRoots: definitions.schemas.isEmpty,
   );
@@ -80,6 +84,7 @@ final class SchemaAssembly(
           operation: ?header.rootTypeSpan(operation),
       },
       includesDeferAndStream: base.includesDeferAndStream,
+      includesCostDirectives: base.includesCostDirectives,
       span: header.span,
     );
   }
```

In `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,6 +21,11 @@ final class const SchemaBuilder({
   /// Whether built schemas have `@defer` and `@stream`, which graphql-js
   /// defines and the specification does not yet (R2.6).
   final bool includesDeferAndStream = false,
+
+  /// Whether built schemas have `@cost` and `@listSize` of the IBM GraphQL
+  /// Cost Directives draft, which the specification does not define; an
+  /// opt-in, so that schemas stay portable.
+  final bool includesCostDirectives = false,
 }) {
   /// Creates a builder.
   this;
@@ -34,6 +39,7 @@ final class const SchemaBuilder({
     final schema = SchemaAssembly(report).fromSdl(
       DocumentDefinitions.of(document),
       includesDeferAndStream: includesDeferAndStream,
+      includesCostDirectives: includesCostDirectives,
     );
     return _result(schema, report);
   }
@@ -62,8 +68,9 @@ final class const SchemaBuilder({
   /// message led by the JSON path of the problem; the elements they are
   /// about are left out of the partial schema. Like [fromSdl], it does not
   /// validate: a field of an input type builds, and schema validation
-  /// reports it. Elements have no span; [includesDeferAndStream] does not
-  /// apply, as the result says whether `@defer` and `@stream` exist.
+  /// reports it. Elements have no span; [includesDeferAndStream] and
+  /// [includesCostDirectives] do not apply, as the result says whether those
+  /// directives exist.
   BuildResult fromIntrospection(JsonValue result) {
     final sink = DiagnosticSink();
     final schema = IntrospectionReader(sink).read(result);
```

In `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -54,6 +54,7 @@ final class SchemaDefinitionReader(
           ...elements.appliedAll(extension.directives),
       ],
       includesDeferAndStream: base.includesDeferAndStream,
+      includesCostDirectives: base.includesCostDirectives,
       span:
           base.span ??
           (definition == null ? null : report.spans.of(definition)),
```

In `packages/typed_graphql/lib/src/schema/build/unique_definitions.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -60,6 +60,7 @@ final class UniqueDefinitions(
       if (const BuiltIns().isBuiltInDirective(
         name,
         includesDeferAndStream: base.includesDeferAndStream,
+        includesCostDirectives: base.includesCostDirectives,
       )) {
         report.error(
           .builtInRedefinition,
```

In `packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -17,7 +17,8 @@ import 'type_ref_reader.dart';
 ///
 /// The built-in scalars and introspection types the result lists are the
 /// schema's built-ins, not declared types; so are the built-in directives,
-/// and `@defer` or `@stream` turn on `includesDeferAndStream`. A result
+/// and `@defer` or `@stream` turn on `includesDeferAndStream`, `@cost` or
+/// `@listSize` on `includesCostDirectives`. A result
 /// without `directives` has none declared, as graphql-js reads it.
 final class IntrospectionReader(
   /// Where problems are reported.
@@ -61,6 +62,7 @@ final class IntrospectionReader(
       subscriptionTypeName: subscription,
       description: root.optionalString('description'),
       includesDeferAndStream: directives.any(_isDeferOrStream),
+      includesCostDirectives: directives.any(_isCostDirective),
     );
   }
 
@@ -108,8 +110,12 @@ final class IntrospectionReader(
 
   bool _isBuiltInDirective(SchemaDirective directive) =>
       const BuiltIns().directiveNamed(directive.name) != null ||
-      _isDeferOrStream(directive);
+      _isDeferOrStream(directive) ||
+      _isCostDirective(directive);
 
   bool _isDeferOrStream(SchemaDirective directive) =>
       directive.name == 'defer' || directive.name == 'stream';
+
+  bool _isCostDirective(SchemaDirective directive) =>
+      directive.name == 'cost' || directive.name == 'listSize';
 }
```

In `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -119,6 +119,8 @@ final class IntrospectionWriter(
         ...builtIns.directives,
         builtIns.defer,
         builtIns.stream,
+        builtIns.cost,
+        builtIns.listSize,
       ])
         if (identical(schema.directiveNamed(directive.name), directive))
           directive,
```

In `packages/typed_graphql/lib/src/schema/print/schema_printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,8 +16,8 @@ import 'type_printer.dart';
 /// {@category schema}
 final class const SchemaPrinter({
   /// Whether the built-in directives, scalars and introspection types
-  /// are printed too, around the declared ones; `@defer` and `@stream`
-  /// only when the schema includes them.
+  /// are printed too, around the declared ones; `@defer`, `@stream`,
+  /// `@cost` and `@listSize` only when the schema includes them.
   final bool includesBuiltIns = false,
 }) {
   /// Creates a printer.
@@ -37,6 +37,10 @@ final class const SchemaPrinter({
             _builtIns.defer,
             _builtIns.stream,
           ],
+          if (schema.includesCostDirectives) ...[
+            _builtIns.cost,
+            _builtIns.listSize,
+          ],
         ].map(_types.directive),
       ...schema.directives.map(_types.directive),
       if (includesBuiltIns) ..._builtIns.scalars.map(_types.type),
```

In `packages/typed_graphql/lib/src/schema/schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -47,6 +47,11 @@ final class Schema({
   /// graphql-js defines them; R2.6).
   final bool includesDeferAndStream = false,
 
+  /// Whether `@cost` and `@listSize` of the IBM GraphQL Cost Directives
+  /// draft exist in this schema. They are not in the specification, so they
+  /// are an opt-in and schemas stay portable.
+  final bool includesCostDirectives = false,
+
   /// Where the schema definition was; null without one.
   final SourceSpan? span,
 }) {
@@ -108,6 +113,8 @@ final class Schema({
     return switch (name) {
       'defer' when includesDeferAndStream => builtIns.defer,
       'stream' when includesDeferAndStream => builtIns.stream,
+      'cost' when includesCostDirectives => builtIns.cost,
+      'listSize' when includesCostDirectives => builtIns.listSize,
       _ => builtIns.directiveNamed(name),
     };
   }
```

In `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,6 +56,7 @@ final class DirectiveDefinitionRules(
       if (const BuiltIns().isBuiltInDirective(
         directive.name,
         includesDeferAndStream: schema.includesDeferAndStream,
+        includesCostDirectives: schema.includesCostDirectives,
       )) {
         report.error(
           .builtInRedefinition,
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/cost_directives_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `includesCostDirectives` on `SchemaBuilder` and `Schema`: the IBM draft's `@cost` and `@listSize` as opt-in built-in directives.
```

In `packages/typed_graphql/doc/introspection.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -102,7 +102,8 @@ Where the reader differs from graphql-js's `buildClientSchema`:
   `deprecated`, `specifiedBy`, `oneOf`) is dropped, whatever its definition.
   graphql-js drops built-in types only.
 - A directive named `defer` or `stream` is dropped too and switches on
-  `includesDeferAndStream`, whatever its arguments.
+  `includesDeferAndStream`, whatever its arguments; `cost` or `listSize` does
+  the same for `includesCostDirectives`.
 - Directive deprecation (`isDeprecated` of a directive) is ignored: it is
   working-draft, and the built-in `@deprecated` cannot be applied to a
   directive definition, so keeping it would make the schema invalid.
```

In `packages/typed_graphql/doc/schema.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -97,6 +97,8 @@ Query: object with 2 fields
 
 `SchemaBuilder(includesDeferAndStream: true)` adds `@defer` and `@stream`, which
 graphql-js defines and the specification does not yet.
+`SchemaBuilder(includesCostDirectives: true)` adds `@cost` and `@listSize` of
+the IBM GraphQL Cost Directives draft, an opt-in so that schemas stay portable.
 
 ## Reading a schema
 
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/introspection.md packages/typed_graphql/doc/schema.md packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart packages/typed_graphql/lib/src/schema/build/built_ins.dart packages/typed_graphql/lib/src/schema/build/cost_directive_sdl.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/schema_builder.dart packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart packages/typed_graphql/lib/src/schema/build/unique_definitions.dart packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart packages/typed_graphql/lib/src/schema/print/schema_printer.dart packages/typed_graphql/lib/src/schema/schema.dart packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart packages/typed_graphql/test/schema/cost_directives_test.dart packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart
git commit -q -m "feat(typed_graphql): add the opt-in cost directives" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: The schema checks of the cost directives

`CostDirectiveRules` and `ListSizeRules` in `SchemaValidator`, run only with `includesCostDirectives` (`GQL156`–`GQL161`): weights, `@cost` on interface fields, `@listSize` on a non-list, slicing arguments, sized fields, `assumedSize` conflicts.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/cost_directive_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/list_size_rules.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`
- Test: `packages/typed_graphql/test/schema/validation/cost_directive_rules_test.dart`

**Interfaces:**
- Consumes: Task 3 (`Schema.includesCostDirectives`).
- Produces:
- Diagnostic codes: `GQL156`, `GQL157`, `GQL158`, `GQL159`, `GQL160`, `GQL161`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// schema/validation/cost_directive_rules.dart
final class CostDirectiveRules(…)
  void check()

// schema/validation/list_size_rules.dart
final class ListSizeRules(…)
  void check(String coordinate, SchemaField field)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/schema/validation/cost_directive_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

const _builder = SchemaBuilder(includesCostDirectives: true);

final class const _Checked() {
  this;

  List<String> errors(String sdl, {bool includesCost = true}) {
    final built = Built(
      sdl,
      builder: includesCost ? _builder : const SchemaBuilder(),
    );
    final result = const SchemaValidator().validate(built.schema);
    return switch (result) {
      ValidSchema() => const [],
      InvalidSchema(:final diagnostics) => [
        for (final diagnostic in diagnostics)
          '${diagnostic.span?.location} ${diagnostic.code.id} '
              '${diagnostic.message}',
      ],
    };
  }
}

void main() {
  group('@cost weight', () {
    test('reports a weight that is not a number (GQL156)', () {
      expect(
        const _Checked().errors(
          'type Query {\n  users: Int @cost(weight: "abc")\n}',
        ),
        [
          '2:14 GQL156 The @cost weight "abc" of "Query.users" is not a '
              'number.',
        ],
      );
    });

    test('accepts integer, negative decimal and exponent weights', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int @cost(weight: "1")
  b: Int @cost(weight: "-2.5")
  c(x: Int @cost(weight: "1e3")): Int
}
'''),
        isEmpty,
      );
    });

    test('names an argument and an input field by coordinate', () {
      expect(
        const _Checked().errors('''
type Query {
  a(x: Int @cost(weight: "q")): Int
}

input In {
  f: Int @cost(weight: "z")
}
'''),
        [
          '2:12 GQL156 The @cost weight "q" of "Query.a(x:)" is not a number.',
          '6:10 GQL156 The @cost weight "z" of "In.f" is not a number.',
        ],
      );
    });

    test('names a type and an enum by their name', () {
      expect(
        const _Checked().errors('''
type Query @cost(weight: "x") {
  a: E
}

enum E @cost(weight: "y") {
  A
}
'''),
        [
          '1:12 GQL156 The @cost weight "x" of "Query" is not a number.',
          '5:8 GQL156 The @cost weight "y" of "E" is not a number.',
        ],
      );
    });
  });

  group('@cost placement', () {
    test('reports an interface field (GQL157)', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int
}

interface Node {
  id: ID @cost(weight: "1")
}
'''),
        [
          '6:10 GQL157 @cost cannot be applied to the interface field "Node.id".',
        ],
      );
    });

    test('reports an interface field argument (GQL157)', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int
}

interface Node {
  id(x: Int @cost(weight: "1")): ID
}
'''),
        [
          '6:13 GQL157 @cost cannot be applied to the interface field '
              'argument "Node.id(x:)".',
        ],
      );
    });

    test('accepts a field of an implementing object', () {
      expect(
        const _Checked().errors('''
type Query {
  a: Int
}

interface Node {
  id: ID
}

type User implements Node {
  id: ID @cost(weight: "1")
}
'''),
        isEmpty,
      );
    });
  });

  group('@listSize', () {
    test('reports a field that is not a list (GQL158)', () {
      expect(
        const _Checked().errors(
          'type Query {\n  user: Int @listSize(assumedSize: 1)\n}',
        ),
        [
          '2:13 GQL158 @listSize on "Query.user" requires a list field or '
              'sizedFields.',
        ],
      );
    });

    test('accepts a non-list with valid sizedFields', () {
      expect(
        const _Checked().errors('''
type Query {
  users: Connection @listSize(sizedFields: ["edges"])
}

type Connection {
  edges: [Int!]!
}
'''),
        isEmpty,
      );
    });

    test('reports a slicing argument that is not Int (GQL159)', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: String, last: Int): [Int] @listSize(
    slicingArguments: ["first", "missing", "last"]
  )
}
'''),
        [
          '2:42 GQL159 The slicing argument "first" of @listSize on '
              '"Query.users" is not an Int argument of the field.',
          '2:42 GQL159 The slicing argument "missing" of @listSize on '
              '"Query.users" is not an Int argument of the field.',
        ],
      );
    });

    test('accepts an Int! slicing argument', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int!): [Int] @listSize(slicingArguments: ["first"])
}
'''),
        isEmpty,
      );
    });

    test('reports a sized field that is not a list (GQL160)', () {
      expect(
        const _Checked().errors('''
type Query {
  users: Connection @listSize(sizedFields: ["edges", "count", "nope"])
}

type Connection {
  edges: [Int]
  count: Int
}
'''),
        [
          '2:21 GQL160 The sized field "count" of @listSize on '
              '"Query.users" is not a list field of "Connection".',
          '2:21 GQL160 The sized field "nope" of @listSize on '
              '"Query.users" is not a list field of "Connection".',
        ],
      );
    });

    test('reports assumedSize with slicing arguments (GQL161)', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int): [Int] @listSize(
    assumedSize: 10
    slicingArguments: ["first"]
  )
}
'''),
        [
          '2:28 GQL161 @listSize on "Query.users" gives assumedSize with '
              'slicing arguments, which needs requireOneSlicingArgument: '
              'false and slicing arguments without default values.',
        ],
      );
    });

    test('reports assumedSize when a slicing argument has a default', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int = 5): [Int] @listSize(
    assumedSize: 10
    slicingArguments: ["first"]
    requireOneSlicingArgument: false
  )
}
'''),
        [contains('GQL161')],
      );
    });

    test('accepts assumedSize with requireOneSlicingArgument false', () {
      expect(
        const _Checked().errors('''
type Query {
  users(first: Int): [Int] @listSize(
    assumedSize: 10
    slicingArguments: ["first"]
    requireOneSlicingArgument: false
  )
}
'''),
        isEmpty,
      );
    });
  });

  test('checks nothing without the flag', () {
    expect(
      const _Checked().errors(
        'type Query {\n  a: Int @cost(weight: "abc")\n}',
        includesCost: false,
      ),
      everyElement(contains('GQL1')),
    );
    expect(
      const _Checked()
          .errors(
            'type Query {\n  a: Int @cost(weight: "abc")\n}',
            includesCost: false,
          )
          .join(),
      isNot(contains('GQL156')),
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/cost_directive_rules_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -325,6 +325,33 @@ enum DiagnosticCode(
   /// can read.
   introspectionTypeTooDeep('GQL155'),
 
+  /// `GQL156`: the `weight` of an applied `@cost` that is not a GraphQL
+  /// number (an integer or float literal written as text), reported when
+  /// the schema includes the cost directives (IBM cost draft).
+  invalidCostWeight('GQL156'),
+
+  /// `GQL157`: a `@cost` on a field of an interface or on one of its
+  /// arguments; the draft applies it to the fields of the implementing
+  /// types.
+  misplacedCost('GQL157'),
+
+  /// `GQL158`: a `@listSize` on a field whose type is not a list and that
+  /// names no `sizedFields`.
+  listSizeOnNonList('GQL158'),
+
+  /// `GQL159`: a name in the `slicingArguments` of a `@listSize` that is
+  /// not an argument of type `Int` or `Int!` of the field.
+  invalidSlicingArgument('GQL159'),
+
+  /// `GQL160`: a name in the `sizedFields` of a `@listSize` that is not a
+  /// list field of the field's object or interface return type.
+  invalidSizedField('GQL160'),
+
+  /// `GQL161`: a `@listSize` that gives `assumedSize` together with
+  /// slicing arguments, without `requireOneSlicingArgument: false` and
+  /// slicing arguments that have no default value.
+  conflictingAssumedSize('GQL161'),
+
   /// `GQL200`: a type system definition or extension in a document sent
   /// for execution (spec §5.1.1).
   executableDefinitions('GQL200'),
```

Create `packages/typed_graphql/lib/src/schema/validation/cost_directive_rules.dart`:

```dart
import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'list_size_rules.dart';
import 'validation_report.dart';

/// The IBM cost draft's rules for `@cost` and `@listSize`, run only for a
/// schema that includes the cost directives: a weight is a number, `@cost`
/// stays off interface fields, and `@listSize` is consistent with its
/// field. Types are walked in declaration order, then their fields.
final class CostDirectiveRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  static final RegExp _number = RegExp(
    r'^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$',
  );

  /// Reports the problems of the cost directives applied in the schema.
  void check() {
    for (final type in schema.types) {
      _weights(type.name, type.appliedDirectives);
      switch (type) {
        case ObjectType(:final fields):
          _fields(type, fields, isInterface: false);
        case InterfaceType(:final fields):
          _fields(type, fields, isInterface: true);
        case InputObjectType(:final fields):
          for (final field in fields) {
            _weights('${type.name}.${field.name}', field.appliedDirectives);
          }
        case ScalarType() || UnionType() || EnumType():
          break;
      }
    }
  }

  void _fields(
    SchemaType type,
    List<SchemaField> fields, {
    required bool isInterface,
  }) {
    for (final field in fields) {
      final coordinate = '${type.name}.${field.name}';
      _weights(coordinate, field.appliedDirectives);
      if (isInterface) {
        _misplaced('field', coordinate, field.appliedDirectives);
      }
      ListSizeRules(report, schema).check(coordinate, field);
      for (final argument in field.arguments) {
        _argument(coordinate, argument, isInterface: isInterface);
      }
    }
  }

  void _argument(
    String fieldCoordinate,
    InputValue argument, {
    required bool isInterface,
  }) {
    final coordinate = '$fieldCoordinate(${argument.name}:)';
    _weights(coordinate, argument.appliedDirectives);
    if (isInterface) {
      _misplaced('field argument', coordinate, argument.appliedDirectives);
    }
  }

  void _weights(String coordinate, List<AppliedDirective> directives) {
    for (final directive in directives) {
      if (directive.name != 'cost') {
        continue;
      }
      // A weight of another type is already a GQL124 of the directive.
      if (directive.argument('weight') case StringValue(:final value)
          when !_number.hasMatch(value)) {
        report.error(
          .invalidCostWeight,
          'The @cost weight "$value" of "$coordinate" is not a number.',
          [directive.span],
        );
      }
    }
  }

  void _misplaced(
    String what,
    String coordinate,
    List<AppliedDirective> directives,
  ) {
    for (final directive in directives) {
      if (directive.name == 'cost') {
        report.error(
          .misplacedCost,
          '@cost cannot be applied to the interface $what "$coordinate".',
          [directive.span],
        );
      }
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/list_size_rules.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rules of an applied `@listSize` (IBM cost draft): a list field or
/// `sizedFields`, slicing arguments that are `Int` arguments, sized fields
/// that are list fields, and no `assumedSize` that slicing arguments make
/// ambiguous.
final class ListSizeRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of the `@listSize` applied to [field], whose
  /// schema coordinate is [coordinate].
  void check(String coordinate, SchemaField field) {
    for (final directive in field.appliedDirectives) {
      if (directive.name != 'listSize') {
        continue;
      }
      final sizedFields = _names(directive, 'sizedFields');
      final slicing = _names(directive, 'slicingArguments');
      if (sizedFields.isEmpty && !_isList(field.type)) {
        report.error(
          .listSizeOnNonList,
          '@listSize on "$coordinate" requires a list field or sizedFields.',
          [directive.span],
        );
      }
      _slicing(coordinate, field, directive, slicing);
      _sized(coordinate, field, directive, sizedFields);
      _assumedSize(coordinate, field, directive, slicing);
    }
  }

  void _slicing(
    String coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> names,
  ) {
    for (final name in names) {
      final type = field.argumentNamed(name)?.type;
      if (type == null || !_isInt(type)) {
        report.error(
          .invalidSlicingArgument,
          'The slicing argument "$name" of @listSize on "$coordinate" is '
          'not an Int argument of the field.',
          [directive.span],
        );
      }
    }
  }

  void _sized(
    String coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> names,
  ) {
    if (names.isEmpty) {
      return;
    }
    final returned = schema.namedTypeOf(field.type);
    final fields = switch (returned) {
      ObjectType(:final fields) || InterfaceType(:final fields) => fields,
      _ => const <SchemaField>[],
    };
    for (final name in names) {
      final sized = fields.where((candidate) => candidate.name == name);
      if (sized.isEmpty || !_isList(sized.first.type)) {
        report.error(
          .invalidSizedField,
          'The sized field "$name" of @listSize on "$coordinate" is not a '
          'list field of "${const TypeComparator().namedTypeName(field.type)}".',
          [directive.span],
        );
      }
    }
  }

  void _assumedSize(
    String coordinate,
    SchemaField field,
    AppliedDirective directive,
    List<String> slicing,
  ) {
    if (directive.argument('assumedSize') is! IntValue || slicing.isEmpty) {
      return;
    }
    final isOneRequired = switch (directive.argument(
      'requireOneSlicingArgument',
    )) {
      BooleanValue(value: false) => false,
      _ => true,
    };
    final hasDefault = slicing.any(
      (name) => field.argumentNamed(name)?.defaultValue != null,
    );
    if (isOneRequired || hasDefault) {
      report.error(
        .conflictingAssumedSize,
        '@listSize on "$coordinate" gives assumedSize with slicing '
        'arguments, which needs requireOneSlicingArgument: false and '
        'slicing arguments without default values.',
        [directive.span],
      );
    }
  }

  // An argument that is not a list of strings is a GQL124 already.
  List<String> _names(AppliedDirective directive, String argument) {
    if (directive.argument(argument) case ListValue(:final values)) {
      return [
        for (final value in values)
          if (value case StringValue(:final value)) value,
      ];
    }
    return const [];
  }

  // Loops, not recursion: a wrapper chain can be deep.
  TypeRef _unwrapNonNull(TypeRef type) {
    var current = type;
    while (current is NonNullType) {
      current = current.type;
    }
    return current;
  }

  bool _isList(TypeRef type) => _unwrapNonNull(type) is ListType;

  bool _isInt(TypeRef type) => switch (_unwrapNonNull(type)) {
    NamedType(:final name) => name.value == 'Int',
    _ => false,
  };
}
```

In `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import '../schema.dart';
 import 'applied_directive_rules.dart';
+import 'cost_directive_rules.dart';
 import 'directive_definition_rules.dart';
 import 'root_type_rules.dart';
 import 'schema_validation_result.dart';
@@ -30,6 +31,9 @@ final class const SchemaValidator() {
     ).check(schema.appliedDirectives, .schema);
     DirectiveDefinitionRules(report, schema).check();
     TypeRules(report, schema).check();
+    if (schema.includesCostDirectives) {
+      CostDirectiveRules(report, schema).check();
+    }
     return report.hasErrors
         ? InvalidSchema(schema, report.diagnostics)
         : ValidSchema.assumeValid(schema);
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/cost_directive_rules_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- With `includesCostDirectives`, `SchemaValidator` checks the IBM draft's rules for `@cost` and `@listSize` (`GQL156`-`GQL161`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/cost_directive_rules.dart packages/typed_graphql/lib/src/schema/validation/list_size_rules.dart packages/typed_graphql/lib/src/schema/validation/schema_validator.dart packages/typed_graphql/test/schema/validation/cost_directive_rules_test.dart
git commit -q -m "feat(typed_graphql): check the cost directives of a schema" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Cost analysis

`CostAnalysis` and `OperationCost` (spec section 11) over the internal `CostWalk`, `CostWeights`, `ListSizes`, `ListSizeSetting`, `ArgumentCost` and `SizedContext`.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/cost/argument_cost.dart`, `packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart`, `packages/typed_graphql/lib/src/validation/cost/cost_walk.dart`, `packages/typed_graphql/lib/src/validation/cost/cost_weights.dart`, `packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart`, `packages/typed_graphql/lib/src/validation/cost/list_sizes.dart`, `packages/typed_graphql/lib/src/validation/cost/operation_cost.dart`, `packages/typed_graphql/lib/src/validation/cost/sized_context.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/validation/cost/cost_analysis_test.dart`

**Interfaces:**
- Consumes: Task 3 (the directives); M4a's language walkers and `Schema` accessors.
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/cost/argument_cost.dart
final class ArgumentCost(…)
  double of(

// validation/cost/cost_analysis.dart
final class const CostAnalysis(…)
  OperationCost costOf(

// validation/cost/cost_walk.dart
final class CostWalk(…)
final class _Frame(…)
  void add(double field, double type)

// validation/cost/cost_weights.dart
final class CostWeights(…)
  double ofType(SchemaType type)
  double ofField(SchemaField field)
  double ofInputValue(InputValue value)
  double ofNamedTypeIn(TypeRef type)
  ListSizeSetting? listSizeOf(SchemaField field)

// validation/cost/list_size_setting.dart
final class ListSizeSetting(…)
  static ListSizeSetting? read(List<AppliedDirective> directives)

// validation/cost/list_sizes.dart
final class ListSizes(…)

// validation/cost/operation_cost.dart
final class const OperationCost(…)
  int get hashCode
  String toString()

// validation/cost/sized_context.dart
final class SizedContext(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/cost/cost_analysis_test.dart`:

```dart
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../schema/built.dart';

const _sliced = '''
type Query {
  users(first: Int, last: Int): [User]
    @listSize(slicingArguments: ["first", "last"], requireOneSlicingArgument: false)
}
type User { name: String friends: [User] }
''';

final class _Costs {
  const _Costs();

  OperationCost of(
    String sdl,
    String text, {
    Map<String, JsonValue> variables = const {},
    int defaultListSize = 10,
  }) {
    final schema = Built(
      sdl,
      builder: const SchemaBuilder(includesCostDirectives: true),
    ).schema;
    final document = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(Source(text)).requireDocument();
    final operation = document.definitions
        .whereType<OperationDefinition>()
        .first;
    return CostAnalysis(
      schema,
      defaultListSize: defaultListSize,
    ).costOf(document, operation, variables: variables);
  }
}

const _costs = _Costs();

void main() {
  group('the draft example', () {
    test('costs the fields and the types', () {
      // Fields: users 1 + 5 * (name 0 + friends (1 + 10 * 0)) = 6.
      // Types: Query 1 + 5 * (User 1 + name 0 + 10 * (User 1 + 0)) = 56.
      expect(
        _costs.of(_sliced, '{ users(first: 5) { name friends { name } } }'),
        const OperationCost(6, 56),
      );
    });

    test('takes the larger of two slicing arguments', () {
      // users 1 + 7 * 0 = 1; types 1 + 7 * (1 + 0) = 8.
      expect(
        _costs.of(_sliced, '{ users(first: 2, last: 7) { name } }'),
        const OperationCost(1, 8),
      );
    });
  });

  group('slicing by a variable', () {
    const text = r'query ($n: Int) { users(first: $n) { name } }';

    test('takes the given value', () {
      // Types: 1 + 3 * (1 + 0) = 4.
      expect(
        _costs.of(_sliced, text, variables: {'n': JsonNumber(3)}),
        const OperationCost(1, 4),
      );
    });

    test('takes the default of the variable without a value', () {
      // Types: 1 + 2 * (1 + 0) = 3.
      expect(
        _costs.of(
          _sliced,
          r'query ($n: Int = 2) { users(first: $n) { name } }',
        ),
        const OperationCost(1, 3),
      );
    });

    test('takes the default list size with neither', () {
      // Types: 1 + 10 * (1 + 0) = 11.
      expect(_costs.of(_sliced, text), const OperationCost(1, 11));
    });
  });

  group('list sizes', () {
    test('a slicing argument default is the size', () {
      // items 1 + 4 * 0 = 1; types 1 + 4 * (1 + 0) = 5.
      expect(
        _costs.of(
          'type Query { items(first: Int = 4): [Item] '
              '@listSize(slicingArguments: ["first"]) } type Item { id: ID }',
          '{ items { id } }',
        ),
        const OperationCost(1, 5),
      );
    });

    test('assumedSize is the size without a slicing argument', () {
      // Types: 1 + 7 * (1 + 0) = 8.
      expect(
        _costs.of(
          'type Query { items: [Item] @listSize(assumedSize: 7) } '
              'type Item { id: ID }',
          '{ items { id } }',
        ),
        const OperationCost(1, 8),
      );
    });

    test('a list without @listSize has the default list size', () {
      // Types: 1 + 3 * (1 + 0) = 4, with a default list size of 3.
      expect(
        _costs.of(
          'type Query { items: [Item] } type Item { id: ID }',
          '{ items { id } }',
          defaultListSize: 3,
        ),
        const OperationCost(1, 4),
      );
    });

    group('sizedFields', () {
      const sdl = '''
type Query {
  conn(first: Int): Conn
    @listSize(slicingArguments: ["first"], sizedFields: ["edges"], requireOneSlicingArgument: false)
}
type Conn { edges: [Edge] }
type Edge { node: Leaf }
type Leaf { id: ID }
''';

      test('the listed child has the size, the field has 1', () {
        // node 1 + 1 * 0 = 1; edges 1 + 3 * 1 = 4; conn 1 + 1 * 4 = 5.
        // Types: Query 1 + 1 * (Conn 1 + 3 * (Edge 1 + 1 * (Leaf 1))) = 8.
        expect(
          _costs.of(sdl, '{ conn(first: 3) { edges { node { id } } } }'),
          const OperationCost(5, 8),
        );
      });

      test('a fragment in the field receives the size', () {
        expect(
          _costs.of(
            sdl,
            '{ conn(first: 3) { ...F } } '
            'fragment F on Conn { edges { node { id } } }',
          ),
          const OperationCost(5, 8),
        );
      });
    });
  });

  group('weights', () {
    test('@cost on a field replaces its type weight', () {
      // Fields: 5. Types: Query 1 + 1 * (Int 0) = 1.
      expect(
        _costs.of('type Query { a: Int @cost(weight: "5") }', '{ a }'),
        const OperationCost(5, 1),
      );
    });

    test('@cost on an argument adds to the field', () {
      // Fields: a 0 + argument 3 = 3.
      expect(
        _costs.of(
          'type Query { a(x: Int @cost(weight: "3")): Int }',
          '{ a(x: 1) }',
        ),
        const OperationCost(3, 1),
      );
    });

    group('@cost on an input field', () {
      const sdl = '''
input In { v: Int @cost(weight: "2") w: Int }
type Query { a(l: [In]): Int }
''';

      test('counts each one written, inside a list', () {
        // Argument l (In, 0) + v 2 + w 0 + v 2 = 4.
        expect(
          _costs.of(sdl, '{ a(l: [{v: 1, w: 2}, {v: 3}]) }'),
          const OperationCost(4, 1),
        );
      });

      test('an unknown input field adds nothing', () {
        expect(
          _costs.of(sdl, '{ a(l: [{z: {v: 1}}]) }'),
          const OperationCost(0, 1),
        );
      });

      test('a variable adds nothing', () {
        expect(
          _costs.of(sdl, r'query ($l: [In]) { a(l: $l) }'),
          const OperationCost(0, 1),
        );
      });
    });

    test('@cost on an argument of a directive counts', () {
      expect(
        _costs.of(
          'directive @weigh(n: Int @cost(weight: "4")) on FIELD '
              'type Query { a: Int }',
          '{ a @weigh(n: 1) }',
        ),
        const OperationCost(4, 1),
      );
    });

    test('@cost on an object type is the weight of its fields', () {
      // u 7 + id 0 = 7. Types: 1 + 1 * (7 + 0) = 8.
      expect(
        _costs.of(
          'type Query { u: U } type U @cost(weight: "7") { id: ID }',
          '{ u { id } }',
        ),
        const OperationCost(7, 8),
      );
    });

    test('@cost on an enum', () {
      expect(
        _costs.of(
          'enum E @cost(weight: "4") { A } type Query { e: E }',
          '{ e }',
        ),
        const OperationCost(4, 5),
      );
    });

    test('@cost on a scalar', () {
      expect(
        _costs.of('scalar S @cost(weight: "6") type Query { s: S }', '{ s }'),
        const OperationCost(6, 7),
      );
    });

    test('a negative weight clamps the field at 0', () {
      // a max(0, -5) = 0, b 2.
      expect(
        _costs.of(
          'type Query { a: Int @cost(weight: "-5") b: Int @cost(weight: "2") }',
          '{ a b }',
        ),
        const OperationCost(2, 1),
      );
    });

    test('an interface weighs as its heaviest implementation', () {
      // n 5 + id 0 = 5. Types: 1 + 1 * (5 + 0) = 6.
      expect(
        _costs.of(
          'interface Node { id: ID } '
              'type A implements Node @cost(weight: "3") { id: ID } '
              'type B implements Node @cost(weight: "5") { id: ID } '
              'type Query { n: Node }',
          '{ n { id } }',
        ),
        const OperationCost(5, 6),
      );
    });
  });

  group('selections', () {
    test('meta-fields cost 0 and their selections are not counted', () {
      // users 1 + 1 * 0 = 1; types 1 + 1 * (1 + 0) = 2.
      expect(
        _costs.of(
          _sliced,
          '{ __typename users(first: 1) { __typename name } '
          '__schema { types { name } } }',
        ),
        const OperationCost(1, 2),
      );
    });

    test('a field the parent does not define costs 0', () {
      expect(_costs.of(_sliced, '{ nope { x } }'), const OperationCost(0, 1));
    });

    test('a fragment adds its selections', () {
      // users 1 + 2 * (friends 1 + 10 * 0) = 3. Types: 1 + 2 * (1 + 0 + 10 *
      // (1 + 0)) = 23.
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 2) { ...F } } '
          'fragment F on User { name friends { name } }',
        ),
        const OperationCost(3, 23),
      );
    });

    test('an inline fragment adds its selections', () {
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 2) { ... on User { name friends { name } } } }',
        ),
        const OperationCost(3, 23),
      );
    });

    test('a fragment spread twice counts twice', () {
      // users 1 + 2 * (1 + 1) = 5. Types: 1 + 2 * (1 + 10 + 10) = 43.
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 2) { ...F ...F } } '
          'fragment F on User { friends { name } }',
        ),
        const OperationCost(5, 43),
      );
    });

    test('a fragment cycle counts its repeat as 0', () {
      // users 1 + 1 * (friends 1 + 10 * 0) = 2. Types: 1 + 1 * (1 + 10 *
      // (1 + 0)) = 12.
      expect(
        _costs.of(
          _sliced,
          '{ users(first: 1) { ...F } } '
          'fragment F on User { friends { ...F } }',
        ),
        const OperationCost(2, 12),
      );
    });
  });

  group('hostile documents', () {
    test('a fragment chain that expands 2^60 times is linear', () {
      final fragments = StringBuffer('fragment F0 on Query { a }');
      for (var level = 1; level <= 60; level++) {
        fragments.write(
          ' fragment F$level on Query { ...F${level - 1} ...F${level - 1} }',
        );
      }
      final cost = _costs.of(
        'type Query { a: Query }',
        '{ ...F60 } $fragments',
      );
      expect(cost.fieldCost, pow(2, 60).toDouble());
      expect(cost.typeCost, pow(2, 60).toDouble());
    });

    test('a nesting of 100000 fields does not overflow the stack', () {
      final schema = Built(
        'type Query { a: Query }',
        builder: const SchemaBuilder(includesCostDirectives: true),
      ).schema;
      var selection = Field(null, const Name('a'));
      for (var depth = 1; depth < 100000; depth++) {
        selection = Field(
          null,
          const Name('a'),
          selectionSet: SelectionSet([selection]),
        );
      }
      final operation = OperationDefinition(
        .query,
        SelectionSet([selection]),
      );
      final cost = CostAnalysis(
        schema,
      ).costOf(Document([operation]), operation);
      expect(cost, const OperationCost(100000, 100001));
    });
  });

  test('a negative default list size is a RangeError', () {
    expect(
      () => _costs.of(_sliced, '{ users { name } }', defaultListSize: -1),
      throwsRangeError,
    );
  });

  group('OperationCost', () {
    test('equal costs are equal and hash alike', () {
      expect(const OperationCost(1, 2), const OperationCost(1, 2));
      expect(
        const OperationCost(1, 2).hashCode,
        const OperationCost(1, 2).hashCode,
      );
    });

    test('different costs differ', () {
      expect(
        const OperationCost(1, 2),
        isNot(const OperationCost(1, 3)),
      );
    });

    test('prints both numbers', () {
      expect(
        const OperationCost(6, 56).toString(),
        'OperationCost(fieldCost: 6.0, typeCost: 56.0)',
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/cost/cost_analysis_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/validation/cost/argument_cost.dart`:

```dart
import '../../language/ast/argument.dart';
import '../../language/ast/value.dart';
import '../../schema/model/input_value.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import 'cost_weights.dart';

/// The cost of the arguments written on a field or a directive (IBM cost
/// draft): the weight of each argument given plus the weight of each input
/// field written in its value.
final class ArgumentCost(
  /// The schema that defines the arguments.
  final Schema schema,

  /// The weights of its elements.
  final CostWeights weights,
) {
  /// Creates the calculation.
  this;

  /// The cost of [arguments], whose definitions [definitionNamed] finds.
  ///
  /// An argument or input field the schema does not define adds 0, and so
  /// does everything written inside an unknown input field. A variable adds
  /// only its argument's weight. The value is walked with a stack, because
  /// a value can be nested very deeply.
  double of(
    List<Argument> arguments,
    InputValue? Function(String name) definitionNamed,
  ) {
    var total = 0.0;
    for (final argument in arguments) {
      if (definitionNamed(argument.name.value) case final definition?) {
        total += weights.ofInputValue(definition);
        total += _inside(
          argument.value,
          schema.namedTypeOf(definition.type),
        );
      }
    }
    return total;
  }

  double _inside(Value value, SchemaType? type) {
    var total = 0.0;
    final stack = [(value, type)];
    while (stack.isNotEmpty) {
      final (current, currentType) = stack.removeLast();
      switch (current) {
        case ListValue(:final values):
          stack.addAll([for (final item in values) (item, currentType)]);
        case ObjectValue(:final fields) when currentType is InputObjectType:
          for (final field in fields) {
            if (currentType.fieldNamed(field.name.value) case final input?) {
              total += weights.ofInputValue(input);
              stack.add((field.value, schema.namedTypeOf(input.type)));
            }
          }
        default:
          break;
      }
    }
    return total;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart`:

```dart
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/value.dart';
import '../../protocol/json_value.dart';
import '../../schema/schema.dart';
import 'cost_walk.dart';
import 'cost_weights.dart';
import 'list_sizes.dart';
import 'operation_cost.dart';

/// Computes the static cost of an operation by the IBM cost directives draft
/// (`@cost` and `@listSize`; R3.8).
///
/// The schema need not include the cost directives: without them every
/// weight is its default. A weight that is not a number counts as the
/// default too (the schema check reports it).
///
/// - The **type weight** of a named type is its `@cost` weight, else 1 for
///   an object and 0 for a scalar or an enum. An interface or a union weighs
///   as its heaviest possible type, the draft's upper bound. An input object
///   weighs 0.
/// - The **field weight** is the field definition's `@cost` weight, else the
///   type weight of its named return type.
/// - The **argument cost** of a field is, for each argument given, the
///   argument definition's `@cost` weight, else the type weight of its
///   named input type, plus the weight of each input field written in its
///   value (inside lists too, at any depth) the same way. A variable adds
///   nothing beyond its argument. Unknown arguments and input fields add 0.
/// - The **directive cost** of a field is the argument cost of each
///   directive applied to it.
/// - The **raw cost** of a field is its field weight plus its argument cost
///   plus its directive cost, but never below 0: a negative weight lowers
///   the cost only down to 0.
/// - The **list size** of a field whose type is a list (ignoring non-null)
///   is the largest slicing argument given: an `Int` literal, or a
///   variable's value in `variables`, else its default in the operation,
///   else `defaultListSize`; a `null` is ignored. With none given, it is
///   the largest default value of a slicing argument, else `assumedSize`,
///   else `defaultListSize`. A list field without `@listSize` has
///   `defaultListSize`; any other field has 1. When `@listSize` has
///   `sizedFields`, the field itself has size 1 and the size above is the
///   size of each child, fragments included, whose name is listed.
/// - The **field cost** of a selection set is the sum over its fields of
///   the raw cost plus the size times the field cost of the field's own
///   selection set. Inline fragments and spreads add the cost of their
///   selections to the enclosing set, an upper bound: fragments on
///   different possible types all count.
/// - The **type cost** of a selection set is the sum over its fields of the
///   size times the type weight of the field's named type plus the type
///   cost of its selection set. The operation's type cost adds its root
///   type's weight.
///
/// The meta-fields `__typename`, `__schema` and `__type` cost 0 and their
/// selections are not counted; nor are a field its parent type does not
/// define and its selections.
///
/// The cost is computed in time linear in the document, however often
/// fragments are spread, and without recursion. A fragment spread inside
/// itself counts 0, like an unknown fragment.
///
/// {@category validation}
final class const CostAnalysis(
  /// The schema the operations are written against.
  final Schema schema, {

  /// The size of a list field the schema gives no size.
  final int defaultListSize = 10,
}) {
  /// Creates the analysis of operations against [schema].
  this;

  /// The cost of [operation], an operation of [document], given the values
  /// of its [variables].
  ///
  /// Throws a [RangeError] when [defaultListSize] is negative.
  OperationCost costOf(
    Document document,
    OperationDefinition operation, {
    Map<String, JsonValue> variables = const {},
  }) {
    RangeError.checkNotNegative(defaultListSize, 'defaultListSize');
    final weights = CostWeights(schema);
    final walk = CostWalk(
      schema,
      weights,
      ListSizes(weights, defaultListSize, variables, _defaults(operation)),
      {
        for (final definition in document.definitions)
          if (definition case FragmentDefinition(:final name))
            name.value: definition,
      },
    );
    final (:fieldCost, :typeCost) = walk.cost(operation);
    return OperationCost(fieldCost, typeCost);
  }

  Map<String, Value> _defaults(OperationDefinition operation) => {
    for (final definition in operation.variableDefinitions)
      definition.variable.name.value: ?definition.defaultValue,
  };
}
```

Create `packages/typed_graphql/lib/src/validation/cost/cost_walk.dart`:

```dart
import 'dart:math';

import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import '../meta_fields.dart';
import 'argument_cost.dart';
import 'cost_weights.dart';
import 'list_sizes.dart';
import 'sized_context.dart';

/// One computation of an operation's cost: walks the selections with an
/// explicit stack and memoises each fragment.
///
/// A fragment's cost depends only on the fragment and the [SizedContext] in
/// effect where it is spread, so it is computed once per pair and a chain of
/// fragments that expands exponentially costs one visit each. A fragment on
/// the stack when it is spread again is a cycle and counts 0, like an unknown
/// fragment. The costs are sums and products of doubles: they cannot
/// overflow an integer.
final class CostWalk(
  /// The schema.
  final Schema schema,

  /// The weights.
  final CostWeights weights,

  /// The list sizes.
  final ListSizes sizes,

  /// The fragments of the document by name; the last definition wins.
  final Map<String, FragmentDefinition> fragments,
) {
  /// Creates a walk.
  this;

  final Map<String, ({double fieldCost, double typeCost})> _memo = {};
  late final ArgumentCost _arguments = ArgumentCost(schema, weights);

  /// The field cost and the type cost of [operation].
  ({double fieldCost, double typeCost}) cost(OperationDefinition operation) {
    final rootName = schema.rootTypeName(operation.operation);
    final root = rootName == null ? null : schema.typeNamed(rootName);
    if (root == null) {
      return (fieldCost: 0.0, typeCost: 0.0);
    }
    final selections = _selectionsCost(operation.selectionSet.selections, root);
    return (
      fieldCost: selections.fieldCost,
      typeCost: weights.ofType(root) + selections.typeCost,
    );
  }

  ({double fieldCost, double typeCost}) _selectionsCost(
    List<Selection> selections,
    SchemaType root,
  ) {
    final inProgress = <String>{};
    final stack = [_Frame(selections, root, null)];
    while (true) {
      final frame = stack.last;
      if (frame.index < frame.selections.length) {
        final child = _visit(
          frame.selections[frame.index++],
          frame,
          inProgress,
        );
        if (child != null) {
          stack.add(child);
        }
        continue;
      }
      stack.removeLast();
      if (frame.fragmentName case final name?) {
        inProgress.remove(name);
        _memo['$name|${frame.sized?.key}'] = (
          fieldCost: frame.fieldCost,
          typeCost: frame.typeCost,
        );
      }
      if (stack.isEmpty) {
        return (fieldCost: frame.fieldCost, typeCost: frame.typeCost);
      }
      stack.last.add(
        frame.rawCost + frame.multiplier * frame.fieldCost,
        frame.multiplier * (frame.typeWeight + frame.typeCost),
      );
    }
  }

  // Adds the cost of [selection] to [frame] when it needs no walk, else
  // returns the frame that computes it.
  _Frame? _visit(Selection selection, _Frame frame, Set<String> inProgress) {
    switch (selection) {
      case Field():
        return _field(selection, frame);
      case InlineFragment(:final typeCondition, :final selectionSet):
        final parent = switch (typeCondition) {
          final condition? => schema.typeNamed(condition.name.value),
          null => frame.parentType,
        };
        return _Frame(selectionSet.selections, parent, frame.sized);
      case FragmentSpread(:final name):
        return _spread(name.value, frame, inProgress);
    }
  }

  _Frame? _spread(String name, _Frame frame, Set<String> inProgress) {
    final fragment = fragments[name];
    if (fragment == null || inProgress.contains(name)) {
      return null;
    }
    if (_memo['$name|${frame.sized?.key}'] case final known?) {
      frame.add(known.fieldCost, known.typeCost);
      return null;
    }
    inProgress.add(name);
    return _Frame(
      fragment.selectionSet.selections,
      schema.typeNamed(fragment.typeCondition.name.value),
      frame.sized,
      fragmentName: name,
    );
  }

  _Frame? _field(Field node, _Frame frame) {
    final definition = _definitionOf(node, frame.parentType);
    if (definition == null) {
      return null;
    }
    final raw = max<double>(
      0,
      weights.ofField(definition) +
          _arguments.of(node.arguments, definition.argumentNamed) +
          _directives(node),
    );
    final size = sizes.of(node, definition, frame.sized);
    final typeWeight = weights.ofNamedTypeIn(definition.type);
    final named = schema.namedTypeOf(definition.type);
    final selectionSet = node.selectionSet;
    if (selectionSet == null || named == null) {
      frame.add(raw, size.size * typeWeight);
      return null;
    }
    return _Frame(
      selectionSet.selections,
      named,
      size.childContext,
      rawCost: raw,
      typeWeight: typeWeight,
      multiplier: size.size,
    );
  }

  // A meta-field is free and so is a field the parent does not define.
  SchemaField? _definitionOf(Field node, SchemaType? parent) {
    final name = node.name.value;
    if (parent == null || name.startsWith('__')) {
      return null;
    }
    return MetaFields.fieldOf(schema, parent, name);
  }

  double _directives(Field node) {
    var total = 0.0;
    for (final directive in node.directives) {
      if (schema.directiveNamed(directive.name.value) case final definition?) {
        total += _arguments.of(directive.arguments, definition.argumentNamed);
      }
    }
    return total;
  }
}

// A selection set being summed. When it is popped, its sum goes to the frame
// below as `rawCost + multiplier * fieldCost` and `multiplier * (typeWeight +
// typeCost)`: a field's own cost and the size of its list.
final class _Frame(
  final List<Selection> selections,
  final SchemaType? parentType,
  final SizedContext? sized, {
  final String? fragmentName,
  final double rawCost = 0,
  final double typeWeight = 0,
  final double multiplier = 1,
}) {
  this;

  int index = 0;
  double fieldCost = 0;
  double typeCost = 0;

  void add(double field, double type) {
    fieldCost += field;
    typeCost += type;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/cost/cost_weights.dart`:

```dart
import 'dart:math';

import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../schema/model/applied_directive.dart';
import '../../schema/model/input_value.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import 'list_size_setting.dart';

/// The `@cost` weights and `@listSize` settings of a schema's elements, each
/// parsed once.
///
/// Elements compare by identity, so a map keyed by element is a cache. A
/// weight that is not a finite number is the element's default weight: the
/// schema check reports it.
final class CostWeights(
  /// The schema whose elements are weighed.
  final Schema schema,
) {
  /// Creates empty caches for [schema].
  this;

  final Map<Object, double> _weights = {};
  final Map<SchemaField, ListSizeSetting?> _settings = {};

  /// The weight of [type].
  double ofType(SchemaType type) {
    if (_weights[type] case final known?) {
      return known;
    }
    final weight = switch (type) {
      ObjectType() => _declared(type.appliedDirectives) ?? 1.0,
      ScalarType() || EnumType() => _declared(type.appliedDirectives) ?? 0.0,
      InterfaceType() || UnionType() => _heaviest(type),
      InputObjectType() => 0.0,
    };
    return _weights[type] = weight;
  }

  /// The weight of [field]: its `@cost`, else its returned type's weight.
  double ofField(SchemaField field) =>
      _ofElement(field, field.appliedDirectives, field.type);

  /// The weight of an argument or input field.
  double ofInputValue(InputValue value) =>
      _ofElement(value, value.appliedDirectives, value.type);

  /// The weight of the named type [type] wraps; 0 when it is unknown.
  double ofNamedTypeIn(TypeRef type) => switch (schema.namedTypeOf(type)) {
    final named? => ofType(named),
    null => 0.0,
  };

  /// The `@listSize` of [field]; null when it has none.
  ListSizeSetting? listSizeOf(SchemaField field) {
    if (_settings.containsKey(field)) {
      return _settings[field];
    }
    return _settings[field] = ListSizeSetting.read(field.appliedDirectives);
  }

  double _ofElement(
    Object element,
    List<AppliedDirective> directives,
    TypeRef type,
  ) {
    if (_weights[element] case final known?) {
      return known;
    }
    return _weights[element] = _declared(directives) ?? ofNamedTypeIn(type);
  }

  // The draft's upper bound: an abstract type weighs as its heaviest
  // possible type.
  double _heaviest(SchemaType type) {
    var heaviest = 0.0;
    for (final possible in schema.possibleTypes(type)) {
      heaviest = max(heaviest, ofType(possible));
    }
    return heaviest;
  }

  double? _declared(List<AppliedDirective> directives) {
    for (final directive in directives) {
      if (directive.name == 'cost') {
        final weight = switch (directive.argument('weight')) {
          StringValue(:final value) => double.tryParse(value),
          _ => null,
        };
        return weight != null && weight.isFinite ? weight : null;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart`:

```dart
import '../../language/ast/value.dart';
import '../../schema/model/applied_directive.dart';

/// The arguments of one applied `@listSize`, read once.
final class ListSizeSetting(
  /// The `assumedSize`, if any.
  final double? assumedSize,

  /// The names of the `slicingArguments`.
  final List<String> slicingArguments,

  /// The names of the `sizedFields`.
  final List<String> sizedFields,
) {
  /// Creates a setting.
  this;

  /// The setting of the first `@listSize` in [directives]; null when there
  /// is none. A malformed argument counts as absent: the schema check
  /// reports it.
  static ListSizeSetting? read(List<AppliedDirective> directives) {
    for (final directive in directives) {
      if (directive.name == 'listSize') {
        return ListSizeSetting(
          switch (directive.argument('assumedSize')) {
            IntValue(:final value) => double.tryParse(value),
            _ => null,
          },
          _names(directive, 'slicingArguments'),
          _names(directive, 'sizedFields'),
        );
      }
    }
    return null;
  }

  static List<String> _names(AppliedDirective directive, String argument) {
    if (directive.argument(argument) case ListValue(:final values)) {
      return [
        for (final value in values)
          if (value case StringValue(:final value)) value,
      ];
    }
    return const [];
  }
}
```

Create `packages/typed_graphql/lib/src/validation/cost/list_sizes.dart`:

```dart
import 'dart:math';

import '../../language/ast/selection.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../protocol/json_value.dart';
import '../../schema/model/schema_field.dart';
import 'cost_weights.dart';
import 'list_size_setting.dart';
import 'sized_context.dart';

/// How many items a field node is assumed to return (IBM cost draft), and
/// which of its children `sizedFields` sizes.
final class ListSizes(
  /// The weights and `@listSize` settings.
  final CostWeights weights,

  /// The size of a list field the schema says nothing about.
  final int defaultListSize,

  /// The values of the operation's variables.
  final Map<String, JsonValue> variables,

  /// The default value of each variable that has one.
  final Map<String, Value> variableDefaults,
) {
  /// Creates the calculation.
  this;

  /// The size of [node], a use of [definition], inside [sized], and the
  /// context it gives its own selection set (null when `@listSize` has no
  /// `sizedFields`).
  ///
  /// A field with `sizedFields` has size 1 and passes the size it would
  /// have to the children named; a field that its parent sized takes that
  /// size.
  ({double size, SizedContext? childContext}) of(
    Field node,
    SchemaField definition,
    SizedContext? sized,
  ) {
    final setting = weights.listSizeOf(definition);
    final computed = _computed(node, definition, setting);
    if (setting != null && setting.sizedFields.isNotEmpty) {
      return (
        size: 1.0,
        childContext: SizedContext({...setting.sizedFields}, computed),
      );
    }
    if (sized != null && sized.names.contains(node.name.value)) {
      return (size: sized.size, childContext: null);
    }
    return (size: computed, childContext: null);
  }

  double _computed(
    Field node,
    SchemaField definition,
    ListSizeSetting? setting,
  ) {
    final isList = _unwrapNonNull(definition.type) is ListType;
    if (setting == null) {
      return isList ? defaultListSize.toDouble() : 1.0;
    }
    if (!isList && setting.sizedFields.isEmpty) {
      return 1;
    }
    final sliced = _sliced(node, definition, setting);
    return sliced ?? setting.assumedSize ?? defaultListSize.toDouble();
  }

  double? _sliced(Field node, SchemaField definition, ListSizeSetting setting) {
    double? largest;
    for (final name in setting.slicingArguments) {
      for (final argument in node.arguments) {
        if (argument.name.value == name) {
          largest = _largest(largest, _valueOf(argument.value));
        }
      }
    }
    if (largest != null) {
      return largest;
    }
    for (final name in setting.slicingArguments) {
      final fallback = definition.argumentNamed(name)?.defaultValue;
      largest = _largest(largest, _count(fallback));
    }
    return largest;
  }

  double? _largest(double? first, double? second) => switch ((first, second)) {
    (final a?, final b?) => max(a, b),
    (final a?, null) => a,
    (null, final b) => b,
  };

  // The number a slicing argument's value stands for; null for a value that
  // names no size, such as null.
  double? _valueOf(Value value) => switch (value) {
    Variable(:final name) => _variable(name.value),
    _ => _count(value),
  };

  double _variable(String name) {
    if (variables[name] case JsonNumber(asInt: final int given)) {
      return max(0, given).toDouble();
    }
    return _count(variableDefaults[name]) ?? defaultListSize.toDouble();
  }

  double? _count(Value? value) => switch (value) {
    IntValue(:final value) => switch (double.tryParse(value)) {
      final number? => max(0, number),
      null => null,
    },
    _ => null,
  };

  // Loops, not recursion: a wrapper chain can be deep.
  TypeRef _unwrapNonNull(TypeRef type) {
    var current = type;
    while (current is NonNullType) {
      current = current.type;
    }
    return current;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/cost/operation_cost.dart`:

```dart
/// The static cost of one operation by the IBM cost directives draft.
///
/// Both numbers are upper bounds computed before execution; `CostAnalysis`
/// defines them.
///
/// {@category validation}
final class const OperationCost(
  /// The cost of resolving the fields: each field's weight and arguments,
  /// multiplied by the sizes of the lists above it.
  final double fieldCost,

  /// The cost of the objects the operation can return: the type weights of
  /// the selected fields, multiplied by the sizes of the lists above them.
  final double typeCost,
) {
  /// Creates a cost.
  this;

  @override
  bool operator ==(Object other) =>
      other is OperationCost &&
      other.fieldCost == fieldCost &&
      other.typeCost == typeCost;

  @override
  int get hashCode => Object.hash(fieldCost, typeCost);

  @override
  String toString() =>
      'OperationCost(fieldCost: $fieldCost, typeCost: $typeCost)';
}
```

Create `packages/typed_graphql/lib/src/validation/cost/sized_context.dart`:

```dart
/// The size a field's `sizedFields` give to the fields directly in its
/// selection set: each name in [names] has the list size [size].
final class SizedContext(
  /// The field names that take [size].
  final Set<String> names,

  /// The size of each of those fields.
  final double size,
) {
  /// Creates a context.
  this;

  /// Identifies the context in a memo: two contexts with the same key give a
  /// fragment the same cost.
  late final String key = '${(names.toList()..sort()).join(',')}#$size';
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -87,6 +87,8 @@ export 'src/schema/scalars/string_codec.dart';
 export 'src/schema/schema.dart';
 export 'src/schema/validation/schema_validation_result.dart';
 export 'src/schema/validation/schema_validator.dart';
+export 'src/validation/cost/cost_analysis.dart';
+export 'src/validation/cost/operation_cost.dart';
 export 'src/validation/document_validation_result.dart';
 export 'src/validation/document_validator.dart';
 export 'src/validation/limits/max_aliases_rule.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/cost/cost_analysis_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `CostAnalysis` computes an operation's field cost and type cost by the IBM cost directives draft, fragments expanded, in linear time.
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/validation/cost/argument_cost.dart packages/typed_graphql/lib/src/validation/cost/cost_analysis.dart packages/typed_graphql/lib/src/validation/cost/cost_walk.dart packages/typed_graphql/lib/src/validation/cost/cost_weights.dart packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart packages/typed_graphql/lib/src/validation/cost/list_sizes.dart packages/typed_graphql/lib/src/validation/cost/operation_cost.dart packages/typed_graphql/lib/src/validation/cost/sized_context.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/cost/cost_analysis_test.dart
git commit -q -m "feat(typed_graphql): add cost analysis" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: The slicing-argument and cost limit rules

`SlicingArgumentsRule` (`GQL237`) and `MaxCostRule` (`GQL238`); `CostNumber` prints a cost the same way on every platform, and `OperationCost.toString` uses it.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/cost/cost_number.dart`, `packages/typed_graphql/lib/src/validation/cost/max_cost_rule.dart`, `packages/typed_graphql/lib/src/validation/cost/slicing_arguments_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart`, `packages/typed_graphql/lib/src/validation/cost/operation_cost.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/validation/checked.dart`, `packages/typed_graphql/test/validation/cost/cost_analysis_test.dart`, `packages/typed_graphql/test/validation/cost/max_cost_rule_test.dart`, `packages/typed_graphql/test/validation/cost/slicing_arguments_rule_test.dart`

**Interfaces:**
- Consumes: Task 1 (`OperationSubject`), Task 5 (`CostAnalysis`, `ListSizeSetting`).
- Produces:
- Diagnostic codes: `GQL237`, `GQL238`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/cost/cost_number.dart
final class CostNumber(final double value)
  String get text

// validation/cost/max_cost_rule.dart
final class const MaxCostRule
  AstVisitor createVisitor(ValidationContext context)
final class _MaxCost(…)
  void checkOperation(OperationDefinition operation)

// validation/cost/slicing_arguments_rule.dart
final class const SlicingArgumentsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _SlicingArguments(final ValidationContext context)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql/test/validation/checked.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,8 +6,10 @@ import '../schema/built.dart';
 /// A validated schema to check documents against, for a validation test.
 final class Checked {
   /// Builds and validates [sdl]; fails the test when it is not valid.
-  Checked(String sdl)
-    : schema = switch (const SchemaValidator().validate(Built(sdl).schema)) {
+  Checked(String sdl, {SchemaBuilder builder = const SchemaBuilder()})
+    : schema = switch (const SchemaValidator().validate(
+        Built(sdl, builder: builder).schema,
+      )) {
         final ValidSchema valid => valid,
         InvalidSchema(:final diagnostics) => fail('$diagnostics'),
       };
```

In `packages/typed_graphql/test/validation/cost/cost_analysis_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -405,7 +405,7 @@ type Query { a(l: [In]): Int }
     test('prints both numbers', () {
       expect(
         const OperationCost(6, 56).toString(),
-        'OperationCost(fieldCost: 6.0, typeCost: 56.0)',
+        'OperationCost(fieldCost: 6, typeCost: 56)',
       );
     });
   });
```

Create `packages/typed_graphql/test/validation/cost/max_cost_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked(
    '''
type Query {
  users(first: Int): [User] @listSize(slicingArguments: ["first"], requireOneSlicingArgument: false)
  half: Half
  a: Query
  heavy: Int @cost(weight: "50")
}
type User { name: String }
type Half { value: Int @cost(weight: "0.5") }
''',
    builder: const SchemaBuilder(includesCostDirectives: true),
  );

  List<String> errors(String text, double maxCost) =>
      checked.errors(text, [MaxCostRule(maxCost: maxCost)]);

  test('an operation at the limit is valid', () {
    expect(errors('{ users(first: 100) { name } }', 101), isEmpty);
  });

  test('an operation over by field cost only is reported', () {
    expect(errors('{ heavy }', 10), [
      '1:1 GQL238 The anonymous operation has a field cost of 50 and a type '
          'cost of 1, more than the maximum of 10.',
    ]);
  });

  test('an operation over by type cost only is reported', () {
    expect(errors('{ users(first: 100) { name } }', 100), [
      '1:1 GQL238 The anonymous operation has a field cost of 1 and a type '
          'cost of 101, more than the maximum of 100.',
    ]);
  });

  test('a negative weight lowers a cost only to zero', () {
    final onlyTypes = Checked(
      'type Query { users: [User] @listSize(assumedSize: 5) } '
      'type User { name: String @cost(weight: "-1") }',
      builder: const SchemaBuilder(includesCostDirectives: true),
    );
    expect(
      onlyTypes.errors('{ users { name } }', [const MaxCostRule(maxCost: 5)]),
      [
        '1:1 GQL238 The anonymous operation has a field cost of 1 and a type '
            'cost of 6, more than the maximum of 5.',
      ],
    );
  });

  test('a fractional cost prints with its fraction', () {
    expect(errors('{ half { value } }', 0), [
      '1:1 GQL238 The anonymous operation has a field cost of 1.5 and a type '
          'cost of 2, more than the maximum of 0.',
    ]);
  });

  test('a named operation is named in the message', () {
    expect(errors('query Q { a { a } }', 1), [
      '1:1 GQL238 The operation "Q" has a field cost of 2 and a type cost of '
          '3, more than the maximum of 1.',
    ]);
  });

  test('two operations are reported in document order', () {
    expect(errors('query A { a { a } } query B { a }', 2), [
      '1:1 GQL238 The operation "A" has a field cost of 2 and a type cost of '
          '3, more than the maximum of 2.',
    ]);
  });

  test('a fragment defined after the operation adds its cost', () {
    expect(errors('{ ...F } fragment F on Query { a { a } }', 1), [
      '1:1 GQL238 The anonymous operation has a field cost of 2 and a type '
          'cost of 3, more than the maximum of 1.',
    ]);
  });

  test('a fragment chain that expands 2^60 times reports its huge cost', () {
    final fragments = StringBuffer('fragment F0 on Query { a }');
    for (var level = 1; level <= 60; level++) {
      fragments.write(
        ' fragment F$level on Query { ...F${level - 1} ...F${level - 1} }',
      );
    }
    // 2^60 prints in exponential form, the same text on every platform.
    expect(errors('{ ...F60 } $fragments', 1000), [
      '1:1 GQL238 The anonymous operation has a field cost of '
          '1.152921504606847e+18 and a type cost of 1.152921504606847e+18, '
          'more than the maximum of 1000.',
    ]);
  });

  test('a negative or NaN maximum is an ArgumentError', () {
    expect(() => errors('{ a }', -1), throwsArgumentError);
    expect(() => errors('{ a }', double.nan), throwsArgumentError);
  });
}
```

Create `packages/typed_graphql/test/validation/cost/slicing_arguments_rule_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

void main() {
  final checked = Checked('''
type Query {
  users(first: Int, last: Int): [User]
    @listSize(slicingArguments: ["first", "last"])
  pairs(first: Int, last: Int, tag: String): [User]
    @listSize(slicingArguments: ["first", "last"], requireOneSlicingArgument: false)
  one(first: Int): [User] @listSize(slicingArguments: ["first"])
  plain: [User]
}
type User { name: String }
''', builder: const SchemaBuilder(includesCostDirectives: true));

  List<String> errors(String text) =>
      checked.errors(text, [const SlicingArgumentsRule()]);

  test('a field given none of its slicing arguments is reported', () {
    expect(errors('{ users { name } }'), [
      '1:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 0.',
    ]);
  });

  test('a field given one slicing argument is valid', () {
    expect(errors('{ users(first: 3) { name } }'), isEmpty);
  });

  test('a field given two slicing arguments is reported', () {
    expect(errors('{ users(first: 3, last: 2) { name } }'), [
      '1:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 2.',
    ]);
  });

  test('a variable counts as given', () {
    expect(errors(r'query ($n: Int) { users(first: $n) { name } }'), isEmpty);
  });

  test('a null literal does not count', () {
    expect(errors('{ users(first: null) { name } }'), [
      '1:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 0.',
    ]);
  });

  test('a single slicing argument is named alone', () {
    expect(errors('{ one { name } }'), [
      '1:3 GQL237 Field "one" must be given exactly one of its slicing '
          'arguments "first", but it was given 0.',
    ]);
  });

  test('requireOneSlicingArgument false skips the field', () {
    expect(errors('{ pairs { name } }'), isEmpty);
  });

  test('a field without @listSize is skipped', () {
    expect(errors('{ plain { name } }'), isEmpty);
  });

  test('an alias reports the field name at the field', () {
    expect(errors('{\n  list: users { name }\n}'), [
      '2:3 GQL237 Field "users" must be given exactly one of its slicing '
          'arguments "first" or "last", but it was given 0.',
    ]);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/cost/cost_analysis_test.dart test/validation/cost/max_cost_rule_test.dart test/validation/cost/slicing_arguments_rule_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -500,5 +500,13 @@ enum DiagnosticCode(
   /// `GQL236`: a `__schema` or `__type` field with a path through three or
   /// more of `fields`, `interfaces`, `possibleTypes` and `inputFields`,
   /// fragments expanded (`MaxIntrospectionDepthRule`).
-  maxIntrospectionDepthExceeded('GQL236');
+  maxIntrospectionDepthExceeded('GQL236'),
+
+  /// `GQL237`: a field with `@listSize(slicingArguments:)` that is not given
+  /// exactly one of its slicing arguments (`SlicingArgumentsRule`).
+  slicingArgumentsRequired('GQL237'),
+
+  /// `GQL238`: an operation whose field cost or type cost is more than the
+  /// maximum `MaxCostRule` allows.
+  maxCostExceeded('GQL238');
 }
```

Create `packages/typed_graphql/lib/src/validation/cost/cost_number.dart`:

```dart
/// A cost as the messages print it.
final class CostNumber(final double value) {
  /// Creates the printable form of [value].
  this;

  // Beyond 1e15 the platforms print doubles differently (the VM
  // `1.152921504606847e+18`, JavaScript `1152921504606847000`); the
  // exponential form is the same everywhere.
  static const double _largest = 1000000000000000;

  /// `1200` for an integral value below 1e15, `2.5` for a fraction,
  /// `1.152921504606847e+18` from 1e15 on, `Infinity` for an infinity: the
  /// same text on every platform.
  String get text => switch (value) {
    final number when !number.isFinite => number.toString(),
    final number when number.abs() >= _largest =>
      number.toStringAsExponential(),
    final number when number == number.truncateToDouble() =>
      number.toStringAsFixed(0),
    final number => number.toString(),
  };
}
```

In `packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,6 +11,10 @@ final class ListSizeSetting(
 
   /// The names of the `sizedFields`.
   final List<String> sizedFields,
+
+  /// Whether a field must be given exactly one slicing argument (the
+  /// draft's `requireOneSlicingArgument`, true by default).
+  final bool requiresOneSlicingArgument,
 ) {
   /// Creates a setting.
   this;
@@ -28,6 +32,10 @@ final class ListSizeSetting(
           },
           _names(directive, 'slicingArguments'),
           _names(directive, 'sizedFields'),
+          switch (directive.argument('requireOneSlicingArgument')) {
+            BooleanValue(value: false) => false,
+            _ => true,
+          },
         );
       }
     }
```

Create `packages/typed_graphql/lib/src/validation/cost/max_cost_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../limits/operation_subject.dart';
import '../rules/operation_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'cost_analysis.dart';
import 'cost_number.dart';

/// Limits the static cost of an operation (R3.5, R3.8, `GQL238`).
///
/// The cost is [CostAnalysis]'s field cost and type cost, computed without
/// variable values: a slicing variable counts with its default value in the
/// operation, else with [defaultListSize]. An operation is reported when
/// either cost is more than [maxCost]. The rule is opt-in: it is not one of
/// the specified rules.
///
/// {@category validation}
final class const MaxCostRule({
  /// The largest field cost and type cost an operation may have.
  required final double maxCost,

  /// The size of a list field the schema gives no size.
  final int defaultListSize = 10,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws an [ArgumentError] when [maxCost] is negative or NaN, and a
  /// [RangeError] when [defaultListSize] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    if (maxCost.isNaN || maxCost < 0) {
      throw ArgumentError.value(maxCost, 'maxCost', 'must not be negative');
    }
    RangeError.checkNotNegative(defaultListSize, 'defaultListSize');
    return _MaxCost(context, maxCost, defaultListSize);
  }
}

final class _MaxCost(
  final ValidationContext context,
  final double maxCost,
  final int defaultListSize,
) extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    final cost = CostAnalysis(
      context.schema,
      defaultListSize: defaultListSize,
    ).costOf(context.document, operation);
    if (cost.fieldCost > maxCost || cost.typeCost > maxCost) {
      context.report(
        .maxCostExceeded,
        '${OperationSubject(operation).text} has a field cost of '
        '${CostNumber(cost.fieldCost).text} and a type cost of '
        '${CostNumber(cost.typeCost).text}, more than the maximum of '
        '${CostNumber(maxCost).text}.',
        [operation],
      );
    }
  }
}
```

In `packages/typed_graphql/lib/src/validation/cost/operation_cost.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,5 @@
+import 'cost_number.dart';
+
 /// The static cost of one operation by the IBM cost directives draft.
 ///
 /// Both numbers are upper bounds computed before execution; `CostAnalysis`
@@ -27,5 +29,6 @@ final class const OperationCost(
 
   @override
   String toString() =>
-      'OperationCost(fieldCost: $fieldCost, typeCost: $typeCost)';
+      'OperationCost(fieldCost: ${CostNumber(fieldCost).text}, '
+      'typeCost: ${CostNumber(typeCost).text})';
 }
```

Create `packages/typed_graphql/lib/src/validation/cost/slicing_arguments_rule.dart`:

```dart
import '../../diagnostics/suggestions.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/value.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'list_size_setting.dart';

/// The IBM cost directives draft's operation rule (R3.8, `GQL237`): a field
/// whose `@listSize` has `slicingArguments` and keeps
/// `requireOneSlicingArgument` is given exactly one of them.
///
/// An argument counts when it is given a value other than the `null`
/// literal; a variable counts. The rule is opt-in: it is not one of the
/// specified rules.
///
/// {@category validation}
final class const SlicingArgumentsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _SlicingArguments(context);
}

final class _SlicingArguments(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      _check(node);
    }
    return .next;
  }

  void _check(Field field) {
    final definition = context.typeInfo.fieldDefinition;
    if (definition == null) {
      return;
    }
    final setting = ListSizeSetting.read(definition.appliedDirectives);
    if (setting == null ||
        setting.slicingArguments.isEmpty ||
        !setting.requiresOneSlicingArgument) {
      return;
    }
    final names = setting.slicingArguments;
    final given = {
      for (final argument in field.arguments)
        if (names.contains(argument.name.value) && argument.value is! NullValue)
          argument.name.value,
    }.length;
    if (given != 1) {
      final quoted = [for (final name in names) '"$name"'];
      context.report(
        .slicingArgumentsRequired,
        'Field "${field.name.value}" must be given exactly one of its '
        'slicing arguments ${const Suggestions().orList(quoted)}, but it was '
        'given $given.',
        [field],
      );
    }
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -88,7 +88,9 @@ export 'src/schema/schema.dart';
 export 'src/schema/validation/schema_validation_result.dart';
 export 'src/schema/validation/schema_validator.dart';
 export 'src/validation/cost/cost_analysis.dart';
+export 'src/validation/cost/max_cost_rule.dart';
 export 'src/validation/cost/operation_cost.dart';
+export 'src/validation/cost/slicing_arguments_rule.dart';
 export 'src/validation/document_validation_result.dart';
 export 'src/validation/document_validator.dart';
 export 'src/validation/limits/max_aliases_rule.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/cost/cost_analysis_test.dart test/validation/cost/max_cost_rule_test.dart test/validation/cost/slicing_arguments_rule_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `SlicingArgumentsRule` (`GQL237`): a field with `@listSize(slicingArguments:)` is given exactly one slicing argument.
- `MaxCostRule` (`GQL238`) limits an operation's field cost and type cost.
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/cost/cost_number.dart packages/typed_graphql/lib/src/validation/cost/list_size_setting.dart packages/typed_graphql/lib/src/validation/cost/max_cost_rule.dart packages/typed_graphql/lib/src/validation/cost/operation_cost.dart packages/typed_graphql/lib/src/validation/cost/slicing_arguments_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/checked.dart packages/typed_graphql/test/validation/cost/cost_analysis_test.dart packages/typed_graphql/test/validation/cost/max_cost_rule_test.dart packages/typed_graphql/test/validation/cost/slicing_arguments_rule_test.dart
git commit -q -m "feat(typed_graphql): add the slicing-argument and cost limit rules" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: The operation-validation fuzzers

Three fuzzers in `packages/typed_graphql_conformance/test/fuzz/` (spec section 12): generated valid operations over a schema valid by construction (`RandomValidSchema`, `RandomOperation`) are valid; random and mutated documents never throw and respect `maxErrors`; hostile shapes end within 10 s, and a fan past the budget yields `GQL230`. They pass at once: they pin behaviour the earlier tasks built.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`
- Test: `packages/typed_graphql_conformance/test/fuzz/hostile_operation_fuzz_test.dart`, `packages/typed_graphql_conformance/test/fuzz/hostile_rules.dart`, `packages/typed_graphql_conformance/test/fuzz/hostile_shape_fuzz_test.dart`, `packages/typed_graphql_conformance/test/fuzz/random_operation.dart`, `packages/typed_graphql_conformance/test/fuzz/random_valid_schema.dart`, `packages/typed_graphql_conformance/test/fuzz/valid_operation_fuzz_test.dart`

**Interfaces:**
- Consumes: Every earlier task (`recommendedRules`, the limit and cost rules).
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql_conformance/test/fuzz/hostile_operation_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'hostile_rules.dart';
import 'random_executable.dart';
import 'random_operation.dart';
import 'random_parts.dart';
import 'random_valid_schema.dart';

/// R0.3, R10.3 and R10.4: random and mutated executable documents, with
/// every rule on, never throw, end, and give at most `maxErrors + 1`
/// diagnostics (the `GQL000` sink limit), each with a code.
void main() {
  final budget = FuzzBudget(defaultIterations: 300);
  const parser = Parser(options: ParserOptions(maxTokens: null));
  final tokenPattern = RegExp(r'\.\.\.|\$?[A-Za-z_]\w*|"[^"]*"|-?\d\S*|\S');
  const printer = Printer();

  String randomDocument(Random random) {
    final executable = RandomExecutable(RandomParts(random));
    return printer.print(
      Document([
        executable.operation(isFirst: true),
        for (var i = 0, n = random.nextInt(3); i < n; i++)
          executable.fragment(),
      ]),
    );
  }

  List<String> tokensOf(String text) => [
    for (final match in tokenPattern.allMatches(text)) match[0] ?? '',
  ];

  /// [text] with up to three tokens dropped, doubled or exchanged, or its
  /// tail replaced by a tail of [other].
  String mutate(Random random, String text, String other) {
    var tokens = tokensOf(text);
    for (var step = random.nextInt(4); step > 0 && tokens.isNotEmpty; step--) {
      final index = random.nextInt(tokens.length);
      switch (random.nextInt(4)) {
        case 0:
          tokens.removeAt(index);
        case 1:
          tokens.insert(index, tokens[index]);
        case 2:
          final second = random.nextInt(tokens.length);
          final kept = tokens[index];
          tokens[index] = tokens[second];
          tokens[second] = kept;
        default:
          final others = tokensOf(other);
          tokens = [
            ...tokens.take(index),
            ...others.skip(random.nextInt(others.length + 1)),
          ];
      }
    }
    return tokens.join(' ');
  }

  var outcomes = <String, int>{};

  void count(String outcome) =>
      outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;

  void check(ValidSchema schema, String text, String reason) {
    final source = Source(text);
    final document = switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure() => null,
    };
    if (document == null) {
      count('parse failure');
      return;
    }
    final result = HostileRules.validator.validate(
      schema,
      document,
      source: source,
    );
    count(result is ValidDocument ? 'valid' : 'invalid');
    expect(
      result.diagnostics.length,
      lessThanOrEqualTo(HostileRules.maxErrors + 1),
      reason: reason,
    );
    for (final diagnostic in result.diagnostics) {
      expect(diagnostic.code.id, startsWith('GQL'), reason: reason);
    }
  }

  test(
    'random and mutated documents never throw and report a bounded list',
    () {
      outcomes = {};
      for (var index = 0; index < budget.iterations; index++) {
        final random = budget.randomFor(index);
        final (:sdl, :schema) = RandomValidSchema(random).build();
        final valid = printer.print(
          RandomOperation(schema.schema, random).document(),
        );
        final other = printer.print(
          RandomOperation(schema.schema, random).document(),
        );
        final texts = [
          randomDocument(random),
          valid,
          mutate(random, valid, other),
          mutate(random, valid, randomDocument(random)),
          mutate(random, randomDocument(random), valid),
        ];
        for (final text in texts) {
          check(schema, text, '${budget.replay(index)}\n$sdl\n$text');
        }
      }
      if (budget.iterations >= 100) {
        expect(outcomes['valid'], greaterThan(0));
        expect(outcomes['invalid'], greaterThan(0));
        expect(outcomes['parse failure'], greaterThan(0));
      }
    },
  );
}
```

Create `packages/typed_graphql_conformance/test/fuzz/hostile_rules.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// The validator the hostile operation fuzzers run: every specified rule
/// and every opt-in rule, with small limits so that the limit rules fire.
final class HostileRules {
  const HostileRules._();

  /// The rules of one run.
  static const List<ValidationRule> all = [
    ...DocumentValidator.recommendedRules,
    MaxDepthRule(maxDepth: 5),
    MaxAliasesRule(maxAliases: 5),
    MaxDirectivesRule(maxDirectives: 5),
    NoIntrospectionRule(),
    SlicingArgumentsRule(),
    MaxCostRule(maxCost: 100),
  ];

  /// The most errors a run reports.
  static const int maxErrors = 20;

  /// A validator over [all] with [maxErrors].
  static const DocumentValidator validator = DocumentValidator(
    rules: all,
    maxErrors: maxErrors,
  );
}
```

Create `packages/typed_graphql_conformance/test/fuzz/hostile_shape_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'hostile_rules.dart';

/// R0.3, R3.7 and R10.3: documents of hostile shapes, built in code with
/// random sizes inside a fixed bound, end within ten seconds with every
/// rule on, and a shape whose work grows exponentially gives `GQL230`.
void main() {
  final budget = FuzzBudget(defaultIterations: 36);
  final schema = () {
    final source = Source(
      'type Query { a: Query b(x: Int): Query s: String l: [Query] }',
    );
    final document = const Parser().parse(source).requireDocument();
    final built = const SchemaBuilder().fromSdl(document, source: source);
    return switch (built) {
      BuildSuccess(:final schema) => ValidSchema.assumeValid(schema),
      BuildFailure(:final diagnostics) => fail('$diagnostics'),
    };
  }();

  Field leaf() => Field(null, const Name('s'));

  /// `{ <inner> }` as a selection set.
  SelectionSet only(Selection inner) => SelectionSet([inner]);

  Document operationOf(List<Selection> selections, [List<Definition>? more]) =>
      Document([
        OperationDefinition(.query, SelectionSet(selections)),
        ...?more,
      ]);

  FragmentDefinition fragment(String name, List<Selection> selections) =>
      FragmentDefinition(
        Name(name),
        const NamedType(Name('Query')),
        SelectionSet(selections),
      );

  FragmentSpread spread(String name) => FragmentSpread(Name(name));

  /// `{ a { a { ... { s } } } }` [depth] levels deep, built from the leaf.
  Document deepSelection(int depth) {
    var inner = leaf();
    for (var i = 0; i < depth; i++) {
      inner = Field(null, const Name('a'), selectionSet: only(inner));
    }
    return operationOf([inner]);
  }

  /// [width] fields of one response name, `b(x: 1)` or `b(x: i)`.
  Document wideSelection(int width, {required bool isSameArguments}) =>
      operationOf([
        for (var i = 0; i < width; i++)
          Field(
            null,
            const Name('b'),
            arguments: [
              Argument(
                const Name('x'),
                IntValue(isSameArguments ? '1' : '$i'),
              ),
            ],
            selectionSet: only(leaf()),
          ),
      ]);

  /// `F0 { ...F1 ...F1 }`, ..., `F<k> { s }`: 2^k fields once expanded.
  Document fragmentChain(int length) => operationOf(
    [spread('F0')],
    [
      for (var i = 0; i < length; i++)
        fragment('F$i', [spread('F${i + 1}'), spread('F${i + 1}')]),
      fragment('F$length', [leaf()]),
    ],
  );

  /// Each fragment selects `a { ...next }` and `b(x: i) { ...next }`, so
  /// the fields to merge double with each level.
  Document fragmentFan(int length) => operationOf(
    [spread('F0')],
    [
      for (var i = 0; i < length; i++)
        fragment('F$i', [
          for (final (alias, name) in [('p', 'a'), ('q', 'b')])
            Field(
              Name(alias),
              Name(name),
              selectionSet: only(spread('F${i + 1}')),
            ),
          Field(
            const Name('r'),
            const Name('a'),
            selectionSet: only(spread('F${i + 1}')),
          ),
        ]),
      fragment('F$length', [leaf()]),
    ],
  );

  /// `F0` spreads `F1`, ..., the last spreads `F0`.
  Document fragmentCycle(int length) => operationOf(
    [spread('F0')],
    [
      for (var i = 0; i < length; i++)
        fragment('F$i', [leaf(), spread('F${(i + 1) % length}')]),
    ],
  );

  /// [count] operations that spread the same chain of [length] fragments.
  Document manyOperations(int count, int length) => Document([
    for (var i = 0; i < count; i++)
      OperationDefinition(
        .query,
        only(spread('F0')),
        name: Name('Q$i'),
      ),
    for (var i = 0; i < length; i++)
      fragment('F$i', [leaf(), spread('F${i + 1}')]),
    fragment('F$length', [leaf()]),
  ]);

  /// The shapes by name, each a function of the random source.
  final shapes = <String, Document Function(Random)>{
    'deep selection': (random) => deepSelection(1 + random.nextInt(20000)),
    'wide, same arguments': (random) =>
        wideSelection(1 + random.nextInt(20000), isSameArguments: true),
    'wide, differing arguments': (random) =>
        wideSelection(1 + random.nextInt(20000), isSameArguments: false),
    'fragment chain': (random) => fragmentChain(1 + random.nextInt(60)),
    'fragment fan': (random) => fragmentFan(1 + random.nextInt(60)),
    'fragment cycle': (random) => fragmentCycle(1 + random.nextInt(2000)),
    'many operations': (random) =>
        manyOperations(1 + random.nextInt(300), 1 + random.nextInt(300)),
  };

  test('every hostile shape ends within ten seconds', () {
    final names = shapes.keys.toList();
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final name = names[index % names.length];
      final document = shapes[name]!(random);
      final reason = '${budget.replay(index)}: $name';
      final stopwatch = Stopwatch()..start();
      final result = HostileRules.validator.validate(schema, document);
      stopwatch.stop();
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason: reason,
      );
      expect(
        result.diagnostics.length,
        lessThanOrEqualTo(HostileRules.maxErrors + 1),
        reason: reason,
      );
    }
  });

  test('fragments that triple the fields to merge 60 times give GQL230', () {
    final result = HostileRules.validator.validate(schema, fragmentFan(60));
    expect(
      [for (final diagnostic in result.diagnostics) diagnostic.code],
      contains(DiagnosticCode.documentTooComplex),
    );
  });

  test('a chain that spreads each fragment twice is valid and fast', () {
    final result = HostileRules.validator.validate(schema, fragmentChain(60));
    expect(result.diagnostics, isEmpty);
  });
}
```

Create `packages/typed_graphql_conformance/test/fuzz/random_operation.dart`:

```dart
import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// Random operations that are valid against a schema by construction
/// (R3.1, R10.4).
///
/// Every field comes from its parent type, has a sub-selection exactly when
/// its type is composite, and gets a valid literal or a variable of the
/// argument's type for each required argument. A response name is used
/// once in the whole document, unless a field is picked again, which then
/// gets a unique alias, so no two fields can conflict. A fragment is
/// created where it is first spread and may be spread again after it is
/// complete, so the spreads never form a cycle.
final class RandomOperation {
  /// Draws from [random] over the types of [schema].
  RandomOperation(this.schema, this.random);

  /// The schema the operation is valid against.
  final Schema schema;

  /// The random source.
  final Random random;

  static const int _maxDepth = 3;

  final Set<String> _usedNames = {};
  final Map<String, VariableDefinition> _variablesByType = {};
  final List<VariableDefinition> _variables = [];
  final List<FragmentDefinition> _fragments = [];
  int _counter = 0;

  /// One query and the fragments it uses.
  Document document() {
    final root = schema.typeNamed(schema.rootTypeName(.query) ?? 'Query');
    if (root is! ObjectType) {
      throw StateError('the schema has no query root');
    }
    final selectionSet = _selectionSet(root, 0);
    return Document([
      OperationDefinition(
        .query,
        selectionSet,
        name: random.nextBool() ? const Name('Generated') : null,
        variableDefinitions: _variables,
      ),
      ..._fragments,
    ]);
  }

  SelectionSet _selectionSet(SchemaType parent, int depth) => SelectionSet([
    for (var i = 0, n = 1 + random.nextInt(3); i < n; i++)
      _selection(parent, depth),
  ]);

  Selection _selection(SchemaType parent, int depth) {
    final kind = random.nextInt(10);
    if (depth >= _maxDepth) {
      return _typename();
    }
    if (parent is UnionType) {
      return kind < 3
          ? _typename()
          : kind < 7
          ? _inlineFragment(parent, depth)
          : _fragmentSpread(parent, depth);
    }
    return switch (kind) {
      < 6 => _field(parent, depth),
      6 => _typename(),
      7 => _inlineFragment(parent, depth),
      _ => _fragmentSpread(parent, depth),
    };
  }

  Field _typename() => Field(null, const Name('__typename'));

  Selection _field(SchemaType parent, int depth) {
    final candidates = switch (parent) {
      ObjectType(:final fields) || InterfaceType(:final fields) => [
        for (final field in fields)
          if (depth < _maxDepth || _isLeaf(field.type)) field,
      ],
      _ => const <SchemaField>[],
    };
    if (candidates.isEmpty) {
      return _typename();
    }
    final field = candidates[random.nextInt(candidates.length)];
    final alias = !_usedNames.add(field.name) || random.nextInt(7) == 0
        ? Name('a${_counter++}')
        : null;
    final target = _named(field.type);
    return Field(
      alias,
      Name(field.name),
      arguments: _arguments(field.arguments),
      directives: _directives(),
      selectionSet: target.isCompositeType
          ? _selectionSet(target, depth + 1)
          : null,
    );
  }

  bool _isLeaf(TypeRef type) => _named(type).isLeafType;

  SchemaType _named(TypeRef type) =>
      schema.namedTypeOf(type) ?? (throw StateError('unknown type $type'));

  InlineFragment _inlineFragment(SchemaType parent, int depth) {
    if (random.nextInt(6) == 0) {
      return InlineFragment(
        null,
        _selectionSet(parent, depth + 1),
        directives: _directives(),
      );
    }
    final type = _overlapping(parent);
    return InlineFragment(
      NamedType(Name(type.name)),
      _selectionSet(type, depth + 1),
      directives: _directives(),
    );
  }

  /// A composite type that shares a possible object type with [parent];
  /// [parent] itself is always one.
  SchemaType _overlapping(SchemaType parent) {
    final candidates = [
      parent,
      for (final type in schema.types)
        if (type.isCompositeType && schema.typesOverlap(parent, type)) type,
    ];
    return candidates[random.nextInt(candidates.length)];
  }

  FragmentSpread _fragmentSpread(SchemaType parent, int depth) {
    final reusable = [
      for (final fragment in _fragments)
        if (schema.typesOverlap(
          parent,
          _named(fragment.typeCondition),
        ))
          fragment,
    ];
    if (reusable.isNotEmpty && random.nextBool()) {
      final fragment = reusable[random.nextInt(reusable.length)];
      return FragmentSpread(fragment.name, directives: _directives());
    }
    final type = _overlapping(parent);
    final name = Name('Frag${_counter++}');
    _fragments.add(
      FragmentDefinition(
        name,
        NamedType(Name(type.name)),
        _selectionSet(type, depth + 1),
      ),
    );
    return FragmentSpread(name, directives: _directives());
  }

  /// `@skip` or `@include`, on a few selections.
  List<Directive> _directives() {
    if (random.nextInt(8) != 0) {
      return const [];
    }
    final condition = random.nextBool()
        ? BooleanValue(random.nextBool())
        : _variableOf(const NonNullType(NamedType(Name('Boolean'))));
    return [
      Directive(
        Name(random.nextBool() ? 'skip' : 'include'),
        arguments: [Argument(const Name('if'), condition)],
      ),
    ];
  }

  List<Argument> _arguments(List<InputValue> declared) => [
    for (final argument in declared)
      if (_isRequired(argument) || random.nextInt(5) < 2)
        Argument(Name(argument.name), _value(argument.type)),
  ];

  bool _isRequired(InputValue value) =>
      value.type is NonNullType && value.defaultValue == null;

  /// A value valid for [type]: a literal, or a variable of [type] (a
  /// non-null one when [isNullable] is false, which a `@oneOf` field and
  /// the inside of a non-null type need).
  Value _value(
    TypeRef type, {
    bool isNullable = true,
    bool allowsVariables = true,
  }) {
    if (allowsVariables && random.nextInt(5) == 0) {
      return _variableOf(isNullable ? type : _nonNull(type));
    }
    return switch (type) {
      NonNullType(:final type) => _value(
        type,
        isNullable: false,
        allowsVariables: allowsVariables,
      ),
      _ when isNullable && random.nextInt(12) == 0 => const NullValue(),
      ListType(:final type) => ListValue([
        for (var i = 0, n = random.nextInt(3); i < n; i++)
          _value(type, allowsVariables: allowsVariables),
      ]),
      NamedType() => _namedValue(
        _named(type),
        allowsVariables: allowsVariables,
      ),
    };
  }

  TypeRef _nonNull(TypeRef type) =>
      type is NonNullType ? type : NonNullType(type);

  Value _namedValue(SchemaType type, {required bool allowsVariables}) =>
      switch (type) {
        EnumType(:final values) => EnumValue(
          values[random.nextInt(values.length)].name,
        ),
        InputObjectType() => _objectValue(
          type,
          allowsVariables: allowsVariables,
        ),
        ScalarType(:final name) => switch (name) {
          'Int' => IntValue('${random.nextInt(100)}'),
          'Float' => FloatValue('${random.nextInt(100)}.5'),
          'Boolean' => BooleanValue(random.nextBool()),
          _ => const StringValue('text'),
        },
        _ => throw StateError('${type.name} is not an input type'),
      };

  ObjectValue _objectValue(
    InputObjectType type, {
    required bool allowsVariables,
  }) {
    if (type.isOneOf) {
      final field = type.fields[random.nextInt(type.fields.length)];
      return ObjectValue([
        ObjectField(
          Name(field.name),
          _value(
            field.type,
            isNullable: false,
            allowsVariables: allowsVariables,
          ),
        ),
      ]);
    }
    return ObjectValue([
      for (final field in type.fields)
        if (_isRequired(field) || random.nextBool())
          ObjectField(
            Name(field.name),
            _value(field.type, allowsVariables: allowsVariables),
          ),
    ]);
  }

  /// A variable of exactly [type], defined for the operation, with a
  /// default value at times.
  Variable _variableOf(TypeRef type) {
    final key = const Printer().print(type);
    final existing = _variablesByType[key];
    if (existing != null) {
      return existing.variable;
    }
    final variable = Variable(Name('v${_counter++}'));
    final definition = VariableDefinition(
      variable,
      type,
      defaultValue: random.nextInt(3) == 0
          ? _value(type, allowsVariables: false)
          : null,
    );
    _variablesByType[key] = definition;
    _variables.add(definition);
    return variable;
  }
}
```

Create `packages/typed_graphql_conformance/test/fuzz/random_valid_schema.dart`:

```dart
import 'dart:math';

import 'package:typed_graphql/typed_graphql.dart';

/// A random schema that is valid by construction, and the SDL it was built
/// from (R10.4).
///
/// The random schemas of the round-trip fuzzer use random type names, so
/// they almost never validate; the operation fuzzers need a schema with
/// every kind of type, wrapper, required argument and `@oneOf` input
/// object. Input objects refer only to earlier ones, so no input cycle can
/// arise; an object copies the fields of the one interface it implements.
final class RandomValidSchema {
  /// Draws from [random].
  RandomValidSchema(this.random);

  /// The random source.
  final Random random;

  static const List<String> _builtInScalars = [
    'Int',
    'Float',
    'String',
    'Boolean',
    'ID',
  ];

  final StringBuffer _sdl = StringBuffer();
  final List<String> _scalars = [..._builtInScalars];
  final List<String> _enums = [];
  final List<String> _inputs = [];
  final List<String> _outputs = [];

  /// The SDL text and the validated schema; a schema that does not
  /// validate is a bug of this generator and fails.
  ({String sdl, ValidSchema schema}) build() {
    _writeScalarsAndEnums();
    _writeInputs();
    final objectNames = [
      'Query',
      for (var i = 0, n = random.nextInt(4); i < n; i++) 'Obj$i',
    ];
    final interfaceNames = [
      for (var i = 0, n = random.nextInt(3); i < n; i++) 'Ifc$i',
    ];
    final unionNames = [
      for (var i = 0, n = random.nextInt(3); i < n; i++) 'Uni$i',
    ];
    _outputs.addAll([
      ..._scalars,
      ..._enums,
      ...objectNames,
      ...interfaceNames,
      ...unionNames,
    ]);
    final interfaceFields = _writeInterfaces(interfaceNames);
    _writeObjects(objectNames, interfaceFields);
    for (final name in unionNames) {
      final members = (List.of(objectNames)..shuffle(random)).take(
        1 + random.nextInt(objectNames.length),
      );
      _sdl.writeln('union $name = ${members.join(' | ')}');
    }
    final sdl = _sdl.toString();
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final built = const SchemaBuilder().fromSdl(document);
    if (built is! BuildSuccess) {
      throw StateError(
        'generated SDL does not build: ${built.diagnostics}\n'
        '$sdl',
      );
    }
    final validated = const SchemaValidator().validate(built.schema);
    if (validated is! ValidSchema) {
      throw StateError(
        'generated SDL is invalid: ${validated.diagnostics}\n'
        '$sdl',
      );
    }
    return (sdl: sdl, schema: validated);
  }

  void _writeScalarsAndEnums() {
    for (var i = 0, n = random.nextInt(3); i < n; i++) {
      _sdl.writeln('scalar Scalar$i');
      _scalars.add('Scalar$i');
    }
    for (var i = 0, n = random.nextInt(3); i < n; i++) {
      final values = [
        for (var j = 0, m = 1 + random.nextInt(3); j < m; j++) 'E${i}V$j',
      ];
      _sdl.writeln('enum Enum$i { ${values.join(' ')} }');
      _enums.add('Enum$i');
    }
  }

  void _writeInputs() {
    for (var i = 0, n = random.nextInt(4); i < n; i++) {
      final isOneOf = random.nextInt(4) == 0;
      final pool = [..._scalars, ..._enums, ..._inputs];
      final fields = [
        for (var j = 0, m = 1 + random.nextInt(3); j < m; j++)
          'g$j: ${_wrap(pool[random.nextInt(pool.length)], isNullable: isOneOf)}',
      ];
      _sdl.writeln(
        'input In$i${isOneOf ? ' @oneOf' : ''} { ${fields.join(' ')} }',
      );
      _inputs.add('In$i');
    }
  }

  /// The interfaces' fields by name, for the objects that implement them.
  Map<String, List<String>> _writeInterfaces(List<String> names) {
    final fields = <String, List<String>>{};
    for (final name in names) {
      final own = _fields('i${name}_', 1 + random.nextInt(3));
      fields[name] = own;
      _sdl.writeln('interface $name { ${own.join(' ')} }');
    }
    return fields;
  }

  void _writeObjects(
    List<String> names,
    Map<String, List<String>> interfaceFields,
  ) {
    for (final name in names) {
      final interfaces = interfaceFields.keys.toList();
      final implemented = interfaces.isNotEmpty && random.nextBool()
          ? interfaces[random.nextInt(interfaces.length)]
          : null;
      final fields = [
        if (implemented != null) ...interfaceFields[implemented]!,
        ..._fields('f${name}_', implemented == null ? 1 : random.nextInt(3)),
      ];
      final clause = implemented == null ? '' : ' implements $implemented';
      _sdl.writeln('type $name$clause { ${fields.join(' ')} }');
    }
  }

  List<String> _fields(String prefix, int count) => [
    for (var i = 0; i < count; i++)
      '$prefix$i${_arguments()}: ${_wrap(_pickOutput())}',
  ];

  String _pickOutput() => _outputs[random.nextInt(_outputs.length)];

  /// Zero to two arguments; some required, some with a default.
  String _arguments() {
    final count = random.nextInt(3);
    if (count == 0) {
      return '';
    }
    final pool = [..._scalars, ..._enums, ..._inputs];
    final arguments = [
      for (var i = 0; i < count; i++) _argument(i, pool),
    ];
    return '(${arguments.join(', ')})';
  }

  String _argument(int index, List<String> pool) {
    if (random.nextInt(5) == 0) {
      final withDefault = random.nextBool();
      return withDefault
          ? 'a$index: Int! = ${random.nextInt(9)}'
          : 'a$index: String = "x"';
    }
    return 'a$index: ${_wrap(pool[random.nextInt(pool.length)])}';
  }

  /// [name] as it, non-null, a list or a nested list; with [isNullable],
  /// never non-null (a `@oneOf` field).
  String _wrap(String name, {bool isNullable = false}) {
    if (isNullable) {
      return random.nextBool() ? name : '[$name]';
    }
    return switch (random.nextInt(6)) {
      0 => name,
      1 => '$name!',
      2 => '[$name]',
      3 => '[$name!]!',
      4 => '[$name!]',
      _ => '[[$name]]',
    };
  }
}
```

Create `packages/typed_graphql_conformance/test/fuzz/valid_operation_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'random_operation.dart';
import 'random_valid_schema.dart';

/// R0.3, R10.3 and R10.4: an operation that is valid by construction over a
/// random valid schema passes every specified rule, as printed text parsed
/// back. A failure names the case, the schema and the operation.
void main() {
  final budget = FuzzBudget(defaultIterations: 300);
  const parser = Parser(options: ParserOptions(maxTokens: null));

  test('generated operations are valid', () {
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final (:sdl, :schema) = RandomValidSchema(random).build();
      for (var round = 0; round < 3; round++) {
        final text = const Printer().print(
          RandomOperation(schema.schema, random).document(),
        );
        final reason = '${budget.replay(index)}\n$sdl\n$text';
        final source = Source(text);
        final document = switch (parser.parse(source)) {
          ParseSuccess(:final document) => document,
          ParseFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
        };
        final result = const DocumentValidator().validate(
          schema,
          document,
          source: source,
        );
        expect(result.diagnostics, isEmpty, reason: reason);
        expect(result, isA<ValidDocument>(), reason: reason);
      }
    }
  });

  test('the generator reaches fragments, variables and aliases', () {
    final features = <String>{};
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final schema = RandomValidSchema(random).build().schema;
      final text = const Printer().print(
        RandomOperation(schema.schema, random).document(),
      );
      if (text.contains('fragment ')) features.add('fragment');
      if (text.contains('... on ')) features.add('inline fragment');
      if (text.contains(r'$')) features.add('variable');
      if (RegExp(r'\ba\d+:').hasMatch(text)) features.add('alias');
      if (text.contains('@skip') || text.contains('@include')) {
        features.add('directive');
      }
    }
    if (budget.iterations >= 100) {
      expect(features, {
        'fragment',
        'inline fragment',
        'variable',
        'alias',
        'directive',
      });
    }
  });
}
```

- [ ] **Step 2: Update the documents**

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Fuzzers for operation validation: operations valid by construction over
  random valid schemas, random and mutated documents with every rule on,
  and documents of hostile shapes that must end within ten seconds.
```

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -52,6 +52,14 @@ same elements (`SchemaDump`) and prints the same text;
 `hostile_sdl_fuzz_test.dart` builds random and mutated type-system text,
 and extends a schema with it, and checks that the builder reports every
 kind of problem, within the sink limit, and never throws.
+`valid_operation_fuzz_test.dart` builds random operations that are valid by
+construction over random valid schemas (`RandomValidSchema`,
+`RandomOperation`) and checks that every specified rule accepts them;
+`hostile_operation_fuzz_test.dart` validates random and mutated documents
+with every rule and limit on and checks that the result is bounded and
+never throws; `hostile_shape_fuzz_test.dart` validates documents of hostile
+shapes (deep, wide, exponentially expanding, cyclic) and checks that each
+run ends within ten seconds and that exponential merging gives `GQL230`.
 
 ## License
 
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/fuzz/hostile_operation_fuzz_test.dart test/fuzz/hostile_shape_fuzz_test.dart test/fuzz/valid_operation_fuzz_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/test/fuzz/hostile_operation_fuzz_test.dart packages/typed_graphql_conformance/test/fuzz/hostile_rules.dart packages/typed_graphql_conformance/test/fuzz/hostile_shape_fuzz_test.dart packages/typed_graphql_conformance/test/fuzz/random_operation.dart packages/typed_graphql_conformance/test/fuzz/random_valid_schema.dart packages/typed_graphql_conformance/test/fuzz/valid_operation_fuzz_test.dart
git commit -q -m "test(typed_graphql_conformance): fuzz operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Document the limit rules and cost analysis

The guide's Limits and Cost sections with runnable snippets, the README, `llms.txt`, `CLAUDE.md` and the handoff.

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/doc/validation.md`

**Interfaces:**
- Consumes: Every earlier task.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -38,7 +38,11 @@ and the Introspection guide. M4a (operation validation) delivers the rule
 framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection
 merging in linear time, the step budget (`GQL230`), every graphql-js
 validation suite, the hostile-document tests and the Operation Validation
-guide.
+guide. M4b (limits and cost) delivers the opt-in limit rules (depth, aliases,
+directives, introspection: `GQL232`-`GQL236`), `recommendedRules`, the IBM
+cost directives (`includesCostDirectives`, `GQL156`-`GQL161`), `CostAnalysis`,
+`SlicingArgumentsRule` and `MaxCostRule` (`GQL237`, `GQL238`), the operation
+fuzzers and the guide sections on limits and cost.
 
 ## Documents
 
@@ -318,6 +322,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   then reports each cycle among the rest once; `DefaultValueCycleRules`
   walks default values depth-first and, created once per run, remembers
   the fields it walked across types.
+- Cost directives (opt-in): `SchemaBuilder(includesCostDirectives: true)`
+  (and `Schema`) adds `@cost` and `@listSize` from the internal
+  `CostDirectiveSdl`, kept apart from `BuiltInSdl` because the IBM draft is
+  not part of the specification. `SchemaValidator` runs `CostDirectiveRules`
+  and `ListSizeRules` (`GQL156`-`GQL161`) only with the flag.
 
 **Validation** (`validation/`; M4). Imports every layer before it.
 - `DocumentValidator` (const: `rules`, `maxErrors`, `includesSuggestions`,
@@ -356,6 +365,22 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   class, `ConflictJudge` judges a pair at its nearest distinct ancestors,
   `ConflictTree` and `ConflictReports` build graphql-js's nested messages
   and order them by the selection set graphql-js finds them in.
+- `limits/` holds the opt-in rules `MaxDepthRule`, `MaxAliasesRule`,
+  `MaxDirectivesRule`, `NoIntrospectionRule` and `MaxIntrospectionDepthRule`
+  (R3.5), none in `specifiedRules`; `DocumentValidator.recommendedRules` is
+  `specifiedRules` plus the last. `SelectionMeasure` is a memoised
+  explicit-stack fold over operations with fragments expanded, one per
+  `MeasuredQuantity` (depth, aliases, directives); `LimitVisitor` reports
+  an operation at most once; `OperationSubject` words the operation in a
+  message.
+- `cost/` (R3.8): `CostAnalysis` is const and makes a `CostWalk` per call,
+  an explicit-stack walk over `CostWeights` (type and field weight caches)
+  with a fragment memo keyed by fragment and `SizedContext`, so fragments
+  cost linear time. `ListSizes` and `ListSizeSetting` read `@listSize`,
+  `ArgumentCost` the weights of arguments and input fields, `CostNumber`
+  prints a cost. `OperationCost` holds the field cost and type cost.
+  `MaxCostRule` (`GQL238`) and `SlicingArgumentsRule` (`GQL237`) are
+  opt-in rules.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
@@ -454,6 +479,15 @@ Learned in M4a:
 - A work budget is measured, not guessed: about a million steps take a
   second on the VM, so the default `maxSteps` is a million.
 
+Learned in M4b:
+- `avoid_classes_with_only_static_members` rejects a static-only helper:
+  make it a small instance class (const when it holds nothing).
+- A fold over fragments must be memoised per fragment (and per sized
+  context for the cost), or a chain of fragments that each spread the next
+  twice is exponential; a fragment on the stack is a cycle and counts 0.
+- graphql-js test names may be double-quoted in the source; the suite
+  reader handles both quotes.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
@@ -544,6 +578,7 @@ README that leaves the package folder is an absolute URL.
 - Hostile-document tests: `packages/typed_graphql/test/validation/hostile_*_test.dart`.
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
   round trip, hostile SDL, introspection round trip, hostile
-  introspection, coordinates); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
+  introspection, coordinates, valid operations, hostile operations and
+  hostile shapes); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
   `TYPED_GRAPHQL_FUZZ_SEED` tune them.
 - CI: `.github/workflows/ci.yml`.
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,8 +64,8 @@ void main() {
 > every API may change before 0.1.0. Stages M2 (language) and M3
 > (the schema: building it from SDL, extending, printing and validating it,
 > resolving schema coordinates, and introspection in both directions) are
-> done, and so is M4a (operation validation by the specification's 30
-> rules).
+> done, and so is M4 (operation validation by the specification's 30 rules,
+> limits and cost analysis).
 
 ## Table of contents
 
@@ -109,7 +109,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 
 | Package | Role | Status |
 |---|---|---|
-| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation (M1, M2, M3, M4a) |
+| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a done). Read this
+Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a and M4b done on the stage branch, not merged). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
@@ -15,7 +15,7 @@ needed.
 | M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md); M3b: [plan](plans/2026-10-14-m3b-schema-validation.md) | M3a and M3b merged into `main` locally (not pushed); M3 is complete; next is M4 (operation validation) |
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
-| M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a is complete: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging in linear time, the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`; next is M4b (limit rules, cost analysis, fuzzers) |
+| M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a and M4b are complete on the stage branch (not merged). M4a: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging in linear time, the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`. M4b: the opt-in limit rules `MaxDepthRule`, `MaxAliasesRule`, `MaxDirectivesRule`, `NoIntrospectionRule`, `MaxIntrospectionDepthRule` (`GQL232`-`GQL236`) and `DocumentValidator.recommendedRules`; `includesCostDirectives` with `@cost` and `@listSize` and their schema checks (`GQL156`-`GQL161`); `CostAnalysis` / `OperationCost`, `SlicingArgumentsRule` (`GQL237`), `MaxCostRule` (`GQL238`); three operation fuzzers; the guide sections "Limits" and "Cost"; next is the merge of the stage branch, then M5 |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
@@ -93,6 +93,15 @@ M3b is complete and merged into `main` locally (not pushed). Left open by the M3
   more fields of one response name conflict: each field is compared with
   the first field of every other class (M4 spec, deviation 4; one adapted
   row in `mapping/validation.csv`).
+- **`recommendedRules` as the default?** `DocumentValidator.rules` still
+  defaults to `specifiedRules`; whether it becomes `recommendedRules` (adds
+  `MaxIntrospectionDepthRule`) is undecided.
+- **`defaultListSize` is 10.** The draft names no default; 10 is this
+  library's choice for `CostAnalysis` and `MaxCostRule`.
+- **Variables in validation-time cost.** `MaxCostRule` has no variable
+  values, so a slicing variable counts with its default in the operation,
+  else `defaultListSize`; `CostAnalysis.costOf(variables:)` takes coerced
+  values. Whether validation should be stricter is open.
 - **Validation budget.** `maxSteps` defaults to 1 000 000 (about a second
   on the VM); a document that needs more is `GQL230` (M4 spec section 8).
 
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,7 +4,7 @@
 
 ## Packages
 
-- [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation, wire protocol and diagnostics
+- [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation with opt-in limits and cost analysis, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): skeleton; code generator and its CLI, not usable yet (M8, M10)
@@ -20,7 +20,7 @@
 - [Schema](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/schema.md): build a schema from SDL, read, validate, extend and print it; resolve coordinates
 - [Scalars and codecs](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/scalars.md): the built-in scalar codecs and your own
 - [Introspection](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/introspection.md): the introspection query, a schema's answer, and a schema built from an answer
-- [Operation validation](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/validation.md): validate a document against a schema; the rules and their codes; custom rules; work limits
+- [Operation validation](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/validation.md): validate a document against a schema; the rules and their codes; custom rules; work limits; limit rules and cost analysis
 - [Example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/example/example.dart): a runnable program: report syntax errors, print a document, build a schema from SDL, validate a request
 
 ## Reference
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The Operation Validation guide covers the limit rules and cost analysis.
```

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -15,7 +15,8 @@ and the web (dart2js and dart2wasm). Part of [typed_graphql](https://github.com/
 > visitors, transformers, schema coordinates) and the schema (its model, building and
 > extending it from SDL, printing it, scalar codecs, validating it,
 > introspection both ways, resolving schema coordinates) and the validation
-> of executable documents by the specification's 30 rules. Execution
+> of executable documents by the specification's 30 rules, with opt-in
+> limit rules and cost analysis. Execution
 > arrives in M5 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
@@ -42,7 +43,8 @@ dependencies:
 ## Should I use this?
 
 - **Use it when** you need to parse, print, rewrite or inspect GraphQL text,
-  build and validate a schema from SDL, or validate operations against it,
+  build and validate a schema from SDL, or validate operations against it (with
+  limits on depth, aliases and cost),
   in Dart (VM, web or Wasm), and want every problem as a diagnostic with a
   stable code (and a place when the source is given), or a decode failure
   with a path
@@ -146,7 +148,7 @@ is run by the test suite, so what they print is what the package does.
 | [Schema](doc/schema.md) | Build a schema from SDL, read it, validate it, extend it, print it; resolve coordinates |
 | [Scalars and codecs](doc/scalars.md) | The built-in codecs and your own |
 | [Introspection](doc/introspection.md) | Write the introspection query, answer it from a schema, build a schema from an answer |
-| [Operation validation](doc/validation.md) | Validate a document against a schema; the rules and their codes; custom rules; work limits |
+| [Operation validation](doc/validation.md) | Validate a document against a schema; the rules and their codes; custom rules; work limits; limit rules and cost analysis |
 
 The API reference is generated by `dart doc` and groups every type under the
 same topics. Run it in this directory and open `doc/api/index.html`.
```

In `packages/typed_graphql/doc/validation.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -188,3 +188,198 @@ the fields that must merge. The run charges that work to a budget
 (`maxSteps`, a million by default); a document shaped to exceed it gets
 one `GQL230` error instead of keeping the server busy. `maxErrors` stops
 the run after that many errors with one `GQL000`.
+
+## Limits
+
+A document the specification accepts can still be too expensive to
+serve. These rules bound it; each is opt-in and none is in
+`DocumentValidator.specifiedRules`. Add one to the list of rules, as
+`DocumentValidator(rules: [...DocumentValidator.specifiedRules, ...])`.
+
+| Code | Rule | Counts |
+|---|---|---|
+| `GQL232` | `MaxDepthRule(maxDepth:)` | the deepest field |
+| `GQL233` | `MaxAliasesRule(maxAliases:)` | fields written with an alias |
+| `GQL234` | `MaxDirectivesRule(maxDirectives:)` | applied directives |
+| `GQL235` | `NoIntrospectionRule` | `__schema` and `__type` fields |
+| `GQL236` | `MaxIntrospectionDepthRule` | nested introspection lists |
+
+A top-level field has depth 1, a field in its selection set depth 2. Inline
+fragments and fragment spreads add no depth, and a spread counts as if its
+fragment were written there. Aliases and directives are counted with the
+fragments expanded: every spread counts what its fragment holds again. The
+directives counted are those on the operation, its variable definitions,
+fields, inline fragments and spreads. Each operation is measured once, in
+time linear in the document however often its fragments are spread. The
+messages say "more than" the limit for aliases and directives, and give the
+depth and "more than the maximum" for depth.
+
+`NoIntrospectionRule` reports every field whose type is an introspection
+type; `__typename` stays allowed. Switching introspection off is not a best
+practice, so use it only when you need it. `MaxIntrospectionDepthRule`
+ports graphql-js's rule: below a `__schema` or `__type` field, no path may
+pass through three of the list fields `fields`, `interfaces`,
+`possibleTypes` and `inputFields`.
+
+`DocumentValidator.recommendedRules` is `specifiedRules` plus
+`MaxIntrospectionDepthRule`, as graphql-js's `recommendedRules`. It is not
+the default of `rules`; whether it becomes the default is an open decision.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  final schema = switch (const SchemaBuilder().fromSdl(
+    const Parser()
+        .parse(Source('type Query { me: Query name: String }'))
+        .requireDocument(),
+  )) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure() => throw StateError('the schema is valid'),
+  };
+  final valid = switch (const SchemaValidator().validate(schema)) {
+    final ValidSchema valid => valid,
+    InvalidSchema() => throw StateError('the schema is valid'),
+  };
+  final source = Source('query Deep { me { me { me { name } } } }');
+  final document = const Parser().parse(source).requireDocument();
+  const validator = DocumentValidator(
+    rules: [...DocumentValidator.specifiedRules, MaxDepthRule(maxDepth: 3)],
+  );
+  switch (validator.validate(valid, document, source: source)) {
+    case ValidDocument():
+      print('valid');
+    case InvalidDocument(:final diagnostics):
+      for (final diagnostic in diagnostics) {
+        print(
+          '${diagnostic.span?.location} ${diagnostic.code.id} '
+          '${diagnostic.message}',
+        );
+      }
+  }
+}
+```
+
+It prints:
+
+```text
+1:1 GQL232 The operation "Deep" has a depth of 4, more than the maximum of 3.
+```
+
+## Cost
+
+`CostAnalysis` computes the static cost of an operation by the
+[IBM GraphQL cost directives draft](https://ibm.github.io/graphql-specs/cost-spec.html),
+and `MaxCostRule` limits it. The draft is not part of the specification, so
+its two directives are an opt-in of the schema:
+`SchemaBuilder(includesCostDirectives: true)` (also a flag of `Schema`)
+adds their definitions.
+
+```text
+directive @cost(weight: String!) on ARGUMENT_DEFINITION | ENUM
+  | FIELD_DEFINITION | INPUT_FIELD_DEFINITION | OBJECT | SCALAR
+directive @listSize(
+  assumedSize: Int
+  slicingArguments: [String!]
+  sizedFields: [String!]
+  requireOneSlicingArgument: Boolean = true
+) on FIELD_DEFINITION
+```
+
+With the flag, `SchemaValidator` also checks how the directives are used:
+
+| Code | Reported when |
+|---|---|
+| `GQL156` | a `@cost` weight is not a number |
+| `GQL157` | `@cost` is on an interface field or on its argument |
+| `GQL158` | `@listSize` is on a field that is not a list and has no `sizedFields` |
+| `GQL159` | a slicing argument is not an `Int` argument of the field |
+| `GQL160` | a sized field is not a list field of the return type |
+| `GQL161` | `assumedSize` is combined with slicing arguments that must be given and have no default |
+
+The analysis works without the flag too: every weight is then its default.
+Its model, in short (the doc comment of `CostAnalysis` is the contract):
+
+- A type weighs its `@cost` weight, else 1 for an object and 0 for a scalar
+  or an enum; an interface or a union weighs as its heaviest possible type;
+  an input object weighs 0.
+- A field weighs its `@cost` weight, else the weight of its named type.
+  Each argument given adds its own `@cost` weight, else the weight of its
+  type, plus the same for every input field written in its value.
+  Directives on the field add their arguments the same way. The raw cost of
+  a field is never below 0.
+- A list field has a size: the largest slicing argument given (a literal, or
+  a variable's value or default), else the largest default of a slicing
+  argument, else `assumedSize`, else `defaultListSize` (10 unless set). A
+  list field without `@listSize` has `defaultListSize`. With `sizedFields`
+  the field has size 1 and the listed child fields get the size.
+- The field cost of a selection set is the sum of each field's raw cost plus
+  its size times the field cost of its own selections. The type cost is the
+  sum of each field's size times its type weight plus the type cost of its
+  selections, and the root type's weight is added. Fragments add up in the
+  set that spreads them, an upper bound, in time linear in the document.
+- `__typename`, `__schema` and `__type` cost 0.
+
+`costOf(document, operation, variables:)` takes the coerced variable values
+for slicing arguments. `MaxCostRule` runs during validation, where there are
+none, so a variable counts with its default in the operation, else
+`defaultListSize`. The rule reports an operation when either cost is more
+than `maxCost` (`GQL238`).
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  final schema = switch (const SchemaBuilder(
+    includesCostDirectives: true,
+  ).fromSdl(
+    const Parser()
+        .parse(
+          Source('''
+type Query {
+  users(first: Int): [User]
+    @listSize(slicingArguments: ["first"], requireOneSlicingArgument: false)
+}
+
+type User @cost(weight: "2") {
+  name: String
+}
+'''),
+        )
+        .requireDocument(),
+  )) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure() => throw StateError('the schema is valid'),
+  };
+  final valid = switch (const SchemaValidator().validate(schema)) {
+    final ValidSchema valid => valid,
+    InvalidSchema() => throw StateError('the schema is valid'),
+  };
+  final source = Source('query Users { users(first: 5) { name } }');
+  final document = const Parser().parse(source).requireDocument();
+  final operation = document.definitions.whereType<OperationDefinition>().first;
+  print(CostAnalysis(schema).costOf(document, operation));
+
+  const validator = DocumentValidator(rules: [MaxCostRule(maxCost: 8)]);
+  switch (validator.validate(valid, document, source: source)) {
+    case ValidDocument():
+      print('valid');
+    case InvalidDocument(:final diagnostics):
+      for (final diagnostic in diagnostics) {
+        print('${diagnostic.code.id} ${diagnostic.message}');
+      }
+  }
+}
+```
+
+It prints:
+
+```text
+OperationCost(fieldCost: 2, typeCost: 11)
+GQL238 The operation "Users" has a field cost of 2 and a type cost of 11, more than the maximum of 8.
+```
+
+`SlicingArgumentsRule` (`GQL237`) is the draft's operation rule: a field
+whose `@listSize` has `slicingArguments` and keeps
+`requireOneSlicingArgument` must be given exactly one of them. An argument
+counts when its value is not the `null` literal; a variable counts.
````

- [ ] **Step 2: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 3: Commit**

```sh
git add CLAUDE.md README.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql/CHANGELOG.md packages/typed_graphql/README.md packages/typed_graphql/doc/validation.md
git commit -q -m "docs(typed_graphql): document the limit rules and cost analysis" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

From the spec's section 15, with the choice this plan makes:

- Question 2: `recommendedRules` exists and the default stays `specifiedRules`; recommendation: make `recommendedRules` the default (one line in `DocumentValidator`).
- Question 4: a slicing variable counts with its default in validation; `costOf(variables:)` takes coerced values for the server (M6).
- Question 6: `defaultListSize` is 10.
- Question 7: fragments add up in cost (an upper bound), and the type cost counts the root type.

## Self-review

- Spec coverage: section 10 (Tasks 1–2), section 11 (Tasks 3–6), section 12 fuzzers (Task 7), section 13 (Task 8), the codes of section 4 (each in its task).
- Every code block in this plan is the content of a commit that passed the green check; no placeholder remains.
- Type consistency: each task's Produces block is extracted from its commit.

## After the plan

Task 8 updates `docs/superpowers/HANDOFF.md`. Then the final whole-branch review and the merge, as the handoff's "How a stage is done" says.
