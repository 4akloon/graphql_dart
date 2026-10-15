# M4a Operation Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `validation/` layer of `packages/typed_graphql`: the rule framework, the 30 rules of spec §5 with `GQL200`–`GQL229`, field selection merging in linear time, the step budget (`GQL230`) and custom rules (`GQL231`), every graphql-js validation suite ported or recorded in `mapping/validation.csv`, hostile-document tests, and the Operation Validation guide (R0.3, R0.7, R3.1–R3.4, R3.6, R10.3, R11.1–R11.3).

**Architecture:** `DocumentValidator.validate(ValidSchema, Document)` walks the document once (`ValidationWalk` over `AstWalker`), with `TypeInfo` entered before and left after a `ParallelVisitor` of the internal `UsageIndex` and one visitor per `ValidationRule`. A rule is const configuration whose `createVisitor(ValidationContext)` gives a fresh visitor per run; it reports through the context. Rules that need an operation's fragment closure report at `leave(Document)`. `OverlappingFieldsCanBeMergedRule` delegates to `validation/overlap/` (XING's decomposition, linear in the expanded document). Work beyond the walk is charged to a step budget. The result is the sealed `DocumentValidationResult` (`ValidDocument` | `InvalidDocument`).

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`. graphql-js 17 in `reference/graphql-js` is the reference for messages and suites; the September2025 specification is the authority.

**Spec:** `docs/superpowers/specs/2026-10-14-m4-operation-validation-design.md` (sections 1–9, 12–15), section 3 of `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, `docs/requirements.md` R3.

**Base:** `main` at `1a5c135` (M3 and the agent-discoverability merge). Work on a branch `m4-operation-validation` in a worktree. The plan was verified by applying every task in order on that base, one commit per task, with the green check after each and the core suite on exe, dart2js and dart2wasm at the end. M4b (`2026-10-14-m4b-limits-and-cost.md`) follows on the same branch or after the merge.

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

The inputs most likely to bite a user that no single rule's suite exercises, each pinned by a test in the task that owns the code:

1. A document built in code nested 100000 deep (selections, an input object, a list): valid or the expected diagnostics, never a stack overflow, on the web too. Task 11, `hostile_nesting_test.dart`.
2. Fragments shaped to expand exponentially, or 1000 operations over one chain of 1000 fragments: one `GQL230`, not a hang. Task 11, `hostile_width_test.dart`; the budget itself in Task 2.
3. A conflict inside a fragment spread twice is reported once, at the fragment; a chain of 1000 fragments is merged once. Task 10, `field_merging_test.dart`.
4. A description on an operation, a fragment or a variable is never seen by a rule (graphql-js's `validate` never sees one). Task 2, `document_validator_test.dart` "the walk does not enter descriptions".
5. `maxErrors` stops a run with one `GQL000` and a throwing custom rule is a bug that surfaces, not a swallowed error. Task 11, `validate_test.dart` (the port of `validation-test.ts`).

## File map

| File | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/diagnostics/lexical_distance.dart` | graphql-js's `LexicalDistance` | 1 |
| `packages/typed_graphql/lib/src/diagnostics/suggestions.dart` | graphql-js's "Did you mean" text | 1 |
| `packages/typed_graphql/lib/src/schema/validation/value_problem_kind.dart` | Which rule of spec §5.6 a value problem breaks, so that operation validation reports each with the code of its own rule | 1 |
| `packages/typed_graphql/test/diagnostics/suggestions_test.dart` | Tests | 1 |
| `packages/typed_graphql/doc/validation.md` | Document | 2 |
| `packages/typed_graphql/lib/src/validation/document_validation_result.dart` | The result of validating a document against a schema | 2 |
| `packages/typed_graphql/lib/src/validation/document_validator.dart` | Checks an executable document against a schema (spec §5 | 2 |
| `packages/typed_graphql/lib/src/validation/meta_fields.dart` | The meta-fields of spec §4.1 "Type Name Introspection" and §4.2 "Schema Introspection" | 2 |
| `packages/typed_graphql/lib/src/validation/type_info.dart` | The types around the node a walk is at (R3.2), graphql-js's `TypeInfo` | 2 |
| `packages/typed_graphql/lib/src/validation/usage_index.dart` | The variable usages and fragment spreads of each executable definition, recorded during the one walk of a run, and the closures of operations over them | 2 |
| `packages/typed_graphql/lib/src/validation/validation_context.dart` | What the rules of one validation run share (R3.2, R3.6) | 2 |
| `packages/typed_graphql/lib/src/validation/validation_rule.dart` | One check of an executable document against a schema (R3.1, R3.6) | 2 |
| `packages/typed_graphql/lib/src/validation/validation_walk.dart` | The visitor of one validation run (R3.2), graphql-js's `visitWithTypeInfo` around `visitInParallel` | 2 |
| `packages/typed_graphql/lib/src/validation/variable_usage.dart` | A variable used as a value, with the input type expected where it stands, as graphql-js's `VariableUsage` | 2 |
| `packages/typed_graphql/test/validation/checked.dart` | A validated schema to check documents against, for a validation test | 2 |
| `packages/typed_graphql/test/validation/document_validator_test.dart` | Tests | 2 |
| `packages/typed_graphql/test/validation/type_info_test.dart` | Tests | 2 |
| `packages/typed_graphql/lib/src/validation/rules/executable_definitions_rule.dart` | Spec §5.1.1 "Executable Definitions" | 3 |
| `packages/typed_graphql/lib/src/validation/rules/known_operation_types_rule.dart` | Spec §5.2.1.1 "Operation Type Existence" | 3 |
| `packages/typed_graphql/lib/src/validation/rules/lone_anonymous_operation_rule.dart` | Spec §5.2.3.1 "Lone Anonymous Operation" | 3 |
| `packages/typed_graphql/lib/src/validation/rules/single_field_subscriptions_rule.dart` | Spec §5.2.4.1 "Single Root Field" | 3 |
| `packages/typed_graphql/lib/src/validation/rules/subscription_fields.dart` | The top-level fields of a subscription grouped by response key, as graphql-js's `collectFields` gathers them with `@skip` and `@include` forbidden (spec §5.2.4.1 `CollectSubscriptionFields`) | 3 |
| `packages/typed_graphql/lib/src/validation/rules/unique_operation_names_rule.dart` | Spec §5.2.2.1 "Operation Name Uniqueness" | 3 |
| `packages/typed_graphql/test/validation/rules/operation_rules_test.dart` | Tests | 3 |
| `packages/typed_graphql_conformance/mapping/validation.csv` | Document | 3 |
| `packages/typed_graphql_conformance/test/support/rule_port.dart` | graphql-js's validation harness (`validation/__tests__/harness.ts`) | 3 |
| `packages/typed_graphql_conformance/test/validation/executable_definitions_test.dart` | Tests | 3 |
| `packages/typed_graphql_conformance/test/validation/known_operation_types_test.dart` | Tests | 3 |
| `packages/typed_graphql_conformance/test/validation/lone_anonymous_operation_test.dart` | Tests | 3 |
| `packages/typed_graphql_conformance/test/validation/single_field_subscriptions_test.dart` | Tests | 3 |
| `packages/typed_graphql_conformance/test/validation/unique_operation_names_test.dart` | Tests | 3 |
| `packages/typed_graphql/lib/src/validation/rules/engine_ordered_sort.dart` | Sorts a short list as the JavaScript engines' `Array.prototype.sort` does, so a comparator that is not a total order (graphql-js's type suggestions compare by usage, then by inheritance, then by name) gives the order graphql-js gives | 4 |
| `packages/typed_graphql/lib/src/validation/rules/field_type_suggestions.dart` | The types to condition on when an abstract type lacks a field (graphql-js's `getSuggestedTypeNames`) | 4 |
| `packages/typed_graphql/lib/src/validation/rules/fields_on_correct_type_rule.dart` | Spec §5.3.1 "Field Selections" | 4 |
| `packages/typed_graphql/lib/src/validation/rules/fragments_on_composite_types_rule.dart` | Spec §5.5.1.3 "Fragments On Composite Types" | 4 |
| `packages/typed_graphql/lib/src/validation/rules/known_type_names_rule.dart` | Spec §5.5.1.2 "Fragment Spread Type Existence" and §5.8.2 "Variables Are Input Types" | 4 |
| `packages/typed_graphql/lib/src/validation/rules/scalar_leafs_rule.dart` | Spec §5.3.3 "Leaf Field Selections" | 4 |
| `packages/typed_graphql/lib/src/validation/rules/variables_are_input_types_rule.dart` | Spec §5.8.2 "Variables Are Input Types" | 4 |
| `packages/typed_graphql/test/validation/rules/type_rules_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/validation/fields_on_correct_type_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/validation/fragments_on_composite_types_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/validation/known_type_names_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/validation/scalar_leafs_test.dart` | Tests | 4 |
| `packages/typed_graphql_conformance/test/validation/variables_are_input_types_test.dart` | Tests | 4 |
| `packages/typed_graphql/lib/src/validation/rules/known_argument_names_rule.dart` | Spec §5.4.1 "Argument Names" | 5 |
| `packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart` | Spec §5.4.3 "Required Arguments" | 5 |
| `packages/typed_graphql/lib/src/validation/rules/unique_argument_names_rule.dart` | Spec §5.4.2 "Argument Uniqueness" | 5 |
| `packages/typed_graphql/test/validation/rules/argument_rules_test.dart` | Tests | 5 |
| `packages/typed_graphql_conformance/test/validation/known_argument_names_test.dart` | Tests | 5 |
| `packages/typed_graphql_conformance/test/validation/provided_required_arguments_test.dart` | Tests | 5 |
| `packages/typed_graphql_conformance/test/validation/unique_argument_names_test.dart` | Tests | 5 |
| `packages/typed_graphql/lib/src/validation/fragment_spread_collector.dart` | Finds the fragment spreads in a selection set, as graphql-js's `getFragmentSpreads` | 6 |
| `packages/typed_graphql/lib/src/validation/rules/known_fragment_names_rule.dart` | Spec §5.5.2.1 "Fragment spread target defined" | 6 |
| `packages/typed_graphql/lib/src/validation/rules/no_fragment_cycles_rule.dart` | Spec §5.5.2.2 "Fragment spreads must not form cycles" | 6 |
| `packages/typed_graphql/lib/src/validation/rules/no_unused_fragments_rule.dart` | Spec §5.5.1.4 "Fragments Must Be Used" | 6 |
| `packages/typed_graphql/lib/src/validation/rules/possible_fragment_spreads_rule.dart` | Spec §5.5.2.3 "Fragment spread is possible" | 6 |
| `packages/typed_graphql/lib/src/validation/rules/unique_fragment_names_rule.dart` | Spec §5.5.1.1 "Fragment Name Uniqueness" | 6 |
| `packages/typed_graphql/test/validation/rules/fragment_rules_test.dart` | Tests | 6 |
| `packages/typed_graphql_conformance/test/validation/known_fragment_names_test.dart` | Tests | 6 |
| `packages/typed_graphql_conformance/test/validation/no_fragment_cycles_test.dart` | Tests | 6 |
| `packages/typed_graphql_conformance/test/validation/no_unused_fragments_test.dart` | Tests | 6 |
| `packages/typed_graphql_conformance/test/validation/possible_fragment_spreads_test.dart` | Tests | 6 |
| `packages/typed_graphql_conformance/test/validation/unique_fragment_names_test.dart` | Tests | 6 |
| `packages/typed_graphql/lib/src/validation/rules/input_object_field_names_rule.dart` | Spec §5.6.2 "Input Object Field Names" | 7 |
| `packages/typed_graphql/lib/src/validation/rules/input_object_required_fields_rule.dart` | Spec §5.6.4 "Input Object Required Fields" | 7 |
| `packages/typed_graphql/lib/src/validation/rules/unique_input_field_names_rule.dart` | Spec §5.6.3 "Input Object Field Uniqueness" | 7 |
| `packages/typed_graphql/lib/src/validation/rules/values_of_correct_type_rule.dart` | Spec §5.6.1 "Values of Correct Type" | 7 |
| `packages/typed_graphql/lib/src/validation/value_problem_visitor.dart` | The visitor behind the three value rules (spec §5.6) | 7 |
| `packages/typed_graphql/test/validation/rules/value_rules_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/validation/unique_input_field_names_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/validation/values_of_correct_type_defaults_and_directives_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/validation/values_of_correct_type_enums_and_lists_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/validation/values_of_correct_type_input_objects_test.dart` | Tests | 7 |
| `packages/typed_graphql_conformance/test/validation/values_of_correct_type_test.dart` | Tests | 7 |
| `packages/typed_graphql/lib/src/validation/rules/directives_in_valid_locations_rule.dart` | Spec §5.7.2 "Directives Are In Valid Locations" | 8 |
| `packages/typed_graphql/lib/src/validation/rules/known_directives_rule.dart` | Spec §5.7.1 "Directives Are Defined" | 8 |
| `packages/typed_graphql/lib/src/validation/rules/unique_directives_per_location_rule.dart` | Spec §5.7.3 "Directives Are Unique Per Location" | 8 |
| `packages/typed_graphql/test/validation/rules/directive_rules_test.dart` | Tests | 8 |
| `packages/typed_graphql_conformance/test/validation/known_directives_test.dart` | Tests | 8 |
| `packages/typed_graphql_conformance/test/validation/unique_directives_per_location_test.dart` | Tests | 8 |
| `packages/typed_graphql/lib/src/validation/rules/no_undefined_variables_rule.dart` | Spec §5.8.3 "All Variable Uses Defined" | 9 |
| `packages/typed_graphql/lib/src/validation/rules/no_unused_variables_rule.dart` | Spec §5.8.4 "All Variables Used" | 9 |
| `packages/typed_graphql/lib/src/validation/rules/operation_visitor.dart` | A rule visitor that checks each operation once the walk left the document, when the fragment closures of the operations are known | 9 |
| `packages/typed_graphql/lib/src/validation/rules/unique_variable_names_rule.dart` | Spec §5.8.1 "Variable Uniqueness" | 9 |
| `packages/typed_graphql/lib/src/validation/rules/variables_in_allowed_position_rule.dart` | Spec §5.8.5 "All Variable Usages Are Allowed" | 9 |
| `packages/typed_graphql/test/validation/rules/variable_rules_test.dart` | Tests | 9 |
| `packages/typed_graphql_conformance/test/validation/no_undefined_variables_test.dart` | Tests | 9 |
| `packages/typed_graphql_conformance/test/validation/no_unused_variables_test.dart` | Tests | 9 |
| `packages/typed_graphql_conformance/test/validation/unique_variable_names_test.dart` | Tests | 9 |
| `packages/typed_graphql_conformance/test/validation/variables_in_allowed_position_test.dart` | Tests | 9 |
| `packages/typed_graphql/lib/src/validation/overlap/argument_text.dart` | A field's arguments as one text that is equal for two fields exactly when graphql-js's `sameArguments` holds | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/conflict_judge.dart` | Decides whether a pair of fields from one merged set conflicts as graphql-js's `findConflict` would report it | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/conflict_reports.dart` | The conflicts of field merging, one report per pair of distinct ancestors over the whole document (graphql-js memoizes the pairs it compared), reported in graphql-js's order | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/conflict_tree.dart` | One reported conflict of two fields with all the conflicts found between their subfields | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/field_conflict.dart` | Two fields that conflict, as graphql-js reports them | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/field_merging.dart` | Spec §5.3.2 "Field Selection Merging" without comparing every pair of fields (R3.3 | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/field_origin.dart` | Where a field is written | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/field_shape.dart` | The shape of a field's type for spec §5.3.2 `SameResponseShape` | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/fragment_path.dart` | The fragments expanded on the way from the top of a definition to the selection being merged | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/fragment_trail.dart` | The fragments spread between a selection set and a field it selects, innermost first | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/merge_item.dart` | A field in a merged selection | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/merge_split.dart` | Splits a [MergeWork] into classes as XING's linear field-merging algorithm does (the Sangria algorithm, R3.3), and lists the pairs that may conflict | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/merge_work.dart` | Fields with one response name at one place, to check together, and which of the two checks of spec §5.3.2 apply to them | 10 |
| `packages/typed_graphql/lib/src/validation/overlap/selection_collector.dart` | Collects the fields selected under the items of a merged set, as graphql-js's `getFieldsAndFragmentSpreads` collects one selection set | 10 |
| `packages/typed_graphql/lib/src/validation/rules/overlapping_fields_can_be_merged_rule.dart` | Spec §5.3.2 "Field Selection Merging" | 10 |
| `packages/typed_graphql/test/validation/rules/field_merging_test.dart` | Tests | 10 |
| `packages/typed_graphql_conformance/test/validation/overlapping_fields_can_be_merged_test.dart` | Tests | 10 |
| `packages/typed_graphql_conformance/test/validation/overlapping_fields_deep_conflicts_test.dart` | Tests | 10 |
| `packages/typed_graphql_conformance/test/validation/overlapping_fields_recursive_fragments_test.dart` | Tests | 10 |
| `packages/typed_graphql_conformance/test/validation/overlapping_fields_return_types_test.dart` | Tests | 10 |
| `packages/typed_graphql/test/validation/hostile_nesting_test.dart` | Tests | 11 |
| `packages/typed_graphql/test/validation/hostile_width_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/validation/validate_test.dart` | Tests | 11 |
| `packages/typed_graphql/CHANGELOG.md` | Modified | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12 |
| `packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart` | Modified | 1 |
| `packages/typed_graphql/lib/src/schema/validation/value_checker.dart` | Modified | 1 |
| `packages/typed_graphql/lib/src/schema/validation/value_problem.dart` | Modified | 1 |
| `packages/typed_graphql/test/schema/validation/value_checker_test.dart` | Modified | 1 |
| `llms.txt` | Modified | 2, 12 |
| `packages/typed_graphql/dartdoc_options.yaml` | Modified | 2 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | Modified | 2, 3, 4, 5, 6, 7, 8, 9, 10 |
| `packages/typed_graphql/lib/typed_graphql.dart` | Modified | 2, 3, 4, 5, 6, 7, 8, 9, 10 |
| `packages/typed_graphql_conformance/test/mapping_test.dart` | Modified | 3, 4, 5, 6, 7, 8, 9, 10, 11 |
| `CLAUDE.md` | Modified | 12 |
| `README.md` | Modified | 12 |
| `docs/discovery.md` | Modified | 12 |
| `docs/superpowers/HANDOFF.md` | Modified | 12 |
| `packages/typed_graphql/README.md` | Modified | 12 |
| `packages/typed_graphql/example/example.dart` | Modified | 12 |
| `packages/typed_graphql/pubspec.yaml` | Modified | 12 |
| `test/discovery/discovery_page_test.dart` | Modified | 12 |

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

### Task 1: Suggestions and a value checker for operations

graphql-js's did-you-mean text (`suggestionList`, `didYouMean`, `orList`, `naturalCompare`, `LexicalDistance`) moves into `diagnostics/` as the internal `Suggestions`, and M3b's `ValueChecker` gains what `ValuesOfCorrectTypeRule` needs (spec section 5): variables allowed as values, suggestions for unknown input fields and enum values, and a `ValueProblemKind` on each problem so three rules can split its findings.

**Files:**
- Create: `packages/typed_graphql/lib/src/diagnostics/lexical_distance.dart`, `packages/typed_graphql/lib/src/diagnostics/suggestions.dart`, `packages/typed_graphql/lib/src/schema/validation/value_problem_kind.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart`, `packages/typed_graphql/lib/src/schema/validation/value_checker.dart`, `packages/typed_graphql/lib/src/schema/validation/value_problem.dart`
- Test: `packages/typed_graphql/test/diagnostics/suggestions_test.dart`, `packages/typed_graphql/test/schema/validation/value_checker_test.dart`

**Interfaces:**
- Consumes: M3b's `ValueChecker`, `LeafValueChecker`, `ValueProblem` (`lib/src/schema/validation/`).
- Produces:
- Declarations (signatures as committed; the code is in the steps):

```dart
// diagnostics/lexical_distance.dart
final class LexicalDistance
  LexicalDistance(this.input)
  final String input
  int? measure(String option, int threshold)

// diagnostics/suggestions.dart
final class const Suggestions()
  List<String> listFor(String input, Iterable<String> options)
  String didYouMean(List<String> suggestions,
  String orList(List<String> items)
  int naturalCompare(String a, String b)

// schema/validation/leaf_value_checker.dart
  String? errorOf(

// schema/validation/value_problem_kind.dart
enum ValueProblemKind
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/diagnostics/suggestions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/diagnostics/suggestions.dart';

// The cases of graphql-js's suggestionList, didYouMean and naturalCompare
// suites (src/jsutils/__tests__).
void main() {
  const suggestions = Suggestions();

  group('listFor', () {
    test('returns results when input is empty', () {
      expect(suggestions.listFor('', ['a']), ['a']);
    });

    test('returns an empty list when there are no options', () {
      expect(suggestions.listFor('input', []), isEmpty);
    });

    test('returns options with small lexical distance', () {
      expect(suggestions.listFor('greenish', ['green']), ['green']);
      expect(suggestions.listFor('green', ['greenish']), ['greenish']);
    });

    test('rejects options with distance that exceeds threshold', () {
      expect(suggestions.listFor('aaaa', ['aaab']), ['aaab']);
      expect(suggestions.listFor('aaaa', ['aabb']), ['aabb']);
      expect(suggestions.listFor('aaaa', ['abbb']), isEmpty);
      expect(suggestions.listFor('ab', ['ca']), isEmpty);
    });

    test('returns options with different case', () {
      expect(suggestions.listFor('verylongstring', ['VERYLONGSTRING']), [
        'VERYLONGSTRING',
      ]);
      expect(suggestions.listFor('VERYLONGSTRING', ['VeryLongString']), [
        'VeryLongString',
      ]);
    });

    test('returns options with transpositions', () {
      expect(suggestions.listFor('agr', ['arg']), ['arg']);
      expect(suggestions.listFor('214365879', ['123456789']), ['123456789']);
    });

    test('sorts options by lexical distance', () {
      expect(suggestions.listFor('abc', ['a', 'ab', 'abc']), [
        'abc',
        'ab',
        'a',
      ]);
      expect(
        suggestions.listFor('GraphQl', [
          'graphics',
          'SQL',
          'GraphQL',
          'quarks',
          'mark',
        ]),
        ['GraphQL', 'graphics'],
      );
    });

    test('sorts options at the same distance naturally', () {
      expect(suggestions.listFor('a', ['az', 'ax', 'ay']), ['ax', 'ay', 'az']);
      expect(suggestions.listFor('abc', ['a1', 'a12', 'a2']), [
        'a1',
        'a2',
        'a12',
      ]);
      expect(
        suggestions.listFor('csutomer', [
          'store',
          'customer',
          'stomer',
          'some',
          'more',
        ]),
        ['customer', 'stomer', 'some', 'store'],
      );
    });

    test('drops long options against a short input at once', () {
      final long = 'a' * 100000;
      expect(suggestions.listFor('a', [long]), isEmpty);
      expect(suggestions.listFor(long, ['a']), isEmpty);
    });
  });

  group('didYouMean', () {
    test('is empty for no suggestion', () {
      expect(suggestions.didYouMean([]), '');
    });

    test('lists one, two and several suggestions', () {
      expect(suggestions.didYouMean(['A']), ' Did you mean "A"?');
      expect(suggestions.didYouMean(['A', 'B']), ' Did you mean "A" or "B"?');
      expect(
        suggestions.didYouMean(['A', 'B', 'C']),
        ' Did you mean "A", "B", or "C"?',
      );
    });

    test('lists at most five suggestions', () {
      expect(
        suggestions.didYouMean(['A', 'B', 'C', 'D', 'E', 'F']),
        ' Did you mean "A", "B", "C", "D", or "E"?',
      );
    });

    test('names the subject', () {
      expect(
        suggestions.didYouMean(['A'], subject: 'the letter'),
        ' Did you mean the letter "A"?',
      );
    });
  });

  group('naturalCompare', () {
    int compare(String a, String b) => suggestions.naturalCompare(a, b);

    test('handles empty strings and different lengths', () {
      expect(compare('', ''), 0);
      expect(compare('', 'a'), -1);
      expect(compare('1', ''), 1);
      expect(compare('A1', 'A1A'), -1);
      expect(compare('A1A', 'A1'), 1);
    });

    test('compares numbers by value', () {
      expect(compare('1', '2'), -1);
      expect(compare('2', '11'), -1);
      expect(compare('11', '2'), 1);
    });

    test('takes a leading zero alone', () {
      expect(compare('00', '00'), 0);
      expect(compare('0', '00'), -1);
      expect(compare('02', '11'), -1);
      expect(compare('011', '200'), -1);
      expect(compare('200', '011'), 1);
    });

    test('compares numbers embedded into names', () {
      expect(compare('a0a', 'a9a'), -1);
      expect(compare('a00a', 'a09a'), -1);
      expect(compare('a0a9', 'a0a1'), 1);
      expect(compare('a10a11a', 'a10a19a'), -1);
      expect(compare('a10a11b', 'a10a11a'), 1);
    });

    test('compares runs longer than any integer', () {
      expect(compare('a${'9' * 40}', 'a1${'0' * 40}'), -1);
    });
  });
}
```

In `packages/typed_graphql/test/schema/validation/value_checker_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import 'package:test/test.dart';
 import 'package:typed_graphql/src/schema/validation/value_checker.dart';
+import 'package:typed_graphql/src/schema/validation/value_problem_kind.dart';
 import 'package:typed_graphql/typed_graphql.dart';
 
 import '../built.dart';
@@ -43,6 +44,106 @@ input In { a: In b: Int }''').schema;
     expect(problem.message, 'Int cannot represent non-integer value: x');
   });
 
+  test('allowsVariables accepts a variable anywhere in the value', () {
+    final value = ObjectValue([
+      const ObjectField(Name('a'), Variable(Name('v'))),
+      const ObjectField(Name('b'), Variable(Name('w'))),
+    ]);
+    // The variables' types are the variable rules' to check.
+    expect(
+      ValueChecker(schema, allowsVariables: true).check(value, input),
+      isEmpty,
+    );
+  });
+
+  test('each problem has the kind of the rule it breaks', () {
+    final enums = Built('''
+type Query { a: Int }
+input Req { r: Int! s: Int }''').schema;
+    final value = ObjectValue([
+      const ObjectField(Name('s'), StringValue('x')),
+      const ObjectField(Name('t'), IntValue('1')),
+    ]);
+    final kinds = [
+      for (final problem in ValueChecker(
+        enums,
+      ).check(value, const NamedType(Name('Req'))))
+        problem.kind,
+    ];
+    expect(kinds, [
+      ValueProblemKind.missingField,
+      ValueProblemKind.invalid,
+      ValueProblemKind.unknownField,
+    ]);
+  });
+
+  group('includesSuggestions', () {
+    final enums = Built('''
+type Query { a: Int }
+enum Color { RED BLUE }
+input Pick { color: Color shade: Int }''').schema;
+    List<String> messages(Value value, String type, bool suggests) => [
+      for (final problem in ValueChecker(
+        enums,
+        includesSuggestions: suggests,
+      ).check(value, NamedType(Name(type))))
+        problem.message,
+    ];
+
+    test('suggests an enum value', () {
+      expect(messages(const EnumValue('RDE'), 'Color', true), [
+        'Value "RDE" does not exist in "Color" enum. Did you mean the enum '
+            'value "RED"?',
+      ]);
+      expect(messages(const StringValue('RED'), 'Color', true), [
+        'Enum "Color" cannot represent non-enum value: "RED". Did you mean '
+            'the enum value "RED"?',
+      ]);
+    });
+
+    test('suggests an input field', () {
+      expect(
+        messages(
+          ObjectValue([const ObjectField(Name('colr'), EnumValue('RED'))]),
+          'Pick',
+          true,
+        ),
+        [
+          'Expected value of type "Pick" not to include unknown field '
+              '"colr". Did you mean "color"? Found: { colr: RED }.',
+        ],
+      );
+    });
+
+    test('is off by default', () {
+      expect(messages(const EnumValue('RDE'), 'Color', false), [
+        'Value "RDE" does not exist in "Color" enum.',
+      ]);
+      expect(
+        messages(
+          ObjectValue([const ObjectField(Name('colr'), EnumValue('RED'))]),
+          'Pick',
+          false,
+        ),
+        [
+          'Expected value of type "Pick" not to include unknown field '
+              '"colr", found: { colr: RED }.',
+        ],
+      );
+    });
+  });
+
+  test('a deep value given to a leaf type is not printed whole', () {
+    Value value = ListValue(const []);
+    for (var depth = 0; depth < 100000; depth++) {
+      value = ListValue([value]);
+    }
+    final problem = ValueChecker(
+      schema,
+    ).check(value, const NamedType(Name('Int'))).single;
+    expect(problem.message, 'Int cannot represent non-integer value: [ ... ]');
+  });
+
   test('a value of an output or unknown type is left to the type rules', () {
     const value = IntValue('1');
     expect(
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/diagnostics/suggestions_test.dart test/schema/validation/value_checker_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/diagnostics/lexical_distance.dart`:

```dart
/// graphql-js's `LexicalDistance`: the Damerau-Levenshtein distance of an
/// option from one input, ignoring case, used to suggest names.
///
/// A case change alone counts as one edit. The rows are reused between
/// options, and an option whose distance exceeds the threshold is dropped
/// as soon as a whole row exceeds it, so a long input against short
/// options costs little.
final class LexicalDistance {
  /// Prepares to measure options against [input].
  LexicalDistance(this.input)
    : _inputLowerCase = input.toLowerCase(),
      _rows = List.generate(3, (_) => List.filled(input.length + 1, 0));

  /// The text the options are compared with.
  final String input;

  final String _inputLowerCase;
  final List<List<int>> _rows;

  /// The distance of [option] from [input]; null when it exceeds
  /// [threshold].
  int? measure(String option, int threshold) {
    if (input == option) {
      return 0;
    }
    final optionLowerCase = option.toLowerCase();
    if (_inputLowerCase == optionLowerCase) {
      return 1;
    }
    final (a, b) = optionLowerCase.length < _inputLowerCase.length
        ? (_inputLowerCase, optionLowerCase)
        : (optionLowerCase, _inputLowerCase);
    if (a.length - b.length > threshold) {
      return null;
    }
    if (!_fill(a, b, threshold)) {
      return null;
    }
    final distance = _rows[a.length % 3][b.length];
    return distance <= threshold ? distance : null;
  }

  // Fills the rows for [a] against [b], the shorter of the two, which is
  // never longer than the input, so the rows fit; false as soon as a row's
  // smallest cell exceeds [threshold].
  bool _fill(String a, String b, int threshold) {
    final rows = _rows;
    for (var j = 0; j <= b.length; j++) {
      rows[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      final current = rows[i % 3];
      var smallest = current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        current[j] = _cell(a, b, i, j, rows);
        if (current[j] < smallest) {
          smallest = current[j];
        }
      }
      if (smallest > threshold) {
        return false;
      }
    }
    return true;
  }

  static int _cell(String a, String b, int i, int j, List<List<int>> rows) {
    final up = rows[(i - 1) % 3];
    final current = rows[i % 3];
    final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
    var cell = _min(up[j] + 1, current[j - 1] + 1, up[j - 1] + cost);
    if (i > 1 &&
        j > 1 &&
        a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
        a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
      final transposed = rows[(i - 2) % 3][j - 2] + 1;
      if (transposed < cell) {
        cell = transposed;
      }
    }
    return cell;
  }

  static int _min(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
  }
}
```

Create `packages/typed_graphql/lib/src/diagnostics/suggestions.dart`:

```dart
import 'lexical_distance.dart';

/// graphql-js's "Did you mean" text: `suggestionList`, `didYouMean`,
/// `orList` and `naturalCompare`, shared by the messages that suggest a
/// name.
final class const Suggestions() {
  /// Creates the helper; it keeps no state.
  this;

  /// The most names [didYouMean] lists.
  static const int maxSuggestions = 5;

  static final RegExp _digit = RegExp('[0-9]');

  /// The [options] close to [input], closest first and then in natural
  /// order (graphql-js's `suggestionList`).
  List<String> listFor(String input, Iterable<String> options) {
    final distance = LexicalDistance(input);
    final threshold = (input.length * 0.4).floor() + 1;
    final distances = <String, int>{
      for (final option in options)
        option: ?distance.measure(option, threshold),
    };
    final sorted = distances.entries.toList()
      ..sort((a, b) {
        final difference = a.value - b.value;
        return difference != 0 ? difference : naturalCompare(a.key, b.key);
      });
    return [for (final entry in sorted) entry.key];
  }

  /// ` Did you mean "A", "B", or "C"?`, naming at most [maxSuggestions]
  /// of [suggestions] after [subject] when given; empty for no suggestion.
  String didYouMean(List<String> suggestions, {String? subject}) {
    if (suggestions.isEmpty) {
      return '';
    }
    final quoted = [
      for (final suggestion in suggestions.take(maxSuggestions))
        '"$suggestion"',
    ];
    return ' Did you mean ${subject == null ? '' : '$subject '}'
        '${orList(quoted)}?';
  }

  /// `A`, `A or B`, `A, B, or C` (graphql-js's `orList`).
  String orList(List<String> items) => switch (items) {
    [] => '',
    [final only] => only,
    [final first, final second] => '$first or $second',
    [...final rest, final last] => '${rest.join(', ')}, or $last',
  };

  /// Compares [a] and [b] with runs of digits as numbers, as graphql-js's
  /// `naturalCompare` does: negative, zero or positive.
  ///
  /// A run that starts with `0` is that zero alone. Runs compare by length
  /// and then by text, which is their numeric order without parsing them,
  /// so a run of any length compares the same on every platform.
  int naturalCompare(String a, String b) {
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      if (_isDigit(a, i) && _isDigit(b, j)) {
        final aEnd = _runEnd(a, i);
        final bEnd = _runEnd(b, j);
        final order = _compareRuns(a.substring(i, aEnd), b.substring(j, bEnd));
        if (order != 0) {
          return order;
        }
        (i, j) = (aEnd, bEnd);
      } else {
        final order = a.codeUnitAt(i).compareTo(b.codeUnitAt(j));
        if (order != 0) {
          return order;
        }
        (i, j) = (i + 1, j + 1);
      }
    }
    return (a.length - b.length).sign;
  }

  static bool _isDigit(String text, int index) =>
      _digit.matchAsPrefix(text, index) != null;

  static int _runEnd(String text, int start) {
    if (text.codeUnitAt(start) == 0x30) {
      return start + 1;
    }
    var end = start + 1;
    while (end < text.length && _isDigit(text, end)) {
      end++;
    }
    return end;
  }

  static int _compareRuns(String a, String b) =>
      a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b);
}
```

In `packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
+import '../../diagnostics/suggestions.dart';
 import '../../language/ast/value.dart';
-import '../../language/printer/printer.dart';
 import '../model/schema_type.dart';
+import 'bounded_value_printer.dart';
 
 /// Whether a constant literal is a value of a scalar or enum type, with
 /// the messages of graphql-js's `coerceInputLiteral` of the built-in
@@ -12,15 +13,23 @@ final class const LeafValueChecker() {
   /// Creates the checker; it keeps no state.
   this;
 
-  static const Printer _printer = Printer();
+  // Bounded: a value nested deeper than the printer can recurse is not
+  // printed whole (M3 deviation 14).
+  static const BoundedValuePrinter _printer = BoundedValuePrinter();
   static const int _minInt = -2147483648;
   static const int _maxInt = 2147483647;
   static const int _longestInt = 11;
   static final RegExp _integer = RegExp(r'^-?(0|[1-9][0-9]*)$');
 
   /// The message of why [value] is not a value of [type]; null when it is.
-  String? errorOf(Value value, SchemaType type) => switch (type) {
-    EnumType() => _enumError(value, type),
+  /// With [includesSuggestions], a wrong enum value gets graphql-js's
+  /// "Did you mean the enum value" text.
+  String? errorOf(
+    Value value,
+    SchemaType type, {
+    bool includesSuggestions = false,
+  }) => switch (type) {
+    EnumType() => _enumError(value, type, includesSuggestions),
     ScalarType(name: 'Int') => _intError(value),
     ScalarType(name: 'Float') when value is! IntValue && value is! FloatValue =>
       'Float cannot represent non numeric value: ${_printer.print(value)}',
@@ -51,14 +60,20 @@ final class const LeafValueChecker() {
     return null;
   }
 
-  String? _enumError(Value value, EnumType type) {
-    if (value is! EnumValue) {
-      return 'Enum "${type.name}" cannot represent non-enum value: '
-          '${_printer.print(value)}.';
+  String? _enumError(Value value, EnumType type, bool includesSuggestions) {
+    if (value is EnumValue && type.valueNamed(value.value) != null) {
+      return null;
     }
-    if (type.valueNamed(value.value) == null) {
-      return 'Value "${value.value}" does not exist in "${type.name}" enum.';
+    final printed = _printer.print(value);
+    final message = value is EnumValue
+        ? 'Value "$printed" does not exist in "${type.name}" enum.'
+        : 'Enum "${type.name}" cannot represent non-enum value: $printed.';
+    if (!includesSuggestions) {
+      return message;
     }
-    return null;
+    const suggestions = Suggestions();
+    final names = [for (final known in type.values) known.name];
+    return '$message'
+        '${suggestions.didYouMean(suggestions.listFor(printed, names), subject: 'the enum value')}';
   }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/value_checker.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import '../../diagnostics/suggestions.dart';
 import '../../language/ast/node.dart';
 import '../../language/ast/object_field.dart';
 import '../../language/ast/type_ref.dart';
@@ -9,11 +10,17 @@ import 'bounded_value_printer.dart';
 import 'input_object_shape.dart';
 import 'leaf_value_checker.dart';
 import 'value_problem.dart';
+import 'value_problem_kind.dart';
 
 /// Whether a constant value, such as a default value or an applied
 /// directive's argument, is a value of an input type (spec §3.10 "Input
 /// Coercion", graphql-js's `validateInputLiteral` without variables).
 ///
+/// With [allowsVariables], a variable anywhere in the value is accepted, as
+/// graphql-js's static `validateInputLiteral` accepts it for operation
+/// validation (spec §5.6.1); with [includesSuggestions], unknown input
+/// fields and enum values get graphql-js's "Did you mean" text.
+///
 /// It walks the value with its own stack, so a deeply nested value cannot
 /// overflow the call stack, and reports the problems in graphql-js's
 /// depth-first order. A type the schema does not have, or one that is not
@@ -21,12 +28,21 @@ import 'value_problem.dart';
 /// checked.
 final class ValueChecker(
   /// The schema whose types are known.
-  final Schema schema,
-) {
+  final Schema schema, {
+
+  /// Whether a variable is a valid value; otherwise it is reported as not
+  /// constant.
+  final bool allowsVariables = false,
+
+  /// Whether messages suggest the names of known input fields and enum
+  /// values.
+  final bool includesSuggestions = false,
+}) {
   /// Creates the checker for [schema].
   this;
 
   static const Printer _printer = Printer();
+  static const BoundedValuePrinter _values = BoundedValuePrinter();
 
   /// The problems of [value] as a value of [type], in report order.
   ///
@@ -37,8 +53,8 @@ final class ValueChecker(
     final work = <_Work>[_Check(value, type, null)];
     while (work.isNotEmpty) {
       switch (work.removeLast()) {
-        case _Report(:final message, :final node, :final path):
-          yield ValueProblem(message(), node, _Path.keys(path));
+        case _Report(:final message, :final node, :final path, :final kind):
+          yield ValueProblem(message(), node, _Path.keys(path), kind: kind);
         case _Check(:final value, :final type, :final path):
           work.addAll(_step(value, type, path, shapes).reversed);
       }
@@ -51,9 +67,10 @@ final class ValueChecker(
     _Path? path,
     Map<InputObjectType, InputObjectShape> shapes,
   ) => switch ((value, type)) {
+    (Variable(), _) when allowsVariables => const [],
     (Variable(), _) => [
       _report(
-        'Expected a constant value, found: ${_printer.print(value)}.',
+        'Expected a constant value, found: ${_values.print(value)}.',
         value,
         path,
       ),
@@ -95,7 +112,12 @@ final class ValueChecker(
       path,
     ),
     final type? => [
-      if (const LeafValueChecker().errorOf(value, type) case final m?)
+      if (const LeafValueChecker().errorOf(
+            value,
+            type,
+            includesSuggestions: includesSuggestions,
+          )
+          case final m?)
         _report(m, value, path),
     ],
     null => const [],
@@ -111,7 +133,7 @@ final class ValueChecker(
       return [
         _report(
           'Expected value of type "${type.name}" to be an object, found: '
-          '${_printer.print(value)}.',
+          '${_values.print(value)}.',
           value,
           path,
         ),
@@ -124,11 +146,10 @@ final class ValueChecker(
       for (final node in value.fields)
         if (shape.indexOf(node.name.value) == null)
           _reportLater(
-            () =>
-                'Expected value of type "${type.name}" not to include '
-                'unknown field "${node.name.value}", found: ${text.value}.',
+            () => _unknownField(type, node.name.value, text),
             node,
             path,
+            .unknownField,
           ),
       if (type.isOneOf) ?_oneOf(value, shape, type, path),
     ];
@@ -167,6 +188,7 @@ final class ValueChecker(
                 'field "${shape.fields[index].name}", found: ${text.value}.',
             value,
             path,
+            .missingField,
           ),
     ];
   }
@@ -196,14 +218,27 @@ final class ValueChecker(
     };
   }
 
+  String _unknownField(InputObjectType type, String name, _ObjectText text) {
+    const suggestions = Suggestions();
+    final suggestion = includesSuggestions
+        ? suggestions.didYouMean(
+            suggestions.listFor(name, [for (final f in type.fields) f.name]),
+          )
+        : '';
+    return 'Expected value of type "${type.name}" not to include unknown '
+        'field "$name"${suggestion.isEmpty ? ', found' : '.$suggestion Found'}'
+        ': ${text.value}.';
+  }
+
   static _Report _report(String message, Node node, _Path? path) =>
-      _Report(() => message, node, path);
+      _Report(() => message, node, path, .invalid);
 
   static _Report _reportLater(
     String Function() message,
     Node node,
     _Path? path,
-  ) => _Report(message, node, path);
+    ValueProblemKind kind,
+  ) => _Report(message, node, path, kind);
 }
 
 sealed class _Work {}
@@ -236,6 +271,7 @@ final class _Report(
   final String Function() message,
   final Node node,
   final _Path? path,
+  final ValueProblemKind kind,
 ) extends _Work {
   this;
 }
```

In `packages/typed_graphql/lib/src/schema/validation/value_problem.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../language/ast/node.dart';
+import 'value_problem_kind.dart';
 
 /// Why a constant value is not a value of its input type: a message, the
 /// node it is about and the path to that node inside the value.
@@ -8,8 +9,11 @@ final class ValueProblem(
 
   /// The node the problem is about: the value, an item, a field.
   final Node node,
-  List<Object> path,
-) {
+  List<Object> path, {
+
+  /// Which rule of spec §5.6 the problem breaks.
+  final ValueProblemKind kind = .invalid,
+}) {
   /// Creates a problem.
   this;
 
```

Create `packages/typed_graphql/lib/src/schema/validation/value_problem_kind.dart`:

```dart
/// Which rule of spec §5.6 a value problem breaks, so that operation
/// validation reports each with the code of its own rule.
enum ValueProblemKind {
  /// A value of the wrong type (spec §5.6.1 "Values of Correct Type").
  invalid,

  /// An input object field the type does not have (spec §5.6.2 "Input
  /// Object Field Names").
  unknownField,

  /// A required input object field that is missing (spec §5.6.4 "Input
  /// Object Required Fields").
  missingField,
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/diagnostics/suggestions_test.dart test/schema/validation/value_checker_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- A value printed in a schema validation message about a scalar or enum
  type is bounded as the other value messages are, so a deeply nested value
  cannot overflow the printer.
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/lexical_distance.dart packages/typed_graphql/lib/src/diagnostics/suggestions.dart packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart packages/typed_graphql/lib/src/schema/validation/value_checker.dart packages/typed_graphql/lib/src/schema/validation/value_problem.dart packages/typed_graphql/lib/src/schema/validation/value_problem_kind.dart packages/typed_graphql/test/diagnostics/suggestions_test.dart packages/typed_graphql/test/schema/validation/value_checker_test.dart
git commit -q -m "feat(typed_graphql): suggest names and accept variables in the value checker" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: The validation framework

The framework of spec section 3: `ValidationRule`, `ValidationContext` (reporting, the error limit, the step budget with `GQL230`, fragment lookup and the usage index), `TypeInfo`, `MetaFields`, `VariableUsage`, `UsageIndex`, `ValidationWalk` and `DocumentValidator` with the sealed `DocumentValidationResult`. `specifiedRules` is empty here; Tasks 3–10 fill it. The `validation` dartdoc category, the first page of the guide and its `llms.txt` entry (the discovery suite checks that `llms.txt` lists every guide) come with it.

**Files:**
- Create: `packages/typed_graphql/doc/validation.md`, `packages/typed_graphql/lib/src/validation/document_validation_result.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/src/validation/meta_fields.dart`, `packages/typed_graphql/lib/src/validation/type_info.dart`, `packages/typed_graphql/lib/src/validation/usage_index.dart`, `packages/typed_graphql/lib/src/validation/validation_context.dart`, `packages/typed_graphql/lib/src/validation/validation_rule.dart`, `packages/typed_graphql/lib/src/validation/validation_walk.dart`, `packages/typed_graphql/lib/src/validation/variable_usage.dart`
- Modify: `llms.txt`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/dartdoc_options.yaml`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/validation/checked.dart`, `packages/typed_graphql/test/validation/document_validator_test.dart`, `packages/typed_graphql/test/validation/type_info_test.dart`

**Interfaces:**
- Consumes: Task 1 (`Suggestions`); the language walker (`AstWalker`, `ParallelVisitor`), `ValidSchema`.
- Produces:
- Diagnostic codes: `GQL230`, `GQL231`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/document_validation_result.dart
sealed class DocumentValidationResult
  const DocumentValidationResult()
  ValidSchema get schema
  Document get document
  List<Diagnostic> get diagnostics
final class ValidDocument extends DocumentValidationResult
  const ValidDocument._(this.schema, this.document)
  factory ValidDocument.assumeValid(ValidSchema schema, Document document)
  final ValidSchema schema
  final Document document
  List<Diagnostic> get diagnostics
final class InvalidDocument(…)

// validation/document_validator.dart
final class const DocumentValidator
  DocumentValidationResult validate(

// validation/meta_fields.dart
final class MetaFields
  MetaFields._()
  static SchemaField? fieldOf(

// validation/type_info.dart
final class TypeInfo
  TypeInfo(this.schema)
  final Schema schema
  TypeRef? get type
  SchemaType? get parentType
  SchemaField? get fieldDefinition
  TypeRef? get inputType
  TypeRef? get parentInputType
  Value? get defaultValue
  SchemaDirective? get directive
  InputValue? get argument
  SchemaEnumValue? get enumValue
  void enter(Node node)
  void leave(Node node)

// validation/usage_index.dart
final class UsageIndex extends AstVisitor
  UsageIndex(this._typeInfo, this._spend, this._fragmentNamed)
  final bool Function(int steps) _spend
  final FragmentDefinition? Function(String name) _fragmentNamed
  VisitAction enter(Node node)
  void leave(Node node)
  List<VariableUsage> variableUsagesOf(ExecutableDefinition definition)
  List<FragmentDefinition> recursivelyReferencedFragments(
  List<VariableUsage> recursiveVariableUsages(OperationDefinition operation)

// validation/validation_context.dart
final class ValidationContext
  ValidationContext(
  final Schema schema
  final Document document
  final TypeInfo typeInfo
  final bool includesSuggestions
  final int maxSteps
  bool get isAborted
  void report(DiagnosticCode code, String message, List<Node> nodes)
  bool spend(int steps)
  FragmentDefinition? fragmentNamed(String name)
  List<VariableUsage> variableUsagesOf(ExecutableDefinition definition)
  List<FragmentDefinition> recursivelyReferencedFragments(
  List<VariableUsage> recursiveVariableUsages(OperationDefinition operation)
  AstVisitor visitorFor(List<AstVisitor> visitors)

// validation/validation_rule.dart
abstract class ValidationRule
  const ValidationRule()
  AstVisitor createVisitor(ValidationContext context)

// validation/validation_walk.dart
final class ValidationWalk extends AstVisitor
  ValidationWalk(this._context, UsageIndex usages, List<AstVisitor> visitors)
  VisitAction enter(Node node)
  void leave(Node node)

// validation/variable_usage.dart
final class VariableUsage(…)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/checked.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../schema/built.dart';

/// A validated schema to check documents against, for a validation test.
final class Checked {
  /// Builds and validates [sdl]; fails the test when it is not valid.
  Checked(String sdl)
    : schema = switch (const SchemaValidator().validate(Built(sdl).schema)) {
        final ValidSchema valid => valid,
        InvalidSchema(:final diagnostics) => fail('$diagnostics'),
      };

  /// The schema.
  final ValidSchema schema;

  /// [text] parsed without limits and validated with [validator].
  DocumentValidationResult validate(
    String text, {
    DocumentValidator validator = const DocumentValidator(),
  }) {
    final source = Source(text);
    final document = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source).requireDocument();
    return validator.validate(schema, document, source: source);
  }

  /// The diagnostics of [text] checked by [rules], each as `line:column
  /// id message`.
  List<String> errors(String text, List<ValidationRule> rules) => [
    for (final diagnostic in validate(
      text,
      validator: DocumentValidator(rules: rules),
    ).diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];
}
```

Create `packages/typed_graphql/test/validation/document_validator_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

/// Runs [onEnter] at each node and [onLeave] when the walk leaves the
/// document.
final class _Probe extends ValidationRule {
  const _Probe({this.onEnter, this.onLeave});

  final void Function(ValidationContext context, Node node)? onEnter;
  final void Function(ValidationContext context)? onLeave;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ProbeVisitor(this, context);
}

final class _ProbeVisitor extends AstVisitor {
  _ProbeVisitor(this.probe, this.context);

  final _Probe probe;
  final ValidationContext context;

  @override
  VisitAction enter(Node node) {
    probe.onEnter?.call(context, node);
    return VisitAction.next;
  }

  @override
  void leave(Node node) {
    if (node is Document) {
      probe.onLeave?.call(context);
    }
  }
}

void main() {
  final checked = Checked('''
type Query { name: String friend: Query }
''');
  final fieldsReported = _Probe(
    onEnter: (context, node) {
      if (node is Field) {
        context.report(
          DiagnosticCode.customRuleViolation,
          'field ${node.name.value}',
          [node, node.name],
        );
      }
    },
  );

  test('a document no rule reports is valid and bound to the schema', () {
    final result = checked.validate('{ name }');
    expect(result, isA<ValidDocument>());
    expect(result.schema, same(checked.schema));
    expect(result.diagnostics, isEmpty);
  });

  test('a report points at the first node and relates the others', () {
    final result = checked.validate(
      '{ name }',
      validator: DocumentValidator(rules: [fieldsReported]),
    );
    final diagnostic = (result as InvalidDocument).diagnostics.single;
    expect(diagnostic.code, DiagnosticCode.customRuleViolation);
    expect(diagnostic.span?.text, 'name');
    expect(diagnostic.span?.location, const SourceLocation(1, 3));
    expect(diagnostic.related, hasLength(1));
  });

  test('without a source a report has no span', () {
    final document = const Parser().parse(Source('{ name }')).requireDocument();
    final result = DocumentValidator(
      rules: [fieldsReported],
    ).validate(checked.schema, document);
    expect(result.diagnostics.single.span, isNull);
  });

  test('the error limit stops the walk with GQL000', () {
    var fieldsSeen = 0;
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is Field) {
          fieldsSeen++;
          context.report(DiagnosticCode.customRuleViolation, 'field', [node]);
        }
      },
    );
    final result = checked.validate(
      '{ name name name name }',
      validator: DocumentValidator(rules: [rule], maxErrors: 2),
    );
    expect(result.diagnostics.map((diagnostic) => diagnostic.code.id), [
      'GQL231',
      'GQL231',
      'GQL000',
    ]);
    expect(fieldsSeen, 3);
  });

  test('spending past the budget reports GQL230 once and stops', () {
    var fieldsSeen = 0;
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is Field) {
          fieldsSeen++;
          context.spend(10);
        }
      },
    );
    final result = checked.validate(
      '{ name name name name }',
      validator: DocumentValidator(rules: [rule], maxSteps: 15),
    );
    final diagnostic = result.diagnostics.single;
    expect(diagnostic.code, DiagnosticCode.documentTooComplex);
    expect(diagnostic.span?.text, '{ name name name name }');
    expect(fieldsSeen, 2);
  });

  test('includesSuggestions reaches the context', () {
    bool? seen;
    final rule = _Probe(
      onLeave: (context) => seen = context.includesSuggestions,
    );
    checked.validate(
      '{ name }',
      validator: DocumentValidator(rules: [rule], includesSuggestions: false),
    );
    expect(seen, isFalse);
  });

  test('usage queries throw before the walk has left the document', () {
    var isChecked = false;
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is OperationDefinition) {
          expect(() => context.variableUsagesOf(node), throwsStateError);
          isChecked = true;
        }
      },
    );
    checked.validate('{ name }', validator: DocumentValidator(rules: [rule]));
    expect(isChecked, isTrue);
  });

  test('variable usages are collected through fragments, each once', () {
    final lines = <String>[];
    final rule = _Probe(
      onLeave: (context) {
        for (final definition in context.document.definitions) {
          if (definition is! OperationDefinition) {
            continue;
          }
          final fragments = context.recursivelyReferencedFragments(definition);
          final usages = context.recursiveVariableUsages(definition);
          lines
            ..add(fragments.map((fragment) => fragment.name.value).join(' '))
            ..add(usages.map((usage) => usage.node.name.value).join(' '));
        }
      },
    );
    checked.validate(r'''
query Q($a: String) { ...A friend { ...B } }
fragment A on Query { ...B ...A name @include(if: $a) }
fragment B on Query { friend { ...A name @skip(if: $b) } }
''', validator: DocumentValidator(rules: [rule]));
    expect(lines, ['A B', 'a b']);
  });

  test('a variable usage knows its expected type and default', () {
    final lines = <String>[];
    final rule = _Probe(
      onLeave: (context) {
        final operation = context.document.definitions.single;
        for (final usage in context.variableUsagesOf(
          operation as OperationDefinition,
        )) {
          lines.add(
            '${usage.node.name.value} ${const Printer().print(usage.type!)}',
          );
        }
      },
    );
    checked.validate(
      r'query ($a: Boolean!) { name @include(if: $a) }',
      validator: DocumentValidator(rules: [rule]),
    );
    expect(lines, ['a Boolean!']);
  });

  test('a fragment name shared by two definitions means the last one', () {
    String? seen;
    final rule = _Probe(
      onLeave: (context) =>
          seen = context.fragmentNamed('F')?.typeCondition.name.value,
    );
    checked.validate(
      'fragment F on Query { name } fragment F on Missing { name }',
      validator: DocumentValidator(rules: [rule]),
    );
    expect(seen, 'Missing');
  });

  test('the walk does not enter descriptions', () {
    final strings = <String>[];
    final rule = _Probe(
      onEnter: (context, node) {
        if (node is StringValue) strings.add(node.value);
      },
    );
    checked.validate(
      r'"o" query Q("v" $a: String = "d") { name } '
      '"f" fragment F on Query { name }',
      validator: DocumentValidator(rules: [rule]),
    );
    expect(strings, ['d']);
  });
}
```

Create `packages/typed_graphql/test/validation/type_info_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

/// Records what [TypeInfo] says at each node of a kind it is asked about.
final class _Recorder extends ValidationRule {
  _Recorder(this.describe);

  final String? Function(Node node, TypeInfo info) describe;
  final List<String> lines = [];

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _RecordingVisitor(this, context.typeInfo);
}

final class _RecordingVisitor extends AstVisitor {
  _RecordingVisitor(this.recorder, this.info);

  final _Recorder recorder;
  final TypeInfo info;

  @override
  VisitAction enter(Node node) {
    if (recorder.describe(node, info) case final line?) {
      recorder.lines.add(line);
    }
    return VisitAction.next;
  }
}

void main() {
  final checked = Checked('''
type Query {
  pet(id: ID! = "1", filter: Filter): Pet
  pets(ids: [[ID!]]): [Pet]
  scalar: Int
}
interface Pet { name: String }
type Dog implements Pet { name: String barks: Boolean }
type Cat implements Pet { name: String }
union Animal = Dog | Cat
input Filter { color: Color = RED, nested: Filter }
enum Color { RED GREEN }
directive @tag(label: String = "x") on FIELD
''');
  const printer = Printer();
  String text(TypeRef? type) => type == null ? '-' : printer.print(type);

  List<String> record(
    String document,
    String? Function(Node node, TypeInfo info) describe,
  ) {
    final recorder = _Recorder(describe);
    checked.validate(document, validator: DocumentValidator(rules: [recorder]));
    return recorder.lines;
  }

  test('a field has its parent type, definition and type', () {
    final lines = record('{ pet { name ... on Dog { barks } } }', (node, info) {
      if (node is! Field) {
        return null;
      }
      return '${node.name.value}: ${info.parentType?.name} '
          '${info.fieldDefinition?.name} ${text(info.type)}';
    });
    expect(lines, [
      'pet: Query pet Pet',
      'name: Pet name String',
      'barks: Dog barks Boolean',
    ]);
  });

  test('meta-fields resolve where graphql-js resolves them', () {
    final lines = record(
      '{ __typename __schema { __typename } pet { __typename __type } }',
      (node, info) =>
          node is Field ? '${node.name.value}: ${text(info.type)}' : null,
    );
    expect(lines, [
      '__typename: String!',
      '__schema: __Schema!',
      '__typename: String!',
      'pet: Pet',
      '__typename: String!',
      // __type exists only on the query root.
      '__type: -',
    ]);
  });

  test('unknown fields and types give nulls', () {
    final lines = record(
      '{ missing { name } ... on Missing { scalar } }',
      (node, info) => node is Field
          ? '${node.name.value}: ${info.parentType?.name} ${text(info.type)}'
          : null,
    );
    expect(lines, ['missing: Query -', 'name: null -', 'scalar: null -']);
  });

  test('an inline fragment without a type condition keeps the type', () {
    final lines = record(
      '{ pet { ... { name } } }',
      (node, info) => node is InlineFragment ? text(info.type) : null,
    );
    expect(lines, ['Pet']);
  });

  test('arguments, list items and input fields have input types', () {
    final lines = record(
      r'query ($c: Color) { pet(id: 1, filter: { color: $c, nested: {} }) '
      'pets(ids: [[1]]) { name } }',
      (node, info) => switch (node) {
        Argument(:final name) || ObjectField(:final name) =>
          '${name.value}: ${text(info.inputType)} '
              'default ${info.defaultValue == null ? '-' : printer.print(info.defaultValue!)}',
        ListValue() =>
          'list: ${text(info.inputType)} in '
              '${text(info.parentInputType)}',
        Variable(:final name) =>
          '\$${name.value}: ${text(info.inputType)} in '
              '${text(info.parentInputType)}',
        _ => null,
      },
    );
    expect(lines, [
      // A variable definition's variable has the definition's type.
      r'$c: Color in -',
      'id: ID! default "1"',
      'filter: Filter default -',
      'color: Color default RED',
      r'$c: Color in Filter',
      'nested: Filter default -',
      'ids: [[ID!]] default -',
      'list: [ID!] in [[ID!]]',
      'list: ID! in [ID!]',
    ]);
  });

  test('a variable definition has its input type', () {
    final lines = record(
      r'query ($a: [Color!], $b: Pet, $c: Missing) { scalar }',
      (node, info) => node is VariableDefinition ? text(info.inputType) : null,
    );
    expect(lines, ['[Color!]', '-', '-']);
  });

  test('an enum value, a directive and an argument have definitions', () {
    final lines = record(
      '{ pet(filter: { color: GREEN }) { name @tag(label: "a") } }',
      (node, info) => switch (node) {
        EnumValue() => 'enum ${info.enumValue?.name}',
        Directive() => 'directive ${info.directive?.name}',
        Argument() =>
          'argument ${info.argument?.name} '
              'of ${info.directive?.name ?? info.fieldDefinition?.name}',
        _ => null,
      },
    );
    expect(lines, [
      'argument filter of pet',
      'enum GREEN',
      'directive tag',
      'argument label of tag',
    ]);
  });

  test('state is left behind when the walk leaves a node', () {
    final lines = record(
      '{ pet(id: 1) { name } scalar }',
      (node, info) => node is Field && node.name.value == 'scalar'
          ? '${info.argument} ${info.directive} ${info.parentType?.name} '
                '${text(info.inputType)}'
          : null,
    );
    expect(lines, ['null null Query -']);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/document_validator_test.dart test/validation/type_info_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -323,5 +323,15 @@ enum DiagnosticCode(
   /// result without its `ofType`: the type is deeper than the query read
   /// (spec §4.2), or a chain of more than 100 wrappers, the most a query
   /// can read.
-  introspectionTypeTooDeep('GQL155');
+  introspectionTypeTooDeep('GQL155'),
+
+  /// `GQL230`: validating a document needed more work than the
+  /// validator's step budget allows, such as fragments that expand to
+  /// more fields than the budget, or many operations each spreading a
+  /// long chain of fragments. Validation stops there.
+  documentTooComplex('GQL230'),
+
+  /// `GQL231`: a problem a custom validation rule reports (R3.6); its
+  /// message says what the rule checks.
+  customRuleViolation('GQL231');
 }
```

Create `packages/typed_graphql/lib/src/validation/document_validation_result.dart`:

```dart
import '../diagnostics/diagnostic.dart';
import '../language/ast/document.dart';
import '../schema/validation/schema_validation_result.dart';

/// The result of validating a document against a schema:
/// [ValidDocument] or [InvalidDocument] (R3.4). An invalid document never
/// throws.
///
/// {@category validation}
sealed class DocumentValidationResult {
  /// Creates a result.
  const DocumentValidationResult();

  /// The schema the document was validated against.
  ValidSchema get schema;

  /// The document that was validated.
  Document get document;

  /// The problems found, in report order; empty for a [ValidDocument].
  List<Diagnostic> get diagnostics;
}

/// A document that passed every rule of a run, bound to the schema it was
/// validated against (R3.4).
///
/// Only `DocumentValidator.validate` and [ValidDocument.assumeValid] make
/// one, so the executor knows the document was checked; it also checks that
/// [schema] is the schema it executes against.
///
/// {@category validation}
final class ValidDocument extends DocumentValidationResult {
  const ValidDocument._(this.schema, this.document);

  /// Binds [document] to [schema] without validating it, for a document
  /// known to be valid, such as a trusted document checked when it was
  /// registered; nothing checks it.
  factory ValidDocument.assumeValid(ValidSchema schema, Document document) =>
      ValidDocument._(schema, document);

  @override
  final ValidSchema schema;

  @override
  final Document document;

  @override
  List<Diagnostic> get diagnostics => const [];
}

/// A document that breaks at least one rule of a run.
///
/// {@category validation}
final class InvalidDocument(
  @override final ValidSchema schema,
  @override final Document document,
  List<Diagnostic> diagnostics,
) extends DocumentValidationResult {
  /// Creates the result of validating [document].
  this : assert(diagnostics.isNotEmpty, 'an invalid document has a problem');

  @override
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql/lib/src/validation/document_validator.dart`:

````dart
import '../diagnostics/diagnostic_sink.dart';
import '../diagnostics/source.dart';
import '../language/ast/document.dart';
import '../language/visitor/ast_walker.dart';
import '../schema/validation/schema_validation_result.dart';
import 'document_validation_result.dart';
import 'validation_context.dart';
import 'validation_rule.dart';

/// Checks an executable document against a schema (spec §5; R3.1–R3.4):
/// every rule in one walk, the result a [ValidDocument] or an
/// [InvalidDocument] with every error up to [maxErrors].
///
/// The default rules are [specifiedRules], the 30 rules of spec §5. Add
/// limits or custom rules to a copy of the list:
///
/// ```dart
/// const validator = DocumentValidator(
///   rules: [...DocumentValidator.specifiedRules, NoDogsRule()],
/// );
/// ```
///
/// {@category validation}
final class const DocumentValidator({
  /// The rules each run checks, in the order their visitors are called
  /// at each node.
  final List<ValidationRule> rules = specifiedRules,

  /// The most errors a run reports; the next becomes `GQL000` and stops
  /// the run, as graphql-js's `maxErrors`.
  final int maxErrors = DiagnosticSink.defaultMaxErrors,

  /// Whether messages may suggest names ("Did you mean ..."); a
  /// production server turns them off (R5.15).
  final bool includesSuggestions = true,

  /// The most work a run may do beyond its one walk; see
  /// [ValidationContext.spend].
  final int maxSteps = ValidationContext.defaultMaxSteps,
}) {
  /// Creates a validator.
  this;

  /// The rules of spec §5, in graphql-js's order.
  static const List<ValidationRule> specifiedRules = [];

  /// Validates [document] against [schema]; diagnostics point into
  /// [source] when it is given, the text [document] was parsed from.
  DocumentValidationResult validate(
    ValidSchema schema,
    Document document, {
    Source? source,
  }) {
    final sink = DiagnosticSink(maxErrors: maxErrors);
    final context = ValidationContext(
      schema.schema,
      document,
      sink,
      source: source,
      includesSuggestions: includesSuggestions,
      maxSteps: maxSteps,
    );
    final visitors = [for (final rule in rules) rule.createVisitor(context)];
    const AstWalker().walk(document, context.visitorFor(visitors));
    return sink.hasErrors
        ? InvalidDocument(schema, document, sink.diagnostics)
        : ValidDocument.assumeValid(schema, document);
  }
}
````

Create `packages/typed_graphql/lib/src/validation/meta_fields.dart`:

```dart
import '../language/ast/name.dart';
import '../language/ast/type_ref.dart';
import '../schema/model/input_value.dart';
import '../schema/model/schema_field.dart';
import '../schema/model/schema_type.dart';
import '../schema/schema.dart';

/// The meta-fields of spec §4.1 "Type Name Introspection" and §4.2 "Schema
/// Introspection": fields every selection may ask for although no type
/// declares them.
final class MetaFields {
  MetaFields._();

  /// `__typename: String!`, on every composite type.
  static final SchemaField typename = SchemaField(
    '__typename',
    const NonNullType(NamedType(Name('String'))),
    description: 'The name of the current Object type at runtime.',
  );

  /// `__schema: __Schema!`, on the query root type.
  static final SchemaField schema = SchemaField(
    '__schema',
    const NonNullType(NamedType(Name('__Schema'))),
    description: 'Access the current type schema of this server.',
  );

  /// `__type(name: String!): __Type`, on the query root type.
  static final SchemaField type = SchemaField(
    '__type',
    const NamedType(Name('__Type')),
    description: 'Request the type information of a single type.',
    arguments: [
      InputValue('name', const NonNullType(NamedType(Name('String')))),
    ],
  );

  /// The field named [name] of [parentType] in [schema], meta-fields
  /// included, as graphql-js's `GraphQLSchema.getField`; null when there
  /// is none.
  static SchemaField? fieldOf(
    Schema schema,
    SchemaType parentType,
    String name,
  ) => switch (name) {
    '__schema' when _isQueryRoot(schema, parentType) => MetaFields.schema,
    '__type' when _isQueryRoot(schema, parentType) => type,
    '__typename' when parentType.isCompositeType => typename,
    _ => switch (parentType) {
      ObjectType() => parentType.fieldNamed(name),
      InterfaceType() => parentType.fieldNamed(name),
      _ => null,
    },
  };

  static bool _isQueryRoot(Schema schema, SchemaType type) =>
      switch (schema.queryTypeName) {
        final name? => identical(schema.typeNamed(name), type),
        null => false,
      };
}
```

Create `packages/typed_graphql/lib/src/validation/type_info.dart`:

```dart
import '../language/ast/argument.dart';
import '../language/ast/directive.dart';
import '../language/ast/executable_definition.dart';
import '../language/ast/name.dart';
import '../language/ast/node.dart';
import '../language/ast/object_field.dart';
import '../language/ast/selection.dart';
import '../language/ast/selection_set.dart';
import '../language/ast/type_ref.dart';
import '../language/ast/value.dart';
import '../language/ast/variable_definition.dart';
import '../schema/model/input_value.dart';
import '../schema/model/schema_directive.dart';
import '../schema/model/schema_enum_value.dart';
import '../schema/model/schema_field.dart';
import '../schema/model/schema_type.dart';
import '../schema/relations/type_comparator.dart';
import '../schema/schema.dart';
import 'meta_fields.dart';

/// The types around the node a walk is at (R3.2), graphql-js's
/// `TypeInfo`: [enter] and [leave] keep stacks of the output types, the
/// parent types, the field definitions, the input types and the default
/// values, and the current directive, argument and enum value.
///
/// `DocumentValidator` updates one for each run before the rules enter a
/// node and after they leave it, and rules read it through
/// `ValidationContext.typeInfo`. Each getter is null where the document
/// names something the schema does not have.
///
/// {@category validation}
final class TypeInfo {
  /// Creates the state of a walk over documents for [schema].
  TypeInfo(this.schema);

  /// The schema whose types are looked up.
  final Schema schema;

  static const TypeComparator _types = TypeComparator();

  final List<TypeRef?> _outputTypes = [];
  final List<SchemaType?> _parentTypes = [];
  final List<TypeRef?> _inputTypes = [];
  final List<SchemaField?> _fieldDefinitions = [];
  final List<Value?> _defaultValues = [];
  SchemaDirective? _directive;
  InputValue? _argument;
  SchemaEnumValue? _enumValue;

  /// The output type of the current field, fragment or operation.
  TypeRef? get type => _outputTypes.lastOrNull;

  /// The composite type whose selection set holds the current node.
  SchemaType? get parentType => _parentTypes.lastOrNull;

  /// The definition of the current field, meta-fields included.
  SchemaField? get fieldDefinition => _fieldDefinitions.lastOrNull;

  /// The input type of the current value: of a variable definition, an
  /// argument, a list item or an input object field.
  TypeRef? get inputType => _inputTypes.lastOrNull;

  /// The input type that holds [inputType]: the list or input object
  /// around the current value.
  TypeRef? get parentInputType =>
      _inputTypes.length < 2 ? null : _inputTypes[_inputTypes.length - 2];

  /// The default value of the current argument or input field; null in a
  /// list and where there is none.
  Value? get defaultValue => _defaultValues.lastOrNull;

  /// The definition of the current directive.
  SchemaDirective? get directive => _directive;

  /// The definition of the current argument, of a field or a directive.
  InputValue? get argument => _argument;

  /// The definition of the current enum value.
  SchemaEnumValue? get enumValue => _enumValue;

  /// Moves into [node], before a visitor enters it.
  void enter(Node node) {
    switch (node) {
      case SelectionSet():
        _parentTypes.add(switch (_namedOf(type)) {
          final named? when named.isCompositeType => named,
          _ => null,
        });
      case Field(:final name):
        _enterField(name.value);
      case Directive(:final name):
        _directive = schema.directiveNamed(name.value);
      case OperationDefinition(:final operation):
        _outputTypes.add(_root(schema.rootTypeName(operation)));
      case InlineFragment(:final typeCondition):
        _outputTypes.add(_outputOrNull(typeCondition ?? _namedTypeOf(type)));
      case FragmentDefinition(:final typeCondition):
        _outputTypes.add(_outputOrNull(typeCondition));
      case VariableDefinition(type: final declared):
        _inputTypes.add(schema.isInputType(declared) ? declared : null);
      case Argument(:final name):
        _enterArgument(name.value);
      case ListValue():
        _enterListValue();
      case ObjectField(:final name):
        _enterObjectField(name.value);
      case EnumValue(:final value):
        _enumValue = switch (_namedOf(inputType)) {
          final EnumType type => type.valueNamed(value),
          _ => null,
        };
      case _:
        break;
    }
  }

  /// Moves out of [node], after a visitor leaves it.
  void leave(Node node) {
    switch (node) {
      case SelectionSet():
        _parentTypes.removeLast();
      case Field():
        _fieldDefinitions.removeLast();
        _outputTypes.removeLast();
      case Directive():
        _directive = null;
      case OperationDefinition() || InlineFragment() || FragmentDefinition():
        _outputTypes.removeLast();
      case VariableDefinition():
        _inputTypes.removeLast();
      case Argument():
        _argument = null;
        _defaultValues.removeLast();
        _inputTypes.removeLast();
      case ListValue() || ObjectField():
        _defaultValues.removeLast();
        _inputTypes.removeLast();
      case EnumValue():
        _enumValue = null;
      case _:
        break;
    }
  }

  void _enterField(String name) {
    final definition = switch (parentType) {
      final parent? => MetaFields.fieldOf(schema, parent, name),
      null => null,
    };
    _fieldDefinitions.add(definition);
    _outputTypes.add(_outputOrNull(definition?.type));
  }

  void _enterArgument(String name) {
    final argument = switch (directive) {
      final directive? => directive.argumentNamed(name),
      null => fieldDefinition?.argumentNamed(name),
    };
    _argument = argument;
    _defaultValues.add(argument?.defaultValue);
    _inputTypes.add(_inputOrNull(argument?.type));
  }

  void _enterListValue() {
    final listType = switch (inputType) {
      NonNullType(type: final inner) => inner,
      final other => other,
    };
    // A list position never has a default value.
    _defaultValues.add(null);
    _inputTypes.add(
      _inputOrNull(switch (listType) {
        ListType(type: final item) => item,
        _ => null,
      }),
    );
  }

  void _enterObjectField(String name) {
    final field = switch (_namedOf(inputType)) {
      final InputObjectType object => object.fieldNamed(name),
      _ => null,
    };
    _defaultValues.add(field?.defaultValue);
    _inputTypes.add(_inputOrNull(field?.type));
  }

  TypeRef? _root(String? name) => switch (name) {
    final name? when schema.typeNamed(name) is ObjectType => NamedType(
      Name(name),
    ),
    _ => null,
  };

  TypeRef? _outputOrNull(TypeRef? type) =>
      type != null && schema.isOutputType(type) ? type : null;

  TypeRef? _inputOrNull(TypeRef? type) =>
      type != null && schema.isInputType(type) ? type : null;

  NamedType? _namedTypeOf(TypeRef? type) =>
      type == null ? null : _types.namedType(type);

  SchemaType? _namedOf(TypeRef? type) => switch (_namedTypeOf(type)) {
    final named? => schema.typeNamed(named.name.value),
    null => null,
  };
}
```

Create `packages/typed_graphql/lib/src/validation/usage_index.dart`:

```dart
import '../language/ast/document.dart';
import '../language/ast/executable_definition.dart';
import '../language/ast/node.dart';
import '../language/ast/selection.dart';
import '../language/ast/value.dart';
import '../language/ast/variable_definition.dart';
import '../language/visitor/ast_visitor.dart';
import '../language/visitor/visit_action.dart';
import 'type_info.dart';
import 'variable_usage.dart';

/// The variable usages and fragment spreads of each executable definition,
/// recorded during the one walk of a run, and the closures of operations
/// over them.
///
/// graphql-js walks each fragment again when a rule asks for an
/// operation's variables; recording them in the walk does the same work
/// once. The queries need the whole document, so they answer only after
/// the walk left it.
final class UsageIndex extends AstVisitor {
  /// Records usages with the input types of [typeInfo]; [spend] charges
  /// the closures to the run's step budget and says whether it lasts.
  UsageIndex(this._typeInfo, this._spend, this._fragmentNamed);

  final TypeInfo _typeInfo;
  final bool Function(int steps) _spend;
  final FragmentDefinition? Function(String name) _fragmentNamed;

  // Keyed by node identity: syntax nodes do not override ==.
  final Map<ExecutableDefinition, List<VariableUsage>> _usages = {};
  final Map<ExecutableDefinition, List<FragmentSpread>> _spreads = {};
  final Map<OperationDefinition, List<FragmentDefinition>> _fragments = {};
  final Map<OperationDefinition, List<VariableUsage>> _closures = {};
  List<VariableUsage>? _currentUsages;
  List<FragmentSpread>? _currentSpreads;
  bool _isComplete = false;

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case final ExecutableDefinition definition:
        _currentUsages = _usages[definition] = [];
        _currentSpreads = _spreads[definition] = [];
      // The variable a definition declares is not a usage.
      case VariableDefinition():
        return VisitAction.skip;
      case final Variable variable:
        _currentUsages?.add(
          VariableUsage(
            variable,
            _typeInfo.inputType,
            parentType: _typeInfo.parentInputType,
            defaultValue: _typeInfo.defaultValue,
          ),
        );
      case final FragmentSpread spread:
        _currentSpreads?.add(spread);
      case _:
        break;
    }
    return VisitAction.next;
  }

  @override
  void leave(Node node) {
    switch (node) {
      case ExecutableDefinition():
        _currentUsages = null;
        _currentSpreads = null;
      case Document():
        _isComplete = true;
      case _:
        break;
    }
  }

  /// The usages directly in [definition], in document order.
  List<VariableUsage> variableUsagesOf(ExecutableDefinition definition) {
    _checkComplete();
    return _usages[definition] ?? const [];
  }

  /// The fragments [operation] spreads, directly or through other
  /// fragments, each once, in graphql-js's order.
  List<FragmentDefinition> recursivelyReferencedFragments(
    OperationDefinition operation,
  ) {
    _checkComplete();
    return _fragments[operation] ??= _collectFragments(operation);
  }

  /// The usages in [operation] and in every fragment it reaches.
  List<VariableUsage> recursiveVariableUsages(OperationDefinition operation) {
    _checkComplete();
    return _closures[operation] ??= [
      ...variableUsagesOf(operation),
      for (final fragment in recursivelyReferencedFragments(operation))
        if (_spend(variableUsagesOf(fragment).length + 1))
          ...variableUsagesOf(fragment),
    ];
  }

  List<FragmentDefinition> _collectFragments(OperationDefinition operation) {
    final fragments = <FragmentDefinition>[];
    final names = <String>{};
    final pending = <ExecutableDefinition>[operation];
    while (pending.isNotEmpty) {
      final spreads = _spreads[pending.removeLast()] ?? const [];
      if (!_spend(spreads.length + 1)) {
        break;
      }
      for (final spread in spreads) {
        final fragment = _fragmentNamed(spread.name.value);
        if (names.add(spread.name.value) && fragment != null) {
          fragments.add(fragment);
          pending.add(fragment);
        }
      }
    }
    return fragments;
  }

  void _checkComplete() {
    if (!_isComplete) {
      throw StateError('The document has not been walked to its end.');
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/validation_context.dart`:

```dart
import '../diagnostics/diagnostic.dart';
import '../diagnostics/diagnostic_code.dart';
import '../diagnostics/diagnostic_sink.dart';
import '../diagnostics/source.dart';
import '../diagnostics/source_span.dart';
import '../language/ast/document.dart';
import '../language/ast/executable_definition.dart';
import '../language/ast/node.dart';
import '../language/visitor/ast_visitor.dart';
import '../schema/schema.dart';
import 'type_info.dart';
import 'usage_index.dart';
import 'validation_walk.dart';
import 'variable_usage.dart';

/// What the rules of one validation run share (R3.2, R3.6): the schema,
/// the document, the [typeInfo] of the walk, the sink their diagnostics
/// go to, the step budget, and the fragments and variable usages of the
/// document.
///
/// `DocumentValidator` makes one for each run and gives it to each rule's
/// `createVisitor`.
///
/// {@category validation}
final class ValidationContext {
  /// Creates the context of a run over [document], reporting into a sink.
  ///
  /// Diagnostics get spans in `source` when it is given, the text
  /// [document] was parsed from. [maxSteps] bounds the work beyond one
  /// walk (see [spend]).
  ValidationContext(
    this.schema,
    this.document,
    this._sink, {
    this._source,
    this.includesSuggestions = true,
    this.maxSteps = defaultMaxSteps,
  }) : typeInfo = TypeInfo(schema) {
    _usages = UsageIndex(typeInfo, spend, fragmentNamed);
  }

  /// The default of [maxSteps].
  static const int defaultMaxSteps = 1000000;

  /// The schema the document is validated against.
  final Schema schema;

  /// The document being validated.
  final Document document;

  /// The types around the node the walk is at.
  final TypeInfo typeInfo;

  /// Whether messages may suggest names ("Did you mean ..."), graphql-js's
  /// `hideSuggestions` negated; a production server turns them off
  /// (R5.15).
  final bool includesSuggestions;

  /// The most steps [spend] allows before the run stops.
  final int maxSteps;

  final DiagnosticSink _sink;
  final Source? _source;
  // Set in the constructor body: the index needs this context's methods.
  late final UsageIndex _usages;
  Map<String, FragmentDefinition>? _fragments;
  int _steps = 0;
  bool _isOverBudget = false;

  /// Whether the run stops: the error limit or the step budget was
  /// reached. Reports are then ignored.
  bool get isAborted => _sink.isFull || _isOverBudget;

  /// Reports an error with [code] and [message] at the first of [nodes],
  /// the others being related places, as graphql-js lists an error's
  /// nodes. Ignored once the run [isAborted].
  void report(DiagnosticCode code, String message, List<Node> nodes) {
    if (isAborted) {
      return;
    }
    final spans = [
      if (_source case final source?)
        for (final node in nodes) SourceSpan(source, node.start, node.end),
    ];
    _sink.report(
      Diagnostic(
        code,
        .error,
        message,
        span: spans.firstOrNull,
        related: spans.skip(1).toList(),
      ),
    );
  }

  /// Charges [steps] units of work to the run's budget; false once the
  /// budget is spent.
  ///
  /// Work that grows faster than the document (an operation's fragment
  /// closure, field merging) is charged, so a document shaped to make it
  /// explode ends with one [DiagnosticCode.documentTooComplex] error
  /// instead of running for minutes.
  bool spend(int steps) {
    _steps += steps;
    if (_steps > maxSteps && !_isOverBudget) {
      _sink.report(
        Diagnostic(
          .documentTooComplex,
          .error,
          'The document is too complex to validate: it needs more than '
          '$maxSteps steps.',
          span: switch (_source) {
            final source? => SourceSpan(source, document.start, document.end),
            null => null,
          },
        ),
      );
      _isOverBudget = true;
    }
    return !_isOverBudget;
  }

  /// The fragment definition named [name]; the last one when several
  /// share it, as graphql-js's `getFragment`.
  FragmentDefinition? fragmentNamed(String name) => (_fragments ??= {
    for (final definition in document.definitions)
      if (definition is FragmentDefinition) definition.name.value: definition,
  })[name];

  /// The variable usages directly in [definition], in document order.
  ///
  /// This and the other usage queries answer once the walk has left the
  /// document, so a rule asks them in its `leave` of the [Document]; a
  /// [StateError] before that.
  List<VariableUsage> variableUsagesOf(ExecutableDefinition definition) =>
      _usages.variableUsagesOf(definition);

  /// The fragments [operation] spreads, directly or through other
  /// fragments, each once.
  List<FragmentDefinition> recursivelyReferencedFragments(
    OperationDefinition operation,
  ) => _usages.recursivelyReferencedFragments(operation);

  /// The variable usages in [operation] and in every fragment it reaches.
  List<VariableUsage> recursiveVariableUsages(OperationDefinition operation) =>
      _usages.recursiveVariableUsages(operation);

  /// The visitor that runs [visitors] in one walk with this context:
  /// it keeps [typeInfo] and the usage index up to date around them and
  /// stops the walk once the run [isAborted].
  AstVisitor visitorFor(List<AstVisitor> visitors) =>
      ValidationWalk(this, _usages, visitors);
}
```

Create `packages/typed_graphql/lib/src/validation/validation_rule.dart`:

````dart
import '../language/visitor/ast_visitor.dart';
import 'validation_context.dart';

/// One check of an executable document against a schema (R3.1, R3.6): a
/// rule of spec §5, a limit, or a custom rule.
///
/// A rule is a const value that holds only its configuration, so one
/// object serves every run. For each run, `DocumentValidator` asks every
/// rule for a fresh visitor and walks the document once with all of them
/// (R3.2). The visitor reads the types around each node from
/// [ValidationContext.typeInfo] and reports through
/// [ValidationContext.report].
///
/// ```dart
/// final class NoDogsRule extends ValidationRule {
///   const NoDogsRule();
///
///   @override
///   AstVisitor createVisitor(ValidationContext context) => _NoDogs(context);
/// }
/// ```
///
/// {@category validation}
abstract class ValidationRule {
  /// Creates a rule.
  const ValidationRule();

  /// A new visitor that checks one document; it may keep state for that
  /// run.
  AstVisitor createVisitor(ValidationContext context);
}
````

Create `packages/typed_graphql/lib/src/validation/validation_walk.dart`:

```dart
import '../language/ast/executable_definition.dart';
import '../language/ast/node.dart';
import '../language/ast/value.dart';
import '../language/ast/variable_definition.dart';
import '../language/visitor/ast_visitor.dart';
import '../language/visitor/parallel_visitor.dart';
import '../language/visitor/visit_action.dart';
import 'usage_index.dart';
import 'validation_context.dart';

/// The visitor of one validation run (R3.2), graphql-js's
/// `visitWithTypeInfo` around `visitInParallel`: the context's `TypeInfo`
/// enters a node before the rules and leaves it after them, and the usage
/// index records the node first.
///
/// Descriptions are not walked: they do not affect validation (spec
/// §2.2), and graphql-js's `validate` drops the `description` keys.
final class ValidationWalk extends AstVisitor {
  /// Runs [visitors] with [context] and its [usages].
  ValidationWalk(this._context, UsageIndex usages, List<AstVisitor> visitors)
    : _visitors = ParallelVisitor([usages, ...visitors]);

  final ValidationContext _context;
  final ParallelVisitor _visitors;
  // A description is the first child of its definition, so it is the
  // next node entered after the definition.
  StringValue? _description;

  @override
  VisitAction enter(Node node) {
    if (identical(node, _description)) {
      return VisitAction.skip;
    }
    if (_context.isAborted) {
      return VisitAction.stop;
    }
    _description = switch (node) {
      OperationDefinition(:final description) => description,
      FragmentDefinition(:final description) => description,
      VariableDefinition(:final description) => description,
      _ => null,
    };
    _context.typeInfo.enter(node);
    final action = _visitors.enter(node);
    // The walk will not leave a node it does not go into.
    if (action != VisitAction.next) {
      _context.typeInfo.leave(node);
    }
    return action;
  }

  @override
  void leave(Node node) {
    _visitors.leave(node);
    _context.typeInfo.leave(node);
  }
}
```

Create `packages/typed_graphql/lib/src/validation/variable_usage.dart`:

```dart
import '../language/ast/type_ref.dart';
import '../language/ast/value.dart';

/// A variable used as a value, with the input type expected where it
/// stands, as graphql-js's `VariableUsage`.
///
/// {@category validation}
final class VariableUsage(
  /// The variable, `$name`.
  final Variable node,

  /// The input type of the position; null where the document names an
  /// argument or field the schema does not have.
  final TypeRef? type, {

  /// The list or input object type that holds the position, if any.
  final TypeRef? parentType,

  /// The default value of the argument or input field at the position;
  /// null in a list and where there is none.
  final Value? defaultValue,
}) {
  /// Creates a usage.
  this;
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -87,3 +87,9 @@ export 'src/schema/scalars/string_codec.dart';
 export 'src/schema/schema.dart';
 export 'src/schema/validation/schema_validation_result.dart';
 export 'src/schema/validation/schema_validator.dart';
+export 'src/validation/document_validation_result.dart';
+export 'src/validation/document_validator.dart';
+export 'src/validation/type_info.dart';
+export 'src/validation/validation_context.dart';
+export 'src/validation/validation_rule.dart';
+export 'src/validation/variable_usage.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,6 +21,9 @@ dartdoc:
     introspection:
       markdown: doc/introspection.md
       displayName: Introspection
+    validation:
+      markdown: doc/validation.md
+      displayName: Operation Validation
   categoryOrder:
     - getting-started
     - diagnostics
@@ -29,4 +32,5 @@ dartdoc:
     - schema
     - scalars
     - introspection
+    - validation
   showUndocumentedCategories: true
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/document_validator_test.dart test/validation/type_info_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,7 @@
 - [Schema](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/schema.md): build a schema from SDL, read, validate, extend and print it; resolve coordinates
 - [Scalars and codecs](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/scalars.md): the built-in scalar codecs and your own
 - [Introspection](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/introspection.md): the introspection query, a schema's answer, and a schema built from an answer
+- [Operation validation](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/validation.md): validate a document against a schema; custom rules; work limits
 - [Example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/example/example.dart): a runnable program: report syntax errors, print a document, build a schema from SDL
 
 ## Reference
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Operation validation framework (M4): `DocumentValidator` runs every
  `ValidationRule` in one walk and returns `ValidDocument` or
  `InvalidDocument`; `ValidationContext` gives rules the schema, `TypeInfo`,
  fragments, variable usages and a step budget (`GQL230`); custom rules
  report `GQL231`. The Operation Validation guide.
```

Create `packages/typed_graphql/doc/validation.md`:

````markdown
# Operation Validation

A server validates an executable document against its schema before it runs
it (September2025, "Validation"). `DocumentValidator` checks a parsed
`Document` against a `ValidSchema` in one walk and returns a
`ValidDocument` or an `InvalidDocument` with every problem as a diagnostic;
an invalid document never throws.

## Rules

A `ValidationRule` is one check. For each run the validator asks every rule
for a fresh `AstVisitor` and walks the document once with all of them. At
each node a visitor reads the types around it from
`ValidationContext.typeInfo` (`TypeInfo`: the parent type, the field
definition, the expected input type) and reports with
`ValidationContext.report`, which points the diagnostic at the first node
it is given. A custom rule reports `GQL231` or a code of its own choice.

```dart
import 'package:typed_graphql/typed_graphql.dart';

final class NoSecretsRule extends ValidationRule {
  const NoSecretsRule();

  @override
  AstVisitor createVisitor(ValidationContext context) => _NoSecrets(context);
}

final class _NoSecrets extends AstVisitor {
  _NoSecrets(this.context);

  final ValidationContext context;

  @override
  VisitAction enter(Node node) {
    if (node is Field && context.typeInfo.fieldDefinition?.name == 'secret') {
      context.report(.customRuleViolation, 'Secrets are not served.', [node]);
    }
    return .next;
  }
}

void main() {
  final schema = switch (const SchemaBuilder().fromSdl(
    const Parser()
        .parse(Source('type Query { name: String secret: String }'))
        .requireDocument(),
  )) {
    BuildSuccess(:final schema) => schema,
    BuildFailure() => throw StateError('the schema is valid'),
  };
  final valid = switch (const SchemaValidator().validate(schema)) {
    final ValidSchema valid => valid,
    InvalidSchema() => throw StateError('the schema is valid'),
  };
  final source = Source('{ name secret }');
  final document = const Parser().parse(source).requireDocument();
  const validator = DocumentValidator(rules: [NoSecretsRule()]);
  switch (validator.validate(valid, document, source: source)) {
    case ValidDocument():
      print('valid');
    case InvalidDocument(:final diagnostics):
      for (final diagnostic in diagnostics) {
        print('${diagnostic.span?.location} ${diagnostic.message}');
      }
  }
}
```

It prints:

```text
1:8 Secrets are not served.
```

## Work limits

Some checks do more work than one walk: the fragments an operation reaches,
the fields that must merge. The run charges that work to a budget
(`maxSteps`, a million by default); a document shaped to exceed it gets
one `GQL230` error instead of keeping the server busy. `maxErrors` stops
the run after that many errors with one `GQL000`.
````

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
git add llms.txt packages/typed_graphql/CHANGELOG.md packages/typed_graphql/dartdoc_options.yaml packages/typed_graphql/doc/validation.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validation_result.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/meta_fields.dart packages/typed_graphql/lib/src/validation/type_info.dart packages/typed_graphql/lib/src/validation/usage_index.dart packages/typed_graphql/lib/src/validation/validation_context.dart packages/typed_graphql/lib/src/validation/validation_rule.dart packages/typed_graphql/lib/src/validation/validation_walk.dart packages/typed_graphql/lib/src/validation/variable_usage.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/checked.dart packages/typed_graphql/test/validation/document_validator_test.dart packages/typed_graphql/test/validation/type_info_test.dart
git commit -q -m "feat(typed_graphql): add the validation framework" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: The operation rules and the rule conformance harness

The five rules of spec §5.1–§5.2 (`GQL200`–`GQL204`), and in the conformance package the `RulePort` harness over graphql-js's test schema, `mapping/validation.csv` with the coverage test, and the five ported suites.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/rules/executable_definitions_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/known_operation_types_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/lone_anonymous_operation_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/single_field_subscriptions_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/subscription_fields.dart`, `packages/typed_graphql/lib/src/validation/rules/unique_operation_names_rule.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/validation/rules/operation_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/support/rule_port.dart`, `packages/typed_graphql_conformance/test/validation/executable_definitions_test.dart`, `packages/typed_graphql_conformance/test/validation/known_operation_types_test.dart`, `packages/typed_graphql_conformance/test/validation/lone_anonymous_operation_test.dart`, `packages/typed_graphql_conformance/test/validation/single_field_subscriptions_test.dart`, `packages/typed_graphql_conformance/test/validation/unique_operation_names_test.dart`

**Interfaces:**
- Consumes: Task 2 (`ValidationRule`, `ValidationContext`, `DocumentValidator`, `TypeInfo`).
- Produces:
- Diagnostic codes: `GQL200`, `GQL201`, `GQL202`, `GQL203`, `GQL204`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/rules/executable_definitions_rule.dart
final class const ExecutableDefinitionsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _ExecutableDefinitions(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/known_operation_types_rule.dart
final class const KnownOperationTypesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _KnownOperationTypes(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/lone_anonymous_operation_rule.dart
final class const LoneAnonymousOperationRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _LoneAnonymousOperation(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/single_field_subscriptions_rule.dart
final class const SingleFieldSubscriptionsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _SingleFieldSubscriptions(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/subscription_fields.dart
final class SubscriptionFields
  SubscriptionFields(

// validation/rules/unique_operation_names_rule.dart
final class const UniqueOperationNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UniqueOperationNames(final ValidationContext context)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/operation_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the walks.
void main() {
  final checked = Checked('''
type Query { name: String }
type Subscription { a: String b: String }
''');

  test('a type definition in a document is GQL200', () {
    expect(
      checked.errors('{ name } type T { f: String }', [
        const ExecutableDefinitionsRule(),
      ]),
      ['1:10 GQL200 The "T" definition is not executable.'],
    );
  });

  test('an operation without a root type is GQL201', () {
    expect(
      checked.errors('mutation { name }', [const KnownOperationTypesRule()]),
      ['1:1 GQL201 The mutation operation is not supported by the schema.'],
    );
  });

  test('a repeated operation name is GQL202 at the first one', () {
    expect(
      checked.errors('query A { name } query A { name }', [
        const UniqueOperationNamesRule(),
      ]),
      ['1:7 GQL202 There can be only one operation named "A".'],
    );
  });

  test('an anonymous operation beside another is GQL203', () {
    expect(
      checked.errors('{ name } query A { name }', [
        const LoneAnonymousOperationRule(),
      ]),
      [
        '1:1 GQL203 This anonymous operation must be the only defined '
            'operation.',
      ],
    );
  });

  test('a second subscription field is GQL204', () {
    expect(
      checked.errors('subscription { a b }', [
        const SingleFieldSubscriptionsRule(),
      ]),
      [
        '1:18 GQL204 Anonymous Subscription must select only one top level '
            'field.',
      ],
    );
  });

  test('subscription fields are collected without recursion', () {
    // Built in code: the parser stops at its own depth limit first.
    var selections = <Selection>[Field(null, const Name('b'))];
    for (var i = 0; i < 100000; i++) {
      selections = [InlineFragment(null, SelectionSet(selections))];
    }
    final document = Document([
      OperationDefinition(
        OperationType.subscription,
        SelectionSet([Field(null, const Name('a')), ...selections]),
      ),
    ]);
    final result = const DocumentValidator(
      rules: [SingleFieldSubscriptionsRule()],
    ).validate(checked.schema, document);
    expect(
      result.diagnostics.single.code,
      DiagnosticCode.singleFieldSubscriptions,
    );
  });

  test('the specified rules start with the operation rules', () {
    expect(DocumentValidator.specifiedRules.take(5), [
      isA<ExecutableDefinitionsRule>(),
      isA<KnownOperationTypesRule>(),
      isA<UniqueOperationNamesRule>(),
      isA<LoneAnonymousOperationRule>(),
      isA<SingleFieldSubscriptionsRule>(),
    ]);
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -80,6 +80,17 @@ void main() {
         'utilities/__tests__/resolveSchemaCoordinate-test.ts',
       ],
     ),
+    (
+      path: 'mapping/validation.csv',
+      prefix: '',
+      covered: const [
+        'validation/__tests__/ExecutableDefinitionsRule-test.ts',
+        'validation/__tests__/KnownOperationTypesRules-test.ts',
+        'validation/__tests__/LoneAnonymousOperationRule-test.ts',
+        'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
+        'validation/__tests__/UniqueOperationNamesRule-test.ts',
+      ],
+    ),
   ];
   for (final (:path, :prefix, :covered) in tables) {
     group(path, () {
```

Create `packages/typed_graphql_conformance/test/support/rule_port.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'validation_port.dart';

/// graphql-js's validation harness (`validation/__tests__/harness.ts`): one
/// rule checked against `testSchema` or another schema, each error as
/// `expectJSON` compares it.
final class RulePort {
  /// Checks documents with [rule] against [schema], graphql-js's
  /// `testSchema` by default.
  RulePort(ValidationRule rule, {ValidSchema? schema})
    : this.all([rule], schema: schema);

  /// Checks documents with [rules] together: a graphql-js rule that M4
  /// splits into several (section 5 of the M4 spec).
  RulePort.all(this.rules, {ValidSchema? schema})
    : schema = schema ?? testSchema;

  /// The rules the tests check.
  final List<ValidationRule> rules;

  /// The schema documents are validated against.
  final ValidSchema schema;

  /// graphql-js's `testSchema`, built once.
  static final ValidSchema testSchema = RulePort.validated(_testSdl);

  /// [sdl] built as graphql-js's `buildSchema` builds a template literal,
  /// and validated: graphql-js's `validate` asserts a valid schema.
  static ValidSchema validated(String sdl) =>
      switch (const SchemaValidator().validate(
        const ValidationPort().build(sdl),
      )) {
        final ValidSchema valid => valid,
        InvalidSchema(:final diagnostics) => fail('$diagnostics'),
      };

  /// graphql-js's `expectValidationErrorsWithSchema`: the same rules
  /// against the schema built from [sdl].
  RulePort withSchema(String sdl) =>
      RulePort.all(rules, schema: validated(sdl));

  /// The errors of [query], a template literal written as a Dart
  /// multi-line literal (its first line break is restored, so lines count
  /// as in graphql-js): each the message, then ` @ ` and its locations
  /// when it has any. [hidesSuggestions] is graphql-js's
  /// `hideSuggestions`.
  List<String> errors(String query, {bool hidesSuggestions = false}) {
    final source = Source('\n$query');
    final document = switch (const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final diagnostics) => fail('$diagnostics'),
    };
    final validator = DocumentValidator(
      rules: rules,
      includesSuggestions: !hidesSuggestions,
    );
    return [
      for (final diagnostic
          in validator.validate(schema, document, source: source).diagnostics)
        _printed(diagnostic),
    ];
  }

  String _printed(Diagnostic diagnostic) {
    final locations = [
      for (final span in [?diagnostic.span, ...diagnostic.related])
        '${span.location.line}:${span.location.column}',
    ];
    return switch (locations) {
      [] => diagnostic.message,
      _ => '${diagnostic.message} @ ${locations.join(' ')}',
    };
  }

  static const String _testSdl = '''
  interface Mammal {
    mother: Mammal
    father: Mammal
  }

  interface Pet {
    name(surname: Boolean): String
  }

  interface Canine implements Mammal {
    name(surname: Boolean): String
    mother: Canine
    father: Canine
  }

  enum DogCommand {
    SIT
    HEEL
    DOWN
  }

  scalar GeoPoint

  type Dog implements Pet & Mammal & Canine {
    name(surname: Boolean): String
    nickname: String
    barkVolume: Int
    barks: Boolean
    doesKnowCommand(dogCommand: DogCommand): Boolean
    isHouseTrained(atOtherHomes: Boolean = true): Boolean
    isAtLocation(x: Int, y: Int): Boolean
    distanceFrom(loc: GeoPoint): Float
    mother: Dog
    father: Dog
  }

  type Cat implements Pet {
    name(surname: Boolean): String
    nickname: String
    meows: Boolean
    meowsVolume: Int
    furColor: FurColor
  }

  union CatOrDog = Cat | Dog

  type Human {
    name(surname: Boolean): String
    pets: [Pet]
    relatives: [Human]!
  }

  enum FurColor {
    BROWN
    BLACK
    TAN
    SPOTTED
    NO_FUR
    UNKNOWN
  }

  input ComplexInput {
    requiredField: Boolean!
    nonNullField: Boolean! = false
    intField: Int
    stringField: String
    booleanField: Boolean
    stringListField: [String]
  }

  input OneOfInput @oneOf {
    stringField: String
    intField: Int
  }

  type ComplicatedArgs {
    # TODO List
    # TODO Coercion
    # TODO NotNulls
    intArgField(intArg: Int): String
    nonNullIntArgField(nonNullIntArg: Int!): String
    stringArgField(stringArg: String): String
    booleanArgField(booleanArg: Boolean): String
    enumArgField(enumArg: FurColor): String
    floatArgField(floatArg: Float): String
    idArgField(idArg: ID): String
    stringListArgField(stringListArg: [String]): String
    stringListNonNullArgField(stringListNonNullArg: [String!]): String
    complexArgField(complexArg: ComplexInput): String
    oneOfArgField(oneOfArg: OneOfInput): String
    multipleReqs(req1: Int!, req2: Int!): String
    nonNullFieldWithDefault(arg: Int! = 0): String
    multipleOpts(opt1: Int = 0, opt2: Int = 0): String
    multipleOptAndReq(req1: Int!, req2: Int!, opt1: Int = 0, opt2: Int = 0): String
  }

  type QueryRoot {
    human(id: ID): Human
    dog: Dog
    cat: Cat
    pet: Pet
    catOrDog: CatOrDog
    complicatedArgs: ComplicatedArgs
  }

  schema {
    query: QueryRoot
  }

  directive @onField on FIELD
''';
}
```

Create `packages/typed_graphql_conformance/test/validation/executable_definitions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ExecutableDefinitionsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const ExecutableDefinitionsRule());

  group('Validate: Executable definitions', () {
    test('with only operation', () {
      expect(
        port.errors('''
      query Foo {
        dog {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('with operation and fragment', () {
      expect(
        port.errors('''
      query Foo {
        dog {
          name
          ...Frag
        }
      }

      fragment Frag on Dog {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('with type definition', () {
      expect(
        port.errors('''
      query Foo {
        dog {
          name
        }
      }

      type Cow {
        name: String
      }

      extend type Dog {
        color: String
      }
    '''),
        [
          'The "Cow" definition is not executable. @ 8:7',
          'The "Dog" definition is not executable. @ 12:7',
        ],
      );
    });

    test('with schema definition', () {
      expect(
        port.errors('''
      schema {
        query: Query
      }

      type Query {
        test: String
      }

      extend schema @directive
    '''),
        [
          'The schema definition is not executable. @ 2:7',
          'The "Query" definition is not executable. @ 6:7',
          'The schema definition is not executable. @ 10:7',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/known_operation_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownOperationTypesRules-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownOperationTypesRule());

  group('Validate: Known operation types', () {
    test('one known operation', () {
      expect(
        port.errors('''
      { field }
    '''),
        isEmpty,
      );
    });

    test('unknown mutation operation', () {
      expect(
        port.errors('''
      mutation { field }
    '''),
        [
          'The mutation operation is not supported by the schema. @ 2:7',
        ],
      );
    });

    test('unknown subscription operation', () {
      expect(
        port.errors('''
      subscription { field }
    '''),
        [
          'The subscription operation is not supported by the schema. @ 2:7',
        ],
      );
    });

    test('mixture of known and unknown operations', () {
      expect(
        port.errors('''
      query { field }
      mutation { field }
      subscription { field }
  '''),
        [
          'The mutation operation is not supported by the schema. @ 3:7',
          'The subscription operation is not supported by the schema. @ 4:7',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/lone_anonymous_operation_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/LoneAnonymousOperationRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const LoneAnonymousOperationRule());

  group('Validate: Anonymous operation must be alone', () {
    test('no operations', () {
      expect(
        port.errors('''
      fragment fragA on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('one anon operation', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple named operations', () {
      expect(
        port.errors('''
      query Foo {
        field
      }

      query Bar {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('anon operation with fragment', () {
      expect(
        port.errors('''
      {
        ...Foo
      }
      fragment Foo on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple anon operations', () {
      expect(
        port.errors('''
      {
        fieldA
      }
      {
        fieldB
      }
    '''),
        [
          'This anonymous operation must be the only defined operation. @ 2:7',
          'This anonymous operation must be the only defined operation. @ 5:7',
        ],
      );
    });

    test('anon operation with a mutation', () {
      expect(
        port.errors('''
      {
        fieldA
      }
      mutation Foo {
        fieldB
      }
    '''),
        [
          'This anonymous operation must be the only defined operation. @ 2:7',
        ],
      );
    });

    test('anon operation with a subscription', () {
      expect(
        port.errors('''
      {
        fieldA
      }
      subscription Foo {
        fieldB
      }
    '''),
        [
          'This anonymous operation must be the only defined operation. @ 2:7',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/single_field_subscriptions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/SingleFieldSubscriptionsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const SingleFieldSubscriptionsRule()).withSchema('''
  type Message {
    body: String
    sender: String
  }

  type SubscriptionRoot {
    importantEmails: [String]
    notImportantEmails: [String]
    moreImportantEmails: [String]
    spamEmails: [String]
    deletedEmails: [String]
    newMessage: Message
  }

  type QueryRoot {
    dummy: String
  }

  schema {
    query: QueryRoot
    subscription: SubscriptionRoot
  }
''');

  group('Validate: Subscriptions with single field', () {
    test('valid subscription', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
      }
    '''),
        isEmpty,
      );
    });

    test('valid subscription with fragment', () {
      // From https://spec.graphql.org/draft/#example-13061
      expect(
        port.errors('''
      subscription sub {
        ...newMessageFields
      }

      fragment newMessageFields on SubscriptionRoot {
        newMessage {
          body
          sender
        }
      }
    '''),
        isEmpty,
      );
    });

    test('valid subscription with fragment and field', () {
      // From https://spec.graphql.org/draft/#example-13061
      expect(
        port.errors('''
      subscription sub {
        newMessage {
          body
        }
        ...newMessageFields
      }

      fragment newMessageFields on SubscriptionRoot {
        newMessage {
          body
          sender
        }
      }
    '''),
        isEmpty,
      );
    });

    test('fails with more than one root field', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        notImportantEmails
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 4:9',
        ],
      );
    });

    test('fails with more than one root field including introspection', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        __typename
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 4:9',
          'Subscription "ImportantEmails" must not select an introspection top level field. @ 4:9',
        ],
      );
    });

    test('fails with more than one root field including aliased introspection via fragment', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        ...Introspection
      }
      fragment Introspection on SubscriptionRoot {
        typename: __typename
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 7:9',
          'Subscription "ImportantEmails" must not select an introspection top level field. @ 7:9',
        ],
      );
    });

    test('fails with many more than one root field', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        notImportantEmails
        spamEmails
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 4:9 5:9',
        ],
      );
    });

    test('fails with many more than one root field via fragments', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        importantEmails
        ... {
          more: moreImportantEmails
        }
        ...NotImportantEmails
      }
      fragment NotImportantEmails on SubscriptionRoot {
        notImportantEmails
        deleted: deletedEmails
        ...SpamEmails
      }
      fragment SpamEmails on SubscriptionRoot {
        spamEmails
      }
    '''),
        [
          'Subscription "ImportantEmails" must select only one top level field. @ 5:11 10:9 11:9 15:9',
        ],
      );
    });

    test('does not infinite loop on recursive fragments', () {
      expect(
        port.errors('''
      subscription NoInfiniteLoop {
        ...A
      }
      fragment A on SubscriptionRoot {
        ...A
      }
    '''),
        isEmpty,
      );
    });

    test(
      'fails with many more than one root field via fragments (anonymous)',
      () {
        expect(
          port.errors('''
      subscription {
        importantEmails
        ... {
          more: moreImportantEmails
          ...NotImportantEmails
        }
        ...NotImportantEmails
      }
      fragment NotImportantEmails on SubscriptionRoot {
        notImportantEmails
        deleted: deletedEmails
        ... {
          ... {
            archivedEmails
          }
        }
        ...SpamEmails
      }
      fragment SpamEmails on SubscriptionRoot {
        spamEmails
        ...NonExistentFragment
      }
    '''),
          [
            'Anonymous Subscription must select only one top level field. @ 5:11 11:9 12:9 15:13 21:9',
          ],
        );
      },
    );

    test('fails with more than one root field in anonymous subscriptions', () {
      expect(
        port.errors('''
      subscription {
        importantEmails
        notImportantEmails
      }
    '''),
        [
          'Anonymous Subscription must select only one top level field. @ 4:9',
        ],
      );
    });

    test('fails with introspection field', () {
      expect(
        port.errors('''
      subscription ImportantEmails {
        __typename
      }
    '''),
        [
          'Subscription "ImportantEmails" must not select an introspection top level field. @ 3:9',
        ],
      );
    });

    test('fails with introspection field in anonymous subscription', () {
      expect(
        port.errors('''
      subscription {
        __typename
      }
    '''),
        [
          'Anonymous Subscription must not select an introspection top level field. @ 3:9',
        ],
      );
    });

    test('fails with @skip or @include directive', () {
      expect(
        port.errors(r'''
      subscription RequiredRuntimeValidation($bool: Boolean!) {
        newMessage @include(if: $bool) {
          body
          sender
        }
        disallowedSecondRootField @skip(if: $bool)
      }
    '''),
        [
          'Subscription "RequiredRuntimeValidation" must not use `@skip` or `@include` directives in the top level selection. @ 3:20 7:35',
        ],
      );
    });

    test(
      'fails with @skip or @include directive in anonymous subscription',
      () {
        expect(
          port.errors(r'''
      subscription ($bool: Boolean!) {
        newMessage @include(if: $bool) {
          body
          sender
        }
        disallowedSecondRootField @skip(if: $bool)
      }
    '''),
          [
            'Anonymous Subscription must not use `@skip` or `@include` directives in the top level selection. @ 3:20 7:35',
          ],
        );
      },
    );

    test('skips if not subscription type', () {
      final emptySchema = port.withSchema('''
      type Query {
        dummy: String
      }
    ''');
      expect(
        emptySchema.errors('''
        subscription {
          __typename
        }
      '''),
        isEmpty,
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/unique_operation_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueOperationNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueOperationNamesRule());

  group('Validate: Unique operation names', () {
    test('no operations', () {
      expect(
        port.errors('''
      fragment fragA on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('one anon operation', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('one named operation', () {
      expect(
        port.errors('''
      query Foo {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple operations', () {
      expect(
        port.errors('''
      query Foo {
        field
      }

      query Bar {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple operations of different types', () {
      expect(
        port.errors('''
      query Foo {
        field
      }

      mutation Bar {
        field
      }

      subscription Baz {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('fragment and operation named the same', () {
      expect(
        port.errors('''
      query Foo {
        ...Foo
      }
      fragment Foo on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('multiple operations of same name', () {
      expect(
        port.errors('''
      query Foo {
        fieldA
      }
      query Foo {
        fieldB
      }
    '''),
        [
          'There can be only one operation named "Foo". @ 2:13 5:13',
        ],
      );
    });

    test('multiple ops of same name of different types (mutation)', () {
      expect(
        port.errors('''
      query Foo {
        fieldA
      }
      mutation Foo {
        fieldB
      }
    '''),
        [
          'There can be only one operation named "Foo". @ 2:13 5:16',
        ],
      );
    });

    test('multiple ops of same name of different types (subscription)', () {
      expect(
        port.errors('''
      query Foo {
        fieldA
      }
      subscription Foo {
        fieldB
      }
    '''),
        [
          'There can be only one operation named "Foo". @ 2:13 5:20',
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/operation_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/executable_definitions_test.dart test/validation/known_operation_types_test.dart test/validation/lone_anonymous_operation_test.dart test/validation/single_field_subscriptions_test.dart test/validation/unique_operation_names_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -325,6 +325,26 @@ enum DiagnosticCode(
   /// can read.
   introspectionTypeTooDeep('GQL155'),
 
+  /// `GQL200`: a type system definition or extension in a document sent
+  /// for execution (spec §5.1.1).
+  executableDefinitions('GQL200'),
+
+  /// `GQL201`: an operation whose type has no root type in the schema,
+  /// such as a mutation against a schema without one (spec §5.2.1.1).
+  knownOperationTypes('GQL201'),
+
+  /// `GQL202`: two operations with the same name (spec §5.2.2.1).
+  uniqueOperationNames('GQL202'),
+
+  /// `GQL203`: an anonymous operation beside another operation
+  /// (spec §5.2.3.1).
+  loneAnonymousOperation('GQL203'),
+
+  /// `GQL204`: a subscription that selects more than one top-level field,
+  /// an introspection field at the top level, or uses `@skip` or
+  /// `@include` there (spec §5.2.4.1).
+  singleFieldSubscriptions('GQL204'),
+
   /// `GQL230`: validating a document needed more work than the
   /// validator's step budget allows, such as fragments that expand to
   /// more fields than the budget, or many operations each spreading a
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,11 @@ import '../language/ast/document.dart';
 import '../language/visitor/ast_walker.dart';
 import '../schema/validation/schema_validation_result.dart';
 import 'document_validation_result.dart';
+import 'rules/executable_definitions_rule.dart';
+import 'rules/known_operation_types_rule.dart';
+import 'rules/lone_anonymous_operation_rule.dart';
+import 'rules/single_field_subscriptions_rule.dart';
+import 'rules/unique_operation_names_rule.dart';
 import 'validation_context.dart';
 import 'validation_rule.dart';
 
@@ -42,7 +47,13 @@ final class const DocumentValidator({
   this;
 
   /// The rules of spec §5, in graphql-js's order.
-  static const List<ValidationRule> specifiedRules = [];
+  static const List<ValidationRule> specifiedRules = [
+    ExecutableDefinitionsRule(),
+    KnownOperationTypesRule(),
+    UniqueOperationNamesRule(),
+    LoneAnonymousOperationRule(),
+    SingleFieldSubscriptionsRule(),
+  ];
 
   /// Validates [document] against [schema]; diagnostics point into
   /// [source] when it is given, the text [document] was parsed from.
```

Create `packages/typed_graphql/lib/src/validation/rules/executable_definitions_rule.dart`:

```dart
import '../../language/ast/definition.dart';
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/ast/type_system_extension.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.1.1 "Executable Definitions": a document sent for execution
/// holds only operations and fragments (`GQL200`).
///
/// {@category validation}
final class const ExecutableDefinitionsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ExecutableDefinitions(context);
}

final class _ExecutableDefinitions(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is! Document) {
      return .next;
    }
    for (final definition in node.definitions) {
      if (definition is ExecutableDefinition) {
        continue;
      }
      context.report(
        .executableDefinitions,
        'The ${_described(definition)} definition is not executable.',
        [definition],
      );
    }
    return .skip;
  }

  static String _described(Definition definition) => switch (definition) {
    SchemaDefinition() || SchemaExtension() => 'schema',
    DirectiveDefinition(:final name) ||
    TypeDefinition(:final name) ||
    DirectiveExtension(:final name) ||
    TypeExtension(:final name) => '"${name.value}"',
    _ => throw ArgumentError.value(
      definition,
      'definition',
      'is not a GraphQL definition',
    ),
  };
}
```

Create `packages/typed_graphql/lib/src/validation/rules/known_operation_types_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.2.1.1 "Operation Type Existence": the schema has a root type for
/// the operation's type (`GQL201`).
///
/// {@category validation}
final class const KnownOperationTypesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownOperationTypes(context);
}

final class _KnownOperationTypes(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case OperationDefinition(:final operation)
        when context.schema.rootTypeName(operation) == null) {
      context.report(
        .knownOperationTypes,
        'The ${operation.name} operation is not supported by the schema.',
        [node],
      );
    }
    return .next;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/lone_anonymous_operation_rule.dart`:

```dart
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.2.3.1 "Lone Anonymous Operation": an anonymous operation is the
/// only operation of its document (`GQL203`).
///
/// {@category validation}
final class const LoneAnonymousOperationRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _LoneAnonymousOperation(context);
}

final class _LoneAnonymousOperation(final ValidationContext context)
    extends AstVisitor {
  int _operationCount = 0;

  // Reported at each operation, not at the document, so the errors of all
  // rules keep graphql-js's order.
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case Document(:final definitions):
        _operationCount = definitions.whereType<OperationDefinition>().length;
        return .next;
      case OperationDefinition(name: null) when _operationCount > 1:
        context.report(
          .loneAnonymousOperation,
          'This anonymous operation must be the only defined operation.',
          [node],
        );
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/single_field_subscriptions_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'subscription_fields.dart';

/// Spec §5.2.4.1 "Single Root Field": a subscription selects one
/// top-level field, not an introspection field, without `@skip` or
/// `@include` at the top level (`GQL204`).
///
/// {@category validation}
final class const SingleFieldSubscriptionsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _SingleFieldSubscriptions(context);
}

final class _SingleFieldSubscriptions(final ValidationContext context)
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

  ObjectType? get _root => switch (context.schema.rootTypeName(
    .subscription,
  )) {
    final name? => switch (context.schema.typeNamed(name)) {
      final ObjectType type => type,
      _ => null,
    },
    null => null,
  };

  void _check(OperationDefinition operation) {
    final root = _root;
    if (root == null) {
      return;
    }
    final collected = SubscriptionFields(context, root, operation.selectionSet);
    final subject = switch (operation.name) {
      final name? => 'Subscription "${name.value}"',
      null => 'Anonymous Subscription',
    };
    if (collected.forbiddenDirectives.isNotEmpty) {
      context.report(
        .singleFieldSubscriptions,
        '$subject must not use `@skip` or `@include` directives in the top '
        'level selection.',
        collected.forbiddenDirectives,
      );
      return;
    }
    final groups = collected.fields.values.toList();
    if (groups.length > 1) {
      context.report(
        .singleFieldSubscriptions,
        '$subject must select only one top level field.',
        [for (final group in groups.skip(1)) ...group],
      );
    }
    for (final group in groups) {
      if (group.first.name.value.startsWith('__')) {
        context.report(
          .singleFieldSubscriptions,
          '$subject must not select an introspection top level field.',
          group,
        );
      }
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/subscription_fields.dart`:

```dart
import '../../language/ast/directive.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../../language/ast/type_ref.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import '../validation_context.dart';

/// The top-level fields of a subscription grouped by response key, as
/// graphql-js's `collectFields` gathers them with `@skip` and `@include`
/// forbidden (spec §5.2.4.1 `CollectSubscriptionFields`).
final class SubscriptionFields {
  /// Collects [selectionSet] for [root], following the fragments of
  /// [context] each once.
  ///
  /// The selections are walked with a stack, so deeply nested inline
  /// fragments cannot overflow the call stack.
  SubscriptionFields(
    ValidationContext context,
    ObjectType root,
    SelectionSet selectionSet,
  ) {
    final visited = <String>{};
    final pending = [...selectionSet.selections.reversed];
    while (pending.isNotEmpty && context.spend(1)) {
      final selection = pending.removeLast();
      if (_isForbidden(selection)) {
        continue;
      }
      switch (selection) {
        case Field():
          (fields[(selection.alias ?? selection.name).value] ??= []).add(
            selection,
          );
        case InlineFragment(:final typeCondition, :final selectionSet):
          if (_matches(context.schema, typeCondition, root)) {
            pending.addAll(selectionSet.selections.reversed);
          }
        case FragmentSpread(:final name):
          final fragment = context.fragmentNamed(name.value);
          if (fragment != null &&
              _matches(context.schema, fragment.typeCondition, root) &&
              visited.add(name.value)) {
            pending.addAll(fragment.selectionSet.selections.reversed);
          }
      }
    }
  }

  /// The fields by response key, in the order they were first selected.
  final Map<String, List<Field>> fields = {};

  /// The `@skip` and `@include` directives found, in document order.
  final List<Directive> forbiddenDirectives = [];

  // graphql-js's `shouldIncludeNode` with `forbidSkipAndInclude`: the
  // first `@skip`, else the first `@include`, makes the selection
  // forbidden.
  bool _isForbidden(Selection selection) {
    final directives = switch (selection) {
      Field(:final directives) ||
      InlineFragment(:final directives) ||
      FragmentSpread(:final directives) => directives,
    };
    for (final name in const ['skip', 'include']) {
      for (final directive in directives) {
        if (directive.name.value == name) {
          forbiddenDirectives.add(directive);
          return true;
        }
      }
    }
    return false;
  }

  // graphql-js's `doesFragmentConditionMatch`.
  static bool _matches(Schema schema, NamedType? condition, ObjectType root) {
    if (condition == null) {
      return true;
    }
    return switch (schema.typeNamed(condition.name.value)) {
      final type? when identical(type, root) => true,
      final InterfaceType type => schema.isSubType(type, root),
      final UnionType type => schema.isSubType(type, root),
      _ => false,
    };
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/unique_operation_names_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.2.2.1 "Operation Name Uniqueness": no two operations share a
/// name (`GQL202`).
///
/// {@category validation}
final class const UniqueOperationNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueOperationNames(context);
}

final class _UniqueOperationNames(final ValidationContext context)
    extends AstVisitor {
  final Map<String, Name> _known = {};

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(:final name?):
        if (_known[name.value] case final known?) {
          context.report(
            .uniqueOperationNames,
            'There can be only one operation named "${name.value}".',
            [known, name],
          );
        } else {
          _known[name.value] = name;
        }
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -89,6 +89,11 @@ export 'src/schema/validation/schema_validation_result.dart';
 export 'src/schema/validation/schema_validator.dart';
 export 'src/validation/document_validation_result.dart';
 export 'src/validation/document_validator.dart';
+export 'src/validation/rules/executable_definitions_rule.dart';
+export 'src/validation/rules/known_operation_types_rule.dart';
+export 'src/validation/rules/lone_anonymous_operation_rule.dart';
+export 'src/validation/rules/single_field_subscriptions_rule.dart';
+export 'src/validation/rules/unique_operation_names_rule.dart';
 export 'src/validation/type_info.dart';
 export 'src/validation/validation_context.dart';
 export 'src/validation/validation_rule.dart';
```

- [ ] **Step 4: Update the package files**

Create `packages/typed_graphql_conformance/mapping/validation.csv`:

```csv
graphql_js_file,group,test,status,dart_file,reason
validation/__tests__/ExecutableDefinitionsRule-test.ts,Validate: Executable definitions,with only operation,ported,test/validation/executable_definitions_test.dart,
validation/__tests__/ExecutableDefinitionsRule-test.ts,Validate: Executable definitions,with operation and fragment,ported,test/validation/executable_definitions_test.dart,
validation/__tests__/ExecutableDefinitionsRule-test.ts,Validate: Executable definitions,with type definition,ported,test/validation/executable_definitions_test.dart,
validation/__tests__/ExecutableDefinitionsRule-test.ts,Validate: Executable definitions,with schema definition,ported,test/validation/executable_definitions_test.dart,
validation/__tests__/KnownOperationTypesRules-test.ts,Validate: Known operation types,one known operation,ported,test/validation/known_operation_types_test.dart,
validation/__tests__/KnownOperationTypesRules-test.ts,Validate: Known operation types,unknown mutation operation,ported,test/validation/known_operation_types_test.dart,
validation/__tests__/KnownOperationTypesRules-test.ts,Validate: Known operation types,unknown subscription operation,ported,test/validation/known_operation_types_test.dart,
validation/__tests__/KnownOperationTypesRules-test.ts,Validate: Known operation types,mixture of known and unknown operations,ported,test/validation/known_operation_types_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,no operations,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,one anon operation,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,one named operation,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,multiple operations,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,multiple operations of different types,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,fragment and operation named the same,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,multiple operations of same name,ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,multiple ops of same name of different types (mutation),ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/UniqueOperationNamesRule-test.ts,Validate: Unique operation names,multiple ops of same name of different types (subscription),ported,test/validation/unique_operation_names_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,no operations,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,one anon operation,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,multiple named operations,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,anon operation with fragment,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,multiple anon operations,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,anon operation with a mutation,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/LoneAnonymousOperationRule-test.ts,Validate: Anonymous operation must be alone,anon operation with a subscription,ported,test/validation/lone_anonymous_operation_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,valid subscription,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,valid subscription with fragment,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,valid subscription with fragment and field,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with more than one root field,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with more than one root field including introspection,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with more than one root field including aliased introspection via fragment,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with many more than one root field,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with many more than one root field via fragments,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,does not infinite loop on recursive fragments,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with many more than one root field via fragments (anonymous),ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with more than one root field in anonymous subscriptions,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with introspection field,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with introspection field in anonymous subscription,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with @skip or @include directive,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with @skip or @include directive in anonymous subscription,ported,test/validation/single_field_subscriptions_test.dart,
validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,skips if not subscription type,ported,test/validation/single_field_subscriptions_test.dart,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/operation_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/executable_definitions_test.dart test/validation/known_operation_types_test.dart test/validation/lone_anonymous_operation_test.dart test/validation/single_field_subscriptions_test.dart test/validation/unique_operation_names_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The operation rules: `ExecutableDefinitionsRule`, `KnownOperationTypesRule`,
  `UniqueOperationNamesRule`, `LoneAnonymousOperationRule` and
  `SingleFieldSubscriptionsRule` (`GQL200`-`GQL204`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/rules/executable_definitions_rule.dart packages/typed_graphql/lib/src/validation/rules/known_operation_types_rule.dart packages/typed_graphql/lib/src/validation/rules/lone_anonymous_operation_rule.dart packages/typed_graphql/lib/src/validation/rules/single_field_subscriptions_rule.dart packages/typed_graphql/lib/src/validation/rules/subscription_fields.dart packages/typed_graphql/lib/src/validation/rules/unique_operation_names_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/operation_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/support/rule_port.dart packages/typed_graphql_conformance/test/validation/executable_definitions_test.dart packages/typed_graphql_conformance/test/validation/known_operation_types_test.dart packages/typed_graphql_conformance/test/validation/lone_anonymous_operation_test.dart packages/typed_graphql_conformance/test/validation/single_field_subscriptions_test.dart packages/typed_graphql_conformance/test/validation/unique_operation_names_test.dart
git commit -q -m "feat(typed_graphql): add the operation rules and the rule conformance harness" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: The type rules

`FieldsOnCorrectTypeRule`, `ScalarLeafsRule`, `KnownTypeNamesRule`, `FragmentsOnCompositeTypesRule` and `VariablesAreInputTypesRule` (`GQL205`, `GQL207`, `GQL212`, `GQL213`, `GQL226`), with `FieldTypeSuggestions` and `EngineOrderedSort` (V8's sort order, so suggestion lists match graphql-js's), and their ported suites.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/rules/engine_ordered_sort.dart`, `packages/typed_graphql/lib/src/validation/rules/field_type_suggestions.dart`, `packages/typed_graphql/lib/src/validation/rules/fields_on_correct_type_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/fragments_on_composite_types_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/known_type_names_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/scalar_leafs_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/variables_are_input_types_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/type_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/fields_on_correct_type_test.dart`, `packages/typed_graphql_conformance/test/validation/fragments_on_composite_types_test.dart`, `packages/typed_graphql_conformance/test/validation/known_type_names_test.dart`, `packages/typed_graphql_conformance/test/validation/scalar_leafs_test.dart`, `packages/typed_graphql_conformance/test/validation/variables_are_input_types_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
- Diagnostic codes: `GQL205`, `GQL207`, `GQL212`, `GQL213`, `GQL226`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/rules/engine_ordered_sort.dart
final class EngineOrderedSort<T>(final int Function(T a, T b) compare)
  List<T> sorted(Iterable<T> items)

// validation/rules/field_type_suggestions.dart
final class FieldTypeSuggestions(final Schema schema)
  List<String> namesFor(SchemaType parent, String fieldName)

// validation/rules/fields_on_correct_type_rule.dart
final class const FieldsOnCorrectTypeRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _FieldsOnCorrectType(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/fragments_on_composite_types_rule.dart
final class const FragmentsOnCompositeTypesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _FragmentsOnCompositeTypes(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/known_type_names_rule.dart
final class const KnownTypeNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _KnownTypeNames extends AstVisitor
  final ValidationContext context
  VisitAction enter(Node node)

// validation/rules/scalar_leafs_rule.dart
final class const ScalarLeafsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _ScalarLeafs(final ValidationContext context) extends AstVisitor
  VisitAction enter(Node node)

// validation/rules/variables_are_input_types_rule.dart
final class const VariablesAreInputTypesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _VariablesAreInputTypes(final ValidationContext context)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/type_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/validation/rules/engine_ordered_sort.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the branches
// those suites do not reach.
void main() {
  final checked = Checked('''
type Query { name: String pet: Pet }
interface Pet { name: String }
type Dog implements Pet { name: String barks: Boolean }
input Filter { name: String }
''');

  List<String> idsOf(String text, ValidationRule rule) => [
    for (final diagnostic
        in checked
            .validate(text, validator: DocumentValidator(rules: [rule]))
            .diagnostics)
      diagnostic.code.id,
  ];

  test('an unknown type name is GQL212', () {
    expect(
      checked.errors('fragment F on Dg { name }', [const KnownTypeNamesRule()]),
      ['1:15 GQL212 Unknown type "Dg". Did you mean "Dog"?'],
    );
  });

  test('a type the document defines is known', () {
    expect(
      checked.errors('type Extra { a: String } fragment F on Extra { a }', [
        const KnownTypeNamesRule(),
      ]),
      isEmpty,
    );
  });

  test('suggestions can be turned off', () {
    final result = checked.validate(
      'fragment F on Dg { name }',
      validator: const DocumentValidator(
        rules: [KnownTypeNamesRule()],
        includesSuggestions: false,
      ),
    );
    expect(result.diagnostics.single.message, 'Unknown type "Dg".');
  });

  test('a fragment on a scalar is GQL213', () {
    expect(
      idsOf(
        'fragment F on String { name }',
        const FragmentsOnCompositeTypesRule(),
      ),
      ['GQL213'],
    );
  });

  test('an inline fragment on an input type is GQL213', () {
    expect(
      checked.errors('{ ... on Filter { name } }', [
        const FragmentsOnCompositeTypesRule(),
      ]),
      ['1:10 GQL213 Fragment cannot condition on non composite type "Filter".'],
    );
  });

  test('a variable of an object type is GQL226', () {
    expect(
      checked.errors(r'query ($p: [Dog!]) { name }', [
        const VariablesAreInputTypesRule(),
      ]),
      [r'1:12 GQL226 Variable "$p" cannot be non-input type "[Dog!]".'],
    );
  });

  test('a leaf field with a selection is GQL207', () {
    expect(
      checked.errors('{ name { length } }', [const ScalarLeafsRule()]),
      [
        '1:8 GQL207 Field "name" must not have a selection since type '
            '"String" has no subfields.',
      ],
    );
  });

  test('a composite field without a selection is GQL207', () {
    expect(
      checked.errors('{ pet }', [const ScalarLeafsRule()]),
      [
        '1:3 GQL207 Field "pet" of type "Pet" must have a selection of '
            'subfields. Did you mean "pet { ... }"?',
      ],
    );
  });

  test('a missing field is GQL205 with a type suggestion', () {
    expect(
      checked.errors('{ pet { barks } }', [const FieldsOnCorrectTypeRule()]),
      [
        '1:9 GQL205 Cannot query field "barks" on type "Pet". Did you mean '
            'to use an inline fragment on "Dog"?',
      ],
    );
  });

  test('a missing field suggests a close field name', () {
    expect(
      checked.errors('{ nam }', [const FieldsOnCorrectTypeRule()]),
      [
        '1:3 GQL205 Cannot query field "nam" on type "Query". Did you mean "name"?',
      ],
    );
  });

  test('a meta-field is a field of every composite type', () {
    expect(
      checked.errors('{ __typename pet { __typename } }', [
        const FieldsOnCorrectTypeRule(),
      ]),
      isEmpty,
    );
  });

  test('a field below an unknown type is left to KnownTypeNames', () {
    expect(
      checked.errors('{ ... on Nope { missing } }', [
        const FieldsOnCorrectTypeRule(),
      ]),
      isEmpty,
    );
  });

  group('EngineOrderedSort', () {
    int byValue(int a, int b) => a - b;

    test('sorts by a total order like List.sort', () {
      final items = [5, 3, 9, 1, 7, 3, 8, 2];
      expect(
        EngineOrderedSort<int>(byValue).sorted(items),
        [...items]..sort(),
      );
    });

    test('reverses a strictly descending leading run', () {
      expect(EngineOrderedSort<int>(byValue).sorted([9, 5, 2, 7]), [
        2,
        5,
        7,
        9,
      ]);
    });

    test('keeps equal items in their order', () {
      final pairs = [(1, 'a'), (0, 'b'), (1, 'c'), (0, 'd')];
      expect(
        EngineOrderedSort<(int, String)>(
          (a, b) => a.$1 - b.$1,
        ).sorted(pairs),
        [(0, 'b'), (0, 'd'), (1, 'a'), (1, 'c')],
      );
    });

    test('a long list is sorted too', () {
      final items = [for (var i = 0; i < 200; i++) (i * 37) % 101];
      expect(
        EngineOrderedSort<int>(byValue).sorted(items),
        [...items]..sort(),
      );
    });
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -85,10 +85,15 @@ void main() {
       prefix: '',
       covered: const [
         'validation/__tests__/ExecutableDefinitionsRule-test.ts',
+        'validation/__tests__/FieldsOnCorrectTypeRule-test.ts',
+        'validation/__tests__/FragmentsOnCompositeTypesRule-test.ts',
         'validation/__tests__/KnownOperationTypesRules-test.ts',
+        'validation/__tests__/KnownTypeNamesRule-test.ts',
         'validation/__tests__/LoneAnonymousOperationRule-test.ts',
+        'validation/__tests__/ScalarLeafsRule-test.ts',
         'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
         'validation/__tests__/UniqueOperationNamesRule-test.ts',
+        'validation/__tests__/VariablesAreInputTypesRule-test.ts',
       ],
     ),
   ];
```

Create `packages/typed_graphql_conformance/test/validation/fields_on_correct_type_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/FieldsOnCorrectTypeRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const FieldsOnCorrectTypeRule()).withSchema('''
  interface Pet {
    name: String
  }

  type Dog implements Pet {
    name: String
    nickname: String
    barkVolume: Int
  }

  type Cat implements Pet {
    name: String
    nickname: String
    meowVolume: Int
  }

  union CatOrDog = Cat | Dog

  type Human {
    name: String
    pets: [Pet]
  }

  type Query {
    human: Human
  }
''');

  group('Validate: Fields on correct type', () {
    test('Object field selection', () {
      expect(
        port.errors('''
      fragment objectFieldSelection on Dog {
        __typename
        name
      }
    '''),
        isEmpty,
      );
    });

    test('Aliased object field selection', () {
      expect(
        port.errors('''
      fragment aliasedObjectFieldSelection on Dog {
        tn : __typename
        otherName : name
      }
    '''),
        isEmpty,
      );
    });

    test('Interface field selection', () {
      expect(
        port.errors('''
      fragment interfaceFieldSelection on Pet {
        __typename
        name
      }
    '''),
        isEmpty,
      );
    });

    test('Aliased interface field selection', () {
      expect(
        port.errors('''
      fragment interfaceFieldSelection on Pet {
        otherName : name
      }
    '''),
        isEmpty,
      );
    });

    test('Lying alias selection', () {
      expect(
        port.errors('''
      fragment lyingAliasSelection on Dog {
        name : nickname
      }
    '''),
        isEmpty,
      );
    });

    test('Ignores fields on unknown type', () {
      expect(
        port.errors('''
      fragment unknownSelection on UnknownType {
        unknownField
      }
    '''),
        isEmpty,
      );
    });

    test('reports errors when type is known again', () {
      expect(
        port.errors('''
      fragment typeKnownAgain on Pet {
        unknown_pet_field {
          ... on Cat {
            unknown_cat_field
          }
        }
      }
    '''),
        [
          'Cannot query field "unknown_pet_field" on type "Pet". @ 3:9',
          'Cannot query field "unknown_cat_field" on type "Cat". @ 5:13',
        ],
      );
    });

    test('Field not defined on fragment', () {
      expect(
        port.errors('''
      fragment fieldNotDefined on Dog {
        meowVolume
      }
    '''),
        [
          'Cannot query field "meowVolume" on type "Dog". Did you mean "barkVolume"? @ 3:9',
        ],
      );
    });

    test('Field not defined on fragment (no suggestions)', () {
      expect(
        port.errors('''
      fragment fieldNotDefined on Dog {
        meowVolume
      }
    ''', hidesSuggestions: true),
        [
          'Cannot query field "meowVolume" on type "Dog". @ 3:9',
        ],
      );
    });

    test('Ignores deeply unknown field', () {
      expect(
        port.errors('''
      fragment deepFieldNotDefined on Dog {
        unknown_field {
          deeper_unknown_field
        }
      }
    '''),
        [
          'Cannot query field "unknown_field" on type "Dog". @ 3:9',
        ],
      );
    });

    test('Sub-field not defined', () {
      expect(
        port.errors('''
      fragment subFieldNotDefined on Human {
        pets {
          unknown_field
        }
      }
    '''),
        [
          'Cannot query field "unknown_field" on type "Pet". @ 4:11',
        ],
      );
    });

    test('Field not defined on inline fragment', () {
      expect(
        port.errors('''
      fragment fieldNotDefined on Pet {
        ... on Dog {
          meowVolume
        }
      }
    '''),
        [
          'Cannot query field "meowVolume" on type "Dog". Did you mean "barkVolume"? @ 4:11',
        ],
      );
    });

    test('Aliased field target not defined', () {
      expect(
        port.errors('''
      fragment aliasedFieldTargetNotDefined on Dog {
        volume : mooVolume
      }
    '''),
        [
          'Cannot query field "mooVolume" on type "Dog". Did you mean "barkVolume"? @ 3:9',
        ],
      );
    });

    test('Aliased lying field target not defined', () {
      expect(
        port.errors('''
      fragment aliasedLyingFieldTargetNotDefined on Dog {
        barkVolume : kawVolume
      }
    '''),
        [
          'Cannot query field "kawVolume" on type "Dog". Did you mean "barkVolume"? @ 3:9',
        ],
      );
    });

    test('Not defined on interface', () {
      expect(
        port.errors('''
      fragment notDefinedOnInterface on Pet {
        tailLength
      }
    '''),
        [
          'Cannot query field "tailLength" on type "Pet". @ 3:9',
        ],
      );
    });

    test('Defined on implementors but not on interface', () {
      expect(
        port.errors('''
      fragment definedOnImplementorsButNotInterface on Pet {
        nickname
      }
    '''),
        [
          'Cannot query field "nickname" on type "Pet". Did you mean to use an inline fragment on "Cat" or "Dog"? @ 3:9',
        ],
      );
    });

    test('Meta field selection on union', () {
      expect(
        port.errors('''
      fragment directFieldSelectionOnUnion on CatOrDog {
        __typename
      }
    '''),
        isEmpty,
      );
    });

    test('Direct field selection on union', () {
      expect(
        port.errors('''
      fragment directFieldSelectionOnUnion on CatOrDog {
        directField
      }
    '''),
        [
          'Cannot query field "directField" on type "CatOrDog". @ 3:9',
        ],
      );
    });

    test('Defined on implementors queried on union', () {
      expect(
        port.errors('''
      fragment definedOnImplementorsQueriedOnUnion on CatOrDog {
        name
      }
    '''),
        [
          'Cannot query field "name" on type "CatOrDog". Did you mean to use an inline fragment on "Pet", "Cat", or "Dog"? @ 3:9',
        ],
      );
    });

    test('valid field in inline fragment', () {
      expect(
        port.errors('''
      fragment objectFieldSelection on Pet {
        ... on Dog {
          name
        }
        ... {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    group('Fields on correct type error message', () {
      String message(String sdl, String query) {
        final errors = RulePort(
          const FieldsOnCorrectTypeRule(),
        ).withSchema(sdl).errors(query);
        expect(errors, hasLength(1));
        return errors.single.split(' @ ').first;
      }

      test('Works with no suggestions', () {
        expect(
          message('''
        type T {
          fieldWithVeryLongNameThatWillNeverBeSuggested: String
        }
        type Query { t: T }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T".',
        );
      });

      test('Works with no small numbers of type suggestions', () {
        expect(
          message('''
        union T = A | B
        type Query { t: T }

        type A { f: String }
        type B { f: String }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean to use an inline fragment on "A" or "B"?',
        );
      });

      test('Works with no small numbers of field suggestions', () {
        expect(
          message('''
        type T {
          y: String
          z: String
        }
        type Query { t: T }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean "y" or "z"?',
        );
      });

      test('Only shows one set of suggestions at a time, preferring types', () {
        expect(
          message('''
        interface T {
          y: String
          z: String
        }
        type Query { t: T }

        type A implements T {
          f: String
          y: String
          z: String
        }
        type B implements T {
          f: String
          y: String
          z: String
        }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean to use an inline fragment on "A" or "B"?',
        );
      });

      test('Sort type suggestions based on inheritance order', () {
        expect(
          message('''
        interface T { bar: String }
        type Query { t: T }

        interface Z implements T {
          foo: String
          bar: String
        }

        interface Y implements Z & T {
          foo: String
          bar: String
        }

        type X implements Y & Z & T {
          foo: String
          bar: String
        }
      ''', '{ t { foo } }'),
          'Cannot query field "foo" on type "T". Did you mean to use an inline fragment on "Z", "Y", or "X"?',
        );

        expect(
          message('''
        interface Animal { name: String }
        interface Mammal implements Animal { name: String }

        interface Canine implements Animal & Mammal { name: String }
        type Dog implements Animal & Mammal & Canine { name: String }

        interface Feline implements Animal & Mammal { name: String }
        type Cat implements Animal & Mammal & Feline { name: String }

        union CatOrDog = Cat | Dog
        type Query { catOrDog: CatOrDog }
      ''', '{ catOrDog { name } }'),
          'Cannot query field "name" on type "CatOrDog". Did you mean to use an inline fragment on "Animal", "Mammal", "Canine", "Dog", or "Feline"?',
        );
      });

      test('Limits lots of type suggestions', () {
        expect(
          message('''
        union T = A | B | C | D | E | F
        type Query { t: T }

        type A { f: String }
        type B { f: String }
        type C { f: String }
        type D { f: String }
        type E { f: String }
        type F { f: String }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean to use an inline fragment on "A", "B", "C", "D", or "E"?',
        );
      });

      test('Limits lots of field suggestions', () {
        expect(
          message('''
        type T {
          u: String
          v: String
          w: String
          x: String
          y: String
          z: String
        }
        type Query { t: T }
      ''', '{ t { f } }'),
          'Cannot query field "f" on type "T". Did you mean "u", "v", "w", "x", or "y"?',
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/fragments_on_composite_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/FragmentsOnCompositeTypesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const FragmentsOnCompositeTypesRule());

  group('Validate: Fragments on composite types', () {
    test('object is valid fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Dog {
        barks
      }
    '''),
        isEmpty,
      );
    });

    test('interface is valid fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Pet {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('object is valid inline fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Pet {
        ... on Dog {
          barks
        }
      }
    '''),
        isEmpty,
      );
    });

    test('interface is valid inline fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on Mammal {
        ... on Canine {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('inline fragment without type is valid', () {
      expect(
        port.errors('''
      fragment validFragment on Pet {
        ... {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('union is valid fragment type', () {
      expect(
        port.errors('''
      fragment validFragment on CatOrDog {
        __typename
      }
    '''),
        isEmpty,
      );
    });

    test('scalar is invalid fragment type', () {
      expect(
        port.errors('''
      fragment scalarFragment on Boolean {
        bad
      }
    '''),
        [
          'Fragment "scalarFragment" cannot condition on non composite type "Boolean". @ 2:34',
        ],
      );
    });

    test('enum is invalid fragment type', () {
      expect(
        port.errors('''
      fragment scalarFragment on FurColor {
        bad
      }
    '''),
        [
          'Fragment "scalarFragment" cannot condition on non composite type "FurColor". @ 2:34',
        ],
      );
    });

    test('input object is invalid fragment type', () {
      expect(
        port.errors('''
      fragment inputFragment on ComplexInput {
        stringField
      }
    '''),
        [
          'Fragment "inputFragment" cannot condition on non composite type "ComplexInput". @ 2:33',
        ],
      );
    });

    test('scalar is invalid inline fragment type', () {
      expect(
        port.errors('''
      fragment invalidFragment on Pet {
        ... on String {
          barks
        }
      }
    '''),
        [
          'Fragment cannot condition on non composite type "String". @ 3:16',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/known_type_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownTypeNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownTypeNamesRule());

  group('Validate: Known type names', () {
    test('known type names are valid', () {
      expect(
        port.errors(r'''
      query Foo(
        $var: String
        $required: [Int!]!
        $introspectionType: __EnumValue
      ) {
        user(id: 4) {
          pets { ... on Pet { name }, ...PetFields, ... { name } }
        }
      }

      fragment PetFields on Pet {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('unknown type names are invalid', () {
      expect(
        port.errors(r'''
      query Foo($var: [JumbledUpLetters!]!) {
        user(id: 4) {
          name
          pets { ... on Badger { name }, ...PetFields }
        }
      }
      fragment PetFields on Peat {
        name
      }
    '''),
        [
          'Unknown type "JumbledUpLetters". @ 2:24',
          'Unknown type "Badger". @ 5:25',
          'Unknown type "Peat". Did you mean "Pet" or "Cat"? @ 8:29',
        ],
      );
    });

    test('unknown type names are invalid (no suggestions)', () {
      expect(
        port.errors(r'''
      query Foo($var: [JumbledUpLetters!]!) {
        user(id: 4) {
          name
          pets { ... on Badger { name }, ...PetFields }
        }
      }
      fragment PetFields on Peat {
        name
      }
    ''', hidesSuggestions: true),
        [
          'Unknown type "JumbledUpLetters". @ 2:24',
          'Unknown type "Badger". @ 5:25',
          'Unknown type "Peat". @ 8:29',
        ],
      );
    });

    test('references to standard scalars that are missing in schema', () {
      // Adapted: graphql-js's type map holds only the types the schema
      // reaches, so `ID`, `Float` and `Int` are unknown there. A schema here
      // always has the five built-in scalars (spec §3.5).
      final queryOnly = port.withSchema('type Query { foo: String }');
      expect(
        queryOnly.errors(r'''
      query ($id: ID, $float: Float, $int: Int) {
        __typename
      }
    '''),
        isEmpty,
      );
    });

    group('within SDL', () {
      test('use standard types', () {
        expect(
          port.errors('''
        type Query {
          string: String
          int: Int
          float: Float
          boolean: Boolean
          id: ID
          introspectionType: __EnumValue
        }
      '''),
          isEmpty,
        );
      });

      test('reference types defined inside the same document', () {
        expect(
          port.errors('''
        union SomeUnion = SomeObject | AnotherObject

        type SomeObject implements SomeInterface {
          someScalar(arg: SomeInputObject): SomeScalar
        }

        type AnotherObject {
          foo(arg: SomeInputObject): String
        }

        type SomeInterface {
          someScalar(arg: SomeInputObject): SomeScalar
        }

        input SomeInputObject {
          someScalar: SomeScalar
        }

        scalar SomeScalar

        type RootQuery {
          someInterface: SomeInterface
          someUnion: SomeUnion
          someScalar: SomeScalar
          someObject: SomeObject
        }

        schema {
          query: RootQuery
        }
      '''),
          isEmpty,
        );
      });

      test('does not consider non-type definitions', () {
        expect(
          port.errors('''
        query Foo { __typename }
        fragment Foo on Query { __typename }
        directive @Foo on QUERY

        type Query {
          foo: Foo
        }
      ''', hidesSuggestions: true),
          ['Unknown type "Foo". @ 7:16'],
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/scalar_leafs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ScalarLeafsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const ScalarLeafsRule());

  group('Validate: Scalar leafs', () {
    test('valid scalar selection', () {
      expect(
        port.errors('''
      fragment scalarSelection on Dog {
        barks
      }
    '''),
        isEmpty,
      );
    });

    test('object type missing selection', () {
      expect(
        port.errors('''
      query directQueryOnObjectWithoutSubFields {
        human
      }
    '''),
        [
          'Field "human" of type "Human" must have a selection of subfields. Did you mean "human { ... }"? @ 3:9',
        ],
      );
    });

    test('object type having only one selection', () {
      // The parser rejects an empty selection set, so the document is built
      // in code, as graphql-js's test does.
      final document = Document([
        OperationDefinition(
          .query,
          SelectionSet([
            Field(null, const Name('human'), selectionSet: SelectionSet([])),
          ]),
        ),
      ]);
      final result = const DocumentValidator(
        rules: [ScalarLeafsRule()],
      ).validate(RulePort.testSchema, document);
      expect(
        [for (final diagnostic in result.diagnostics) diagnostic.message],
        [
          'Field "human" of type "Human" must have at least one field '
              'selected.',
        ],
      );
    });

    test('interface type missing selection', () {
      expect(
        port.errors('''
      {
        human { pets }
      }
    '''),
        [
          'Field "pets" of type "[Pet]" must have a selection of subfields. Did you mean "pets { ... }"? @ 3:17',
        ],
      );
    });

    test('valid scalar selection with args', () {
      expect(
        port.errors('''
      fragment scalarSelectionWithArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('scalar selection not allowed on Boolean', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedOnBoolean on Dog {
        barks { sinceWhen }
      }
    '''),
        [
          'Field "barks" must not have a selection since type "Boolean" has no subfields. @ 3:15',
        ],
      );
    });

    test('scalar selection not allowed on Enum', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedOnEnum on Cat {
        furColor { inHexDec }
      }
    '''),
        [
          'Field "furColor" must not have a selection since type "FurColor" has no subfields. @ 3:18',
        ],
      );
    });

    test('scalar selection not allowed with args', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedWithArgs on Dog {
        doesKnowCommand(dogCommand: SIT) { sinceWhen }
      }
    '''),
        [
          'Field "doesKnowCommand" must not have a selection since type "Boolean" has no subfields. @ 3:42',
        ],
      );
    });

    test('Scalar selection not allowed with directives', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedWithDirectives on Dog {
        name @include(if: true) { isAlsoHumanName }
      }
    '''),
        [
          'Field "name" must not have a selection since type "String" has no subfields. @ 3:33',
        ],
      );
    });

    test('Scalar selection not allowed with directives and args', () {
      expect(
        port.errors('''
      fragment scalarSelectionsNotAllowedWithDirectivesAndArgs on Dog {
        doesKnowCommand(dogCommand: SIT) @include(if: true) { sinceWhen }
      }
    '''),
        [
          'Field "doesKnowCommand" must not have a selection since type "Boolean" has no subfields. @ 3:61',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/variables_are_input_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/VariablesAreInputTypesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const VariablesAreInputTypesRule());

  group('Validate: Variables are input types', () {
    // Adapted: September2025 has no fragment arguments, so the fragment of
    // the graphql-js test is left out (mapping/validation.csv).
    test('unknown types are ignored', () {
      expect(
        port.errors(r'''
      query Foo($a: Unknown, $b: [[Unknown!]]!) {
        field(a: $a, b: $b)
      }
    '''),
        isEmpty,
      );
    });

    test('input types are valid', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: [Boolean!]!, $c: ComplexInput) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('output types are invalid', () {
      expect(
        port.errors(r'''
      query Foo($a: Dog, $b: [[CatOrDog!]]!, $c: Pet) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        [
          r'Variable "$a" cannot be non-input type "Dog". @ 2:21',
          r'Variable "$b" cannot be non-input type "[[CatOrDog!]]!". @ 2:30',
          r'Variable "$c" cannot be non-input type "Pet". @ 2:50',
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/type_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/fields_on_correct_type_test.dart test/validation/fragments_on_composite_types_test.dart test/validation/known_type_names_test.dart test/validation/scalar_leafs_test.dart test/validation/variables_are_input_types_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -345,6 +345,25 @@ enum DiagnosticCode(
   /// `@include` there (spec §5.2.4.1).
   singleFieldSubscriptions('GQL204'),
 
+  /// `GQL205`: a field the parent type does not define and that is no
+  /// meta-field (spec §5.3.1).
+  fieldsOnCorrectType('GQL205'),
+
+  /// `GQL207`: a leaf field with a selection, or a composite field without
+  /// one (spec §5.3.3).
+  scalarLeafs('GQL207'),
+
+  /// `GQL212`: a type name in a type condition or a variable definition
+  /// that the schema does not define (spec §5.5.1.2, §5.8.1).
+  knownTypeNames('GQL212'),
+
+  /// `GQL213`: a fragment or inline fragment whose type condition is not
+  /// an object, interface or union type (spec §5.5.1.3).
+  fragmentsOnCompositeTypes('GQL213'),
+
+  /// `GQL226`: a variable whose type is not an input type (spec §5.8.2).
+  variablesAreInputTypes('GQL226'),
+
   /// `GQL230`: validating a document needed more work than the
   /// validator's step budget allows, such as fragments that expand to
   /// more fields than the budget, or many operations each spreading a
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,10 +5,15 @@ import '../language/visitor/ast_walker.dart';
 import '../schema/validation/schema_validation_result.dart';
 import 'document_validation_result.dart';
 import 'rules/executable_definitions_rule.dart';
+import 'rules/fields_on_correct_type_rule.dart';
+import 'rules/fragments_on_composite_types_rule.dart';
 import 'rules/known_operation_types_rule.dart';
+import 'rules/known_type_names_rule.dart';
 import 'rules/lone_anonymous_operation_rule.dart';
+import 'rules/scalar_leafs_rule.dart';
 import 'rules/single_field_subscriptions_rule.dart';
 import 'rules/unique_operation_names_rule.dart';
+import 'rules/variables_are_input_types_rule.dart';
 import 'validation_context.dart';
 import 'validation_rule.dart';
 
@@ -53,6 +58,11 @@ final class const DocumentValidator({
     UniqueOperationNamesRule(),
     LoneAnonymousOperationRule(),
     SingleFieldSubscriptionsRule(),
+    KnownTypeNamesRule(),
+    FragmentsOnCompositeTypesRule(),
+    VariablesAreInputTypesRule(),
+    ScalarLeafsRule(),
+    FieldsOnCorrectTypeRule(),
   ];
 
   /// Validates [document] against [schema]; diagnostics point into
```

Create `packages/typed_graphql/lib/src/validation/rules/engine_ordered_sort.dart`:

```dart
/// Sorts a short list as the JavaScript engines' `Array.prototype.sort`
/// does, so a comparator that is not a total order (graphql-js's type
/// suggestions compare by usage, then by inheritance, then by name) gives
/// the order graphql-js gives.
///
/// V8 sorts a list of fewer than 64 items by finding the leading run
/// (reversing it when strictly descending) and inserting the rest by
/// binary search. A longer list falls back to [List.sort], which agrees
/// whenever the comparator is a total order.
final class EngineOrderedSort<T>(final int Function(T a, T b) compare) {
  /// Creates a sort with [compare].
  this;

  static const int _shortListLength = 64;

  /// A new list of [items] in order.
  List<T> sorted(Iterable<T> items) {
    final list = items.toList();
    if (list.length >= _shortListLength) {
      return list..sort(compare);
    }
    if (list.length < 2) {
      return list;
    }
    _insertAfterRun(list, _makeRun(list));
    return list;
  }

  // The length of the leading run, which is reversed when descending.
  int _makeRun(List<T> list) {
    final isDescending = compare(list[1], list[0]) < 0;
    var length = 2;
    while (length < list.length) {
      final order = compare(list[length], list[length - 1]);
      if (isDescending ? order >= 0 : order < 0) {
        break;
      }
      length++;
    }
    if (isDescending) {
      final reversed = list.sublist(0, length).reversed.toList();
      list.setRange(0, length, reversed);
    }
    return length;
  }

  void _insertAfterRun(List<T> list, int runLength) {
    for (var start = runLength; start < list.length; start++) {
      final pivot = list[start];
      var left = 0;
      var right = start;
      while (left < right) {
        final middle = left + ((right - left) >> 1);
        if (compare(pivot, list[middle]) < 0) {
          right = middle;
        } else {
          left = middle + 1;
        }
      }
      list.setRange(left + 1, start + 1, list, left);
      list[left] = pivot;
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/field_type_suggestions.dart`:

```dart
import '../../diagnostics/suggestions.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import 'engine_ordered_sort.dart';

/// The types to condition on when an abstract type lacks a field
/// (graphql-js's `getSuggestedTypeNames`): the possible types that define
/// it and the interfaces of those, the most used first.
final class FieldTypeSuggestions(final Schema schema) {
  /// Creates the suggestions over [schema].
  this;

  /// The names of the object and interface types that define [fieldName]
  /// among the possible types of [parent]; empty unless [parent] is
  /// abstract.
  List<String> namesFor(SchemaType parent, String fieldName) {
    if (!parent.isAbstractType) {
      return const [];
    }
    final suggested = <SchemaType>{};
    final usageCount = <String, int>{};
    for (final possible in schema.possibleTypes(parent)) {
      if (possible.fieldNamed(fieldName) == null) {
        continue;
      }
      suggested.add(possible);
      usageCount[possible.name] = 1;
      for (final reference in possible.interfaces) {
        if (schema.typeNamed(reference.name) case final InterfaceType type
            when type.fieldNamed(fieldName) != null) {
          suggested.add(type);
          usageCount[type.name] = (usageCount[type.name] ?? 0) + 1;
        }
      }
    }
    final sorted = EngineOrderedSort<SchemaType>(
      (a, b) => _compare(a, b, usageCount),
    ).sorted(suggested);
    return [for (final type in sorted) type.name];
  }

  // Most used first, then super types before their subtypes, then by name.
  int _compare(SchemaType a, SchemaType b, Map<String, int> usageCount) {
    final usageDifference =
        (usageCount[b.name] ?? 0) - (usageCount[a.name] ?? 0);
    if (usageDifference != 0) {
      return usageDifference;
    }
    if (a is InterfaceType && schema.isSubType(a, b)) {
      return -1;
    }
    if (b is InterfaceType && schema.isSubType(b, a)) {
      return 1;
    }
    return const Suggestions().naturalCompare(a.name, b.name);
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/fields_on_correct_type_rule.dart`:

```dart
import '../../diagnostics/suggestions.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'field_type_suggestions.dart';

/// Spec §5.3.1 "Field Selections": a field is defined by the type whose
/// selection set holds it, or is a meta-field (`GQL205`).
///
/// The message suggests inline fragments on the types that define the
/// field, or else field names close to the one written.
///
/// {@category validation}
final class const FieldsOnCorrectTypeRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _FieldsOnCorrectType(context);
}

final class _FieldsOnCorrectType(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field && context.typeInfo.fieldDefinition == null) {
      if (context.typeInfo.parentType case final parent?) {
        final name = node.name.value;
        context.report(
          .fieldsOnCorrectType,
          'Cannot query field "$name" on type "${parent.name}".'
          '${_suggestion(parent, name)}',
          [node],
        );
      }
    }
    return .next;
  }

  String _suggestion(SchemaType parent, String fieldName) {
    if (!context.includesSuggestions) {
      return '';
    }
    const suggestions = Suggestions();
    final onTypes = suggestions.didYouMean(
      FieldTypeSuggestions(context.schema).namesFor(parent, fieldName),
      subject: 'to use an inline fragment on',
    );
    if (onTypes.isNotEmpty) {
      return onTypes;
    }
    final fieldNames = switch (parent) {
      ObjectType(:final fields) || InterfaceType(:final fields) => [
        for (final field in fields) field.name,
      ],
      _ => const <String>[],
    };
    return suggestions.didYouMean(suggestions.listFor(fieldName, fieldNames));
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/fragments_on_composite_types_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.3 "Fragments On Composite Types": a fragment's type
/// condition is an object, interface or union type (`GQL213`).
///
/// An unknown type is left to `KnownTypeNamesRule`.
///
/// {@category validation}
final class const FragmentsOnCompositeTypesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _FragmentsOnCompositeTypes(context);
}

final class _FragmentsOnCompositeTypes(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case InlineFragment(:final typeCondition?):
        if (_isNonComposite(typeCondition)) {
          context.report(
            .fragmentsOnCompositeTypes,
            'Fragment cannot condition on non composite type '
            '"${const Printer().print(typeCondition)}".',
            [typeCondition],
          );
        }
      case FragmentDefinition(:final name, :final typeCondition):
        if (_isNonComposite(typeCondition)) {
          context.report(
            .fragmentsOnCompositeTypes,
            'Fragment "${name.value}" cannot condition on non composite type '
            '"${const Printer().print(typeCondition)}".',
            [typeCondition],
          );
        }
      default:
    }
    return .next;
  }

  bool _isNonComposite(NamedType condition) =>
      switch (context.schema.namedTypeOf(condition)) {
        final type? => !type.isCompositeType,
        null => false,
      };
}
```

Create `packages/typed_graphql/lib/src/validation/rules/known_type_names_rule.dart`:

```dart
import '../../diagnostics/suggestions.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/build/built_ins.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.2 "Fragment Spread Type Existence" and §5.8.2 "Variables
/// Are Input Types": every type a type condition or a variable definition
/// names exists (`GQL212`).
///
/// As graphql-js, the types the document itself defines are known. The
/// built-in scalars and introspection types are always known: graphql-js's
/// extra case for them inside a type system definition only matters when
/// there is no schema, and a validated document always has one.
///
/// {@category validation}
final class const KnownTypeNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownTypeNames(context);
}

final class _KnownTypeNames extends AstVisitor {
  _KnownTypeNames(this.context) {
    const builtIns = BuiltIns();
    for (final type in [
      ...context.schema.types,
      ...builtIns.scalars,
      ...builtIns.introspectionTypes,
    ]) {
      _typeNames.add(type.name);
    }
    for (final definition in context.document.definitions) {
      if (definition case TypeDefinition(:final name)) {
        _typeNames.add(name.value);
      }
    }
  }

  final ValidationContext context;
  final Set<String> _typeNames = {};

  @override
  VisitAction enter(Node node) {
    if (node case NamedType(:final name)
        when !_typeNames.contains(name.value)) {
      const suggestions = Suggestions();
      final suggested = context.includesSuggestions
          ? suggestions.listFor(name.value, _typeNames)
          : const <String>[];
      context.report(
        .knownTypeNames,
        'Unknown type "${name.value}".${suggestions.didYouMean(suggested)}',
        [node],
      );
    }
    return .next;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/scalar_leafs_rule.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.3.3 "Leaf Field Selections": a field of a scalar or enum type
/// has no selection, and a field of any other type has one that is not
/// empty (`GQL207`).
///
/// {@category validation}
final class const ScalarLeafsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => _ScalarLeafs(context);
}

final class _ScalarLeafs(final ValidationContext context) extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      if (context.typeInfo.type case final type?) {
        _check(node, type);
      }
    }
    return .next;
  }

  void _check(Field field, TypeRef type) {
    final name = field.name.value;
    final typeText = const Printer().print(type);
    final isLeaf = context.schema.namedTypeOf(type)?.isLeafType ?? false;
    switch (field.selectionSet) {
      case final selection? when isLeaf:
        context.report(
          .scalarLeafs,
          'Field "$name" must not have a selection since type "$typeText" '
          'has no subfields.',
          [selection],
        );
      case null when !isLeaf:
        context.report(
          .scalarLeafs,
          'Field "$name" of type "$typeText" must have a selection of '
          'subfields. Did you mean "$name { ... }"?',
          [field],
        );
      case SelectionSet(selections: []) when !isLeaf:
        context.report(
          .scalarLeafs,
          'Field "$name" of type "$typeText" must have at least one field '
          'selected.',
          [field],
        );
      default:
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/variables_are_input_types_rule.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.8.2 "Variables Are Input Types": a variable's type is a
/// scalar, enum or input object type, possibly wrapped (`GQL226`).
///
/// An unknown type is left to `KnownTypeNamesRule`.
///
/// {@category validation}
final class const VariablesAreInputTypesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _VariablesAreInputTypes(context);
}

final class _VariablesAreInputTypes(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case VariableDefinition(:final variable, :final type)) {
      final named = context.schema.namedTypeOf(type);
      if (named != null && !named.isInputType) {
        context.report(
          .variablesAreInputTypes,
          'Variable "\$${variable.name.value}" cannot be non-input type '
          '"${const Printer().print(type)}".',
          [type],
        );
      }
    }
    return .next;
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -90,10 +90,15 @@ export 'src/schema/validation/schema_validator.dart';
 export 'src/validation/document_validation_result.dart';
 export 'src/validation/document_validator.dart';
 export 'src/validation/rules/executable_definitions_rule.dart';
+export 'src/validation/rules/fields_on_correct_type_rule.dart';
+export 'src/validation/rules/fragments_on_composite_types_rule.dart';
 export 'src/validation/rules/known_operation_types_rule.dart';
+export 'src/validation/rules/known_type_names_rule.dart';
 export 'src/validation/rules/lone_anonymous_operation_rule.dart';
+export 'src/validation/rules/scalar_leafs_rule.dart';
 export 'src/validation/rules/single_field_subscriptions_rule.dart';
 export 'src/validation/rules/unique_operation_names_rule.dart';
+export 'src/validation/rules/variables_are_input_types_rule.dart';
 export 'src/validation/type_info.dart';
 export 'src/validation/validation_context.dart';
 export 'src/validation/validation_rule.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,3 +39,65 @@ validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscription
 validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with @skip or @include directive,ported,test/validation/single_field_subscriptions_test.dart,
 validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,fails with @skip or @include directive in anonymous subscription,ported,test/validation/single_field_subscriptions_test.dart,
 validation/__tests__/SingleFieldSubscriptionsRule-test.ts,Validate: Subscriptions with single field,skips if not subscription type,ported,test/validation/single_field_subscriptions_test.dart,
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names,known type names are valid,ported,test/validation/known_type_names_test.dart,
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names,unknown type names are invalid,ported,test/validation/known_type_names_test.dart,
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names,unknown type names are invalid (no suggestions),ported,test/validation/known_type_names_test.dart,
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names,references to standard scalars that are missing in schema,adapted,test/validation/known_type_names_test.dart,graphql-js's type map holds only the types a schema reaches; here the built-in scalars always exist (spec §3.5)
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,use standard types,ported,test/validation/known_type_names_test.dart,
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,reference types defined inside the same document,ported,test/validation/known_type_names_test.dart,
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,unknown type references,skipped,,SDL validation: the schema builder reports unknown types (M3)
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,does not consider non-type definitions,adapted,test/validation/known_type_names_test.dart,run without suggestions: the test schema's type names would be suggested
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,reference standard types inside extension document,skipped,,SDL validation: the schema builder reports unknown types (M3)
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,reference types inside extension document,skipped,,SDL validation: the schema builder reports unknown types (M3)
+validation/__tests__/KnownTypeNamesRule-test.ts,Validate: Known type names > within SDL,unknown type references inside extension document,skipped,,SDL validation: the schema builder reports unknown types (M3)
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,object is valid fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,interface is valid fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,object is valid inline fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,interface is valid inline fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,inline fragment without type is valid,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,union is valid fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,scalar is invalid fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,enum is invalid fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,input object is invalid fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments on composite types,scalar is invalid inline fragment type,ported,test/validation/fragments_on_composite_types_test.dart,
+validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,unknown types are ignored,adapted,test/validation/variables_are_input_types_test.dart,the fragment with variables is left out: September2025 has no fragment arguments
+validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,input types are valid,adapted,test/validation/variables_are_input_types_test.dart,the fragment with variables is left out: September2025 has no fragment arguments
+validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,output types are invalid,ported,test/validation/variables_are_input_types_test.dart,
+validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,output types on fragment arguments are invalid,skipped,,experimental fragment arguments: September2025 does not have them and the parser does not parse them
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,valid scalar selection,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,object type missing selection,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,object type having only one selection,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,interface type missing selection,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,valid scalar selection with args,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,scalar selection not allowed on Boolean,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,scalar selection not allowed on Enum,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,scalar selection not allowed with args,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,Scalar selection not allowed with directives,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,Scalar selection not allowed with directives and args,ported,test/validation/scalar_leafs_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Object field selection,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Aliased object field selection,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Interface field selection,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Aliased interface field selection,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Lying alias selection,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Ignores fields on unknown type,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,reports errors when type is known again,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Field not defined on fragment,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Field not defined on fragment (no suggestions),ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Ignores deeply unknown field,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Sub-field not defined,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Field not defined on inline fragment,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Aliased field target not defined,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Aliased lying field target not defined,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Not defined on interface,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Defined on implementors but not on interface,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Meta field selection on union,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Direct field selection on union,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,Defined on implementors queried on union,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type,valid field in inline fragment,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Works with no suggestions,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Works with no small numbers of type suggestions,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Works with no small numbers of field suggestions,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,"Only shows one set of suggestions at a time, preferring types",ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Sort type suggestions based on inheritance order,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Limits lots of type suggestions,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Limits lots of field suggestions,ported,test/validation/fields_on_correct_type_test.dart,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/type_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/fields_on_correct_type_test.dart test/validation/fragments_on_composite_types_test.dart test/validation/known_type_names_test.dart test/validation/scalar_leafs_test.dart test/validation/variables_are_input_types_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The type rules: `KnownTypeNamesRule`, `FragmentsOnCompositeTypesRule`,
  `VariablesAreInputTypesRule`, `ScalarLeafsRule` and
  `FieldsOnCorrectTypeRule` (`GQL205`, `GQL207`, `GQL212`, `GQL213`,
  `GQL226`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/rules/engine_ordered_sort.dart packages/typed_graphql/lib/src/validation/rules/field_type_suggestions.dart packages/typed_graphql/lib/src/validation/rules/fields_on_correct_type_rule.dart packages/typed_graphql/lib/src/validation/rules/fragments_on_composite_types_rule.dart packages/typed_graphql/lib/src/validation/rules/known_type_names_rule.dart packages/typed_graphql/lib/src/validation/rules/scalar_leafs_rule.dart packages/typed_graphql/lib/src/validation/rules/variables_are_input_types_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/type_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/fields_on_correct_type_test.dart packages/typed_graphql_conformance/test/validation/fragments_on_composite_types_test.dart packages/typed_graphql_conformance/test/validation/known_type_names_test.dart packages/typed_graphql_conformance/test/validation/scalar_leafs_test.dart packages/typed_graphql_conformance/test/validation/variables_are_input_types_test.dart
git commit -q -m "feat(typed_graphql): add the type rules of operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: The argument rules

`KnownArgumentNamesRule`, `UniqueArgumentNamesRule` and `ProvidedRequiredArgumentsRule` (`GQL208`–`GQL210`) with their ported suites.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/rules/known_argument_names_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/unique_argument_names_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/argument_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/known_argument_names_test.dart`, `packages/typed_graphql_conformance/test/validation/provided_required_arguments_test.dart`, `packages/typed_graphql_conformance/test/validation/unique_argument_names_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
- Diagnostic codes: `GQL208`, `GQL209`, `GQL210`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/rules/known_argument_names_rule.dart
final class const KnownArgumentNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _KnownArgumentNames(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/provided_required_arguments_rule.dart
final class const ProvidedRequiredArgumentsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _ProvidedRequiredArguments(final ValidationContext context)
  void leave(Node node)

// validation/rules/unique_argument_names_rule.dart
final class const UniqueArgumentNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UniqueArgumentNames(final ValidationContext context)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/argument_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the branches
// those suites do not reach.
void main() {
  final checked = Checked('''
type Query { field(arg: String, needed: Int!): String plain: String }
directive @tag(label: String!) on FIELD
''');

  test('an unknown field argument is GQL208', () {
    expect(
      checked.errors('{ field(arg: "a", needed: 1, agr: "b") }', [
        const KnownArgumentNamesRule(),
      ]),
      [
        '1:30 GQL208 Unknown argument "agr" on field "Query.field". '
            'Did you mean "arg"?',
      ],
    );
  });

  test('an unknown directive argument is GQL208', () {
    expect(
      checked.errors('{ plain @tag(lable: "a", label: "b") }', [
        const KnownArgumentNamesRule(),
      ]),
      [
        '1:14 GQL208 Unknown argument "lable" on directive "@tag". '
            'Did you mean "label"?',
      ],
    );
  });

  test('a repeated argument is GQL209', () {
    expect(
      checked.errors('{ field(arg: "a", needed: 1, arg: "b") }', [
        const UniqueArgumentNamesRule(),
      ]),
      ['1:9 GQL209 There can be only one argument named "arg".'],
    );
  });

  test('a repeated argument relates to every other name', () {
    final result = checked.validate(
      '{ field(arg: "a", arg: "b", arg: "c") }',
      validator: const DocumentValidator(rules: [UniqueArgumentNamesRule()]),
    );
    expect(result.diagnostics.single.related, hasLength(2));
  });

  test('a repeated directive argument is GQL209', () {
    expect(
      checked.errors('{ plain @tag(label: "a", label: "b") }', [
        const UniqueArgumentNamesRule(),
      ]),
      ['1:14 GQL209 There can be only one argument named "label".'],
    );
  });

  test('a missing required field argument is GQL210', () {
    expect(
      checked.errors('{ field }', [const ProvidedRequiredArgumentsRule()]),
      [
        '1:3 GQL210 Argument "Query.field(needed:)" of type "Int!" is '
            'required, but it was not provided.',
      ],
    );
  });

  test('a missing required directive argument is GQL210', () {
    expect(
      checked.errors('{ plain @tag }', [const ProvidedRequiredArgumentsRule()]),
      [
        '1:9 GQL210 Argument "@tag(label:)" of type "String!" is required, '
            'but it was not provided.',
      ],
    );
  });

  test('an unknown directive is left to KnownDirectives', () {
    expect(
      checked.errors('{ plain @nope(x: 1) }', [
        const KnownArgumentNamesRule(),
        const ProvidedRequiredArgumentsRule(),
      ]),
      isEmpty,
    );
  });

  test('errors inside a field come before its missing argument', () {
    expect(
      checked.errors('{ field(arg: "a", other: 1) }', [
        const KnownArgumentNamesRule(),
        const ProvidedRequiredArgumentsRule(),
      ]),
      [startsWith('1:19 GQL208'), startsWith('1:3 GQL210')],
    );
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -87,11 +87,14 @@ void main() {
         'validation/__tests__/ExecutableDefinitionsRule-test.ts',
         'validation/__tests__/FieldsOnCorrectTypeRule-test.ts',
         'validation/__tests__/FragmentsOnCompositeTypesRule-test.ts',
+        'validation/__tests__/KnownArgumentNamesRule-test.ts',
         'validation/__tests__/KnownOperationTypesRules-test.ts',
         'validation/__tests__/KnownTypeNamesRule-test.ts',
         'validation/__tests__/LoneAnonymousOperationRule-test.ts',
+        'validation/__tests__/ProvidedRequiredArgumentsRule-test.ts',
         'validation/__tests__/ScalarLeafsRule-test.ts',
         'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
+        'validation/__tests__/UniqueArgumentNamesRule-test.ts',
         'validation/__tests__/UniqueOperationNamesRule-test.ts',
         'validation/__tests__/VariablesAreInputTypesRule-test.ts',
       ],
```

Create `packages/typed_graphql_conformance/test/validation/known_argument_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownArgumentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownArgumentNamesRule());

  group('Validate: Known argument names', () {
    test('single arg is known', () {
      expect(
        port.errors('''
      fragment argOnRequiredArg on Dog {
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('multiple args are known', () {
      expect(
        port.errors('''
      fragment multipleArgs on ComplicatedArgs {
        multipleReqs(req1: 1, req2: 2)
      }
    '''),
        isEmpty,
      );
    });

    test('ignores args of unknown fields', () {
      expect(
        port.errors('''
      fragment argOnUnknownField on Dog {
        unknownField(unknownArg: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('multiple args in reverse order are known', () {
      expect(
        port.errors('''
      fragment multipleArgsReverseOrder on ComplicatedArgs {
        multipleReqs(req2: 2, req1: 1)
      }
    '''),
        isEmpty,
      );
    });

    test('no args on optional arg', () {
      expect(
        port.errors('''
      fragment noArgOnOptionalArg on Dog {
        isHouseTrained
      }
    '''),
        isEmpty,
      );
    });

    test('args are known deeply', () {
      expect(
        port.errors('''
      {
        dog {
          doesKnowCommand(dogCommand: SIT)
        }
        human {
          pet {
            ... on Dog {
              doesKnowCommand(dogCommand: SIT)
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('directive args are known', () {
      expect(
        port.errors('''
      {
        dog @skip(if: true)
      }
    '''),
        isEmpty,
      );
    });

    test('field args are invalid', () {
      expect(
        port.errors('''
      {
        dog @skip(unless: true)
      }
    '''),
        [
          'Unknown argument "unless" on directive "@skip". @ 3:19',
        ],
      );
    });

    test('directive without args is valid', () {
      expect(
        port.errors('''
      {
        dog @onField
      }
    '''),
        isEmpty,
      );
    });

    test('arg passed to directive without arg is reported', () {
      expect(
        port.errors('''
      {
        dog @onField(if: true)
      }
    '''),
        [
          'Unknown argument "if" on directive "@onField". @ 3:22',
        ],
      );
    });

    test('misspelled directive args are reported', () {
      expect(
        port.errors('''
      {
        dog @skip(iff: true)
      }
    '''),
        [
          'Unknown argument "iff" on directive "@skip". Did you mean "if"? @ 3:19',
        ],
      );
    });

    test('misspelled directive args are reported (no suggestions)', () {
      expect(
        port.errors('''
      {
        dog @skip(iff: true)
      }
    ''', hidesSuggestions: true),
        [
          'Unknown argument "iff" on directive "@skip". @ 3:19',
        ],
      );
    });

    test('invalid arg name', () {
      expect(
        port.errors('''
      fragment invalidArgName on Dog {
        doesKnowCommand(unknown: true)
      }
    '''),
        [
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 3:25',
        ],
      );
    });

    test('misspelled arg name is reported', () {
      expect(
        port.errors('''
      fragment invalidArgName on Dog {
        doesKnowCommand(DogCommand: true)
      }
    '''),
        [
          'Unknown argument "DogCommand" on field "Dog.doesKnowCommand". Did you mean "dogCommand"? @ 3:25',
        ],
      );
    });

    test('misspelled arg name is reported (no suggestions)', () {
      expect(
        port.errors('''
      fragment invalidArgName on Dog {
        doesKnowCommand(DogCommand: true)
      }
    ''', hidesSuggestions: true),
        [
          'Unknown argument "DogCommand" on field "Dog.doesKnowCommand". @ 3:25',
        ],
      );
    });

    test('unknown args amongst known args', () {
      expect(
        port.errors('''
      fragment oneGoodArgOneInvalidArg on Dog {
        doesKnowCommand(whoKnows: 1, dogCommand: SIT, unknown: true)
      }
    '''),
        [
          'Unknown argument "whoKnows" on field "Dog.doesKnowCommand". @ 3:25',
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 3:55',
        ],
      );
    });

    test('unknown args deeply', () {
      expect(
        port.errors('''
      {
        dog {
          doesKnowCommand(unknown: true)
        }
        human {
          pet {
            ... on Dog {
              doesKnowCommand(unknown: true)
            }
          }
        }
      }
    '''),
        [
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 4:27',
          'Unknown argument "unknown" on field "Dog.doesKnowCommand". @ 9:31',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/provided_required_arguments_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ProvidedRequiredArgumentsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const ProvidedRequiredArgumentsRule());

  group('Validate: Provided required arguments', () {
    test('ignores unknown arguments', () {
      expect(
        port.errors('''
      {
        dog {
          isHouseTrained(unknownArgument: true)
        }
      }
    '''),
        isEmpty,
      );
    });

    group('Valid non-nullable value', () {
      test('Arg on optional arg', () {
        expect(
          port.errors('''
        {
          dog {
            isHouseTrained(atOtherHomes: true)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No Arg on optional arg', () {
        expect(
          port.errors('''
        {
          dog {
            isHouseTrained
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No arg on non-null field with default', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            nonNullFieldWithDefault
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple args', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: 1, req2: 2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple args reverse order', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: 2, req1: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No args on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts
          }
        }
      '''),
          isEmpty,
        );
      });

      test('One arg on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts(opt1: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Second arg on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts(opt2: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple required args on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple required and one optional arg on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4, opt1: 5)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('All required and optional args on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4, opt1: 5, opt2: 6)
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid non-nullable value', () {
      test('Missing one non-nullable argument', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: 2)
          }
        }
      '''),
          [
            'Argument "ComplicatedArgs.multipleReqs(req1:)" of type "Int!" is required, but it was not provided. @ 4:13',
          ],
        );
      });

      test('Missing multiple non-nullable arguments', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs
          }
        }
      '''),
          [
            'Argument "ComplicatedArgs.multipleReqs(req1:)" of type "Int!" is required, but it was not provided. @ 4:13',
            'Argument "ComplicatedArgs.multipleReqs(req2:)" of type "Int!" is required, but it was not provided. @ 4:13',
          ],
        );
      });

      test('Incorrect value and missing argument', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: "one")
          }
        }
      '''),
          [
            'Argument "ComplicatedArgs.multipleReqs(req2:)" of type "Int!" is required, but it was not provided. @ 4:13',
          ],
        );
      });
    });

    group('Directive arguments', () {
      test('ignores unknown directives', () {
        expect(
          port.errors('''
        {
          dog @unknown
        }
      '''),
          isEmpty,
        );
      });

      test('with directives of valid types', () {
        expect(
          port.errors('''
        {
          dog @include(if: true) {
            name
          }
          human @skip(if: false) {
            name
          }
        }
      '''),
          isEmpty,
        );
      });

      test('with directive with missing types', () {
        expect(
          port.errors('''
        {
          dog @include {
            name @skip
          }
        }
      '''),
          [
            'Argument "@include(if:)" of type "Boolean!" is required, but it was not provided. @ 3:15',
            'Argument "@skip(if:)" of type "Boolean!" is required, but it was not provided. @ 4:18',
          ],
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/unique_argument_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueArgumentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueArgumentNamesRule());

  group('Validate: Unique argument names', () {
    test('no arguments on field', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('no arguments on directive', () {
      expect(
        port.errors('''
      {
        field @directive
      }
    '''),
        isEmpty,
      );
    });

    test('argument on field', () {
      expect(
        port.errors('''
      {
        field(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('argument on directive', () {
      expect(
        port.errors('''
      {
        field @directive(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('same argument on two fields', () {
      expect(
        port.errors('''
      {
        one: field(arg: "value")
        two: field(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('same argument on field and directive', () {
      expect(
        port.errors('''
      {
        field(arg: "value") @directive(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('same argument on two directives', () {
      expect(
        port.errors('''
      {
        field @directive1(arg: "value") @directive2(arg: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('multiple field arguments', () {
      expect(
        port.errors('''
      {
        field(arg1: "value", arg2: "value", arg3: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('multiple directive arguments', () {
      expect(
        port.errors('''
      {
        field @directive(arg1: "value", arg2: "value", arg3: "value")
      }
    '''),
        isEmpty,
      );
    });

    test('duplicate field arguments', () {
      expect(
        port.errors('''
      {
        field(arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:15 3:30',
        ],
      );
    });

    test('many duplicate field arguments', () {
      expect(
        port.errors('''
      {
        field(arg1: "value", arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:15 3:30 3:45',
        ],
      );
    });

    test('duplicate directive arguments', () {
      expect(
        port.errors('''
      {
        field @directive(arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:26 3:41',
        ],
      );
    });

    test('many duplicate directive arguments', () {
      expect(
        port.errors('''
      {
        field @directive(arg1: "value", arg1: "value", arg1: "value")
      }
    '''),
        [
          'There can be only one argument named "arg1". @ 3:26 3:41 3:56',
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/argument_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/known_argument_names_test.dart test/validation/provided_required_arguments_test.dart test/validation/unique_argument_names_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -353,6 +353,18 @@ enum DiagnosticCode(
   /// one (spec §5.3.3).
   scalarLeafs('GQL207'),
 
+  /// `GQL208`: an argument that the field or directive does not define
+  /// (spec §5.4.1).
+  knownArgumentNames('GQL208'),
+
+  /// `GQL209`: a field or directive that names an argument more than once
+  /// (spec §5.4.2).
+  uniqueArgumentNames('GQL209'),
+
+  /// `GQL210`: a non-null argument without a default value that a field or
+  /// directive does not provide (spec §5.4.3).
+  providedRequiredArguments('GQL210'),
+
   /// `GQL212`: a type name in a type condition or a variable definition
   /// that the schema does not define (spec §5.5.1.2, §5.8.1).
   knownTypeNames('GQL212'),
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,11 +7,14 @@ import 'document_validation_result.dart';
 import 'rules/executable_definitions_rule.dart';
 import 'rules/fields_on_correct_type_rule.dart';
 import 'rules/fragments_on_composite_types_rule.dart';
+import 'rules/known_argument_names_rule.dart';
 import 'rules/known_operation_types_rule.dart';
 import 'rules/known_type_names_rule.dart';
 import 'rules/lone_anonymous_operation_rule.dart';
+import 'rules/provided_required_arguments_rule.dart';
 import 'rules/scalar_leafs_rule.dart';
 import 'rules/single_field_subscriptions_rule.dart';
+import 'rules/unique_argument_names_rule.dart';
 import 'rules/unique_operation_names_rule.dart';
 import 'rules/variables_are_input_types_rule.dart';
 import 'validation_context.dart';
@@ -63,6 +66,9 @@ final class const DocumentValidator({
     VariablesAreInputTypesRule(),
     ScalarLeafsRule(),
     FieldsOnCorrectTypeRule(),
+    KnownArgumentNamesRule(),
+    UniqueArgumentNamesRule(),
+    ProvidedRequiredArgumentsRule(),
   ];
 
   /// Validates [document] against [schema]; diagnostics point into
```

Create `packages/typed_graphql/lib/src/validation/rules/known_argument_names_rule.dart`:

```dart
import '../../diagnostics/suggestions.dart';
import '../../language/ast/argument.dart';
import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.4.1 "Argument Names": every argument names an argument of its
/// field or directive (`GQL208`).
///
/// A directive the schema does not define is left to `KnownDirectives`.
/// Unlike graphql-js, a directive definition inside the document is not
/// read: an executable document that holds one already fails
/// `ExecutableDefinitions`.
///
/// {@category validation}
final class const KnownArgumentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownArgumentNames(context);
}

final class _KnownArgumentNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case Directive():
        _checkDirective(node);
        return .skip;
      case Argument(:final name):
        _checkFieldArgument(node, name.value);
    }
    return .next;
  }

  void _checkFieldArgument(Argument node, String name) {
    final typeInfo = context.typeInfo;
    final field = typeInfo.fieldDefinition;
    final parent = typeInfo.parentType;
    if (typeInfo.argument != null || field == null || parent == null) {
      return;
    }
    final known = [for (final argument in field.arguments) argument.name];
    context.report(
      .knownArgumentNames,
      'Unknown argument "$name" on field "${parent.name}.${field.name}".'
      '${_suggestion(name, known)}',
      [node],
    );
  }

  void _checkDirective(Directive node) {
    final name = node.name.value;
    final definition = context.schema.directiveNamed(name);
    if (definition == null) {
      return;
    }
    final known = [for (final argument in definition.arguments) argument.name];
    for (final argument in node.arguments) {
      final argumentName = argument.name.value;
      if (!known.contains(argumentName)) {
        context.report(
          .knownArgumentNames,
          'Unknown argument "$argumentName" on directive "@$name".'
          '${_suggestion(argumentName, known)}',
          [argument],
        );
      }
    }
  }

  String _suggestion(String name, List<String> known) {
    if (!context.includesSuggestions) {
      return '';
    }
    const suggestions = Suggestions();
    return suggestions.didYouMean(suggestions.listFor(name, known));
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart`:

```dart
import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../schema/model/input_value.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.4.3 "Required Arguments": every non-null argument without a
/// default value is provided (`GQL210`).
///
/// Checked when the field or directive is left, so errors inside it come
/// first, as graphql-js.
///
/// {@category validation}
final class const ProvidedRequiredArgumentsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ProvidedRequiredArguments(context);
}

final class _ProvidedRequiredArguments(final ValidationContext context)
    extends AstVisitor {
  @override
  void leave(Node node) {
    switch (node) {
      case Field():
        _checkField(node);
      case Directive():
        _checkDirective(node);
    }
  }

  void _checkField(Field node) {
    final typeInfo = context.typeInfo;
    final field = typeInfo.fieldDefinition;
    final parent = typeInfo.parentType;
    if (field == null || parent == null) {
      return;
    }
    final provided = {
      for (final argument in node.arguments) argument.name.value,
    };
    for (final argument in field.arguments) {
      if (_isMissing(argument, provided)) {
        _report(
          node,
          '${parent.name}.${field.name}(${argument.name}:)',
          argument,
        );
      }
    }
  }

  void _checkDirective(Directive node) {
    final name = node.name.value;
    final definition = context.schema.directiveNamed(name);
    if (definition == null) {
      return;
    }
    final provided = {
      for (final argument in node.arguments) argument.name.value,
    };
    for (final argument in definition.arguments) {
      if (_isMissing(argument, provided)) {
        _report(node, '@$name(${argument.name}:)', argument);
      }
    }
  }

  bool _isMissing(InputValue argument, Set<String> provided) =>
      !provided.contains(argument.name) &&
      argument.type is NonNullType &&
      argument.defaultValue == null;

  void _report(Node node, String coordinate, InputValue argument) {
    final type = const Printer().print(argument.type);
    context.report(
      .providedRequiredArguments,
      'Argument "$coordinate" of type "$type" is required, but it was '
      'not provided.',
      [node],
    );
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/unique_argument_names_rule.dart`:

```dart
import '../../language/ast/argument.dart';
import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.4.2 "Argument Uniqueness": a field or directive names each
/// argument once (`GQL209`).
///
/// One error per repeated name, pointing at every name written.
///
/// {@category validation}
final class const UniqueArgumentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueArgumentNames(context);
}

final class _UniqueArgumentNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case Field(:final arguments) || Directive(:final arguments):
        _check(arguments);
    }
    return .next;
  }

  void _check(List<Argument> arguments) {
    if (arguments.length < 2) {
      return;
    }
    // A map keeps insertion order, so errors come in order of first use.
    final byName = <String, List<Argument>>{};
    for (final argument in arguments) {
      (byName[argument.name.value] ??= []).add(argument);
    }
    for (final MapEntry(:key, :value) in byName.entries) {
      if (value.length > 1) {
        context.report(
          .uniqueArgumentNames,
          'There can be only one argument named "$key".',
          [for (final argument in value) argument.name],
        );
      }
    }
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -92,11 +92,14 @@ export 'src/validation/document_validator.dart';
 export 'src/validation/rules/executable_definitions_rule.dart';
 export 'src/validation/rules/fields_on_correct_type_rule.dart';
 export 'src/validation/rules/fragments_on_composite_types_rule.dart';
+export 'src/validation/rules/known_argument_names_rule.dart';
 export 'src/validation/rules/known_operation_types_rule.dart';
 export 'src/validation/rules/known_type_names_rule.dart';
 export 'src/validation/rules/lone_anonymous_operation_rule.dart';
+export 'src/validation/rules/provided_required_arguments_rule.dart';
 export 'src/validation/rules/scalar_leafs_rule.dart';
 export 'src/validation/rules/single_field_subscriptions_rule.dart';
+export 'src/validation/rules/unique_argument_names_rule.dart';
 export 'src/validation/rules/unique_operation_names_rule.dart';
 export 'src/validation/rules/variables_are_input_types_rule.dart';
 export 'src/validation/type_info.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -101,3 +101,75 @@ validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct
 validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Sort type suggestions based on inheritance order,ported,test/validation/fields_on_correct_type_test.dart,
 validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Limits lots of type suggestions,ported,test/validation/fields_on_correct_type_test.dart,
 validation/__tests__/FieldsOnCorrectTypeRule-test.ts,Validate: Fields on correct type > Fields on correct type error message,Limits lots of field suggestions,ported,test/validation/fields_on_correct_type_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,single arg is known,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,multiple args are known,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,ignores args of unknown fields,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,multiple args in reverse order are known,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,no args on optional arg,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,args are known deeply,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,directive args are known,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,fragment args are known,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,field args are invalid,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,directive without args is valid,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,arg passed to directive without arg is reported,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,misspelled directive args are reported,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,misspelled directive args are reported (no suggestions),ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,arg passed to fragment without arg is reported,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,misspelled fragment args are reported,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,misspelled fragment args are reported (no suggestions),skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,invalid arg name,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,misspelled arg name is reported,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,misspelled arg name is reported (no suggestions),ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,unknown args amongst known args,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names,unknown args deeply,ported,test/validation/known_argument_names_test.dart,
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,known arg on directive defined inside SDL,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,unknown arg on directive defined inside SDL,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,misspelled arg name is reported on directive defined inside SDL,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,unknown arg on standard directive,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,unknown arg on overridden standard directive,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,unknown arg on directive defined in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownArgumentNamesRule-test.ts,Validate: Known argument names > within SDL,unknown arg on directive used in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,no arguments on field,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,no arguments on directive,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,argument on field,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,argument on directive,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,same argument on two fields,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,same argument on field and directive,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,same argument on two directives,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,multiple field arguments,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,multiple directive arguments,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,duplicate field arguments,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,many duplicate field arguments,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,duplicate directive arguments,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/UniqueArgumentNamesRule-test.ts,Validate: Unique argument names,many duplicate directive arguments,ported,test/validation/unique_argument_names_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments,ignores unknown arguments,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,Arg on optional arg,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,No Arg on optional arg,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,No arg on non-null field with default,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,Multiple args,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,Multiple args reverse order,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,No args on multiple optional,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,One arg on multiple optional,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,Second arg on multiple optional,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,Multiple required args on mixedList,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,Multiple required and one optional arg on mixedList,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Valid non-nullable value,All required and optional args on mixedList,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Invalid non-nullable value,Missing one non-nullable argument,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Invalid non-nullable value,Missing multiple non-nullable arguments,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Invalid non-nullable value,Incorrect value and missing argument,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Directive arguments,ignores unknown directives,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Directive arguments,with directives of valid types,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Directive arguments,with directive with missing types,ported,test/validation/provided_required_arguments_test.dart,
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > within SDL,Missing optional args on directive defined inside SDL,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > within SDL,Missing arg on directive defined inside SDL,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > within SDL,Missing arg on standard directive,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > within SDL,Missing arg on overridden standard directive,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > within SDL,Missing arg on directive defined in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > within SDL,Missing arg on directive used in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,ignores unknown arguments,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Missing nullable argument with default is allowed,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Missing nullable argument is allowed,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Missing non-nullable argument with default is allowed,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Missing non-nullable argument is not allowed,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Supplies required variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Skips missing fragments,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/argument_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/known_argument_names_test.dart test/validation/provided_required_arguments_test.dart test/validation/unique_argument_names_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The argument rules: `KnownArgumentNamesRule`, `UniqueArgumentNamesRule` and
  `ProvidedRequiredArgumentsRule` (`GQL208`-`GQL210`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/rules/known_argument_names_rule.dart packages/typed_graphql/lib/src/validation/rules/provided_required_arguments_rule.dart packages/typed_graphql/lib/src/validation/rules/unique_argument_names_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/argument_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/known_argument_names_test.dart packages/typed_graphql_conformance/test/validation/provided_required_arguments_test.dart packages/typed_graphql_conformance/test/validation/unique_argument_names_test.dart
git commit -q -m "feat(typed_graphql): add the argument rules of operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: The fragment rules

`UniqueFragmentNamesRule`, `NoUnusedFragmentsRule`, `KnownFragmentNamesRule`, `NoFragmentCyclesRule` (an explicit stack) and `PossibleFragmentSpreadsRule` (`GQL211`, `GQL214`–`GQL217`), the shared `FragmentSpreadCollector`, and their ported suites.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/fragment_spread_collector.dart`, `packages/typed_graphql/lib/src/validation/rules/known_fragment_names_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/no_fragment_cycles_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/no_unused_fragments_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/possible_fragment_spreads_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/unique_fragment_names_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/fragment_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/known_fragment_names_test.dart`, `packages/typed_graphql_conformance/test/validation/no_fragment_cycles_test.dart`, `packages/typed_graphql_conformance/test/validation/no_unused_fragments_test.dart`, `packages/typed_graphql_conformance/test/validation/possible_fragment_spreads_test.dart`, `packages/typed_graphql_conformance/test/validation/unique_fragment_names_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
- Diagnostic codes: `GQL211`, `GQL214`, `GQL215`, `GQL216`, `GQL217`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/fragment_spread_collector.dart
final class const FragmentSpreadCollector()
  List<FragmentSpread> collect(SelectionSet root)

// validation/rules/known_fragment_names_rule.dart
final class const KnownFragmentNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _KnownFragmentNames(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/no_fragment_cycles_rule.dart
final class const NoFragmentCyclesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _Frame(final String name, final List<FragmentSpread> spreads)
final class _NoFragmentCycles(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/no_unused_fragments_rule.dart
final class const NoUnusedFragmentsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _NoUnusedFragments(final ValidationContext context)
  VisitAction enter(Node node)
  void leave(Node node)

// validation/rules/possible_fragment_spreads_rule.dart
final class const PossibleFragmentSpreadsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _PossibleFragmentSpreads(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/unique_fragment_names_rule.dart
final class const UniqueFragmentNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UniqueFragmentNames(final ValidationContext context)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/fragment_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes and the branches
// those suites do not reach.
void main() {
  final checked = Checked('''
type Query { name: String dog: Dog pet: Pet }
interface Pet { name: String }
type Dog implements Pet { name: String }
type Cat implements Pet { name: String }
''');

  test('a repeated fragment name is GQL211', () {
    expect(
      checked.errors(
        'fragment A on Query { name } fragment A on Query { name }',
        [
          const UniqueFragmentNamesRule(),
        ],
      ),
      ['1:10 GQL211 There can be only one fragment named "A".'],
    );
  });

  test('an unknown fragment is GQL215', () {
    expect(
      checked.errors('{ ...Missing }', [const KnownFragmentNamesRule()]),
      ['1:6 GQL215 Unknown fragment "Missing".'],
    );
  });

  test('a fragment only a fragment spreads is used', () {
    expect(
      checked.errors(
        'query { ...A } fragment A on Query { ...B } '
        'fragment B on Query { name } fragment C on Query { name }',
        [const NoUnusedFragmentsRule()],
      ),
      ['1:74 GQL214 Fragment "C" is never used.'],
    );
  });

  test('a fragment that spreads itself is GQL216', () {
    expect(
      checked.errors('fragment A on Query { ...A } { ...A }', [
        const NoFragmentCyclesRule(),
      ]),
      ['1:23 GQL216 Cannot spread fragment "A" within itself.'],
    );
  });

  test('a fragment spread on an unrelated type is GQL217', () {
    expect(
      checked.errors('{ dog { ...OnCat } } fragment OnCat on Cat { name }', [
        const PossibleFragmentSpreadsRule(),
      ]),
      [
        '1:9 GQL217 Fragment "OnCat" cannot be spread here as objects of '
            'type "Dog" can never be of type "Cat".',
      ],
    );
  });

  test('an inline fragment on an unrelated type is GQL217', () {
    expect(
      checked.errors('{ dog { ... on Cat { name } } }', [
        const PossibleFragmentSpreadsRule(),
      ]),
      [
        '1:9 GQL217 Fragment cannot be spread here as objects of type "Dog" '
            'can never be of type "Cat".',
      ],
    );
  });

  test('an inline fragment without a type condition is possible', () {
    expect(
      checked.errors('{ dog { ... @include(if: true) { name } } }', [
        const PossibleFragmentSpreadsRule(),
      ]),
      isEmpty,
    );
  });

  group('a fragment chain of 100000', () {
    const length = 100000;

    // Built in code: the parser limits the size of a document.
    Document chain({required bool isCycle}) => Document([
      for (var i = 0; i < length; i++)
        FragmentDefinition(
          Name('F$i'),
          const NamedType(Name('Query')),
          SelectionSet([
            if (i + 1 < length)
              FragmentSpread(Name('F${i + 1}'))
            else if (isCycle)
              FragmentSpread(const Name('F0')),
          ]),
        ),
    ]);

    List<Diagnostic> cycleErrors(Document document) =>
        const DocumentValidator(rules: [NoFragmentCyclesRule()])
            .validate(checked.schema, document)
            .diagnostics;

    test('that closes on itself is one cycle, without recursion', () {
      final diagnostics = cycleErrors(chain(isCycle: true));
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.code, DiagnosticCode.noFragmentCycles);
      expect(
        diagnostics.single.message,
        startsWith('Cannot spread fragment "F0" within itself via "F1", '),
      );
    });

    test('that ends is valid, without recursion', () {
      expect(cycleErrors(chain(isCycle: false)), isEmpty);
    });
  });

  test('following spreads is charged to the step budget', () {
    final result = checked.validate(
      'fragment A on Query { ...B } fragment B on Query { ...A }',
      validator: const DocumentValidator(
        rules: [NoFragmentCyclesRule()],
        maxSteps: 1,
      ),
    );
    expect(result.diagnostics.map((diagnostic) => diagnostic.code), [
      DiagnosticCode.documentTooComplex,
    ]);
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -88,13 +88,18 @@ void main() {
         'validation/__tests__/FieldsOnCorrectTypeRule-test.ts',
         'validation/__tests__/FragmentsOnCompositeTypesRule-test.ts',
         'validation/__tests__/KnownArgumentNamesRule-test.ts',
+        'validation/__tests__/KnownFragmentNamesRule-test.ts',
         'validation/__tests__/KnownOperationTypesRules-test.ts',
         'validation/__tests__/KnownTypeNamesRule-test.ts',
         'validation/__tests__/LoneAnonymousOperationRule-test.ts',
+        'validation/__tests__/NoFragmentCyclesRule-test.ts',
+        'validation/__tests__/NoUnusedFragmentsRule-test.ts',
+        'validation/__tests__/PossibleFragmentSpreadsRule-test.ts',
         'validation/__tests__/ProvidedRequiredArgumentsRule-test.ts',
         'validation/__tests__/ScalarLeafsRule-test.ts',
         'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
         'validation/__tests__/UniqueArgumentNamesRule-test.ts',
+        'validation/__tests__/UniqueFragmentNamesRule-test.ts',
         'validation/__tests__/UniqueOperationNamesRule-test.ts',
         'validation/__tests__/VariablesAreInputTypesRule-test.ts',
       ],
```

Create `packages/typed_graphql_conformance/test/validation/known_fragment_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownFragmentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const KnownFragmentNamesRule());

  group('Validate: Known fragment names', () {
    test('known fragment names are valid', () {
      expect(
        port.errors('''
      {
        human(id: 4) {
          ...HumanFields1
          ... on Human {
            ...HumanFields2
          }
          ... {
            name
          }
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('unknown fragment names are invalid', () {
      expect(
        port.errors('''
      {
        human(id: 4) {
          ...UnknownFragment1
          ... on Human {
            ...UnknownFragment2
          }
        }
      }
      fragment HumanFields on Human {
        name
        ...UnknownFragment3
      }
    '''),
        [
          'Unknown fragment "UnknownFragment1". @ 4:14',
          'Unknown fragment "UnknownFragment2". @ 6:16',
          'Unknown fragment "UnknownFragment3". @ 12:12',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/no_fragment_cycles_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoFragmentCyclesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoFragmentCyclesRule());

  group('Validate: No circular fragment spreads', () {
    test('single reference is valid', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { name }
    '''),
        isEmpty,
      );
    });

    test('spreading twice is not circular', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB, ...fragB }
      fragment fragB on Dog { name }
    '''),
        isEmpty,
      );
    });

    test('spreading twice indirectly is not circular', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB, ...fragC }
      fragment fragB on Dog { ...fragC }
      fragment fragC on Dog { name }
    '''),
        isEmpty,
      );
    });

    test('double spread within abstract types', () {
      expect(
        port.errors('''
      fragment nameFragment on Pet {
        ... on Dog { name }
        ... on Cat { name }
      }

      fragment spreadsInAnon on Pet {
        ... on Dog { ...nameFragment }
        ... on Cat { ...nameFragment }
      }
    '''),
        isEmpty,
      );
    });

    test('does not false positive on unknown fragment', () {
      expect(
        port.errors('''
      fragment nameFragment on Pet {
        ...UnknownFragment
      }
    '''),
        isEmpty,
      );
    });

    test('spreading recursively within field fails', () {
      expect(
        port.errors('''
      fragment fragA on Human { relatives { ...fragA } },
    '''),
        [
          'Cannot spread fragment "fragA" within itself. @ 2:45',
        ],
      );
    });

    test('no spreading itself directly', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragA }
    '''),
        [
          'Cannot spread fragment "fragA" within itself. @ 2:31',
        ],
      );
    });

    test('no spreading itself directly within inline fragment', () {
      expect(
        port.errors('''
      fragment fragA on Pet {
        ... on Dog {
          ...fragA
        }
      }
    '''),
        [
          'Cannot spread fragment "fragA" within itself. @ 4:11',
        ],
      );
    });

    test('no spreading itself indirectly', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { ...fragA }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB". @ 2:31 3:31',
        ],
      );
    });

    test('no spreading itself indirectly reports opposite order', () {
      expect(
        port.errors('''
      fragment fragB on Dog { ...fragA }
      fragment fragA on Dog { ...fragB }
    '''),
        [
          'Cannot spread fragment "fragB" within itself via "fragA". @ 2:31 3:31',
        ],
      );
    });

    test('no spreading itself indirectly within inline fragment', () {
      expect(
        port.errors('''
      fragment fragA on Pet {
        ... on Dog {
          ...fragB
        }
      }
      fragment fragB on Pet {
        ... on Dog {
          ...fragA
        }
      }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB". @ 4:11 9:11',
        ],
      );
    });

    test('no spreading itself deeply', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { ...fragC }
      fragment fragC on Dog { ...fragO }
      fragment fragX on Dog { ...fragY }
      fragment fragY on Dog { ...fragZ }
      fragment fragZ on Dog { ...fragO }
      fragment fragO on Dog { ...fragP }
      fragment fragP on Dog { ...fragA, ...fragX }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB", "fragC", "fragO", "fragP". @ 2:31 3:31 4:31 8:31 9:31',
          'Cannot spread fragment "fragO" within itself via "fragP", "fragX", "fragY", "fragZ". @ 8:31 9:41 5:31 6:31 7:31',
        ],
      );
    });

    test('no spreading itself deeply two paths', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB, ...fragC }
      fragment fragB on Dog { ...fragA }
      fragment fragC on Dog { ...fragA }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragB". @ 2:31 3:31',
          'Cannot spread fragment "fragA" within itself via "fragC". @ 2:41 4:31',
        ],
      );
    });

    test('no spreading itself deeply two paths -- alt traverse order', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragC }
      fragment fragB on Dog { ...fragC }
      fragment fragC on Dog { ...fragA, ...fragB }
    '''),
        [
          'Cannot spread fragment "fragA" within itself via "fragC". @ 2:31 4:31',
          'Cannot spread fragment "fragC" within itself via "fragB". @ 4:41 3:31',
        ],
      );
    });

    test('no spreading itself deeply and immediately', () {
      expect(
        port.errors('''
      fragment fragA on Dog { ...fragB }
      fragment fragB on Dog { ...fragB, ...fragC }
      fragment fragC on Dog { ...fragA, ...fragB }
    '''),
        [
          'Cannot spread fragment "fragB" within itself. @ 3:31',
          'Cannot spread fragment "fragA" within itself via "fragB", "fragC". @ 2:31 3:41 4:31',
          'Cannot spread fragment "fragB" within itself via "fragC". @ 3:41 4:41',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/no_unused_fragments_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoUnusedFragmentsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoUnusedFragmentsRule());

  group('Validate: No unused fragments', () {
    test('all fragment names are used', () {
      expect(
        port.errors('''
      {
        human(id: 4) {
          ...HumanFields1
          ... on Human {
            ...HumanFields2
          }
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('all fragment names are used by multiple operations', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...HumanFields1
        }
      }
      query Bar {
        human(id: 4) {
          ...HumanFields2
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('contains unknown fragments', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...HumanFields1
        }
      }
      query Bar {
        human(id: 4) {
          ...HumanFields2
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
      fragment Unused1 on Human {
        name
      }
      fragment Unused2 on Human {
        name
      }
    '''),
        [
          'Fragment "Unused1" is never used. @ 22:7',
          'Fragment "Unused2" is never used. @ 25:7',
        ],
      );
    });

    test('contains unknown fragments with ref cycle', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...HumanFields1
        }
      }
      query Bar {
        human(id: 4) {
          ...HumanFields2
        }
      }
      fragment HumanFields1 on Human {
        name
        ...HumanFields3
      }
      fragment HumanFields2 on Human {
        name
      }
      fragment HumanFields3 on Human {
        name
      }
      fragment Unused1 on Human {
        name
        ...Unused2
      }
      fragment Unused2 on Human {
        name
        ...Unused1
      }
    '''),
        [
          'Fragment "Unused1" is never used. @ 22:7',
          'Fragment "Unused2" is never used. @ 26:7',
        ],
      );
    });

    test('contains unknown and undef fragments', () {
      expect(
        port.errors('''
      query Foo {
        human(id: 4) {
          ...bar
        }
      }
      fragment foo on Human {
        name
      }
    '''),
        [
          'Fragment "foo" is never used. @ 7:7',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/possible_fragment_spreads_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/PossibleFragmentSpreadsRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const PossibleFragmentSpreadsRule()).withSchema('''
  interface Being {
    name: String
  }

  interface Pet implements Being {
    name: String
  }

  type Dog implements Being & Pet {
    name: String
    barkVolume: Int
  }

  type Cat implements Being & Pet {
    name: String
    meowVolume: Int
  }

  union CatOrDog = Cat | Dog

  interface Intelligent {
    iq: Int
  }

  type Human implements Being & Intelligent {
    name: String
    pets: [Pet]
    iq: Int
  }

  type Alien implements Being & Intelligent {
    name: String
    iq: Int
  }

  union DogOrHuman = Dog | Human

  union HumanOrAlien = Human | Alien

  type Query {
    catOrDog: CatOrDog
    dogOrHuman: DogOrHuman
    humanOrAlien: HumanOrAlien
  }
''');

  group('Validate: Possible fragment spreads', () {
    test('of the same object', () {
      expect(
        port.errors('''
      fragment objectWithinObject on Dog { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        isEmpty,
      );
    });

    test('of the same object with inline fragment', () {
      expect(
        port.errors('''
      fragment objectWithinObjectAnon on Dog { ... on Dog { barkVolume } }
    '''),
        isEmpty,
      );
    });

    test('object into an implemented interface', () {
      expect(
        port.errors('''
      fragment objectWithinInterface on Pet { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        isEmpty,
      );
    });

    test('object into containing union', () {
      expect(
        port.errors('''
      fragment objectWithinUnion on CatOrDog { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        isEmpty,
      );
    });

    test('union into contained object', () {
      expect(
        port.errors('''
      fragment unionWithinObject on Dog { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        isEmpty,
      );
    });

    test('union into overlapping interface', () {
      expect(
        port.errors('''
      fragment unionWithinInterface on Pet { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        isEmpty,
      );
    });

    test('union into overlapping union', () {
      expect(
        port.errors('''
      fragment unionWithinUnion on DogOrHuman { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        isEmpty,
      );
    });

    test('interface into implemented object', () {
      expect(
        port.errors('''
      fragment interfaceWithinObject on Dog { ...petFragment }
      fragment petFragment on Pet { name }
    '''),
        isEmpty,
      );
    });

    test('interface into overlapping interface', () {
      expect(
        port.errors('''
      fragment interfaceWithinInterface on Pet { ...beingFragment }
      fragment beingFragment on Being { name }
    '''),
        isEmpty,
      );
    });

    test('interface into overlapping interface in inline fragment', () {
      expect(
        port.errors('''
      fragment interfaceWithinInterface on Pet { ... on Being { name } }
    '''),
        isEmpty,
      );
    });

    test('interface into overlapping union', () {
      expect(
        port.errors('''
      fragment interfaceWithinUnion on CatOrDog { ...petFragment }
      fragment petFragment on Pet { name }
    '''),
        isEmpty,
      );
    });

    test(
      'ignores incorrect type (caught by FragmentsOnCompositeTypesRule)',
      () {
        expect(
          port.errors('''
      fragment petFragment on Pet { ...badInADifferentWay }
      fragment badInADifferentWay on String { name }
    '''),
          isEmpty,
        );
      },
    );

    test('ignores unknown fragments (caught by KnownFragmentNamesRule)', () {
      expect(
        port.errors('''
      fragment petFragment on Pet { ...UnknownFragment }
    '''),
        isEmpty,
      );
    });

    test('different object into object', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinObject on Cat { ...dogFragment }
      fragment dogFragment on Dog { barkVolume }
    '''),
        [
          'Fragment "dogFragment" cannot be spread here as objects of type "Cat" can never be of type "Dog". @ 2:51',
        ],
      );
    });

    test('different object into object in inline fragment', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinObjectAnon on Cat {
        ... on Dog { barkVolume }
      }
    '''),
        [
          'Fragment cannot be spread here as objects of type "Cat" can never be of type "Dog". @ 3:9',
        ],
      );
    });

    test('object into not implementing interface', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinInterface on Pet { ...humanFragment }
      fragment humanFragment on Human { pets { name } }
    '''),
        [
          'Fragment "humanFragment" cannot be spread here as objects of type "Pet" can never be of type "Human". @ 2:54',
        ],
      );
    });

    test('object into not containing union', () {
      expect(
        port.errors('''
      fragment invalidObjectWithinUnion on CatOrDog { ...humanFragment }
      fragment humanFragment on Human { pets { name } }
    '''),
        [
          'Fragment "humanFragment" cannot be spread here as objects of type "CatOrDog" can never be of type "Human". @ 2:55',
        ],
      );
    });

    test('union into not contained object', () {
      expect(
        port.errors('''
      fragment invalidUnionWithinObject on Human { ...catOrDogFragment }
      fragment catOrDogFragment on CatOrDog { __typename }
    '''),
        [
          'Fragment "catOrDogFragment" cannot be spread here as objects of type "Human" can never be of type "CatOrDog". @ 2:52',
        ],
      );
    });

    test('union into non overlapping interface', () {
      expect(
        port.errors('''
      fragment invalidUnionWithinInterface on Pet { ...humanOrAlienFragment }
      fragment humanOrAlienFragment on HumanOrAlien { __typename }
    '''),
        [
          'Fragment "humanOrAlienFragment" cannot be spread here as objects of type "Pet" can never be of type "HumanOrAlien". @ 2:53',
        ],
      );
    });

    test('union into non overlapping union', () {
      expect(
        port.errors('''
      fragment invalidUnionWithinUnion on CatOrDog { ...humanOrAlienFragment }
      fragment humanOrAlienFragment on HumanOrAlien { __typename }
    '''),
        [
          'Fragment "humanOrAlienFragment" cannot be spread here as objects of type "CatOrDog" can never be of type "HumanOrAlien". @ 2:54',
        ],
      );
    });

    test('interface into non implementing object', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinObject on Cat { ...intelligentFragment }
      fragment intelligentFragment on Intelligent { iq }
    '''),
        [
          'Fragment "intelligentFragment" cannot be spread here as objects of type "Cat" can never be of type "Intelligent". @ 2:54',
        ],
      );
    });

    test('interface into non overlapping interface', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinInterface on Pet {
        ...intelligentFragment
      }
      fragment intelligentFragment on Intelligent { iq }
    '''),
        [
          'Fragment "intelligentFragment" cannot be spread here as objects of type "Pet" can never be of type "Intelligent". @ 3:9',
        ],
      );
    });

    test('interface into non overlapping interface in inline fragment', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinInterfaceAnon on Pet {
        ...on Intelligent { iq }
      }
    '''),
        [
          'Fragment cannot be spread here as objects of type "Pet" can never be of type "Intelligent". @ 3:9',
        ],
      );
    });

    test('interface into non overlapping union', () {
      expect(
        port.errors('''
      fragment invalidInterfaceWithinUnion on HumanOrAlien { ...petFragment }
      fragment petFragment on Pet { name }
    '''),
        [
          'Fragment "petFragment" cannot be spread here as objects of type "HumanOrAlien" can never be of type "Pet". @ 2:62',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/unique_fragment_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueFragmentNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueFragmentNamesRule());

  group('Validate: Unique fragment names', () {
    test('no fragments', () {
      expect(
        port.errors('''
      {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('one fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
      }

      fragment fragA on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('many fragments', () {
      expect(
        port.errors('''
      {
        ...fragA
        ...fragB
        ...fragC
      }
      fragment fragA on Type {
        fieldA
      }
      fragment fragB on Type {
        fieldB
      }
      fragment fragC on Type {
        fieldC
      }
    '''),
        isEmpty,
      );
    });

    test('inline fragments are always unique', () {
      expect(
        port.errors('''
      {
        ...on Type {
          fieldA
        }
        ...on Type {
          fieldB
        }
      }
    '''),
        isEmpty,
      );
    });

    test('fragment and operation named the same', () {
      expect(
        port.errors('''
      query Foo {
        ...Foo
      }
      fragment Foo on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('fragments named the same', () {
      expect(
        port.errors('''
      {
        ...fragA
      }
      fragment fragA on Type {
        fieldA
      }
      fragment fragA on Type {
        fieldB
      }
    '''),
        [
          'There can be only one fragment named "fragA". @ 5:16 8:16',
        ],
      );
    });

    test('fragments named the same without being referenced', () {
      expect(
        port.errors('''
      fragment fragA on Type {
        fieldA
      }
      fragment fragA on Type {
        fieldB
      }
    '''),
        [
          'There can be only one fragment named "fragA". @ 2:16 5:16',
        ],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/fragment_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/known_fragment_names_test.dart test/validation/no_fragment_cycles_test.dart test/validation/no_unused_fragments_test.dart test/validation/possible_fragment_spreads_test.dart test/validation/unique_fragment_names_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -365,6 +365,10 @@ enum DiagnosticCode(
   /// directive does not provide (spec §5.4.3).
   providedRequiredArguments('GQL210'),
 
+  /// `GQL211`: two fragment definitions with the same name (spec
+  /// §5.5.1.1).
+  uniqueFragmentNames('GQL211'),
+
   /// `GQL212`: a type name in a type condition or a variable definition
   /// that the schema does not define (spec §5.5.1.2, §5.8.1).
   knownTypeNames('GQL212'),
@@ -373,6 +377,22 @@ enum DiagnosticCode(
   /// an object, interface or union type (spec §5.5.1.3).
   fragmentsOnCompositeTypes('GQL213'),
 
+  /// `GQL214`: a fragment definition that no operation spreads, directly or
+  /// through other fragments (spec §5.5.1.4).
+  noUnusedFragments('GQL214'),
+
+  /// `GQL215`: a fragment spread whose fragment the document does not
+  /// define (spec §5.5.2.1).
+  knownFragmentNames('GQL215'),
+
+  /// `GQL216`: a fragment that spreads itself, directly or through other
+  /// fragments (spec §5.5.2.2).
+  noFragmentCycles('GQL216'),
+
+  /// `GQL217`: a fragment spread or inline fragment whose type condition
+  /// can never apply to the parent type (spec §5.5.2.3).
+  possibleFragmentSpreads('GQL217'),
+
   /// `GQL226`: a variable whose type is not an input type (spec §5.8.2).
   variablesAreInputTypes('GQL226'),
 
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,13 +8,18 @@ import 'rules/executable_definitions_rule.dart';
 import 'rules/fields_on_correct_type_rule.dart';
 import 'rules/fragments_on_composite_types_rule.dart';
 import 'rules/known_argument_names_rule.dart';
+import 'rules/known_fragment_names_rule.dart';
 import 'rules/known_operation_types_rule.dart';
 import 'rules/known_type_names_rule.dart';
 import 'rules/lone_anonymous_operation_rule.dart';
+import 'rules/no_fragment_cycles_rule.dart';
+import 'rules/no_unused_fragments_rule.dart';
+import 'rules/possible_fragment_spreads_rule.dart';
 import 'rules/provided_required_arguments_rule.dart';
 import 'rules/scalar_leafs_rule.dart';
 import 'rules/single_field_subscriptions_rule.dart';
 import 'rules/unique_argument_names_rule.dart';
+import 'rules/unique_fragment_names_rule.dart';
 import 'rules/unique_operation_names_rule.dart';
 import 'rules/variables_are_input_types_rule.dart';
 import 'validation_context.dart';
@@ -66,6 +71,11 @@ final class const DocumentValidator({
     VariablesAreInputTypesRule(),
     ScalarLeafsRule(),
     FieldsOnCorrectTypeRule(),
+    UniqueFragmentNamesRule(),
+    KnownFragmentNamesRule(),
+    NoUnusedFragmentsRule(),
+    PossibleFragmentSpreadsRule(),
+    NoFragmentCyclesRule(),
     KnownArgumentNamesRule(),
     UniqueArgumentNamesRule(),
     ProvidedRequiredArgumentsRule(),
```

Create `packages/typed_graphql/lib/src/validation/fragment_spread_collector.dart`:

```dart
import '../language/ast/selection.dart';
import '../language/ast/selection_set.dart';

/// Finds the fragment spreads in a selection set, as graphql-js's
/// `getFragmentSpreads`: nested selections included, other fragments'
/// bodies not, in graphql-js's order (the message of a cycle depends on
/// it).
final class const FragmentSpreadCollector() {
  /// Creates the collector.
  this;

  /// The spreads inside [root], found with an explicit stack.
  List<FragmentSpread> collect(SelectionSet root) {
    final spreads = <FragmentSpread>[];
    final pending = [root];
    while (pending.isNotEmpty) {
      for (final selection in pending.removeLast().selections) {
        switch (selection) {
          case final FragmentSpread spread:
            spreads.add(spread);
          case Field(:final selectionSet?):
            pending.add(selectionSet);
          case InlineFragment(:final selectionSet):
            pending.add(selectionSet);
          case Field():
            break;
        }
      }
    }
    return spreads;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/known_fragment_names_rule.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.2.1 "Fragment spread target defined": a fragment spread names
/// a fragment the document defines (`GQL215`).
///
/// {@category validation}
final class const KnownFragmentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownFragmentNames(context);
}

final class _KnownFragmentNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case FragmentSpread(:final name)
        when context.fragmentNamed(name.value) == null) {
      context.report(
        .knownFragmentNames,
        'Unknown fragment "${name.value}".',
        [name],
      );
    }
    return .next;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/no_fragment_cycles_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../fragment_spread_collector.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.2.2 "Fragment spreads must not form cycles": a fragment does
/// not spread itself, directly or through other fragments (`GQL216`).
///
/// A depth-first search as graphql-js's, but with an explicit stack: a
/// chain of a hundred thousand fragments must not overflow the call stack,
/// on the web least of all. Each spread followed is charged to the step
/// budget.
///
/// {@category validation}
final class const NoFragmentCyclesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoFragmentCycles(context);
}

/// A fragment on the search stack and how many of its spreads were taken.
final class _Frame(final String name, final List<FragmentSpread> spreads) {
  int nextIndex = 0;
}

final class _NoFragmentCycles(final ValidationContext context)
    extends AstVisitor {
  // Fragments already searched: keeps the work linear and reports a cycle
  // once.
  final Set<String> _visited = {};
  // The spreads from the search root to the current fragment.
  final List<FragmentSpread> _spreadPath = [];
  // Where each fragment on the stack starts in _spreadPath.
  final Map<String, int> _pathIndexByName = {};

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition():
        return .skip;
      case final FragmentDefinition fragment:
        _search(fragment);
        return .skip;
      default:
        return .next;
    }
  }

  void _search(FragmentDefinition root) {
    final frames = <_Frame>[];
    _open(root, frames);
    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.nextIndex == frame.spreads.length) {
        _pathIndexByName.remove(frame.name);
        frames.removeLast();
        if (frames.isNotEmpty) {
          _spreadPath.removeLast();
        }
        continue;
      }
      if (!_follow(frame.spreads[frame.nextIndex++], frames)) {
        frames.clear();
        _spreadPath.clear();
        _pathIndexByName.clear();
      }
    }
  }

  // Takes one spread; false once the step budget is spent.
  bool _follow(FragmentSpread spread, List<_Frame> frames) {
    if (!context.spend(1)) {
      return false;
    }
    final spreadName = spread.name.value;
    _spreadPath.add(spread);
    if (_pathIndexByName[spreadName] case final cycleStart?) {
      _reportCycle(spreadName, _spreadPath.sublist(cycleStart));
    } else if (context.fragmentNamed(spreadName) case final target?) {
      // The path stays while the target's frame is open.
      if (_open(target, frames)) {
        return true;
      }
    }
    _spreadPath.removeLast();
    return true;
  }

  // Opens a frame for [fragment]; false when it was searched already or
  // spreads nothing.
  bool _open(FragmentDefinition fragment, List<_Frame> frames) {
    final name = fragment.name.value;
    if (!_visited.add(name)) {
      return false;
    }
    final spreads = const FragmentSpreadCollector().collect(
      fragment.selectionSet,
    );
    if (spreads.isEmpty) {
      return false;
    }
    _pathIndexByName[name] = _spreadPath.length;
    frames.add(_Frame(name, spreads));
    return true;
  }

  void _reportCycle(String spreadName, List<FragmentSpread> cyclePath) {
    final via = [
      for (final spread in cyclePath.take(cyclePath.length - 1))
        '"${spread.name.value}"',
    ].join(', ');
    context.report(
      .noFragmentCycles,
      'Cannot spread fragment "$spreadName" within itself'
      '${via.isEmpty ? '.' : ' via $via.'}',
      cyclePath,
    );
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/no_unused_fragments_rule.dart`:

```dart
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.4 "Fragments Must Be Used": every fragment is spread by an
/// operation, directly or through other fragments (`GQL214`).
///
/// Reported when the walk leaves the document, in definition order.
///
/// {@category validation}
final class const NoUnusedFragmentsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoUnusedFragments(context);
}

final class _NoUnusedFragments(final ValidationContext context)
    extends AstVisitor {
  final List<OperationDefinition> _operations = [];
  final List<FragmentDefinition> _fragments = [];

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case final OperationDefinition operation:
        _operations.add(operation);
        return .skip;
      case final FragmentDefinition fragment:
        _fragments.add(fragment);
        return .skip;
      default:
        return .next;
    }
  }

  @override
  void leave(Node node) {
    if (node is! Document) {
      return;
    }
    final usedNames = {
      for (final operation in _operations)
        for (final fragment in context.recursivelyReferencedFragments(
          operation,
        ))
          fragment.name.value,
    };
    for (final fragment in _fragments) {
      if (!usedNames.contains(fragment.name.value)) {
        context.report(
          .noUnusedFragments,
          'Fragment "${fragment.name.value}" is never used.',
          [fragment],
        );
      }
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/possible_fragment_spreads_rule.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.2.3 "Fragment spread is possible": the type condition of a
/// fragment spread or inline fragment overlaps the parent type (`GQL217`).
///
/// {@category validation}
final class const PossibleFragmentSpreadsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _PossibleFragmentSpreads(context);
}

final class _PossibleFragmentSpreads(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case InlineFragment():
        _checkInline(node);
      case FragmentSpread(:final name):
        _checkSpread(node, name.value);
      default:
    }
    return .next;
  }

  void _checkInline(InlineFragment node) {
    final fragmentType = switch (context.typeInfo.type) {
      final type? => context.schema.namedTypeOf(type),
      null => null,
    };
    final parentType = context.typeInfo.parentType;
    if (_cannotOverlap(fragmentType, parentType)) {
      context.report(
        .possibleFragmentSpreads,
        'Fragment cannot be spread here as objects of type '
        '"${parentType?.name}" can never be of type "${fragmentType?.name}".',
        [node],
      );
    }
  }

  void _checkSpread(FragmentSpread node, String fragmentName) {
    final fragmentType = switch (context.fragmentNamed(fragmentName)) {
      final fragment? => context.schema.namedTypeOf(fragment.typeCondition),
      null => null,
    };
    final parentType = context.typeInfo.parentType;
    if (_cannotOverlap(fragmentType, parentType)) {
      context.report(
        .possibleFragmentSpreads,
        'Fragment "$fragmentName" cannot be spread here as objects of type '
        '"${parentType?.name}" can never be of type "${fragmentType?.name}".',
        [node],
      );
    }
  }

  // Both must be composite; an unknown or non-composite type is left to
  // the other rules.
  bool _cannotOverlap(SchemaType? fragmentType, SchemaType? parentType) =>
      fragmentType != null &&
      parentType != null &&
      fragmentType.isCompositeType &&
      parentType.isCompositeType &&
      !context.schema.typesOverlap(fragmentType, parentType);
}
```

Create `packages/typed_graphql/lib/src/validation/rules/unique_fragment_names_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.1 "Fragment Name Uniqueness": a document defines each
/// fragment name once (`GQL211`).
///
/// The error points at the first name and relates to the repeat.
///
/// {@category validation}
final class const UniqueFragmentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueFragmentNames(context);
}

final class _UniqueFragmentNames(final ValidationContext context)
    extends AstVisitor {
  final Map<String, Name> _knownNames = {};

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition():
        return .skip;
      case FragmentDefinition(:final name):
        if (_knownNames[name.value] case final known?) {
          context.report(
            .uniqueFragmentNames,
            'There can be only one fragment named "${name.value}".',
            [known, name],
          );
        } else {
          _knownNames[name.value] = name;
        }
        return .skip;
      default:
        return .next;
    }
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -93,13 +93,18 @@ export 'src/validation/rules/executable_definitions_rule.dart';
 export 'src/validation/rules/fields_on_correct_type_rule.dart';
 export 'src/validation/rules/fragments_on_composite_types_rule.dart';
 export 'src/validation/rules/known_argument_names_rule.dart';
+export 'src/validation/rules/known_fragment_names_rule.dart';
 export 'src/validation/rules/known_operation_types_rule.dart';
 export 'src/validation/rules/known_type_names_rule.dart';
 export 'src/validation/rules/lone_anonymous_operation_rule.dart';
+export 'src/validation/rules/no_fragment_cycles_rule.dart';
+export 'src/validation/rules/no_unused_fragments_rule.dart';
+export 'src/validation/rules/possible_fragment_spreads_rule.dart';
 export 'src/validation/rules/provided_required_arguments_rule.dart';
 export 'src/validation/rules/scalar_leafs_rule.dart';
 export 'src/validation/rules/single_field_subscriptions_rule.dart';
 export 'src/validation/rules/unique_argument_names_rule.dart';
+export 'src/validation/rules/unique_fragment_names_rule.dart';
 export 'src/validation/rules/unique_operation_names_rule.dart';
 export 'src/validation/rules/variables_are_input_types_rule.dart';
 export 'src/validation/type_info.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -173,3 +173,56 @@ validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided re
 validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Missing non-nullable argument is not allowed,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
 validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Supplies required variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
 validation/__tests__/ProvidedRequiredArgumentsRule-test.ts,Validate: Provided required arguments > Fragment required arguments,Skips missing fragments,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,no fragments,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,one fragment,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,many fragments,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,inline fragments are always unique,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,fragment and operation named the same,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,fragments named the same,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/UniqueFragmentNamesRule-test.ts,Validate: Unique fragment names,fragments named the same without being referenced,ported,test/validation/unique_fragment_names_test.dart,
+validation/__tests__/KnownFragmentNamesRule-test.ts,Validate: Known fragment names,known fragment names are valid,ported,test/validation/known_fragment_names_test.dart,
+validation/__tests__/KnownFragmentNamesRule-test.ts,Validate: Known fragment names,unknown fragment names are invalid,ported,test/validation/known_fragment_names_test.dart,
+validation/__tests__/NoUnusedFragmentsRule-test.ts,Validate: No unused fragments,all fragment names are used,ported,test/validation/no_unused_fragments_test.dart,
+validation/__tests__/NoUnusedFragmentsRule-test.ts,Validate: No unused fragments,all fragment names are used by multiple operations,ported,test/validation/no_unused_fragments_test.dart,
+validation/__tests__/NoUnusedFragmentsRule-test.ts,Validate: No unused fragments,contains unknown fragments,ported,test/validation/no_unused_fragments_test.dart,
+validation/__tests__/NoUnusedFragmentsRule-test.ts,Validate: No unused fragments,contains unknown fragments with ref cycle,ported,test/validation/no_unused_fragments_test.dart,
+validation/__tests__/NoUnusedFragmentsRule-test.ts,Validate: No unused fragments,contains unknown and undef fragments,ported,test/validation/no_unused_fragments_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,single reference is valid,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,spreading twice is not circular,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,spreading twice indirectly is not circular,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,double spread within abstract types,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,does not false positive on unknown fragment,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,spreading recursively within field fails,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself directly,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself directly within inline fragment,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself indirectly,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself indirectly reports opposite order,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself indirectly within inline fragment,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself deeply,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself deeply two paths,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself deeply two paths -- alt traverse order,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/NoFragmentCyclesRule-test.ts,Validate: No circular fragment spreads,no spreading itself deeply and immediately,ported,test/validation/no_fragment_cycles_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,of the same object,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,of the same object with inline fragment,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,object into an implemented interface,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,object into containing union,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,union into contained object,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,union into overlapping interface,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,union into overlapping union,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into implemented object,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into overlapping interface,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into overlapping interface in inline fragment,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into overlapping union,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,ignores incorrect type (caught by FragmentsOnCompositeTypesRule),ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,ignores unknown fragments (caught by KnownFragmentNamesRule),ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,different object into object,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,different object into object in inline fragment,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,object into not implementing interface,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,object into not containing union,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,union into not contained object,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,union into non overlapping interface,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,union into non overlapping union,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non implementing object,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non overlapping interface,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non overlapping interface in inline fragment,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non overlapping union,ported,test/validation/possible_fragment_spreads_test.dart,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/fragment_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/known_fragment_names_test.dart test/validation/no_fragment_cycles_test.dart test/validation/no_unused_fragments_test.dart test/validation/possible_fragment_spreads_test.dart test/validation/unique_fragment_names_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The fragment rules: `UniqueFragmentNamesRule`, `KnownFragmentNamesRule`,
  `NoUnusedFragmentsRule`, `NoFragmentCyclesRule` and
  `PossibleFragmentSpreadsRule` (`GQL211`, `GQL214`-`GQL217`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/fragment_spread_collector.dart packages/typed_graphql/lib/src/validation/rules/known_fragment_names_rule.dart packages/typed_graphql/lib/src/validation/rules/no_fragment_cycles_rule.dart packages/typed_graphql/lib/src/validation/rules/no_unused_fragments_rule.dart packages/typed_graphql/lib/src/validation/rules/possible_fragment_spreads_rule.dart packages/typed_graphql/lib/src/validation/rules/unique_fragment_names_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/fragment_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/known_fragment_names_test.dart packages/typed_graphql_conformance/test/validation/no_fragment_cycles_test.dart packages/typed_graphql_conformance/test/validation/no_unused_fragments_test.dart packages/typed_graphql_conformance/test/validation/possible_fragment_spreads_test.dart packages/typed_graphql_conformance/test/validation/unique_fragment_names_test.dart
git commit -q -m "feat(typed_graphql): add the fragment rules of operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: The value rules

`ValuesOfCorrectTypeRule`, `InputObjectFieldNamesRule`, `UniqueInputFieldNamesRule` and `InputObjectRequiredFieldsRule` (`GQL218`–`GQL221`): graphql-js's one value rule split by `ValueProblemKind` through `ValueProblemVisitor`, one `ValueChecker` pass per literal; their ported suites.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/rules/input_object_field_names_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/input_object_required_fields_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/unique_input_field_names_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/values_of_correct_type_rule.dart`, `packages/typed_graphql/lib/src/validation/value_problem_visitor.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/value_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/unique_input_field_names_test.dart`, `packages/typed_graphql_conformance/test/validation/values_of_correct_type_defaults_and_directives_test.dart`, `packages/typed_graphql_conformance/test/validation/values_of_correct_type_enums_and_lists_test.dart`, `packages/typed_graphql_conformance/test/validation/values_of_correct_type_input_objects_test.dart`, `packages/typed_graphql_conformance/test/validation/values_of_correct_type_test.dart`

**Interfaces:**
- Consumes: Task 1 (`ValueChecker` with `allowsVariables`, `ValueProblemKind`), Tasks 2–3.
- Produces:
- Diagnostic codes: `GQL218`, `GQL219`, `GQL220`, `GQL221`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/rules/input_object_field_names_rule.dart
final class const InputObjectFieldNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)

// validation/rules/input_object_required_fields_rule.dart
final class const InputObjectRequiredFieldsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)

// validation/rules/unique_input_field_names_rule.dart
final class const UniqueInputFieldNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UniqueInputFieldNames(final ValidationContext context)
  VisitAction enter(Node node)
  void leave(Node node)

// validation/rules/values_of_correct_type_rule.dart
final class const ValuesOfCorrectTypeRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)

// validation/value_problem_visitor.dart
final class ValueProblemVisitor(…)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/value_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes, the split of one
// graphql-js rule into three and the branches those suites do not reach.
void main() {
  final checked = Checked('''
scalar Any
input In { a: Int! b: Int next: In }
type Query { f(arg: In): Int any(arg: Any): Int }
''');
  const query = '{ f(arg: { b: "x", c: 1 }) }';
  const valueRules = <ValidationRule>[
    ValuesOfCorrectTypeRule(),
    InputObjectFieldNamesRule(),
    InputObjectRequiredFieldsRule(),
  ];

  test('a value of the wrong type is GQL218', () {
    expect(checked.errors(query, [const ValuesOfCorrectTypeRule()]), [
      '1:15 GQL218 Int cannot represent non-integer value: "x"',
    ]);
  });

  test('an unknown input field is GQL219', () {
    expect(checked.errors(query, [const InputObjectFieldNamesRule()]), [
      '1:20 GQL219 Expected value of type "In" not to include unknown field '
          '"c". Did you mean "a" or "b"? Found: { b: "x", c: 1 }.',
    ]);
  });

  test('a missing required input field is GQL221', () {
    expect(checked.errors(query, [const InputObjectRequiredFieldsRule()]), [
      '1:10 GQL221 Expected value of type "In" to include required field '
          '"a", found: { b: "x", c: 1 }.',
    ]);
  });

  test('a repeated input field is GQL220', () {
    expect(
      checked.errors('{ f(arg: { a: 1, a: 2 }) }', [
        const UniqueInputFieldNamesRule(),
      ]),
      ['1:12 GQL220 There can be only one input field named "a".'],
    );
  });

  test('a variable is not checked as a value', () {
    expect(
      checked.errors(r'query($v: Int) { f(arg: { a: $v }) }', valueRules),
      isEmpty,
    );
  });

  test('a value is checked once, at its outermost literal', () {
    expect(
      checked.errors('{ f(arg: { a: 1, next: { a: "x" } }) }', [
        const ValuesOfCorrectTypeRule(),
      ]),
      ['1:29 GQL218 Int cannot represent non-integer value: "x"'],
    );
  });

  group('values nested 100000 deep, built in code', () {
    const depth = 100000;

    List<Diagnostic> validate(String field, Value argument) {
      final document = Document([
        OperationDefinition(
          OperationType.query,
          SelectionSet([
            Field(
              null,
              Name(field),
              arguments: [Argument(const Name('arg'), argument)],
            ),
          ]),
        ),
      ]);
      return const DocumentValidator(
        rules: [...valueRules, UniqueInputFieldNamesRule()],
      ).validate(checked.schema, document).diagnostics;
    }

    test('a list value', () {
      Value value = const IntValue('1');
      for (var i = 0; i < depth; i++) {
        value = ListValue([value]);
      }
      expect(validate('any', value), isEmpty);
    });

    test('an object value', () {
      Value value = const IntValue('1');
      for (var i = 0; i < depth; i++) {
        value = ObjectValue([ObjectField(const Name('a'), value)]);
      }
      expect(validate('any', value), isEmpty);
    });

    test('an input object value of a recursive input type', () {
      Value value = ObjectValue([
        const ObjectField(Name('a'), IntValue('1')),
      ]);
      for (var i = 0; i < depth; i++) {
        value = ObjectValue([
          const ObjectField(Name('a'), IntValue('1')),
          ObjectField(const Name('next'), value),
        ]);
      }
      expect(validate('f', value), isEmpty);
    });
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -100,7 +100,9 @@ void main() {
         'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
         'validation/__tests__/UniqueArgumentNamesRule-test.ts',
         'validation/__tests__/UniqueFragmentNamesRule-test.ts',
+        'validation/__tests__/UniqueInputFieldNamesRule-test.ts',
         'validation/__tests__/UniqueOperationNamesRule-test.ts',
+        'validation/__tests__/ValuesOfCorrectTypeRule-test.ts',
         'validation/__tests__/VariablesAreInputTypesRule-test.ts',
       ],
     ),
```

Create `packages/typed_graphql_conformance/test/validation/unique_input_field_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueInputFieldNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueInputFieldNamesRule());

  group('Validate: Unique input field names', () {
    test('input object with fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f: true })
      }
    '''),
        isEmpty,
      );
    });

    test('same input object within two args', () {
      expect(
        port.errors('''
      {
        field(arg1: { f: true }, arg2: { f: true })
      }
    '''),
        isEmpty,
      );
    });

    test('multiple input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: "value", f2: "value", f3: "value" })
      }
    '''),
        isEmpty,
      );
    });

    test('allows for nested input objects with similar fields', () {
      expect(
        port.errors('''
      {
        field(arg: {
          deep: {
            deep: {
              id: 1
            }
            id: 1
          }
          id: 1
        })
      }
    '''),
        isEmpty,
      );
    });

    test('duplicate input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: "value", f1: "value" })
      }
    '''),
        [
          'There can be only one input field named "f1". @ 3:22 3:35',
        ],
      );
    });

    test('many duplicate input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: "value", f1: "value", f1: "value" })
      }
    '''),
        [
          'There can be only one input field named "f1". @ 3:22 3:35',
          'There can be only one input field named "f1". @ 3:22 3:48',
        ],
      );
    });

    test('nested duplicate input object fields', () {
      expect(
        port.errors('''
      {
        field(arg: { f1: {f2: "value", f2: "value" }})
      }
    '''),
        [
          'There can be only one input field named "f2". @ 3:27 3:40',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/values_of_correct_type_defaults_and_directives_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ValuesOfCorrectTypeRule-test.ts
// (one rule there, three here: M4 splits it by kind of problem);
// mapping/validation.csv says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort.all([
    const ValuesOfCorrectTypeRule(),
    const InputObjectFieldNamesRule(),
    const InputObjectRequiredFieldsRule(),
  ]);

  group('Validate: Values of correct type', () {
    group('Directive arguments', () {
      test('with directives of valid types', () {
        expect(
          port.errors('''
        {
          dog @include(if: true) {
            name
          }
          human @skip(if: false) {
            name
          }
        }
      '''),
          isEmpty,
        );
      });

      test('with directive with incorrect types', () {
        expect(
          port.errors('''
        {
          dog @include(if: "yes") {
            name @skip(if: ENUM)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: "yes" @ 3:28',
            'Boolean cannot represent a non boolean value: ENUM @ 4:28',
          ],
        );
      });
    });

    group('Variable default values', () {
      test('variables with valid default values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: Int = 1,
          $b: String = "ok",
          $c: ComplexInput = { requiredField: true, intField: 3 }
          $d: Int! = 123
        ) {
          dog { name }
        }
      '''),
          isEmpty,
        );
      });

      test('variables with valid default null values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: Int = null,
          $b: String = null,
          $c: ComplexInput = { requiredField: true, intField: null }
        ) {
          dog { name }
        }
      '''),
          isEmpty,
        );
      });

      test('variables with invalid default null values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: Int! = null,
          $b: String! = null,
          $c: ComplexInput = { requiredField: null, intField: null }
        ) {
          dog { name }
        }
      '''),
          [
            'Expected value of non-null type "Int!" not to be null. @ 3:22',
            'Expected value of non-null type "String!" not to be null. @ 4:25',
            'Expected value of non-null type "Boolean!" not to be null. @ 5:47',
          ],
        );
      });

      test('variables with invalid default values', () {
        expect(
          port.errors(r'''
        query InvalidDefaultValues(
          $a: Int = "one",
          $b: String = 4,
          $c: ComplexInput = "NotVeryComplex"
        ) {
          dog { name }
        }
      '''),
          [
            'Int cannot represent non-integer value: "one" @ 3:21',
            'String cannot represent a non string value: 4 @ 4:24',
            'Expected value of type "ComplexInput" to be an object, found: "NotVeryComplex". @ 5:30',
          ],
        );
      });

      test('variables with complex invalid default values', () {
        expect(
          port.errors(r'''
        query WithDefaultValues(
          $a: ComplexInput = { requiredField: 123, intField: "abc" }
        ) {
          dog { name }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: 123 @ 3:47',
            'Int cannot represent non-integer value: "abc" @ 3:62',
          ],
        );
      });

      test('complex variables missing required field', () {
        expect(
          port.errors(r'''
        query MissingRequiredField($a: ComplexInput = {intField: 3}) {
          dog { name }
        }
      '''),
          [
            'Expected value of type "ComplexInput" to include required field "requiredField", found: { intField: 3 }. @ 2:55',
          ],
        );
      });

      test('list variables with invalid item', () {
        expect(
          port.errors(r'''
        query InvalidItem($a: [String] = ["one", 2]) {
          dog { name }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 2:50',
          ],
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/values_of_correct_type_enums_and_lists_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ValuesOfCorrectTypeRule-test.ts
// (one rule there, three here: M4 splits it by kind of problem);
// mapping/validation.csv says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort.all([
    const ValuesOfCorrectTypeRule(),
    const InputObjectFieldNamesRule(),
    const InputObjectRequiredFieldsRule(),
  ]);

  group('Validate: Values of correct type', () {
    group('Invalid Enum value', () {
      test('Int into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: 2)
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: 2. @ 4:41',
          ],
        );
      });

      test('Float into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: 1.0)
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: 1.0. @ 4:41',
          ],
        );
      });

      test('String into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: "SIT")
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: "SIT". Did you mean the enum value "SIT"? @ 4:41',
          ],
        );
      });

      test('String into Enum (no suggestion)', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: "SIT")
          }
        }
      ''', hidesSuggestions: true),
          [
            'Enum "DogCommand" cannot represent non-enum value: "SIT". @ 4:41',
          ],
        );
      });

      test('Boolean into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: true)
          }
        }
      '''),
          [
            'Enum "DogCommand" cannot represent non-enum value: true. @ 4:41',
          ],
        );
      });

      test('Unknown Enum Value into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: JUGGLE)
          }
        }
      '''),
          [
            'Value "JUGGLE" does not exist in "DogCommand" enum. @ 4:41',
          ],
        );
      });

      test('Different case Enum Value into Enum', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: sit)
          }
        }
      '''),
          [
            'Value "sit" does not exist in "DogCommand" enum. Did you mean the enum value "SIT"? @ 4:41',
          ],
        );
      });

      test('Different case Enum Value into Enum (no suggestion)', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: sit)
          }
        }
      ''', hidesSuggestions: true),
          [
            'Value "sit" does not exist in "DogCommand" enum. @ 4:41',
          ],
        );
      });
    });

    group('Valid List value', () {
      test('Good list value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: ["one", null, "two"])
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Empty list value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: [])
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Null value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: null)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Single value into List', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: "one")
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid List value', () {
      test('Incorrect item type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: ["one", 2])
          }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 4:55',
          ],
        );
      });

      test('Single value of incorrect type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringListArgField(stringListArg: 1)
          }
        }
      '''),
          [
            'String cannot represent a non string value: 1 @ 4:47',
          ],
        );
      });
    });

    group('Valid non-nullable value', () {
      test('Arg on optional arg', () {
        expect(
          port.errors('''
        {
          dog {
            isHouseTrained(atOtherHomes: true)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No Arg on optional arg', () {
        expect(
          port.errors('''
        {
          dog {
            isHouseTrained
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple args', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: 1, req2: 2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple args reverse order', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: 2, req1: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('No args on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts
          }
        }
      '''),
          isEmpty,
        );
      });

      test('One arg on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts(opt1: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Second arg on multiple optional', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOpts(opt2: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple required args on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Multiple required and one optional arg on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4, opt1: 5)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('All required and optional args on mixedList', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleOptAndReq(req1: 3, req2: 4, opt1: 5, opt2: 6)
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid non-nullable value', () {
      test('Incorrect value type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req2: "two", req1: "one")
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: "two" @ 4:32',
            'Int cannot represent non-integer value: "one" @ 4:45',
          ],
        );
      });

      test(
        'Incorrect value and missing argument (ProvidedRequiredArgumentsRule)',
        () {
          expect(
            port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: "one")
          }
        }
      '''),
            [
              'Int cannot represent non-integer value: "one" @ 4:32',
            ],
          );
        },
      );

      test('Null value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            multipleReqs(req1: null)
          }
        }
      '''),
          [
            'Expected value of non-null type "Int!" not to be null. @ 4:32',
          ],
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/values_of_correct_type_input_objects_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ValuesOfCorrectTypeRule-test.ts
// (one rule there, three here: M4 splits it by kind of problem);
// mapping/validation.csv says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort.all([
    const ValuesOfCorrectTypeRule(),
    const InputObjectFieldNamesRule(),
    const InputObjectRequiredFieldsRule(),
  ]);

  group('Validate: Values of correct type', () {
    group('Valid input object value', () {
      test('Optional arg, despite required field in type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Partial object, only required', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { requiredField: true })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Partial object, required field can be falsy', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { requiredField: false })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Partial object, including required', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { requiredField: true, intField: 4 })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Full object', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              intField: 4,
              stringField: "foo",
              booleanField: false,
              stringListField: ["one", "two"]
            })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Full object with fields in different order', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              stringListField: ["one", "two"],
              booleanField: false,
              requiredField: true,
              stringField: "foo",
              intField: 4,
            })
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Valid oneOf input object value', () {
      test('Exactly one field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: "abc" })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Exactly one non-nullable variable', () {
        expect(
          port.errors(r'''
        query ($string: String!) {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: $string })
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid input object value', () {
      test('Partial object, missing required', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: { intField: 4 })
          }
        }
      '''),
          [
            'Expected value of type "ComplexInput" to include required field "requiredField", found: { intField: 4 }. @ 4:41',
          ],
        );
      });

      test('Partial object, invalid field type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              stringListField: ["one", 2],
              requiredField: true,
            })
          }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 5:40',
          ],
        );
      });

      test('Partial object, null to non-null field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              nonNullField: null,
            })
          }
        }
      '''),
          [
            'Expected value of non-null type "Boolean!" not to be null. @ 6:29',
          ],
        );
      });

      test('Partial object, unknown field arg', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              invalidField: "value"
            })
          }
        }
      '''),
          [
            'Expected value of type "ComplexInput" not to include unknown field "invalidField". Did you mean "intField"? Found: { requiredField: true, invalidField: "value" }. @ 6:15',
          ],
        );
      });

      test('Partial object, unknown field arg (no suggestions)', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            complexArgField(complexArg: {
              requiredField: true,
              invalidField: "value"
            })
          }
        }
      ''', hidesSuggestions: true),
          [
            'Expected value of type "ComplexInput" not to include unknown field "invalidField", found: { requiredField: true, invalidField: "value" }. @ 6:15',
          ],
        );
      });

      test('allows custom scalar to accept complex literals', () {
        final scalarPort = port.withSchema('''
          scalar Any
          type Query { anyArg(arg: Any): String }
        ''');

        expect(
          scalarPort.errors('''
          {
            test1: anyArg(arg: 123)
            test2: anyArg(arg: "abc")
            test3: anyArg(arg: [123, "abc"])
            test4: anyArg(arg: {deep: [123, "abc"]})
          }
        '''),
          isEmpty,
        );
      });
    });

    group('Invalid oneOf input object value', () {
      test('Invalid field type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: 2 })
          }
        }
      '''),
          [
            'String cannot represent a non string value: 2 @ 4:52',
          ],
        );
      });

      test('Exactly one null field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: null })
          }
        }
      '''),
          [
            'Within OneOf Input Object type "OneOfInput", exactly one field must be specified, and the value for that field must be non-null. @ 4:37',
          ],
        );
      });

      test('More than one field', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: "abc", intField: 123 })
          }
        }
      '''),
          [
            'Within OneOf Input Object type "OneOfInput", exactly one field must be specified, and the value for that field must be non-null. @ 4:37',
          ],
        );
      });

      test('Unknown field does not add a oneOf error', () {
        expect(
          port.errors('''
          {
            complicatedArgs {
              oneOfArgField(oneOfArg: {
                stringField: "abc",
                invalidField: 123
              })
            }
          }
        '''),
          [
            'Expected value of type "OneOfInput" not to include unknown field "invalidField". Did you mean "intField"? Found: { stringField: "abc", invalidField: 123 }. @ 6:17',
          ],
        );
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/values_of_correct_type_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/ValuesOfCorrectTypeRule-test.ts
// (one rule there, three here: M4 splits it by kind of problem);
// mapping/validation.csv says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort.all([
    const ValuesOfCorrectTypeRule(),
    const InputObjectFieldNamesRule(),
    const InputObjectRequiredFieldsRule(),
  ]);

  group('Validate: Values of correct type', () {
    group('Valid values', () {
      test('Good int value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good negative int value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: -2)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good boolean value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: true)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good string value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: "foo")
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good float value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: 1.1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good negative float value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: -1.1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Int into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Int into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: 1)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('String into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: "someIdString")
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Good enum value', () {
        expect(
          port.errors('''
        {
          dog {
            doesKnowCommand(dogCommand: SIT)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Enum with undefined value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            enumArgField(enumArg: UNKNOWN)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Enum with null value', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            enumArgField(enumArg: NO_FUR)
          }
        }
      '''),
          isEmpty,
        );
      });

      test('null into nullable type', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: null)
          }
        }
      '''),
          isEmpty,
        );

        expect(
          port.errors('''
        {
          dog(a: null, b: null, c:{ requiredField: true, intField: null }) {
            name
          }
        }
      '''),
          isEmpty,
        );
      });
    });

    group('Invalid String values', () {
      test('Int into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: 1)
          }
        }
      '''),
          [
            'String cannot represent a non string value: 1 @ 4:39',
          ],
        );
      });

      test('Float into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: 1.0)
          }
        }
      '''),
          [
            'String cannot represent a non string value: 1.0 @ 4:39',
          ],
        );
      });

      test('Boolean into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: true)
          }
        }
      '''),
          [
            'String cannot represent a non string value: true @ 4:39',
          ],
        );
      });

      test('Unquoted String into String', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            stringArgField(stringArg: BAR)
          }
        }
      '''),
          [
            'String cannot represent a non string value: BAR @ 4:39',
          ],
        );
      });
    });

    group('Invalid Int values', () {
      test('String into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: "3")
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: "3" @ 4:33',
          ],
        );
      });

      test('Big Int into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 829384293849283498239482938)
          }
        }
      '''),
          [
            'Int cannot represent non 32-bit signed integer value: 829384293849283498239482938 @ 4:33',
          ],
        );
      });

      test('Unquoted String into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: FOO)
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: FOO @ 4:33',
          ],
        );
      });

      test('Simple Float into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 3.0)
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: 3.0 @ 4:33',
          ],
        );
      });

      test('Float into Int', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            intArgField(intArg: 3.333)
          }
        }
      '''),
          [
            'Int cannot represent non-integer value: 3.333 @ 4:33',
          ],
        );
      });
    });

    group('Invalid Float values', () {
      test('String into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: "3.333")
          }
        }
      '''),
          [
            'Float cannot represent non numeric value: "3.333" @ 4:37',
          ],
        );
      });

      test('Boolean into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: true)
          }
        }
      '''),
          [
            'Float cannot represent non numeric value: true @ 4:37',
          ],
        );
      });

      test('Unquoted into Float', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            floatArgField(floatArg: FOO)
          }
        }
      '''),
          [
            'Float cannot represent non numeric value: FOO @ 4:37',
          ],
        );
      });
    });

    group('Invalid Boolean value', () {
      test('Int into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: 2)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: 2 @ 4:41',
          ],
        );
      });

      test('Float into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: 1.0)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: 1.0 @ 4:41',
          ],
        );
      });

      test('String into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: "true")
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: "true" @ 4:41',
          ],
        );
      });

      test('Unquoted into Boolean', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            booleanArgField(booleanArg: TRUE)
          }
        }
      '''),
          [
            'Boolean cannot represent a non boolean value: TRUE @ 4:41',
          ],
        );
      });
    });

    group('Invalid ID value', () {
      test('Float into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: 1.0)
          }
        }
      '''),
          [
            'ID cannot represent a non-string and non-integer value: 1.0 @ 4:31',
          ],
        );
      });

      test('Boolean into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: true)
          }
        }
      '''),
          [
            'ID cannot represent a non-string and non-integer value: true @ 4:31',
          ],
        );
      });

      test('Unquoted into ID', () {
        expect(
          port.errors('''
        {
          complicatedArgs {
            idArgField(idArg: SOMETHING)
          }
        }
      '''),
          [
            'ID cannot represent a non-string and non-integer value: SOMETHING @ 4:31',
          ],
        );
      });
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/value_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/unique_input_field_names_test.dart test/validation/values_of_correct_type_defaults_and_directives_test.dart test/validation/values_of_correct_type_enums_and_lists_test.dart test/validation/values_of_correct_type_input_objects_test.dart test/validation/values_of_correct_type_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -393,6 +393,22 @@ enum DiagnosticCode(
   /// can never apply to the parent type (spec §5.5.2.3).
   possibleFragmentSpreads('GQL217'),
 
+  /// `GQL218`: a value literal that is not a value of the input type
+  /// expected at its position (spec §5.6.1).
+  valuesOfCorrectType('GQL218'),
+
+  /// `GQL219`: an input object literal that gives a field its type does
+  /// not define (spec §5.6.2).
+  inputObjectFieldNames('GQL219'),
+
+  /// `GQL220`: an input object literal that gives a field more than once
+  /// (spec §5.6.3).
+  uniqueInputFieldNames('GQL220'),
+
+  /// `GQL221`: an input object literal that omits a required field of its
+  /// type (spec §5.6.4).
+  inputObjectRequiredFields('GQL221'),
+
   /// `GQL226`: a variable whose type is not an input type (spec §5.8.2).
   variablesAreInputTypes('GQL226'),
 
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -7,6 +7,8 @@ import 'document_validation_result.dart';
 import 'rules/executable_definitions_rule.dart';
 import 'rules/fields_on_correct_type_rule.dart';
 import 'rules/fragments_on_composite_types_rule.dart';
+import 'rules/input_object_field_names_rule.dart';
+import 'rules/input_object_required_fields_rule.dart';
 import 'rules/known_argument_names_rule.dart';
 import 'rules/known_fragment_names_rule.dart';
 import 'rules/known_operation_types_rule.dart';
@@ -20,7 +22,9 @@ import 'rules/scalar_leafs_rule.dart';
 import 'rules/single_field_subscriptions_rule.dart';
 import 'rules/unique_argument_names_rule.dart';
 import 'rules/unique_fragment_names_rule.dart';
+import 'rules/unique_input_field_names_rule.dart';
 import 'rules/unique_operation_names_rule.dart';
+import 'rules/values_of_correct_type_rule.dart';
 import 'rules/variables_are_input_types_rule.dart';
 import 'validation_context.dart';
 import 'validation_rule.dart';
@@ -78,7 +82,11 @@ final class const DocumentValidator({
     NoFragmentCyclesRule(),
     KnownArgumentNamesRule(),
     UniqueArgumentNamesRule(),
+    ValuesOfCorrectTypeRule(),
+    InputObjectFieldNamesRule(),
+    InputObjectRequiredFieldsRule(),
     ProvidedRequiredArgumentsRule(),
+    UniqueInputFieldNamesRule(),
   ];
 
   /// Validates [document] against [schema]; diagnostics point into
```

Create `packages/typed_graphql/lib/src/validation/rules/input_object_field_names_rule.dart`:

```dart
import '../../language/visitor/ast_visitor.dart';
import '../../schema/validation/value_problem_kind.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../value_problem_visitor.dart';

/// Spec §5.6.2 "Input Object Field Names": an input object literal gives
/// only fields its type defines (`GQL219`).
///
/// It reports a field the input object type does not define, at the node
/// graphql-js's
/// `ValuesOfCorrectTypeRule` points at; the other problems of a value
/// belong to the other value rules.
///
/// {@category validation}
final class const InputObjectFieldNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => ValueProblemVisitor(
    context,
    ValueProblemKind.unknownField,
    .inputObjectFieldNames,
  );
}
```

Create `packages/typed_graphql/lib/src/validation/rules/input_object_required_fields_rule.dart`:

```dart
import '../../language/visitor/ast_visitor.dart';
import '../../schema/validation/value_problem_kind.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../value_problem_visitor.dart';

/// Spec §5.6.4 "Input Object Required Fields": an input object literal gives
/// every required field (`GQL221`).
///
/// It reports a required field of the input object type that the literal
/// omits, at the node graphql-js's
/// `ValuesOfCorrectTypeRule` points at; the other problems of a value
/// belong to the other value rules.
///
/// {@category validation}
final class const InputObjectRequiredFieldsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => ValueProblemVisitor(
    context,
    ValueProblemKind.missingField,
    .inputObjectRequiredFields,
  );
}
```

Create `packages/typed_graphql/lib/src/validation/rules/unique_input_field_names_rule.dart`:

```dart
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/ast/object_field.dart';
import '../../language/ast/value.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.6.3 "Input Object Field Uniqueness": an input object literal
/// gives each field once (`GQL220`).
///
/// The error points at the first name and at the repeat.
///
/// {@category validation}
final class const UniqueInputFieldNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueInputFieldNames(context);
}

final class _UniqueInputFieldNames(final ValidationContext context)
    extends AstVisitor {
  // One map of known names per object being walked, innermost last.
  final List<Map<String, Name>> _stack = [];

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case ObjectValue():
        _stack.add({});
      case ObjectField(:final name):
        _check(name);
    }
    return .next;
  }

  @override
  void leave(Node node) {
    if (node is ObjectValue) {
      _stack.removeLast();
    }
  }

  void _check(Name name) {
    final known = _stack.last[name.value];
    if (known == null) {
      _stack.last[name.value] = name;
      return;
    }
    context.report(
      .uniqueInputFieldNames,
      'There can be only one input field named "${name.value}".',
      [known, name],
    );
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/values_of_correct_type_rule.dart`:

```dart
import '../../language/visitor/ast_visitor.dart';
import '../../schema/validation/value_problem_kind.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../value_problem_visitor.dart';

/// Spec §5.6.1 "Values of Correct Type": a value literal is of the type
/// expected at its position (`GQL218`).
///
/// It reports a literal that is not a value of its input type, or null where
/// a non-null value is expected, at the node graphql-js's
/// `ValuesOfCorrectTypeRule` points at; the other problems of a value
/// belong to the other value rules.
///
/// {@category validation}
final class const ValuesOfCorrectTypeRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => ValueProblemVisitor(
    context,
    ValueProblemKind.invalid,
    .valuesOfCorrectType,
  );
}
```

Create `packages/typed_graphql/lib/src/validation/value_problem_visitor.dart`:

```dart
import '../diagnostics/diagnostic_code.dart';
import '../language/ast/node.dart';
import '../language/ast/value.dart';
import '../language/visitor/ast_visitor.dart';
import '../language/visitor/visit_action.dart';
import '../schema/validation/value_checker.dart';
import '../schema/validation/value_problem_kind.dart';
import 'validation_context.dart';

/// The visitor behind the three value rules (spec §5.6): graphql-js's
/// `ValuesOfCorrectTypeRule` checks each value literal once, and M4 splits
/// its errors by [kind], each reported with [code].
///
/// On entering a literal whose input type is known it checks the whole
/// value and skips its children, as graphql-js does.
final class ValueProblemVisitor(
  /// The context of the run.
  final ValidationContext context,

  /// The problems this rule reports.
  final ValueProblemKind kind,

  /// The code of those problems.
  final DiagnosticCode code,
) extends AstVisitor {
  /// Creates the visitor.
  this;

  @override
  VisitAction enter(Node node) {
    if (node is! Value || node is Variable) {
      return .next;
    }
    // A list's own type is its parent's input type: TypeInfo has already
    // entered the item type.
    final type = node is ListValue
        ? context.typeInfo.parentInputType
        : context.typeInfo.inputType;
    if (type == null) {
      return .skip;
    }
    final checker = ValueChecker(
      context.schema,
      allowsVariables: true,
      includesSuggestions: context.includesSuggestions,
    );
    for (final problem in checker.check(node, type)) {
      if (problem.kind == kind) {
        context.report(code, problem.message, [problem.node]);
      }
    }
    return .skip;
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -92,6 +92,8 @@ export 'src/validation/document_validator.dart';
 export 'src/validation/rules/executable_definitions_rule.dart';
 export 'src/validation/rules/fields_on_correct_type_rule.dart';
 export 'src/validation/rules/fragments_on_composite_types_rule.dart';
+export 'src/validation/rules/input_object_field_names_rule.dart';
+export 'src/validation/rules/input_object_required_fields_rule.dart';
 export 'src/validation/rules/known_argument_names_rule.dart';
 export 'src/validation/rules/known_fragment_names_rule.dart';
 export 'src/validation/rules/known_operation_types_rule.dart';
@@ -105,7 +107,9 @@ export 'src/validation/rules/scalar_leafs_rule.dart';
 export 'src/validation/rules/single_field_subscriptions_rule.dart';
 export 'src/validation/rules/unique_argument_names_rule.dart';
 export 'src/validation/rules/unique_fragment_names_rule.dart';
+export 'src/validation/rules/unique_input_field_names_rule.dart';
 export 'src/validation/rules/unique_operation_names_rule.dart';
+export 'src/validation/rules/values_of_correct_type_rule.dart';
 export 'src/validation/rules/variables_are_input_types_rule.dart';
 export 'src/validation/type_info.dart';
 export 'src/validation/validation_context.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -226,3 +226,100 @@ validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible frag
 validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non overlapping interface,ported,test/validation/possible_fragment_spreads_test.dart,
 validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non overlapping interface in inline fragment,ported,test/validation/possible_fragment_spreads_test.dart,
 validation/__tests__/PossibleFragmentSpreadsRule-test.ts,Validate: Possible fragment spreads,interface into non overlapping union,ported,test/validation/possible_fragment_spreads_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good int value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good negative int value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good boolean value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good string value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good float value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good negative float value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Int into Float,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Int into ID,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,String into ID,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Good enum value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Enum with undefined value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,Enum with null value,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid values,null into nullable type,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid String values,Int into String,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid String values,Float into String,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid String values,Boolean into String,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid String values,Unquoted String into String,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Int values,String into Int,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Int values,Big Int into Int,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Int values,Unquoted String into Int,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Int values,Simple Float into Int,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Int values,Float into Int,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Float values,String into Float,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Float values,Boolean into Float,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Float values,Unquoted into Float,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Boolean value,Int into Boolean,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Boolean value,Float into Boolean,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Boolean value,String into Boolean,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Boolean value,Unquoted into Boolean,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid ID value,Float into ID,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid ID value,Boolean into ID,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid ID value,Unquoted into ID,ported,test/validation/values_of_correct_type_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,Int into Enum,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,Float into Enum,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,String into Enum,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,String into Enum (no suggestion),ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,Boolean into Enum,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,Unknown Enum Value into Enum,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,Different case Enum Value into Enum,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid Enum value,Different case Enum Value into Enum (no suggestion),ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid List value,Good list value,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid List value,Empty list value,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid List value,Null value,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid List value,Single value into List,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid List value,Incorrect item type,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid List value,Single value of incorrect type,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,Arg on optional arg,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,No Arg on optional arg,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,Multiple args,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,Multiple args reverse order,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,No args on multiple optional,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,One arg on multiple optional,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,Second arg on multiple optional,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,Multiple required args on mixedList,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,Multiple required and one optional arg on mixedList,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid non-nullable value,All required and optional args on mixedList,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid non-nullable value,Incorrect value type,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid non-nullable value,Incorrect value and missing argument (ProvidedRequiredArgumentsRule),ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid non-nullable value,Null value,ported,test/validation/values_of_correct_type_enums_and_lists_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid input object value,"Optional arg, despite required field in type",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid input object value,"Partial object, only required",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid input object value,"Partial object, required field can be falsy",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid input object value,"Partial object, including required",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid input object value,Full object,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid input object value,Full object with fields in different order,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid oneOf input object value,Exactly one field,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Valid oneOf input object value,Exactly one non-nullable variable,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,"Partial object, missing required",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,"Partial object, invalid field type",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,"Partial object, null to non-null field",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,"Partial object, unknown field arg",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,"Partial object, unknown field arg (no suggestions)",ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,reports original error for custom scalar which throws,skipped,,a custom scalar's coercion function is not part of a schema built from SDL (R2.9): a custom scalar accepts any literal here
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,reports error for custom scalar that returns undefined,skipped,,a custom scalar's coercion function is not part of a schema built from SDL (R2.9): a custom scalar accepts any literal here
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid input object value,allows custom scalar to accept complex literals,adapted,test/validation/values_of_correct_type_input_objects_test.dart,the schema is built from SDL: scalar Any
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid oneOf input object value,Invalid field type,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid oneOf input object value,Exactly one null field,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid oneOf input object value,More than one field,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Invalid oneOf input object value,Unknown field does not add a oneOf error,ported,test/validation/values_of_correct_type_input_objects_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Directive arguments,with directives of valid types,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Directive arguments,with directive with incorrect types,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,variables with valid default values,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,variables with valid default null values,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,variables with invalid default null values,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,variables with invalid default values,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,variables with complex invalid default values,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,complex variables missing required field,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,list variables with invalid item,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Fragment argument values,list variables with invalid item,skipped,,fragment arguments are experimental: September2025 has none and the parser does not parse them
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Fragment argument values,fragment spread with invalid argument value,skipped,,fragment arguments are experimental: September2025 has none and the parser does not parse them
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,input object with fields,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,same input object within two args,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,multiple input object fields,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,allows for nested input objects with similar fields,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,duplicate input object fields,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,many duplicate input object fields,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,nested duplicate input object fields,ported,test/validation/unique_input_field_names_test.dart,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/value_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/unique_input_field_names_test.dart test/validation/values_of_correct_type_defaults_and_directives_test.dart test/validation/values_of_correct_type_enums_and_lists_test.dart test/validation/values_of_correct_type_input_objects_test.dart test/validation/values_of_correct_type_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The value rules: `ValuesOfCorrectTypeRule`, `InputObjectFieldNamesRule`,
  `UniqueInputFieldNamesRule` and `InputObjectRequiredFieldsRule`
  (`GQL218`-`GQL221`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/rules/input_object_field_names_rule.dart packages/typed_graphql/lib/src/validation/rules/input_object_required_fields_rule.dart packages/typed_graphql/lib/src/validation/rules/unique_input_field_names_rule.dart packages/typed_graphql/lib/src/validation/rules/values_of_correct_type_rule.dart packages/typed_graphql/lib/src/validation/value_problem_visitor.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/value_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/unique_input_field_names_test.dart packages/typed_graphql_conformance/test/validation/values_of_correct_type_defaults_and_directives_test.dart packages/typed_graphql_conformance/test/validation/values_of_correct_type_enums_and_lists_test.dart packages/typed_graphql_conformance/test/validation/values_of_correct_type_input_objects_test.dart packages/typed_graphql_conformance/test/validation/values_of_correct_type_test.dart
git commit -q -m "feat(typed_graphql): add the value rules of operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: The directive rules

`KnownDirectivesRule`, `DirectivesInValidLocationsRule` and `UniqueDirectivesPerLocationRule` (`GQL222`–`GQL224`) with their ported suites.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/rules/directives_in_valid_locations_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/known_directives_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/unique_directives_per_location_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/directive_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/known_directives_test.dart`, `packages/typed_graphql_conformance/test/validation/unique_directives_per_location_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
- Diagnostic codes: `GQL222`, `GQL223`, `GQL224`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/rules/directives_in_valid_locations_rule.dart
final class const DirectivesInValidLocationsRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _DirectivesInValidLocations(final ValidationContext context)
  VisitAction enter(Node node)
  void leave(Node node)

// validation/rules/known_directives_rule.dart
final class const KnownDirectivesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _KnownDirectives(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/unique_directives_per_location_rule.dart
final class const UniqueDirectivesPerLocationRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UniqueDirectivesPerLocation(final ValidationContext context)
  VisitAction enter(Node node)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/directive_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes, the split of
// graphql-js's KnownDirectivesRule in two and the branches those suites do
// not reach.
void main() {
  final checked = Checked('''
directive @once on FIELD | QUERY
directive @many repeatable on FIELD
type Query { f: Int }
''');

  test('an unknown directive is GQL222', () {
    expect(checked.errors('{ f @nope }', [const KnownDirectivesRule()]), [
      '1:5 GQL222 Unknown directive "@nope".',
    ]);
  });

  test('a misplaced directive is GQL223', () {
    expect(
      checked.errors('query @skip(if: true) { f }', [
        const DirectivesInValidLocationsRule(),
      ]),
      ['1:7 GQL223 Directive "@skip" may not be used on QUERY.'],
    );
  });

  test('a repeated directive is GQL224', () {
    expect(
      checked.errors('{ f @once @once }', [
        const UniqueDirectivesPerLocationRule(),
      ]),
      [
        '1:5 GQL224 The directive "@once" can only be used once at this '
            'location.',
      ],
    );
  });

  test('KnownDirectivesRule leaves a misplaced directive alone', () {
    expect(
      checked.errors('query @skip(if: true) { f }', [
        const KnownDirectivesRule(),
      ]),
      isEmpty,
    );
  });

  test('DirectivesInValidLocationsRule leaves an unknown one alone', () {
    expect(
      checked.errors('{ f @nope }', [const DirectivesInValidLocationsRule()]),
      isEmpty,
    );
  });

  test('UniqueDirectivesPerLocationRule leaves an unknown one alone', () {
    expect(
      checked.errors('{ f @nope @nope }', [
        const UniqueDirectivesPerLocationRule(),
      ]),
      isEmpty,
    );
  });

  test('a repeatable directive may repeat', () {
    expect(
      checked.errors('{ f @many @many }', [
        const UniqueDirectivesPerLocationRule(),
      ]),
      isEmpty,
    );
  });

  test('a variable definition and a fragment spread have locations', () {
    expect(
      checked.errors(
        r'query ($v: Int @once) { ...F } fragment F on Query { f }',
        [const DirectivesInValidLocationsRule()],
      ),
      ['1:16 GQL223 Directive "@once" may not be used on VARIABLE_DEFINITION.'],
    );
  });

  test('the split rules together report in graphql-js order', () {
    expect(
      checked.errors('query @nope @skip(if: true) { f }', [
        const KnownDirectivesRule(),
        const DirectivesInValidLocationsRule(),
      ]),
      [
        '1:7 GQL222 Unknown directive "@nope".',
        '1:13 GQL223 Directive "@skip" may not be used on QUERY.',
      ],
    );
  });

  group('100000 directives on one field, built in code', () {
    const count = 100000;

    Document documentWith(String directive) => Document([
      OperationDefinition(
        OperationType.query,
        SelectionSet([
          Field(
            null,
            const Name('f'),
            directives: [
              for (var i = 0; i < count; i++) Directive(Name(directive)),
            ],
          ),
        ]),
      ),
    ]);

    test('a non-repeatable one is reported once per repeat', () {
      final diagnostics = const DocumentValidator(
        rules: [UniqueDirectivesPerLocationRule()],
        maxErrors: count,
      ).validate(checked.schema, documentWith('once')).diagnostics;
      expect(diagnostics, hasLength(count - 1));
    });

    test('a repeatable one is not reported', () {
      final diagnostics = const DocumentValidator(
        rules: [
          KnownDirectivesRule(),
          DirectivesInValidLocationsRule(),
          UniqueDirectivesPerLocationRule(),
        ],
      ).validate(checked.schema, documentWith('many')).diagnostics;
      expect(diagnostics, isEmpty);
    });
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -88,6 +88,7 @@ void main() {
         'validation/__tests__/FieldsOnCorrectTypeRule-test.ts',
         'validation/__tests__/FragmentsOnCompositeTypesRule-test.ts',
         'validation/__tests__/KnownArgumentNamesRule-test.ts',
+        'validation/__tests__/KnownDirectivesRule-test.ts',
         'validation/__tests__/KnownFragmentNamesRule-test.ts',
         'validation/__tests__/KnownOperationTypesRules-test.ts',
         'validation/__tests__/KnownTypeNamesRule-test.ts',
@@ -99,6 +100,7 @@ void main() {
         'validation/__tests__/ScalarLeafsRule-test.ts',
         'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
         'validation/__tests__/UniqueArgumentNamesRule-test.ts',
+        'validation/__tests__/UniqueDirectivesPerLocationRule-test.ts',
         'validation/__tests__/UniqueFragmentNamesRule-test.ts',
         'validation/__tests__/UniqueInputFieldNamesRule-test.ts',
         'validation/__tests__/UniqueOperationNamesRule-test.ts',
```

Create `packages/typed_graphql_conformance/test/validation/known_directives_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/KnownDirectivesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  // graphql-js's one rule is two here (M4 spec section 5).
  final port = RulePort.all(
    const [KnownDirectivesRule(), DirectivesInValidLocationsRule()],
    schema: RulePort.validated(_schemaWithDirectives),
  );

  group('Validate: Known directives', () {
    test('with no directives', () {
      expect(
        port.errors('''
      query Foo {
        name
        ...Frag
      }

      fragment Frag on Dog {
        name
      }
    '''),
        isEmpty,
      );
    });

    test('with standard directives', () {
      expect(
        port.errors('''
      {
        human @skip(if: false) {
          name
          pets {
            ... on Dog @include(if: true) {
              name
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('with unknown directive', () {
      expect(
        port.errors('''
      {
        human @unknown(directive: "value") {
          name
        }
      }
    '''),
        [
          'Unknown directive "@unknown". @ 3:15',
        ],
      );
    });

    test('with many unknown directives', () {
      expect(
        port.errors('''
      {
        __typename @unknown
        human @unknown {
          name
          pets @unknown {
            name
          }
        }
      }
    '''),
        [
          'Unknown directive "@unknown". @ 3:20',
          'Unknown directive "@unknown". @ 4:15',
          'Unknown directive "@unknown". @ 6:16',
        ],
      );
    });

    test('with well placed directives', () {
      expect(
        port.errors(r'''
      query ($var: Boolean @onVariableDefinition) @onQuery {
        human @onField {
          ...Frag @onFragmentSpread
          ... @onInlineFragment {
            name @onField
          }
        }
      }

      mutation @onMutation {
        someField @onField
      }

      subscription @onSubscription {
        someField @onField
      }

      fragment Frag on Human @onFragmentDefinition {
        name @onField
      }
    '''),
        isEmpty,
      );
    });

    test('with misplaced directives', () {
      expect(
        port.errors(r'''
      query ($var: Boolean @onQuery) @onMutation {
        human @onQuery {
          ...Frag @onQuery
          ... @onQuery {
            name @onQuery
          }
        }
      }

      mutation @onQuery {
        someField @onQuery
      }

      subscription @onQuery {
        someField @onQuery
      }

      fragment Frag on Human @onQuery {
        name @onQuery
      }
    '''),
        [
          'Directive "@onQuery" may not be used on VARIABLE_DEFINITION. @ 2:28',
          'Directive "@onMutation" may not be used on QUERY. @ 2:38',
          'Directive "@onQuery" may not be used on FIELD. @ 3:15',
          'Directive "@onQuery" may not be used on FRAGMENT_SPREAD. @ 4:19',
          'Directive "@onQuery" may not be used on INLINE_FRAGMENT. @ 5:15',
          'Directive "@onQuery" may not be used on FIELD. @ 6:18',
          'Directive "@onQuery" may not be used on MUTATION. @ 11:16',
          'Directive "@onQuery" may not be used on FIELD. @ 12:19',
          'Directive "@onQuery" may not be used on SUBSCRIPTION. @ 15:20',
          'Directive "@onQuery" may not be used on FIELD. @ 16:19',
          'Directive "@onQuery" may not be used on FRAGMENT_DEFINITION. @ 19:30',
          'Directive "@onQuery" may not be used on FIELD. @ 20:14',
        ],
      );
    });
  });
}

const _schemaWithDirectives = '''
  type Query {
    dummy: String
  }

  directive @onQuery on QUERY
  directive @onMutation on MUTATION
  directive @onSubscription on SUBSCRIPTION
  directive @onField on FIELD
  directive @onFragmentDefinition on FRAGMENT_DEFINITION
  directive @onFragmentSpread on FRAGMENT_SPREAD
  directive @onInlineFragment on INLINE_FRAGMENT
  directive @onVariableDefinition on VARIABLE_DEFINITION
''';
```

Create `packages/typed_graphql_conformance/test/validation/unique_directives_per_location_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueDirectivesPerLocationRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final extended = const SchemaPort().extend(
    RulePort.testSchema.schema,
    _extensionSdl,
  );
  final port = RulePort(
    const UniqueDirectivesPerLocationRule(),
    schema: switch (const SchemaValidator().validate(extended)) {
      final ValidSchema valid => valid,
      InvalidSchema(:final diagnostics) => fail('$diagnostics'),
    },
  );

  group('Validate: Directives Are Unique Per Location', () {
    test('no directives', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field
      }
    '''),
        isEmpty,
      );
    });

    test('unique directives in different locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directiveA {
        field @directiveB
      }
    '''),
        isEmpty,
      );
    });

    test('unique directives in same locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directiveA @directiveB {
        field @directiveA @directiveB
      }
    '''),
        isEmpty,
      );
    });

    test('same directives in different locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directiveA {
        field @directiveA
      }
    '''),
        isEmpty,
      );
    });

    test('same directives in similar locations', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directive
        field @directive
      }
    '''),
        isEmpty,
      );
    });

    test('repeatable directives in same location', () {
      expect(
        port.errors('''
      fragment Test on Type @repeatable @repeatable {
        field @repeatable @repeatable
      }
    '''),
        isEmpty,
      );
    });

    test('unknown directives must be ignored', () {
      expect(
        port.errors('''
      type Test @unknown @unknown {
        field: String! @unknown @unknown
      }

      extend type Test @unknown {
        anotherField: String!
      }
    '''),
        isEmpty,
      );
    });

    test('duplicate directives in one location', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directive @directive
      }
    '''),
        [
          'The directive "@directive" can only be used once at this location. @ 3:15 3:26',
        ],
      );
    });

    test('many duplicate directives in one location', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directive @directive @directive
      }
    '''),
        [
          'The directive "@directive" can only be used once at this location. @ 3:15 3:26',
          'The directive "@directive" can only be used once at this location. @ 3:15 3:37',
        ],
      );
    });

    test('different duplicate directives in one location', () {
      expect(
        port.errors('''
      fragment Test on Type {
        field @directiveA @directiveB @directiveA @directiveB
      }
    '''),
        [
          'The directive "@directiveA" can only be used once at this location. @ 3:15 3:39',
          'The directive "@directiveB" can only be used once at this location. @ 3:27 3:51',
        ],
      );
    });

    test('duplicate directives in many locations', () {
      expect(
        port.errors('''
      fragment Test on Type @directive @directive {
        field @directive @directive
      }
    '''),
        [
          'The directive "@directive" can only be used once at this location. @ 2:29 2:40',
          'The directive "@directive" can only be used once at this location. @ 3:15 3:26',
        ],
      );
    });
  });
}

const _extensionSdl = '''
  directive @directive on FIELD | FRAGMENT_DEFINITION
  directive @directiveA on FIELD | FRAGMENT_DEFINITION
  directive @directiveB on FIELD | FRAGMENT_DEFINITION
  directive @repeatable repeatable on FIELD | FRAGMENT_DEFINITION
''';
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/directive_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/known_directives_test.dart test/validation/unique_directives_per_location_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -409,6 +409,17 @@ enum DiagnosticCode(
   /// type (spec §5.6.4).
   inputObjectRequiredFields('GQL221'),
 
+  /// `GQL222`: a directive the schema does not define (spec §5.7.1).
+  knownDirectives('GQL222'),
+
+  /// `GQL223`: a directive applied at a location its definition does not
+  /// list (spec §5.7.2).
+  directivesInValidLocations('GQL223'),
+
+  /// `GQL224`: a non-repeatable directive applied more than once at one
+  /// location (spec §5.7.3).
+  uniqueDirectivesPerLocation('GQL224'),
+
   /// `GQL226`: a variable whose type is not an input type (spec §5.8.2).
   variablesAreInputTypes('GQL226'),
 
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,12 +4,14 @@ import '../language/ast/document.dart';
 import '../language/visitor/ast_walker.dart';
 import '../schema/validation/schema_validation_result.dart';
 import 'document_validation_result.dart';
+import 'rules/directives_in_valid_locations_rule.dart';
 import 'rules/executable_definitions_rule.dart';
 import 'rules/fields_on_correct_type_rule.dart';
 import 'rules/fragments_on_composite_types_rule.dart';
 import 'rules/input_object_field_names_rule.dart';
 import 'rules/input_object_required_fields_rule.dart';
 import 'rules/known_argument_names_rule.dart';
+import 'rules/known_directives_rule.dart';
 import 'rules/known_fragment_names_rule.dart';
 import 'rules/known_operation_types_rule.dart';
 import 'rules/known_type_names_rule.dart';
@@ -21,6 +23,7 @@ import 'rules/provided_required_arguments_rule.dart';
 import 'rules/scalar_leafs_rule.dart';
 import 'rules/single_field_subscriptions_rule.dart';
 import 'rules/unique_argument_names_rule.dart';
+import 'rules/unique_directives_per_location_rule.dart';
 import 'rules/unique_fragment_names_rule.dart';
 import 'rules/unique_input_field_names_rule.dart';
 import 'rules/unique_operation_names_rule.dart';
@@ -80,6 +83,9 @@ final class const DocumentValidator({
     NoUnusedFragmentsRule(),
     PossibleFragmentSpreadsRule(),
     NoFragmentCyclesRule(),
+    KnownDirectivesRule(),
+    DirectivesInValidLocationsRule(),
+    UniqueDirectivesPerLocationRule(),
     KnownArgumentNamesRule(),
     UniqueArgumentNamesRule(),
     ValuesOfCorrectTypeRule(),
```

Create `packages/typed_graphql/lib/src/validation/rules/directives_in_valid_locations_rule.dart`:

```dart
import '../../language/ast/directive.dart';
import '../../language/ast/directive_location.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/operation_type.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.7.2 "Directives Are In Valid Locations": a directive is applied
/// only where its definition allows (`GQL223`).
///
/// This is the second half of graphql-js's `KnownDirectivesRule`; a
/// directive the schema does not define is left to `KnownDirectivesRule`.
/// Only executable locations are known: a type system definition in an
/// executable document is reported by `ExecutableDefinitionsRule`.
///
/// {@category validation}
final class const DirectivesInValidLocationsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _DirectivesInValidLocations(context);
}

final class _DirectivesInValidLocations(final ValidationContext context)
    extends AstVisitor {
  // The nodes entered and not yet left; a directive's parent is the top.
  final List<Node> _ancestors = [];

  @override
  VisitAction enter(Node node) {
    if (node case Directive(:final name) when _ancestors.isNotEmpty) {
      _check(node, name.value, _locationOf(_ancestors.last));
    }
    _ancestors.add(node);
    return .next;
  }

  @override
  void leave(Node node) {
    _ancestors.removeLast();
  }

  void _check(Directive node, String name, DirectiveLocation? location) {
    final definition = context.schema.directiveNamed(name);
    if (definition == null ||
        location == null ||
        definition.locations.contains(location)) {
      return;
    }
    context.report(
      .directivesInValidLocations,
      'Directive "@$name" may not be used on ${location.spelling}.',
      [node],
    );
  }

  DirectiveLocation? _locationOf(Node parent) => switch (parent) {
    OperationDefinition(:final operation) => switch (operation) {
      OperationType.query => .query,
      OperationType.mutation => .mutation,
      OperationType.subscription => .subscription,
    },
    Field() => .field,
    FragmentSpread() => .fragmentSpread,
    InlineFragment() => .inlineFragment,
    FragmentDefinition() => .fragmentDefinition,
    VariableDefinition() => .variableDefinition,
    _ => null,
  };
}
```

Create `packages/typed_graphql/lib/src/validation/rules/known_directives_rule.dart`:

```dart
import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.7.1 "Directives Are Defined": every directive applied is defined
/// by the schema (`GQL222`).
///
/// graphql-js reports unknown and misplaced directives from one rule; here
/// this rule reports only the unknown ones and
/// `DirectivesInValidLocationsRule` the misplaced ones.
///
/// {@category validation}
final class const KnownDirectivesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownDirectives(context);
}

final class _KnownDirectives(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case Directive(:final name)
        when context.schema.directiveNamed(name.value) == null) {
      context.report(.knownDirectives, 'Unknown directive "@${name.value}".', [
        node,
      ]);
    }
    return .next;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/unique_directives_per_location_rule.dart`:

```dart
import '../../language/ast/directive.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.7.3 "Directives Are Unique Per Location": a directive that is
/// not repeatable is applied once at each location (`GQL224`).
///
/// The error points at the first use and relates to the repeat. A directive
/// the schema does not define is left to `KnownDirectivesRule`.
///
/// {@category validation}
final class const UniqueDirectivesPerLocationRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueDirectivesPerLocation(context);
}

final class _UniqueDirectivesPerLocation(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    final directives = switch (node) {
      OperationDefinition(:final directives) ||
      FragmentDefinition(:final directives) ||
      Field(:final directives) ||
      FragmentSpread(:final directives) ||
      InlineFragment(:final directives) ||
      VariableDefinition(:final directives) => directives,
      _ => const <Directive>[],
    };
    if (directives.length > 1) {
      _check(directives);
    }
    return .next;
  }

  void _check(List<Directive> directives) {
    final seen = <String, Directive>{};
    for (final directive in directives) {
      final name = directive.name.value;
      if (context.schema.directiveNamed(name)?.isRepeatable ?? true) {
        continue;
      }
      final first = seen[name];
      if (first == null) {
        seen[name] = directive;
      } else {
        context.report(
          .uniqueDirectivesPerLocation,
          'The directive "@$name" can only be used once at this location.',
          [first, directive],
        );
      }
    }
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -89,12 +89,14 @@ export 'src/schema/validation/schema_validation_result.dart';
 export 'src/schema/validation/schema_validator.dart';
 export 'src/validation/document_validation_result.dart';
 export 'src/validation/document_validator.dart';
+export 'src/validation/rules/directives_in_valid_locations_rule.dart';
 export 'src/validation/rules/executable_definitions_rule.dart';
 export 'src/validation/rules/fields_on_correct_type_rule.dart';
 export 'src/validation/rules/fragments_on_composite_types_rule.dart';
 export 'src/validation/rules/input_object_field_names_rule.dart';
 export 'src/validation/rules/input_object_required_fields_rule.dart';
 export 'src/validation/rules/known_argument_names_rule.dart';
+export 'src/validation/rules/known_directives_rule.dart';
 export 'src/validation/rules/known_fragment_names_rule.dart';
 export 'src/validation/rules/known_operation_types_rule.dart';
 export 'src/validation/rules/known_type_names_rule.dart';
@@ -106,6 +108,7 @@ export 'src/validation/rules/provided_required_arguments_rule.dart';
 export 'src/validation/rules/scalar_leafs_rule.dart';
 export 'src/validation/rules/single_field_subscriptions_rule.dart';
 export 'src/validation/rules/unique_argument_names_rule.dart';
+export 'src/validation/rules/unique_directives_per_location_rule.dart';
 export 'src/validation/rules/unique_fragment_names_rule.dart';
 export 'src/validation/rules/unique_input_field_names_rule.dart';
 export 'src/validation/rules/unique_operation_names_rule.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -323,3 +323,35 @@ validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input fi
 validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,duplicate input object fields,ported,test/validation/unique_input_field_names_test.dart,
 validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,many duplicate input object fields,ported,test/validation/unique_input_field_names_test.dart,
 validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,nested duplicate input object fields,ported,test/validation/unique_input_field_names_test.dart,
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives,with no directives,ported,test/validation/known_directives_test.dart,
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives,with standard directives,ported,test/validation/known_directives_test.dart,
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives,with unknown directive,ported,test/validation/known_directives_test.dart,
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives,with many unknown directives,ported,test/validation/known_directives_test.dart,
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives,with well placed directives,adapted,test/validation/known_directives_test.dart,the fragment variable definition is left out: September2025 has no fragment arguments
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives,with misplaced directives,adapted,test/validation/known_directives_test.dart,the fragment variable definition is left out: September2025 has no fragment arguments
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with directive defined inside SDL,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with standard directive,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with overridden standard directive,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with directive defined in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with directive used in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with unknown directive in schema extension,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with well placed directives,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/KnownDirectivesRule-test.ts,Validate: Known directives > within SDL,with misplaced directives,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,no directives,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,unique directives in different locations,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,unique directives in same locations,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,same directives in different locations,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,same directives in similar locations,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,repeatable directives in same location,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,unknown directives must be ignored,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives in one location,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,many duplicate directives in one location,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,different duplicate directives in one location,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives in many locations,ported,test/validation/unique_directives_per_location_test.dart,
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives on SDL definitions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives on SDL extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives between SDL definitions and extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives on directive definitions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives on directive extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives between directive definitions and extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives between directive extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/directive_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/known_directives_test.dart test/validation/unique_directives_per_location_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The directive rules: `KnownDirectivesRule`, `DirectivesInValidLocationsRule`
  and `UniqueDirectivesPerLocationRule` (`GQL222`-`GQL224`); graphql-js's
  `KnownDirectivesRule` is split in two.
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/rules/directives_in_valid_locations_rule.dart packages/typed_graphql/lib/src/validation/rules/known_directives_rule.dart packages/typed_graphql/lib/src/validation/rules/unique_directives_per_location_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/directive_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/known_directives_test.dart packages/typed_graphql_conformance/test/validation/unique_directives_per_location_test.dart
git commit -q -m "feat(typed_graphql): add the directive rules of operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: The variable rules

`UniqueVariableNamesRule`, `NoUndefinedVariablesRule`, `NoUnusedVariablesRule` and `VariablesInAllowedPositionRule` (`GQL225`, `GQL227`–`GQL229`). The closure rules work at `leave(Document)` through `OperationVisitor`, since a fragment may be defined after the operation that spreads it.

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/rules/no_undefined_variables_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/no_unused_variables_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/operation_visitor.dart`, `packages/typed_graphql/lib/src/validation/rules/unique_variable_names_rule.dart`, `packages/typed_graphql/lib/src/validation/rules/variables_in_allowed_position_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/variable_rules_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/no_undefined_variables_test.dart`, `packages/typed_graphql_conformance/test/validation/no_unused_variables_test.dart`, `packages/typed_graphql_conformance/test/validation/unique_variable_names_test.dart`, `packages/typed_graphql_conformance/test/validation/variables_in_allowed_position_test.dart`

**Interfaces:**
- Consumes: Task 2 (`recursiveVariableUsages`, `VariableUsage`), Task 3.
- Produces:
- Diagnostic codes: `GQL225`, `GQL227`, `GQL228`, `GQL229`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/rules/no_undefined_variables_rule.dart
final class const NoUndefinedVariablesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _NoUndefinedVariables(final ValidationContext context)
  void checkOperation(OperationDefinition operation)

// validation/rules/no_unused_variables_rule.dart
final class const NoUnusedVariablesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _NoUnusedVariables(final ValidationContext context)
  void checkOperation(OperationDefinition operation)

// validation/rules/operation_visitor.dart
abstract base class OperationVisitor extends AstVisitor
  VisitAction enter(Node node)
  void leave(Node node)
  void checkOperation(OperationDefinition operation)

// validation/rules/unique_variable_names_rule.dart
final class const UniqueVariableNamesRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _UniqueVariableNames(final ValidationContext context)
  VisitAction enter(Node node)

// validation/rules/variables_in_allowed_position_rule.dart
final class const VariablesInAllowedPositionRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _VariablesInAllowedPosition(final ValidationContext context)
  void checkOperation(OperationDefinition operation)
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/variable_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// The graphql-js suites of these rules are ported in
// typed_graphql_conformance; these tests pin the codes, the branches those
// suites do not reach and the work on large documents.
void main() {
  final checked = Checked('''
type Query { f(a: Int, b: Int! = 1, c: Int!, o: One, l: [Int!]): Int }
input One @oneOf { x: Int, y: String }
''');

  test('a repeated variable name is GQL225', () {
    expect(
      checked.errors(
        r'query ($a: Int, $b: Int, $a: Int) { f(a: $a, c: 1) }',
        [
          const UniqueVariableNamesRule(),
        ],
      ),
      [r'1:9 GQL225 There can be only one variable named "$a".'],
    );
  });

  test('an undefined variable is GQL227', () {
    expect(
      checked.errors(r'query Q { f(c: $c) }', [
        const NoUndefinedVariablesRule(),
      ]),
      [r'1:16 GQL227 Variable "$c" is not defined by operation "Q".'],
    );
  });

  test('an unused variable is GQL228', () {
    expect(
      checked.errors(r'query ($c: Int) { f(c: 1) }', [
        const NoUnusedVariablesRule(),
      ]),
      [r'1:8 GQL228 Variable "$c" is never used.'],
    );
  });

  test('a variable used only in a fragment the operation spreads is used', () {
    expect(
      checked.errors(
        r'query ($c: Int!) { ...F } fragment F on Query { f(c: $c) }',
        [const NoUnusedVariablesRule(), const NoUndefinedVariablesRule()],
      ),
      isEmpty,
    );
  });

  test('a variable of the wrong type is GQL229', () {
    expect(
      checked.errors(r'query ($c: String) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      [
        r'1:8 GQL229 Variable "$c" of type "String" used in position '
            'expecting type "Int!".',
      ],
    );
  });

  test('a nullable variable with a default fits a non-null position', () {
    expect(
      checked.errors(r'query ($c: Int = 1) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('a nullable variable fits a non-null position with a default', () {
    expect(
      checked.errors(r'query ($b: Int) { f(b: $b, c: 1) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('a null default does not make a nullable variable non-null', () {
    expect(
      checked.errors(r'query ($c: Int = null) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      hasLength(1),
    );
  });

  test('a nullable variable for a @oneOf field is GQL229', () {
    expect(
      checked.errors(r'query ($x: Int) { f(c: 1, o: {x: $x}) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      [
        r'1:8 GQL229 Variable "$x" is of type "Int" but must be non-nullable '
            'to be used for OneOf Input Object "One".',
      ],
    );
  });

  test('a non-null variable for a @oneOf field is allowed', () {
    expect(
      checked.errors(r'query ($x: Int!) { f(c: 1, o: {x: $x}) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('a variable of an unknown type is left to KnownTypeNamesRule', () {
    expect(
      checked.errors(r'query ($c: Nope) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('the last of two definitions of one name is the one checked', () {
    expect(
      checked.errors(r'query ($c: String, $c: Int!) { f(c: $c) }', [
        const VariablesInAllowedPositionRule(),
      ]),
      isEmpty,
    );
  });

  test('errors of an operation come before those of the next', () {
    expect(
      checked.errors(r'query A { f(c: $x) } query B { f(c: $y) }', [
        const NoUndefinedVariablesRule(),
      ]),
      [
        r'1:16 GQL227 Variable "$x" is not defined by operation "A".',
        r'1:37 GQL227 Variable "$y" is not defined by operation "B".',
      ],
    );
  });

  group('100000 variables, built in code', () {
    const count = 100000;

    // The parser limits the size of a document.
    Document document({required bool isDefined, required bool isUsed}) =>
        Document([
          OperationDefinition(
            OperationType.query,
            SelectionSet([
              if (isUsed)
                for (var i = 0; i < count; i++)
                  Field(
                    Name('x$i'),
                    const Name('f'),
                    arguments: [
                      Argument(const Name('a'), Variable(Name('v$i'))),
                    ],
                  )
              else
                Field(null, const Name('f')),
            ]),
            variableDefinitions: [
              if (isDefined)
                for (var i = 0; i < count; i++)
                  VariableDefinition(
                    Variable(Name('v$i')),
                    const NamedType(Name('Int')),
                  ),
            ],
          ),
        ]);

    List<Diagnostic> run(Document document, ValidationRule rule) =>
        DocumentValidator(
          rules: [rule],
          maxErrors: count,
        ).validate(checked.schema, document).diagnostics;

    test('declared and used raise no error', () {
      final valid = document(isDefined: true, isUsed: true);
      expect(run(valid, const UniqueVariableNamesRule()), isEmpty);
      expect(run(valid, const NoUndefinedVariablesRule()), isEmpty);
      expect(run(valid, const NoUnusedVariablesRule()), isEmpty);
      expect(run(valid, const VariablesInAllowedPositionRule()), isEmpty);
    });

    test('used and not declared is one error each', () {
      final diagnostics = run(
        document(isDefined: false, isUsed: true),
        const NoUndefinedVariablesRule(),
      );
      expect(diagnostics, hasLength(count));
    });

    test('declared and not used is one error each', () {
      final diagnostics = run(
        document(isDefined: true, isUsed: false),
        const NoUnusedVariablesRule(),
      );
      expect(diagnostics, hasLength(count));
    });
  });

  test('a variable used at the end of a fragment chain of 100000', () {
    const length = 100000;
    // Built in code: the parser limits the size of a document.
    final document = Document([
      OperationDefinition(
        OperationType.query,
        SelectionSet([FragmentSpread(const Name('F0'))]),
        variableDefinitions: [
          VariableDefinition(
            const Variable(Name('c')),
            const NonNullType(NamedType(Name('Int'))),
          ),
        ],
      ),
      for (var i = 0; i < length; i++)
        FragmentDefinition(
          Name('F$i'),
          const NamedType(Name('Query')),
          SelectionSet([
            if (i + 1 < length)
              FragmentSpread(Name('F${i + 1}'))
            else
              Field(
                null,
                const Name('f'),
                arguments: [
                  const Argument(Name('c'), Variable(Name('c'))),
                ],
              ),
          ]),
        ),
    ]);
    final diagnostics = const DocumentValidator(
      rules: [
        NoUndefinedVariablesRule(),
        NoUnusedVariablesRule(),
        VariablesInAllowedPositionRule(),
      ],
    ).validate(checked.schema, document).diagnostics;
    expect(diagnostics, isEmpty);
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -94,7 +94,9 @@ void main() {
         'validation/__tests__/KnownTypeNamesRule-test.ts',
         'validation/__tests__/LoneAnonymousOperationRule-test.ts',
         'validation/__tests__/NoFragmentCyclesRule-test.ts',
+        'validation/__tests__/NoUndefinedVariablesRule-test.ts',
         'validation/__tests__/NoUnusedFragmentsRule-test.ts',
+        'validation/__tests__/NoUnusedVariablesRule-test.ts',
         'validation/__tests__/PossibleFragmentSpreadsRule-test.ts',
         'validation/__tests__/ProvidedRequiredArgumentsRule-test.ts',
         'validation/__tests__/ScalarLeafsRule-test.ts',
@@ -104,8 +106,10 @@ void main() {
         'validation/__tests__/UniqueFragmentNamesRule-test.ts',
         'validation/__tests__/UniqueInputFieldNamesRule-test.ts',
         'validation/__tests__/UniqueOperationNamesRule-test.ts',
+        'validation/__tests__/UniqueVariableNamesRule-test.ts',
         'validation/__tests__/ValuesOfCorrectTypeRule-test.ts',
         'validation/__tests__/VariablesAreInputTypesRule-test.ts',
+        'validation/__tests__/VariablesInAllowedPositionRule-test.ts',
       ],
     ),
   ];
```

Create `packages/typed_graphql_conformance/test/validation/no_undefined_variables_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoUndefinedVariablesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoUndefinedVariablesRule());

  group('Validate: No undefined variables', () {
    test('all variables defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('all variables deeply defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a) {
          field(b: $b) {
            field(c: $c)
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('all variables deeply in inline fragments defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ... on Type {
          field(a: $a) {
            field(b: $b) {
              ... on Type {
                field(c: $c)
              }
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('all variables in fragments deeply defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field(c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('variable within single fragment defined in multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      query Bar($a: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a)
      }
    '''),
        isEmpty,
      );
    });

    test('variable within fragments defined in operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      query Bar($b: String) {
        ...FragB
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        isEmpty,
      );
    });

    test('variable within recursive fragment defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragA
        }
      }
    '''),
        isEmpty,
      );
    });

    test('variable not defined', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a, b: $b, c: $c, d: $d)
      }
    '''),
        [
          r'Variable "$d" is not defined by operation "Foo". @ 3:39 2:7',
        ],
      );
    });

    test('variable not defined by un-named query', () {
      expect(
        port.errors(r'''
      {
        field(a: $a)
      }
    '''),
        [
          r'Variable "$a" is not defined. @ 3:18 2:7',
        ],
      );
    });

    test('multiple variables not defined', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 3:18 2:7',
          r'Variable "$c" is not defined by operation "Foo". @ 3:32 2:7',
        ],
      );
    });

    test('variable in fragment not defined by un-named query', () {
      expect(
        port.errors(r'''
      {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a)
      }
    '''),
        [
          r'Variable "$a" is not defined. @ 6:18 2:7',
        ],
      );
    });

    test('variable in fragment not defined by operation', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field(c: $c)
      }
    '''),
        [
          r'Variable "$c" is not defined by operation "Foo". @ 16:18 2:7',
        ],
      );
    });

    test('multiple variables in fragments not defined', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field(c: $c)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 6:18 2:7',
          r'Variable "$c" is not defined by operation "Foo". @ 16:18 2:7',
        ],
      );
    });

    test('single variable in fragment not defined by multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragAB
      }
      query Bar($a: String) {
        ...FragAB
      }
      fragment FragAB on Type {
        field(a: $a, b: $b)
      }
    '''),
        [
          r'Variable "$b" is not defined by operation "Foo". @ 9:25 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 9:25 5:7',
        ],
      );
    });

    test('variables in fragment not defined by multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragAB
      }
      query Bar($a: String) {
        ...FragAB
      }
      fragment FragAB on Type {
        field(a: $a, b: $b)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 9:18 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 9:25 5:7',
        ],
      );
    });

    test('variable in fragment used by other operation', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragA
      }
      query Bar($a: String) {
        ...FragB
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 9:18 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 12:18 5:7',
        ],
      );
    });

    test('multiple undefined variables produce multiple errors', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragAB
      }
      query Bar($a: String) {
        ...FragAB
      }
      fragment FragAB on Type {
        field1(a: $a, b: $b)
        ...FragC
        field3(a: $a, b: $b)
      }
      fragment FragC on Type {
        field2(c: $c)
      }
    '''),
        [
          r'Variable "$a" is not defined by operation "Foo". @ 9:19 2:7',
          r'Variable "$a" is not defined by operation "Foo". @ 11:19 2:7',
          r'Variable "$c" is not defined by operation "Foo". @ 14:19 2:7',
          r'Variable "$b" is not defined by operation "Bar". @ 9:26 5:7',
          r'Variable "$b" is not defined by operation "Bar". @ 11:26 5:7',
          r'Variable "$c" is not defined by operation "Bar". @ 14:19 5:7',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/no_unused_variables_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/NoUnusedVariablesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const NoUnusedVariablesRule());

  group('Validate: No unused variables', () {
    test('uses all variables', () {
      expect(
        port.errors(r'''
      query ($a: String, $b: String, $c: String) {
        field(a: $a, b: $b, c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('uses all variables deeply', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(a: $a) {
          field(b: $b) {
            field(c: $c)
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('uses all variables deeply in inline fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ... on Type {
          field(a: $a) {
            field(b: $b) {
              ... on Type {
                field(c: $c)
              }
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('uses all variables in fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field(c: $c)
      }
    '''),
        isEmpty,
      );
    });

    test('variable used by fragment in multiple operations', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      query Bar($b: String) {
        ...FragB
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        isEmpty,
      );
    });

    test('variable used by recursive fragment', () {
      expect(
        port.errors(r'''
      query Foo($a: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragA
        }
      }
    '''),
        isEmpty,
      );
    });

    test('variable not used', () {
      expect(
        port.errors(r'''
      query ($a: String, $b: String, $c: String) {
        field(a: $a, b: $b)
      }
    '''),
        [
          r'Variable "$c" is never used. @ 2:38',
        ],
      );
    });

    test('multiple variables not used', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$a" is never used in operation "Foo". @ 2:17',
          r'Variable "$c" is never used in operation "Foo". @ 2:41',
        ],
      );
    });

    test('variable not used in fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a) {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field
      }
    '''),
        [
          r'Variable "$c" is never used in operation "Foo". @ 2:41',
        ],
      );
    });

    test('multiple variables not used in fragments', () {
      expect(
        port.errors(r'''
      query Foo($a: String, $b: String, $c: String) {
        ...FragA
      }
      fragment FragA on Type {
        field {
          ...FragB
        }
      }
      fragment FragB on Type {
        field(b: $b) {
          ...FragC
        }
      }
      fragment FragC on Type {
        field
      }
    '''),
        [
          r'Variable "$a" is never used in operation "Foo". @ 2:17',
          r'Variable "$c" is never used in operation "Foo". @ 2:41',
        ],
      );
    });

    test('variable not used by unreferenced fragment', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragA
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$b" is never used in operation "Foo". @ 2:17',
        ],
      );
    });

    test('variable not used by fragment used by other operation', () {
      expect(
        port.errors(r'''
      query Foo($b: String) {
        ...FragA
      }
      query Bar($a: String) {
        ...FragB
      }
      fragment FragA on Type {
        field(a: $a)
      }
      fragment FragB on Type {
        field(b: $b)
      }
    '''),
        [
          r'Variable "$b" is never used in operation "Foo". @ 2:17',
          r'Variable "$a" is never used in operation "Bar". @ 5:17',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/unique_variable_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/UniqueVariableNamesRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const UniqueVariableNamesRule());

  group('Validate: Unique variable names', () {
    test('unique variable names', () {
      expect(
        port.errors(r'''
      query A($x: Int, $y: String) { __typename }
      query B($x: String, $y: Int) { __typename }
    '''),
        isEmpty,
      );
    });

    test('duplicate variable names', () {
      expect(
        port.errors(r'''
      query A($x: Int, $x: Int, $x: String) { __typename }
      query B($x: String, $x: Int) { __typename }
      query C($x: Int, $x: Int) { __typename }
    '''),
        [
          r'There can be only one variable named "$x". @ 2:16 2:25 2:34',
          r'There can be only one variable named "$x". @ 3:16 3:28',
          r'There can be only one variable named "$x". @ 4:16 4:25',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/variables_in_allowed_position_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/VariablesInAllowedPositionRule-test.ts; mapping/validation.csv
// says which tests are adapted or skipped, and why.
void main() {
  final port = RulePort(const VariablesInAllowedPositionRule());

  group('Validate: Variables are in allowed positions', () {
    test('Boolean => Boolean', () {
      expect(
        port.errors(r'''
      query Query($booleanArg: Boolean)
      {
        complicatedArgs {
          booleanArgField(booleanArg: $booleanArg)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean => Boolean within fragment', () {
      expect(
        port.errors(r'''
      fragment booleanArgFrag on ComplicatedArgs {
        booleanArgField(booleanArg: $booleanArg)
      }
      query Query($booleanArg: Boolean)
      {
        complicatedArgs {
          ...booleanArgFrag
        }
      }
    '''),
        isEmpty,
      );

      expect(
        port.errors(r'''
      query Query($booleanArg: Boolean)
      {
        complicatedArgs {
          ...booleanArgFrag
        }
      }
      fragment booleanArgFrag on ComplicatedArgs {
        booleanArgField(booleanArg: $booleanArg)
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean! => Boolean', () {
      expect(
        port.errors(r'''
      query Query($nonNullBooleanArg: Boolean!)
      {
        complicatedArgs {
          booleanArgField(booleanArg: $nonNullBooleanArg)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean! => Boolean within fragment', () {
      expect(
        port.errors(r'''
      fragment booleanArgFrag on ComplicatedArgs {
        booleanArgField(booleanArg: $nonNullBooleanArg)
      }

      query Query($nonNullBooleanArg: Boolean!)
      {
        complicatedArgs {
          ...booleanArgFrag
        }
      }
    '''),
        isEmpty,
      );
    });

    test('[String] => [String]', () {
      expect(
        port.errors(r'''
      query Query($stringListVar: [String])
      {
        complicatedArgs {
          stringListArgField(stringListArg: $stringListVar)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('[String!] => [String]', () {
      expect(
        port.errors(r'''
      query Query($stringListVar: [String!])
      {
        complicatedArgs {
          stringListArgField(stringListArg: $stringListVar)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('String => [String] in item position', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String)
      {
        complicatedArgs {
          stringListArgField(stringListArg: [$stringVar])
        }
      }
    '''),
        isEmpty,
      );
    });

    test('String! => [String] in item position', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String!)
      {
        complicatedArgs {
          stringListArgField(stringListArg: [$stringVar])
        }
      }
    '''),
        isEmpty,
      );
    });

    test('ComplexInput => ComplexInput', () {
      expect(
        port.errors(r'''
      query Query($complexVar: ComplexInput)
      {
        complicatedArgs {
          complexArgField(complexArg: $complexVar)
        }
      }
    '''),
        isEmpty,
      );
    });

    test('ComplexInput => ComplexInput in field position', () {
      expect(
        port.errors(r'''
      query Query($boolVar: Boolean = false)
      {
        complicatedArgs {
          complexArgField(complexArg: {requiredArg: $boolVar})
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Boolean! => Boolean! in directive', () {
      expect(
        port.errors(r'''
      query Query($boolVar: Boolean!)
      {
        dog @include(if: $boolVar)
      }
    '''),
        isEmpty,
      );
    });

    test('Int => Int!', () {
      expect(
        port.errors(r'''
      query Query($intArg: Int) {
        complicatedArgs {
          nonNullIntArgField(nonNullIntArg: $intArg)
        }
      }
    '''),
        [
          r'Variable "$intArg" of type "Int" used in position expecting type "Int!". @ 2:19 4:45',
        ],
      );
    });

    test('Int => Int! within fragment', () {
      expect(
        port.errors(r'''
      fragment nonNullIntArgFieldFrag on ComplicatedArgs {
        nonNullIntArgField(nonNullIntArg: $intArg)
      }

      query Query($intArg: Int) {
        complicatedArgs {
          ...nonNullIntArgFieldFrag
        }
      }
    '''),
        [
          r'Variable "$intArg" of type "Int" used in position expecting type "Int!". @ 6:19 3:43',
        ],
      );
    });

    test('Int => Int! within nested fragment', () {
      expect(
        port.errors(r'''
      fragment outerFrag on ComplicatedArgs {
        ...nonNullIntArgFieldFrag
      }

      fragment nonNullIntArgFieldFrag on ComplicatedArgs {
        nonNullIntArgField(nonNullIntArg: $intArg)
      }

      query Query($intArg: Int) {
        complicatedArgs {
          ...outerFrag
        }
      }
    '''),
        [
          r'Variable "$intArg" of type "Int" used in position expecting type "Int!". @ 10:19 7:43',
        ],
      );
    });

    test('String over Boolean', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String) {
        complicatedArgs {
          booleanArgField(booleanArg: $stringVar)
        }
      }
    '''),
        [
          r'Variable "$stringVar" of type "String" used in position expecting type "Boolean". @ 2:19 4:39',
        ],
      );
    });

    test('String => [String]', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String) {
        complicatedArgs {
          stringListArgField(stringListArg: $stringVar)
        }
      }
    '''),
        [
          r'Variable "$stringVar" of type "String" used in position expecting type "[String]". @ 2:19 4:45',
        ],
      );
    });

    test('Boolean => Boolean! in directive', () {
      expect(
        port.errors(r'''
      query Query($boolVar: Boolean) {
        dog @include(if: $boolVar)
      }
    '''),
        [
          r'Variable "$boolVar" of type "Boolean" used in position expecting type "Boolean!". @ 2:19 3:26',
        ],
      );
    });

    test('String => Boolean! in directive', () {
      expect(
        port.errors(r'''
      query Query($stringVar: String) {
        dog @include(if: $stringVar)
      }
    '''),
        [
          r'Variable "$stringVar" of type "String" used in position expecting type "Boolean!". @ 2:19 3:26',
        ],
      );
    });

    test('[String] => [String!]', () {
      expect(
        port.errors(r'''
      query Query($stringListVar: [String])
      {
        complicatedArgs {
          stringListNonNullArgField(stringListNonNullArg: $stringListVar)
        }
      }
    '''),
        [
          r'Variable "$stringListVar" of type "[String]" used in position expecting type "[String!]". @ 2:19 5:59',
        ],
      );
    });

    group('Allows optional (nullable) variables with default values', () {
      test('Int => Int! fails when variable provides null default value', () {
        expect(
          port.errors(r'''
        query Query($intVar: Int = null) {
          complicatedArgs {
            nonNullIntArgField(nonNullIntArg: $intVar)
          }
        }
      '''),
          [
            r'Variable "$intVar" of type "Int" used in position expecting type "Int!". @ 2:21 4:47',
          ],
        );
      });

      test('Int => Int! when variable provides non-null default value', () {
        expect(
          port.errors(r'''
        query Query($intVar: Int = 1) {
          complicatedArgs {
            nonNullIntArgField(nonNullIntArg: $intVar)
          }
        }'''),
          isEmpty,
        );
      });

      test('Int => Int! when optional argument provides default value', () {
        expect(
          port.errors(r'''
        query Query($intVar: Int) {
          complicatedArgs {
            nonNullFieldWithDefault(nonNullIntArg: $intVar)
          }
        }'''),
          isEmpty,
        );
      });

      test(
        'Boolean => Boolean! in directive with default value with option',
        () {
          expect(
            port.errors(r'''
        query Query($boolVar: Boolean = false) {
          dog @include(if: $boolVar)
        }'''),
            isEmpty,
          );
        },
      );

      test('undefined in directive with default value with option', () {
        expect(
          port.errors(r'''
        {
          dog @include(if: $x)
        }'''),
          isEmpty,
        );
      });
    });

    group('Validates OneOf Input Objects', () {
      test('Allows exactly one non-nullable variable', () {
        expect(
          port.errors(r'''
        query ($string: String!) {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: $string })
          }
        }
      '''),
          isEmpty,
        );
      });

      test('Forbids one nullable variable', () {
        expect(
          port.errors(r'''
        query ($string: String) {
          complicatedArgs {
            oneOfArgField(oneOfArg: { stringField: $string })
          }
        }
      '''),
          [
            r'Variable "$string" is of type "String" but must be non-nullable to be used for OneOf Input Object "OneOfInput". @ 2:16 4:52',
          ],
        );
      });
    });
  });

  group('Validates OneOf Input Objects', () {
    test('Allows exactly one non-nullable variable', () {
      expect(
        port.errors(r'''
      query ($string: String!) {
        complicatedArgs {
          oneOfArgField(oneOfArg: { stringField: $string })
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Undefined variable in oneOf input object', () {
      expect(
        port.errors(r'''
      {
        complicatedArgs {
          oneOfArgField(oneOfArg: { stringField: $undefinedVariable })
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Forbids one nullable variable', () {
      expect(
        port.errors(r'''
      query ($string: String) {
        complicatedArgs {
          oneOfArgField(oneOfArg: { stringField: $string })
        }
      }
    '''),
        [
          r'Variable "$string" is of type "String" but must be non-nullable to be used for OneOf Input Object "OneOfInput". @ 2:14 4:50',
        ],
      );
    });
  });

  group('Non-specified behavior of variables within custom scalars', () {
    test('Allows using variables inside object literal in custom scalar', () {
      expect(
        port.errors(r'''
      query Query($x: Float) {
        dog {
          distanceFrom(loc: {x: $x, y: 10.0})
        }
      }'''),
        isEmpty,
      );
    });

    test('Allows using variables inside list literal in custom scalar', () {
      expect(
        port.errors(r'''
      query Query($x: Float) {
        dog {
          distanceFrom(loc: [$x, 10.0])
        }
      }'''),
        isEmpty,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/variable_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/no_undefined_variables_test.dart test/validation/no_unused_variables_test.dart test/validation/unique_variable_names_test.dart test/validation/variables_in_allowed_position_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -420,9 +420,25 @@ enum DiagnosticCode(
   /// location (spec §5.7.3).
   uniqueDirectivesPerLocation('GQL224'),
 
+  /// `GQL225`: an operation that declares two variables with one name
+  /// (spec §5.8.1).
+  uniqueVariableNames('GQL225'),
+
   /// `GQL226`: a variable whose type is not an input type (spec §5.8.2).
   variablesAreInputTypes('GQL226'),
 
+  /// `GQL227`: a variable an operation uses, directly or through
+  /// fragments, without declaring it (spec §5.8.3).
+  noUndefinedVariables('GQL227'),
+
+  /// `GQL228`: a variable an operation declares and never uses, directly or
+  /// through fragments (spec §5.8.4).
+  noUnusedVariables('GQL228'),
+
+  /// `GQL229`: a variable used where its type is not allowed, or a nullable
+  /// variable used for a field of a `@oneOf` input object (spec §5.8.5).
+  variablesInAllowedPosition('GQL229'),
+
   /// `GQL230`: validating a document needed more work than the
   /// validator's step budget allows, such as fragments that expand to
   /// more fields than the budget, or many operations each spreading a
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -17,7 +17,9 @@ import 'rules/known_operation_types_rule.dart';
 import 'rules/known_type_names_rule.dart';
 import 'rules/lone_anonymous_operation_rule.dart';
 import 'rules/no_fragment_cycles_rule.dart';
+import 'rules/no_undefined_variables_rule.dart';
 import 'rules/no_unused_fragments_rule.dart';
+import 'rules/no_unused_variables_rule.dart';
 import 'rules/possible_fragment_spreads_rule.dart';
 import 'rules/provided_required_arguments_rule.dart';
 import 'rules/scalar_leafs_rule.dart';
@@ -27,8 +29,10 @@ import 'rules/unique_directives_per_location_rule.dart';
 import 'rules/unique_fragment_names_rule.dart';
 import 'rules/unique_input_field_names_rule.dart';
 import 'rules/unique_operation_names_rule.dart';
+import 'rules/unique_variable_names_rule.dart';
 import 'rules/values_of_correct_type_rule.dart';
 import 'rules/variables_are_input_types_rule.dart';
+import 'rules/variables_in_allowed_position_rule.dart';
 import 'validation_context.dart';
 import 'validation_rule.dart';
 
@@ -83,6 +87,9 @@ final class const DocumentValidator({
     NoUnusedFragmentsRule(),
     PossibleFragmentSpreadsRule(),
     NoFragmentCyclesRule(),
+    UniqueVariableNamesRule(),
+    NoUndefinedVariablesRule(),
+    NoUnusedVariablesRule(),
     KnownDirectivesRule(),
     DirectivesInValidLocationsRule(),
     UniqueDirectivesPerLocationRule(),
@@ -92,6 +99,7 @@ final class const DocumentValidator({
     InputObjectFieldNamesRule(),
     InputObjectRequiredFieldsRule(),
     ProvidedRequiredArgumentsRule(),
+    VariablesInAllowedPositionRule(),
     UniqueInputFieldNamesRule(),
   ];
 
```

Create `packages/typed_graphql/lib/src/validation/rules/no_undefined_variables_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'operation_visitor.dart';

/// Spec §5.8.3 "All Variable Uses Defined": every variable an operation
/// uses, directly or through fragments, is declared by it (`GQL227`).
///
/// Reported when the walk leaves the document, operation by operation.
///
/// {@category validation}
final class const NoUndefinedVariablesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoUndefinedVariables(context);
}

final class _NoUndefinedVariables(final ValidationContext context)
    extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    final declared = {
      for (final definition in operation.variableDefinitions)
        definition.variable.name.value,
    };
    final operationName = operation.name?.value;
    for (final usage in context.recursiveVariableUsages(operation)) {
      final name = usage.node.name.value;
      if (declared.contains(name)) {
        continue;
      }
      context.report(
        .noUndefinedVariables,
        operationName == null
            ? 'Variable "\$$name" is not defined.'
            : 'Variable "\$$name" is not defined by operation '
                  '"$operationName".',
        [usage.node, operation],
      );
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/no_unused_variables_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'operation_visitor.dart';

/// Spec §5.8.4 "All Variables Used": every variable an operation declares
/// is used by it, directly or through fragments (`GQL228`).
///
/// Reported when the walk leaves the document, operation by operation.
///
/// {@category validation}
final class const NoUnusedVariablesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoUnusedVariables(context);
}

final class _NoUnusedVariables(final ValidationContext context)
    extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    final used = {
      for (final usage in context.recursiveVariableUsages(operation))
        usage.node.name.value,
    };
    final operationName = operation.name?.value;
    for (final definition in operation.variableDefinitions) {
      final name = definition.variable.name.value;
      if (used.contains(name)) {
        continue;
      }
      context.report(
        .noUnusedVariables,
        operationName == null
            ? 'Variable "\$$name" is never used.'
            : 'Variable "\$$name" is never used in operation '
                  '"$operationName".',
        [definition],
      );
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/operation_visitor.dart`:

```dart
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';

/// A rule visitor that checks each operation once the walk left the
/// document, when the fragment closures of the operations are known.
///
/// Operations are checked in document order, which is graphql-js's order
/// within a rule.
abstract base class OperationVisitor extends AstVisitor {
  final List<OperationDefinition> _operations = [];

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case final OperationDefinition operation:
        _operations.add(operation);
        return .skip;
      case FragmentDefinition():
        return .skip;
      default:
        return .next;
    }
  }

  @override
  void leave(Node node) {
    if (node is Document) {
      _operations.forEach(checkOperation);
    }
  }

  /// Reports the errors of [operation].
  void checkOperation(OperationDefinition operation);
}
```

Create `packages/typed_graphql/lib/src/validation/rules/unique_variable_names_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.8.1 "Variable Uniqueness": an operation declares each variable
/// name once (`GQL225`).
///
/// The error points at the first name and relates to the others.
///
/// {@category validation}
final class const UniqueVariableNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueVariableNames(context);
}

final class _UniqueVariableNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(:final variableDefinitions):
        _check([
          for (final definition in variableDefinitions)
            definition.variable.name,
        ]);
        return .skip;
      case FragmentDefinition():
        return .skip;
      default:
        return .next;
    }
  }

  void _check(List<Name> names) {
    final byName = <String, List<Name>>{};
    for (final name in names) {
      (byName[name.value] ??= []).add(name);
    }
    for (final MapEntry(:key, :value) in byName.entries) {
      if (value.length > 1) {
        context.report(
          .uniqueVariableNames,
          'There can be only one variable named "\$$key".',
          value,
        );
      }
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/rules/variables_in_allowed_position_rule.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import '../variable_usage.dart';
import 'operation_visitor.dart';

/// Spec §5.8.5 "All Variable Usages Are Allowed": a variable's type fits
/// the position it is used in (`GQL229`).
///
/// A nullable variable may stand where a non-null type is expected when
/// the variable or the position has a default value; a field of a `@oneOf`
/// input object takes only a non-null variable. Reported when the walk
/// leaves the document, operation by operation.
///
/// {@category validation}
final class const VariablesInAllowedPositionRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _VariablesInAllowedPosition(context);
}

final class _VariablesInAllowedPosition(final ValidationContext context)
    extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    // The last definition of a repeated name wins, as graphql-js's map.
    final definitions = {
      for (final definition in operation.variableDefinitions)
        definition.variable.name.value: definition,
    };
    for (final usage in context.recursiveVariableUsages(operation)) {
      final definition = definitions[usage.node.name.value];
      final position = usage.type;
      if (definition != null && position != null) {
        _checkUsage(definition, usage, position);
      }
    }
  }

  void _checkUsage(
    VariableDefinition definition,
    VariableUsage usage,
    TypeRef position,
  ) {
    final variableType = definition.type;
    // An unknown type is left to KnownTypeNamesRule.
    if (context.schema.namedTypeOf(variableType) == null) {
      return;
    }
    final name = usage.node.name.value;
    final nodes = [definition, usage.node];
    if (!_isAllowed(definition, usage, position)) {
      context.report(
        .variablesInAllowedPosition,
        'Variable "\$$name" of type "${_print(variableType)}" used in '
        'position expecting type "${_print(position)}".',
        nodes,
      );
    }
    if (usage.parentType case final NamedType parent
        when _isOneOf(parent) && variableType is! NonNullType) {
      context.report(
        .variablesInAllowedPosition,
        'Variable "\$$name" is of type "${_print(variableType)}" but must be '
        'non-nullable to be used for OneOf Input Object "${_print(parent)}".',
        nodes,
      );
    }
  }

  // graphql-js's allowedVariableUsage; a @oneOf field is checked apart, for
  // its more descriptive message.
  bool _isAllowed(
    VariableDefinition definition,
    VariableUsage usage,
    TypeRef position,
  ) {
    final variableType = definition.type;
    if (position is NonNullType && variableType is! NonNullType) {
      final hasVariableDefault =
          definition.defaultValue != null &&
          definition.defaultValue is! NullValue;
      if (!hasVariableDefault && usage.defaultValue == null) {
        return false;
      }
      return context.schema.isTypeSubTypeOf(variableType, position.type);
    }
    return context.schema.isTypeSubTypeOf(variableType, position);
  }

  bool _isOneOf(NamedType type) {
    if (context.schema.typeNamed(type.name.value) case InputObjectType(
      :final isOneOf,
    )) {
      return isOneOf;
    }
    return false;
  }

  String _print(TypeRef type) => const Printer().print(type);
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -102,7 +102,9 @@ export 'src/validation/rules/known_operation_types_rule.dart';
 export 'src/validation/rules/known_type_names_rule.dart';
 export 'src/validation/rules/lone_anonymous_operation_rule.dart';
 export 'src/validation/rules/no_fragment_cycles_rule.dart';
+export 'src/validation/rules/no_undefined_variables_rule.dart';
 export 'src/validation/rules/no_unused_fragments_rule.dart';
+export 'src/validation/rules/no_unused_variables_rule.dart';
 export 'src/validation/rules/possible_fragment_spreads_rule.dart';
 export 'src/validation/rules/provided_required_arguments_rule.dart';
 export 'src/validation/rules/scalar_leafs_rule.dart';
@@ -112,8 +114,10 @@ export 'src/validation/rules/unique_directives_per_location_rule.dart';
 export 'src/validation/rules/unique_fragment_names_rule.dart';
 export 'src/validation/rules/unique_input_field_names_rule.dart';
 export 'src/validation/rules/unique_operation_names_rule.dart';
+export 'src/validation/rules/unique_variable_names_rule.dart';
 export 'src/validation/rules/values_of_correct_type_rule.dart';
 export 'src/validation/rules/variables_are_input_types_rule.dart';
+export 'src/validation/rules/variables_in_allowed_position_rule.dart';
 export 'src/validation/type_info.dart';
 export 'src/validation/validation_context.dart';
 export 'src/validation/validation_rule.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -355,3 +355,78 @@ validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directive
 validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives on directive extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
 validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives between directive definitions and extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
 validation/__tests__/UniqueDirectivesPerLocationRule-test.ts,Validate: Directives Are Unique Per Location,duplicate directives between directive extensions,skipped,,SDL validation: the schema validator checks applied directives (M3b)
+validation/__tests__/UniqueVariableNamesRule-test.ts,Validate: Unique variable names,unique variable names,ported,test/validation/unique_variable_names_test.dart,
+validation/__tests__/UniqueVariableNamesRule-test.ts,Validate: Unique variable names,duplicate variable names,ported,test/validation/unique_variable_names_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,all variables defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,all variables deeply defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,all variables deeply in inline fragments defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,all variables in fragments deeply defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable within single fragment defined in multiple operations,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable within fragments defined in operations,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable within recursive fragment defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable not defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable not defined by un-named query,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,multiple variables not defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable in fragment not defined by un-named query,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable in fragment not defined by operation,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,multiple variables in fragments not defined,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,single variable in fragment not defined by multiple operations,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variables in fragment not defined by multiple operations,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variable in fragment used by other operation,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,multiple undefined variables produce multiple errors,ported,test/validation/no_undefined_variables_test.dart,
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,fragment defined arguments are not undefined variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,defined variables used as fragment arguments are not undefined variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variables used as fragment arguments may be undefined variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/NoUndefinedVariablesRule-test.ts,Validate: No undefined variables,variables shadowed by parent fragment arguments are still undefined variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,uses all variables,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,uses all variables deeply,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,uses all variables deeply in inline fragments,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,uses all variables in fragments,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,variable used by fragment in multiple operations,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,variable used by recursive fragment,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,variable not used,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,multiple variables not used,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,variable not used in fragments,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,multiple variables not used in fragments,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,variable not used by unreferenced fragment,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,variable not used by fragment used by other operation,ported,test/validation/no_unused_variables_test.dart,
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,fragment defined arguments are not unused variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,defined variables used as fragment arguments are not unused variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/NoUnusedVariablesRule-test.ts,Validate: No unused variables,unused fragment variables are reported,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Boolean => Boolean,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Boolean => Boolean within fragment,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Boolean! => Boolean,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Boolean! => Boolean within fragment,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,[String] => [String],ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,[String!] => [String],ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,String => [String] in item position,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,String! => [String] in item position,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,ComplexInput => ComplexInput,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,ComplexInput => ComplexInput in field position,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Boolean! => Boolean! in directive,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Int => Int!,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Int => Int! within fragment,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Int => Int! within nested fragment,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,String over Boolean,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,String => [String],ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,Boolean => Boolean! in directive,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,String => Boolean! in directive,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions,[String] => [String!],ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Allows optional (nullable) variables with default values,Int => Int! fails when variable provides null default value,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Allows optional (nullable) variables with default values,Int => Int! when variable provides non-null default value,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Allows optional (nullable) variables with default values,Int => Int! when optional argument provides default value,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Allows optional (nullable) variables with default values,Boolean => Boolean! in directive with default value with option,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Allows optional (nullable) variables with default values,undefined in directive with default value with option,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Validates OneOf Input Objects,Allows exactly one non-nullable variable,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Validates OneOf Input Objects,Forbids one nullable variable,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Fragment arguments are validated,validates fragment variables defined before the operation,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Fragment arguments are validated,Boolean => Boolean,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Fragment arguments are validated,Boolean => Boolean with default value,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Fragment arguments are validated,Boolean => Boolean!,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Fragment arguments are validated,Int => Int! fails when variable provides null default value,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validate: Variables are in allowed positions > Fragment arguments are validated,Int fragment arg => Int! field arg fails even when shadowed by Int! variable,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validates OneOf Input Objects,Allows exactly one non-nullable variable,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validates OneOf Input Objects,Undefined variable in oneOf input object,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validates OneOf Input Objects,Forbids one nullable variable,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Non-specified behavior of variables within custom scalars,Allows using variables inside object literal in custom scalar,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/VariablesInAllowedPositionRule-test.ts,Non-specified behavior of variables within custom scalars,Allows using variables inside list literal in custom scalar,ported,test/validation/variables_in_allowed_position_test.dart,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/variable_rules_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/no_undefined_variables_test.dart test/validation/no_unused_variables_test.dart test/validation/unique_variable_names_test.dart test/validation/variables_in_allowed_position_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The variable rules: `UniqueVariableNamesRule`, `NoUndefinedVariablesRule`,
  `NoUnusedVariablesRule` and `VariablesInAllowedPositionRule`
  (`GQL225`, `GQL227`-`GQL229`).
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/rules/no_undefined_variables_rule.dart packages/typed_graphql/lib/src/validation/rules/no_unused_variables_rule.dart packages/typed_graphql/lib/src/validation/rules/operation_visitor.dart packages/typed_graphql/lib/src/validation/rules/unique_variable_names_rule.dart packages/typed_graphql/lib/src/validation/rules/variables_in_allowed_position_rule.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/variable_rules_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/no_undefined_variables_test.dart packages/typed_graphql_conformance/test/validation/no_unused_variables_test.dart packages/typed_graphql_conformance/test/validation/unique_variable_names_test.dart packages/typed_graphql_conformance/test/validation/variables_in_allowed_position_test.dart
git commit -q -m "feat(typed_graphql): add the variable rules of operation validation" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: Field selection merging

`OverlappingFieldsCanBeMergedRule` (`GQL206`) over `validation/overlap/`, as spec section 6 describes: roots are the operations and the fragments no earlier root expanded; items grouped by response name, split by shape and by name and arguments, paired with the first item of every other class; pairs judged at their nearest distinct ancestors; reports nested and ordered as graphql-js orders them. `ValidationContext` gains `maxErrors`. The four ported suites (one row `adapted`).

**Files:**
- Create: `packages/typed_graphql/lib/src/validation/overlap/argument_text.dart`, `packages/typed_graphql/lib/src/validation/overlap/conflict_judge.dart`, `packages/typed_graphql/lib/src/validation/overlap/conflict_reports.dart`, `packages/typed_graphql/lib/src/validation/overlap/conflict_tree.dart`, `packages/typed_graphql/lib/src/validation/overlap/field_conflict.dart`, `packages/typed_graphql/lib/src/validation/overlap/field_merging.dart`, `packages/typed_graphql/lib/src/validation/overlap/field_origin.dart`, `packages/typed_graphql/lib/src/validation/overlap/field_shape.dart`, `packages/typed_graphql/lib/src/validation/overlap/fragment_path.dart`, `packages/typed_graphql/lib/src/validation/overlap/fragment_trail.dart`, `packages/typed_graphql/lib/src/validation/overlap/merge_item.dart`, `packages/typed_graphql/lib/src/validation/overlap/merge_split.dart`, `packages/typed_graphql/lib/src/validation/overlap/merge_work.dart`, `packages/typed_graphql/lib/src/validation/overlap/selection_collector.dart`, `packages/typed_graphql/lib/src/validation/rules/overlapping_fields_can_be_merged_rule.dart`
- Modify: `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/validation/document_validator.dart`, `packages/typed_graphql/lib/src/validation/validation_context.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/rules/field_merging_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/overlapping_fields_can_be_merged_test.dart`, `packages/typed_graphql_conformance/test/validation/overlapping_fields_deep_conflicts_test.dart`, `packages/typed_graphql_conformance/test/validation/overlapping_fields_recursive_fragments_test.dart`, `packages/typed_graphql_conformance/test/validation/overlapping_fields_return_types_test.dart`

**Interfaces:**
- Consumes: Task 2 (`ValidationContext.spend`, `TypeInfo.parentType`), Task 3.
- Produces:
- Diagnostic codes: `GQL206`.
- Declarations (signatures as committed; the code is in the steps):

```dart
// validation/overlap/argument_text.dart
final class ArgumentText
  ArgumentText()
  String of(Field field)

// validation/overlap/conflict_judge.dart
final class ConflictJudge(…)
  FieldConflict? judge((MergeItem, MergeItem) pair)

// validation/overlap/conflict_reports.dart
final class ConflictReports(…)
  bool get isFull
  void add(FieldConflict conflict)
  void flush()

// validation/overlap/conflict_tree.dart
final class ConflictTree
  ConflictTree(FieldConflict conflict, this.sequence)
  final int position
  final int sequence
  void add(FieldConflict conflict)
  String get message
  List<Node> get nodes
final class _Pair(final Field first, final Field second)
  String? reason
  _Pair child(Field one, Field other)

// validation/overlap/field_conflict.dart
final class FieldConflict(…)
  FieldConflict get swapped

// validation/overlap/field_merging.dart
final class FieldMerging(…)
  void check()
final class _RootMerge(…)
  void visit(List<_Step> steps, MergeWork work, ConflictReports reports)
  void descend(
sealed class _Step
final class _Enter(final List<String> fragments) extends _Step;
final class _Leave(final List<String> fragments) extends _Step;
final class _Visit(final MergeWork work) extends _Step;

// validation/overlap/field_origin.dart
final class const FieldOrigin(…)

// validation/overlap/field_shape.dart
final class const FieldShape(…)
  String? of(SchemaField? definition)

// validation/overlap/fragment_path.dart
final class FragmentPath
  FragmentPath()
  bool contains(String name)
  void enter(List<String> names)
  void leave(List<String> names)

// validation/overlap/fragment_trail.dart
final class FragmentTrail
  const FragmentTrail._root() : name = null, outer = null, length = 0
  FragmentTrail._(String this.name, FragmentTrail this.outer)
  final String? name
  final FragmentTrail? outer
  final int length
  FragmentTrail inside(String fragment)
  static String? innermostShared(FragmentTrail first, FragmentTrail second)

// validation/overlap/merge_item.dart
final class MergeItem(…)
  String get responseName

// validation/overlap/merge_split.dart
final class MergeSplit(…)

// validation/overlap/merge_work.dart
final class const MergeWork(…)

// validation/overlap/selection_collector.dart
final class SelectionCollector(…)

// validation/rules/overlapping_fields_can_be_merged_rule.dart
final class const OverlappingFieldsCanBeMergedRule() extends ValidationRule
  AstVisitor createVisitor(ValidationContext context)
final class _OverlappingFields(final ValidationContext context)
  VisitAction enter(Node node)
  void leave(Node node)

// validation/validation_context.dart
  int get maxErrors
```

- [ ] **Step 1: Write the tests**

Create `packages/typed_graphql/test/validation/rules/field_merging_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../checked.dart';

// graphql-js's suite of this rule is ported in typed_graphql_conformance;
// these tests pin the code, the documented differences and the bounds.
void main() {
  final checked = Checked('''
type Query { dog: Dog pet: Pet name: String }
interface Pet { name: String }
type Dog implements Pet { name: String nickname: String mother: Dog father: Dog }
type Cat implements Pet { name: String meows: Boolean }
''');
  const rules = [OverlappingFieldsCanBeMergedRule()];

  // `dog { mother { mother { ... x: leaf } } }`, [depth] fields deep, built
  // in code: the parser's depth limit would refuse it as text.
  Field chain(int depth, String leaf) {
    var field = Field(const Name('x'), Name(leaf));
    for (var level = 0; level < depth; level++) {
      field = Field(
        null,
        const Name('mother'),
        selectionSet: SelectionSet([field]),
      );
    }
    return Field(null, const Name('dog'), selectionSet: SelectionSet([field]));
  }

  test('two fields with one response name and different targets are '
      'GQL206', () {
    expect(checked.errors('{ dog { x: name x: nickname } }', rules), [
      '1:9 GQL206 Fields "x" conflict because "name" and "nickname" are '
          'different fields. Use different aliases on the fields to fetch '
          'both if this was intentional.',
    ]);
  });

  test('a field is compared with the first field of each other class '
      'only', () {
    // graphql-js reports the father against both mothers; comparing each
    // field with the first of every other class keeps the work linear.
    expect(
      checked.errors(
        '{ dog { p: mother { name } p: mother { nickname } p: father { name } } }',
        rules,
      ),
      hasLength(1),
    );
  });

  test('a conflict 100000 fields deep is reported at the top pair', () {
    final document = Document([
      OperationDefinition(
        .query,
        SelectionSet([chain(100000, 'name'), chain(100000, 'nickname')]),
      ),
    ]);
    final diagnostics = const DocumentValidator(
      rules: rules,
    ).validate(checked.schema, document).diagnostics;
    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single.message,
      endsWith(
        'subfields "x" conflict because "name" and "nickname" are '
        'different fields. Use different aliases on the fields to fetch '
        'both if this was intentional.',
      ),
    );
  });

  test('100000 fields with one response name merge in linear time', () {
    final fields = List.filled(100000, 'name').join(' ');
    final stopwatch = Stopwatch()..start();
    expect(checked.errors('{ dog { $fields } }', rules), isEmpty);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('fields that conflict only through a recursive fragment end', () {
    expect(
      checked.errors(
        '{ dog { ...F } } fragment F on Dog { x: name mother { ...F } }',
        rules,
      ),
      isEmpty,
    );
  });

  test('a conflict inside a fragment spread twice is reported once, at '
      'the fragment', () {
    expect(
      checked.errors(
        'query A { dog { ...F } } query B { dog { ...F } } '
        'fragment F on Dog { x: name x: nickname }',
        rules,
      ),
      [
        '1:71 GQL206 Fields "x" conflict because "name" and "nickname" are '
            'different fields. Use different aliases on the fields to fetch '
            'both if this was intentional.',
      ],
    );
  });

  test('a chain of fragments is merged once, not once per fragment', () {
    final fragments = List.generate(
      1000,
      (index) => 'fragment F$index on Dog { name ...F${index + 1} }',
    ).join(' ');
    final result = checked.validate(
      '{ dog { ...F0 } } $fragments fragment F1000 on Dog { name }',
      validator: const DocumentValidator(rules: rules, maxSteps: 10000),
    );
    expect(result, isA<ValidDocument>());
  });

  test('a document that expands beyond the step budget is GQL230', () {
    final result = checked.validate(
      '{ dog { ...A ...A } } fragment A on Dog { name nickname }',
      validator: const DocumentValidator(rules: rules, maxSteps: 2),
    );
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -97,6 +97,7 @@ void main() {
         'validation/__tests__/NoUndefinedVariablesRule-test.ts',
         'validation/__tests__/NoUnusedFragmentsRule-test.ts',
         'validation/__tests__/NoUnusedVariablesRule-test.ts',
+        'validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts',
         'validation/__tests__/PossibleFragmentSpreadsRule-test.ts',
         'validation/__tests__/ProvidedRequiredArgumentsRule-test.ts',
         'validation/__tests__/ScalarLeafsRule-test.ts',
```

Create `packages/typed_graphql_conformance/test/validation/overlapping_fields_can_be_merged_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the main describe block, up to the deep conflicts); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    test('unique fields', () {
      expect(
        port.errors('''
      fragment uniqueFields on Dog {
        name
        nickname
      }
    '''),
        isEmpty,
      );
    });

    test('identical fields', () {
      expect(
        port.errors('''
      fragment mergeIdenticalFields on Dog {
        name
        name
      }
    '''),
        isEmpty,
      );
    });

    test('identical fields with identical args', () {
      expect(
        port.errors('''
      fragment mergeIdenticalFieldsWithIdenticalArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        isEmpty,
      );
    });

    test('identical fields with identical directives', () {
      expect(
        port.errors('''
      fragment mergeSameFieldsWithSameDirectives on Dog {
        name @include(if: true)
        name @include(if: true)
      }
    '''),
        isEmpty,
      );
    });

    test('different args with different aliases', () {
      expect(
        port.errors('''
      fragment differentArgsWithDifferentAliases on Dog {
        knowsSit: doesKnowCommand(dogCommand: SIT)
        knowsDown: doesKnowCommand(dogCommand: DOWN)
      }
    '''),
        isEmpty,
      );
    });

    test('different directives with different aliases', () {
      expect(
        port.errors('''
      fragment differentDirectivesWithDifferentAliases on Dog {
        nameIfTrue: name @include(if: true)
        nameIfFalse: name @include(if: false)
      }
    '''),
        isEmpty,
      );
    });

    test('different skip/include directives accepted', () {
      // Note: Differing skip/include directives don't create an ambiguous return
      // value and are acceptable in conditions where differing runtime values
      // may have the same desired effect of including or skipping a field.
      expect(
        port.errors('''
      fragment differentDirectivesWithDifferentAliases on Dog {
        name @include(if: true)
        name @include(if: false)
      }
    '''),
        isEmpty,
      );
    });

    test('Same aliases with different field targets', () {
      expect(
        port.errors('''
      fragment sameAliasesWithDifferentFieldTargets on Dog {
        fido: name
        fido: nickname
      }
    '''),
        [
          'Fields "fido" conflict because "name" and "nickname" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('Same aliases allowed on non-overlapping fields', () {
      // This is valid since no object can be both a "Dog" and a "Cat", thus
      // these fields can never overlap.
      expect(
        port.errors('''
      fragment sameAliasesWithDifferentFieldTargets on Pet {
        ... on Dog {
          name
        }
        ... on Cat {
          name: nickname
        }
      }
    '''),
        isEmpty,
      );
    });

    test('Alias masking direct field access', () {
      expect(
        port.errors('''
      fragment aliasMaskingDirectFieldAccess on Dog {
        name: nickname
        name
      }
    '''),
        [
          'Fields "name" conflict because "nickname" and "name" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('different args, second adds an argument', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand
        doesKnowCommand(dogCommand: HEEL)
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('different args, second missing an argument', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
        doesKnowCommand
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('different args, first has two, second missing one', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand(dogCommand: SIT, atExpertLevel: true)
        doesKnowCommand(dogCommand: SIT)
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('conflicting arg values', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        doesKnowCommand(dogCommand: SIT)
        doesKnowCommand(dogCommand: HEEL)
      }
    '''),
        [
          'Fields "doesKnowCommand" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('conflicting arg names', () {
      expect(
        port.errors('''
      fragment conflictingArgs on Dog {
        isAtLocation(x: 0)
        isAtLocation(y: 0)
      }
    '''),
        [
          'Fields "isAtLocation" conflict because they have differing arguments. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:9',
        ],
      );
    });

    test('allows different args where no conflict is possible', () {
      // This is valid since no object can be both a "Dog" and a "Cat", thus
      // these fields can never overlap.
      expect(
        port.errors('''
      fragment conflictingArgs on Pet {
        ... on Dog {
          name(surname: true)
        }
        ... on Cat {
          name
        }
      }
    '''),
        isEmpty,
      );
    });

    test('allows different order of args', () {
      const schema = '''
      type Query {
        someField(a: String, b: String): String
      }
    ''';

      // This is valid since arguments are unordered, see:
      // https://spec.graphql.org/draft/#sec-Language.Arguments.Arguments-are-unordered
      expect(
        port.withSchema(schema).errors('''
        {
          someField(a: null, b: null)
          someField(b: null, a: null)
        }
      '''),
        isEmpty,
      );
    });

    test('allows different order of input object fields in arg values', () {
      const schema = '''
      input SomeInput {
        a: String
        b: String
      }

      type Query {
        someField(arg: SomeInput): String
      }
    ''';

      // This is valid since input object fields are unordered, see:
      // https://spec.graphql.org/draft/#sec-Input-Object-Values.Input-object-fields-are-unordered
      expect(
        port.withSchema(schema).errors('''
        {
          someField(arg: { a: null, b: null })
          someField(arg: { b: null, a: null })
        }
      '''),
        isEmpty,
      );
    });

    test('encounters conflict in fragments', () {
      expect(
        port.errors('''
      {
        ...A
        ...B
      }
      fragment A on Type {
        x: a
      }
      fragment B on Type {
        x: b
      }
    '''),
        [
          'Fields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 7:9 10:9',
        ],
      );
    });

    test('reports each conflict once', () {
      expect(
        port.errors('''
      {
        f1 {
          ...A
          ...B
        }
        f2 {
          ...B
          ...A
        }
        f3 {
          ...A
          ...B
          x: c
        }
      }
      fragment A on Type {
        x: a
      }
      fragment B on Type {
        x: b
      }
    '''),
        [
          'Fields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 18:9 21:9',
          'Fields "x" conflict because "c" and "a" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 14:11 18:9',
          'Fields "x" conflict because "c" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 14:11 21:9',
        ],
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/overlapping_fields_deep_conflicts_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the main describe block, from the deep conflicts on); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    test('deep conflict', () {
      expect(
        port.errors('''
      {
        field {
          x: a
        },
        field {
          x: b
        }
      }
    '''),
        [
          'Fields "field" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 6:9 7:11',
        ],
      );
    });

    test('deep conflict with multiple issues', () {
      expect(
        port.errors('''
      {
        field {
          x: a
          y: c
        },
        field {
          x: b
          y: d
        }
      }
    '''),
        [
          'Fields "field" conflict because subfields "x" conflict because "a" and "b" are different fields and subfields "y" conflict because "c" and "d" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 5:11 7:9 8:11 9:11',
        ],
      );
    });

    test('does not compare subfields of incompatible parent calls', () {
      expect(
        port.errors('''
      fragment incompatibleParents on Dog {
        parent: mother {
          value: name
        }
        parent: father {
          value: mother { name }
        }
      }
    '''),
        [
          'Fields "parent" conflict because "mother" and "father" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 6:9',
        ],
      );
    });

    test('still compares subfields of each compatible parent-call group', () {
      // Adapted (M4 spec deviation 4): the father is compared with the
      // first mother only, which keeps the work linear, and the conflicts
      // found in one selection set come in discovery order.
      expect(
        port.errors('''
      fragment mixedParents on Dog {
        parent: mother {
          value: name
        }
        parent: mother {
          value: mother { name }
        }
        parent: father { name }
      }
    '''),
        [
          'Fields "parent" conflict because "mother" and "father" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 9:9',
          'Fields "parent" conflict because subfields "value" conflict because "name" and "mother" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 6:9 7:11',
        ],
      );
    });

    test('very deep conflict', () {
      expect(
        port.errors('''
      {
        field {
          deepField {
            x: a
          }
        },
        field {
          deepField {
            x: b
          }
        }
      }
    '''),
        [
          'Fields "field" conflict because subfields "deepField" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 4:11 5:13 8:9 9:11 10:13',
        ],
      );
    });

    test('reports deep conflict to nearest common ancestor', () {
      expect(
        port.errors('''
      {
        field {
          deepField {
            x: a
          }
          deepField {
            x: b
          }
        },
        field {
          deepField {
            y
          }
        }
      }
    '''),
        [
          'Fields "deepField" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 4:11 5:13 7:11 8:13',
        ],
      );
    });

    test('reports deep conflict to nearest common ancestor in fragments', () {
      expect(
        port.errors('''
      {
        field {
          ...F
        }
        field {
          ...F
        }
      }
      fragment F on T {
        deepField {
          deeperField {
            x: a
          }
          deeperField {
            x: b
          }
        },
        deepField {
          deeperField {
            y
          }
        }
      }
    '''),
        [
          'Fields "deeperField" conflict because subfields "x" conflict because "a" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 12:11 13:13 15:11 16:13',
        ],
      );
    });

    test('reports deep conflict in nested fragments', () {
      expect(
        port.errors('''
      {
        field {
          ...I
        }
        field {
          ...F
        }
      }
      fragment F on T {
        x: a
        ...G
      }
      fragment G on T {
        y: c
      }
      fragment I on T {
        y: d
        ...J
      }
      fragment J on T {
        x: b
      }
    '''),
        [
          'Fields "field" conflict because subfields "y" conflict because "d" and "c" are different fields and subfields "x" conflict because "b" and "a" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 18:9 22:9 6:9 15:9 11:9',
        ],
      );
    });

    test('reports deep conflict after nested fragments', () {
      expect(
        port.errors('''
      fragment F on T {
        ...G
      }
      fragment G on T {
        ...H
      }
      fragment H on T {
        x: a
      }
      {
        x: b
        ...F
      }
    '''),
        [
          'Fields "x" conflict because "b" and "a" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 12:9 9:9',
        ],
      );
    });

    test('ignores unknown fragments', () {
      expect(
        port.errors('''
      {
        field
        ...Unknown
        ...Known
      }

      fragment Known on T {
        field
        ...OtherUnknown
      }
    '''),
        isEmpty,
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/overlapping_fields_recursive_fragments_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the recursive fragment tests); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    test('does not infinite loop on recursive fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
      }

      fragment fragA on Human { name, relatives { name, ...fragA } }
    '''),
        isEmpty,
      );
    });

    test('does not infinite loop on immediately recursive fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
      }

      fragment fragA on Human { name, ...fragA }
    '''),
        isEmpty,
      );
    });

    test('does not infinite loop on recursive fragment with a field named after fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
        fragA
      }

      fragment fragA on Query { ...fragA }
    '''),
        isEmpty,
      );
    });

    test('finds invalid cases even with field named after fragment', () {
      expect(
        port.errors('''
      {
        fragA
        ...fragA
      }

      fragment fragA on Type {
        fragA: b
      }
    '''),
        [
          'Fields "fragA" conflict because "fragA" and "b" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 3:9 8:9',
        ],
      );
    });

    test('does not infinite loop on transitively recursive fragment', () {
      expect(
        port.errors('''
      {
        ...fragA
        fragB
      }

      fragment fragA on Human { name, ...fragB }
      fragment fragB on Human { name, ...fragC }
      fragment fragC on Human { name, ...fragA }
    '''),
        isEmpty,
      );
    });

    test('finds invalid case even with immediately recursive fragment', () {
      expect(
        port.errors('''
      fragment sameAliasesWithDifferentFieldTargets on Dog {
        ...sameAliasesWithDifferentFieldTargets
        fido: name
        fido: nickname
      }
    '''),
        [
          'Fields "fido" conflict because "name" and "nickname" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 4:9 5:9',
        ],
      );
    });

    test(
      'does not infinite loop on recursive fragments separated by fields',
      () {
        expect(
          port.errors('''
      {
        ...fragA
        ...fragB
      }

      fragment fragA on T {
        x {
          ...fragA
          x {
            ...fragA
          }
        }
      }

      fragment fragB on T {
        x {
          ...fragB
          x {
            ...fragB
          }
        }
      }
    '''),
          isEmpty,
        );
      },
    );
  });
}
```

Create `packages/typed_graphql_conformance/test/validation/overlapping_fields_return_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js
// src/validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts
// (the describe block 'return types must be unambiguous'); mapping/validation.csv says which tests
// are adapted or skipped, and why.
void main() {
  final port = RulePort(const OverlappingFieldsCanBeMergedRule());

  group('Validate: Overlapping fields can be merged', () {
    group('return types must be unambiguous', () {
      final boxes = port.withSchema('''
      interface SomeBox {
        deepBox: SomeBox
        unrelatedField: String
      }

      type StringBox implements SomeBox {
        scalar: String
        deepBox: StringBox
        unrelatedField: String
        listNode: [Node]
        listStringBox: [StringBox]
        stringBox: StringBox
        intBox: IntBox
      }

      type IntBox implements SomeBox {
        scalar: Int
        deepBox: IntBox
        unrelatedField: String
        node: Node
        listStringBox: [StringBox]
        stringBox: StringBox
        intBox: IntBox
      }

      interface NonNullStringBox1 {
        scalar: String!
      }

      type NonNullStringBox1Impl implements SomeBox & NonNullStringBox1 {
        scalar: String!
        unrelatedField: String
        deepBox: SomeBox
      }

      interface NonNullStringBox2 {
        scalar: String!
      }

      type NonNullStringBox2Impl implements SomeBox & NonNullStringBox2 {
        scalar: String!
        unrelatedField: String
        deepBox: SomeBox
      }

      type Connection {
        edges: [Edge]
      }

      type Edge {
        node: Node
      }

      type Node {
        id: ID
        name: String
      }

      type Query {
        someBox: SomeBox
        connection: Connection
      }
    ''');

      test('conflicting return types which potentially overlap', () {
        // This is invalid since an object could potentially be both the Object
        // type IntBox and the interface type NonNullStringBox1. While that
        // condition does not exist in the current schema, the schema could
        // expand in the future to allow this. Thus it is invalid.
        expect(
          boxes.errors('''
          {
            someBox {
              ...on IntBox {
                scalar
              }
              ...on NonNullStringBox1 {
                scalar
              }
            }
          }
        '''),
          [
            'Fields "scalar" conflict because they return conflicting types "Int" and "String!". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
          ],
        );
      });

      test('compatible return shapes on different return types', () {
        // In this case `deepBox` returns `SomeBox` in the first usage, and
        // `StringBox` in the second usage. These return types are not the same!
        // however this is valid because the return *shapes* are compatible.
        expect(
          boxes.errors('''
          {
            someBox {
              ... on SomeBox {
                deepBox {
                  unrelatedField
                }
              }
              ... on StringBox {
                deepBox {
                  unrelatedField
                }
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('disallows differing return types despite no overlap', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                scalar
              }
              ... on StringBox {
                scalar
              }
            }
          }
        '''),
          [
            'Fields "scalar" conflict because they return conflicting types "Int" and "String". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
          ],
        );
      });

      test('does not compare subfields after a response-type conflict', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on StringBox {
                parent: listNode { value: name }
              }
              ... on IntBox {
                parent: node { value: id }
              }
            }
          }
        '''),
          [
            'Fields "parent" conflict because they return conflicting types "[Node]" and "Node". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
          ],
        );
      });

      test('reports correctly when a non-exclusive follows an exclusive', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                deepBox {
                  ...X
                }
              }
            }
            someBox {
              ... on StringBox {
                deepBox {
                  ...Y
                }
              }
            }
            memoed: someBox {
              ... on IntBox {
                deepBox {
                  ...X
                }
              }
            }
            memoed: someBox {
              ... on StringBox {
                deepBox {
                  ...Y
                }
              }
            }
            other: someBox {
              ...X
            }
            other: someBox {
              ...Y
            }
          }
          fragment X on SomeBox {
            scalar
          }
          fragment Y on SomeBox {
            scalar: unrelatedField
          }
        '''),
          [
            'Fields "other" conflict because subfields "scalar" conflict because "scalar" and "unrelatedField" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 31:13 39:13 34:13 42:13',
          ],
        );
      });

      test(
        'disallows differing return type nullability despite no overlap',
        () {
          expect(
            boxes.errors('''
          {
            someBox {
              ... on NonNullStringBox1 {
                scalar
              }
              ... on StringBox {
                scalar
              }
            }
          }
        '''),
            [
              'Fields "scalar" conflict because they return conflicting types "String!" and "String". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 8:17',
            ],
          );
        },
      );

      test('disallows differing return type list despite no overlap', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: listStringBox {
                  scalar
                }
              }
              ... on StringBox {
                box: stringBox {
                  scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "box" conflict because they return conflicting types "[StringBox]" and "StringBox". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 10:17',
          ],
        );

        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: stringBox {
                  scalar
                }
              }
              ... on StringBox {
                box: listStringBox {
                  scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "box" conflict because they return conflicting types "StringBox" and "[StringBox]". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 10:17',
          ],
        );
      });

      test('disallows differing subfields', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: stringBox {
                  val: scalar
                  val: unrelatedField
                }
              }
              ... on StringBox {
                box: stringBox {
                  val: scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "val" conflict because "scalar" and "unrelatedField" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 6:19 7:19',
          ],
        );
      });

      test('disallows differing deep return types despite no overlap', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                box: stringBox {
                  scalar
                }
              }
              ... on StringBox {
                box: intBox {
                  scalar
                }
              }
            }
          }
        '''),
          [
            'Fields "box" conflict because subfields "scalar" conflict because they return conflicting types "String" and "Int". Use different aliases on the fields to fetch both if this was intentional. @ 5:17 6:19 10:17 11:19',
          ],
        );
      });

      test('allows non-conflicting overlapping types', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ... on IntBox {
                scalar: unrelatedField
              }
              ... on StringBox {
                scalar
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('same wrapped scalar return types', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ...on NonNullStringBox1 {
                scalar
              }
              ...on NonNullStringBox2 {
                scalar
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('allows inline fragments without type condition', () {
        expect(
          boxes.errors('''
          {
            a
            ... {
              a
            }
          }
        '''),
          isEmpty,
        );
      });

      test('compares deep types including list', () {
        expect(
          boxes.errors('''
          {
            connection {
              ...edgeID
              edges {
                node {
                  id: name
                }
              }
            }
          }

          fragment edgeID on Connection {
            edges {
              node {
                id
              }
            }
          }
        '''),
          [
            'Fields "edges" conflict because subfields "node" conflict because subfields "id" conflict because "name" and "id" are different fields. Use different aliases on the fields to fetch both if this was intentional. @ 5:15 6:17 7:19 14:13 15:15 16:17',
          ],
        );
      });

      test('ignores unknown types', () {
        expect(
          boxes.errors('''
          {
            someBox {
              ...on UnknownType {
                scalar
              }
              ...on NonNullStringBox2 {
                scalar
              }
            }
          }
        '''),
          isEmpty,
        );
      });

      test('works for field names that are JS keywords', () {
        const schemaWithKeywords = '''
        type Foo {
          constructor: String
        }

        type Query {
          foo: Foo
        }
      ''';

        expect(
          port.withSchema(schemaWithKeywords).errors('''
          {
            foo {
              constructor
            }
          }
        '''),
          isEmpty,
        );
      });
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/field_merging_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/overlapping_fields_can_be_merged_test.dart test/validation/overlapping_fields_deep_conflicts_test.dart test/validation/overlapping_fields_recursive_fragments_test.dart test/validation/overlapping_fields_return_types_test.dart)
```

Expected: FAIL. The test files do not compile: they use the names that the next step adds (`Error: ... isn't defined` or `Member not found`).

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -349,6 +349,11 @@ enum DiagnosticCode(
   /// meta-field (spec §5.3.1).
   fieldsOnCorrectType('GQL205'),
 
+  /// `GQL206`: two fields with one response name that cannot be merged:
+  /// different fields or arguments under one parent, or different
+  /// response shapes (spec §5.3.2).
+  overlappingFieldsCanBeMerged('GQL206'),
+
   /// `GQL207`: a leaf field with a selection, or a composite field without
   /// one (spec §5.3.3).
   scalarLeafs('GQL207'),
```

In `packages/typed_graphql/lib/src/validation/document_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,7 @@ import 'rules/no_fragment_cycles_rule.dart';
 import 'rules/no_undefined_variables_rule.dart';
 import 'rules/no_unused_fragments_rule.dart';
 import 'rules/no_unused_variables_rule.dart';
+import 'rules/overlapping_fields_can_be_merged_rule.dart';
 import 'rules/possible_fragment_spreads_rule.dart';
 import 'rules/provided_required_arguments_rule.dart';
 import 'rules/scalar_leafs_rule.dart';
@@ -100,6 +101,7 @@ final class const DocumentValidator({
     InputObjectRequiredFieldsRule(),
     ProvidedRequiredArgumentsRule(),
     VariablesInAllowedPositionRule(),
+    OverlappingFieldsCanBeMergedRule(),
     UniqueInputFieldNamesRule(),
   ];
 
```

Create `packages/typed_graphql/lib/src/validation/overlap/argument_text.dart`:

```dart
import 'dart:convert';

import '../../language/ast/argument.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/value.dart';

/// A field's arguments as one text that is equal for two fields exactly
/// when graphql-js's `sameArguments` holds: the arguments sorted by name,
/// object fields sorted by name, each value tagged with its kind.
///
/// The text is built with a stack, so a value nested 100000 deep cannot
/// overflow the call stack, and kept per field.
final class ArgumentText {
  /// Creates an empty cache.
  ArgumentText();

  final Map<Field, String> _texts = Map.identity();

  /// The text of [field]'s arguments.
  String of(Field field) => _texts[field] ??= _text(field.arguments);

  String _text(List<Argument> arguments) {
    final sorted = [...arguments]
      ..sort((a, b) => a.name.value.compareTo(b.name.value));
    final pending = <Object>[
      for (final argument in sorted.reversed) ...[
        ',',
        argument.value,
        '${argument.name.value}:',
      ],
    ];
    final buffer = StringBuffer();
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final String text:
          buffer.write(text);
        case final Value value:
          buffer.write(_scalarText(value, pending));
      }
    }
    return buffer.toString();
  }

  /// The text of [value] when it is a scalar; a list or an object puts
  /// its parts on [pending] instead and gives its opening bracket.
  String _scalarText(Value value, List<Object> pending) {
    switch (value) {
      case Variable(:final name):
        return '\$${name.value}';
      case IntValue(:final value):
        return 'i$value';
      case FloatValue(:final value):
        return 'f$value';
      case StringValue(:final value):
        return jsonEncode(value);
      case BooleanValue(:final value):
        return '$value';
      case NullValue():
        return 'null';
      case EnumValue(:final value):
        return 'e$value';
      case ListValue(:final values):
        pending.add(']');
        for (final item in values.reversed) {
          pending.addAll([',', item]);
        }
        return '[';
      case ObjectValue(:final fields):
        final sorted = [...fields]
          ..sort((a, b) => a.name.value.compareTo(b.name.value));
        pending.add('}');
        for (final field in sorted.reversed) {
          pending.addAll([',', field.value, '${field.name.value}:']);
        }
        return '{';
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/conflict_judge.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/printer/printer.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import 'argument_text.dart';
import 'field_conflict.dart';
import 'field_shape.dart';
import 'fragment_trail.dart';
import 'merge_item.dart';

/// Decides whether a pair of fields from one merged set conflicts as
/// graphql-js's `findConflict` would report it.
///
/// The pair is reported for its nearest pair of distinct ancestors, at the
/// selection set graphql-js finds it in: the innermost fragment both are
/// spread through, else their parent field's, else the top of [root]. It
/// is dropped when a pair of ancestors already conflicts, since graphql-js
/// does not compare the subfields of conflicting fields. Mutual exclusion
/// is computed from the ancestors down: once two parents are different
/// object types, names and arguments may differ.
final class ConflictJudge(
  /// The run the work is charged to and reported in.
  final ValidationContext context,

  /// The shapes of the fields' types.
  final FieldShape shapes,

  /// The canonical text of the fields' arguments.
  final ArgumentText arguments,

  /// The operation or fragment whose fields are being merged.
  final ExecutableDefinition root,
) {
  /// Creates the judge of the pairs found while merging [root].
  this;

  static const Printer _printer = Printer();

  /// The conflict of [pair] to report, or null.
  FieldConflict? judge((MergeItem, MergeItem) pair) {
    final (first, second) = _chains(pair);
    if (!context.spend(first.length)) {
      return null;
    }
    var isExclusive = false;
    for (final (index, one) in first.indexed) {
      final other = second[index];
      isExclusive = isExclusive || _areExclusive(one, other);
      final reason = _reason(one, other, isExclusive: isExclusive);
      if (index < first.length - 1 && reason != null) {
        return null;
      }
      if (index == first.length - 1 && reason != null) {
        final reverse = _reason(other, one, isExclusive: isExclusive) ?? '';
        return FieldConflict(
          first,
          second,
          reason,
          reverse,
          _position(first[0], second[0]),
        );
      }
    }
    return null;
  }

  /// The ancestors of the pair up to the nearest distinct pair, from that
  /// pair down to the fields.
  (List<MergeItem>, List<MergeItem>) _chains((MergeItem, MergeItem) pair) {
    final (first, second) = pair;
    final ones = [first];
    final others = [second];
    var (one, other) = (first.parent, second.parent);
    while (one != null && other != null && !identical(one, other)) {
      ones.add(one);
      others.add(other);
      (one, other) = (one.parent, other.parent);
    }
    return (ones.reversed.toList(), others.reversed.toList());
  }

  /// The offset of the selection set where graphql-js finds the conflict
  /// of [one] and [other], two fields of one merged set: the innermost
  /// fragment both are spread through, else their parent field's
  /// selection, else the top of [root]. Definitions do not overlap, so
  /// the offset also orders the reports by definition.
  int _position(MergeItem one, MergeItem other) {
    final shared = switch (FragmentTrail.innermostShared(
      one.trail,
      other.trail,
    )) {
      final String name => context.fragmentNamed(name)?.selectionSet,
      null => one.parent?.node.selectionSet,
    };
    return (shared ??
            switch (root) {
              OperationDefinition(:final selectionSet) => selectionSet,
              FragmentDefinition(:final selectionSet) => selectionSet,
            })
        .start;
  }

  bool _areExclusive(MergeItem one, MergeItem other) =>
      !identical(one.origin.parentType, other.origin.parentType) &&
      one.origin.parentType is ObjectType &&
      other.origin.parentType is ObjectType;

  String? _reason(
    MergeItem one,
    MergeItem other, {
    required bool isExclusive,
  }) {
    if (!isExclusive) {
      final (name, otherName) = (one.node.name.value, other.node.name.value);
      if (name != otherName) {
        return '"$name" and "$otherName" are different fields';
      }
      if (arguments.of(one.node) != arguments.of(other.node)) {
        return 'they have differing arguments';
      }
    }
    if ((one.definition, other.definition) case (final d1?, final d2?)
        when shapes.of(d1) != shapes.of(d2)) {
      return 'they return conflicting types "${_printer.print(d1.type)}" '
          'and "${_printer.print(d2.type)}"';
    }
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/conflict_reports.dart`:

```dart
import '../../language/ast/selection.dart';
import '../validation_context.dart';
import 'conflict_tree.dart';
import 'field_conflict.dart';

/// The conflicts of field merging, one report per pair of distinct
/// ancestors over the whole document (graphql-js memoizes the pairs it
/// compared), reported in graphql-js's order.
final class ConflictReports(
  /// The run the work is charged to and reported in.
  final ValidationContext context,
) {
  /// Creates an empty set of reports.
  this;

  final Map<Field, Map<Field, ConflictTree>> _trees = Map.identity();
  final List<ConflictTree> _pending = [];
  int _count = 0;

  /// Whether as many reports as the run may hold are known, so the
  /// search can stop.
  bool get isFull => _count >= context.maxErrors;

  /// Adds [conflict] to the report of its pair of ancestors, starting
  /// that report when it is new.
  void add(FieldConflict conflict) {
    final (one, other) = (conflict.first[0].node, conflict.second[0].node);
    if (_trees[one]?[other] ?? _trees[other]?[one] case final tree?) {
      tree.add(conflict);
      return;
    }
    final tree = ConflictTree(conflict, _count++);
    (_trees[one] ??= Map.identity())[other] = tree;
    _pending.add(tree);
  }

  /// Reports the reports started since the last flush, ordered by the
  /// selection set graphql-js finds them in (so by definition, as
  /// graphql-js visits them), then by discovery.
  void flush() {
    _pending.sort(
      (a, b) => a.position != b.position
          ? a.position.compareTo(b.position)
          : a.sequence.compareTo(b.sequence),
    );
    for (final tree in _pending) {
      context.report(.overlappingFieldsCanBeMerged, tree.message, tree.nodes);
    }
    _pending.clear();
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/conflict_tree.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import 'field_conflict.dart';

/// One reported conflict of two fields with all the conflicts found
/// between their subfields: graphql-js's nested `Conflict`, as a tree of
/// field pairs whose leaves hold the reasons.
///
/// The message and the nodes are built with stacks, so a conflict 100000
/// levels deep cannot overflow the call stack.
final class ConflictTree {
  /// Starts the tree of [conflict], whose first chain gives the side of
  /// every later conflict; [sequence] orders reports found at one
  /// position.
  ConflictTree(FieldConflict conflict, this.sequence)
    : position = conflict.position,
      _root = _Pair(conflict.first[0].node, conflict.second[0].node) {
    add(conflict);
  }

  /// The offset of the selection set where graphql-js reports it.
  final int position;

  /// The order in which the tree was started.
  final int sequence;

  final _Pair _root;

  /// Adds the pairs of [conflict], whose chains start at this tree's two
  /// fields in either order, and its reason; a pair added before is kept.
  void add(FieldConflict conflict) {
    final oriented = identical(conflict.first[0].node, _root.first)
        ? conflict
        : conflict.swapped;
    var pair = _root;
    for (var level = 1; level < oriented.first.length; level++) {
      pair = pair.child(
        oriented.first[level].node,
        oriented.second[level].node,
      );
    }
    if (pair.children.isEmpty) {
      pair.reason ??= oriented.reason;
    }
  }

  /// graphql-js's message: the response name and the nested reasons.
  String get message {
    final buffer = StringBuffer(
      'Fields "${_responseName(_root.first)}" conflict because ',
    );
    final pending = <Object>[_root];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final String text:
          buffer.write(text);
        case _Pair(:final reason?):
          buffer.write(reason);
        case _Pair(:final children):
          for (final (index, child) in children.indexed.toList().reversed) {
            pending.addAll([
              child,
              'subfields "${_responseName(child.first)}" conflict because ',
              if (index > 0) ' and ',
            ]);
          }
      }
    }
    buffer.write(
      '. Use different aliases on the fields to fetch both if this was '
      'intentional.',
    );
    return buffer.toString();
  }

  /// The fields of the first side in pre-order, then those of the second,
  /// as graphql-js lists a conflict's nodes.
  List<Node> get nodes => [..._side(isFirst: true), ..._side(isFirst: false)];

  List<Field> _side({required bool isFirst}) {
    final fields = <Field>[];
    final pending = [_root];
    while (pending.isNotEmpty) {
      final pair = pending.removeLast();
      fields.add(isFirst ? pair.first : pair.second);
      pending.addAll(pair.children.reversed);
    }
    return fields;
  }

  String _responseName(Field field) => field.alias?.value ?? field.name.value;
}

/// A pair of fields in a [ConflictTree]: a leaf with the reason they
/// conflict, or the pairs of their subfields that do.
final class _Pair(final Field first, final Field second) {
  /// Why the pair conflicts; null while it is not a leaf.
  String? reason;
  final List<_Pair> children = [];
  final Map<Field, Map<Field, _Pair>> _index = Map.identity();

  /// The pair of [one] and [other] under this one, added when new.
  _Pair child(Field one, Field other) {
    final byOther = _index[one] ??= Map.identity();
    if (byOther[other] case final pair?) {
      return pair;
    }
    final pair = _Pair(one, other);
    children.add(pair);
    return byOther[other] = pair;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/field_conflict.dart`:

```dart
import 'merge_item.dart';

/// Two fields that conflict, as graphql-js reports them: the chains of
/// fields from the nearest pair of distinct ancestors down to the pair,
/// the reason the pair conflicts, and where graphql-js finds it.
final class FieldConflict(
  /// The first chain, from the ancestor to the conflicting field.
  final List<MergeItem> first,

  /// The second chain, as long as [first].
  final List<MergeItem> second,

  /// Why the last fields of the chains conflict, such as
  /// `"a" and "b" are different fields`.
  final String reason,

  /// [reason] with the two fields named the other way round.
  final String reverseReason,

  /// The offset of the selection set whose visit reports the conflict in
  /// graphql-js, which orders the reports.
  final int position,
) {
  /// Creates a conflict.
  this;

  /// The same conflict seen from the second chain.
  FieldConflict get swapped =>
      FieldConflict(second, first, reverseReason, reason, position);
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/field_merging.dart`:

```dart
import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../validation_context.dart';
import 'argument_text.dart';
import 'conflict_judge.dart';
import 'conflict_reports.dart';
import 'field_origin.dart';
import 'field_shape.dart';
import 'fragment_path.dart';
import 'merge_item.dart';
import 'merge_split.dart';
import 'merge_work.dart';
import 'selection_collector.dart';

/// Spec §5.3.2 "Field Selection Merging" without comparing every pair of
/// fields (R3.3; XING's algorithm, which Sangria uses).
///
/// Each operation is a root, and so is each fragment that no earlier root
/// expanded: a fragment's own conflicts are found wherever it is
/// expanded, so a chain of fragments is merged once, not once per link
/// (graphql-js checks every fragment again). A root's fields are merged
/// level by level: each set of fields with one response name is split
/// into classes ([MergeSplit]), the pairs that may conflict are judged
/// ([ConflictJudge]) and each class's subfields form the sets of the next
/// level, depth first over an explicit stack. Every field merged and every
/// pair compared charges the step budget.
final class FieldMerging(
  /// The run the work is charged to and reported in.
  final ValidationContext context,
  final Map<Field, FieldOrigin> origins,
) {
  /// Creates the check of the fields [origins] describes.
  this;

  final FieldShape _shapes = FieldShape(context.schema);
  final ArgumentText _arguments = ArgumentText();
  final ConflictReports _reports = ConflictReports(context);
  final Set<String> _expanded = {};

  /// Reports the conflicts of every root.
  void check() {
    for (final definition in context.document.definitions) {
      if (context.isAborted || _reports.isFull) {
        break;
      }
      switch (definition) {
        case FragmentDefinition(:final name)
            when _expanded.contains(name.value):
          continue;
        case final ExecutableDefinition root:
          _checkRoot(root);
      }
    }
    _reports.flush();
  }

  void _checkRoot(ExecutableDefinition root) {
    final path = FragmentPath();
    final SelectionSet selectionSet;
    switch (root) {
      case OperationDefinition():
        selectionSet = root.selectionSet;
      case FragmentDefinition():
        selectionSet = root.selectionSet;
        path.enter([root.name.value]);
    }
    final merge = _RootMerge(
      SelectionCollector(context, origins, path),
      MergeSplit(context, _shapes, _arguments),
      ConflictJudge(context, _shapes, _arguments, root),
    );
    final steps = <_Step>[];
    merge.descend(steps, const MergeWork([]), [(selectionSet, null)]);
    while (steps.isNotEmpty && !context.isAborted && !_reports.isFull) {
      switch (steps.removeLast()) {
        case _Enter(:final fragments):
          path.enter(fragments);
          _expanded.addAll(fragments);
        case _Leave(:final fragments):
          path.leave(fragments);
        case _Visit(:final work):
          merge.visit(steps, work, _reports);
      }
    }
  }
}

/// The merge of one root: its collector, splitter and judge.
final class _RootMerge(
  final SelectionCollector collector,
  final MergeSplit splitter,
  final ConflictJudge judge,
) {
  /// Judges the pairs of [work] into [reports] and puts the sets under
  /// each of its classes on [steps].
  void visit(List<_Step> steps, MergeWork work, ConflictReports reports) {
    final (:pairs, :parts) = splitter.split(work);
    for (final pair in pairs) {
      if (reports.isFull) return;
      if (judge.judge(pair) case final conflict?) reports.add(conflict);
    }
    final descents = [
      for (final part in parts)
        (
          part,
          [
            for (final item in part.items)
              if (item.node.selectionSet case final selectionSet?)
                (selectionSet, item),
          ],
        ),
    ];
    for (final (part, sources) in descents.reversed) {
      descend(steps, part, sources);
    }
  }

  /// Collects the fields of [sources] and puts their sets on [steps],
  /// checked as [part] is, between entering and leaving the fragments
  /// expanded to find them.
  void descend(
    List<_Step> steps,
    MergeWork part,
    List<(SelectionSet, MergeItem?)> sources,
  ) {
    final (:groups, :expanded) = collector.collect(sources);
    steps.add(_Leave(expanded));
    for (final items in groups.values.toList().reversed) {
      steps.add(
        _Visit(
          MergeWork(
            items,
            checksShape: part.checksShape,
            checksNames: part.checksNames,
          ),
        ),
      );
    }
    steps.add(_Enter(expanded));
  }
}

sealed class _Step {}

final class _Enter(final List<String> fragments) extends _Step;

final class _Leave(final List<String> fragments) extends _Step;

final class _Visit(final MergeWork work) extends _Step;
```

Create `packages/typed_graphql/lib/src/validation/overlap/field_origin.dart`:

```dart
import '../../schema/model/schema_type.dart';

/// Where a field is written: the type its selection set selects from, as
/// the walk's type information saw it.
final class const FieldOrigin(
  /// The type the field is selected on; null when it is unknown.
  final SchemaType? parentType,
) {
  /// Creates an origin.
  this;
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/field_shape.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/schema.dart';

/// The shape of a field's type for spec §5.3.2 `SameResponseShape`: its
/// list and non-null wrappers and, inside them, the leaf type's name or
/// `{}` for a composite type.
///
/// Two fields' types conflict, as graphql-js's `doTypesConflict` decides,
/// exactly when their shapes differ.
final class const FieldShape(
  /// The schema the types are in.
  final Schema schema,
) {
  /// Creates the shape reader.
  this;

  /// The shape of [definition]'s type; null without a definition, which
  /// conflicts with nothing.
  String? of(SchemaField? definition) {
    if (definition == null) {
      return null;
    }
    final buffer = StringBuffer();
    var type = definition.type;
    while (true) {
      switch (type) {
        case ListType(type: final item):
          buffer.write('[');
          type = item;
        case NonNullType(type: final nullable):
          buffer.write('!');
          type = nullable;
        case NamedType(:final name):
          final named = schema.typeNamed(name.value);
          buffer.write(named?.isLeafType ?? false ? name.value : '{}');
          return buffer.toString();
      }
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/fragment_path.dart`:

```dart
/// The fragments expanded on the way from the top of a definition to the
/// selection being merged: a fragment on the path is not expanded again,
/// so a recursive fragment ends.
final class FragmentPath {
  /// Creates an empty path.
  FragmentPath();

  final Map<String, int> _counts = {};

  /// Whether the fragment named [name] is on the path.
  bool contains(String name) => _counts.containsKey(name);

  /// Puts [names] on the path.
  void enter(List<String> names) {
    for (final name in names) {
      _counts.update(name, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  /// Takes [names], put there by [enter], off the path.
  void leave(List<String> names) {
    for (final name in names) {
      if (_counts[name] case final count? when count > 1) {
        _counts[name] = count - 1;
      } else {
        _counts.remove(name);
      }
    }
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/fragment_trail.dart`:

```dart
/// The fragments spread between a selection set and a field it selects,
/// innermost first: a shared list, so a chain of fragments 100000 deep
/// costs one link per fragment.
final class FragmentTrail {
  const FragmentTrail._root() : name = null, outer = null, length = 0;

  FragmentTrail._(String this.name, FragmentTrail this.outer)
    : length = outer.length + 1;

  /// No fragment: a field written in the selection set itself.
  static const FragmentTrail empty = FragmentTrail._root();

  /// The innermost fragment; null for [empty].
  final String? name;

  /// The trail without [name]; null for [empty].
  final FragmentTrail? outer;

  /// The number of fragments.
  final int length;

  /// This trail followed by the fragment named [fragment].
  FragmentTrail inside(String fragment) => FragmentTrail._(fragment, this);

  /// The innermost fragment that [first] and [second] both pass through,
  /// from the same spread; null when they share none.
  static String? innermostShared(FragmentTrail first, FragmentTrail second) {
    var (one, other) = (first, second);
    // Trails from one collection share their links, and every trail ends
    // in [empty], so the walk meets.
    while (!identical(one, other)) {
      if (one.length >= other.length) {
        one = one.outer ?? one;
      } else {
        other = other.outer ?? other;
      }
    }
    return one.name;
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/merge_item.dart`:

```dart
import '../../language/ast/selection.dart';
import '../../schema/model/schema_field.dart';
import 'field_origin.dart';
import 'fragment_trail.dart';

/// A field in a merged selection: the node, where it is written, its
/// definition in the schema and the item it is selected under.
///
/// The same node is one item per place it is reached from, so a fragment
/// spread under two fields gives two items with different parents.
final class MergeItem(
  /// The field node.
  final Field node,

  /// Where [node] is written.
  final FieldOrigin origin,

  /// The field of the parent type that [node] selects; null when the
  /// parent type is unknown or not an object or interface type, as
  /// graphql-js's `getFields` lookup (no meta-fields).
  final SchemaField? definition,

  /// The item whose selection set holds [node]; null at the top of an
  /// operation or fragment.
  final MergeItem? parent,

  /// The fragments spread between the parent's selection set and [node].
  final FragmentTrail trail,
) {
  /// Creates an item.
  this;

  /// The key of the field in a response: its alias, else its name.
  String get responseName => node.alias?.value ?? node.name.value;
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/merge_split.dart`:

```dart
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import 'argument_text.dart';
import 'field_shape.dart';
import 'merge_item.dart';
import 'merge_work.dart';

/// Splits a [MergeWork] into classes as XING's linear field-merging
/// algorithm does (the Sangria algorithm, R3.3), and lists the pairs that
/// may conflict.
///
/// Shape classes hold the fields of one response shape; a field without a
/// definition joins every class. Name classes hold the fields that select
/// the same field with the same arguments, within a group of fields whose
/// parent types may be the same object (graphql-js's mutual exclusion):
/// one group per object parent type, a field with another parent joining
/// every group. A field is paired with the first field of each other class
/// seen before it, so the work is the number of fields times the number of
/// classes, not of pairs. Each class is merged further on its own.
final class MergeSplit(
  /// The run the work is charged to and reported in.
  final ValidationContext context,

  /// The shapes of the fields' types.
  final FieldShape shapes,
  final ArgumentText arguments,
) {
  /// Creates the splitter.
  this;

  /// The pairs of [work] that may conflict and the works under it.
  ({List<(MergeItem, MergeItem)> pairs, List<MergeWork> parts}) split(
    MergeWork work,
  ) {
    final pairs = <(MergeItem, MergeItem)>[];
    final items = work.items;
    final byName = [
      if (work.checksNames)
        for (final group in _groups(items))
          ..._classes(group, _nameKeys(group), pairs),
    ];
    final byShape = work.checksShape
        ? _classes(items, [
            for (final item in items) shapes.of(item.definition),
          ], pairs)
        : const <List<MergeItem>>[];
    if (byName case [final names] when names.length == items.length) {
      if (byShape case [final shape] when shape.length == items.length) {
        return (pairs: pairs, parts: [work]);
      }
    }
    return (
      pairs: pairs,
      parts: [
        for (final names in byName) MergeWork(names, checksShape: false),
        for (final shape in byShape) MergeWork(shape, checksNames: false),
      ],
    );
  }

  List<String> _nameKeys(List<MergeItem> group) => [
    for (final item in group)
      '${item.node.name.value}(${arguments.of(item.node)})',
  ];

  /// The groups of [items] whose parent types may be the same object.
  List<List<MergeItem>> _groups(List<MergeItem> items) {
    final objects = Map<SchemaType, void>.identity();
    for (final item in items) {
      if (item.origin.parentType case final ObjectType type) {
        objects[type] = null;
      }
    }
    if (objects.length < 2) {
      return [items];
    }
    return [
      for (final type in objects.keys)
        [
          for (final item in items)
            if (item.origin.parentType case final parent
                when identical(parent, type) || parent is! ObjectType)
              item,
        ],
    ];
  }

  /// The classes of [items] by [keys] (null joins every class), in order
  /// of first appearance; adds to [pairs] each item with the first item of
  /// every other class seen before it.
  List<List<MergeItem>> _classes(
    List<MergeItem> items,
    List<String?> keys,
    List<(MergeItem, MergeItem)> pairs,
  ) {
    final firsts = <String, MergeItem>{};
    for (final (index, item) in items.indexed) {
      if (keys[index] case final key?) {
        if (!context.spend(firsts.length)) break;
        pairs.addAll([
          for (final MapEntry(key: other, value: first) in firsts.entries)
            if (other != key) (first, item),
        ]);
        firsts.putIfAbsent(key, () => item);
      }
    }
    if (firsts.isEmpty) {
      return [items];
    }
    return [
      for (final key in firsts.keys)
        [
          for (final (index, item) in items.indexed)
            if (keys[index] == key || keys[index] == null) item,
        ],
    ];
  }
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/merge_work.dart`:

```dart
import 'merge_item.dart';

/// Fields with one response name at one place, to check together, and
/// which of the two checks of spec §5.3.2 apply to them.
final class const MergeWork(
  /// The fields, in graphql-js's collection order.
  final List<MergeItem> items, {

  /// Whether the fields must have the same response shape
  /// (`SameResponseShape`).
  final bool checksShape = true,

  /// Whether fields with a common parent type must select the same field
  /// with the same arguments (`FieldsInSetCanMerge`).
  final bool checksNames = true,
}) {
  /// Creates the work.
  this;
}
```

Create `packages/typed_graphql/lib/src/validation/overlap/selection_collector.dart`:

```dart
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import 'field_origin.dart';
import 'fragment_path.dart';
import 'fragment_trail.dart';
import 'merge_item.dart';

/// Collects the fields selected under the items of a merged set, as
/// graphql-js's `getFieldsAndFragmentSpreads` collects one selection set:
/// its fields and inline fragments in order, then each spread fragment's
/// fields, depth first.
///
/// A fragment is expanded once per collection and not at all when it is on
/// the [path], so recursive fragments end. Each field charges one step.
final class SelectionCollector(
  /// The run the work is charged to and reported in.
  final ValidationContext context,

  /// The parent type and definition of each field of the document.
  final Map<Field, FieldOrigin> origins,
  final FragmentPath path,
) {
  /// Creates a collector that skips the fragments on [path].
  this;

  /// The fields under [sources] (each a selection set and the item it
  /// belongs to, null at the top of a definition) grouped by response
  /// name in first-seen order, and the fragments expanded to reach them.
  ({Map<String, List<MergeItem>> groups, List<String> expanded}) collect(
    List<(SelectionSet, MergeItem?)> sources,
  ) {
    final groups = <String, List<MergeItem>>{};
    // Insertion-ordered, so the path is entered and left in one order.
    final expanded = <String>{};
    for (final (selectionSet, parent) in sources) {
      final units = [(selectionSet, FragmentTrail.empty)];
      while (units.isNotEmpty && !context.isAborted) {
        final (set, trail) = units.removeLast();
        final spreads = _fields(set, (parent, trail), groups);
        final fragments = _newFragments(spreads, expanded);
        for (final (name, fragmentSet) in fragments.reversed) {
          units.add((fragmentSet, trail.inside(name)));
        }
      }
    }
    return (groups: groups, expanded: expanded.toList());
  }

  /// The fragments of [spreads] to expand, in order: known, not on the
  /// path and not yet in [expanded], to which they are added.
  List<(String, SelectionSet)> _newFragments(
    List<String> spreads,
    Set<String> expanded,
  ) {
    final fragments = <(String, SelectionSet)>[];
    for (final name in spreads) {
      if (path.contains(name) || expanded.contains(name)) continue;
      if (context.fragmentNamed(name) case final fragment?) {
        expanded.add(name);
        fragments.add((name, fragment.selectionSet));
      }
    }
    return fragments;
  }

  /// Adds the fields of [selectionSet] and of its inline fragments to
  /// [groups]; returns the names of the fragments it spreads, in order.
  List<String> _fields(
    SelectionSet selectionSet,
    (MergeItem?, FragmentTrail) place,
    Map<String, List<MergeItem>> groups,
  ) {
    final spreads = <String>[];
    final pending = [...selectionSet.selections.reversed];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final Field field:
          if (_item(field, place) case final item?) {
            (groups[item.responseName] ??= []).add(item);
          }
        case InlineFragment(:final selectionSet):
          pending.addAll(selectionSet.selections.reversed);
        case FragmentSpread(:final name):
          spreads.add(name.value);
      }
    }
    return spreads;
  }

  MergeItem? _item(Field field, (MergeItem?, FragmentTrail) place) {
    final origin = origins[field];
    if (origin == null || !context.spend(1)) {
      return null;
    }
    final (parent, trail) = place;
    return MergeItem(field, origin, _definition(origin, field), parent, trail);
  }

  SchemaField? _definition(FieldOrigin origin, Field field) =>
      switch (origin.parentType) {
        final ObjectType type => type.fieldNamed(field.name.value),
        final InterfaceType type => type.fieldNamed(field.name.value),
        _ => null,
      };
}
```

Create `packages/typed_graphql/lib/src/validation/rules/overlapping_fields_can_be_merged_rule.dart`:

```dart
import '../../language/ast/document.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../overlap/field_merging.dart';
import '../overlap/field_origin.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.3.2 "Field Selection Merging": fields with one response name
/// that may be selected together select the same field with the same
/// arguments, and all fields with that name have the same response shape
/// (`GQL206`).
///
/// graphql-js compares fields pairwise, quadratic in the size of a
/// selection (graphql-js#2185); this rule merges them level by level in
/// linear time (R3.3) and reports each conflicting pair of fields once,
/// with graphql-js's messages, for the nearest pair of distinct
/// ancestors. With three or more conflicting fields of one name, a field
/// is reported against the first field of each other kind, not against
/// every one, so there may be fewer reports than in graphql-js.
///
/// {@category validation}
final class const OverlappingFieldsCanBeMergedRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _OverlappingFields(context);
}

final class _OverlappingFields(final ValidationContext context)
    extends AstVisitor {
  final Map<Field, FieldOrigin> _origins = Map.identity();

  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      _origins[node] = FieldOrigin(context.typeInfo.parentType);
    }
    return .next;
  }

  @override
  void leave(Node node) {
    if (node is Document && !context.isAborted) {
      FieldMerging(context, _origins).check();
    }
  }
}
```

In `packages/typed_graphql/lib/src/validation/validation_context.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -67,6 +67,10 @@ final class ValidationContext {
   int _steps = 0;
   bool _isOverBudget = false;
 
+  /// The most errors the run keeps; a rule that gathers its reports
+  /// before it flushes them stops gathering there.
+  int get maxErrors => _sink.maxErrors;
+
   /// Whether the run stops: the error limit or the step budget was
   /// reached. Reports are then ignored.
   bool get isAborted => _sink.isFull || _isOverBudget;
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -105,6 +105,7 @@ export 'src/validation/rules/no_fragment_cycles_rule.dart';
 export 'src/validation/rules/no_undefined_variables_rule.dart';
 export 'src/validation/rules/no_unused_fragments_rule.dart';
 export 'src/validation/rules/no_unused_variables_rule.dart';
+export 'src/validation/rules/overlapping_fields_can_be_merged_rule.dart';
 export 'src/validation/rules/possible_fragment_spreads_rule.dart';
 export 'src/validation/rules/provided_required_arguments_rule.dart';
 export 'src/validation/rules/scalar_leafs_rule.dart';
```

- [ ] **Step 4: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -430,3 +430,81 @@ validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validates OneOf Inpu
 validation/__tests__/VariablesInAllowedPositionRule-test.ts,Validates OneOf Input Objects,Forbids one nullable variable,ported,test/validation/variables_in_allowed_position_test.dart,
 validation/__tests__/VariablesInAllowedPositionRule-test.ts,Non-specified behavior of variables within custom scalars,Allows using variables inside object literal in custom scalar,ported,test/validation/variables_in_allowed_position_test.dart,
 validation/__tests__/VariablesInAllowedPositionRule-test.ts,Non-specified behavior of variables within custom scalars,Allows using variables inside list literal in custom scalar,ported,test/validation/variables_in_allowed_position_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,unique fields,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,identical fields,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,identical fields with identical args,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,identical fields with identical directives,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different args with different aliases,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different directives with different aliases,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different skip/include directives accepted,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,stream directive used on different instances of the same field,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different stream directive label,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different stream directive initialCount,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different stream directive first missing args,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different stream directive second missing args,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different stream directive extra argument,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,mix of stream and no stream,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,different stream directive both missing args,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,Same aliases with different field targets,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,Same aliases allowed on non-overlapping fields,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,Alias masking direct field access,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,"different args, second adds an argument",ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,"different args, second missing an argument",ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,"different args, first has two, second missing one",ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,conflicting arg values,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,conflicting arg names,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,allows different args where no conflict is possible,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,allows different order of args,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,allows different order of input object fields in arg values,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,encounters conflict in fragments,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,reports each conflict once,ported,test/validation/overlapping_fields_can_be_merged_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,deep conflict,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,deep conflict with multiple issues,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not compare subfields of incompatible parent calls,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,still compares subfields of each compatible parent-call group,adapted,test/validation/overlapping_fields_deep_conflicts_test.dart,"a field is compared with the first field of each other class (linear, R3.3): one ""mother"" and ""father"" conflict instead of two, reported before the subfield conflict"
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not compare subfields after a stream conflict,skipped,,the @stream directive waits for incremental delivery (M14)
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,very deep conflict,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,reports deep conflict to nearest common ancestor,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,reports deep conflict to nearest common ancestor in fragments,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,reports deep conflict in nested fragments,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,reports deep conflict after nested fragments,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,ignores unknown fragments,ported,test/validation/overlapping_fields_deep_conflicts_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,conflicting return types which potentially overlap,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,compatible return shapes on different return types,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,disallows differing return types despite no overlap,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,does not compare subfields after a response-type conflict,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,reports correctly when a non-exclusive follows an exclusive,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,disallows differing return type nullability despite no overlap,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,disallows differing return type list despite no overlap,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,disallows differing subfields,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,disallows differing deep return types despite no overlap,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,allows non-conflicting overlapping types,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,same wrapped scalar return types,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,allows inline fragments without type condition,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,compares deep types including list,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,ignores unknown types,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > return types must be unambiguous,works for field names that are JS keywords,ported,test/validation/overlapping_fields_return_types_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not infinite loop on recursive fragment,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not infinite loop on immediately recursive fragment,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not infinite loop on recursive fragment with a field named after fragment,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,finds invalid cases even with field named after fragment,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not infinite loop on transitively recursive fragment,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,finds invalid case even with immediately recursive fragment,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged,does not infinite loop on recursive fragments separated by fields,ported,test/validation/overlapping_fields_recursive_fragments_test.dart,
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,allows conflicting spreads at different depths,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,encounters conflict in fragments,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,checks fragment arguments in each variable scope,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,allows operations with overlapping fields with arguments using identical operation variables,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects overlapping fields whose variables have different definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects overlapping fields with different nested variable definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects a fragment variable even when its default matches a literal,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,keeps an omitted fragment variable distinct from a shadowed operation variable,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,raises errors with overlapping fields with arguments that conflict via operation variables even with defaults and fragment variable defaults,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects overlapping fields using list variables with different definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects nested list values with different variable definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects overlapping fields using input object variables with different definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects nested input values with different variable definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,rejects fragment spreads whose variables have different definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,allows repeated spreads with the same local variable definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,encounters nested field conflict in fragments that could otherwise merge,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,encounters nested conflict in fragments,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/rules/field_merging_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/overlapping_fields_can_be_merged_test.dart test/validation/overlapping_fields_deep_conflicts_test.dart test/validation/overlapping_fields_recursive_fragments_test.dart test/validation/overlapping_fields_return_types_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 6: Update the documents**

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `OverlappingFieldsCanBeMergedRule` (`GQL206`): field selection merging
  in linear time (R3.3); with three or more conflicting fields of one
  response name it reports fewer conflicts than graphql-js.
- `ValidationContext.maxErrors`.
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
git add packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/validation/document_validator.dart packages/typed_graphql/lib/src/validation/overlap/argument_text.dart packages/typed_graphql/lib/src/validation/overlap/conflict_judge.dart packages/typed_graphql/lib/src/validation/overlap/conflict_reports.dart packages/typed_graphql/lib/src/validation/overlap/conflict_tree.dart packages/typed_graphql/lib/src/validation/overlap/field_conflict.dart packages/typed_graphql/lib/src/validation/overlap/field_merging.dart packages/typed_graphql/lib/src/validation/overlap/field_origin.dart packages/typed_graphql/lib/src/validation/overlap/field_shape.dart packages/typed_graphql/lib/src/validation/overlap/fragment_path.dart packages/typed_graphql/lib/src/validation/overlap/fragment_trail.dart packages/typed_graphql/lib/src/validation/overlap/merge_item.dart packages/typed_graphql/lib/src/validation/overlap/merge_split.dart packages/typed_graphql/lib/src/validation/overlap/merge_work.dart packages/typed_graphql/lib/src/validation/overlap/selection_collector.dart packages/typed_graphql/lib/src/validation/rules/overlapping_fields_can_be_merged_rule.dart packages/typed_graphql/lib/src/validation/validation_context.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/validation/rules/field_merging_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/overlapping_fields_can_be_merged_test.dart packages/typed_graphql_conformance/test/validation/overlapping_fields_deep_conflicts_test.dart packages/typed_graphql_conformance/test/validation/overlapping_fields_recursive_fragments_test.dart packages/typed_graphql_conformance/test/validation/overlapping_fields_return_types_test.dart
git commit -q -m "feat(typed_graphql): add field selection merging" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 11: Every graphql-js suite and hostile documents

Closes the conformance table: the port of `validation-test.ts`, the `skipped` rows for the SDL, defer/stream and other out-of-scope suites with their reasons, and the coverage test over every file of `src/validation/__tests__/` (except the two M4b ports). Adds the hostile-document tests of spec section 9 and the check that `specifiedRules` holds the 30 rules once each. These tests pass at once: they pin behaviour the earlier tasks built.

**Files:**
- Modify: `packages/typed_graphql_conformance/mapping/validation.csv`
- Test: `packages/typed_graphql/test/validation/document_validator_test.dart`, `packages/typed_graphql/test/validation/hostile_nesting_test.dart`, `packages/typed_graphql/test/validation/hostile_width_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/validation/validate_test.dart`

**Interfaces:**
- Consumes: Tasks 2–10.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `packages/typed_graphql/test/validation/document_validator_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -219,4 +219,12 @@ fragment B on Query { friend { ...A name @skip(if: $b) } }
     );
     expect(strings, ['d']);
   });
+
+  test('the specified rules are the 30 rules of spec §5, each once', () {
+    final kinds = {
+      for (final rule in DocumentValidator.specifiedRules) rule.runtimeType,
+    };
+    expect(kinds, hasLength(30));
+    expect(DocumentValidator.specifiedRules, hasLength(30));
+  });
 }
```

Create `packages/typed_graphql/test/validation/hostile_nesting_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec section 9 of M4 (R0.3): documents nested 100000 deep, built in code
// because the parser's depth limit would refuse them as text. No rule may
// recurse over them: on the web that overflows the stack.
void main() {
  final checked = Checked('''
type Query { node: Node nodes(filter: Filter, list: [[Int]]): [Node] }
type Node { name: String child: Node }
input Filter { name: String inner: Filter }
''');
  const depth = 100000;
  const limit = Duration(seconds: 10);
  final name = Field(null, const Name('name'));

  DocumentValidationResult timed(List<Definition> definitions) {
    final stopwatch = Stopwatch()..start();
    final result = const DocumentValidator().validate(
      checked.schema,
      Document(definitions),
    );
    expect(stopwatch.elapsed, lessThan(limit));
    return result;
  }

  OperationDefinition query(Selection selection) =>
      OperationDefinition(.query, SelectionSet([selection]));

  Field nodes(Argument argument) => Field(
    null,
    const Name('nodes'),
    arguments: [argument],
    selectionSet: SelectionSet([name]),
  );

  // `{ node { ...F0 } }` and fragments F0 to F[count - 1], each spreading
  // the next.
  List<Definition> chain(int count) => [
    query(
      Field(
        null,
        const Name('node'),
        selectionSet: SelectionSet([FragmentSpread(const Name('F0'))]),
      ),
    ),
    for (var index = 0; index < count; index++)
      FragmentDefinition(
        Name('F$index'),
        const NamedType(Name('Node')),
        SelectionSet([
          name,
          if (index < count - 1) FragmentSpread(Name('F${index + 1}')),
        ]),
      ),
  ];

  test('selections nested 100000 deep are valid', () {
    Selection field = name;
    for (var level = 0; level < depth; level++) {
      field = Field(
        null,
        const Name('child'),
        selectionSet: SelectionSet([field]),
      );
    }
    final node = Field(
      null,
      const Name('node'),
      selectionSet: SelectionSet([field]),
    );
    expect(timed([query(node)]), isA<ValidDocument>());
  });

  test('an input object nested 100000 deep is valid', () {
    Value value = ObjectValue([
      const ObjectField(Name('name'), StringValue('a')),
    ]);
    for (var level = 0; level < depth; level++) {
      value = ObjectValue([ObjectField(const Name('inner'), value)]);
    }
    final argument = Argument(const Name('filter'), value);
    expect(timed([query(nodes(argument))]), isA<ValidDocument>());
  });

  test('a list nested 100000 deep is one value error', () {
    Value value = const IntValue('1');
    for (var level = 0; level < depth; level++) {
      value = ListValue([value]);
    }
    final argument = Argument(const Name('list'), value);
    final result = timed([query(nodes(argument))]) as InvalidDocument;
    expect(
      result.diagnostics.single.code,
      DiagnosticCode.valuesOfCorrectType,
    );
  });

  test('a chain of 100000 fragments is valid', () {
    expect(timed(chain(depth)), isA<ValidDocument>());
  });
}
```

Create `packages/typed_graphql/test/validation/hostile_width_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec section 9 of M4 (R0.3): documents 100000 items wide, parsed without
// the token limit. graphql-js is quadratic in some of them; every rule here
// must stay linear.
void main() {
  final checked = Checked('''
directive @tag(n: Int) repeatable on FIELD
type Query { node: Node }
type Node { name: String child: Node size(n: Int): Int }
''');
  const width = 100000;
  const limit = Duration(seconds: 10);

  DocumentValidationResult timed(String text) {
    final stopwatch = Stopwatch()..start();
    final result = checked.validate(text);
    expect(stopwatch.elapsed, lessThan(limit));
    return result;
  }

  String repeated(String Function(int index) item) =>
      List.generate(width, item).join(' ');

  test('100000 aliases are valid', () {
    final fields = repeated((index) => 'a$index: name');
    expect(timed('{ node { $fields } }'), isA<ValidDocument>());
  });

  test('100000 fields of one response name with two targets are '
      'conflicts up to the error limit', () {
    final fields = repeated(
      (index) => index.isEven ? 'x: name' : 'x: child { name }',
    );
    final result = timed('{ node { $fields } }') as InvalidDocument;
    expect(
      result.diagnostics.first.code,
      DiagnosticCode.overlappingFieldsCanBeMerged,
    );
  });

  test('100000 directives are valid', () {
    final directives = repeated((index) => '@tag(n: $index)');
    expect(timed('{ node { name $directives } }'), isA<ValidDocument>());
  });

  test('100000 repeated arguments are one diagnostic', () {
    final arguments = repeated((index) => 'n: $index');
    final result = timed('{ node { size($arguments) } }') as InvalidDocument;
    expect(
      result.diagnostics.single.code,
      DiagnosticCode.uniqueArgumentNames,
    );
  });

  test('100000 variables, each used once, are valid', () {
    final definitions = repeated((index) => '\$v$index: Int');
    final fields = repeated((index) => 's$index: size(n: \$v$index)');
    expect(
      timed('query Q($definitions) { node { $fields } }'),
      isA<ValidDocument>(),
    );
  });

  test('100000 operations are valid', () {
    final operations = repeated((index) => 'query Q$index { node { name } }');
    expect(timed(operations), isA<ValidDocument>());
  });

  test('100000 fragments spread side by side are valid', () {
    final spreads = repeated((index) => '...F$index');
    final fragments = repeated((index) => 'fragment F$index on Node { name }');
    expect(timed('{ node { $spreads } } $fragments'), isA<ValidDocument>());
  });

  test('1000 operations over one chain of 1000 fragments spend the step '
      'budget', () {
    // Each operation expands the whole chain: a million fields to merge.
    final operations = List.generate(
      1000,
      (index) => 'query Q$index { node { ...F0 } }',
    ).join(' ');
    final fragments = List.generate(
      1000,
      (index) =>
          'fragment F$index on Node { name ${index < 999 ? '...F${index + 1}' : ''} }',
    ).join(' ');
    final result = timed('$operations $fragments') as InvalidDocument;
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });

  test('fragments that expand to 2^60 fields spend the step budget', () {
    final fragments = List.generate(
      60,
      (index) =>
          'fragment F$index on Node { a: child { ...F${index + 1} } '
          'b: child { ...F${index + 1} } }',
    ).join(' ');
    final result = timed(
      '{ node { ...F0 } } $fragments fragment F60 on Node { name }',
    ) as InvalidDocument;
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -60,6 +60,11 @@ void main() {
 
   // A row names its graphql-js file relative to `prefix`, under `src/`;
   // `covered` lists the files whose every test must have a row.
+  // The suites of the limit rules, which M4b ports.
+  const waitingForM4b = {
+    'MaxIntrospectionDepthRule-test.ts',
+    'NoSchemaIntrospectionCustomRule-test.ts',
+  };
   final tables = [
     (
       path: 'mapping/language.csv',
@@ -83,34 +88,9 @@ void main() {
     (
       path: 'mapping/validation.csv',
       prefix: '',
-      covered: const [
-        'validation/__tests__/ExecutableDefinitionsRule-test.ts',
-        'validation/__tests__/FieldsOnCorrectTypeRule-test.ts',
-        'validation/__tests__/FragmentsOnCompositeTypesRule-test.ts',
-        'validation/__tests__/KnownArgumentNamesRule-test.ts',
-        'validation/__tests__/KnownDirectivesRule-test.ts',
-        'validation/__tests__/KnownFragmentNamesRule-test.ts',
-        'validation/__tests__/KnownOperationTypesRules-test.ts',
-        'validation/__tests__/KnownTypeNamesRule-test.ts',
-        'validation/__tests__/LoneAnonymousOperationRule-test.ts',
-        'validation/__tests__/NoFragmentCyclesRule-test.ts',
-        'validation/__tests__/NoUndefinedVariablesRule-test.ts',
-        'validation/__tests__/NoUnusedFragmentsRule-test.ts',
-        'validation/__tests__/NoUnusedVariablesRule-test.ts',
-        'validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts',
-        'validation/__tests__/PossibleFragmentSpreadsRule-test.ts',
-        'validation/__tests__/ProvidedRequiredArgumentsRule-test.ts',
-        'validation/__tests__/ScalarLeafsRule-test.ts',
-        'validation/__tests__/SingleFieldSubscriptionsRule-test.ts',
-        'validation/__tests__/UniqueArgumentNamesRule-test.ts',
-        'validation/__tests__/UniqueDirectivesPerLocationRule-test.ts',
-        'validation/__tests__/UniqueFragmentNamesRule-test.ts',
-        'validation/__tests__/UniqueInputFieldNamesRule-test.ts',
-        'validation/__tests__/UniqueOperationNamesRule-test.ts',
-        'validation/__tests__/UniqueVariableNamesRule-test.ts',
-        'validation/__tests__/ValuesOfCorrectTypeRule-test.ts',
-        'validation/__tests__/VariablesAreInputTypesRule-test.ts',
-        'validation/__tests__/VariablesInAllowedPositionRule-test.ts',
+      covered: [
+        for (final file in GraphqlJsSuite.filesIn('validation/__tests__'))
+          if (!waitingForM4b.contains(file)) 'validation/__tests__/$file',
       ],
     ),
   ];
```

Create `packages/typed_graphql_conformance/test/validation/validate_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/rule_port.dart';

// Ported from graphql-js src/validation/__tests__/validation-test.ts;
// mapping/validation.csv says which tests are adapted, and why.
void main() {
  final specified = RulePort.all(DocumentValidator.specifiedRules);

  group('Validate: Supports full validation', () {
    test('validates queries', () {
      expect(
        specified.errors('''
      query {
        human {
          pets {
            ... on Cat {
              meowsVolume
            }
            ... on Dog {
              barkVolume
            }
          }
        }
      }
    '''),
        isEmpty,
      );
    });

    test('detects unknown fields', () {
      expect(
        specified.errors('''
      {
        unknown
      }
    '''),
        ['Cannot query field "unknown" on type "QueryRoot". @ 3:9'],
      );
    });

    test('validates using a custom rule', () {
      final port = RulePort(const _ReportDirectiveRule()).withSchema('''
      directive @custom(arg: String) on FIELD

      type Query {
        foo: String
      }
    ''');
      expect(
        port.errors('''
      query {
        name @custom
      }
    '''),
        ['Reporting directive: @custom @ 3:14'],
      );
    });
  });

  group('Validate: Limit maximum number of validation errors', () {
    final document = const Parser()
        .parse(
          Source('''
    {
      firstUnknownField
      secondUnknownField
      thirdUnknownField
    }
  '''),
        )
        .requireDocument();

    List<String> messages(int maxErrors) => [
      for (final diagnostic in DocumentValidator(
        maxErrors: maxErrors,
      ).validate(RulePort.testSchema, document).diagnostics)
        diagnostic.message,
    ];

    String invalidField(String name) =>
        'Cannot query field "$name" on type "QueryRoot".';

    test('when maxErrors is equal to number of errors', () {
      expect(messages(3), [
        invalidField('firstUnknownField'),
        invalidField('secondUnknownField'),
        invalidField('thirdUnknownField'),
      ]);
    });

    test('when maxErrors is less than number of errors', () {
      // Adapted: the limit is the sink's GQL000, with its own message.
      expect(messages(2), [
        invalidField('firstUnknownField'),
        invalidField('secondUnknownField'),
        'Too many errors: the limit of 2 was reached and the rest are not '
            'reported.',
      ]);
    });

    test('passthrough exceptions from rules', () {
      expect(
        () => const DocumentValidator(
          rules: [_ThrowingRule()],
          maxErrors: 1,
        ).validate(RulePort.testSchema, document),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Error from custom rule!',
          ),
        ),
      );
    });
  });

  group('operation and variable definition descriptions', () {
    test('validates operation with description and variable descriptions', () {
      final port = RulePort.all(
        DocumentValidator.specifiedRules,
      ).withSchema('type Query { field(a: Int, b: String): String }');
      expect(
        port.errors(r'''
        "Operation description"
        query myQuery(
          "Variable a description"
          $a: Int,
          """Variable b\nmultiline description"""
          $b: String
        ) {
          field(a: $a, b: $b)
        }
      '''),
        isEmpty,
      );
    });
  });
}

/// graphql-js's `customRule` that reports each directive it enters.
final class _ReportDirectiveRule extends ValidationRule {
  const _ReportDirectiveRule();

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ReportDirective(context);
}

final class _ReportDirective extends AstVisitor {
  _ReportDirective(this.context);

  final ValidationContext context;

  @override
  VisitAction enter(Node node) {
    if (node is Directive) {
      context.report(
        DiagnosticCode.customRuleViolation,
        'Reporting directive: @${context.typeInfo.directive?.name}',
        [node],
      );
    }
    return VisitAction.next;
  }
}

/// graphql-js's rule that throws from its `Field` visitor.
final class _ThrowingRule extends ValidationRule {
  const _ThrowingRule();

  @override
  AstVisitor createVisitor(ValidationContext context) => _Throwing();
}

final class _Throwing extends AstVisitor {
  @override
  VisitAction enter(Node node) => switch (node) {
    Field() => throw StateError('Error from custom rule!'),
    _ => VisitAction.next,
  };
}
```

- [ ] **Step 2: Update the package files**

In `packages/typed_graphql_conformance/mapping/validation.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -63,7 +63,7 @@ validation/__tests__/FragmentsOnCompositeTypesRule-test.ts,Validate: Fragments o
 validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,unknown types are ignored,adapted,test/validation/variables_are_input_types_test.dart,the fragment with variables is left out: September2025 has no fragment arguments
 validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,input types are valid,adapted,test/validation/variables_are_input_types_test.dart,the fragment with variables is left out: September2025 has no fragment arguments
 validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,output types are invalid,ported,test/validation/variables_are_input_types_test.dart,
-validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,output types on fragment arguments are invalid,skipped,,experimental fragment arguments: September2025 does not have them and the parser does not parse them
+validation/__tests__/VariablesAreInputTypesRule-test.ts,Validate: Variables are input types,output types on fragment arguments are invalid,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
 validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,valid scalar selection,ported,test/validation/scalar_leafs_test.dart,
 validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,object type missing selection,ported,test/validation/scalar_leafs_test.dart,
 validation/__tests__/ScalarLeafsRule-test.ts,Validate: Scalar leafs,object type having only one selection,ported,test/validation/scalar_leafs_test.dart,
@@ -314,8 +314,8 @@ validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct
 validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,variables with complex invalid default values,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
 validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,complex variables missing required field,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
 validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Variable default values,list variables with invalid item,ported,test/validation/values_of_correct_type_defaults_and_directives_test.dart,
-validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Fragment argument values,list variables with invalid item,skipped,,fragment arguments are experimental: September2025 has none and the parser does not parse them
-validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Fragment argument values,fragment spread with invalid argument value,skipped,,fragment arguments are experimental: September2025 has none and the parser does not parse them
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Fragment argument values,list variables with invalid item,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/ValuesOfCorrectTypeRule-test.ts,Validate: Values of correct type > Fragment argument values,fragment spread with invalid argument value,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
 validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,input object with fields,ported,test/validation/unique_input_field_names_test.dart,
 validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,same input object within two args,ported,test/validation/unique_input_field_names_test.dart,
 validation/__tests__/UniqueInputFieldNamesRule-test.ts,Validate: Unique input field names,multiple input object fields,ported,test/validation/unique_input_field_names_test.dart,
@@ -508,3 +508,166 @@ validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapp
 validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,allows repeated spreads with the same local variable definitions,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
 validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,encounters nested field conflict in fragments that could otherwise merge,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
 validation/__tests__/OverlappingFieldsCanBeMergedRule-test.ts,Validate: Overlapping fields can be merged > fragment arguments must produce fields that can be merged,encounters nested conflict in fragments,skipped,,fragment arguments are experimental; September2025 has none and the parser does not parse them
+validation/__tests__/validation-test.ts,Validate: Supports full validation,validates queries,ported,test/validation/validate_test.dart,
+validation/__tests__/validation-test.ts,Validate: Supports full validation,detects unknown fields,ported,test/validation/validate_test.dart,
+validation/__tests__/validation-test.ts,Validate: Supports full validation,validates using a custom rule,ported,test/validation/validate_test.dart,
+validation/__tests__/validation-test.ts,Validate: Limit maximum number of validation errors,when maxErrors is equal to number of errors,ported,test/validation/validate_test.dart,
+validation/__tests__/validation-test.ts,Validate: Limit maximum number of validation errors,when maxErrors is less than number of errors,adapted,test/validation/validate_test.dart,"the limit is the diagnostic sink's GQL000, with its own message"
+validation/__tests__/validation-test.ts,Validate: Limit maximum number of validation errors,passthrough exceptions from rules,ported,test/validation/validate_test.dart,
+validation/__tests__/validation-test.ts,operation and variable definition descriptions,validates operation with description and variable descriptions,ported,test/validation/validate_test.dart,
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,no schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,one schema definition,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,multiple schema definitions,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,define schema in schema extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,redefine schema in schema extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,redefine implicit schema in schema extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/LoneSchemaDefinitionRule-test.ts,Validate: Schema definition should be alone,extend schema in schema extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,no extensions,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,one extension per type,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,many extensions per type,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,extending unknown type,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,does not consider non-type definitions,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,extending with different kinds,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,extending types within existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,extending unknown types within existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/PossibleTypeExtensionsRule-test.ts,Validate: Possible type extensions,extending types with different kinds within existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueArgumentDefinitionNamesRule-test.ts,Validate: Unique argument definition names,no args,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueArgumentDefinitionNamesRule-test.ts,Validate: Unique argument definition names,one argument,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueArgumentDefinitionNamesRule-test.ts,Validate: Unique argument definition names,multiple arguments,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueArgumentDefinitionNamesRule-test.ts,Validate: Unique argument definition names,duplicating arguments,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,no directive,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,one directive,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,many directives,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,directive and non-directive definitions named the same,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,directives named the same,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,adding new directive to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,adding new directive with standard name to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,adding new directive to existing schema with same-named type,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueDirectiveNamesRule-test.ts,Validate: Unique directive names,adding conflicting directives to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,no values,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,one value,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,multiple values,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,duplicate values inside the same enum definition,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,extend enum with new value,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,extend enum with duplicate value,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,duplicate value inside extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,duplicate value inside different extensions,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,adding new value to the type inside existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,adding conflicting value to existing schema twice,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueEnumValueNamesRule-test.ts,Validate: Unique enum value names,adding enum values to existing schema twice,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,no fields,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,one field,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,multiple fields,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,duplicate fields inside the same type definition,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,extend type with new field,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,extend type with duplicate field,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,duplicate field inside extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,duplicate field inside different extensions,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,adding new field to the type inside existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,adding conflicting fields to existing schema twice,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueFieldDefinitionNamesRule-test.ts,Validate: Unique field definition names,adding fields to existing schema twice,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,no schema definition,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,schema definition with all types,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,schema definition with single extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,schema definition with separate extensions,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,extend schema before definition,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,duplicate operation types inside single schema definition,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,duplicate operation types inside schema extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,duplicate operation types inside schema extension twice,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,duplicate operation types inside second schema extension,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,define schema inside extension SDL,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,define and extend schema inside extension SDL,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,adding new operation types to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,adding conflicting operation types to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueOperationTypesRule-test.ts,Validate: Unique operation types,adding conflicting operation types to existing schema twice,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,no types,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,one type,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,many types,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,type and non-type definitions named the same,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,types named the same,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,adding new type to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,adding new type to existing schema with same-named directive,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/UniqueTypeNamesRule-test.ts,Validate: Unique type names,adding conflicting types to existing schema,skipped,,an SDL rule: the schema builder reports these problems (M3)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer fragments with no label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,"Defer fragments, one with label, one without",skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer fragment with null label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer fragment with variable label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer fragments with different labels,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer fragments with same label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer and stream with no label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Stream with null label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Stream with variable label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveLabelRule-test.ts,Validate: Defer/Stream directive labels,Defer and stream with the same label,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on root query field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer inline fragment spread on root query field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on root mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Fragment spread cycle on root mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Self-referencing fragment spread on root mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer inline fragment spread on root mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on root mutation field interface,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on nested mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on root subscription field interface,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on root subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer inline fragment spread on root subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Defer fragment spread on nested subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Stream field on root query field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Stream field on fragment on root query field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Stream field on root mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Stream field on fragment on root mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Stream field on root subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnRootFieldRule-test.ts,Validate: Defer/Stream directive on root field,Stream field on fragment on root subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread nested in query operation,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer inline fragment spread in query operation,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread on mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer inline fragment spread on mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread on subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with boolean true if argument,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with boolean false if argument,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread on query in multi operation document,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread on subscription in multi operation document,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with invalid if argument,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @skip directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @skip(if: true) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @skip(if: false) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer in fragment spread nested under @skip(if: true) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer in fragment spread nested under @skip(if: false) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer in fragment spread nested under @skip(if: $variable) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @skip(if: $variable) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @include directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @include(if: true) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @include(if: false) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer in fragment spread nested under @include(if: true) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer in fragment spread nested under @include(if: false) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer in fragment spread nested under @include(if: $variable) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Defer fragment spread with @include(if: $variable) directive,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on query field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on fragment on mutation field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on fragment on subscription field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on fragment on query in multi operation document,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on subscription in multi operation document,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/DeferStreamDirectiveOnValidOperationsRule-test.ts,Validate: Defer/Stream directive on valid operations,Stream on subscription in document with fragment used multiple times,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/StreamDirectiveOnListFieldRule-test.ts,Validate: Stream directive on list field,Stream on list field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/StreamDirectiveOnListFieldRule-test.ts,Validate: Stream directive on list field,Stream on non-null list field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/StreamDirectiveOnListFieldRule-test.ts,Validate: Stream directive on list field,reports errors when stream is used on non-list field,skipped,,the @defer and @stream rules wait for incremental delivery (M14)
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated fields,ignores fields that are not deprecated,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated fields,ignores unknown fields,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated fields,reports error when a deprecated field is selected,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated arguments on fields,ignores arguments that are not deprecated,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated arguments on fields,ignores unknown arguments,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated arguments on fields,reports error when a deprecated argument is used,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated arguments on directives,ignores arguments that are not deprecated,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated arguments on directives,ignores unknown arguments,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated arguments on directives,reports error when a deprecated argument is used,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated input fields,ignores input fields that are not deprecated,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated input fields,ignores unknown input fields,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated input fields,reports error when a deprecated input field is used,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated enum values,ignores enum values that are not deprecated,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated enum values,ignores unknown enum values,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/NoDeprecatedCustomRule-test.ts,Validate: no deprecated > no deprecated enum values,reports error when a deprecated enum value is used,skipped,,"a graphql-js custom rule outside R3 (M4 spec, open question 5)"
+validation/__tests__/ValidationContext-test.ts,ValidationContext,can be Object.toStringified,skipped,,checks JavaScript's Object.prototype.toString; Dart has no counterpart
+validation/__tests__/diagnostics-test.ts,validate diagnostics channel,emits start and end around a successful validate,skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
+validation/__tests__/diagnostics-test.ts,validate diagnostics channel,emits start and end for a document with validation errors,skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
+validation/__tests__/diagnostics-test.ts,validate diagnostics channel,"emits start, error, and end when validate throws on an invalid schema",skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
+validation/__tests__/diagnostics-test.ts,validate diagnostics channel,does not call tracing methods when no subscribers are attached,skipped,,checks Node's diagnostics_channel tracing; Dart has no counterpart
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/validation/document_validator_test.dart test/validation/hostile_nesting_test.dart test/validation/hostile_width_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/validation/validate_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add packages/typed_graphql/test/validation/document_validator_test.dart packages/typed_graphql/test/validation/hostile_nesting_test.dart packages/typed_graphql/test/validation/hostile_width_test.dart packages/typed_graphql_conformance/mapping/validation.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/validation/validate_test.dart
git commit -q -m "test(typed_graphql): cover every graphql-js validation suite and hostile documents" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 12: The Operation Validation guide

The guide (`doc/validation.md`): validating a document, the specified rules and their codes, field selection merging, custom rules, work limits; the example and the README tour validate a request; the README, `llms.txt` and `docs/discovery.md` say operation validation works today; `CLAUDE.md` and the handoff.

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/discovery.md`, `docs/superpowers/HANDOFF.md`, `llms.txt`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/doc/validation.md`, `packages/typed_graphql/example/example.dart`, `packages/typed_graphql/pubspec.yaml`
- Test: `test/discovery/discovery_page_test.dart`

**Interfaces:**
- Consumes: Every earlier task.
- Produces:
- Nothing for later tasks.

- [ ] **Step 1: Write the tests**

In `test/discovery/discovery_page_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,6 +66,7 @@ void main() {
         'GraphQL request response JSON types dart',
         'validate a GraphQL schema dart',
         'GraphQL introspection query schema dart',
+        'validate a GraphQL operation dart',
       ]),
     );
   });
```

- [ ] **Step 2: Update the package files**

In `packages/typed_graphql/pubspec.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 name: typed_graphql
 description: >-
-  Parses, prints and builds GraphQL documents and schemas in pure Dart for the VM, web and Wasm, with error-resilient diagnostics and wire-protocol types.
+  Parses, prints, builds and validates GraphQL documents and schemas in pure Dart for the VM, web and Wasm, with error-resilient diagnostics and wire-protocol types.
 version: 0.0.1
 repository: https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql
 issue_tracker: https://github.com/4akloon/graphql_dart/issues
```

- [ ] **Step 3: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -34,7 +34,11 @@ relations, the schema validator, the introspection query, introspection
 results in both directions, coordinate resolution, the graphql-js
 `validateSchema`, `buildClientSchema`, `introspectionFromSchema` and
 `resolveSchemaCoordinate` suites, the introspection and coordinate fuzzers,
-and the Introspection guide.
+and the Introspection guide. M4a (operation validation) delivers the rule
+framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection
+merging in linear time, the step budget (`GQL230`), every graphql-js
+validation suite, the hostile-document tests and the Operation Validation
+guide.
 
 ## Documents
 
@@ -315,6 +319,44 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   walks default values depth-first and, created once per run, remembers
   the fields it walked across types.
 
+**Validation** (`validation/`; M4). Imports every layer before it.
+- `DocumentValidator` (const: `rules`, `maxErrors`, `includesSuggestions`,
+  `maxSteps`) validates a `Document` against a `ValidSchema` and returns the
+  sealed `DocumentValidationResult` (`ValidDocument` | `InvalidDocument`).
+  `specifiedRules` are the 30 rules of spec §5 in graphql-js's order, three
+  graphql-js rules split so that one class reports one code.
+- A `ValidationRule` is const configuration; `createVisitor(context)` gives
+  a fresh `AstVisitor` per run. `ValidationWalk` walks the document once
+  with all of them (a `ParallelVisitor`), with `TypeInfo` (graphql-js's:
+  parent type, field definition, input type, directive, argument) entered
+  before the rules and left after them, and `UsageIndex` recording
+  variable usages and spreads per definition. Descriptions are not walked
+  (spec §2.2).
+- `ValidationContext`: `report(code, message, nodes)` (the first node is
+  the place, the others related), `fragmentNamed` (the last definition of a
+  name), `recursivelyReferencedFragments` and `recursiveVariableUsages`
+  (only from `leave(Document)`), `spend(steps)` (the step budget: past
+  `maxSteps` one `GQL230` and the run stops), `isAborted`, `maxErrors`.
+  A rule that needs operation closures reports at `leave(Document)`
+  (`OperationVisitor`), after the rules that report during the walk.
+- Shared pieces: `FragmentSpreadCollector`, `ValueProblemVisitor` (one
+  `ValueChecker` pass per literal, split by `ValueProblemKind` into
+  `GQL218`-`GQL221`), `FieldTypeSuggestions`, `MetaFields`.
+  `EngineOrderedSort` reproduces the order V8's sort gives graphql-js's
+  type suggestions, whose comparator is not a total order, so messages
+  match to the character. "Did you mean" text is
+  `diagnostics/Suggestions` over `LexicalDistance`.
+- `overlap/` is `OverlappingFieldsCanBeMergedRule` (R3.3; spec section 6 of
+  M4): `FieldMerging` merges each operation, and each fragment no earlier
+  root expanded, level by level over an explicit stack.
+  `SelectionCollector` groups `MergeItem`s by response name (each with its
+  `FragmentTrail`, a persistent list of the fragments spread to reach it),
+  `MergeSplit` classes them by `FieldShape` and by name and `ArgumentText`
+  per object parent and pairs each with the first item of every other
+  class, `ConflictJudge` judges a pair at its nearest distinct ancestors,
+  `ConflictTree` and `ConflictReports` build graphql-js's nested messages
+  and order them by the selection set graphql-js finds them in.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
@@ -404,6 +446,14 @@ Learned in M3a:
 - An empty document is a syntax error (spec §2.2), so an empty schema
   prints text that does not build back; a round trip treats it apart.
 
+Learned in M4a:
+- Equal messages need equal order: a comparator that is not a total
+  order sorts differently in Dart and in V8; `EngineOrderedSort` follows V8.
+- A ported template literal keeps its indentation: moving tests between
+  groups must not re-indent the query text, or every column shifts.
+- A work budget is measured, not guessed: about a million steps take a
+  second on the VM, so the default `maxSteps` is a million.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
@@ -485,11 +535,13 @@ README that leaves the package folder is an absolute URL.
   `packages/typed_graphql/example/example.dart`. The documentation suite is
   `packages/typed_graphql/test/doc/`.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
-- Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`
-  and `mapping/schema.csv`, checked by `test/mapping_test.dart` there; port
-  helpers in its `test/support/` (`SchemaPort` for the schema suites,
-  `ValidationPort` for `validateSchema`, `IntrospectionPort` for
-  `buildClientSchema`).
+- Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`,
+  `mapping/schema.csv` and `mapping/validation.csv`, checked by
+  `test/mapping_test.dart` there; port helpers in its `test/support/`
+  (`SchemaPort` for the schema suites, `ValidationPort` for
+  `validateSchema`, `IntrospectionPort` for `buildClientSchema`,
+  `RulePort` for the validation rule suites).
+- Hostile-document tests: `packages/typed_graphql/test/validation/hostile_*_test.dart`.
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
   round trip, hostile SDL, introspection round trip, hostile
   introspection, coordinates); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,7 +64,8 @@ void main() {
 > every API may change before 0.1.0. Stages M2 (language) and M3
 > (the schema: building it from SDL, extending, printing and validating it,
 > resolving schema coordinates, and introspection in both directions) are
-> done.
+> done, and so is M4a (operation validation by the specification's 30
+> rules).
 
 ## Table of contents
 
@@ -93,12 +94,13 @@ approaches:
   signature.
 - **Every problem at once.** The parser reports every syntax error in one
   pass, and schema building and validation report every diagnostic, each with
-  a stable code (`GQL0xx`-`GQL5xx`) and a source location. Operation
-  validation (M4) will do the same.
+  a stable code (`GQL0xx`-`GQL5xx`) and a source location; so does
+  operation validation.
 - **Conformance is measured.** The graphql-js v17 language and schema suites
   are ported with a mapping table (`typed_graphql_conformance`), and the core
   tests also run AOT-compiled and in the browser (dart2js and dart2wasm). The
-  validation and execution suites will be ported with their stages.
+  validation suites are ported too; the execution suites will be ported
+  with their stage.
 - **Independent.** The core is pure Dart and depends only on `meta`.
 
 ## Packages
@@ -107,7 +109,7 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 
 | Package | Role | Status |
 |---|---|---|
-| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection (M1, M2, M3) |
+| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation (M1, M2, M3, M4a) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
```

In `docs/discovery.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -37,7 +37,7 @@ adds its row (or turns it to "yes") together with its README line and its
 | GraphQL request response JSON types dart | M1 | yes |
 | validate a GraphQL schema dart | M3 | yes |
 | GraphQL introspection query schema dart | M3 | yes |
-| validate a GraphQL operation dart | M4 | no |
+| validate a GraphQL operation dart | M4 | yes |
 | execute a GraphQL query dart | M5 | no |
 | GraphQL server dart | M7 | no |
 | generate a typed GraphQL client dart | M10 | no |
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-14 (M3a, M3c and M3b merged into `main` locally, not pushed). Read this
+Last updated: 2026-10-15 (M3a, M3c and M3b merged into `main` locally, not pushed; M4a done). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
@@ -15,6 +15,7 @@ needed.
 | M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md); M3b: [plan](plans/2026-10-14-m3b-schema-validation.md) | M3a and M3b merged into `main` locally (not pushed); M3 is complete; next is M4 (operation validation) |
 | M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 | Agent discoverability | [spec](specs/2026-10-14-agent-discoverability-design.md) | [plan](plans/2026-10-14-agent-discoverability.md) | merged locally into main (3df6740, not pushed): pub.dev metadata, the core README's "Should I use this?", `llms.txt`, `docs/discovery.md`, the `test/discovery/` suite |
+| M4 Operation validation | [spec](specs/2026-10-14-m4-operation-validation-design.md) | M4a: [plan](plans/2026-10-14-m4a-operation-validation.md); M4b: [plan](plans/2026-10-14-m4b-limits-and-cost.md) | M4a is complete: the rule framework, the 30 rules of spec §5 (`GQL200`-`GQL229`), field selection merging in linear time, the step budget (`GQL230`), custom rules (`GQL231`), every graphql-js validation suite in `mapping/validation.csv`, the hostile-document tests and `doc/validation.md`; next is M4b (limit rules, cost analysis, fuzzers) |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
@@ -88,6 +89,13 @@ M3b is complete and merged into `main` locally (not pushed). Left open by the M3
 - **Directive reference cycles with repeated names.** A cycle is judged per
   directive name (the first definition is the node).
 
+- **Field merging reports fewer conflicts than graphql-js** when three or
+  more fields of one response name conflict: each field is compared with
+  the first field of every other class (M4 spec, deviation 4; one adapted
+  row in `mapping/validation.csv`).
+- **Validation budget.** `maxSteps` defaults to 1 000 000 (about a second
+  on the VM); a document that needs more is `GQL230` (M4 spec section 8).
+
 ## Rules the user set
 
 - **Outward actions need the user's explicit yes:** pushing to GitHub, tags,
```

In `llms.txt`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,10 +1,10 @@
 # typed_graphql
 
-> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. Operation validation (stage M4), execution (M5) and the server, client and code generation packages are not built yet, and nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
+> GraphQL for Dart, written from scratch and fully typed. Today the core package, typed_graphql, parses, prints and transforms GraphQL documents, builds, validates and prints schemas from SDL, writes and reads introspection, validates operations against a schema by the specification's rules, and reads and writes GraphQL request and response JSON as typed values. Bad input never throws: every problem is a value, a diagnostic with a stable code (and a place when the source is given) or a decode failure with a JSON path. It is pure Dart and runs on the VM, AOT, dart2js and dart2wasm. Execution (stage M5) and the server, client and code generation packages are not built yet, and nothing is on pub.dev yet: install the core from this repository with a git dependency on the path packages/typed_graphql.
 
 ## Packages
 
-- [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, wire protocol and diagnostics
+- [typed_graphql](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/README.md): under construction; the core, usable today: language, schema, introspection, operation validation, wire protocol and diagnostics
 - [typed_graphql_builder](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_builder/README.md): skeleton; build_runner builders, not usable yet (M9)
 - [typed_graphql_client](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_client/README.md): skeleton; client runtime and normalized cache, not usable yet (M11, M12)
 - [typed_graphql_codegen](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/README.md): skeleton; code generator and its CLI, not usable yet (M8, M10)
@@ -20,8 +20,8 @@
 - [Schema](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/schema.md): build a schema from SDL, read, validate, extend and print it; resolve coordinates
 - [Scalars and codecs](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/scalars.md): the built-in scalar codecs and your own
 - [Introspection](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/introspection.md): the introspection query, a schema's answer, and a schema built from an answer
-- [Operation validation](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/validation.md): validate a document against a schema; custom rules; work limits
-- [Example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/example/example.dart): a runnable program: report syntax errors, print a document, build a schema from SDL
+- [Operation validation](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/doc/validation.md): validate a document against a schema; the rules and their codes; custom rules; work limits
+- [Example](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql/example/example.dart): a runnable program: report syntax errors, print a document, build a schema from SDL, validate a request
 
 ## Reference
 
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The Operation Validation guide covers validating a document, the
  specified rules and their codes, field selection merging and custom rules;
  the example and the README tour validate a request.
- pub.dev metadata, README and `llms.txt` say that the package validates
  operations; the discovery query "validate a GraphQL operation dart"
  works today.
```

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -5,17 +5,18 @@
 ![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)
 
 **Parse, print and transform GraphQL queries and SDL in Dart, build and
-validate a schema from SDL, and decode GraphQL responses into sealed
-`ResponsePayload` values, with every syntax error reported in one pass with
-its line and column.** Pure Dart, depends only on `meta`, runs on the VM, AOT
+validate a schema from SDL, validate operations against it, and decode
+GraphQL responses into sealed `ResponsePayload` values, with every syntax
+error reported in one pass with its line and column.** Pure Dart, depends only on `meta`, runs on the VM, AOT
 and the web (dart2js and dart2wasm). Part of [typed_graphql](https://github.com/4akloon/graphql_dart).
 
 > **Status: under construction.** This release has the diagnostics model, the
 > protocol data types, the language (syntax trees, lexer, parser, printer,
 > visitors, transformers, schema coordinates) and the schema (its model, building and
 > extending it from SDL, printing it, scalar codecs, validating it,
-> introspection both ways, resolving schema coordinates). Document validation
-> arrives in M4 (see the
+> introspection both ways, resolving schema coordinates) and the validation
+> of executable documents by the specification's 30 rules. Execution
+> arrives in M5 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 ## Contents
@@ -41,16 +42,17 @@ dependencies:
 ## Should I use this?
 
 - **Use it when** you need to parse, print, rewrite or inspect GraphQL text,
-  or build and validate a schema from SDL, in Dart (VM, web or Wasm), and want
-  every problem as a diagnostic with a stable code (and a place when the
-  source is given), or a decode failure with a path
+  build and validate a schema from SDL, or validate operations against it,
+  in Dart (VM, web or Wasm), and want every problem as a diagnostic with a
+  stable code (and a place when the source is given), or a decode failure
+  with a path
   ([Language](doc/language.md#parsing-a-document),
   [Schema](doc/schema.md#building-a-schema-from-sdl),
+  [Operation validation](doc/validation.md#validating-a-document),
   [Diagnostics](doc/diagnostics.md#reading-a-diagnostic)).
 - **You do not need it when** you only send a query string to a server and
-  read the JSON back. Today it also does not validate an operation against a
-  schema or execute one: operation validation arrives in this package in M4,
-  and execution in `typed_graphql_server` (M5).
+  read the JSON back. Today it also does not execute an operation:
+  execution arrives in `typed_graphql_server` (M5).
 - **What it replaces**: matching GraphQL text with regular expressions or
   string splitting, and reading responses as `Map<String, dynamic>`. A regular
   expression does not see comments, block strings or nested selections, and
@@ -66,8 +68,8 @@ dependencies:
 
 ## A quick tour
 
-Bad input never throws: a syntax error or a problem in the SDL is a value you
-inspect. The same program is in [example/example.dart](example/example.dart).
+Bad input never throws: a syntax error, a problem in the SDL or an invalid
+request is a value you inspect. The same program is in [example/example.dart](example/example.dart).
 
 ```dart
 import 'dart:io';
@@ -98,6 +100,19 @@ void main() {
   switch (result) {
     case BuildSuccess(:final schema):
       stdout.writeln('query root: ${schema.queryTypeName}');
+      // A request is checked against a valid schema by the spec's rules.
+      final request = Source('{ heroes }', name: 'request.graphql');
+      if (const SchemaValidator().validate(schema)
+          case final ValidSchema valid) {
+        final checked = const DocumentValidator().validate(
+          valid,
+          parser.parse(request).requireDocument(),
+          source: request,
+        );
+        if (checked case InvalidDocument(:final diagnostics)) {
+          diagnostics.forEach(stdout.writeln);
+        }
+      }
     case BuildFailure(:final diagnostics):
       diagnostics.forEach(stdout.writeln);
   }
@@ -114,6 +129,7 @@ query Hero {
   }
 }
 query root: Query
+request.graphql:1:3: error GQL205: Cannot query field "heroes" on type "Query". Did you mean "hero"?
 ```
 
 ## Guides
@@ -130,6 +146,7 @@ is run by the test suite, so what they print is what the package does.
 | [Schema](doc/schema.md) | Build a schema from SDL, read it, validate it, extend it, print it; resolve coordinates |
 | [Scalars and codecs](doc/scalars.md) | The built-in codecs and your own |
 | [Introspection](doc/introspection.md) | Write the introspection query, answer it from a schema, build a schema from an answer |
+| [Operation validation](doc/validation.md) | Validate a document against a schema; the rules and their codes; custom rules; work limits |
 
 The API reference is generated by `dart doc` and groups every type under the
 same topics. Run it in this directory and open `doc/api/index.html`.
````

In `packages/typed_graphql/doc/validation.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -6,7 +6,115 @@ it (September2025, "Validation"). `DocumentValidator` checks a parsed
 `ValidDocument` or an `InvalidDocument` with every problem as a diagnostic;
 an invalid document never throws.
 
-## Rules
+## Validating a document
+
+By default the validator runs `DocumentValidator.specifiedRules`, the 30
+rules of the specification. Each problem is a diagnostic with a stable code
+and graphql-js's message, at the place it is about when the validator is
+given the `Source`:
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  final schema = switch (const SchemaBuilder().fromSdl(
+    const Parser()
+        .parse(Source('type Query { name: String friends: [Query] }'))
+        .requireDocument(),
+  )) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure() => throw StateError('the schema is valid'),
+  };
+  final valid = switch (const SchemaValidator().validate(schema)) {
+    final ValidSchema valid => valid,
+    InvalidSchema() => throw StateError('the schema is valid'),
+  };
+  final source = Source(r'query ($id: ID) { nam friends }');
+  final document = const Parser().parse(source).requireDocument();
+  const validator = DocumentValidator();
+  switch (validator.validate(valid, document, source: source)) {
+    case ValidDocument():
+      print('valid');
+    case InvalidDocument(:final diagnostics):
+      for (final diagnostic in diagnostics) {
+        final location = diagnostic.span?.location;
+        print('$location ${diagnostic.code.id} ${diagnostic.message}');
+      }
+  }
+}
+```
+
+It prints:
+
+```text
+1:19 GQL205 Cannot query field "nam" on type "Query". Did you mean "name"?
+1:23 GQL207 Field "friends" of type "[Query]" must have a selection of subfields. Did you mean "friends { ... }"?
+1:8 GQL228 Variable "$id" is never used.
+```
+
+The rules that need an operation's fragments, such as `GQL228`, report
+when the walk has left the document, after the others. "Did you mean"
+suggestions follow graphql-js; a production server turns them
+off with `includesSuggestions: false`, so that error messages do not list
+the schema's names.
+
+## The specified rules
+
+The rules are public classes, so a list can drop, reorder or extend them:
+`DocumentValidator(rules: [...DocumentValidator.specifiedRules, MyRule()])`.
+Three graphql-js rules are split so that each class checks one rule of the
+specification and reports one code.
+
+| Code | Rule | Specification |
+|---|---|---|
+| `GQL200` | `ExecutableDefinitionsRule` | §5.1.1 Executable Definitions |
+| `GQL201` | `KnownOperationTypesRule` | §5.2.1.1 Operation Type Existence |
+| `GQL202` | `UniqueOperationNamesRule` | §5.2.2.1 Operation Name Uniqueness |
+| `GQL203` | `LoneAnonymousOperationRule` | §5.2.3.1 Lone Anonymous Operation |
+| `GQL204` | `SingleFieldSubscriptionsRule` | §5.2.4.1 Single Root Field |
+| `GQL205` | `FieldsOnCorrectTypeRule` | §5.3.1 Field Selections |
+| `GQL206` | `OverlappingFieldsCanBeMergedRule` | §5.3.2 Field Selection Merging |
+| `GQL207` | `ScalarLeafsRule` | §5.3.3 Leaf Field Selections |
+| `GQL208` | `KnownArgumentNamesRule` | §5.4.1 Argument Names |
+| `GQL209` | `UniqueArgumentNamesRule` | §5.4.2 Argument Uniqueness |
+| `GQL210` | `ProvidedRequiredArgumentsRule` | §5.4.3 Required Arguments |
+| `GQL211` | `UniqueFragmentNamesRule` | §5.5.1.1 Fragment Name Uniqueness |
+| `GQL212` | `KnownTypeNamesRule` | §5.5.1.2 Fragment Spread Type Existence |
+| `GQL213` | `FragmentsOnCompositeTypesRule` | §5.5.1.3 Fragments on Object, Interface or Union Types |
+| `GQL214` | `NoUnusedFragmentsRule` | §5.5.1.4 Fragments Must Be Used |
+| `GQL215` | `KnownFragmentNamesRule` | §5.5.2.1 Fragment Spread Target Defined |
+| `GQL216` | `NoFragmentCyclesRule` | §5.5.2.2 Fragment Spreads Must Not Form Cycles |
+| `GQL217` | `PossibleFragmentSpreadsRule` | §5.5.2.3 Fragment Spread Is Possible |
+| `GQL218` | `ValuesOfCorrectTypeRule` | §5.6.1 Values of Correct Type |
+| `GQL219` | `InputObjectFieldNamesRule` | §5.6.2 Input Object Field Names |
+| `GQL220` | `UniqueInputFieldNamesRule` | §5.6.3 Input Object Field Uniqueness |
+| `GQL221` | `InputObjectRequiredFieldsRule` | §5.6.4 Input Object Required Fields |
+| `GQL222` | `KnownDirectivesRule` | §5.7.1 Directives Are Defined |
+| `GQL223` | `DirectivesInValidLocationsRule` | §5.7.2 Directives Are in Valid Locations |
+| `GQL224` | `UniqueDirectivesPerLocationRule` | §5.7.3 Directives Are Unique per Location |
+| `GQL225` | `UniqueVariableNamesRule` | §5.8.1 Variable Uniqueness |
+| `GQL226` | `VariablesAreInputTypesRule` | §5.8.2 Variables Are Input Types |
+| `GQL227` | `NoUndefinedVariablesRule` | §5.8.3 All Variable Uses Defined |
+| `GQL228` | `NoUnusedVariablesRule` | §5.8.4 All Variables Used |
+| `GQL229` | `VariablesInAllowedPositionRule` | §5.8.5 All Variable Usages Are Allowed |
+
+`KnownTypeNamesRule` also checks the types of variable definitions, as
+graphql-js does. Descriptions on operations and variables are not
+validated (§2.2).
+
+## Field selection merging
+
+Two fields with one response name must select the same thing. graphql-js
+compares every pair of such fields, which is quadratic: a document with a
+few thousand copies of one field keeps it busy for seconds.
+`OverlappingFieldsCanBeMergedRule` merges the fields level by level instead
+and compares each field with the first field of every other kind, so its
+work grows with the size of the document. It reports graphql-js's messages
+at graphql-js's places; with three or more conflicting fields of one name
+it may report fewer conflicts, since one report per kind is enough to show
+the problem.
+
+## Custom rules
 
 A `ValidationRule` is one check. For each run the validator asks every rule
 for a fresh `AstVisitor` and walks the document once with all of them. At
````

In `packages/typed_graphql/example/example.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -26,6 +26,19 @@ void main() {
   switch (result) {
     case BuildSuccess(:final schema):
       stdout.writeln('query root: ${schema.queryTypeName}');
+      // A request is checked against a valid schema by the spec's rules.
+      final request = Source('{ heroes }', name: 'request.graphql');
+      if (const SchemaValidator().validate(schema)
+          case final ValidSchema valid) {
+        final checked = const DocumentValidator().validate(
+          valid,
+          parser.parse(request).requireDocument(),
+          source: request,
+        );
+        if (checked case InvalidDocument(:final diagnostics)) {
+          diagnostics.forEach(stdout.writeln);
+        }
+      }
     case BuildFailure(:final diagnostics):
       diagnostics.forEach(stdout.writeln);
   }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(ulimit -v 8000000 && timeout 600 dart test test/discovery/discovery_page_test.dart)
```

Expected: `All tests passed!`.

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add CLAUDE.md README.md docs/discovery.md docs/superpowers/HANDOFF.md llms.txt packages/typed_graphql/CHANGELOG.md packages/typed_graphql/README.md packages/typed_graphql/doc/validation.md packages/typed_graphql/example/example.dart packages/typed_graphql/pubspec.yaml test/discovery/discovery_page_test.dart
git commit -q -m "docs(typed_graphql): add the Operation Validation guide" \
  -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Open questions for the owner

The spec's section 15 lists them with recommendations; this plan implements the recommendations: the step budget with a default of 1 000 000 (question 1), all 30 rule classes exported (question 3), no `NoDeprecatedCustomRule` (question 5). Overlap reports with three or more conflicting fields of one name differ in count from graphql-js (question 8; one `adapted` row).

## Self-review

- Spec coverage: sections 3 (Tasks 2 and 9), 4 (each code in the task that first reports it), 5 (Tasks 3–9), 6 (Task 10), 7–9 (Tasks 2, 10, 11), 12 (Tasks 3–11), 13 (Task 12).
- Every code block in this plan is the content of a commit that passed the green check; no placeholder remains.
- Type consistency: each task's Produces block is extracted from its commit, and later tasks consume those names.

## After the plan

Update `docs/superpowers/HANDOFF.md` (Task 12 does), then run the final whole-branch review and merge as the handoff's "How a stage is done" says.
