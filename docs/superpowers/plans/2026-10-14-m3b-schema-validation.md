# M3b Schema Validation and Introspection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish M3's `schema/` layer and its conformance measurement:
- schema validation: every rule of spec §7, as a sealed `SchemaValidationResult` (`ValidSchema` | `InvalidSchema`) with `GQL111`–`GQL149` diagnostics (R2.3, R2.4);
- introspection: `IntrospectionQuery`, `Schema.toIntrospection` and `SchemaBuilder.fromIntrospection`, a malformed result being `GQL150`–`GQL155` diagnostics (R2.7, R0.3);
- schema coordinates: `Schema.resolve(SchemaCoordinate)` with a sealed `CoordinateTarget` (R2.8);
- the schema accessors M4 needs: type predicates, possible types, sub-typing and overlap;
- the ported graphql-js `validateSchema`, `getIntrospectionQuery`, `introspectionFromSchema`, `buildClientSchema` and `resolveSchemaCoordinate` suites, with mapping rows; the M3a rows that waited for validation (R0.7, R10.3);
- the hostile introspection-JSON and coordinate fuzzers and a `Schema` → introspection → `Schema` round-trip fuzzer (R10.4);
- the stage's documentation in M3c's guides, as the handoff's M3c row asks: the Schema guide's "Validating a schema" and "Resolving a coordinate" sections, a new Introspection guide with its own dartdoc category, the `{@category}` tags of the new types, the README, the CHANGELOGs, `CLAUDE.md` and the handoff (R11.1–R11.3).

**Architecture:** `packages/typed_graphql/lib/src/schema/` gains four folders:
- `relations/` holds `ImplementationIndex` and `TypeComparator`, behind new `Schema` accessors.
- `validation/` holds `SchemaValidator`. It runs one rule class per family of spec §7 into a `ValidationReport`, in graphql-js's order. The families are `RootTypeRules`, `NameRules`, `TypeRules` and the per-kind rules it calls, `TypeReferenceRules`, `AppliedDirectiveRules`, `DefaultValueRules` over a `ValueChecker`, `DirectiveDefinitionRules`, `ImplementationRules`, `FiniteValueRules` and `DefaultValueCycleRules`.
- `introspection/` holds `IntrospectionQuery`, the writer (`IntrospectionWriter`, `TypeWriter`, `TypeRefWriter`) and the reader (`IntrospectionReader` over `IntrospectionObject`, `NamedTypeReader`, `MemberReader`, `DirectiveDefinitionReader`, `TypeRefReader`).
- `coordinates/` holds the `CoordinateTarget` family and `CoordinateResolver`.

In `packages/typed_graphql_conformance`, the ported suites go under `test/schema/` and the fuzzers under `test/fuzz/`.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`. graphql-js 17.0.2 (commit `ee5ce41`, fetched into `reference/` by `tool/fetch_reference.sh`) is the reference. The September2025 specification is the authority where they differ. Chrome runs dart2js and dart2wasm.

**Spec:**
- `docs/superpowers/specs/2026-10-14-m3-type-system-design.md`: the M3b row of section 1, and sections 7–13;
- section 3 of `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`;
- `docs/requirements.md`: R0.2, R0.3, R0.6, R0.7, R2.3, R2.4, R2.7, R2.8, R10.2, R10.3, R10.4, R11.1–R11.3;
- `docs/superpowers/HANDOFF.md`: the M3c row and "Open for M3b"; the M3c plan `docs/superpowers/plans/2026-10-14-m3c-core-docs.md`, "How M3b extends these guides".

**Base:** `main` at `5a9261d` (M3a, M3c, the handoff update and the agent-discoverability design). Work on a branch `m3b-schema-validation` in a worktree. The plan was verified on two bases:
- the whole plan, all 19 tasks, on `main` at `5a9261d`: every diff below was made against that tree;
- Tasks 1–18 also on `main` at `90f0236`, before M3c, where the guide steps do not apply.

See "Running after M3c" in the Global Constraints.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one; a helper in a test is a local closure inside `main` or a method of a class.
- Layering (spec §2): `schema/` imports `diagnostics/`, `language/`, `protocol/` and itself. The core stays pure Dart: no new dependency and no `dart:io` in `lib/` (R0.6). The schema tests run on the VM, as exe, with dart2js and with dart2wasm. A test that needs `dart:io` starts with `@TestOn('vm')` and then `library;`.
- No new package dependency in this stage.
- Bad input never throws (R0.3). A schema that breaks a rule is an `InvalidSchema` with `GQL1xx` diagnostics, and a malformed introspection result is a `BuildFailure` with `GQL150`–`GQL155` diagnostics. Only programmer errors throw (`ArgumentError`, `RangeError`, `StateError`).
- **No unbounded work on hostile input.** Some walks run over a schema or a JSON result that can be deep or cyclic: type references, `ofType` chains, interface and input-object cycles, directive self-reference.
  - Each such walk is a loop over an explicit stack or worklist with a visited set, never recursion.
  - Nothing copies a path per level.
  - Each such walk has a test at depth 10000 or more.
  - Fuzzers run a small fixed count in CI; the M2 environment variables raise it.
- **Memory and time limits when running the suites.** A runaway test once took 22 GB (decision 10).
  - Run every `dart test`, `dart analyze`, `dart format` and `dart pub` command under `ulimit -v 8000000` and `timeout`, one Dart process at a time.
  - Chrome cannot start under `ulimit -v` (it exits with code -5: it reserves more address space than that). Bound the browser runs by resident memory instead: `systemd-run --user --scope -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome …`.
- New codes go into `DiagnosticCode` in id order, with a doc comment, in the commit that first reports them (spec §10): `GQL111`–`GQL149` in Tasks 4–10, `GQL150`–`GQL155` in Task 15.
- Messages are graphql-js's text where graphql-js has the same check, so the ported suites compare them unchanged. Each diagnostic carries the span of the element at fault, and related spans where graphql-js lists several nodes.
- Output is deterministic: diagnostics come in graphql-js's rule order and the schema's declaration order; no hash-ordered collection is iterated.
- Public API goes through the barrel `lib/typed_graphql.dart`. These stay out of it: the rule classes, the readers and writers, `ImplementationIndex`, `TypeComparator` and `CoordinateResolver`.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- `CLAUDE.md`, the specs and the package `CHANGELOG.md` change in the task that changes what they describe; the steps give those changes.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise. Use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are unified diffs against the tree that the earlier tasks leave. Each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: stop and report it, unless the next rule covers it.
- **If `main` has moved.** The diffs were made against `5a9261d`, and every one applied there as is.
  - If `main` differs where a diff applies, apply the diff with `git apply --3way` (save it to a file first): the blobs it was made against are in the repository.
  - Measured: Tasks 1–18 made before M3c also applied to M3c's tree, except one hunk of Task 2 in `schema_type.dart` (M3c's `{@category}` lines), which `--3way` merged without a conflict.
  - A CHANGELOG change is given as "Append to": add the lines at the end of the file, after M3c's entries.
  - The guide sections are given whole inside their diffs; if a diff does not apply, insert the same text at the place its context names.
- **Documentation rule (M3c, `CLAUDE.md` "Documentation").** A task that adds exported API tags each new exported type with `/// {@category …}` (after a `///` line, as M3c's tagging script does) and adds its guide section in the same commit: "Validating a schema" (Task 4) and "Resolving a coordinate" (Task 17) in the Schema guide; the Introspection guide, its category and "The introspection query" (Task 13), "Answering from a schema" (Task 14) and "Reading an answer" (Task 15). M3c's documentation suite (`test/doc`) runs in every green check.

## Rulings

The user decided these before the plan was written; the plan follows them.

1. **The M3a rows that waited for validation are converted** (Task 12). Each adapted `buildASTSchema` / `extendSchema` row whose reason was "schema validation arrives in M3b" now asserts `validateSchema` as graphql-js does, and its reason is cleared or rewritten.
2. **`SchemaBuilder.fromIntrospection(JsonValue)` returns the sealed `BuildResult`.** Structural problems are `GQL150`–`GQL155` diagnostics with the JSON path in the message (`$.__schema.types[3].fields: …`). This deviates from spec §8 ("a `DecodeFailure` with a path"); Task 15 updates spec §8 and adds deviation 7 to §13.
3. **Directive locations are typed** (Task 1). `DirectiveLocation`, an enum in the language layer, replaces the strings of `SchemaDirective.locations`.
4. **Type references in the model are `NamedTypeReference` elements** (Task 2). Interfaces, union members and root types keep their own spans, so a validation error points at the reference, not the type. See Open question 1.
5. **Rules:**
   - new codes in id order with doc comments;
   - one rule family per class;
   - methods of at most 40 lines;
   - cycle detection is iterative;
   - the order is deterministic.
6. **Scope:**
   - every rule of spec §7;
   - `ValidSchema`, `InvalidSchema` and `SchemaValidator`;
   - `IntrospectionQuery`, `fromIntrospection` and `toIntrospection`;
   - `Schema.resolve` with a sealed `CoordinateTarget`;
   - the ported suites with mapping rows;
   - the introspection-JSON and coordinate hostile fuzzers, and the introspection round-trip fuzzer;
   - the documents;
   - the `Schema` accessors M4 needs (Task 3).

## Review Focus

These are the five failure modes most likely to hurt someone who validates a schema they did not write, reads an introspection result from a server they do not control, or resolves a coordinate typed by a user. Each one has tests that pin it, in the task named.

1. **Unbounded work on deep or cyclic schemas (constraint "No unbounded work").** Input-object cycles, chains of defaults, deeply wrapped types, values nested 100000 deep and directives that reach themselves must end, in linear time, without recursion. Pinned in:
   - Task 3: `deeply wrapped types compare without recursion`;
   - Task 7: `a value nested 100000 deep is checked without recursion`, `a problem deep inside a value has the whole path`;
   - Task 8: `a directive reached through another directive references itself`, `a cycle of types that does not reach the directive ends`;
   - Task 10: `a long chain is checked without recursion`, `a long chain of defaults is walked without recursion`, `a cycle through two types points at every field`.
2. **A hostile introspection result (R0.3, ruling 2).** A result with a member missing, a value of the wrong JSON type, an unknown kind, a reference to a type it does not list, or an `ofType` chain thousands of levels deep must give `GQL150`–`GQL155` diagnostics with a JSON path, never an exception. There must never be more than `maxErrors + 1` of them, and the memory must stay linear (the 22 GB incident, decision 10). Pinned in:
   - Task 15: `rejects a result without __schema`, `reports a missing member with its path`, `reports a member of the wrong JSON type`, `reports a reference to a type the result does not list`, `reports a non-null type inside a non-null type`, `reads a long ofType chain without recursion`;
   - Task 16: `throws when missing kind`, `fails on very deep (> 8 levels) lists`;
   - Task 18: `broken results never throw and reach every introspection code`, `many broken types reach the sink limit and stop there`, `a long ofType chain builds in linear memory`.
3. **Validation that misses a rule or points at the wrong place (R2.3, R2.4).** Every rule must report graphql-js's message at the element at fault; the related spans are the other elements graphql-js lists. A `ValidSchema` must come only from the validator or `assumeValid`. Pinned in:
   - Task 2: `an implemented interface has the span of its name`, `a root type added by a schema extension has a span in its source`;
   - Task 4: `a type used as three roots lists them with a serial comma`, `assumeValid wraps a schema without checking it`;
   - Task 5: `a repeat relates to the span of the first`;
   - Task 9: `a missing transitive interface points at both references`, `a field of an unknown type reports only the unknown type`;
   - Task 11: the ported `validateSchema` suite, for example `rejects a Schema where the same type is used for all root types`;
   - Task 12: the converted `buildASTSchema` / `extendSchema` rows.
4. **Introspection that loses or invents part of a schema (R2.7).** `Schema` → introspection → `Schema` must keep everything introspection can carry: descriptions, deprecations, `@specifiedBy`, `@oneOf`, every union member, defaults printed as GraphQL. It must write only what the query reads. Pinned in:
   - Task 14: `writes every union member, also one that is not an object`, `writes only the fields the query reads`, `leaves deprecated arguments out unless the query reads them`, `rejects a reference to a type the schema lacks`;
   - Task 15: `reads back what toIntrospection writes`, `leaves the built-in types and directives undeclared`;
   - Task 16: the ported `buildClientSchema` cycle tests;
   - Task 18: `introspection then build gives what introspection carries`.
5. **Coordinates that resolve to the wrong element or throw (R2.8, spec §9).** A miss, a containing element of the wrong kind, a meta-field and an introspection type must give `null`. Every element of a schema must be found by its own coordinate, and no text may make the parser or the resolver throw. Pinned in:
   - Task 17: `gives null when the containing element is missing or wrong`, `gives null for meta-fields and introspection types`, `compares targets by the elements they hold`;
   - Task 18: `the coordinate of every element resolves to it`, `hostile text never throws and reaches every outcome`, `a long hostile text gives one diagnostic`.

## M3b design decisions

These were made while writing this plan; the spec leaves them open.

1. **Validation reads the model, never the syntax.** Rules take a `Schema`, so a schema built in code (M5) is validated like one built from SDL. That is why the name rules also report repeated types, fields, arguments, enum values and directives (`GQL013` reused): SDL building drops repeats, but code does not.
2. **`ValidSchema` is a proof.** Its constructor is private. `SchemaValidator.validate` gives one, and `ValidSchema.assumeValid` is the documented escape hatch for a schema the caller has already validated (graphql-js's `assumeValid`).
3. **Rule order is graphql-js's**: roots, directives, types, then each type's members in declaration order. The rules graphql-js lacks (directive self-reference, default-value cycles) come after, so the ported suites compare whole lists.
4. **Applied directive arguments and default values are checked** against their types (`GQL123`, `GQL124`) by one `ValueChecker`. It accepts any literal for a custom scalar (there is no codec at validation time) and reports a variable in a constant.
5. **Union `possibleTypes` in introspection lists every member,** also one that is not an object, so a round trip keeps the error for the validator.
6. **`toIntrospection` writes what the query reads.**
   - Without input-value deprecation, the deprecated arguments are left out, as `includeDeprecated: false` would.
   - Directive deprecation is written only when asked for (working draft).
   - A reference to a type the schema lacks is an `ArgumentError`: introspect a validated schema.
7. **`fromIntrospection` builds what it can and leaves kinds to the validator.** An input type used as a field type, a root of the wrong kind or a union of interfaces builds, and `SchemaValidator` reports it. Only what cannot be built is a `GQL150`–`GQL155` diagnostic: a missing member, a wrong JSON type, an unknown kind, an unknown type name, an unterminated `ofType` chain, a non-null inside a non-null.
8. **Built-ins in an introspection result stay built-in.**
   - Built-in scalars, introspection types and specified directives in the result are not declared.
   - Listing `@defer` or `@stream` turns on `includesDeferAndStream`.
   - A missing `directives` key means none are declared.
9. **`@deprecated` is read back without its default reason.** `isDeprecated: true` with the default reason, or none, becomes `@deprecated`, so SDL → introspection → SDL prints the same text.
10. **The introspection reader keeps parents, not paths.** `IntrospectionObject` holds its parent and the step from it; the path is built only when a problem is reported. Copying the path per level made a 100000-level `ofType` chain cost about 22 GB: the kernel killed the test process, and the session with it. A parent link keeps it linear (218 MB measured).
11. **Coordinates resolve to `null`** when an element is missing, as spec §9 says; graphql-js throws for a coordinate whose parent is of the wrong kind. Meta-fields and introspection types have no coordinate.
12. **The documentation follows M3c's rules and the handoff.**
    - Validation and coordinates are sections of M3c's Schema guide. Introspection gets its own guide `doc/introspection.md` and dartdoc category `introspection` (for `lib/src/schema/introspection/`, as `scalars` is for `schema/scalars/`), as the brief and the handoff's M3c row ask; M3c's plan had put it in the Schema guide (finding 10, Open question 6).
    - Each new exported type gets its `{@category}` tag in the task that creates it (Tasks 1, 2, 4, 13, 17), in the format of M3c's tagging script, so M3c's `category_tags_test.dart` passes after every task.
    - Each guide section comes with the task that adds its API (Tasks 4, 13, 14, 15, 17); Task 1 keeps M3c's Built-ins program right, and Task 19 updates what M3c's other guides, the README and the handoff say about the stage.
    - The compiling snippets are the guide programs, which M3c's `doc_snippets_test.dart` runs and compares.
    - `example/example.dart` is the README tour, which M3b does not change.
    - M3b exports nothing from `lib/src/validation/`; `schema/validation/` and `schema/coordinates/` are in the `schema` category, like the rest of the layer.

## Spec deviations and findings

Bring these to the user with the plan.

1. **Spec §7 was incomplete.** It lacked:
   - unknown types and directives (`GQL116`, `GQL117`);
   - applied-directive arguments and locations (`GQL118`–`GQL122`);
   - default-value validity and default-value cycles (`GQL123`, `GQL149`);
   - repeats in code-built schemas.

   Task 6 adds them to §7.
2. **"`@oneOf` must not be provided by an input extension"** cannot be checked. The model merges extensions into the type (M3a decision 3), so nothing tells which part applied `@oneOf`.
3. **Spec §8 said `DecodeFailure`** for a malformed introspection result. Ruling 2 makes it diagnostics in a `BuildResult`; Task 15 updates §8 and §13.
4. **Spec §9 says `null`** where the specification's resolution algorithm raises an error (a member of a scalar, an argument of a type). The plan keeps `null` (decision 11).
5. **`GQL013` is reused** for repeats found by validation: the problem is the one the parser and the builder already name.
6. **graphql-js lacks the §3.13 rule that a directive must not reference itself** (`GQL130`). The plan follows the specification, and no ported test contradicts it.
7. **September2025 introspection has no directive deprecation;** graphql-js 17 has it (working draft). `IntrospectionQuery.full` leaves it out, and `includesDirectiveDeprecation` asks for it.
8. **Messages that differ from graphql-js:** "Unknown type" names the coordinate of the reference, and there are no "Did you mean" suggestions. The rows say so.
9. **Rows that assert `InvalidSchema` where graphql-js only builds:** "Can build recursive Union" and "can build invalid schema" now also validate, since validation exists.
10. **The order of M3b and M3c, and two descriptions of M3b's documentation.** The roadmap lists M3c as depending on M3b, but M3c ran first and is merged; correct the roadmap's M3c row.
    - M3c's plan ("How M3b extends these guides") puts introspection in the Schema guide; the handoff's M3c row and the original brief ask for `doc/introspection.md` and a new category. The plan follows the handoff (decision 12).
    - Task 1 breaks one of M3c's guide programs: the Built-ins program prints `SchemaDirective.locations`, which would print `DirectiveLocation.fieldDefinition` instead of `FIELD_DEFINITION`. So Task 1 fixes it.
11. **A fuzzer generator bug, fixed in Task 18.** The SDL fuzzers' `RandomSchema._unique` avoided a `__` prefix but not the name `_`, which its `_<index>` suffix turned into `__1`. Only the coordinate fuzzer noticed, because `__` names resolve to `null`.
12. **What could not be verified locally:**
    - the CI matrix on exactly 3.13.0, macOS and Windows;
    - the browser runs under `ulimit -v`: Chrome cannot start there, so they ran under a systemd memory scope (the handoff says CI covers them).

## File map

New files first, in task order, then the existing files the plan changes.

| Path | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/language/ast/directive_location.dart` | A place where a directive may be applied (spec §3.13, `DirectiveLocation`) | 1 |
| `packages/typed_graphql/test/language/ast/directive_location_test.dart` | Tests | 1 |
| `packages/typed_graphql/lib/src/schema/model/named_type_reference.dart` | A reference to a named type by its name, with the place it was written | 2 |
| `packages/typed_graphql/test/schema/build/reference_spans_test.dart` | Tests | 2 |
| `packages/typed_graphql/lib/src/schema/relations/implementation_index.dart` | The object and interface types that declare each interface, in declaration order | 3 |
| `packages/typed_graphql/lib/src/schema/relations/type_comparator.dart` | Compares type references (spec §3.6.1 `IsValidImplementationFieldType`, graphql-js's `typeComparators`) without recursion, so a deeply wrapped type cannot overflow the stack | 3 |
| `packages/typed_graphql/test/schema/relations/type_comparator_test.dart` | Tests | 3 |
| `packages/typed_graphql/test/schema/schema_relations_test.dart` | Tests | 3 |
| `packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart` | The rules of the root operation types (spec §3.3.1) | 4 |
| `packages/typed_graphql/lib/src/schema/validation/schema_validation_result.dart` | The result of validating a schema | 4 |
| `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart` | Checks a schema against the type-system rules of the specification (spec §7 | 4 |
| `packages/typed_graphql/lib/src/schema/validation/validation_report.dart` | Collects the errors of one schema validation in the order the rules report them, as graphql-js's `validateSchema` does, up to a [DiagnosticSink]'s limit | 4 |
| `packages/typed_graphql/test/schema/validated.dart` | `Validated`: test helper that builds SDL and validates it | 4 |
| `packages/typed_graphql/test/schema/validation/root_type_rules_test.dart` | Tests | 4 |
| `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart` | The rules of the arguments of one field or directive definition (spec §3.6.1, §3.13) | 5 |
| `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart` | The rules of the directive definitions of a schema (spec §3.13), as graphql-js's `validateDirectives` | 5 |
| `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart` | The rules of an enum type (spec §3.9) | 5 |
| `packages/typed_graphql/lib/src/schema/validation/field_rules.dart` | The rules of the fields of an object or interface type (spec §3.6, §3.7) | 5 |
| `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart` | The rules of an input object type (spec §3.10) | 5 |
| `packages/typed_graphql/lib/src/schema/validation/name_rules.dart` | The rules every name of a schema follows | 5 |
| `packages/typed_graphql/lib/src/schema/validation/type_rules.dart` | The rules of the named types of a schema (spec §3.4–§3.10), type by type in declaration order, as graphql-js's `validateTypes` | 5 |
| `packages/typed_graphql/lib/src/schema/validation/unique_names.dart` | The rule that the elements of one list have different names | 5 |
| `packages/typed_graphql/test/schema/validation/name_rules_test.dart` | Tests | 5 |
| `packages/typed_graphql/test/schema/validation/unique_names_test.dart` | Tests | 5 |
| `packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart` | The rules of the directives applied to a schema element (spec §3.13, §5.7) | 6 |
| `packages/typed_graphql/lib/src/schema/validation/interface_rules.dart` | The rules of the interfaces an object or interface type implements (spec §3.6, §3.7) | 6 |
| `packages/typed_graphql/lib/src/schema/validation/node_span.dart` | The span of a syntax node held by a schema element, such as a field's type or an argument's default value, so an error points where graphql-js points | 6 |
| `packages/typed_graphql/lib/src/schema/validation/type_reference_rules.dart` | The rule that a type named by a schema element exists (spec §3.4) | 6 |
| `packages/typed_graphql/lib/src/schema/validation/union_rules.dart` | The rules of a union type (spec §3.8) | 6 |
| `packages/typed_graphql/test/schema/validation/applied_directive_rules_test.dart` | Tests | 6 |
| `packages/typed_graphql/test/schema/validation/type_reference_rules_test.dart` | Tests | 6 |
| `packages/typed_graphql/lib/src/schema/validation/default_value_rules.dart` | The rule that the default value of an argument or an input field is a value of its type (spec §3.6.1, §3.10), as graphql-js's `validateDefaultValue` for a literal default | 7 |
| `packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart` | Whether a constant literal is a value of a scalar or enum type, with the messages of graphql-js's `coerceInputLiteral` of the built-in scalars and of `GraphQLEnumType` (spec §3.5, §3.9) | 7 |
| `packages/typed_graphql/lib/src/schema/validation/value_checker.dart` | Whether a constant value, such as a default value or an applied directive's argument, is a value of an input type (spec §3.10 "Input Coercion", graphql-js's `validateInputLiteral` without variables) | 7 |
| `packages/typed_graphql/lib/src/schema/validation/value_problem.dart` | Why a constant value is not a value of its input type | 7 |
| `packages/typed_graphql/test/schema/validation/default_value_rules_test.dart` | Tests | 7 |
| `packages/typed_graphql/test/schema/validation/value_checker_test.dart` | Tests | 7 |
| `packages/typed_graphql/lib/src/schema/validation/deprecation_rules.dart` | The rule that a required argument or input field is not deprecated (spec §3.6.1, §3.10) | 8 |
| `packages/typed_graphql/lib/src/schema/validation/directive_reference_rules.dart` | The rule that a directive definition does not reference itself, directly (`directive @d(a: Int @d)`) or through the types and directives it references (spec §3.13 "Type Validation", rules 2 and 3) | 8 |
| `packages/typed_graphql/test/schema/validation/directive_definition_rules_test.dart` | Tests | 8 |
| `packages/typed_graphql/test/schema/validation/field_rules_test.dart` | Tests | 8 |
| `packages/typed_graphql/lib/src/schema/validation/implementation_rules.dart` | The rules of a type implementing one interface's fields (spec §3.6.3 `IsValidImplementation`), as graphql-js's `validateTypeImplementsInterface` | 9 |
| `packages/typed_graphql/test/schema/validation/interface_rules_test.dart` | Tests | 9 |
| `packages/typed_graphql/lib/src/schema/validation/default_value_cycle_rules.dart` | The rule that no input field's default value contains itself (spec §3.10, "default values must not form a cycle"), as graphql-js's `createInputObjectDefaultValueCircularRefsValidator` | 10 |
| `packages/typed_graphql/lib/src/schema/validation/finite_value_rules.dart` | The rule that every input object type can be given a finite value (spec §3.10.1 `InputObjectHasUnbreakableCycle`), as graphql-js's `detectInputObjectNonFiniteValues` | 10 |
| `packages/typed_graphql/test/schema/validation/input_cycle_rules_test.dart` | Tests | 10 |
| `packages/typed_graphql/test/schema/validation/union_enum_rules_test.dart` | Tests | 10 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_field_types_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_inputs_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_interfaces_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_objects_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_one_of_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_roots_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/schema/validate_schema_unions_test.dart` | Tests | 11 |
| `packages/typed_graphql_conformance/test/support/validation_port.dart` | `ValidationPort`: validates SDL and compares graphql-js-shaped errors | 11 |
| `packages/typed_graphql/doc/introspection.md` | The Introspection guide: the query, a schema's answer, reading an answer | 13 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_query.dart` |  | 13 |
| `packages/typed_graphql/test/schema/introspection/introspection_query_test.dart` | Tests | 13 |
| `packages/typed_graphql_conformance/test/schema/introspection_query_test.dart` | Tests | 13 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart` | Writes a schema as the `data` of its answer to an [IntrospectionQuery] (graphql-js's `introspectionFromSchema`), without executing the query | 14 |
| `packages/typed_graphql/lib/src/schema/introspection/type_ref_writer.dart` | Writes type references as the introspection query's `TypeRef` fragment reads them | 14 |
| `packages/typed_graphql/lib/src/schema/introspection/type_writer.dart` | Writes named types as the introspection query's `FullType` fragment reads them, and arguments and input fields as its `InputValue` fragment does (spec §4.2) | 14 |
| `packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart` | Tests | 14 |
| `packages/typed_graphql/lib/src/schema/introspection/directive_definition_reader.dart` | Reads the directives of an introspection result (graphql-js's `buildDirective`) | 15 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_annotations.dart` | The applied directives that stand for what introspection reports as fields | 15 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_object.dart` | One object of an introspection result, read member by member | 15 |
| `packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart` | Reads the `data` of an introspection result into a schema (graphql-js's `buildClientSchema`), reporting every structural problem into [sink] | 15 |
| `packages/typed_graphql/lib/src/schema/introspection/member_reader.dart` | Reads the fields, input values and enum values of an introspection result (graphql-js's `buildField`, `buildInputValue` and `buildEnumDef`) | 15 |
| `packages/typed_graphql/lib/src/schema/introspection/named_type_reader.dart` | Reads one type of an introspection result's `types` by its `kind` (graphql-js's `buildType`) | 15 |
| `packages/typed_graphql/lib/src/schema/introspection/type_ref_reader.dart` | Reads the `TypeRef` objects of an introspection result into type references (graphql-js's `getType` in `buildClientSchema`) | 15 |
| `packages/typed_graphql/test/schema/introspection/introspection_reader_test.dart` | Tests | 15 |
| `packages/typed_graphql_conformance/test/schema/introspection_from_schema_test.dart` | Tests | 15 |
| `packages/typed_graphql_conformance/test/schema/build_client_schema_directives_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/schema/build_client_schema_errors_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/schema/build_client_schema_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/support/introspection_port.dart` | `IntrospectionPort`: `cycleIntrospection` and editable introspection results | 16 |
| `packages/typed_graphql/lib/src/schema/coordinates/coordinate_resolver.dart` | Finds the element a schema coordinate names in [schema] (September2025 §2.14, "Resolving a Schema Coordinate") | 17 |
| `packages/typed_graphql/lib/src/schema/coordinates/coordinate_target.dart` | The schema element a schema coordinate names (September2025 §2.14), as `Schema.resolve` finds it | 17 |
| `packages/typed_graphql/test/schema/coordinates/coordinate_resolver_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/schema/resolve_schema_coordinate_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/fuzz/coordinate_fuzz_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/fuzz/hostile_introspection_fuzz_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/fuzz/introspection_mutator.dart` | `IntrospectionMutator`: breaks an introspection result the ways a server can | 18 |
| `packages/typed_graphql_conformance/test/fuzz/introspection_round_trip_fuzz_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/fuzz/introspection_view.dart` | `IntrospectionView`: the closed and the carried views of a random schema | 18 |
| `packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart` | `SchemaMapper`: rebuilds a schema with its types, references and directives mapped | 18 |
| `CLAUDE.md` | Repository guide: the schema layer (relations, validation, introspection, coordinates), the status | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17, 18, 19 |
| `packages/typed_graphql/CHANGELOG.md` | User-facing changes of the core | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 17, 19 |
| `packages/typed_graphql/doc/schema.md` | M3c's Schema guide: validation, coordinates | 1, 4, 17 |
| `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart` | Modified | 1 |
| `packages/typed_graphql/lib/src/schema/build/element_reader.dart` | Modified | 1, 2 |
| `packages/typed_graphql/lib/src/schema/model/schema_directive.dart` | Modified | 1 |
| `packages/typed_graphql/lib/src/schema/print/type_printer.dart` | Modified | 1, 2 |
| `packages/typed_graphql/lib/typed_graphql.dart` | The barrel: the new public types | 1, 2, 4, 13, 17 |
| `packages/typed_graphql_conformance/test/fuzz/random_schema.dart` | Modified | 1, 2, 18 |
| `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart` | Modified | 1, 2 |
| `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart` | Modified | 2 |
| `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart` | Modified | 2 |
| `packages/typed_graphql/lib/src/schema/build/type_extender.dart` | Modified | 2 |
| `packages/typed_graphql/lib/src/schema/build/type_reader.dart` | Modified | 2 |
| `packages/typed_graphql/lib/src/schema/model/schema_type.dart` | Modified | 2, 3 |
| `packages/typed_graphql/lib/src/schema/schema.dart` | Modified | 2, 3, 14, 17 |
| `packages/typed_graphql_conformance/test/support/schema_port.dart` | Modified | 2, 12 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | The catalog: `GQL111`–`GQL155` | 4, 5, 6, 7, 8, 9, 10, 15 |
| `docs/superpowers/specs/2026-10-14-m3-type-system-design.md` | Stage spec: §7 completed, §8 and §13 (ruling 2) | 6, 15 |
| `packages/typed_graphql_conformance/CHANGELOG.md` | Changes of the conformance package | 11, 12, 13, 15, 16, 17, 18 |
| `packages/typed_graphql_conformance/mapping/schema.csv` | Conformance mapping rows | 11, 12, 13, 15, 16, 17 |
| `packages/typed_graphql/README.md` | Package README: status and the guide table | 13, 19 |
| `packages/typed_graphql/dartdoc_options.yaml` | The dartdoc categories: `introspection` | 13 |
| `packages/typed_graphql/doc/getting_started.md` | M3c's Getting Started guide: the layer table | 13, 19 |
| `packages/typed_graphql/lib/src/schema/build/schema_builder.dart` | Modified | 15 |
| `packages/typed_graphql/doc/language.md` | M3c's Language guide: a pointer to resolving | 17 |
| `docs/superpowers/HANDOFF.md` | Where the work stands | 19 |
| `packages/typed_graphql/doc/diagnostics.md` | M3c's Diagnostics guide: what reports diagnostics | 19 |

## The green check

Every task ends with this check. "Green" means each command exits 0. Each command runs under a memory limit and a timeout, one at a time, so that a runaway test fails fast instead of taking the machine (decision 10):

```sh
ulimit -v 8000000
timeout 300 dart pub get
timeout 300 dart format --output=none --set-exit-if-changed packages test
timeout 600 dart analyze --fatal-infos
timeout 600 dart test
for p in packages/*/; do (cd "$p" && timeout 600 dart test) || exit 1; done
```

Run a new test file alone first under the same limits; `/usr/bin/time -v` prints its peak memory. With M3c merged, the core suite includes M3c's documentation tests, which run each guide program as a `dart` process (about 25 s). With `reference/` fetched, the conformance suite also runs the coverage checks; run `tool/fetch_reference.sh` once before Task 11. If a run is killed (exit 137) or times out (exit 124), find the cause before going on.

---

### Task 1: Type directive locations as `DirectiveLocation`

Ruling 3. The enum lives in the language layer because the parser checks a directive definition's locations against it; the schema model then holds the values instead of strings. M3c's Built-ins program prints `SchemaDirective.locations`, so this task also changes that program to print the spellings (finding 10).

**Files:**
- Create: `packages/typed_graphql/lib/src/language/ast/directive_location.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/schema.md`, `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart`, `packages/typed_graphql/lib/src/schema/build/element_reader.dart`, `packages/typed_graphql/lib/src/schema/model/schema_directive.dart`, `packages/typed_graphql/lib/src/schema/print/type_printer.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/language/ast/directive_location_test.dart`, `packages/typed_graphql/test/schema/build/built_ins_test.dart`, `packages/typed_graphql/test/schema/build/element_reader_test.dart`, `packages/typed_graphql/test/schema/model/schema_members_test.dart`, `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart`

**Interfaces:**
- Consumes: M2 `TypeSystemParser` (directive definitions), M3a `SchemaDirective`, `ElementReader`, `TypePrinter`; M3c `doc/schema.md` ("Built-ins").
- Produces:
```text
enum DirectiveLocation { query('QUERY'), mutation, subscription, field, fragmentDefinition, fragmentSpread,
  inlineFragment, variableDefinition, schema, scalar, object, fieldDefinition, argumentDefinition, interface,
  union, enumType('ENUM'), enumValue, inputObject, inputFieldDefinition, directiveDefinition }
  final String spelling;                              // the SDL name, e.g. 'FIELD_DEFINITION'
  static DirectiveLocation? named(String spelling);
  bool get isExecutable;
SchemaDirective.locations: List<DirectiveLocation>    // **Breaking:** was List<String>
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/language/ast/directive_location_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  test('spells every location as the spec does', () {
    expect(DirectiveLocation.values.map((location) => location.spelling), [
      'QUERY',
      'MUTATION',
      'SUBSCRIPTION',
      'FIELD',
      'FRAGMENT_DEFINITION',
      'FRAGMENT_SPREAD',
      'INLINE_FRAGMENT',
      'VARIABLE_DEFINITION',
      'SCHEMA',
      'SCALAR',
      'OBJECT',
      'FIELD_DEFINITION',
      'ARGUMENT_DEFINITION',
      'INTERFACE',
      'UNION',
      'ENUM',
      'ENUM_VALUE',
      'INPUT_OBJECT',
      'INPUT_FIELD_DEFINITION',
      'DIRECTIVE_DEFINITION',
    ]);
  });

  test('finds a location by its spelling', () {
    expect(
      DirectiveLocation.named('INPUT_FIELD_DEFINITION'),
      DirectiveLocation.inputFieldDefinition,
    );
    expect(DirectiveLocation.named('ENUM'), DirectiveLocation.enumType);
  });

  test('finds nothing for another spelling', () {
    expect(DirectiveLocation.named('field'), isNull);
    expect(DirectiveLocation.named('FIELDS'), isNull);
  });

  test('the eight operation locations are executable', () {
    expect(
      DirectiveLocation.values.where((location) => location.isExecutable),
      [
        DirectiveLocation.query,
        DirectiveLocation.mutation,
        DirectiveLocation.subscription,
        DirectiveLocation.field,
        DirectiveLocation.fragmentDefinition,
        DirectiveLocation.fragmentSpread,
        DirectiveLocation.inlineFragment,
        DirectiveLocation.variableDefinition,
      ],
    );
  });
}
```

In `packages/typed_graphql/test/schema/build/built_ins_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -30,10 +30,10 @@ void main() {
   test('defines @deprecated as September2025 does', () {
     final deprecated = builtIns.directiveNamed('deprecated')!;
     expect(deprecated.locations, [
-      'FIELD_DEFINITION',
-      'ARGUMENT_DEFINITION',
-      'INPUT_FIELD_DEFINITION',
-      'ENUM_VALUE',
+      DirectiveLocation.fieldDefinition,
+      DirectiveLocation.argumentDefinition,
+      DirectiveLocation.inputFieldDefinition,
+      DirectiveLocation.enumValue,
     ]);
     final reason = deprecated.argumentNamed('reason')!;
     expect(const Printer().print(reason.type), 'String!');
@@ -49,7 +49,7 @@ void main() {
       'if',
       'label',
     ]);
-    expect(builtIns.stream.locations, ['FIELD']);
+    expect(builtIns.stream.locations, [DirectiveLocation.field]);
     expect(builtIns.stream.arguments.map((argument) => argument.name), [
       'initialCount',
       'if',
@@ -96,11 +96,19 @@ void main() {
   });
 
   test('gives the specified directives their locations', () {
-    const common = ['FIELD', 'FRAGMENT_SPREAD', 'INLINE_FRAGMENT'];
+    const common = [
+      DirectiveLocation.field,
+      DirectiveLocation.fragmentSpread,
+      DirectiveLocation.inlineFragment,
+    ];
     expect(builtIns.directiveNamed('include')!.locations, common);
     expect(builtIns.directiveNamed('skip')!.locations, common);
-    expect(builtIns.directiveNamed('specifiedBy')!.locations, ['SCALAR']);
-    expect(builtIns.directiveNamed('oneOf')!.locations, ['INPUT_OBJECT']);
+    expect(builtIns.directiveNamed('specifiedBy')!.locations, [
+      DirectiveLocation.scalar,
+    ]);
+    expect(builtIns.directiveNamed('oneOf')!.locations, [
+      DirectiveLocation.inputObject,
+    ]);
   });
 
   test('types introspection fields with their nullability', () {
@@ -142,7 +150,10 @@ void main() {
     expect(defaultOf(builtIns.defer, 'label'), isNull);
     expect(defaultOf(builtIns.stream, 'initialCount'), '0');
     expect(defaultOf(builtIns.stream, 'if'), 'true');
-    expect(builtIns.defer.locations, ['FRAGMENT_SPREAD', 'INLINE_FRAGMENT']);
+    expect(builtIns.defer.locations, [
+      DirectiveLocation.fragmentSpread,
+      DirectiveLocation.inlineFragment,
+    ]);
   });
 
   test('finds a scalar or an introspection type by name', () {
```

In `packages/typed_graphql/test/schema/build/element_reader_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -90,11 +90,22 @@ directive @auth(role: String) repeatable on FIELD_DEFINITION | OBJECT
       expect(directive.name, 'auth');
       expect(directive.description, 'Marks a field');
       expect(directive.isRepeatable, isTrue);
-      expect(directive.locations, ['FIELD_DEFINITION', 'OBJECT']);
+      expect(directive.locations, [
+        DirectiveLocation.fieldDefinition,
+        DirectiveLocation.object,
+      ]);
       expect(directive.arguments.single.name, 'role');
       expect(directive.span?.location, const SourceLocation(11, 1));
     });
 
+    test('rejects a location no parser accepts, in a node built in code', () {
+      final node = DirectiveDefinition(
+        const Name('d'),
+        locations: const [Name('FIELDS')],
+      );
+      expect(() => reader.directive(node), throwsArgumentError);
+    });
+
     test('gives no spans without a source', () {
       const reader = ElementReader(NodeSpans(null));
       final field = reader.field(type.fields.single);
```

In `packages/typed_graphql/test/schema/model/schema_members_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,7 +64,7 @@ void main() {
     test('reads the first of two @deprecated', () {
       final directive = SchemaDirective(
         'd',
-        locations: ['FIELD'],
+        locations: [.field],
         appliedDirectives: [
           deprecated(const StringValue('first')),
           deprecated(const StringValue('second')),
@@ -98,9 +98,15 @@ void main() {
   });
 
   test('a directive definition is not repeatable by default', () {
-    final directive = SchemaDirective('d', locations: ['FIELD', 'QUERY']);
+    final directive = SchemaDirective(
+      'd',
+      locations: [.field, .query],
+    );
     expect(directive.isRepeatable, isFalse);
-    expect(directive.locations, ['FIELD', 'QUERY']);
+    expect(directive.locations, [
+      DirectiveLocation.field,
+      DirectiveLocation.query,
+    ]);
   });
 
   test('an input value keeps its default value node', () {
@@ -115,7 +121,7 @@ void main() {
 
   test('the lists of a field and a directive cannot be modified', () {
     final field = SchemaField('f', const NamedType(Name('String')));
-    final directive = SchemaDirective('d', locations: ['FIELD']);
+    final directive = SchemaDirective('d', locations: [.field]);
     expect(
       () => field.arguments.add(InputValue('a', field.type)),
       throwsUnsupportedError,
@@ -124,14 +130,14 @@ void main() {
       () => field.appliedDirectives.add(AppliedDirective('x')),
       throwsUnsupportedError,
     );
-    expect(() => directive.locations.add('QUERY'), throwsUnsupportedError);
+    expect(() => directive.locations.add(.query), throwsUnsupportedError);
   });
 
   test('an element does not see the list it was built from change', () {
-    final locations = ['FIELD'];
+    final locations = [DirectiveLocation.field];
     final directive = SchemaDirective('d', locations: locations);
-    locations.add('QUERY');
-    expect(directive.locations, ['FIELD']);
+    locations.add(.query);
+    expect(directive.locations, [DirectiveLocation.field]);
   });
 
   test('an element keeps its description and span', () {
```

In `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,26 +13,9 @@ final class RandomSchema {
   final RandomParts parts;
 
   /// The 19 directive locations of the September2025 edition.
-  static const List<String> _locations = [
-    'QUERY',
-    'MUTATION',
-    'SUBSCRIPTION',
-    'FIELD',
-    'FRAGMENT_DEFINITION',
-    'FRAGMENT_SPREAD',
-    'INLINE_FRAGMENT',
-    'VARIABLE_DEFINITION',
-    'SCHEMA',
-    'SCALAR',
-    'OBJECT',
-    'FIELD_DEFINITION',
-    'ARGUMENT_DEFINITION',
-    'INTERFACE',
-    'UNION',
-    'ENUM',
-    'ENUM_VALUE',
-    'INPUT_OBJECT',
-    'INPUT_FIELD_DEFINITION',
+  static final List<DirectiveLocation> _locations = [
+    for (final location in DirectiveLocation.values)
+      if (location != .directiveDefinition) location,
   ];
 
   /// A schema of up to six types and two directive definitions. A type
```

In `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -54,7 +54,7 @@ final class SchemaDump {
   List<String> _directive(SchemaDirective directive) => [
     ..._described(
       'directive ${directive.name} repeatable ${directive.isRepeatable} '
-      'on ${directive.locations.join(' | ')}',
+      'on ${directive.locations.map((location) => location.spelling).join(' | ')}',
       directive.description,
       directive.appliedDirectives,
     ),
```

In `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -56,7 +56,7 @@ void main() {
             'someDirective',
             description: '',
             arguments: arguments(),
-            locations: ['QUERY'],
+            locations: [.query],
           ),
         ],
       );
```

In `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -275,7 +275,7 @@ void main() {
     test('Prints custom directives', () {
       final schema = Schema(
         directives: [
-          SchemaDirective('simpleDirective', locations: ['FIELD']),
+          SchemaDirective('simpleDirective', locations: [.field]),
           SchemaDirective(
             'complexDirective',
             description: 'Complex Directive',
@@ -284,7 +284,7 @@ void main() {
               port.input('intArg', 'Int', defaultValue: '-1'),
             ],
             isRepeatable: true,
-            locations: ['FIELD', 'QUERY'],
+            locations: [.field, .query],
           ),
         ],
       );
@@ -304,7 +304,7 @@ void main() {
         directives: [
           SchemaDirective(
             'deprecatedDirective',
-            locations: ['FIELD'],
+            locations: [.field],
             appliedDirectives: port.applied(
               '@deprecated(reason: "Use another directive")',
             ),
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/language/ast/directive_location_test.dart test/schema/build/built_ins_test.dart test/schema/build/element_reader_test.dart test/schema/model/schema_members_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/schema/print_schema_descriptions_test.dart test/schema/print_schema_types_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+0 -4: Some tests failed.`; the first messages: `Error: Undefined name 'DirectiveLocation'.`. `typed_graphql_conformance` ends with `+0 -2: Some tests failed.`; the first messages: `Error: The static getter or field 'query' isn't defined for the type 'String'.`, `Error: The static getter or field 'field' isn't defined for the type 'String'.`.

- [ ] **Step 3: Write the implementation**

The parser checks a location with `DirectiveLocation.named` instead of its own string set, with the messages it had before. `ElementReader` maps the parsed names; a code-built node with another spelling is an `ArgumentError` (a programmer error: the parser never makes one). `TypePrinter` prints `spelling`.

Create `packages/typed_graphql/lib/src/language/ast/directive_location.dart`:

```dart
/// A place where a directive may be applied (spec §3.13,
/// `DirectiveLocation`): the nineteen locations of the September2025
/// edition and the working draft's [directiveDefinition].
///
/// A directive definition names its locations in [spelling]: `FIELD`,
/// `INPUT_FIELD_DEFINITION`. The values are in the order of the spec's
/// grammar, executable locations first.
///
/// {@category language}
enum DirectiveLocation(
  /// The name a directive definition and introspection use, such as
  /// `FIELD_DEFINITION`.
  final String spelling,
) {
  /// `QUERY`: a query operation.
  query('QUERY'),

  /// `MUTATION`: a mutation operation.
  mutation('MUTATION'),

  /// `SUBSCRIPTION`: a subscription operation.
  subscription('SUBSCRIPTION'),

  /// `FIELD`: a field of a selection set.
  field('FIELD'),

  /// `FRAGMENT_DEFINITION`: a fragment definition.
  fragmentDefinition('FRAGMENT_DEFINITION'),

  /// `FRAGMENT_SPREAD`: a fragment spread.
  fragmentSpread('FRAGMENT_SPREAD'),

  /// `INLINE_FRAGMENT`: an inline fragment.
  inlineFragment('INLINE_FRAGMENT'),

  /// `VARIABLE_DEFINITION`: a variable definition of an operation.
  variableDefinition('VARIABLE_DEFINITION'),

  /// `SCHEMA`: the schema definition or a schema extension.
  schema('SCHEMA'),

  /// `SCALAR`: a scalar type.
  scalar('SCALAR'),

  /// `OBJECT`: an object type.
  object('OBJECT'),

  /// `FIELD_DEFINITION`: a field of an object or interface type.
  fieldDefinition('FIELD_DEFINITION'),

  /// `ARGUMENT_DEFINITION`: an argument of a field or a directive.
  argumentDefinition('ARGUMENT_DEFINITION'),

  /// `INTERFACE`: an interface type.
  interface('INTERFACE'),

  /// `UNION`: a union type.
  union('UNION'),

  /// `ENUM`: an enum type.
  enumType('ENUM'),

  /// `ENUM_VALUE`: a value of an enum type.
  enumValue('ENUM_VALUE'),

  /// `INPUT_OBJECT`: an input object type.
  inputObject('INPUT_OBJECT'),

  /// `INPUT_FIELD_DEFINITION`: a field of an input object type.
  inputFieldDefinition('INPUT_FIELD_DEFINITION'),

  /// `DIRECTIVE_DEFINITION`: a directive definition; working draft only
  /// (`ParserOptions.allowDirectiveExtensions`).
  directiveDefinition('DIRECTIVE_DEFINITION');

  /// The location spelled [spelling]; null when there is none.
  static DirectiveLocation? named(String spelling) {
    for (final location in values) {
      if (location.spelling == spelling) {
        return location;
      }
    }
    return null;
  }

  /// Whether it is a place in an operation, not in a schema (spec §3.13,
  /// `ExecutableDirectiveLocation`).
  bool get isExecutable => index <= variableDefinition.index;
}
```

In `packages/typed_graphql/lib/src/language/parser/type_system_parser.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../ast/directive.dart';
+import '../ast/directive_location.dart';
 import '../ast/name.dart';
 import '../ast/type_system_definition.dart';
 import 'directive_parser.dart';
@@ -45,33 +46,6 @@ final class TypeSystemParser {
     'directive',
   };
 
-  /// The working draft's location for directives on a directive
-  /// definition.
-  static const String directiveDefinitionLocation = 'DIRECTIVE_DEFINITION';
-
-  /// The September2025 directive locations (spec §3.13).
-  static const Set<String> locations = {
-    'QUERY',
-    'MUTATION',
-    'SUBSCRIPTION',
-    'FIELD',
-    'FRAGMENT_DEFINITION',
-    'FRAGMENT_SPREAD',
-    'INLINE_FRAGMENT',
-    'VARIABLE_DEFINITION',
-    'SCHEMA',
-    'SCALAR',
-    'OBJECT',
-    'FIELD_DEFINITION',
-    'ARGUMENT_DEFINITION',
-    'INTERFACE',
-    'UNION',
-    'ENUM',
-    'ENUM_VALUE',
-    'INPUT_OBJECT',
-    'INPUT_FIELD_DEFINITION',
-  };
-
   /// The definition that [keyword], one of [keywords], starts, after an
   /// optional description.
   TypeSystemDefinition definition(String keyword) => switch (keyword) {
@@ -244,22 +218,21 @@ final class TypeSystemParser {
     return directives.directives(isConst: true);
   }
 
-  /// `DirectiveLocation`: one of [locations], or the working draft's
-  /// [directiveDefinitionLocation].
+  /// `DirectiveLocation`: a [DirectiveLocation]; the working draft's
+  /// `DIRECTIVE_DEFINITION` only with [allowsDirectiveExtensions].
   Name _location() {
     final token = cursor.token;
     final name = cursor.name();
-    if (name.value == directiveDefinitionLocation) {
-      if (!allowsDirectiveExtensions) {
-        cursor.fail(
-          .workingDraftFeatureDisabled,
-          'The $directiveDefinitionLocation location is a working-draft '
-          'feature; enable it with ParserOptions.allowDirectiveExtensions.',
-          at: token,
-        );
-      }
-    } else if (!locations.contains(name.value)) {
+    final location = DirectiveLocation.named(name.value);
+    if (location == null) {
       cursor.unexpected(token);
+    } else if (location == .directiveDefinition && !allowsDirectiveExtensions) {
+      cursor.fail(
+        .workingDraftFeatureDisabled,
+        'The DIRECTIVE_DEFINITION location is a working-draft feature; '
+        'enable it with ParserOptions.allowDirectiveExtensions.',
+        at: token,
+      );
     }
     return name;
   }
```

In `packages/typed_graphql/lib/src/schema/build/element_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,7 +1,9 @@
 import '../../language/ast/directive.dart';
+import '../../language/ast/directive_location.dart';
 import '../../language/ast/enum_value_definition.dart';
 import '../../language/ast/field_definition.dart';
 import '../../language/ast/input_value_definition.dart';
+import '../../language/ast/name.dart';
 import '../../language/ast/type_system_definition.dart';
 import '../model/applied_directive.dart';
 import '../model/input_value.dart';
@@ -64,8 +66,18 @@ final class const ElementReader(
     description: node.description?.value,
     arguments: node.arguments.map(inputValue).toList(),
     isRepeatable: node.isRepeatable,
-    locations: [for (final location in node.locations) location.value],
+    locations: node.locations.map(_location).toList(),
     appliedDirectives: appliedAll(node.directives),
     span: spans.of(node),
   );
+
+  /// The location [name] spells. The parser accepts no other name, so an
+  /// unknown one comes from a document built in code: a programmer error.
+  static DirectiveLocation _location(Name name) =>
+      DirectiveLocation.named(name.value) ??
+      (throw ArgumentError.value(
+        name.value,
+        'locations',
+        'Not a directive location',
+      ));
 }
```

In `packages/typed_graphql/lib/src/schema/model/schema_directive.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../../diagnostics/source_span.dart';
+import '../../language/ast/directive_location.dart';
 import 'applied_directive.dart';
 import 'applied_directives.dart';
 import 'input_value.dart';
@@ -21,7 +22,7 @@ final class SchemaDirective(
 
   /// Whether it may be applied more than once to one place.
   final bool isRepeatable = false,
-  List<String> locations = const [],
+  List<DirectiveLocation> locations = const [],
   List<AppliedDirective> appliedDirectives = const [],
 
   /// Where it was defined; null when it was not read from SDL.
@@ -33,8 +34,8 @@ final class SchemaDirective(
   /// The arguments, in declaration order.
   final List<InputValue> arguments = List.unmodifiable(arguments);
 
-  /// The locations it may be applied to, such as `FIELD`, as written.
-  final List<String> locations = List.unmodifiable(locations);
+  /// The locations it may be applied to, in the order written.
+  final List<DirectiveLocation> locations = List.unmodifiable(locations);
 
   /// The directives applied to the definition itself, in the order written.
   final List<AppliedDirective> appliedDirectives = List.unmodifiable(
```

In `packages/typed_graphql/lib/src/schema/print/type_printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -37,7 +37,7 @@ final class const TypePrinter() {
       'directive @${directive.name}${_members.arguments(directive.arguments)}'
       '${_members.directives(directive.appliedDirectives)}'
       '${directive.isRepeatable ? ' repeatable' : ''}'
-      ' on ${directive.locations.join(' | ')}';
+      ' on ${directive.locations.map((location) => location.spelling).join(' | ')}';
 
   static String _union(List<NamedType> memberTypes) =>
       memberTypes.isEmpty ? '' : ' = ${_names(memberTypes, ' | ')}';
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,7 @@ export 'src/diagnostics/source_span.dart';
 export 'src/language/ast/argument.dart';
 export 'src/language/ast/definition.dart';
 export 'src/language/ast/directive.dart';
+export 'src/language/ast/directive_location.dart';
 export 'src/language/ast/document.dart';
 export 'src/language/ast/enum_value_definition.dart';
 export 'src/language/ast/executable_definition.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/language/ast/directive_location_test.dart test/schema/build/built_ins_test.dart test/schema/build/element_reader_test.dart test/schema/model/schema_members_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/schema/print_schema_descriptions_test.dart test/schema/print_schema_types_test.dart)
```

Expected: `typed_graphql` `+43: All tests passed!`, `typed_graphql_conformance` `+17: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+397: All tests passed!`.

- [ ] **Step 5: Update the guides**

M3c's Built-ins program printed the location strings. It now prints their spellings, so its output is unchanged, and the model table names the new type.

In `packages/typed_graphql/doc/schema.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -112,7 +112,7 @@ The elements of the model:
 | `SchemaField` | A field of an object or interface: `name`, `type`, `arguments`, `description` |
 | `InputValue` | An argument or an input field, with its `defaultValue` |
 | `SchemaEnumValue` | A value of an enum |
-| `SchemaDirective` | A directive definition: `arguments`, `isRepeatable`, `locations` |
+| `SchemaDirective` | A directive definition: `arguments`, `isRepeatable`, `locations` (`DirectiveLocation` values, whose `spelling` is the SDL name) |
 | `AppliedDirective` | A directive applied to an element, with its arguments as written |
 
 The spec's own names, `FieldDefinition`, `EnumValueDefinition` and
@@ -210,7 +210,7 @@ void main() {
   print(schema.typeNamed('__Schema')?.name);
   final deprecated = schema.directiveNamed('deprecated');
   print(deprecated?.arguments.map((argument) => argument.name).toList());
-  print(deprecated?.locations);
+  print(deprecated?.locations.map((location) => location.spelling).toList());
 
   // @defer and @stream are opt-in.
   print(schema.directiveNamed('defer'));
```

- [ ] **Step 6: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+225: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 7: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -132,7 +132,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   definition's draft parts report `GQL014` instead of a generic error.
   `Parser.parseSchemaCoordinate` runs `SchemaCoordinateParser` over a
   cursor on a `SchemaCoordinateLexer` (the cursor reads any
-  `TokenSource`); `ParserOptions` do not apply to it.
+  `TokenSource`); `ParserOptions` do not apply to it. A directive
+  definition's locations are checked against `DirectiveLocation`
+  (`ast/directive_location.dart`), whose `spelling` is the SDL name.
 - `printer/`: `Printer` prints any node as graphql-js's `print` does, to
   the character (80-column wrapping included), through collaborators:
   `ValuePrinter` (values, types, arguments, directives), `ExecutablePrinter`,
@@ -185,7 +187,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   Every element has `SourceSpan? span`. `deprecationReason`,
   `specifiedByUrl` and `isOneOf` read the applied directives through the
   internal `AppliedDirectives`; the directives stay in the element's list.
-  Elements compare by identity.
+  Elements compare by identity. `SchemaDirective.locations` are
+  `DirectiveLocation` values; a code-built node with another spelling is an
+  `ArgumentError` in the reader.
 - `build/BuiltIns` (const): the five built-in scalars, the five specified
   directives, `defer` and `stream` (graphql-js's definitions, not in the
   specified five) and the introspection types, read once from the internal
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- **Breaking:** `SchemaDirective.locations` is a `List<DirectiveLocation>`.
  `DirectiveLocation` names the nineteen September2025 locations and the
  working draft's `DIRECTIVE_DEFINITION` (`spelling`, `named`,
  `isExecutable`); the parser accepts exactly its spellings.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/schema.md packages/typed_graphql/lib/src/language/ast/directive_location.dart packages/typed_graphql/lib/src/language/parser/type_system_parser.dart packages/typed_graphql/lib/src/schema/build/element_reader.dart packages/typed_graphql/lib/src/schema/model/schema_directive.dart packages/typed_graphql/lib/src/schema/print/type_printer.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/language/ast/directive_location_test.dart packages/typed_graphql/test/schema/build/built_ins_test.dart packages/typed_graphql/test/schema/build/element_reader_test.dart packages/typed_graphql/test/schema/model/schema_members_test.dart packages/typed_graphql_conformance/test/fuzz/random_schema.dart packages/typed_graphql_conformance/test/fuzz/schema_dump.dart packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart
git commit -q -m "refactor(typed_graphql): type directive locations as DirectiveLocation" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: Give interface, union member and root references their own spans

Ruling 4 (Open question 1). A validation error about an implemented interface, a union member or a root type points at the reference, which may sit in an extension of another source. The model keeps a `NamedTypeReference` (name and span) instead of a language `NamedType`, and `Schema` keeps the span of each root name.

The diff of `schema_type.dart` was made against M3c's tagged file. If M3c's merge changed that doc comment, see "Running after M3c" in the Global Constraints.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/model/named_type_reference.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/schema/build/element_reader.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart`, `packages/typed_graphql/lib/src/schema/build/type_extender.dart`, `packages/typed_graphql/lib/src/schema/build/type_reader.dart`, `packages/typed_graphql/lib/src/schema/model/schema_type.dart`, `packages/typed_graphql/lib/src/schema/print/type_printer.dart`, `packages/typed_graphql/lib/src/schema/schema.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/build/member_filter_test.dart`, `packages/typed_graphql/test/schema/build/reference_spans_test.dart`, `packages/typed_graphql/test/schema/build/type_extender_test.dart`, `packages/typed_graphql/test/schema/build/type_reader_test.dart`, `packages/typed_graphql/test/schema/model/schema_type_test.dart`, `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart`, `packages/typed_graphql_conformance/test/support/schema_port.dart`

**Interfaces:**
- Consumes: Task 1; M3a `ElementReader`, `TypeReader`, `TypeExtender`, `SchemaDefinitionReader`, `SchemaAssembly`, `TypePrinter`, `Schema`.
- Produces:
```text
final class NamedTypeReference(String name, {SourceSpan? span})          // exported
ObjectType.interfaces, InterfaceType.interfaces: List<NamedTypeReference>  // **Breaking:** were List<NamedType>
UnionType.memberTypes: List<NamedTypeReference>                          // **Breaking**
Schema({..., Map<OperationType, SourceSpan> rootTypeSpans = const {}})
SourceSpan? Schema.rootTypeSpan(OperationType operation)                 // null for a default root
ElementReader.references(List<NamedType> nodes) -> List<NamedTypeReference>   // internal
```

- [ ] **Step 1: Write the failing tests**

In `packages/typed_graphql/test/schema/build/member_filter_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -98,7 +98,7 @@ type B { f: Int }''');
   test('keeps the interfaces and directives of a type with a repeat', () {
     final built = Built('type T implements I @d { a: Int a: Int }');
     final type = built.partial.typeNamed('T') as ObjectType;
-    expect(type.interfaces.single.name.value, 'I');
+    expect(type.interfaces.single.name, 'I');
     expect(type.appliedDirectives.single.name, 'd');
     expect(type.fields.single.name, 'a');
   });
```

Create `packages/typed_graphql/test/schema/build/reference_spans_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final base = Built('''
schema { query: Query }
interface A { a: Int }
interface B { a: Int }
type Query implements A { a: Int }
type M { a: Int }
union U = Query''').schema;

  test('an implemented interface has the span of its name', () {
    final query = base.typeNamed('Query') as ObjectType;
    final span = query.interfaces.single.span;
    expect(span?.text, 'A');
    expect(span?.location, const SourceLocation(4, 23));
  });

  test('a union member has the span of its name', () {
    final union = base.typeNamed('U') as UnionType;
    expect(
      union.memberTypes.single.span?.location,
      const SourceLocation(6, 11),
    );
  });

  test('an interface added by an extension has a span in its source', () {
    const text = 'extend type Query implements B';
    final schema = Built.extending(base, text).schema;
    final query = schema.typeNamed('Query') as ObjectType;
    final added = query.interfaces.last.span;
    expect(added?.text, 'B');
    expect(added?.source.body, text);
    expect(query.interfaces.first.span?.source, same(query.span?.source));
  });

  test('a union member added by an extension has a span in its source', () {
    const text = 'extend union U = M';
    final schema = Built.extending(base, text).schema;
    final union = schema.typeNamed('U') as UnionType;
    expect(union.memberTypes.last.span?.source.body, text);
  });

  test('a root type has the span of its name in the schema definition', () {
    final span = base.rootTypeSpan(OperationType.query);
    expect(span?.text, 'Query');
    expect(span?.location, const SourceLocation(1, 17));
  });

  test('a root type added by a schema extension has a span in its source', () {
    const text = 'extend schema { mutation: M }';
    final schema = Built.extending(base, text).schema;
    expect(schema.rootTypeSpan(OperationType.mutation)?.source.body, text);
    expect(
      schema.rootTypeSpan(OperationType.query),
      same(base.rootTypeSpan(OperationType.query)),
    );
  });

  test('a default root type has no span', () {
    final schema = Built('type Query { a: Int }').schema;
    expect(schema.queryTypeName, 'Query');
    expect(schema.rootTypeSpan(OperationType.query), isNull);
  });

  test('a schema built in code keeps the root spans it is given', () {
    final span = SourceSpan(Source('Root'), 0, 4);
    final schema = Schema(
      queryTypeName: 'Root',
      rootTypeSpans: {OperationType.query: span},
    );
    expect(schema.rootTypeSpan(OperationType.query), same(span));
    expect(schema.rootTypeSpan(OperationType.mutation), isNull);
  });
}
```

In `packages/typed_graphql/test/schema/build/type_extender_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -11,7 +11,7 @@ void main() {
         InputValue(:final name) => name,
         SchemaEnumValue(:final name) => name,
         AppliedDirective(:final name) => name,
-        NamedType(:final name) => name.value,
+        NamedTypeReference(:final name) => name,
         _ => fail('unexpected $element'),
       },
   ];
```

In `packages/typed_graphql/test/schema/build/type_reader_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -43,14 +43,14 @@ input Filter @oneOf { color: Color = RED, limit: Int }
 
   test('keeps implemented interfaces and union members as names', () {
     final query = types[1] as ObjectType;
-    expect(query.interfaces.map((type) => type.name.value), [
+    expect(query.interfaces.map((type) => type.name), [
       'Node',
       'Entity',
     ]);
     final node = types[2] as InterfaceType;
-    expect(node.interfaces.single.name.value, 'Entity');
+    expect(node.interfaces.single.name, 'Entity');
     final result = types[3] as UnionType;
-    expect(result.memberTypes.map((type) => type.name.value), [
+    expect(result.memberTypes.map((type) => type.name), [
       'Query',
       'Other',
     ]);
```

In `packages/typed_graphql/test/schema/model/schema_type_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -81,7 +81,7 @@ void main() {
   });
 
   test('a union keeps a repeated member for validation to report', () {
-    const member = NamedType(Name('A'));
+    const member = NamedTypeReference('A');
     final union = UnionType('U', memberTypes: [member, member]);
     expect(union.memberTypes, hasLength(2));
   });
@@ -93,13 +93,13 @@ void main() {
       throwsUnsupportedError,
     );
     expect(
-      () => type.interfaces.add(const NamedType(Name('I'))),
+      () => type.interfaces.add(const NamedTypeReference('I')),
       throwsUnsupportedError,
     );
   });
 
   test('every list of every kind cannot be modified', () {
-    const member = NamedType(Name('A'));
+    const member = NamedTypeReference('A');
     final additions = <void Function()>[
       () => ObjectType('T').appliedDirectives.add(AppliedDirective('d')),
       () => InterfaceType('I').interfaces.add(member),
```

In `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -71,14 +71,14 @@ final class RandomSchema {
       1 => ObjectType(
         name,
         description: description,
-        interfaces: parts.some(2, () => NamedType(parts.name())),
+        interfaces: parts.some(2, () => NamedTypeReference(parts.name().value)),
         appliedDirectives: applied,
         fields: _members(3, _field),
       ),
       2 => InterfaceType(
         name,
         description: description,
-        interfaces: parts.some(2, () => NamedType(parts.name())),
+        interfaces: parts.some(2, () => NamedTypeReference(parts.name().value)),
         appliedDirectives: applied,
         fields: _members(3, _field),
       ),
@@ -86,7 +86,10 @@ final class RandomSchema {
         name,
         description: description,
         appliedDirectives: applied,
-        memberTypes: parts.some(3, () => NamedType(parts.name())),
+        memberTypes: parts.some(
+          3,
+          () => NamedTypeReference(parts.name().value),
+        ),
       ),
       4 => EnumType(
         name,
```

In `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -31,11 +31,11 @@ final class SchemaDump {
       ScalarType() => const <String>[],
       ObjectType(:final interfaces, :final fields) ||
       InterfaceType(:final interfaces, :final fields) => [
-        'implements ${interfaces.map(_printer.print).join(' & ')}',
+        'implements ${interfaces.map((type) => type.name).join(' & ')}',
         for (final field in fields) ..._field(field),
       ],
       UnionType(:final memberTypes) => [
-        'members ${memberTypes.map(_printer.print).join(' | ')}',
+        'members ${memberTypes.map((type) => type.name).join(' | ')}',
       ],
       EnumType(:final values) => [
         for (final value in values)
```

In `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -39,7 +39,7 @@ void main() {
           UnionType(
             'SomeUnion',
             description: '',
-            memberTypes: [port.named('Query')],
+            memberTypes: [port.reference('Query')],
           ),
           ObjectType('Query', description: '', fields: fields()),
           EnumType(
```

In `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@ void main() {
         types: [
           ObjectType(
             'Bar',
-            interfaces: [port.named('Foo')],
+            interfaces: [port.reference('Foo')],
             fields: [SchemaField('str', port.type('String'))],
           ),
           InterfaceType(
@@ -44,7 +44,7 @@ void main() {
         types: [
           ObjectType(
             'Bar',
-            interfaces: [port.named('Foo'), port.named('Baz')],
+            interfaces: [port.reference('Foo'), port.reference('Baz')],
             fields: [
               SchemaField('str', port.type('String')),
               SchemaField('int', port.type('Int')),
@@ -81,7 +81,7 @@ void main() {
         types: [
           ObjectType(
             'Bar',
-            interfaces: [port.named('Foo'), port.named('Baz')],
+            interfaces: [port.reference('Foo'), port.reference('Baz')],
             fields: [
               SchemaField('str', port.type('String')),
               SchemaField('int', port.type('Int')),
@@ -93,7 +93,7 @@ void main() {
           ),
           InterfaceType(
             'Baz',
-            interfaces: [port.named('Foo')],
+            interfaces: [port.reference('Foo')],
             fields: [
               SchemaField('int', port.type('Int')),
               SchemaField('str', port.type('String')),
@@ -130,14 +130,14 @@ void main() {
     test('Print Unions', () {
       final schema = Schema(
         types: [
-          UnionType('SingleUnion', memberTypes: [port.named('Foo')]),
+          UnionType('SingleUnion', memberTypes: [port.reference('Foo')]),
           ObjectType(
             'Foo',
             fields: [SchemaField('bool', port.type('Boolean'))],
           ),
           UnionType(
             'MultipleUnion',
-            memberTypes: [port.named('Foo'), port.named('Bar')],
+            memberTypes: [port.reference('Foo'), port.reference('Bar')],
           ),
           ObjectType(
             'Bar',
```

In `packages/typed_graphql_conformance/test/support/schema_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,9 @@ final class SchemaPort {
   /// member.
   NamedType named(String name) => NamedType(Name(name));
 
+  /// A reference to the type [name], for interfaces and union members.
+  NamedTypeReference reference(String name) => NamedTypeReference(name);
+
   /// [text] as a constant value, such as `{ a: 1 }`.
   Value value(String text) =>
       _element(_parser.parseValue(Source(text), isConst: true));
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/build/member_filter_test.dart test/schema/build/reference_spans_test.dart test/schema/build/type_extender_test.dart test/schema/build/type_reader_test.dart test/schema/model/schema_type_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/schema/print_schema_descriptions_test.dart test/schema/print_schema_types_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+16 -5: Some tests failed.`; the first messages: `Error: No named parameter with the name 'rootTypeSpans'.`, `Error: The getter 'span' isn't defined for the type 'NamedType'.`, `Error: The method 'rootTypeSpan' isn't defined for the type 'Schema'.`, `Error: 'NamedTypeReference' isn't a type.`. `typed_graphql_conformance` ends with `+0 -2: Some tests failed.`; the first messages: `Error: Type 'NamedTypeReference' not found.`, `Error: The method 'NamedTypeReference' isn't defined for the type 'SchemaPort'.`.

- [ ] **Step 3: Write the implementation**

An extension's reference keeps the extension's span, unlike the type's own span, which stays the definition's. The conformance helpers and the SDL fuzzers change with the model.

In `packages/typed_graphql/lib/src/schema/build/element_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,9 +4,11 @@ import '../../language/ast/enum_value_definition.dart';
 import '../../language/ast/field_definition.dart';
 import '../../language/ast/input_value_definition.dart';
 import '../../language/ast/name.dart';
+import '../../language/ast/type_ref.dart';
 import '../../language/ast/type_system_definition.dart';
 import '../model/applied_directive.dart';
 import '../model/input_value.dart';
+import '../model/named_type_reference.dart';
 import '../model/schema_directive.dart';
 import '../model/schema_enum_value.dart';
 import '../model/schema_field.dart';
@@ -50,6 +52,12 @@ final class const ElementReader(
     span: spans.of(node),
   );
 
+  /// References to the types [nodes] name, each with its span.
+  List<NamedTypeReference> references(List<NamedType> nodes) => [
+    for (final node in nodes)
+      NamedTypeReference(node.name.value, span: spans.of(node)),
+  ];
+
   /// The directives applied to an element, in order.
   List<AppliedDirective> appliedAll(List<Directive> nodes) => [
     for (final node in nodes)
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -75,6 +75,10 @@ final class SchemaAssembly(
           header.subscriptionTypeName ?? defaults[OperationType.subscription],
       description: header.description,
       appliedDirectives: header.appliedDirectives,
+      rootTypeSpans: {
+        for (final operation in OperationType.values)
+          operation: ?header.rootTypeSpan(operation),
+      },
       includesDeferAndStream: base.includesDeferAndStream,
       span: header.span,
     );
```

In `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,6 +2,7 @@ import '../../language/ast/operation_type.dart';
 import '../../language/ast/operation_type_definition.dart';
 import '../../language/ast/type_system_definition.dart';
 import '../../language/ast/type_system_extension.dart';
+import '../model/named_type_reference.dart';
 import '../schema.dart';
 import 'build_report.dart';
 import 'element_reader.dart';
@@ -39,9 +40,12 @@ final class SchemaDefinitionReader(
     return Schema(
       types: base.types,
       directives: base.directives,
-      queryTypeName: roots[OperationType.query],
-      mutationTypeName: roots[OperationType.mutation],
-      subscriptionTypeName: roots[OperationType.subscription],
+      queryTypeName: roots[OperationType.query]?.name,
+      mutationTypeName: roots[OperationType.mutation]?.name,
+      subscriptionTypeName: roots[OperationType.subscription]?.name,
+      rootTypeSpans: {
+        for (final MapEntry(:key, :value) in roots.entries) key: ?value.span,
+      },
       description: definition?.description?.value ?? base.description,
       appliedDirectives: [
         ...base.appliedDirectives,
@@ -83,13 +87,18 @@ final class SchemaDefinitionReader(
     return hasSchema ? null : nodes.firstOrNull;
   }
 
-  Map<OperationType, String> _roots(
+  /// The root types, each with the span of the name that set it.
+  Map<OperationType, NamedTypeReference> _roots(
     Schema base,
     List<OperationTypeDefinition> nodes,
   ) {
     final roots = {
       for (final operation in OperationType.values)
-        operation: ?base.rootTypeName(operation),
+        if (base.rootTypeName(operation) case final name?)
+          operation: NamedTypeReference(
+            name,
+            span: base.rootTypeSpan(operation),
+          ),
     };
     final firsts = <OperationType, OperationTypeDefinition>{};
     for (final node in nodes) {
@@ -110,7 +119,7 @@ final class SchemaDefinitionReader(
         );
       } else {
         firsts[operation] = node;
-        roots[operation] = node.type.name.value;
+        roots[operation] = elements.references([node.type]).single;
       }
     }
     return roots;
```

In `packages/typed_graphql/lib/src/schema/build/type_extender.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -98,7 +98,7 @@ final class TypeExtender(
         memberTypes: [
           ...type.memberTypes,
           for (final node in matching.whereType<UnionTypeExtension>())
-            ...node.types,
+            ..._elements.references(node.types),
         ],
         span: type.span,
       ),
@@ -141,7 +141,7 @@ final class TypeExtender(
     interfaces: [
       ...type.interfaces,
       for (final node in nodes.whereType<ObjectTypeExtension>())
-        ...node.interfaces,
+        ..._elements.references(node.interfaces),
     ],
     appliedDirectives: _directives(type, nodes),
     fields: [
@@ -159,7 +159,7 @@ final class TypeExtender(
         interfaces: [
           ...type.interfaces,
           for (final node in nodes.whereType<InterfaceTypeExtension>())
-            ...node.interfaces,
+            ..._elements.references(node.interfaces),
         ],
         appliedDirectives: _directives(type, nodes),
         fields: [
```

In `packages/typed_graphql/lib/src/schema/build/type_reader.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -25,7 +25,7 @@ final class const TypeReader(
       node.name.value,
       description: node.description?.value,
       appliedDirectives: elements.appliedAll(node.directives),
-      memberTypes: node.types,
+      memberTypes: elements.references(node.types),
       span: elements.spans.of(node),
     ),
     EnumTypeDefinition() => _enum(node),
@@ -35,7 +35,7 @@ final class const TypeReader(
   ObjectType _object(ObjectTypeDefinition node) => ObjectType(
     node.name.value,
     description: node.description?.value,
-    interfaces: node.interfaces,
+    interfaces: elements.references(node.interfaces),
     appliedDirectives: elements.appliedAll(node.directives),
     fields: node.fields.map(elements.field).toList(),
     span: elements.spans.of(node),
@@ -44,7 +44,7 @@ final class const TypeReader(
   InterfaceType _interface(InterfaceTypeDefinition node) => InterfaceType(
     node.name.value,
     description: node.description?.value,
-    interfaces: node.interfaces,
+    interfaces: elements.references(node.interfaces),
     appliedDirectives: elements.appliedAll(node.directives),
     fields: node.fields.map(elements.field).toList(),
     span: elements.spans.of(node),
```

Create `packages/typed_graphql/lib/src/schema/model/named_type_reference.dart`:

```dart
import '../../diagnostics/source_span.dart';

/// A reference to a named type by its name, with the place it was
/// written: an interface that a type implements or a member of a union.
///
/// An extension may add a reference from another source than the type's
/// definition, so the reference carries its own span; a diagnostic about
/// it points there (spec §3.4.3).
///
/// {@category schema}
final class const NamedTypeReference(
  /// The name of the type referred to.
  final String name, {

  /// Where the reference was written; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates a reference to the type named [name].
  this;
}
```

In `packages/typed_graphql/lib/src/schema/model/schema_type.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,8 +1,8 @@
 import '../../diagnostics/source_span.dart';
-import '../../language/ast/type_ref.dart';
 import 'applied_directive.dart';
 import 'applied_directives.dart';
 import 'input_value.dart';
+import 'named_type_reference.dart';
 import 'schema_enum_value.dart';
 import 'schema_field.dart';
 
@@ -10,7 +10,8 @@ import 'schema_field.dart';
 /// types (R2.1).
 ///
 /// The language node `NamedType` is a reference to a type by name; this
-/// is the type itself. References between types are names, so a cyclic
+/// is the type itself. References between types are names (a
+/// [NamedTypeReference] for interfaces and union members), so a cyclic
 /// schema needs no `late`.
 ///
 /// {@category schema}
@@ -69,7 +70,7 @@ final class ScalarType(
 final class ObjectType(
   super.name, {
   super.description,
-  List<NamedType> interfaces = const [],
+  List<NamedTypeReference> interfaces = const [],
   super.appliedDirectives,
   List<SchemaField> fields = const [],
   super.span,
@@ -78,7 +79,7 @@ final class ObjectType(
   this;
 
   /// The interfaces it implements, by name, in declaration order.
-  final List<NamedType> interfaces = List.unmodifiable(interfaces);
+  final List<NamedTypeReference> interfaces = List.unmodifiable(interfaces);
 
   /// The fields, in declaration order.
   final List<SchemaField> fields = List.unmodifiable(fields);
@@ -94,7 +95,7 @@ final class ObjectType(
 final class InterfaceType(
   super.name, {
   super.description,
-  List<NamedType> interfaces = const [],
+  List<NamedTypeReference> interfaces = const [],
   super.appliedDirectives,
   List<SchemaField> fields = const [],
   super.span,
@@ -103,7 +104,7 @@ final class InterfaceType(
   this;
 
   /// The interfaces it implements, by name, in declaration order.
-  final List<NamedType> interfaces = List.unmodifiable(interfaces);
+  final List<NamedTypeReference> interfaces = List.unmodifiable(interfaces);
 
   /// The fields, in declaration order.
   final List<SchemaField> fields = List.unmodifiable(fields);
@@ -119,7 +120,7 @@ final class UnionType(
   super.name, {
   super.description,
   super.appliedDirectives,
-  List<NamedType> memberTypes = const [],
+  List<NamedTypeReference> memberTypes = const [],
   super.span,
 }) extends SchemaType {
   /// Creates a union type.
@@ -127,7 +128,9 @@ final class UnionType(
 
   /// The member types, by name, in declaration order; a repeated member
   /// is kept for schema validation to report.
-  final List<NamedType> memberTypes = List.unmodifiable(memberTypes);
+  final List<NamedTypeReference> memberTypes = List.unmodifiable(
+    memberTypes,
+  );
 }
 
 /// An enum type, `enum Name { VALUES }` (spec §3.9).
```

In `packages/typed_graphql/lib/src/schema/print/type_printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,4 @@
-import '../../language/ast/type_ref.dart';
+import '../model/named_type_reference.dart';
 import '../model/schema_directive.dart';
 import '../model/schema_type.dart';
 import 'member_printer.dart';
@@ -39,12 +39,12 @@ final class const TypePrinter() {
       '${directive.isRepeatable ? ' repeatable' : ''}'
       ' on ${directive.locations.map((location) => location.spelling).join(' | ')}';
 
-  static String _union(List<NamedType> memberTypes) =>
+  static String _union(List<NamedTypeReference> memberTypes) =>
       memberTypes.isEmpty ? '' : ' = ${_names(memberTypes, ' | ')}';
 
-  static String _interfaces(List<NamedType> interfaces) =>
+  static String _interfaces(List<NamedTypeReference> interfaces) =>
       interfaces.isEmpty ? '' : ' implements ${_names(interfaces, ' & ')}';
 
-  static String _names(List<NamedType> types, String separator) =>
-      types.map((type) => type.name.value).join(separator);
+  static String _names(List<NamedTypeReference> types, String separator) =>
+      types.map((type) => type.name).join(separator);
 }
```

In `packages/typed_graphql/lib/src/schema/schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -32,6 +32,8 @@ final class Schema({
   final String? description,
   List<AppliedDirective> appliedDirectives = const [],
 
+  Map<OperationType, SourceSpan> rootTypeSpans = const {},
+
   /// Whether `@defer` and `@stream` exist in this schema (an opt-in, as
   /// graphql-js defines them; R2.6).
   final bool includesDeferAndStream = false,
@@ -55,6 +57,11 @@ final class Schema({
     appliedDirectives,
   );
 
+  // Only for lookups, never iterated.
+  final Map<OperationType, SourceSpan> _rootTypeSpans = Map.unmodifiable(
+    rootTypeSpans,
+  );
+
   // Only for lookups, never iterated. Built from the end, so the first of
   // two types with one name wins, as the builder keeps the first.
   final Map<String, SchemaType> _typesByName = {
@@ -89,6 +96,11 @@ final class Schema({
     };
   }
 
+  /// Where the root type of [operation] was named, as `query: Query` in a
+  /// schema definition or extension; null when it was not named in SDL.
+  SourceSpan? rootTypeSpan(OperationType operation) =>
+      _rootTypeSpans[operation];
+
   /// The name of the root type of [operation]; null when there is none.
   String? rootTypeName(OperationType operation) => switch (operation) {
     .query => queryTypeName,
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -68,6 +68,7 @@ export 'src/schema/build/built_ins.dart';
 export 'src/schema/build/schema_builder.dart';
 export 'src/schema/model/applied_directive.dart';
 export 'src/schema/model/input_value.dart';
+export 'src/schema/model/named_type_reference.dart';
 export 'src/schema/model/schema_directive.dart';
 export 'src/schema/model/schema_enum_value.dart';
 export 'src/schema/model/schema_field.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/build/member_filter_test.dart test/schema/build/reference_spans_test.dart test/schema/build/type_extender_test.dart test/schema/build/type_reader_test.dart test/schema/model/schema_type_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/schema/print_schema_descriptions_test.dart test/schema/print_schema_types_test.dart)
```

Expected: `typed_graphql` `+57: All tests passed!`, `typed_graphql_conformance` `+17: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+397: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -181,8 +181,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `NamedType` already name language nodes, so the schema's take a
   `Schema` prefix. `SchemaType` is the sealed family of named types
   (`ScalarType`, `ObjectType`, `InterfaceType`, `UnionType`, `EnumType`,
-  `InputObjectType`). Types are language `TypeRef` nodes (implemented
-  interfaces and union members `NamedType` nodes), resolved by name;
+  `InputObjectType`). Types are language `TypeRef` nodes, resolved by
+  name; implemented interfaces and union members are `NamedTypeReference`s,
+  a name and the span where it was written (an extension's reference has a
+  span in the extension's source, unlike the type's own span);
   defaults and directive arguments are constant language `Value` nodes.
   Every element has `SourceSpan? span`. `deprecationReason`,
   `specifiedByUrl` and `isOneOf` read the applied directives through the
@@ -197,7 +199,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 - `Schema` (`schema.dart`) lists only what was declared; `typeNamed` and
   `directiveNamed` fall back to `BuiltIns` (`defer` and `stream` only with
   `includesDeferAndStream`). Roots are names (`queryTypeName`, ...,
-  `rootTypeName(OperationType)`).
+  `rootTypeName(OperationType)`); `rootTypeSpan(OperationType)` is the
+  span of the name in the schema definition or extension, null for a
+  default root.
 - `build/SchemaBuilder` (const, `includesDeferAndStream`): `fromSdl(document,
   source:)` returns the sealed `BuildResult` (`BuildSuccess(schema)` |
   `BuildFailure(partial, diagnostics)`). A run sorts the definitions
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- **Breaking:** the interfaces of `ObjectType` and `InterfaceType` and the
  members of `UnionType` are `NamedTypeReference`s (a name and a span)
  instead of `NamedType` nodes, so a reference added by `extend` from
  another source points into that source. `Schema.rootTypeSpan` gives
  where a root type was named (`rootTypeSpans` in the constructor).
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/build/element_reader.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart packages/typed_graphql/lib/src/schema/build/type_extender.dart packages/typed_graphql/lib/src/schema/build/type_reader.dart packages/typed_graphql/lib/src/schema/model/named_type_reference.dart packages/typed_graphql/lib/src/schema/model/schema_type.dart packages/typed_graphql/lib/src/schema/print/type_printer.dart packages/typed_graphql/lib/src/schema/schema.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/build/member_filter_test.dart packages/typed_graphql/test/schema/build/reference_spans_test.dart packages/typed_graphql/test/schema/build/type_extender_test.dart packages/typed_graphql/test/schema/build/type_reader_test.dart packages/typed_graphql/test/schema/model/schema_type_test.dart packages/typed_graphql_conformance/test/fuzz/random_schema.dart packages/typed_graphql_conformance/test/fuzz/schema_dump.dart packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart packages/typed_graphql_conformance/test/support/schema_port.dart
git commit -q -m "refactor(typed_graphql): give interface, union member and root references their own spans" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: Add the type predicates and relations of a schema

The accessors that validation (Tasks 4–10) and M4's operation validation need, as graphql-js has them on `GraphQLSchema` and in `typeComparators`. `TypeComparator` walks wrappers with a loop, so a type wrapped 10000 times compares without recursion.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/relations/implementation_index.dart`, `packages/typed_graphql/lib/src/schema/relations/type_comparator.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/schema/model/schema_type.dart`, `packages/typed_graphql/lib/src/schema/schema.dart`
- Test: `packages/typed_graphql/test/schema/relations/type_comparator_test.dart`, `packages/typed_graphql/test/schema/schema_relations_test.dart`

**Interfaces:**
- Consumes: Task 2 (`NamedTypeReference`); M3a `Schema`, `SchemaType`.
- Produces:
```text
SchemaType: bool get isInputType, isOutputType, isLeafType, isCompositeType, isAbstractType
Schema:
  SchemaType? namedTypeOf(TypeRef type)
  bool isInputType(TypeRef type); bool isOutputType(TypeRef type)
  List<SchemaType> implementations(InterfaceType interfaceType)   // objects and interfaces, declaration order
  List<ObjectType> possibleTypes(SchemaType type)
  bool isSubType(SchemaType abstractType, SchemaType maybeSubType)
  bool isTypeSubTypeOf(TypeRef subType, TypeRef superType)
  bool typesOverlap(SchemaType a, SchemaType b)
internal: final class ImplementationIndex(List<SchemaType> types) { List<SchemaType> of(String interfaceName) }
internal: final class const TypeComparator() {
  String namedTypeName(TypeRef type); bool isEqual(TypeRef a, TypeRef b);
  bool isSubType(TypeRef subType, TypeRef superType, bool Function(String subName, String superName) isNamedSubType) }
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/relations/type_comparator_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/relations/type_comparator.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const comparator = TypeComparator();
  const dog = NamedType(Name('Dog'));
  const cat = NamedType(Name('Cat'));

  TypeRef deep(TypeRef inner, int depth) {
    var type = inner;
    for (var i = 0; i < depth; i++) {
      type = ListType(type);
    }
    return type;
  }

  bool never(String sub, String sup) => false;

  test('finds the name inside the wrappers', () {
    expect(comparator.namedTypeName(const NonNullType(ListType(dog))), 'Dog');
  });

  test('equal types have the same wrappers and name', () {
    expect(
      comparator.isEqual(const ListType(dog), const ListType(dog)),
      isTrue,
    );
    expect(
      comparator.isEqual(const ListType(dog), const ListType(cat)),
      isFalse,
    );
    expect(comparator.isEqual(const NonNullType(dog), dog), isFalse);
  });

  test('a non-null type is a sub type of its nullable form', () {
    expect(comparator.isSubType(const NonNullType(dog), dog, never), isTrue);
    expect(comparator.isSubType(dog, const NonNullType(dog), never), isFalse);
  });

  test('named types defer to the given relation', () {
    expect(comparator.isSubType(dog, cat, never), isFalse);
    expect(comparator.isSubType(dog, cat, (sub, sup) => sub == 'Dog'), isTrue);
  });

  test('deeply wrapped types compare without recursion', () {
    final a = deep(dog, 100000);
    final b = deep(dog, 100000);
    expect(comparator.namedTypeName(a), 'Dog');
    expect(comparator.isEqual(a, b), isTrue);
    expect(comparator.isSubType(a, b, never), isTrue);
  });
}
```

Create `packages/typed_graphql/test/schema/schema_relations_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'built.dart';

void main() {
  final schema = Built('''
interface Node { id: ID }
interface Named implements Node { id: ID name: String }
type Dog implements Named & Node { id: ID name: String }
type Cat implements Node { id: ID }
type Query { pet: Pet }
union Pet = Cat | Dog | Missing | Named
enum Mood { HAPPY }
input Filter { mood: Mood }
scalar Date''').schema;

  T type<T extends SchemaType>(String name) => schema.typeNamed(name) as T;
  List<String> names(List<SchemaType> types) => [
    for (final type in types) type.name,
  ];
  TypeRef ref(String text) => switch (const Parser().parseTypeRef(
    Source(text),
  )) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };

  group('kinds of named types', () {
    test('input types are scalars, enums and input objects', () {
      final inputs = [
        for (final type in schema.types)
          if (type.isInputType) type.name,
      ];
      expect(inputs, ['Mood', 'Filter', 'Date']);
    });

    test('output types are every kind but input objects', () {
      expect(type('Filter').isOutputType, isFalse);
      expect(type('Pet').isOutputType, isTrue);
      expect(type('Mood').isOutputType, isTrue);
    });

    test('leaf, composite and abstract types', () {
      expect(type('Date').isLeafType, isTrue);
      expect(type('Mood').isLeafType, isTrue);
      expect(type('Dog').isLeafType, isFalse);
      expect(type('Dog').isCompositeType, isTrue);
      expect(type('Filter').isCompositeType, isFalse);
      expect(type('Node').isAbstractType, isTrue);
      expect(type('Pet').isAbstractType, isTrue);
      expect(type('Dog').isAbstractType, isFalse);
    });
  });

  group('type references', () {
    test('the named type is found inside its wrappers', () {
      expect(schema.namedTypeOf(ref('[Dog!]!')), same(type('Dog')));
      expect(schema.namedTypeOf(ref('[String]'))?.name, 'String');
      expect(schema.namedTypeOf(ref('Missing')), isNull);
    });

    test('input and output checks look through wrappers', () {
      expect(schema.isInputType(ref('[Filter!]')), isTrue);
      expect(schema.isInputType(ref('Dog')), isFalse);
      expect(schema.isOutputType(ref('[Dog]!')), isTrue);
      expect(schema.isOutputType(ref('Filter')), isFalse);
    });

    test('an unknown named type is neither input nor output', () {
      expect(schema.isInputType(ref('Missing')), isFalse);
      expect(schema.isOutputType(ref('[Missing]')), isFalse);
    });
  });

  group('implementations and possible types', () {
    test('an interface lists the types that declare it, in order', () {
      expect(names(schema.implementations(type('Node'))), [
        'Named',
        'Dog',
        'Cat',
      ]);
      expect(names(schema.implementations(type('Named'))), ['Dog']);
    });

    test('the possible types of an interface are its object types', () {
      expect(names(schema.possibleTypes(type('Node'))), ['Dog', 'Cat']);
    });

    test('a union\'s possible types are its members that are objects', () {
      expect(names(schema.possibleTypes(type('Pet'))), ['Cat', 'Dog']);
    });

    test('an object is its own possible type; a leaf has none', () {
      expect(names(schema.possibleTypes(type('Dog'))), ['Dog']);
      expect(schema.possibleTypes(type('Mood')), isEmpty);
    });

    test('a type that declares an interface twice is listed once', () {
      final twice = Built('''
interface I { a: Int }
type T implements I & I { a: Int }''').schema;
      final interface = twice.typeNamed('I') as InterfaceType;
      expect(names(twice.implementations(interface)), ['T']);
    });
  });

  group('sub types', () {
    test('a member or a declaring type is a sub type', () {
      expect(schema.isSubType(type('Pet'), type('Cat')), isTrue);
      expect(schema.isSubType(type('Node'), type('Named')), isTrue);
      expect(schema.isSubType(type('Named'), type('Cat')), isFalse);
      expect(schema.isSubType(type('Dog'), type('Dog')), isFalse);
    });

    test('a type reference is a sub type through non-null and abstracts', () {
      expect(schema.isTypeSubTypeOf(ref('Dog!'), ref('Dog')), isTrue);
      expect(schema.isTypeSubTypeOf(ref('Dog'), ref('Dog!')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('[Dog!]!'), ref('[Node]')), isTrue);
      expect(schema.isTypeSubTypeOf(ref('[Dog]'), ref('Node')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Dog'), ref('[Dog]')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Cat'), ref('Pet')), isTrue);
      expect(schema.isTypeSubTypeOf(ref('Cat'), ref('Named')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Missing'), ref('Pet')), isFalse);
      expect(schema.isTypeSubTypeOf(ref('Missing'), ref('Missing')), isTrue);
    });

    test('types overlap when an object is possible for both', () {
      expect(schema.typesOverlap(type('Pet'), type('Named')), isTrue);
      expect(schema.typesOverlap(type('Cat'), type('Named')), isFalse);
      expect(schema.typesOverlap(type('Mood'), type('Mood')), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/relations/type_comparator_test.dart test/schema/schema_relations_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+0 -2: Some tests failed.`; the first messages: `Error: Error when reading 'lib/src/schema/relations/type_comparator.dart': No such file or directory`, `Error: Method not found: 'TypeComparator'.`, `Error: The getter 'isInputType' isn't defined for the type 'SchemaType'.`, `Error: The getter 'isOutputType' isn't defined for the type 'SchemaType'.`.

- [ ] **Step 3: Write the implementation**

`ImplementationIndex` is built on the first call and kept by the schema (the schema is immutable). Its map is only looked up, never iterated, so the order stays the declaration order.

In `packages/typed_graphql/lib/src/schema/model/schema_type.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -36,6 +36,28 @@ sealed class SchemaType(
     appliedDirectives,
   );
 
+  /// Whether it can be the type of an argument, an input field or a
+  /// variable: a scalar, an enum or an input object (spec §3.4.2).
+  bool get isInputType => switch (this) {
+    ScalarType() || EnumType() || InputObjectType() => true,
+    ObjectType() || InterfaceType() || UnionType() => false,
+  };
+
+  /// Whether it can be the type of a field: anything but an input object
+  /// (spec §3.4.2).
+  bool get isOutputType => this is! InputObjectType;
+
+  /// Whether a value of it has no fields: a scalar or an enum.
+  bool get isLeafType => this is ScalarType || this is EnumType;
+
+  /// Whether a selection set selects from it: an object, an interface or
+  /// a union.
+  bool get isCompositeType => !isLeafType && this is! InputObjectType;
+
+  /// Whether its runtime type is one of several object types: an
+  /// interface or a union.
+  bool get isAbstractType => this is InterfaceType || this is UnionType;
+
   /// The field of [fields] named [name], for object and interface types.
   static SchemaField? _fieldIn(List<SchemaField> fields, String name) {
     for (final field in fields) {
```

Create `packages/typed_graphql/lib/src/schema/relations/implementation_index.dart`:

```dart
import '../model/named_type_reference.dart';
import '../model/schema_type.dart';

/// The object and interface types that declare each interface, in
/// declaration order: graphql-js's `getImplementations`, built once.
///
/// It reads only the `implements` lists, so a transitive interface counts
/// only where it is declared, as schema validation requires (spec
/// §3.7.2).
final class ImplementationIndex(List<SchemaType> types) {
  /// Indexes [types].
  this;

  // Only for lookups, never iterated.
  final Map<String, List<SchemaType>> _byInterface = _index(types);

  /// The types that declare the interface named [interfaceName].
  List<SchemaType> of(String interfaceName) =>
      _byInterface[interfaceName] ?? const [];

  static Map<String, List<SchemaType>> _index(List<SchemaType> types) {
    final index = <String, List<SchemaType>>{};
    for (final type in types) {
      final interfaces = switch (type) {
        ObjectType(:final interfaces) ||
        InterfaceType(:final interfaces) => interfaces,
        _ => const <NamedTypeReference>[],
      };
      for (final reference in interfaces) {
        final implementers = index.putIfAbsent(reference.name, () => []);
        if (!implementers.contains(type)) {
          implementers.add(type);
        }
      }
    }
    return {
      for (final MapEntry(:key, :value) in index.entries)
        key: List.unmodifiable(value),
    };
  }
}
```

Create `packages/typed_graphql/lib/src/schema/relations/type_comparator.dart`:

```dart
import '../../language/ast/type_ref.dart';

/// Compares type references (spec §3.6.1 `IsValidImplementationFieldType`,
/// graphql-js's `typeComparators`) without recursion, so a deeply wrapped
/// type cannot overflow the stack.
final class const TypeComparator() {
  /// Creates a comparator.
  this;

  /// The name of the named type inside [type]'s list and non-null
  /// wrappers.
  String namedTypeName(TypeRef type) {
    var current = type;
    while (true) {
      switch (current) {
        case NamedType(:final name):
          return name.value;
        case ListType(type: final inner) || NonNullType(type: final inner):
          current = inner;
      }
    }
  }

  /// Whether [a] and [b] are the same type: the same wrappers around the
  /// same name.
  bool isEqual(TypeRef a, TypeRef b) {
    var (left, right) = (a, b);
    while (true) {
      switch ((left, right)) {
        case (NamedType(:final name), NamedType(name: final other)):
          return name.value == other.value;
        case (ListType(type: final l), ListType(type: final r)) ||
            (NonNullType(type: final l), NonNullType(type: final r)):
          (left, right) = (l, r);
        case _:
          return false;
      }
    }
  }

  /// Whether a value of type [subType] is always a valid value of
  /// [superType]: equal, or narrower by non-null or by [isNamedSubType]
  /// on the named types (graphql-js's `isTypeSubTypeOf`).
  bool isSubType(
    TypeRef subType,
    TypeRef superType,
    bool Function(String subName, String superName) isNamedSubType,
  ) {
    var (sub, sup) = (subType, superType);
    while (true) {
      switch ((sub, sup)) {
        case (NamedType(:final name), NamedType(name: final other)):
          return name.value == other.value ||
              isNamedSubType(name.value, other.value);
        case (NonNullType(type: final s), NonNullType(type: final t)) ||
            (ListType(type: final s), ListType(type: final t)):
          (sub, sup) = (s, t);
        case (NonNullType(type: final s), _):
          sub = s;
        case _:
          return false;
      }
    }
  }
}
```

In `packages/typed_graphql/lib/src/schema/schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,9 +1,12 @@
 import '../diagnostics/source_span.dart';
 import '../language/ast/operation_type.dart';
+import '../language/ast/type_ref.dart';
 import 'build/built_ins.dart';
 import 'model/applied_directive.dart';
 import 'model/schema_directive.dart';
 import 'model/schema_type.dart';
+import 'relations/implementation_index.dart';
+import 'relations/type_comparator.dart';
 
 /// A GraphQL schema (spec §3.3; R2.1): its named types, its directive
 /// definitions and its root operation types, immutable.
@@ -73,6 +76,12 @@ final class Schema({
     for (final directive in directives.reversed) directive.name: directive,
   };
 
+  // Late: built on the first question about implementations, from the
+  // final list of types, which never changes after construction.
+  late final ImplementationIndex _implementations = ImplementationIndex(
+    types,
+  );
+
   /// The declared type named [name], else the built-in scalar or
   /// introspection type; null when there is none.
   SchemaType? typeNamed(String name) {
@@ -107,4 +116,68 @@ final class Schema({
     .mutation => mutationTypeName,
     .subscription => subscriptionTypeName,
   };
+
+  /// The named type inside [type]'s wrappers; null when no type has its
+  /// name.
+  SchemaType? namedTypeOf(TypeRef type) =>
+      typeNamed(const TypeComparator().namedTypeName(type));
+
+  /// Whether [type] names an input type (spec §3.4.2); false when its
+  /// named type does not exist.
+  bool isInputType(TypeRef type) => namedTypeOf(type)?.isInputType ?? false;
+
+  /// Whether [type] names an output type (spec §3.4.2); false when its
+  /// named type does not exist.
+  bool isOutputType(TypeRef type) => namedTypeOf(type)?.isOutputType ?? false;
+
+  /// The object and interface types that declare [interfaceType] in their
+  /// `implements` list, in declaration order.
+  List<SchemaType> implementations(InterfaceType interfaceType) =>
+      _implementations.of(interfaceType.name);
+
+  /// The object types a value of [type] can be at run time, in
+  /// declaration order: the object itself, the members of a union that
+  /// are objects, or the objects that implement an interface.
+  List<ObjectType> possibleTypes(SchemaType type) => switch (type) {
+    ObjectType() => [type],
+    InterfaceType() => implementations(type).whereType<ObjectType>().toList(),
+    UnionType(:final memberTypes) => [
+      for (final member in memberTypes)
+        if (typeNamed(member.name) case final ObjectType object) object,
+    ],
+    ScalarType() || EnumType() || InputObjectType() => const [],
+  };
+
+  /// Whether [maybeSubType] is a member of the union [abstractType] or
+  /// declares the interface [abstractType] (graphql-js's `isSubType`).
+  bool isSubType(SchemaType abstractType, SchemaType maybeSubType) =>
+      switch (abstractType) {
+        UnionType(:final memberTypes) => memberTypes.any(
+          (member) => member.name == maybeSubType.name,
+        ),
+        InterfaceType() => implementations(abstractType).contains(maybeSubType),
+        _ => false,
+      };
+
+  /// Whether a value of type [subType] is always a value of [superType]
+  /// (graphql-js's `isTypeSubTypeOf`): the same type, or narrower by
+  /// non-null, or an implementation or member of an abstract type.
+  bool isTypeSubTypeOf(TypeRef subType, TypeRef superType) =>
+      const TypeComparator().isSubType(subType, superType, (sub, sup) {
+        final (subNamed, superNamed) = (typeNamed(sub), typeNamed(sup));
+        return subNamed != null &&
+            superNamed != null &&
+            (subNamed is ObjectType || subNamed is InterfaceType) &&
+            isSubType(superNamed, subNamed);
+      });
+
+  /// Whether some object type is possible for both [a] and [b]
+  /// (graphql-js's `doTypesOverlap`).
+  bool typesOverlap(SchemaType a, SchemaType b) {
+    if (identical(a, b)) {
+      return true;
+    }
+    final possible = possibleTypes(b);
+    return possibleTypes(a).any(possible.contains);
+  }
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/relations/type_comparator_test.dart test/schema/schema_relations_test.dart)
```

Expected: `typed_graphql` `+19: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -201,7 +201,12 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `includesDeferAndStream`). Roots are names (`queryTypeName`, ...,
   `rootTypeName(OperationType)`); `rootTypeSpan(OperationType)` is the
   span of the name in the schema definition or extension, null for a
-  default root.
+  default root. The type relations M4 needs live on `Schema`
+  (`namedTypeOf`, `implementations`, `possibleTypes`, `isSubType`,
+  `isTypeSubTypeOf`, `typesOverlap`) over the internal `relations/`
+  (`ImplementationIndex`, built on first use; `TypeComparator`, which walks
+  wrappers without recursion); the kind predicates (`isInputType`, ...)
+  are getters of `SchemaType`.
 - `build/SchemaBuilder` (const, `includesDeferAndStream`): `fromSdl(document,
   source:)` returns the sealed `BuildResult` (`BuildSuccess(schema)` |
   `BuildFailure(partial, diagnostics)`). A run sorts the definitions
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `SchemaType.isInputType`, `isOutputType`, `isLeafType`,
  `isCompositeType` and `isAbstractType`; `Schema.namedTypeOf`,
  `isInputType`, `isOutputType` (for a `TypeRef`), `implementations`,
  `possibleTypes`, `isSubType`, `isTypeSubTypeOf` and `typesOverlap`, as
  graphql-js names them, for validation and execution.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/model/schema_type.dart packages/typed_graphql/lib/src/schema/relations/implementation_index.dart packages/typed_graphql/lib/src/schema/relations/type_comparator.dart packages/typed_graphql/lib/src/schema/schema.dart packages/typed_graphql/test/schema/relations/type_comparator_test.dart packages/typed_graphql/test/schema/schema_relations_test.dart
git commit -q -m "feat(typed_graphql): add the type predicates and relations of a schema" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: Validate the root operation types of a schema

The validator's skeleton and its first rule family (spec §7, "Root Operation Types"). `ValidSchema` is a proof (decision 2, R2.4). The Schema guide gains "Validating a schema", as M3c's contract asks; its program shows only root problems, so its output does not change when Tasks 5–10 add rules.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/schema_validation_result.dart`, `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`, `packages/typed_graphql/lib/src/schema/validation/validation_report.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/schema.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/validated.dart`, `packages/typed_graphql/test/schema/validation/root_type_rules_test.dart`

**Interfaces:**
- Consumes: Task 2 (`Schema.rootTypeSpan`); M1 `DiagnosticSink`, `Diagnostic`.
- Produces:
```text
sealed class SchemaValidationResult { Schema get schema; List<Diagnostic> get diagnostics; }   // exported
final class ValidSchema extends SchemaValidationResult { ValidSchema._; factory ValidSchema.assumeValid(Schema) }
final class InvalidSchema(Schema schema, List<Diagnostic> diagnostics) extends SchemaValidationResult
final class const SchemaValidator() { SchemaValidationResult validate(Schema schema) }          // exported
internal: final class ValidationReport { void error(DiagnosticCode code, String message, [List<SourceSpan?> spans]);
  bool get hasErrors; List<Diagnostic> get diagnostics }   // first non-null span is the place, the rest related
internal: final class RootTypeRules(ValidationReport report, Schema schema) { void check() }
DiagnosticCode: GQL111 missingQueryRootType, GQL112 rootTypeNotObject, GQL113 sharedRootType
test helper: final class Validated(String sdl) / Validated.schema(Schema) { List<String> errors; List<String> codes }
```

- [ ] **Step 1: Write the failing tests**

`Validated` builds SDL named `schema.graphql`, validates it and lists each diagnostic as `line:column code message | related…`; every validation test from here on uses it.

Create `packages/typed_graphql/test/schema/validated.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'built.dart';

/// The validation of a schema, for a validation test.
final class Validated {
  /// Builds [text], which must build without errors, and validates it.
  Validated(String text) : this.schema(Built(text).schema);

  /// Validates [schema].
  Validated.schema(Schema schema)
    : result = const SchemaValidator().validate(schema);

  /// What the validator returned.
  final SchemaValidationResult result;

  /// Each diagnostic as `line:column id message`, with the locations of
  /// its related spans after `|`.
  List<String> get errors => [
    for (final diagnostic in result.diagnostics)
      [
        '${diagnostic.span?.location} ${diagnostic.code.id} '
            '${diagnostic.message}',
        for (final related in diagnostic.related) '| ${related.location}',
      ].join(' '),
  ];

  /// The ids of the diagnostics' codes, in order.
  List<String> get codes => [
    for (final diagnostic in result.diagnostics) diagnostic.code.id,
  ];
}
```

Create `packages/typed_graphql/test/schema/validation/root_type_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  test('a schema with an object query root is valid', () {
    final validated = Validated('type Query { a: Int }');
    expect(validated.result, isA<ValidSchema>());
    expect(validated.result.diagnostics, isEmpty);
  });

  test('a schema without a query root is invalid', () {
    final validated = Validated('type Mutation { a: Int }');
    expect(validated.result, isA<InvalidSchema>());
    expect(validated.errors, [
      'null GQL111 Query root type must be provided.',
    ]);
  });

  test('the missing query root points at the schema definition', () {
    final validated = Validated('''
schema { mutation: M }
type M { a: Int }''');
    expect(validated.errors, [
      '1:1 GQL111 Query root type must be provided.',
    ]);
  });

  test('a root of another kind points at its name in the schema', () {
    final validated = Validated('''
schema { query: Q subscription: S }
input Q { a: Int }
scalar S''');
    expect(validated.errors, [
      '1:17 GQL112 Query root type must be Object type, it cannot be Q.',
      '1:33 GQL112 Subscription root type must be Object type if provided, '
          'it cannot be S.',
    ]);
  });

  test('a default root of another kind points at the type', () {
    final validated = Validated('''
scalar Mutation
type Query { a: Int }''');
    expect(validated.errors, [
      '1:1 GQL112 Mutation root type must be Object type if provided, it '
          'cannot be Mutation.',
    ]);
  });

  test('a type used as two roots is reported with both places', () {
    final validated = Validated('''
schema { query: Q mutation: Q }
type Q { a: Int }''');
    expect(validated.errors, [
      '1:17 GQL113 All root types must be different, "Q" type is used as '
          'query and mutation root types. | 1:29',
    ]);
  });

  test('a type used as three roots lists them with a serial comma', () {
    final validated = Validated('''
schema { query: Q mutation: Q subscription: Q }
type Q { a: Int }''');
    expect(validated.errors.single, contains('used as query, mutation, and '));
  });

  test('a root that names no type is left to the reference rules', () {
    final schema = Schema(queryTypeName: 'Missing');
    expect(Validated.schema(schema).codes, isNot(contains('GQL112')));
  });

  test('assumeValid wraps a schema without checking it', () {
    final schema = Schema();
    final valid = ValidSchema.assumeValid(schema);
    expect(valid.schema, same(schema));
    expect(valid.diagnostics, isEmpty);
  });

  test('the result keeps the schema it validated', () {
    final schema = Schema();
    expect(const SchemaValidator().validate(schema).schema, same(schema));
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/root_type_rules_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+0 -1: Some tests failed.`; the first messages: `Error: Type 'SchemaValidationResult' not found.`, `Error: 'ValidSchema' isn't a type.`, `Error: 'InvalidSchema' isn't a type.`, `Error: Undefined name 'ValidSchema'.`.

- [ ] **Step 3: Write the implementation**

`ValidationReport` keeps report order: a schema's elements may come from several sources, so there is no offset order to sort by (decision 3). The new types carry `{@category schema}`.

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -134,5 +134,16 @@ enum DiagnosticCode(
 
   /// `GQL110`: an extension of a type of another kind, such as
   /// `extend input` of an object type; it is ignored.
-  extensionKindMismatch('GQL110');
+  extensionKindMismatch('GQL110'),
+
+  /// `GQL111`: a schema without a query root type (spec §3.3.1).
+  missingQueryRootType('GQL111'),
+
+  /// `GQL112`: a root operation type that is not an object type, such as
+  /// `query: SomeInterface` (spec §3.3.1).
+  rootTypeNotObject('GQL112'),
+
+  /// `GQL113`: one object type that is the root type of two operations
+  /// (spec §3.3.1).
+  sharedRootType('GQL113');
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart`:

```dart
import '../../language/ast/operation_type.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rules of the root operation types (spec §3.3.1): a query root
/// exists, every root is an object type, and no object type is the root
/// of two operations; graphql-js's `validateRootTypes`.
///
/// A root that names no type is the reference rules' to report.
final class RootTypeRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every problem of the roots of [schema].
  void check() {
    if (schema.queryTypeName == null) {
      report.error(.missingQueryRootType, 'Query root type must be provided.', [
        schema.span,
      ]);
    }
    final operationsByRoot = <ObjectType, List<OperationType>>{};
    for (final operation in OperationType.values) {
      final name = schema.rootTypeName(operation);
      switch (name == null ? null : schema.typeNamed(name)) {
        case null:
          continue;
        case final ObjectType type:
          operationsByRoot.putIfAbsent(type, () => []).add(operation);
        case final type:
          _notObject(operation, type);
      }
    }
    for (final MapEntry(key: type, value: operations)
        in operationsByRoot.entries) {
      if (operations.length > 1) {
        _shared(type, operations);
      }
    }
  }

  void _notObject(OperationType operation, SchemaType type) {
    final title = switch (operation) {
      .query => 'Query root type must be Object type',
      .mutation => 'Mutation root type must be Object type if provided',
      .subscription => 'Subscription root type must be Object type if provided',
    };
    report.error(
      .rootTypeNotObject,
      '$title, it cannot be ${type.name}.',
      [schema.rootTypeSpan(operation) ?? type.span],
    );
  }

  void _shared(ObjectType type, List<OperationType> operations) {
    final names = [for (final operation in operations) operation.name];
    final list = names.length == 2
        ? names.join(' and ')
        : '${names.take(names.length - 1).join(', ')}, and ${names.last}';
    report.error(
      .sharedRootType,
      'All root types must be different, "${type.name}" type is used as '
      '$list root types.',
      [for (final operation in operations) schema.rootTypeSpan(operation)],
    );
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/schema_validation_result.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../schema.dart';

/// The result of validating a schema: [ValidSchema] or [InvalidSchema]
/// (spec §7; R2.3). An invalid schema never throws.
///
/// {@category schema}
sealed class SchemaValidationResult {
  /// Creates a result.
  const SchemaValidationResult();

  /// The schema that was validated.
  Schema get schema;

  /// The problems found, in the order the rules report them; empty for a
  /// [ValidSchema].
  List<Diagnostic> get diagnostics;
}

/// A schema that passed every type-system rule, or one a caller trusts.
///
/// Only `SchemaValidator.validate` and [ValidSchema.assumeValid] make
/// one, so code that takes a [ValidSchema] (execution, operation
/// validation) knows the schema was checked.
///
/// {@category schema}
final class ValidSchema extends SchemaValidationResult {
  const ValidSchema._(this.schema);

  /// Wraps [schema] without validating it, for a schema that is known to
  /// be valid, such as one built by generated code; nothing checks it.
  factory ValidSchema.assumeValid(Schema schema) => ValidSchema._(schema);

  @override
  final Schema schema;

  @override
  List<Diagnostic> get diagnostics => const [];
}

/// A schema that breaks at least one type-system rule.
///
/// {@category schema}
final class InvalidSchema(
  @override final Schema schema,
  List<Diagnostic> diagnostics,
) extends SchemaValidationResult {
  /// Creates the result of validating [schema].
  this;

  @override
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`:

```dart
import '../schema.dart';
import 'root_type_rules.dart';
import 'schema_validation_result.dart';
import 'validation_report.dart';

/// Checks a schema against the type-system rules of the specification
/// (spec §7; R2.3, R2.4) in one pass, in graphql-js's order: roots,
/// directive definitions, then types in declaration order.
///
/// Each rule family is a class in `schema/validation/`. A schema with no
/// error is a [ValidSchema]; otherwise the result is an [InvalidSchema]
/// with every error, up to the sink's limit. Nothing throws.
///
/// {@category schema}
final class const SchemaValidator() {
  /// Creates a validator.
  this;

  /// Validates [schema].
  SchemaValidationResult validate(Schema schema) {
    final report = ValidationReport();
    RootTypeRules(report, schema).check();
    return report.hasErrors
        ? InvalidSchema(schema, report.diagnostics)
        : ValidSchema.assumeValid(schema);
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/validation_report.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source_span.dart';

/// Collects the errors of one schema validation in the order the rules
/// report them, as graphql-js's `validateSchema` does, up to a
/// [DiagnosticSink]'s limit.
///
/// The elements of a schema may come from several sources, so the errors
/// are not sorted by offset: the rules walk the schema in declaration
/// order, which is deterministic.
final class ValidationReport {
  /// Creates an empty report.
  ValidationReport();

  final DiagnosticSink _sink = DiagnosticSink();

  /// Whether an error was reported.
  bool get hasErrors => _sink.hasErrors;

  /// The errors, in report order.
  List<Diagnostic> get diagnostics => _sink.diagnostics;

  /// Reports an error at the first of [spans], with the others as related
  /// places; null spans are left out (an element built in code has none).
  void error(
    DiagnosticCode code,
    String message, [
    List<SourceSpan?> spans = const [],
  ]) {
    final places = [for (final span in spans) ?span];
    _sink.report(
      Diagnostic(
        code,
        .error,
        message,
        span: places.firstOrNull,
        related: places.skip(1).toList(),
      ),
    );
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -83,3 +83,5 @@ export 'src/schema/scalars/scalar_codec.dart';
 export 'src/schema/scalars/scalar_codecs.dart';
 export 'src/schema/scalars/string_codec.dart';
 export 'src/schema/schema.dart';
+export 'src/schema/validation/schema_validation_result.dart';
+export 'src/schema/validation/schema_validator.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/root_type_rules_test.dart)
```

Expected: `typed_graphql` `+10: All tests passed!`.

- [ ] **Step 5: Update the guides**

The new section goes before "What building does not check", whose last sentence now points to it.

In `packages/typed_graphql/doc/schema.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -435,6 +435,72 @@ false
 true
 ```
 
+## Validating a schema
+
+`SchemaValidator().validate(schema)` checks a schema against every type-system
+rule of the specification and returns a sealed `SchemaValidationResult`:
+
+- `ValidSchema(schema)` when no rule is broken. Only the validator and
+  `ValidSchema.assumeValid(schema)` make one, so code that takes a `ValidSchema`
+  knows the schema was checked. `assumeValid` checks nothing: keep it for a
+  schema known to be valid, such as one generated from a schema that was
+  validated before.
+- `InvalidSchema(schema, diagnostics)` with every problem: a `GQL1xx` code,
+  graphql-js's message and the place of the element (or the node inside it,
+  such as a default value) the problem is about. The problems come in
+  graphql-js's order: the roots, the directive definitions, then the types in
+  declaration order.
+
+Validation never throws, and a schema built in code is validated the same way
+as one built from SDL.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  report(
+    validate('''
+type Query { hero: Character }
+interface Character { name: String! }
+type Human implements Character { name: String! }
+'''),
+  );
+  report(
+    validate('''
+schema { query: Query mutation: Character subscription: Query }
+type Query { hero: Character }
+interface Character { name: String! }
+'''),
+  );
+}
+
+SchemaValidationResult validate(String sdl) {
+  final source = Source(sdl, name: 'schema.graphql');
+  final document = const Parser().parse(source).requireDocument();
+  return switch (const SchemaBuilder().fromSdl(document, source: source)) {
+    BuildSuccess(:final schema) => const SchemaValidator().validate(schema),
+    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
+  };
+}
+
+void report(SchemaValidationResult result) {
+  switch (result) {
+    case ValidSchema(:final schema):
+      print('valid, ${schema.types.length} types');
+    case InvalidSchema(:final diagnostics):
+      diagnostics.forEach(print);
+  }
+}
+```
+
+It prints:
+
+```text
+valid, 3 types
+schema.graphql:1:33: error GQL112: Mutation root type must be Object type if provided, it cannot be Character.
+schema.graphql:1:17: error GQL113: All root types must be different, "Query" type is used as query and subscription root types.
+```
+
 ## What building does not check
 
 Building a schema does not validate it. A field may name a type that does not
@@ -470,5 +536,5 @@ null
 Query
 ```
 
-Checking a schema against the rules of the specification arrives in a later
-release of this package.
+Checking a schema against the rules of the specification is the validator's
+work: see "Validating a schema" above.
````

- [ ] **Step 6: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+230: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 7: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -248,6 +248,16 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   decodes (an enum value becomes its name), so codecs have no
   `parseLiteral`.
 
+- `validation/SchemaValidator` (const): `validate(schema)` returns the
+  sealed `SchemaValidationResult` (`ValidSchema` | `InvalidSchema(schema,
+  diagnostics)`); `ValidSchema` has a private constructor and
+  `ValidSchema.assumeValid`. One class per rule family (spec §7), each
+  `XRules(report, schema).check()`, run in graphql-js's order (roots,
+  directive definitions, types) into a `ValidationReport`, which keeps
+  report order (elements may come from several sources, so no offset
+  sort) and gives the first span of an error as its place and the others
+  as related. Messages are graphql-js's `validateSchema` messages.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `SchemaValidator` and the sealed `SchemaValidationResult`: `ValidSchema`
  (made only by the validator or `ValidSchema.assumeValid`) or
  `InvalidSchema(schema, diagnostics)`. The root-type rules: `GQL111` for
  a missing query root, `GQL112` for a root that is not an object type,
  `GQL113` for one type used as two roots.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/schema.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart packages/typed_graphql/lib/src/schema/validation/schema_validation_result.dart packages/typed_graphql/lib/src/schema/validation/schema_validator.dart packages/typed_graphql/lib/src/schema/validation/validation_report.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/validated.dart packages/typed_graphql/test/schema/validation/root_type_rules_test.dart
git commit -q -m "feat(typed_graphql): validate the root operation types of a schema" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: Validate the names of a schema and repeats built in code

Spec §7 "Names" and the repeats a schema built in code can hold (decision 1): SDL building drops a repeat, code does not. Each family gets its class; `TypeRules` walks the types in declaration order and calls the per-kind rules.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/field_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/name_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/unique_names.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`
- Test: `packages/typed_graphql/test/schema/validation/name_rules_test.dart`, `packages/typed_graphql/test/schema/validation/unique_names_test.dart`

**Interfaces:**
- Consumes: Task 4 (`ValidationReport`, `SchemaValidator`, `Validated`).
- Produces:
```text
internal, each `XRules(report[, schema])`:
  NameRules(report) { void check(String name, SourceSpan? span); void checkEnumValue(String name, SourceSpan? span) }
  UniqueNames(report) { void check(List<(String, SourceSpan?)> named, DiagnosticCode code, String Function(String) message) }
  ArgumentRules(report) { void check(String owner, List<InputValue> arguments) }
  FieldRules(report) { void check(String typeName, List<SchemaField> fields) }
  EnumRules(report) { void check(EnumType type) }
  InputObjectRules(report) { void check(InputObjectType type) }
  DirectiveDefinitionRules(report, schema) { void check() }
  TypeRules(report, schema) { void check() }
DiagnosticCode: GQL114 reservedName, GQL115 invalidName; GQL013 reused for repeats (finding 5)
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/validation/name_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  const string = NamedType(Name('String'));
  final query = ObjectType('Query', fields: [SchemaField('a', string)]);
  Schema withQuery(List<SchemaType> types) =>
      Schema(types: [query, ...types], queryTypeName: 'Query');

  test('a schema of valid names has no name error', () {
    expect(
      Validated('type Query { a(b: Int): E } enum E { A }').errors,
      isEmpty,
    );
  });

  test('a type name that begins with __ points at the type', () {
    final validated = Validated('''
type Query { a: Int }
scalar __Odd''');
    expect(validated.errors, [
      '2:1 GQL114 Name "__Odd" must not begin with "__", which is reserved '
          'by GraphQL introspection.',
    ]);
  });

  test('a field, an argument and an enum value that begin with __ are '
      'reported in order', () {
    final validated = Validated('''
type Query { __f(__a: Int): E }
enum E { __V }''');
    expect(validated.codes, ['GQL114', 'GQL114', 'GQL114']);
    expect(validated.errors.first, startsWith('1:14 GQL114 Name "__f"'));
    expect(validated.errors[1], startsWith('1:18 GQL114 Name "__a"'));
    expect(validated.errors.last, startsWith('2:10 GQL114 Name "__V"'));
  });

  test('an input field that begins with __ is reported', () {
    final validated = Validated('''
type Query { a: Int }
input In { __f: Int }''');
    expect(validated.errors.single, startsWith('2:12 GQL114 Name "__f"'));
  });

  test('a directive and its argument that begin with __ are reported', () {
    final validated = Validated('''
type Query { a: Int }
directive @__d(__a: Int) on FIELD''');
    expect(validated.codes, ['GQL114', 'GQL114']);
    expect(validated.errors.first, startsWith('2:1 GQL114 Name "__d"'));
    expect(validated.errors.last, startsWith('2:16 GQL114 Name "__a"'));
  });

  test('an empty name built in code is reported', () {
    final schema = withQuery([ScalarType('')]);
    expect(Validated.schema(schema).errors, [
      'null GQL115 Expected name to be a non-empty string.',
    ]);
  });

  test('a name built in code that starts with a digit is reported', () {
    final schema = withQuery([ScalarType('1x')]);
    expect(Validated.schema(schema).errors, [
      'null GQL115 Names must start with [_a-zA-Z] but "1x" does not.',
    ]);
  });

  test('a name built in code with another character is reported', () {
    final schema = withQuery([
      ObjectType('T', fields: [SchemaField('x-y', string)]),
    ]);
    expect(Validated.schema(schema).errors, [
      'null GQL115 Names must only contain [_a-zA-Z0-9] but "x-y" does not.',
    ]);
  });

  test('enum values built in code named true, false and null are '
      'reported', () {
    final schema = withQuery([
      EnumType(
        'E',
        values: [
          SchemaEnumValue('true'),
          SchemaEnumValue('false'),
          SchemaEnumValue('null'),
        ],
      ),
    ]);
    expect(Validated.schema(schema).errors, [
      'null GQL013 Enum values cannot be named: true',
      'null GQL013 Enum values cannot be named: false',
      'null GQL013 Enum values cannot be named: null',
    ]);
  });
}
```

Create `packages/typed_graphql/test/schema/validation/unique_names_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../validated.dart';

void main() {
  const string = NamedType(Name('String'));
  final query = ObjectType('Query', fields: [SchemaField('a', string)]);
  List<String> errorsOf({
    List<SchemaType> types = const [],
    List<SchemaDirective> directives = const [],
  }) => Validated.schema(
    Schema(
      types: [query, ...types],
      directives: directives,
      queryTypeName: 'Query',
    ),
  ).errors;

  test('two types with one name are reported once', () {
    expect(errorsOf(types: [ScalarType('S'), ScalarType('S')]), [
      'null GQL101 There can be only one type named "S".',
    ]);
  });

  test('a type with a built-in name is reported', () {
    expect(errorsOf(types: [ScalarType('String')]), [
      'null GQL103 The built-in type "String" cannot be redefined.',
    ]);
  });

  test('two directives with one name are reported once', () {
    final directive = SchemaDirective('d', locations: const [.field]);
    expect(errorsOf(directives: [directive, directive]), [
      'null GQL102 There can be only one directive named "@d".',
    ]);
  });

  test('a directive with a built-in name is reported', () {
    final skip = SchemaDirective('skip', locations: const [.field]);
    expect(errorsOf(directives: [skip]), [
      'null GQL103 The built-in directive "@skip" cannot be redefined.',
    ]);
  });

  test('two fields with one name are reported with their coordinate', () {
    final type = ObjectType(
      'T',
      fields: [SchemaField('f', string), SchemaField('f', string)],
    );
    expect(errorsOf(types: [type]), [
      'null GQL104 Field "T.f" can only be defined once.',
    ]);
  });

  test('two input fields with one name are reported', () {
    final type = InputObjectType(
      'In',
      fields: [InputValue('f', string), InputValue('f', string)],
    );
    expect(errorsOf(types: [type]), [
      'null GQL104 Field "In.f" can only be defined once.',
    ]);
  });

  test('two arguments of a field with one name are reported', () {
    final type = InterfaceType(
      'I',
      fields: [
        SchemaField(
          'f',
          string,
          arguments: [InputValue('a', string), InputValue('a', string)],
        ),
      ],
    );
    expect(errorsOf(types: [type]), [
      'null GQL105 Argument "I.f(a:)" can only be defined once.',
    ]);
  });

  test('two arguments of a directive with one name are reported', () {
    final directive = SchemaDirective(
      'd',
      arguments: [InputValue('a', string), InputValue('a', string)],
      locations: const [.field],
    );
    expect(errorsOf(directives: [directive]), [
      'null GQL105 Argument "@d(a:)" can only be defined once.',
    ]);
  });

  test('two enum values with one name are reported', () {
    final type = EnumType(
      'E',
      values: [SchemaEnumValue('A'), SchemaEnumValue('A')],
    );
    expect(errorsOf(types: [type]), [
      'null GQL106 Enum value "E.A" can only be defined once.',
    ]);
  });

  test('a repeat relates to the span of the first', () {
    final sdl = Built('type Query { a: Int }').schema;
    final first = sdl.types.single;
    final schema = Schema(types: [first, first], queryTypeName: 'Query');
    expect(Validated.schema(schema).errors, [
      '1:1 GQL101 There can be only one type named "Query". | 1:1',
    ]);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/name_rules_test.dart test/schema/validation/unique_names_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+1 -18: Some tests failed.`; the first messages: `Expected: ['null GQL101 There can be only one type named "S".']`, `Expected: ['null GQL103 The built-in type "String" cannot be redefined.']`, `Expected: ['null GQL102 There can be only one directive named "@d".']`, `Expected: ['null GQL103 The built-in directive "@skip" cannot be redefined.']`.

- [ ] **Step 3: Write the implementation**

A repeat points at the second name and relates to the first, as the builder's `UniqueDefinitions` does.

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -78,7 +78,8 @@ enum DiagnosticCode(
   emptySelectionSet('GQL012'),
 
   /// `GQL013`: an enum value named `true`, `false` or `null` (spec
-  /// §3.9, `EnumValue`).
+  /// §3.9, `EnumValue`); schema validation reports one in a schema built
+  /// in code.
   reservedEnumValueName('GQL013'),
 
   /// `GQL014`: working-draft grammar that the parser's options leave off:
@@ -93,29 +94,35 @@ enum DiagnosticCode(
 
   /// `GQL101`: a second type definition with the name of a type already
   /// defined in the document or in the schema being extended; the second
-  /// is ignored.
+  /// is ignored. Schema validation reports a repeat in a schema built in
+  /// code.
   duplicateTypeName('GQL101'),
 
   /// `GQL102`: a second directive definition with the name of a directive
   /// already defined in the document or in the schema being extended; the
-  /// second is ignored.
+  /// second is ignored. Schema validation reports a repeat in a schema
+  /// built in code.
   duplicateDirectiveName('GQL102'),
 
   /// `GQL103`: a definition or an extension of a built-in: a built-in
   /// scalar, an introspection type or a built-in directive (R2.6); it is
-  /// ignored.
+  /// ignored. Schema validation reports a built-in name declared in a
+  /// schema built in code.
   builtInRedefinition('GQL103'),
 
   /// `GQL104`: a second field or input field with one name in a type, its
-  /// extensions included; the second is ignored.
+  /// extensions included; the second is ignored. Schema validation
+  /// reports a repeat in a schema built in code.
   duplicateFieldName('GQL104'),
 
   /// `GQL105`: a second argument with one name in a field or a directive
-  /// definition; the second is ignored.
+  /// definition; the second is ignored. Schema validation reports a
+  /// repeat in a schema built in code.
   duplicateArgumentName('GQL105'),
 
   /// `GQL106`: a second value with one name in an enum type, its
-  /// extensions included; the second is ignored.
+  /// extensions included; the second is ignored. Schema validation
+  /// reports a repeat in a schema built in code.
   duplicateEnumValueName('GQL106'),
 
   /// `GQL107`: a second schema definition, or one in a document that
@@ -145,5 +152,13 @@ enum DiagnosticCode(
 
   /// `GQL113`: one object type that is the root type of two operations
   /// (spec §3.3.1).
-  sharedRootType('GQL113');
+  sharedRootType('GQL113'),
+
+  /// `GQL114`: a name of a type, field, argument, enum value or directive
+  /// that begins with `__`, which introspection reserves (spec §3.4).
+  reservedName('GQL114'),
+
+  /// `GQL115`: a name that is empty or not of the name syntax
+  /// `[_A-Za-z][_0-9A-Za-z]*` (spec §2.1.9), in a schema built in code.
+  invalidName('GQL115');
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`:

```dart
import '../model/input_value.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the arguments of one field or directive definition (spec
/// §3.6.1, §3.13): unique and valid names.
final class ArgumentRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  /// Reports the problems of [arguments], which belong to [owner]: the
  /// coordinate of a field (`Type.field`) or a directive (`@name`).
  void check(String owner, List<InputValue> arguments) {
    UniqueNames(report).check(
      [for (final argument in arguments) (argument.name, argument.span)],
      .duplicateArgumentName,
      (name) => 'Argument "$owner($name:)" can only be defined once.',
    );
    for (final argument in arguments) {
      NameRules(report).check(argument.name, argument.span);
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`:

```dart
import '../build/built_ins.dart';
import '../schema.dart';
import 'argument_rules.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the directive definitions of a schema (spec §3.13), as
/// graphql-js's `validateDirectives`.
final class DirectiveDefinitionRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every problem of the declared directives of [schema].
  void check() {
    _definitions();
    for (final directive in schema.directives) {
      NameRules(report).check(directive.name, directive.span);
      ArgumentRules(report).check('@${directive.name}', directive.arguments);
    }
  }

  // The builder drops these from SDL; a schema built in code may hold
  // them.
  void _definitions() {
    for (final directive in schema.directives) {
      if (const BuiltIns().isBuiltInDirective(
        directive.name,
        includesDeferAndStream: schema.includesDeferAndStream,
      )) {
        report.error(
          .builtInRedefinition,
          'The built-in directive "@${directive.name}" cannot be redefined.',
          [directive.span],
        );
      }
    }
    UniqueNames(report).check(
      [
        for (final directive in schema.directives)
          (directive.name, directive.span),
      ],
      .duplicateDirectiveName,
      (name) => 'There can be only one directive named "@$name".',
    );
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart`:

```dart
import '../model/schema_type.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an enum type (spec §3.9): unique and valid value names.
final class EnumRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  /// Reports the problems of [type].
  void check(EnumType type) {
    UniqueNames(report).check(
      [for (final value in type.values) (value.name, value.span)],
      .duplicateEnumValueName,
      (name) => 'Enum value "${type.name}.$name" can only be defined once.',
    );
    for (final value in type.values) {
      NameRules(report).checkEnumValue(value.name, value.span);
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/field_rules.dart`:

```dart
import '../model/schema_field.dart';
import 'argument_rules.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the fields of an object or interface type (spec §3.6,
/// §3.7): unique and valid names, and their arguments'.
final class FieldRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  /// Reports the problems of [fields], the fields of the type [typeName].
  void check(String typeName, List<SchemaField> fields) {
    UniqueNames(report).check(
      [for (final field in fields) (field.name, field.span)],
      .duplicateFieldName,
      (name) => 'Field "$typeName.$name" can only be defined once.',
    );
    for (final field in fields) {
      NameRules(report).check(field.name, field.span);
      ArgumentRules(report).check('$typeName.${field.name}', field.arguments);
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`:

```dart
import '../model/schema_type.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an input object type (spec §3.10): unique and valid
/// field names.
final class InputObjectRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  /// Reports the problems of [type].
  void check(InputObjectType type) {
    UniqueNames(report).check(
      [for (final field in type.fields) (field.name, field.span)],
      .duplicateFieldName,
      (name) => 'Field "${type.name}.$name" can only be defined once.',
    );
    for (final field in type.fields) {
      NameRules(report).check(field.name, field.span);
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/name_rules.dart`:

```dart
import '../../diagnostics/source_span.dart';
import 'validation_report.dart';

/// The rules every name of a schema follows: the name syntax (spec
/// §2.1.9), no `__` prefix outside the introspection types (spec §3.4),
/// and no enum value named `true`, `false` or `null` (spec §3.9).
///
/// A schema read from SDL always has names of valid syntax; one built in
/// code may not, so the syntax is checked with graphql-js's `assertName`
/// messages.
final class NameRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  static final RegExp _start = RegExp('^[_A-Za-z]');
  static final RegExp _syntax = RegExp(r'^[_A-Za-z][_0-9A-Za-z]*$');
  static const List<String> _reservedEnumValues = ['true', 'false', 'null'];

  /// Reports [name], defined at [span], when its syntax is invalid or it
  /// begins with `__`.
  void check(String name, SourceSpan? span) {
    if (name.isEmpty) {
      report.error(.invalidName, 'Expected name to be a non-empty string.', [
        span,
      ]);
    } else if (!_start.hasMatch(name)) {
      report.error(
        .invalidName,
        'Names must start with [_a-zA-Z] but "$name" does not.',
        [span],
      );
    } else if (!_syntax.hasMatch(name)) {
      report.error(
        .invalidName,
        'Names must only contain [_a-zA-Z0-9] but "$name" does not.',
        [span],
      );
    } else if (name.startsWith('__')) {
      report.error(
        .reservedName,
        'Name "$name" must not begin with "__", which is reserved by '
        'GraphQL introspection.',
        [span],
      );
    }
  }

  /// Reports the name of an enum value as [check] does, and also when it
  /// is `true`, `false` or `null`.
  void checkEnumValue(String name, SourceSpan? span) {
    check(name, span);
    if (_reservedEnumValues.contains(name)) {
      report.error(
        .reservedEnumValueName,
        'Enum values cannot be named: $name',
        [span],
      );
    }
  }
}
```

In `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,8 @@
 import '../schema.dart';
+import 'directive_definition_rules.dart';
 import 'root_type_rules.dart';
 import 'schema_validation_result.dart';
+import 'type_rules.dart';
 import 'validation_report.dart';
 
 /// Checks a schema against the type-system rules of the specification
@@ -20,6 +22,8 @@ final class const SchemaValidator() {
   SchemaValidationResult validate(Schema schema) {
     final report = ValidationReport();
     RootTypeRules(report, schema).check();
+    DirectiveDefinitionRules(report, schema).check();
+    TypeRules(report, schema).check();
     return report.hasErrors
         ? InvalidSchema(schema, report.diagnostics)
         : ValidSchema.assumeValid(schema);
```

Create `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`:

```dart
import '../build/built_ins.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'enum_rules.dart';
import 'field_rules.dart';
import 'input_object_rules.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the named types of a schema (spec §3.4–§3.10), type by
/// type in declaration order, as graphql-js's `validateTypes`: each type
/// is checked by the rule family of its kind.
final class TypeRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every problem of the declared types of [schema].
  void check() {
    _definitions();
    for (final type in schema.types) {
      NameRules(report).check(type.name, type.span);
      switch (type) {
        case ObjectType(:final name, :final fields) ||
            InterfaceType(:final name, :final fields):
          FieldRules(report).check(name, fields);
        case EnumType():
          EnumRules(report).check(type);
        case InputObjectType():
          InputObjectRules(report).check(type);
        case ScalarType() || UnionType():
          break;
      }
    }
  }

  // The builder drops these from SDL; a schema built in code may hold
  // them.
  void _definitions() {
    for (final type in schema.types) {
      if (const BuiltIns().typeNamed(type.name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "${type.name}" cannot be redefined.',
          [type.span],
        );
      }
    }
    UniqueNames(report).check(
      [for (final type in schema.types) (type.name, type.span)],
      .duplicateTypeName,
      (name) => 'There can be only one type named "$name".',
    );
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/unique_names.dart`:

```dart
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/source_span.dart';
import 'validation_report.dart';

/// The rule that the elements of one list have different names: types,
/// directives, the fields of a type, the arguments of a field.
///
/// The builder drops repeats in SDL, so only a schema built in code has
/// any; the messages are the builder's.
final class UniqueNames(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rule.
  this;

  /// Reports each of [named] whose name an earlier one has, with
  /// [message] of the name, at the repeat and related to the first.
  void check(
    List<(String, SourceSpan?)> named,
    DiagnosticCode code,
    String Function(String name) message,
  ) {
    // Only for lookups; the errors follow the order of [named].
    final firstSpans = <String, SourceSpan?>{};
    for (final (name, span) in named) {
      if (firstSpans.containsKey(name)) {
        report.error(code, message(name), [span, firstSpans[name]]);
      } else {
        firstSpans[name] = span;
      }
    }
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/name_rules_test.dart test/schema/validation/unique_names_test.dart)
```

Expected: `typed_graphql` `+19: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -257,6 +257,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   report order (elements may come from several sources, so no offset
   sort) and gives the first span of an error as its place and the others
   as related. Messages are graphql-js's `validateSchema` messages.
+  `TypeRules` walks the types and hands each to the family of its kind
+  (`FieldRules`, `EnumRules`, `InputObjectRules`, ...);
+  `DirectiveDefinitionRules` walks the directives; both share
+  `ArgumentRules`, `NameRules` (syntax, `__`, reserved enum values) and
+  `UniqueNames` (repeats, which only a schema built in code can hold).
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Schema validation checks names: `GQL114` for a name that begins with
  `__`, `GQL115` for a name of invalid syntax and `GQL013` for an enum
  value named `true`, `false` or `null`; and, in a schema built in code,
  repeated types, directives, fields, arguments and enum values
  (`GQL101`–`GQL106`, the builder's messages) and redefined built-ins
  (`GQL103`).
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/argument_rules.dart packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart packages/typed_graphql/lib/src/schema/validation/enum_rules.dart packages/typed_graphql/lib/src/schema/validation/field_rules.dart packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart packages/typed_graphql/lib/src/schema/validation/name_rules.dart packages/typed_graphql/lib/src/schema/validation/schema_validator.dart packages/typed_graphql/lib/src/schema/validation/type_rules.dart packages/typed_graphql/lib/src/schema/validation/unique_names.dart packages/typed_graphql/test/schema/validation/name_rules_test.dart packages/typed_graphql/test/schema/validation/unique_names_test.dart
git commit -q -m "feat(typed_graphql): validate the names of a schema and repeats built in code" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: Validate type references and applied directives

References to unknown types and directives, and applied directives (location, repetition, arguments). These rules are missing from spec §7 (finding 1); this task adds them there. From here on the rule classes that look types up take `(report, schema)`.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/interface_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/node_span.dart`, `packages/typed_graphql/lib/src/schema/validation/type_reference_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/union_rules.dart`
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-10-14-m3-type-system-design.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/relations/type_comparator.dart`, `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/field_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`, `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`
- Test: `packages/typed_graphql/test/schema/validation/applied_directive_rules_test.dart`, `packages/typed_graphql/test/schema/validation/root_type_rules_test.dart`, `packages/typed_graphql/test/schema/validation/type_reference_rules_test.dart`

**Interfaces:**
- Consumes: Task 5 (the rule classes), Task 1 (`DirectiveLocation`), Task 2 (`NamedTypeReference`).
- Produces:
```text
internal:
  TypeReferenceRules(report, schema) { bool isKnown(String name, SourceSpan? span); bool isKnownType(TypeRef type, SourceSpan? element) }
  AppliedDirectiveRules(report, schema) { void check(List<AppliedDirective> directives, DirectiveLocation location) }
  InterfaceRules(report, schema) { void check(List<NamedTypeReference> interfaces) }
  UnionRules(report, schema) { void check(UnionType type) }
  final class const NodeSpan() { SourceSpan? within(SourceSpan? element, Node node) }  // a node's span in its element's source
  FieldRules, EnumRules, InputObjectRules, ArgumentRules now take (report, schema)
  TypeComparator.namedType(TypeRef type) -> NamedType
DiagnosticCode: GQL116 unknownType, GQL117 unknownDirective, GQL118 misplacedDirective, GQL119 repeatedDirective,
  GQL120 duplicateDirectiveArgument, GQL121 unknownDirectiveArgument, GQL122 missingDirectiveArgument
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/validation/applied_directive_rules_test.dart`:

```dart
import 'package:test/test.dart';

import '../validated.dart';

void main() {
  test('an unknown directive points at the directive', () {
    final validated = Validated('''
type Query {
  foo: String @unknown
}''');
    expect(validated.errors, ['2:15 GQL117 Unknown directive "@unknown".']);
  });

  test('an unknown directive on the schema is reported', () {
    final validated = Validated('''
schema @unknown { query: Query }
type Query { a: Int }''');
    expect(validated.errors, ['1:8 GQL117 Unknown directive "@unknown".']);
  });

  test('a directive at a location it does not list is reported', () {
    final validated = Validated('type Query @deprecated { a: Int }');
    expect(validated.errors, [
      '1:12 GQL118 Directive "@deprecated" may not be used on OBJECT.',
    ]);
  });

  test('each element kind has its location', () {
    final validated = Validated('''
directive @d on QUERY
directive @e(a: Int @d) @d on FIELD
type Query @d { a(b: Int @d): E @d }
scalar S @d
interface I @d { a: Int }
union U @d = Query
enum E @d { A @d }
input In @d { a: Int @d }''');
    expect(validated.errors.map((error) => error.split(' may').first), [
      '2:25 GQL118 Directive "@d"',
      '2:21 GQL118 Directive "@d"',
      '3:12 GQL118 Directive "@d"',
      '3:33 GQL118 Directive "@d"',
      '3:26 GQL118 Directive "@d"',
      '4:10 GQL118 Directive "@d"',
      '5:13 GQL118 Directive "@d"',
      '6:9 GQL118 Directive "@d"',
      '7:8 GQL118 Directive "@d"',
      '7:15 GQL118 Directive "@d"',
      '8:10 GQL118 Directive "@d"',
      '8:22 GQL118 Directive "@d"',
    ]);
  });

  test('a directive at a location it lists is valid', () {
    final validated = Validated('''
directive @d on FIELD_DEFINITION
type Query { a: Int @d }''');
    expect(validated.errors, isEmpty);
  });

  test('a directive that is not repeatable used twice is reported at both '
      'uses', () {
    final validated = Validated('''
directive @d on FIELD_DEFINITION
type Query { a: Int @d @d }''');
    expect(validated.errors, [
      '2:21 GQL119 The directive "@d" can only be used once at this '
          'location. | 2:24',
    ]);
  });

  test('a repeatable directive may be used twice', () {
    final validated = Validated('''
directive @d repeatable on FIELD_DEFINITION
type Query { a: Int @d @d }''');
    expect(validated.errors, isEmpty);
  });

  test('an argument given twice is reported at the second', () {
    final validated = Validated('''
directive @d(a: Int) on FIELD_DEFINITION
type Query { f: Int @d(a: 1, a: 2) }''');
    expect(validated.errors, [
      '2:30 GQL120 There can be only one argument named "a". | 2:24',
    ]);
  });

  test('an argument the definition does not have is reported', () {
    final validated = Validated('''
directive @d on FIELD_DEFINITION
type Query { f: Int @d(b: 1) }''');
    expect(validated.errors, [
      '2:24 GQL121 Unknown argument "b" on directive "@d".',
    ]);
  });

  test('a required argument left out is reported with its type', () {
    final validated = Validated('''
directive @d(a: [Int]!) on FIELD_DEFINITION
type Query { f: Int @d }''');
    expect(validated.errors, [
      '2:21 GQL122 Argument "@d(a:)" of type "[Int]!" is required, but it was '
          'not provided.',
    ]);
  });

  test('a non-null argument with a default value may be left out', () {
    final validated = Validated('''
directive @d(a: Int! = 1) on FIELD_DEFINITION
type Query { f: Int @d }''');
    expect(validated.errors, isEmpty);
  });

  test('the built-in directives are known', () {
    final validated = Validated('''
type Query { f: Int @deprecated(reason: "old") }
scalar Url @specifiedBy(url: "https://example.com")''');
    expect(validated.errors, isEmpty);
  });
}
```

In `packages/typed_graphql/test/schema/validation/root_type_rules_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,9 +66,18 @@ type Q { a: Int }''');
     expect(validated.errors.single, contains('used as query, mutation, and '));
   });
 
-  test('a root that names no type is left to the reference rules', () {
+  test('a root that names no type is an unknown type', () {
     final schema = Schema(queryTypeName: 'Missing');
-    expect(Validated.schema(schema).codes, isNot(contains('GQL112')));
+    expect(Validated.schema(schema).errors, [
+      'null GQL116 Unknown type "Missing".',
+    ]);
+  });
+
+  test('an unknown root points at its name in the schema', () {
+    final validated = Validated('''
+schema { query: Q mutation: Missing }
+type Q { a: Int }''');
+    expect(validated.errors, ['1:29 GQL116 Unknown type "Missing".']);
   });
 
   test('assumeValid wraps a schema without checking it', () {
```

Create `packages/typed_graphql/test/schema/validation/type_reference_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  test('a field of an unknown type points at the type name', () {
    final validated = Validated('''
type Query {
  a: [Missing!]
}''');
    expect(validated.errors, ['2:7 GQL116 Unknown type "Missing".']);
  });

  test('an argument of an unknown type is reported', () {
    final validated = Validated('type Query { a(b: Missing): Int }');
    expect(validated.errors, ['1:19 GQL116 Unknown type "Missing".']);
  });

  test('an input field of an unknown type is reported', () {
    final validated = Validated('''
type Query { a: Int }
input In { b: Missing! }''');
    expect(validated.errors, ['2:15 GQL116 Unknown type "Missing".']);
  });

  test('a directive argument of an unknown type is reported', () {
    final validated = Validated('''
type Query { a: Int }
directive @d(b: Missing) on FIELD''');
    expect(validated.errors, ['2:17 GQL116 Unknown type "Missing".']);
  });

  test('an unknown interface points at its name', () {
    final validated = Validated('type Query implements Missing { a: Int }');
    expect(validated.errors, ['1:23 GQL116 Unknown type "Missing".']);
  });

  test('an unknown union member points at its name', () {
    final validated = Validated('''
type Query { a: U }
union U = Query | Missing''');
    expect(validated.errors, ['2:19 GQL116 Unknown type "Missing".']);
  });

  test('a built-in scalar is a known type', () {
    expect(Validated('type Query { a(b: ID): Boolean }').errors, isEmpty);
  });

  test('an unknown type built in code has no place', () {
    final schema = Schema(
      types: [
        ObjectType(
          'Query',
          fields: [SchemaField('a', const NamedType(Name('Missing')))],
        ),
      ],
      queryTypeName: 'Query',
    );
    expect(Validated.schema(schema).errors, [
      'null GQL116 Unknown type "Missing".',
    ]);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/applied_directive_rules_test.dart test/schema/validation/root_type_rules_test.dart test/schema/validation/type_reference_rules_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+14 -17: Some tests failed.`; the first messages: `Expected: ['2:15 GQL117 Unknown directive "@unknown".']`, `Expected: ['1:8 GQL117 Unknown directive "@unknown".']`, `Expected: ['1:12 GQL118 Directive "@deprecated" may not be used on OBJECT.']`, `Expected: ['2:7 GQL116 Unknown type "Missing".']`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -160,5 +160,34 @@ enum DiagnosticCode(
 
   /// `GQL115`: a name that is empty or not of the name syntax
   /// `[_A-Za-z][_0-9A-Za-z]*` (spec §2.1.9), in a schema built in code.
-  invalidName('GQL115');
+  invalidName('GQL115'),
+
+  /// `GQL116`: a reference to a type the schema does not have: the type
+  /// of a field, an argument or an input field, an implemented interface,
+  /// a union member or a root type (spec §3.4).
+  unknownType('GQL116'),
+
+  /// `GQL117`: a directive applied to a schema element that the schema
+  /// does not define (spec §3.13).
+  unknownDirective('GQL117'),
+
+  /// `GQL118`: a directive applied at a location its definition does not
+  /// list, such as `@deprecated` on an object type (spec §3.13).
+  misplacedDirective('GQL118'),
+
+  /// `GQL119`: a directive that is not `repeatable` applied twice to one
+  /// schema element (spec §3.13).
+  repeatedDirective('GQL119'),
+
+  /// `GQL120`: an applied directive given one argument twice
+  /// (spec §5.4.2).
+  duplicateDirectiveArgument('GQL120'),
+
+  /// `GQL121`: an applied directive given an argument its definition
+  /// does not have (spec §5.4.1).
+  unknownDirectiveArgument('GQL121'),
+
+  /// `GQL122`: an applied directive without a required argument: one of
+  /// non-null type and without a default value (spec §5.4.2.1).
+  missingDirectiveArgument('GQL122');
 }
```

In `packages/typed_graphql/lib/src/schema/relations/type_comparator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,12 +9,15 @@ final class const TypeComparator() {
 
   /// The name of the named type inside [type]'s list and non-null
   /// wrappers.
-  String namedTypeName(TypeRef type) {
+  String namedTypeName(TypeRef type) => namedType(type).name.value;
+
+  /// The named type node inside [type]'s list and non-null wrappers.
+  NamedType namedType(TypeRef type) {
     var current = type;
     while (true) {
       switch (current) {
-        case NamedType(:final name):
-          return name.value;
+        case NamedType():
+          return current;
         case ListType(type: final inner) || NonNullType(type: final inner):
           current = inner;
       }
```

Create `packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart`:

```dart
import '../../language/ast/directive_location.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../model/applied_directive.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'node_span.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the directives applied to a schema element (spec §3.13,
/// §5.7): the directive is defined, allowed at the element's location and
/// used once unless repeatable; its arguments are defined, unique and
/// every required one is given.
///
/// graphql-js checks these on SDL before building (`KnownDirectivesRule`,
/// `UniqueDirectivesPerLocationRule`, `KnownArgumentNamesOnDirectivesRule`,
/// `UniqueArgumentNamesRule`, `ProvidedRequiredArgumentsOnDirectivesRule`);
/// the messages are theirs.
final class AppliedDirectiveRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema whose directives are defined.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [directives], applied at [location].
  void check(List<AppliedDirective> directives, DirectiveLocation location) {
    // Only for lookups; the errors follow the order of [directives].
    final firstUses = <String, AppliedDirective>{};
    for (final applied in directives) {
      final definition = schema.directiveNamed(applied.name);
      if (definition == null) {
        report.error(
          .unknownDirective,
          'Unknown directive "@${applied.name}".',
          [applied.span],
        );
        continue;
      }
      if (!definition.locations.contains(location)) {
        report.error(
          .misplacedDirective,
          'Directive "@${applied.name}" may not be used on '
          '${location.spelling}.',
          [applied.span],
        );
      }
      if (firstUses[applied.name] case final first?
          when !definition.isRepeatable) {
        report.error(
          .repeatedDirective,
          'The directive "@${applied.name}" can only be used once at this '
          'location.',
          [first.span, applied.span],
        );
      }
      firstUses.putIfAbsent(applied.name, () => applied);
      _arguments(applied, definition);
    }
  }

  void _arguments(AppliedDirective applied, SchemaDirective definition) {
    UniqueNames(report).check(
      [
        for (final argument in applied.arguments)
          (
            argument.name.value,
            const NodeSpan().within(applied.span, argument),
          ),
      ],
      .duplicateDirectiveArgument,
      (name) => 'There can be only one argument named "$name".',
    );
    for (final argument in applied.arguments) {
      if (definition.argumentNamed(argument.name.value) == null) {
        report.error(
          .unknownDirectiveArgument,
          'Unknown argument "${argument.name.value}" on directive '
          '"@${definition.name}".',
          [const NodeSpan().within(applied.span, argument)],
        );
      }
    }
    for (final parameter in definition.arguments) {
      if (parameter.type is NonNullType &&
          parameter.defaultValue == null &&
          applied.argument(parameter.name) == null) {
        report.error(
          .missingDirectiveArgument,
          'Argument "@${definition.name}(${parameter.name}:)" of type '
          '"${const Printer().print(parameter.type)}" is required, but it '
          'was not provided.',
          [applied.span],
        );
      }
    }
  }
}
```

In `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,22 @@
 import '../model/input_value.dart';
+import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'name_rules.dart';
+import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of the arguments of one field or directive definition (spec
-/// §3.6.1, §3.13): unique and valid names.
+/// §3.6.1, §3.13): unique and valid names, valid applied directives and
+/// known types.
 final class ArgumentRules(
   /// Receives the errors.
   final ValidationReport report,
+
+  /// The schema checked.
+  final Schema schema,
 ) {
-  /// Creates the rules.
+  /// Creates the rules for [schema].
   this;
 
   /// Reports the problems of [arguments], which belong to [owner]: the
@@ -22,6 +29,14 @@ final class ArgumentRules(
     );
     for (final argument in arguments) {
       NameRules(report).check(argument.name, argument.span);
+      AppliedDirectiveRules(
+        report,
+        schema,
+      ).check(argument.appliedDirectives, .argumentDefinition);
+      TypeReferenceRules(
+        report,
+        schema,
+      ).isKnownType(argument.type, argument.span);
     }
   }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import '../build/built_ins.dart';
 import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'argument_rules.dart';
 import 'name_rules.dart';
 import 'unique_names.dart';
@@ -22,7 +23,14 @@ final class DirectiveDefinitionRules(
     _definitions();
     for (final directive in schema.directives) {
       NameRules(report).check(directive.name, directive.span);
-      ArgumentRules(report).check('@${directive.name}', directive.arguments);
+      AppliedDirectiveRules(
+        report,
+        schema,
+      ).check(directive.appliedDirectives, .directiveDefinition);
+      ArgumentRules(
+        report,
+        schema,
+      ).check('@${directive.name}', directive.arguments);
     }
   }
 
```

In `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,14 +1,20 @@
 import '../model/schema_type.dart';
+import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'name_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
-/// The rules of an enum type (spec §3.9): unique and valid value names.
+/// The rules of an enum type (spec §3.9): unique and valid value names
+/// and valid applied directives.
 final class EnumRules(
   /// Receives the errors.
   final ValidationReport report,
+
+  /// The schema checked.
+  final Schema schema,
 ) {
-  /// Creates the rules.
+  /// Creates the rules for [schema].
   this;
 
   /// Reports the problems of [type].
@@ -20,6 +26,10 @@ final class EnumRules(
     );
     for (final value in type.values) {
       NameRules(report).checkEnumValue(value.name, value.span);
+      AppliedDirectiveRules(
+        report,
+        schema,
+      ).check(value.appliedDirectives, .enumValue);
     }
   }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/field_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,16 +1,23 @@
 import '../model/schema_field.dart';
+import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'argument_rules.dart';
 import 'name_rules.dart';
+import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of the fields of an object or interface type (spec §3.6,
-/// §3.7): unique and valid names, and their arguments'.
+/// §3.7): unique and valid names, valid applied directives, known types,
+/// and the rules of their arguments.
 final class FieldRules(
   /// Receives the errors.
   final ValidationReport report,
+
+  /// The schema checked.
+  final Schema schema,
 ) {
-  /// Creates the rules.
+  /// Creates the rules for [schema].
   this;
 
   /// Reports the problems of [fields], the fields of the type [typeName].
@@ -22,7 +29,15 @@ final class FieldRules(
     );
     for (final field in fields) {
       NameRules(report).check(field.name, field.span);
-      ArgumentRules(report).check('$typeName.${field.name}', field.arguments);
+      AppliedDirectiveRules(
+        report,
+        schema,
+      ).check(field.appliedDirectives, .fieldDefinition);
+      TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
+      ArgumentRules(
+        report,
+        schema,
+      ).check('$typeName.${field.name}', field.arguments);
     }
   }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,21 @@
 import '../model/schema_type.dart';
+import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'name_rules.dart';
+import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of an input object type (spec §3.10): unique and valid
-/// field names.
+/// field names, valid applied directives and known field types.
 final class InputObjectRules(
   /// Receives the errors.
   final ValidationReport report,
+
+  /// The schema checked.
+  final Schema schema,
 ) {
-  /// Creates the rules.
+  /// Creates the rules for [schema].
   this;
 
   /// Reports the problems of [type].
@@ -21,6 +27,11 @@ final class InputObjectRules(
     );
     for (final field in type.fields) {
       NameRules(report).check(field.name, field.span);
+      AppliedDirectiveRules(
+        report,
+        schema,
+      ).check(field.appliedDirectives, .inputFieldDefinition);
+      TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
     }
   }
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/interface_rules.dart`:

```dart
import '../model/named_type_reference.dart';
import '../schema.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

/// The rules of the interfaces an object or interface type implements
/// (spec §3.6, §3.7): each names a known type.
final class InterfaceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [interfaces], the interfaces of one type.
  void check(List<NamedTypeReference> interfaces) {
    for (final reference in interfaces) {
      TypeReferenceRules(
        report,
        schema,
      ).isKnown(reference.name, reference.span);
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/node_span.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/node.dart';

/// The span of a syntax node held by a schema element, such as a field's
/// type or an argument's default value, so an error points where
/// graphql-js points.
///
/// The model keeps a span for the element only; a node it holds was read
/// from the same source, so the element's source and the node's offsets
/// give the node's span.
final class const NodeSpan() {
  /// Creates the function; it keeps no state.
  this;

  /// The span of [node] in the source of [element]; null when the
  /// element has no span (it was built in code).
  SourceSpan? within(SourceSpan? element, Node node) => switch (element) {
    final element? => SourceSpan(element.source, node.start, node.end),
    null => null,
  };
}
```

In `packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,13 +1,14 @@
 import '../../language/ast/operation_type.dart';
 import '../model/schema_type.dart';
 import '../schema.dart';
+import 'type_reference_rules.dart';
 import 'validation_report.dart';
 
 /// The rules of the root operation types (spec §3.3.1): a query root
 /// exists, every root is an object type, and no object type is the root
 /// of two operations; graphql-js's `validateRootTypes`.
 ///
-/// A root that names no type is the reference rules' to report.
+/// A root that names no type is reported as an unknown type.
 final class RootTypeRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -28,7 +29,14 @@ final class RootTypeRules(
     final operationsByRoot = <ObjectType, List<OperationType>>{};
     for (final operation in OperationType.values) {
       final name = schema.rootTypeName(operation);
-      switch (name == null ? null : schema.typeNamed(name)) {
+      if (name == null ||
+          !TypeReferenceRules(
+            report,
+            schema,
+          ).isKnown(name, schema.rootTypeSpan(operation))) {
+        continue;
+      }
+      switch (schema.typeNamed(name)) {
         case null:
           continue;
         case final ObjectType type:
```

In `packages/typed_graphql/lib/src/schema/validation/schema_validator.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,4 +1,5 @@
 import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'directive_definition_rules.dart';
 import 'root_type_rules.dart';
 import 'schema_validation_result.dart';
@@ -22,6 +23,10 @@ final class const SchemaValidator() {
   SchemaValidationResult validate(Schema schema) {
     final report = ValidationReport();
     RootTypeRules(report, schema).check();
+    AppliedDirectiveRules(
+      report,
+      schema,
+    ).check(schema.appliedDirectives, .schema);
     DirectiveDefinitionRules(report, schema).check();
     TypeRules(report, schema).check();
     return report.hasErrors
```

Create `packages/typed_graphql/lib/src/schema/validation/type_reference_rules.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rule that a type named by a schema element exists (spec §3.4):
/// the type of a field, an argument or an input field, an implemented
/// interface, a union member or a root type.
///
/// References are names, so the builder keeps an unknown one and this
/// rule reports it, with graphql-js's `KnownTypeNamesRule` message.
final class TypeReferenceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema whose types are known.
  final Schema schema,
) {
  /// Creates the rule for [schema].
  this;

  /// Whether [name], written at [span], names a type of [schema];
  /// reports it when not.
  bool isKnown(String name, SourceSpan? span) {
    if (schema.typeNamed(name) != null) {
      return true;
    }
    report.error(.unknownType, 'Unknown type "$name".', [span]);
    return false;
  }

  /// Whether the named type inside [type], held by an element defined at
  /// [element], exists; reports it at the name when not.
  bool isKnownType(TypeRef type, SourceSpan? element) {
    final named = const TypeComparator().namedType(type);
    return isKnown(named.name.value, const NodeSpan().within(element, named));
  }
}
```

In `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,10 +1,14 @@
+import '../../language/ast/directive_location.dart';
 import '../build/built_ins.dart';
 import '../model/schema_type.dart';
 import '../schema.dart';
+import 'applied_directive_rules.dart';
 import 'enum_rules.dart';
 import 'field_rules.dart';
 import 'input_object_rules.dart';
+import 'interface_rules.dart';
 import 'name_rules.dart';
+import 'union_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
@@ -26,20 +30,40 @@ final class TypeRules(
     _definitions();
     for (final type in schema.types) {
       NameRules(report).check(type.name, type.span);
-      switch (type) {
-        case ObjectType(:final name, :final fields) ||
-            InterfaceType(:final name, :final fields):
-          FieldRules(report).check(name, fields);
-        case EnumType():
-          EnumRules(report).check(type);
-        case InputObjectType():
-          InputObjectRules(report).check(type);
-        case ScalarType() || UnionType():
-          break;
-      }
+      AppliedDirectiveRules(
+        report,
+        schema,
+      ).check(type.appliedDirectives, _locationOf(type));
+      _kind(type);
     }
   }
 
+  void _kind(SchemaType type) {
+    switch (type) {
+      case ObjectType(:final name, :final fields, :final interfaces) ||
+          InterfaceType(:final name, :final fields, :final interfaces):
+        FieldRules(report, schema).check(name, fields);
+        InterfaceRules(report, schema).check(interfaces);
+      case UnionType():
+        UnionRules(report, schema).check(type);
+      case EnumType():
+        EnumRules(report, schema).check(type);
+      case InputObjectType():
+        InputObjectRules(report, schema).check(type);
+      case ScalarType():
+        break;
+    }
+  }
+
+  static DirectiveLocation _locationOf(SchemaType type) => switch (type) {
+    ScalarType() => .scalar,
+    ObjectType() => .object,
+    InterfaceType() => .interface,
+    UnionType() => .union,
+    EnumType() => .enumType,
+    InputObjectType() => .inputObject,
+  };
+
   // The builder drops these from SDL; a schema built in code may hold
   // them.
   void _definitions() {
```

Create `packages/typed_graphql/lib/src/schema/validation/union_rules.dart`:

```dart
import '../model/schema_type.dart';
import '../schema.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

/// The rules of a union type (spec §3.8): each member names a known type.
final class UnionRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [type].
  void check(UnionType type) {
    for (final member in type.memberTypes) {
      TypeReferenceRules(report, schema).isKnown(member.name, member.span);
    }
  }
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/applied_directive_rules_test.dart test/schema/validation/root_type_rules_test.dart test/schema/validation/type_reference_rules_test.dart)
```

Expected: `typed_graphql` `+31: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -262,6 +262,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `DirectiveDefinitionRules` walks the directives; both share
   `ArgumentRules`, `NameRules` (syntax, `__`, reserved enum values) and
   `UniqueNames` (repeats, which only a schema built in code can hold).
+  Every element also goes through `AppliedDirectiveRules` (at its
+  `DirectiveLocation`) and `TypeReferenceRules` (unknown types). An error
+  about a node an element holds (its type, a default value, an applied
+  directive's argument) points at the node through `NodeSpan.within`: the
+  element's source with the node's offsets, as graphql-js points.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

In `docs/superpowers/specs/2026-10-14-m3-type-system-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -107,6 +107,9 @@ behaviour, and the server and client register codecs by scalar name.
 pass; each rule family is a separate class in `schema/validation/`:
 
 - root operation types exist, are object types and are distinct;
+- every referenced type exists: the type of a field, an argument or an input
+  field, an implemented interface, a union member, a root type (the builder
+  keeps references as names, so it builds a schema with an unknown one);
 - names: no `__` prefix outside the introspection types, valid name syntax;
 - object and interface types have at least one field; field and argument types
   are output / input types as the position requires;
@@ -117,7 +120,10 @@ pass; each rule family is a separate class in `schema/validation/`:
 - `@oneOf` input objects: fields are nullable and without defaults;
 - directives: argument types, uniqueness of non-repeatable directives, valid
   locations, no self-referencing directive definition, `@deprecated` only
-  where allowed, applied-directive arguments checked against the definition.
+  where allowed, applied-directive arguments checked against the definition;
+  every applied directive is defined (graphql-js checks this and the unique,
+  known and required directive arguments on SDL before building; here the
+  validator checks them on any schema).
 
 The result is the sealed `SchemaValidationResult`: `ValidSchema` or
 `InvalidSchema(diagnostics)`. `ValidSchema` is a `final class` with a private
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Schema validation reports unknown types (`GQL116`, at the type name; a
  root that names no type included) and checks applied directives: unknown
  (`GQL117`), misplaced (`GQL118`), repeated when not repeatable
  (`GQL119`), with a repeated (`GQL120`), unknown (`GQL121`) or missing
  required (`GQL122`) argument, with graphql-js's SDL-rule messages.
  `TypeComparator.namedType` gives the named type node inside wrappers.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md docs/superpowers/specs/2026-10-14-m3-type-system-design.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/relations/type_comparator.dart packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart packages/typed_graphql/lib/src/schema/validation/argument_rules.dart packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart packages/typed_graphql/lib/src/schema/validation/enum_rules.dart packages/typed_graphql/lib/src/schema/validation/field_rules.dart packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart packages/typed_graphql/lib/src/schema/validation/interface_rules.dart packages/typed_graphql/lib/src/schema/validation/node_span.dart packages/typed_graphql/lib/src/schema/validation/root_type_rules.dart packages/typed_graphql/lib/src/schema/validation/schema_validator.dart packages/typed_graphql/lib/src/schema/validation/type_reference_rules.dart packages/typed_graphql/lib/src/schema/validation/type_rules.dart packages/typed_graphql/lib/src/schema/validation/union_rules.dart packages/typed_graphql/test/schema/validation/applied_directive_rules_test.dart packages/typed_graphql/test/schema/validation/root_type_rules_test.dart packages/typed_graphql/test/schema/validation/type_reference_rules_test.dart
git commit -q -m "feat(typed_graphql): validate type references and applied directives" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 7: Validate default values and directive argument values

Decision 4: one `ValueChecker` checks a constant against an input type, for defaults (`GQL123`) and applied-directive arguments (`GQL124`). It walks with an explicit work list and a parent-linked path, so a value nested 100000 deep costs linear time and memory.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/default_value_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart`, `packages/typed_graphql/lib/src/schema/validation/value_checker.dart`, `packages/typed_graphql/lib/src/schema/validation/value_problem.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`
- Test: `packages/typed_graphql/test/schema/validation/default_value_rules_test.dart`, `packages/typed_graphql/test/schema/validation/value_checker_test.dart`

**Interfaces:**
- Consumes: Task 6 (`AppliedDirectiveRules`, `NodeSpan`, `ArgumentRules`, `InputObjectRules`).
- Produces:
```text
internal:
  ValueChecker(Schema schema) { List<ValueProblem> check(Value value, TypeRef type) }
  final class ValueProblem(String message, Node node, List<Object> path) { String get pathText }  // ' at .a[0].b'
  final class const LeafValueChecker() { String? errorOf(Value value, SchemaType type) }
  DefaultValueRules(report, schema) { void check(String coordinate, InputValue input) }
DiagnosticCode: GQL123 invalidDefaultValue, GQL124 invalidDirectiveArgumentValue
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/validation/default_value_rules_test.dart`:

```dart
import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('an invalid argument default points at the value, directives '
      'first', () {
    expect(
      errorsOf('''
type Query {
  field(arg: Int = 3.14): Int
}
directive @bad(arg: Int = 2.718) on FIELD'''),
      [
        '4:27 GQL123 @bad(arg:) has invalid default value: Int cannot '
            'represent non-integer value: 2.718',
        '2:20 GQL123 Query.field(arg:) has invalid default value: Int cannot '
            'represent non-integer value: 3.14',
      ],
    );
  });

  test('an invalid input field default names the field', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In { field: Int = 3.14 }'''),
      [
        '2:25 GQL123 In.field has invalid default value: Int cannot represent '
            'non-integer value: 3.14',
      ],
    );
  });

  test('a problem inside the value gives its path', () {
    expect(
      errorsOf('''
type Query { f(x: In = {a: [1, "2"]}): Int }
input In { a: [Int] }'''),
      [
        '1:32 GQL123 Query.f(x:) has invalid default value at .a[1]: Int '
            'cannot represent non-integer value: "2"',
      ],
    );
  });

  test('null for a non-null type is reported', () {
    expect(errorsOf('type Query { f(x: Int! = null): Int }'), [
      '1:26 GQL123 Query.f(x:) has invalid default value: Expected value of '
          'non-null type "Int!" not to be null.',
    ]);
  });

  test('a single value for a list type is a list of one', () {
    expect(errorsOf('type Query { f(x: [Int] = 1): Int }'), isEmpty);
  });

  test('a missing required field and an unknown field are reported', () {
    expect(
      errorsOf('''
type Query { f(x: In = {c: 1}): Int }
input In { a: Int! b: Int! = 1 }'''),
      [
        '1:24 GQL123 Query.f(x:) has invalid default value: Expected value of '
            'type "In" to include required field "a", found: { c: 1 }.',
        '1:25 GQL123 Query.f(x:) has invalid default value: Expected value of '
            'type "In" not to include unknown field "c", found: { c: 1 }.',
      ],
    );
  });

  test('a value that is not an object for an input object is reported', () {
    expect(
      errorsOf('''
type Query { f(x: In = 1): Int }
input In { a: Int }'''),
      [
        '1:24 GQL123 Query.f(x:) has invalid default value: Expected value of '
            'type "In" to be an object, found: 1.',
      ],
    );
  });

  test('an enum value must be a known enum value', () {
    expect(
      errorsOf('''
type Query { f(x: E = B, y: E = "A"): Int }
enum E { A }'''),
      [
        '1:23 GQL123 Query.f(x:) has invalid default value: Value "B" does not '
            'exist in "E" enum.',
        '1:33 GQL123 Query.f(y:) has invalid default value: Enum "E" cannot '
            'represent non-enum value: "A".',
      ],
    );
  });

  test('each built-in scalar rejects a literal of another kind', () {
    final errors = errorsOf('''
type Query {
  f(a: String = 1, b: Boolean = 1, c: ID = 1.5, d: Float = "x", e: Int = 2147483648): Int
}''');
    expect(errors.map((error) => error.split('default value: ').last), [
      'String cannot represent a non string value: 1',
      'Boolean cannot represent a non boolean value: 1',
      'ID cannot represent a non-string and non-integer value: 1.5',
      'Float cannot represent non numeric value: "x"',
      'Int cannot represent non 32-bit signed integer value: 2147483648',
    ]);
  });

  test('the built-in scalars accept their literals', () {
    expect(
      errorsOf('''
type Query {
  f(a: String = "s", b: Boolean = true, c: ID = 1, d: Float = 1, e: Int = -2147483648): Int
}'''),
      isEmpty,
    );
  });

  test('a custom scalar accepts any literal', () {
    expect(
      errorsOf('''
type Query { f(a: Json = {a: [1, true, null]}): Int }
scalar Json'''),
      isEmpty,
    );
  });

  test('a OneOf input object needs exactly one non-null field', () {
    expect(
      errorsOf('''
type Query { f(a: In = {a: 1, b: 2}, b: In = {a: null}): Int }
input In @oneOf { a: Int b: Int }'''),
      [
        '1:24 GQL123 Query.f(a:) has invalid default value: Within OneOf Input '
            'Object type "In", exactly one field must be specified, and the '
            'value for that field must be non-null.',
        '1:46 GQL123 Query.f(b:) has invalid default value at .a: Within '
            'OneOf Input Object type "In", exactly one field must be specified, '
            'and the value for that field must be non-null.',
      ],
    );
  });

  test('an invalid directive argument value points at the value', () {
    expect(
      errorsOf('''
directive @d(a: [Int]) on FIELD_DEFINITION
type Query { f: Int @d(a: [1, "x"]) }'''),
      [
        '2:31 GQL124 Argument "@d(a:)" has invalid value at [1]: Int cannot '
            'represent non-integer value: "x"',
      ],
    );
  });
}
```

Create `packages/typed_graphql/test/schema/validation/value_checker_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/validation/value_checker.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final schema = Built('''
type Query { a: Int }
input In { a: In b: Int }''').schema;
  const input = NamedType(Name('In'));

  test('a value nested 100000 deep is checked without recursion', () {
    Value value = ObjectValue(const []);
    for (var depth = 0; depth < 100000; depth++) {
      value = ObjectValue([ObjectField(const Name('a'), value)]);
    }
    expect(ValueChecker(schema).check(value, input), isEmpty);
  });

  test('a problem deep inside a value has the whole path', () {
    Value value = ObjectValue([
      const ObjectField(Name('b'), StringValue('x')),
    ]);
    for (var depth = 0; depth < 3; depth++) {
      value = ObjectValue([ObjectField(const Name('a'), value)]);
    }
    final problem = ValueChecker(schema).check(value, input).single;
    expect(problem.pathText, ' at .a.a.a.b');
  });

  test('a variable built in code is not a constant', () {
    final problem = ValueChecker(
      schema,
    ).check(const Variable(Name('v')), const NamedType(Name('Int'))).single;
    expect(problem.message, r'Expected a constant value, found: $v.');
  });

  test('an Int literal built in code with other text is not an integer', () {
    final problem = ValueChecker(
      schema,
    ).check(const IntValue('x'), const NamedType(Name('Int'))).single;
    expect(problem.message, 'Int cannot represent non-integer value: x');
  });

  test('a value of an output or unknown type is left to the type rules', () {
    const value = IntValue('1');
    expect(
      ValueChecker(schema).check(value, const NamedType(Name('Query'))),
      isEmpty,
    );
    expect(
      ValueChecker(schema).check(value, const NamedType(Name('Missing'))),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/default_value_rules_test.dart test/schema/validation/value_checker_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+3 -11: Some tests failed.`; the first messages: `Error: Error when reading 'lib/src/schema/validation/value_checker.dart': No such file or directory`, `Error: Method not found: 'ValueChecker'.`, `Actual: MappedListIterable<String, String>:[]`.

- [ ] **Step 3: Write the implementation**

A custom scalar accepts any literal: there is no codec at validation time. A variable in a constant is a problem.

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -189,5 +189,13 @@ enum DiagnosticCode(
 
   /// `GQL122`: an applied directive without a required argument: one of
   /// non-null type and without a default value (spec §5.4.2.1).
-  missingDirectiveArgument('GQL122');
+  missingDirectiveArgument('GQL122'),
+
+  /// `GQL123`: a default value of an argument or an input field that is
+  /// not a value of its type (spec §3.6.1, §3.10).
+  invalidDefaultValue('GQL123'),
+
+  /// `GQL124`: an argument of an applied directive whose value is not a
+  /// value of the argument's type (spec §5.6.1).
+  invalidDirectiveArgumentValue('GQL124');
 }
```

In `packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,17 +1,20 @@
 import '../../language/ast/directive_location.dart';
 import '../../language/ast/type_ref.dart';
+import '../../language/ast/value.dart';
 import '../../language/printer/printer.dart';
 import '../model/applied_directive.dart';
+import '../model/input_value.dart';
 import '../model/schema_directive.dart';
 import '../schema.dart';
 import 'node_span.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
+import 'value_checker.dart';
 
 /// The rules of the directives applied to a schema element (spec §3.13,
 /// §5.7): the directive is defined, allowed at the element's location and
-/// used once unless repeatable; its arguments are defined, unique and
-/// every required one is given.
+/// used once unless repeatable; its arguments are defined, unique, of
+/// valid values, and every required one is given.
 ///
 /// graphql-js checks these on SDL before building (`KnownDirectivesRule`,
 /// `UniqueDirectivesPerLocationRule`, `KnownArgumentNamesOnDirectivesRule`,
@@ -76,13 +79,16 @@ final class AppliedDirectiveRules(
       (name) => 'There can be only one argument named "$name".',
     );
     for (final argument in applied.arguments) {
-      if (definition.argumentNamed(argument.name.value) == null) {
-        report.error(
-          .unknownDirectiveArgument,
-          'Unknown argument "${argument.name.value}" on directive '
-          '"@${definition.name}".',
-          [const NodeSpan().within(applied.span, argument)],
-        );
+      switch (definition.argumentNamed(argument.name.value)) {
+        case final parameter?:
+          _value(applied, parameter, argument.value);
+        case null:
+          report.error(
+            .unknownDirectiveArgument,
+            'Unknown argument "${argument.name.value}" on directive '
+            '"@${definition.name}".',
+            [const NodeSpan().within(applied.span, argument)],
+          );
       }
     }
     for (final parameter in definition.arguments) {
@@ -99,4 +105,15 @@ final class AppliedDirectiveRules(
       }
     }
   }
+
+  void _value(AppliedDirective applied, InputValue parameter, Value value) {
+    for (final problem in ValueChecker(schema).check(value, parameter.type)) {
+      report.error(
+        .invalidDirectiveArgumentValue,
+        'Argument "@${applied.name}(${parameter.name}:)" has invalid '
+        'value${problem.pathText}: ${problem.message}',
+        [const NodeSpan().within(applied.span, problem.node)],
+      );
+    }
+  }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,14 +1,15 @@
 import '../model/input_value.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
+import 'default_value_rules.dart';
 import 'name_rules.dart';
 import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of the arguments of one field or directive definition (spec
-/// §3.6.1, §3.13): unique and valid names, valid applied directives and
-/// known types.
+/// §3.6.1, §3.13): unique and valid names, valid applied directives,
+/// known types and valid default values.
 final class ArgumentRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -37,6 +38,10 @@ final class ArgumentRules(
         report,
         schema,
       ).isKnownType(argument.type, argument.span);
+      DefaultValueRules(
+        report,
+        schema,
+      ).check('$owner(${argument.name}:)', argument);
     }
   }
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/default_value_rules.dart`:

```dart
import '../model/input_value.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';
import 'value_checker.dart';

/// The rule that the default value of an argument or an input field is a
/// value of its type (spec §3.6.1, §3.10), as graphql-js's
/// `validateDefaultValue` for a literal default.
final class DefaultValueRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rule for [schema].
  this;

  /// Reports each problem of the default value of [input], whose
  /// coordinate is [coordinate] (`Type.field(arg:)`, `@d(arg:)`,
  /// `Input.field`), at the node it is about.
  void check(String coordinate, InputValue input) {
    final value = input.defaultValue;
    if (value == null) {
      return;
    }
    for (final problem in ValueChecker(schema).check(value, input.type)) {
      report.error(
        .invalidDefaultValue,
        '$coordinate has invalid default value${problem.pathText}: '
        '${problem.message}',
        [const NodeSpan().within(input.span, problem.node)],
      );
    }
  }
}
```

In `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,13 +1,15 @@
 import '../model/schema_type.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
+import 'default_value_rules.dart';
 import 'name_rules.dart';
 import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of an input object type (spec §3.10): unique and valid
-/// field names, valid applied directives and known field types.
+/// field names, valid applied directives, known field types and valid
+/// default values.
 final class InputObjectRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -32,6 +34,10 @@ final class InputObjectRules(
         schema,
       ).check(field.appliedDirectives, .inputFieldDefinition);
       TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
+      DefaultValueRules(
+        report,
+        schema,
+      ).check('${type.name}.${field.name}', field);
     }
   }
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart`:

```dart
import '../../language/ast/value.dart';
import '../../language/printer/printer.dart';
import '../model/schema_type.dart';

/// Whether a constant literal is a value of a scalar or enum type, with
/// the messages of graphql-js's `coerceInputLiteral` of the built-in
/// scalars and of `GraphQLEnumType` (spec §3.5, §3.9).
///
/// A custom scalar accepts any literal, as graphql-js's default
/// `parseLiteral` does: only its codec, at execution, knows its values.
final class const LeafValueChecker() {
  /// Creates the checker; it keeps no state.
  this;

  static const Printer _printer = Printer();
  static final BigInt _minInt = BigInt.from(-2147483648);
  static final BigInt _maxInt = BigInt.from(2147483647);

  /// The message of why [value] is not a value of [type]; null when it is.
  String? errorOf(Value value, SchemaType type) => switch (type) {
    EnumType() => _enumError(value, type),
    ScalarType(name: 'Int') => _intError(value),
    ScalarType(name: 'Float') when value is! IntValue && value is! FloatValue =>
      'Float cannot represent non numeric value: ${_printer.print(value)}',
    ScalarType(name: 'String') when value is! StringValue =>
      'String cannot represent a non string value: ${_printer.print(value)}',
    ScalarType(name: 'Boolean') when value is! BooleanValue =>
      'Boolean cannot represent a non boolean value: ${_printer.print(value)}',
    ScalarType(name: 'ID') when value is! StringValue && value is! IntValue =>
      'ID cannot represent a non-string and non-integer value: '
          '${_printer.print(value)}',
    _ => null,
  };

  String? _intError(Value value) {
    // A node built in code may hold any text; tryParse keeps it an error.
    final text = value is IntValue ? value.value : null;
    final number = text == null ? null : BigInt.tryParse(text);
    if (number == null) {
      return 'Int cannot represent non-integer value: ${_printer.print(value)}';
    }
    if (number < _minInt || number > _maxInt) {
      return 'Int cannot represent non 32-bit signed integer value: $text';
    }
    return null;
  }

  String? _enumError(Value value, EnumType type) {
    if (value is! EnumValue) {
      return 'Enum "${type.name}" cannot represent non-enum value: '
          '${_printer.print(value)}.';
    }
    if (type.valueNamed(value.value) == null) {
      return 'Value "${value.value}" does not exist in "${type.name}" enum.';
    }
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/validation/value_checker.dart`:

```dart
import '../../language/ast/node.dart';
import '../../language/ast/object_field.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../language/printer/printer.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'leaf_value_checker.dart';
import 'value_problem.dart';

/// Whether a constant value, such as a default value or an applied
/// directive's argument, is a value of an input type (spec §3.10 "Input
/// Coercion", graphql-js's `validateInputLiteral` without variables).
///
/// It walks the value with its own stack, so a deeply nested value cannot
/// overflow the call stack, and reports the problems in graphql-js's
/// depth-first order. A type the schema does not have, or one that is not
/// an input type, is the type rules' to report: its values are not
/// checked.
final class ValueChecker(
  /// The schema whose types are known.
  final Schema schema,
) {
  /// Creates the checker for [schema].
  this;

  static const Printer _printer = Printer();

  /// The problems of [value] as a value of [type], in report order.
  List<ValueProblem> check(Value value, TypeRef type) {
    final problems = <ValueProblem>[];
    final work = <_Work>[_Check(value, type, null)];
    while (work.isNotEmpty) {
      switch (work.removeLast()) {
        case _Report(:final problem):
          problems.add(problem);
        case _Check(:final value, :final type, :final path):
          work.addAll(_step(value, type, path).reversed);
      }
    }
    return problems;
  }

  List<_Work> _step(Value value, TypeRef type, _Path? path) =>
      switch ((value, type)) {
        (Variable(), _) => [
          _report(
            'Expected a constant value, found: ${_printer.print(value)}.',
            value,
            path,
          ),
        ],
        (NullValue(), NonNullType()) => [
          _report(
            'Expected value of non-null type "${_printer.print(type)}" not '
            'to be null.',
            value,
            path,
          ),
        ],
        (_, NonNullType(type: final inner)) => [_Check(value, inner, path)],
        (NullValue(), _) => const [],
        (ListValue(:final values), ListType(type: final inner)) => [
          for (final (index, item) in values.indexed)
            _Check(item, inner, _Path(path, index)),
        ],
        // A value that is not a list is a list of one (spec §3.11).
        (_, ListType(type: final inner)) => [_Check(value, inner, path)],
        (_, NamedType(:final name)) => switch (schema.typeNamed(name.value)) {
          final InputObjectType object => _object(value, object, path),
          final type? => [
            if (const LeafValueChecker().errorOf(value, type) case final m?)
              _report(m, value, path),
          ],
          null => const [],
        },
      };

  List<_Work> _object(Value value, InputObjectType type, _Path? path) {
    if (value is! ObjectValue) {
      return [
        _report(
          'Expected value of type "${type.name}" to be an object, found: '
          '${_printer.print(value)}.',
          value,
          path,
        ),
      ];
    }
    // Only for lookups; as graphql-js's keyMap, a repeated field's last
    // value counts.
    final given = {for (final field in value.fields) field.name.value: field};
    return [
      for (final field in type.fields)
        if (given[field.name] case final node?)
          _Check(node.value, field.type, _Path(path, field.name))
        else if (field.type is NonNullType && field.defaultValue == null)
          _report(
            'Expected value of type "${type.name}" to include required field '
            '"${field.name}", found: ${_printer.print(value)}.',
            value,
            path,
          ),
      for (final node in value.fields)
        if (type.fieldNamed(node.name.value) == null)
          _report(
            'Expected value of type "${type.name}" not to include unknown '
            'field "${node.name.value}", found: ${_printer.print(value)}.',
            node,
            path,
          ),
      if (type.isOneOf) ?_oneOf(value, type, path),
    ];
  }

  // Spec §3.10 "OneOf Input Objects": exactly one field, not null.
  _Work? _oneOf(ObjectValue value, InputObjectType type, _Path? path) {
    final known = [
      for (final node in value.fields)
        if (type.fieldNamed(node.name.value) != null) node,
    ];
    final message =
        'Within OneOf Input Object type "${type.name}", exactly one field '
        'must be specified, and the value for that field must be non-null.';
    return switch (known) {
      [ObjectField(name: final name, value: NullValue())] => _report(
        message,
        value,
        _Path(path, name.value),
      ),
      [_] => null,
      _ => _report(message, value, path),
    };
  }

  static _Report _report(String message, Node node, _Path? path) =>
      _Report(ValueProblem(message, node, _Path.keys(path)));
}

sealed class _Work {}

final class _Check(
  final Value value,
  final TypeRef type,
  final _Path? path,
) extends _Work {
  this;
}

// A path shares its parent, so a deep value costs linear time; the list
// of keys is built only for a problem.
final class _Path(final _Path? parent, final Object key) {
  this;

  static List<Object> keys(_Path? path) {
    final keys = <Object>[];
    for (var current = path; current != null; current = current.parent) {
      keys.add(current.key);
    }
    return keys.reversed.toList();
  }
}

final class _Report(final ValueProblem problem) extends _Work {
  this;
}
```

Create `packages/typed_graphql/lib/src/schema/validation/value_problem.dart`:

```dart
import '../../language/ast/node.dart';

/// Why a constant value is not a value of its input type: a message, the
/// node it is about and the path to that node inside the value.
final class ValueProblem(
  /// graphql-js's `validateInputLiteral` message.
  final String message,

  /// The node the problem is about: the value, an item, a field.
  final Node node,
  List<Object> path,
) {
  /// Creates a problem.
  this;

  /// The keys from the whole value to [node]: input field names
  /// ([String]) and list indexes ([int]).
  final List<Object> path = List.unmodifiable(path);

  /// The path as graphql-js's `printPathArray` prints it, `' at .a[0]'`;
  /// empty for the whole value.
  String get pathText => [
    if (path.isNotEmpty) ' at ',
    for (final key in path)
      switch (key) {
        int() => '[$key]',
        _ => '.$key',
      },
  ].join();
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/default_value_rules_test.dart test/schema/validation/value_checker_test.dart)
```

Expected: `typed_graphql` `+18: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -267,6 +267,12 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   about a node an element holds (its type, a default value, an applied
   directive's argument) points at the node through `NodeSpan.within`: the
   element's source with the node's offsets, as graphql-js points.
+  `ValueChecker` checks a constant `Value` against a `TypeRef` with its own
+  stack (paths share their parents, so a deep value costs linear time) and
+  returns `ValueProblem`s (message, node, path); `LeafValueChecker` holds
+  the literal rules of the built-in scalars and enums, and a custom scalar
+  accepts any literal. `DefaultValueRules` and `AppliedDirectiveRules`
+  turn the problems into `GQL123` and `GQL124`.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Schema validation checks constant values against their input types,
  with graphql-js's `validateInputLiteral` messages and paths: default
  values of arguments and input fields (`GQL123`) and the arguments of
  applied directives (`GQL124`), `@oneOf` input objects included.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/applied_directive_rules.dart packages/typed_graphql/lib/src/schema/validation/argument_rules.dart packages/typed_graphql/lib/src/schema/validation/default_value_rules.dart packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart packages/typed_graphql/lib/src/schema/validation/leaf_value_checker.dart packages/typed_graphql/lib/src/schema/validation/value_checker.dart packages/typed_graphql/lib/src/schema/validation/value_problem.dart packages/typed_graphql/test/schema/validation/default_value_rules_test.dart packages/typed_graphql/test/schema/validation/value_checker_test.dart
git commit -q -m "feat(typed_graphql): validate default values and directive argument values" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 8: Validate fields, input types and directive definitions

Spec §7: types with fields, output and input positions, deprecated required inputs, directive definitions with no location, and a directive that references itself (§3.13, which graphql-js lacks: finding 6). The self-reference walk uses a work list and a visited set.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/deprecation_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/directive_reference_rules.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/field_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`
- Test: `packages/typed_graphql/test/schema/validation/directive_definition_rules_test.dart`, `packages/typed_graphql/test/schema/validation/field_rules_test.dart`

**Interfaces:**
- Consumes: Task 7 (`DefaultValueRules`), Task 3 (`Schema.isInputType`, `isOutputType`).
- Produces:
```text
internal:
  DeprecationRules(report) { void checkRequired(String subject, InputValue input) }
  DirectiveReferenceRules(report, schema) { void check(SchemaDirective directive) }
  FieldRules.check(SchemaType type, List<SchemaField> fields)   // was (String typeName, ...)
DiagnosticCode: GQL125 missingFields, GQL126 notOutputType, GQL127 notInputType, GQL128 deprecatedRequiredInput,
  GQL129 missingDirectiveLocations, GQL130 directiveSelfReference
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/validation/directive_definition_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('a directive without locations built in code is reported', () {
    final schema = Schema(
      types: [
        ObjectType(
          'Query',
          fields: [SchemaField('a', const NamedType(Name('Int')))],
        ),
      ],
      directives: [SchemaDirective('d')],
      queryTypeName: 'Query',
    );
    expect(Validated.schema(schema).errors, [
      'null GQL129 Directive @d must include 1 or more locations.',
    ]);
  });

  test('a directive applied to its own argument references itself', () {
    expect(
      errorsOf(
        '''
type Query { a: Int }
directive @invalidExample(arg: String @invalidExample) on ARGUMENT_DEFINITION''',
      ),
      [
        '2:1 GQL130 Directive "@invalidExample" must not reference itself '
            'directly or indirectly.',
      ],
    );
  });

  test('a directive reached through an argument type references itself', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(arg: In) on INPUT_FIELD_DEFINITION
input In { a: Int @d }'''),
      [
        '2:1 GQL130 Directive "@d" must not reference itself directly or '
            'indirectly.',
      ],
    );
  });

  test('a directive reached through another directive references itself', () {
    expect(
      Validated('''
type Query { a: Int }
directive @a(x: Int @b) on ARGUMENT_DEFINITION
directive @b(y: Int @a) on ARGUMENT_DEFINITION''').codes,
      ['GQL130', 'GQL130'],
    );
  });

  test('a cycle of types that does not reach the directive ends', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(arg: In) on FIELD
input In { a: In b: Int @deprecated }'''),
      isEmpty,
    );
  });

  test('a directive that references other directives only is valid', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(arg: Int @deprecated) on FIELD'''),
      isEmpty,
    );
  });
}
```

Create `packages/typed_graphql/test/schema/validation/field_rules_test.dart`:

```dart
import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('an object type without fields points at the type', () {
    expect(
      errorsOf('''
type Query { a: Empty }
type Empty'''),
      ['2:1 GQL125 Type Empty must define one or more fields.'],
    );
  });

  test('an interface type without fields is reported', () {
    expect(
      errorsOf('''
type Query { a: Empty }
interface Empty'''),
      ['2:1 GQL125 Type Empty must define one or more fields.'],
    );
  });

  test('a field of an input type points at its type', () {
    expect(
      errorsOf('''
type Query { a: [In!] }
input In { b: Int }'''),
      [
        '1:17 GQL126 The type of Query.a must be Output Type but got: [In!].',
      ],
    );
  });

  test('a field argument of an output type points at its type', () {
    expect(
      errorsOf('type Query { a(b: Query): Int }'),
      [
        '1:19 GQL127 The type of Query.a(b:) must be Input Type but got: '
            'Query.',
      ],
    );
  });

  test('a directive argument of an output type points at the argument', () {
    expect(
      errorsOf('''
type Query { a: Int }
directive @d(b: Query) on FIELD'''),
      [
        '2:14 GQL127 The type of @d(b:) must be Input Type but got: Query.',
      ],
    );
  });

  test('an input field of an output type points at its type', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In { c: Query }'''),
      ['2:15 GQL127 The type of In.c must be Input Type but got: Query.'],
    );
  });

  test('a deprecated required argument points at the directive and the '
      'type', () {
    expect(
      errorsOf('type Query { a(b: Int! @deprecated): Int }'),
      [
        '1:24 GQL128 Required argument Query.a(b:) cannot be deprecated. | '
            '1:19',
      ],
    );
  });

  test('a deprecated required input field is reported', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In { c: Int! @deprecated }'''),
      [
        '2:20 GQL128 Required input field In.c cannot be deprecated. | 2:15',
      ],
    );
  });

  test('a deprecated argument with a default value is allowed', () {
    expect(
      errorsOf('type Query { a(b: Int! = 1 @deprecated): Int }'),
      isEmpty,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/directive_definition_rules_test.dart test/schema/validation/field_rules_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+3 -12: Some tests failed.`; the first messages: `Expected: ['null GQL129 Directive @d must include 1 or more locations.']`, `Expected: ['2:1 GQL125 Type Empty must define one or more fields.']`, `Expected: ['1:17 GQL126 The type of Query.a must be Output Type but got: [In!].']`, `Expected: ['1:19 GQL127 The type of Query.a(b:) must be Input Type but got: Query.']`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -197,5 +197,28 @@ enum DiagnosticCode(
 
   /// `GQL124`: an argument of an applied directive whose value is not a
   /// value of the argument's type (spec §5.6.1).
-  invalidDirectiveArgumentValue('GQL124');
+  invalidDirectiveArgumentValue('GQL124'),
+
+  /// `GQL125`: an object or interface type without fields (spec §3.6,
+  /// §3.7).
+  missingFields('GQL125'),
+
+  /// `GQL126`: a field whose type is an input object type (spec §3.6).
+  notOutputType('GQL126'),
+
+  /// `GQL127`: an argument or an input field whose type is an object,
+  /// interface or union type (spec §3.6.1, §3.10).
+  notInputType('GQL127'),
+
+  /// `GQL128`: a required argument or input field (non-null, without
+  /// a default value) marked `@deprecated` (spec §3.6.1, §3.10).
+  deprecatedRequiredInput('GQL128'),
+
+  /// `GQL129`: a directive definition without locations, which only
+  /// a schema built in code can have (spec §3.13).
+  missingDirectiveLocations('GQL129'),
+
+  /// `GQL130`: a directive definition that references itself, directly
+  /// or through the types and directives it references (spec §3.13).
+  directiveSelfReference('GQL130');
 }
```

In `packages/typed_graphql/lib/src/schema/validation/argument_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,19 @@
+import '../../language/printer/printer.dart';
 import '../model/input_value.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
 import 'default_value_rules.dart';
+import 'deprecation_rules.dart';
 import 'name_rules.dart';
+import 'node_span.dart';
 import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of the arguments of one field or directive definition (spec
 /// §3.6.1, §3.13): unique and valid names, valid applied directives,
-/// known types and valid default values.
+/// known input types, no deprecated required argument and valid default
+/// values.
 final class ArgumentRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -29,19 +33,42 @@ final class ArgumentRules(
       (name) => 'Argument "$owner($name:)" can only be defined once.',
     );
     for (final argument in arguments) {
+      final coordinate = '$owner(${argument.name}:)';
       NameRules(report).check(argument.name, argument.span);
       AppliedDirectiveRules(
         report,
         schema,
       ).check(argument.appliedDirectives, .argumentDefinition);
-      TypeReferenceRules(
+      _type(coordinate, argument, isOfDirective: owner.startsWith('@'));
+      DeprecationRules(
         report,
-        schema,
-      ).isKnownType(argument.type, argument.span);
-      DefaultValueRules(
-        report,
-        schema,
-      ).check('$owner(${argument.name}:)', argument);
+      ).checkRequired('Required argument $coordinate', argument);
+      DefaultValueRules(report, schema).check(coordinate, argument);
     }
   }
+
+  // graphql-js points at a directive argument, but at a field argument's
+  // type.
+  void _type(
+    String coordinate,
+    InputValue argument, {
+    required bool isOfDirective,
+  }) {
+    if (!TypeReferenceRules(
+          report,
+          schema,
+        ).isKnownType(argument.type, argument.span) ||
+        schema.isInputType(argument.type)) {
+      return;
+    }
+    final span = isOfDirective
+        ? argument.span
+        : const NodeSpan().within(argument.span, argument.type);
+    report.error(
+      .notInputType,
+      'The type of $coordinate must be Input Type but got: '
+      '${const Printer().print(argument.type)}.',
+      [span],
+    );
+  }
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/deprecation_rules.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../model/input_value.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rule that a required argument or input field is not deprecated
/// (spec §3.6.1, §3.10): a caller must give it, so it cannot go away.
final class DeprecationRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rule.
  this;

  /// Reports [input] when it is required (non-null without a default)
  /// and deprecated; [subject] names it, as `Required argument Q.f(a:)`.
  void checkRequired(String subject, InputValue input) {
    if (input.type is! NonNullType ||
        input.defaultValue != null ||
        input.deprecationReason == null) {
      return;
    }
    final deprecated = input.appliedDirectives
        .where((directive) => directive.name == 'deprecated')
        .first;
    report.error(.deprecatedRequiredInput, '$subject cannot be deprecated.', [
      deprecated.span,
      const NodeSpan().within(input.span, input.type),
    ]);
  }
}
```

In `packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,12 +2,14 @@ import '../build/built_ins.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
 import 'argument_rules.dart';
+import 'directive_reference_rules.dart';
 import 'name_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of the directive definitions of a schema (spec §3.13), as
-/// graphql-js's `validateDirectives`.
+/// graphql-js's `validateDirectives`: valid names, at least one location,
+/// valid arguments and no reference to itself.
 final class DirectiveDefinitionRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -27,10 +29,18 @@ final class DirectiveDefinitionRules(
         report,
         schema,
       ).check(directive.appliedDirectives, .directiveDefinition);
+      if (directive.locations.isEmpty) {
+        report.error(
+          .missingDirectiveLocations,
+          'Directive @${directive.name} must include 1 or more locations.',
+          [directive.span],
+        );
+      }
       ArgumentRules(
         report,
         schema,
       ).check('@${directive.name}', directive.arguments);
+      DirectiveReferenceRules(report, schema).check(directive);
     }
   }
 
```

Create `packages/typed_graphql/lib/src/schema/validation/directive_reference_rules.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rule that a directive definition does not reference itself, directly
/// (`directive @d(a: Int @d)`) or through the types and directives it
/// references (spec §3.13 "Type Validation", rules 2 and 3).
///
/// The references form a graph of `@name` (a directive) and `Name` (a
/// type) keys, walked with a stack and a visited set, so a cycle that does
/// not pass through the directive checked ends the walk.
final class DirectiveReferenceRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rule for [schema].
  this;

  /// Reports [directive] when it references itself.
  void check(SchemaDirective directive) {
    final self = '@${directive.name}';
    final visited = <String>{};
    final pending = _ofDirective(directive);
    while (pending.isNotEmpty) {
      final reference = pending.removeLast();
      if (reference == self) {
        report.error(
          .directiveSelfReference,
          'Directive "$self" must not reference itself directly or '
          'indirectly.',
          [directive.span],
        );
        return;
      }
      if (visited.add(reference)) {
        pending.addAll(_of(reference));
      }
    }
  }

  List<String> _of(String reference) {
    if (reference.startsWith('@')) {
      return switch (schema.directiveNamed(reference.substring(1))) {
        final directive? => _ofDirective(directive),
        null => const [],
      };
    }
    return switch (schema.typeNamed(reference)) {
      final type? => _ofType(type),
      null => const [],
    };
  }

  List<String> _ofDirective(SchemaDirective directive) => [
    ..._applied(directive.appliedDirectives),
    for (final argument in directive.arguments) ..._ofInput(argument),
  ];

  List<String> _ofType(SchemaType type) => [
    ..._applied(type.appliedDirectives),
    ...switch (type) {
      ObjectType(:final interfaces, :final fields) ||
      InterfaceType(:final interfaces, :final fields) => [
        for (final interface in interfaces) interface.name,
        for (final field in fields) ..._ofField(field),
      ],
      UnionType(:final memberTypes) => [
        for (final member in memberTypes) member.name,
      ],
      EnumType(:final values) => [
        for (final value in values) ..._applied(value.appliedDirectives),
      ],
      InputObjectType(:final fields) => [
        for (final field in fields) ..._ofInput(field),
      ],
      ScalarType() => const <String>[],
    },
  ];

  List<String> _ofField(SchemaField field) => [
    ..._applied(field.appliedDirectives),
    _named(field.type),
    for (final argument in field.arguments) ..._ofInput(argument),
  ];

  List<String> _ofInput(InputValue input) => [
    ..._applied(input.appliedDirectives),
    _named(input.type),
  ];

  static List<String> _applied(List<AppliedDirective> directives) => [
    for (final directive in directives) '@${directive.name}',
  ];

  static String _named(TypeRef type) =>
      const TypeComparator().namedTypeName(type);
}
```

In `packages/typed_graphql/lib/src/schema/validation/field_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,19 @@
+import '../../language/printer/printer.dart';
 import '../model/schema_field.dart';
+import '../model/schema_type.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
 import 'argument_rules.dart';
 import 'name_rules.dart';
+import 'node_span.dart';
 import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of the fields of an object or interface type (spec §3.6,
-/// §3.7): unique and valid names, valid applied directives, known types,
-/// and the rules of their arguments.
+/// §3.7), as graphql-js's `validateFields`: at least one field; unique and
+/// valid names, valid applied directives, known output types, and the
+/// rules of their arguments.
 final class FieldRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -20,12 +24,19 @@ final class FieldRules(
   /// Creates the rules for [schema].
   this;
 
-  /// Reports the problems of [fields], the fields of the type [typeName].
-  void check(String typeName, List<SchemaField> fields) {
+  /// Reports the problems of [fields], the fields of [type].
+  void check(SchemaType type, List<SchemaField> fields) {
+    if (fields.isEmpty) {
+      report.error(
+        .missingFields,
+        'Type ${type.name} must define one or more fields.',
+        [type.span],
+      );
+    }
     UniqueNames(report).check(
       [for (final field in fields) (field.name, field.span)],
       .duplicateFieldName,
-      (name) => 'Field "$typeName.$name" can only be defined once.',
+      (name) => 'Field "${type.name}.$name" can only be defined once.',
     );
     for (final field in fields) {
       NameRules(report).check(field.name, field.span);
@@ -33,11 +44,27 @@ final class FieldRules(
         report,
         schema,
       ).check(field.appliedDirectives, .fieldDefinition);
-      TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
+      _type('${type.name}.${field.name}', field);
       ArgumentRules(
         report,
         schema,
-      ).check('$typeName.${field.name}', field.arguments);
+      ).check('${type.name}.${field.name}', field.arguments);
     }
   }
+
+  void _type(String coordinate, SchemaField field) {
+    if (!TypeReferenceRules(
+          report,
+          schema,
+        ).isKnownType(field.type, field.span) ||
+        schema.isOutputType(field.type)) {
+      return;
+    }
+    report.error(
+      .notOutputType,
+      'The type of $coordinate must be Output Type but got: '
+      '${const Printer().print(field.type)}.',
+      [const NodeSpan().within(field.span, field.type)],
+    );
+  }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,15 +1,19 @@
+import '../../language/printer/printer.dart';
+import '../model/input_value.dart';
 import '../model/schema_type.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
 import 'default_value_rules.dart';
+import 'deprecation_rules.dart';
 import 'name_rules.dart';
+import 'node_span.dart';
 import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
 /// The rules of an input object type (spec §3.10): unique and valid
-/// field names, valid applied directives, known field types and valid
-/// default values.
+/// field names, valid applied directives, known input types, no
+/// deprecated required field and valid default values.
 final class InputObjectRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -33,11 +37,30 @@ final class InputObjectRules(
         report,
         schema,
       ).check(field.appliedDirectives, .inputFieldDefinition);
-      TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
+      _type('${type.name}.${field.name}', field);
+      DeprecationRules(
+        report,
+      ).checkRequired('Required input field ${type.name}.${field.name}', field);
       DefaultValueRules(
         report,
         schema,
       ).check('${type.name}.${field.name}', field);
     }
   }
+
+  void _type(String coordinate, InputValue field) {
+    if (!TypeReferenceRules(
+          report,
+          schema,
+        ).isKnownType(field.type, field.span) ||
+        schema.isInputType(field.type)) {
+      return;
+    }
+    report.error(
+      .notInputType,
+      'The type of $coordinate must be Input Type but got: '
+      '${const Printer().print(field.type)}.',
+      [const NodeSpan().within(field.span, field.type)],
+    );
+  }
 }
```

In `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -40,9 +40,9 @@ final class TypeRules(
 
   void _kind(SchemaType type) {
     switch (type) {
-      case ObjectType(:final name, :final fields, :final interfaces) ||
-          InterfaceType(:final name, :final fields, :final interfaces):
-        FieldRules(report, schema).check(name, fields);
+      case ObjectType(:final fields, :final interfaces) ||
+          InterfaceType(:final fields, :final interfaces):
+        FieldRules(report, schema).check(type, fields);
         InterfaceRules(report, schema).check(interfaces);
       case UnionType():
         UnionRules(report, schema).check(type);
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/directive_definition_rules_test.dart test/schema/validation/field_rules_test.dart)
```

Expected: `typed_graphql` `+15: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -272,7 +272,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   returns `ValueProblem`s (message, node, path); `LeafValueChecker` holds
   the literal rules of the built-in scalars and enums, and a custom scalar
   accepts any literal. `DefaultValueRules` and `AppliedDirectiveRules`
-  turn the problems into `GQL123` and `GQL124`.
+  turn the problems into `GQL123` and `GQL124`. `DeprecationRules` holds
+  the required-and-deprecated rule of arguments and input fields;
+  `DirectiveReferenceRules` walks `@name` and type-name keys with a stack
+  and a visited set.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Schema validation checks fields and directive definitions: an object or
  interface type without fields (`GQL125`), a field of an input type
  (`GQL126`), an argument or input field of an output type (`GQL127`), a
  deprecated required argument or input field (`GQL128`), a directive
  without locations (`GQL129`) and a directive that references itself,
  directly or through types and directives (`GQL130`).
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/argument_rules.dart packages/typed_graphql/lib/src/schema/validation/deprecation_rules.dart packages/typed_graphql/lib/src/schema/validation/directive_definition_rules.dart packages/typed_graphql/lib/src/schema/validation/directive_reference_rules.dart packages/typed_graphql/lib/src/schema/validation/field_rules.dart packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart packages/typed_graphql/lib/src/schema/validation/type_rules.dart packages/typed_graphql/test/schema/validation/directive_definition_rules_test.dart packages/typed_graphql/test/schema/validation/field_rules_test.dart
git commit -q -m "feat(typed_graphql): validate fields, input types and directive definitions" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 9: Validate interface implementations

Spec §7 "Interfaces" / IsValidImplementation, with graphql-js's messages: implementing a non-interface, cycles, repeats, transitive interfaces, field and argument types, extra required arguments and deprecation. A field of an unknown type reports only the unknown type (Task 6), not a type mismatch.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/implementation_rules.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/validation/interface_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`
- Test: `packages/typed_graphql/test/schema/validation/interface_rules_test.dart`

**Interfaces:**
- Consumes: Task 3 (`Schema.isTypeSubTypeOf`), Task 6 (`InterfaceRules`), Task 8 (`FieldRules`).
- Produces:
```text
internal:
  ImplementationRules(report, schema) { void check(SchemaType type, List<SchemaField> fields, InterfaceType interface) }
  InterfaceRules.check(SchemaType type, List<NamedTypeReference> interfaces, List<SchemaField> fields)
DiagnosticCode: GQL131 implementsNonInterface, GQL132 circularImplementation, GQL133 repeatedInterface,
  GQL134 missingTransitiveInterface, GQL135 missingInterfaceField, GQL136 invalidImplementationFieldType,
  GQL137 missingInterfaceArgument, GQL138 invalidImplementationArgumentType, GQL139 requiredExtraArgument,
  GQL140 deprecatedImplementationField
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/validation/interface_rules_test.dart`:

```dart
import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  group('implemented interfaces', () {
    test('a type that implements a union points at the reference', () {
      expect(
        errorsOf('''
type Query { a: B }
union U = B
type B implements U { a: Int }'''),
        [
          '3:19 GQL131 Type B must only implement Interface types, it cannot '
              'implement U.',
        ],
      );
    });

    test('an interface that implements itself is circular', () {
      expect(
        errorsOf('''
type Query { a: I }
interface I implements I { a: Int }'''),
        [
          '2:24 GQL132 Type I cannot implement itself because it would create '
              'a circular reference.',
        ],
      );
    });

    test('an interface named twice points at both references', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I & I { a: Int }'''),
        ['3:19 GQL133 Type B can only implement I once. | 3:23'],
      );
    });

    test('a missing transitive interface points at both references', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
interface J implements I { a: Int }
type B implements J { a: Int }'''),
        [
          '3:24 GQL134 Type B must implement I because it is implemented by J. '
              '| 4:19',
        ],
      );
    });

    test('interfaces that implement each other are circular', () {
      expect(
        errorsOf('''
type Query { a: I }
interface I implements J { a: Int }
interface J implements I { a: Int }'''),
        [
          '3:24 GQL132 Type I cannot implement J because it would create a '
              'circular reference. | 2:24',
          '2:24 GQL132 Type J cannot implement I because it would create a '
              'circular reference. | 3:24',
        ],
      );
    });
  });

  group('implemented fields', () {
    test('a missing interface field points at the field and the type', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int b: Int }
type B implements I { a: Int }'''),
        [
          '2:22 GQL135 Interface field I.b expected but B does not provide '
              'it. | 3:1',
        ],
      );
    });

    test('a field of a type that is not a subtype points at both types', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int! }
type B implements I { a: Int }'''),
        [
          '2:18 GQL136 Interface field I.a expects type Int! but B.a is type '
              'Int. | 3:26',
        ],
      );
    });

    test('a covariant field type is accepted', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: I }
type B implements I { a: B! }'''),
        isEmpty,
      );
    });

    test('a missing interface argument points at it and the field', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a(x: Int): Int }
type B implements I { a: Int }'''),
        [
          '2:17 GQL137 Interface field argument I.a(x:) expected but B.a does '
              'not provide it. | 3:23',
        ],
      );
    });

    test('an argument of another type points at both types', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a(x: Int): Int }
type B implements I { a(x: Int!): Int }'''),
        [
          '2:20 GQL138 Interface field argument I.a(x:) expects type Int but '
              'B.a(x:) is type Int!. | 3:28',
        ],
      );
    });

    test('an added required argument points at it and the field', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I { a(y: Int!): Int }'''),
        [
          '3:25 GQL139 Argument "B.a(y:)" must not be required type "Int!" if '
              'not provided by the Interface field "I.a". | 2:15',
        ],
      );
    });

    test('an added optional argument is accepted', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I { a(y: Int, z: Int! = 1): Int }'''),
        isEmpty,
      );
    });

    test('a deprecated implementation of a live field is reported', () {
      expect(
        errorsOf('''
type Query { a: B }
interface I { a: Int }
type B implements I { a: Int @deprecated }'''),
        [
          '3:30 GQL140 Interface field I.a is not deprecated, so '
              'implementation field B.a must not be deprecated. | 3:26',
        ],
      );
    });

    test('a field of an unknown type reports only the unknown type', () {
      expect(
        Validated('''
type Query { a: B }
interface I { a: Missing }
type B implements I { a: Int }''').codes,
        ['GQL116'],
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/interface_rules_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+3 -11: Some tests failed.`; the first messages: `Expected: ['3:19 GQL133 Type B can only implement I once. | 3:23']`, `Expected: ['3:24 GQL134 Type B must implement I because it is implemented by J. | 4:19']`, `Expected: ['2:22 GQL135 Interface field I.b expected but B does not provide it. | 3:1']`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -220,5 +220,46 @@ enum DiagnosticCode(
 
   /// `GQL130`: a directive definition that references itself, directly
   /// or through the types and directives it references (spec §3.13).
-  directiveSelfReference('GQL130');
+  directiveSelfReference('GQL130'),
+
+  /// `GQL131`: an object or interface type that implements a type
+  /// that is not an interface type (spec §3.6, §3.7).
+  implementsNonInterface('GQL131'),
+
+  /// `GQL132`: an interface type that implements itself, directly or
+  /// through the interfaces it inherits (spec §3.7).
+  circularImplementation('GQL132'),
+
+  /// `GQL133`: an object or interface type that names one interface twice
+  /// among the interfaces it implements (spec §3.6, §3.7).
+  repeatedInterface('GQL133'),
+
+  /// `GQL134`: a type that implements an interface but not the
+  /// interfaces that interface implements (spec §3.7).
+  missingTransitiveInterface('GQL134'),
+
+  /// `GQL135`: a type without a field of an interface it implements
+  /// (spec §3.6.3 `IsValidImplementation`).
+  missingInterfaceField('GQL135'),
+
+  /// `GQL136`: a field whose type is not a subtype of the type of
+  /// the interface field it implements (spec §3.6.3
+  /// `IsValidImplementationFieldType`).
+  invalidImplementationFieldType('GQL136'),
+
+  /// `GQL137`: a field without an argument of the interface field it
+  /// implements (spec §3.6.3).
+  missingInterfaceArgument('GQL137'),
+
+  /// `GQL138`: an argument whose type is not the type of the same
+  /// argument of the interface field (spec §3.6.3).
+  invalidImplementationArgumentType('GQL138'),
+
+  /// `GQL139`: a required argument of a field that the interface field
+  /// it implements does not have (spec §3.6.3).
+  requiredExtraArgument('GQL139'),
+
+  /// `GQL140`: a deprecated field that implements an interface
+  /// field that is not deprecated (spec §3.6.3).
+  deprecatedImplementationField('GQL140');
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/implementation_rules.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rules of a type implementing one interface's fields (spec §3.6.3
/// `IsValidImplementation`), as graphql-js's
/// `validateTypeImplementsInterface`: each interface field exists with a
/// covariant type, each of its arguments exists with the same type, an
/// added argument is optional, and a field is deprecated only when the
/// interface field is.
final class ImplementationRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  static const Printer _printer = Printer();

  /// Reports how [type], whose fields are [fields], fails to implement the
  /// fields of [interface].
  void check(
    SchemaType type,
    List<SchemaField> fields,
    InterfaceType interface,
  ) {
    for (final expected in interface.fields) {
      final field = fields.where((f) => f.name == expected.name).firstOrNull;
      if (field == null) {
        report.error(
          .missingInterfaceField,
          'Interface field ${interface.name}.${expected.name} expected but '
          '${type.name} does not provide it.',
          [expected.span, type.span],
        );
        continue;
      }
      _fieldType(type, field, interface, expected);
      _arguments(type, field, interface, expected);
      _deprecation(type, field, interface, expected);
    }
  }

  void _fieldType(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    // An unknown type is reported once, by the type reference rules.
    if (!_isKnown(field.type) ||
        !_isKnown(expected.type) ||
        schema.isTypeSubTypeOf(field.type, expected.type)) {
      return;
    }
    report.error(
      .invalidImplementationFieldType,
      'Interface field ${interface.name}.${expected.name} expects type '
      '${_printer.print(expected.type)} but ${type.name}.${field.name} is '
      'type ${_printer.print(field.type)}.',
      [
        const NodeSpan().within(expected.span, expected.type),
        const NodeSpan().within(field.span, field.type),
      ],
    );
  }

  void _arguments(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    final owner = '${type.name}.${field.name}';
    for (final wanted in expected.arguments) {
      final coordinate = '${interface.name}.${expected.name}(${wanted.name}:)';
      switch (field.argumentNamed(wanted.name)) {
        case null:
          report.error(
            .missingInterfaceArgument,
            'Interface field argument $coordinate expected but $owner does '
            'not provide it.',
            [wanted.span, field.span],
          );
        case final given
            when !const TypeComparator().isEqual(wanted.type, given.type):
          report.error(
            .invalidImplementationArgumentType,
            'Interface field argument $coordinate expects type '
            '${_printer.print(wanted.type)} but $owner(${given.name}:) is '
            'type ${_printer.print(given.type)}.',
            [
              const NodeSpan().within(wanted.span, wanted.type),
              const NodeSpan().within(given.span, given.type),
            ],
          );
        case _:
          break;
      }
    }
    _addedArguments(type, field, interface, expected);
  }

  void _addedArguments(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    final owner = '${type.name}.${field.name}';
    for (final added in field.arguments) {
      if (added.type is NonNullType &&
          added.defaultValue == null &&
          expected.argumentNamed(added.name) == null) {
        report.error(
          .requiredExtraArgument,
          'Argument "$owner(${added.name}:)" must not be required type '
          '"${_printer.print(added.type)}" if not provided by the Interface '
          'field "${interface.name}.${expected.name}".',
          [added.span, expected.span],
        );
      }
    }
  }

  void _deprecation(
    SchemaType type,
    SchemaField field,
    InterfaceType interface,
    SchemaField expected,
  ) {
    if (field.deprecationReason == null || expected.deprecationReason != null) {
      return;
    }
    final deprecated = field.appliedDirectives
        .where((directive) => directive.name == 'deprecated')
        .first;
    report.error(
      .deprecatedImplementationField,
      'Interface field ${interface.name}.${expected.name} is not deprecated, '
      'so implementation field ${type.name}.${field.name} must not be '
      'deprecated.',
      [deprecated.span, const NodeSpan().within(field.span, field.type)],
    );
  }

  bool _isKnown(TypeRef type) => schema.namedTypeOf(type) != null;
}
```

In `packages/typed_graphql/lib/src/schema/validation/interface_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,10 +1,17 @@
+import '../../diagnostics/source_span.dart';
 import '../model/named_type_reference.dart';
+import '../model/schema_field.dart';
+import '../model/schema_type.dart';
 import '../schema.dart';
+import 'implementation_rules.dart';
 import 'type_reference_rules.dart';
 import 'validation_report.dart';
 
 /// The rules of the interfaces an object or interface type implements
-/// (spec §3.6, §3.7): each names a known type.
+/// (spec §3.6, §3.7 "Type Validation"), as graphql-js's
+/// `validateInterfaces`: each is a known interface type, other than the
+/// type itself, named once; the type also implements the interfaces it
+/// inherits, and implements each interface's fields.
 final class InterfaceRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -15,13 +22,97 @@ final class InterfaceRules(
   /// Creates the rules for [schema].
   this;
 
-  /// Reports the problems of [interfaces], the interfaces of one type.
-  void check(List<NamedTypeReference> interfaces) {
+  /// Reports the problems of the [interfaces] of [type], whose fields are
+  /// [fields].
+  void check(
+    SchemaType type,
+    List<NamedTypeReference> interfaces,
+    List<SchemaField> fields,
+  ) {
+    final implemented = <String>{};
     for (final reference in interfaces) {
-      TypeReferenceRules(
+      if (!TypeReferenceRules(
         report,
         schema,
-      ).isKnown(reference.name, reference.span);
+      ).isKnown(reference.name, reference.span)) {
+        continue;
+      }
+      switch (schema.typeNamed(reference.name)) {
+        case final InterfaceType interface when interface.name == type.name:
+          report.error(
+            .circularImplementation,
+            'Type ${type.name} cannot implement itself because it would '
+            'create a circular reference.',
+            _spansOf(interfaces, interface.name),
+          );
+        case final InterfaceType interface
+            when !implemented.add(interface.name):
+          report.error(
+            .repeatedInterface,
+            'Type ${type.name} can only implement ${interface.name} once.',
+            _spansOf(interfaces, interface.name),
+          );
+        case final InterfaceType interface:
+          _ancestors(type, interfaces, interface);
+          ImplementationRules(report, schema).check(type, fields, interface);
+        case final other?:
+          _notInterface(type, interfaces, other);
+        case null:
+          break;
+      }
     }
   }
+
+  void _notInterface(
+    SchemaType type,
+    List<NamedTypeReference> interfaces,
+    SchemaType other,
+  ) => report.error(
+    .implementsNonInterface,
+    'Type ${type.name} must only implement Interface types, it cannot '
+    'implement ${other.name}.',
+    _spansOf(interfaces, other.name),
+  );
+
+  // graphql-js's validateTypeImplementsAncestors (spec §3.7, "the
+  // implementing type must also implement the interfaces it inherits").
+  void _ancestors(
+    SchemaType type,
+    List<NamedTypeReference> interfaces,
+    InterfaceType interface,
+  ) {
+    for (final transitive in interface.interfaces) {
+      if (schema.typeNamed(transitive.name) == null ||
+          interfaces.any((reference) => reference.name == transitive.name)) {
+        continue;
+      }
+      final spans = [
+        ..._spansOf(interface.interfaces, transitive.name),
+        ..._spansOf(interfaces, interface.name),
+      ];
+      if (transitive.name == type.name) {
+        report.error(
+          .circularImplementation,
+          'Type ${type.name} cannot implement ${interface.name} because it '
+          'would create a circular reference.',
+          spans,
+        );
+      } else {
+        report.error(
+          .missingTransitiveInterface,
+          'Type ${type.name} must implement ${transitive.name} because it is '
+          'implemented by ${interface.name}.',
+          spans,
+        );
+      }
+    }
+  }
+
+  static List<SourceSpan?> _spansOf(
+    List<NamedTypeReference> references,
+    String name,
+  ) => [
+    for (final reference in references)
+      if (reference.name == name) reference.span,
+  ];
 }
```

In `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -43,7 +43,7 @@ final class TypeRules(
       case ObjectType(:final fields, :final interfaces) ||
           InterfaceType(:final fields, :final interfaces):
         FieldRules(report, schema).check(type, fields);
-        InterfaceRules(report, schema).check(interfaces);
+        InterfaceRules(report, schema).check(type, interfaces, fields);
       case UnionType():
         UnionRules(report, schema).check(type);
       case EnumType():
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/interface_rules_test.dart)
```

Expected: `typed_graphql` `+14: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -275,7 +275,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   turn the problems into `GQL123` and `GQL124`. `DeprecationRules` holds
   the required-and-deprecated rule of arguments and input fields;
   `DirectiveReferenceRules` walks `@name` and type-name keys with a stack
-  and a visited set.
+  and a visited set. `InterfaceRules` checks the references of an object or
+  interface type and hands each interface to `ImplementationRules`
+  (spec §3.6.3 `IsValidImplementation`).
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Schema validation checks implemented interfaces, with graphql-js's
  messages: a non-interface (`GQL131`), a circular implementation
  (`GQL132`), a repeat (`GQL133`), a missing inherited interface
  (`GQL134`), and, for each interface field, a missing field (`GQL135`),
  a field type that is not a subtype (`GQL136`), a missing argument
  (`GQL137`), an argument of another type (`GQL138`), an added required
  argument (`GQL139`) and a deprecated implementation of a live field
  (`GQL140`).
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/implementation_rules.dart packages/typed_graphql/lib/src/schema/validation/interface_rules.dart packages/typed_graphql/lib/src/schema/validation/type_rules.dart packages/typed_graphql/test/schema/validation/interface_rules_test.dart
git commit -q -m "feat(typed_graphql): validate interface implementations" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 10: Validate unions, enums, input objects and input cycles

The last rule families: unions, enums, input objects and `@oneOf`, input objects that cannot be finite (graphql-js's `validateInputObjectCircularRefs`, with its "cycle through" messages), and default values that reference themselves (graphql-js's `validateInputObjectDefaultValueCircularRefs`). Both cycle walks are iterative and run once over the schema, so a chain of 10000 input types is linear.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/validation/default_value_cycle_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/finite_value_rules.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`, `packages/typed_graphql/lib/src/schema/validation/union_rules.dart`
- Test: `packages/typed_graphql/test/schema/validation/input_cycle_rules_test.dart`, `packages/typed_graphql/test/schema/validation/union_enum_rules_test.dart`

**Interfaces:**
- Consumes: Task 9 (`TypeRules`), Task 7 (`DefaultValueRules`), Task 6 (`UnionRules`, `EnumRules`).
- Produces:
```text
internal:
  FiniteValueRules(report, schema) { void check() }
  DefaultValueCycleRules(report, schema) { void check(InputObjectType type) }
DiagnosticCode: GQL141 missingUnionMembers, GQL142 repeatedUnionMember, GQL143 nonObjectUnionMember,
  GQL144 missingEnumValues, GQL145 missingInputFields, GQL146 nonNullOneOfField, GQL147 defaultedOneOfField,
  GQL148 infiniteInputValue, GQL149 defaultValueCycle
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/validation/input_cycle_rules_test.dart`:

```dart
import 'package:test/test.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  group('finite values', () {
    test('nullable and list fields break a cycle', () {
      expect(
        errorsOf('''
type Query { a(b: In): Int }
input In { a: In b: [In] c: [In!]! d: Other }
input Other { a: In }'''),
        isEmpty,
      );
    });

    test('a non-null self reference points at the field', () {
      expect(
        errorsOf('''
type Query { a(b: In): Int }
input In { a: In! }'''),
        [
          '2:12 GQL148 Input Object In cannot be provided a finite value '
              'because it references itself through fields: In.a.',
        ],
      );
    });

    test('a cycle through two types points at every field', () {
      expect(
        errorsOf('''
type Query { a(b: A): Int }
input A { b: B! }
input B { a: A! }'''),
        [
          '2:11 GQL148 Input Object A cannot be provided a finite value '
              'because it references itself through fields: A.b, B.a. | 3:11',
        ],
      );
    });

    test('a type that reaches a cycle without being in it is not reported', () {
      expect(
        Validated('''
type Query { a(b: A): Int }
input A { b: B! }
input B { b: B! }''').errors,
        [
          '3:11 GQL148 Input Object B cannot be provided a finite value '
              'because it references itself through fields: B.b.',
        ],
      );
    });

    test('a OneOf type with one finite field is finite', () {
      expect(
        errorsOf('''
type Query { a(b: In): Int }
input In @oneOf { a: In b: Int }'''),
        isEmpty,
      );
    });

    test('a OneOf type whose every field is infinite is reported', () {
      expect(
        Validated('''
type Query { a(b: In): Int }
input In @oneOf { a: In b: In }''').codes,
        ['GQL148', 'GQL148'],
      );
    });

    test('a long chain is checked without recursion', () {
      final types = [
        for (var i = 0; i < 20000; i++) 'input T$i { a: T${i + 1}! }',
      ];
      expect(
        Validated('''
type Query { a(b: T0): Int }
${types.join('\n')}
input T20000 { a: T0! }''').codes,
        ['GQL148'],
      );
    });
  });

  group('default value cycles', () {
    test('a default value that contains itself points at it', () {
      expect(
        errorsOf('''
type Query { a(b: A): Int }
input A { x: A = {} }'''),
        [
          '2:18 GQL149 Invalid circular reference. The default value of Input '
              'Object field A.x references itself.',
        ],
      );
    });

    test('a cycle through other defaults names them', () {
      expect(
        errorsOf('''
type Query { a(b: B): Int }
input B { x: B2 = {} }
input B2 { x: B = {} }'''),
        [
          '2:19 GQL149 Invalid circular reference. The default value of Input '
              'Object field B.x references itself via the default values of: '
              'B2.x. | 3:19',
        ],
      );
    });

    test('a cycle inside a list default is found', () {
      expect(
        Validated('''
type Query { a(b: C): Int }
input C { x: [C] = [{}] }''').codes,
        ['GQL149'],
      );
    });

    test('a default that gives the field a value breaks the cycle', () {
      expect(
        errorsOf('''
type Query { a(b: A): Int }
input A { x: A = { x: null } y: Int }'''),
        isEmpty,
      );
    });

    test('a long chain of defaults is walked without recursion', () {
      final types = [
        for (var i = 0; i < 20000; i++) 'input T$i { a: T${i + 1} = {} }',
      ];
      expect(
        Validated('''
type Query { a(b: T0): Int }
${types.join('\n')}
input T20000 { a: Int }''').codes,
        isEmpty,
      );
    });
  });
}
```

Create `packages/typed_graphql/test/schema/validation/union_enum_rules_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../validated.dart';

void main() {
  List<String> errorsOf(String sdl) => Validated(sdl).errors;

  test('a union without members points at the union', () {
    expect(
      errorsOf('''
type Query { a: U }
union U'''),
      ['2:1 GQL141 Union type U must define one or more member types.'],
    );
  });

  test('a union member named twice points at both references', () {
    final schema = Schema(
      types: [
        ObjectType(
          'Query',
          fields: [SchemaField('a', const NamedType(Name('U')))],
        ),
        UnionType(
          'U',
          memberTypes: [
            const NamedTypeReference('Query'),
            const NamedTypeReference('Query'),
          ],
        ),
      ],
      queryTypeName: 'Query',
    );
    expect(Validated.schema(schema).errors, [
      'null GQL142 Union type U can only include type Query once.',
    ]);
  });

  test('a union member that is not an object type points at it', () {
    expect(
      errorsOf('''
type Query { a: U }
union U = Query | I
interface I { a: Int }'''),
      [
        '2:19 GQL143 Union type U can only include Object types, it cannot '
            'include I.',
      ],
    );
  });

  test('an enum without values points at the enum', () {
    expect(
      errorsOf('''
type Query { a: E }
enum E'''),
      ['2:1 GQL144 Enum type E must define one or more values.'],
    );
  });

  test('an input object without fields points at the type', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In'''),
      ['2:1 GQL145 Input Object type In must define one or more fields.'],
    );
  });

  test('a non-null field of a OneOf type points at its type', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In @oneOf { c: Int! d: Int }'''),
      ['2:22 GQL146 OneOf input field In.c must be nullable.'],
    );
  });

  test('a defaulted field of a OneOf type points at the field', () {
    expect(
      errorsOf('''
type Query { a(b: In): Int }
input In @oneOf { c: Int = 1 d: Int }'''),
      ['2:19 GQL147 OneOf input field In.c cannot have a default value.'],
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/input_cycle_rules_test.dart test/schema/validation/union_enum_rules_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+4 -15: Some tests failed.`; the first messages: `Expected: ['2:1 GQL141 Union type U must define one or more member types.']`, `Expected: ['null GQL142 Union type U can only include type Query once.']`, `Expected: ['2:19 GQL143 Union type U can only include Object types, it cannot include I.']`, `Expected: ['2:1 GQL144 Enum type E must define one or more values.']`.

- [ ] **Step 3: Write the implementation**

`@oneOf` provided by an input extension cannot be checked (finding 2).

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -261,5 +261,38 @@ enum DiagnosticCode(
 
   /// `GQL140`: a deprecated field that implements an interface
   /// field that is not deprecated (spec §3.6.3).
-  deprecatedImplementationField('GQL140');
+  deprecatedImplementationField('GQL140'),
+
+  /// `GQL141`: a union type without member types (spec §3.8).
+  missingUnionMembers('GQL141'),
+
+  /// `GQL142`: a union type that names one member type twice
+  /// (spec §3.8).
+  repeatedUnionMember('GQL142'),
+
+  /// `GQL143`: a union member that is not an object type (spec §3.8).
+  nonObjectUnionMember('GQL143'),
+
+  /// `GQL144`: an enum type without values (spec §3.9).
+  missingEnumValues('GQL144'),
+
+  /// `GQL145`: an input object type without fields (spec §3.10).
+  missingInputFields('GQL145'),
+
+  /// `GQL146`: a field of a `@oneOf` input object type of non-null
+  /// type (spec §3.10.1).
+  nonNullOneOfField('GQL146'),
+
+  /// `GQL147`: a field of a `@oneOf` input object type with a default
+  /// value (spec §3.10.1).
+  defaultedOneOfField('GQL147'),
+
+  /// `GQL148`: an input object type that cannot be given a finite
+  /// value: it reaches itself through non-null fields, or through every
+  /// field of a `@oneOf` type (spec §3.10.1 `InputObjectHasUnbreakableCycle`).
+  infiniteInputValue('GQL148'),
+
+  /// `GQL149`: an input field whose default value contains itself,
+  /// directly or through the default values of other fields (spec §3.10).
+  defaultValueCycle('GQL149');
 }
```

Create `packages/typed_graphql/lib/src/schema/validation/default_value_cycle_rules.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/value.dart';
import '../model/input_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rule that no input field's default value contains itself (spec
/// §3.10, "default values must not form a cycle"), as graphql-js's
/// `createInputObjectDefaultValueCircularRefsValidator`: a depth-first
/// walk through the default values, with its own stack.
///
/// One instance serves one validation run: the fields it has walked are
/// remembered across input types, so a cycle is reported once and the run
/// costs linear time.
final class DefaultValueCycleRules {
  /// Creates the rule for [schema].
  DefaultValueCycleRules(this.report, this.schema);

  /// Receives the errors.
  final ValidationReport report;

  /// The schema checked.
  final Schema schema;

  final Set<String> _visited = {};

  // The fields whose default values are being walked, outermost first,
  // with the span of each default value; _positions indexes it by field.
  final List<(String, SourceSpan?)> _path = [];
  final Map<String, int> _positions = {};

  /// Reports the cycles reached from the fields of [type].
  void check(InputObjectType type) {
    final work = <_Work>[];
    _pushFields(work, type, const {});
    while (work.isNotEmpty) {
      switch (work.removeLast()) {
        case _Literal(:final type, :final value):
          _literal(work, type, value);
        case _Field(:final field, :final coordinate, :final type):
          _field(work, field, coordinate, type);
        case _Leave(:final coordinate):
          _path.removeLast();
          _positions.remove(coordinate);
      }
    }
  }

  void _literal(List<_Work> work, InputObjectType type, Value value) {
    switch (value) {
      case ListValue(:final values):
        work.addAll([
          for (final item in values.reversed) _Literal(type, item),
        ]);
      case ObjectValue(:final fields):
        _pushFields(work, type, {
          for (final field in fields) field.name.value: field.value,
        });
      case _:
        break;
    }
  }

  // The fields given in [given] are walked through the given value, the
  // others through their own default values.
  void _pushFields(
    List<_Work> work,
    InputObjectType type,
    Map<String, Value> given,
  ) {
    final items = <_Work>[
      for (final field in type.fields)
        if (schema.namedTypeOf(field.type) case final InputObjectType target)
          switch (given[field.name]) {
            final value? => _Literal(target, value),
            null => _Field(field, '${type.name}.${field.name}', target),
          },
    ];
    work.addAll(items.reversed);
  }

  void _field(
    List<_Work> work,
    InputValue field,
    String coordinate,
    InputObjectType type,
  ) {
    final defaultValue = field.defaultValue;
    if (defaultValue == null) return;
    if (_positions[coordinate] case final position?) {
      _report(coordinate, position);
      return;
    }
    if (!_visited.add(coordinate)) return;
    _positions[coordinate] = _path.length;
    _path.add((
      coordinate,
      const NodeSpan().within(field.span, defaultValue),
    ));
    work
      ..add(_Leave(coordinate))
      ..add(_Literal(type, defaultValue));
  }

  void _report(String coordinate, int position) {
    final via = [for (final (name, _) in _path.skip(position + 1)) name];
    report.error(
      .defaultValueCycle,
      'Invalid circular reference. The default value of Input Object field '
      '$coordinate references itself'
      '${via.isEmpty ? '' : ' via the default values of: ${via.join(', ')}'}.',
      [for (final (_, span) in _path.skip(position)) span],
    );
  }
}

sealed class _Work {}

final class _Literal(final InputObjectType type, final Value value)
    extends _Work {
  this;
}

final class _Field(
  final InputValue field,
  final String coordinate,
  final InputObjectType type,
) extends _Work {
  this;
}

// Ends the walk of a field's default value: the field leaves the path.
final class _Leave(final String coordinate) extends _Work {
  this;
}
```

In `packages/typed_graphql/lib/src/schema/validation/enum_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,8 +5,8 @@ import 'name_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
-/// The rules of an enum type (spec §3.9): unique and valid value names
-/// and valid applied directives.
+/// The rules of an enum type (spec §3.9): one or more values, unique and
+/// valid value names and valid applied directives.
 final class EnumRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -19,6 +19,13 @@ final class EnumRules(
 
   /// Reports the problems of [type].
   void check(EnumType type) {
+    if (type.values.isEmpty) {
+      report.error(
+        .missingEnumValues,
+        'Enum type ${type.name} must define one or more values.',
+        [type.span],
+      );
+    }
     UniqueNames(report).check(
       [for (final value in type.values) (value.name, value.span)],
       .duplicateEnumValueName,
```

Create `packages/typed_graphql/lib/src/schema/validation/finite_value_rules.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../model/input_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'validation_report.dart';

/// The rule that every input object type can be given a finite value
/// (spec §3.10.1 `InputObjectHasUnbreakableCycle`), as graphql-js's
/// `detectInputObjectNonFiniteValues`: the types known to have a finite
/// value are propagated through the reverse edges in one pass, then each
/// cycle among the others is reported once, by a walk with its own stack.
final class FiniteValueRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports every input object type that cannot be given a finite value.
  void check() {
    // A repeated name, which only a schema built in code holds, keeps the
    // first type, as Schema.typeNamed does.
    final states = <String, _State>{};
    for (final type in schema.types.whereType<InputObjectType>()) {
      states.putIfAbsent(type.name, () => _State(type));
    }
    final finite = <_State>[];
    for (final state in states.values) {
      _link(state, states, finite);
    }
    while (finite.isNotEmpty) {
      for (final dependent in finite.removeLast().dependents) {
        if (dependent.hasFiniteValue) continue;
        dependent.unresolved--;
        if (dependent.type.isOneOf || dependent.unresolved == 0) {
          _mark(dependent, finite);
        }
      }
    }
    _CycleReport(report, states).run();
  }

  // A non-null field of an input object type must be given a value; a
  // OneOf type is given one field, so any nullable input object field.
  void _link(_State state, Map<String, _State> states, List<_State> finite) {
    final fields = state.type.fields;
    for (final field in fields) {
      if (states[_targetName(state.type, field.type)] case final target?) {
        state.targets.add((field, target));
        target.dependents.add(state);
      }
    }
    state.unresolved = state.targets.length;
    if (state.type.isOneOf
        ? fields.isEmpty || state.targets.length < fields.length
        : state.targets.isEmpty) {
      _mark(state, finite);
    }
  }

  String? _targetName(InputObjectType type, TypeRef fieldType) =>
      switch ((type.isOneOf, fieldType)) {
        (true, NamedType(:final name)) => name.value,
        (false, NonNullType(type: NamedType(:final name))) => name.value,
        _ => null,
      };

  static void _mark(_State state, List<_State> finite) {
    if (state.hasFiniteValue) return;
    state.hasFiniteValue = true;
    finite.add(state);
  }
}

// The propagation state of one input object type.
final class _State(final InputObjectType type) {
  this;

  final List<(InputValue, _State)> targets = [];
  final List<_State> dependents = [];
  int unresolved = 0;
  bool hasFiniteValue = false;
}

// graphql-js's reportCycleRecursive, with a stack of frames: the path of
// fields walked, and the position in it where each walked type entered.
final class _CycleReport(
  final ValidationReport report,
  final Map<String, _State> states,
) {
  this;

  final Set<_State> _visited = {};
  final List<_Frame> _frames = [];
  final List<(String, InputValue)> _path = [];
  final Map<_State, int> _positions = {};

  void run() {
    for (final state in states.values) {
      if (!state.hasFiniteValue && !_visited.contains(state)) _walk(state);
    }
  }

  void _walk(_State root) {
    _enter(root);
    while (_frames.isNotEmpty) {
      final frame = _frames.last;
      if (frame.next == frame.state.targets.length) {
        _frames.removeLast();
        _positions.remove(frame.state);
        if (_frames.isNotEmpty) _path.removeLast();
        continue;
      }
      final (field, target) = frame.state.targets[frame.next++];
      if (target.hasFiniteValue) continue;
      _path.add(('${frame.state.type.name}.${field.name}', field));
      if (_positions[target] case final position?) {
        _report(target, position);
        _path.removeLast();
      } else if (_visited.contains(target)) {
        _path.removeLast();
      } else {
        _enter(target);
      }
    }
  }

  void _enter(_State state) {
    _visited.add(state);
    _positions[state] = _path.length;
    _frames.add(_Frame(state));
  }

  void _report(_State target, int position) {
    final cycle = _path.sublist(position);
    report.error(
      .infiniteInputValue,
      'Input Object ${target.type.name} cannot be provided a finite value '
      'because it references itself through fields: '
      '${[for (final (name, _) in cycle) name].join(', ')}.',
      [for (final (_, field) in cycle) field.span],
    );
  }
}

// A type being walked and the index of its next target.
final class _Frame(final _State state) {
  this;

  int next = 0;
}
```

In `packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import '../../language/ast/type_ref.dart';
 import '../../language/printer/printer.dart';
 import '../model/input_value.dart';
 import '../model/schema_type.dart';
@@ -11,9 +12,10 @@ import 'type_reference_rules.dart';
 import 'unique_names.dart';
 import 'validation_report.dart';
 
-/// The rules of an input object type (spec §3.10): unique and valid
-/// field names, valid applied directives, known input types, no
-/// deprecated required field and valid default values.
+/// The rules of an input object type (spec §3.10): one or more fields,
+/// unique and valid field names, valid applied directives, known input
+/// types, no deprecated required field, valid default values and, for a
+/// `@oneOf` type, nullable fields without defaults.
 final class InputObjectRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -26,25 +28,56 @@ final class InputObjectRules(
 
   /// Reports the problems of [type].
   void check(InputObjectType type) {
+    if (type.fields.isEmpty) {
+      report.error(
+        .missingInputFields,
+        'Input Object type ${type.name} must define one or more fields.',
+        [type.span],
+      );
+    }
     UniqueNames(report).check(
       [for (final field in type.fields) (field.name, field.span)],
       .duplicateFieldName,
       (name) => 'Field "${type.name}.$name" can only be defined once.',
     );
     for (final field in type.fields) {
-      NameRules(report).check(field.name, field.span);
-      AppliedDirectiveRules(
-        report,
-        schema,
-      ).check(field.appliedDirectives, .inputFieldDefinition);
-      _type('${type.name}.${field.name}', field);
-      DeprecationRules(
-        report,
-      ).checkRequired('Required input field ${type.name}.${field.name}', field);
-      DefaultValueRules(
-        report,
-        schema,
-      ).check('${type.name}.${field.name}', field);
+      _field(type, field);
+    }
+  }
+
+  void _field(InputObjectType type, InputValue field) {
+    final coordinate = '${type.name}.${field.name}';
+    NameRules(report).check(field.name, field.span);
+    AppliedDirectiveRules(
+      report,
+      schema,
+    ).check(field.appliedDirectives, .inputFieldDefinition);
+    _type(coordinate, field);
+    DeprecationRules(
+      report,
+    ).checkRequired('Required input field $coordinate', field);
+    DefaultValueRules(report, schema).check(coordinate, field);
+    if (type.isOneOf) {
+      _oneOf(coordinate, field);
+    }
+  }
+
+  // Spec §3.10.1: exactly one field of a OneOf value is given, so none can
+  // be required or defaulted.
+  void _oneOf(String coordinate, InputValue field) {
+    if (field.type is NonNullType) {
+      report.error(
+        .nonNullOneOfField,
+        'OneOf input field $coordinate must be nullable.',
+        [const NodeSpan().within(field.span, field.type)],
+      );
+    }
+    if (field.defaultValue != null) {
+      report.error(
+        .defaultedOneOfField,
+        'OneOf input field $coordinate cannot have a default value.',
+        [field.span],
+      );
     }
   }
 
```

In `packages/typed_graphql/lib/src/schema/validation/type_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,8 +3,10 @@ import '../build/built_ins.dart';
 import '../model/schema_type.dart';
 import '../schema.dart';
 import 'applied_directive_rules.dart';
+import 'default_value_cycle_rules.dart';
 import 'enum_rules.dart';
 import 'field_rules.dart';
+import 'finite_value_rules.dart';
 import 'input_object_rules.dart';
 import 'interface_rules.dart';
 import 'name_rules.dart';
@@ -14,7 +16,8 @@ import 'validation_report.dart';
 
 /// The rules of the named types of a schema (spec §3.4–§3.10), type by
 /// type in declaration order, as graphql-js's `validateTypes`: each type
-/// is checked by the rule family of its kind.
+/// is checked by the rule family of its kind, then the input object types
+/// together for values that cannot be finite.
 final class TypeRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -28,17 +31,19 @@ final class TypeRules(
   /// Reports every problem of the declared types of [schema].
   void check() {
     _definitions();
+    final cycles = DefaultValueCycleRules(report, schema);
     for (final type in schema.types) {
       NameRules(report).check(type.name, type.span);
       AppliedDirectiveRules(
         report,
         schema,
       ).check(type.appliedDirectives, _locationOf(type));
-      _kind(type);
+      _kind(type, cycles);
     }
+    FiniteValueRules(report, schema).check();
   }
 
-  void _kind(SchemaType type) {
+  void _kind(SchemaType type, DefaultValueCycleRules cycles) {
     switch (type) {
       case ObjectType(:final fields, :final interfaces) ||
           InterfaceType(:final fields, :final interfaces):
@@ -50,6 +55,7 @@ final class TypeRules(
         EnumRules(report, schema).check(type);
       case InputObjectType():
         InputObjectRules(report, schema).check(type);
+        cycles.check(type);
       case ScalarType():
         break;
     }
```

In `packages/typed_graphql/lib/src/schema/validation/union_rules.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -3,7 +3,9 @@ import '../schema.dart';
 import 'type_reference_rules.dart';
 import 'validation_report.dart';
 
-/// The rules of a union type (spec §3.8): each member names a known type.
+/// The rules of a union type (spec §3.8), as graphql-js's
+/// `validateUnionMembers`: one or more members, each a known object type
+/// named once.
 final class UnionRules(
   /// Receives the errors.
   final ValidationReport report,
@@ -16,8 +18,40 @@ final class UnionRules(
 
   /// Reports the problems of [type].
   void check(UnionType type) {
+    if (type.memberTypes.isEmpty) {
+      report.error(
+        .missingUnionMembers,
+        'Union type ${type.name} must define one or more member types.',
+        [type.span],
+      );
+    }
+    final included = <String>{};
     for (final member in type.memberTypes) {
-      TypeReferenceRules(report, schema).isKnown(member.name, member.span);
+      if (!TypeReferenceRules(
+        report,
+        schema,
+      ).isKnown(member.name, member.span)) {
+        continue;
+      }
+      final spans = [
+        for (final reference in type.memberTypes)
+          if (reference.name == member.name) reference.span,
+      ];
+      if (!included.add(member.name)) {
+        report.error(
+          .repeatedUnionMember,
+          'Union type ${type.name} can only include type ${member.name} '
+          'once.',
+          spans,
+        );
+      } else if (schema.typeNamed(member.name) is! ObjectType) {
+        report.error(
+          .nonObjectUnionMember,
+          'Union type ${type.name} can only include Object types, it cannot '
+          'include ${member.name}.',
+          spans,
+        );
+      }
     }
   }
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/validation/input_cycle_rules_test.dart test/schema/validation/union_enum_rules_test.dart)
```

Expected: `typed_graphql` `+19: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -277,7 +277,12 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `DirectiveReferenceRules` walks `@name` and type-name keys with a stack
   and a visited set. `InterfaceRules` checks the references of an object or
   interface type and hands each interface to `ImplementationRules`
-  (spec §3.6.3 `IsValidImplementation`).
+  (spec §3.6.3 `IsValidImplementation`). The two input cycles are found
+  without recursion: `FiniteValueRules` propagates the types known to have
+  a finite value through reverse edges (graphql-js's one-pass algorithm),
+  then reports each cycle among the rest once; `DefaultValueCycleRules`
+  walks default values depth-first and, created once per run, remembers
+  the fields it walked across types.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- Schema validation checks unions, enums and input objects, with
  graphql-js's messages: a union without members (`GQL141`), with a
  repeated member (`GQL142`) or a member that is not an object type
  (`GQL143`); an enum without values (`GQL144`); an input object without
  fields (`GQL145`); a `@oneOf` field that is non-null (`GQL146`) or has a
  default (`GQL147`); an input object that cannot be given a finite value
  (`GQL148`) and a default value that contains itself (`GQL149`).
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/validation/default_value_cycle_rules.dart packages/typed_graphql/lib/src/schema/validation/enum_rules.dart packages/typed_graphql/lib/src/schema/validation/finite_value_rules.dart packages/typed_graphql/lib/src/schema/validation/input_object_rules.dart packages/typed_graphql/lib/src/schema/validation/type_rules.dart packages/typed_graphql/lib/src/schema/validation/union_rules.dart packages/typed_graphql/test/schema/validation/input_cycle_rules_test.dart packages/typed_graphql/test/schema/validation/union_enum_rules_test.dart
git commit -q -m "feat(typed_graphql): validate unions, enums, input objects and input cycles" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 11: Port the graphql-js schema validation suite

`type/__tests__/validation-test.ts` (R0.7, R10.3), one test file per `describe` group. Every test has a row in `mapping/schema.csv`; adapted rows give their reason (finding 8).

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_field_types_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_inputs_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_interfaces_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_objects_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_one_of_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_roots_test.dart`, `packages/typed_graphql_conformance/test/schema/validate_schema_unions_test.dart`, `packages/typed_graphql_conformance/test/support/validation_port.dart`

**Interfaces:**
- Consumes: Tasks 4–10 (`SchemaValidator`); M3a `SchemaPort`, `mapping_test.dart`.
- Produces:
```text
test/support/validation_port.dart: final class ValidationPort {
  Schema build(String sdl); Schema extend(Schema schema, String sdl); List<SchemaType> get someTypes;
  List<String> withModifiers(String name); Schema withFieldType(SchemaType type, {List<SchemaType> types});
  List<String> errors(Schema schema) }    // graphql-js-shaped "message @ line:column" strings
mapping_test.dart: `covered` gains type/__tests__/validation-test.ts
```

- [ ] **Step 1: Write the ported tests and the coverage entry**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -70,6 +70,7 @@ void main() {
       path: 'mapping/schema.csv',
       prefix: '',
       covered: const [
+        'type/__tests__/validation-test.ts',
         'utilities/__tests__/buildASTSchema-test.ts',
         'utilities/__tests__/extendSchema-test.ts',
         'utilities/__tests__/printSchema-test.ts',
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_field_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: input and
// output types of fields and arguments, and implemented interfaces. Locations
// are compared as graphql-js reports them; mapping/schema.csv says which tests
// are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();
  List<String> withModifiersOf(List<String> names) => [
    for (final name in names) ...port.withModifiers(name),
  ];
  final outputTypes = withModifiersOf([
    'String',
    'SomeScalar',
    'SomeEnum',
    'SomeObject',
    'SomeUnion',
    'SomeInterface',
  ]);
  final notOutputTypes = withModifiersOf(['SomeInputObject']);
  final inputTypes = withModifiersOf([
    'String',
    'SomeScalar',
    'SomeEnum',
    'SomeInputObject',
  ]);
  final notInputTypes = withModifiersOf([
    'SomeObject',
    'SomeUnion',
    'SomeInterface',
  ]);

  group('Type System: Object fields must have output types', () {
    test('rejects with relevant locations for a non-output type as an Object field type', () {
      final schema = port.build('''
      type Query {
        field: [SomeInputObject]
      }

      input SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'The type of Query.field must be Output Type but got: '
            '[SomeInputObject]. @ 3:16',
      ]);
    });

    Schema schemaWithObjectField(String type) => port.schema([
      ObjectType(
        'Query',
        fields: [SchemaField('f', schemas.type('BadObject'))],
      ),
      ObjectType(
        'BadObject',
        fields: [SchemaField('badField', schemas.type(type))],
      ),
      ...port.someTypes,
    ]);
    for (final type in outputTypes) {
      test('accepts an output type as an Object field type: $type', () {
        expect(port.errors(schemaWithObjectField(type)), isEmpty);
      });
    }
    for (final type in notOutputTypes) {
      test('rejects a non-output type as an Object field type: $type', () {
        expect(port.errors(schemaWithObjectField(type)), [
          'The type of BadObject.badField must be Output Type but got: $type.',
        ]);
      });
    }
  });

  group('Type System: Objects can only implement unique interfaces', () {
    test('rejects an Object implementing a non-Interface type', () {
      final schema = port.build('''
      type Query {
        test: BadObject
      }

      input SomeInputObject {
        field: String
      }

      type BadObject implements SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type BadObject must only implement Interface types, it cannot '
            'implement SomeInputObject. @ 10:33',
      ]);
    });

    test('rejects an Object implementing the same interface twice', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface & AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type AnotherObject can only implement AnotherInterface once. @ '
            '10:37 10:56',
      ]);
    });

    test('rejects an Object implementing the same interface twice due to extension', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = schemas.extend(
        schema,
        'extend type AnotherObject implements AnotherInterface',
      );
      expect(port.errors(extendedSchema), [
        'Type AnotherObject can only implement AnotherInterface once. @ '
            '10:37 1:38',
      ]);
    });
  });

  group('Type System: Interface extensions should be valid', () {
    test('rejects an Object implementing the extended interface due to missing field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = port.extend(schema, '''
        extend interface AnotherInterface {
          newField: String
        }

        extend type AnotherObject {
          differentNewField: String
        }
      ''');
      expect(port.errors(extendedSchema), [
        'Interface field AnotherInterface.newField expected but '
            'AnotherObject does not provide it. @ 3:11 10:7',
      ]);
    });

    test('rejects an Object implementing the extended interface due to missing field args', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = port.extend(schema, '''
        extend interface AnotherInterface {
          newField(test: Boolean): String
        }

        extend type AnotherObject {
          newField: String
        }
      ''');
      expect(port.errors(extendedSchema), [
        'Interface field argument AnotherInterface.newField(test:) '
            'expected but AnotherObject.newField does not provide it. @ 3:20 '
            '7:11',
      ]);
    });

    test('rejects Objects implementing the extended interface due to mismatching interface type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      final extendedSchema = port.extend(schema, '''
        extend interface AnotherInterface {
          newInterfaceField: NewInterface
        }

        interface NewInterface {
          newField: String
        }

        interface MismatchingInterface {
          newField: String
        }

        extend type AnotherObject {
          newInterfaceField: MismatchingInterface
        }

        # Required to prevent unused interface errors
        type DummyObject implements NewInterface & MismatchingInterface {
          newField: String
        }
      ''');
      expect(port.errors(extendedSchema), [
        'Interface field AnotherInterface.newInterfaceField expects type '
            'NewInterface but AnotherObject.newInterfaceField is type '
            'MismatchingInterface. @ 3:30 15:30',
      ]);
    });
  });

  group('Type System: Interface fields must have output types', () {
    test(
      'rejects a non-output type as an Interface field type with locations',
      () {
        final schema = port.build('''
      type Query {
        test: SomeInterface
      }

      interface SomeInterface {
        field: SomeInputObject
      }

      input SomeInputObject {
        foo: String
      }

      type SomeObject implements SomeInterface {
        field: SomeInputObject
      }
    ''');
        expect(port.errors(schema), [
          'The type of SomeInterface.field must be Output Type but got: '
              'SomeInputObject. @ 7:16',
          'The type of SomeObject.field must be Output Type but got: '
              'SomeInputObject. @ 15:16',
        ]);
      },
    );

    test('accepts an interface not implemented by at least one object', () {
      final schema = port.build('''
      type Query {
        test: SomeInterface
      }

      interface SomeInterface {
        foo: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    // BadImplementing comes first, as in graphql-js's type map.
    Schema schemaWithInterfaceField(String type) {
      final fields = [SchemaField('badField', schemas.type(type))];
      return port.schema([
        ObjectType(
          'BadImplementing',
          interfaces: [const NamedTypeReference('BadInterface')],
          fields: fields,
        ),
        InterfaceType('BadInterface', fields: fields),
        ObjectType(
          'Query',
          fields: [SchemaField('f', schemas.type('BadInterface'))],
        ),
        ...port.someTypes,
      ]);
    }

    for (final type in outputTypes) {
      test('accepts an output type as an Interface field type: $type', () {
        expect(port.errors(schemaWithInterfaceField(type)), isEmpty);
      });
    }
    for (final type in notOutputTypes) {
      test('rejects a non-output type as an Interface field type: $type', () {
        expect(port.errors(schemaWithInterfaceField(type)), [
          'The type of BadImplementing.badField must be Output Type but got: '
              '$type.',
          'The type of BadInterface.badField must be Output Type but got: '
              '$type.',
        ]);
      });
    }
  });

  group('Type System: Arguments must have input types', () {
    test('rejects a required argument that is deprecated', () {
      final schema = port.build('''
      directive @BadDirective(
        badArg: String! @deprecated
        optionalArg: String @deprecated
        anotherOptionalArg: String! = "" @deprecated
      ) on FIELD

      type Query {
        test(
          badArg: String! @deprecated
          optionalArg: String @deprecated
          anotherOptionalArg: String! = "" @deprecated
        ): String
      }
    ''');
      expect(port.errors(schema), [
        'Required argument @BadDirective(badArg:) cannot be deprecated. '
            '@ 3:25 3:17',
        'Required argument Query.test(badArg:) cannot be deprecated. @ '
            '10:27 10:19',
      ]);
    });

    test('rejects a non-input type as a field arg with locations', () {
      final schema = port.build('''
      type Query {
        test(arg: SomeObject): String
      }

      type SomeObject {
        foo: String
      }
    ''');
      expect(port.errors(schema), [
        'The type of Query.test(arg:) must be Input Type but got: '
            'SomeObject. @ 3:19',
      ]);
    });

    Schema schemaWithArg(String type) => port.schema(
      [
        ObjectType(
          'Query',
          fields: [SchemaField('f', schemas.type('BadObject'))],
        ),
        ObjectType(
          'BadObject',
          fields: [
            SchemaField(
              'badField',
              schemas.type('String'),
              arguments: [schemas.input('badArg', type)],
            ),
          ],
        ),
        ...port.someTypes,
      ],
      directives: [
        SchemaDirective(
          'BadDirective',
          arguments: [schemas.input('badArg', type)],
          locations: [DirectiveLocation.query],
        ),
      ],
    );
    for (final type in inputTypes) {
      test('accepts an input type as a field arg type: $type', () {
        expect(port.errors(schemaWithArg(type)), isEmpty);
      });
    }
    for (final type in notInputTypes) {
      test('rejects a non-input type as a field arg type: $type', () {
        expect(port.errors(schemaWithArg(type)), [
          'The type of @BadDirective(badArg:) must be Input Type but got: '
              '$type.',
          'The type of BadObject.badField(badArg:) must be Input Type but got: '
              '$type.',
        ]);
      });
    }
  });

  group('Type System: Input Object fields must have input types', () {
    test(
      'rejects a non-input type as an input object field with locations',
      () {
        final schema = port.build('''
      type Query {
        test(arg: SomeInputObject): String
      }

      input SomeInputObject {
        foo: SomeObject
      }

      type SomeObject {
        bar: String
      }
    ''');
        expect(port.errors(schema), [
          'The type of SomeInputObject.foo must be Input Type but got: '
              'SomeObject. @ 7:14',
        ]);
      },
    );

    Schema schemaWithInputField(String type) => port.schema([
      ObjectType(
        'Query',
        fields: [
          SchemaField(
            'f',
            schemas.type('String'),
            arguments: [schemas.input('badArg', 'BadInputObject')],
          ),
        ],
      ),
      InputObjectType(
        'BadInputObject',
        fields: [schemas.input('badField', type)],
      ),
      ...port.someTypes,
    ]);
    for (final type in inputTypes) {
      test('accepts an input type as an input field type: $type', () {
        expect(port.errors(schemaWithInputField(type)), isEmpty);
      });
    }
    for (final type in notInputTypes) {
      test('rejects a non-input type as an input field type: $type', () {
        expect(port.errors(schemaWithInputField(type)), [
          'The type of BadInputObject.badField must be Input Type but got: '
              '$type.',
        ]);
      });
    }
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_inputs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: input objects,
// their cycles and default values. Locations are compared as graphql-js reports
// them; mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: Input Objects must have fields', () {
    test('accepts an Input Object type with fields', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Input Object type with missing fields', () {
      var schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject
    ''');
      schema = port.extend(schema, '''
        directive @test on INPUT_OBJECT

        extend input SomeInputObject @test
      ''');
      expect(port.errors(schema), [
        'Input Object type SomeInputObject must define one or more '
            'fields. @ 6:7',
      ]);
    });

    test('accepts an Input Object with breakable circular reference', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        self: SomeInputObject
        arrayOfSelf: [SomeInputObject]
        nonNullArrayOfSelf: [SomeInputObject]!
        nonNullArrayOfNonNullSelf: [SomeInputObject!]!
        intermediateSelf: AnotherInputObject
      }

      input AnotherInputObject {
        parent: SomeInputObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Input Object with non-breakable circular reference', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        nonNullSelf: SomeInputObject!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object SomeInputObject cannot be provided a finite value '
            'because it references itself through fields: '
            'SomeInputObject.nonNullSelf. @ 7:9',
      ]);
    });

    test('rejects Input Objects with non-breakable circular reference spread across them', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        startLoop: AnotherInputObject!
      }

      input AnotherInputObject {
        nextInLoop: YetAnotherInputObject!
      }

      input YetAnotherInputObject {
        closeLoop: SomeInputObject!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object SomeInputObject cannot be provided a finite value '
            'because it references itself through fields: '
            'SomeInputObject.startLoop, AnotherInputObject.nextInLoop, '
            'YetAnotherInputObject.closeLoop. @ 7:9 11:9 15:9',
      ]);
    });

    test(
      'rejects Input Objects with multiple non-breakable circular reference',
      () {
        final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        startLoop: AnotherInputObject!
      }

      input AnotherInputObject {
        closeLoop: SomeInputObject!
        startSecondLoop: YetAnotherInputObject!
      }

      input YetAnotherInputObject {
        closeSecondLoop: AnotherInputObject!
        nonNullSelf: YetAnotherInputObject!
      }
    ''');
        expect(port.errors(schema), [
          'Input Object SomeInputObject cannot be provided a finite value '
              'because it references itself through fields: '
              'SomeInputObject.startLoop, AnotherInputObject.closeLoop. @ 7:9 '
              '11:9',
          'Input Object AnotherInputObject cannot be provided a finite '
              'value because it references itself through fields: '
              'AnotherInputObject.startSecondLoop, '
              'YetAnotherInputObject.closeSecondLoop. @ 12:9 16:9',
          'Input Object YetAnotherInputObject cannot be provided a finite '
              'value because it references itself through fields: '
              'YetAnotherInputObject.nonNullSelf. @ 17:9',
        ]);
      },
    );

    test(
      'rejects an Input Object with multiple non-breakable circular references',
      () {
        final schema = port.build('''
      type Query {
        field(arg: A): String
      }

      input A {
        b: B!
        c: C!
      }

      input B {
        a: A!
      }

      input C {
        a: A!
      }
    ''');
        expect(port.errors(schema), [
          'Input Object A cannot be provided a finite value because it '
              'references itself through fields: A.b, B.a. @ 7:9 12:9',
          'Input Object A cannot be provided a finite value because it '
              'references itself through fields: A.c, C.a. @ 8:9 16:9',
        ]);
      },
    );

    test('accepts Input Objects with default values without circular references (SDL)', () {
      final validSchema = port.build('''
      type Query {
        field(arg1: A, arg2: B): String
      }

      input A {
        x: A = null
        y: A = { x: null, y: null }
        z: [A] = []
      }

      input B {
        x: B2! = {}
        y: String = "abc"
        z: Custom = {}
      }

      input B2 {
        x: B3 = {}
      }

      input B3 {
        x: B = { x: { x: null } }
      }

      scalar Custom
    ''');
      expect(port.errors(validSchema), isEmpty);
    });

    test(
      'rejects Input Objects with default value circular reference (SDL)',
      () {
        final invalidSchema = port.build('''
      type Query {
        field(arg1: A, arg2: B, arg3: C, arg4: D, arg5: E): String
      }

      input A {
        x: A = {}
      }

      input B {
        x: B2 = {}
      }

      input B2 {
        x: B3 = {}
      }

      input B3 {
        x: B = {}
      }

      input C {
        x: [C] = [{}]
      }

      input D {
        x: D = { x: { x: {} } }
      }

      input E {
        x: E = { x: null }
        y: E = { y: null }
      }

      input F {
        x: F2! = {}
      }

      input F2 {
        x: F = { x: {} }
      }
    ''');
        expect(port.errors(invalidSchema), [
          'Invalid circular reference. The default value of Input Object '
              'field A.x references itself. @ 7:16',
          'Invalid circular reference. The default value of Input Object '
              'field B.x references itself via the default values of: B2.x, '
              'B3.x. @ 11:17 15:17 19:16',
          'Invalid circular reference. The default value of Input Object '
              'field C.x references itself. @ 23:18',
          'Invalid circular reference. The default value of Input Object '
              'field D.x references itself. @ 27:16',
          'Invalid circular reference. The default value of Input Object '
              'field E.x references itself via the default values of: E.y. @ '
              '31:16 32:16',
          'Invalid circular reference. The default value of Input Object '
              'field F2.x references itself. @ 40:16',
        ]);
      },
    );

    test('rejects an Input Object type with incorrectly typed fields', () {
      final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      type SomeObject {
        field: String
      }

      union SomeUnion = SomeObject

      input SomeInputObject {
        badObject: SomeObject
        badUnion: SomeUnion
        goodInputObject: SomeInputObject
      }
    ''');
      expect(port.errors(schema), [
        'The type of SomeInputObject.badObject must be Input Type but '
            'got: SomeObject. @ 13:20',
        'The type of SomeInputObject.badUnion must be Input Type but '
            'got: SomeUnion. @ 14:19',
      ]);
    });

    test(
      'rejects an Input Object type with required field that is deprecated',
      () {
        final schema = port.build('''
      type Query {
        field(arg: SomeInputObject): String
      }

      input SomeInputObject {
        badField: String! @deprecated
        optionalField: String @deprecated
        anotherOptionalField: String! = "" @deprecated
      }
    ''');
        expect(port.errors(schema), [
          'Required input field SomeInputObject.badField cannot be '
              'deprecated. @ 7:27 7:19',
        ]);
      },
    );
  });

  group('Type System: Argument default values must be valid', () {
    test('rejects an argument with invalid default values (SDL)', () {
      final schema = port.build('''
      type Query {
        field(arg: Int = 3.14): Int
      }

      directive @bad(arg: Int = 2.718) on FIELD
    ''');
      expect(port.errors(schema), [
        '@bad(arg:) has invalid default value: Int cannot represent '
            'non-integer value: 2.718 @ 6:33',
        'Query.field(arg:) has invalid default value: Int cannot '
            'represent non-integer value: 3.14 @ 3:26',
      ]);
    });

    test('rejects an argument with invalid default values (programmatic)', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Query',
            fields: [
              SchemaField(
                'field',
                schemas.type('Int'),
                arguments: [schemas.input('arg', 'Int', defaultValue: '3.14')],
              ),
            ],
          ),
        ],
        directives: [
          SchemaDirective(
            'bad',
            arguments: [schemas.input('arg', 'Int', defaultValue: '2.718')],
            locations: [DirectiveLocation.field],
          ),
        ],
        queryTypeName: 'Query',
      );
      expect(port.errors(schema), [
        '@bad(arg:) has invalid default value: Int cannot represent non-integer '
            'value: 2.718',
        'Query.field(arg:) has invalid default value: Int cannot represent '
            'non-integer value: 3.14',
      ]);
    });
  });

  group('Type System: Input Object field default values must be valid', () {
    test('rejects an Input Object field with invalid default values (SDL)', () {
      final schema = port.build('''
    type Query {
      field(arg: SomeInputObject): Int
    }

    input SomeInputObject {
      field: Int = 3.14
    }
  ''');
      expect(port.errors(schema), [
        'SomeInputObject.field has invalid default value: Int cannot '
            'represent non-integer value: 3.14 @ 7:20',
      ]);
    });

    test('rejects an Input Object field with invalid default values (programmatic)', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Query',
            fields: [
              SchemaField(
                'field',
                schemas.type('Int'),
                arguments: [schemas.input('arg', 'SomeInputObject')],
              ),
            ],
          ),
          InputObjectType(
            'SomeInputObject',
            fields: [schemas.input('field', 'Int', defaultValue: '3.14')],
          ),
        ],
        queryTypeName: 'Query',
      );
      expect(port.errors(schema), [
        'SomeInputObject.field has invalid default value: Int cannot represent '
            'non-integer value: 3.14',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_interfaces_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: interfaces
// implementing interfaces, and assertValidSchema. Locations are compared as
// graphql-js reports them; mapping/schema.csv says which tests are adapted or
// skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Interfaces must adhere to Interface they implement', () {
    test('accepts an Interface which implements an Interface', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts an Interface which implements an Interface along with more fields', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String): String
        anotherField: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts an Interface which implements an Interface field along with additional optional arguments', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String, anotherInput: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Interface missing an Interface field', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        anotherField: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expected but '
            'ChildInterface does not provide it. @ 7:9 10:7',
      ]);
    });

    test('rejects an Interface with an incorrectly typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: String): Int
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type String but '
            'ChildInterface.field is type Int. @ 7:31 11:31',
      ]);
    });

    test('rejects an Interface with a differently typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      type A { foo: String }
      type B { foo: String }

      interface ParentInterface {
        field: A
      }

      interface ChildInterface implements ParentInterface {
        field: B
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type A but '
            'ChildInterface.field is type B. @ 10:16 14:16',
      ]);
    });

    test(
      'accepts an Interface with a subtyped Interface field (interface)',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: ParentInterface
      }

      interface ChildInterface implements ParentInterface {
        field: ChildInterface
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts an Interface with a subtyped Interface field (union)', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      type SomeObject {
        field: String
      }

      union SomeUnionType = SomeObject

      interface ParentInterface {
        field: SomeUnionType
      }

      interface ChildInterface implements ParentInterface {
        field: SomeObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Interface implementing a non-Interface type', () {
      final schema = port.build('''
      type Query {
        field: String
      }

      input SomeInputObject {
        field: String
      }

      interface BadInterface implements SomeInputObject {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type BadInterface must only implement Interface types, it '
            'cannot implement SomeInputObject. @ 10:41',
      ]);
    });

    test('rejects an Interface missing an Interface argument', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field argument ParentInterface.field(input:) expected '
            'but ChildInterface.field does not provide it. @ 7:15 11:9',
      ]);
    });

    test(
      'rejects an Interface with an incorrectly typed Interface argument',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: Int): String
      }
    ''');
        expect(port.errors(schema), [
          'Interface field argument ParentInterface.field(input:) expects '
              'type String but ChildInterface.field(input:) is type Int. @ '
              '7:22 11:22',
        ]);
      },
    );

    test(
      'rejects an Interface with both an incorrectly typed field and argument',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(input: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(input: Int): Int
      }
    ''');
        expect(port.errors(schema), [
          'Interface field ParentInterface.field expects type String but '
              'ChildInterface.field is type Int. @ 7:31 11:28',
          'Interface field argument ParentInterface.field(input:) expects '
              'type String but ChildInterface.field(input:) is type Int. @ '
              '7:22 11:22',
        ]);
      },
    );

    test('rejects an Interface which implements an Interface field along with additional required arguments', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field(baseArg: String): String
      }

      interface ChildInterface implements ParentInterface {
        field(
          baseArg: String,
          requiredArg: String!
          optionalArg1: String,
          optionalArg2: String = "",
        ): String
      }
    ''');
      expect(port.errors(schema), [
        'Argument "ChildInterface.field(requiredArg:)" must not be '
            'required type "String!" if not provided by the Interface field '
            '"ParentInterface.field". @ 13:11 7:9',
      ]);
    });

    test(
      'accepts an Interface with an equivalently wrapped Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: [String]!
      }

      interface ChildInterface implements ParentInterface {
        field: [String]!
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('rejects an Interface with a non-list Interface field list type', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: [String]
      }

      interface ChildInterface implements ParentInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type [String] but '
            'ChildInterface.field is type String. @ 7:16 11:16',
      ]);
    });

    test('rejects an Interface with a list Interface field non-list type', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: String
      }

      interface ChildInterface implements ParentInterface {
        field: [String]
      }
    ''');
      expect(port.errors(schema), [
        'Interface field ParentInterface.field expects type String but '
            'ChildInterface.field is type [String]. @ 7:16 11:16',
      ]);
    });

    test(
      'accepts an Interface with a subset non-null Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: String
      }

      interface ChildInterface implements ParentInterface {
        field: String!
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test(
      'rejects an Interface with a superset nullable Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface ParentInterface {
        field: String!
      }

      interface ChildInterface implements ParentInterface {
        field: String
      }
    ''');
        expect(port.errors(schema), [
          'Interface field ParentInterface.field expects type String! but '
              'ChildInterface.field is type String. @ 7:16 11:16',
        ]);
      },
    );

    test('rejects an Object missing a transitive interface', () {
      final schema = port.build('''
      type Query {
        test: ChildInterface
      }

      interface SuperInterface {
        field: String!
      }

      interface ParentInterface implements SuperInterface {
        field: String!
      }

      interface ChildInterface implements ParentInterface {
        field: String!
      }
    ''');
      expect(port.errors(schema), [
        'Type ChildInterface must implement SuperInterface because it is '
            'implemented by ParentInterface. @ 10:44 14:43',
      ]);
    });

    test('rejects a self reference interface', () {
      final schema = port.build('''
      type Query {
        test: FooInterface
      }

      interface FooInterface implements FooInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type FooInterface cannot implement itself because it would '
            'create a circular reference. @ 6:41',
      ]);
    });

    test('rejects a circular Interface implementation', () {
      final schema = port.build('''
      type Query {
        test: FooInterface
      }

      interface FooInterface implements BarInterface {
        field: String
      }

      interface BarInterface implements FooInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Type FooInterface cannot implement BarInterface because it '
            'would create a circular reference. @ 10:41 6:41',
        'Type BarInterface cannot implement FooInterface because it '
            'would create a circular reference. @ 6:41 10:41',
      ]);
    });

    test('rejects deprecated implementation field when interface field is not deprecated', () {
      final schema = port.build('''
      interface Node {
        id: ID!
      }

      type Foo implements Node {
        id: ID! @deprecated
      }

      type Query {
        foo: Foo
      }
    ''');
      expect(port.errors(schema), [
        'Interface field Node.id is not deprecated, so implementation '
            'field Foo.id must not be deprecated. @ 7:17 7:13',
      ]);
    });
  });

  group('assertValidSchema', () {
    test('does not throw on valid schemas', () {
      final schema = port.build('''
      type Query {
        foo: String
      }
    ''');
      expect(const SchemaValidator().validate(schema), isA<ValidSchema>());
    });

    test('combines multiple errors', () {
      final schema = schemas.build('type SomeType');
      expect(port.errors(schema), [
        'Query root type must be provided.',
        'Type SomeType must define one or more fields. @ 1:1',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_objects_test.dart`:

```dart
import 'package:test/test.dart';

import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: objects
// implementing interfaces. Locations are compared as graphql-js reports them;
// mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();

  group('Objects must adhere to Interface they implement', () {
    test('accepts an Object which implements an Interface', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'accepts an Object which implements an Interface along with more fields',
      () {
        final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String): String
        anotherField: String
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts an Object which implements an Interface field along with additional optional arguments', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String, anotherInput: String): String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object missing an Interface field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        anotherField: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expected but '
            'AnotherObject does not provide it. @ 7:9 10:7',
      ]);
    });

    test('rejects an Object with an incorrectly typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: String): Int
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type String but '
            'AnotherObject.field is type Int. @ 7:31 11:31',
      ]);
    });

    test('rejects an Object with a differently typed Interface field', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      type A { foo: String }
      type B { foo: String }

      interface AnotherInterface {
        field: A
      }

      type AnotherObject implements AnotherInterface {
        field: B
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type A but '
            'AnotherObject.field is type B. @ 10:16 14:16',
      ]);
    });

    test('accepts an Object with a subtyped Interface field (interface)', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: AnotherInterface
      }

      type AnotherObject implements AnotherInterface {
        field: AnotherObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts an Object with a subtyped Interface field (union)', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      type SomeObject {
        field: String
      }

      union SomeUnionType = SomeObject

      interface AnotherInterface {
        field: SomeUnionType
      }

      type AnotherObject implements AnotherInterface {
        field: SomeObject
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object missing an Interface argument', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field argument AnotherInterface.field(input:) '
            'expected but AnotherObject.field does not provide it. @ 7:15 '
            '11:9',
      ]);
    });

    test('rejects an Object with an incorrectly typed Interface argument', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: Int): String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field argument AnotherInterface.field(input:) expects '
            'type String but AnotherObject.field(input:) is type Int. @ 7:22 '
            '11:22',
      ]);
    });

    test(
      'rejects an Object with both an incorrectly typed field and argument',
      () {
        final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(input: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(input: Int): Int
      }
    ''');
        expect(port.errors(schema), [
          'Interface field AnotherInterface.field expects type String but '
              'AnotherObject.field is type Int. @ 7:31 11:28',
          'Interface field argument AnotherInterface.field(input:) expects '
              'type String but AnotherObject.field(input:) is type Int. @ 7:22 '
              '11:22',
        ]);
      },
    );

    test('rejects an Object which implements an Interface field along with additional required arguments', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field(baseArg: String): String
      }

      type AnotherObject implements AnotherInterface {
        field(
          baseArg: String,
          requiredArg: String!
          optionalArg1: String,
          optionalArg2: String = "",
        ): String
      }
    ''');
      expect(port.errors(schema), [
        'Argument "AnotherObject.field(requiredArg:)" must not be '
            'required type "String!" if not provided by the Interface field '
            '"AnotherInterface.field". @ 13:11 7:9',
      ]);
    });

    test(
      'accepts an Object with an equivalently wrapped Interface field type',
      () {
        final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: [String]!
      }

      type AnotherObject implements AnotherInterface {
        field: [String]!
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('rejects an Object with a non-list Interface field list type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: [String]
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type [String] '
            'but AnotherObject.field is type String. @ 7:16 11:16',
      ]);
    });

    test('rejects an Object with a list Interface field non-list type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: [String]
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type String but '
            'AnotherObject.field is type [String]. @ 7:16 11:16',
      ]);
    });

    test('accepts an Object with a subset non-null Interface field type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String
      }

      type AnotherObject implements AnotherInterface {
        field: String!
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object with a superset nullable Interface field type', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface AnotherInterface {
        field: String!
      }

      type AnotherObject implements AnotherInterface {
        field: String
      }
    ''');
      expect(port.errors(schema), [
        'Interface field AnotherInterface.field expects type String! but '
            'AnotherObject.field is type String. @ 7:16 11:16',
      ]);
    });

    test('rejects an Object missing a transitive interface', () {
      final schema = port.build('''
      type Query {
        test: AnotherObject
      }

      interface SuperInterface {
        field: String!
      }

      interface AnotherInterface implements SuperInterface {
        field: String!
      }

      type AnotherObject implements AnotherInterface {
        field: String!
      }
    ''');
      expect(port.errors(schema), [
        'Type AnotherObject must implement SuperInterface because it is '
            'implemented by AnotherInterface. @ 10:45 14:37',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_one_of_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: OneOf input
// objects. Locations are compared as graphql-js reports them;
// mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: OneOf Input Object fields must be nullable', () {
    test('accepts a OneOf Input Object with a scalar field', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        a: Int
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a OneOf Input Object with a recursive list field', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        a: [A!]
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'accepts a OneOf Input Object referencing a non-OneOf input object',
      () {
        final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        x: Int
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts a OneOf Input Object referencing an already checked input object', () {
      final schema = port.build('''
      type Query {
        a(arg: A): Int
      }

      input B {
        value: Int
      }

      input A @oneOf {
        b: B
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'accepts a OneOf Input Object with multiple acyclic input object fields',
      () {
        final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        c: C
      }

      input B {
        value: Int
      }

      input C {
        value: Int
      }
    ''');
        expect(port.errors(schema), isEmpty);
      },
    );

    test('accepts a OneOf/OneOf cycle with a scalar escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        escape: Int
      }

      input B @oneOf {
        a: A
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a OneOf/non-OneOf cycle with a nullable escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        a: A
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a OneOf/non-OneOf with scalar escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        escape: Int
      }

      input B {
        a: A!
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a non-OneOf/non-OneOf cycle with a nullable escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A {
        b: B!
      }

      input B {
        a: A
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('accepts a non-OneOf/non-OneOf cycle with a non-null list of non-null items escape', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A {
        b: [B!]!
      }

      input B {
        a: A!
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects non-nullable fields', () {
      final schema = port.build('''
      type Query {
        test(arg: SomeInputObject): String
      }

      input SomeInputObject @oneOf {
        a: String
        b: String!
      }
    ''');
      expect(port.errors(schema), [
        'OneOf input field SomeInputObject.b must be nullable. @ 8:12',
      ]);
    });

    test('rejects fields with default values', () {
      final schema = port.build('''
      type Query {
        test(arg: SomeInputObject): String
      }

      input SomeInputObject @oneOf {
        a: String
        b: String = "foo"
      }
    ''');
      expect(port.errors(schema), [
        'OneOf input field SomeInputObject.b cannot have a default '
            'value. @ 8:9',
      ]);
    });

    test('rejects a self-referencing OneOf type with no escapes', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        self: A
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.self. @ 7:9',
      ]);
    });

    test(
      'rejects a non-OneOf Input Object requiring an unbreakable OneOf cycle',
      () {
        final schema = port.build('''
      type Query {
        a(arg: A): Int
      }

      input T @oneOf {
        self: T
      }

      input A {
        t: T!
      }
    ''');
        expect(port.errors(schema), [
          'Input Object T cannot be provided a finite value because it '
              'references itself through fields: T.self. @ 7:9',
        ]);
      },
    );

    test('checks each shared unbreakable OneOf subgraph once', () {
      const chainLength = 16;
      final oneOf = schemas.applied('@oneOf');
      final types = [
        InputObjectType(
          'T0',
          appliedDirectives: oneOf,
          fields: [schemas.input('self', 'T0')],
        ),
        for (var i = 1; i <= chainLength; i++)
          InputObjectType(
            'T$i',
            appliedDirectives: oneOf,
            fields: [
              schemas.input('a', 'T${i - 1}'),
              schemas.input('b', 'T${i - 1}'),
            ],
          ),
      ];
      final schema = Schema(
        types: [
          ObjectType(
            'Query',
            fields: [
              SchemaField(
                'test',
                schemas.type('Int'),
                arguments: [schemas.input('input', 'T$chainLength')],
              ),
            ],
          ),
          ...types,
        ],
        queryTypeName: 'Query',
      );
      expect(port.errors(schema), hasLength(1));
    });

    test('rejects a mixed OneOf/non-OneOf cycle with no escapes', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        a: A!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.a. @ 7:9 11:9',
      ]);
    });

    test('rejects multiple OneOf branches without duplicate cycle reports', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
        c: C
      }

      input B {
        a: A!
      }

      input C {
        a: A!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.a. @ 7:9 12:9',
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.c, C.a. @ 8:9 16:9',
      ]);
    });

    test('rejects a non-OneOf/non-OneOf cycle with required scalar, list, and finite input fields', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A {
        list: [B]!
        finite: Finite!
        b: B!
      }

      input B {
        value: Int!
        a: A!
      }

      input Finite {
        value: Int!
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.a. @ 9:9 14:9',
      ]);
    });

    test('rejects a larger mixed OneOf/non-OneOf cycle with no escapes', () {
      final schema = port.build('''
      type Query {
        test(arg: A): Int
      }

      input A @oneOf {
        b: B
      }

      input B {
        c: C!
      }

      input C @oneOf {
        a: A
      }
    ''');
      expect(port.errors(schema), [
        'Input Object A cannot be provided a finite value because it '
            'references itself through fields: A.b, B.c, C.a. @ 7:9 11:9 15:9',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_roots_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: root types,
// fields and arguments. Locations are compared as graphql-js reports them;
// mapping/schema.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: A Schema must have Object root types', () {
    test('accepts a Schema whose query type is an object type', () {
      final schema = port.build('''
      type Query {
        test: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
      final schemaWithDef = port.build('''
      schema {
        query: QueryRoot
      }

      type QueryRoot {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), isEmpty);
    });

    test(
      'accepts a Schema whose query and mutation types are object types',
      () {
        final schema = port.build('''
      type Query {
        test: String
      }

      type Mutation {
        test: String
      }
    ''');
        expect(port.errors(schema), isEmpty);
        final schemaWithDef = port.build('''
      schema {
        query: QueryRoot
        mutation: MutationRoot
      }

      type QueryRoot {
        test: String
      }

      type MutationRoot {
        test: String
      }
    ''');
        expect(port.errors(schemaWithDef), isEmpty);
      },
    );

    test(
      'accepts a Schema whose query and subscription types are object types',
      () {
        final schema = port.build('''
      type Query {
        test: String
      }

      type Subscription {
        test: String
      }
    ''');
        expect(port.errors(schema), isEmpty);
        final schemaWithDef = port.build('''
      schema {
        query: QueryRoot
        subscription: SubscriptionRoot
      }

      type QueryRoot {
        test: String
      }

      type SubscriptionRoot {
        test: String
      }
    ''');
        expect(port.errors(schemaWithDef), isEmpty);
      },
    );

    test('rejects a Schema without a query type', () {
      final schema = port.build('''
      type Mutation {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Query root type must be provided.',
      ]);
      final schemaWithDef = port.build('''
      schema {
        mutation: MutationRoot
      }

      type MutationRoot {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Query root type must be provided. @ 2:7',
      ]);
    });

    test('rejects a Schema whose query root type is not an Object type', () {
      final schema = port.build('''
      input Query {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Query root type must be Object type, it cannot be Query. @ 2:7',
      ]);
      final schemaWithDef = port.build('''
      schema {
        query: SomeInputObject
      }

      input SomeInputObject {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Query root type must be Object type, it cannot be '
            'SomeInputObject. @ 3:16',
      ]);
    });

    test('rejects a Schema whose mutation type is an input type', () {
      final schema = port.build('''
      type Query {
        field: String
      }

      input Mutation {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Mutation root type must be Object type if provided, it cannot '
            'be Mutation. @ 6:7',
      ]);
      final schemaWithDef = port.build('''
      schema {
        query: Query
        mutation: SomeInputObject
      }

      type Query {
        field: String
      }

      input SomeInputObject {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Mutation root type must be Object type if provided, it cannot '
            'be SomeInputObject. @ 4:19',
      ]);
    });

    test('rejects a Schema whose subscription type is an input type', () {
      final schema = port.build('''
      type Query {
        field: String
      }

      input Subscription {
        test: String
      }
    ''');
      expect(port.errors(schema), [
        'Subscription root type must be Object type if provided, it '
            'cannot be Subscription. @ 6:7',
      ]);
      final schemaWithDef = port.build('''
      schema {
        query: Query
        subscription: SomeInputObject
      }

      type Query {
        field: String
      }

      input SomeInputObject {
        test: String
      }
    ''');
      expect(port.errors(schemaWithDef), [
        'Subscription root type must be Object type if provided, it '
            'cannot be SomeInputObject. @ 4:23',
      ]);
    });

    test('rejects a Schema extended with invalid root types', () {
      var schema = port.build('''
      input SomeInputObject {
        test: String
      }

      scalar SomeScalar

      enum SomeEnum {
        ENUM_VALUE
      }
    ''');
      schema = port.extend(schema, '''
        extend schema {
          query: SomeInputObject
        }
      ''');
      schema = port.extend(schema, '''
        extend schema {
          mutation: SomeScalar
        }
      ''');
      schema = port.extend(schema, '''
        extend schema {
          subscription: SomeEnum
        }
      ''');
      expect(port.errors(schema), [
        'Query root type must be Object type, it cannot be '
            'SomeInputObject. @ 3:18',
        'Mutation root type must be Object type if provided, it cannot '
            'be SomeScalar. @ 3:21',
        'Subscription root type must be Object type if provided, it '
            'cannot be SomeEnum. @ 3:25',
      ]);
    });

    test('rejects a Schema whose directives have empty locations', () {
      final schema = Schema(
        types: port.someTypes,
        directives: [SchemaDirective('BadDirective')],
        queryTypeName: 'SomeObject',
      );
      expect(port.errors(schema), [
        'Directive @BadDirective must include 1 or more locations.',
      ]);
    });
  });

  group('Type System: Root types must all be different if provided', () {
    test('accepts a Schema with different root types', () {
      final schema = port.build('''
      type SomeObject1 {
        field: String
      }

      type SomeObject2 {
        field: String
      }

      type SomeObject3 {
        field: String
      }

      schema {
        query: SomeObject1
        mutation: SomeObject2
        subscription: SomeObject3
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test(
      'rejects a Schema where the same type is used for multiple root types',
      () {
        final schema = port.build('''
      type SomeObject {
        field: String
      }

      type UniqueObject {
        field: String
      }

      schema {
        query: SomeObject
        mutation: UniqueObject
        subscription: SomeObject
      }
    ''');
        expect(port.errors(schema), [
          'All root types must be different, "SomeObject" type is used as '
              'query and subscription root types. @ 11:16 13:23',
        ]);
      },
    );

    test('rejects a Schema where the same type is used for all root types', () {
      final schema = port.build('''
      type SomeObject {
        field: String
      }

      schema {
        query: SomeObject
        mutation: SomeObject
        subscription: SomeObject
      }
    ''');
      expect(port.errors(schema), [
        'All root types must be different, "SomeObject" type is used as '
            'query, mutation, and subscription root types. @ 7:16 8:19 9:23',
      ]);
    });
  });

  group('Type System: Objects must have fields', () {
    test('accepts an Object type with fields object', () {
      final schema = port.build('''
      type Query {
        field: SomeObject
      }

      type SomeObject {
        field: String
      }
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects an Object type with missing fields', () {
      final schema = port.build('''
      type Query {
        test: IncompleteObject
      }

      type IncompleteObject
    ''');
      expect(port.errors(schema), [
        'Type IncompleteObject must define one or more fields. @ 6:7',
      ]);
      final manualSchema = port.withFieldType(ObjectType('IncompleteObject'));
      expect(port.errors(manualSchema), [
        'Type IncompleteObject must define one or more fields.',
      ]);
    });

    test('rejects an Object type with incorrectly named fields', () {
      final schema = port.withFieldType(
        ObjectType(
          'SomeObject',
          fields: [SchemaField('__badName', schemas.type('String'))],
        ),
      );
      expect(port.errors(schema), [
        'Name "__badName" must not begin with "__", which is '
            'reserved by GraphQL introspection.',
      ]);
    });
  });

  group('Type System: Fields args must be properly named', () {
    test('accepts field args with valid names', () {
      final schema = port.withFieldType(
        ObjectType(
          'SomeObject',
          fields: [
            SchemaField(
              'goodField',
              schemas.type('String'),
              arguments: [schemas.input('goodArg', 'String')],
            ),
          ],
        ),
      );
      expect(port.errors(schema), isEmpty);
    });

    test('rejects field arg with invalid names', () {
      final schema = port.withFieldType(
        ObjectType(
          'SomeObject',
          fields: [
            SchemaField(
              'badField',
              schemas.type('String'),
              arguments: [schemas.input('__badName', 'String')],
            ),
          ],
        ),
      );
      expect(port.errors(schema), [
        'Name "__badName" must not begin with "__", which is '
            'reserved by GraphQL introspection.',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/validate_schema_unions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';
import '../support/validation_port.dart';

// Ported from graphql-js src/type/__tests__/validation-test.ts: unions and
// enums. Locations are compared as graphql-js reports them; mapping/schema.csv
// says which tests are adapted or skipped, and why.
void main() {
  const port = ValidationPort();
  const schemas = SchemaPort();

  group('Type System: Union types must be valid', () {
    test('accepts a Union type with member types', () {
      final schema = port.build('''
      type Query {
        test: GoodUnion
      }

      type TypeA {
        field: String
      }

      type TypeB {
        field: String
      }

      union GoodUnion =
        | TypeA
        | TypeB
    ''');
      expect(port.errors(schema), isEmpty);
    });

    test('rejects a Union type with empty types', () {
      var schema = port.build('''
      type Query {
        test: BadUnion
      }

      union BadUnion
    ''');
      schema = port.extend(schema, '''
        directive @test on UNION

        extend union BadUnion @test
      ''');
      expect(port.errors(schema), [
        'Union type BadUnion must define one or more member types. @ 6:7',
      ]);
    });

    test('rejects a Union type with duplicated member type', () {
      var schema = port.build('''
      type Query {
        test: BadUnion
      }

      type TypeA {
        field: String
      }

      type TypeB {
        field: String
      }

      union BadUnion =
        | TypeA
        | TypeB
        | TypeA
    ''');
      expect(port.errors(schema), [
        'Union type BadUnion can only include type TypeA once. @ 15:11 '
            '17:11',
      ]);
      schema = schemas.extend(schema, 'extend union BadUnion = TypeB');
      expect(port.errors(schema), [
        'Union type BadUnion can only include type TypeA once. @ 15:11 '
            '17:11',
        'Union type BadUnion can only include type TypeB once. @ 16:11 '
            '1:25',
      ]);
    });

    test('rejects a Union type with non-Object members types', () {
      var schema = port.build('''
      type Query {
        test: BadUnion
      }

      type TypeA {
        field: String
      }

      type TypeB {
        field: String
      }

      union BadUnion =
        | TypeA
        | String
        | TypeB
    ''');
      schema = schemas.extend(schema, 'extend union BadUnion = Int');
      expect(port.errors(schema), [
        'Union type BadUnion can only include Object types, it cannot '
            'include String. @ 16:11',
        'Union type BadUnion can only include Object types, it cannot '
            'include Int. @ 1:25',
      ]);
      final badMembers = [
        'String',
        'SomeInterface',
        'SomeUnion',
        'SomeEnum',
        'SomeInputObject',
      ];
      for (final member in badMembers) {
        final badSchema = port.withFieldType(
          UnionType('BadUnion', memberTypes: [NamedTypeReference(member)]),
          types: port.someTypes,
        );
        expect(port.errors(badSchema), [
          'Union type BadUnion can only include Object types, it cannot include '
              '$member.',
        ]);
      }
    });
  });

  group('Type System: Enum types must be well defined', () {
    test('rejects an Enum type without values', () {
      var schema = port.build('''
      type Query {
        field: SomeEnum
      }

      enum SomeEnum
    ''');
      schema = port.extend(schema, '''
        directive @test on ENUM

        extend enum SomeEnum @test
      ''');
      expect(port.errors(schema), [
        'Enum type SomeEnum must define one or more values. @ 6:7',
      ]);
    });

    test('rejects an Enum type with incorrectly named values', () {
      final schema = port.withFieldType(
        EnumType('SomeEnum', values: [SchemaEnumValue('__badName')]),
      );
      expect(port.errors(schema), [
        'Name "__badName" must not begin with "__", which is '
            'reserved by GraphQL introspection.',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/support/validation_port.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'schema_port.dart';

/// graphql-js's `buildSchema`, `extendSchema` and `validateSchema` as the
/// ported validation tests use them, with each error as graphql-js's
/// message and locations.
final class ValidationPort {
  /// Creates the helpers; they keep no state.
  const ValidationPort();

  static const SchemaPort _schemas = SchemaPort();

  /// graphql-js's `buildSchema` of a template literal written as a Dart
  /// multi-line literal, which drops the line break right after its
  /// opening quotes: the break is restored, so lines count as in
  /// graphql-js.
  Schema build(String sdl) => _schemas.build('\n$sdl');

  /// graphql-js's `extendSchema` of [schema] with [sdl], restored as
  /// [build] restores it.
  Schema extend(Schema schema, String sdl) => _schemas.extend(schema, '\n$sdl');

  /// The text of graphql-js's `SomeSchema`, whose types the tests that
  /// build a schema in code reference.
  static const String someSdl = '''
scalar SomeScalar
interface SomeInterface { f: SomeObject }
type SomeObject implements SomeInterface { f: SomeObject }
union SomeUnion = SomeObject
enum SomeEnum { ONLY }
input SomeInputObject { val: String = "hello" }
directive @SomeDirective on QUERY''';

  /// The types of graphql-js's `SomeSchema`.
  List<SchemaType> get someTypes => _schemas.build(someSdl).types;

  /// graphql-js's `withModifiers`: the type named [name], as a list, as
  /// non-null and as a non-null list, written as GraphQL text.
  List<String> withModifiers(String name) => [
    name,
    '[$name]',
    '$name!',
    '[$name]!',
  ];

  /// A schema built in code of [types] and [directives], whose query root
  /// is `Query`.
  Schema schema(
    List<SchemaType> types, {
    List<SchemaDirective> directives = const [],
  }) => Schema(types: types, directives: directives, queryTypeName: 'Query');

  /// graphql-js's `schemaWithFieldType`: a `Query` root whose field `f`
  /// has [type], beside [type] and [types].
  Schema withFieldType(SchemaType type, {List<SchemaType> types = const []}) =>
      schema([
        ObjectType(
          'Query',
          fields: [SchemaField('f', NamedType(Name(type.name)))],
        ),
        type,
        ...types,
      ]);

  /// graphql-js's `validateSchema(schema)` as `expectJSON` compares it:
  /// each error as its message, then ` @ ` and its locations
  /// (`line:column`, the place first, then the related spans) when it has
  /// any.
  List<String> errors(Schema schema) => [
    for (final diagnostic
        in const SchemaValidator().validate(schema).diagnostics)
      _printed(diagnostic),
  ];

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
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/validate_schema_field_types_test.dart test/schema/validate_schema_inputs_test.dart test/schema/validate_schema_interfaces_test.dart test/schema/validate_schema_objects_test.dart test/schema/validate_schema_one_of_test.dart test/schema/validate_schema_roots_test.dart test/schema/validate_schema_unions_test.dart)
```

Expected: FAIL. `typed_graphql_conformance` ends with `+253 -1: Some tests failed.`; the first messages: `Which: does not contain (String, String):<(Type System: A Schema must have Object root types, accepts a Schema whose query type is an object type)>`.

This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 3: Record the mapping rows**

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -143,3 +143,131 @@ utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root
 utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,builds directives with deprecation from extensions,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped"
 utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,applies multiple directive extensions defined in the same document,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directives"
 utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,extend directive without adding new directives is an error,ported,test/schema/extend_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,accepts a Schema whose query type is an object type,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,accepts a Schema whose query and mutation types are object types,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,accepts a Schema whose query and subscription types are object types,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema without a query type,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema whose query root type is not an Object type,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema whose mutation type is an input type,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema whose subscription type is an input type,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema extended with invalid root types,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema whose types are incorrectly typed,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema whose directives are incorrectly typed,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: A Schema must have Object root types,rejects a Schema whose directives have empty locations,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Root types must all be different if provided,accepts a Schema with different root types,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Root types must all be different if provided,rejects a Schema where the same type is used for multiple root types,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Root types must all be different if provided,rejects a Schema where the same type is used for all root types,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Objects must have fields,accepts an Object type with fields object,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Objects must have fields,rejects an Object type with missing fields,adapted,test/schema/validate_schema_roots_test.dart,the thunk form of fields is JavaScript's; one code-built type stands for both
+type/__tests__/validation-test.ts,Type System: Objects must have fields,rejects an Object type with incorrectly named fields,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Fields args must be properly named,accepts field args with valid names,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Fields args must be properly named,rejects field arg with invalid names,ported,test/schema/validate_schema_roots_test.dart,
+type/__tests__/validation-test.ts,Type System: Union types must be valid,accepts a Union type with member types,ported,test/schema/validate_schema_unions_test.dart,
+type/__tests__/validation-test.ts,Type System: Union types must be valid,rejects a Union type with empty types,adapted,test/schema/validate_schema_unions_test.dart,"the model keeps no extension nodes, so the locations of the extensions are not related"
+type/__tests__/validation-test.ts,Type System: Union types must be valid,rejects a Union type with duplicated member type,ported,test/schema/validate_schema_unions_test.dart,
+type/__tests__/validation-test.ts,Type System: Union types must be valid,rejects a Union type with non-Object members types,adapted,test/schema/validate_schema_unions_test.dart,"a union member is a name in the model, so the list and non-null members cannot be written"
+type/__tests__/validation-test.ts,Type System: Union types must be valid,rejects a Union type with non-Object members types with malformed AST,skipped,,the model holds no syntax nodes to malform
+type/__tests__/validation-test.ts,Type System: Enum types must be well defined,rejects an Enum type without values,adapted,test/schema/validate_schema_unions_test.dart,"the model keeps no extension nodes, so the locations of the extensions are not related"
+type/__tests__/validation-test.ts,Type System: Enum types must be well defined,rejects an Enum type with incorrectly named values,ported,test/schema/validate_schema_unions_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,accepts an Input Object type with fields,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects an Input Object type with missing fields,adapted,test/schema/validate_schema_inputs_test.dart,"the model keeps no extension nodes, so the locations of the extensions are not related"
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,accepts an Input Object with breakable circular reference,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects an Input Object with non-breakable circular reference,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects Input Objects with non-breakable circular reference spread across them,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects Input Objects with multiple non-breakable circular reference,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects an Input Object with multiple non-breakable circular references,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,accepts Input Objects with default values without circular references (SDL),ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,accepts Input Objects with default values without circular references (programmatic),skipped,,"a default is a constant literal in the model; graphql-js's internal-value defaults have no counterpart, and the (SDL) twin covers the rule"
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects Input Objects with default value circular reference (SDL),ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects Input Objects with default value circular reference (programmatic),skipped,,"a default is a constant literal in the model; graphql-js's internal-value defaults have no counterpart, and the (SDL) twin covers the rule"
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects an Input Object type with incorrectly typed fields,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Objects must have fields,rejects an Input Object type with required field that is deprecated,ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Argument default values must be valid,rejects an argument with invalid default values (SDL),ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Argument default values must be valid,rejects an argument with invalid default values (programmatic),adapted,test/schema/validate_schema_inputs_test.dart,"the defaults are written as literals, the model's form"
+type/__tests__/validation-test.ts,Type System: Argument default values must be valid,Attempts to offer a suggested fix if possible (programmatic),skipped,,"a default is a constant literal in the model, so there is no internal value to suggest a fix for (spec findings: no ""Did you mean"" suggestions)"
+type/__tests__/validation-test.ts,Type System: Argument default values must be valid,Attempts to offer a suggested fix if possible (SDL),skipped,,"a default is a constant literal in the model, so there is no internal value to suggest a fix for (spec findings: no ""Did you mean"" suggestions)"
+type/__tests__/validation-test.ts,Type System: Input Object field default values must be valid,rejects an Input Object field with invalid default values (SDL),ported,test/schema/validate_schema_inputs_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Object field default values must be valid,rejects an Input Object field with invalid default values (programmatic),adapted,test/schema/validate_schema_inputs_test.dart,"the default is written as a literal, the model's form"
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf Input Object with a scalar field,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf Input Object with a recursive list field,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf Input Object referencing a non-OneOf input object,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf Input Object referencing an already checked input object,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf Input Object with multiple acyclic input object fields,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf/OneOf cycle with a scalar escape,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf/non-OneOf cycle with a nullable escape,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a OneOf/non-OneOf with scalar escape,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a non-OneOf/non-OneOf cycle with a nullable escape,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,accepts a non-OneOf/non-OneOf cycle with a non-null list of non-null items escape,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects non-nullable fields,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects fields with default values,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects a self-referencing OneOf type with no escapes,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects a non-OneOf Input Object requiring an unbreakable OneOf cycle,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,checks each shared unbreakable OneOf subgraph once,adapted,test/schema/validate_schema_one_of_test.dart,the model has no getFields to spy on; the single error shows each subgraph is reported once
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects a mixed OneOf/non-OneOf cycle with no escapes,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects multiple OneOf branches without duplicate cycle reports,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,"rejects a non-OneOf/non-OneOf cycle with required scalar, list, and finite input fields",ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: OneOf Input Object fields must be nullable,rejects a larger mixed OneOf/non-OneOf cycle with no escapes,ported,test/schema/validate_schema_one_of_test.dart,
+type/__tests__/validation-test.ts,Type System: Object fields must have output types,rejects an empty Object field type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Object fields must have output types,rejects a non-type value as an Object field type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Object fields must have output types,rejects with relevant locations for a non-output type as an Object field type,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Objects can only implement unique interfaces,rejects an Object implementing a non-type value,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Objects can only implement unique interfaces,rejects an Object implementing a non-Interface type,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Objects can only implement unique interfaces,rejects an Object implementing a non-Interface type with malformed AST,skipped,,the model holds no syntax nodes to malform
+type/__tests__/validation-test.ts,Type System: Objects can only implement unique interfaces,rejects an Object implementing the same interface twice,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Objects can only implement unique interfaces,rejects an Object implementing the same interface twice due to extension,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Interface extensions should be valid,rejects an Object implementing the extended interface due to missing field,adapted,test/schema/validate_schema_field_types_test.dart,"the model keeps no extension nodes, so the locations of the extensions are not related"
+type/__tests__/validation-test.ts,Type System: Interface extensions should be valid,rejects an Object implementing the extended interface due to missing field args,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Interface extensions should be valid,rejects Objects implementing the extended interface due to mismatching interface type,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Interface fields must have output types,rejects an empty Interface field type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Interface fields must have output types,rejects a non-type value as an Interface field type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Interface fields must have output types,rejects a non-output type as an Interface field type with locations,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Interface fields must have output types,accepts an interface not implemented by at least one object,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Arguments must have input types,rejects an empty field arg type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Arguments must have input types,rejects a non-type value as a field arg type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Arguments must have input types,rejects a required argument that is deprecated,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Arguments must have input types,rejects a non-input type as a field arg with locations,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Type System: Input Object fields must have input types,rejects an empty input field type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Input Object fields must have input types,rejects a non-type value as an input field type,skipped,,Dart types forbid an undefined or non-type value where a type is expected
+type/__tests__/validation-test.ts,Type System: Input Object fields must have input types,rejects a non-input type as an input object field with locations,ported,test/schema/validate_schema_field_types_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object which implements an Interface,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object which implements an Interface along with more fields,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object which implements an Interface field along with additional optional arguments,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object missing an Interface field,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with an incorrectly typed Interface field,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with a differently typed Interface field,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object with a subtyped Interface field (interface),ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object with a subtyped Interface field (union),ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object missing an Interface argument,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with an incorrectly typed Interface argument,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with both an incorrectly typed field and argument,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object which implements an Interface field along with additional required arguments,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object with an equivalently wrapped Interface field type,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with a non-list Interface field list type,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with a list Interface field non-list type,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,accepts an Object with a subset non-null Interface field type,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object with a superset nullable Interface field type,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Objects must adhere to Interface they implement,rejects an Object missing a transitive interface,ported,test/schema/validate_schema_objects_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface which implements an Interface,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface which implements an Interface along with more fields,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface which implements an Interface field along with additional optional arguments,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface missing an Interface field,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with an incorrectly typed Interface field,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with a differently typed Interface field,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface with a subtyped Interface field (interface),ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface with a subtyped Interface field (union),ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface implementing a non-Interface type,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface missing an Interface argument,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with an incorrectly typed Interface argument,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with both an incorrectly typed field and argument,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface which implements an Interface field along with additional required arguments,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface with an equivalently wrapped Interface field type,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with a non-list Interface field list type,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with a list Interface field non-list type,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,accepts an Interface with a subset non-null Interface field type,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Interface with a superset nullable Interface field type,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects an Object missing a transitive interface,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects a self reference interface,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects a circular Interface implementation,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects deprecated implementation field when interface field is not deprecated,ported,test/schema/validate_schema_interfaces_test.dart,
+type/__tests__/validation-test.ts,assertValidSchema,does not throw on valid schemas,adapted,test/schema/validate_schema_interfaces_test.dart,SchemaValidator returns a sealed result instead of throwing
+type/__tests__/validation-test.ts,assertValidSchema,combines multiple errors,adapted,test/schema/validate_schema_interfaces_test.dart,SchemaValidator returns a sealed result instead of throwing; the result holds both errors
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/validate_schema_field_types_test.dart test/schema/validate_schema_inputs_test.dart test/schema/validate_schema_interfaces_test.dart test/schema/validate_schema_objects_test.dart test/schema/validate_schema_one_of_test.dart test/schema/validate_schema_roots_test.dart test/schema/validate_schema_unions_test.dart)
```

Expected: `typed_graphql_conformance` `+254: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+621: All tests passed!`.

- [ ] **Step 5: Update the documents**

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Ported graphql-js `validation-test.ts` (schema validation), with
  `ValidationPort`: each error as its message and `line:column` locations,
  compared with graphql-js's; template-named tests become loops.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_field_types_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_inputs_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_interfaces_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_objects_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_one_of_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_roots_test.dart packages/typed_graphql_conformance/test/schema/validate_schema_unions_test.dart packages/typed_graphql_conformance/test/support/validation_port.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js schema validation suite" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 12: Check schema validation in the build and extend ports

Ruling 1. The M3a rows of `buildASTSchema` and `extendSchema` whose reason was "schema validation arrives in M3b" now assert `validateSchema` as graphql-js does; their reasons are cleared or rewritten (finding 9).

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart`, `packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_test.dart`, `packages/typed_graphql_conformance/test/support/schema_port.dart`

**Interfaces:**
- Consumes: Task 11 (`ValidationPort`), M3a `SchemaPort` and the build and extend ports.
- Produces:
```text
SchemaPort.validate(Schema schema) -> SchemaValidationResult            // graphql-js's validateSchema
SchemaPort.validationErrors(Schema schema) -> List<String>              // 'GQL116 Unknown type "X".'
```

- [ ] **Step 1: Convert the tests**

The behaviour exists since Task 10, so these tests pass as soon as they are written: their proof is that the converted assertions run (no red phase).

In `packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,7 +6,7 @@ import '../support/schema_port.dart';
 
 // Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
 // deprecation, spans, root types and the built-in names. Where graphql-js
-// calls validateSchema, the check returns with schema validation in M3b.
+// calls validateSchema, the port checks SchemaValidator.
 void main() {
   const dedent = Dedent();
   const port = SchemaPort();
@@ -207,11 +207,11 @@ void main() {
     });
 
     test('can build invalid schema', () {
-      // Invalid, because it has no query root type; validateSchema
-      // reports it from M3b.
+      // Invalid, because it has no query root type.
       final schema = port.build('type Mutation');
       expect(schema.queryTypeName, isNull);
       expect(schema.mutationTypeName, 'Mutation');
+      expect(port.validate(schema), isA<InvalidSchema>());
     });
 
     test('Do not override standard types', () {
@@ -259,10 +259,22 @@ void main() {
       );
     });
 
+    test('Rejects invalid SDL', () {
+      // Adapted: the builder builds; the validator reports the directive.
+      final schema = port.build('''
+        type Query {
+          foo: String @unknown
+        }
+      ''');
+      expect(port.validationErrors(schema), [
+        'GQL117 Unknown directive "@unknown".',
+      ]);
+    });
+
     test('Allows to disable SDL validation', () {
       // Adapted: the builder never validates, so an unknown directive
-      // builds without an option; schema validation (M3b) is what
-      // `assumeValid` turns off.
+      // builds without an option; `ValidSchema.assumeValid` is
+      // graphql-js's `assumeValid`.
       final schema = port.build('''
         type Query {
           foo: String @unknown
@@ -270,6 +282,7 @@ void main() {
       ''');
       final field = (schema.typeNamed('Query')! as ObjectType).fields.single;
       expect(field.appliedDirectives.single.name, 'unknown');
+      expect(ValidSchema.assumeValid(schema).schema, same(schema));
     });
 
     test('buildSchema parses directives on directive definitions', () {
@@ -290,7 +303,7 @@ void main() {
 
     test('Throws on unknown types', () {
       // References are names: the build succeeds and schema validation
-      // reports the unknown type from M3b.
+      // reports the unknown type.
       final schema = port.build('''
         type Query {
           unknown: UnknownType
@@ -306,6 +319,9 @@ void main() {
         '''),
       );
       expect(schema.typeNamed('UnknownType'), isNull);
+      expect(port.validationErrors(schema), [
+        'GQL116 Unknown type "UnknownType".',
+      ]);
     });
 
     test('correctly processes viral schema', () {
```

In `packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -159,11 +159,11 @@ void main() {
           hello: Hello
         }
       ''');
-      // graphql-js then checks that validateSchema reports the union;
-      // schema validation arrives in M3b.
+      // graphql-js then checks that validateSchema reports the union.
       final hello = schema.typeNamed('Hello');
       expect(hello, isA<UnionType>());
       expect(port.print(Schema(types: [?hello])), 'union Hello = Hello');
+      expect(port.validate(schema), isA<InvalidSchema>());
     });
 
     test('Custom Scalar', () {
```

In `packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,12 +1,12 @@
 import 'package:test/test.dart';
+import 'package:typed_graphql/typed_graphql.dart';
 
 import '../support/dedent.dart';
 import '../support/schema_port.dart';
 
 // Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
-// repeated extensions, interfaces, root types and directives. graphql-js
-// also checks validateSchema; that check returns with schema validation
-// in M3b.
+// repeated extensions, interfaces, root types and directives. Where
+// graphql-js checks validateSchema, the port checks SchemaValidator.
 void main() {
   const dedent = Dedent();
   const port = SchemaPort();
@@ -124,6 +124,10 @@ void main() {
         port.schemaChanges(schema, extendedSchema),
         '$changes\n\n$newTypesSdl',
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends interfaces by adding new fields', () {
@@ -176,6 +180,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends interfaces by adding new implemented interfaces', () {
@@ -227,6 +235,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('allows extension of interface with missing Object fields', () {
@@ -257,6 +269,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<InvalidSchema>(),
+      );
     });
 
     test('extends interfaces multiple times', () {
@@ -288,6 +304,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('may extend mutations and subscriptions', () {
@@ -353,6 +373,10 @@ void main() {
       ''');
       final extendedSchema = port.extend(schema, extensionSdl);
       expect(port.schemaChanges(schema, extendedSchema), extensionSdl);
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
   });
 }
```

In `packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,8 +5,8 @@ import '../support/dedent.dart';
 import '../support/schema_port.dart';
 
 // Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
-// deprecation, new types and extensions of object types. graphql-js also
-// checks validateSchema; that check returns with schema validation in M3b.
+// deprecation, new types and extensions of object types. Where
+// graphql-js checks validateSchema, the port checks SchemaValidator.
 void main() {
   const dedent = Dedent();
   const port = SchemaPort();
@@ -99,6 +99,10 @@ void main() {
       ''');
       final extendedSchema = port.extend(schema, extensionSdl);
       expect(port.schemaChanges(schema, extendedSchema), extensionSdl);
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends objects by adding new fields with arguments', () {
@@ -134,6 +138,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends objects by adding new fields with existing types', () {
@@ -158,6 +166,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends objects by adding implemented interfaces', () {
@@ -185,6 +197,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends objects by including new types', () {
@@ -240,6 +256,10 @@ $newTypesSdl
         port.schemaChanges(schema, extendedSchema),
         '$changes\n\n$newTypesSdl',
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends objects by adding implemented new interfaces', () {
@@ -278,6 +298,10 @@ $newTypesSdl
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
   });
 }
```

In `packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,7 +14,8 @@ void main() {
   group('extendSchema', () {
     test('Throws on unknown types', () {
       // References are names: the build succeeds and schema validation
-      // reports the unknown type from M3b.
+      // reports the unknown type, after the query root: an extension adds
+      // no default roots.
       final extendedSchema = port.extend(Schema(), '''
         type Query {
           unknown: UnknownType
@@ -22,6 +23,10 @@ void main() {
       ''');
       expect(extendedSchema.typeNamed('Query'), isA<ObjectType>());
       expect(extendedSchema.typeNamed('UnknownType'), isNull);
+      expect(port.validationErrors(extendedSchema), [
+        'GQL111 Query root type must be provided.',
+        'GQL116 Unknown type "UnknownType".',
+      ]);
     });
 
     test('does not allow replacing a default directive', () {
@@ -36,13 +41,24 @@ void main() {
       expect(result.diagnostics.single.span?.text, 'include');
     });
 
+    test('Rejects invalid SDL', () {
+      // Adapted: the extension builds; the validator reports the directive,
+      // after the query root that the empty schema lacks.
+      final extended = port.extend(Schema(), 'extend schema @unknown');
+      expect(port.validationErrors(extended), [
+        'GQL111 Query root type must be provided.',
+        'GQL117 Unknown directive "@unknown".',
+      ]);
+    });
+
     test('Allows to disable SDL validation', () {
       // Adapted: the builder never validates, so an unknown directive
-      // extends without an option; schema validation (M3b) is what
-      // `assumeValid` turns off.
+      // extends without an option; `ValidSchema.assumeValid` is
+      // graphql-js's `assumeValid`.
       final schema = port.build('type Query { foo: String }');
       final extended = port.extend(schema, 'extend schema @unknown');
       expect(extended.appliedDirectives.single.name, 'unknown');
+      expect(ValidSchema.assumeValid(extended).schema, same(extended));
     });
 
     test('does not allow replacing an existing enum value', () {
```

In `packages/typed_graphql_conformance/test/schema/extend_schema_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,8 +6,7 @@ import '../support/schema_port.dart';
 
 // Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
 // the original schema, built-ins and extensions of each kind of type.
-// graphql-js also checks validateSchema; that check returns with schema
-// validation in M3b.
+// Where graphql-js checks validateSchema, the port checks SchemaValidator.
 void main() {
   const dedent = Dedent();
   const port = SchemaPort();
@@ -113,6 +112,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends objects with standard type fields', () {
@@ -145,6 +148,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedTwiceSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends enums by adding new values', () {
@@ -177,6 +184,10 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends unions by adding new types', () {
@@ -198,6 +209,10 @@ void main() {
         port.schemaChanges(schema, extendedSchema),
         'union SomeUnion = Foo | Biz | Bar',
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('allows extension of union by adding itself', () {
@@ -211,6 +226,10 @@ void main() {
         port.schemaChanges(schema, extendedSchema),
         'union SomeUnion = SomeUnion',
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<InvalidSchema>(),
+      );
     });
 
     test('extends inputs by adding new fields', () {
@@ -243,10 +262,17 @@ void main() {
           }
         '''),
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('extends scalars by adding new directives', () {
-      // The model keeps no extension nodes; the directive is applied.
+      // The model keeps no extension nodes; the directive is applied. The
+      // spec forbids a directive that reaches itself through the types of
+      // its arguments (§3.13), which graphql-js does not check: @foo takes
+      // a SomeScalar, which @foo is applied to.
       final schema = port.build('''
         type Query {
           someScalar(arg: SomeScalar): SomeScalar
@@ -272,6 +298,12 @@ void main() {
         [for (final directive in someScalar.appliedDirectives) directive.name],
         ['foo'],
       );
+      expect(
+        port.validationErrors(extendedSchema),
+        [
+          'GQL130 Directive "@foo" must not reference itself directly or indirectly.',
+        ],
+      );
     });
 
     test('extends scalars by adding specifiedBy directive', () {
@@ -298,6 +330,10 @@ void main() {
         port.printType(foo),
         'scalar Foo @foo @specifiedBy(url: "https://example.com/foo_spec")',
       );
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
 
     test('builds scalars with specifiedBy directive from extensions', () {
@@ -321,6 +357,10 @@ void main() {
       final foo = port.assertType<ScalarType>(extendedSchema, 'Foo');
       expect(foo.specifiedByUrl, 'https://example.com/foo_spec');
       expect(foo.span?.text, 'scalar Foo');
+      expect(
+        port.validate(extendedSchema),
+        isA<ValidSchema>(),
+      );
     });
   });
 }
```

In `packages/typed_graphql_conformance/test/support/schema_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -88,6 +88,17 @@ final class SchemaPort {
     ).where((definition) => !before.contains(definition)).join('\n\n');
   }
 
+  /// graphql-js's `validateSchema`: [schema] validated.
+  SchemaValidationResult validate(Schema schema) =>
+      const SchemaValidator().validate(schema);
+
+  /// The diagnostics of `validateSchema(schema)`, each as its code id and
+  /// message, such as `GQL116 Unknown type "X".`.
+  List<String> validationErrors(Schema schema) => [
+    for (final diagnostic in validate(schema).diagnostics)
+      '${diagnostic.code.id} ${diagnostic.message}',
+  ];
+
   /// The ids of the codes of [result]'s diagnostics, such as `GQL103`.
   List<String> codes(BuildResult result) => [
     for (final diagnostic in result.diagnostics) diagnostic.code.id,
```

- [ ] **Step 2: Update the mapping rows**

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -65,7 +65,7 @@ utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Multiple value enum,po
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty union,ported,test/schema/build_schema_types_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple Union,ported,test/schema/build_schema_types_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Multiple Union,ported,test/schema/build_schema_types_test.dart,
-utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Can build recursive Union,adapted,test/schema/build_schema_types_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Can build recursive Union,ported,test/schema/build_schema_types_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Custom Scalar,ported,test/schema/build_schema_types_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty Input Object,ported,test/schema/build_schema_types_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple Input Object,ported,test/schema/build_schema_types_test.dart,
@@ -87,47 +87,47 @@ utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend input
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly assign AST nodes,adapted,test/schema/build_schema_elements_test.dart,the model keeps source spans instead of AST nodes; the test compares their text
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Root operation types with custom names,ported,test/schema/build_schema_elements_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Default root operation type names,ported,test/schema/build_schema_elements_test.dart,
-utilities/__tests__/buildASTSchema-test.ts,Schema Builder,can build invalid schema,adapted,test/schema/build_schema_elements_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,can build invalid schema,ported,test/schema/build_schema_elements_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Do not override standard types,adapted,test/schema/build_schema_elements_test.dart,redefining a built-in type is GQL103 instead of being ignored
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Allows to reference introspection types,ported,test/schema/build_schema_elements_test.dart,
-utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Rejects invalid SDL,skipped,,SDL validation (unknown directives) arrives with schema validation in M3b
-utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Allows to disable SDL validation,adapted,test/schema/build_schema_elements_test.dart,"the builder never validates, so an unknown directive builds; M3b adds the assumeValid link"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Rejects invalid SDL,adapted,test/schema/build_schema_elements_test.dart,the builder builds; the validator reports the unknown directive (GQL117)
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Allows to disable SDL validation,adapted,test/schema/build_schema_elements_test.dart,"the builder never validates, so an unknown directive builds without an option; ValidSchema.assumeValid stands for assumeValid"
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,buildSchema parses directives on directive definitions,ported,test/schema/build_schema_elements_test.dart,
-utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Throws on unknown types,adapted,test/schema/build_schema_elements_test.dart,"references are names, so the build succeeds; schema validation reports the unknown type from M3b"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Throws on unknown types,adapted,test/schema/build_schema_elements_test.dart,"references are names, so the build succeeds; the validator reports the unknown type (GQL116)"
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,correctly processes viral schema,ported,test/schema/build_schema_elements_test.dart,
 utilities/__tests__/extendSchema-test.ts,extendSchema,returns the original schema when there are no type definitions,adapted,test/schema/extend_schema_test.dart,an operation in SDL is GQL100; the partial schema is the original instance
 utilities/__tests__/extendSchema-test.ts,extendSchema,can be used for limited execution,skipped,,execution arrives in M5
 utilities/__tests__/extendSchema-test.ts,extendSchema,Do not modify built-in types and directives,adapted,test/schema/extend_schema_test.dart,built-in directives are not listed in Schema.directives; the test checks the lookups
 utilities/__tests__/extendSchema-test.ts,extendSchema,preserves original schema config,adapted,test/schema/extend_schema_test.dart,the model has no extensions bag; the test checks the description
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects with standard type fields,adapted,test/schema/extend_schema_test.dart,every schema finds every built-in scalar; schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends enums by adding new values,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends unions by adding new types,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,allows extension of union by adding itself,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends inputs by adding new fields,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends scalars by adding new directives,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directive; schema validation arrives in M3b; the test checks what the builder keeps"
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends scalars by adding specifiedBy directive,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; schema validation arrives in M3b; the test checks what the builder keeps"
-utilities/__tests__/extendSchema-test.ts,extendSchema,builds scalars with specifiedBy directive from extensions,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; schema validation arrives in M3b; the test checks what the builder keeps"
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields,ported,test/schema/extend_schema_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects with standard type fields,adapted,test/schema/extend_schema_test.dart,every schema finds every built-in scalar
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends enums by adding new values,ported,test/schema/extend_schema_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends unions by adding new types,ported,test/schema/extend_schema_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,allows extension of union by adding itself,ported,test/schema/extend_schema_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends inputs by adding new fields,ported,test/schema/extend_schema_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends scalars by adding new directives,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directive; the spec's directive rule (§3.13), which graphql-js does not check, rejects @foo(arg: SomeScalar) applied to SomeScalar (GQL130)"
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends scalars by adding specifiedBy directive,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/extendSchema-test.ts,extendSchema,builds scalars with specifiedBy directive from extensions,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped"
 utilities/__tests__/extendSchema-test.ts,extendSchema,correctly assign AST nodes to new and extended types,adapted,test/schema/extend_schema_spans_test.dart,the model keeps source spans instead of AST nodes and no extension nodes; the test compares span texts
 utilities/__tests__/extendSchema-test.ts,extendSchema,builds types with deprecated fields/values,ported,test/schema/extend_schema_objects_test.dart,
 utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects with deprecated fields,ported,test/schema/extend_schema_objects_test.dart,
 utilities/__tests__/extendSchema-test.ts,extendSchema,extends enums with deprecated values,ported,test/schema/extend_schema_objects_test.dart,
-utilities/__tests__/extendSchema-test.ts,extendSchema,adds new unused types,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields with arguments,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields with existing types,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding implemented interfaces,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by including new types,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding implemented new interfaces,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends different types multiple times,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces by adding new fields,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces by adding new implemented interfaces,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,allows extension of interface with missing Object fields,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces multiple times,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,adds new unused types,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields with arguments,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields with existing types,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding implemented interfaces,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by including new types,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding implemented new interfaces,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends different types multiple times,ported,test/schema/extend_schema_interfaces_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces by adding new fields,ported,test/schema/extend_schema_interfaces_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces by adding new implemented interfaces,ported,test/schema/extend_schema_interfaces_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,allows extension of interface with missing Object fields,ported,test/schema/extend_schema_interfaces_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces multiple times,ported,test/schema/extend_schema_interfaces_test.dart,
 utilities/__tests__/extendSchema-test.ts,extendSchema,may extend mutations and subscriptions,ported,test/schema/extend_schema_interfaces_test.dart,
-utilities/__tests__/extendSchema-test.ts,extendSchema,may extend directives with new directive,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
-utilities/__tests__/extendSchema-test.ts,extendSchema,Rejects invalid SDL,skipped,,SDL validation (unknown directives) arrives with schema validation in M3b
-utilities/__tests__/extendSchema-test.ts,extendSchema,Allows to disable SDL validation,adapted,test/schema/extend_schema_roots_test.dart,"the builder never validates, so an unknown directive extends; M3b adds the assumeValid link"
-utilities/__tests__/extendSchema-test.ts,extendSchema,Throws on unknown types,adapted,test/schema/extend_schema_roots_test.dart,"references are names, so the build succeeds; schema validation reports the unknown type from M3b"
+utilities/__tests__/extendSchema-test.ts,extendSchema,may extend directives with new directive,ported,test/schema/extend_schema_interfaces_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,Rejects invalid SDL,adapted,test/schema/extend_schema_roots_test.dart,the extension builds; the validator reports the unknown directive (GQL117) after the missing query root of the empty schema
+utilities/__tests__/extendSchema-test.ts,extendSchema,Allows to disable SDL validation,adapted,test/schema/extend_schema_roots_test.dart,"the builder never validates, so an unknown directive extends without an option; ValidSchema.assumeValid stands for assumeValid"
+utilities/__tests__/extendSchema-test.ts,extendSchema,Throws on unknown types,adapted,test/schema/extend_schema_roots_test.dart,"references are names, so the build succeeds; the validator reports the unknown type (GQL116) after the query root, which an extension does not default"
 utilities/__tests__/extendSchema-test.ts,extendSchema,does not allow replacing a default directive,adapted,test/schema/extend_schema_roots_test.dart,redefining a built-in directive is GQL103 with its own message
 utilities/__tests__/extendSchema-test.ts,extendSchema,does not allow replacing an existing enum value,ported,test/schema/extend_schema_roots_test.dart,
 utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,does not automatically include common root type names,ported,test/schema/extend_schema_roots_test.dart,
```

- [ ] **Step 3: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/schema/build_schema_elements_test.dart test/schema/build_schema_types_test.dart test/schema/extend_schema_interfaces_test.dart test/schema/extend_schema_objects_test.dart test/schema/extend_schema_roots_test.dart test/schema/extend_schema_test.dart)
```

Expected: `typed_graphql_conformance` `+80: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+623: All tests passed!`.

- [ ] **Step 4: Update the documents**

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- The build and extend ports check `validateSchema` where graphql-js does
  (`SchemaPort.validate`, `validationErrors`); SDL validation is the
  validator's: an unknown directive is `GQL117`, an unknown type `GQL116`.
```

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_test.dart packages/typed_graphql_conformance/test/support/schema_port.dart
git commit -q -m "test(typed_graphql_conformance): check schema validation in the build and extend ports" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 13: Add the introspection query

R2.7. `IntrospectionQuery` builds graphql-js's `getIntrospectionQuery` with the same options and fragments (Open question 3). The September2025 edition has no directive deprecation; `includesDirectiveDeprecation` asks for the working-draft field (finding 7).

It is the first exported type of `lib/src/schema/introspection/`, which gets its own dartdoc category and guide, as the handoff asks (decision 12): `introspection`, declared in `dartdoc_options.yaml`, mapped like `scalars` in M3c's `category_tags_test.dart`, with the guide `doc/introspection.md`. This task writes the guide's first section; Tasks 14 and 15 add theirs.

**Files:**
- Create: `packages/typed_graphql/doc/introspection.md`, `packages/typed_graphql/lib/src/schema/introspection/introspection_query.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/dartdoc_options.yaml`, `packages/typed_graphql/doc/getting_started.md`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql/test/doc/category_tags_test.dart`, `packages/typed_graphql/test/schema/introspection/introspection_query_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/introspection_query_test.dart`

**Interfaces:**
- Consumes: M3c `dartdoc_options.yaml`, `test/doc/category_tags_test.dart`, the README guide table and Getting Started's "Where to go next".
- Produces:
```text
final class const IntrospectionQuery({bool includesDescriptions = true, bool includesSpecifiedByUrl = false,
  bool includesDirectiveIsRepeatable = false, bool includesSchemaDescription = false,
  bool includesInputValueDeprecation = false, bool includesDirectiveDeprecation = false,
  bool includesOneOf = false, int typeDepth = 9})               // exported, {@category introspection}
  static const IntrospectionQuery full;   // every September2025 option on
  String get text;                        // RangeError for a typeDepth outside 0..100 (Open question 4)
dartdoc category `introspection` -> doc/introspection.md ("Introspection"), after `scalars`
category_tags_test.dart categoryOf: ['src', 'schema', 'introspection', ...] => 'introspection'
mapping_test.dart: `covered` gains utilities/__tests__/getIntrospectionQuery-test.ts
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/introspection/introspection_query_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  int count(String text, String word) =>
      RegExp('\\b$word\\b').allMatches(text).length;

  group('IntrospectionQuery', () {
    test('parses as one operation and three fragments', () {
      final result = const Parser().parse(
        Source(IntrospectionQuery.full.text),
      );
      final document = (result as ParseSuccess).document;
      expect(document.definitions.map((definition) => definition.runtimeType), [
        OperationDefinition,
        FragmentDefinition,
        FragmentDefinition,
        FragmentDefinition,
      ]);
    });

    test('reads nine ofType levels by default', () {
      expect(count(const IntrospectionQuery().text, 'ofType'), 9);
    });

    test('reads no ofType level at depth 0', () {
      expect(
        count(const IntrospectionQuery(typeDepth: 0).text, 'ofType'),
        0,
      );
    });

    test('rejects a depth above 100', () {
      expect(
        () => const IntrospectionQuery(typeDepth: 101).text,
        throwsA(
          isA<RangeError>().having(
            (error) => error.message,
            'message',
            contains('Please set typeDepth to a reasonable value'),
          ),
        ),
      );
    });

    test('rejects a negative depth', () {
      expect(
        () => const IntrospectionQuery(typeDepth: -1).text,
        throwsRangeError,
      );
    });

    test('full reads every September2025 field', () {
      final text = IntrospectionQuery.full.text;
      for (final word in ['specifiedByURL', 'isRepeatable', 'isOneOf']) {
        expect(count(text, word), 1, reason: word);
      }
      expect(count(text, 'description'), 6);
      expect(count(text, 'includeDeprecated: true'), 5);
    });

    test('full does not read directive deprecation', () {
      expect(
        IntrospectionQuery.full.text,
        isNot(contains('directives(includeDeprecated: true)')),
      );
    });

    test('starts and ends with the operation and the TypeRef fragment', () {
      final text = const IntrospectionQuery(typeDepth: 1).text;
      expect(text, startsWith('query IntrospectionQuery {\n  __schema {\n'));
      expect(
        text,
        endsWith(
          'fragment TypeRef on __Type {\n'
          '  kind\n'
          '  name\n'
          '  ofType {\n'
          '    name\n'
          '    kind\n'
          '  }\n'
          '}',
        ),
      );
    });
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -73,6 +73,7 @@ void main() {
         'type/__tests__/validation-test.ts',
         'utilities/__tests__/buildASTSchema-test.ts',
         'utilities/__tests__/extendSchema-test.ts',
+        'utilities/__tests__/getIntrospectionQuery-test.ts',
         'utilities/__tests__/printSchema-test.ts',
       ],
     ),
```

Create `packages/typed_graphql_conformance/test/schema/introspection_query_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

// Ported from graphql-js src/utilities/__tests__/getIntrospectionQuery-test.ts.
// graphql-js validates each query against a schema; operation validation
// arrives in M4, so the port parses it instead. Option names map to the
// `includes*` flags of IntrospectionQuery.
void main() {
  /// The text of [query], which must parse.
  String textOf(IntrospectionQuery query) {
    final text = query.text;
    expect(const Parser().parse(Source(text)), isA<ParseSuccess>());
    return text;
  }

  int count(IntrospectionQuery query, String name) =>
      RegExp('\\b$name\\b').allMatches(textOf(query)).length;

  group('getIntrospectionQuery', () {
    test('skip all "description" fields', () {
      expect(count(const IntrospectionQuery(), 'description'), 5);
      expect(
        count(
          const IntrospectionQuery(includesDescriptions: true),
          'description',
        ),
        5,
      );
      expect(
        count(
          const IntrospectionQuery(includesDescriptions: false),
          'description',
        ),
        0,
      );
    });

    test('include "isRepeatable" field on directives', () {
      expect(count(const IntrospectionQuery(), 'isRepeatable'), 0);
      expect(
        count(
          const IntrospectionQuery(includesDirectiveIsRepeatable: true),
          'isRepeatable',
        ),
        1,
      );
      expect(
        count(
          const IntrospectionQuery(includesDirectiveIsRepeatable: false),
          'isRepeatable',
        ),
        0,
      );
    });

    test('include "description" field on schema', () {
      expect(count(const IntrospectionQuery(), 'description'), 5);
      expect(
        count(
          const IntrospectionQuery(includesSchemaDescription: false),
          'description',
        ),
        5,
      );
      expect(
        count(
          const IntrospectionQuery(includesSchemaDescription: true),
          'description',
        ),
        6,
      );
      expect(
        count(
          const IntrospectionQuery(
            includesDescriptions: false,
            includesSchemaDescription: true,
          ),
          'description',
        ),
        0,
      );
    });

    test('include "specifiedBy" field', () {
      expect(count(const IntrospectionQuery(), 'specifiedByURL'), 0);
      expect(
        count(
          const IntrospectionQuery(includesSpecifiedByUrl: true),
          'specifiedByURL',
        ),
        1,
      );
      expect(
        count(
          const IntrospectionQuery(includesSpecifiedByUrl: false),
          'specifiedByURL',
        ),
        0,
      );
    });

    test('include "isDeprecated" field on input values', () {
      expect(count(const IntrospectionQuery(), 'isDeprecated'), 2);
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: true),
          'isDeprecated',
        ),
        3,
      );
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: false),
          'isDeprecated',
        ),
        2,
      );
    });

    test('include "deprecationReason" field on input values', () {
      expect(count(const IntrospectionQuery(), 'deprecationReason'), 2);
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: true),
          'deprecationReason',
        ),
        3,
      );
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: false),
          'deprecationReason',
        ),
        2,
      );
    });

    test('include "isOneOf" field on input objects', () {
      expect(count(const IntrospectionQuery(), 'isOneOf'), 0);
      expect(
        count(const IntrospectionQuery(includesOneOf: true), 'isOneOf'),
        1,
      );
      expect(
        count(const IntrospectionQuery(includesOneOf: false), 'isOneOf'),
        0,
      );
    });

    test('include deprecated input field and args', () {
      expect(count(const IntrospectionQuery(), 'includeDeprecated: true'), 2);
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: true),
          'includeDeprecated: true',
        ),
        5,
      );
      expect(
        count(
          const IntrospectionQuery(includesInputValueDeprecation: false),
          'includeDeprecated: true',
        ),
        2,
      );
    });

    test('include "isDeprecated" field on directives', () {
      expect(count(const IntrospectionQuery(), 'isDeprecated'), 2);
      expect(
        count(
          const IntrospectionQuery(includesDirectiveDeprecation: true),
          'isDeprecated',
        ),
        3,
      );
      expect(
        count(
          const IntrospectionQuery(includesDirectiveDeprecation: false),
          'isDeprecated',
        ),
        2,
      );
    });

    test('include "deprecationReason" field on directives', () {
      const opening = 'directives(includeDeprecated: true) {';
      expect(textOf(const IntrospectionQuery()), isNot(contains(opening)));
      expect(count(const IntrospectionQuery(), 'deprecationReason'), 2);
      const withDeprecation = IntrospectionQuery(
        includesDirectiveDeprecation: true,
      );
      expect(textOf(withDeprecation), contains(opening));
      expect(count(withDeprecation, 'deprecationReason'), 3);
      const without = IntrospectionQuery(includesDirectiveDeprecation: false);
      expect(textOf(without), isNot(contains(opening)));
      expect(count(without, 'deprecationReason'), 2);
    });

    test('throw error if typeDepth is too high', () {
      expect(
        () => const IntrospectionQuery(typeDepth: 101).text,
        throwsA(
          isA<RangeError>().having(
            (error) => error.message,
            'message',
            'Please set typeDepth to a reasonable value between 0 and 100; '
                'the default is 9.',
          ),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_query_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/introspection_query_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+0 -1: Some tests failed.`; the first messages: `Error: Undefined name 'IntrospectionQuery'.`, `Error: Couldn't find constructor 'IntrospectionQuery'.`. `typed_graphql_conformance` ends with `+31 -2: Some tests failed.`; the first messages: `Error: 'IntrospectionQuery' isn't a type.`, `Error: Couldn't find constructor 'IntrospectionQuery'.`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/schema/introspection/introspection_query.dart`:

```dart
import 'package:meta/meta.dart';

/// The introspection query (spec §4): the operation a client sends to read
/// a schema, as graphql-js's `getIntrospectionQuery` writes it.
///
/// Each flag adds fields that a server of an older edition, or one without
/// a working-draft feature, may lack; [text] is the query. [full] is what
/// a September2025 server answers and what `Schema.toIntrospection` writes
/// by default.
///
/// {@category introspection}
@immutable
final class const IntrospectionQuery({
  /// Whether types, fields, arguments, enum values and directives read
  /// their `description`.
  final bool includesDescriptions = true,

  /// Whether scalars read `specifiedByURL`.
  final bool includesSpecifiedByUrl = false,

  /// Whether directives read `isRepeatable`.
  final bool includesDirectiveIsRepeatable = false,

  /// Whether the schema reads its `description`; only with
  /// [includesDescriptions].
  final bool includesSchemaDescription = false,

  /// Whether arguments and input fields are read with their deprecated
  /// ones, `isDeprecated` and `deprecationReason`.
  final bool includesInputValueDeprecation = false,

  /// Whether directives are read with their deprecated ones,
  /// `isDeprecated` and `deprecationReason`: a working-draft feature that
  /// September2025 introspection lacks.
  final bool includesDirectiveDeprecation = false,

  /// Whether input objects read `isOneOf`.
  final bool includesOneOf = false,

  /// How many `ofType` levels a type reference reads, from 0 to 100; a
  /// deeper type reads as cut off.
  final int typeDepth = 9,
}) {
  /// Creates the query with graphql-js's default options.
  this;

  /// Every field September2025 introspection has: graphql-js's
  /// `introspectionFromSchema` options without directive deprecation,
  /// which the edition lacks (R0.1).
  static const IntrospectionQuery full = IntrospectionQuery(
    includesSpecifiedByUrl: true,
    includesDirectiveIsRepeatable: true,
    includesSchemaDescription: true,
    includesInputValueDeprecation: true,
    includesOneOf: true,
  );

  static const String _depthMessage =
      'Please set typeDepth to a reasonable value between 0 and 100; the '
      'default is 9.';

  /// The query text: the operation `IntrospectionQuery` and the fragments
  /// `FullType`, `InputValue` and `TypeRef`.
  ///
  /// A [typeDepth] outside 0 to 100 is a [RangeError] with graphql-js's
  /// message.
  String get text {
    RangeError.checkValueInInterval(
      typeDepth,
      0,
      100,
      'typeDepth',
      _depthMessage,
    );
    return [
      ..._operation,
      '',
      ..._fullType,
      '',
      ..._inputValue,
      '',
      ..._typeRef,
    ].join('\n');
  }

  String get _directiveArguments =>
      includesDirectiveDeprecation ? '(includeDeprecated: true)' : '';

  String get _inputArguments =>
      includesInputValueDeprecation ? '(includeDeprecated: true)' : '';

  List<String> get _operation => [
    'query IntrospectionQuery {',
    '  __schema {',
    if (includesSchemaDescription && includesDescriptions) '    description',
    '    queryType { name kind }',
    '    mutationType { name kind }',
    '    subscriptionType { name kind }',
    '    types {',
    '      ...FullType',
    '    }',
    '    directives$_directiveArguments {',
    '      name',
    if (includesDescriptions) '      description',
    if (includesDirectiveIsRepeatable) '      isRepeatable',
    if (includesDirectiveDeprecation) ...[
      '      isDeprecated',
      '      deprecationReason',
    ],
    '      locations',
    '      args$_inputArguments {',
    '        ...InputValue',
    '      }',
    '    }',
    '  }',
    '}',
  ];

  List<String> get _fullType => [
    'fragment FullType on __Type {',
    '  kind',
    '  name',
    if (includesDescriptions) '  description',
    if (includesSpecifiedByUrl) '  specifiedByURL',
    if (includesOneOf) '  isOneOf',
    '  fields(includeDeprecated: true) {',
    '    name',
    if (includesDescriptions) '    description',
    '    args$_inputArguments {',
    '      ...InputValue',
    '    }',
    '    type {',
    '      ...TypeRef',
    '    }',
    '    isDeprecated',
    '    deprecationReason',
    '  }',
    '  inputFields$_inputArguments {',
    '    ...InputValue',
    '  }',
    '  interfaces {',
    '    ...TypeRef',
    '  }',
    ..._enumValues,
    '  possibleTypes {',
    '    ...TypeRef',
    '  }',
    '}',
  ];

  List<String> get _enumValues => [
    '  enumValues(includeDeprecated: true) {',
    '    name',
    if (includesDescriptions) '    description',
    '    isDeprecated',
    '    deprecationReason',
    '  }',
  ];

  List<String> get _inputValue => [
    'fragment InputValue on __InputValue {',
    '  name',
    if (includesDescriptions) '  description',
    '  type { ...TypeRef }',
    '  defaultValue',
    if (includesInputValueDeprecation) ...[
      '  isDeprecated',
      '  deprecationReason',
    ],
    '}',
  ];

  // The `ofType` levels nest; they are written with a loop, not recursion.
  List<String> get _typeRef {
    final opening = <String>[];
    final closing = <String>[];
    for (var level = 1; level <= typeDepth; level++) {
      final indent = '  ' * level;
      opening.addAll(['${indent}ofType {', '$indent  name', '$indent  kind']);
      closing.insert(0, '$indent}');
    }
    return [
      'fragment TypeRef on __Type {',
      '  kind',
      '  name',
      ...opening,
      ...closing,
      '}',
    ];
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,6 +66,7 @@ export 'src/protocol/response_payload.dart';
 export 'src/schema/build/build_result.dart';
 export 'src/schema/build/built_ins.dart';
 export 'src/schema/build/schema_builder.dart';
+export 'src/schema/introspection/introspection_query.dart';
 export 'src/schema/model/applied_directive.dart';
 export 'src/schema/model/input_value.dart';
 export 'src/schema/model/named_type_reference.dart';
```

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -271,3 +271,14 @@ type/__tests__/validation-test.ts,Interfaces must adhere to Interface they imple
 type/__tests__/validation-test.ts,Interfaces must adhere to Interface they implement,rejects deprecated implementation field when interface field is not deprecated,ported,test/schema/validate_schema_interfaces_test.dart,
 type/__tests__/validation-test.ts,assertValidSchema,does not throw on valid schemas,adapted,test/schema/validate_schema_interfaces_test.dart,SchemaValidator returns a sealed result instead of throwing
 type/__tests__/validation-test.ts,assertValidSchema,combines multiple errors,adapted,test/schema/validate_schema_interfaces_test.dart,SchemaValidator returns a sealed result instead of throwing; the result holds both errors
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"skip all ""description"" fields",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""isRepeatable"" field on directives",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""description"" field on schema",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""specifiedBy"" field",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""isDeprecated"" field on input values",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""deprecationReason"" field on input values",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""isOneOf"" field on input objects",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,include deprecated input field and args,adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""isDeprecated"" field on directives",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""deprecationReason"" field on directives",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
+utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,throw error if typeDepth is too high,ported,test/schema/introspection_query_test.dart,
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_query_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/introspection_query_test.dart)
```

Expected: `typed_graphql` `+8: All tests passed!`, `typed_graphql_conformance` `+43: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+635: All tests passed!`.

- [ ] **Step 5: Update the guides**

The new guide starts with the query; the README and Getting Started list it, and the category test maps the folder to its category.

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -101,6 +101,7 @@ is run by the test suite, so what they print is what the package does.
 | [Wire protocol](doc/protocol.md) | `JsonValue`, requests, responses, errors |
 | [Schema](doc/schema.md) | Build a schema from SDL, read it, extend it, print it |
 | [Scalars and codecs](doc/scalars.md) | The built-in codecs and your own |
+| [Introspection](doc/introspection.md) | Write the introspection query, answer it from a schema, build a schema from an answer |
 
 The API reference is generated by `dart doc` and groups every type under the
 same topics. Run it in this directory and open `doc/api/index.html`.
```

In `packages/typed_graphql/dartdoc_options.yaml`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -18,6 +18,9 @@ dartdoc:
     scalars:
       markdown: doc/scalars.md
       displayName: Scalars & Codecs
+    introspection:
+      markdown: doc/introspection.md
+      displayName: Introspection
   categoryOrder:
     - getting-started
     - diagnostics
@@ -25,4 +28,5 @@ dartdoc:
     - protocol
     - schema
     - scalars
+    - introspection
   showUndocumentedCategories: true
```

In `packages/typed_graphql/doc/getting_started.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -91,5 +91,7 @@ query root: Query
 - **Wire Protocol** — requests, responses and errors as typed values.
 - **Schema** — build a schema from SDL, extend it, print it.
 - **Scalars & Codecs** — the built-in scalar codecs and your own.
+- **Introspection** — the introspection query, a schema's answer, and a
+  schema built from an answer.
 
 The API reference lists every type under the same topics.
```

Create `packages/typed_graphql/doc/introspection.md`:

````markdown
# Introspection

Introspection is how a client asks a server for its schema (September2025,
"Introspection"). The client sends the introspection query; the server answers
it with a JSON description of its schema, which the client can build a schema
from. The types of this topic write the query, answer it from a `Schema`, and
read an answer back.

## The introspection query

`IntrospectionQuery` writes the query a client sends. Its `text` has the
fields and fragments of graphql-js's `getIntrospectionQuery`, and its flags
choose the optional fields: `includesDescriptions` (on by default),
`includesSpecifiedByUrl`, `includesDirectiveIsRepeatable`,
`includesSchemaDescription`, `includesInputValueDeprecation`, `includesOneOf`,
and the working-draft `includesDirectiveDeprecation`. `IntrospectionQuery.full`
asks for every field of September2025. `typeDepth` (9 by default, at most 100)
is how many `ofType` levels the query reads for a wrapped type.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  print(IntrospectionQuery.full.text.split('\n').first);
  print(IntrospectionQuery.full.text.contains('isOneOf'));
  print(const IntrospectionQuery().text.contains('isOneOf'));
}
```

It prints:

```text
query IntrospectionQuery {
true
false
```
````

In `packages/typed_graphql/test/doc/category_tags_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -28,6 +28,7 @@ void main() {
   /// The category of the types in the library file [path], from `lib/`.
   String categoryOf(String path) => switch (path.split('/')) {
     ['src', 'schema', 'scalars', ...] => 'scalars',
+    ['src', 'schema', 'introspection', ...] => 'introspection',
     ['src', final layer, ...] => layer,
     _ => throw ArgumentError.value(path, 'path', 'is not under lib/src'),
   };
```

- [ ] **Step 6: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+234: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 7: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -248,6 +248,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   decodes (an enum value becomes its name), so codecs have no
   `parseLiteral`.
 
+- `introspection/IntrospectionQuery` (const): graphql-js's
+  `getIntrospectionQuery` options as `includes*` flags and `typeDepth`;
+  `text` writes the operation and its three fragments line by line (the
+  `ofType` levels with a loop). `full` is every September2025 field:
+  directive deprecation is working-draft and stays off.
 - `validation/SchemaValidator` (const): `validate(schema)` returns the
   sealed `SchemaValidationResult` (`ValidSchema` | `InvalidSchema(schema,
   diagnostics)`); `ValidSchema` has a private constructor and
@@ -391,7 +396,7 @@ in `It prints:` and a `text` fence with its exact output; a fragment or a
 signature is a `text` fence. A guide has no relative link (dartdoc breaks
 it) and names another guide by its topic. Every exported public type has
 `/// {@category <folder>}` in its doc comment (`schema/scalars/` is
-`scalars`); a new exported folder needs its category in
+`scalars`, `schema/introspection/` is `introspection`); a new exported folder needs its category in
 `dartdoc_options.yaml` and its guide. `dart doc` reports 0 warnings. A stage
 that adds API adds its section to the guide of its layer in the same commit.
 
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `IntrospectionQuery`: graphql-js's `getIntrospectionQuery` as a const
  value with `includes*` flags and `typeDepth` (0 to 100, else a
  `RangeError`); `text` is the query. `IntrospectionQuery.full` reads
  every field September2025 introspection has.
```

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Ported graphql-js `getIntrospectionQuery-test.ts`; each query is parsed,
  since operation validation arrives in M4.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/README.md packages/typed_graphql/dartdoc_options.yaml packages/typed_graphql/doc/getting_started.md packages/typed_graphql/doc/introspection.md packages/typed_graphql/lib/src/schema/introspection/introspection_query.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/doc/category_tags_test.dart packages/typed_graphql/test/schema/introspection/introspection_query_test.dart packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/introspection_query_test.dart
git commit -q -m "feat(typed_graphql): add the introspection query" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 14: Write a schema as its introspection result

`Schema.toIntrospection` gives the `data` of the introspection query, for the fields the query reads (decision 6). Union `possibleTypes` lists every member (decision 5). A reference to a type the schema lacks is an `ArgumentError` (Open question 2). The Introspection guide gains "Answering from a schema".

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart`, `packages/typed_graphql/lib/src/schema/introspection/type_ref_writer.dart`, `packages/typed_graphql/lib/src/schema/introspection/type_writer.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/introspection.md`, `packages/typed_graphql/lib/src/schema/schema.dart`
- Test: `packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart`

**Interfaces:**
- Consumes: Task 13 (`IntrospectionQuery`, `doc/introspection.md`), Task 3 (`Schema.possibleTypes`); M1 `JsonValue`.
- Produces:
```text
JsonObject Schema.toIntrospection([IntrospectionQuery query = IntrospectionQuery.full])   // {"__schema": ...}
internal:
  IntrospectionWriter(Schema schema, IntrospectionQuery query) { JsonObject write() }
  TypeWriter(Schema schema, IntrospectionQuery query) { JsonObject type(SchemaType type);
    JsonArray inputValues(List<InputValue> values); Map<String, JsonValue> deprecation(String? reason) }
  TypeRefWriter(Schema schema, int typeDepth) { JsonObject reference(TypeRef type); JsonObject named(String name);
    String kindOf(SchemaType type); String kindNamed(String name) }
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  Map<String, Object?> schemaOf(
    String sdl, [
    IntrospectionQuery query = IntrospectionQuery.full,
  ]) {
    final json = Built(sdl).schema.toIntrospection(query).toJson();
    return json['__schema']! as Map<String, Object?>;
  }

  List<Map<String, Object?>> listOf(Object? json) =>
      (json! as List<Object?>).cast<Map<String, Object?>>();

  Map<String, Object?> typeOf(Map<String, Object?> schema, String name) =>
      listOf(schema['types']).singleWhere((type) => type['name'] == name);

  Map<String, Object?> fieldOf(Map<String, Object?> type, String name) =>
      listOf(type['fields']).singleWhere((field) => field['name'] == name);

  List<Object?> namesOf(Object? json) => [
    for (final element in listOf(json)) element['name'],
  ];

  group('Schema.toIntrospection', () {
    test('writes the root types by name and kind', () {
      final schema = schemaOf('type Query { a: String }');
      expect(schema['queryType'], {'name': 'Query', 'kind': 'OBJECT'});
      expect(schema['mutationType'], isNull);
      expect(schema['subscriptionType'], isNull);
    });

    test('lists declared types, used built-in scalars, then introspection', () {
      final schema = schemaOf('type Query { a: Int }');
      expect(namesOf(schema['types']), [
        'Query',
        'String',
        'Int',
        'Boolean',
        '__Schema',
        '__Type',
        '__TypeKind',
        '__Field',
        '__InputValue',
        '__EnumValue',
        '__Directive',
        '__DirectiveLocation',
      ]);
    });

    test('lists declared directives before the built-in ones', () {
      final schema = schemaOf('directive @a on FIELD type Query { a: Int }');
      expect(namesOf(schema['directives']), [
        'a',
        'include',
        'skip',
        'deprecated',
        'specifiedBy',
        'oneOf',
      ]);
    });

    test('lists @defer and @stream when the schema has them', () {
      final document = Sdl('type Query { a: Int }').document;
      final result = const SchemaBuilder(
        includesDeferAndStream: true,
      ).fromSdl(document);
      final schema = (result as BuildSuccess).schema;
      final json = schema.toIntrospection().toJson()['__schema']!;
      expect(
        namesOf((json as Map<String, Object?>)['directives']),
        containsAllInOrder(['oneOf', 'defer', 'stream']),
      );
    });

    test('writes wrappers as nested ofType levels', () {
      final type = typeOf(schemaOf('type Query { a: [Int!]! }'), 'Query');
      final reference = fieldOf(type, 'a')['type']! as Map<String, Object?>;
      expect(reference['kind'], 'NON_NULL');
      expect(reference['name'], isNull);
      final list = reference['ofType']! as Map<String, Object?>;
      final item = list['ofType']! as Map<String, Object?>;
      expect(item['ofType'], {'kind': 'SCALAR', 'name': 'Int', 'ofType': null});
    });

    test('cuts a reference at the type depth', () {
      final schema = schemaOf(
        'type Query { a: [Int!]! }',
        const IntrospectionQuery(typeDepth: 1),
      );
      final type = typeOf(schema, 'Query');
      expect(fieldOf(type, 'a')['type'], {
        'kind': 'NON_NULL',
        'name': null,
        'ofType': {'kind': 'LIST', 'name': null},
      });
    });

    test('writes a deep reference without recursion', () {
      TypeRef type = const NamedType(Name('Int'));
      for (var i = 0; i < 10000; i++) {
        type = ListType(type);
      }
      final schema = Schema(
        types: [
          ObjectType('Query', fields: [SchemaField('a', type)]),
        ],
        queryTypeName: 'Query',
      );
      final json = schema.toIntrospection(
        const IntrospectionQuery(typeDepth: 100),
      );
      expect(json.toString(), contains('"kind":"LIST"'));
    });

    test('prints default values as GraphQL', () {
      final type = typeOf(
        schemaOf('type Query { a(b: [Int] = [1, 2]): Int }'),
        'Query',
      );
      final argument = listOf(fieldOf(type, 'a')['args']).single;
      expect(argument['defaultValue'], '[1, 2]');
    });

    test('leaves deprecated arguments out unless the query reads them', () {
      const sdl = 'type Query { a(b: Int @deprecated, c: Int): Int }';
      final full = typeOf(schemaOf(sdl), 'Query');
      expect(namesOf(fieldOf(full, 'a')['args']), ['b', 'c']);
      final older = typeOf(schemaOf(sdl, const IntrospectionQuery()), 'Query');
      expect(namesOf(fieldOf(older, 'a')['args']), ['c']);
    });

    test('writes the possible types of interfaces and unions', () {
      final schema = schemaOf('''
        type Query { a: I, b: U }
        interface I { a: Int }
        type A implements I { a: Int }
        union U = A
      ''');
      expect(namesOf(typeOf(schema, 'I')['possibleTypes']), ['A']);
      expect(namesOf(typeOf(schema, 'U')['possibleTypes']), ['A']);
      expect(namesOf(typeOf(schema, 'A')['interfaces']), ['I']);
      expect(typeOf(schema, 'A')['possibleTypes'], isNull);
    });

    test('writes only the fields the query reads', () {
      final schema = schemaOf(
        '"Q" type Query { a: Int }',
        const IntrospectionQuery(includesDescriptions: false),
      );
      expect(schema.containsKey('description'), isFalse);
      expect(typeOf(schema, 'Query').keys, [
        'kind',
        'name',
        'fields',
        'inputFields',
        'interfaces',
        'enumValues',
        'possibleTypes',
      ]);
    });

    test('writes directive deprecation only when the query reads it', () {
      final directive = SchemaDirective(
        'old',
        locations: [DirectiveLocation.query],
        appliedDirectives: [
          AppliedDirective(
            'deprecated',
            arguments: [
              const Argument(Name('reason'), StringValue('Use another')),
            ],
          ),
        ],
      );
      final schema = Schema(directives: [directive]);
      Map<String, Object?> writtenWith(IntrospectionQuery query) {
        final json = schema.toIntrospection(query).toJson()['__schema']!;
        return listOf((json as Map<String, Object?>)['directives']).first;
      }

      expect(
        writtenWith(IntrospectionQuery.full),
        isNot(contains('isDeprecated')),
      );
      expect(
        writtenWith(
          const IntrospectionQuery(includesDirectiveDeprecation: true),
        ),
        containsPair('deprecationReason', 'Use another'),
      );
    });

    test('rejects a reference to a type the schema lacks', () {
      expect(
        () => Built('type Query { a: Missing }').schema.toIntrospection(),
        throwsArgumentError,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_writer_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+0 -1: Some tests failed.`; the first messages: `Error: The method 'toIntrospection' isn't defined for the type 'Schema'.`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../../protocol/json_value.dart';
import '../build/built_ins.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import '../relations/type_comparator.dart';
import '../schema.dart';
import 'introspection_query.dart';
import 'type_writer.dart';

/// Writes a schema as the `data` of its answer to an [IntrospectionQuery]
/// (graphql-js's `introspectionFromSchema`), without executing the query.
///
/// Types are listed in declaration order, then the built-in scalars the
/// schema references (`String` and `Boolean` always, as introspection
/// does; spec §3.5), then the introspection types. Directives are listed
/// in declaration order, then the built-in ones the schema did not
/// redefine.
final class IntrospectionWriter(
  /// The schema written.
  final Schema schema,

  /// The query whose answer is written.
  final IntrospectionQuery query,
) {
  /// Creates a writer.
  this;

  final TypeWriter _types = TypeWriter(schema, query);

  /// `{"__schema": {...}}`.
  ///
  /// A reference to a type the schema lacks is an [ArgumentError]:
  /// introspection describes a schema that validation accepts.
  JsonObject write() => JsonObject({
    '__schema': JsonObject({
      if (query.includesSchemaDescription && query.includesDescriptions)
        'description': switch (schema.description) {
          final description? => JsonString(description),
          null => const JsonNull(),
        },
      'queryType': _root(schema.queryTypeName),
      'mutationType': _root(schema.mutationTypeName),
      'subscriptionType': _root(schema.subscriptionTypeName),
      'types': JsonArray([
        for (final type in _listedTypes()) _types.type(type),
      ]),
      'directives': JsonArray([
        for (final directive in _listedDirectives()) _directive(directive),
      ]),
    }),
  });

  JsonValue _root(String? name) => switch (name) {
    final name? => JsonObject({
      'name': JsonString(name),
      'kind': JsonString(_types.references.kindNamed(name)),
    }),
    null => const JsonNull(),
  };

  List<SchemaType> _listedTypes() {
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
      for (final directive in _listedDirectives())
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

  List<SchemaDirective> _listedDirectives() {
    const builtIns = BuiltIns();
    return [
      ...schema.directives,
      for (final directive in [
        ...builtIns.directives,
        builtIns.defer,
        builtIns.stream,
      ])
        if (identical(schema.directiveNamed(directive.name), directive))
          directive,
    ];
  }

  JsonObject _directive(SchemaDirective directive) => JsonObject({
    'name': JsonString(directive.name),
    if (query.includesDescriptions)
      'description': switch (directive.description) {
        final description? => JsonString(description),
        null => const JsonNull(),
      },
    if (query.includesDirectiveIsRepeatable)
      'isRepeatable': JsonBool(directive.isRepeatable),
    if (query.includesDirectiveDeprecation)
      ..._types.deprecation(directive.deprecationReason),
    'locations': JsonArray([
      for (final location in directive.locations) JsonString(location.spelling),
    ]),
    'args': _types.inputValues(directive.arguments),
  });
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/type_ref_writer.dart`:

```dart
import '../../language/ast/name.dart';
import '../../language/ast/type_ref.dart';
import '../../protocol/json_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';

/// Writes type references as the introspection query's `TypeRef` fragment
/// reads them: `kind`, `name` and `ofType`, [typeDepth] levels deep.
final class TypeRefWriter(
  /// The schema whose types the references name.
  final Schema schema,

  /// How many `ofType` levels a reference has.
  final int typeDepth,
) {
  /// Creates a writer.
  this;

  /// [type] with its wrappers as nested `ofType` objects; a wrapper below
  /// [typeDepth] levels has no `ofType` key, as the query does not read it.
  ///
  /// A named type the schema lacks is an [ArgumentError]: introspection
  /// describes a valid schema.
  JsonObject reference(TypeRef type) {
    final levels = <TypeRef>[];
    for (
      TypeRef? level = type;
      level != null && levels.length <= typeDepth;
      level = _wrapped(level)
    ) {
      levels.add(level);
    }
    // Built from the innermost level out, so nesting needs no recursion.
    var result = _level(levels.last, levels.length - 1, null);
    for (var depth = levels.length - 2; depth >= 0; depth--) {
      result = _level(levels[depth], depth, result);
    }
    return result;
  }

  /// The type named [name] as a reference, as the query reads an
  /// implemented interface or a possible type.
  JsonObject named(String name) => reference(NamedType(Name(name)));

  /// The `__TypeKind` value of [type].
  String kindOf(SchemaType type) => switch (type) {
    ScalarType() => 'SCALAR',
    ObjectType() => 'OBJECT',
    InterfaceType() => 'INTERFACE',
    UnionType() => 'UNION',
    EnumType() => 'ENUM',
    InputObjectType() => 'INPUT_OBJECT',
  };

  /// The kind of the type named [name]; an [ArgumentError] when the schema
  /// has no such type.
  String kindNamed(String name) => switch (schema.typeNamed(name)) {
    final type? => kindOf(type),
    null => throw ArgumentError.value(
      name,
      'name',
      'is not a type of the schema; validate the schema first',
    ),
  };

  // [inner] is the level below, null below a named type or at the cut.
  JsonObject _level(TypeRef type, int depth, JsonObject? inner) {
    final (kind, name) = _kindAndName(type);
    return JsonObject({
      'kind': JsonString(kind),
      'name': name == null ? const JsonNull() : JsonString(name),
      if (depth < typeDepth) 'ofType': inner ?? const JsonNull(),
    });
  }

  TypeRef? _wrapped(TypeRef type) => switch (type) {
    NamedType() => null,
    ListType(:final type) || NonNullType(:final type) => type,
  };

  (String, String?) _kindAndName(TypeRef type) => switch (type) {
    NamedType(:final name) => (kindNamed(name.value), name.value),
    ListType() => ('LIST', null),
    NonNullType() => ('NON_NULL', null),
  };
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/type_writer.dart`:

```dart
import '../../language/printer/printer.dart';
import '../../protocol/json_value.dart';
import '../model/input_value.dart';
import '../model/named_type_reference.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'introspection_query.dart';
import 'type_ref_writer.dart';

/// Writes named types as the introspection query's `FullType` fragment
/// reads them, and arguments and input fields as its `InputValue`
/// fragment does (spec §4.2).
///
/// Only the fields [query] reads are written, in the query's order; a
/// field that does not apply to a kind is `null`, as introspection
/// answers.
final class TypeWriter(
  /// The schema the types belong to.
  final Schema schema,

  /// The query whose answer is written.
  final IntrospectionQuery query,
) {
  /// Creates a writer.
  this;

  /// The writer of the type references inside a type.
  final TypeRefWriter references = TypeRefWriter(schema, query.typeDepth);

  /// [type] as `FullType`.
  JsonObject type(SchemaType type) => JsonObject({
    'kind': JsonString(references.kindOf(type)),
    'name': JsonString(type.name),
    if (query.includesDescriptions) 'description': _text(type.description),
    if (query.includesSpecifiedByUrl)
      'specifiedByURL': _text(type is ScalarType ? type.specifiedByUrl : null),
    if (query.includesOneOf)
      'isOneOf': type is InputObjectType
          ? JsonBool(type.isOneOf)
          : const JsonNull(),
    ..._members(type),
  });

  // The members of each kind; null for the kinds without them.
  Map<String, JsonValue> _members(SchemaType type) => {
    'fields': switch (type) {
      ObjectType(:final fields) || InterfaceType(:final fields) => JsonArray([
        for (final field in fields) _field(field),
      ]),
      _ => const JsonNull(),
    },
    'inputFields': switch (type) {
      InputObjectType(:final fields) => inputValues(fields),
      _ => const JsonNull(),
    },
    'interfaces': switch (type) {
      ObjectType(:final interfaces) ||
      InterfaceType(:final interfaces) => _named(interfaces),
      _ => const JsonNull(),
    },
    'enumValues': switch (type) {
      EnumType(:final values) => JsonArray(values.map(_enumValue).toList()),
      _ => const JsonNull(),
    },
    'possibleTypes': switch (type) {
      InterfaceType() || UnionType() => JsonArray([
        for (final possible in schema.possibleTypes(type))
          references.named(possible.name),
      ]),
      _ => const JsonNull(),
    },
  };

  /// [values] as `InputValue`s; without input value deprecation in the
  /// query, the deprecated ones are left out, as `includeDeprecated: false`
  /// leaves them out.
  JsonArray inputValues(List<InputValue> values) => JsonArray([
    for (final value in values)
      if (query.includesInputValueDeprecation ||
          value.deprecationReason == null)
        _inputValue(value),
  ]);

  JsonObject _inputValue(InputValue value) => JsonObject({
    'name': JsonString(value.name),
    if (query.includesDescriptions) 'description': _text(value.description),
    'type': references.reference(value.type),
    'defaultValue': _text(switch (value.defaultValue) {
      final defaultValue? => const Printer().print(defaultValue),
      null => null,
    }),
    if (query.includesInputValueDeprecation)
      ...deprecation(
        value.deprecationReason,
      ),
  });

  JsonObject _field(SchemaField field) => JsonObject({
    'name': JsonString(field.name),
    if (query.includesDescriptions) 'description': _text(field.description),
    'args': inputValues(field.arguments),
    'type': references.reference(field.type),
    ...deprecation(field.deprecationReason),
  });

  JsonObject _enumValue(SchemaEnumValue value) => JsonObject({
    'name': JsonString(value.name),
    if (query.includesDescriptions) 'description': _text(value.description),
    ...deprecation(value.deprecationReason),
  });

  /// `isDeprecated` and `deprecationReason` of an element deprecated for
  /// [reason], or not deprecated when [reason] is null.
  Map<String, JsonValue> deprecation(String? reason) => {
    'isDeprecated': JsonBool(reason != null),
    'deprecationReason': _text(reason),
  };

  JsonArray _named(List<NamedTypeReference> references) => JsonArray([
    for (final reference in references) this.references.named(reference.name),
  ]);

  JsonValue _text(String? text) =>
      text == null ? const JsonNull() : JsonString(text);
}
```

In `packages/typed_graphql/lib/src/schema/schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,7 +1,10 @@
 import '../diagnostics/source_span.dart';
 import '../language/ast/operation_type.dart';
 import '../language/ast/type_ref.dart';
+import '../protocol/json_value.dart';
 import 'build/built_ins.dart';
+import 'introspection/introspection_query.dart';
+import 'introspection/introspection_writer.dart';
 import 'model/applied_directive.dart';
 import 'model/schema_directive.dart';
 import 'model/schema_type.dart';
@@ -117,6 +120,16 @@ final class Schema({
     .subscription => subscriptionTypeName,
   };
 
+  /// This schema as the `data` of its answer to [query] (graphql-js's
+  /// `introspectionFromSchema`; spec §4), which `SchemaBuilder`'s
+  /// `fromIntrospection` reads back.
+  ///
+  /// It describes a schema that validation accepts: a reference to a type
+  /// the schema lacks is an [ArgumentError].
+  JsonObject toIntrospection([
+    IntrospectionQuery query = IntrospectionQuery.full,
+  ]) => IntrospectionWriter(this, query).write();
+
   /// The named type inside [type]'s wrappers; null when no type has its
   /// name.
   SchemaType? namedTypeOf(TypeRef type) =>
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_writer_test.dart)
```

Expected: `typed_graphql` `+13: All tests passed!`.

- [ ] **Step 5: Update the guides**

In `packages/typed_graphql/doc/introspection.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -34,3 +34,53 @@ query IntrospectionQuery {
 true
 false
 ```
+
+## Answering from a schema
+
+`schema.toIntrospection(query)` writes the `data` a server answers the query
+with, as a `JsonObject`. It writes only the fields the query reads, so the
+answer to a narrower query is smaller. A union lists every member as a
+possible type, even one that is not an object type, so the validator still
+sees it on the client. Introspect a validated schema: a reference to a type
+the schema does not have is an `ArgumentError`.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  final source = Source('''
+type Query { hero: Character }
+interface Character { name: String! }
+type Droid implements Character { name: String! }
+''');
+  final document = const Parser().parse(source).requireDocument();
+  final schema = switch (const SchemaBuilder().fromSdl(document)) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
+  };
+
+  final result = schema.toIntrospection();
+  if (result.fields['__schema'] case JsonObject(:final fields)) {
+    print(fields['queryType']);
+    if (fields['types'] case JsonArray(:final items)) {
+      for (final type in items) {
+        if (type case JsonObject(
+          fields: {
+            'name': JsonString(value: final name),
+            'possibleTypes': JsonArray(items: final possible),
+          },
+        )) {
+          print('$name: $possible');
+        }
+      }
+    }
+  }
+}
+```
+
+It prints:
+
+```text
+{"name":"Query","kind":"OBJECT"}
+Character: [{"kind":"OBJECT","name":"Droid","ofType":null}]
+```
````

- [ ] **Step 6: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+236: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 7: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -253,6 +253,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `text` writes the operation and its three fragments line by line (the
   `ofType` levels with a loop). `full` is every September2025 field:
   directive deprecation is working-draft and stays off.
+  `Schema.toIntrospection` runs `IntrospectionWriter` (the `__schema`
+  object, which types and directives are listed), `TypeWriter` (`FullType`
+  and `InputValue`, only the fields the query reads) and `TypeRefWriter`
+  (`TypeRef`, built from the innermost level out, cut at `typeDepth`);
+  an unknown type is an `ArgumentError`, not a guessed kind.
 - `validation/SchemaValidator` (const): `validate(schema)` returns the
   sealed `SchemaValidationResult` (`ValidSchema` | `InvalidSchema(schema,
   diagnostics)`); `ValidSchema` has a private constructor and
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `Schema.toIntrospection([query])` writes the schema as the `data` of its
  answer to an `IntrospectionQuery` (graphql-js's
  `introspectionFromSchema`), `IntrospectionQuery.full` by default: the
  declared types, the built-in scalars they use, then the introspection
  types; the declared directives, then the built-in ones. A reference to
  a type the schema lacks is an `ArgumentError`.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/introspection.md packages/typed_graphql/lib/src/schema/introspection/introspection_writer.dart packages/typed_graphql/lib/src/schema/introspection/type_ref_writer.dart packages/typed_graphql/lib/src/schema/introspection/type_writer.dart packages/typed_graphql/lib/src/schema/schema.dart packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart
git commit -q -m "feat(typed_graphql): write a schema as its introspection result" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 15: Build a schema from an introspection result

Ruling 2: `SchemaBuilder.fromIntrospection(JsonValue)` returns the sealed `BuildResult`; a structural problem is a `GQL150`–`GQL155` diagnostic whose message starts with the JSON path. Kinds are left to the validator (decision 7), built-ins stay built-in (decision 8), `@deprecated` comes back without its default reason (decision 9).

**Memory (decision 10).** `IntrospectionObject` keeps its parent and its step, and builds the path only when it reports. The first version copied the path at every level: a 100000-level `ofType` chain took about 22 GB and the kernel killed the test run. Run `introspection_reader_test.dart` alone first, under the limits, with `/usr/bin/time -v`: its peak is about 220 MB.

The Introspection guide gains "Reading an answer".

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/introspection/directive_definition_reader.dart`, `packages/typed_graphql/lib/src/schema/introspection/introspection_annotations.dart`, `packages/typed_graphql/lib/src/schema/introspection/introspection_object.dart`, `packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart`, `packages/typed_graphql/lib/src/schema/introspection/member_reader.dart`, `packages/typed_graphql/lib/src/schema/introspection/named_type_reader.dart`, `packages/typed_graphql/lib/src/schema/introspection/type_ref_reader.dart`
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-10-14-m3-type-system-design.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/introspection.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`, `packages/typed_graphql/lib/src/schema/introspection/type_writer.dart`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql/test/schema/introspection/introspection_reader_test.dart`, `packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/introspection_from_schema_test.dart`

**Interfaces:**
- Consumes: Task 14 (`toIntrospection`, `TypeWriter`), M3a `SchemaBuilder`, `BuildResult`, `BuiltIns`, the language `Parser` (default values are parsed as constants).
- Produces:
```text
BuildResult SchemaBuilder.fromIntrospection(JsonValue result)
internal:
  IntrospectionReader(DiagnosticSink sink) { Schema read(JsonValue result) }
  IntrospectionObject(JsonObject json, DiagnosticSink sink, {IntrospectionObject? parent, List<PathSegment> steps})
    { List<PathSegment> get path; String? string(String key, {String? what}); String? optionalString(String key);
      bool flag(String key); IntrospectionObject? optionalObject(String key);
      List<IntrospectionObject>? list(String key, {String? what}); List<IntrospectionObject>? optionalList(String key);
      List<(int, String)>? strings(String key, {String? what});
      void report(DiagnosticCode code, String message, {List<PathSegment> inside}) }
  NamedTypeReader(MemberReader members) { SchemaType? read(IntrospectionObject type) }
  MemberReader(TypeRefReader types) { fields, inputValues, enumValues }
  DirectiveDefinitionReader(MemberReader members) { SchemaDirective? read(IntrospectionObject directive) }
  TypeRefReader(Set<String> knownNames) { TypeRef? read(IntrospectionObject owner, String key); String? named(IntrospectionObject reference) }
  final class const IntrospectionAnnotations() { deprecated, specifiedBy, oneOf }  // -> List<AppliedDirective>
DiagnosticCode: GQL150 invalidIntrospectionResult, GQL151 missingIntrospectionMember, GQL152 unknownIntrospectionKind,
  GQL153 malformedIntrospectionMember, GQL154 unknownIntrospectionType, GQL155 introspectionTypeTooDeep
mapping_test.dart: `covered` gains utilities/__tests__/introspectionFromSchema-test.ts
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/introspection/introspection_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  /// The result of building [result] from introspection.
  BuildResult fromJson(Object? result) => const SchemaBuilder()
      .fromIntrospection(switch (const JsonReader().read(result)) {
        DecodeSuccess(:final value) => value,
        DecodeFailure() => throw StateError('not JSON: $result'),
      });

  /// The messages of the diagnostics of [result].
  List<String> messagesOf(BuildResult result) => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.code.id} ${diagnostic.message}',
  ];

  /// [sdl] written as introspection, as plain Dart objects to edit.
  Map<String, Object?> introspectionOf(String sdl) =>
      Built(sdl).schema.toIntrospection().toJson();

  /// The `__schema.types` entry of [json] named [name].
  Map<String, Object?> typeIn(Map<String, Object?> json, String name) {
    final schema = json['__schema']! as Map<String, Object?>;
    return (schema['types']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((type) => type['name'] == name);
  }

  group('SchemaBuilder.fromIntrospection', () {
    test('reads back what toIntrospection writes', () {
      const sdl = '''
"""A schema"""
schema {
  query: Root
}

directive @tag(name: String = "x") repeatable on FIELD_DEFINITION | QUERY

scalar Url @specifiedBy(url: "https://example.com")

type Root implements Node {
  id: ID!
  items(first: Int = 10, after: String @deprecated): [Item!]! @deprecated(reason: "Use edges")
  url: Url
}

interface Node {
  id: ID!
}

union Item = Root

enum Color {
  RED
  GREEN @deprecated
}

input Filter @oneOf {
  color: Color
  ids: [ID!]
}''';
      final schema = Built(sdl).schema;
      final result = fromJson(schema.toIntrospection().toJson());
      final rebuilt = (result as BuildSuccess).schema;
      expect(const SchemaPrinter().print(rebuilt), sdl);
    });

    test('leaves the built-in types and directives undeclared', () {
      final result = fromJson(introspectionOf('type Query { a: Int }'));
      final schema = (result as BuildSuccess).schema;
      expect(schema.types.map((type) => type.name), ['Query']);
      expect(schema.directives, isEmpty);
    });

    test('turns on @defer and @stream when the result lists them', () {
      final schema = const SchemaBuilder(
        includesDeferAndStream: true,
      ).fromSdl(Sdl('type Query { a: Int }').document);
      final json = (schema as BuildSuccess).schema.toIntrospection().toJson();
      final rebuilt = (fromJson(json) as BuildSuccess).schema;
      expect(rebuilt.includesDeferAndStream, isTrue);
      expect(rebuilt.directives, isEmpty);
    });

    test('rejects a result without __schema', () {
      expect(messagesOf(fromJson({'data': <String, Object?>{}})), [
        r'GQL150 $: Invalid or incomplete introspection result. Ensure that '
            'you are passing "data" property of introspection response and '
            'no "errors" was returned alongside.',
      ]);
    });

    test('reports a missing member with its path', () {
      final json = introspectionOf('type Query { a: Int }');
      typeIn(json, 'Query').remove('fields');
      expect(messagesOf(fromJson(json)), [
        r'GQL151 $.__schema.types[0]: Introspection result missing fields.',
      ]);
    });

    test('reports an unknown kind', () {
      final json = introspectionOf('type Query { a: Int }');
      typeIn(json, 'Query')['kind'] = 'TABLE';
      expect(fromJson(json).diagnostics.single.code.id, 'GQL152');
    });

    test('reports a member of the wrong JSON type', () {
      final json = introspectionOf('type Query { a: Int }');
      typeIn(json, 'Query')['description'] = 3;
      expect(messagesOf(fromJson(json)), [
        r'GQL153 $.__schema.types[0].description: expected a string',
      ]);
    });

    test('reports a default value that does not parse', () {
      final json = introspectionOf('type Query { a(b: Int = 1): Int }');
      final field =
          (typeIn(json, 'Query')['fields']! as List<Object?>).single!
              as Map<String, Object?>;
      final argument =
          (field['args']! as List<Object?>).single! as Map<String, Object?>;
      argument['defaultValue'] = r'$var';
      expect(
        fromJson(json).diagnostics.single.message,
        startsWith(
          r'$.__schema.types[0].fields[0].args[0].defaultValue: Default value '
          'is not a constant GraphQL value: ',
        ),
      );
    });

    test('reports an unknown directive location', () {
      final json = introspectionOf(
        'directive @a on FIELD type Query { a: Int }',
      );
      final schema = json['__schema']! as Map<String, Object?>;
      final directive =
          (schema['directives']! as List<Object?>).first!
              as Map<String, Object?>;
      directive['locations'] = ['FIELD', 'NOWHERE'];
      expect(messagesOf(fromJson(json)), [
        r'GQL153 $.__schema.directives[0].locations[1]: Unknown directive '
            'location "NOWHERE".',
      ]);
    });

    test('reports a reference to a type the result does not list', () {
      final json = introspectionOf('type Query { a: Int }');
      final schema = json['__schema']! as Map<String, Object?>;
      (schema['types']! as List<Object?>).removeWhere(
        (type) => (type! as Map<String, Object?>)['name'] == 'Int',
      );
      expect(messagesOf(fromJson(json)), [
        r'GQL154 $.__schema.types[0].fields[0].type: Invalid or incomplete '
            'schema, unknown type: Int. Ensure that a full introspection '
            'query is used in order to build a client schema.',
      ]);
    });

    test('reports a type deeper than the query read', () {
      final schema = Built('type Query { a: [[Int]] }').schema;
      final json = schema.toIntrospection(
        const IntrospectionQuery(typeDepth: 1),
      );
      expect(messagesOf(fromJson(json.toJson())), [
        r'GQL155 $.__schema.types[0].fields[0].type.ofType: Decorated type '
            'deeper than introspection query.',
      ]);
    });

    test('reports a non-null type inside a non-null type', () {
      final json = introspectionOf('type Query { a: Int! }');
      final field =
          (typeIn(json, 'Query')['fields']! as List<Object?>).single!
              as Map<String, Object?>;
      field['type'] = {
        'kind': 'NON_NULL',
        'name': null,
        'ofType': field['type'],
      };
      expect(messagesOf(fromJson(json)), [
        r'GQL153 $.__schema.types[0].fields[0].type: Expected a nullable '
            'type inside NON_NULL.',
      ]);
    });

    test('reads a long ofType chain without recursion', () {
      JsonValue reference = JsonObject({
        'kind': const JsonString('SCALAR'),
        'name': const JsonString('Int'),
        'ofType': const JsonNull(),
      });
      for (var i = 0; i < 10000; i++) {
        reference = JsonObject({
          'kind': const JsonString('LIST'),
          'name': const JsonNull(),
          'ofType': reference,
        });
      }
      final query = JsonObject({
        'kind': const JsonString('OBJECT'),
        'name': const JsonString('Query'),
        'interfaces': JsonArray(const []),
        'fields': JsonArray([
          JsonObject({
            'name': const JsonString('a'),
            'args': JsonArray(const []),
            'type': reference,
          }),
        ]),
      });
      final scalar = JsonObject({
        'kind': const JsonString('SCALAR'),
        'name': const JsonString('Int'),
      });
      final result = JsonObject({
        '__schema': JsonObject({
          'queryType': JsonObject({'name': const JsonString('Query')}),
          'types': JsonArray([query, scalar]),
        }),
      });
      expect(
        const SchemaBuilder().fromIntrospection(result),
        isA<BuildSuccess>(),
      );
    });
  });
}
```

In `packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -147,6 +147,16 @@ void main() {
       expect(typeOf(schema, 'A')['possibleTypes'], isNull);
     });
 
+    test('writes every union member, also one that is not an object', () {
+      final schema = schemaOf('''
+        type Query { a: U }
+        interface I { a: Int }
+        type A { a: Int }
+        union U = A | I
+      ''');
+      expect(namesOf(typeOf(schema, 'U')['possibleTypes']), ['A', 'I']);
+    });
+
     test('writes only the fields the query reads', () {
       final schema = schemaOf(
         '"Q" type Query { a: Int }',
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -74,6 +74,7 @@ void main() {
         'utilities/__tests__/buildASTSchema-test.ts',
         'utilities/__tests__/extendSchema-test.ts',
         'utilities/__tests__/getIntrospectionQuery-test.ts',
+        'utilities/__tests__/introspectionFromSchema-test.ts',
         'utilities/__tests__/printSchema-test.ts',
       ],
     ),
```

Create `packages/typed_graphql_conformance/test/schema/introspection_from_schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/introspectionFromSchema-test.ts.
// graphql-js builds the schemas in code; the port writes them as SDL.
void main() {
  const port = SchemaPort();
  const dedent = Dedent();

  /// graphql-js's `introspectionToSDL`: [introspection] built back into a
  /// schema and printed.
  String introspectionToSdl(JsonObject introspection) =>
      switch (const SchemaBuilder().fromIntrospection(introspection)) {
        BuildSuccess(:final schema) => port.print(schema),
        BuildFailure(:final diagnostics) => fail('$diagnostics'),
      };

  group('introspectionFromSchema', () {
    final schema = port.build('''
"""This is a simple schema"""
schema {
  query: Simple
}

"""This is a simple type"""
type Simple {
  """This is a string field"""
  string: String
}
''');

    test('converts a simple schema', () {
      final introspection = schema.toIntrospection();
      expect(
        introspectionToSdl(introspection),
        dedent('''
          """This is a simple schema"""
          schema {
            query: Simple
          }

          """This is a simple type"""
          type Simple {
            """This is a string field"""
            string: String
          }
        '''),
      );
    });

    test('converts a simple schema without descriptions', () {
      final introspection = schema.toIntrospection(
        const IntrospectionQuery(
          includesDescriptions: false,
          includesSchemaDescription: true,
        ),
      );
      expect(
        introspectionToSdl(introspection),
        dedent('''
          schema {
            query: Simple
          }

          type Simple {
            string: String
          }
        '''),
      );
    });

    // Directive deprecation is working-draft (graphql-js 17), so the
    // query asks for it explicitly and the SDL applies `@deprecated` to a
    // directive definition.
    test('includes deprecated directives', () {
      final withDeprecatedDirective = port.build('''
type Query {
  string: String
}

directive @deprecatedDirective @deprecated(reason: "Use another directive") on QUERY
''');
      final introspection = withDeprecatedDirective.toIntrospection(
        const IntrospectionQuery(includesDirectiveDeprecation: true),
      );
      final directives = switch (introspection.fields['__schema']) {
        JsonObject(fields: {'directives': JsonArray(:final items)}) => items,
        _ => fail('No directives'),
      };
      final deprecatedDirective = directives.whereType<JsonObject>().where(
        (directive) =>
            directive.fields['name'] == const JsonString('deprecatedDirective'),
      );
      expect(deprecatedDirective, hasLength(1));
      expect(deprecatedDirective.single.fields, <String, JsonValue>{
        'name': const JsonString('deprecatedDirective'),
        'description': const JsonNull(),
        'isDeprecated': const JsonBool(true),
        'deprecationReason': const JsonString('Use another directive'),
        'locations': JsonArray(const [JsonString('QUERY')]),
        'args': JsonArray(const []),
      });
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_reader_test.dart test/schema/introspection/introspection_writer_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/introspection_from_schema_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+13 -2: Some tests failed.`; the first messages: `Error: The method 'fromIntrospection' isn't defined for the type 'SchemaBuilder'.`, `Expected: ['A', 'I']`, `Actual: ['A']`. `typed_graphql_conformance` ends with `+32 -2: Some tests failed.`; the first messages: `Error: The method 'fromIntrospection' isn't defined for the type 'SchemaBuilder'.`, `Error: The type 'dynamic' is not exhaustively matched by the switch cases since it doesn't match 'Object()'.`, `Which: does not contain (String, String):<(introspectionFromSchema, converts a simple schema)>`.

- [ ] **Step 3: Write the implementation**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -294,5 +294,33 @@ enum DiagnosticCode(
 
   /// `GQL149`: an input field whose default value contains itself,
   /// directly or through the default values of other fields (spec §3.10).
-  defaultValueCycle('GQL149');
+  defaultValueCycle('GQL149'),
+
+  /// `GQL150`: an introspection result that is not an object with a
+  /// `__schema` object, such as a whole response instead of its `data`
+  /// (spec §4).
+  invalidIntrospectionResult('GQL150'),
+
+  /// `GQL151`: a member an introspection result must have that is
+  /// absent or null, such as the `fields` of an `OBJECT` type (spec §4.2).
+  missingIntrospectionMember('GQL151'),
+
+  /// `GQL152`: a type in an introspection result whose `kind` is absent
+  /// or not a named type kind (spec §4.2.1).
+  unknownIntrospectionKind('GQL152'),
+
+  /// `GQL153`: a member of an introspection result of the wrong JSON
+  /// type, a default value that is not a constant GraphQL value, an
+  /// unknown directive location or a `NON_NULL` inside a `NON_NULL`
+  /// (spec §4.2).
+  malformedIntrospectionMember('GQL153'),
+
+  /// `GQL154`: a type reference in an introspection result to a type its
+  /// `types` do not list: the query was not a full one (spec §4.2).
+  unknownIntrospectionType('GQL154'),
+
+  /// `GQL155`: a list or non-null type reference in an introspection
+  /// result without its `ofType`: the type is deeper than the query read
+  /// (spec §4.2).
+  introspectionTypeTooDeep('GQL155');
 }
```

In `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,8 @@
+import '../../diagnostics/diagnostic_sink.dart';
 import '../../diagnostics/source.dart';
 import '../../language/ast/document.dart';
+import '../../protocol/json_value.dart';
+import '../introspection/introspection_reader.dart';
 import '../schema.dart';
 import 'build_report.dart';
 import 'build_result.dart';
@@ -50,6 +53,25 @@ final class const SchemaBuilder({
     return _result(extended, report);
   }
 
+  /// The schema the `data` of an introspection result describes
+  /// (graphql-js's `buildClientSchema`; spec §4), such as
+  /// `Schema.toIntrospection` writes and a server answers
+  /// `IntrospectionQuery.full` with.
+  ///
+  /// Structural problems are `GQL150` to `GQL155` diagnostics, each
+  /// message led by the JSON path of the problem; the elements they are
+  /// about are left out of the partial schema. Like [fromSdl], it does not
+  /// validate: a field of an input type builds, and schema validation
+  /// reports it. Elements have no span; [includesDeferAndStream] does not
+  /// apply, as the result says whether `@defer` and `@stream` exist.
+  BuildResult fromIntrospection(JsonValue result) {
+    final sink = DiagnosticSink();
+    final schema = IntrospectionReader(sink).read(result);
+    return sink.hasErrors
+        ? BuildFailure(schema, sink.diagnostics)
+        : BuildSuccess(schema);
+  }
+
   BuildResult _result(Schema schema, BuildReport report) => report.hasErrors
       ? BuildFailure(schema, report.diagnostics())
       : BuildSuccess(schema);
```

Create `packages/typed_graphql/lib/src/schema/introspection/directive_definition_reader.dart`:

```dart
import '../../language/ast/directive_location.dart';
import '../../protocol/path_segment.dart';
import '../model/schema_directive.dart';
import 'introspection_annotations.dart';
import 'introspection_object.dart';
import 'member_reader.dart';

/// Reads the directives of an introspection result (graphql-js's
/// `buildDirective`).
final class DirectiveDefinitionReader(
  /// Reads the arguments of the directives.
  final MemberReader members,
) {
  /// Creates a reader.
  this;

  /// The directive [directive] describes; null, after a report, without a
  /// name, `args` or `locations`.
  SchemaDirective? read(IntrospectionObject directive) {
    final name = directive.string('name');
    final arguments = directive.list('args', what: 'directive args');
    final locations = _locations(directive);
    if (name == null || arguments == null || locations == null) {
      return null;
    }
    return SchemaDirective(
      name,
      description: directive.optionalString('description'),
      arguments: members.inputValues(arguments),
      isRepeatable: directive.flag('isRepeatable'),
      locations: locations,
      appliedDirectives: const IntrospectionAnnotations().deprecated(
        directive,
      ),
    );
  }

  /// The `locations` of [directive]; an unknown spelling is reported and
  /// left out.
  List<DirectiveLocation>? _locations(IntrospectionObject directive) {
    final spellings = directive.strings(
      'locations',
      what: 'directive locations',
    );
    if (spellings == null) {
      return null;
    }
    final locations = <DirectiveLocation>[];
    for (final (index, spelling) in spellings) {
      if (DirectiveLocation.named(spelling) case final location?) {
        locations.add(location);
      } else {
        directive.report(
          .malformedIntrospectionMember,
          'Unknown directive location "$spelling".',
          inside: [const PathKey('locations'), PathIndex(index)],
        );
      }
    }
    return locations;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/introspection_annotations.dart`:

```dart
import '../../language/ast/argument.dart';
import '../../language/ast/name.dart';
import '../../language/ast/value.dart';
import '../model/applied_directive.dart';
import '../model/applied_directives.dart';
import 'introspection_object.dart';

/// The applied directives that stand for what introspection reports as
/// fields: `@deprecated`, `@specifiedBy` and `@oneOf` (R2.1 keeps them as
/// directives, so the elements read them as SDL-built ones do).
final class const IntrospectionAnnotations() {
  /// Creates the annotations.
  this;

  /// `@deprecated` when [element] reports `isDeprecated` or a
  /// `deprecationReason`; without an argument for the default reason, as
  /// SDL writes it.
  List<AppliedDirective> deprecated(IntrospectionObject element) {
    final reason = element.optionalString('deprecationReason');
    if (reason == null && !element.flag('isDeprecated')) {
      return const [];
    }
    if (reason == null ||
        reason == AppliedDirectives.defaultDeprecationReason) {
      return [AppliedDirective('deprecated')];
    }
    return [_withString('deprecated', 'reason', reason)];
  }

  /// `@specifiedBy(url:)` when [type] reports a `specifiedByURL`.
  List<AppliedDirective> specifiedBy(IntrospectionObject type) => [
    if (type.optionalString('specifiedByURL') case final url?)
      _withString('specifiedBy', 'url', url),
  ];

  /// `@oneOf` when [type] reports `isOneOf`.
  List<AppliedDirective> oneOf(IntrospectionObject type) => [
    if (type.flag('isOneOf')) AppliedDirective('oneOf'),
  ];

  AppliedDirective _withString(String name, String argument, String text) =>
      AppliedDirective(
        name,
        arguments: [Argument(Name(argument), StringValue(text))],
      );
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/introspection_object.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';

/// One object of an introspection result, read member by member; every
/// problem is reported into [sink] with the JSON path, never thrown.
///
/// A message is the path as JSONPath and graphql-js's message, as a
/// [DecodeFailure] writes it: `$.__schema.types[0]: Introspection result
/// missing fields.` An object keeps only its [parent] and the [steps] from
/// it, so a deep `ofType` chain costs linear memory; the path is built
/// only for a report.
final class IntrospectionObject(
  /// The object.
  final JsonObject json,

  /// Where problems are reported.
  final DiagnosticSink sink, {

  /// The object [json] is inside; null for `__schema`.
  final IntrospectionObject? parent,

  /// The keys and indexes from [parent] (or the root) to [json].
  final List<PathSegment> steps = const [],
}) {
  /// Creates a reader of [json].
  this;

  /// The keys and indexes from the root of the result to [json].
  List<PathSegment> get path {
    final reversed = <PathSegment>[];
    for (IntrospectionObject? at = this; at != null; at = at.parent) {
      reversed.addAll(at.steps.reversed);
    }
    return reversed.reversed.toList();
  }

  /// The string at [key]; null, after a report, when it is absent, null
  /// or not a string. [what] names the member in graphql-js's message.
  String? string(String key, {String? what}) => switch (json[key]) {
    null || JsonNull() => _missing(what ?? key),
    JsonString(:final value) => value,
    _ => _malformed(key, 'expected a string'),
  };

  /// The string at [key]; null when it is absent or null, and, after a
  /// report, when it is not a string.
  String? optionalString(String key) => switch (json[key]) {
    null || JsonNull() => null,
    JsonString(:final value) => value,
    _ => _malformed(key, 'expected a string'),
  };

  /// The boolean at [key]; false when it is absent or null, and, after a
  /// report, when it is not a boolean.
  bool flag(String key) => switch (json[key]) {
    null || JsonNull() => false,
    JsonBool(:final value) => value,
    _ => _malformed<bool>(key, 'expected a boolean') ?? false,
  };

  /// The object at [key]; null when it is absent or null, and, after a
  /// report, when it is not an object.
  IntrospectionObject? optionalObject(String key) => switch (json[key]) {
    null || JsonNull() => null,
    final JsonObject value => IntrospectionObject(
      value,
      sink,
      parent: this,
      steps: [PathKey(key)],
    ),
    _ => _malformed(key, 'expected an object'),
  };

  /// The objects of the array at [key]; null, after a report, when it is
  /// absent, null or not an array. An item that is not an object is
  /// reported and left out. [what] names the member in graphql-js's
  /// message.
  List<IntrospectionObject>? list(String key, {String? what}) {
    if (json[key] case null || JsonNull()) {
      return _missing(what ?? key);
    }
    return optionalList(key);
  }

  /// The objects of the array at [key], as [list] reads them; null when it
  /// is absent or null.
  List<IntrospectionObject>? optionalList(String key) {
    final items = switch (json[key]) {
      null || JsonNull() => null,
      JsonArray(:final items) => items,
      _ => _malformed<List<JsonValue>>(key, 'expected an array'),
    };
    if (items == null) {
      return null;
    }
    final objects = <IntrospectionObject>[];
    for (final (index, item) in items.indexed) {
      final steps = [PathKey(key), PathIndex(index)];
      if (item case final JsonObject object) {
        objects.add(
          IntrospectionObject(object, sink, parent: this, steps: steps),
        );
      } else {
        report(
          .malformedIntrospectionMember,
          'expected an object',
          inside: steps,
        );
      }
    }
    return objects;
  }

  /// The strings of the array at [key], each with its index; null, after
  /// a report, when it is absent, null or not an array. An item that is
  /// not a string is reported and left out. [what] names the member in
  /// graphql-js's message.
  List<(int, String)>? strings(String key, {String? what}) {
    final items = switch (json[key]) {
      null || JsonNull() => _missing<List<JsonValue>>(what ?? key),
      JsonArray(:final items) => items,
      _ => _malformed<List<JsonValue>>(key, 'expected an array'),
    };
    if (items == null) {
      return null;
    }
    final strings = <(int, String)>[];
    for (final (index, item) in items.indexed) {
      if (item case JsonString(:final value)) {
        strings.add((index, value));
      } else {
        report(
          .malformedIntrospectionMember,
          'expected a string',
          inside: [PathKey(key), PathIndex(index)],
        );
      }
    }
    return strings;
  }

  /// Reports [message] with [code] at this object, or [inside] it.
  void report(
    DiagnosticCode code,
    String message, {
    List<PathSegment> inside = const [],
  }) {
    final where = [...path, ...inside];
    final text = DecodeFailure(message, path: where).toString();
    sink.report(Diagnostic(code, .error, text));
  }

  // Each returns null, so a reader can report and give no value in one
  // step.
  T? _missing<T>(String what) {
    report(.missingIntrospectionMember, 'Introspection result missing $what.');
    return null;
  }

  T? _malformed<T>(String key, String message) {
    report(.malformedIntrospectionMember, message, inside: [PathKey(key)]);
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';
import '../build/built_ins.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'directive_definition_reader.dart';
import 'introspection_object.dart';
import 'member_reader.dart';
import 'named_type_reader.dart';
import 'type_ref_reader.dart';

/// Reads the `data` of an introspection result into a schema (graphql-js's
/// `buildClientSchema`), reporting every structural problem into [sink].
///
/// The built-in scalars and introspection types the result lists are the
/// schema's built-ins, not declared types; so are the built-in directives,
/// and `@defer` or `@stream` turn on `includesDeferAndStream`. A result
/// without `directives` has none declared, as graphql-js reads it.
final class IntrospectionReader(
  /// Where problems are reported.
  final DiagnosticSink sink,
) {
  /// Creates a reader.
  this;

  /// The schema [result] describes, with every element that read without
  /// a problem.
  Schema read(JsonValue result) {
    final root = _schemaObject(result);
    if (root == null) {
      return Schema();
    }
    final types = root.list('types') ?? const [];
    final references = TypeRefReader({
      for (final type in types)
        if (type.json['name'] case JsonString(:final value)) value,
    });
    final members = MemberReader(references);
    // In graphql-js's order: types, roots, directives.
    final declaredTypes = [
      for (final type in types)
        if (!_isBuiltInType(type)) ?NamedTypeReader(members).read(type),
    ];
    final (query, mutation, subscription) = (
      _root(root, 'queryType', references),
      _root(root, 'mutationType', references),
      _root(root, 'subscriptionType', references),
    );
    final directives = _directives(root, DirectiveDefinitionReader(members));
    return Schema(
      types: declaredTypes,
      directives: [
        for (final directive in directives)
          if (!_isBuiltInDirective(directive)) directive,
      ],
      queryTypeName: query,
      mutationTypeName: mutation,
      subscriptionTypeName: subscription,
      description: root.optionalString('description'),
      includesDeferAndStream: directives.any(_isDeferOrStream),
    );
  }

  IntrospectionObject? _schemaObject(JsonValue result) {
    if (result case JsonObject(fields: {'__schema': final JsonObject root})) {
      return IntrospectionObject(
        root,
        sink,
        steps: const [PathKey('__schema')],
      );
    }
    const message =
        'Invalid or incomplete introspection result. Ensure that you are '
        'passing "data" property of introspection response and no "errors" '
        'was returned alongside.';
    sink.report(
      Diagnostic(
        .invalidIntrospectionResult,
        .error,
        const DecodeFailure(message).toString(),
      ),
    );
    return null;
  }

  String? _root(IntrospectionObject root, String key, TypeRefReader types) =>
      switch (root.optionalObject(key)) {
        final reference? => types.named(reference),
        null => null,
      };

  List<SchemaDirective> _directives(
    IntrospectionObject root,
    DirectiveDefinitionReader reader,
  ) => [
    for (final directive
        in root.optionalList('directives') ?? const <IntrospectionObject>[])
      ?reader.read(directive),
  ];

  bool _isBuiltInType(IntrospectionObject type) => switch (type.json['name']) {
    JsonString(:final value) => const BuiltIns().typeNamed(value) != null,
    _ => false,
  };

  bool _isBuiltInDirective(SchemaDirective directive) =>
      const BuiltIns().directiveNamed(directive.name) != null ||
      _isDeferOrStream(directive);

  bool _isDeferOrStream(SchemaDirective directive) =>
      directive.name == 'defer' || directive.name == 'stream';
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/member_reader.dart`:

```dart
import '../../diagnostics/source.dart';
import '../../language/ast/value.dart';
import '../../language/parser/parse_element_result.dart';
import '../../language/parser/parser.dart';
import '../../protocol/path_segment.dart';
import '../model/input_value.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import 'introspection_annotations.dart';
import 'introspection_object.dart';
import 'type_ref_reader.dart';

/// Reads the fields, input values and enum values of an introspection
/// result (graphql-js's `buildField`, `buildInputValue` and
/// `buildEnumDef`).
///
/// An element with a problem is reported and left out; its siblings are
/// still read.
final class MemberReader(
  /// Reads the type references of the members.
  final TypeRefReader types,
) {
  /// Creates a reader.
  this;

  static const IntrospectionAnnotations _annotations =
      IntrospectionAnnotations();

  /// The fields of [type]; empty, after a report, without a `fields`
  /// array.
  List<SchemaField> fields(IntrospectionObject type) => [
    for (final field in type.list('fields') ?? const <IntrospectionObject>[])
      ?_field(field),
  ];

  /// The input values in [values]: arguments or input fields.
  List<InputValue> inputValues(List<IntrospectionObject> values) => [
    for (final value in values) ?_inputValue(value),
  ];

  /// The values of the enum [type]; empty, after a report, without an
  /// `enumValues` array.
  List<SchemaEnumValue> enumValues(IntrospectionObject type) => [
    for (final value
        in type.list('enumValues') ?? const <IntrospectionObject>[])
      if (value.string('name') case final name?)
        SchemaEnumValue(
          name,
          description: value.optionalString('description'),
          appliedDirectives: _annotations.deprecated(value),
        ),
  ];

  SchemaField? _field(IntrospectionObject field) {
    final name = field.string('name');
    final type = types.read(field, 'type');
    final arguments = field.list('args', what: 'field args');
    if (name == null || type == null || arguments == null) {
      return null;
    }
    return SchemaField(
      name,
      type,
      description: field.optionalString('description'),
      arguments: inputValues(arguments),
      appliedDirectives: _annotations.deprecated(field),
    );
  }

  InputValue? _inputValue(IntrospectionObject value) {
    final name = value.string('name');
    final type = types.read(value, 'type');
    final defaultValue = _defaultValue(value);
    if (name == null || type == null || defaultValue == null) {
      return null;
    }
    return InputValue(
      name,
      type,
      description: value.optionalString('description'),
      defaultValue: defaultValue.value,
      appliedDirectives: _annotations.deprecated(value),
    );
  }

  /// The parsed `defaultValue` of [element], a null value without one;
  /// null itself, after a report, when it is not a constant GraphQL value.
  ({Value? value})? _defaultValue(IntrospectionObject element) {
    final text = element.optionalString('defaultValue');
    if (text == null) {
      return (value: null);
    }
    final parsed = const Parser().parseValue(Source(text), isConst: true);
    switch (parsed) {
      case ParseElementSuccess(:final value):
        return (value: value);
      case ParseElementFailure(:final diagnostics):
        element.report(
          .malformedIntrospectionMember,
          'Default value is not a constant GraphQL value: '
          '${diagnostics.first.message}',
          inside: const [PathKey('defaultValue')],
        );
        return null;
    }
  }
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/named_type_reader.dart`:

```dart
import '../model/named_type_reference.dart';
import '../model/schema_type.dart';
import 'introspection_annotations.dart';
import 'introspection_object.dart';
import 'member_reader.dart';

/// Reads one type of an introspection result's `types` by its `kind`
/// (graphql-js's `buildType`).
///
/// A type without a member its kind needs is reported and kept with no
/// such members, so references to it still resolve. Kinds are not checked
/// against their uses (a field of an input type, a union member that is
/// not an object): schema validation reports those, as for SDL.
final class NamedTypeReader(
  /// Reads the members of the types.
  final MemberReader members,
) {
  /// Creates a reader.
  this;

  static const IntrospectionAnnotations _annotations =
      IntrospectionAnnotations();

  /// The type [type] describes; null, after a report, without a name or
  /// with a kind that is not a named type kind.
  SchemaType? read(IntrospectionObject type) {
    final name = type.string('name');
    if (name == null) {
      return null;
    }
    final description = type.optionalString('description');
    final kind = type.optionalString('kind');
    switch (kind) {
      case 'SCALAR':
        final directives = _annotations.specifiedBy(type);
        return ScalarType(
          name,
          description: description,
          appliedDirectives: directives,
        );
      case 'OBJECT':
        return ObjectType(
          name,
          description: description,
          interfaces: _references(type.list('interfaces')),
          fields: members.fields(type),
        );
      case 'INTERFACE':
        // graphql-js reads a null `interfaces` of an interface as none,
        // for servers older than interfaces implementing interfaces.
        return InterfaceType(
          name,
          description: description,
          interfaces: _references(type.optionalList('interfaces')),
          fields: members.fields(type),
        );
      default:
        return _other(type, kind, name, description);
    }
  }

  // The kinds without fields, and the unknown ones.
  SchemaType? _other(
    IntrospectionObject type,
    String? kind,
    String name,
    String? text,
  ) {
    switch (kind) {
      case 'UNION':
        final possible = type.list('possibleTypes');
        return UnionType(
          name,
          description: text,
          memberTypes: _references(possible),
        );
      case 'ENUM':
        return EnumType(
          name,
          description: text,
          values: members.enumValues(type),
        );
      case 'INPUT_OBJECT':
        final fields = type.list('inputFields') ?? const [];
        return InputObjectType(
          name,
          description: text,
          fields: members.inputValues(fields),
          appliedDirectives: _annotations.oneOf(type),
        );
      default:
        type.report(
          .unknownIntrospectionKind,
          'Invalid or incomplete introspection result. Ensure that a full '
          'introspection query is used in order to build a client schema.',
        );
        return null;
    }
  }

  List<NamedTypeReference> _references(List<IntrospectionObject>? objects) => [
    for (final object in objects ?? const <IntrospectionObject>[])
      if (members.types.named(object) case final name?)
        NamedTypeReference(name),
  ];
}
```

Create `packages/typed_graphql/lib/src/schema/introspection/type_ref_reader.dart`:

```dart
import '../../language/ast/name.dart';
import '../../language/ast/type_ref.dart';
import '../../protocol/json_value.dart';
import 'introspection_object.dart';

/// Reads the `TypeRef` objects of an introspection result into type
/// references (graphql-js's `getType` in `buildClientSchema`).
///
/// The `ofType` chain is walked with a loop, so a hostile chain cannot
/// overflow the stack.
final class TypeRefReader(
  /// The names the result's `types` list; a reference to another name is
  /// reported, as graphql-js reports it.
  final Set<String> knownNames,
) {
  /// Creates a reader.
  this;

  /// The type at [key] of [owner]; null, after a report, when it is
  /// absent, malformed, deeper than the query read or names an unknown
  /// type.
  TypeRef? read(IntrospectionObject owner, String key) {
    if (owner.json[key] case null || JsonNull()) {
      owner.report(
        .missingIntrospectionMember,
        'Introspection result missing $key.',
      );
      return null;
    }
    final outer = owner.optionalObject(key);
    return outer == null ? null : _build(outer);
  }

  /// The name of the named type [reference] refers to; null, after a
  /// report, when it has none or the result does not list it.
  String? named(IntrospectionObject reference) {
    final name = reference.string('name');
    if (name == null || knownNames.contains(name)) {
      return name;
    }
    reference.report(
      .unknownIntrospectionType,
      'Invalid or incomplete schema, unknown type: $name. Ensure that a '
      'full introspection query is used in order to build a client schema.',
    );
    return null;
  }

  TypeRef? _build(IntrospectionObject outer) {
    final wrappers = <IntrospectionObject>[];
    var level = outer;
    while (_isWrapper(level)) {
      wrappers.add(level);
      if (level.json['ofType'] case null || JsonNull()) {
        level.report(
          .introspectionTypeTooDeep,
          'Decorated type deeper than introspection query.',
        );
        return null;
      }
      if (level.optionalObject('ofType') case final inner?) {
        level = inner;
      } else {
        return null;
      }
    }
    final name = named(level);
    return name == null ? null : _wrap(NamedType(Name(name)), wrappers);
  }

  bool _isWrapper(IntrospectionObject level) =>
      switch (level.optionalString('kind')) {
        'LIST' || 'NON_NULL' => true,
        _ => false,
      };

  // Wraps from the innermost wrapper out.
  TypeRef? _wrap(TypeRef named, List<IntrospectionObject> wrappers) {
    var type = named;
    for (final wrapper in wrappers.reversed) {
      if (wrapper.optionalString('kind') == 'LIST') {
        type = ListType(type);
      } else if (type is NonNullType) {
        wrapper.report(
          .malformedIntrospectionMember,
          'Expected a nullable type inside NON_NULL.',
        );
        return null;
      } else {
        type = NonNullType(type);
      }
    }
    return type;
  }
}
```

In `packages/typed_graphql/lib/src/schema/introspection/type_writer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -65,10 +65,13 @@ final class TypeWriter(
       _ => const JsonNull(),
     },
     'possibleTypes': switch (type) {
-      InterfaceType() || UnionType() => JsonArray([
+      InterfaceType() => JsonArray([
         for (final possible in schema.possibleTypes(type))
           references.named(possible.name),
       ]),
+      // Every member, as graphql-js writes them, so that a member that is
+      // not an object survives the round trip to the validator.
+      UnionType(:final memberTypes) => _named(memberTypes),
       _ => const JsonNull(),
     },
   };
```

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -282,3 +282,6 @@ utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,include
 utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""isDeprecated"" field on directives",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
 utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,"include ""deprecationReason"" field on directives",adapted,test/schema/introspection_query_test.dart,"operation validation arrives in M4, so the query is parsed instead of validated"
 utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,throw error if typeDepth is too high,ported,test/schema/introspection_query_test.dart,
+utilities/__tests__/introspectionFromSchema-test.ts,introspectionFromSchema,converts a simple schema,adapted,test/schema/introspection_from_schema_test.dart,the schema is written as SDL instead of built in code
+utilities/__tests__/introspectionFromSchema-test.ts,introspectionFromSchema,converts a simple schema without descriptions,adapted,test/schema/introspection_from_schema_test.dart,the schema is written as SDL instead of built in code
+utilities/__tests__/introspectionFromSchema-test.ts,introspectionFromSchema,includes deprecated directives,adapted,test/schema/introspection_from_schema_test.dart,"directive deprecation is working-draft, so the query asks for it (includesDirectiveDeprecation) and the SDL applies @deprecated to the directive definition"
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/introspection/introspection_reader_test.dart test/schema/introspection/introspection_writer_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/introspection_from_schema_test.dart)
```

Expected: `typed_graphql` `+27: All tests passed!`, `typed_graphql_conformance` `+36: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+639: All tests passed!`.

- [ ] **Step 5: Update the guides**

In `packages/typed_graphql/doc/introspection.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -84,3 +84,71 @@ It prints:
 {"name":"Query","kind":"OBJECT"}
 Character: [{"kind":"OBJECT","name":"Droid","ofType":null}]
 ```
+
+## Reading an answer
+
+`SchemaBuilder().fromIntrospection(json)` builds a schema from an answer and
+returns a `BuildResult`, like `fromSdl`. The built-in scalars, directives and
+introspection types in the answer stay built-in, and `@deprecated` comes back
+as written, so SDL printed from the schema matches the server's.
+
+A broken answer (a missing field, a value of the wrong JSON type, an unknown
+kind, a reference to a type the answer does not list, an `ofType` chain deeper
+than the query reads) gives a `GQL150` to `GQL155` diagnostic whose message
+starts with the JSON path of the problem; the elements it is about are left
+out of the partial schema. Like `fromSdl`, it does not validate: a schema from
+a server you do not trust goes through `SchemaValidator` next (see "Validating
+a schema" in the Schema topic).
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  final source = Source('''
+"The entry point."
+type Query {
+  hero(episode: Episode = JEDI): String @deprecated(reason: "Use heroes.")
+  heroes: [String!]!
+}
+
+enum Episode { NEWHOPE EMPIRE JEDI }
+''');
+  final document = const Parser().parse(source).requireDocument();
+  final schema = switch (const SchemaBuilder().fromSdl(document)) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
+  };
+
+  // The server's answer, read back into a schema on the client.
+  final result = schema.toIntrospection();
+  if (const SchemaBuilder().fromIntrospection(result) case BuildSuccess(
+    schema: final client,
+  )) {
+    print(const SchemaPrinter().print(client));
+  }
+
+  // A broken answer: every problem says where it is.
+  const text = '{"__schema": {"queryType": {"name": "Query"}, "types": [{}]}}';
+  if (const JsonReader().parse(text) case DecodeSuccess(:final value)) {
+    const SchemaBuilder().fromIntrospection(value).diagnostics.forEach(print);
+  }
+}
+```
+
+It prints:
+
+```text
+"""The entry point."""
+type Query {
+  hero(episode: Episode = JEDI): String @deprecated(reason: "Use heroes.")
+  heroes: [String!]!
+}
+
+enum Episode {
+  NEWHOPE
+  EMPIRE
+  JEDI
+}
+error GQL151: $.__schema.types[0]: Introspection result missing name.
+error GQL154: $.__schema.queryType: Invalid or incomplete schema, unknown type: Query. Ensure that a full introspection query is used in order to build a client schema.
+```
````

- [ ] **Step 6: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+238: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 7: Update the documents**

Spec §8 and §13 record ruling 2 (finding 3).

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -258,6 +258,14 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   and `InputValue`, only the fields the query reads) and `TypeRefWriter`
   (`TypeRef`, built from the innermost level out, cut at `typeDepth`);
   an unknown type is an `ArgumentError`, not a guessed kind.
+  `SchemaBuilder.fromIntrospection` runs `IntrospectionReader` (the
+  `__schema` object: types, then roots, then directives, as graphql-js
+  reads them) over `IntrospectionObject` (one JSON object and its parent,
+  so the path is built only for a report: a deep `ofType` chain stays
+  linear), `NamedTypeReader`, `MemberReader`, `DirectiveDefinitionReader`
+  and `TypeRefReader` (the `ofType` chain with a loop). Problems are
+  `GQL150`-`GQL155` with the JSON path in the message; kind misuse is
+  left to the validator.
 - `validation/SchemaValidator` (const): `validate(schema)` returns the
   sealed `SchemaValidationResult` (`ValidSchema` | `InvalidSchema(schema,
   diagnostics)`); `ValidSchema` has a private constructor and
```

In `docs/superpowers/specs/2026-10-14-m3-type-system-design.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -137,10 +137,13 @@ in the message.
 - `IntrospectionQuery` generates the query. Options switch the
   working-draft fields (`isOneOf`, `specifiedByUrl`, descriptions of inputs, the
   deprecation of arguments and input fields) on and off.
-- `SchemaBuilder.fromIntrospection(JsonValue)` builds a `Schema`. A malformed
-  response is a `DecodeFailure` with a path; an unknown or inconsistent element
-  is a diagnostic; nothing throws. The result goes through the same sealed
-  `BuildResult` as SDL.
+- `SchemaBuilder.fromIntrospection(JsonValue)` builds a `Schema` and returns
+  the same sealed `BuildResult` as SDL; nothing throws. A malformed response
+  (a missing member, a wrong JSON type, an unknown kind or type, a type deeper
+  than the query read) is a `GQL150`-`GQL155` diagnostic whose message starts
+  with the JSON path, as a `DecodeFailure` prints it (deviation 7). Kind
+  misuse (an input type as a field type, a root of the wrong kind) builds and
+  is left to schema validation.
 - `Schema.toIntrospection()` produces the response (`introspectionFromSchema`).
   Default values are printed as GraphQL literals, as the introspection format
   requires.
@@ -198,6 +201,10 @@ stay green after every task, no allowlist grows.
    language nodes.
 6. The hostile-SDL fuzzer for `fromSdl` / `extend` ships with M3a, the
    introspection and coordinate fuzzers with M3b.
+7. A malformed introspection response is not a `DecodeFailure`: one response
+   can have many problems, so `fromIntrospection` reports them all as
+   diagnostics in its `BuildResult`, with the JSON path in each message (M3b
+   plan, ruling 2).
 7. The printer prints every applied directive as written; graphql-js prints
    only `@deprecated`, `@specifiedBy` and `@oneOf`. SDL to schema to SDL then
    loses nothing.
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `SchemaBuilder.fromIntrospection(result)` builds a schema from the `data`
  of an introspection result (graphql-js's `buildClientSchema`) and returns
  the sealed `BuildResult`: structural problems are `GQL150` to `GQL155`
  diagnostics whose message starts with the JSON path. Built-in types and
  directives in the result stay undeclared; listing `@defer` or `@stream`
  turns on `includesDeferAndStream`.
- `Schema.toIntrospection` lists every member of a union, also one that is
  not an object, so the validator sees it after a round trip.
```

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Ported graphql-js `introspectionFromSchema-test.ts`; the schemas are
  written as SDL.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md docs/superpowers/specs/2026-10-14-m3-type-system-design.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/introspection.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/build/schema_builder.dart packages/typed_graphql/lib/src/schema/introspection/directive_definition_reader.dart packages/typed_graphql/lib/src/schema/introspection/introspection_annotations.dart packages/typed_graphql/lib/src/schema/introspection/introspection_object.dart packages/typed_graphql/lib/src/schema/introspection/introspection_reader.dart packages/typed_graphql/lib/src/schema/introspection/member_reader.dart packages/typed_graphql/lib/src/schema/introspection/named_type_reader.dart packages/typed_graphql/lib/src/schema/introspection/type_ref_reader.dart packages/typed_graphql/lib/src/schema/introspection/type_writer.dart packages/typed_graphql/test/schema/introspection/introspection_reader_test.dart packages/typed_graphql/test/schema/introspection/introspection_writer_test.dart packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/introspection_from_schema_test.dart
git commit -q -m "feat(typed_graphql): build a schema from an introspection result" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 16: Port the graphql-js `buildClientSchema` suite

`utilities/__tests__/buildClientSchema-test.ts`. The cycle tests go SDL → schema → introspection → schema → SDL. The seven "throws" tests about kind misuse become `InvalidSchema` (decision 7, Open question 5); the rest compare `GQL150`–`GQL155` messages.

**Files:**
- Modify: `CLAUDE.md`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/build_client_schema_directives_test.dart`, `packages/typed_graphql_conformance/test/schema/build_client_schema_errors_test.dart`, `packages/typed_graphql_conformance/test/schema/build_client_schema_test.dart`, `packages/typed_graphql_conformance/test/support/introspection_port.dart`

**Interfaces:**
- Consumes: Task 15 (`fromIntrospection`), Task 14 (`toIntrospection`), M3a `SchemaPort`.
- Produces:
```text
test/support/introspection_port.dart: final class IntrospectionPort {
  String cycle(String sdl); Map<String, Object?> introspectionOf(...); Map<String, Object?> schemaIn(...);
  Map<String, Object?> typeIn(...); BuildResult buildResult(Object? introspection);
  Schema client(Object? introspection); List<String> errors(Object? introspection) }
mapping_test.dart: `covered` gains utilities/__tests__/buildClientSchema-test.ts
```

- [ ] **Step 1: Write the ported tests and the coverage entry**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -72,6 +72,7 @@ void main() {
       covered: const [
         'type/__tests__/validation-test.ts',
         'utilities/__tests__/buildASTSchema-test.ts',
+        'utilities/__tests__/buildClientSchema-test.ts',
         'utilities/__tests__/extendSchema-test.ts',
         'utilities/__tests__/getIntrospectionQuery-test.ts',
         'utilities/__tests__/introspectionFromSchema-test.ts',
```

Create `packages/typed_graphql_conformance/test/schema/build_client_schema_directives_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/introspection_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildClientSchema-test.ts,
// the schemas with directives, deprecation, `@specifiedBy` and `@oneOf`.
void main() {
  const port = IntrospectionPort();
  const schemas = SchemaPort();
  const dedent = Dedent();

  group('Type System: build schema from introspection', () {
    test('builds a schema with custom directives', () {
      final sdl = dedent('''
        """This is a custom directive"""
        directive @customDirective repeatable on FIELD

        type Query {
          string: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // Directive deprecation is working-draft: the SDL applies @deprecated
    // to the definition and the query asks for it.
    test('builds a schema with deprecated directives', () {
      final introspection = port.introspectionOf(
        '''
type Query {
  string: String
}

directive @someDirective @deprecated(reason: "Use another directive") on QUERY
''',
        const IntrospectionQuery(includesDirectiveDeprecation: true),
      );
      final directive = port
          .client(introspection)
          .directiveNamed(
            'someDirective',
          );
      expect(directive?.name, 'someDirective');
      expect(directive?.deprecationReason, 'Use another directive');
    });

    // Built-ins are not listed in `Schema.directives`: the port checks the
    // server's result lists directives before it removes them.
    test('builds a schema without directives', () {
      final sdl = dedent('''
        type Query {
          string: String
        }
      ''');
      final introspection = port.introspectionOf(sdl);
      final schema = port.schemaIn(introspection);
      expect(schema['directives'], isNotEmpty);
      schema.remove('directives');
      final client = port.client(introspection);
      expect(client.directives, isEmpty);
      expect(schemas.print(client), sdl);
    });

    test('builds a schema aware of deprecation', () {
      final sdl = dedent('''
        directive @someDirective(
          """This is a shiny new argument"""
          shinyArg: SomeInputObject

          """This was our design mistake :("""
          oldArg: String @deprecated(reason: "Use shinyArg")
        ) on QUERY

        enum Color {
          """So rosy"""
          RED

          """So grassy"""
          GREEN

          """So calming"""
          BLUE

          """So sickening"""
          MAUVE @deprecated(reason: "No longer in fashion")
        }

        input SomeInputObject {
          """Nothing special about it, just deprecated for some unknown reason"""
          oldField: String @deprecated(reason: "Don't use it, use newField instead!")

          """Same field but with a new name"""
          newField: String
        }

        type Query {
          """This is a shiny string field"""
          shinyString: String

          """This is a deprecated string field"""
          deprecatedString: String @deprecated(reason: "Use shinyString")

          """Color of a week"""
          color: Color

          """Some random field"""
          someField(
            """This is a shiny new argument"""
            shinyArg: SomeInputObject

            """This was our design mistake :("""
            oldArg: String @deprecated(reason: "Use shinyArg")
          ): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with empty deprecation reasons', () {
      final sdl = dedent('''
        directive @someDirective(someArg: SomeInputObject @deprecated(reason: "")) on QUERY

        type Query {
          someField(someArg: SomeInputObject @deprecated(reason: "")): SomeEnum @deprecated(reason: "")
        }

        input SomeInputObject {
          someInputField: String @deprecated(reason: "")
        }

        enum SomeEnum {
          SOME_VALUE @deprecated(reason: "")
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with specifiedBy url', () {
      final sdl = dedent('''
        scalar Foo @specifiedBy(url: "https://example.com/foo_spec")

        type Query {
          foo: Foo
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with @oneOf directive', () {
      final sdl = dedent('''
        type Query {
          someField(someArg: SomeInputObject): String
        }

        input SomeInputObject @oneOf {
          someInputField1: String
          someInputField2: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // `assumeValid` has no counterpart: the client schema builds, and
    // the validator reports what is wrong with it.
    test('can build invalid schema', () {
      final introspection = schemas.build('type Query').toIntrospection();
      final client = port.client(introspection);
      expect(schemas.validationErrors(client), [
        'GQL125 Type Query must define one or more fields.',
      ]);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/build_client_schema_errors_test.dart`:

```dart
import 'package:test/test.dart';

import '../support/dedent.dart';
import '../support/introspection_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildClientSchema-test.ts,
// the invalid introspection results. graphql-js throws at the first
// problem; `fromIntrospection` reports each as a diagnostic whose message
// starts with its JSON path instead of ending with the object. A kind
// used in the wrong place builds, and schema validation reports it.
void main() {
  const port = IntrospectionPort();
  const schemas = SchemaPort();
  const dedent = Dedent();

  group('Type System: build schema from introspection', () {
    group('throws when given invalid introspection', () {
      const dummySchema = '''
      type Query {
        foo(bar: String): String
      }

      interface SomeInterface {
        foo: String
      }

      union SomeUnion = Query

      enum SomeEnum { FOO }

      input SomeInputObject {
        foo: String
      }

      directive @SomeDirective on QUERY
    ''';

      /// The result for the dummy schema, as plain objects to edit.
      Map<String, Object?> dummy() => port.introspectionOf(dummySchema);

      test('throws when introspection is missing __schema property', () {
        const message =
            r'GQL150 $: Invalid or incomplete introspection result. Ensure '
            'that you are passing "data" property of introspection response '
            'and no "errors" was returned alongside.';
        expect(port.errors(null), [message]);
        expect(port.errors(<String, Object?>{}), [message]);
      });

      test('throws when referenced unknown type', () {
        final introspection = dummy();
        (port.schemaIn(introspection)['types']! as List).removeWhere(
          (type) => (type! as Map<String, Object?>)['name'] == 'Query',
        );
        const unknown =
            'Invalid or incomplete schema, unknown type: Query. Ensure that a '
            'full introspection query is used in order to build a client '
            'schema.';
        expect(port.errors(introspection), [
          'GQL154 \$.__schema.types[1].possibleTypes[0]: $unknown',
          'GQL154 \$.__schema.queryType: $unknown',
        ]);
      });

      test(
        'throws when missing definition for one of the standard scalars',
        () {
          final introspection = port.introspectionOf(
            'type Query { foo: Float }',
          );
          (port.schemaIn(introspection)['types']! as List).removeWhere(
            (type) => (type! as Map<String, Object?>)['name'] == 'Float',
          );
          expect(port.errors(introspection), [
            r'GQL154 $.__schema.types[0].fields[0].type: Invalid or incomplete '
                'schema, unknown type: Float. Ensure that a full introspection '
                'query is used in order to build a client schema.',
          ]);
        },
      );

      test('throws when type reference is missing name', () {
        final introspection = dummy();
        (port.schemaIn(introspection)['queryType']! as Map).remove('name');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.queryType: Introspection result missing name.',
        ]);
      });

      test('throws when missing kind', () {
        final introspection = dummy();
        port.typeIn(introspection, 'Query').remove('kind');
        expect(port.errors(introspection), [
          r'GQL152 $.__schema.types[0]: Invalid or incomplete introspection '
              'result. Ensure that a full introspection query is used in order '
              'to build a client schema.',
        ]);
      });

      test('throws when missing interfaces', () {
        final introspection = dummy();
        port.typeIn(introspection, 'Query').remove('interfaces');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[0]: Introspection result missing '
              'interfaces.',
        ]);
      });

      test('Legacy support for interfaces with null as interfaces field', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeInterface')['interfaces'] = null;
        expect(
          schemas.print(port.client(introspection)),
          schemas.print(schemas.build(dummySchema)),
        );
      });

      test('throws when missing fields', () {
        final introspection = dummy();
        port.typeIn(introspection, 'Query').remove('fields');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[0]: Introspection result missing fields.',
        ]);
      });

      test('throws when missing field args', () {
        final introspection = dummy();
        final fields = port.typeIn(introspection, 'Query')['fields']! as List;
        (fields.first! as Map).remove('args');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[0].fields[0]: Introspection result '
              'missing field args.',
        ]);
      });

      test('throws when output type is used as an arg type', () {
        final introspection = dummy();
        final fields = port.typeIn(introspection, 'Query')['fields']! as List;
        final argument =
            ((fields.first! as Map)['args']! as List).first! as Map;
        final type = argument['type']! as Map;
        expect(type['name'], 'String');
        type['name'] = 'SomeUnion';
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL127 The type of Query.foo(bar:) must be Input Type but got: '
              'SomeUnion.',
        ]);
      });

      test('throws when input type is used as a field type', () {
        final introspection = dummy();
        final fields = port.typeIn(introspection, 'Query')['fields']! as List;
        final type = (fields.first! as Map)['type']! as Map;
        expect(type['name'], 'String');
        type['name'] = 'SomeInputObject';
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL126 The type of Query.foo must be Output Type but got: '
              'SomeInputObject.',
        ]);
      });

      test('throws when missing possibleTypes', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeUnion').remove('possibleTypes');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[2]: Introspection result missing '
              'possibleTypes.',
        ]);
      });

      test('throws when missing enumValues', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeEnum').remove('enumValues');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[3]: Introspection result missing '
              'enumValues.',
        ]);
      });

      test('throws when missing inputFields', () {
        final introspection = dummy();
        port.typeIn(introspection, 'SomeInputObject').remove('inputFields');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.types[4]: Introspection result missing '
              'inputFields.',
        ]);
      });

      test('throws when missing directive locations', () {
        final introspection = dummy();
        final directives = port.schemaIn(introspection)['directives']! as List;
        final directive = directives.first! as Map;
        expect(directive['name'], 'SomeDirective');
        expect(directive['locations'], ['QUERY']);
        directive.remove('locations');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.directives[0]: Introspection result missing '
              'directive locations.',
        ]);
      });

      test('throws when missing directive args', () {
        final introspection = dummy();
        final directives = port.schemaIn(introspection)['directives']! as List;
        final directive = directives.first! as Map;
        expect(directive['name'], 'SomeDirective');
        expect(directive['args'], isEmpty);
        directive.remove('args');
        expect(port.errors(introspection), [
          r'GQL151 $.__schema.directives[0]: Introspection result missing '
              'directive args.',
        ]);
      });
    });

    group('very deep decorators are not supported', () {
      const tooDeep =
          r'GQL155 $.__schema.types[0].fields[0].type.ofType.ofType.ofType'
          '.ofType.ofType.ofType.ofType.ofType.ofType: Decorated type deeper '
          'than introspection query.';

      test('fails on very deep (> 8 levels) lists', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: [[[[[[[[[[String]]]]]]]]]]
        }
      ''');
        expect(port.errors(introspection), [tooDeep]);
      });

      test('fails on a very deep (> 8 levels) non-null', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: [[[[[String!]!]!]!]!]
        }
      ''');
        expect(port.errors(introspection), [tooDeep]);
      });

      test('succeeds on deep (<= 8 levels) types', () {
        final sdl = dedent('''
        type Query {
          foo: [[[[String!]!]!]!]!
        }
      ''');
        expect(port.cycle(sdl), sdl);
      });
    });

    // graphql-js throws while it builds; the model holds names, so the
    // client schema builds and the validator reports the kind.
    group('prevents infinite recursion on invalid introspection', () {
      test('recursive interfaces', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: Foo
        }

        type Foo implements Foo {
          foo: String
        }
      ''');
        expect(port.typeIn(introspection, 'Foo')['interfaces'], [
          {'kind': 'OBJECT', 'name': 'Foo', 'ofType': null},
        ]);
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL131 Type Foo must only implement Interface types, it cannot '
              'implement Foo.',
        ]);
      });

      test('recursive union', () {
        final introspection = port.introspectionOf('''
        type Query {
          foo: Foo
        }

        union Foo = Foo
      ''');
        expect(port.typeIn(introspection, 'Foo')['possibleTypes'], [
          {'kind': 'UNION', 'name': 'Foo', 'ofType': null},
        ]);
        expect(schemas.validationErrors(port.client(introspection)), [
          'GQL143 Union type Foo can only include Object types, it cannot '
              'include Foo.',
        ]);
      });
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/build_client_schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/introspection_port.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildClientSchema-test.ts,
// the schemas it builds. graphql-js builds some schemas in code; the port
// writes them as SDL. Execution arrives in M5, so the two execution tests
// are skipped.
void main() {
  const port = IntrospectionPort();
  const schemas = SchemaPort();
  const dedent = Dedent();

  group('Type System: build schema from introspection', () {
    test('builds a simple schema', () {
      final sdl = dedent('''
        """Simple schema"""
        schema {
          query: Simple
        }

        """This is a simple type"""
        type Simple {
          """This is a string field"""
          string: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema without the query type', () {
      final sdl = dedent('''
        type Query {
          foo: String
        }
      ''');
      final introspection = port.introspectionOf(sdl);
      port.schemaIn(introspection).remove('queryType');
      final client = port.client(introspection);
      expect(client.queryTypeName, isNull);
      expect(schemas.print(client), sdl);
    });

    test('builds a simple schema with all operation types', () {
      final sdl = dedent('''
        schema {
          query: QueryType
          mutation: MutationType
          subscription: SubscriptionType
        }

        """This is a simple mutation type"""
        type MutationType {
          """Set the string field"""
          string: String
        }

        """This is a simple query type"""
        type QueryType {
          """This is a string field"""
          string: String
        }

        """This is a simple subscription type"""
        type SubscriptionType {
          """This is a string field"""
          string: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // A built-in is found through `typeNamed`, so "used" is identity with
    // the shared `BuiltIns` instance.
    test('uses built-in scalars when possible', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          int: Int
          float: Float
          string: String
          boolean: Boolean
          id: ID
          custom: CustomScalar
        }
      ''');
      expect(port.cycle(sdl), sdl);
      final schema = schemas.build(sdl);
      final client = port.client(schema.toIntrospection());
      for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
        expect(client.typeNamed(name), same(const BuiltIns().typeNamed(name)));
      }
      expect(
        client.typeNamed('CustomScalar'),
        isNot(same(schema.typeNamed('CustomScalar'))),
      );
    });

    // Built-ins are found, not listed (M3a decision 2): the port checks
    // that the result lists no unused scalar and that the client schema
    // declares none.
    test('includes standard types only if they are used', () {
      final introspection = port.introspectionOf('type Query { foo: String }');
      final names = [
        for (final type in port.schemaIn(introspection)['types']! as List)
          (type! as Map<String, Object?>)['name'],
      ];
      expect(names, isNot(contains('Int')));
      expect(names, isNot(contains('Float')));
      expect(names, isNot(contains('ID')));
      final client = port.client(introspection);
      expect(client.types.map((type) => type.name), ['Query']);
    });

    test('builds a schema with a recursive type reference', () {
      final sdl = dedent('''
        schema {
          query: Recur
        }

        type Recur {
          recur: Recur
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with a circular type reference', () {
      final sdl = dedent('''
        type Dog {
          bestFriend: Human
        }

        type Human {
          bestFriend: Dog
        }

        type Query {
          dog: Dog
          human: Human
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with an interface', () {
      final sdl = dedent('''
        type Dog implements Friendly {
          bestFriend: Friendly
        }

        interface Friendly {
          """The best friend of this friendly thing"""
          bestFriend: Friendly
        }

        type Human implements Friendly {
          bestFriend: Friendly
        }

        type Query {
          friendly: Friendly
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with an interface hierarchy', () {
      final sdl = dedent('''
        type Dog implements Friendly & Named {
          bestFriend: Friendly
          name: String
        }

        interface Friendly implements Named {
          """The best friend of this friendly thing"""
          bestFriend: Friendly
          name: String
        }

        type Human implements Friendly & Named {
          bestFriend: Friendly
          name: String
        }

        interface Named {
          name: String
        }

        type Query {
          friendly: Friendly
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with an implicit interface', () {
      final sdl = dedent('''
        type Dog implements Friendly {
          bestFriend: Friendly
        }

        interface Friendly {
          """The best friend of this friendly thing"""
          bestFriend: Friendly
        }

        type Query {
          dog: Dog
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with a union', () {
      final sdl = dedent('''
        type Dog {
          bestFriend: Friendly
        }

        union Friendly = Dog | Human

        type Human {
          bestFriend: Friendly
        }

        type Query {
          friendly: Friendly
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with complex field values', () {
      final sdl = dedent('''
        type Query {
          string: String
          listOfString: [String]
          nonNullString: String!
          nonNullListOfString: [String]!
          nonNullListOfNonNullString: [String!]!
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with field arguments', () {
      final sdl = dedent('''
        type Query {
          """A field with a single arg"""
          one(
            """This is an int arg"""
            intArg: Int
          ): String

          """A field with a two args"""
          two(
            """This is a list of int arg"""
            listArg: [Int]

            """This is a required arg"""
            requiredArg: Boolean!
          ): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with default value on custom scalar field', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          testField(testArg: CustomScalar = "default"): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    // graphql-js gives the server values integers; the model has no
    // internal values, so the port checks names, descriptions and
    // deprecation, as graphql-js does for the client.
    test('builds a schema with an enum', () {
      final introspection = schemas.build('''
"""Varieties of food stuffs"""
enum Food {
  """Foods that are vegetables."""
  VEGETABLES
  FRUITS
  OILS @deprecated(reason: "Too fatty")
}

type EnumFields {
  """Repeats the arg you give it"""
  food("""what kind of food?""" kind: Food): Food
}

schema {
  query: EnumFields
}
''').toIntrospection();
      final client = port.client(introspection);
      expect(client.toIntrospection(), introspection);
      final values = schemas.assertType<EnumType>(client, 'Food').values;
      expect(values, hasLength(3));
      expect(
        [
          for (final value in values)
            (value.name, value.description, value.deprecationReason),
        ],
        [
          ('VEGETABLES', 'Foods that are vegetables.', null),
          ('FRUITS', null, null),
          ('OILS', null, 'Too fatty'),
        ],
      );
    });

    test('builds a schema with an input object', () {
      final sdl = dedent('''
        """An input address"""
        input Address {
          """What street is this address?"""
          street: String!

          """The city the address is within?"""
          city: String!

          """The country (blank will assume USA)."""
          country: String = "USA"
        }

        type Query {
          """Get a geocode from an address"""
          geocode(
            """The address to lookup"""
            address: Address
          ): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('builds a schema with field arguments with default values', () {
      final sdl = dedent('''
        input Geo {
          lat: Float
          lon: Float
        }

        type Query {
          defaultID(intArg: ID = "123"): String
          defaultInt(intArg: Int = 30): String
          defaultList(listArg: [Int] = [1, 2, 3]): String
          defaultObject(objArg: Geo = { lat: 37.485, lon: -122.148 }): String
          defaultNull(intArg: Int = null): String
          noDefault(intArg: Int): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/support/introspection_port.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'schema_port.dart';

/// graphql-js's `buildClientSchema` test helpers: `cycleIntrospection` and
/// introspection results as plain Dart objects a test edits before it
/// builds them, as graphql-js's tests edit the JSON.
final class IntrospectionPort {
  /// Creates the helpers; they keep no state.
  const IntrospectionPort();

  static const SchemaPort _schemas = SchemaPort();

  /// graphql-js's `cycleIntrospection`: [sdl] built, written as
  /// introspection, built back and printed; the client schema must write
  /// the same introspection as the server schema.
  String cycle(String sdl) {
    final initial = _schemas.build(sdl).toIntrospection();
    final client = this.client(initial);
    expect(client.toIntrospection(), initial);
    return _schemas.print(client);
  }

  /// graphql-js's `introspectionFromSchema` on `buildSchema(sdl)`, as plain
  /// maps and lists to edit.
  Map<String, Object?> introspectionOf(
    String sdl, [
    IntrospectionQuery query = IntrospectionQuery.full,
  ]) => _schemas.build(sdl).toIntrospection(query).toJson();

  /// The `__schema` object of [introspection].
  Map<String, Object?> schemaIn(Map<String, Object?> introspection) =>
      introspection['__schema']! as Map<String, Object?>;

  /// The entry of `__schema.types` in [introspection] named [name].
  Map<String, Object?> typeIn(
    Map<String, Object?> introspection,
    String name,
  ) => (schemaIn(introspection)['types']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .singleWhere((type) => type['name'] == name);

  /// [introspection] (a [JsonValue] or plain Dart objects) built.
  BuildResult buildResult(Object? introspection) =>
      const SchemaBuilder().fromIntrospection(switch (introspection) {
        final JsonValue value => value,
        _ => switch (const JsonReader().read(introspection)) {
          DecodeSuccess(:final value) => value,
          DecodeFailure() => fail('Not JSON: $introspection'),
        },
      });

  /// graphql-js's `buildClientSchema`: [introspection] built; fails the
  /// test on a diagnostic.
  Schema client(Object? introspection) => switch (buildResult(introspection)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// The diagnostics of building [introspection], each as its code id and
  /// message.
  List<String> errors(Object? introspection) => [
    for (final diagnostic in buildResult(introspection).diagnostics)
      '${diagnostic.code.id} ${diagnostic.message}',
  ];
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/build_client_schema_directives_test.dart test/schema/build_client_schema_errors_test.dart test/schema/build_client_schema_test.dart)
```

Expected: FAIL. `typed_graphql_conformance` ends with `+79 -1: Some tests failed.`; the first messages: `Which: does not contain (String, String):<(Type System: build schema from introspection, builds a simple schema)>`.

This needs `reference/`.

- [ ] **Step 3: Record the mapping rows**

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -285,3 +285,51 @@ utilities/__tests__/getIntrospectionQuery-test.ts,getIntrospectionQuery,throw er
 utilities/__tests__/introspectionFromSchema-test.ts,introspectionFromSchema,converts a simple schema,adapted,test/schema/introspection_from_schema_test.dart,the schema is written as SDL instead of built in code
 utilities/__tests__/introspectionFromSchema-test.ts,introspectionFromSchema,converts a simple schema without descriptions,adapted,test/schema/introspection_from_schema_test.dart,the schema is written as SDL instead of built in code
 utilities/__tests__/introspectionFromSchema-test.ts,introspectionFromSchema,includes deprecated directives,adapted,test/schema/introspection_from_schema_test.dart,"directive deprecation is working-draft, so the query asks for it (includesDirectiveDeprecation) and the SDL applies @deprecated to the directive definition"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a simple schema,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema without the query type,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a simple schema with all operation types,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,uses built-in scalars when possible,adapted,test/schema/build_client_schema_test.dart,"a built-in is found through typeNamed, so ""used"" is identity with the shared BuiltIns instance"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,includes standard types only if they are used,adapted,test/schema/build_client_schema_test.dart,"built-ins are found, not listed (M3a decision 2): the result lists no unused scalar and the client schema declares none"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with a recursive type reference,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with a circular type reference,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with an interface,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with an interface hierarchy,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with an implicit interface,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with a union,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with complex field values,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with field arguments,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with default value on custom scalar field,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with an enum,adapted,test/schema/build_client_schema_test.dart,"the schema is written as SDL; the model has no internal enum values, so names, descriptions and deprecation are compared"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with an input object,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with field arguments with default values,ported,test/schema/build_client_schema_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with custom directives,ported,test/schema/build_client_schema_directives_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with deprecated directives,adapted,test/schema/build_client_schema_directives_test.dart,directive deprecation is working-draft: the SDL applies @deprecated to the definition and the query asks for it
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema without directives,adapted,test/schema/build_client_schema_directives_test.dart,"built-ins are not listed in Schema.directives, so the port checks that the result listed directives before it removes them"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema aware of deprecation,ported,test/schema/build_client_schema_directives_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with empty deprecation reasons,ported,test/schema/build_client_schema_directives_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with specifiedBy url,ported,test/schema/build_client_schema_directives_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,builds a schema with @oneOf directive,ported,test/schema/build_client_schema_directives_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,can use client schema for limited execution,skipped,,execution arrives in M5
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,can use client schema for execution if resolvers are added,skipped,,the model has no resolvers (R2.1); execution arrives in M5
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection,can build invalid schema,adapted,test/schema/build_client_schema_directives_test.dart,assumeValid has no counterpart: the client schema builds and the validator reports what is wrong (GQL125)
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when introspection is missing __schema property,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when referenced unknown type,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it; every reference to the type is reported"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing definition for one of the standard scalars,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when type reference is missing name,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing kind,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing interfaces,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,Legacy support for interfaces with null as interfaces field,ported,test/schema/build_client_schema_errors_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing fields,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing field args,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when output type is used as an arg type,adapted,test/schema/build_client_schema_errors_test.dart,"the client schema builds and schema validation reports the kind (GQL1xx), as fromIntrospection leaves kinds to the validator"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when input type is used as a field type,adapted,test/schema/build_client_schema_errors_test.dart,"the client schema builds and schema validation reports the kind (GQL1xx), as fromIntrospection leaves kinds to the validator"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing possibleTypes,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing enumValues,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing inputFields,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing directive locations,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > throws when given invalid introspection,throws when missing directive args,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > very deep decorators are not supported,fails on very deep (> 8 levels) lists,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > very deep decorators are not supported,fails on a very deep (> 8 levels) non-null,adapted,test/schema/build_client_schema_errors_test.dart,"a diagnostic (GQL15x) whose message starts with the JSON path instead of ending with the object, as graphql-js throws it"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > very deep decorators are not supported,succeeds on deep (<= 8 levels) types,ported,test/schema/build_client_schema_errors_test.dart,
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > prevents infinite recursion on invalid introspection,recursive interfaces,adapted,test/schema/build_client_schema_errors_test.dart,"the client schema builds and schema validation reports the kind (GQL1xx), as fromIntrospection leaves kinds to the validator"
+utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > prevents infinite recursion on invalid introspection,recursive union,adapted,test/schema/build_client_schema_errors_test.dart,"the client schema builds and schema validation reports the kind (GQL1xx), as fromIntrospection leaves kinds to the validator"
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/build_client_schema_directives_test.dart test/schema/build_client_schema_errors_test.dart test/schema/build_client_schema_test.dart)
```

Expected: `typed_graphql_conformance` `+80: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+686: All tests passed!`.

- [ ] **Step 5: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -462,7 +462,9 @@ that adds API adds its section to the guide of its layer in the same commit.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
 - Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`
   and `mapping/schema.csv`, checked by `test/mapping_test.dart` there; port
-  helpers in its `test/support/` (`SchemaPort` for the schema suites).
+  helpers in its `test/support/` (`SchemaPort` for the schema suites,
+  `ValidationPort` for `validateSchema`, `IntrospectionPort` for
+  `buildClientSchema`).
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
   round trip, hostile SDL); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
   `TYPED_GRAPHQL_FUZZ_SEED` tune them.
```

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Ported graphql-js `buildClientSchema-test.ts` over `IntrospectionPort`
  (`cycleIntrospection` and editable results): a structural problem is a
  `GQL150`-`GQL155` diagnostic with its JSON path, and kind misuse is
  checked with schema validation; the two execution tests wait for M5.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/build_client_schema_directives_test.dart packages/typed_graphql_conformance/test/schema/build_client_schema_errors_test.dart packages/typed_graphql_conformance/test/schema/build_client_schema_test.dart packages/typed_graphql_conformance/test/support/introspection_port.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js buildClientSchema suite" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 17: Resolve schema coordinates against a schema

R2.8, spec §9. `Schema.resolve` gives the element a coordinate names, or `null` for a miss, a container of the wrong kind, a meta-field or an introspection type (decision 11, finding 4). The Schema guide gains "Resolving a coordinate", and the Language guide one sentence that points to it.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/coordinates/coordinate_resolver.dart`, `packages/typed_graphql/lib/src/schema/coordinates/coordinate_target.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/doc/language.md`, `packages/typed_graphql/doc/schema.md`, `packages/typed_graphql/lib/src/schema/schema.dart`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql/test/schema/coordinates/coordinate_resolver_test.dart`, `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/resolve_schema_coordinate_test.dart`

**Interfaces:**
- Consumes: M2 `SchemaCoordinate` family, `Parser.parseSchemaCoordinate`; M3a `Schema`.
- Produces:
```text
sealed class CoordinateTarget                                     // exported; equal when they hold the same elements
  TypeTarget(SchemaType type), FieldTarget(SchemaType type, SchemaField field),
  ArgumentTarget(SchemaType type, SchemaField field, InputValue argument),
  InputFieldTarget(InputObjectType type, InputValue inputField), EnumValueTarget(EnumType type, SchemaEnumValue enumValue),
  DirectiveTarget(SchemaDirective directive), DirectiveArgumentTarget(SchemaDirective directive, InputValue argument)
CoordinateTarget? Schema.resolve(SchemaCoordinate coordinate)
internal: CoordinateResolver(Schema schema) { CoordinateTarget? resolve(SchemaCoordinate coordinate) }
mapping_test.dart: `covered` gains utilities/__tests__/resolveSchemaCoordinate-test.ts
```

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/coordinates/coordinate_resolver_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final schema = Built('''
    type Query {
      search(criteria: Criteria!): [Business]
    }

    interface Node {
      id(format: String): ID
    }

    type Business implements Node {
      id(format: String): ID
      email: String @private(scope: "loggedIn")
    }

    input Criteria {
      filter: Filter
    }

    enum Filter {
      OPEN_NOW
    }

    directive @private(scope: String!) on FIELD_DEFINITION
  ''').schema;

  /// [text] parsed as a schema coordinate and resolved against the schema.
  CoordinateTarget? resolve(String text) =>
      switch (const Parser().parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => schema.resolve(value),
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  final business = schema.typeNamed('Business')! as ObjectType;
  final node = schema.typeNamed('Node')! as InterfaceType;
  final query = schema.typeNamed('Query')! as ObjectType;
  final criteria = schema.typeNamed('Criteria')! as InputObjectType;
  final filter = schema.typeNamed('Filter')! as EnumType;
  final private = schema.directiveNamed('private')!;

  group('Schema.resolve', () {
    test('resolves a declared and a built-in type', () {
      expect(resolve('Business'), TypeTarget(business));
      expect(resolve('String'), TypeTarget(schema.typeNamed('String')!));
    });

    test('resolves the field of an object and of an interface', () {
      expect(
        resolve('Business.email'),
        FieldTarget(business, business.fieldNamed('email')!),
      );
      expect(resolve('Node.id'), FieldTarget(node, node.fieldNamed('id')!));
    });

    test('resolves an input field and an enum value', () {
      expect(
        resolve('Criteria.filter'),
        InputFieldTarget(criteria, criteria.fieldNamed('filter')!),
      );
      expect(
        resolve('Filter.OPEN_NOW'),
        EnumValueTarget(filter, filter.valueNamed('OPEN_NOW')!),
      );
    });

    test('resolves a field argument', () {
      final search = query.fieldNamed('search')!;
      expect(
        resolve('Query.search(criteria:)'),
        ArgumentTarget(query, search, search.argumentNamed('criteria')!),
      );
    });

    test('resolves a declared and a built-in directive and arguments', () {
      expect(resolve('@private'), DirectiveTarget(private));
      expect(
        resolve('@private(scope:)'),
        DirectiveArgumentTarget(private, private.argumentNamed('scope')!),
      );
      final deprecated = schema.directiveNamed('deprecated')!;
      expect(
        resolve('@deprecated(reason:)'),
        DirectiveArgumentTarget(
          deprecated,
          deprecated.argumentNamed('reason')!,
        ),
      );
    });

    test('gives null for an element the schema lacks', () {
      for (final text in [
        'Unknown',
        'private',
        'Business.unknown',
        'Criteria.unknown',
        'Filter.UNKNOWN',
        'Business.id(unknown:)',
        '@unknown',
        '@Business',
        '@private(unknown:)',
      ]) {
        expect(resolve(text), isNull, reason: text);
      }
    });

    // The specification raises an error when a containing element is
    // missing or of the wrong kind; spec §9 keeps every miss a null.
    test('gives null when the containing element is missing or wrong', () {
      for (final text in [
        'Unknown.field',
        'String.field',
        'Unknown.field(arg:)',
        'Business.unknown(arg:)',
        'Criteria.filter(arg:)',
        'Filter.OPEN_NOW(arg:)',
        '@unknown(arg:)',
      ]) {
        expect(resolve(text), isNull, reason: text);
      }
    });

    // September2025 §2.14: meta-fields and introspection types are not
    // schema elements.
    test('gives null for meta-fields and introspection types', () {
      for (final text in [
        'Business.__typename',
        'Query.__type(name:)',
        '__Type',
        '__Directive.name',
        '__DirectiveLocation.INLINE_FRAGMENT',
      ]) {
        expect(resolve(text), isNull, reason: text);
      }
    });

    test('compares targets by the elements they hold', () {
      expect(TypeTarget(business), TypeTarget(business));
      expect(TypeTarget(business).hashCode, TypeTarget(business).hashCode);
      expect(TypeTarget(business), isNot(TypeTarget(query)));
      expect(DirectiveTarget(private), isNot(TypeTarget(business)));
    });
  });
}
```

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -77,6 +77,7 @@ void main() {
         'utilities/__tests__/getIntrospectionQuery-test.ts',
         'utilities/__tests__/introspectionFromSchema-test.ts',
         'utilities/__tests__/printSchema-test.ts',
+        'utilities/__tests__/resolveSchemaCoordinate-test.ts',
       ],
     ),
   ];
```

Create `packages/typed_graphql_conformance/test/schema/resolve_schema_coordinate_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/resolveSchemaCoordinate-test.ts.
// graphql-js throws when an element that contains the coordinate is missing
// or of the wrong kind; `Schema.resolve` gives null (spec §9). Meta-fields
// and introspection types are not schema elements (September2025 §2.14),
// so they resolve to null where graphql-js resolves them.
void main() {
  const port = SchemaPort();
  final schema = port.build('''
  type Query {
    searchBusiness(criteria: SearchCriteria!): [Business]
  }

  input SearchCriteria {
    name: String
    filter: SearchFilter
  }

  enum SearchFilter {
    OPEN_NOW
    DELIVERS_TAKEOUT
    VEGETARIAN_MENU
  }

  type Business {
    id: ID
    name: String
    email: String @private(scope: "loggedIn")
  }

  directive @private(scope: String!) on FIELD_DEFINITION
''');

  /// graphql-js's `resolveSchemaCoordinate(schema, text)`.
  CoordinateTarget? resolveSchemaCoordinate(String text) =>
      switch (const Parser().parseSchemaCoordinate(Source(text))) {
        ParseElementSuccess(:final value) => schema.resolve(value),
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };

  group('resolveSchemaCoordinate', () {
    test('resolves a Named Type', () {
      expect(
        resolveSchemaCoordinate('Business'),
        TypeTarget(schema.typeNamed('Business')!),
      );
      expect(
        resolveSchemaCoordinate('String'),
        TypeTarget(schema.typeNamed('String')!),
      );
      expect(resolveSchemaCoordinate('private'), isNull);
      expect(resolveSchemaCoordinate('Unknown'), isNull);
    });

    test('resolves a Type Field', () {
      final type = port.assertType<ObjectType>(schema, 'Business');
      expect(
        resolveSchemaCoordinate('Business.name'),
        FieldTarget(type, type.fieldNamed('name')!),
      );
      expect(resolveSchemaCoordinate('Business.unknown'), isNull);
      expect(resolveSchemaCoordinate('Unknown.field'), isNull);
      expect(resolveSchemaCoordinate('String.field'), isNull);
    });

    test('resolves a Input Field', () {
      final type = port.assertType<InputObjectType>(schema, 'SearchCriteria');
      expect(
        resolveSchemaCoordinate('SearchCriteria.filter'),
        InputFieldTarget(type, type.fieldNamed('filter')!),
      );
      expect(resolveSchemaCoordinate('SearchCriteria.unknown'), isNull);
    });

    test('resolves a Enum Value', () {
      final type = port.assertType<EnumType>(schema, 'SearchFilter');
      expect(
        resolveSchemaCoordinate('SearchFilter.OPEN_NOW'),
        EnumValueTarget(type, type.valueNamed('OPEN_NOW')!),
      );
      expect(resolveSchemaCoordinate('SearchFilter.UNKNOWN'), isNull);
    });

    test('resolves a Field Argument', () {
      final type = port.assertType<ObjectType>(schema, 'Query');
      final field = type.fieldNamed('searchBusiness')!;
      expect(
        resolveSchemaCoordinate('Query.searchBusiness(criteria:)'),
        ArgumentTarget(type, field, field.argumentNamed('criteria')!),
      );
      expect(resolveSchemaCoordinate('Business.name(unknown:)'), isNull);
      expect(resolveSchemaCoordinate('Unknown.field(arg:)'), isNull);
      expect(resolveSchemaCoordinate('Business.unknown(arg:)'), isNull);
      expect(resolveSchemaCoordinate('SearchCriteria.name(arg:)'), isNull);
    });

    test('resolves a Directive', () {
      expect(
        resolveSchemaCoordinate('@private'),
        DirectiveTarget(schema.directiveNamed('private')!),
      );
      expect(
        resolveSchemaCoordinate('@deprecated'),
        DirectiveTarget(schema.directiveNamed('deprecated')!),
      );
      expect(resolveSchemaCoordinate('@unknown'), isNull);
      expect(resolveSchemaCoordinate('@Business'), isNull);
    });

    test('resolves a Directive Argument', () {
      final directive = schema.directiveNamed('private')!;
      expect(
        resolveSchemaCoordinate('@private(scope:)'),
        DirectiveArgumentTarget(directive, directive.argumentNamed('scope')!),
      );
      expect(resolveSchemaCoordinate('@private(unknown:)'), isNull);
      expect(resolveSchemaCoordinate('@unknown(arg:)'), isNull);
    });
  });

  group('resolveSchemaCoordinate (meta-fields and introspection types)', () {
    test('resolves a meta-field', () {
      expect(resolveSchemaCoordinate('Business.__typename'), isNull);
    });

    test('resolves a meta-field argument', () {
      expect(resolveSchemaCoordinate('Query.__type(name:)'), isNull);
    });

    test('resolves an Introspection Type', () {
      expect(resolveSchemaCoordinate('__Type'), isNull);
    });

    test('resolves an Introspection Type Field', () {
      expect(resolveSchemaCoordinate('__Directive.name'), isNull);
    });

    test('resolves an Introspection Type Enum Value', () {
      expect(
        resolveSchemaCoordinate('__DirectiveLocation.INLINE_FRAGMENT'),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/coordinates/coordinate_resolver_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/resolve_schema_coordinate_test.dart)
```

Expected: FAIL. `typed_graphql` ends with `+0 -1: Some tests failed.`; the first messages: `Error: 'CoordinateTarget' isn't a type.`, `Error: Method not found: 'TypeTarget'.`, `Error: Method not found: 'FieldTarget'.`, `Error: Method not found: 'InputFieldTarget'.`. `typed_graphql_conformance` ends with `+34 -2: Some tests failed.`; the first messages: `Error: 'CoordinateTarget' isn't a type.`, `Error: Method not found: 'TypeTarget'.`, `Error: Method not found: 'FieldTarget'.`, `Error: Method not found: 'InputFieldTarget'.`.

- [ ] **Step 3: Write the implementation**

Create `packages/typed_graphql/lib/src/schema/coordinates/coordinate_resolver.dart`:

```dart
import '../../language/ast/schema_coordinate.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'coordinate_target.dart';

/// Finds the element a schema coordinate names in [schema] (September2025
/// §2.14, "Resolving a Schema Coordinate").
///
/// Where the specification raises an error (a containing element that is
/// missing or of the wrong kind), the result is null too (spec §9): a
/// coordinate is user input. Meta-fields and introspection types are not
/// schema elements, so their coordinates resolve to null.
final class CoordinateResolver(
  /// The schema the coordinates refer to.
  final Schema schema,
) {
  /// Creates a resolver.
  this;

  /// The element [coordinate] names; null when there is none.
  CoordinateTarget? resolve(SchemaCoordinate coordinate) =>
      switch (coordinate) {
        TypeCoordinate(:final name) => switch (_type(name.value)) {
          final type? => TypeTarget(type),
          null => null,
        },
        MemberCoordinate(:final name, :final memberName) => _member(
          name.value,
          memberName.value,
        ),
        ArgumentCoordinate(
          :final name,
          :final fieldName,
          :final argumentName,
        ) =>
          _argument(name.value, fieldName.value, argumentName.value),
        DirectiveCoordinate(:final name) => switch (schema.directiveNamed(
          name.value,
        )) {
          final directive? => DirectiveTarget(directive),
          null => null,
        },
        DirectiveArgumentCoordinate(:final name, :final argumentName) =>
          _directiveArgument(name.value, argumentName.value),
      };

  // An introspection type is not a schema element (§2.14, note).
  SchemaType? _type(String name) =>
      name.startsWith('__') ? null : schema.typeNamed(name);

  CoordinateTarget? _member(String typeName, String memberName) =>
      switch (_type(typeName)) {
        final EnumType type => switch (type.valueNamed(memberName)) {
          final value? => EnumValueTarget(type, value),
          null => null,
        },
        final InputObjectType type => switch (type.fieldNamed(memberName)) {
          final field? => InputFieldTarget(type, field),
          null => null,
        },
        final type? => switch (_fieldOf(type, memberName)) {
          final field? => FieldTarget(type, field),
          null => null,
        },
        null => null,
      };

  CoordinateTarget? _argument(
    String typeName,
    String fieldName,
    String argumentName,
  ) {
    if (_type(typeName) case final type?) {
      if (_fieldOf(type, fieldName) case final field?) {
        if (field.argumentNamed(argumentName) case final argument?) {
          return ArgumentTarget(type, field, argument);
        }
      }
    }
    return null;
  }

  CoordinateTarget? _directiveArgument(String name, String argumentName) {
    if (schema.directiveNamed(name) case final directive?) {
      if (directive.argumentNamed(argumentName) case final argument?) {
        return DirectiveArgumentTarget(directive, argument);
      }
    }
    return null;
  }

  // Only object and interface types have fields; meta-fields are not in
  // the model, so `__typename` finds nothing.
  SchemaField? _fieldOf(SchemaType type, String name) => switch (type) {
    ObjectType() => type.fieldNamed(name),
    InterfaceType() => type.fieldNamed(name),
    _ => null,
  };
}
```

Create `packages/typed_graphql/lib/src/schema/coordinates/coordinate_target.dart`:

```dart
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';

/// The schema element a schema coordinate names (September2025 §2.14), as
/// `Schema.resolve` finds it: one kind per coordinate form, with the
/// elements that contain it.
///
/// Two targets are equal when they are of one kind and hold the same
/// elements; elements compare by identity.
///
/// {@category schema}
sealed class CoordinateTarget {
  /// Creates a target.
  const CoordinateTarget();

  /// The elements it holds, from the outermost in.
  List<Object> get _elements;

  @override
  bool operator ==(Object other) {
    if (other is! CoordinateTarget || other.runtimeType != runtimeType) {
      return false;
    }
    final elements = _elements;
    final others = other._elements;
    for (var index = 0; index < elements.length; index++) {
      if (!identical(elements[index], others[index])) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(_elements));
}

/// A named type, `Business`.
///
/// {@category schema}
final class TypeTarget(
  /// The type.
  final SchemaType type,
) extends CoordinateTarget {
  /// Creates the target of [type].
  this;

  @override
  List<Object> get _elements => [type];
}

/// A field of an object or interface type, `Business.name`.
///
/// {@category schema}
final class FieldTarget(
  /// The object or interface type.
  final SchemaType type,

  /// The field.
  final SchemaField field,
) extends CoordinateTarget {
  /// Creates the target of [field] of [type].
  this;

  @override
  List<Object> get _elements => [type, field];
}

/// An argument of a field, `Query.search(criteria:)`.
///
/// {@category schema}
final class ArgumentTarget(
  /// The object or interface type.
  final SchemaType type,

  /// The field.
  final SchemaField field,

  /// The argument.
  final InputValue argument,
) extends CoordinateTarget {
  /// Creates the target of [argument] of [field] of [type].
  this;

  @override
  List<Object> get _elements => [type, field, argument];
}

/// A field of an input object type, `Criteria.filter`.
///
/// {@category schema}
final class InputFieldTarget(
  /// The input object type.
  final InputObjectType type,

  /// The input field.
  final InputValue inputField,
) extends CoordinateTarget {
  /// Creates the target of [inputField] of [type].
  this;

  @override
  List<Object> get _elements => [type, inputField];
}

/// A value of an enum type, `Filter.OPEN_NOW`.
///
/// {@category schema}
final class EnumValueTarget(
  /// The enum type.
  final EnumType type,

  /// The value.
  final SchemaEnumValue enumValue,
) extends CoordinateTarget {
  /// Creates the target of [enumValue] of [type].
  this;

  @override
  List<Object> get _elements => [type, enumValue];
}

/// A directive, `@private`.
///
/// {@category schema}
final class DirectiveTarget(
  /// The directive.
  final SchemaDirective directive,
) extends CoordinateTarget {
  /// Creates the target of [directive].
  this;

  @override
  List<Object> get _elements => [directive];
}

/// An argument of a directive, `@private(scope:)`.
///
/// {@category schema}
final class DirectiveArgumentTarget(
  /// The directive.
  final SchemaDirective directive,

  /// The argument.
  final InputValue argument,
) extends CoordinateTarget {
  /// Creates the target of [argument] of [directive].
  this;

  @override
  List<Object> get _elements => [directive, argument];
}
```

In `packages/typed_graphql/lib/src/schema/schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,8 +1,11 @@
 import '../diagnostics/source_span.dart';
 import '../language/ast/operation_type.dart';
+import '../language/ast/schema_coordinate.dart';
 import '../language/ast/type_ref.dart';
 import '../protocol/json_value.dart';
 import 'build/built_ins.dart';
+import 'coordinates/coordinate_resolver.dart';
+import 'coordinates/coordinate_target.dart';
 import 'introspection/introspection_query.dart';
 import 'introspection/introspection_writer.dart';
 import 'model/applied_directive.dart';
@@ -130,6 +133,12 @@ final class Schema({
     IntrospectionQuery query = IntrospectionQuery.full,
   ]) => IntrospectionWriter(this, query).write();
 
+  /// The element [coordinate] names (spec §9); null when the schema has
+  /// none, also when an element that contains it is missing or of the
+  /// wrong kind. Meta-fields and introspection types have no coordinate.
+  CoordinateTarget? resolve(SchemaCoordinate coordinate) =>
+      CoordinateResolver(this).resolve(coordinate);
+
   /// The named type inside [type]'s wrappers; null when no type has its
   /// name.
   SchemaType? namedTypeOf(TypeRef type) =>
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,6 +66,7 @@ export 'src/protocol/response_payload.dart';
 export 'src/schema/build/build_result.dart';
 export 'src/schema/build/built_ins.dart';
 export 'src/schema/build/schema_builder.dart';
+export 'src/schema/coordinates/coordinate_target.dart';
 export 'src/schema/introspection/introspection_query.dart';
 export 'src/schema/model/applied_directive.dart';
 export 'src/schema/model/input_value.dart';
```

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -333,3 +333,15 @@ utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from int
 utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > very deep decorators are not supported,succeeds on deep (<= 8 levels) types,ported,test/schema/build_client_schema_errors_test.dart,
 utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > prevents infinite recursion on invalid introspection,recursive interfaces,adapted,test/schema/build_client_schema_errors_test.dart,"the client schema builds and schema validation reports the kind (GQL1xx), as fromIntrospection leaves kinds to the validator"
 utilities/__tests__/buildClientSchema-test.ts,Type System: build schema from introspection > prevents infinite recursion on invalid introspection,recursive union,adapted,test/schema/build_client_schema_errors_test.dart,"the client schema builds and schema validation reports the kind (GQL1xx), as fromIntrospection leaves kinds to the validator"
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Named Type,ported,test/schema/resolve_schema_coordinate_test.dart,
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Type Field,adapted,test/schema/resolve_schema_coordinate_test.dart,a containing element that is missing or of the wrong kind gives null (spec §9) where graphql-js throws
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Input Field,ported,test/schema/resolve_schema_coordinate_test.dart,
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Enum Value,ported,test/schema/resolve_schema_coordinate_test.dart,
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Field Argument,adapted,test/schema/resolve_schema_coordinate_test.dart,a containing element that is missing or of the wrong kind gives null (spec §9) where graphql-js throws
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Directive,ported,test/schema/resolve_schema_coordinate_test.dart,
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate,resolves a Directive Argument,adapted,test/schema/resolve_schema_coordinate_test.dart,a containing element that is missing or of the wrong kind gives null (spec §9) where graphql-js throws
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate (meta-fields and introspection types),resolves a meta-field,adapted,test/schema/resolve_schema_coordinate_test.dart,"meta-fields and introspection types are not schema elements (September2025 §2.14), so the coordinate resolves to null; graphql-js resolves it (implementation-defined)"
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate (meta-fields and introspection types),resolves a meta-field argument,adapted,test/schema/resolve_schema_coordinate_test.dart,"meta-fields and introspection types are not schema elements (September2025 §2.14), so the coordinate resolves to null; graphql-js resolves it (implementation-defined)"
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate (meta-fields and introspection types),resolves an Introspection Type,adapted,test/schema/resolve_schema_coordinate_test.dart,"meta-fields and introspection types are not schema elements (September2025 §2.14), so the coordinate resolves to null; graphql-js resolves it (implementation-defined)"
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate (meta-fields and introspection types),resolves an Introspection Type Field,adapted,test/schema/resolve_schema_coordinate_test.dart,"meta-fields and introspection types are not schema elements (September2025 §2.14), so the coordinate resolves to null; graphql-js resolves it (implementation-defined)"
+utilities/__tests__/resolveSchemaCoordinate-test.ts,resolveSchemaCoordinate (meta-fields and introspection types),resolves an Introspection Type Enum Value,adapted,test/schema/resolve_schema_coordinate_test.dart,"meta-fields and introspection types are not schema elements (September2025 §2.14), so the coordinate resolves to null; graphql-js resolves it (implementation-defined)"
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/schema/coordinates/coordinate_resolver_test.dart)
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/mapping_test.dart test/schema/resolve_schema_coordinate_test.dart)
```

Expected: `typed_graphql` `+9: All tests passed!`, `typed_graphql_conformance` `+47: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+699: All tests passed!`.

- [ ] **Step 5: Update the guides**

In `packages/typed_graphql/doc/language.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -513,6 +513,9 @@ Query.hero(episode:) is the argument episode of Query.hero
 GraphQL request:1:7: error GQL001: Invalid character: " ".
 ```
 
+A coordinate is only text until a schema resolves it: `Schema.resolve` finds the
+element it names (see "Resolving a coordinate" in the Schema topic).
+
 ## Tokens
 
 `Lexer(source, sink).advance()` returns the next `Token`: a `TokenKind`, the
````

In `packages/typed_graphql/doc/schema.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -185,6 +185,85 @@ null
 null
 ```
 
+### Resolving a coordinate
+
+`schema.resolve(coordinate)` finds the element a schema coordinate names
+(September2025, "Resolving a Schema Coordinate"). It returns a sealed
+`CoordinateTarget`, one kind per form, holding the element and the elements that
+contain it: `TypeTarget`, `FieldTarget`, `ArgumentTarget`, `InputFieldTarget`,
+`EnumValueTarget`, `DirectiveTarget` and `DirectiveArgumentTarget`. It returns
+null when the schema has no such element, also when a containing element is
+missing or of the wrong kind. Meta-fields such as `__typename` and the
+introspection types are not elements of a schema, so they resolve to null too.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  final source = Source('''
+type Query {
+  hero(episode: Episode): Character
+}
+
+enum Episode { NEWHOPE EMPIRE JEDI }
+
+interface Character {
+  name: String!
+}
+
+directive @cost(units: Int) on FIELD_DEFINITION
+''');
+  final document = const Parser().parse(source).requireDocument();
+  final schema = switch (const SchemaBuilder().fromSdl(document)) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
+  };
+  const texts = [
+    'Character',
+    'Query.hero(episode:)',
+    'Episode.JEDI',
+    '@cost(units:)',
+    'Query.villain',
+    'Episode.JEDI.name',
+    'Query.__typename',
+  ];
+  for (final text in texts) {
+    final target = switch (const Parser().parseSchemaCoordinate(Source(text))) {
+      ParseElementSuccess(:final value) => describe(schema.resolve(value)),
+      ParseElementFailure(:final diagnostics) => '${diagnostics.first.message}',
+    };
+    print('$text: $target');
+  }
+}
+
+String describe(CoordinateTarget? target) => switch (target) {
+  TypeTarget(:final type) => 'the type ${type.name}',
+  FieldTarget(:final type, :final field) =>
+    'the field ${type.name}.${field.name}',
+  ArgumentTarget(:final field, :final argument) =>
+    'the argument ${argument.name} of ${field.name}',
+  InputFieldTarget(:final inputField) => 'the input field ${inputField.name}',
+  EnumValueTarget(:final type, :final enumValue) =>
+    'the value ${enumValue.name} of ${type.name}',
+  DirectiveTarget(:final directive) => 'the directive @${directive.name}',
+  DirectiveArgumentTarget(:final directive, :final argument) =>
+    'the argument ${argument.name} of @${directive.name}',
+  null => 'nothing',
+};
+```
+
+It prints:
+
+```text
+Character: the type Character
+Query.hero(episode:): the argument episode of hero
+Episode.JEDI: the value JEDI of Episode
+@cost(units:): the argument units of @cost
+Query.villain: nothing
+Episode.JEDI.name: Expected <EOF>, found ".".
+Query.__typename: nothing
+```
+
 ## Built-ins
 
 Every schema has the five built-in scalars (`String`, `Int`, `Float`, `Boolean`,
````

- [ ] **Step 6: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+241: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 7: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -266,6 +266,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   and `TypeRefReader` (the `ofType` chain with a loop). Problems are
   `GQL150`-`GQL155` with the JSON path in the message; kind misuse is
   left to the validator.
+- `coordinates/`: `Schema.resolve(coordinate)` runs `CoordinateResolver`
+  (September2025 §2.14 "Resolving a Schema Coordinate") and returns the
+  sealed `CoordinateTarget`, one kind per coordinate form holding the
+  elements that contain it (equal when they hold the same elements), or
+  null for any miss (spec §9). Names starting with `__` resolve to null.
 - `validation/SchemaValidator` (const): `validate(schema)` returns the
   sealed `SchemaValidationResult` (`ValidSchema` | `InvalidSchema(schema,
   diagnostics)`); `ValidSchema` has a private constructor and
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- `Schema.resolve(SchemaCoordinate)` finds the element a schema coordinate
  names as a sealed `CoordinateTarget` (`TypeTarget`, `FieldTarget`,
  `ArgumentTarget`, `InputFieldTarget`, `EnumValueTarget`,
  `DirectiveTarget`, `DirectiveArgumentTarget`), or null: also when a
  containing element is missing or of the wrong kind, and for meta-fields
  and introspection types, which are not schema elements.
```

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Ported graphql-js `resolveSchemaCoordinate-test.ts`; where graphql-js
  throws or resolves a meta-field, the port expects null.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/doc/language.md packages/typed_graphql/doc/schema.md packages/typed_graphql/lib/src/schema/coordinates/coordinate_resolver.dart packages/typed_graphql/lib/src/schema/coordinates/coordinate_target.dart packages/typed_graphql/lib/src/schema/schema.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/coordinates/coordinate_resolver_test.dart packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/resolve_schema_coordinate_test.dart
git commit -q -m "feat(typed_graphql): resolve schema coordinates against a schema" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 18: Fuzz introspection results and schema coordinates

R10.4. Three fuzzers over M3a's `RandomSchema`, with small CI counts (300 and 500 iterations; `TYPED_GRAPHQL_FUZZ_ITERATIONS` raises them):
- the round trip: introspection then build gives what introspection carries (`IntrospectionView`);
- hostile results: `IntrospectionMutator` breaks results the ways a server can; nothing throws, every introspection code is reached, the sink limit holds and a long `ofType` chain stays linear;
- coordinates: every element resolves to itself, and hostile text never throws.

The coordinate fuzzer found a generator bug (finding 11): `RandomSchema._unique` turned a name `_` into `__1`, a reserved name that resolves to `null`. The fix is in this task.

Run each new fuzzer alone first, under the limits, with `/usr/bin/time -v`. All of them together peak at about 364 MB; the hostile-introspection fuzzer at 10000 iterations took 194 MB.

**Files:**
- Modify: `CLAUDE.md`, `packages/typed_graphql_conformance/CHANGELOG.md`
- Test: `packages/typed_graphql_conformance/test/fuzz/coordinate_fuzz_test.dart`, `packages/typed_graphql_conformance/test/fuzz/hostile_introspection_fuzz_test.dart`, `packages/typed_graphql_conformance/test/fuzz/introspection_mutator.dart`, `packages/typed_graphql_conformance/test/fuzz/introspection_round_trip_fuzz_test.dart`, `packages/typed_graphql_conformance/test/fuzz/introspection_view.dart`, `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, `packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart`

**Interfaces:**
- Consumes: Tasks 14, 15, 17; M3a `RandomSchema`, `SchemaDump`.
- Produces:
```text
test/fuzz/schema_mapper.dart: final class SchemaMapper({type, references, directives}) { Schema map(Schema schema) }
test/fuzz/introspection_view.dart: final class IntrospectionView { Schema closed(Schema); Schema carried(Schema) }
test/fuzz/introspection_mutator.dart: final class IntrospectionMutator(Random random) { void mutate(Map<String, Object?> json) }
```

- [ ] **Step 1: Write the fuzzers and fix the generator**

The fuzzers check behaviour that exists, so there is no red phase for them. The red phase is the generator bug: without the `_unique` change in `random_schema.dart`, `coordinate_fuzz_test.dart` fails with `case 331 of seed 20261014: Random(20261345): __1`.

Create `packages/typed_graphql_conformance/test/fuzz/coordinate_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'random_parts.dart';
import 'random_schema.dart';

/// R10.4 and spec §11 of M3 for schema coordinates: the coordinate of
/// every element of a random schema resolves to that element, and hostile
/// coordinate text never throws, ends, and gives at most `maxErrors + 1`
/// diagnostics; what parses resolves without throwing.
void main() {
  final budget = FuzzBudget(defaultIterations: 500);
  const parser = Parser();
  const limit = DiagnosticSink.defaultMaxErrors + 1;

  /// Every element of [schema] that has a coordinate, with its text.
  List<(String, CoordinateTarget)> elementsOf(Schema schema) => [
    for (final type in schema.types) ...[
      (type.name, TypeTarget(type)),
      ...switch (type) {
        ObjectType(:final fields) || InterfaceType(:final fields) => [
          for (final field in fields) ...[
            ('${type.name}.${field.name}', FieldTarget(type, field)),
            for (final argument in field.arguments)
              (
                '${type.name}.${field.name}(${argument.name}:)',
                ArgumentTarget(type, field, argument),
              ),
          ],
        ],
        InputObjectType(:final fields) => [
          for (final field in fields)
            ('${type.name}.${field.name}', InputFieldTarget(type, field)),
        ],
        EnumType(:final values) => [
          for (final value in values)
            ('${type.name}.${value.name}', EnumValueTarget(type, value)),
        ],
        ScalarType() || UnionType() => const <(String, CoordinateTarget)>[],
      },
    ],
    for (final directive in schema.directives) ...[
      ('@${directive.name}', DirectiveTarget(directive)),
      for (final argument in directive.arguments)
        (
          '@${directive.name}(${argument.name}:)',
          DirectiveArgumentTarget(directive, argument),
        ),
    ],
  ];

  /// The coordinate [text] parsed and resolved; null when it does not
  /// parse. The diagnostics are checked to be bounded.
  CoordinateTarget? resolve(Schema schema, String text, String reason) {
    final result = parser.parseSchemaCoordinate(Source(text));
    expect(result.diagnostics.length, lessThanOrEqualTo(limit), reason: reason);
    return switch (result) {
      ParseElementSuccess(:final value) => schema.resolve(value),
      ParseElementFailure() => null,
    };
  }

  /// Text made of coordinate punctuation, names of [schema] and debris.
  String hostileText(Random random, Schema schema) {
    final names = [
      for (final (text, _) in elementsOf(schema))
        ...text.split(RegExp('[.@():]')),
      '__typename',
      '__Type',
      'String',
      'deprecated',
    ].where((name) => name.isNotEmpty).toList();
    const debris = ['.', '(', ')', ':', '@', ' ', '#', r'$', '\uD800', '1'];
    return List.generate(random.nextInt(8), (_) {
      if (random.nextBool() && names.isNotEmpty) {
        return names[random.nextInt(names.length)];
      }
      return debris[random.nextInt(debris.length)];
    }).join();
  }

  Schema schemaFor(int index) =>
      RandomSchema(RandomParts(budget.randomFor(index))).schema();

  test('the coordinate of every element resolves to it', () {
    var count = 0;
    for (var index = 0; index < budget.iterations; index++) {
      final schema = schemaFor(index);
      for (final (text, target) in elementsOf(schema)) {
        final reason = '${budget.replay(index)}: $text';
        expect(resolve(schema, text, reason), target, reason: reason);
        count++;
      }
    }
    expect(count, greaterThan(budget.iterations));
  });

  test('hostile text never throws and reaches every outcome', () {
    final outcomes = {'parse failure': 0, 'null': 0, 'element': 0};
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final schema = schemaFor(index);
      final text = hostileText(random, schema);
      final reason = '${budget.replay(index)}: $text ${text.codeUnits}';
      final parsed = parser.parseSchemaCoordinate(Source(text));
      final outcome = switch (resolve(schema, text, reason)) {
        _ when parsed is ParseElementFailure => 'parse failure',
        null => 'null',
        _ => 'element',
      };
      outcomes[outcome] = outcomes[outcome]! + 1;
    }
    if (budget.iterations >= 200) {
      expect(
        outcomes.values,
        everyElement(greaterThan(0)),
        reason: '$outcomes',
      );
    }
  });

  // A coordinate is one element: the parser stops at the first problem
  // instead of recovering, so a long text costs one diagnostic.
  test('a long hostile text gives one diagnostic', () {
    final result = parser.parseSchemaCoordinate(Source('#' * 100000));
    expect(result.diagnostics, hasLength(1));
  });
}
```

Create `packages/typed_graphql_conformance/test/fuzz/hostile_introspection_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'introspection_mutator.dart';
import 'introspection_view.dart';
import 'random_parts.dart';
import 'random_schema.dart';

/// R10.4 and spec §11 of M3, property 2 for introspection JSON: a broken
/// introspection result never makes `fromIntrospection` throw, ends, and
/// gives at most `maxErrors + 1` diagnostics, each a `GQL150`-`GQL155`
/// whose message starts with a JSON path (or the limit's `GQL000`); the
/// partial schema it gives validates without throwing.
void main() {
  final budget = FuzzBudget(defaultIterations: 500);
  const view = IntrospectionView();
  const limit = DiagnosticSink.defaultMaxErrors + 1;
  final introspectionCodes = {
    for (var id = 150; id <= 155; id++) 'GQL$id',
    DiagnosticCode.diagnosticLimitReached.id,
  };

  /// A result of a random schema, as plain objects to break.
  Map<String, Object?> resultFor(int index) {
    final parts = RandomParts(budget.randomFor(index));
    return view.closed(RandomSchema(parts).schema()).toIntrospection().toJson();
  }

  /// The codes of building [json], each diagnostic checked to be bounded,
  /// of the introspection family and led by a path; the partial schema is
  /// validated too.
  List<String> buildChecked(Object? json, String reason) {
    final value = switch (const JsonReader().read(json)) {
      DecodeSuccess(:final value) => value,
      DecodeFailure() => fail('not JSON: $reason'),
    };
    final result = const SchemaBuilder().fromIntrospection(value);
    expect(result.diagnostics.length, lessThanOrEqualTo(limit), reason: reason);
    for (final diagnostic in result.diagnostics) {
      expect(introspectionCodes, contains(diagnostic.code.id), reason: reason);
      if (diagnostic.code != DiagnosticCode.diagnosticLimitReached) {
        expect(diagnostic.message, startsWith(r'$'), reason: reason);
      }
    }
    final schema = switch (result) {
      BuildSuccess(:final schema) => schema,
      BuildFailure(:final partial) => partial,
    };
    final validation = const SchemaValidator().validate(schema);
    expect(
      validation.diagnostics.length,
      lessThanOrEqualTo(limit),
      reason: reason,
    );
    return [for (final diagnostic in result.diagnostics) diagnostic.code.id];
  }

  test('broken results never throw and reach every introspection code', () {
    final codes = <String>{};
    for (var index = 0; index < budget.iterations; index++) {
      final json = resultFor(index);
      IntrospectionMutator(budget.randomFor(index)).mutate(json);
      codes.addAll(buildChecked(json, budget.replay(index)));
    }
    // A handful of iterations cannot be expected to break every way.
    if (budget.iterations >= 200) {
      expect(
        codes,
        containsAll([for (var id = 150; id <= 155; id++) 'GQL$id']),
      );
    }
  });

  test('unbroken results build without diagnostics', () {
    for (var index = 0; index < 50; index++) {
      expect(buildChecked(resultFor(index), budget.replay(index)), isEmpty);
    }
  });

  test('many broken types reach the sink limit and stop there', () {
    final json = {
      '__schema': {
        'types': [
          for (var index = 0; index < 300; index++) {'name': 'T$index'},
        ],
      },
    };
    final codes = buildChecked(json, 'kinds missing');
    expect(codes, hasLength(limit));
    expect(codes.last, DiagnosticCode.diagnosticLimitReached.id);
  });

  // The reader once copied the JSON path per `ofType` level, which made a
  // long chain quadratic in memory (22 GB at 100000 levels); it keeps
  // parents now, so the chain is linear.
  test('a long ofType chain builds in linear memory', () {
    final scalar = JsonObject({
      'kind': const JsonString('SCALAR'),
      'name': const JsonString('String'),
    });
    JsonValue reference = scalar;
    for (var level = 0; level < 20000; level++) {
      reference = JsonObject({
        'kind': const JsonString('NON_NULL'),
        'ofType': JsonObject({
          'kind': const JsonString('LIST'),
          'ofType': reference,
        }),
      });
    }
    final result = const SchemaBuilder().fromIntrospection(
      JsonObject({
        '__schema': JsonObject({
          'queryType': JsonObject({'name': const JsonString('Query')}),
          'types': JsonArray([
            JsonObject({
              'kind': const JsonString('OBJECT'),
              'name': const JsonString('Query'),
              'interfaces': JsonArray(const []),
              'fields': JsonArray([
                JsonObject({
                  'name': const JsonString('a'),
                  'args': JsonArray(const []),
                  'type': reference,
                }),
              ]),
            }),
            scalar,
          ]),
        }),
      }),
    );
    expect(result, isA<BuildSuccess>());
  });
}
```

Create `packages/typed_graphql_conformance/test/fuzz/introspection_mutator.dart`:

```dart
import 'dart:math';

/// Breaks an introspection result, given as plain Dart maps and lists,
/// the ways a hostile or broken server can: a member removed, a value of
/// another JSON type, an unknown kind, name or location, a list item
/// repeated or dropped.
final class IntrospectionMutator {
  /// Draws from [random].
  IntrospectionMutator(this.random);

  /// The random source.
  final Random random;

  /// Values put where any value was; each is wrong somewhere.
  static const List<Object?> _hostileValues = [
    null,
    0,
    -1.5,
    true,
    '',
    'x',
    '{',
    '[1,',
    r'$v',
    'NON_NULL',
    'LIST',
    'OBJECT',
    'SCALAR',
    'UNKNOWN',
    'QUERY',
    'NOT_A_LOCATION',
    'Missing',
    'String',
    '__Type',
    <Object?>[],
    <String, Object?>{},
    <Object?>[null, 1],
    {'kind': 'LIST'},
    {'kind': 'NON_NULL', 'name': null, 'ofType': null},
    {'kind': 'OBJECT', 'name': 'Missing', 'ofType': null},
  ];

  /// [json] with one to five breaks, in place; one result in fifty loses
  /// or breaks `__schema` itself, which a pick among every map and list
  /// would almost never do.
  void mutate(Map<String, Object?> json) {
    if (random.nextInt(50) == 0) {
      _breakOne(json);
    }
    for (var step = random.nextInt(5); step >= 0; step--) {
      final containers = _containers(json);
      _breakOne(containers[random.nextInt(containers.length)]);
    }
  }

  void _breakOne(Object container) {
    switch (container) {
      case final Map<String, Object?> map when map.isNotEmpty:
        final key = map.keys.elementAt(random.nextInt(map.length));
        if (random.nextInt(3) == 0) {
          map.remove(key);
        } else {
          map[key] = _hostile();
        }
      case final List<Object?> list when list.isNotEmpty:
        final index = random.nextInt(list.length);
        switch (random.nextInt(3)) {
          case 0:
            list.removeAt(index);
          case 1:
            list.add(list[index]);
          default:
            list[index] = _hostile();
        }
      default:
    }
  }

  /// A hostile value; a map or a list is a fresh copy, so a later break
  /// cannot change the constant.
  Object? _hostile() =>
      switch (_hostileValues[random.nextInt(_hostileValues.length)]) {
        final Map<String, Object?> map => <String, Object?>{...map},
        final List<Object?> list => <Object?>[...list],
        final value => value,
      };

  /// Every map and list in [json], found with an explicit stack.
  List<Object> _containers(Map<String, Object?> json) {
    final found = <Object>[];
    final stack = <Object?>[json];
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case final Map<String, Object?> map:
          found.add(map);
          stack.addAll(map.values);
        case final List<Object?> list:
          found.add(list);
          stack.addAll(list);
        default:
      }
    }
    return found;
  }
}
```

Create `packages/typed_graphql_conformance/test/fuzz/introspection_round_trip_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'introspection_view.dart';
import 'random_parts.dart';
import 'random_schema.dart';
import 'schema_dump.dart';

/// R10.4 and spec §11 of M3, property 1 through introspection: a random
/// schema, written as introspection and built back, holds what
/// introspection carries of it, and writes the same introspection again
/// (graphql-js's `cycleIntrospection`).
void main() {
  final budget = FuzzBudget(defaultIterations: 300);
  const view = IntrospectionView();
  const dump = SchemaDump();

  void check(int index) {
    final random = RandomSchema(RandomParts(budget.randomFor(index)));
    final schema = view.closed(random.schema());
    final introspection = schema.toIntrospection();
    final reason = budget.replay(index);
    final client = switch (const SchemaBuilder().fromIntrospection(
      introspection,
    )) {
      BuildSuccess(:final schema) => schema,
      BuildFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
    };
    expect(dump.of(client), dump.of(view.carried(schema)), reason: reason);
    expect(client.toIntrospection(), introspection, reason: reason);
  }

  test('introspection then build gives what introspection carries', () {
    for (var index = 0; index < budget.iterations; index++) {
      var isDone = false;
      try {
        check(index);
        isDone = true;
      } finally {
        // The generator and the writer can throw too; name the replay.
        if (!isDone) printOnFailure(budget.replay(index));
      }
    }
  });

  test('a closed schema keeps only references the schema has', () {
    final schema = view.closed(
      Schema(
        types: [
          ObjectType(
            'Query',
            interfaces: [const NamedTypeReference('Missing')],
            fields: [SchemaField('a', const ListType(NamedType(Name('X'))))],
          ),
        ],
        queryTypeName: 'Query',
      ),
    );
    final query = schema.typeNamed('Query')! as ObjectType;
    expect(query.interfaces, isEmpty);
    expect(const Printer().print(query.fields.single.type), '[String]');
  });
}
```

Create `packages/typed_graphql_conformance/test/fuzz/introspection_view.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'schema_mapper.dart';

/// The two views of a random schema the introspection fuzzers compare:
/// [closed] can be introspected, and [carried] is what an introspection
/// result can carry of a schema.
final class IntrospectionView {
  /// Creates the views; they keep no state.
  const IntrospectionView();

  /// The default reason of `@deprecated` (September2025 §3.13.3), which
  /// `fromIntrospection` reads back as `@deprecated` without an argument.
  static const String _defaultReason = 'No longer supported';

  /// [schema] with every reference to a type it lacks replaced: a field or
  /// argument type by `String` (in the same wrappers), an interface or a
  /// union member left out. `toIntrospection` refuses the original.
  Schema closed(Schema schema) => SchemaMapper(
    type: (type) => _KnownTypes(schema).transform(type)! as TypeRef,
    references: (references) => [
      for (final reference in references)
        if (schema.typeNamed(reference.name) != null) reference,
    ],
    directives: _applied,
  ).map(schema);

  /// [schema] with only the directives introspection carries: a scalar's
  /// `@specifiedBy`, an input object's `@oneOf` and the `@deprecated` of a
  /// field, argument, input field or enum value, written as
  /// `fromIntrospection` writes them. Directive deprecation is not in
  /// `IntrospectionQuery.full`.
  Schema carried(Schema schema) => SchemaMapper(
    type: (type) => type,
    references: (references) => references,
    directives: _carriedDirectives,
  ).map(schema);

  List<AppliedDirective> _applied(Object element) => switch (element) {
    Schema(:final appliedDirectives) ||
    SchemaType(:final appliedDirectives) ||
    SchemaField(:final appliedDirectives) ||
    InputValue(:final appliedDirectives) ||
    SchemaEnumValue(:final appliedDirectives) ||
    SchemaDirective(:final appliedDirectives) => appliedDirectives,
    _ => throw ArgumentError.value(element, 'element', 'not an element'),
  };

  List<AppliedDirective> _carriedDirectives(Object element) =>
      switch (element) {
        ScalarType(:final specifiedByUrl?) => [
          _withString('specifiedBy', 'url', specifiedByUrl),
        ],
        InputObjectType(isOneOf: true) => [AppliedDirective('oneOf')],
        SchemaField(:final deprecationReason?) ||
        InputValue(:final deprecationReason?) ||
        SchemaEnumValue(:final deprecationReason?) => [
          if (deprecationReason == _defaultReason)
            AppliedDirective('deprecated')
          else
            _withString('deprecated', 'reason', deprecationReason),
        ],
        _ => const [],
      };

  AppliedDirective _withString(String name, String argument, String text) =>
      AppliedDirective(
        name,
        arguments: [Argument(Name(argument), StringValue(text))],
      );
}

/// Replaces a named type the schema lacks by `String`.
final class _KnownTypes extends AstTransformer {
  _KnownTypes(this.schema);

  final Schema schema;

  @override
  Node? rewrite(Node node) => switch (node) {
    NamedType(:final name) when schema.typeNamed(name.value) == null =>
      const NamedType(Name('String')),
    _ => node,
  };
}
```

In `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -152,10 +152,11 @@ final class RandomSchema {
 
   /// A random name made unique by [index]; no built-in name ends in `_`
   /// and a digit, and neither does `Query`. A `__` prefix is reserved for
-  /// introspection, so it is avoided.
+  /// introspection, so it is avoided; the name `_` would make one with
+  /// the suffix (`__1`), so any leading `_` is.
   String _unique(int index) {
     final name = parts.enumValueName().value;
-    return '${name.startsWith('__') ? 'x$name' : name}_$index';
+    return '${name.startsWith('_') ? 'x$name' : name}_$index';
   }
 
   String? _description() => parts.description()?.value;
```

Create `packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Rebuilds a schema element by element, changing its type references,
/// its interface and member references and its applied directives, for
/// the introspection fuzzers.
///
/// [directives] gets each element (a [Schema], [SchemaType],
/// [SchemaField], [InputValue], [SchemaEnumValue] or [SchemaDirective])
/// and returns the directives its copy keeps.
final class SchemaMapper {
  /// A mapper that changes what the three functions say.
  const SchemaMapper({
    required this.type,
    required this.references,
    required this.directives,
  });

  /// The type reference a copy holds instead of the given one.
  final TypeRef Function(TypeRef type) type;

  /// The interfaces or union members a copy keeps.
  final List<NamedTypeReference> Function(List<NamedTypeReference> references)
  references;

  /// The directives the copy of an element keeps.
  final List<AppliedDirective> Function(Object element) directives;

  /// The copy of [schema].
  Schema map(Schema schema) => Schema(
    types: [for (final type in schema.types) _type(type)],
    directives: [
      for (final directive in schema.directives)
        SchemaDirective(
          directive.name,
          description: directive.description,
          arguments: _inputValues(directive.arguments),
          isRepeatable: directive.isRepeatable,
          locations: directive.locations,
          appliedDirectives: directives(directive),
        ),
    ],
    queryTypeName: schema.queryTypeName,
    mutationTypeName: schema.mutationTypeName,
    subscriptionTypeName: schema.subscriptionTypeName,
    description: schema.description,
    appliedDirectives: directives(schema),
    includesDeferAndStream: schema.includesDeferAndStream,
  );

  SchemaType _type(SchemaType type) => switch (type) {
    ScalarType(:final name, :final description) => ScalarType(
      name,
      description: description,
      appliedDirectives: directives(type),
    ),
    ObjectType(:final name, :final description) => ObjectType(
      name,
      description: description,
      interfaces: references(type.interfaces),
      appliedDirectives: directives(type),
      fields: _fields(type.fields),
    ),
    InterfaceType(:final name, :final description) => InterfaceType(
      name,
      description: description,
      interfaces: references(type.interfaces),
      appliedDirectives: directives(type),
      fields: _fields(type.fields),
    ),
    UnionType(:final name, :final description) => UnionType(
      name,
      description: description,
      appliedDirectives: directives(type),
      memberTypes: references(type.memberTypes),
    ),
    EnumType(:final name, :final description) => EnumType(
      name,
      description: description,
      appliedDirectives: directives(type),
      values: [
        for (final value in type.values)
          SchemaEnumValue(
            value.name,
            description: value.description,
            appliedDirectives: directives(value),
          ),
      ],
    ),
    InputObjectType(:final name, :final description) => InputObjectType(
      name,
      description: description,
      appliedDirectives: directives(type),
      fields: _inputValues(type.fields),
    ),
  };

  List<SchemaField> _fields(List<SchemaField> fields) => [
    for (final field in fields)
      SchemaField(
        field.name,
        type(field.type),
        description: field.description,
        arguments: _inputValues(field.arguments),
        appliedDirectives: directives(field),
      ),
  ];

  List<InputValue> _inputValues(List<InputValue> values) => [
    for (final value in values)
      InputValue(
        value.name,
        type(value.type),
        description: value.description,
        defaultValue: value.defaultValue,
        appliedDirectives: directives(value),
      ),
  ];
}
```

- [ ] **Step 2: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test test/fuzz/coordinate_fuzz_test.dart test/fuzz/hostile_introspection_fuzz_test.dart test/fuzz/introspection_round_trip_fuzz_test.dart)
```

Expected: `typed_graphql_conformance` `+9: All tests passed!`.

Then the whole conformance suite: `(cd packages/typed_graphql_conformance && ulimit -v 8000000 && timeout 600 dart test)`, expected `+708: All tests passed!`.

- [ ] **Step 3: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -471,6 +471,7 @@ that adds API adds its section to the guide of its layer in the same commit.
   `ValidationPort` for `validateSchema`, `IntrospectionPort` for
   `buildClientSchema`).
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
-  round trip, hostile SDL); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
+  round trip, hostile SDL, introspection round trip, hostile
+  introspection, coordinates); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
   `TYPED_GRAPHQL_FUZZ_SEED` tune them.
 - CI: `.github/workflows/ci.yml`.
```

Append to `packages/typed_graphql_conformance/CHANGELOG.md`:

```markdown
- Fuzzers for introspection and schema coordinates: a random schema
  written as introspection builds back to what introspection carries and
  writes the same result again; a broken result gives only bounded
  `GQL150`-`GQL155` diagnostics with a path; every element's coordinate
  resolves to it, and hostile coordinate text never throws. Random type
  names no longer start with `_`.
```

- [ ] **Step 4: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 5: Commit**

```sh
git add CLAUDE.md packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/test/fuzz/coordinate_fuzz_test.dart packages/typed_graphql_conformance/test/fuzz/hostile_introspection_fuzz_test.dart packages/typed_graphql_conformance/test/fuzz/introspection_mutator.dart packages/typed_graphql_conformance/test/fuzz/introspection_round_trip_fuzz_test.dart packages/typed_graphql_conformance/test/fuzz/introspection_view.dart packages/typed_graphql_conformance/test/fuzz/random_schema.dart packages/typed_graphql_conformance/test/fuzz/schema_mapper.dart
git commit -q -m "test(typed_graphql_conformance): fuzz introspection results and schema coordinates" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 19: Describe M3b in the guides, the README and the handoff

The self-review of `CLAUDE.md` and the handoff: the Diagnostics and Getting Started guides name the new work, the README status and Schema row change, `CLAUDE.md` records the stage, and the handoff records it, answers its M3c row and keeps the "Open for M3b" items M3b does not resolve under "Open items" (Open question 7). Then the whole stage is checked on every compiler.

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/HANDOFF.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/doc/diagnostics.md`, `packages/typed_graphql/doc/getting_started.md`

**Interfaces:**
- Consumes: Tasks 1–18.
- Produces:
documents only.

- [ ] **Step 1: Update the guides**

Each edit replaces a sentence or a table row M3c wrote.

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,8 +13,9 @@ web (dart2js and dart2wasm). Part of
 > **Status: under construction.** This release has the diagnostics model, the
 > protocol data types, the language (syntax trees, lexer, parser, printer,
 > visitors, transformers, schema coordinates) and the schema (its model, building and
-> extending it from SDL, printing it, scalar codecs). Schema validation and
-> introspection arrive in M3b, and document validation in M4 (see the
+> extending it from SDL, printing it, scalar codecs, validating it,
+> introspection both ways, resolving schema coordinates). Document validation
+> arrives in M4 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 ## Contents
@@ -99,7 +100,7 @@ is run by the test suite, so what they print is what the package does.
 | [Language](doc/language.md) | Parse, print, visit and rewrite documents; schema coordinates; tokens |
 | [Diagnostics](doc/diagnostics.md) | Sources, spans, codes, the sink |
 | [Wire protocol](doc/protocol.md) | `JsonValue`, requests, responses, errors |
-| [Schema](doc/schema.md) | Build a schema from SDL, read it, extend it, print it |
+| [Schema](doc/schema.md) | Build a schema from SDL, read it, validate it, extend it, print it; resolve coordinates |
 | [Scalars and codecs](doc/scalars.md) | The built-in codecs and your own |
 | [Introspection](doc/introspection.md) | Write the introspection query, answer it from a schema, build a schema from an answer |
 
```

In `packages/typed_graphql/doc/diagnostics.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,8 +2,9 @@
 
 Every problem the package finds in a document, a schema or a payload is a
 `Diagnostic`: a stable code, a severity, a message for people and the place in
-the source it is about. Parsing and building a schema return diagnostics
-instead of throwing, and validation will report through the same model.
+the source it is about. Parsing, building a schema from SDL or from an
+introspection result, and validating a schema return diagnostics instead of
+throwing, and operation validation will report through the same model.
 
 ## Sources and spans
 
@@ -107,7 +108,7 @@ digit is the area:
 | Ids | Area |
 |---|---|
 | `GQL0xx` | lexer and syntax |
-| `GQL1xx` | type system: building a schema |
+| `GQL1xx` | type system: building, validating and introspecting a schema |
 | `GQL2xx` | operation validation |
 | `GQL3xx` | coercion and execution |
 | `GQL4xx` | transports and protocols |
```

In `packages/typed_graphql/doc/getting_started.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -12,7 +12,7 @@ The package is built in layers. A layer imports only the layers before it:
 | diagnostics | **Diagnostics** | `Source`, `SourceSpan`, `Diagnostic`, `DiagnosticCode`, `DiagnosticSink` |
 | language | **Language** | `Parser`, `Printer`, the syntax tree, `AstWalker`, `AstTransformer`, schema coordinates |
 | protocol | **Wire Protocol** | `JsonValue`, `JsonReader`, `GraphQLRequest`, `ResponsePayload`, `GraphQLError` |
-| schema | **Schema**, **Scalars & Codecs** | `Schema`, `SchemaBuilder`, `SchemaPrinter`, `ScalarCodec` |
+| schema | **Schema**, **Scalars & Codecs**, **Introspection** | `Schema`, `SchemaBuilder`, `SchemaValidator`, `SchemaPrinter`, `ScalarCodec`, `IntrospectionQuery` |
 
 Everything is exported from one library, `package:typed_graphql/typed_graphql.dart`.
 
@@ -89,7 +89,8 @@ query root: Query
 - **Language** — parse, print, walk and rewrite documents; schema coordinates.
 - **Diagnostics** — sources, spans, codes, and how to report your own.
 - **Wire Protocol** — requests, responses and errors as typed values.
-- **Schema** — build a schema from SDL, extend it, print it.
+- **Schema** — build a schema from SDL, validate it, extend it, print it;
+  resolve schema coordinates.
 - **Scalars & Codecs** — the built-in scalar codecs and your own.
 - **Introspection** — the introspection query, a schema's answer, and a
   schema built from an answer.
```

- [ ] **Step 2: Run the documentation suite**

Run:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test test/doc)
```

Expected: `+241: All tests passed!`. It runs every guide program and compares its output with the `text` fence after it, checks the links and checks the `{@category}` tags.

- [ ] **Step 3: Update the documents**

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -29,7 +29,12 @@ graphql-js language suite and the language fuzzers. M3a (schema core)
 delivers the schema model, SDL building and extension, the SDL printer,
 scalar codecs, the graphql-js schema builder, extension and printer suites
 and the SDL fuzzers. M3c (core documentation) delivers the guides, the
-example and the dartdoc categories.
+example and the dartdoc categories. M3b (schema validation) delivers the type
+relations, the schema validator, the introspection query, introspection
+results in both directions, coordinate resolution, the graphql-js
+`validateSchema`, `buildClientSchema`, `introspectionFromSchema` and
+`resolveSchemaCoordinate` suites, the introspection and coordinate fuzzers,
+and the Introspection guide.
 
 ## Documents
 
```

In `docs/superpowers/HANDOFF.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,6 @@
 # Handoff: where typed_graphql stands and how to continue
 
-Last updated: 2026-10-14 (M3a and M3c merged into `main` locally, not pushed). Read this
+Last updated: 2026-10-14 (M3a, M3c and M3b merged into `main` locally, not pushed). Read this
 first on a new device or in a new Claude session. Session memory and scratch
 directories do not travel; this file and the repository hold everything
 needed.
@@ -12,8 +12,8 @@ needed.
 | Architecture | [spec](specs/2026-10-13-typed-graphql-design.md), [requirements](../requirements.md), [roadmap](../roadmap.md) | — | — |
 | M1 Foundations | the architecture spec (no stage spec) | [plan](plans/2026-10-13-m1-foundations.md) | done: merged into `main` locally (not pushed); next is M2 |
 | M2 Language | [spec](specs/2026-10-14-m2-language-design.md) | M2a: [plan](plans/2026-10-14-m2a-language-core.md); M2b: [plan](plans/2026-10-14-m2b-language-tools.md) | M2a and M2b merged into `main` locally (M2a pushed, M2b not); M2 is complete; next is M3 (schema) |
-| M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md) | M3a merged into `main` locally (not pushed); next is the M3b plan (validation, introspection) |
-| M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b must add a Validation section to `doc/schema.md`, a new dartdoc category/guide, and `doc/introspection.md` |
+| M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md); M3b: [plan](plans/2026-10-14-m3b-schema-validation.md) | M3a and M3b merged into `main` locally (not pushed); M3 is complete; next is M4 (operation validation) |
+| M3c Core docs | [plan](plans/2026-10-14-m3c-core-docs.md) | — | merged into `main` locally (not pushed): six guides in `packages/typed_graphql/doc/`, `example/`, dartdoc categories, doc test suite (`test/doc/`), CI `dart doc` step. M3b added "Validating a schema" and "Resolving a coordinate" to `doc/schema.md`, and the `introspection` category with its guide `doc/introspection.md` |
 
 **Decisions (2026-10-14):**
 - Layer order is diagnostics < language < protocol < schema < validation; the
@@ -49,29 +49,10 @@ The superpowers skills: `brainstorming`, `writing-plans`,
 - pub.dev rewrites relative README links only when `repository` is verified and, for a monorepo, points at the package folder (`https://github.com/4akloon/graphql_dart/tree/main/packages/<pkg>`); today every pubspec points at the repo root, so relative links in package READMEs would 404.
 - Chrome runs (dart2js/dart2wasm) cannot launch under the 8 GB `ulimit`; CI covers them.
 
-## Open for M3b
-
-Found by the M3a reviews.
-
-- **CSV conversion.** Every row of `mapping/schema.csv` whose reason says
-  validation arrives in M3b (23 rows) must gain the `validateSchema`
-  assertion: `ValidSchema` normally, `InvalidSchema` for "allows extension of
-  interface with missing Object fields" and "allows extension of union by
-  adding itself". Both "Allows to disable SDL validation" rows are adapted tests
-  already (an unknown directive builds); M3b adds the `ValidSchema.assumeValid`
-  link. "Throws on unknown types" (x2) and
-  "Rejects invalid SDL" (x2) assert real `GQL1xx` codes.
-- **Spec section 7** must list "applied directive must be defined" and
-  "referenced type must exist" explicitly.
-- **Spans of references added by `extend`.** An interface or union member
-  added by an extension from another `Source` is a bare `NamedType` whose
-  offsets belong to the extension's source, while the type's span belongs to
-  the base. Decide: store a span next to each reference, or point the
-  diagnostic at the type.
-- **`fromIntrospection`** returns the sealed `BuildResult`, but spec section 8
-  also says `DecodeFailure`: reconcile.
-- **`locations`** of `SchemaDirective` is `List<String>`: decide a typed
-  location for M4.
+## Open items
+
+Found by the M3a reviews and not in M3b's scope; M3b resolved the CSV conversion, spec section 7, the spans of references, `fromIntrospection` and the typed locations.
+
 - **`ScalarCodec<Object>`** covariance: a wrongly typed `encode` is a
   `TypeError`, not an `ArgumentError` (M5).
 - **`maxErrors`** of a build cannot be lowered in a test: `SchemaBuilder` and
```

Append to `packages/typed_graphql/CHANGELOG.md`:

```markdown
- The Schema guide covers validating a schema and resolving a schema
  coordinate, and the new Introspection guide covers the introspection query
  and results; the new types carry their dartdoc category.
```

- [ ] **Step 4: Run the core on every compiler**

The core runs on the VM, AOT, dart2js and dart2wasm (R0.6). Chrome cannot start under `ulimit -v`, so the browser runs are bounded by a systemd memory scope instead:

```sh
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart test --compiler exe)
(cd packages/typed_graphql && systemd-run --user --scope --quiet -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2js)
(cd packages/typed_graphql && systemd-run --user --scope --quiet -p MemoryMax=8G -p MemorySwapMax=0 timeout 900 dart test -p chrome --compiler dart2wasm)
```

Expected: `+987 ~83: All tests passed!` with exe (the skips are the guide programs: `SnippetRunner` needs `dart run`, which a compiled test does not have), and `+834: All tests passed!` with each of dart2js and dart2wasm.

- [ ] **Step 5: Check the documentation and the package**

```sh
(cd packages/typed_graphql && timeout 600 dart doc --output=/tmp/typed_graphql_doc)
(cd packages/typed_graphql && ulimit -v 8000000 && timeout 600 dart pub publish --dry-run)
```

Expected: `dart doc` reports `Found 0 warnings and 0 errors`; the dry run reports `Package has 0 warnings.`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md docs/superpowers/HANDOFF.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/README.md packages/typed_graphql/doc/diagnostics.md packages/typed_graphql/doc/getting_started.md
git commit -q -m "docs(typed_graphql): describe M3b in the guides, the README and the handoff" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Requirement coverage

| Id | Requirement (verbatim from `docs/requirements.md`) | Where |
|---|---|---|
| R0.2 | No `dynamic` and no `Map<String, dynamic>` in any public signature; arbitrary JSON is `JsonValue` / `JsonObject` | Tasks 14–15: `toIntrospection` gives a `JsonObject` and `fromIntrospection` takes a `JsonValue`; the lints in every green check |
| R0.3 | Bad input (documents, schemas, variables, responses) never throws: results are sealed types carrying every diagnostic. Exceptions only for programmer errors and inside user resolvers | Tasks 4–10 (`InvalidSchema`, `GQL111`–`GQL149`), Task 15 (`BuildFailure`, `GQL150`–`GQL155`), Task 17 (`null` for any miss), Task 18 (hostile JSON and coordinate fuzzers) |
| R0.6 | The core package is pure Dart: no `dart:io`, no dependencies except `meta`; it compiles with dart2js and dart2wasm | `layers_test.dart` in every green check; Task 19, "Run the core on every compiler" |
| R0.7 | Spec conformance is measured with ported graphql-js v17 suites and a coverage mapping table | Tasks 11–17: `mapping/schema.csv` gains the `validateSchema`, `getIntrospectionQuery`, `introspectionFromSchema`, `buildClientSchema` and `resolveSchemaCoordinate` rows; Task 12 converts the rows that waited for validation |
| R2.3 | Schema validation with every type-system rule of the spec (interfaces incl. transitive, unions, input cycles, `@oneOf`, reserved names, directives); result `ValidSchema` / `InvalidSchema` | Tasks 4–10, one rule family each; Task 11 ports graphql-js's suite |
| R2.4 | `ValidSchema` is a `final class` with a private constructor; `assumeValid()` is the only bypass | Task 4 (`ValidSchema._`, `ValidSchema.assumeValid`) |
| R2.7 | Introspection query generation (with options for working-draft fields) and introspection JSON → `Schema` | Task 13 (`IntrospectionQuery`, `includesDirectiveDeprecation`), Task 14 (`toIntrospection`), Task 15 (`fromIntrospection`), Task 16 (`buildClientSchema` port) |
| R2.8 | Schema coordinates resolve against a schema | Task 17 (`Schema.resolve`, `CoordinateTarget`), Task 18 (coordinate fuzzer) |
| R10.2 | Size-limit ratchet and core layer-direction tests | Every green check; no allowlist grows |
| R10.3 | `typed_graphql_conformance` with ported graphql-js suites and a coverage mapping table | Tasks 11–17 (`covered` in `mapping_test.dart` gains five graphql-js files) |
| R10.4 | Parse → print → parse fuzzing | Task 18: introspection round trip, hostile introspection JSON, coordinates |
| R11.1 | basalt-style root README and package READMEs | Task 19: the package README's status and guide table |
| R11.2 | `packages/*/doc/*.md` guides tied to dartdoc categories; every public member documented | The Schema guide's sections in Tasks 4 and 17, the Introspection guide and category in Tasks 13–15, Task 1's Built-ins fix, Task 19's other guides; the `{@category}` tags in Tasks 1, 2, 4, 13 and 17 (M3c's `category_tags_test.dart`); `public_member_api_docs` and `test/doc` in every green check; `dart doc` in Task 19 |
| R11.3 | A CHANGELOG per package with `**Breaking:**` entries | Every task's "Update the documents" step; Tasks 1 and 2 are `**Breaking:**` |

## Open questions

Each has the plan's choice; the plan runs as written unless the user decides otherwise.

1. **`NamedTypeReference` (ruling 4).** Interfaces, union members and roots are `NamedTypeReference(name, span:)` instead of language `NamedType` nodes, so validation points at the reference. The cost is one more public type and a breaking change to M3a's model. Recommended: keep.
2. **`toIntrospection` on an unvalidated schema.** It throws `ArgumentError` for a reference to a missing type. The alternative is to take a `ValidSchema`: that makes the error impossible, but forces a validation before every introspection. Recommended: keep `Schema` and the `ArgumentError`, and revisit when M5's executor serves introspection (it holds a `ValidSchema` anyway).
3. **The introspection query text.** `IntrospectionQuery.text` is a clean query with the same fields and fragments as graphql-js's, not its exact whitespace. Servers and tools compare results, not query text. Recommended: keep.
4. **`typeDepth` bounds.** A value outside 0–100 is a `RangeError`; graphql-js only rejects values over 100. Recommended: keep, since a negative depth is a programmer error.
5. **Kind misuse in `fromIntrospection`** goes to the validator (decision 7), so seven graphql-js `buildClientSchema` "throws" tests are adapted to `InvalidSchema`. The alternative is to report them while reading. Recommended: keep, so that one place owns each rule.
6. **Introspection's guide (decision 12).** M3c's plan and the handoff disagree; the plan gives introspection its own guide and `introspection` category. The alternative is M3c's plan: an "Introspection" section of the Schema guide and no new category (Tasks 13–15 then insert their sections before "What building does not check", and Task 13 leaves `dartdoc_options.yaml` and the category test alone). Recommended: keep the own guide; introspection is a client-facing topic of its own.
7. **The "Open for M3b" items M3b does not resolve.** `maxErrors` of a build cannot be lowered in a test, `Parser` recursion on deeply nested values, `ScalarCodec<Object>` covariance (M5) and the conformance package's `dart:io` test without `@TestOn('vm')`. They are outside the brief's scope; Task 19 moves them to an "Open items" list in the handoff. Recommended: the `@TestOn` line and a `maxErrors` parameter in M4's first task, the parser fix as an M2 follow-up before M4's depth tests.

## Self-review

- **Spec coverage.** Every item of the M3b row of the spec's section 1 has a task:
  - schema validation (Tasks 4–10);
  - `ValidSchema` (Task 4);
  - the type relations (Task 3);
  - the introspection query (Task 13), writing (Task 14) and reading (Task 15);
  - coordinate resolution (Task 17);
  - the ported suites (Tasks 11, 12, 13, 15, 16, 17);
  - the fuzzers (Task 18);
  - the documentation (Tasks 1, 4, 13–15, 17 and 19).

  Rulings 3 and 4 add Tasks 1 and 2.
- **Verified code.** The plan was generated from one commit per task on `main` at `5a9261d`, and checked back: a script applied every block of the plan task by task to `5a9261d`, committed with the plan's commit step, and found each task's tree and message equal to that commit's (all 19 the same).
  - Each TDD task was seen failing before its implementation, on that base, with the message quoted in its "see them fail" step, and passing after, with the count quoted.
  - Tasks 12 and 18 check behaviour that already exists, so they have no red phase: Task 12's proof is that the converted assertions run, and Task 18's red is the generator bug it fixes.
  - The documentation suite passed after every task (the counts are in the guide tasks); `category_tags_test.dart` fails on a new exported type without its tag, which is why the tags come with the types.
  - Every commit passed the green check. At the end: core `+1070`, conformance `+708`, root `+34`, the documentation suite `+241`.
  - The core passed with `--compiler exe` (`+987 ~83`) and in Chrome with dart2js and dart2wasm (`+834` each), the browser runs under a systemd memory scope.
  - `dart doc` reported 0 warnings and 0 errors, and `dart pub publish --dry-run` 0 warnings.
  - Tasks 1–18 were also verified on `main` at `90f0236` without M3c (core `+829`, conformance `+708`, root `+34`).
- **Memory.** Every new test file was run alone first under `ulimit -v 8000000` with `/usr/bin/time -v`. The largest peak was 364 MB, for all the fuzzers together at their CI counts; the hostile-introspection fuzzer at 10000 iterations took 194 MB.
  - The one runaway (22 GB, the per-level path copy of decision 10) was found, fixed and pinned by `reads a long ofType chain without recursion` and `a long ofType chain builds in linear memory`.
- **Code rules.** 43 new and 13 changed library files, 42 new test files. The largest library file touched is `type_extender.dart` at 241 lines, the largest test file `validate_schema_interfaces_test.dart` at 494; the longest member added is `AppliedDirectiveRules._arguments` at 39 lines. No allowlist grows, and every member has at most five parameters.
- **Names and types.** The names in each task's "Interfaces" match the code in its steps, and later tasks use the same names.
- **No placeholders.** Every file is given whole or as a diff that was applied.
- **Documentation.** The stage ships its guide sections, dartdoc category tags, compiling guide programs, README and CHANGELOG changes:
  - the Schema guide's sections in Tasks 4 and 17, the Introspection guide in Tasks 13–15, Task 1's fix of the Built-ins program, Task 17's Language guide sentence, and Task 19's Diagnostics and Getting Started edits;
  - the `{@category}` tags with the types (Tasks 1, 2, 4, 13, 17), and the `introspection` category in `dartdoc_options.yaml` with its guide (Task 13);
  - the guide programs, compiled and run by M3c's `doc_snippets_test.dart` (`example/example.dart` stays the README tour);
  - the README's Introspection row (Task 13), status and Schema row (Task 19);
  - CHANGELOG entries in every task.

## Execution handoff

Two ways to run this plan:

1. **Subagent-driven (recommended).** Dispatch a fresh `implementer` subagent (model `sonnet`) for each task, then a `reviewer` subagent (model `sonnet`) on that task. A final whole-branch review with model `opus` comes at the end. Use superpowers:subagent-driven-development.
   - Tasks 4–10 grow one validator and its rule classes through diffs that depend on each other's internal names. The "Interfaces" blocks pin those names, and a fresh reviewer per task catches drift early.
   - Give every subagent the memory rule of the Global Constraints. Ask it to run new test files alone first and to report the peak memory.
2. **Native.** Run the tasks in this session with superpowers:executing-plans, with a checkpoint after Tasks 3, 10, 12, 16 and 18.

Work on a branch `m3b-schema-validation` in a worktree, from `main` at `5a9261d` or later. Fetch `reference/` once (`tool/fetch_reference.sh`). Do not push, tag or publish without the user's yes.
