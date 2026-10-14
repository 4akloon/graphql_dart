# M3a Schema Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first half of M3's `schema/` layer and its conformance measurement:
- the immutable schema model: a sealed family of named types, their members, applied directives, references by name and source spans (R2.1);
- the built-in scalars, directives and introspection types, with `@defer` and `@stream` behind an opt-in (R2.6);
- `SchemaBuilder`: SDL to `Schema` with every kind of `extend`, and the extension of an existing schema, as a sealed `BuildResult` with `GQL100`–`GQL110` diagnostics (R2.2, R0.3);
- `SchemaPrinter`: `Schema` to SDL as graphql-js's `printSchema` (R2.5);
- `ScalarCodec<T>`, the five built-in codecs with exact boundaries, a codec registry and literal conversion through JSON (R2.9);
- `mapping/schema.csv` with the ported graphql-js `printSchema`, `buildASTSchema` and `extendSchema` suites (R0.7, R10.3), the SDL round-trip fuzzer and the hostile-SDL fuzzer (R10.4).

**Architecture:** `packages/typed_graphql/lib/src/schema/` gets four folders and one library. `model/` holds the elements (`SchemaType` and its six kinds, `SchemaField`, `InputValue`, `SchemaEnumValue`, `SchemaDirective`, `AppliedDirective`), and `schema.dart` the `Schema`, which finds built-ins by falling back to `BuiltIns`. `build/` reads language nodes into elements (`ElementReader`, `TypeReader`) and puts a schema together in `SchemaAssembly`, with one collaborator per concern: `UniqueDefinitions`, `MemberFilter`, `SchemaDefinitionReader`, `TypeExtender`, `DirectiveExtender`, and a `BuildReport` that orders and bounds the diagnostics. `print/` has `SchemaPrinter` over `TypePrinter` and `MemberPrinter`, which reuse the language `Printer`. `scalars/` has the codecs, `ScalarCodecs` and `LiteralConverter`. In `packages/typed_graphql_conformance`, the ported suites go under `test/schema/`, the fuzzers under `test/fuzz/`, and the table check reads two tables.

**Tech Stack:** Dart 3.13 (primary constructors, dot shorthands, null-aware elements, patterns, sealed classes, records), `package:test`, `package:meta`. graphql-js 17.0.2 (commit `ee5ce41`, fetched into `reference/` by `tool/fetch_reference.sh`) is the reference. Chrome runs dart2js and dart2wasm.

**Spec:** `docs/superpowers/specs/2026-10-14-m3-type-system-design.md` (the M3a row of section 1, sections 2–6 and 10–13), section 3 of `docs/superpowers/specs/2026-10-13-typed-graphql-design.md`, and `docs/requirements.md` (R0.2, R0.3, R0.6, R0.7, R2.1, R2.2, R2.5, R2.6, R2.9, R10.2, R10.3, R10.4).

**Base:** `main` at `302b1e6` (M2 merged, the M3 spec added). Work on a branch `m3a-schema-core` in a worktree.

## Global Constraints

- `CLAUDE.md` is binding. The code rules apply to tests too:
  - a file in `lib/` has at most 300 lines and a test file at most 500;
  - a method has at most 40 lines and at most 5 parameters (constructors are exempt);
  - control blocks nest at most 3 deep;
  - a file in `lib/` declares one public class or sealed family;
  - no `part`, no `dynamic`, no catch without `on`, no `// ignore:`, no `utils`/`helpers` names;
  - no top-level function other than `main`, not even a private one; a helper in a test is a local closure inside `main` or a method of a class.
- Layering (spec §2): `schema/` imports `diagnostics/`, `language/`, `protocol/` and itself; nothing below imports `schema/`. The core stays pure Dart: no new dependency and no `dart:io` in `lib/` (R0.6). The schema tests run on the VM, as exe, with dart2js and with dart2wasm. A test that needs `dart:io` (the fuzzers read the environment, the table check reads files) starts with `@TestOn('vm')` and then `library;`.
- No new package dependency in this stage. The conformance package depends on `typed_graphql` only.
- Bad input never throws (R0.3). A problem in SDL is a `Diagnostic` with a `GQL1xx` code and the span of its node, and the result is a `BuildFailure` with the partial schema; a value a codec cannot decode is a `DecodeFailure`. Only programmer errors throw, as `ArgumentError`, `RangeError` or `StateError`.
- New codes go into `DiagnosticCode` in id order, with a doc comment, in the commit that first reports them (spec §10): `GQL100`–`GQL110` in Tasks 6–10.
- Messages are graphql-js's text where graphql-js has the same check, with the schema coordinate of the element, so the ported suites compare them unchanged.
- No `dynamic` and no `Map<String, dynamic>` in a public signature; arbitrary JSON is `JsonValue` (R0.2).
- Output is deterministic: the model keeps declaration order and no hash-ordered collection is iterated.
- Public API goes through the barrel `lib/typed_graphql.dart`. The `build/` collaborators, `AppliedDirectives`, `BuiltInSdl`, `MemberPrinter` and `TypePrinter` stay out of it.
- Tests come in the same commit as the code. Each task leaves format, analyze, the root suite and every package suite green. No allowlist in `test/quality/` grows.
- `CLAUDE.md` and the package `CHANGELOG.md` change in the task that changes what they describe; the steps give those changes.
- Never `git push`. Run `dart pub publish` only with `--dry-run`. Take no other outward action.
- Commits use Conventional Commits, one per task, with the message and the trailer given in the task.
- Run every command from the repository root unless a step says otherwise. Use `(cd packages/<name> && …)` so the shell stays at the root.
- Changes to existing files are given as unified diffs against the tree the earlier tasks leave. Each was applied in that order while the plan was verified. If a hunk does not apply, the tree has drifted: stop and report it.

## Review Focus

These are the five failure modes most likely to hurt someone who builds a schema from SDL they do not control, prints it, or decodes scalar values. Each one has tests that pin it, in the task named.

1. **Broken or hostile SDL (R0.3, spec §4).** Text that does not parse, repeats a definition hundreds of times, or mixes operations into SDL must give diagnostics with spans, never an exception, and never more than `maxErrors + 1` of them. Pinned in:
   - Task 6: `stops after the limit of a sink, with one limit error`, `reports an operation or a fragment and builds the rest`;
   - Task 11: `gives the schema back, failed, for operations only`;
   - Task 20: `random definitions never throw and reach every build diagnostic`, `mutated definitions never throw and report a bounded list`, `many repeated definitions reach the sink limit and stop there`.
2. **Repeated and conflicting definitions (spec §4).** Two types, directives, members or root types with one name must keep the first, report every later one at its own place with the first as the related span, and never let a repeat or a bad extension change the model. Pinned in:
   - Task 5: `finds the first of two types with one name`;
   - Task 7: `points a repeated type at the definition it repeats`, `reports each repeat of a type name`, `rejects a redefined built-in directive`;
   - Task 8: `checks the arguments of a repeated field too, as graphql-js`;
   - Task 9: `keeps the first root type of an operation`;
   - Task 10: `reports an extension of another kind and ignores it`, `extends the first of two types with one name`.
3. **Scalar boundaries (R2.6, spec §6).** `2147483648`, `1.5`, `"1"`, a 2^53 ID, NaN on the way out and a literal too large to be finite are where codecs go wrong. Each must be a `DecodeFailure` (or, for `encode`, an `ArgumentError`), and the bounds themselves must decode. Pinned in:
   - Task 14: `decodes the bounds of a signed 32-bit integer`, `decodes a whole float as an integer`, `rejects a number past the bounds`, `rejects a fraction, a string, a boolean and null`, `refuses to encode an integer past the bounds`, `refuses to encode NaN and the infinities`, `rejects a fraction and a boolean`, `rejects an integer past 2^53 - 1, which the web cannot hold`;
   - Task 15: `reads an integer too large for an int as a number`, `rejects a number too large to be finite, with its path`, `rejects a variable`.
4. **SDL that does not survive the round trip (R2.5, spec §5).** A description that cannot be a block string, a default value, an applied directive, or a root named like a default type must print so that building the text gives the same schema and printing it again the same text. Pinned in:
   - Task 12: `prints a description that cannot be a block string as quoted`, `prints applied directives as written`;
   - Task 13: `prints the schema definition when a default name is not a root`, `prints a schema that builds back to the same text`;
   - Task 16: every `expectPrintedSchema` port goes through `SchemaPort.printed`, which builds the text back;
   - Task 19: `print then build gives the same schema and the same text`.
5. **Extending a schema someone else holds (spec §4, §13 deviation 4).** `extend` must leave the base schema as it is, keep its spans, keep whether it has `@defer` and `@stream`, and give the same instance back when the document adds nothing. Pinned in:
   - Task 5: `cannot be changed through its lists`;
   - Task 11: `gives the schema back for a document without definitions`, `keeps the spans of both sources`, `rejects a type the schema has`, `keeps whether the schema includes @defer and @stream`;
   - Task 18: `returns the original schema when there are no type definitions` and the other `extendSchema` ports.

## M3a design decisions

These were made while writing this plan; the spec leaves them open.

1. **References are names, elements are immutable.** A field's type is the language `TypeRef`, an object's interfaces and a union's members are `NamedType` nodes, and `Schema.typeNamed` resolves them. Every list is copied with `List.unmodifiable`. A cyclic schema needs no `late` (spec §3).
2. **Built-ins are found, not listed.** `Schema.types` and `Schema.directives` hold what was declared, in order; `typeNamed` and `directiveNamed` fall back to `BuiltIns`, whose elements are read once from an SDL text of the September2025 edition and shared by every schema. `@defer` and `@stream` are found only when the schema was built with `includesDeferAndStream` (R2.6), which `extend` keeps.
3. **Extensions merge into the type.** The model keeps no extension nodes: an extension's members and directives are appended to the type's, and the type keeps the span of its definition. Each member keeps its own span, so a later diagnostic can still point at a member an extension added.
4. **The first definition wins.** A repeated type, directive, member, root type or schema definition is dropped and reported at its own node, with the first as the related span. An extension applies to the first type of its name. Every repeat is reported, also the arguments of a field that is itself a repeat, as graphql-js does.
5. **Default root types** (spec §3.3.1) are taken only when the document has no schema definition, and only for the operations that no `extend schema` names. `extend` never takes them.
6. **Every applied directive is printed,** not only `@deprecated`, `@specifiedBy` and `@oneOf` as graphql-js does, and a schema definition is printed for schema directives too. The spec asks for faithful printing (§3), and the round trip then loses only what SDL cannot hold.
7. **Executable definitions are `GQL100`,** an error, in `fromSdl` and in `extend` (spec §4); the rest of the document is still built. A redefined built-in (scalar, introspection type or directive) is `GQL103` and ignored, where graphql-js ignores the type silently and replaces the directive.
8. **Codecs.** `decode` never throws. `encode` of a value the type cannot hold (an `int` past 32 bits, NaN) can only come from code, so it is an `ArgumentError`. `ScalarCodecs.withCodec` refuses to replace a built-in codec, also with an `ArgumentError`.
9. **Building reports, it does not validate** (spec §4). Unknown type references, wrong member kinds and the other rules of spec §7 are M3b's; `BuildReport` sorts the construction errors by offset and passes them through a `DiagnosticSink`, so the sink's limit and `GQL000` apply.
10. **Directive extensions** (working draft, M2a's `allowDirectiveExtensions`) are applied too: they add directives to a directive definition of the document or of the schema being extended.
11. **The hostile-SDL fuzzer builds partial documents.** A text that does not parse is built from the parser's partial document, so the builder meets broken definitions as well as wrong ones.

## Spec deviations and findings

Bring these to the user with the plan.

1. **Model names.** Spec §3 names the family `NamedType` and the members `FieldDefinition`, `EnumValueDefinition` and `DirectiveDefinition`. Those are the names of language nodes already exported by the barrel (M2a), so the schema elements are `SchemaType`, `SchemaField`, `SchemaEnumValue` and `SchemaDirective`; `InputValue` and the six kinds keep the spec's names. The spec should be updated to match (Open question 1).
2. **Built-ins are not listed** in `Schema.types` or `Schema.directives` (decision 2). graphql-js lists them in its type map; three `buildASTSchema` tests are adapted to compare lookups instead.
3. **The introspection types follow September2025.** graphql-js 17 prints the working-draft introspection (`__Schema.directives(includeDeprecated:)`, `__Directive.isDeprecated` and `deprecationReason`, the `FRAGMENT_VARIABLE_DEFINITION` and `DIRECTIVE_DEFINITION` locations). `Print Introspection Schema` is adapted with the September2025 text, checked against the specification.
4. **No extension nodes** (decision 3): 16 graphql-js tests check `extensionASTNodes`; the check is dropped and each test checks what the extension added instead.
5. **Validation is M3b's.** 25 adapted rows say "schema validation arrives in M3b": the test checks what the builder keeps instead of the validation error. Two rows are skipped for the same reason (`Rejects invalid SDL`) and two because there is nothing to disable. The M3b plan should revisit every row whose reason names M3b.
6. **What the SDL round trip cannot carry,** found by the fuzzer: an empty schema prints `''`, which is not a document; a schema description or schema directives need root types to be printed; a type named `Query` that is not a root comes back as the root. graphql-js has the same limits; the generator avoids them and `CLAUDE.md` records the empty document.
7. **The hostile-SDL fuzzer is in M3a.** Spec §1 puts the hostile-input fuzzers in M3b; the brief for this plan asked for the SDL one here (Task 20). The introspection and coordinate fuzzers stay in M3b.
8. **Where graphql-js is silent, a diagnostic.** An operation in SDL is `GQL100` and a redefined built-in `GQL103` (decision 7); five graphql-js tests are adapted for it. `GQL103` for a built-in directive has its own message, since graphql-js has none.
9. **What could not be verified locally:** the CI matrix on exactly 3.13.0, macOS and Windows. Everything else in the green check and in Task 21 ran on Linux with Dart 3.13.1 and Chrome.

## File map

| Path | Responsibility | Task |
|---|---|---|
| `packages/typed_graphql/lib/src/schema/model/applied_directive.dart` | A directive applied to an element | 1 |
| `packages/typed_graphql/lib/src/schema/model/applied_directives.dart` | Reads `@deprecated`, `@specifiedBy`, `@oneOf` from applied directives | 1 |
| `packages/typed_graphql/lib/src/schema/model/input_value.dart` | An argument of a field or a directive, or a field of an input object type | 1 |
| `packages/typed_graphql/lib/src/schema/model/schema_directive.dart` | A directive definition, `"desc" directive @name(args) repeatable on LOCATIONS` (spec §3.13) | 1 |
| `packages/typed_graphql/lib/src/schema/model/schema_enum_value.dart` | A value of an enum type, `"desc" NAME @d` (spec §3.9) | 1 |
| `packages/typed_graphql/lib/src/schema/model/schema_field.dart` | A field of an object or interface type, `"desc" name(args): Type @d` (spec §3.6) | 1 |
| `packages/typed_graphql/test/schema/model/schema_members_test.dart` | Tests | 1 |
| `packages/typed_graphql/lib/src/schema/model/schema_type.dart` | The sealed family of named types: the six kinds | 2 |
| `packages/typed_graphql/test/schema/model/schema_type_test.dart` | Tests | 2 |
| `packages/typed_graphql/lib/src/schema/build/element_reader.dart` | Reads the members of type-system definitions into schema elements | 3 |
| `packages/typed_graphql/lib/src/schema/build/node_spans.dart` | The span of a syntax node in its source, or none | 3 |
| `packages/typed_graphql/lib/src/schema/build/type_reader.dart` | A type definition read into a `SchemaType` of its kind | 3 |
| `packages/typed_graphql/test/schema/build/element_reader_test.dart` | Tests | 3 |
| `packages/typed_graphql/test/schema/build/type_reader_test.dart` | Tests | 3 |
| `packages/typed_graphql/test/schema/sdl.dart` | Test helper: SDL text parsed for a schema test | 3 |
| `packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart` | The built-ins as SDL text (September2025) | 4 |
| `packages/typed_graphql/lib/src/schema/build/built_ins.dart` | The scalars, directives and introspection types every schema has (R2.6) | 4 |
| `packages/typed_graphql/test/schema/build/built_ins_test.dart` | Tests | 4 |
| `packages/typed_graphql/lib/src/schema/schema.dart` | The immutable schema; lookups fall back to the built-ins (spec §3) | 5 |
| `packages/typed_graphql/test/schema/schema_test.dart` | Tests | 5 |
| `packages/typed_graphql/lib/src/schema/build/build_report.dart` | Collects the errors of one build and gives them in document order | 6 |
| `packages/typed_graphql/lib/src/schema/build/build_result.dart` | The result of building a schema | 6 |
| `packages/typed_graphql/lib/src/schema/build/document_definitions.dart` | The definitions of a document sorted by what the builder does with them, each list in document order | 6 |
| `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart` | Puts one schema together from the sorted definitions of a document | 6 |
| `packages/typed_graphql/lib/src/schema/build/schema_builder.dart` | SDL to `Schema`, and the extension of a schema (spec §4) | 6 |
| `packages/typed_graphql/test/schema/build/build_report_test.dart` | Tests | 6 |
| `packages/typed_graphql/test/schema/build/schema_builder_test.dart` | Tests | 6 |
| `packages/typed_graphql/test/schema/built.dart` | Test helper: the result of building SDL | 6 |
| `packages/typed_graphql/lib/src/schema/build/unique_definitions.dart` | Keeps the first type or directive definition of each name and drops the repeats and the built-ins redefined, reporting each | 7 |
| `packages/typed_graphql/test/schema/build/unique_definitions_test.dart` | Tests | 7 |
| `packages/typed_graphql/lib/src/schema/build/member_filter.dart` | Drops the repeated members of type and directive definitions, keeping the first of each name and reporting the others | 8 |
| `packages/typed_graphql/test/schema/build/member_filter_test.dart` | Tests | 8 |
| `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart` | Applies the schema definition and the schema extensions of a document to a schema | 9 |
| `packages/typed_graphql/test/schema/build/schema_definition_reader_test.dart` | Tests | 9 |
| `packages/typed_graphql/lib/src/schema/build/type_extender.dart` | Applies type extensions to the types of a schema (spec §3.4.3) | 10 |
| `packages/typed_graphql/test/schema/build/type_extender_test.dart` | Tests | 10 |
| `packages/typed_graphql/lib/src/schema/build/directive_extender.dart` | Applies directive extensions, `extend directive @name @d` (working draft) | 11 |
| `packages/typed_graphql/test/schema/build/schema_extend_test.dart` | Tests | 11 |
| `packages/typed_graphql/lib/src/schema/print/member_printer.dart` | Prints the parts of schema elements as graphql-js's `printSchema` | 12 |
| `packages/typed_graphql/lib/src/schema/print/schema_printer.dart` | `Schema` to SDL, as graphql-js's `printSchema` (spec §5) | 12 |
| `packages/typed_graphql/lib/src/schema/print/type_printer.dart` | Prints a named type or a directive definition as graphql-js's `printSchema`, with every applied directive as written | 12 |
| `packages/typed_graphql/test/schema/print/type_printing_test.dart` | Tests | 12 |
| `packages/typed_graphql/test/schema/print/schema_printing_test.dart` | Tests | 13 |
| `packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart` | The built-in `Boolean` | 14 |
| `packages/typed_graphql/lib/src/schema/scalars/float_codec.dart` | The built-in `Float` | 14 |
| `packages/typed_graphql/lib/src/schema/scalars/id_codec.dart` | The built-in `ID` | 14 |
| `packages/typed_graphql/lib/src/schema/scalars/int_codec.dart` | The built-in `Int` | 14 |
| `packages/typed_graphql/lib/src/schema/scalars/scalar_codec.dart` | Reads and writes the values of one scalar type (R2.9) | 14 |
| `packages/typed_graphql/lib/src/schema/scalars/string_codec.dart` | The built-in `String` | 14 |
| `packages/typed_graphql/test/schema/scalars/built_in_codecs_test.dart` | Tests | 14 |
| `packages/typed_graphql/lib/src/schema/scalars/literal_converter.dart` | A constant literal converted to the JSON a codec decodes (spec §6) | 15 |
| `packages/typed_graphql/lib/src/schema/scalars/scalar_codecs.dart` | The codecs of the scalar types by name (R2.9) | 15 |
| `packages/typed_graphql/test/schema/scalars/literal_converter_test.dart` | Tests | 15 |
| `packages/typed_graphql/test/schema/scalars/scalar_codecs_test.dart` | Tests | 15 |
| `packages/typed_graphql_conformance/mapping/schema.csv` | The schema mapping table: 144 rows | 16 |
| `packages/typed_graphql_conformance/test/schema/print_introspection_schema_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/schema/print_schema_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart` | Tests | 16 |
| `packages/typed_graphql_conformance/test/support/schema_port.dart` | graphql-js's schema test helpers | 16 |
| `packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/schema/build_schema_extensions_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/schema/build_schema_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart` | Tests | 17 |
| `packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/schema/extend_schema_spans_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/schema/extend_schema_test.dart` | Tests | 18 |
| `packages/typed_graphql_conformance/test/fuzz/random_schema.dart` | Random schemas that SDL can carry | 19 |
| `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart` | A schema as comparable lines, without spans | 19 |
| `packages/typed_graphql_conformance/test/fuzz/schema_round_trip_fuzz_test.dart` | Tests | 19 |
| `packages/typed_graphql_conformance/test/fuzz/hostile_sdl_fuzz_test.dart` | Tests | 20 |
| `CLAUDE.md` | Repository guide: the schema layer, the M3a lessons, the status | 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 21 |
| `packages/typed_graphql/CHANGELOG.md` | Core changelog | 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 |
| `packages/typed_graphql/lib/typed_graphql.dart` | The barrel: the new public API | 1, 2, 4, 5, 6, 12, 14, 15, 21 |
| `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart` | `GQL100`–`GQL110` | 6, 7, 8, 9, 10 |
| `packages/typed_graphql_conformance/CHANGELOG.md` | Conformance changelog | 16, 17, 18, 19, 20 |
| `packages/typed_graphql_conformance/README.md` | Conformance README: the schema table, the SDL fuzzers | 16, 19, 20, 21 |
| `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart` | Any graphql-js test folder: `filesIn` | 16 |
| `README.md` | Repository README: status and the package table | 21 |
| `docs/superpowers/HANDOFF.md` | Where the work stands | 21 |
| `packages/typed_graphql/README.md` | Core README: "Building and printing a schema" | 21 |

## The green check

Every task ends with this check. "Green" means each command exits 0.

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
```

With `reference/` fetched, the conformance suite also runs the coverage checks. Run `tool/fetch_reference.sh` once before Task 16.

---

### Task 1: Schema model elements

R2.1 and spec §3: the members of a schema, immutable, with references by name and an optional span.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/model/applied_directive.dart`, `packages/typed_graphql/lib/src/schema/model/applied_directives.dart`, `packages/typed_graphql/lib/src/schema/model/input_value.dart`, `packages/typed_graphql/lib/src/schema/model/schema_directive.dart`, `packages/typed_graphql/lib/src/schema/model/schema_enum_value.dart`, `packages/typed_graphql/lib/src/schema/model/schema_field.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/model/schema_members_test.dart`

**Interfaces:**
- Consumes: M1: `SourceSpan`; M2a: the language nodes `TypeRef`, `Value`, `Argument`, `Name`.
- Produces:
  - `final class AppliedDirective(String name, {List<Argument> arguments = const [], SourceSpan? span})` with `Value? argument(String name)`;
  - internal `final class const AppliedDirectives(List<AppliedDirective> directives)` with `static const String defaultDeprecationReason = 'No longer supported'`, `String? deprecationReason`, `String? specifiedByUrl`, `bool isOneOf`;
  - `final class InputValue(String name, TypeRef type, {String? description, Value? defaultValue, List<AppliedDirective> appliedDirectives = const [], SourceSpan? span})` with `deprecationReason`;
  - `final class SchemaField(String name, TypeRef type, {String? description, List<InputValue> arguments = const [], List<AppliedDirective> appliedDirectives = const [], SourceSpan? span})` with `deprecationReason` and `InputValue? argumentNamed(String name)`;
  - `final class SchemaEnumValue(String name, {String? description, List<AppliedDirective> appliedDirectives = const [], SourceSpan? span})` with `deprecationReason`;
  - `final class SchemaDirective(String name, {String? description, List<InputValue> arguments = const [], bool isRepeatable = false, List<String> locations = const [], List<AppliedDirective> appliedDirectives = const [], SourceSpan? span})` with `deprecationReason` and `argumentNamed`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/model/schema_members_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  AppliedDirective deprecated([Value? reason]) => AppliedDirective(
    'deprecated',
    arguments: [
      ?reason == null ? null : Argument(const Name('reason'), reason),
    ],
  );

  group('AppliedDirective', () {
    test('finds the first argument of a name', () {
      final directive = AppliedDirective(
        'd',
        arguments: [
          const Argument(Name('a'), IntValue('1')),
          const Argument(Name('a'), IntValue('2')),
        ],
      );
      expect(directive.argument('a'), isA<IntValue>());
      expect((directive.argument('a')! as IntValue).value, '1');
      expect(directive.argument('b'), isNull);
    });

    test('keeps its arguments unmodifiable', () {
      final directive = AppliedDirective('d', arguments: []);
      expect(
        () => directive.arguments.add(const Argument(Name('a'), NullValue())),
        throwsUnsupportedError,
      );
    });
  });

  group('deprecationReason', () {
    test('is null without @deprecated', () {
      const type = NamedType(Name('String'));
      expect(SchemaField('f', type).deprecationReason, isNull);
    });

    test('is the default reason for a bare @deprecated', () {
      final value = SchemaEnumValue('A', appliedDirectives: [deprecated()]);
      expect(value.deprecationReason, 'No longer supported');
    });

    test('is the reason string when one is given', () {
      final argument = InputValue(
        'a',
        const NamedType(Name('Int')),
        appliedDirectives: [deprecated(const StringValue('Use b.'))],
      );
      expect(argument.deprecationReason, 'Use b.');
    });

    test('reads a reason that is not a string as the default', () {
      final field = SchemaField(
        'f',
        const NamedType(Name('String')),
        appliedDirectives: [deprecated(const IntValue('1'))],
      );
      expect(field.deprecationReason, 'No longer supported');
    });

    test('reads the first of two @deprecated', () {
      final directive = SchemaDirective(
        'd',
        locations: ['FIELD'],
        appliedDirectives: [
          deprecated(const StringValue('first')),
          deprecated(const StringValue('second')),
        ],
      );
      expect(directive.deprecationReason, 'first');
    });
  });

  group('argumentNamed', () {
    final arguments = [
      InputValue('a', const NamedType(Name('Int'))),
      InputValue('b', const NamedType(Name('String'))),
    ];

    test('finds a field argument by name', () {
      final field = SchemaField(
        'f',
        const NamedType(Name('String')),
        arguments: arguments,
      );
      expect(field.argumentNamed('b'), same(arguments[1]));
      expect(field.argumentNamed('c'), isNull);
    });

    test('finds a directive argument by name', () {
      final directive = SchemaDirective('d', arguments: arguments);
      expect(directive.argumentNamed('a'), same(arguments[0]));
      expect(directive.argumentNamed('c'), isNull);
    });
  });

  test('a directive definition is not repeatable by default', () {
    final directive = SchemaDirective('d', locations: ['FIELD', 'QUERY']);
    expect(directive.isRepeatable, isFalse);
    expect(directive.locations, ['FIELD', 'QUERY']);
  });

  test('an input value keeps its default value node', () {
    final value = ListValue(const [IntValue('1')]);
    final input = InputValue(
      'a',
      const ListType(NamedType(Name('Int'))),
      defaultValue: value,
    );
    expect(input.defaultValue, same(value));
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/model/schema_members_test.dart)
```

Expected: FAIL. The file does not compile: `Error: 'AppliedDirective' isn't a type.`, `Error: Method not found: 'SchemaField'.`, `Error: Method not found: 'SchemaEnumValue'.`, `Error: Method not found: 'InputValue'.` and `Error: Method not found: 'SchemaDirective'.`

- [ ] **Step 3: Write the implementation**

Every element is immutable: lists are copied with `List.unmodifiable`, and a type is a `TypeRef` (the language node), so references between elements are names. `AppliedDirectives` is the one place that reads `@deprecated`, `@specifiedBy` and `@oneOf` (spec §3, "typed accessors"); it stays out of the barrel.

Create `packages/typed_graphql/lib/src/schema/model/applied_directive.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/argument.dart';
import '../../language/ast/value.dart';

/// A directive applied to a schema element, `@name(arguments)`, as the SDL
/// wrote it (spec §3.13).
///
/// The arguments are constant language [Value] nodes; nothing checks them
/// against the directive's definition here (that is schema validation).
final class AppliedDirective(
  /// The directive name, without the `@`.
  final String name, {
  List<Argument> arguments = const [],

  /// Where the directive was written; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates an applied directive.
  this;

  /// The arguments, in the order they were written.
  final List<Argument> arguments = List.unmodifiable(arguments);

  /// The value of the first argument named [name]; null when there is none.
  Value? argument(String name) {
    for (final argument in arguments) {
      if (argument.name.value == name) {
        return argument.value;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/model/applied_directives.dart`:

```dart
import '../../language/ast/value.dart';
import 'applied_directive.dart';

/// What the built-in directives among the [directives] applied to one
/// schema element say: deprecation, a scalar's specification URL and the
/// one-of flag (spec §3.13).
///
/// The directives stay in the element's list, so printing is faithful;
/// these are typed views of them. An argument of the wrong kind reads as
/// absent: schema validation reports it.
final class const AppliedDirectives(
  /// The directives applied to the element, in the order written.
  final List<AppliedDirective> directives,
) {
  /// Creates the views.
  this;

  /// The reason `@deprecated` gives when it has no `reason` argument
  /// (spec §3.13, "@deprecated").
  static const String defaultDeprecationReason = 'No longer supported';

  /// The reason of the first `@deprecated`: its `reason` string, or
  /// [defaultDeprecationReason] without one; null when not deprecated.
  String? get deprecationReason {
    final directive = _named('deprecated');
    if (directive == null) {
      return null;
    }
    return switch (directive.argument('reason')) {
      StringValue(:final value) => value,
      _ => defaultDeprecationReason,
    };
  }

  /// The `url` string of the first `@specifiedBy`; null without one.
  String? get specifiedByUrl => switch (_named('specifiedBy')?.argument(
    'url',
  )) {
    StringValue(:final value) => value,
    _ => null,
  };

  /// Whether `@oneOf` is among the directives.
  bool get isOneOf => _named('oneOf') != null;

  AppliedDirective? _named(String name) {
    for (final directive in directives) {
      if (directive.name == name) {
        return directive;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/model/input_value.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';

/// An argument of a field or a directive, or a field of an input object
/// type: `"desc" name: Type = default @d` (spec §3.6.1, §3.10).
final class InputValue(
  /// The name.
  final String name,

  /// The input type, by name: resolve it with `Schema.typeNamed`.
  final TypeRef type, {

  /// The description, if any.
  final String? description,

  /// The default value, a constant; null when there is none.
  final Value? defaultValue,
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates an input value.
  this;

  /// The directives applied to it, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;
}
```

Create `packages/typed_graphql/lib/src/schema/model/schema_field.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';
import 'input_value.dart';

/// A field of an object or interface type, `"desc" name(args): Type @d`
/// (spec §3.6).
///
/// The language node with the spec's name is `FieldDefinition`; this is
/// the schema's element.
final class SchemaField(
  /// The field name.
  final String name,

  /// The output type, by name: resolve it with `Schema.typeNamed`.
  final TypeRef type, {

  /// The description, if any.
  final String? description,
  List<InputValue> arguments = const [],
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates a field.
  this;

  /// The arguments, in declaration order.
  final List<InputValue> arguments = List.unmodifiable(arguments);

  /// The directives applied to it, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;

  /// The argument named [name]; null when there is none.
  InputValue? argumentNamed(String name) {
    for (final argument in arguments) {
      if (argument.name == name) {
        return argument;
      }
    }
    return null;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/model/schema_enum_value.dart`:

```dart
import '../../diagnostics/source_span.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';

/// A value of an enum type, `"desc" NAME @d` (spec §3.9).
///
/// The language nodes with the spec's names are `EnumValueDefinition` and,
/// for a literal, `EnumValue`; this is the schema's element.
final class SchemaEnumValue(
  /// The value's name.
  final String name, {

  /// The description, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates an enum value.
  this;

  /// The directives applied to it, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;
}
```

Create `packages/typed_graphql/lib/src/schema/model/schema_directive.dart`:

```dart
import '../../diagnostics/source_span.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';
import 'input_value.dart';

/// A directive definition, `"desc" directive @name(args) repeatable on
/// LOCATIONS` (spec §3.13).
///
/// The language node with the spec's name is `DirectiveDefinition`; this
/// is the schema's element. Directives applied to a directive definition
/// are working-draft syntax (`ParserOptions.allowDirectiveExtensions`).
final class SchemaDirective(
  /// The directive name, without the `@`.
  final String name, {

  /// The description, if any.
  final String? description,
  List<InputValue> arguments = const [],

  /// Whether it may be applied more than once to one place.
  final bool isRepeatable = false,
  List<String> locations = const [],
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates a directive definition.
  this;

  /// The arguments, in declaration order.
  final List<InputValue> arguments = List.unmodifiable(arguments);

  /// The locations it may be applied to, such as `FIELD`, as written.
  final List<String> locations = List.unmodifiable(locations);

  /// The directives applied to the definition itself, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;

  /// The argument named [name]; null when there is none.
  InputValue? argumentNamed(String name) {
    for (final argument in arguments) {
      if (argument.name == name) {
        return argument;
      }
    }
    return null;
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -59,3 +59,8 @@ export 'src/protocol/json_reader.dart';
 export 'src/protocol/json_value.dart';
 export 'src/protocol/path_segment.dart';
 export 'src/protocol/response_payload.dart';
+export 'src/schema/model/applied_directive.dart';
+export 'src/schema/model/input_value.dart';
+export 'src/schema/model/schema_directive.dart';
+export 'src/schema/model/schema_enum_value.dart';
+export 'src/schema/model/schema_field.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/model/schema_members_test.dart)
```

Expected: `+11: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,3 +66,6 @@
 - `Printer` prints schema coordinates, the same in both forms.
 - `SourceExcerpt` and `SourceSpan.excerpt`: a location shown in its lines
   with a caret, as graphql-js's `printLocation` prints it.
+- Schema model elements: `SchemaField`, `InputValue`, `SchemaEnumValue`,
+  `SchemaDirective` and `AppliedDirective`, with `deprecationReason` read
+  from `@deprecated` and lookups of arguments by name.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -164,6 +164,19 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `RequestErrorResult`) read with a static `decode(JsonValue)` and write with
   `toJson()`; equality is equality of their JSON.
 
+**Schema** (`schema/`; M3). Imports `diagnostics`, `language` and
+`protocol`.
+- `model/`: the immutable schema model (R2.1). Its elements are
+  `SchemaField`, `InputValue` (arguments and input fields),
+  `SchemaEnumValue`, `SchemaDirective` and `AppliedDirective`; the spec's
+  names `FieldDefinition`, `EnumValueDefinition`, `DirectiveDefinition` and
+  `NamedType` already name language nodes, so the schema's take a
+  `Schema` prefix. Types are language `TypeRef` nodes, resolved by name;
+  defaults and directive arguments are constant language `Value` nodes.
+  Every element has `SourceSpan? span`. `deprecationReason`,
+  `specifiedByUrl` and `isOneOf` read the applied directives through the
+  internal `AppliedDirectives`, which stay in the element's list.
+
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
 `ArgumentError`, `RangeError`, `StateError`.
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/model/applied_directive.dart packages/typed_graphql/lib/src/schema/model/applied_directives.dart packages/typed_graphql/lib/src/schema/model/input_value.dart packages/typed_graphql/lib/src/schema/model/schema_directive.dart packages/typed_graphql/lib/src/schema/model/schema_enum_value.dart packages/typed_graphql/lib/src/schema/model/schema_field.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/model/schema_members_test.dart
git commit -q -m "feat(typed_graphql): add the schema model elements" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 2: The sealed family of schema types

R2.1: the six kinds of named type as one sealed family.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/model/schema_type.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/schema/model/applied_directives.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/model/schema_type_test.dart`

**Interfaces:**
- Consumes: Task 1: the elements and `AppliedDirectives`; M2a: `NamedType` (the language node of a type reference).
- Produces:
  - `sealed class SchemaType(String name, {String? description, List<AppliedDirective> appliedDirectives = const [], SourceSpan? span})`;
  - `ScalarType` (`specifiedByUrl`), `ObjectType` and `InterfaceType` (`List<NamedType> interfaces`, `List<SchemaField> fields`, `SchemaField? fieldNamed(String)`), `UnionType` (`List<NamedType> memberTypes`), `EnumType` (`List<SchemaEnumValue> values`, `valueNamed`), `InputObjectType` (`List<InputValue> fields`, `bool isOneOf`, `fieldNamed`), each `final` with the same named parameters as its lists.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/model/schema_type_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const string = NamedType(Name('String'));

  /// What a `switch` over the sealed family says about [type].
  String kindOf(SchemaType type) => switch (type) {
    ScalarType() => 'scalar',
    ObjectType() => 'object',
    InterfaceType() => 'interface',
    UnionType() => 'union',
    EnumType() => 'enum',
    InputObjectType() => 'input object',
  };

  test('a switch over the family covers every kind', () {
    final types = <SchemaType>[
      ScalarType('Date'),
      ObjectType('Query'),
      InterfaceType('Node'),
      UnionType('Result'),
      EnumType('Color'),
      InputObjectType('Filter'),
    ];
    expect(types.map(kindOf), [
      'scalar',
      'object',
      'interface',
      'union',
      'enum',
      'input object',
    ]);
  });

  test('object and interface types find a field by name', () {
    final fields = [SchemaField('a', string), SchemaField('b', string)];
    expect(ObjectType('T', fields: fields).fieldNamed('b'), same(fields[1]));
    expect(InterfaceType('I', fields: fields).fieldNamed('a'), same(fields[0]));
    expect(ObjectType('T', fields: fields).fieldNamed('c'), isNull);
  });

  test('an input object type finds a field by name', () {
    final field = InputValue('limit', const NamedType(Name('Int')));
    expect(
      InputObjectType('Page', fields: [field]).fieldNamed('limit'),
      same(field),
    );
    expect(InputObjectType('Page').fieldNamed('offset'), isNull);
  });

  test('an enum type finds a value by name', () {
    final red = SchemaEnumValue('RED');
    expect(EnumType('Color', values: [red]).valueNamed('RED'), same(red));
    expect(EnumType('Color', values: [red]).valueNamed('BLUE'), isNull);
  });

  test('a scalar reads the url of @specifiedBy', () {
    final scalar = ScalarType(
      'Url',
      appliedDirectives: [
        AppliedDirective(
          'specifiedBy',
          arguments: [
            const Argument(
              Name('url'),
              StringValue('https://tools.ietf.org/html/rfc3986'),
            ),
          ],
        ),
      ],
    );
    expect(scalar.specifiedByUrl, 'https://tools.ietf.org/html/rfc3986');
    expect(ScalarType('Date').specifiedByUrl, isNull);
  });

  test('an input object type is one-of only with @oneOf', () {
    final oneOf = AppliedDirective('oneOf');
    expect(InputObjectType('A', appliedDirectives: [oneOf]).isOneOf, isTrue);
    expect(InputObjectType('B').isOneOf, isFalse);
  });

  test('a union keeps a repeated member for validation to report', () {
    const member = NamedType(Name('A'));
    final union = UnionType('U', memberTypes: [member, member]);
    expect(union.memberTypes, hasLength(2));
  });

  test('the lists of a type cannot be modified', () {
    final type = ObjectType('T');
    expect(
      () => type.fields.add(SchemaField('a', string)),
      throwsUnsupportedError,
    );
    expect(
      () => type.interfaces.add(const NamedType(Name('I'))),
      throwsUnsupportedError,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/model/schema_type_test.dart)
```

Expected: FAIL. `Error: 'SchemaType' isn't a type.`, `Error: 'ObjectType' isn't a type.` and `Error: Method not found: 'ScalarType'.`

- [ ] **Step 3: Write the implementation**

One sealed family in one library (the code rules allow a sealed family per file). The family is `SchemaType`, not the spec's `NamedType`, because `NamedType` is already the language node of a type reference (see "Spec deviations and findings", 1).

Create `packages/typed_graphql/lib/src/schema/model/schema_type.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';
import 'input_value.dart';
import 'schema_enum_value.dart';
import 'schema_field.dart';

/// A named type of a schema (spec §3.4): the sealed `NamedType` family of
/// R2.1.
///
/// The language node `NamedType` is a reference to a type by name; this
/// is the type itself. References between types are names, so a cyclic
/// schema needs no `late`.
sealed class SchemaType(
  /// The type name.
  final String name, {

  /// The description, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL. An
  /// extension does not move it.
  final SourceSpan? span,
}) {
  /// Creates a named type.
  this;

  /// The directives applied to it, its extensions' included, in the order
  /// written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The field of [fields] named [name], for object and interface types.
  static SchemaField? _fieldIn(List<SchemaField> fields, String name) {
    for (final field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }
}

/// A scalar type, `scalar Name @specifiedBy(url: "...")` (spec §3.5).
final class ScalarType(
  super.name, {
  super.description,
  super.appliedDirectives,
  super.span,
}) extends SchemaType {
  /// Creates a scalar type.
  this;

  /// The `url` of `@specifiedBy`; null without one.
  String? get specifiedByUrl =>
      AppliedDirectives(appliedDirectives).specifiedByUrl;
}

/// An object type, `type Name implements I { fields }` (spec §3.6).
final class ObjectType(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.appliedDirectives,
  List<SchemaField> fields = const [],
  super.span,
}) extends SchemaType {
  /// Creates an object type.
  this;

  /// The interfaces it implements, by name, in declaration order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in declaration order.
  final List<SchemaField> fields = List.unmodifiable(fields);

  /// The field named [name]; null when there is none.
  SchemaField? fieldNamed(String name) => SchemaType._fieldIn(fields, name);
}

/// An interface type, `interface Name implements I { fields }` (spec
/// §3.7).
final class InterfaceType(
  super.name, {
  super.description,
  List<NamedType> interfaces = const [],
  super.appliedDirectives,
  List<SchemaField> fields = const [],
  super.span,
}) extends SchemaType {
  /// Creates an interface type.
  this;

  /// The interfaces it implements, by name, in declaration order.
  final List<NamedType> interfaces = List.unmodifiable(interfaces);

  /// The fields, in declaration order.
  final List<SchemaField> fields = List.unmodifiable(fields);

  /// The field named [name]; null when there is none.
  SchemaField? fieldNamed(String name) => SchemaType._fieldIn(fields, name);
}

/// A union type, `union Name = A | B` (spec §3.8).
final class UnionType(
  super.name, {
  super.description,
  super.appliedDirectives,
  List<NamedType> memberTypes = const [],
  super.span,
}) extends SchemaType {
  /// Creates a union type.
  this;

  /// The member types, by name, in declaration order; a repeated member
  /// is kept for schema validation to report.
  final List<NamedType> memberTypes = List.unmodifiable(memberTypes);
}

/// An enum type, `enum Name { VALUES }` (spec §3.9).
final class EnumType(
  super.name, {
  super.description,
  super.appliedDirectives,
  List<SchemaEnumValue> values = const [],
  super.span,
}) extends SchemaType {
  /// Creates an enum type.
  this;

  /// The values, in declaration order.
  final List<SchemaEnumValue> values = List.unmodifiable(values);

  /// The value named [name]; null when there is none.
  SchemaEnumValue? valueNamed(String name) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return null;
  }
}

/// An input object type, `input Name @oneOf { fields }` (spec §3.10).
final class InputObjectType(
  super.name, {
  super.description,
  super.appliedDirectives,
  List<InputValue> fields = const [],
  super.span,
}) extends SchemaType {
  /// Creates an input object type.
  this;

  /// The input fields, in declaration order.
  final List<InputValue> fields = List.unmodifiable(fields);

  /// Whether `@oneOf` is applied: exactly one field must be given (spec
  /// §3.10.1).
  bool get isOneOf => AppliedDirectives(appliedDirectives).isOneOf;

  /// The input field named [name]; null when there is none.
  InputValue? fieldNamed(String name) {
    for (final field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }
}
```

In `packages/typed_graphql/lib/src/schema/model/applied_directives.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -16,7 +16,7 @@ final class const AppliedDirectives(
   this;
 
   /// The reason `@deprecated` gives when it has no `reason` argument
-  /// (spec §3.13, "@deprecated").
+  /// (spec §3.13.3).
   static const String defaultDeprecationReason = 'No longer supported';
 
   /// The reason of the first `@deprecated`: its `reason` string, or
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -64,3 +64,4 @@ export 'src/schema/model/input_value.dart';
 export 'src/schema/model/schema_directive.dart';
 export 'src/schema/model/schema_enum_value.dart';
 export 'src/schema/model/schema_field.dart';
+export 'src/schema/model/schema_type.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/model/schema_type_test.dart)
```

Expected: `+8: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -69,3 +69,6 @@
 - Schema model elements: `SchemaField`, `InputValue`, `SchemaEnumValue`,
   `SchemaDirective` and `AppliedDirective`, with `deprecationReason` read
   from `@deprecated` and lookups of arguments by name.
+- `SchemaType`, the sealed family of named types: `ScalarType`
+  (`specifiedByUrl`), `ObjectType`, `InterfaceType`, `UnionType`,
+  `EnumType` and `InputObjectType` (`isOneOf`), with lookups by name.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -171,7 +171,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `SchemaEnumValue`, `SchemaDirective` and `AppliedDirective`; the spec's
   names `FieldDefinition`, `EnumValueDefinition`, `DirectiveDefinition` and
   `NamedType` already name language nodes, so the schema's take a
-  `Schema` prefix. Types are language `TypeRef` nodes, resolved by name;
+  `Schema` prefix. `SchemaType` is the sealed family of named types
+  (`ScalarType`, `ObjectType`, `InterfaceType`, `UnionType`, `EnumType`,
+  `InputObjectType`). Types are language `TypeRef` nodes (implemented
+  interfaces and union members `NamedType` nodes), resolved by name;
   defaults and directive arguments are constant language `Value` nodes.
   Every element has `SourceSpan? span`. `deprecationReason`,
   `specifiedByUrl` and `isOneOf` read the applied directives through the
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/model/applied_directives.dart packages/typed_graphql/lib/src/schema/model/schema_type.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/model/schema_type_test.dart
git commit -q -m "feat(typed_graphql): add the sealed family of schema types" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 3: Read type-system definitions into schema elements

The node-to-element readers that the builder (Tasks 6–11) and the built-ins (Task 4) share.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/element_reader.dart`, `packages/typed_graphql/lib/src/schema/build/node_spans.dart`, `packages/typed_graphql/lib/src/schema/build/type_reader.dart`
- Test: `packages/typed_graphql/test/schema/build/element_reader_test.dart`, `packages/typed_graphql/test/schema/build/type_reader_test.dart`, `packages/typed_graphql/test/schema/sdl.dart`

**Interfaces:**
- Consumes: Tasks 1–2: the model; M2a: the type-system definition nodes, `Parser`, `ParserOptions(allowDirectiveExtensions:)`, `Source`, `SourceSpan`.
- Produces:
  - internal `final class const NodeSpans(Source? source)` with `SourceSpan? of(Node node)`;
  - internal `final class const ElementReader(NodeSpans spans)` with `field`, `inputValue`, `enumValue`, `directive` (one node to one element) and `List<AppliedDirective> appliedAll(List<Directive> nodes)`;
  - internal `final class const TypeReader(ElementReader elements)` with `SchemaType type(TypeDefinition node)`;
  - test helper `Sdl(String text)` in `test/schema/sdl.dart` with `source`, `document` and `List<T> all<T extends Definition>()`.

- [ ] **Step 1: Write the test helper**

`Sdl` parses a text named `schema.graphql` with directive extensions on, and fails the test on a syntax error. Every builder test from here on uses it.

Create `packages/typed_graphql/test/schema/sdl.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// An SDL text parsed for a schema test: its [source] and its [document],
/// which the test expects to have no syntax errors.
final class Sdl {
  /// Parses [text], named `schema.graphql`; directive extensions are on,
  /// as the working draft allows them.
  Sdl(String text) : this._(Source(text, name: 'schema.graphql'));

  Sdl._(this.source) : document = _parse(source);

  /// The parsed text.
  final Source source;

  /// The parsed document.
  final Document document;

  /// The definitions of [document] of type [T], in order.
  List<T> all<T extends Definition>() =>
      document.definitions.whereType<T>().toList();

  static Document _parse(Source source) {
    const parser = Parser(
      options: ParserOptions(allowDirectiveExtensions: true),
    );
    return switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final diagnostics) => fail('$diagnostics'),
    };
  }
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/typed_graphql/test/schema/build/element_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/element_reader.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../sdl.dart';

void main() {
  group('NodeSpans', () {
    test('gives the span of a node in the source', () {
      final source = Source('type Query');
      final span = NodeSpans(source).of(const Name('Query', start: 5, end: 10));
      expect(span, SourceSpan(source, 5, 10));
      expect(span?.text, 'Query');
    });

    test('gives no span without a source', () {
      expect(const NodeSpans(null).of(const Name('Query')), isNull);
    });
  });

  group('ElementReader', () {
    final sdl = Sdl('''
type Query {
  "The hero"
  hero(episode: Episode = JEDI @deprecated, limit: [Int!]): Character @auth(role: "x")
}

enum Episode {
  """Star Wars"""
  NEWHOPE @deprecated(reason: "old")
}

"Marks a field"
directive @auth(role: String) repeatable on FIELD_DEFINITION | OBJECT
''');
    final reader = ElementReader(NodeSpans(sdl.source));
    final type = sdl.all<ObjectTypeDefinition>().single;
    final field = reader.field(type.fields.single);

    test('reads a field with its description, type and arguments', () {
      expect(field.name, 'hero');
      expect(field.description, 'The hero');
      expect(const Printer().print(field.type), 'Character');
      expect(field.arguments.map((argument) => argument.name), [
        'episode',
        'limit',
      ]);
      expect(const Printer().print(field.arguments[1].type), '[Int!]');
    });

    test('keeps a default value as its language node', () {
      final defaultValue = field.arguments.first.defaultValue;
      expect(defaultValue, isA<EnumValue>());
      expect(const Printer().print(defaultValue!), 'JEDI');
      expect(field.arguments[1].defaultValue, isNull);
    });

    test('reads applied directives with their arguments', () {
      expect(field.appliedDirectives.single.name, 'auth');
      expect(
        field.appliedDirectives.single.argument('role'),
        isA<StringValue>(),
      );
      expect(field.arguments.first.deprecationReason, 'No longer supported');
    });

    test('gives every element the span of its node', () {
      expect(field.span?.text, startsWith('"The hero"\n  hero('));
      expect(field.span?.text, endsWith('@auth(role: "x")'));
      expect(
        field.arguments.first.span?.text,
        'episode: Episode = JEDI '
        '@deprecated',
      );
      expect(field.appliedDirectives.single.span?.text, '@auth(role: "x")');
    });

    test('reads an enum value', () {
      final node = sdl.all<EnumTypeDefinition>().single.values.single;
      final value = reader.enumValue(node);
      expect(value.name, 'NEWHOPE');
      expect(value.description, 'Star Wars');
      expect(value.deprecationReason, 'old');
    });

    test('reads a directive definition', () {
      final node = sdl.all<DirectiveDefinition>().single;
      final directive = reader.directive(node);
      expect(directive.name, 'auth');
      expect(directive.description, 'Marks a field');
      expect(directive.isRepeatable, isTrue);
      expect(directive.locations, ['FIELD_DEFINITION', 'OBJECT']);
      expect(directive.arguments.single.name, 'role');
      expect(directive.span?.location, const SourceLocation(11, 1));
    });

    test('gives no spans without a source', () {
      const reader = ElementReader(NodeSpans(null));
      final field = reader.field(type.fields.single);
      expect(field.span, isNull);
      expect(field.arguments.first.span, isNull);
    });
  });
}
```

Create `packages/typed_graphql/test/schema/build/type_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/element_reader.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/src/schema/build/type_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../sdl.dart';

void main() {
  final sdl = Sdl('''
"A date" scalar Date @specifiedBy(url: "https://example.com/date")
type Query implements Node & Entity @key { id: ID! when: Date }
interface Node implements Entity { id: ID! }
union Result @tag = Query | Other
enum Color { RED GREEN }
input Filter @oneOf { color: Color = RED, limit: Int }
''');
  final reader = TypeReader(ElementReader(NodeSpans(sdl.source)));
  final types = sdl.all<TypeDefinition>().map(reader.type).toList();

  test('reads each definition into a type of its kind', () {
    expect(types.map((type) => type.name), [
      'Date',
      'Query',
      'Node',
      'Result',
      'Color',
      'Filter',
    ]);
    expect(types[0], isA<ScalarType>());
    expect(types[1], isA<ObjectType>());
    expect(types[2], isA<InterfaceType>());
    expect(types[3], isA<UnionType>());
    expect(types[4], isA<EnumType>());
    expect(types[5], isA<InputObjectType>());
  });

  test('reads a scalar with its description and @specifiedBy', () {
    final date = types[0] as ScalarType;
    expect(date.description, 'A date');
    expect(date.specifiedByUrl, 'https://example.com/date');
  });

  test('keeps implemented interfaces and union members as names', () {
    final query = types[1] as ObjectType;
    expect(query.interfaces.map((type) => type.name.value), [
      'Node',
      'Entity',
    ]);
    final node = types[2] as InterfaceType;
    expect(node.interfaces.single.name.value, 'Entity');
    final result = types[3] as UnionType;
    expect(result.memberTypes.map((type) => type.name.value), [
      'Query',
      'Other',
    ]);
  });

  test('reads the members of each kind', () {
    expect((types[1] as ObjectType).fields.map((field) => field.name), [
      'id',
      'when',
    ]);
    expect((types[4] as EnumType).values.map((value) => value.name), [
      'RED',
      'GREEN',
    ]);
    final filter = types[5] as InputObjectType;
    expect(filter.fields.map((field) => field.name), ['color', 'limit']);
    expect(filter.isOneOf, isTrue);
  });

  test('reads the directives applied to a type', () {
    expect(types[1].appliedDirectives.single.name, 'key');
    expect(types[3].appliedDirectives.single.name, 'tag');
  });

  test('gives a type the span of its whole definition', () {
    expect(types[0].span?.text, startsWith('"A date" scalar Date'));
    expect(types[4].span?.text, 'enum Color { RED GREEN }');
  });
}
```

- [ ] **Step 3: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/element_reader_test.dart test/schema/build/type_reader_test.dart)
```

Expected: FAIL. `Error: Error when reading 'lib/src/schema/build/element_reader.dart': No such file or directory`, the same for `node_spans.dart` and `type_reader.dart`, and `Error: Method not found: 'NodeSpans'.`

- [ ] **Step 4: Write the implementation**

The readers turn one language node into one model element, with no checks: problems are the builder's (Tasks 6–11). `NodeSpans` gives a node's `SourceSpan` when the source is known and `null` otherwise. All three are internal: none goes into the barrel.

Create `packages/typed_graphql/lib/src/schema/build/node_spans.dart`:

```dart
import '../../diagnostics/source.dart';
import '../../diagnostics/source_span.dart';
import '../../language/ast/node.dart';

/// Turns the offsets of syntax nodes into spans of the [source] they were
/// parsed from.
///
/// A document carries no source, so the builder is given one; without it
/// (a document built in code) every span is null.
final class const NodeSpans(
  /// The text the nodes were parsed from; null when unknown.
  final Source? source,
) {
  /// Creates the spans of nodes parsed from [source].
  this;

  /// The span of [node]; null without a [source].
  SourceSpan? of(Node node) => switch (source) {
    final source? => SourceSpan(source, node.start, node.end),
    null => null,
  };
}
```

Create `packages/typed_graphql/lib/src/schema/build/element_reader.dart`:

```dart
import '../../language/ast/directive.dart';
import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/type_system_definition.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_directive.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';
import 'node_spans.dart';

/// Reads the members of type-system definitions into schema elements:
/// fields, input values, enum values, applied directives and directive
/// definitions, each with its span.
final class const ElementReader(
  /// Gives each element the span of its node.
  final NodeSpans spans,
) {
  /// Creates a reader.
  this;

  /// A field definition, with its arguments.
  SchemaField field(FieldDefinition node) => SchemaField(
    node.name.value,
    node.type,
    description: node.description?.value,
    arguments: node.arguments.map(inputValue).toList(),
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// An argument or input field definition.
  InputValue inputValue(InputValueDefinition node) => InputValue(
    node.name.value,
    node.type,
    description: node.description?.value,
    defaultValue: node.defaultValue,
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// An enum value definition.
  SchemaEnumValue enumValue(EnumValueDefinition node) => SchemaEnumValue(
    node.name.value,
    description: node.description?.value,
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );

  /// The directives applied to an element, in order.
  List<AppliedDirective> appliedAll(List<Directive> nodes) => [
    for (final node in nodes)
      AppliedDirective(
        node.name.value,
        arguments: node.arguments,
        span: spans.of(node),
      ),
  ];

  /// A directive definition, with its arguments and locations.
  SchemaDirective directive(DirectiveDefinition node) => SchemaDirective(
    node.name.value,
    description: node.description?.value,
    arguments: node.arguments.map(inputValue).toList(),
    isRepeatable: node.isRepeatable,
    locations: [for (final location in node.locations) location.value],
    appliedDirectives: appliedAll(node.directives),
    span: spans.of(node),
  );
}
```

Create `packages/typed_graphql/lib/src/schema/build/type_reader.dart`:

```dart
import '../../language/ast/type_system_definition.dart';
import '../model/schema_type.dart';
import 'element_reader.dart';

/// Reads a type definition into a [SchemaType] of the same kind, with its
/// members and span.
final class const TypeReader(
  /// Reads the members and gives the spans.
  final ElementReader elements,
) {
  /// Creates a reader.
  this;

  /// The schema type [node] defines.
  SchemaType type(TypeDefinition node) => switch (node) {
    ScalarTypeDefinition() => ScalarType(
      node.name.value,
      description: node.description?.value,
      appliedDirectives: elements.appliedAll(node.directives),
      span: elements.spans.of(node),
    ),
    ObjectTypeDefinition() => _object(node),
    InterfaceTypeDefinition() => _interface(node),
    UnionTypeDefinition() => UnionType(
      node.name.value,
      description: node.description?.value,
      appliedDirectives: elements.appliedAll(node.directives),
      memberTypes: node.types,
      span: elements.spans.of(node),
    ),
    EnumTypeDefinition() => _enum(node),
    InputObjectTypeDefinition() => _inputObject(node),
  };

  ObjectType _object(ObjectTypeDefinition node) => ObjectType(
    node.name.value,
    description: node.description?.value,
    interfaces: node.interfaces,
    appliedDirectives: elements.appliedAll(node.directives),
    fields: node.fields.map(elements.field).toList(),
    span: elements.spans.of(node),
  );

  InterfaceType _interface(InterfaceTypeDefinition node) => InterfaceType(
    node.name.value,
    description: node.description?.value,
    interfaces: node.interfaces,
    appliedDirectives: elements.appliedAll(node.directives),
    fields: node.fields.map(elements.field).toList(),
    span: elements.spans.of(node),
  );

  EnumType _enum(EnumTypeDefinition node) => EnumType(
    node.name.value,
    description: node.description?.value,
    appliedDirectives: elements.appliedAll(node.directives),
    values: node.values.map(elements.enumValue).toList(),
    span: elements.spans.of(node),
  );

  InputObjectType _inputObject(InputObjectTypeDefinition node) =>
      InputObjectType(
        node.name.value,
        description: node.description?.value,
        appliedDirectives: elements.appliedAll(node.directives),
        fields: node.fields.map(elements.inputValue).toList(),
        span: elements.spans.of(node),
      );
}
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/element_reader_test.dart test/schema/build/type_reader_test.dart)
```

Expected: `element_reader_test.dart` `+9`, `type_reader_test.dart` `+6`, each `All tests passed!`

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql/lib/src/schema/build/element_reader.dart packages/typed_graphql/lib/src/schema/build/node_spans.dart packages/typed_graphql/lib/src/schema/build/type_reader.dart packages/typed_graphql/test/schema/build/element_reader_test.dart packages/typed_graphql/test/schema/build/type_reader_test.dart packages/typed_graphql/test/schema/sdl.dart
git commit -q -m "feat(typed_graphql): read type-system definitions into schema elements" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 4: Built-in scalars, directives and introspection types

R2.6 and spec §3 "Built-ins": what every schema has without declaring it.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart`, `packages/typed_graphql/lib/src/schema/build/built_ins.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/build/built_ins_test.dart`

**Interfaces:**
- Consumes: Task 3: `TypeReader`, `ElementReader`, `NodeSpans`; M2a: `Parser`.
- Produces:
  - `final class const BuiltIns()` with `List<ScalarType> scalars`, `List<SchemaDirective> directives` (the five specified ones), `SchemaDirective defer`, `SchemaDirective stream`, `List<SchemaType> introspectionTypes`, `ScalarType? scalarNamed(String)`, `SchemaType? typeNamed(String)` (scalars and introspection types), `SchemaDirective? directiveNamed(String)` (the five);
  - internal `final class const BuiltInSdl()` with `String text`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/build/built_ins_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const builtIns = BuiltIns();

  test('has the five scalars of the spec, in its order', () {
    expect(builtIns.scalars.map((scalar) => scalar.name), [
      'String',
      'Int',
      'Float',
      'Boolean',
      'ID',
    ]);
    expect(builtIns.scalarNamed('Int')?.description, startsWith('The `Int`'));
    expect(builtIns.scalarNamed('Date'), isNull);
  });

  test('has the five directives of the spec, in its order', () {
    expect(builtIns.directives.map((directive) => directive.name), [
      'include',
      'skip',
      'deprecated',
      'specifiedBy',
      'oneOf',
    ]);
    expect(builtIns.directiveNamed('defer'), isNull);
  });

  test('defines @deprecated as September2025 does', () {
    final deprecated = builtIns.directiveNamed('deprecated')!;
    expect(deprecated.locations, [
      'FIELD_DEFINITION',
      'ARGUMENT_DEFINITION',
      'INPUT_FIELD_DEFINITION',
      'ENUM_VALUE',
    ]);
    final reason = deprecated.argumentNamed('reason')!;
    expect(const Printer().print(reason.type), 'String!');
    expect(
      const Printer().print(reason.defaultValue!),
      '"No longer supported"',
    );
  });

  test('keeps @defer and @stream apart, as graphql-js defines them', () {
    expect(builtIns.defer.name, 'defer');
    expect(builtIns.defer.arguments.map((argument) => argument.name), [
      'if',
      'label',
    ]);
    expect(builtIns.stream.locations, ['FIELD']);
    expect(builtIns.stream.arguments.map((argument) => argument.name), [
      'initialCount',
      'if',
      'label',
    ]);
  });

  test('has the introspection types of the spec, in its order', () {
    expect(builtIns.introspectionTypes.map((type) => type.name), [
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

  test('leaves out the working-draft introspection additions', () {
    final directive = builtIns.introspectionTypes[6] as ObjectType;
    expect(directive.fieldNamed('isDeprecated'), isNull);
    final locations = builtIns.introspectionTypes[7] as EnumType;
    expect(locations.values, hasLength(19));
    expect(locations.valueNamed('DIRECTIVE_DEFINITION'), isNull);
  });

  test('declares includeDeprecated as Boolean! = false everywhere', () {
    final type = builtIns.introspectionTypes[1] as ObjectType;
    final field = builtIns.introspectionTypes[3] as ObjectType;
    final directive = builtIns.introspectionTypes[6] as ObjectType;
    final arguments = [
      type.fieldNamed('fields')!.argumentNamed('includeDeprecated'),
      type.fieldNamed('enumValues')!.argumentNamed('includeDeprecated'),
      type.fieldNamed('inputFields')!.argumentNamed('includeDeprecated'),
      field.fieldNamed('args')!.argumentNamed('includeDeprecated'),
      directive.fieldNamed('args')!.argumentNamed('includeDeprecated'),
    ];
    for (final argument in arguments) {
      expect(const Printer().print(argument!.type), 'Boolean!');
      expect(const Printer().print(argument.defaultValue!), 'false');
    }
  });

  test('gives the specified directives their locations', () {
    const common = ['FIELD', 'FRAGMENT_SPREAD', 'INLINE_FRAGMENT'];
    expect(builtIns.directiveNamed('include')!.locations, common);
    expect(builtIns.directiveNamed('skip')!.locations, common);
    expect(builtIns.directiveNamed('specifiedBy')!.locations, ['SCALAR']);
    expect(builtIns.directiveNamed('oneOf')!.locations, ['INPUT_OBJECT']);
  });

  test('types introspection fields with their nullability', () {
    final schema = builtIns.introspectionTypes[0] as ObjectType;
    final type = builtIns.introspectionTypes[1] as ObjectType;
    expect(const Printer().print(type.fieldNamed('kind')!.type), '__TypeKind!');
    expect(const Printer().print(type.fieldNamed('name')!.type), 'String');
    expect(
      const Printer().print(schema.fieldNamed('types')!.type),
      '[__Type!]!',
    );
    expect(
      const Printer().print(schema.fieldNamed('mutationType')!.type),
      '__Type',
    );
  });

  test('lists the values of __TypeKind', () {
    final kinds = builtIns.introspectionTypes[2] as EnumType;
    expect(kinds.values.map((value) => value.name), [
      'SCALAR',
      'OBJECT',
      'INTERFACE',
      'UNION',
      'ENUM',
      'INPUT_OBJECT',
      'LIST',
      'NON_NULL',
    ]);
  });

  test('gives @defer and @stream their argument defaults', () {
    String? defaultOf(SchemaDirective directive, String name) {
      final value = directive.argumentNamed(name)!.defaultValue;
      return value == null ? null : const Printer().print(value);
    }

    expect(defaultOf(builtIns.defer, 'if'), 'true');
    expect(defaultOf(builtIns.defer, 'label'), isNull);
    expect(defaultOf(builtIns.stream, 'initialCount'), '0');
    expect(defaultOf(builtIns.stream, 'if'), 'true');
    expect(builtIns.defer.locations, ['FRAGMENT_SPREAD', 'INLINE_FRAGMENT']);
  });

  test('finds a scalar or an introspection type by name', () {
    expect(builtIns.typeNamed('ID'), same(builtIns.scalarNamed('ID')));
    expect(builtIns.typeNamed('__Field'), same(builtIns.introspectionTypes[3]));
    expect(builtIns.typeNamed('Query'), isNull);
  });

  test('has no spans: nothing was read from a user source', () {
    expect(builtIns.scalars.first.span, isNull);
    expect(builtIns.directives.first.span, isNull);
    expect(builtIns.directives.first.arguments.single.span, isNull);
  });

  test('gives the same instances on every call', () {
    expect(const BuiltIns().scalars.first, same(builtIns.scalars.first));
    expect(builtIns.defer, same(const BuiltIns().defer));
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/built_ins_test.dart)
```

Expected: FAIL. `Error: Method not found: 'BuiltIns'.` and `Error: Couldn't find constructor 'BuiltIns'.`

- [ ] **Step 3: Write the built-in SDL**

The built-ins are written once, as SDL, and read with Task 3's readers, so they cannot drift from what the builder reads. The text is the September2025 edition: five scalars, `@include`, `@skip`, `@deprecated`, `@specifiedBy`, `@oneOf`, then `@defer` and `@stream` as graphql-js defines them, and the eight introspection types without the working-draft additions. The file has 293 lines, most of them the SDL text.

Create `packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart`:

```dart
/// The SDL of the built-in definitions: the definitions of the September2025
/// spec (Appendix D) with graphql-js 17's descriptions, then `@defer` and
/// `@stream` as graphql-js defines them.
///
/// graphql-js 17 also has working-draft additions (deprecated directives,
/// fragment variables, `includeDeprecated` on `__Schema.directives`,
/// `isDeprecated` and `deprecationReason` on `__Directive` and the
/// `DIRECTIVE_DEFINITION` location); this text follows the September2025
/// edition (R0.1) and omits them.
final class const BuiltInSdl() {
  /// Creates the text holder.
  this;

  /// The built-in scalars, directives and introspection types, in the
  /// order of Appendix D, then `@defer` and `@stream`.
  String get text => _text;

  static const String _text = '''
"""
The `String` scalar type represents textual data, represented as UTF-8 character sequences. The String type is most often used by GraphQL to represent free-form human-readable text.
"""
scalar String

"""
The `Int` scalar type represents non-fractional signed whole numeric values. Int can represent values between -(2^31) and 2^31 - 1.
"""
scalar Int

"""
The `Float` scalar type represents signed double-precision fractional values as specified by [IEEE 754](https://en.wikipedia.org/wiki/IEEE_floating_point).
"""
scalar Float

"""The `Boolean` scalar type represents `true` or `false`."""
scalar Boolean

"""
The `ID` scalar type represents a unique identifier, often used to refetch an object or as key for a cache. The ID type appears in a JSON response as a String; however, it is not intended to be human-readable. When expected as an input type, any string (such as `"4"`) or integer (such as `4`) input value will be accepted as an ID.
"""
scalar ID

"""
Directs the executor to include this field or fragment only when the `if` argument is true.
"""
directive @include(
  """Included when true."""
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

"""
Directs the executor to skip this field or fragment when the `if` argument is true.
"""
directive @skip(
  """Skipped when true."""
  if: Boolean!
) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

"""Marks an element of a GraphQL schema as no longer supported."""
directive @deprecated(
  """
  Explains why this element was deprecated, usually also including a suggestion for how to access supported similar data. Formatted using the Markdown syntax, as specified by [CommonMark](https://commonmark.org/).
  """
  reason: String! = "No longer supported"
) on FIELD_DEFINITION | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | ENUM_VALUE

"""Exposes a URL that specifies the behavior of this scalar."""
directive @specifiedBy(
  """The URL that specifies the behavior of this scalar."""
  url: String!
) on SCALAR

"""
Indicates exactly one field must be supplied and this field must not be `null`.
"""
directive @oneOf on INPUT_OBJECT

"""
A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.
"""
type __Schema {
  description: String

  """A list of all types supported by this server."""
  types: [__Type!]!

  """The type that query operations will be rooted at."""
  queryType: __Type!

  """
  If this server supports mutation, the type that mutation operations will be rooted at.
  """
  mutationType: __Type

  """
  If this server support subscription, the type that subscription operations will be rooted at.
  """
  subscriptionType: __Type

  """A list of all directives supported by this server."""
  directives: [__Directive!]!
}

"""
The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.

Depending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.
"""
type __Type {
  kind: __TypeKind!
  name: String
  description: String
  specifiedByURL: String
  fields(includeDeprecated: Boolean! = false): [__Field!]
  interfaces: [__Type!]
  possibleTypes: [__Type!]
  enumValues(includeDeprecated: Boolean! = false): [__EnumValue!]
  inputFields(includeDeprecated: Boolean! = false): [__InputValue!]
  ofType: __Type
  isOneOf: Boolean
}

"""An enum describing what kind of type a given `__Type` is."""
enum __TypeKind {
  """Indicates this type is a scalar."""
  SCALAR

  """
  Indicates this type is an object. `fields` and `interfaces` are valid fields.
  """
  OBJECT

  """
  Indicates this type is an interface. `fields`, `interfaces`, and `possibleTypes` are valid fields.
  """
  INTERFACE

  """Indicates this type is a union. `possibleTypes` is a valid field."""
  UNION

  """Indicates this type is an enum. `enumValues` is a valid field."""
  ENUM

  """
  Indicates this type is an input object. `inputFields` is a valid field.
  """
  INPUT_OBJECT

  """Indicates this type is a list. `ofType` is a valid field."""
  LIST

  """Indicates this type is a non-null. `ofType` is a valid field."""
  NON_NULL
}

"""
Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.
"""
type __Field {
  name: String!
  description: String
  args(includeDeprecated: Boolean! = false): [__InputValue!]!
  type: __Type!
  isDeprecated: Boolean!
  deprecationReason: String
}

"""
Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.
"""
type __InputValue {
  name: String!
  description: String
  type: __Type!

  """
  A GraphQL-formatted string representing the default value for this input value.
  """
  defaultValue: String
  isDeprecated: Boolean!
  deprecationReason: String
}

"""
One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.
"""
type __EnumValue {
  name: String!
  description: String
  isDeprecated: Boolean!
  deprecationReason: String
}

"""
A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.

In some cases, you need to provide options to alter GraphQL's execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.
"""
type __Directive {
  name: String!
  description: String
  isRepeatable: Boolean!
  locations: [__DirectiveLocation!]!
  args(includeDeprecated: Boolean! = false): [__InputValue!]!
}

"""
A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.
"""
enum __DirectiveLocation {
  """Location adjacent to a query operation."""
  QUERY

  """Location adjacent to a mutation operation."""
  MUTATION

  """Location adjacent to a subscription operation."""
  SUBSCRIPTION

  """Location adjacent to a field."""
  FIELD

  """Location adjacent to a fragment definition."""
  FRAGMENT_DEFINITION

  """Location adjacent to a fragment spread."""
  FRAGMENT_SPREAD

  """Location adjacent to an inline fragment."""
  INLINE_FRAGMENT

  """Location adjacent to an operation variable definition."""
  VARIABLE_DEFINITION

  """Location adjacent to a schema definition."""
  SCHEMA

  """Location adjacent to a scalar definition."""
  SCALAR

  """Location adjacent to an object type definition."""
  OBJECT

  """Location adjacent to a field definition."""
  FIELD_DEFINITION

  """Location adjacent to an argument definition."""
  ARGUMENT_DEFINITION

  """Location adjacent to an interface definition."""
  INTERFACE

  """Location adjacent to a union definition."""
  UNION

  """Location adjacent to an enum definition."""
  ENUM

  """Location adjacent to an enum value definition."""
  ENUM_VALUE

  """Location adjacent to an input object type definition."""
  INPUT_OBJECT

  """Location adjacent to an input object field definition."""
  INPUT_FIELD_DEFINITION
}

"""
Directs the executor to defer this fragment when the `if` argument is true or undefined.
"""
directive @defer(
  """Deferred when true or undefined."""
  if: Boolean! = true

  """Unique name"""
  label: String
) on FRAGMENT_SPREAD | INLINE_FRAGMENT

"""
Directs the executor to stream plural fields when the `if` argument is true or undefined.
"""
directive @stream(
  """Number of items to return immediately"""
  initialCount: Int! = 0

  """Stream when true or undefined."""
  if: Boolean! = true

  """Unique name"""
  label: String
) on FIELD
''';
}
```

- [ ] **Step 4: Write the implementation**

The parsed text and the elements are `static final`, so every call gives the same instances. The text is a constant of this library, so a parse failure is a programmer error (`StateError`).

Create `packages/typed_graphql/lib/src/schema/build/built_ins.dart`:

```dart
import '../../diagnostics/source.dart';
import '../../language/ast/document.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/parser/parse_result.dart';
import '../../language/parser/parser.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import 'built_in_sdl.dart';
import 'element_reader.dart';
import 'node_spans.dart';
import 'type_reader.dart';

/// The definitions every schema has without declaring them (spec §3.5,
/// §3.13, §4.5; R2.6): the five scalars, the five directives and the
/// introspection types, and the opt-in `@defer` and `@stream`.
///
/// They are read once from [BuiltInSdl] and have no spans. `Schema` finds
/// the scalars and directives by name; the SDL printer prints them only
/// when asked.
final class const BuiltIns() {
  /// Creates the accessor; the definitions are shared.
  this;

  static const TypeReader _reader = TypeReader(ElementReader(NodeSpans(null)));

  static final Document _document = switch (const Parser().parse(
    Source(const BuiltInSdl().text, name: 'built-ins'),
  )) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };

  static final List<SchemaType> _types = [
    for (final definition in _document.definitions.whereType<TypeDefinition>())
      _reader.type(definition),
  ];

  static final List<SchemaDirective> _allDirectives = [
    for (final definition
        in _document.definitions.whereType<DirectiveDefinition>())
      _reader.elements.directive(definition),
  ];

  static final List<ScalarType> _scalars = List.unmodifiable(
    _types.whereType<ScalarType>(),
  );

  static final SchemaDirective _defer = _directiveNamed('defer');

  static final SchemaDirective _stream = _directiveNamed('stream');

  // The five specified directives are all but the two opt-in ones, so the
  // SDL order of `@defer` and `@stream` cannot swap them.
  static final List<SchemaDirective> _directives = List.unmodifiable(
    _allDirectives.where(
      (directive) => directive != _defer && directive != _stream,
    ),
  );

  static SchemaDirective _directiveNamed(String name) =>
      _allDirectives.singleWhere((directive) => directive.name == name);

  static final List<SchemaType> _introspectionTypes = List.unmodifiable(
    _types.where((type) => type is! ScalarType),
  );

  /// `String`, `Int`, `Float`, `Boolean` and `ID`, in that order.
  List<ScalarType> get scalars => _scalars;

  /// `@include`, `@skip`, `@deprecated`, `@specifiedBy` and `@oneOf`, in
  /// that order.
  List<SchemaDirective> get directives => _directives;

  /// `@defer`, added to a schema only by an opt-in.
  SchemaDirective get defer => _defer;

  /// `@stream`, added to a schema only by an opt-in.
  SchemaDirective get stream => _stream;

  /// `__Schema`, `__Type`, `__TypeKind`, `__Field`, `__InputValue`,
  /// `__EnumValue`, `__Directive` and `__DirectiveLocation`, in that order.
  List<SchemaType> get introspectionTypes => _introspectionTypes;

  /// The built-in scalar named [name]; null when there is none.
  ScalarType? scalarNamed(String name) {
    for (final scalar in scalars) {
      if (scalar.name == name) {
        return scalar;
      }
    }
    return null;
  }

  /// The built-in scalar or introspection type named [name]; null when
  /// there is none.
  SchemaType? typeNamed(String name) {
    for (final type in _types) {
      if (type.name == name) {
        return type;
      }
    }
    return null;
  }

  /// The built-in directive named [name], among [directives]; null when
  /// there is none (`@defer` and `@stream` are not built in by default).
  SchemaDirective? directiveNamed(String name) {
    for (final directive in directives) {
      if (directive.name == name) {
        return directive;
      }
    }
    return null;
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -59,6 +59,7 @@ export 'src/protocol/json_reader.dart';
 export 'src/protocol/json_value.dart';
 export 'src/protocol/path_segment.dart';
 export 'src/protocol/response_payload.dart';
+export 'src/schema/build/built_ins.dart';
 export 'src/schema/model/applied_directive.dart';
 export 'src/schema/model/input_value.dart';
 export 'src/schema/model/schema_directive.dart';
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/built_ins_test.dart)
```

Expected: `+14: All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -72,3 +72,6 @@
 - `SchemaType`, the sealed family of named types: `ScalarType`
   (`specifiedByUrl`), `ObjectType`, `InterfaceType`, `UnionType`,
   `EnumType` and `InputObjectType` (`isOneOf`), with lookups by name.
+- `BuiltIns`: the built-in scalars (`String`, `Int`, `Float`, `Boolean`,
+  `ID`), the five specified directives, `@defer` and `@stream`, and the
+  introspection types of September2025.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -179,6 +179,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   Every element has `SourceSpan? span`. `deprecationReason`,
   `specifiedByUrl` and `isOneOf` read the applied directives through the
   internal `AppliedDirectives`, which stay in the element's list.
+- `build/BuiltIns` (const): the five built-in scalars, the five specified
+  directives, `defer` and `stream` (graphql-js's definitions, not in the
+  specified five) and the introspection types, read once from the internal
+  `BuiltInSdl` text of September2025 Appendix D; they have no span.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/build/built_in_sdl.dart packages/typed_graphql/lib/src/schema/build/built_ins.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/build/built_ins_test.dart
git commit -q -m "feat(typed_graphql): add the built-in scalars, directives and introspection types" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 5: The schema

R2.1 and spec §3: the immutable `Schema`.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/schema.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/schema_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4; M2a: `OperationType`.
- Produces:
  - `final class Schema({List<SchemaType> types = const [], List<SchemaDirective> directives = const [], String? queryTypeName, String? mutationTypeName, String? subscriptionTypeName, String? description, List<AppliedDirective> appliedDirectives = const [], bool includesDeferAndStream = false, SourceSpan? span})`;
  - `SchemaType? typeNamed(String name)` (the first declared, else a built-in), `SchemaDirective? directiveNamed(String name)` (declared, else built-in; `@defer`/`@stream` only with `includesDeferAndStream`), `String? rootTypeName(OperationType operation)`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const builtIns = BuiltIns();

  test('keeps types and directives in declaration order', () {
    final schema = Schema(
      types: [ObjectType('Query'), ScalarType('Date'), EnumType('Color')],
      directives: [SchemaDirective('key'), SchemaDirective('auth')],
    );
    expect(schema.types.map((type) => type.name), ['Query', 'Date', 'Color']);
    expect(schema.directives.map((directive) => directive.name), [
      'key',
      'auth',
    ]);
  });

  test('finds a declared type by name', () {
    final date = ScalarType('Date');
    final schema = Schema(types: [ObjectType('Query'), date]);
    expect(schema.typeNamed('Date'), same(date));
    expect(schema.typeNamed('Time'), isNull);
  });

  test('finds the first of two types with one name', () {
    final first = ScalarType('Date');
    final schema = Schema(types: [first, EnumType('Date')]);
    expect(schema.typeNamed('Date'), same(first));
  });

  test('finds the built-in scalars and introspection types undeclared', () {
    final schema = Schema();
    expect(schema.typeNamed('Int'), same(builtIns.scalarNamed('Int')));
    expect(schema.typeNamed('__Type'), same(builtIns.introspectionTypes[1]));
  });

  test('finds the five specified directives undeclared', () {
    final schema = Schema();
    expect(
      schema.directiveNamed('skip'),
      same(builtIns.directiveNamed('skip')),
    );
    expect(schema.directiveNamed('oneOf'), isNotNull);
    expect(schema.directiveNamed('key'), isNull);
  });

  test('finds @defer and @stream only when they are included', () {
    expect(Schema().directiveNamed('defer'), isNull);
    final schema = Schema(includesDeferAndStream: true);
    expect(schema.directiveNamed('defer'), same(builtIns.defer));
    expect(schema.directiveNamed('stream'), same(builtIns.stream));
  });

  test('prefers a declared directive to a built-in of the same name', () {
    final skip = SchemaDirective('skip');
    expect(Schema(directives: [skip]).directiveNamed('skip'), same(skip));
  });

  test('has no root operation types unless they are named', () {
    final schema = Schema();
    expect(schema.queryTypeName, isNull);
    expect(schema.mutationTypeName, isNull);
    expect(schema.subscriptionTypeName, isNull);
  });

  test('finds the root operation type by operation', () {
    final schema = Schema(
      queryTypeName: 'Root',
      subscriptionTypeName: 'Events',
    );
    expect(schema.rootTypeName(OperationType.query), 'Root');
    expect(schema.rootTypeName(OperationType.mutation), isNull);
    expect(schema.rootTypeName(OperationType.subscription), 'Events');
  });

  test('cannot be changed through its lists', () {
    final schema = Schema(types: [ScalarType('Date')]);
    expect(() => schema.types.add(ScalarType('Time')), throwsUnsupportedError);
    expect(
      () => schema.appliedDirectives.add(AppliedDirective('key')),
      throwsUnsupportedError,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/schema_test.dart)
```

Expected: FAIL. `Error: Method not found: 'Schema'.`

- [ ] **Step 3: Write the implementation**

`types` and `directives` hold only what was declared; `typeNamed` and `directiveNamed` fall back to `BuiltIns`, so every schema finds every built-in without listing it (decision 2). A lookup map is built once and never iterated, so output order stays the declaration order.

Create `packages/typed_graphql/lib/src/schema/schema.dart`:

```dart
import '../diagnostics/source_span.dart';
import '../language/ast/operation_type.dart';
import 'build/built_ins.dart';
import 'model/applied_directive.dart';
import 'model/schema_directive.dart';
import 'model/schema_type.dart';

/// A GraphQL schema (spec §3.3; R2.1): its named types, its directive
/// definitions and its root operation types, immutable.
///
/// It holds what was declared, in declaration order; the built-in scalars,
/// directives and introspection types of [BuiltIns] exist in every schema
/// and are found by [typeNamed] and [directiveNamed] without being listed.
/// Building does not validate: a reference may name a type that does not
/// exist, and a root may name a type of the wrong kind.
final class Schema({
  List<SchemaType> types = const [],
  List<SchemaDirective> directives = const [],

  /// The name of the query root type; null when there is none.
  final String? queryTypeName,

  /// The name of the mutation root type; null when there is none.
  final String? mutationTypeName,

  /// The name of the subscription root type; null when there is none.
  final String? subscriptionTypeName,

  /// The description of the schema definition, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  /// Whether `@defer` and `@stream` exist in this schema (an opt-in, as
  /// graphql-js defines them; R2.6).
  final bool includesDeferAndStream = false,

  /// Where the schema definition was; null without one.
  final SourceSpan? span,
}) {
  /// Creates a schema.
  this;

  /// The declared named types, in declaration order; built-ins are not
  /// listed.
  final List<SchemaType> types = List.unmodifiable(types);

  /// The declared directive definitions, in declaration order; built-ins
  /// are not listed.
  final List<SchemaDirective> directives = List.unmodifiable(directives);

  /// The directives applied to the schema definition and its extensions.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  // Only for lookups, never iterated. Built from the end, so the first of
  // two types with one name wins, as the builder keeps the first.
  final Map<String, SchemaType> _typesByName = {
    for (final type in types.reversed) type.name: type,
  };

  /// The declared type named [name], else the built-in scalar or
  /// introspection type; null when there is none.
  SchemaType? typeNamed(String name) {
    if (_typesByName[name] case final type?) {
      return type;
    }
    return const BuiltIns().typeNamed(name);
  }

  /// The declared directive named [name], else the built-in one; null
  /// when there is none.
  SchemaDirective? directiveNamed(String name) {
    for (final directive in directives) {
      if (directive.name == name) {
        return directive;
      }
    }
    const builtIns = BuiltIns();
    return switch (name) {
      'defer' when includesDeferAndStream => builtIns.defer,
      'stream' when includesDeferAndStream => builtIns.stream,
      _ => builtIns.directiveNamed(name),
    };
  }

  /// The name of the root type of [operation]; null when there is none.
  String? rootTypeName(OperationType operation) => switch (operation) {
    .query => queryTypeName,
    .mutation => mutationTypeName,
    .subscription => subscriptionTypeName,
  };
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -66,3 +66,4 @@ export 'src/schema/model/schema_directive.dart';
 export 'src/schema/model/schema_enum_value.dart';
 export 'src/schema/model/schema_field.dart';
 export 'src/schema/model/schema_type.dart';
+export 'src/schema/schema.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/schema_test.dart)
```

Expected: `+10: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -75,3 +75,6 @@
 - `BuiltIns`: the built-in scalars (`String`, `Int`, `Float`, `Boolean`,
   `ID`), the five specified directives, `@defer` and `@stream`, and the
   introspection types of September2025.
+- `Schema`: declared types and directives in declaration order, root
+  operation type names, description and applied directives;
+  `typeNamed` and `directiveNamed` also find the built-ins.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -183,6 +183,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   directives, `defer` and `stream` (graphql-js's definitions, not in the
   specified five) and the introspection types, read once from the internal
   `BuiltInSdl` text of September2025 Appendix D; they have no span.
+- `Schema` (`schema.dart`) lists only what was declared; `typeNamed` and
+  `directiveNamed` fall back to `BuiltIns` (`defer` and `stream` only with
+  `includesDeferAndStream`). Roots are names (`queryTypeName`, ...,
+  `rootTypeName(OperationType)`).
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/schema.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/schema_test.dart
git commit -q -m "feat(typed_graphql): add the schema" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 6: Build a schema from SDL

R2.2, R0.3 and spec §4: `SchemaBuilder.fromSdl` and the sealed `BuildResult`.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/build_report.dart`, `packages/typed_graphql/lib/src/schema/build/build_result.dart`, `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/build/build_report_test.dart`, `packages/typed_graphql/test/schema/build/schema_builder_test.dart`, `packages/typed_graphql/test/schema/built.dart`

**Interfaces:**
- Consumes: Tasks 3–5; M1: `Diagnostic`, `DiagnosticCode`, `DiagnosticSink`; M2a: `Document`, the definition nodes.
- Produces:
  - `DiagnosticCode.executableDefinitionInSchema` (`GQL100`);
  - `sealed class BuildResult` with `List<Diagnostic> diagnostics`: `BuildSuccess(Schema schema)` and `BuildFailure(Schema partial, List<Diagnostic> diagnostics)`;
  - `final class const SchemaBuilder({bool includesDeferAndStream = false})` with `BuildResult fromSdl(Document document, {Source? source})`;
  - internal `BuildReport(NodeSpans spans)` with `void error(DiagnosticCode code, String message, Node at, {SourceSpan? related})`, `bool hasErrors`, `List<Diagnostic> diagnostics`;
  - internal `DocumentDefinitions.of(Document)` with the lists `schemas`, `types`, `directives`, `executables`;
  - internal `SchemaAssembly(BuildReport report)` with `Schema fromSdl(DocumentDefinitions definitions, {required bool includesDeferAndStream})`;
  - test helper `Built(String text, {SchemaBuilder builder})` in `test/schema/built.dart` with `result`, `schema`, `partial`, `errors` (`line:column id message`) and `typeNames`.

- [ ] **Step 1: Write the test helper**

`Built` builds a text with a `SchemaBuilder` and gives the schema, the partial schema, the declared type names and each diagnostic as `line:column id message`.

Create `packages/typed_graphql/test/schema/built.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'sdl.dart';

/// The result of building an SDL text, for a schema test.
final class Built {
  /// Builds [text] with [builder].
  Built(String text, {SchemaBuilder builder = const SchemaBuilder()})
    : this._(Sdl(text), builder);

  Built._(Sdl sdl, SchemaBuilder builder)
    : result = builder.fromSdl(sdl.document, source: sdl.source);

  /// What the builder returned.
  final BuildResult result;

  /// The schema; fails the test when the build failed.
  Schema get schema => switch (result) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => fail('$diagnostics'),
  };

  /// The partial schema; fails the test when the build succeeded.
  Schema get partial => switch (result) {
    BuildSuccess() => fail('expected build errors'),
    BuildFailure(:final partial) => partial,
  };

  /// Each diagnostic as `line:column id message`.
  List<String> get errors => [
    for (final diagnostic in result.diagnostics)
      '${diagnostic.span?.location} ${diagnostic.code.id} '
          '${diagnostic.message}',
  ];

  /// The names of the declared types, in order.
  List<String> get typeNames => [
    for (final type in _built.types) type.name,
  ];

  Schema get _built => switch (result) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final partial) => partial,
  };
}
```

- [ ] **Step 2: Write the failing tests**

Create `packages/typed_graphql/test/schema/build/build_report_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/build_report.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('scalar A scalar B');
  const a = Name('A', start: 7, end: 8);
  const b = Name('B', start: 16, end: 17);

  test('gives the errors in document order, not report order', () {
    final report = BuildReport(NodeSpans(source))
      ..error(DiagnosticCode.executableDefinitionInSchema, 'second', b)
      ..error(DiagnosticCode.executableDefinitionInSchema, 'first', a);
    expect(report.diagnostics.map((diagnostic) => diagnostic.message), [
      'first',
      'second',
    ]);
  });

  test('keeps report order between errors at one offset', () {
    final report = BuildReport(NodeSpans(source))
      ..error(DiagnosticCode.executableDefinitionInSchema, 'one', a)
      ..error(DiagnosticCode.executableDefinitionInSchema, 'two', a);
    expect(report.diagnostics.map((diagnostic) => diagnostic.message), [
      'one',
      'two',
    ]);
  });

  test('points an error at its node, with the related span', () {
    final related = SourceSpan(source, 0, 8);
    final report = BuildReport(NodeSpans(source))
      ..error(
        DiagnosticCode.executableDefinitionInSchema,
        'here',
        b,
        related: related,
      );
    final diagnostic = report.diagnostics.single;
    expect(diagnostic.span, SourceSpan(source, 16, 17));
    expect(diagnostic.related, [related]);
    expect(diagnostic.severity, DiagnosticSeverity.error);
  });

  test('stops after the limit of a sink, with one limit error', () {
    final report = BuildReport(NodeSpans(source));
    for (var i = 0; i < DiagnosticSink.defaultMaxErrors + 5; i++) {
      report.error(DiagnosticCode.executableDefinitionInSchema, '$i', a);
    }
    expect(report.diagnostics, hasLength(DiagnosticSink.defaultMaxErrors + 1));
    expect(report.diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
  });

  test('has errors once one is reported', () {
    final report = BuildReport(NodeSpans(source));
    expect(report.hasErrors, isFalse);
    report.error(DiagnosticCode.executableDefinitionInSchema, 'one', a);
    expect(report.hasErrors, isTrue);
  });
}
```

Create `packages/typed_graphql/test/schema/build/schema_builder_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  test('builds types and directives in declaration order', () {
    final built = Built('''
      directive @key(fields: String!) on OBJECT
      scalar Date
      type Query { today: Date }
      enum Color { RED }
    ''');
    expect(built.typeNames, ['Date', 'Query', 'Color']);
    expect(built.schema.directives.single.name, 'key');
    expect(built.schema.typeNamed('Query'), isA<ObjectType>());
  });

  test('builds an empty schema from an empty document', () {
    final schema = const SchemaBuilder().fromSdl(Document(const []));
    expect(schema, isA<BuildSuccess>());
    expect(schema.diagnostics, isEmpty);
  });

  test('takes the root types from the types named after them', () {
    final schema = Built('''
      type Query { a: Int }
      type Mutation { a: Int }
      type Subscription { a: Int }
    ''').schema;
    expect(schema.queryTypeName, 'Query');
    expect(schema.mutationTypeName, 'Mutation');
    expect(schema.subscriptionTypeName, 'Subscription');
  });

  test('has no root without a type named after it', () {
    final schema = Built('type Root { a: Int }').schema;
    expect(schema.queryTypeName, isNull);
  });

  test('takes the root types from the schema definition only', () {
    final schema = Built('''
      "The API." schema @key { query: Root }
      type Root { a: Int }
      type Mutation { a: Int }
    ''').schema;
    expect(schema.queryTypeName, 'Root');
    expect(schema.mutationTypeName, isNull);
    expect(schema.description, 'The API.');
    expect(schema.appliedDirectives.single.name, 'key');
    expect(schema.span?.text, startsWith('"The API." schema'));
  });

  test('keeps a reference to an unknown type: building does not validate', () {
    final field = Built('type Query { a: Missing }').schema.typeNamed('Query');
    expect(field, isA<ObjectType>());
  });

  test('gives every element the span of its definition', () {
    final type = Built('type Query { a: Int }').schema.typeNamed('Query');
    expect(type?.span?.text, 'type Query { a: Int }');
    expect(type?.span?.source.name, 'schema.graphql');
  });

  test('gives no spans without a source', () {
    final document = Sdl('type Query { a: Int }').document;
    final result = const SchemaBuilder().fromSdl(document);
    expect((result as BuildSuccess).schema.types.single.span, isNull);
  });

  test('reports an operation or a fragment and builds the rest', () {
    final built = Built('''
query { a }
type Query { a: Int }
fragment F on Query { a }''');
    expect(built.errors, [
      '1:1 GQL100 A schema document cannot hold operations or fragments.',
      '3:1 GQL100 A schema document cannot hold operations or fragments.',
    ]);
    expect(built.partial.typeNamed('Query'), isNotNull);
  });

  test('adds @defer and @stream when the builder includes them', () {
    const builder = SchemaBuilder(includesDeferAndStream: true);
    final schema = Built('type Query { a: Int }', builder: builder).schema;
    expect(schema.includesDeferAndStream, isTrue);
    expect(schema.directiveNamed('defer'), isNotNull);
    expect(
      Built('type Query { a: Int }').schema.includesDeferAndStream,
      isFalse,
    );
  });
}
```

- [ ] **Step 3: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/build_report_test.dart test/schema/build/schema_builder_test.dart)
```

Expected: FAIL. `Error: Error when reading 'lib/src/schema/build/build_report.dart': No such file or directory`, `Error: Member not found: 'executableDefinitionInSchema'.`, `Error: Couldn't find constructor 'SchemaBuilder'.` and `Error: 'BuildSuccess' isn't a type.`

- [ ] **Step 4: Add the first schema code**

Spec §10: a new code goes into the catalog, in id order, in the commit that first reports it.

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -83,5 +83,9 @@ enum DiagnosticCode(
   /// a directive extension, directives on a directive definition or the
   /// `DIRECTIVE_DEFINITION` location without
   /// `ParserOptions.allowDirectiveExtensions`.
-  workingDraftFeatureDisabled('GQL014');
+  workingDraftFeatureDisabled('GQL014'),
+
+  /// `GQL100`: an operation or a fragment in a document built into a
+  /// schema; it is ignored.
+  executableDefinitionInSchema('GQL100');
 }
```

- [ ] **Step 5: Write the implementation**

`BuildReport` collects errors with the offset of their node and gives them in document order through a `DiagnosticSink`, so the sink's limit and its `GQL000` apply (R0.3). `SchemaAssembly` is the one place that puts a schema together; later tasks add to it. Here it reads types and directives, takes the roots from the schema definition or, without one, from the types named `Query`, `Mutation` and `Subscription` (spec §3.3.1), and reports operations and fragments as `GQL100`.

Create `packages/typed_graphql/lib/src/schema/build/build_report.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source_span.dart';
import '../../language/ast/node.dart';
import 'node_spans.dart';

/// Collects the errors of one build and gives them in document order.
///
/// The builder finds problems pass by pass (definitions, then extensions),
/// so it reports out of order; [diagnostics] sorts them by the offset of
/// the node they point at, as graphql-js's single-pass SDL rules report,
/// and only then applies a [DiagnosticSink]'s limit.
final class BuildReport(
  /// Gives each error the span of its node.
  final NodeSpans spans,
) {
  /// Creates an empty report.
  this;

  final List<(int, Diagnostic)> _errors = [];

  /// Whether an error was reported.
  bool get hasErrors => _errors.isNotEmpty;

  /// Reports an error at [at], with the span of what it repeats or
  /// contradicts as [related].
  void error(
    DiagnosticCode code,
    String message,
    Node at, {
    SourceSpan? related,
  }) {
    final diagnostic = Diagnostic(
      code,
      .error,
      message,
      span: spans.of(at),
      related: [?related],
    );
    _errors.add((at.start, diagnostic));
  }

  /// The errors by offset, report order kept at one offset, cut at the
  /// sink's limit.
  List<Diagnostic> get diagnostics {
    final ordered = [
      for (final (index, (offset, diagnostic)) in _errors.indexed)
        (offset, index, diagnostic),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    final sink = DiagnosticSink();
    for (final (_, _, diagnostic) in ordered) {
      sink.report(diagnostic);
    }
    return sink.diagnostics;
  }
}
```

Create `packages/typed_graphql/lib/src/schema/build/build_result.dart`:

```dart
import '../../diagnostics/diagnostic.dart';
import '../schema.dart';

/// The result of building a schema: [BuildSuccess] or [BuildFailure]
/// (spec §4; R0.3). Bad SDL never throws.
sealed class const BuildResult() {
  /// Creates a result.
  this;

  /// Every diagnostic of the build, in document order; empty on success.
  List<Diagnostic> get diagnostics;
}

/// A schema built without a construction problem. It is not validated:
/// a reference may still name a type that does not exist.
final class BuildSuccess(
  /// The schema.
  final Schema schema,
) extends BuildResult {
  /// Creates a success.
  this;

  @override
  List<Diagnostic> get diagnostics => const [];
}

/// A build with errors, such as a repeated type name.
final class BuildFailure(
  /// Everything that built: what an error is about is left out (the
  /// second of two types with one name, an extension of a missing type).
  final Schema partial,
  List<Diagnostic> diagnostics,
) extends BuildResult {
  /// Creates a failure.
  this;

  @override
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
```

Create `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`:

```dart
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/type_system_definition.dart';

/// The definitions of a document sorted by what the builder does with
/// them, each list in document order.
final class DocumentDefinitions {
  /// Sorts the definitions of [document].
  DocumentDefinitions.of(Document document) {
    for (final definition in document.definitions) {
      switch (definition) {
        case SchemaDefinition():
          schemas.add(definition);
        case TypeDefinition():
          types.add(definition);
        case DirectiveDefinition():
          directives.add(definition);
        case ExecutableDefinition():
          executables.add(definition);
      }
    }
  }

  /// The schema definitions; a valid document has at most one.
  final List<SchemaDefinition> schemas = [];

  /// The type definitions.
  final List<TypeDefinition> types = [];

  /// The directive definitions.
  final List<DirectiveDefinition> directives = [];

  /// What a schema cannot hold: operations and fragments.
  final List<ExecutableDefinition> executables = [];
}
```

Create `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`:

```dart
import '../../language/ast/operation_type.dart';
import '../../language/ast/type_system_definition.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'build_report.dart';
import 'document_definitions.dart';
import 'element_reader.dart';
import 'type_reader.dart';

/// Builds one schema from the sorted definitions of one document,
/// reporting every construction problem into [report].
final class SchemaAssembly(
  /// Receives the errors and gives the spans.
  final BuildReport report,
) {
  /// Creates an assembly.
  this;

  /// The schema [definitions] define; default root types are taken from
  /// types named `Query`, `Mutation` and `Subscription` when no schema
  /// definition names the roots (spec §3.3.1).
  Schema fromSdl(
    DocumentDefinitions definitions, {
    required bool includesDeferAndStream,
  }) {
    for (final executable in definitions.executables) {
      report.error(
        .executableDefinitionInSchema,
        'A schema document cannot hold operations or fragments.',
        executable,
      );
    }
    final elements = ElementReader(report.spans);
    final types = [
      for (final type in definitions.types) TypeReader(elements).type(type),
    ];
    final schema = definitions.schemas.firstOrNull;
    final roots = schema == null ? _defaultRoots(types) : _roots(schema);
    return Schema(
      types: types,
      directives: definitions.directives.map(elements.directive).toList(),
      queryTypeName: roots[OperationType.query],
      mutationTypeName: roots[OperationType.mutation],
      subscriptionTypeName: roots[OperationType.subscription],
      description: schema?.description?.value,
      appliedDirectives: elements.appliedAll(schema?.directives ?? const []),
      includesDeferAndStream: includesDeferAndStream,
      span: schema == null ? null : report.spans.of(schema),
    );
  }

  Map<OperationType, String> _roots(SchemaDefinition schema) => {
    for (final root in schema.operationTypes)
      root.operation: root.type.name.value,
  };

  Map<OperationType, String> _defaultRoots(List<SchemaType> types) => {
    for (final type in types) ?_defaultRootNames[type.name]: type.name,
  };

  static const Map<String, OperationType> _defaultRootNames = {
    'Query': .query,
    'Mutation': .mutation,
    'Subscription': .subscription,
  };
}
```

Create `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`:

```dart
import '../../diagnostics/source.dart';
import '../../language/ast/document.dart';
import 'build_report.dart';
import 'build_result.dart';
import 'document_definitions.dart';
import 'node_spans.dart';
import 'schema_assembly.dart';

/// Builds a schema from SDL (spec §4; R2.2), reporting construction
/// problems as `GQL1xx` diagnostics and never throwing.
///
/// Building does not validate: an unknown type reference is kept, a root
/// may name a type of the wrong kind. Schema validation checks those.
final class const SchemaBuilder({
  /// Whether built schemas have `@defer` and `@stream`, which graphql-js
  /// defines and the specification does not yet (R2.6).
  final bool includesDeferAndStream = false,
}) {
  /// Creates a builder.
  this;

  /// The schema the type-system definitions of [document] define.
  ///
  /// [source] is the text [document] was parsed from: it gives the
  /// elements and the diagnostics their spans, which are null without it.
  BuildResult fromSdl(Document document, {Source? source}) {
    final report = BuildReport(NodeSpans(source));
    final schema = SchemaAssembly(report).fromSdl(
      DocumentDefinitions.of(document),
      includesDeferAndStream: includesDeferAndStream,
    );
    return report.hasErrors
        ? BuildFailure(schema, report.diagnostics)
        : BuildSuccess(schema);
  }
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -59,7 +59,9 @@ export 'src/protocol/json_reader.dart';
 export 'src/protocol/json_value.dart';
 export 'src/protocol/path_segment.dart';
 export 'src/protocol/response_payload.dart';
+export 'src/schema/build/build_result.dart';
 export 'src/schema/build/built_ins.dart';
+export 'src/schema/build/schema_builder.dart';
 export 'src/schema/model/applied_directive.dart';
 export 'src/schema/model/input_value.dart';
 export 'src/schema/model/schema_directive.dart';
```

- [ ] **Step 6: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/build_report_test.dart test/schema/build/schema_builder_test.dart)
```

Expected: `build_report_test.dart` `+5`, `schema_builder_test.dart` `+10`, each `All tests passed!`

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -78,3 +78,8 @@
 - `Schema`: declared types and directives in declaration order, root
   operation type names, description and applied directives;
   `typeNamed` and `directiveNamed` also find the built-ins.
+- `SchemaBuilder.fromSdl`: SDL to a `Schema` without validating, as the
+  sealed `BuildResult` (`BuildSuccess`, `BuildFailure` with the partial
+  schema); root types from the schema definition or the types named
+  `Query`, `Mutation` and `Subscription`; `GQL100` for an operation or a
+  fragment in the document; `includesDeferAndStream` opt-in.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -187,6 +187,12 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `directiveNamed` fall back to `BuiltIns` (`defer` and `stream` only with
   `includesDeferAndStream`). Roots are names (`queryTypeName`, ...,
   `rootTypeName(OperationType)`).
+- `build/SchemaBuilder` (const, `includesDeferAndStream`): `fromSdl(document,
+  source:)` returns the sealed `BuildResult` (`BuildSuccess(schema)` |
+  `BuildFailure(partial, diagnostics)`). A run sorts the definitions
+  (`DocumentDefinitions`), assembles them (`SchemaAssembly`) and reports into
+  a `BuildReport`, which orders the errors by node offset before a
+  `DiagnosticSink` limits them. Without `source` every span is null.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/build/build_report.dart packages/typed_graphql/lib/src/schema/build/build_result.dart packages/typed_graphql/lib/src/schema/build/document_definitions.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/schema_builder.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/build/build_report_test.dart packages/typed_graphql/test/schema/build/schema_builder_test.dart packages/typed_graphql/test/schema/built.dart
git commit -q -m "feat(typed_graphql): build a schema from SDL" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 7: Report repeated and built-in type and directive names

Spec §4: a duplicate type or directive and a redeclared built-in are diagnostics.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/unique_definitions.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`
- Test: `packages/typed_graphql/test/schema/build/unique_definitions_test.dart`

**Interfaces:**
- Consumes: Task 6: `BuildReport`, `SchemaAssembly`, `Built`; Task 4: `BuiltIns`.
- Produces:
  - `DiagnosticCode.duplicateTypeName` (`GQL101`), `duplicateDirectiveName` (`GQL102`), `builtInRedefinition` (`GQL103`);
  - internal `UniqueDefinitions(BuildReport report, Schema base)` with `List<TypeDefinition> types(List<TypeDefinition>)` and `List<DirectiveDefinition> directives(List<DirectiveDefinition>)`: the definitions that stay, the first of each name.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/build/unique_definitions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/build_report.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/src/schema/build/unique_definitions.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';
import '../sdl.dart';

void main() {
  test('keeps the first of two types with one name', () {
    final built = Built('''
type A { a: Int }
enum A { B }''');
    expect(built.errors, [
      '2:6 GQL101 There can be only one type named "A".',
    ]);
    expect(built.partial.types.single, isA<ObjectType>());
  });

  test('points a repeated type at the definition it repeats', () {
    final built = Built('scalar A scalar A');
    final related = built.result.diagnostics.single.related.single;
    expect(related.text, 'scalar A');
    expect(related.start, 0);
  });

  test('reports each repeat of a type name', () {
    expect(Built('scalar A scalar A scalar A').errors, hasLength(2));
  });

  test('keeps the first of two directives with one name', () {
    final built = Built('''
directive @key on OBJECT
directive @key(fields: String) on FIELD''');
    expect(built.errors, [
      '2:12 GQL102 There can be only one directive named "@key".',
    ]);
    expect(built.partial.directives.single.arguments, isEmpty);
  });

  test('rejects a redefined built-in scalar', () {
    final built = Built('''
scalar String
type Int { a: Int }''');
    expect(built.errors, [
      '1:8 GQL103 The built-in type "String" cannot be redefined.',
      '2:6 GQL103 The built-in type "Int" cannot be redefined.',
    ]);
    expect(built.partial.types, isEmpty);
  });

  test('rejects a redefined introspection type', () {
    expect(Built('type __Type { a: Int }').errors, [
      '1:6 GQL103 The built-in type "__Type" cannot be redefined.',
    ]);
  });

  test('rejects a redefined built-in directive', () {
    expect(Built('directive @skip(if: Boolean!) on FIELD').errors, [
      '1:12 GQL103 The built-in directive "@skip" cannot be redefined.',
    ]);
  });

  test('rejects a redefined @defer only when the builder includes it', () {
    const sdl = 'directive @defer on FIELD';
    expect(Built(sdl).schema.directives.single.name, 'defer');
    const builder = SchemaBuilder(includesDeferAndStream: true);
    expect(Built(sdl, builder: builder).errors, [
      '1:12 GQL103 The built-in directive "@defer" cannot be redefined.',
    ]);
  });

  test('reports problems of different definitions in document order', () {
    final built = Built('''
scalar A
directive @d on FIELD
directive @d on FIELD
scalar A''');
    expect(built.errors.map((error) => error.split(' ')[1]), [
      'GQL102',
      'GQL101',
    ]);
  });

  group('onto a schema', () {
    final base = Schema(
      types: [ScalarType('Date')],
      directives: [SchemaDirective('key')],
    );

    /// The messages of checking the definitions of [text] against [base].
    List<String> check(String text) {
      final sdl = Sdl(text);
      final report = BuildReport(NodeSpans(sdl.source));
      UniqueDefinitions(report, base)
        ..types(sdl.all())
        ..directives(sdl.all());
      return [
        for (final diagnostic in report.diagnostics)
          '${diagnostic.code.id} ${diagnostic.message}',
      ];
    }

    test('rejects a type the schema has', () {
      expect(check('scalar Date'), [
        'GQL101 Type "Date" already exists in the schema. It cannot also be '
            'defined in this type definition.',
      ]);
    });

    test('rejects a directive the schema has', () {
      expect(check('directive @key on FIELD'), [
        'GQL102 Directive "@key" already exists in the schema. It cannot be '
            'redefined.',
      ]);
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/unique_definitions_test.dart)
```

Expected: FAIL. `Error: Error when reading 'lib/src/schema/build/unique_definitions.dart': No such file or directory` and `Error: Method not found: 'UniqueDefinitions'.`

- [ ] **Step 3: Add the codes**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -87,5 +87,20 @@ enum DiagnosticCode(
 
   /// `GQL100`: an operation or a fragment in a document built into a
   /// schema; it is ignored.
-  executableDefinitionInSchema('GQL100');
+  executableDefinitionInSchema('GQL100'),
+
+  /// `GQL101`: a second type definition with the name of a type already
+  /// defined in the document or in the schema being extended; the second
+  /// is ignored.
+  duplicateTypeName('GQL101'),
+
+  /// `GQL102`: a second directive definition with the name of a directive
+  /// already defined in the document or in the schema being extended; the
+  /// second is ignored.
+  duplicateDirectiveName('GQL102'),
+
+  /// `GQL103`: a definition or an extension of a built-in: a built-in
+  /// scalar, an introspection type or a built-in directive (R2.6); it is
+  /// ignored.
+  builtInRedefinition('GQL103');
 }
```

- [ ] **Step 4: Write the implementation**

The first definition of a name wins and each later one is reported, with the first as the related span (graphql-js's `UniqueTypeNamesRule` and `UniqueDirectiveNamesRule`). A built-in scalar, an introspection type or a built-in directive cannot be defined: `GQL103` (R2.6). `@defer` and `@stream` count as built-ins only when the builder includes them. The `base` parameter is the schema being extended, which Task 11 passes; here it is always an empty `Schema`.

Create `packages/typed_graphql/lib/src/schema/build/unique_definitions.dart`:

```dart
import '../../language/ast/type_system_definition.dart';
import '../schema.dart';
import 'build_report.dart';
import 'built_ins.dart';

/// Keeps the first type or directive definition of each name and drops
/// the repeats and the built-ins redefined, reporting each.
///
/// The messages are graphql-js's (`UniqueTypeNamesRule`,
/// `UniqueDirectiveNamesRule`); a repeat points at its name and relates
/// to the definition it repeats.
final class UniqueDefinitions(
  /// Receives the errors.
  final BuildReport report,

  /// The schema the definitions are added to; its types and directives
  /// count as defined first.
  final Schema base,
) {
  /// Creates the check.
  this;

  /// [nodes] without repeated or built-in names.
  List<TypeDefinition> types(List<TypeDefinition> nodes) {
    final kept = <String, TypeDefinition>{};
    for (final node in nodes) {
      final name = node.name.value;
      if (const BuiltIns().typeNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "$name" cannot be redefined.',
          node.name,
        );
      } else if (base.typeNamed(name) != null) {
        report.error(
          .duplicateTypeName,
          'Type "$name" already exists in the schema. It cannot also be '
          'defined in this type definition.',
          node.name,
        );
      } else if (kept[name] case final first?) {
        report.error(
          .duplicateTypeName,
          'There can be only one type named "$name".',
          node.name,
          related: report.spans.of(first),
        );
      } else {
        kept[name] = node;
      }
    }
    return [...kept.values];
  }

  /// [nodes] without repeated or built-in names.
  List<DirectiveDefinition> directives(List<DirectiveDefinition> nodes) {
    final kept = <String, DirectiveDefinition>{};
    for (final node in nodes) {
      final name = node.name.value;
      if (_isBuiltInDirective(name)) {
        report.error(
          .builtInRedefinition,
          'The built-in directive "@$name" cannot be redefined.',
          node.name,
        );
      } else if (base.directiveNamed(name) != null) {
        report.error(
          .duplicateDirectiveName,
          'Directive "@$name" already exists in the schema. It cannot be '
          'redefined.',
          node.name,
        );
      } else if (kept[name] case final first?) {
        report.error(
          .duplicateDirectiveName,
          'There can be only one directive named "@$name".',
          node.name,
          related: report.spans.of(first),
        );
      } else {
        kept[name] = node;
      }
    }
    return [...kept.values];
  }

  bool _isBuiltInDirective(String name) =>
      const BuiltIns().directiveNamed(name) != null ||
      (base.includesDeferAndStream && (name == 'defer' || name == 'stream'));
}
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -6,6 +6,7 @@ import 'build_report.dart';
 import 'document_definitions.dart';
 import 'element_reader.dart';
 import 'type_reader.dart';
+import 'unique_definitions.dart';
 
 /// Builds one schema from the sorted definitions of one document,
 /// reporting every construction problem into [report].
@@ -30,15 +31,23 @@ final class SchemaAssembly(
         executable,
       );
     }
+    final unique = UniqueDefinitions(
+      report,
+      Schema(includesDeferAndStream: includesDeferAndStream),
+    );
     final elements = ElementReader(report.spans);
     final types = [
-      for (final type in definitions.types) TypeReader(elements).type(type),
+      for (final type in unique.types(definitions.types))
+        TypeReader(elements).type(type),
     ];
     final schema = definitions.schemas.firstOrNull;
     final roots = schema == null ? _defaultRoots(types) : _roots(schema);
     return Schema(
       types: types,
-      directives: definitions.directives.map(elements.directive).toList(),
+      directives: [
+        for (final directive in unique.directives(definitions.directives))
+          elements.directive(directive),
+      ],
       queryTypeName: roots[OperationType.query],
       mutationTypeName: roots[OperationType.mutation],
       subscriptionTypeName: roots[OperationType.subscription],
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/unique_definitions_test.dart)
```

Expected: `+11: All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -83,3 +83,6 @@
   schema); root types from the schema definition or the types named
   `Query`, `Mutation` and `Subscription`; `GQL100` for an operation or a
   fragment in the document; `includesDeferAndStream` opt-in.
+- The builder keeps the first type or directive of each name: `GQL101`
+  and `GQL102` for a repeat, `GQL103` for a redefined built-in scalar,
+  introspection type or directive.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -193,6 +193,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   (`DocumentDefinitions`), assembles them (`SchemaAssembly`) and reports into
   a `BuildReport`, which orders the errors by node offset before a
   `DiagnosticSink` limits them. Without `source` every span is null.
+- Construction problems use graphql-js's SDL-rule messages; a repeat points
+  at its name and relates to the span of the definition it repeats; the
+  first definition wins (`UniqueDefinitions`).
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/unique_definitions.dart packages/typed_graphql/test/schema/build/unique_definitions_test.dart
git commit -q -m "feat(typed_graphql): report repeated and built-in type and directive names" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 8: Report repeated fields, arguments and enum values

Spec §4: a duplicate member inside one definition is a diagnostic.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/member_filter.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`
- Test: `packages/typed_graphql/test/schema/build/member_filter_test.dart`

**Interfaces:**
- Consumes: Tasks 6–7; M2a: `Node.withChildren`.
- Produces:
  - `DiagnosticCode.duplicateFieldName` (`GQL104`), `duplicateArgumentName` (`GQL105`), `duplicateEnumValueName` (`GQL106`);
  - internal `MemberFilter(BuildReport report)` with `TypeDefinition definition(TypeDefinition node)` and `DirectiveDefinition directive(DirectiveDefinition node)`: the node without its repeated members.

- [ ] **Step 1: Write the failing tests**

The tests go through `Built`, so they compile already and fail on what the builder reports.

Create `packages/typed_graphql/test/schema/build/member_filter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  test('keeps the first of two fields with one name', () {
    final built = Built('''
type Query {
  a: Int
  a: String
}''');
    expect(built.errors, [
      '3:3 GQL104 Field "Query.a" can only be defined once.',
    ]);
    final query = built.partial.typeNamed('Query') as ObjectType;
    expect(query.fields.single.span?.text, 'a: Int');
  });

  test('points a repeated field at the field it repeats', () {
    final built = Built('interface I { a: Int a: Int }');
    expect(built.result.diagnostics.single.related.single.text, 'a: Int');
    expect(built.result.diagnostics.single.related.single.start, 14);
  });

  test('keeps the first of two input fields with one name', () {
    final built = Built('input In { a: Int a: Int b: Int }');
    expect(built.errors, [
      '1:19 GQL104 Field "In.a" can only be defined once.',
    ]);
    final input = built.partial.typeNamed('In') as InputObjectType;
    expect(input.fields.map((field) => field.name), ['a', 'b']);
  });

  test('keeps the first of two enum values with one name', () {
    final built = Built('enum Color { RED GREEN RED }');
    expect(built.errors, [
      '1:24 GQL106 Enum value "Color.RED" can only be defined once.',
    ]);
    final color = built.partial.typeNamed('Color') as EnumType;
    expect(color.values.map((value) => value.name), ['RED', 'GREEN']);
  });

  test('keeps the first of two field arguments with one name', () {
    final built = Built('type Query { f(a: Int, a: Int, b: Int): Int }');
    expect(built.errors, [
      '1:24 GQL105 Argument "Query.f(a:)" can only be defined once.',
    ]);
    final query = built.partial.typeNamed('Query') as ObjectType;
    expect(query.fields.single.arguments.map((argument) => argument.name), [
      'a',
      'b',
    ]);
  });

  test('keeps the first of two directive arguments with one name', () {
    final built = Built('directive @d(a: Int, a: Int) on FIELD');
    expect(built.errors, [
      '1:22 GQL105 Argument "@d(a:)" can only be defined once.',
    ]);
    expect(built.partial.directives.single.arguments, hasLength(1));
  });

  test('checks the arguments of a repeated field too, as graphql-js', () {
    final built = Built('type Query { f: Int f(a: Int, a: Int): Int }');
    expect(built.errors, [
      '1:21 GQL104 Field "Query.f" can only be defined once.',
      '1:31 GQL105 Argument "Query.f(a:)" can only be defined once.',
    ]);
  });

  test('allows one name in different types and fields', () {
    final built = Built('''
type A { f(x: Int): Int g(x: Int): Int }
type B { f: Int }''');
    expect(built.result, isA<BuildSuccess>());
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/member_filter_test.dart)
```

Expected: FAIL. `+1 -7`: every test but `allows one name in different types and fields` fails, such as `Expected: ['3:3 GQL104 Field "Query.a" can only be defined once.']`, `Actual: []`.

- [ ] **Step 3: Add the codes**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -102,5 +102,17 @@ enum DiagnosticCode(
   /// `GQL103`: a definition or an extension of a built-in: a built-in
   /// scalar, an introspection type or a built-in directive (R2.6); it is
   /// ignored.
-  builtInRedefinition('GQL103');
+  builtInRedefinition('GQL103'),
+
+  /// `GQL104`: a second field or input field with one name in a type, its
+  /// extensions included; the second is ignored.
+  duplicateFieldName('GQL104'),
+
+  /// `GQL105`: a second argument with one name in a field or a directive
+  /// definition; the second is ignored.
+  duplicateArgumentName('GQL105'),
+
+  /// `GQL106`: a second value with one name in an enum type, its
+  /// extensions included; the second is ignored.
+  duplicateEnumValueName('GQL106');
 }
```

- [ ] **Step 4: Write the implementation**

`MemberFilter` rebuilds a definition node without its repeated members, through M2a's `withChildren`, before the readers see it, so a repeat never reaches the model. Every repeat is reported, also the arguments of a field that is itself a repeat, as graphql-js does. The messages are graphql-js's, with the schema coordinate of the member.

Create `packages/typed_graphql/lib/src/schema/build/member_filter.dart`:

```dart
import '../../diagnostics/source_span.dart';
import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_definition.dart';
import 'build_report.dart';

/// Drops the repeated members of type and directive definitions, keeping
/// the first of each name and reporting the others.
///
/// It filters syntax nodes and rebuilds them with `withChildren`, so the
/// readers see only kept members. The messages are graphql-js's
/// (`UniqueFieldDefinitionNamesRule`, `UniqueEnumValueNamesRule`,
/// `UniqueArgumentDefinitionNamesRule`).
final class MemberFilter(
  /// Receives the errors.
  final BuildReport report,
) {
  /// Creates a filter.
  this;

  /// [node] without repeated fields, input fields, enum values and field
  /// arguments.
  TypeDefinition definition(TypeDefinition node) =>
      node.withChildren(_members(node.name.value, node.children))
          as TypeDefinition;

  /// [node] without repeated arguments.
  DirectiveDefinition directive(DirectiveDefinition node) =>
      node.withChildren(_arguments('@${node.name.value}', node.children))
          as DirectiveDefinition;

  List<Node> _members(String typeName, List<Node> children) {
    final seen = <String, SourceSpan?>{};
    final kept = <Node>[];
    for (final child in children) {
      final member = switch (child) {
        FieldDefinition(:final name) => child.withChildren(
          _arguments('$typeName.${name.value}', child.children),
        ),
        _ => child,
      };
      switch (_memberName(member)) {
        case final name? when seen.containsKey(name.value):
          final isEnumValue = member is EnumValueDefinition;
          report.error(
            isEnumValue ? .duplicateEnumValueName : .duplicateFieldName,
            '${isEnumValue ? 'Enum value' : 'Field'} '
            '"$typeName.${name.value}" can only be defined once.',
            name,
            related: seen[name.value],
          );
        case final name?:
          seen[name.value] = report.spans.of(member);
          kept.add(member);
        case null:
          kept.add(member);
      }
    }
    return kept;
  }

  List<Node> _arguments(String owner, List<Node> children) {
    final seen = <String, SourceSpan?>{};
    final kept = <Node>[];
    for (final child in children) {
      if (child case InputValueDefinition(:final name)
          when seen.containsKey(name.value)) {
        report.error(
          .duplicateArgumentName,
          'Argument "$owner(${name.value}:)" can only be defined once.',
          name,
          related: seen[name.value],
        );
        continue;
      }
      if (child case InputValueDefinition(:final name)) {
        seen[name.value] = report.spans.of(child);
      }
      kept.add(child);
    }
    return kept;
  }

  Name? _memberName(Node node) => switch (node) {
    FieldDefinition(:final name) => name,
    InputValueDefinition(:final name) => name,
    EnumValueDefinition(:final name) => name,
    _ => null,
  };
}
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -5,6 +5,7 @@ import '../schema.dart';
 import 'build_report.dart';
 import 'document_definitions.dart';
 import 'element_reader.dart';
+import 'member_filter.dart';
 import 'type_reader.dart';
 import 'unique_definitions.dart';
 
@@ -35,10 +36,11 @@ final class SchemaAssembly(
       report,
       Schema(includesDeferAndStream: includesDeferAndStream),
     );
+    final filter = MemberFilter(report);
     final elements = ElementReader(report.spans);
     final types = [
       for (final type in unique.types(definitions.types))
-        TypeReader(elements).type(type),
+        TypeReader(elements).type(filter.definition(type)),
     ];
     final schema = definitions.schemas.firstOrNull;
     final roots = schema == null ? _defaultRoots(types) : _roots(schema);
@@ -46,7 +48,7 @@ final class SchemaAssembly(
       types: types,
       directives: [
         for (final directive in unique.directives(definitions.directives))
-          elements.directive(directive),
+          elements.directive(filter.directive(directive)),
       ],
       queryTypeName: roots[OperationType.query],
       mutationTypeName: roots[OperationType.mutation],
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/member_filter_test.dart)
```

Expected: `+8: All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -86,3 +86,6 @@
 - The builder keeps the first type or directive of each name: `GQL101`
   and `GQL102` for a repeat, `GQL103` for a redefined built-in scalar,
   introspection type or directive.
+- The builder keeps the first member of each name: `GQL104` for a
+  repeated field or input field, `GQL105` for a repeated argument,
+  `GQL106` for a repeated enum value.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -195,7 +195,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `DiagnosticSink` limits them. Without `source` every span is null.
 - Construction problems use graphql-js's SDL-rule messages; a repeat points
   at its name and relates to the span of the definition it repeats; the
-  first definition wins (`UniqueDefinitions`).
+  first definition wins (`UniqueDefinitions`). `MemberFilter` drops repeated
+  members and arguments from syntax nodes with `withChildren` before the
+  readers see them.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/build/member_filter.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/test/schema/build/member_filter_test.dart
git commit -q -m "feat(typed_graphql): report repeated fields, arguments and enum values" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 9: Apply the schema definition and schema extensions

R2.2: the schema definition and `extend schema`.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`
- Test: `packages/typed_graphql/test/schema/build/schema_builder_test.dart`, `packages/typed_graphql/test/schema/build/schema_definition_reader_test.dart`

**Interfaces:**
- Consumes: Tasks 6–8; M2a: `SchemaDefinition`, `SchemaExtension`, `OperationTypeDefinition`.
- Produces:
  - `DiagnosticCode.duplicateSchemaDefinition` (`GQL107`), `duplicateOperationType` (`GQL108`);
  - internal `SchemaDefinitionReader(BuildReport report, ElementReader elements)` with `Schema read(Schema base, List<SchemaDefinition> definitions, List<SchemaExtension> extensions)`;
  - `DocumentDefinitions.schemaExtensions`.

- [ ] **Step 1: Write the failing tests**

Two tests join `schema_builder_test.dart`; the reader gets its own file.

In `packages/typed_graphql/test/schema/build/schema_builder_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -52,6 +52,23 @@ void main() {
     expect(schema.span?.text, startsWith('"The API." schema'));
   });
 
+  test('takes the default root types besides an extension\'s', () {
+    final schema = Built('''
+      extend schema { mutation: Change }
+      type Query { a: Int }
+      type Mutation { a: Int }
+      type Change { a: Int }
+    ''').schema;
+    expect(schema.queryTypeName, 'Query');
+    expect(schema.mutationTypeName, 'Change');
+  });
+
+  test('reports a second schema definition', () {
+    expect(Built('schema { query: A } schema { query: B }').errors, [
+      '1:21 GQL107 Must provide only one schema definition.',
+    ]);
+  });
+
   test('keeps a reference to an unknown type: building does not validate', () {
     final field = Built('type Query { a: Missing }').schema.typeNamed('Query');
     expect(field, isA<ObjectType>());
```

Create `packages/typed_graphql/test/schema/build/schema_definition_reader_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/build_report.dart';
import 'package:typed_graphql/src/schema/build/element_reader.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/src/schema/build/schema_definition_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../sdl.dart';

void main() {
  /// Reads the schema definitions and extensions of [text] onto [base];
  /// the errors go to [errors].
  Schema read(String text, {Schema? base, List<String>? errors}) {
    final sdl = Sdl(text);
    final report = BuildReport(NodeSpans(sdl.source));
    final schema = SchemaDefinitionReader(
      report,
      ElementReader(report.spans),
    ).read(base ?? Schema(), sdl.all<SchemaDefinition>(), sdl.all());
    errors?.addAll([
      for (final diagnostic in report.diagnostics)
        '${diagnostic.span?.location} ${diagnostic.code.id} '
            '${diagnostic.message}',
    ]);
    return schema;
  }

  test('reads the roots, description, directives and span', () {
    final schema = read('"API" schema @a { query: Q subscription: S }');
    expect(schema.queryTypeName, 'Q');
    expect(schema.mutationTypeName, isNull);
    expect(schema.subscriptionTypeName, 'S');
    expect(schema.description, 'API');
    expect(schema.appliedDirectives.single.name, 'a');
    expect(schema.span?.start, 0);
  });

  test('adds the roots and directives of extensions, in order', () {
    final schema = read('''
extend schema @b { mutation: M }
schema @a { query: Q }''');
    expect(schema.queryTypeName, 'Q');
    expect(schema.mutationTypeName, 'M');
    expect(schema.appliedDirectives.map((directive) => directive.name), [
      'a',
      'b',
    ]);
  });

  test('keeps the first of two schema definitions', () {
    final errors = <String>[];
    final schema = read('''
schema { query: A }
schema { query: B }''', errors: errors);
    expect(schema.queryTypeName, 'A');
    expect(errors, ['2:1 GQL107 Must provide only one schema definition.']);
  });

  test('keeps the first root type of an operation', () {
    final errors = <String>[];
    final schema = read('''
schema { query: A query: B }
extend schema { query: C }''', errors: errors);
    expect(schema.queryTypeName, 'A');
    expect(errors, [
      '1:19 GQL108 There can be only one query type in schema.',
      '2:17 GQL108 There can be only one query type in schema.',
    ]);
  });

  group('onto a schema with roots', () {
    final base = Schema(
      queryTypeName: 'Q',
      description: 'Old',
      appliedDirectives: [AppliedDirective('old')],
    );

    test('rejects a new schema definition', () {
      final errors = <String>[];
      final schema = read(
        'schema { mutation: M }',
        base: base,
        errors: errors,
      );
      expect(schema.mutationTypeName, isNull);
      expect(errors, [
        '1:1 GQL107 Cannot define a new schema within a schema extension.',
      ]);
    });

    test('rejects a root type it already has', () {
      final errors = <String>[];
      final schema = read(
        'extend schema { query: Other }',
        base: base,
        errors: errors,
      );
      expect(schema.queryTypeName, 'Q');
      expect(errors, [
        '1:17 GQL108 Type for query already defined in the schema. It '
            'cannot be redefined.',
      ]);
    });

    test('adds a new root type and directives after its own', () {
      final schema = read('extend schema @new { mutation: M }', base: base);
      expect(schema.queryTypeName, 'Q');
      expect(schema.mutationTypeName, 'M');
      expect(schema.description, 'Old');
      expect(schema.appliedDirectives.map((directive) => directive.name), [
        'old',
        'new',
      ]);
    });
  });

  test('accepts a schema definition onto a schema without roots', () {
    final schema = read('schema { query: Q }', base: Schema());
    expect(schema.queryTypeName, 'Q');
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/schema_builder_test.dart test/schema/build/schema_definition_reader_test.dart)
```

Expected: FAIL. `schema_definition_reader_test.dart`: `Error: Error when reading 'lib/src/schema/build/schema_definition_reader.dart': No such file or directory`. `schema_builder_test.dart`: `takes the default root types besides an extension's` and `reports a second schema definition` fail (`Expected: ['1:21 GQL107 Must provide only one schema definition.']`, `Actual: []`); the other 10 pass.

- [ ] **Step 3: Add the codes**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -114,5 +114,14 @@ enum DiagnosticCode(
 
   /// `GQL106`: a second value with one name in an enum type, its
   /// extensions included; the second is ignored.
-  duplicateEnumValueName('GQL106');
+  duplicateEnumValueName('GQL106'),
+
+  /// `GQL107`: a second schema definition, or one in a document that
+  /// extends a schema with root types; it is ignored.
+  duplicateSchemaDefinition('GQL107'),
+
+  /// `GQL108`: a second root type for one operation, in the schema
+  /// definition, its extensions or the schema being extended; the second
+  /// is ignored.
+  duplicateOperationType('GQL108');
 }
```

- [ ] **Step 4: Write the implementation**

`SchemaDefinitionReader` applies the schema definition and every `extend schema`, in document order: the first root type of an operation wins (`GQL108` for the others), a second schema definition is `GQL107`, and the description, directives and span come from the definition. Default root types fill only the operations that neither the definition nor an extension names, and only when the document has no schema definition (graphql-js's `getOperationTypes`).

Create `packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart`:

```dart
import '../../language/ast/operation_type.dart';
import '../../language/ast/operation_type_definition.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/ast/type_system_extension.dart';
import '../schema.dart';
import 'build_report.dart';
import 'element_reader.dart';

/// Applies the schema definition and the schema extensions of a document
/// to a schema: root operation types, description, applied directives and
/// span (spec §3.3).
///
/// The first definition and the first root type of each operation win;
/// the messages are graphql-js's (`LoneSchemaDefinitionRule`,
/// `UniqueOperationTypesRule`).
final class SchemaDefinitionReader(
  /// Receives the errors and gives the spans.
  final BuildReport report,

  /// Reads the applied directives.
  final ElementReader elements,
) {
  /// Creates a reader.
  this;

  /// [base] with [definitions] and [extensions] applied, in document
  /// order; its types and directives are left as they are.
  Schema read(
    Schema base,
    List<SchemaDefinition> definitions,
    List<SchemaExtension> extensions,
  ) {
    final definition = _definition(base, definitions);
    final roots = _roots(base, [
      ...?definition?.operationTypes,
      for (final extension in extensions) ...extension.operationTypes,
    ]);
    return Schema(
      types: base.types,
      directives: base.directives,
      queryTypeName: roots[OperationType.query],
      mutationTypeName: roots[OperationType.mutation],
      subscriptionTypeName: roots[OperationType.subscription],
      description: definition?.description?.value ?? base.description,
      appliedDirectives: [
        ...base.appliedDirectives,
        ...elements.appliedAll(definition?.directives ?? const []),
        for (final extension in extensions)
          ...elements.appliedAll(extension.directives),
      ],
      includesDeferAndStream: base.includesDeferAndStream,
      span:
          base.span ??
          (definition == null ? null : report.spans.of(definition)),
    );
  }

  /// The definition to apply: the first, unless [base] already has a
  /// schema (a root type or a definition), as graphql-js decides.
  SchemaDefinition? _definition(Schema base, List<SchemaDefinition> nodes) {
    final hasSchema =
        base.span != null ||
        OperationType.values.any((operation) {
          return base.rootTypeName(operation) != null;
        });
    for (final (index, node) in nodes.indexed) {
      if (hasSchema) {
        report.error(
          .duplicateSchemaDefinition,
          'Cannot define a new schema within a schema extension.',
          node,
        );
      } else if (index > 0) {
        report.error(
          .duplicateSchemaDefinition,
          'Must provide only one schema definition.',
          node,
          related: report.spans.of(nodes.first),
        );
      }
    }
    return hasSchema ? null : nodes.firstOrNull;
  }

  Map<OperationType, String> _roots(
    Schema base,
    List<OperationTypeDefinition> nodes,
  ) {
    final roots = {
      for (final operation in OperationType.values)
        operation: ?base.rootTypeName(operation),
    };
    final firsts = <OperationType, OperationTypeDefinition>{};
    for (final node in nodes) {
      final operation = node.operation;
      if (base.rootTypeName(operation) != null) {
        report.error(
          .duplicateOperationType,
          'Type for ${operation.name} already defined in the schema. It '
          'cannot be redefined.',
          node,
        );
      } else if (firsts[operation] case final first?) {
        report.error(
          .duplicateOperationType,
          'There can be only one ${operation.name} type in schema.',
          node,
          related: report.spans.of(first),
        );
      } else {
        firsts[operation] = node;
        roots[operation] = node.type.name.value;
      }
    }
    return roots;
  }
}
```

In `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,6 +1,7 @@
 import '../../language/ast/document.dart';
 import '../../language/ast/executable_definition.dart';
 import '../../language/ast/type_system_definition.dart';
+import '../../language/ast/type_system_extension.dart';
 
 /// The definitions of a document sorted by what the builder does with
 /// them, each list in document order.
@@ -15,6 +16,8 @@ final class DocumentDefinitions {
           types.add(definition);
         case DirectiveDefinition():
           directives.add(definition);
+        case SchemaExtension():
+          schemaExtensions.add(definition);
         case ExecutableDefinition():
           executables.add(definition);
       }
@@ -24,6 +27,9 @@ final class DocumentDefinitions {
   /// The schema definitions; a valid document has at most one.
   final List<SchemaDefinition> schemas = [];
 
+  /// The schema extensions.
+  final List<SchemaExtension> schemaExtensions = [];
+
   /// The type definitions.
   final List<TypeDefinition> types = [];
 
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,11 +1,13 @@
 import '../../language/ast/operation_type.dart';
 import '../../language/ast/type_system_definition.dart';
+import '../model/schema_directive.dart';
 import '../model/schema_type.dart';
 import '../schema.dart';
 import 'build_report.dart';
 import 'document_definitions.dart';
 import 'element_reader.dart';
 import 'member_filter.dart';
+import 'schema_definition_reader.dart';
 import 'type_reader.dart';
 import 'unique_definitions.dart';
 
@@ -19,12 +21,41 @@ final class SchemaAssembly(
   this;
 
   /// The schema [definitions] define; default root types are taken from
-  /// types named `Query`, `Mutation` and `Subscription` when no schema
-  /// definition names the roots (spec §3.3.1).
+  /// types named `Query`, `Mutation` and `Subscription` for the operations
+  /// no schema definition or extension names (spec §3.3.1).
   Schema fromSdl(
     DocumentDefinitions definitions, {
     required bool includesDeferAndStream,
   }) {
+    final base = Schema(includesDeferAndStream: includesDeferAndStream);
+    _reportExecutables(definitions);
+    final unique = UniqueDefinitions(report, base);
+    final types = _types(base, unique.types(definitions.types));
+    final header = SchemaDefinitionReader(
+      report,
+      _elements,
+    ).read(base, definitions.schemas, definitions.schemaExtensions);
+    final defaults = definitions.schemas.isEmpty
+        ? _defaultRoots(types)
+        : const <OperationType, String>{};
+    return Schema(
+      types: types,
+      directives: _directives(base, unique.directives(definitions.directives)),
+      queryTypeName: header.queryTypeName ?? defaults[OperationType.query],
+      mutationTypeName:
+          header.mutationTypeName ?? defaults[OperationType.mutation],
+      subscriptionTypeName:
+          header.subscriptionTypeName ?? defaults[OperationType.subscription],
+      description: header.description,
+      appliedDirectives: header.appliedDirectives,
+      includesDeferAndStream: base.includesDeferAndStream,
+      span: header.span,
+    );
+  }
+
+  ElementReader get _elements => ElementReader(report.spans);
+
+  void _reportExecutables(DocumentDefinitions definitions) {
     for (final executable in definitions.executables) {
       report.error(
         .executableDefinitionInSchema,
@@ -32,38 +63,22 @@ final class SchemaAssembly(
         executable,
       );
     }
-    final unique = UniqueDefinitions(
-      report,
-      Schema(includesDeferAndStream: includesDeferAndStream),
-    );
-    final filter = MemberFilter(report);
-    final elements = ElementReader(report.spans);
-    final types = [
-      for (final type in unique.types(definitions.types))
-        TypeReader(elements).type(filter.definition(type)),
-    ];
-    final schema = definitions.schemas.firstOrNull;
-    final roots = schema == null ? _defaultRoots(types) : _roots(schema);
-    return Schema(
-      types: types,
-      directives: [
-        for (final directive in unique.directives(definitions.directives))
-          elements.directive(filter.directive(directive)),
-      ],
-      queryTypeName: roots[OperationType.query],
-      mutationTypeName: roots[OperationType.mutation],
-      subscriptionTypeName: roots[OperationType.subscription],
-      description: schema?.description?.value,
-      appliedDirectives: elements.appliedAll(schema?.directives ?? const []),
-      includesDeferAndStream: includesDeferAndStream,
-      span: schema == null ? null : report.spans.of(schema),
-    );
   }
 
-  Map<OperationType, String> _roots(SchemaDefinition schema) => {
-    for (final root in schema.operationTypes)
-      root.operation: root.type.name.value,
-  };
+  List<SchemaType> _types(Schema base, List<TypeDefinition> nodes) => [
+    ...base.types,
+    for (final node in nodes)
+      TypeReader(_elements).type(MemberFilter(report).definition(node)),
+  ];
+
+  List<SchemaDirective> _directives(
+    Schema base,
+    List<DirectiveDefinition> nodes,
+  ) => [
+    ...base.directives,
+    for (final node in nodes)
+      _elements.directive(MemberFilter(report).directive(node)),
+  ];
 
   Map<OperationType, String> _defaultRoots(List<SchemaType> types) => {
     for (final type in types) ?_defaultRootNames[type.name]: type.name,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/schema_builder_test.dart test/schema/build/schema_definition_reader_test.dart)
```

Expected: `schema_builder_test.dart` `+12`, `schema_definition_reader_test.dart` `+8`, each `All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -89,3 +89,5 @@
 - The builder keeps the first member of each name: `GQL104` for a
   repeated field or input field, `GQL105` for a repeated argument,
   `GQL106` for a repeated enum value.
+- The builder applies schema extensions; `GQL107` for a second schema
+  definition, `GQL108` for a second root type of one operation.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -197,7 +197,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   at its name and relates to the span of the definition it repeats; the
   first definition wins (`UniqueDefinitions`). `MemberFilter` drops repeated
   members and arguments from syntax nodes with `withChildren` before the
-  readers see them.
+  readers see them. `SchemaDefinitionReader` applies the schema definition
+  and `extend schema`; default roots fill only the operations that no schema
+  definition or extension names, and only without a schema definition.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/build/document_definitions.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/schema_definition_reader.dart packages/typed_graphql/test/schema/build/schema_builder_test.dart packages/typed_graphql/test/schema/build/schema_definition_reader_test.dart
git commit -q -m "feat(typed_graphql): apply the schema definition and schema extensions" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 10: Apply type extensions of every kind

R2.2 and spec §4: scalar, object, interface, union, enum and input object extensions.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/type_extender.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, `packages/typed_graphql/lib/src/schema/build/member_filter.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`
- Test: `packages/typed_graphql/test/schema/build/type_extender_test.dart`

**Interfaces:**
- Consumes: Tasks 6–9; M2a: the `TypeExtension` family.
- Produces:
  - `DiagnosticCode.unknownExtensionTarget` (`GQL109`), `extensionKindMismatch` (`GQL110`);
  - internal `TypeExtender(BuildReport report, Schema base)` with `List<SchemaType> applyAll(List<SchemaType> types, List<TypeExtension> extensions)`;
  - `DocumentDefinitions.typeExtensions`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/build/type_extender_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  List<String> namesOf(Iterable<Object> elements) => [
    for (final element in elements)
      switch (element) {
        SchemaField(:final name) => name,
        InputValue(:final name) => name,
        SchemaEnumValue(:final name) => name,
        AppliedDirective(:final name) => name,
        NamedType(:final name) => name.value,
        _ => fail('unexpected $element'),
      },
  ];

  test('extends a scalar with directives', () {
    final schema = Built('''
scalar Date @a
extend scalar Date @b''').schema;
    expect(namesOf(schema.typeNamed('Date')!.appliedDirectives), ['a', 'b']);
  });

  test('extends an object type, definition members first', () {
    final schema = Built('''
extend type Query implements B @b { b: Int }
type Query implements A @a { a: Int }
extend type Query implements C { c: Int }''').schema;
    final query = schema.typeNamed('Query') as ObjectType;
    expect(namesOf(query.fields), ['a', 'b', 'c']);
    expect(namesOf(query.interfaces), ['A', 'B', 'C']);
    expect(namesOf(query.appliedDirectives), ['a', 'b']);
  });

  test('keeps the span of the definition', () {
    final schema = Built('''
type Query { a: Int }
extend type Query { b: Int }''').schema;
    expect(schema.typeNamed('Query')?.span?.text, 'type Query { a: Int }');
  });

  test('extends an interface type', () {
    final schema = Built('''
interface Node { id: ID }
extend interface Node implements Entity @key { name: String }''').schema;
    final node = schema.typeNamed('Node') as InterfaceType;
    expect(namesOf(node.fields), ['id', 'name']);
    expect(namesOf(node.interfaces), ['Entity']);
    expect(namesOf(node.appliedDirectives), ['key']);
  });

  test('extends a union type', () {
    final schema = Built('''
union Result = A
extend union Result @key = B | C''').schema;
    final result = schema.typeNamed('Result') as UnionType;
    expect(namesOf(result.memberTypes), ['A', 'B', 'C']);
    expect(namesOf(result.appliedDirectives), ['key']);
  });

  test('extends an enum type', () {
    final schema = Built('''
enum Color { RED }
extend enum Color @key { GREEN }''').schema;
    final color = schema.typeNamed('Color') as EnumType;
    expect(namesOf(color.values), ['RED', 'GREEN']);
    expect(namesOf(color.appliedDirectives), ['key']);
  });

  test('extends an input object type', () {
    final schema = Built('''
input Filter { a: Int }
extend input Filter @oneOf { b: Int }''').schema;
    final filter = schema.typeNamed('Filter') as InputObjectType;
    expect(namesOf(filter.fields), ['a', 'b']);
    expect(filter.isOneOf, isTrue);
  });

  test('reports a field an extension repeats', () {
    final built = Built('''
type Query { a: Int }
extend type Query { a: String b: Int }''');
    expect(built.errors, [
      '2:21 GQL104 Field "Query.a" can only be defined once.',
    ]);
    expect(built.result.diagnostics.single.related.single.text, 'a: Int');
    final query = built.partial.typeNamed('Query') as ObjectType;
    expect(namesOf(query.fields), ['a', 'b']);
  });

  test('reports an enum value an extension repeats', () {
    expect(Built('enum E { A } extend enum E { A }').errors, [
      '1:30 GQL106 Enum value "E.A" can only be defined once.',
    ]);
  });

  test('reports an extension of a type that is not defined', () {
    final built = Built('extend type Missing { a: Int }');
    expect(built.errors, [
      '1:13 GQL109 Cannot extend type "Missing" because it is not defined.',
    ]);
    expect(built.partial.types, isEmpty);
  });

  test('reports an extension of another kind and ignores it', () {
    final built = Built('''
type A { a: Int }
extend input A { b: Int }''');
    expect(built.errors, [
      '2:14 GQL110 Cannot extend non-input object type "A".',
    ]);
    expect(built.result.diagnostics.single.related.single.start, 0);
    expect(namesOf((built.partial.types.single as ObjectType).fields), ['a']);
  });

  test('names the kind the extension expects', () {
    const sdl =
        'scalar S extend type S @a extend interface S @a '
        'extend union S @a extend enum S @a extend scalar Missing @a';
    expect(Built(sdl).errors.map((error) => error.substring(5)), [
      'GQL110 Cannot extend non-object type "S".',
      'GQL110 Cannot extend non-interface type "S".',
      'GQL110 Cannot extend non-union type "S".',
      'GQL110 Cannot extend non-enum type "S".',
      'GQL109 Cannot extend type "Missing" because it is not defined.',
    ]);
    expect(Built('type T extend scalar T @a').errors, [
      '1:22 GQL110 Cannot extend non-scalar type "T".',
    ]);
  });

  test('rejects an extension of a built-in type', () {
    expect(Built('extend scalar String @a').errors, [
      '1:15 GQL103 The built-in type "String" cannot be extended.',
    ]);
  });

  test('extends the first of two types with one name', () {
    final built = Built('''
type A { a: Int }
input A { b: Int }
extend type A { c: Int }''');
    expect(built.errors, hasLength(1));
    expect(namesOf((built.partial.types.single as ObjectType).fields), [
      'a',
      'c',
    ]);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/type_extender_test.dart)
```

Expected: FAIL. `+1 -13`: only `keeps the span of the definition` passes. The extensions are ignored, so the members stay those of the definition (`Expected: ['a', 'b']`, `Actual: ['a']`), and nothing is reported (`Expected: ['1:13 GQL109 Cannot extend type "Missing" because it is not defined.']`, `Actual: []`).

- [ ] **Step 3: Add the codes**

In `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -123,5 +123,13 @@ enum DiagnosticCode(
   /// `GQL108`: a second root type for one operation, in the schema
   /// definition, its extensions or the schema being extended; the second
   /// is ignored.
-  duplicateOperationType('GQL108');
+  duplicateOperationType('GQL108'),
+
+  /// `GQL109`: an extension of a type that neither the document nor the
+  /// schema being extended defines; it is ignored.
+  unknownExtensionTarget('GQL109'),
+
+  /// `GQL110`: an extension of a type of another kind, such as
+  /// `extend input` of an object type; it is ignored.
+  extensionKindMismatch('GQL110');
 }
```

- [ ] **Step 4: Write the implementation**

`TypeExtender` applies each extension to the first type of its name, in document order, appending its members and directives after the definition's. An extension of an undefined type is `GQL109`, of another kind `GQL110` (graphql-js's "Cannot extend non-input object type"), of a built-in `GQL103`; each is ignored. `MemberFilter` now sees a type together with its extensions, so a member an extension repeats is reported too. The definition keeps its span: an extension does not move it.

Create `packages/typed_graphql/lib/src/schema/build/type_extender.dart`:

```dart
import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_extension.dart';
import '../model/applied_directive.dart';
import '../model/schema_type.dart';
import 'build_report.dart';
import 'built_ins.dart';
import 'element_reader.dart';
import 'member_filter.dart';

/// Applies type extensions to the types of a schema (spec §3.4.3): the
/// members, interfaces, union members and directives of an extension go
/// after the type's own, in document order; the span stays the
/// definition's.
///
/// An extension of a built-in, of a missing type or of a type of another
/// kind is reported and ignored, with graphql-js's messages
/// (`PossibleTypeExtensionsRule`).
final class TypeExtender(
  /// Receives the errors and gives the spans.
  final BuildReport report,
) {
  /// Creates an extender.
  this;

  /// [types] with [extensions] applied, in the order of [types].
  List<SchemaType> applyAll(
    List<SchemaType> types,
    List<TypeExtension> extensions,
  ) {
    final extended = {for (final type in types.reversed) type.name: type};
    for (final node in extensions) {
      final name = node.name.value;
      if (const BuiltIns().typeNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "$name" cannot be extended.',
          node.name,
        );
      } else if (extended[name] case final type?) {
        extended[name] = _extend(type, node) ?? _mismatch(type, node);
      } else {
        report.error(
          .unknownExtensionTarget,
          'Cannot extend type "$name" because it is not defined.',
          node.name,
        );
      }
    }
    return [for (final type in types) extended[type.name] ?? type];
  }

  SchemaType _mismatch(SchemaType type, TypeExtension node) {
    final kind = switch (node) {
      ScalarTypeExtension() => 'scalar',
      ObjectTypeExtension() => 'object',
      InterfaceTypeExtension() => 'interface',
      UnionTypeExtension() => 'union',
      EnumTypeExtension() => 'enum',
      InputObjectTypeExtension() => 'input object',
    };
    report.error(
      .extensionKindMismatch,
      'Cannot extend non-$kind type "${type.name}".',
      node.name,
      related: type.span,
    );
    return type;
  }

  /// [type] extended by [node]; null when their kinds differ.
  SchemaType? _extend(SchemaType type, TypeExtension node) =>
      switch ((type, node)) {
        (ScalarType(), ScalarTypeExtension()) => ScalarType(
          type.name,
          description: type.description,
          appliedDirectives: _directives(type, node),
          span: type.span,
        ),
        (final ObjectType type, final ObjectTypeExtension node) => _object(
          type,
          node,
        ),
        (final InterfaceType type, final InterfaceTypeExtension node) =>
          _interface(type, node),
        (final UnionType type, final UnionTypeExtension node) => UnionType(
          type.name,
          description: type.description,
          appliedDirectives: _directives(type, node),
          memberTypes: [...type.memberTypes, ...node.types],
          span: type.span,
        ),
        (final EnumType type, final EnumTypeExtension node) => _enum(
          type,
          node,
        ),
        (final InputObjectType type, final InputObjectTypeExtension node) =>
          _inputObject(type, node),
        _ => null,
      };

  ObjectType _object(ObjectType type, ObjectTypeExtension node) => ObjectType(
    type.name,
    description: type.description,
    interfaces: [...type.interfaces, ...node.interfaces],
    appliedDirectives: _directives(type, node),
    fields: [
      ...type.fields,
      for (final field in _members<FieldDefinition>(type, node))
        _elements.field(field),
    ],
    span: type.span,
  );

  InterfaceType _interface(InterfaceType type, InterfaceTypeExtension node) =>
      InterfaceType(
        type.name,
        description: type.description,
        interfaces: [...type.interfaces, ...node.interfaces],
        appliedDirectives: _directives(type, node),
        fields: [
          ...type.fields,
          for (final field in _members<FieldDefinition>(type, node))
            _elements.field(field),
        ],
        span: type.span,
      );

  EnumType _enum(EnumType type, EnumTypeExtension node) => EnumType(
    type.name,
    description: type.description,
    appliedDirectives: _directives(type, node),
    values: [
      ...type.values,
      for (final value in _members<EnumValueDefinition>(type, node))
        _elements.enumValue(value),
    ],
    span: type.span,
  );

  InputObjectType _inputObject(
    InputObjectType type,
    InputObjectTypeExtension node,
  ) => InputObjectType(
    type.name,
    description: type.description,
    appliedDirectives: _directives(type, node),
    fields: [
      ...type.fields,
      for (final field in _members<InputValueDefinition>(type, node))
        _elements.inputValue(field),
    ],
    span: type.span,
  );

  ElementReader get _elements => ElementReader(report.spans);

  List<AppliedDirective> _directives(SchemaType type, TypeExtension node) => [
    ...type.appliedDirectives,
    ..._elements.appliedAll(node.directives),
  ];

  /// The members of [node] that [type] does not have yet.
  Iterable<T> _members<T extends Node>(SchemaType type, TypeExtension node) {
    final earlier = switch (type) {
      ObjectType(:final fields) || InterfaceType(:final fields) => {
        for (final field in fields) field.name: field.span,
      },
      EnumType(:final values) => {
        for (final value in values) value.name: value.span,
      },
      InputObjectType(:final fields) => {
        for (final field in fields) field.name: field.span,
      },
      ScalarType() || UnionType() => const <String, Never>{},
    };
    return MemberFilter(
      report,
    ).members(type.name, node.children, earlier).whereType<T>();
  }
}
```

In `packages/typed_graphql/lib/src/schema/build/member_filter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -24,7 +24,7 @@ final class MemberFilter(
   /// [node] without repeated fields, input fields, enum values and field
   /// arguments.
   TypeDefinition definition(TypeDefinition node) =>
-      node.withChildren(_members(node.name.value, node.children))
+      node.withChildren(members(node.name.value, node.children, const {}))
           as TypeDefinition;
 
   /// [node] without repeated arguments.
@@ -32,8 +32,16 @@ final class MemberFilter(
       node.withChildren(_arguments('@${node.name.value}', node.children))
           as DirectiveDefinition;
 
-  List<Node> _members(String typeName, List<Node> children) {
-    final seen = <String, SourceSpan?>{};
+  /// [children] of a definition or an extension of the type [typeName]
+  /// without the members named in [earlier] or before in [children]; the
+  /// kept fields lose their repeated arguments. [earlier] maps the names of
+  /// the members the type already has to their spans.
+  List<Node> members(
+    String typeName,
+    List<Node> children,
+    Map<String, SourceSpan?> earlier,
+  ) {
+    final seen = {...earlier};
     final kept = <Node>[];
     for (final child in children) {
       final member = switch (child) {
```

In `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -14,6 +14,8 @@ final class DocumentDefinitions {
           schemas.add(definition);
         case TypeDefinition():
           types.add(definition);
+        case TypeExtension():
+          typeExtensions.add(definition);
         case DirectiveDefinition():
           directives.add(definition);
         case SchemaExtension():
@@ -33,6 +35,9 @@ final class DocumentDefinitions {
   /// The type definitions.
   final List<TypeDefinition> types = [];
 
+  /// The type extensions.
+  final List<TypeExtension> typeExtensions = [];
+
   /// The directive definitions.
   final List<DirectiveDefinition> directives = [];
 
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -8,6 +8,7 @@ import 'document_definitions.dart';
 import 'element_reader.dart';
 import 'member_filter.dart';
 import 'schema_definition_reader.dart';
+import 'type_extender.dart';
 import 'type_reader.dart';
 import 'unique_definitions.dart';
 
@@ -30,7 +31,10 @@ final class SchemaAssembly(
     final base = Schema(includesDeferAndStream: includesDeferAndStream);
     _reportExecutables(definitions);
     final unique = UniqueDefinitions(report, base);
-    final types = _types(base, unique.types(definitions.types));
+    final types = TypeExtender(report).applyAll(
+      _types(base, unique.types(definitions.types)),
+      definitions.typeExtensions,
+    );
     final header = SchemaDefinitionReader(
       report,
       _elements,
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/type_extender_test.dart)
```

Expected: `+14: All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -91,3 +91,6 @@
   `GQL106` for a repeated enum value.
 - The builder applies schema extensions; `GQL107` for a second schema
   definition, `GQL108` for a second root type of one operation.
+- The builder applies type extensions of every kind; `GQL109` for an
+  extension of a missing type, `GQL110` for one of another kind,
+  `GQL103` for one of a built-in.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -200,6 +200,9 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   readers see them. `SchemaDefinitionReader` applies the schema definition
   and `extend schema`; default roots fill only the operations that no schema
   definition or extension names, and only without a schema definition.
+  `TypeExtender` appends an extension's members, interfaces, union members
+  and directives after the type's own, in document order, and keeps the
+  definition's span.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart packages/typed_graphql/lib/src/schema/build/document_definitions.dart packages/typed_graphql/lib/src/schema/build/member_filter.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/type_extender.dart packages/typed_graphql/test/schema/build/type_extender_test.dart
git commit -q -m "feat(typed_graphql): apply type extensions of every kind" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 11: Extend an existing schema

Spec §4 and deviation 4 of spec §13: graphql-js's `extendSchema`.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/build/directive_extender.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, `packages/typed_graphql/lib/src/schema/build/member_filter.dart`, `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`, `packages/typed_graphql/lib/src/schema/build/type_extender.dart`
- Test: `packages/typed_graphql/test/schema/build/schema_extend_test.dart`, `packages/typed_graphql/test/schema/built.dart`

**Interfaces:**
- Consumes: Tasks 6–10; M2b/M2a: `DirectiveExtension` (working draft).
- Produces:
  - `BuildResult SchemaBuilder.extend(Schema schema, Document document, {Source? source})`;
  - internal `SchemaAssembly.extend(Schema base, DocumentDefinitions definitions)`, `DirectiveExtender(BuildReport report, Schema base)` with `List<SchemaDirective> applyAll(List<SchemaDirective>, List<DirectiveExtension>)`;
  - `DocumentDefinitions.directiveExtensions` and `bool hasTypeSystem`;
  - test helper `Built.extending(Schema base, String text)`.

- [ ] **Step 1: Extend the test helper**

`Built.extending(base, text)` extends a schema.

In `packages/typed_graphql/test/schema/built.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,9 +9,19 @@ final class Built {
   Built(String text, {SchemaBuilder builder = const SchemaBuilder()})
     : this._(Sdl(text), builder);
 
+  /// Extends [base] with [text].
+  Built.extending(Schema base, String text) : this._onto(base, Sdl(text));
+
   Built._(Sdl sdl, SchemaBuilder builder)
     : result = builder.fromSdl(sdl.document, source: sdl.source);
 
+  Built._onto(Schema base, Sdl sdl)
+    : result = const SchemaBuilder().extend(
+        base,
+        sdl.document,
+        source: sdl.source,
+      );
+
   /// What the builder returned.
   final BuildResult result;
 
```

- [ ] **Step 2: Write the failing tests**

Create `packages/typed_graphql/test/schema/build/schema_extend_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  final base = Built('''
directive @key on OBJECT
type Query { a: Int }
enum Color { RED }''').schema;

  List<String> fieldsOf(Schema schema, String type) => [
    for (final field in (schema.typeNamed(type) as ObjectType).fields)
      field.name,
  ];

  test('adds new types after the schema\'s and keeps its roots', () {
    final schema = Built.extending(base, 'type Mutation { b: Int }').schema;
    expect(schema.types.map((type) => type.name), [
      'Query',
      'Color',
      'Mutation',
    ]);
    expect(schema.queryTypeName, 'Query');
    expect(schema.mutationTypeName, isNull);
  });

  test('extends a type of the schema after its own fields', () {
    final schema = Built.extending(base, 'extend type Query { b: Int }').schema;
    expect(fieldsOf(schema, 'Query'), ['a', 'b']);
    expect(fieldsOf(base, 'Query'), ['a']);
  });

  test('keeps the spans of both sources', () {
    final schema = Built.extending(base, 'extend type Query { b: Int }').schema;
    final query = schema.typeNamed('Query') as ObjectType;
    expect(query.span?.text, 'type Query { a: Int }');
    expect(query.fieldNamed('b')?.span?.text, 'b: Int');
  });

  test('gives the schema back for a document without definitions', () {
    final result = const SchemaBuilder().extend(base, Document(const []));
    expect((result as BuildSuccess).schema, same(base));
  });

  test('gives the schema back, failed, for operations only', () {
    final built = Built.extending(base, 'query { a }');
    expect(built.partial, same(base));
    expect(built.errors.single, contains('GQL100'));
  });

  test('rejects a field the schema\'s type has', () {
    final built = Built.extending(base, 'extend type Query { a: String }');
    expect(built.errors, [
      '1:21 GQL104 Field "Query.a" already exists in the schema. It cannot '
          'also be defined in this type extension.',
    ]);
    expect(built.result.diagnostics.single.related, isEmpty);
  });

  test('rejects an enum value the schema\'s type has', () {
    expect(Built.extending(base, 'extend enum Color { RED }').errors, [
      '1:21 GQL106 Enum value "Color.RED" already exists in the schema. It '
          'cannot also be defined in this type extension.',
    ]);
  });

  test('words a repeat of a field added by the document as a repeat', () {
    final built = Built.extending(base, '''
extend type Query { b: Int }
extend type Query { b: Int }''');
    expect(built.errors, [
      '2:21 GQL104 Field "Query.b" can only be defined once.',
    ]);
  });

  test('rejects a type the schema has', () {
    expect(Built.extending(base, 'enum Query { A }').errors, [
      '1:6 GQL101 Type "Query" already exists in the schema. It cannot also '
          'be defined in this type definition.',
    ]);
  });

  test('takes no default root types', () {
    final schema = Built.extending(Schema(), 'type Query { a: Int }').schema;
    expect(schema.queryTypeName, isNull);
  });

  test('keeps whether the schema includes @defer and @stream', () {
    final withDefer = Schema(includesDeferAndStream: true);
    final built = Built.extending(withDefer, 'directive @defer on FIELD');
    expect(built.errors.single, contains('GQL103'));
    expect(built.partial.includesDeferAndStream, isTrue);
  });

  group('directive extensions', () {
    test('add directives to a directive of the schema', () {
      final schema = Built.extending(base, 'extend directive @key @a').schema;
      final key = schema.directiveNamed('key');
      expect(key?.appliedDirectives.map((directive) => directive.name), [
        'a',
      ]);
      expect(base.directiveNamed('key')?.appliedDirectives, isEmpty);
    });

    test('add directives to a directive of the document', () {
      final schema = Built('''
extend directive @d @b
directive @d @a on FIELD''').schema;
      final d = schema.directiveNamed('d');
      expect(d?.appliedDirectives.map((directive) => directive.name), [
        'a',
        'b',
      ]);
    });

    test('report a directive that is not defined', () {
      expect(Built('extend directive @missing @a').errors, [
        '1:19 GQL109 Cannot extend directive "@missing" because it is not '
            'defined.',
      ]);
    });

    test('report a built-in directive', () {
      expect(Built('extend directive @skip @a').errors, [
        '1:19 GQL103 The built-in directive "@skip" cannot be extended.',
      ]);
    });
  });
}
```

- [ ] **Step 3: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/schema_extend_test.dart)
```

Expected: FAIL. `Error: The method 'extend' isn't defined for the type 'SchemaBuilder'.`

- [ ] **Step 4: Write the implementation**

graphql-js's `extendSchema`: the document's types come after the schema's, an extension applies to a type of either, and the schema's own elements keep their spans. A document with no type-system definition gives the schema back, the same instance; with operations only, it is a `BuildFailure` whose partial is that instance. A member that the schema's type already has is reported with graphql-js's "already exists in the schema" wording. No default root types are taken. Directive extensions (working draft, M2a's `allowDirectiveExtensions`) add directives to a directive definition of the schema or the document, through `DirectiveExtender`.

In `packages/typed_graphql/lib/src/schema/build/schema_builder.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,5 +1,6 @@
 import '../../diagnostics/source.dart';
 import '../../language/ast/document.dart';
+import '../schema.dart';
 import 'build_report.dart';
 import 'build_result.dart';
 import 'document_definitions.dart';
@@ -29,8 +30,25 @@ final class const SchemaBuilder({
       DocumentDefinitions.of(document),
       includesDeferAndStream: includesDeferAndStream,
     );
-    return report.hasErrors
-        ? BuildFailure(schema, report.diagnostics)
-        : BuildSuccess(schema);
+    return _result(schema, report);
   }
+
+  /// [schema] with the type-system definitions and extensions of
+  /// [document] applied (graphql-js's `extendSchema`); [schema] itself when
+  /// [document] has none.
+  ///
+  /// [source] is the text [document] was parsed from, as for [fromSdl];
+  /// the elements [schema] already has keep their spans. Whether `@defer`
+  /// and `@stream` exist is [schema]'s, not this builder's.
+  BuildResult extend(Schema schema, Document document, {Source? source}) {
+    final report = BuildReport(NodeSpans(source));
+    final extended = SchemaAssembly(
+      report,
+    ).extend(schema, DocumentDefinitions.of(document));
+    return _result(extended, report);
+  }
+
+  BuildResult _result(Schema schema, BuildReport report) => report.hasErrors
+      ? BuildFailure(schema, report.diagnostics)
+      : BuildSuccess(schema);
 }
```

In `packages/typed_graphql/lib/src/schema/build/schema_assembly.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,6 +4,7 @@ import '../model/schema_directive.dart';
 import '../model/schema_type.dart';
 import '../schema.dart';
 import 'build_report.dart';
+import 'directive_extender.dart';
 import 'document_definitions.dart';
 import 'element_reader.dart';
 import 'member_filter.dart';
@@ -27,11 +28,30 @@ final class SchemaAssembly(
   Schema fromSdl(
     DocumentDefinitions definitions, {
     required bool includesDeferAndStream,
+  }) => _apply(
+    Schema(includesDeferAndStream: includesDeferAndStream),
+    definitions,
+    appliesDefaultRoots: definitions.schemas.isEmpty,
+  );
+
+  /// [base] with [definitions] applied, as graphql-js's `extendSchema`:
+  /// [base] itself when there is no type-system definition or extension.
+  Schema extend(Schema base, DocumentDefinitions definitions) {
+    if (definitions.hasTypeSystem) {
+      return _apply(base, definitions, appliesDefaultRoots: false);
+    }
+    _reportExecutables(definitions);
+    return base;
+  }
+
+  Schema _apply(
+    Schema base,
+    DocumentDefinitions definitions, {
+    required bool appliesDefaultRoots,
   }) {
-    final base = Schema(includesDeferAndStream: includesDeferAndStream);
     _reportExecutables(definitions);
     final unique = UniqueDefinitions(report, base);
-    final types = TypeExtender(report).applyAll(
+    final types = TypeExtender(report, base).applyAll(
       _types(base, unique.types(definitions.types)),
       definitions.typeExtensions,
     );
@@ -39,12 +59,15 @@ final class SchemaAssembly(
       report,
       _elements,
     ).read(base, definitions.schemas, definitions.schemaExtensions);
-    final defaults = definitions.schemas.isEmpty
+    final defaults = appliesDefaultRoots
         ? _defaultRoots(types)
         : const <OperationType, String>{};
     return Schema(
       types: types,
-      directives: _directives(base, unique.directives(definitions.directives)),
+      directives: DirectiveExtender(report, base).applyAll(
+        _directives(base, unique.directives(definitions.directives)),
+        definitions.directiveExtensions,
+      ),
       queryTypeName: header.queryTypeName ?? defaults[OperationType.query],
       mutationTypeName:
           header.mutationTypeName ?? defaults[OperationType.mutation],
```

Create `packages/typed_graphql/lib/src/schema/build/directive_extender.dart`:

```dart
import '../../language/ast/type_system_extension.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'build_report.dart';
import 'element_reader.dart';

/// Applies directive extensions, `extend directive @name @d` (working
/// draft): the directives they apply go after the definition's own.
///
/// An extension of a built-in or of a missing directive is reported and
/// ignored.
final class DirectiveExtender(
  /// Receives the errors and gives the spans.
  final BuildReport report,

  /// The schema being extended, which tells the built-ins it has.
  final Schema base,
) {
  /// Creates an extender.
  this;

  /// [directives] with [extensions] applied, in the order of
  /// [directives]; an extension applies to the first directive of its
  /// name.
  List<SchemaDirective> applyAll(
    List<SchemaDirective> directives,
    List<DirectiveExtension> extensions,
  ) {
    final extended = [...directives];
    final indexes = <String, int>{};
    for (final (index, directive) in directives.indexed) {
      indexes.putIfAbsent(directive.name, () => index);
    }
    for (final node in extensions) {
      final name = node.name.value;
      if (indexes[name] case final index?) {
        extended[index] = _extend(extended[index], node);
      } else if (base.directiveNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in directive "@$name" cannot be extended.',
          node.name,
        );
      } else {
        report.error(
          .unknownExtensionTarget,
          'Cannot extend directive "@$name" because it is not defined.',
          node.name,
        );
      }
    }
    return extended;
  }

  SchemaDirective _extend(SchemaDirective directive, DirectiveExtension node) =>
      SchemaDirective(
        directive.name,
        description: directive.description,
        arguments: directive.arguments,
        isRepeatable: directive.isRepeatable,
        locations: directive.locations,
        appliedDirectives: [
          ...directive.appliedDirectives,
          ...ElementReader(report.spans).appliedAll(node.directives),
        ],
        span: directive.span,
      );
}
```

In `packages/typed_graphql/lib/src/schema/build/type_extender.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,3 +1,4 @@
+import '../../diagnostics/source_span.dart';
 import '../../language/ast/enum_value_definition.dart';
 import '../../language/ast/field_definition.dart';
 import '../../language/ast/input_value_definition.dart';
@@ -5,6 +6,7 @@ import '../../language/ast/node.dart';
 import '../../language/ast/type_system_extension.dart';
 import '../model/applied_directive.dart';
 import '../model/schema_type.dart';
+import '../schema.dart';
 import 'build_report.dart';
 import 'built_ins.dart';
 import 'element_reader.dart';
@@ -21,16 +23,25 @@ import 'member_filter.dart';
 final class TypeExtender(
   /// Receives the errors and gives the spans.
   final BuildReport report,
+
+  /// The schema being extended: a member its type has is "already in the
+  /// schema", which graphql-js words differently from a repeat.
+  final Schema base,
 ) {
   /// Creates an extender.
   this;
 
-  /// [types] with [extensions] applied, in the order of [types].
+  /// [types] with [extensions] applied, in the order of [types]; an
+  /// extension applies to the first type of its name.
   List<SchemaType> applyAll(
     List<SchemaType> types,
     List<TypeExtension> extensions,
   ) {
-    final extended = {for (final type in types.reversed) type.name: type};
+    final extended = [...types];
+    final indexes = <String, int>{};
+    for (final (index, type) in types.indexed) {
+      indexes.putIfAbsent(type.name, () => index);
+    }
     for (final node in extensions) {
       final name = node.name.value;
       if (const BuiltIns().typeNamed(name) != null) {
@@ -39,8 +50,9 @@ final class TypeExtender(
           'The built-in type "$name" cannot be extended.',
           node.name,
         );
-      } else if (extended[name] case final type?) {
-        extended[name] = _extend(type, node) ?? _mismatch(type, node);
+      } else if (indexes[name] case final index?) {
+        final type = extended[index];
+        extended[index] = _extend(type, node) ?? _mismatch(type, node);
       } else {
         report.error(
           .unknownExtensionTarget,
@@ -49,7 +61,7 @@ final class TypeExtender(
         );
       }
     }
-    return [for (final type in types) extended[type.name] ?? type];
+    return extended;
   }
 
   SchemaType _mismatch(SchemaType type, TypeExtension node) {
@@ -164,20 +176,29 @@ final class TypeExtender(
 
   /// The members of [node] that [type] does not have yet.
   Iterable<T> _members<T extends Node>(SchemaType type, TypeExtension node) {
-    final earlier = switch (type) {
-      ObjectType(:final fields) || InterfaceType(:final fields) => {
-        for (final field in fields) field.name: field.span,
-      },
-      EnumType(:final values) => {
-        for (final value in values) value.name: value.span,
-      },
-      InputObjectType(:final fields) => {
-        for (final field in fields) field.name: field.span,
-      },
-      ScalarType() || UnionType() => const <String, Never>{},
-    };
-    return MemberFilter(
-      report,
-    ).members(type.name, node.children, earlier).whereType<T>();
+    final original = base.typeNamed(type.name);
+    return MemberFilter(report)
+        .members(
+          type.name,
+          node.children,
+          _memberSpans(type),
+          inSchema: original == null
+              ? const {}
+              : {..._memberSpans(original).keys},
+        )
+        .whereType<T>();
   }
+
+  Map<String, SourceSpan?> _memberSpans(SchemaType type) => switch (type) {
+    ObjectType(:final fields) || InterfaceType(:final fields) => {
+      for (final field in fields) field.name: field.span,
+    },
+    EnumType(:final values) => {
+      for (final value in values) value.name: value.span,
+    },
+    InputObjectType(:final fields) => {
+      for (final field in fields) field.name: field.span,
+    },
+    ScalarType() || UnionType() => const {},
+  };
 }
```

In `packages/typed_graphql/lib/src/schema/build/member_filter.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -34,13 +34,17 @@ final class MemberFilter(
 
   /// [children] of a definition or an extension of the type [typeName]
   /// without the members named in [earlier] or before in [children]; the
-  /// kept fields lose their repeated arguments. [earlier] maps the names of
-  /// the members the type already has to their spans.
+  /// kept fields lose their repeated arguments.
+  ///
+  /// [earlier] maps the names of the members the type already has to their
+  /// spans; a name in [inSchema] came from the schema being extended,
+  /// which graphql-js words differently.
   List<Node> members(
     String typeName,
     List<Node> children,
-    Map<String, SourceSpan?> earlier,
-  ) {
+    Map<String, SourceSpan?> earlier, {
+    Set<String> inSchema = const {},
+  }) {
     final seen = {...earlier};
     final kept = <Node>[];
     for (final child in children) {
@@ -52,13 +56,18 @@ final class MemberFilter(
       };
       switch (_memberName(member)) {
         case final name? when seen.containsKey(name.value):
-          final isEnumValue = member is EnumValueDefinition;
+          final isInSchema = inSchema.contains(name.value);
           report.error(
-            isEnumValue ? .duplicateEnumValueName : .duplicateFieldName,
-            '${isEnumValue ? 'Enum value' : 'Field'} '
-            '"$typeName.${name.value}" can only be defined once.',
+            member is EnumValueDefinition
+                ? .duplicateEnumValueName
+                : .duplicateFieldName,
+            _message(
+              member,
+              '$typeName.${name.value}',
+              isInSchema: isInSchema,
+            ),
             name,
-            related: seen[name.value],
+            related: isInSchema ? null : seen[name.value],
           );
         case final name?:
           seen[name.value] = report.spans.of(member);
@@ -92,6 +101,18 @@ final class MemberFilter(
     return kept;
   }
 
+  String _message(
+    Node member,
+    String coordinate, {
+    required bool isInSchema,
+  }) {
+    final what = member is EnumValueDefinition ? 'Enum value' : 'Field';
+    return isInSchema
+        ? '$what "$coordinate" already exists in the schema. It cannot also '
+              'be defined in this type extension.'
+        : '$what "$coordinate" can only be defined once.';
+  }
+
   Name? _memberName(Node node) => switch (node) {
     FieldDefinition(:final name) => name,
     InputValueDefinition(:final name) => name,
```

In `packages/typed_graphql/lib/src/schema/build/document_definitions.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -20,6 +20,8 @@ final class DocumentDefinitions {
           directives.add(definition);
         case SchemaExtension():
           schemaExtensions.add(definition);
+        case DirectiveExtension():
+          directiveExtensions.add(definition);
         case ExecutableDefinition():
           executables.add(definition);
       }
@@ -41,6 +43,18 @@ final class DocumentDefinitions {
   /// The directive definitions.
   final List<DirectiveDefinition> directives = [];
 
+  /// The directive extensions (working draft).
+  final List<DirectiveExtension> directiveExtensions = [];
+
   /// What a schema cannot hold: operations and fragments.
   final List<ExecutableDefinition> executables = [];
+
+  /// Whether there is a type-system definition or extension.
+  bool get hasTypeSystem =>
+      schemas.isNotEmpty ||
+      schemaExtensions.isNotEmpty ||
+      types.isNotEmpty ||
+      typeExtensions.isNotEmpty ||
+      directives.isNotEmpty ||
+      directiveExtensions.isNotEmpty;
 }
```

- [ ] **Step 5: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/build/schema_extend_test.dart)
```

Expected: `+15: All tests passed!`

- [ ] **Step 6: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -94,3 +94,7 @@
 - The builder applies type extensions of every kind; `GQL109` for an
   extension of a missing type, `GQL110` for one of another kind,
   `GQL103` for one of a built-in.
+- `SchemaBuilder.extend`: applies a document's definitions and extensions
+  to an existing `Schema` (graphql-js's `extendSchema`), giving the schema
+  back when the document has none; directive extensions (working draft)
+  are applied too.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -202,7 +202,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   definition or extension names, and only without a schema definition.
   `TypeExtender` appends an extension's members, interfaces, union members
   and directives after the type's own, in document order, and keeps the
-  definition's span.
+  definition's span. `extend(schema, document, source:)` is the same run
+  over a base schema, without default roots; a member the base already has
+  is "already exists in the schema" (no related span). `DirectiveExtender`
+  applies `extend directive`.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 7: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 8: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/build/directive_extender.dart packages/typed_graphql/lib/src/schema/build/document_definitions.dart packages/typed_graphql/lib/src/schema/build/member_filter.dart packages/typed_graphql/lib/src/schema/build/schema_assembly.dart packages/typed_graphql/lib/src/schema/build/schema_builder.dart packages/typed_graphql/lib/src/schema/build/type_extender.dart packages/typed_graphql/test/schema/build/schema_extend_test.dart packages/typed_graphql/test/schema/built.dart
git commit -q -m "feat(typed_graphql): extend an existing schema" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 12: Print the types of a schema as SDL

R2.5 and spec §5: `SchemaPrinter`, for types first.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/print/member_printer.dart`, `packages/typed_graphql/lib/src/schema/print/schema_printer.dart`, `packages/typed_graphql/lib/src/schema/print/type_printer.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/print/type_printing_test.dart`

**Interfaces:**
- Consumes: Tasks 1–5; M2a: `Printer`, `BlockString`.
- Produces:
  - `final class const SchemaPrinter()` with `String print(Schema schema)` (no trailing line break);
  - internal `MemberPrinter` (`description`, `directives`, `arguments`, `inputValue`) and `TypePrinter` (`String type(SchemaType)`, `String directive(SchemaDirective)`).

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/print/type_printing_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  /// [sdl] built and printed.
  String reprint(String sdl) => const SchemaPrinter().print(Built(sdl).schema);

  test('prints every kind of type, in declaration order', () {
    const sdl = '''
scalar Date

type Query implements Node & Entity {
  id: ID!
  tags: [String!]!
}

interface Node implements Entity {
  id: ID!
}

union Result = Query | Node

enum Color {
  RED
  GREEN
}

input Filter {
  color: Color = RED
  limit: Int = 10
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints a type without members without braces', () {
    const sdl =
        'type Empty\n\ninterface Nothing\n\nunion None\n\nenum E\n\n'
        'input In';
    expect(reprint(sdl), sdl);
  });

  test('prints arguments on one line without descriptions', () {
    const sdl = '''
type Query {
  hero(episode: Episode = JEDI, first: Int! = 3, filter: In = { a: [1, 2] }): String
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints arguments on their own lines when one has a description', () {
    const sdl = '''
type Query {
  hero(
    """Which one"""
    episode: Episode
    first: Int
  ): String
}''';
    expect(reprint(sdl), sdl);
  });

  test('puts a blank line before a described member that is not first', () {
    const sdl = '''
"""A type"""
type Query {
  """First"""
  a: Int

  """Second"""
  b(
    """Argument"""
    x: Int

    """Other"""
    y: Int
  ): Int
  c: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints a description that cannot be a block string as quoted', () {
    final schema = Schema(
      types: [ScalarType('A', description: 'Ends with a break\n')],
    );
    expect(
      const SchemaPrinter().print(schema),
      '"Ends with a break\\n"\n'
      'scalar A',
    );
  });

  test('prints a multi-line description as a block, indented', () {
    const sdl = '''
type Query {
  """
  Line one

  Line three
  """
  a: Int
}''';
    expect(reprint(sdl), sdl.replaceFirst('one\n\n', 'one\n  \n'));
  });

  test('prints applied directives as written', () {
    const sdl = '''
scalar Date @specifiedBy(url: "https://example.com") @key

type Query @key(fields: "id") {
  a(x: Int @deprecated): Int @deprecated(reason: "No longer supported")
}

union U @key = Query

enum E @key {
  A @deprecated
}

input In @oneOf {
  a: Int @deprecated(reason: "Use b")
}''';
    expect(reprint(sdl), sdl);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/print/type_printing_test.dart)
```

Expected: FAIL. `Error: Couldn't find constructor 'SchemaPrinter'.`

- [ ] **Step 3: Write the implementation**

graphql-js's `printSchema` for the types: descriptions as block strings (quoted when `BlockString().isPrintable` says a block cannot hold them), arguments on one line unless one has a description, a blank line before a described member that is not the first. Values and type references go through the language `Printer`, so a default value prints exactly as written (spec §3). Every applied directive is printed, not only `@deprecated` and `@specifiedBy` (decision 6). This task prints types only; Task 13 adds the schema definition and directives.

Create `packages/typed_graphql/lib/src/schema/print/member_printer.dart`:

```dart
import '../../language/lexer/block_string.dart';
import '../../language/printer/printer.dart';
import '../../language/printer/quoted_string.dart';
import '../model/applied_directive.dart';
import '../model/input_value.dart';
import '../model/schema_enum_value.dart';
import '../model/schema_field.dart';

/// Prints the parts of schema elements as graphql-js's `printSchema`:
/// descriptions, member blocks, arguments and applied directives.
///
/// Values and type references go through the language [Printer], so
/// `ENUM` stays an enum value and `"s"` a string.
final class const MemberPrinter() {
  /// Creates a printer.
  this;

  static const Printer _printer = Printer();

  /// [description] and a line break, as a block string when it can be one
  /// and quoted otherwise, each line after the first indented by
  /// [indentation]; empty without a description.
  ///
  /// A member that is not first in its block ([isFirstInBlock] false)
  /// gets a blank line before its description.
  String description(
    String? description, {
    String indentation = '',
    bool isFirstInBlock = true,
  }) {
    if (description == null) {
      return '';
    }
    final text = const BlockString().isPrintable(description)
        ? const BlockString().print(description)
        : const QuotedString().print(description);
    final prefix = indentation.isNotEmpty && !isFirstInBlock
        ? '\n$indentation'
        : indentation;
    return '$prefix${text.replaceAll('\n', '\n$indentation')}\n';
  }

  /// The applied [directives], each after a space.
  String directives(List<AppliedDirective> directives) => [
    for (final directive in directives)
      ' @${directive.name}${_arguments(directive)}',
  ].join();

  String _arguments(AppliedDirective directive) => directive.arguments.isEmpty
      ? ''
      : '(${directive.arguments.map(_printer.print).join(', ')})';

  /// The fields of an object or interface type as a block.
  String fields(List<SchemaField> fields) => _block([
    for (final (index, field) in fields.indexed)
      '${description(field.description, indentation: '  ', isFirstInBlock: index == 0)}'
          '  ${field.name}${arguments(field.arguments, indentation: '  ')}: '
          '${_printer.print(field.type)}${directives(field.appliedDirectives)}',
  ]);

  /// The fields of an input object type as a block.
  String inputFields(List<InputValue> fields) => _block([
    for (final (index, field) in fields.indexed)
      '${description(field.description, indentation: '  ', isFirstInBlock: index == 0)}'
          '  ${inputValue(field)}',
  ]);

  /// The values of an enum type as a block.
  String enumValues(List<SchemaEnumValue> values) => _block([
    for (final (index, value) in values.indexed)
      '${description(value.description, indentation: '  ', isFirstInBlock: index == 0)}'
          '  ${value.name}${directives(value.appliedDirectives)}',
  ]);

  /// [arguments] in parentheses: on one line, or one per line, indented
  /// by [indentation] and two spaces, when one has a description.
  String arguments(List<InputValue> arguments, {String indentation = ''}) {
    if (arguments.isEmpty) {
      return '';
    }
    if (arguments.every((argument) => argument.description == null)) {
      return '(${arguments.map(inputValue).join(', ')})';
    }
    final lines = [
      for (final (index, argument) in arguments.indexed)
        '${description(argument.description, indentation: '  $indentation', isFirstInBlock: index == 0)}'
            '  $indentation${inputValue(argument)}',
    ];
    return '(\n${lines.join('\n')}\n$indentation)';
  }

  /// An argument or input field: `name: Type = default @directives`.
  String inputValue(InputValue value) {
    final defaultValue = switch (value.defaultValue) {
      final value? => ' = ${_printer.print(value)}',
      null => '',
    };
    return '${value.name}: ${_printer.print(value.type)}$defaultValue'
        '${directives(value.appliedDirectives)}';
  }

  String _block(List<String> items) =>
      items.isEmpty ? '' : ' {\n${items.join('\n')}\n}';
}
```

Create `packages/typed_graphql/lib/src/schema/print/type_printer.dart`:

```dart
import '../../language/ast/type_ref.dart';
import '../model/schema_directive.dart';
import '../model/schema_type.dart';
import 'member_printer.dart';

/// Prints a named type or a directive definition as graphql-js's
/// `printSchema`, with every applied directive as written.
final class const TypePrinter() {
  /// Creates a printer.
  this;

  static const MemberPrinter _members = MemberPrinter();

  /// [type] as SDL, its description first.
  String type(SchemaType type) {
    final head = '${type.name}${_members.directives(type.appliedDirectives)}';
    final definition = switch (type) {
      ScalarType() => 'scalar $head',
      ObjectType(:final interfaces, :final fields) =>
        'type ${type.name}${_interfaces(interfaces)}'
            '${_members.directives(type.appliedDirectives)}'
            '${_members.fields(fields)}',
      InterfaceType(:final interfaces, :final fields) =>
        'interface ${type.name}${_interfaces(interfaces)}'
            '${_members.directives(type.appliedDirectives)}'
            '${_members.fields(fields)}',
      UnionType(:final memberTypes) =>
        'union $head${memberTypes.isEmpty ? '' : ' = ${_names(memberTypes, ' | ')}'}',
      EnumType(:final values) => 'enum $head${_members.enumValues(values)}',
      InputObjectType(:final fields) =>
        'input $head${_members.inputFields(fields)}',
    };
    return '${_members.description(type.description)}$definition';
  }

  /// [directive] as SDL, its description first.
  String directive(SchemaDirective directive) =>
      '${_members.description(directive.description)}'
      'directive @${directive.name}${_members.arguments(directive.arguments)}'
      '${_members.directives(directive.appliedDirectives)}'
      '${directive.isRepeatable ? ' repeatable' : ''}'
      ' on ${directive.locations.join(' | ')}';

  static String _interfaces(List<NamedType> interfaces) =>
      interfaces.isEmpty ? '' : ' implements ${_names(interfaces, ' & ')}';

  static String _names(List<NamedType> types, String separator) =>
      types.map((type) => type.name.value).join(separator);
}
```

Create `packages/typed_graphql/lib/src/schema/print/schema_printer.dart`:

```dart
import '../schema.dart';
import 'type_printer.dart';

/// Prints a schema as SDL, as graphql-js's `printSchema` does (spec §5;
/// R2.5): definitions separated by a blank line, in declaration order,
/// descriptions as block strings where they can be.
///
/// Unlike graphql-js, every applied directive is printed as written, so
/// SDL to schema to SDL loses nothing.
final class const SchemaPrinter() {
  /// Creates a printer.
  this;

  static const TypePrinter _types = TypePrinter();

  /// [schema] as SDL, without a trailing line break.
  String print(Schema schema) => schema.types.map(_types.type).join('\n\n');
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -68,4 +68,5 @@ export 'src/schema/model/schema_directive.dart';
 export 'src/schema/model/schema_enum_value.dart';
 export 'src/schema/model/schema_field.dart';
 export 'src/schema/model/schema_type.dart';
+export 'src/schema/print/schema_printer.dart';
 export 'src/schema/schema.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/print/type_printing_test.dart)
```

Expected: `+8: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -98,3 +98,5 @@
   to an existing `Schema` (graphql-js's `extendSchema`), giving the schema
   back when the document has none; directive extensions (working draft)
   are applied too.
+- `SchemaPrinter`: a schema's types as SDL, laid out as graphql-js's
+  `printSchema`, with every applied directive printed as written.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -206,6 +206,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   over a base schema, without default roots; a member the base already has
   is "already exists in the schema" (no related span). `DirectiveExtender`
   applies `extend directive`.
+- `print/SchemaPrinter` (const): graphql-js's `printSchema` layout through
+  `TypePrinter` (a type or directive definition) and `MemberPrinter`
+  (descriptions, member blocks, arguments, applied directives); values and
+  types go through the language `Printer`. Unlike graphql-js it prints
+  every applied directive as written.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/print/member_printer.dart packages/typed_graphql/lib/src/schema/print/schema_printer.dart packages/typed_graphql/lib/src/schema/print/type_printer.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/print/type_printing_test.dart
git commit -q -m "feat(typed_graphql): print the types of a schema as SDL" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 13: Print the schema definition, directives and built-ins

R2.5 and spec §5: the rest of `printSchema`, and the option that includes the built-ins.

**Files:**
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/src/schema/print/schema_printer.dart`
- Test: `packages/typed_graphql/test/schema/print/schema_printing_test.dart`

**Interfaces:**
- Consumes: Task 12; Task 4: `BuiltIns`; Tasks 6–11 for the round-trip test.
- Produces:
  - `SchemaPrinter({bool includesBuiltIns = false})`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/print/schema_printing_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../built.dart';

void main() {
  /// [sdl] built and printed by [printer].
  String reprint(String sdl, {SchemaPrinter printer = const SchemaPrinter()}) =>
      printer.print(Built(sdl).schema);

  /// The first line of each definition [printed] holds, such as
  /// `directive @include` or `scalar Int`, in order.
  List<String> headsOf(String printed) => [
    for (final match in RegExp(
      r'^(directive @\w+|schema|(scalar|type|interface|union|enum|input) \w+)',
      multiLine: true,
    ).allMatches(printed))
      match[0]!,
  ];

  test('omits a schema definition that names the default roots', () {
    const sdl = 'type Query {\n  a: Int\n}\n\ntype Mutation {\n  a: Int\n}';
    expect(reprint(sdl), sdl);
  });

  test('prints a schema definition that names other roots', () {
    const sdl = '''
schema {
  query: Root
  subscription: Events
}

type Root {
  a: Int
}

type Events {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints the schema definition when a default name is not a root', () {
    const sdl = '''
schema {
  query: Query
}

type Query {
  a: Int
}

type Mutation {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints the schema definition for a description or directives', () {
    const sdl = '''
"""The API"""
schema @key {
  query: Query
}

type Query {
  a: Int
}''';
    expect(reprint(sdl), sdl);
  });

  test('prints no schema definition without roots', () {
    final schema = Schema(description: 'Lost', types: [ScalarType('A')]);
    expect(const SchemaPrinter().print(schema), 'scalar A');
  });

  test('prints directive definitions before types', () {
    const sdl = '''
"""A key"""
directive @key(fields: String!, resolvable: Boolean = true) repeatable on OBJECT | INTERFACE

directive @old @deprecated on FIELD

directive @documented(
  """The reason"""
  reason: String
) on FIELD_DEFINITION

scalar Date''';
    expect(reprint(sdl), sdl);
  });

  test('prints the built-ins around the declared definitions when asked', () {
    const printer = SchemaPrinter(includesBuiltIns: true);
    final printed = reprint('''
directive @key on OBJECT
type Root { a: Int }
schema { query: Root }''', printer: printer);
    expect(headsOf(printed), [
      'schema',
      'directive @include',
      'directive @skip',
      'directive @deprecated',
      'directive @specifiedBy',
      'directive @oneOf',
      'directive @key',
      'scalar String',
      'scalar Int',
      'scalar Float',
      'scalar Boolean',
      'scalar ID',
      'type Root',
      'type __Schema',
      'type __Type',
      'enum __TypeKind',
      'type __Field',
      'type __InputValue',
      'type __EnumValue',
      'type __Directive',
      'enum __DirectiveLocation',
    ]);
  });

  test('prints @defer and @stream when the schema includes them', () {
    const printer = SchemaPrinter(includesBuiltIns: true);
    final withDefer = Schema(includesDeferAndStream: true);
    final heads = headsOf(printer.print(withDefer));
    expect(heads.sublist(5, 7), ['directive @defer', 'directive @stream']);
    expect(
      headsOf(printer.print(Schema())),
      isNot(contains('directive @defer')),
    );
  });

  test('prints a schema that builds back to the same text', () {
    const sdl = '''
"""Root"""
schema @key {
  query: Root
}

"""Marks a key"""
directive @key(fields: String = "id") repeatable on SCHEMA | OBJECT

type Root implements Node @key(fields: "id") {
  """The id"""
  id: ID!

  """Search"""
  search(
    """Text"""
    text: String = "*"
    first: Int = 10 @deprecated
  ): [Result!] @deprecated(reason: "Use find")
}

interface Node {
  id: ID!
}

union Result @key = Root

enum Color {
  RED

  """Green"""
  GREEN @deprecated
}

input Filter @oneOf {
  color: Color = RED
  list: [Int] = [1, 2]
}

scalar Url @specifiedBy(url: "https://url.spec.whatwg.org")''';
    final once = reprint(sdl);
    expect(once, sdl);
    expect(reprint(once), once);
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/print/schema_printing_test.dart)
```

Expected: FAIL. `Error: No named parameter with the name 'includesBuiltIns'.`

- [ ] **Step 3: Write the implementation**

The schema definition is printed only when it says more than the default root names: a root with another name, a type named `Query`, `Mutation` or `Subscription` that is not that root (graphql-js's `isSchemaOfCommonNames`), a description, or directives (which graphql-js does not print). Without roots there is none, since SDL cannot write one. Directive definitions come before types. `includesBuiltIns: true` prints the built-in directives and scalars before the declared ones and the introspection types after them.

In `packages/typed_graphql/lib/src/schema/print/schema_printer.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,18 +1,78 @@
+import '../../language/ast/operation_type.dart';
+import '../build/built_ins.dart';
 import '../schema.dart';
+import 'member_printer.dart';
 import 'type_printer.dart';
 
 /// Prints a schema as SDL, as graphql-js's `printSchema` does (spec §5;
-/// R2.5): definitions separated by a blank line, in declaration order,
-/// descriptions as block strings where they can be.
+/// R2.5): the schema definition when it says more than the default root
+/// names, then the directive definitions and the types, in declaration
+/// order, separated by a blank line.
 ///
 /// Unlike graphql-js, every applied directive is printed as written, so
-/// SDL to schema to SDL loses nothing.
-final class const SchemaPrinter() {
+/// SDL to schema to SDL loses nothing but a schema description or
+/// directives without root types, which SDL cannot hold.
+final class const SchemaPrinter({
+  /// Whether the built-in directives, scalars and introspection types
+  /// are printed too, around the declared ones; `@defer` and `@stream`
+  /// only when the schema includes them.
+  final bool includesBuiltIns = false,
+}) {
   /// Creates a printer.
   this;
 
   static const TypePrinter _types = TypePrinter();
 
   /// [schema] as SDL, without a trailing line break.
-  String print(Schema schema) => schema.types.map(_types.type).join('\n\n');
+  String print(Schema schema) {
+    const builtIns = BuiltIns();
+    return [
+      ?_schemaDefinition(schema),
+      if (includesBuiltIns)
+        ...[
+          ...builtIns.directives,
+          if (schema.includesDeferAndStream) ...[
+            builtIns.defer,
+            builtIns.stream,
+          ],
+        ].map(_types.directive),
+      ...schema.directives.map(_types.directive),
+      if (includesBuiltIns) ...builtIns.scalars.map(_types.type),
+      ...schema.types.map(_types.type),
+      if (includesBuiltIns) ...builtIns.introspectionTypes.map(_types.type),
+    ].join('\n\n');
+  }
+
+  String? _schemaDefinition(Schema schema) {
+    final roots = [
+      for (final operation in OperationType.values)
+        if (schema.rootTypeName(operation) case final name?)
+          '  ${operation.name}: $name\n',
+    ];
+    final isPlain =
+        schema.description == null &&
+        schema.appliedDirectives.isEmpty &&
+        _hasDefaultRoots(schema);
+    if (roots.isEmpty || isPlain) {
+      return null;
+    }
+    const members = MemberPrinter();
+    return '${members.description(schema.description)}'
+        'schema${members.directives(schema.appliedDirectives)} '
+        '{\n${roots.join()}}';
+  }
+
+  /// Whether each root is the type named after its operation, and each
+  /// type named after an operation is its root, as graphql-js checks.
+  static bool _hasDefaultRoots(Schema schema) => OperationType.values.every((
+    operation,
+  ) {
+    final defaultName = switch (operation) {
+      .query => 'Query',
+      .mutation => 'Mutation',
+      .subscription => 'Subscription',
+    };
+    final named = schema.typeNamed(defaultName) == null ? null : defaultName;
+    return schema.rootTypeName(operation) == named;
+  });
 }
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/print/schema_printing_test.dart)
```

Expected: `+9: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -100,3 +100,6 @@
   are applied too.
 - `SchemaPrinter`: a schema's types as SDL, laid out as graphql-js's
   `printSchema`, with every applied directive printed as written.
+- `SchemaPrinter` prints the schema definition when it says more than the
+  default root names, and the directive definitions; `includesBuiltIns`
+  adds the built-in directives, scalars and introspection types.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -210,7 +210,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   `TypePrinter` (a type or directive definition) and `MemberPrinter`
   (descriptions, member blocks, arguments, applied directives); values and
   types go through the language `Printer`. Unlike graphql-js it prints
-  every applied directive as written.
+  every applied directive as written. The schema definition is printed when
+  it has roots and a description, directives or other than the default root
+  names; `includesBuiltIns` prints schema definition, built-in directives,
+  own directives, built-in scalars, own types, introspection types.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/print/schema_printer.dart packages/typed_graphql/test/schema/print/schema_printing_test.dart
git commit -q -m "feat(typed_graphql): print the schema definition, directives and built-ins" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 14: Scalar codecs and the built-in ones

R2.9, R2.6 and spec §6: `ScalarCodec<T>` with exact boundaries.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/float_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/id_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/int_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/scalar_codec.dart`, `packages/typed_graphql/lib/src/schema/scalars/string_codec.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/scalars/built_in_codecs_test.dart`

**Interfaces:**
- Consumes: M1: `JsonValue` and its family, `DecodeResult`, `DecodeSuccess`, `DecodeFailure`.
- Produces:
  - `abstract interface class ScalarCodec<T>` with `DecodeResult<T> decode(JsonValue json)` and `JsonValue encode(T value)`;
  - `IntCodec` (`ScalarCodec<int>`, `static const int min`, `max`), `FloatCodec` (`<double>`), `StringCodec` (`<String>`), `BooleanCodec` (`<bool>`), `IdCodec` (`<String>`), each `const`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/scalars/built_in_codecs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  group('IntCodec', () {
    const codec = IntCodec();

    test('decodes the bounds of a signed 32-bit integer', () {
      expect(
        codec.decode(JsonNumber(2147483647)),
        const DecodeSuccess<int>(2147483647),
      );
      expect(
        codec.decode(JsonNumber(-2147483648)),
        const DecodeSuccess<int>(-2147483648),
      );
    });

    test('decodes a whole float as an integer', () {
      expect(codec.decode(JsonNumber(3.0)), const DecodeSuccess<int>(3));
    });

    test('rejects a number past the bounds', () {
      expect(
        codec.decode(JsonNumber(2147483648)),
        const DecodeFailure(
          'Int cannot represent non 32-bit signed integer value: 2147483648',
        ),
      );
      expect(codec.decode(JsonNumber(-2147483649)), isA<DecodeFailure>());
      expect(codec.decode(JsonNumber(1e100)), isA<DecodeFailure>());
    });

    test('rejects a fraction, a string, a boolean and null', () {
      expect(
        codec.decode(JsonNumber(1.5)),
        const DecodeFailure('Int cannot represent non-integer value: 1.5'),
      );
      expect(
        codec.decode(const JsonString('1')),
        const DecodeFailure('Int cannot represent non-integer value: "1"'),
      );
      expect(codec.decode(const JsonBool(true)), isA<DecodeFailure>());
      expect(codec.decode(const JsonNull()), isA<DecodeFailure>());
    });

    test('encodes an integer as a number', () {
      expect(codec.encode(42), JsonNumber(42));
    });

    test('refuses to encode an integer past the bounds', () {
      expect(() => codec.encode(2147483648), throwsArgumentError);
    });
  });

  group('FloatCodec', () {
    const codec = FloatCodec();

    test('decodes any finite number as a double', () {
      expect(codec.decode(JsonNumber(1.5)), const DecodeSuccess<double>(1.5));
      final whole = codec.decode(JsonNumber(2));
      expect(whole, const DecodeSuccess<double>(2));
      expect((whole as DecodeSuccess<double>).value, isA<double>());
    });

    test('rejects a string and a boolean', () {
      expect(
        codec.decode(const JsonString('1.5')),
        const DecodeFailure('Float cannot represent non numeric value: "1.5"'),
      );
      expect(codec.decode(const JsonBool(false)), isA<DecodeFailure>());
    });

    test('encodes a double as a number', () {
      expect(codec.encode(0.25), JsonNumber(0.25));
    });

    test('refuses to encode NaN and the infinities', () {
      expect(() => codec.encode(double.nan), throwsArgumentError);
      expect(() => codec.encode(double.infinity), throwsArgumentError);
    });
  });

  group('StringCodec', () {
    const codec = StringCodec();

    test('decodes a string and encodes it back', () {
      expect(
        codec.decode(const JsonString('abc')),
        const DecodeSuccess<String>('abc'),
      );
      expect(codec.encode('abc'), const JsonString('abc'));
    });

    test('rejects a number', () {
      expect(
        codec.decode(JsonNumber(1)),
        const DecodeFailure('String cannot represent a non string value: 1'),
      );
    });
  });

  group('BooleanCodec', () {
    const codec = BooleanCodec();

    test('decodes a boolean and encodes it back', () {
      expect(
        codec.decode(const JsonBool(true)),
        const DecodeSuccess<bool>(true),
      );
      expect(codec.encode(false), const JsonBool(false));
    });

    test('rejects a number', () {
      expect(
        codec.decode(JsonNumber(0)),
        const DecodeFailure('Boolean cannot represent a non boolean value: 0'),
      );
    });
  });

  group('IdCodec', () {
    const codec = IdCodec();

    test('decodes a string and an integer as a string', () {
      expect(
        codec.decode(const JsonString('a1')),
        const DecodeSuccess<String>('a1'),
      );
      expect(codec.decode(JsonNumber(12)), const DecodeSuccess<String>('12'));
    });

    test('rejects a fraction and a boolean', () {
      expect(
        codec.decode(JsonNumber(1.5)),
        const DecodeFailure('ID cannot represent value: 1.5'),
      );
      expect(codec.decode(const JsonBool(true)), isA<DecodeFailure>());
    });

    test('rejects an integer past 2^53 - 1, which the web cannot hold', () {
      expect(
        codec.decode(JsonNumber(9007199254740991)),
        const DecodeSuccess<String>('9007199254740991'),
      );
      expect(codec.decode(JsonNumber(9007199254740992)), isA<DecodeFailure>());
    });

    test('encodes a string', () {
      expect(codec.encode('12'), const JsonString('12'));
    });
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/scalars/built_in_codecs_test.dart)
```

Expected: FAIL. `Error: Method not found: 'IntCodec'.`, and the same for `FloatCodec`, `StringCodec`, `BooleanCodec` and `IdCodec`.

- [ ] **Step 3: Write the implementation**

Spec §6 and R2.6: `Int` is a signed 32-bit integer (a whole float such as `3.0` decodes, as on the web), `Float` any finite number, `ID` a string or a safe integer as its decimal text. `decode` never throws: a value the type cannot hold is a `DecodeFailure` that says why (graphql-js's message for `Int`). `encode` of a value the type cannot hold (an `int` past 32 bits, NaN) can only come from code, so it is an `ArgumentError` (decision 8).

Create `packages/typed_graphql/lib/src/schema/scalars/scalar_codec.dart`:

```dart
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';

/// Reads and writes the values of one scalar type (spec §3.5; R2.9).
///
/// [decode] takes input, a variable or a literal converted to JSON, and
/// gives a [DecodeFailure] for a value the type cannot represent; it never
/// throws. [encode] writes a result value. A codec is registered by scalar
/// name with the server or the client, not held by `ScalarType`: the
/// schema model has no behaviour.
abstract interface class ScalarCodec<T> {
  /// The value [json] stands for, or a failure that says why it cannot.
  DecodeResult<T> decode(JsonValue json);

  /// [value] as JSON. A value the type cannot represent, which only code
  /// can produce, is an [ArgumentError].
  JsonValue encode(T value);
}
```

Create `packages/typed_graphql/lib/src/schema/scalars/int_codec.dart`:

```dart
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `Int`: a signed 32-bit integer (spec §3.5.1).
///
/// A whole float such as `3.0` decodes, as on the web; a fraction, a
/// number past the bounds and anything but a number do not. The messages
/// are graphql-js's.
final class const IntCodec() implements ScalarCodec<int> {
  /// Creates the codec.
  this;

  /// The smallest `Int`: -2^31.
  static const int min = -2147483648;

  /// The largest `Int`: 2^31 - 1.
  static const int max = 2147483647;

  @override
  DecodeResult<int> decode(JsonValue json) => switch (json) {
    JsonNumber(:final value) when value % 1 != 0 => DecodeFailure(
      'Int cannot represent non-integer value: $json',
    ),
    JsonNumber(:final value) when value < min || value > max => DecodeFailure(
      'Int cannot represent non 32-bit signed integer value: $json',
    ),
    JsonNumber(:final value) => DecodeSuccess(value.toInt()),
    _ => DecodeFailure('Int cannot represent non-integer value: $json'),
  };

  @override
  JsonValue encode(int value) {
    if (value < min || value > max) {
      throw ArgumentError.value(value, 'value', 'is not a 32-bit integer');
    }
    return JsonNumber(value);
  }
}
```

Create `packages/typed_graphql/lib/src/schema/scalars/float_codec.dart`:

```dart
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `Float`: a finite double (spec §3.5.2). Any JSON number
/// decodes, as JSON has no NaN or infinity.
final class const FloatCodec() implements ScalarCodec<double> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<double> decode(JsonValue json) => switch (json) {
    JsonNumber(:final value) => DecodeSuccess(value.toDouble()),
    _ => DecodeFailure('Float cannot represent non numeric value: $json'),
  };

  @override
  JsonValue encode(double value) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'is not a finite number');
    }
    return JsonNumber(value);
  }
}
```

Create `packages/typed_graphql/lib/src/schema/scalars/string_codec.dart`:

```dart
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `String`: Unicode text (spec §3.5.3).
final class const StringCodec() implements ScalarCodec<String> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => DecodeFailure('String cannot represent a non string value: $json'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}
```

Create `packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart`:

```dart
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `Boolean`: `true` or `false` (spec §3.5.4).
final class const BooleanCodec() implements ScalarCodec<bool> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<bool> decode(JsonValue json) => switch (json) {
    JsonBool(:final value) => DecodeSuccess(value),
    _ => DecodeFailure('Boolean cannot represent a non boolean value: $json'),
  };

  @override
  JsonValue encode(bool value) => JsonBool(value);
}
```

Create `packages/typed_graphql/lib/src/schema/scalars/id_codec.dart`:

```dart
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import 'scalar_codec.dart';

/// The built-in `ID`: a unique identifier, serialized as a string (spec
/// §3.5.5). A string or an integer decodes, the integer as its decimal
/// text; integers past 2^53 - 1 do not, as the web cannot hold them.
final class const IdCodec() implements ScalarCodec<String> {
  /// Creates the codec.
  this;

  @override
  DecodeResult<String> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => DecodeSuccess(value),
    JsonNumber(:final asInt?) => DecodeSuccess('$asInt'),
    _ => DecodeFailure('ID cannot represent value: $json'),
  };

  @override
  JsonValue encode(String value) => JsonString(value);
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -69,4 +69,10 @@ export 'src/schema/model/schema_enum_value.dart';
 export 'src/schema/model/schema_field.dart';
 export 'src/schema/model/schema_type.dart';
 export 'src/schema/print/schema_printer.dart';
+export 'src/schema/scalars/boolean_codec.dart';
+export 'src/schema/scalars/float_codec.dart';
+export 'src/schema/scalars/id_codec.dart';
+export 'src/schema/scalars/int_codec.dart';
+export 'src/schema/scalars/scalar_codec.dart';
+export 'src/schema/scalars/string_codec.dart';
 export 'src/schema/schema.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/scalars/built_in_codecs_test.dart)
```

Expected: `+18: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -103,3 +103,6 @@
 - `SchemaPrinter` prints the schema definition when it says more than the
   default root names, and the directive definitions; `includesBuiltIns`
   adds the built-in directives, scalars and introspection types.
+- `ScalarCodec<T>` (`decode` to a `DecodeResult`, `encode` to a
+  `JsonValue`) and the built-in codecs `IntCodec` (signed 32-bit),
+  `FloatCodec` (finite), `StringCodec`, `BooleanCodec` and `IdCodec`.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -214,6 +214,10 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
   it has roots and a description, directives or other than the default root
   names; `includesBuiltIns` prints schema definition, built-in directives,
   own directives, built-in scalars, own types, introspection types.
+- `scalars/`: `ScalarCodec<T>` (`decode(JsonValue)` → `DecodeResult<T>`,
+  never throws; `encode(T)` → `JsonValue`, an `ArgumentError` for a value the
+  type cannot hold) and the five built-in codecs with graphql-js's messages.
+  A codec is not a field of `ScalarType` (R2.9).
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/scalars/boolean_codec.dart packages/typed_graphql/lib/src/schema/scalars/float_codec.dart packages/typed_graphql/lib/src/schema/scalars/id_codec.dart packages/typed_graphql/lib/src/schema/scalars/int_codec.dart packages/typed_graphql/lib/src/schema/scalars/scalar_codec.dart packages/typed_graphql/lib/src/schema/scalars/string_codec.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/scalars/built_in_codecs_test.dart
git commit -q -m "feat(typed_graphql): add scalar codecs and the built-in ones" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 15: The codec registry and literal conversion

R2.9 and spec §6: codecs by scalar name, and literals through JSON.

**Files:**
- Create: `packages/typed_graphql/lib/src/schema/scalars/literal_converter.dart`, `packages/typed_graphql/lib/src/schema/scalars/scalar_codecs.dart`
- Modify: `CLAUDE.md`, `packages/typed_graphql/CHANGELOG.md`, `packages/typed_graphql/lib/typed_graphql.dart`
- Test: `packages/typed_graphql/test/schema/scalars/literal_converter_test.dart`, `packages/typed_graphql/test/schema/scalars/scalar_codecs_test.dart`

**Interfaces:**
- Consumes: Task 14; M2a: the `Value` family; M1: `PathKey`, `PathIndex`, `DecodeFailure.inside`.
- Produces:
  - `final class const LiteralConverter()` with `DecodeResult<JsonValue> convert(Value value)`;
  - `final class ScalarCodecs` with `ScalarCodecs()` (the five built-ins), `ScalarCodecs withCodec(String name, ScalarCodec<Object> codec)` and `ScalarCodec<Object>? codecFor(String name)`.

- [ ] **Step 1: Write the failing tests**

Create `packages/typed_graphql/test/schema/scalars/literal_converter_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const converter = LiteralConverter();

  /// The JSON of the literal [text].
  DecodeResult<JsonValue> convert(String text) =>
      converter.convert(switch (const Parser().parseValue(Source(text))) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      });

  test('converts each kind of constant', () {
    expect(convert('12'), DecodeSuccess<JsonValue>(JsonNumber(12)));
    expect(convert('1.5e1'), DecodeSuccess<JsonValue>(JsonNumber(15)));
    expect(convert('"s"'), const DecodeSuccess<JsonValue>(JsonString('s')));
    expect(convert('true'), const DecodeSuccess<JsonValue>(JsonBool(true)));
    expect(convert('null'), const DecodeSuccess<JsonValue>(JsonNull()));
    expect(convert('RED'), const DecodeSuccess<JsonValue>(JsonString('RED')));
  });

  test('converts lists and objects, the last of two fields winning', () {
    expect(
      convert('{a: [1, "x"], b: {c: null}, a: 2}'),
      DecodeSuccess<JsonValue>(
        JsonObject({
          'a': JsonNumber(2),
          'b': JsonObject({'c': const JsonNull()}),
        }),
      ),
    );
  });

  test('reads an integer too large for an int as a number', () {
    expect(
      convert('123456789012345678901234567890'),
      DecodeSuccess<JsonValue>(JsonNumber(1.2345678901234568e29)),
    );
  });

  test('rejects a number too large to be finite, with its path', () {
    expect(
      convert('{a: [1, 1e400]}'),
      const DecodeFailure(
        'The number 1e400 is too large.',
        path: [PathKey('a'), PathIndex(1)],
      ),
    );
  });

  test('rejects a variable', () {
    expect(
      converter.convert(const Variable(Name('v'))),
      const DecodeFailure(r'The variable "$v" has no value here.'),
    );
  });

  test('rejects a number node whose text is not a number', () {
    expect(converter.convert(const IntValue('x')), isA<DecodeFailure>());
  });
}
```

Create `packages/typed_graphql/test/schema/scalars/scalar_codecs_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// A custom scalar for the tests: a date as `yyyy-mm-dd` text.
final class _DateCodec implements ScalarCodec<DateTime> {
  const _DateCodec();

  @override
  DecodeResult<DateTime> decode(JsonValue json) => switch (json) {
    JsonString(:final value) => switch (DateTime.tryParse(value)) {
      final date? => DecodeSuccess(date),
      null => DecodeFailure('not a date: $value'),
    },
    _ => DecodeFailure('not a date: $json'),
  };

  @override
  JsonValue encode(DateTime value) =>
      JsonString(value.toIso8601String().substring(0, 10));
}

void main() {
  test('holds the five built-in codecs by name', () {
    final codecs = ScalarCodecs();
    expect(codecs.codecFor('Int'), isA<IntCodec>());
    expect(codecs.codecFor('Float'), isA<FloatCodec>());
    expect(codecs.codecFor('String'), isA<StringCodec>());
    expect(codecs.codecFor('Boolean'), isA<BooleanCodec>());
    expect(codecs.codecFor('ID'), isA<IdCodec>());
    expect(codecs.codecFor('Date'), isNull);
  });

  test('adds a codec for a custom scalar in a new registry', () {
    final codecs = ScalarCodecs();
    final withDate = codecs.withCodec('Date', const _DateCodec());
    expect(withDate.codecFor('Date'), isA<_DateCodec>());
    expect(withDate.codecFor('Int'), isA<IntCodec>());
    expect(codecs.codecFor('Date'), isNull);
  });

  test('decodes through a registered codec', () {
    final codec = ScalarCodecs()
        .withCodec('Date', const _DateCodec())
        .codecFor('Date');
    expect(
      codec?.decode(const JsonString('2026-10-14')),
      DecodeSuccess<DateTime>(DateTime(2026, 10, 14)),
    );
  });

  test('refuses to replace a built-in codec', () {
    expect(
      () => ScalarCodecs().withCodec('Int', const StringCodec()),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/scalars/literal_converter_test.dart test/schema/scalars/scalar_codecs_test.dart)
```

Expected: FAIL. `Error: Method not found: 'LiteralConverter'.` and `Error: Method not found: 'ScalarCodecs'.`

- [ ] **Step 3: Write the implementation**

Spec §6: a literal is converted to JSON first, so a codec has no `parseLiteral`. An enum value becomes its name and, of two object fields with one name, the last wins (graphql-js's `valueFromASTUntyped`). A variable, or a number whose text does not give a finite double, is a `DecodeFailure` with its path. `ScalarCodecs` is an immutable registry by scalar name; replacing a built-in codec is an `ArgumentError`. Its map is used for lookups only, never iterated.

Create `packages/typed_graphql/lib/src/schema/scalars/literal_converter.dart`:

```dart
import '../../language/ast/object_field.dart';
import '../../language/ast/value.dart';
import '../../protocol/decode_result.dart';
import '../../protocol/json_value.dart';
import '../../protocol/path_segment.dart';
import 'scalar_codec.dart';

/// Converts a constant literal to the JSON a [ScalarCodec] decodes, so a
/// codec needs no `parseLiteral` (spec §6).
///
/// An enum value becomes its name, as graphql-js's
/// `valueFromASTUntyped`; of two object fields with one name the last
/// wins (validation reports the repeat). A variable and a number too large
/// to be finite are failures, with the path to them.
final class const LiteralConverter() {
  /// Creates a converter.
  this;

  /// [value] as JSON, or a failure.
  DecodeResult<JsonValue> convert(Value value) => switch (value) {
    IntValue(value: final text) || FloatValue(value: final text) => _number(
      text,
    ),
    StringValue(value: final text) => DecodeSuccess(JsonString(text)),
    BooleanValue(value: final flag) => DecodeSuccess(JsonBool(flag)),
    NullValue() => const DecodeSuccess(JsonNull()),
    EnumValue(value: final name) => DecodeSuccess(JsonString(name)),
    ListValue(:final values) => _list(values),
    ObjectValue(:final fields) => _object(fields),
    Variable(:final name) => DecodeFailure(
      'The variable "\$${name.value}" has no value here.',
    ),
  };

  DecodeResult<JsonValue> _number(String text) => switch (num.tryParse(text)) {
    final number? when number.isFinite => DecodeSuccess(JsonNumber(number)),
    final _? => DecodeFailure('The number $text is too large.'),
    null => DecodeFailure('"$text" is not a number.'),
  };

  DecodeResult<JsonValue> _list(List<Value> values) {
    final items = <JsonValue>[];
    for (final (index, value) in values.indexed) {
      switch (convert(value).inside(PathIndex(index))) {
        case DecodeSuccess(value: final item):
          items.add(item);
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonArray(items));
  }

  DecodeResult<JsonValue> _object(List<ObjectField> fields) {
    final converted = <String, JsonValue>{};
    for (final field in fields) {
      final name = field.name.value;
      switch (convert(field.value).inside(PathKey(name))) {
        case DecodeSuccess(:final value):
          converted[name] = value;
        case final DecodeFailure failure:
          return failure;
      }
    }
    return DecodeSuccess(JsonObject(converted));
  }
}
```

Create `packages/typed_graphql/lib/src/schema/scalars/scalar_codecs.dart`:

```dart
import 'boolean_codec.dart';
import 'float_codec.dart';
import 'id_codec.dart';
import 'int_codec.dart';
import 'scalar_codec.dart';
import 'string_codec.dart';

/// The codecs of the scalar types by name (R2.9): the five built-in ones
/// and those a server or a client adds for its custom scalars.
///
/// A registry is immutable: [withCodec] gives a new one.
final class ScalarCodecs {
  /// A registry of the five built-in codecs.
  ScalarCodecs() : _codecs = _builtIns;

  ScalarCodecs._(this._codecs);

  static const Map<String, ScalarCodec<Object>> _builtIns = {
    'Int': IntCodec(),
    'Float': FloatCodec(),
    'String': StringCodec(),
    'Boolean': BooleanCodec(),
    'ID': IdCodec(),
  };

  // Only for lookups, never iterated.
  final Map<String, ScalarCodec<Object>> _codecs;

  /// This registry with [codec] for the scalar named [name], replacing the
  /// codec it had. A built-in codec cannot be replaced: an
  /// [ArgumentError].
  ScalarCodecs withCodec(String name, ScalarCodec<Object> codec) {
    if (_builtIns.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'is a built-in scalar');
    }
    return ScalarCodecs._({..._codecs, name: codec});
  }

  /// The codec of the scalar named [name]; null when there is none.
  ScalarCodec<Object>? codecFor(String name) => _codecs[name];
}
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -73,6 +73,8 @@ export 'src/schema/scalars/boolean_codec.dart';
 export 'src/schema/scalars/float_codec.dart';
 export 'src/schema/scalars/id_codec.dart';
 export 'src/schema/scalars/int_codec.dart';
+export 'src/schema/scalars/literal_converter.dart';
 export 'src/schema/scalars/scalar_codec.dart';
+export 'src/schema/scalars/scalar_codecs.dart';
 export 'src/schema/scalars/string_codec.dart';
 export 'src/schema/schema.dart';
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql && dart test test/schema/scalars/literal_converter_test.dart test/schema/scalars/scalar_codecs_test.dart)
```

Expected: `literal_converter_test.dart` `+6`, `scalar_codecs_test.dart` `+4`, each `All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -106,3 +106,6 @@
 - `ScalarCodec<T>` (`decode` to a `DecodeResult`, `encode` to a
   `JsonValue`) and the built-in codecs `IntCodec` (signed 32-bit),
   `FloatCodec` (finite), `StringCodec`, `BooleanCodec` and `IdCodec`.
+- `ScalarCodecs`: an immutable registry of codecs by scalar name, with the
+  built-in ones; `LiteralConverter`: a constant literal to the `JsonValue`
+  a codec decodes.
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -217,7 +217,11 @@ no platform library but `dart:async`, `dart:collection`, `dart:convert`,
 - `scalars/`: `ScalarCodec<T>` (`decode(JsonValue)` → `DecodeResult<T>`,
   never throws; `encode(T)` → `JsonValue`, an `ArgumentError` for a value the
   type cannot hold) and the five built-in codecs with graphql-js's messages.
-  A codec is not a field of `ScalarType` (R2.9).
+  A codec is not a field of `ScalarType` (R2.9): `ScalarCodecs` maps names to
+  codecs (`withCodec` gives a new registry; built-ins cannot be replaced).
+  `LiteralConverter` turns a constant `Value` into the `JsonValue` a codec
+  decodes (an enum value becomes its name), so codecs have no
+  `parseLiteral`.
 
 **Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
 `DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add CLAUDE.md packages/typed_graphql/CHANGELOG.md packages/typed_graphql/lib/src/schema/scalars/literal_converter.dart packages/typed_graphql/lib/src/schema/scalars/scalar_codecs.dart packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql/test/schema/scalars/literal_converter_test.dart packages/typed_graphql/test/schema/scalars/scalar_codecs_test.dart
git commit -q -m "feat(typed_graphql): add the codec registry and literal conversion" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 16: Port the graphql-js schema printer suite

**How a graphql-js test is ported.** This applies to Tasks 16, 17 and 18. It is M2's procedure, with a second table.

1. **Source.** `reference/graphql-js/src/utilities/__tests__/<file>`: graphql-js 17.0.2, commit `ee5ce41`, fetched by `tool/fetch_reference.sh`. Every `it` of the file gets a row, in file order.
2. **Names.** A Dart file starts with `// Ported from graphql-js src/utilities/__tests__/<file>; see` and `// mapping/schema.csv.` Each `describe` becomes a `group` and each `it` a `test` with the same name, in one string literal (the table check searches the file for `group('<segment>'` and `test('<name>'`).
3. **Status.** `ported`: the expectation is transcribed unchanged. `adapted`: a deliberate design difference changes it; the Dart test has a `// Adapted: <why>` comment and the row gives the reason. `skipped`: no Dart test, `dart_file` is empty, and the row gives the reason.
4. **Rows.** `mapping/schema.csv` has the columns of `language.csv`: `graphql_js_file,group,test,status,dart_file,reason`. `graphql_js_file` is relative to graphql-js's `src/` (`utilities/__tests__/printSchema-test.ts`), since the M3 suites come from more than one folder. A field that holds a comma or a quote is quoted, and a quote inside it is doubled. The rows in the tasks are final.
5. **A failing ported expectation is a porting mistake first.** Every file was ported against this library while the plan was verified, and every expectation passed. Never weaken one; if the library really differs, stop and report it.
6. **Code rules.** Test code follows them too: no top-level function but `main`, at most 500 lines per file (so a large graphql-js file is split by `describe`), full names (not dot shorthands) in `expect` arguments, a `switch` instead of `as` or `!`.

The coverage check (`rows cover every test of <file>`) runs only where `reference/` is fetched, which CI does not do: run it locally.

**Files:**
- Create: `packages/typed_graphql_conformance/mapping/schema.csv`
- Modify: `CLAUDE.md`, `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`
- Test: `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/print_introspection_schema_test.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_test.dart`, `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart`, `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`, `packages/typed_graphql_conformance/test/support/schema_port.dart`, `packages/typed_graphql_conformance/test/support_test.dart`

**Interfaces:**
- Consumes: Tasks 1–15 (the whole public schema API); M2's `GraphqlJsSuite`, `CsvTable`, `mapping_test.dart`.
- Produces:
  - `GraphqlJsSuite.read(String path)` takes a path relative to graphql-js's `src/`; `static List<String> GraphqlJsSuite.filesIn(String directory)` (empty when the folder is missing); `sourceDirectory` is `../../reference/graphql-js/src`;
  - `mapping_test.dart` checks a list of tables `(path, prefix, covered)`;
  - test helper `const SchemaPort()` in `test/support/schema_port.dart`: `type`, `named`, `value`, `applied`, `build`, `print`, `printed`, `cycle`, `singleField(String type, {List<InputValue> arguments = const [], String? description})`, `input(String name, String type, {String? defaultValue})`;
  - `mapping/schema.csv` with 39 rows for `printSchema-test.ts`.

- [ ] **Step 1: Write the failing tests for the port helpers**

`GraphqlJsSuite` reads any graphql-js test folder now, not only the language one, and the new `SchemaPort` gets two tests of its own.

In `packages/typed_graphql_conformance/test/support_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -1,7 +1,9 @@
 import 'package:test/test.dart';
+import 'package:typed_graphql/typed_graphql.dart';
 
 import 'support/csv_table.dart';
 import 'support/graphql_js_suite.dart';
+import 'support/schema_port.dart';
 
 void main() {
   group('CsvTable', () {
@@ -46,5 +48,26 @@ describe('isPunctuatorTokenKind', () => {
         ('isPunctuatorTokenKind', 'returns true'),
       ]);
     });
+
+    test('finds no files in a folder that does not exist', () {
+      expect(GraphqlJsSuite.filesIn('no/such/__tests__'), isEmpty);
+    });
+  });
+
+  group('SchemaPort', () {
+    const port = SchemaPort();
+
+    test('reads applied directives with their arguments', () {
+      final [directive] = port.applied('@deprecated(reason: "old")');
+      expect(directive.name, 'deprecated');
+      expect(directive.argument('reason'), isA<StringValue>());
+    });
+
+    test('prints a schema it can build back', () {
+      expect(port.printed(port.singleField('[Int!]')), '''
+type Query {
+  singleField: [Int!]
+}''');
+    });
   });
 }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/support_test.dart)
```

Expected: FAIL. `Error: Member not found: 'GraphqlJsSuite.filesIn'.`, `Error: Method not found: 'SchemaPort'.` and `Error: Error when reading 'test/support/schema_port.dart': No such file or directory`.

- [ ] **Step 3: Write the port helpers**

`SchemaPort` holds graphql-js's schema test helpers: `buildSchema` (`build`), `printSchema` (`print`), `expectPrintedSchema` (`printed`, which also checks that the text builds back to the same text), and the small schemas the printer tests start from (`singleField`, `input`).

In `packages/typed_graphql_conformance/test/support/graphql_js_suite.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -4,9 +4,10 @@ import 'dart:io';
 /// `tool/fetch_reference.sh`, absent in CI): each `it` with the path of
 /// the `describe` blocks around it, joined by ` > `.
 final class GraphqlJsSuite {
-  /// Reads `src/language/__tests__/[file]` of the fetched graphql-js.
-  factory GraphqlJsSuite.read(String file) =>
-      GraphqlJsSuite.parse(File('$directory/$file').readAsStringSync());
+  /// Reads `src/[path]` of the fetched graphql-js, such as
+  /// `utilities/__tests__/printSchema-test.ts`.
+  factory GraphqlJsSuite.read(String path) =>
+      GraphqlJsSuite.parse(File('$sourceDirectory/$path').readAsStringSync());
 
   /// Finds the tests in [source], a graphql-js test file formatted by
   /// Prettier: a block's indentation says which `describe` holds it.
@@ -33,21 +34,21 @@ final class GraphqlJsSuite {
 
   GraphqlJsSuite._(this.tests);
 
-  /// The language tests of graphql-js, relative to a package directory.
-  static const String directory =
-      '../../reference/graphql-js/src/language/__tests__';
+  /// The sources of graphql-js, relative to a package directory.
+  static const String sourceDirectory = '../../reference/graphql-js/src';
 
   /// Whether graphql-js was fetched into `reference/`.
-  static bool get isAvailable => Directory(directory).existsSync();
+  static bool get isAvailable => Directory(sourceDirectory).existsSync();
 
-  /// The names of the test files in [directory], sorted; empty when
-  /// graphql-js was not fetched.
-  static List<String> get files {
-    if (!isAvailable) {
+  /// The names of the test files in `src/[directory]`, such as
+  /// `language/__tests__`, sorted; empty when graphql-js was not fetched.
+  static List<String> filesIn(String directory) {
+    final folder = Directory('$sourceDirectory/$directory');
+    if (!folder.existsSync()) {
       return const [];
     }
     return [
-      for (final entity in Directory(directory).listSync())
+      for (final entity in folder.listSync())
         if (entity is File && entity.path.endsWith('.ts'))
           entity.uri.pathSegments.last,
     ]..sort();
```

Create `packages/typed_graphql_conformance/test/support/schema_port.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// graphql-js's schema test helpers (`buildSchema`, `printSchema`,
/// `expectPrintedSchema`, `cycleSDL`, `buildSingleFieldSchema`) and the
/// parts a ported test builds a schema from: type references, constant
/// values and applied directives written as GraphQL text.
final class SchemaPort {
  /// Creates the helpers; they keep no state.
  const SchemaPort();

  static const Parser _parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );

  /// [text] as a type reference, such as `[String!]`.
  TypeRef type(String text) => _element(_parser.parseTypeRef(Source(text)));

  /// A reference to the type named [name], as an interface or a union
  /// member.
  NamedType named(String name) => NamedType(Name(name));

  /// [text] as a constant value, such as `{ a: 1 }`.
  Value value(String text) =>
      _element(_parser.parseValue(Source(text), isConst: true));

  /// The directives applied in [text], such as `@deprecated(reason: "x")`.
  List<AppliedDirective> applied(String text) {
    final directives = switch (_document('scalar Applied $text').definitions) {
      [ScalarTypeDefinition(:final directives)] => directives,
      _ => fail('Not directives: $text'),
    };
    return [
      for (final directive in directives)
        AppliedDirective(
          directive.name.value,
          arguments: directive.arguments,
        ),
    ];
  }

  /// graphql-js's `buildSchema`: [sdl] built; fails the test on a
  /// diagnostic.
  Schema build(String sdl) =>
      switch (const SchemaBuilder().fromSdl(_document(sdl))) {
        BuildSuccess(:final schema) => schema,
        BuildFailure(:final diagnostics) => fail('$diagnostics'),
      };

  /// graphql-js's `printSchema`.
  String print(Schema schema) => const SchemaPrinter().print(schema);

  /// graphql-js's `expectPrintedSchema`: [schema] printed, after checking
  /// that building and printing the text gives it back.
  String printed(Schema schema) {
    final text = print(schema);
    expect(print(build(text)), text);
    return text;
  }

  /// graphql-js's `cycleSDL`: [sdl] built and printed.
  String cycle(String sdl) => print(build(sdl));

  /// graphql-js's `buildSingleFieldSchema`: a `Query` root whose one
  /// field, `singleField`, has [type], [arguments] and [description].
  Schema singleField(
    String type, {
    List<InputValue> arguments = const [],
    String? description,
  }) => Schema(
    types: [
      ObjectType(
        'Query',
        fields: [
          SchemaField(
            'singleField',
            this.type(type),
            arguments: arguments,
            description: description,
          ),
        ],
      ),
    ],
    queryTypeName: 'Query',
  );

  /// An argument or input field named [name] of [type], with the default
  /// value written as [defaultValue].
  InputValue input(String name, String type, {String? defaultValue}) =>
      InputValue(
        name,
        this.type(type),
        defaultValue: defaultValue == null ? null : value(defaultValue),
      );

  Document _document(String sdl) => switch (_parser.parse(Source(sdl))) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  T _element<T extends Node>(ParseElementResult<T> result) => switch (result) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };
}
```

- [ ] **Step 4: Run the tests and see them pass**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/support_test.dart)
```

Expected: `+7: All tests passed!`

- [ ] **Step 5: Write the ported tests**

`printSchema-test.ts` has 39 tests and goes into four files by subject. graphql-js 17 prints the working-draft introspection types (`__Schema.directives(includeDeprecated:)`, `__Directive.isDeprecated`, two more locations); this library follows September2025, so `Print Introspection Schema` is adapted with the text this library prints, and that text was checked line by line against the specification.

Create `packages/typed_graphql_conformance/test/schema/print_schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/printSchema-test.ts: the
// schemas are built with the model where graphql-js uses its type
// constructors, in the order graphql-js collects the types.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Prints String Field', () {
      final schema = port.singleField('String');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: String
          }
        '''),
      );
    });

    test('Prints [String] Field', () {
      final schema = port.singleField('[String]');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String]
          }
        '''),
      );
    });

    test('Prints String! Field', () {
      final schema = port.singleField('String!');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: String!
          }
        '''),
      );
    });

    test('Prints [String]! Field', () {
      final schema = port.singleField('[String]!');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String]!
          }
        '''),
      );
    });

    test('Prints [String!] Field', () {
      final schema = port.singleField('[String!]');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String!]
          }
        '''),
      );
    });

    test('Prints [String!]! Field', () {
      final schema = port.singleField('[String!]!');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField: [String!]!
          }
        '''),
      );
    });

    test('Print Object Field', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Foo {
            str: String
          }
        '''),
      );
    });

    test('Prints String Field With Int Arg', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int): String
          }
        '''),
      );
    });

    test('Prints String Field With Int Arg With Default', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int', defaultValue: '2')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int = 2): String
          }
        '''),
      );
    });

    test('Prints String Field With String Arg With Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'String', defaultValue: r'"tes\t de\fault"'),
        ],
      );
      expect(
        port.printed(schema),
        dedent(r'''
          type Query {
            singleField(argOne: String = "tes\t de\fault"): String
          }
        '''),
      );
    });

    test('Prints String Field With Int Arg With Default Null', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int', defaultValue: 'null')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int = null): String
          }
        '''),
      );
    });

    test('Prints String Field With Int! Arg', () {
      final schema = port.singleField(
        'String',
        arguments: [port.input('argOne', 'Int!')],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int!): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int'),
          port.input('argTwo', 'String'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int, argTwo: String): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args, First is Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int', defaultValue: '1'),
          port.input('argTwo', 'String'),
          port.input('argThree', 'Boolean'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int = 1, argTwo: String, argThree: Boolean): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args, Second is Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int'),
          port.input('argTwo', 'String', defaultValue: '"foo"'),
          port.input('argThree', 'Boolean'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int, argTwo: String = "foo", argThree: Boolean): String
          }
        '''),
      );
    });

    test('Prints String Field With Multiple Args, Last is Default', () {
      final schema = port.singleField(
        'String',
        arguments: [
          port.input('argOne', 'Int'),
          port.input('argTwo', 'String'),
          port.input('argThree', 'Boolean', defaultValue: 'false'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            singleField(argOne: Int, argTwo: String, argThree: Boolean = false): String
          }
        '''),
      );
    });

    test('Prints schema with description', () {
      final schema = Schema(
        description: 'Schema description.',
        types: [ObjectType('Query')],
        queryTypeName: 'Query',
      );
      expect(
        port.printed(schema),
        dedent('''
          """Schema description."""
          schema {
            query: Query
          }

          type Query
        '''),
      );
    });

    test('Omits schema of common names', () {
      final schema = Schema(
        types: [
          ObjectType('Query'),
          ObjectType('Mutation'),
          ObjectType('Subscription'),
        ],
        queryTypeName: 'Query',
        mutationTypeName: 'Mutation',
        subscriptionTypeName: 'Subscription',
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query

          type Mutation

          type Subscription
        '''),
      );
    });

    test('Prints custom query root types', () {
      final schema = Schema(
        types: [ObjectType('CustomType')],
        queryTypeName: 'CustomType',
      );
      expect(
        port.printed(schema),
        dedent('''
          schema {
            query: CustomType
          }

          type CustomType
        '''),
      );
    });

    test('Prints custom mutation root types', () {
      final schema = Schema(
        types: [ObjectType('CustomType')],
        mutationTypeName: 'CustomType',
      );
      expect(
        port.printed(schema),
        dedent('''
          schema {
            mutation: CustomType
          }

          type CustomType
        '''),
      );
    });

    test('Prints custom subscription root types', () {
      final schema = Schema(
        types: [ObjectType('CustomType')],
        subscriptionTypeName: 'CustomType',
      );
      expect(
        port.printed(schema),
        dedent('''
          schema {
            subscription: CustomType
          }

          type CustomType
        '''),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/printSchema-test.ts, the
// tests of the kinds of types and of directive definitions.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Print Interface', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Bar',
            interfaces: [port.named('Foo')],
            fields: [SchemaField('str', port.type('String'))],
          ),
          InterfaceType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Bar implements Foo {
            str: String
          }

          interface Foo {
            str: String
          }
        '''),
      );
    });

    test('Print Multiple Interface', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Bar',
            interfaces: [port.named('Foo'), port.named('Baz')],
            fields: [
              SchemaField('str', port.type('String')),
              SchemaField('int', port.type('Int')),
            ],
          ),
          InterfaceType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
          InterfaceType('Baz', fields: [SchemaField('int', port.type('Int'))]),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          type Bar implements Foo & Baz {
            str: String
            int: Int
          }

          interface Foo {
            str: String
          }

          interface Baz {
            int: Int
          }
        '''),
      );
    });

    test('Print Hierarchical Interface', () {
      final schema = Schema(
        types: [
          ObjectType(
            'Bar',
            interfaces: [port.named('Foo'), port.named('Baz')],
            fields: [
              SchemaField('str', port.type('String')),
              SchemaField('int', port.type('Int')),
            ],
          ),
          InterfaceType(
            'Foo',
            fields: [SchemaField('str', port.type('String'))],
          ),
          InterfaceType(
            'Baz',
            interfaces: [port.named('Foo')],
            fields: [
              SchemaField('int', port.type('Int')),
              SchemaField('str', port.type('String')),
            ],
          ),
          ObjectType('Query', fields: [SchemaField('bar', port.type('Bar'))]),
        ],
        queryTypeName: 'Query',
      );
      expect(
        port.printed(schema),
        dedent('''
          type Bar implements Foo & Baz {
            str: String
            int: Int
          }

          interface Foo {
            str: String
          }

          interface Baz implements Foo {
            int: Int
            str: String
          }

          type Query {
            bar: Bar
          }
        '''),
      );
    });

    test('Print Unions', () {
      final schema = Schema(
        types: [
          UnionType('SingleUnion', memberTypes: [port.named('Foo')]),
          ObjectType(
            'Foo',
            fields: [SchemaField('bool', port.type('Boolean'))],
          ),
          UnionType(
            'MultipleUnion',
            memberTypes: [port.named('Foo'), port.named('Bar')],
          ),
          ObjectType(
            'Bar',
            fields: [SchemaField('str', port.type('String'))],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          union SingleUnion = Foo

          type Foo {
            bool: Boolean
          }

          union MultipleUnion = Foo | Bar

          type Bar {
            str: String
          }
        '''),
      );
    });

    test('Print Input Type', () {
      final schema = Schema(
        types: [
          InputObjectType('InputType', fields: [port.input('int', 'Int')]),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          input InputType {
            int: Int
          }
        '''),
      );
    });

    test('Print Input Type with @oneOf directive', () {
      final schema = Schema(
        types: [
          InputObjectType(
            'InputType',
            appliedDirectives: port.applied('@oneOf'),
            fields: [port.input('int', 'Int')],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          input InputType @oneOf {
            int: Int
          }
        '''),
      );
    });

    test('Custom Scalar', () {
      final schema = Schema(types: [ScalarType('Odd')]);
      expect(port.printed(schema), 'scalar Odd');
    });

    test('Custom Scalar with specifiedByURL', () {
      final schema = Schema(
        types: [
          ScalarType(
            'Foo',
            appliedDirectives: port.applied(
              '@specifiedBy(url: "https://example.com/foo_spec")',
            ),
          ),
        ],
      );
      expect(
        port.printed(schema),
        'scalar Foo @specifiedBy(url: "https://example.com/foo_spec")',
      );
    });

    test('Enum', () {
      final schema = Schema(
        types: [
          EnumType(
            'RGB',
            values: [
              SchemaEnumValue('RED'),
              SchemaEnumValue('GREEN'),
              SchemaEnumValue('BLUE'),
            ],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          enum RGB {
            RED
            GREEN
            BLUE
          }
        '''),
      );
    });

    test('Prints empty types', () {
      final schema = Schema(
        types: [
          EnumType('SomeEnum'),
          InputObjectType('SomeInputObject'),
          InterfaceType('SomeInterface'),
          ObjectType('SomeObject'),
          UnionType('SomeUnion'),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          enum SomeEnum

          input SomeInputObject

          interface SomeInterface

          type SomeObject

          union SomeUnion
        '''),
      );
    });

    test('Prints custom directives', () {
      final schema = Schema(
        directives: [
          SchemaDirective('simpleDirective', locations: ['FIELD']),
          SchemaDirective(
            'complexDirective',
            description: 'Complex Directive',
            arguments: [
              port.input('stringArg', 'String'),
              port.input('intArg', 'Int', defaultValue: '-1'),
            ],
            isRepeatable: true,
            locations: ['FIELD', 'QUERY'],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          directive @simpleDirective on FIELD

          """Complex Directive"""
          directive @complexDirective(stringArg: String, intArg: Int = -1) repeatable on FIELD | QUERY
        '''),
      );
    });

    test('Prints deprecated directives', () {
      final schema = Schema(
        directives: [
          SchemaDirective(
            'deprecatedDirective',
            locations: ['FIELD'],
            appliedDirectives: port.applied(
              '@deprecated(reason: "Use another directive")',
            ),
          ),
        ],
      );
      expect(
        port.print(schema),
        'directive @deprecatedDirective '
        '@deprecated(reason: "Use another directive") on FIELD',
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/printSchema-test.ts, the
// tests of descriptions and of the shared viral schema.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Prints an empty descriptions', () {
      List<InputValue> arguments() => [
        InputValue('someArg', port.type('String'), description: ''),
        InputValue('anotherArg', port.type('String'), description: ''),
      ];
      List<SchemaField> fields() => [
        SchemaField(
          'someField',
          port.type('String'),
          description: '',
          arguments: arguments(),
        ),
        SchemaField(
          'anotherField',
          port.type('String'),
          description: '',
          arguments: arguments(),
        ),
      ];
      final schema = Schema(
        description: '',
        queryTypeName: 'Query',
        types: [
          ScalarType('SomeScalar', description: ''),
          InterfaceType('SomeInterface', description: '', fields: fields()),
          UnionType(
            'SomeUnion',
            description: '',
            memberTypes: [port.named('Query')],
          ),
          ObjectType('Query', description: '', fields: fields()),
          EnumType(
            'SomeEnum',
            description: '',
            values: [
              SchemaEnumValue('SOME_VALUE', description: ''),
              SchemaEnumValue('ANOTHER_VALUE', description: ''),
            ],
          ),
        ],
        directives: [
          SchemaDirective(
            'someDirective',
            description: '',
            arguments: arguments(),
            locations: ['QUERY'],
          ),
        ],
      );
      expect(
        port.printed(schema),
        dedent('''
          """"""
          schema {
            query: Query
          }

          """"""
          directive @someDirective(
            """"""
            someArg: String

            """"""
            anotherArg: String
          ) on QUERY

          """"""
          scalar SomeScalar

          """"""
          interface SomeInterface {
            """"""
            someField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String

            """"""
            anotherField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String
          }

          """"""
          union SomeUnion = Query

          """"""
          type Query {
            """"""
            someField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String

            """"""
            anotherField(
              """"""
              someArg: String

              """"""
              anotherArg: String
            ): String
          }

          """"""
          enum SomeEnum {
            """"""
            SOME_VALUE

            """"""
            ANOTHER_VALUE
          }
        '''),
      );
    });

    test('Prints a description with only whitespace', () {
      final schema = port.singleField('String', description: ' ');
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            " "
            singleField: String
          }
        '''),
      );
    });

    test('One-line prints a short description', () {
      final schema = port.singleField(
        'String',
        description: 'This field is awesome',
      );
      expect(
        port.printed(schema),
        dedent('''
          type Query {
            """This field is awesome"""
            singleField: String
          }
        '''),
      );
    });

    test('prints viral schema correctly', () {
      final schema = Schema(
        queryTypeName: 'Query',
        types: [
          ObjectType(
            'Query',
            fields: [SchemaField('viruses', port.type('[Virus!]'))],
          ),
          ObjectType(
            'Virus',
            fields: [
              SchemaField('name', port.type('String!')),
              SchemaField('knownMutations', port.type('[Mutation!]!')),
            ],
          ),
          ObjectType(
            'Mutation',
            fields: [
              SchemaField('name', port.type('String!')),
              SchemaField('geneSequence', port.type('String!')),
            ],
          ),
        ],
      );
      expect(
        port.print(schema),
        dedent('''
          schema {
            query: Query
          }

          type Query {
            viruses: [Virus!]
          }

          type Virus {
            name: String!
            knownMutations: [Mutation!]!
          }

          type Mutation {
            name: String!
            geneSequence: String!
          }
        '''),
      );
    });

    test('prints schema with description and default root operation types correctly', () {
      final schema = Schema(
        description: 'Test',
        queryTypeName: 'Query',
        types: [
          ObjectType('Query', fields: [SchemaField('a', port.type('Int'))]),
        ],
      );
      expect(
        port.print(schema),
        dedent('''
          """Test"""
          schema {
            query: Query
          }

          type Query {
            a: Int
          }
        '''),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/print_introspection_schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Adapted from graphql-js src/utilities/__tests__/printSchema-test.ts.
// `printIntrospectionSchema` prints the specified directives and the
// introspection types; `SchemaPrinter(includesBuiltIns: true)` also
// prints the built-in scalars, so the test prints a schema declaring the
// built-in directives and introspection types alone. graphql-js 17 prints
// the working draft's introspection; the text below is the September2025
// edition's: `includeDeprecated: Boolean! = false`, no argument on
// `__Schema.directives`, no deprecation of directives, and no
// `FRAGMENT_VARIABLE_DEFINITION` or `DIRECTIVE_DEFINITION` location.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Type System Printer', () {
    test('Print Introspection Schema', () {
      const builtIns = BuiltIns();
      final schema = Schema(
        directives: builtIns.directives,
        types: builtIns.introspectionTypes,
      );
      expect(
        port.print(schema),
        dedent('''
          """
          Directs the executor to include this field or fragment only when the `if` argument is true.
          """
          directive @include(
            """Included when true."""
            if: Boolean!
          ) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          """
          Directs the executor to skip this field or fragment when the `if` argument is true.
          """
          directive @skip(
            """Skipped when true."""
            if: Boolean!
          ) on FIELD | FRAGMENT_SPREAD | INLINE_FRAGMENT

          """Marks an element of a GraphQL schema as no longer supported."""
          directive @deprecated(
            """
            Explains why this element was deprecated, usually also including a suggestion for how to access supported similar data. Formatted using the Markdown syntax, as specified by [CommonMark](https://commonmark.org/).
            """
            reason: String! = "No longer supported"
          ) on FIELD_DEFINITION | ARGUMENT_DEFINITION | INPUT_FIELD_DEFINITION | ENUM_VALUE

          """Exposes a URL that specifies the behavior of this scalar."""
          directive @specifiedBy(
            """The URL that specifies the behavior of this scalar."""
            url: String!
          ) on SCALAR

          """
          Indicates exactly one field must be supplied and this field must not be `null`.
          """
          directive @oneOf on INPUT_OBJECT

          """
          A GraphQL Schema defines the capabilities of a GraphQL server. It exposes all available types and directives on the server, as well as the entry points for query, mutation, and subscription operations.
          """
          type __Schema {
            description: String

            """A list of all types supported by this server."""
            types: [__Type!]!

            """The type that query operations will be rooted at."""
            queryType: __Type!

            """
            If this server supports mutation, the type that mutation operations will be rooted at.
            """
            mutationType: __Type

            """
            If this server support subscription, the type that subscription operations will be rooted at.
            """
            subscriptionType: __Type

            """A list of all directives supported by this server."""
            directives: [__Directive!]!
          }

          """
          The fundamental unit of any GraphQL Schema is the type. There are many kinds of types in GraphQL as represented by the `__TypeKind` enum.

          Depending on the kind of a type, certain fields describe information about that type. Scalar types provide no information beyond a name, description and optional `specifiedByURL`, while Enum types provide their values. Object and Interface types provide the fields they describe. Abstract types, Union and Interface, provide the Object types possible at runtime. List and NonNull types compose other types.
          """
          type __Type {
            kind: __TypeKind!
            name: String
            description: String
            specifiedByURL: String
            fields(includeDeprecated: Boolean! = false): [__Field!]
            interfaces: [__Type!]
            possibleTypes: [__Type!]
            enumValues(includeDeprecated: Boolean! = false): [__EnumValue!]
            inputFields(includeDeprecated: Boolean! = false): [__InputValue!]
            ofType: __Type
            isOneOf: Boolean
          }

          """An enum describing what kind of type a given `__Type` is."""
          enum __TypeKind {
            """Indicates this type is a scalar."""
            SCALAR

            """
            Indicates this type is an object. `fields` and `interfaces` are valid fields.
            """
            OBJECT

            """
            Indicates this type is an interface. `fields`, `interfaces`, and `possibleTypes` are valid fields.
            """
            INTERFACE

            """Indicates this type is a union. `possibleTypes` is a valid field."""
            UNION

            """Indicates this type is an enum. `enumValues` is a valid field."""
            ENUM

            """
            Indicates this type is an input object. `inputFields` is a valid field.
            """
            INPUT_OBJECT

            """Indicates this type is a list. `ofType` is a valid field."""
            LIST

            """Indicates this type is a non-null. `ofType` is a valid field."""
            NON_NULL
          }

          """
          Object and Interface types are described by a list of Fields, each of which has a name, potentially a list of arguments, and a return type.
          """
          type __Field {
            name: String!
            description: String
            args(includeDeprecated: Boolean! = false): [__InputValue!]!
            type: __Type!
            isDeprecated: Boolean!
            deprecationReason: String
          }

          """
          Arguments provided to Fields or Directives and the input fields of an InputObject are represented as Input Values which describe their type and optionally a default value.
          """
          type __InputValue {
            name: String!
            description: String
            type: __Type!

            """
            A GraphQL-formatted string representing the default value for this input value.
            """
            defaultValue: String
            isDeprecated: Boolean!
            deprecationReason: String
          }

          """
          One possible value for a given Enum. Enum values are unique values, not a placeholder for a string or numeric value. However an Enum value is returned in a JSON response as a string.
          """
          type __EnumValue {
            name: String!
            description: String
            isDeprecated: Boolean!
            deprecationReason: String
          }

          """
          A Directive provides a way to describe alternate runtime execution and type validation behavior in a GraphQL document.

          In some cases, you need to provide options to alter GraphQL's execution behavior in ways field arguments will not suffice, such as conditionally including or skipping a field. Directives provide this by describing additional information to the executor.
          """
          type __Directive {
            name: String!
            description: String
            isRepeatable: Boolean!
            locations: [__DirectiveLocation!]!
            args(includeDeprecated: Boolean! = false): [__InputValue!]!
          }

          """
          A Directive can be adjacent to many parts of the GraphQL language, a __DirectiveLocation describes one such possible adjacencies.
          """
          enum __DirectiveLocation {
            """Location adjacent to a query operation."""
            QUERY

            """Location adjacent to a mutation operation."""
            MUTATION

            """Location adjacent to a subscription operation."""
            SUBSCRIPTION

            """Location adjacent to a field."""
            FIELD

            """Location adjacent to a fragment definition."""
            FRAGMENT_DEFINITION

            """Location adjacent to a fragment spread."""
            FRAGMENT_SPREAD

            """Location adjacent to an inline fragment."""
            INLINE_FRAGMENT

            """Location adjacent to an operation variable definition."""
            VARIABLE_DEFINITION

            """Location adjacent to a schema definition."""
            SCHEMA

            """Location adjacent to a scalar definition."""
            SCALAR

            """Location adjacent to an object type definition."""
            OBJECT

            """Location adjacent to a field definition."""
            FIELD_DEFINITION

            """Location adjacent to an argument definition."""
            ARGUMENT_DEFINITION

            """Location adjacent to an interface definition."""
            INTERFACE

            """Location adjacent to a union definition."""
            UNION

            """Location adjacent to an enum definition."""
            ENUM

            """Location adjacent to an enum value definition."""
            ENUM_VALUE

            """Location adjacent to an input object type definition."""
            INPUT_OBJECT

            """Location adjacent to an input object field definition."""
            INPUT_FIELD_DEFINITION
          }
        '''),
      );
    });
  });
}
```

- [ ] **Step 6: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/schema/print_schema_test.dart test/schema/print_schema_types_test.dart test/schema/print_schema_descriptions_test.dart test/schema/print_introspection_schema_test.dart)
```

Expected: `print_schema_test.dart` `+21`, `print_schema_types_test.dart` `+12`, `print_schema_descriptions_test.dart` `+5`, `print_introspection_schema_test.dart` `+1`, each `All tests passed!` at once: they test finished code.

- [ ] **Step 7: Check two tables and see the coverage check fail**

The table check now runs over a list of tables, each with its prefix and its covered files; `language.csv` still covers every file of the language folder.

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,73 +9,94 @@ import 'support/csv_table.dart';
 import 'support/graphql_js_suite.dart';
 
 void main() {
-  final table = CsvTable.parse(
-    File('mapping/language.csv').readAsStringSync(),
-  );
+  void checkRows(CsvTable table) {
+    test('has the documented columns', () {
+      expect(table.header, [
+        'graphql_js_file',
+        'group',
+        'test',
+        'status',
+        'dart_file',
+        'reason',
+      ]);
+    });
 
-  test('has the documented columns', () {
-    expect(table.header, [
-      'graphql_js_file',
-      'group',
-      'test',
-      'status',
-      'dart_file',
-      'reason',
-    ]);
-  });
-
-  test('every row has a known status', () {
-    for (final row in table.rows) {
-      expect(row['status'], isIn(['ported', 'adapted', 'skipped']));
-    }
-  });
+    test('every row has a known status', () {
+      for (final row in table.rows) {
+        expect(row['status'], isIn(['ported', 'adapted', 'skipped']));
+      }
+    });
 
-  test('adapted and skipped rows give a reason', () {
-    for (final row in table.rows.where((row) => row['status'] != 'ported')) {
-      expect(row['reason'], isNotEmpty, reason: '$row');
-    }
-  });
+    test('adapted and skipped rows give a reason', () {
+      for (final row in table.rows.where((row) => row['status'] != 'ported')) {
+        expect(row['reason'], isNotEmpty, reason: '$row');
+      }
+    });
 
-  test('no graphql-js test has two rows', () {
-    final keys = [
-      for (final row in table.rows)
-        (row['graphql_js_file'], row['group'], row['test']),
-    ];
-    expect(keys.toSet(), hasLength(keys.length));
-  });
+    test('no graphql-js test has two rows', () {
+      final keys = [
+        for (final row in table.rows)
+          (row['graphql_js_file'], row['group'], row['test']),
+      ];
+      expect(keys.toSet(), hasLength(keys.length));
+    });
 
-  test('ported and adapted rows name a Dart test that exists', () {
-    // `name(` and the quoted argument, with any whitespace between: the
-    // formatter moves a long name to its own line.
-    RegExp call(String name, String argument) =>
-        RegExp('$name\\(\\s*${RegExp.escape("'$argument'")}');
-    for (final row in table.rows.where((row) => row['status'] != 'skipped')) {
-      final file = File('${row['dart_file']}');
-      expect(file.existsSync(), isTrue, reason: '$row');
-      final text = file.readAsStringSync();
-      for (final group in '${row['group']}'.split(' > ')) {
-        expect(text, contains(call('group', group)), reason: '$row');
+    test('ported and adapted rows name a Dart test that exists', () {
+      // `name(` and the quoted argument, with any whitespace between: the
+      // formatter moves a long name to its own line.
+      RegExp call(String name, String argument) =>
+          RegExp('$name\\(\\s*${RegExp.escape("'$argument'")}');
+      for (final row in table.rows.where((row) => row['status'] != 'skipped')) {
+        final file = File('${row['dart_file']}');
+        expect(file.existsSync(), isTrue, reason: '$row');
+        final text = file.readAsStringSync();
+        for (final group in '${row['group']}'.split(' > ')) {
+          expect(text, contains(call('group', group)), reason: '$row');
+        }
+        expect(text, contains(call('test', '${row['test']}')), reason: '$row');
       }
-      expect(text, contains(call('test', '${row['test']}')), reason: '$row');
-    }
-  });
-
-  test('names only graphql-js files that exist', () {
-    final names = {for (final row in table.rows) row['graphql_js_file']};
-    expect(GraphqlJsSuite.files, containsAll(names));
-  }, skip: !GraphqlJsSuite.isAvailable);
+    });
+  }
 
-  // Spec §8: every file of the graphql-js language tests has a row for
-  // each of its tests, so a new upstream file or test fails here.
-  group('rows cover every test of', () {
-    for (final file in GraphqlJsSuite.files) {
-      test(file, () {
-        final mapped = {
-          for (final row in table.rows)
-            if (row['graphql_js_file'] == file) (row['group'], row['test']),
-        };
-        expect(mapped, GraphqlJsSuite.read(file).tests.toSet());
-      });
-    }
-  });
+  // A row names its graphql-js file relative to `prefix`, under `src/`;
+  // `covered` lists the files whose every test must have a row.
+  final tables = [
+    (
+      path: 'mapping/language.csv',
+      prefix: 'language/__tests__/',
+      covered: GraphqlJsSuite.filesIn('language/__tests__'),
+    ),
+    (
+      path: 'mapping/schema.csv',
+      prefix: '',
+      covered: const ['utilities/__tests__/printSchema-test.ts'],
+    ),
+  ];
+  for (final (:path, :prefix, :covered) in tables) {
+    group(path, () {
+      final table = CsvTable.parse(File(path).readAsStringSync());
+      checkRows(table);
+      test('names only graphql-js files that exist', () {
+        for (final row in table.rows) {
+          final file =
+              '${GraphqlJsSuite.sourceDirectory}/'
+              '$prefix${row['graphql_js_file']}';
+          expect(File(file).existsSync(), isTrue, reason: '$row');
+        }
+      }, skip: !GraphqlJsSuite.isAvailable);
+      // Spec §8 of M2, §11 of M3: every covered file has a row for each of
+      // its tests, so a new upstream file or test fails here.
+      group('rows cover every test of', () {
+        for (final file in covered) {
+          test(file, () {
+            final mapped = {
+              for (final row in table.rows)
+                if (row['graphql_js_file'] == file) (row['group'], row['test']),
+            };
+            expect(mapped, GraphqlJsSuite.read('$prefix$file').tests.toSet());
+          });
+        }
+      }, skip: !GraphqlJsSuite.isAvailable);
+    });
+  }
 }
```

Create `packages/typed_graphql_conformance/mapping/schema.csv` with the header only:

```csv
graphql_js_file,group,test,status,dart_file,reason
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of utilities/__tests__/printSchema-test.ts`: `Actual: Set:[]`, `Which: does not contain (String, String):<(Type System Printer, Prints String Field)>`. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 8: Write the rows**

Thirty-nine rows: 38 ported, 1 adapted.

Replace `packages/typed_graphql_conformance/mapping/schema.csv` whole with:

```csv
graphql_js_file,group,test,status,dart_file,reason
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints [String] Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String! Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints [String]! Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints [String!] Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints [String!]! Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Object Field,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field With Int Arg,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field With Int Arg With Default,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field With String Arg With Default,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field With Int Arg With Default Null,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field With Int! Arg,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints String Field With Multiple Args,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,"Prints String Field With Multiple Args, First is Default",ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,"Prints String Field With Multiple Args, Second is Default",ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,"Prints String Field With Multiple Args, Last is Default",ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints schema with description,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Omits schema of common names,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints custom query root types,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints custom mutation root types,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints custom subscription root types,ported,test/schema/print_schema_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Interface,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Multiple Interface,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Hierarchical Interface,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Unions,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Input Type,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Input Type with @oneOf directive,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Custom Scalar,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Custom Scalar with specifiedByURL,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Enum,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints empty types,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints custom directives,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints deprecated directives,ported,test/schema/print_schema_types_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints an empty descriptions,ported,test/schema/print_schema_descriptions_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Prints a description with only whitespace,ported,test/schema/print_schema_descriptions_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,One-line prints a short description,ported,test/schema/print_schema_descriptions_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,Print Introspection Schema,adapted,test/schema/print_introspection_schema_test.dart,"graphql-js 17 prints the working-draft introspection types; the expected text is the September2025 edition, printed from a schema declaring the built-in directives and introspection types"
utilities/__tests__/printSchema-test.ts,Type System Printer,prints viral schema correctly,ported,test/schema/print_schema_descriptions_test.dart,
utilities/__tests__/printSchema-test.ts,Type System Printer,prints schema with description and default root operation types correctly,ported,test/schema/print_schema_descriptions_test.dart,
```

- [ ] **Step 9: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+285: All tests passed!`

- [ ] **Step 10: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -19,3 +19,6 @@
 - Hostile-text fuzzer (R1.6, R10.4): random and mutated text through every
   parser entry point stays within the sink limit, and every diagnostic has
   a source excerpt.
+- `mapping/schema.csv`, the conformance table of the schema suites, checked
+  by the same mapping test; `SchemaPort`, the port helpers. Ported
+  graphql-js schema suites: `printSchema-test.ts`.
```

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -13,22 +13,23 @@
 
 ## Ported suites
 
-Tests under `test/language/` are ported from graphql-js 17
-(`reference/graphql-js`, fetched by `tool/fetch_reference.sh`), one Dart test
-per graphql-js test, with the same group and test names.
-`mapping/language.csv` records each graphql-js test:
+Tests under `test/language/` and `test/schema/` are ported from graphql-js
+17 (`reference/graphql-js`, fetched by `tool/fetch_reference.sh`), one Dart
+test per graphql-js test, with the same group and test names.
+`mapping/language.csv` and `mapping/schema.csv` record each graphql-js test:
 
 | Column | Meaning |
 |---|---|
-| `graphql_js_file` | the file in `src/language/__tests__/`, such as `lexer-test.ts` |
+| `graphql_js_file` | the file: in `src/language/__tests__/` for `language.csv`, such as `lexer-test.ts`; in `src/` for `schema.csv`, such as `utilities/__tests__/printSchema-test.ts` |
 | `group` | the `describe` blocks around the test, joined by ` > ` |
 | `test` | the `it` name |
 | `status` | `ported` (same assertions), `adapted` (a deliberate design difference changes them) or `skipped` (behaviour this library does not have) |
 | `dart_file` | the Dart test file, relative to this package; empty when skipped |
 | `reason` | why, for `adapted` and `skipped` |
 
-`test/mapping_test.dart` checks the table; with `reference/` fetched it also
-checks that every test of every graphql-js language test file has a row.
+`test/mapping_test.dart` checks the tables; with `reference/` fetched it also
+checks that every test of every graphql-js language test file, and of each
+graphql-js schema test file the stage ports, has a row.
 
 ## Fuzzing
 
```

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -358,8 +358,9 @@ fails when it finds none.
   and its scanners).
 - Core layer test: `packages/typed_graphql/test/quality/layers_test.dart`.
 - Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
-- Conformance mapping table: `packages/typed_graphql_conformance/mapping/language.csv`,
-  checked by `test/mapping_test.dart` there; port helpers in its `test/support/`.
+- Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`
+  and `mapping/schema.csv`, checked by `test/mapping_test.dart` there; port
+  helpers in its `test/support/` (`SchemaPort` for the schema suites).
 - Fuzzers: `packages/typed_graphql_conformance/test/fuzz/`;
   `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune them.
 - CI: `.github/workflows/ci.yml`.
```

- [ ] **Step 11: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 12: Commit**

```sh
git add CLAUDE.md packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/print_introspection_schema_test.dart packages/typed_graphql_conformance/test/schema/print_schema_descriptions_test.dart packages/typed_graphql_conformance/test/schema/print_schema_test.dart packages/typed_graphql_conformance/test/schema/print_schema_types_test.dart packages/typed_graphql_conformance/test/support/graphql_js_suite.dart packages/typed_graphql_conformance/test/support/schema_port.dart packages/typed_graphql_conformance/test/support_test.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js schema printer suite" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 17: Port the graphql-js schema builder suite

`buildASTSchema-test.ts`, by the procedure of Task 16.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart`, `packages/typed_graphql_conformance/test/schema/build_schema_extensions_test.dart`, `packages/typed_graphql_conformance/test/schema/build_schema_test.dart`, `packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart`, `packages/typed_graphql_conformance/test/support/schema_port.dart`

**Interfaces:**
- Consumes: Task 16: `SchemaPort`, `schema.csv`, the table check.
- Produces:
  - `SchemaPort.buildResult(String sdl)`, `codes(BuildResult)`, `assertType<T extends SchemaType>(Schema, String)`, `printType(SchemaType)`, `document(String sdl)`;
  - 57 rows for `buildASTSchema-test.ts`.

- [ ] **Step 1: Extend the port helper**

`buildResult` and `codes` serve the tests that expect diagnostics; `assertType` is graphql-js's `assertObjectType` and its siblings; `printType` prints one type.

In `packages/typed_graphql_conformance/test/support/schema_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -26,7 +26,8 @@ final class SchemaPort {
 
   /// The directives applied in [text], such as `@deprecated(reason: "x")`.
   List<AppliedDirective> applied(String text) {
-    final directives = switch (_document('scalar Applied $text').definitions) {
+    final directives = switch (_document(Source('scalar Applied $text'))
+        .definitions) {
       [ScalarTypeDefinition(:final directives)] => directives,
       _ => fail('Not directives: $text'),
     };
@@ -41,15 +42,36 @@ final class SchemaPort {
 
   /// graphql-js's `buildSchema`: [sdl] built; fails the test on a
   /// diagnostic.
-  Schema build(String sdl) =>
-      switch (const SchemaBuilder().fromSdl(_document(sdl))) {
-        BuildSuccess(:final schema) => schema,
-        BuildFailure(:final diagnostics) => fail('$diagnostics'),
+  Schema build(String sdl) => switch (buildResult(sdl)) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure(:final diagnostics) => fail('$diagnostics'),
+  };
+
+  /// [sdl] built, for a test that expects diagnostics.
+  BuildResult buildResult(String sdl) {
+    final source = Source(sdl);
+    return const SchemaBuilder().fromSdl(_document(source), source: source);
+  }
+
+  /// The ids of the codes of [result]'s diagnostics, such as `GQL103`.
+  List<String> codes(BuildResult result) => [
+    for (final diagnostic in result.diagnostics) diagnostic.code.id,
+  ];
+
+  /// graphql-js's `assertScalarType` and its siblings: the type of
+  /// [schema] named [name]; fails the test unless it is a [T].
+  T assertType<T extends SchemaType>(Schema schema, String name) =>
+      switch (schema.typeNamed(name)) {
+        final T type => type,
+        final other => fail('$name is $other, not a $T.'),
       };
 
   /// graphql-js's `printSchema`.
   String print(Schema schema) => const SchemaPrinter().print(schema);
 
+  /// graphql-js's `printType`: [type] printed alone.
+  String printType(SchemaType type) => print(Schema(types: [type]));
+
   /// graphql-js's `expectPrintedSchema`: [schema] printed, after checking
   /// that building and printing the text gives it back.
   String printed(Schema schema) {
@@ -93,7 +115,10 @@ final class SchemaPort {
         defaultValue: defaultValue == null ? null : value(defaultValue),
       );
 
-  Document _document(String sdl) => switch (_parser.parse(Source(sdl))) {
+  /// [sdl] parsed; fails the test on a syntax error.
+  Document document(String sdl) => _document(Source(sdl));
+
+  Document _document(Source source) => switch (_parser.parse(source)) {
     ParseSuccess(:final document) => document,
     ParseFailure(:final diagnostics) => fail('$diagnostics'),
   };
```

- [ ] **Step 2: Write the ported tests**

`buildASTSchema-test.ts` has 57 tests, in four files. Most adaptations have one of four reasons: schema validation arrives in M3b, so a test checks what the builder keeps instead of the error; the model keeps spans, not AST nodes; built-ins are found, not listed; and an operation or a redefined built-in is a diagnostic where graphql-js ignores or replaces it.

Create `packages/typed_graphql_conformance/test/schema/build_schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// built-ins, directives, descriptions and type references. The built-in
// scalars, directives and introspection types are never listed in a
// schema; lookups find the shared instances of `BuiltIns`.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();
  const builtIns = BuiltIns();

  group('Schema Builder', () {
    test('Ignores non-type system definitions', () {
      final result = port.buildResult('''
        type Query {
          str: String
        }

        fragment SomeFragment on Query {
          str
        }
      ''');
      expect(port.codes(result), ['GQL100']);
    });

    test('Match order of default types and directives', () {
      final built = switch (const SchemaBuilder().fromSdl(
        Document(const []),
      )) {
        BuildSuccess(:final schema) => schema,
        BuildFailure(:final diagnostics) => fail('$diagnostics'),
      };
      final empty = Schema();
      expect(built.types, isEmpty);
      expect(built.directives, isEmpty);
      for (final directive in builtIns.directives) {
        expect(
          built.directiveNamed(directive.name),
          same(empty.directiveNamed(directive.name)),
        );
      }
    });

    test('Empty type', () {
      final sdl = dedent('''
        type EmptyType
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type', () {
      final sdl = dedent('''
        type Query {
          str: String
          int: Int
          float: Float
          id: ID
          bool: Boolean
        }
      ''');
      expect(port.cycle(sdl), sdl);

      final schema = port.build(sdl);
      for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
        expect(schema.typeNamed(name), same(builtIns.scalarNamed(name)));
      }
    });

    test('include standard type only if it is used', () {
      final schema = port.build('type Query');
      expect([for (final type in schema.types) type.name], ['Query']);
      expect(port.print(schema), 'type Query');
    });

    test('With directives', () {
      final sdl = dedent('''
        directive @foo(arg: Int) on FIELD

        directive @repeatableFoo(arg: Int) repeatable on FIELD
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Supports descriptions', () {
      final sdl = dedent('''
        """Do you agree that this is the most creative schema ever?"""
        schema {
          query: Query
        }

        """This is a directive"""
        directive @foo(
          """It has an argument"""
          arg: Int
        ) on FIELD

        """Who knows what inside this scalar?"""
        scalar MysteryScalar

        """This is a input object type"""
        input FooInput {
          """It has a field"""
          field: Int
        }

        """This is a interface type"""
        interface Energy {
          """It also has a field"""
          str: String
        }

        """There is nothing inside!"""
        union BlackHole

        """With an enum"""
        enum Color {
          RED

          """Not a creative color"""
          GREEN
          BLUE
        }

        """What a great type"""
        type Query {
          """And a field to boot"""
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Maintains @include, @skip & @specifiedBy', () {
      final schema = port.build('type Query');
      expect(schema.directives, isEmpty);
      expect(builtIns.directives, hasLength(5));
      for (final name in [
        'skip',
        'include',
        'deprecated',
        'specifiedBy',
        'oneOf',
      ]) {
        expect(
          schema.directiveNamed(name),
          same(builtIns.directiveNamed(name)),
        );
      }
    });

    test('Overriding directives excludes specified', () {
      final result = port.buildResult('''
        directive @skip on FIELD
        directive @include on FIELD
        directive @deprecated on FIELD_DEFINITION
        directive @specifiedBy on FIELD_DEFINITION
        directive @oneOf on OBJECT
      ''');
      expect(port.codes(result), List.filled(5, 'GQL103'));
    });

    test(
      'Adding directives maintains @include, @skip, @deprecated, @specifiedBy, and @oneOf',
      () {
        final schema = port.build('''
          directive @foo(arg: Int) on FIELD
        ''');
        expect(
          [
            for (final directive in schema.directives) directive.name,
          ],
          ['foo'],
        );
        for (final name in [
          'skip',
          'include',
          'deprecated',
          'specifiedBy',
          'oneOf',
        ]) {
          expect(schema.directiveNamed(name), isNotNull);
        }
      },
    );

    test('Type modifiers', () {
      final sdl = dedent('''
        type Query {
          nonNullStr: String!
          listOfStrings: [String]
          listOfNonNullStrings: [String!]
          nonNullListOfStrings: [String]!
          nonNullListOfNonNullStrings: [String!]!
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Recursive type', () {
      final sdl = dedent('''
        type Query {
          str: String
          recurse: Query
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Two types circular', () {
      final sdl = dedent('''
        type TypeOne {
          str: String
          typeTwo: TypeTwo
        }

        type TypeTwo {
          str: String
          typeOne: TypeOne
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Single argument field', () {
      final sdl = dedent('''
        type Query {
          str(int: Int): String
          floatToStr(float: Float): String
          idToStr(id: ID): String
          booleanToStr(bool: Boolean): String
          strToStr(bool: String): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with multiple arguments', () {
      final sdl = dedent('''
        type Query {
          str(int: Int, bool: Boolean): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// each kind of type and the root operation types, built and printed.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Schema Builder', () {
    test('Empty interface', () {
      final sdl = dedent('''
        interface EmptyInterface
      ''');
      // graphql-js leaves `interfaces` undefined; the Dart node has an
      // empty list.
      final [definition] = port.document(sdl).definitions;
      expect(
        definition,
        isA<InterfaceTypeDefinition>().having(
          (definition) => definition.interfaces,
          'interfaces',
          isEmpty,
        ),
      );
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with interface', () {
      final sdl = dedent('''
        type Query implements WorldInterface {
          str: String
        }

        interface WorldInterface {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple interface hierarchy', () {
      final sdl = dedent('''
        schema {
          query: Child
        }

        interface Child implements Parent {
          str: String
        }

        type Hello implements Parent & Child {
          str: String
        }

        interface Parent {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Empty enum', () {
      final sdl = dedent('''
        enum EmptyEnum
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple output enum', () {
      final sdl = dedent('''
        enum Hello {
          WORLD
        }

        type Query {
          hello: Hello
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple input enum', () {
      final sdl = dedent('''
        enum Hello {
          WORLD
        }

        type Query {
          str(hello: Hello): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Multiple value enum', () {
      final sdl = dedent('''
        enum Hello {
          WO
          RLD
        }

        type Query {
          hello: Hello
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Empty union', () {
      final sdl = dedent('''
        union EmptyUnion
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple Union', () {
      final sdl = dedent('''
        union Hello = World

        type Query {
          hello: Hello
        }

        type World {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Multiple Union', () {
      final sdl = dedent('''
        union Hello = WorldOne | WorldTwo

        type Query {
          hello: Hello
        }

        type WorldOne {
          str: String
        }

        type WorldTwo {
          str: String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Can build recursive Union', () {
      final schema = port.build('''
        union Hello = Hello

        type Query {
          hello: Hello
        }
      ''');
      // graphql-js then checks that validateSchema reports the union;
      // schema validation arrives in M3b.
      final hello = schema.typeNamed('Hello');
      expect(hello, isA<UnionType>());
      expect(port.print(Schema(types: [?hello])), 'union Hello = Hello');
    });

    test('Custom Scalar', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          customScalar: CustomScalar
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Empty Input Object', () {
      final sdl = dedent('''
        input EmptyInputObject
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple Input Object', () {
      final sdl = dedent('''
        input Input {
          int: Int
        }

        type Query {
          field(in: Input): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple argument field with default', () {
      final sdl = dedent('''
        type Query {
          str(int: Int = 2): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Custom scalar argument field with default', () {
      final sdl = dedent('''
        scalar CustomScalar

        type Query {
          str(int: CustomScalar = 2): String
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with mutation', () {
      final sdl = dedent('''
        schema {
          query: HelloScalars
          mutation: Mutation
        }

        type HelloScalars {
          str: String
          int: Int
          bool: Boolean
        }

        type Mutation {
          addHelloScalars(str: String, int: Int, bool: Boolean): HelloScalars
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Simple type with subscription', () {
      final sdl = dedent('''
        schema {
          query: HelloScalars
          subscription: Subscription
        }

        type HelloScalars {
          str: String
          int: Int
          bool: Boolean
        }

        type Subscription {
          subscribeHelloScalars(str: String, int: Int, bool: Boolean): HelloScalars
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Unreferenced type implementing referenced interface', () {
      final sdl = dedent('''
        type Concrete implements Interface {
          key: String
        }

        interface Interface {
          key: String
        }

        type Query {
          interface: Interface
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Unreferenced interface implementing referenced interface', () {
      final sdl = dedent('''
        interface Child implements Parent {
          key: String
        }

        interface Parent {
          key: String
        }

        type Query {
          interfaceField: Parent
        }
      ''');
      expect(port.cycle(sdl), sdl);
    });

    test('Unreferenced type implementing referenced union', () {
      final sdl = dedent('''
        type Concrete {
          key: String
        }

        type Query {
          union: Union
        }

        union Union = Concrete
      ''');
      expect(port.cycle(sdl), sdl);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/build_schema_extensions_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Adapted from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// extensions in the document that defines the type. graphql-js keeps the
// extension nodes (`extensionASTNodes`); the model keeps only the span of
// the definition, so those checks are dropped. The SDL is dedented, so a
// span's text is the definition as graphql-js prints its node.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('Schema Builder', () {
    test('Correctly extend scalar type', () {
      final schema = port.build(
        dedent('''
          scalar SomeScalar
          extend scalar SomeScalar @foo
          extend scalar SomeScalar @bar

          directive @foo on SCALAR
          directive @bar on SCALAR
        '''),
      );
      final someScalar = port.assertType<ScalarType>(schema, 'SomeScalar');
      // graphql-js prints `scalar SomeScalar`: it drops directives other
      // than @deprecated, @specifiedBy and @oneOf.
      expect(port.printType(someScalar), 'scalar SomeScalar @foo @bar');
      expect(someScalar.span?.text, 'scalar SomeScalar');
    });

    test('Correctly extend object type', () {
      final schema = port.build(
        dedent('''
          type SomeObject implements Foo {
            first: String
          }

          extend type SomeObject implements Bar {
            second: Int
          }

          extend type SomeObject implements Baz {
            third: Float
          }

          interface Foo
          interface Bar
          interface Baz
        '''),
      );
      final someObject = port.assertType<ObjectType>(schema, 'SomeObject');
      expect(
        port.printType(someObject),
        dedent('''
          type SomeObject implements Foo & Bar & Baz {
            first: String
            second: Int
            third: Float
          }
        '''),
      );
      expect(
        someObject.span?.text,
        dedent('''
          type SomeObject implements Foo {
            first: String
          }
        '''),
      );
    });

    test('Correctly extend interface type', () {
      final schema = port.build(
        dedent('''
          interface SomeInterface {
            first: String
          }

          extend interface SomeInterface {
            second: Int
          }

          extend interface SomeInterface {
            third: Float
          }
        '''),
      );
      final someInterface = port.assertType<InterfaceType>(
        schema,
        'SomeInterface',
      );
      expect(
        port.printType(someInterface),
        dedent('''
          interface SomeInterface {
            first: String
            second: Int
            third: Float
          }
        '''),
      );
      expect(
        someInterface.span?.text,
        dedent('''
          interface SomeInterface {
            first: String
          }
        '''),
      );
    });

    test('Correctly extend union type', () {
      final schema = port.build(
        dedent('''
          union SomeUnion = FirstType
          extend union SomeUnion = SecondType
          extend union SomeUnion = ThirdType

          type FirstType
          type SecondType
          type ThirdType
        '''),
      );
      final someUnion = port.assertType<UnionType>(schema, 'SomeUnion');
      expect(
        port.printType(someUnion),
        'union SomeUnion = FirstType | SecondType | ThirdType',
      );
      expect(someUnion.span?.text, 'union SomeUnion = FirstType');
    });

    test('Correctly extend enum type', () {
      final schema = port.build(
        dedent('''
          enum SomeEnum {
            FIRST
          }

          extend enum SomeEnum {
            SECOND
          }

          extend enum SomeEnum {
            THIRD
          }
        '''),
      );
      final someEnum = port.assertType<EnumType>(schema, 'SomeEnum');
      expect(
        port.printType(someEnum),
        dedent('''
          enum SomeEnum {
            FIRST
            SECOND
            THIRD
          }
        '''),
      );
      expect(
        someEnum.span?.text,
        dedent('''
          enum SomeEnum {
            FIRST
          }
        '''),
      );
    });

    test('Correctly extend input object type', () {
      final schema = port.build(
        dedent('''
          input SomeInput {
            first: String
          }

          extend input SomeInput {
            second: Int
          }

          extend input SomeInput {
            third: Float
          }
        '''),
      );
      final someInput = port.assertType<InputObjectType>(schema, 'SomeInput');
      expect(
        port.printType(someInput),
        dedent('''
          input SomeInput {
            first: String
            second: Int
            third: Float
          }
        '''),
      );
      expect(
        someInput.span?.text,
        dedent('''
          input SomeInput {
            first: String
          }
        '''),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/buildASTSchema-test.ts:
// deprecation, spans, root types and the built-in names. Where graphql-js
// calls validateSchema, the check returns with schema validation in M3b.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();
  const builtIns = BuiltIns();

  group('Schema Builder', () {
    test('Supports @deprecated', () {
      final sdl = dedent('''
        enum MyEnum {
          VALUE
          OLD_VALUE @deprecated
          OTHER_VALUE @deprecated(reason: "Terrible reasons")
        }

        input MyInput {
          oldInput: String @deprecated
          otherInput: String @deprecated(reason: "Use newInput")
          newInput: String
        }

        type Query {
          field1: String @deprecated
          field2: Int @deprecated(reason: "Because I said so")
          enum: MyEnum
          field3(oldArg: String @deprecated, arg: String): String
          field4(oldArg: String @deprecated(reason: "Why not?"), arg: String): String
          field5(arg: MyInput): String
        }
      ''');
      expect(port.cycle(sdl), sdl);

      final schema = port.build(sdl);
      final myEnum = port.assertType<EnumType>(schema, 'MyEnum');
      expect(myEnum.valueNamed('VALUE')?.deprecationReason, isNull);
      expect(
        myEnum.valueNamed('OLD_VALUE')?.deprecationReason,
        'No longer supported',
      );
      expect(
        myEnum.valueNamed('OTHER_VALUE')?.deprecationReason,
        'Terrible reasons',
      );

      final query = port.assertType<ObjectType>(schema, 'Query');
      expect(
        query.fieldNamed('field1')?.deprecationReason,
        'No longer supported',
      );
      expect(
        query.fieldNamed('field2')?.deprecationReason,
        'Because I said so',
      );

      final myInput = port.assertType<InputObjectType>(schema, 'MyInput');
      expect(myInput.fieldNamed('newInput')?.deprecationReason, isNull);
      expect(
        myInput.fieldNamed('oldInput')?.deprecationReason,
        'No longer supported',
      );
      expect(
        myInput.fieldNamed('otherInput')?.deprecationReason,
        'Use newInput',
      );

      expect(
        query.fieldNamed('field3')?.arguments.first.deprecationReason,
        'No longer supported',
      );
      expect(
        query.fieldNamed('field4')?.arguments.first.deprecationReason,
        'Why not?',
      );
    });

    test('Supports @specifiedBy', () {
      final sdl = dedent('''
        scalar Foo @specifiedBy(url: "https://example.com/foo_spec")

        type Query {
          foo: Foo @deprecated
        }
      ''');
      expect(port.cycle(sdl), sdl);

      final schema = port.build(sdl);
      expect(
        port.assertType<ScalarType>(schema, 'Foo').specifiedByUrl,
        'https://example.com/foo_spec',
      );
    });

    test('Correctly assign AST nodes', () {
      // graphql-js compares the AST nodes; the model keeps their spans.
      final sdl = dedent('''
        schema {
          query: Query
        }

        type Query {
          testField(testArg: TestInput): TestUnion
        }

        input TestInput {
          testInputField: TestEnum
        }

        enum TestEnum {
          TEST_VALUE
        }

        union TestUnion = TestType

        interface TestInterface {
          interfaceField: String
        }

        type TestType implements TestInterface {
          interfaceField: String
        }

        scalar TestScalar

        directive @test(arg: TestScalar) on FIELD
      ''');
      final schema = port.build(sdl);
      final query = port.assertType<ObjectType>(schema, 'Query');
      final testInput = port.assertType<InputObjectType>(schema, 'TestInput');
      final testEnum = port.assertType<EnumType>(schema, 'TestEnum');
      final testInterface = port.assertType<InterfaceType>(
        schema,
        'TestInterface',
      );
      final testType = port.assertType<ObjectType>(schema, 'TestType');
      final testDirective = schema.directiveNamed('test');

      expect(
        [
          schema.span,
          query.span,
          testInput.span,
          testEnum.span,
          schema.typeNamed('TestUnion')?.span,
          testInterface.span,
          testType.span,
          schema.typeNamed('TestScalar')?.span,
          testDirective?.span,
        ].map((span) => span?.text),
        port.document(sdl).definitions.map(const Printer().print),
      );

      final testField = query.fieldNamed('testField');
      expect(
        testField?.span?.text,
        'testField(testArg: TestInput): TestUnion',
      );
      expect(testField?.arguments.first.span?.text, 'testArg: TestInput');
      expect(
        testInput.fieldNamed('testInputField')?.span?.text,
        'testInputField: TestEnum',
      );
      expect(testEnum.valueNamed('TEST_VALUE')?.span?.text, 'TEST_VALUE');
      expect(
        testInterface.fieldNamed('interfaceField')?.span?.text,
        'interfaceField: String',
      );
      expect(
        testType.fieldNamed('interfaceField')?.span?.text,
        'interfaceField: String',
      );
      expect(testDirective?.arguments.first.span?.text, 'arg: TestScalar');
    });

    test('Root operation types with custom names', () {
      final schema = port.build('''
        schema {
          query: SomeQuery
          mutation: SomeMutation
          subscription: SomeSubscription
        }
        type SomeQuery
        type SomeMutation
        type SomeSubscription
      ''');
      expect(schema.queryTypeName, 'SomeQuery');
      expect(schema.mutationTypeName, 'SomeMutation');
      expect(schema.subscriptionTypeName, 'SomeSubscription');
    });

    test('Default root operation type names', () {
      final schema = port.build('''
        type Query
        type Mutation
        type Subscription
      ''');
      expect(schema.queryTypeName, 'Query');
      expect(schema.mutationTypeName, 'Mutation');
      expect(schema.subscriptionTypeName, 'Subscription');
    });

    test('can build invalid schema', () {
      // Invalid, because it has no query root type; validateSchema
      // reports it from M3b.
      final schema = port.build('type Mutation');
      expect(schema.queryTypeName, isNull);
      expect(schema.mutationTypeName, 'Mutation');
    });

    test('Do not override standard types', () {
      // graphql-js ignores the definitions silently; they are GQL103 here,
      // and the built-ins stay.
      final result = port.buildResult('''
        scalar ID

        scalar __Schema
      ''');
      expect(port.codes(result), ['GQL103', 'GQL103']);
      final partial = switch (result) {
        BuildFailure(:final partial) => partial,
        BuildSuccess() => fail('Redefined built-ins must fail.'),
      };
      expect(partial.typeNamed('ID'), same(builtIns.typeNamed('ID')));
      expect(
        partial.typeNamed('__Schema'),
        same(builtIns.typeNamed('__Schema')),
      );
    });

    test('Allows to reference introspection types', () {
      final schema = port.build('''
        type Query {
          introspectionField: __EnumValue
        }
      ''');
      final query = port.assertType<ObjectType>(schema, 'Query');
      expect(
        query.fieldNamed('introspectionField')?.type,
        isA<NamedType>().having(
          (type) => type.name.value,
          'name',
          '__EnumValue',
        ),
      );
      expect(
        schema.typeNamed('__EnumValue'),
        same(builtIns.typeNamed('__EnumValue')),
      );
    });

    test('buildSchema parses directives on directive definitions', () {
      final schema = port.build(
        dedent('''
          type Query {
            foo: String
          }

          directive @bar @deprecated(reason: "Use another directive") on FIELD_DEFINITION
        '''),
      );
      expect(
        schema.directiveNamed('bar')?.deprecationReason,
        'Use another directive',
      );
    });

    test('Throws on unknown types', () {
      // References are names: the build succeeds and schema validation
      // reports the unknown type from M3b.
      final schema = port.build('''
        type Query {
          unknown: UnknownType
        }
      ''');
      final query = port.assertType<ObjectType>(schema, 'Query');
      expect(
        port.printType(query),
        dedent('''
          type Query {
            unknown: UnknownType
          }
        '''),
      );
      expect(schema.typeNamed('UnknownType'), isNull);
    });

    test('correctly processes viral schema', () {
      final schema = port.build(
        dedent('''
          schema {
            query: Query
          }

          type Query {
            viruses: [Virus!]
          }

          type Virus {
            name: String!
            knownMutations: [Mutation!]!
          }

          type Mutation {
            name: String!
            geneSequence: String!
          }
        '''),
      );
      expect(schema.queryTypeName, 'Query');
      expect(schema.typeNamed('Virus')?.name, 'Virus');
      expect(schema.typeNamed('Mutation')?.name, 'Mutation');
      // The viral schema has a `Mutation` type, but no mutation root.
      expect(schema.mutationTypeName, isNull);
    });
  });
}
```

- [ ] **Step 3: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/schema/build_schema_test.dart test/schema/build_schema_types_test.dart test/schema/build_schema_extensions_test.dart test/schema/build_schema_elements_test.dart)
```

Expected: `build_schema_test.dart` `+15`, `build_schema_types_test.dart` `+21`, `build_schema_extensions_test.dart` `+6`, `build_schema_elements_test.dart` `+11`, each `All tests passed!`

- [ ] **Step 4: Cover the file and see the coverage check fail**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -69,7 +69,10 @@ void main() {
     (
       path: 'mapping/schema.csv',
       prefix: '',
-      covered: const ['utilities/__tests__/printSchema-test.ts'],
+      covered: const [
+        'utilities/__tests__/buildASTSchema-test.ts',
+        'utilities/__tests__/printSchema-test.ts',
+      ],
     ),
   ];
   for (final (:path, :prefix, :covered) in tables) {
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of utilities/__tests__/buildASTSchema-test.ts`: `Actual: Set:[]`, `Which: does not contain (String, String):<(Schema Builder, can use built schema for limited execution)>`. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 5: Write the rows**

Fifty-seven rows: 35 ported, 18 adapted, 4 skipped (two need execution, M5; `Rejects invalid SDL` needs validation, M3b; `Allows to disable SDL validation` has nothing to disable).

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -38,3 +38,60 @@ utilities/__tests__/printSchema-test.ts,Type System Printer,One-line prints a sh
 utilities/__tests__/printSchema-test.ts,Type System Printer,Print Introspection Schema,adapted,test/schema/print_introspection_schema_test.dart,"graphql-js 17 prints the working-draft introspection types; the expected text is the September2025 edition, printed from a schema declaring the built-in directives and introspection types"
 utilities/__tests__/printSchema-test.ts,Type System Printer,prints viral schema correctly,ported,test/schema/print_schema_descriptions_test.dart,
 utilities/__tests__/printSchema-test.ts,Type System Printer,prints schema with description and default root operation types correctly,ported,test/schema/print_schema_descriptions_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,can use built schema for limited execution,skipped,,execution arrives in M5
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,can build a schema directly from the source,skipped,,execution arrives in M5
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Ignores non-type system definitions,adapted,test/schema/build_schema_test.dart,an operation or fragment in SDL is GQL100 instead of being ignored
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Match order of default types and directives,adapted,test/schema/build_schema_test.dart,"built-ins are shared instances of BuiltIns, never listed in a schema; the test compares the lookups"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty type,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple type,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,include standard type only if it is used,adapted,test/schema/build_schema_test.dart,every schema finds every built-in scalar; the test checks that only declared types are listed and printed
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,With directives,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Supports descriptions,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,"Maintains @include, @skip & @specifiedBy",adapted,test/schema/build_schema_test.dart,built-in directives are not listed in Schema.directives; the test checks the lookups
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Overriding directives excludes specified,adapted,test/schema/build_schema_test.dart,redefining a built-in directive is GQL103 instead of replacing it
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,"Adding directives maintains @include, @skip, @deprecated, @specifiedBy, and @oneOf",adapted,test/schema/build_schema_test.dart,built-in directives are not listed in Schema.directives; the test checks the lookups
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Type modifiers,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Recursive type,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Two types circular,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Single argument field,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple type with multiple arguments,ported,test/schema/build_schema_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty interface,adapted,test/schema/build_schema_types_test.dart,the parsed node has an empty interfaces list where graphql-js leaves the property undefined
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple type with interface,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple interface hierarchy,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty enum,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple output enum,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple input enum,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Multiple value enum,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty union,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple Union,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Multiple Union,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Can build recursive Union,adapted,test/schema/build_schema_types_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Custom Scalar,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Empty Input Object,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple Input Object,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple argument field with default,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Custom scalar argument field with default,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple type with mutation,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Simple type with subscription,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Unreferenced type implementing referenced interface,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Unreferenced interface implementing referenced interface,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Unreferenced type implementing referenced union,ported,test/schema/build_schema_types_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Supports @deprecated,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Supports @specifiedBy,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend scalar type,adapted,test/schema/build_schema_extensions_test.dart,"every applied directive is printed; the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend object type,adapted,test/schema/build_schema_extensions_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend interface type,adapted,test/schema/build_schema_extensions_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend union type,adapted,test/schema/build_schema_extensions_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend enum type,adapted,test/schema/build_schema_extensions_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly extend input object type,adapted,test/schema/build_schema_extensions_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Correctly assign AST nodes,adapted,test/schema/build_schema_elements_test.dart,the model keeps source spans instead of AST nodes; the test compares their text
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Root operation types with custom names,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Default root operation type names,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,can build invalid schema,adapted,test/schema/build_schema_elements_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Do not override standard types,adapted,test/schema/build_schema_elements_test.dart,redefining a built-in type is GQL103 instead of being ignored
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Allows to reference introspection types,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Rejects invalid SDL,skipped,,SDL validation (unknown directives) arrives with schema validation in M3b
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Allows to disable SDL validation,skipped,,"the builder never validates, so there is nothing to disable"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,buildSchema parses directives on directive definitions,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Throws on unknown types,adapted,test/schema/build_schema_elements_test.dart,"references are names, so the build succeeds; schema validation reports the unknown type from M3b"
+utilities/__tests__/buildASTSchema-test.ts,Schema Builder,correctly processes viral schema,ported,test/schema/build_schema_elements_test.dart,
```

- [ ] **Step 6: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+339: All tests passed!`

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,4 +21,4 @@
   a source excerpt.
 - `mapping/schema.csv`, the conformance table of the schema suites, checked
   by the same mapping test; `SchemaPort`, the port helpers. Ported
-  graphql-js schema suites: `printSchema-test.ts`.
+  graphql-js schema suites: `printSchema-test.ts`, `buildASTSchema-test.ts`.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/build_schema_elements_test.dart packages/typed_graphql_conformance/test/schema/build_schema_extensions_test.dart packages/typed_graphql_conformance/test/schema/build_schema_test.dart packages/typed_graphql_conformance/test/schema/build_schema_types_test.dart packages/typed_graphql_conformance/test/support/schema_port.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js schema builder suite" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 18: Port the graphql-js schema extension suite

`extendSchema-test.ts`, by the procedure of Task 16.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/mapping/schema.csv`
- Test: `packages/typed_graphql_conformance/test/mapping_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_spans_test.dart`, `packages/typed_graphql_conformance/test/schema/extend_schema_test.dart`, `packages/typed_graphql_conformance/test/support/schema_port.dart`

**Interfaces:**
- Consumes: Tasks 16–17: `SchemaPort`, `schema.csv`.
- Produces:
  - `SchemaPort.extend(Schema, String sdl)`, `extendResult(Schema, String sdl)`, `schemaChanges(Schema schema, Schema extended)`;
  - 48 rows for `extendSchema-test.ts`; `schema.csv` has 144 rows.

- [ ] **Step 1: Extend the port helper**

`extend` and `extendResult` are graphql-js's `extendSchema`; `schemaChanges` is its `expectSchemaChanges`: the definitions the extension added, printed.

In `packages/typed_graphql_conformance/test/support/schema_port.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -53,6 +53,38 @@ final class SchemaPort {
     return const SchemaBuilder().fromSdl(_document(source), source: source);
   }
 
+  /// graphql-js's `extendSchema`: [schema] extended with [sdl]; fails the
+  /// test on a diagnostic.
+  Schema extend(Schema schema, String sdl) =>
+      switch (extendResult(schema, sdl)) {
+        BuildSuccess(:final schema) => schema,
+        BuildFailure(:final diagnostics) => fail('$diagnostics'),
+      };
+
+  /// [schema] extended with [sdl], for a test that expects diagnostics.
+  BuildResult extendResult(Schema schema, String sdl) {
+    final source = Source(sdl);
+    return const SchemaBuilder().extend(
+      schema,
+      _document(source),
+      source: source,
+    );
+  }
+
+  /// graphql-js's `expectSchemaChanges`: the definitions printed for
+  /// [extended] that are not printed for [schema], each printed by the
+  /// language printer, separated by a blank line.
+  String schemaChanges(Schema schema, Schema extended) {
+    List<String> definitions(Schema schema) => [
+      for (final definition in document(print(schema)).definitions)
+        const Printer().print(definition),
+    ];
+    final before = definitions(schema).toSet();
+    return definitions(
+      extended,
+    ).where((definition) => !before.contains(definition)).join('\n\n');
+  }
+
   /// The ids of the codes of [result]'s diagnostics, such as `GQL103`.
   List<String> codes(BuildResult result) => [
     for (final diagnostic in result.diagnostics) diagnostic.code.id,
```

- [ ] **Step 2: Write the ported tests**

`extendSchema-test.ts` has 48 tests, in five files. Most are adapted for one reason: graphql-js checks `extensionASTNodes`, which this model does not keep (decision 3), so the check is dropped and the test checks what the extension added.

Create `packages/typed_graphql_conformance/test/schema/extend_schema_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// the original schema, built-ins and extensions of each kind of type.
// graphql-js also checks validateSchema; that check returns with schema
// validation in M3b.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();
  const builtIns = BuiltIns();

  group('extendSchema', () {
    test('returns the original schema when there are no type definitions', () {
      final schema = port.build('type Query');
      final result = port.extendResult(schema, '{ field }');
      // The operation is GQL100; the partial schema is the original.
      expect(port.codes(result), ['GQL100']);
      expect(
        result,
        isA<BuildFailure>().having(
          (failure) => failure.partial,
          'partial',
          same(schema),
        ),
      );
    });

    test('Do not modify built-in types and directives', () {
      final schema = port.build('''
        type Query {
          str: String
          int: Int
          float: Float
          id: ID
          bool: Boolean
        }
      ''');
      final extendedSchema = port.extend(
        schema,
        dedent('''
          extend type Query {
            foo: String
          }
        '''),
      );
      for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
        expect(
          extendedSchema.typeNamed(name),
          same(builtIns.scalarNamed(name)),
        );
      }
      expect(extendedSchema.directives, isEmpty);
      for (final directive in builtIns.directives) {
        expect(
          extendedSchema.directiveNamed(directive.name),
          same(directive),
        );
      }
    });

    test('preserves original schema config', () {
      // The model has no `extensions` bag.
      final schema = Schema(description: 'A schema description');
      final extendedSchema = port.extend(schema, 'scalar Bar');
      expect(extendedSchema.description, 'A schema description');
    });

    test('extends objects by adding new fields', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject implements AnotherInterface & SomeInterface {
          self: SomeObject
          tree: [SomeObject]!
          """Old field description."""
          oldField: String
        }

        interface SomeInterface {
          self: SomeInterface
        }

        interface AnotherInterface {
          self: SomeObject
        }
      ''');
      final extendedSchema = port.extend(
        schema,
        dedent('''
          extend type SomeObject {
            """New field description."""
            newField(arg: Boolean): String
          }
        '''),
      );
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject implements AnotherInterface & SomeInterface {
            self: SomeObject
            tree: [SomeObject]!
            """Old field description."""
            oldField: String
            """New field description."""
            newField(arg: Boolean): String
          }
        '''),
      );
    });

    test('extends objects with standard type fields', () {
      // Every schema finds every built-in scalar, whether a field uses it
      // or not.
      final schema = port.build('type Query');
      final extendedSchema = port.extend(schema, '''
        extend type Query {
          bool: Boolean
        }
      ''');
      final extendedTwiceSchema = port.extend(schema, '''
        extend type Query {
          int: Int
          float: Float
          id: ID
        }
      ''');
      for (final built in [schema, extendedSchema, extendedTwiceSchema]) {
        for (final name in ['Int', 'Float', 'String', 'Boolean', 'ID']) {
          expect(built.typeNamed(name), same(builtIns.scalarNamed(name)));
        }
      }
      expect(
        port.print(extendedTwiceSchema),
        dedent('''
          type Query {
            int: Int
            float: Float
            id: ID
          }
        '''),
      );
    });

    test('extends enums by adding new values', () {
      final schema = port.build('''
        type Query {
          someEnum(arg: SomeEnum): SomeEnum
        }

        directive @foo(arg: SomeEnum) on SCHEMA

        enum SomeEnum {
          """Old value description."""
          OLD_VALUE
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend enum SomeEnum {
          """New value description."""
          NEW_VALUE
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          enum SomeEnum {
            """Old value description."""
            OLD_VALUE
            """New value description."""
            NEW_VALUE
          }
        '''),
      );
    });

    test('extends unions by adding new types', () {
      final schema = port.build('''
        type Query {
          someUnion: SomeUnion
        }

        union SomeUnion = Foo | Biz

        type Foo { foo: String }
        type Biz { biz: String }
        type Bar { bar: String }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend union SomeUnion = Bar
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        'union SomeUnion = Foo | Biz | Bar',
      );
    });

    test('allows extension of union by adding itself', () {
      final schema = port.build('''
        union SomeUnion
      ''');
      final extendedSchema = port.extend(schema, '''
        extend union SomeUnion = SomeUnion
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        'union SomeUnion = SomeUnion',
      );
    });

    test('extends inputs by adding new fields', () {
      final schema = port.build('''
        type Query {
          someInput(arg: SomeInput): String
        }

        directive @foo(arg: SomeInput) on SCHEMA

        input SomeInput {
          """Old field description."""
          oldField: String
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend input SomeInput {
          """New field description."""
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          input SomeInput {
            """Old field description."""
            oldField: String
            """New field description."""
            newField: String
          }
        '''),
      );
    });

    test('extends scalars by adding new directives', () {
      // The model keeps no extension nodes; the directive is applied.
      final schema = port.build('''
        type Query {
          someScalar(arg: SomeScalar): SomeScalar
        }

        directive @foo(arg: SomeScalar) on SCALAR

        input FooInput {
          foo: SomeScalar
        }

        scalar SomeScalar
      ''');
      final extendedSchema = port.extend(
        schema,
        'extend scalar SomeScalar @foo',
      );
      final someScalar = port.assertType<ScalarType>(
        extendedSchema,
        'SomeScalar',
      );
      expect(
        [for (final directive in someScalar.appliedDirectives) directive.name],
        ['foo'],
      );
    });

    test('extends scalars by adding specifiedBy directive', () {
      final schema = port.build('''
        type Query {
          foo: Foo
        }

        scalar Foo

        directive @foo on SCALAR
      ''');
      final extendedSchema = port.extend(
        schema,
        dedent('''
          extend scalar Foo @foo

          extend scalar Foo @specifiedBy(url: "https://example.com/foo_spec")
        '''),
      );
      final foo = port.assertType<ScalarType>(extendedSchema, 'Foo');
      expect(foo.specifiedByUrl, 'https://example.com/foo_spec');
      expect(
        port.printType(foo),
        'scalar Foo @foo @specifiedBy(url: "https://example.com/foo_spec")',
      );
    });

    test('builds scalars with specifiedBy directive from extensions', () {
      final schema = Schema();
      final extendedSchema = port.extend(
        schema,
        dedent('''
          schema {
            query: Query
          }

          type Query {
            foo: Foo
          }

          scalar Foo

          extend scalar Foo @specifiedBy(url: "https://example.com/foo_spec")
        '''),
      );
      final foo = port.assertType<ScalarType>(extendedSchema, 'Foo');
      expect(foo.specifiedByUrl, 'https://example.com/foo_spec');
      expect(foo.span?.text, 'scalar Foo');
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/extend_schema_spans_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Adapted from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// the AST nodes of new and extended elements. The model keeps the span of
// each definition instead of its node, and no extension nodes; the texts
// are dedented, so a span's text is the definition as graphql-js prints
// its node.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('correctly assign AST nodes to new and extended types', () {
      final schema = port.build('''
        type Query

        scalar SomeScalar
        enum SomeEnum
        union SomeUnion
        input SomeInput
        type SomeObject
        interface SomeInterface

        directive @foo on SCALAR
      ''');
      final firstExtension = dedent('''
        extend type Query {
          newField(testArg: TestInput): TestEnum
        }

        extend scalar SomeScalar @foo

        extend enum SomeEnum {
          NEW_VALUE
        }

        extend union SomeUnion = SomeObject

        extend input SomeInput {
          newField: String
        }

        extend interface SomeInterface {
          newField: String
        }

        enum TestEnum {
          TEST_VALUE
        }

        input TestInput {
          testInputField: TestEnum
        }
      ''');
      final secondExtension = dedent('''
        extend type Query {
          oneMoreNewField: TestUnion
        }

        extend scalar SomeScalar @test

        extend enum SomeEnum {
          ONE_MORE_NEW_VALUE
        }

        extend union SomeUnion = TestType

        extend input SomeInput {
          oneMoreNewField: String
        }

        extend interface SomeInterface {
          oneMoreNewField: String
        }

        union TestUnion = TestType

        interface TestInterface {
          interfaceField: String
        }

        type TestType implements TestInterface {
          interfaceField: String
        }

        directive @test(arg: Int) repeatable on FIELD | SCALAR
      ''');
      final extendedSchema = port.extend(schema, firstExtension);
      final extendedTwiceSchema = port.extend(extendedSchema, secondExtension);
      final extendedInOneGoSchema = port.extend(
        schema,
        '$firstExtension\n\n$secondExtension',
      );
      expect(
        port.print(extendedInOneGoSchema),
        port.print(extendedTwiceSchema),
      );

      final query = port.assertType<ObjectType>(extendedTwiceSchema, 'Query');
      final someEnum = port.assertType<EnumType>(
        extendedTwiceSchema,
        'SomeEnum',
      );
      final someInput = port.assertType<InputObjectType>(
        extendedTwiceSchema,
        'SomeInput',
      );
      final someInterface = port.assertType<InterfaceType>(
        extendedTwiceSchema,
        'SomeInterface',
      );
      final testInput = port.assertType<InputObjectType>(
        extendedTwiceSchema,
        'TestInput',
      );
      final testEnum = port.assertType<EnumType>(
        extendedTwiceSchema,
        'TestEnum',
      );
      final testInterface = port.assertType<InterfaceType>(
        extendedTwiceSchema,
        'TestInterface',
      );
      final testType = port.assertType<ObjectType>(
        extendedTwiceSchema,
        'TestType',
      );
      final testDirective = extendedTwiceSchema.directiveNamed('test');

      expect(
        [
          testInput.span,
          testEnum.span,
          extendedTwiceSchema.typeNamed('TestUnion')?.span,
          testInterface.span,
          testType.span,
          testDirective?.span,
        ].map((span) => span?.text),
        [
          'input TestInput {\n  testInputField: TestEnum\n}',
          'enum TestEnum {\n  TEST_VALUE\n}',
          'union TestUnion = TestType',
          'interface TestInterface {\n  interfaceField: String\n}',
          'type TestType implements TestInterface {\n'
              '  interfaceField: String\n'
              '}',
          'directive @test(arg: Int) repeatable on FIELD | SCALAR',
        ],
      );

      final newField = query.fieldNamed('newField');
      expect(newField?.span?.text, 'newField(testArg: TestInput): TestEnum');
      expect(newField?.arguments.first.span?.text, 'testArg: TestInput');
      expect(
        query.fieldNamed('oneMoreNewField')?.span?.text,
        'oneMoreNewField: TestUnion',
      );
      expect(someEnum.valueNamed('NEW_VALUE')?.span?.text, 'NEW_VALUE');
      expect(
        someEnum.valueNamed('ONE_MORE_NEW_VALUE')?.span?.text,
        'ONE_MORE_NEW_VALUE',
      );
      expect(someInput.fieldNamed('newField')?.span?.text, 'newField: String');
      expect(
        someInput.fieldNamed('oneMoreNewField')?.span?.text,
        'oneMoreNewField: String',
      );
      expect(
        someInterface.fieldNamed('newField')?.span?.text,
        'newField: String',
      );
      expect(
        someInterface.fieldNamed('oneMoreNewField')?.span?.text,
        'oneMoreNewField: String',
      );
      expect(
        testInput.fieldNamed('testInputField')?.span?.text,
        'testInputField: TestEnum',
      );
      expect(testEnum.valueNamed('TEST_VALUE')?.span?.text, 'TEST_VALUE');
      expect(
        testInterface.fieldNamed('interfaceField')?.span?.text,
        'interfaceField: String',
      );
      expect(
        testType.fieldNamed('interfaceField')?.span?.text,
        'interfaceField: String',
      );
      expect(testDirective?.arguments.first.span?.text, 'arg: Int');
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// deprecation, new types and extensions of object types. graphql-js also
// checks validateSchema; that check returns with schema validation in M3b.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('builds types with deprecated fields/values', () {
      final extendedSchema = port.extend(Schema(), '''
        type SomeObject {
          deprecatedField: String @deprecated(reason: "not used anymore")
        }

        enum SomeEnum {
          DEPRECATED_VALUE @deprecated(reason: "do not use")
        }
      ''');
      final someType = port.assertType<ObjectType>(
        extendedSchema,
        'SomeObject',
      );
      expect(
        someType.fieldNamed('deprecatedField')?.deprecationReason,
        'not used anymore',
      );
      final someEnum = port.assertType<EnumType>(extendedSchema, 'SomeEnum');
      expect(
        someEnum.valueNamed('DEPRECATED_VALUE')?.deprecationReason,
        'do not use',
      );
    });

    test('extends objects with deprecated fields', () {
      final schema = port.build('type SomeObject');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject {
          deprecatedField: String @deprecated(reason: "not used anymore")
        }
      ''');
      final someType = port.assertType<ObjectType>(
        extendedSchema,
        'SomeObject',
      );
      expect(
        someType.fieldNamed('deprecatedField')?.deprecationReason,
        'not used anymore',
      );
    });

    test('extends enums with deprecated values', () {
      final schema = port.build('enum SomeEnum');
      final extendedSchema = port.extend(schema, '''
        extend enum SomeEnum {
          DEPRECATED_VALUE @deprecated(reason: "do not use")
        }
      ''');
      final someEnum = port.assertType<EnumType>(extendedSchema, 'SomeEnum');
      expect(
        someEnum.valueNamed('DEPRECATED_VALUE')?.deprecationReason,
        'do not use',
      );
    });

    test('adds new unused types', () {
      final schema = port.build('''
        type Query {
          dummy: String
        }
      ''');
      final extensionSdl = dedent('''
        type DummyUnionMember {
          someField: String
        }

        enum UnusedEnum {
          SOME_VALUE
        }

        input UnusedInput {
          someField: String
        }

        interface UnusedInterface {
          someField: String
        }

        type UnusedObject {
          someField: String
        }

        union UnusedUnion = DummyUnionMember
      ''');
      final extendedSchema = port.extend(schema, extensionSdl);
      expect(port.schemaChanges(schema, extendedSchema), extensionSdl);
    });

    test('extends objects by adding new fields with arguments', () {
      final schema = port.build('''
        type SomeObject

        type Query {
          someObject: SomeObject
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        input NewInputObj {
          field1: Int
          field2: [Float]
          field3: String!
        }

        extend type SomeObject {
          newField(arg1: String, arg2: NewInputObj!): String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject {
            newField(arg1: String, arg2: NewInputObj!): String
          }

          input NewInputObj {
            field1: Int
            field2: [Float]
            field3: String!
          }
        '''),
      );
    });

    test('extends objects by adding new fields with existing types', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject
        enum SomeEnum { VALUE }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject {
          newField(arg1: SomeEnum!): SomeEnum
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject {
            newField(arg1: SomeEnum!): SomeEnum
          }
        '''),
      );
    });

    test('extends objects by adding implemented interfaces', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject {
          foo: String
        }

        interface SomeInterface {
          foo: String
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject implements SomeInterface
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject implements SomeInterface {
            foo: String
          }
        '''),
      );
    });

    test('extends objects by including new types', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject {
          oldField: String
        }
      ''');
      final newTypesSdl = dedent('''
        enum NewEnum {
          VALUE
        }

        interface NewInterface {
          baz: String
        }

        type NewObject implements NewInterface {
          baz: String
        }

        scalar NewScalar

        union NewUnion = NewObject
      ''');
      final extendedSchema = port.extend(schema, '''
$newTypesSdl
        extend type SomeObject {
          newObject: NewObject
          newInterface: NewInterface
          newUnion: NewUnion
          newScalar: NewScalar
          newEnum: NewEnum
          newTree: [SomeObject]!
        }
      ''');
      final changes = dedent('''
        type SomeObject {
          oldField: String
          newObject: NewObject
          newInterface: NewInterface
          newUnion: NewUnion
          newScalar: NewScalar
          newEnum: NewEnum
          newTree: [SomeObject]!
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        '$changes\n\n$newTypesSdl',
      );
    });

    test('extends objects by adding implemented new interfaces', () {
      final schema = port.build('''
        type Query {
          someObject: SomeObject
        }

        type SomeObject implements OldInterface {
          oldField: String
        }

        interface OldInterface {
          oldField: String
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend type SomeObject implements NewInterface {
          newField: String
        }

        interface NewInterface {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          type SomeObject implements OldInterface & NewInterface {
            oldField: String
            newField: String
          }

          interface NewInterface {
            newField: String
          }
        '''),
      );
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart`:

```dart
import 'package:test/test.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// repeated extensions, interfaces, root types and directives. graphql-js
// also checks validateSchema; that check returns with schema validation
// in M3b.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('extends different types multiple times', () {
      final schema = port.build('''
        type Query {
          someScalar: SomeScalar
          someObject(someInput: SomeInput): SomeObject
          someInterface: SomeInterface
          someEnum: SomeEnum
          someUnion: SomeUnion
        }

        scalar SomeScalar

        type SomeObject implements SomeInterface {
          oldField: String
        }

        interface SomeInterface {
          oldField: String
        }

        enum SomeEnum {
          OLD_VALUE
        }

        union SomeUnion = SomeObject

        input SomeInput {
          oldField: String
        }
      ''');
      final newTypesSdl = dedent('''
        scalar NewScalar

        scalar AnotherNewScalar

        type NewObject {
          foo: String
        }

        type AnotherNewObject {
          foo: String
        }

        interface NewInterface {
          newField: String
        }

        interface AnotherNewInterface {
          anotherNewField: String
        }
      ''');
      final schemaWithNewTypes = port.extend(schema, newTypesSdl);
      expect(port.schemaChanges(schema, schemaWithNewTypes), newTypesSdl);

      final extendedSchema = port.extend(schemaWithNewTypes, '''
        extend scalar SomeScalar @specifiedBy(url: "http://example.com/foo_spec")

        extend type SomeObject implements NewInterface {
          newField: String
        }

        extend type SomeObject implements AnotherNewInterface {
          anotherNewField: String
        }

        extend enum SomeEnum {
          NEW_VALUE
        }

        extend enum SomeEnum {
          ANOTHER_NEW_VALUE
        }

        extend union SomeUnion = NewObject

        extend union SomeUnion = AnotherNewObject

        extend input SomeInput {
          newField: String
        }

        extend input SomeInput {
          anotherNewField: String
        }
      ''');
      final changes = dedent('''
        scalar SomeScalar @specifiedBy(url: "http://example.com/foo_spec")

        type SomeObject implements SomeInterface & NewInterface & AnotherNewInterface {
          oldField: String
          newField: String
          anotherNewField: String
        }

        enum SomeEnum {
          OLD_VALUE
          NEW_VALUE
          ANOTHER_NEW_VALUE
        }

        union SomeUnion = SomeObject | NewObject | AnotherNewObject

        input SomeInput {
          oldField: String
          newField: String
          anotherNewField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        '$changes\n\n$newTypesSdl',
      );
    });

    test('extends interfaces by adding new fields', () {
      final schema = port.build('''
        interface SomeInterface {
          oldField: String
        }

        interface AnotherInterface implements SomeInterface {
          oldField: String
        }

        type SomeObject implements SomeInterface & AnotherInterface {
          oldField: String
        }

        type Query {
          someInterface: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend interface SomeInterface {
          newField: String
        }

        extend interface AnotherInterface {
          newField: String
        }

        extend type SomeObject {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface SomeInterface {
            oldField: String
            newField: String
          }

          interface AnotherInterface implements SomeInterface {
            oldField: String
            newField: String
          }

          type SomeObject implements SomeInterface & AnotherInterface {
            oldField: String
            newField: String
          }
        '''),
      );
    });

    test('extends interfaces by adding new implemented interfaces', () {
      final schema = port.build('''
        interface SomeInterface {
          oldField: String
        }

        interface AnotherInterface implements SomeInterface {
          oldField: String
        }

        type SomeObject implements SomeInterface & AnotherInterface {
          oldField: String
        }

        type Query {
          someInterface: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        interface NewInterface {
          newField: String
        }

        extend interface AnotherInterface implements NewInterface {
          newField: String
        }

        extend type SomeObject implements NewInterface {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface AnotherInterface implements SomeInterface & NewInterface {
            oldField: String
            newField: String
          }

          type SomeObject implements SomeInterface & AnotherInterface & NewInterface {
            oldField: String
            newField: String
          }

          interface NewInterface {
            newField: String
          }
        '''),
      );
    });

    test('allows extension of interface with missing Object fields', () {
      final schema = port.build('''
        type Query {
          someInterface: SomeInterface
        }

        type SomeObject implements SomeInterface {
          oldField: SomeInterface
        }

        interface SomeInterface {
          oldField: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend interface SomeInterface {
          newField: String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface SomeInterface {
            oldField: SomeInterface
            newField: String
          }
        '''),
      );
    });

    test('extends interfaces multiple times', () {
      final schema = port.build('''
        type Query {
          someInterface: SomeInterface
        }

        interface SomeInterface {
          some: SomeInterface
        }
      ''');
      final extendedSchema = port.extend(schema, '''
        extend interface SomeInterface {
          newFieldA: Int
        }

        extend interface SomeInterface {
          newFieldB(test: Boolean): String
        }
      ''');
      expect(
        port.schemaChanges(schema, extendedSchema),
        dedent('''
          interface SomeInterface {
            some: SomeInterface
            newFieldA: Int
            newFieldB(test: Boolean): String
          }
        '''),
      );
    });

    test('may extend mutations and subscriptions', () {
      final mutationSchema = port.build('''
        type Query {
          queryField: String
        }

        type Mutation {
          mutationField: String
        }

        type Subscription {
          subscriptionField: String
        }
      ''');
      final originalPrint = port.print(mutationSchema);
      final extendedSchema = port.extend(mutationSchema, '''
        extend type Query {
          newQueryField: Int
        }

        extend type Mutation {
          newMutationField: Int
        }

        extend type Subscription {
          newSubscriptionField: Int
        }
      ''');
      expect(extendedSchema, isNot(same(mutationSchema)));
      expect(port.print(mutationSchema), originalPrint);
      expect(
        port.print(extendedSchema),
        dedent('''
          type Query {
            queryField: String
            newQueryField: Int
          }

          type Mutation {
            mutationField: String
            newMutationField: Int
          }

          type Subscription {
            subscriptionField: String
            newSubscriptionField: Int
          }
        '''),
      );
    });

    test('may extend directives with new directive', () {
      final schema = port.build('''
        type Query {
          foo: String
        }
      ''');
      final extensionSdl = dedent('''
        """New directive."""
        directive @new(enable: Boolean!, tag: String) repeatable on QUERY | FIELD
      ''');
      final extendedSchema = port.extend(schema, extensionSdl);
      expect(port.schemaChanges(schema, extendedSchema), extensionSdl);
    });
  });
}
```

Create `packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/dedent.dart';
import '../support/schema_port.dart';

// Ported from graphql-js src/utilities/__tests__/extendSchema-test.ts:
// redefinitions, root operation types and directive extensions. The model
// keeps no extension nodes, so their checks are dropped.
void main() {
  const dedent = Dedent();
  const port = SchemaPort();

  group('extendSchema', () {
    test('Throws on unknown types', () {
      // References are names: the build succeeds and schema validation
      // reports the unknown type from M3b.
      final extendedSchema = port.extend(Schema(), '''
        type Query {
          unknown: UnknownType
        }
      ''');
      expect(extendedSchema.typeNamed('Query'), isA<ObjectType>());
      expect(extendedSchema.typeNamed('UnknownType'), isNull);
    });

    test('does not allow replacing a default directive', () {
      final result = port.extendResult(Schema(), '''
        directive @include(if: Boolean!) on FIELD | FRAGMENT_SPREAD
      ''');
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.message),
        ['The built-in directive "@include" cannot be redefined.'],
      );
    });

    test('does not allow replacing an existing enum value', () {
      final schema = port.build('''
        enum SomeEnum {
          ONE
        }
      ''');
      final result = port.extendResult(schema, '''
        extend enum SomeEnum {
          ONE
        }
      ''');
      expect(result.diagnostics.map((diagnostic) => diagnostic.message), [
        'Enum value "SomeEnum.ONE" already exists in the schema. '
            'It cannot also be defined in this type extension.',
      ]);
    });

    group('can add additional root operation types', () {
      test('does not automatically include common root type names', () {
        final extendedSchema = port.extend(Schema(), 'type Mutation');
        expect(extendedSchema.typeNamed('Mutation'), isNotNull);
        expect(extendedSchema.mutationTypeName, isNull);
      });

      test('adds schema definition missing in the original schema', () {
        final schema = port.build('''
          directive @foo on SCHEMA
          type Foo
        ''');
        expect(schema.queryTypeName, isNull);

        final extensionSdl = dedent('''
          schema @foo {
            query: Foo
          }
        ''');
        final extendedSchema = port.extend(schema, extensionSdl);
        expect(extendedSchema.queryTypeName, 'Foo');
        expect(extendedSchema.span?.text, extensionSdl);
      });

      test('adds new root types via schema extension', () {
        final schema = port.build('''
          type Query
          type MutationRoot
        ''');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: MutationRoot
          }
        ''');
        expect(extendedSchema.mutationTypeName, 'MutationRoot');
      });

      test('adds directive via schema extension', () {
        final schema = port.build('''
          type Query

          directive @foo on SCHEMA
        ''');
        final extendedSchema = port.extend(schema, 'extend schema @foo');
        expect(
          [
            for (final directive in extendedSchema.appliedDirectives)
              directive.name,
          ],
          ['foo'],
        );
      });

      test('adds multiple new root types via schema extension', () {
        final schema = port.build('type Query');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: Mutation
            subscription: Subscription
          }

          type Mutation
          type Subscription
        ''');
        expect(extendedSchema.mutationTypeName, 'Mutation');
        expect(extendedSchema.subscriptionTypeName, 'Subscription');
      });

      test('applies multiple schema extensions', () {
        final schema = port.build('type Query');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: Mutation
          }
          type Mutation

          extend schema {
            subscription: Subscription
          }
          type Subscription
        ''');
        expect(extendedSchema.mutationTypeName, 'Mutation');
        expect(extendedSchema.subscriptionTypeName, 'Subscription');
      });

      test('schema extension AST are available from schema object', () {
        final schema = port.build('''
          type Query

          directive @foo on SCHEMA
        ''');
        final extendedSchema = port.extend(schema, '''
          extend schema {
            mutation: Mutation
          }
          type Mutation

          extend schema {
            subscription: Subscription
          }
          type Subscription
        ''');
        final extendedTwiceSchema = port.extend(
          extendedSchema,
          'extend schema @foo',
        );
        // What the extensions added stays; the nodes are not kept.
        expect(extendedTwiceSchema.mutationTypeName, 'Mutation');
        expect(extendedTwiceSchema.subscriptionTypeName, 'Subscription');
        expect(
          [
            for (final directive in extendedTwiceSchema.appliedDirectives)
              directive.name,
          ],
          ['foo'],
        );
      });

      test('extend directive to make it deprecated', () {
        final schema = port.build(
          'directive @isDeprecated on FIELD_DEFINITION',
        );
        final extendedSchema = port.extend(schema, '''
          extend directive @isDeprecated @deprecated(reason: "use another directive")
        ''');
        expect(
          extendedSchema.directiveNamed('isDeprecated')?.deprecationReason,
          'use another directive',
        );
      });

      test('preserves deprecated directives when extending other types', () {
        final schema = port.build(
          dedent('''
            type Query {
              foo: String
            }

            directive @isDeprecated @deprecated(reason: "use another directive") on FIELD_DEFINITION
          '''),
        );
        final extendedSchema = port.extend(
          schema,
          dedent('''
            extend type Query {
              bar: Int
            }
          '''),
        );
        expect(
          extendedSchema.directiveNamed('isDeprecated')?.deprecationReason,
          'use another directive',
        );
      });

      test('applies directive extensions defined in the same document', () {
        final schema = port.build(
          dedent('''
            directive @onDirective on DIRECTIVE_DEFINITION
            directive @someDirective on FIELD_DEFINITION

            extend directive @someDirective @onDirective
          '''),
        );
        final someDirective = schema.directiveNamed('someDirective');
        expect(
          [
            for (final directive in [...?someDirective?.appliedDirectives])
              directive.name,
          ],
          ['onDirective'],
        );
      });

      test('builds directives with deprecation from extensions', () {
        final extendedSchema = port.extend(
          Schema(),
          dedent('''
            directive @isDeprecated on FIELD_DEFINITION

            extend directive @isDeprecated @deprecated(reason: "use another directive")
          '''),
        );
        final isDeprecated = extendedSchema.directiveNamed('isDeprecated');
        expect(isDeprecated?.deprecationReason, 'use another directive');
        expect(
          isDeprecated?.span?.text,
          'directive @isDeprecated on FIELD_DEFINITION',
        );
      });

      test(
        'applies multiple directive extensions defined in the same document',
        () {
          final schema = port.build(
            dedent('''
              directive @onDirective on DIRECTIVE_DEFINITION
              directive @otherDirective on DIRECTIVE_DEFINITION
              directive @someDirective on FIELD_DEFINITION

              extend directive @someDirective @onDirective
              extend directive @someDirective @otherDirective
            '''),
          );
          final someDirective = schema.directiveNamed('someDirective');
          expect(
            [
              for (final directive in [...?someDirective?.appliedDirectives])
                directive.name,
            ],
            ['onDirective', 'otherDirective'],
          );
        },
      );

      test('extend directive without adding new directives is an error', () {
        const parser = Parser(
          options: ParserOptions(allowDirectiveExtensions: true),
        );
        final result = parser.parse(Source('extend directive @isDeprecated'));
        expect(
          result.diagnostics.map((diagnostic) => diagnostic.message),
          ['Unexpected <EOF>.'],
        );
      });
    });
  });
}
```

- [ ] **Step 3: Run the ported tests**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/schema/extend_schema_test.dart test/schema/extend_schema_spans_test.dart test/schema/extend_schema_objects_test.dart test/schema/extend_schema_interfaces_test.dart test/schema/extend_schema_roots_test.dart)
```

Expected: `extend_schema_test.dart` `+12`, `extend_schema_spans_test.dart` `+1`, `extend_schema_objects_test.dart` `+9`, `extend_schema_interfaces_test.dart` `+7`, `extend_schema_roots_test.dart` `+16`, each `All tests passed!`

- [ ] **Step 4: Cover the file and see the coverage check fail**

In `packages/typed_graphql_conformance/test/mapping_test.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -71,6 +71,7 @@ void main() {
       prefix: '',
       covered: const [
         'utilities/__tests__/buildASTSchema-test.ts',
+        'utilities/__tests__/extendSchema-test.ts',
         'utilities/__tests__/printSchema-test.ts',
       ],
     ),
```

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/mapping_test.dart)
```

Expected: FAIL in `rows cover every test of utilities/__tests__/extendSchema-test.ts`: `Actual: Set:[]`, `Which: does not contain (String, String):<(extendSchema, returns the original schema when there are no type definitions)>`. This needs `reference/` (run `tool/fetch_reference.sh` once); without it the coverage tests are skipped.

- [ ] **Step 5: Write the rows**

Forty-eight rows: 11 ported, 34 adapted, 3 skipped (execution, M5; SDL validation, M3b; nothing to disable). The table has 144 rows.

In `packages/typed_graphql_conformance/mapping/schema.csv`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -95,3 +95,51 @@ utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Allows to disable SDL
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,buildSchema parses directives on directive definitions,ported,test/schema/build_schema_elements_test.dart,
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,Throws on unknown types,adapted,test/schema/build_schema_elements_test.dart,"references are names, so the build succeeds; schema validation reports the unknown type from M3b"
 utilities/__tests__/buildASTSchema-test.ts,Schema Builder,correctly processes viral schema,ported,test/schema/build_schema_elements_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,returns the original schema when there are no type definitions,adapted,test/schema/extend_schema_test.dart,an operation in SDL is GQL100; the partial schema is the original instance
+utilities/__tests__/extendSchema-test.ts,extendSchema,can be used for limited execution,skipped,,execution arrives in M5
+utilities/__tests__/extendSchema-test.ts,extendSchema,Do not modify built-in types and directives,adapted,test/schema/extend_schema_test.dart,built-in directives are not listed in Schema.directives; the test checks the lookups
+utilities/__tests__/extendSchema-test.ts,extendSchema,preserves original schema config,adapted,test/schema/extend_schema_test.dart,the model has no extensions bag; the test checks the description
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects with standard type fields,adapted,test/schema/extend_schema_test.dart,every schema finds every built-in scalar; schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends enums by adding new values,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends unions by adding new types,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,allows extension of union by adding itself,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends inputs by adding new fields,adapted,test/schema/extend_schema_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends scalars by adding new directives,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directive; schema validation arrives in M3b; the test checks what the builder keeps"
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends scalars by adding specifiedBy directive,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; schema validation arrives in M3b; the test checks what the builder keeps"
+utilities/__tests__/extendSchema-test.ts,extendSchema,builds scalars with specifiedBy directive from extensions,adapted,test/schema/extend_schema_test.dart,"the model keeps no extension nodes, so their check is dropped; schema validation arrives in M3b; the test checks what the builder keeps"
+utilities/__tests__/extendSchema-test.ts,extendSchema,correctly assign AST nodes to new and extended types,adapted,test/schema/extend_schema_spans_test.dart,the model keeps source spans instead of AST nodes and no extension nodes; the test compares span texts
+utilities/__tests__/extendSchema-test.ts,extendSchema,builds types with deprecated fields/values,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects with deprecated fields,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends enums with deprecated values,ported,test/schema/extend_schema_objects_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,adds new unused types,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields with arguments,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding new fields with existing types,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding implemented interfaces,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by including new types,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends objects by adding implemented new interfaces,adapted,test/schema/extend_schema_objects_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends different types multiple times,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces by adding new fields,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces by adding new implemented interfaces,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,allows extension of interface with missing Object fields,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,extends interfaces multiple times,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,may extend mutations and subscriptions,ported,test/schema/extend_schema_interfaces_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema,may extend directives with new directive,adapted,test/schema/extend_schema_interfaces_test.dart,schema validation arrives in M3b; the test checks what the builder keeps
+utilities/__tests__/extendSchema-test.ts,extendSchema,Rejects invalid SDL,skipped,,SDL validation (unknown directives) arrives with schema validation in M3b
+utilities/__tests__/extendSchema-test.ts,extendSchema,Allows to disable SDL validation,skipped,,"the builder never validates, so there is nothing to disable"
+utilities/__tests__/extendSchema-test.ts,extendSchema,Throws on unknown types,adapted,test/schema/extend_schema_roots_test.dart,"references are names, so the build succeeds; schema validation reports the unknown type from M3b"
+utilities/__tests__/extendSchema-test.ts,extendSchema,does not allow replacing a default directive,adapted,test/schema/extend_schema_roots_test.dart,redefining a built-in directive is GQL103 with its own message
+utilities/__tests__/extendSchema-test.ts,extendSchema,does not allow replacing an existing enum value,ported,test/schema/extend_schema_roots_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,does not automatically include common root type names,ported,test/schema/extend_schema_roots_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,adds schema definition missing in the original schema,adapted,test/schema/extend_schema_roots_test.dart,the model keeps the span of the schema definition instead of its node
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,adds new root types via schema extension,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,adds directive via schema extension,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directive"
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,adds multiple new root types via schema extension,ported,test/schema/extend_schema_roots_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,applies multiple schema extensions,ported,test/schema/extend_schema_roots_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,schema extension AST are available from schema object,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks what the extensions added"
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,extend directive to make it deprecated,ported,test/schema/extend_schema_roots_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,preserves deprecated directives when extending other types,ported,test/schema/extend_schema_roots_test.dart,
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,applies directive extensions defined in the same document,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directive"
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,builds directives with deprecation from extensions,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped"
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,applies multiple directive extensions defined in the same document,adapted,test/schema/extend_schema_roots_test.dart,"the model keeps no extension nodes, so their check is dropped; the test checks the applied directives"
+utilities/__tests__/extendSchema-test.ts,extendSchema > can add additional root operation types,extend directive without adding new directives is an error,ported,test/schema/extend_schema_roots_test.dart,
```

- [ ] **Step 6: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+385: All tests passed!`

- [ ] **Step 7: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -21,4 +21,5 @@
   a source excerpt.
 - `mapping/schema.csv`, the conformance table of the schema suites, checked
   by the same mapping test; `SchemaPort`, the port helpers. Ported
-  graphql-js schema suites: `printSchema-test.ts`, `buildASTSchema-test.ts`.
+  graphql-js schema suites: `printSchema-test.ts`, `buildASTSchema-test.ts`,
+  `extendSchema-test.ts`.
```

- [ ] **Step 8: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 9: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/mapping/schema.csv packages/typed_graphql_conformance/test/mapping_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_interfaces_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_objects_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_roots_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_spans_test.dart packages/typed_graphql_conformance/test/schema/extend_schema_test.dart packages/typed_graphql_conformance/test/support/schema_port.dart
git commit -q -m "test(typed_graphql_conformance): port the graphql-js schema extension suite" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 19: Fuzz the SDL round trip

R10.4 and spec §11, property 1, for SDL (the introspection half is M3b's).

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`
- Test: `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`, `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart`, `packages/typed_graphql_conformance/test/fuzz/schema_round_trip_fuzz_test.dart`

**Interfaces:**
- Consumes: Tasks 5–13; M2b: `FuzzBudget`, `RandomParts`.
- Produces:
  - `RandomSchema(RandomParts parts)` with `Schema schema()`, in `test/fuzz/random_schema.dart`;
  - `const SchemaDump()` with `List<String> of(Schema schema)`, in `test/fuzz/schema_dump.dart`.

- [ ] **Step 1: Write the generator and the dump**

R10.4 and spec §11, property 1: `RandomSchema` builds a schema from M2b's `RandomParts`, and `SchemaDump` writes everything a schema holds but spans as lines, so two schemas compare with one `expect`. The generator builds only schemas that SDL can carry, so the property is exact. Each rule was found by a failing case while the plan was verified:
- names are unique per kind, with an index suffix, since a repeat is a diagnostic (Tasks 7–8);
- a schema description and schema directives only when there are root types: without roots there is no schema definition to hold them (Task 13);
- a type named `Query` is always the query root: a schema with a `Query` type and no roots prints no schema definition, and the text builds back with `Query` as root, in graphql-js too;
- members come from `List.generate`, never from a `for` loop whose condition draws a random number (it would draw again on every turn);
- an empty schema prints `''`, which is not a document (a document needs a definition), so it is compared with `Schema()` instead.

Create `packages/typed_graphql_conformance/test/fuzz/random_schema.dart`:

```dart
import 'package:typed_graphql/typed_graphql.dart';

import 'random_parts.dart';

/// Random schemas for the SDL round-trip fuzzer: every kind of type and
/// element, with names that are unique where the builder requires it and
/// never a built-in's, so the printed text builds without diagnostics.
final class RandomSchema {
  /// Draws from [parts].
  RandomSchema(this.parts);

  /// The shared random parts.
  final RandomParts parts;

  static const List<String> _locations = [
    'QUERY',
    'FIELD',
    'FRAGMENT_SPREAD',
    'SCHEMA',
    'SCALAR',
    'OBJECT',
    'FIELD_DEFINITION',
    'ARGUMENT_DEFINITION',
    'ENUM_VALUE',
    'INPUT_OBJECT',
  ];

  /// A schema of up to six types and two directive definitions. A type
  /// named `Query` is always the query root: SDL without a schema
  /// definition makes it one.
  Schema schema() {
    final types = _members(6, _type);
    final objects = [
      for (final type in types)
        if (type is ObjectType) type.name,
    ];
    final hasQuery = objects.isNotEmpty && parts.chance(80);
    final query = hasQuery && parts.chance(30) ? 'Query' : null;
    final roots = (
      query: hasQuery ? (query ?? parts.pick(objects)) : null,
      mutation: objects.isNotEmpty && parts.chance(30)
          ? parts.pick(objects)
          : null,
    );
    final hasRoots = roots.query != null || roots.mutation != null;
    return Schema(
      types: [
        if (query != null) ObjectType(query, fields: _members(2, _field)),
        ...types,
      ],
      directives: _members(2, _directive),
      queryTypeName: roots.query,
      mutationTypeName: roots.mutation,
      description: hasRoots ? _description() : null,
      appliedDirectives: hasRoots ? _applied() : const [],
    );
  }

  SchemaType _type(String name) {
    final description = _description();
    final applied = _applied();
    return switch (parts.random.nextInt(6)) {
      0 => ScalarType(
        name,
        description: description,
        appliedDirectives: applied,
      ),
      1 => ObjectType(
        name,
        description: description,
        interfaces: parts.some(2, () => NamedType(parts.name())),
        appliedDirectives: applied,
        fields: _members(3, _field),
      ),
      2 => InterfaceType(
        name,
        description: description,
        interfaces: parts.some(2, () => NamedType(parts.name())),
        appliedDirectives: applied,
        fields: _members(3, _field),
      ),
      3 => UnionType(
        name,
        description: description,
        appliedDirectives: applied,
        memberTypes: parts.some(3, () => NamedType(parts.name())),
      ),
      4 => EnumType(
        name,
        description: description,
        appliedDirectives: applied,
        values: _members(
          3,
          (name) => SchemaEnumValue(
            name,
            description: _description(),
            appliedDirectives: _applied(),
          ),
        ),
      ),
      _ => InputObjectType(
        name,
        description: description,
        appliedDirectives: applied,
        fields: _members(3, _inputValue),
      ),
    };
  }

  SchemaDirective _directive(String name) => SchemaDirective(
    name,
    description: _description(),
    arguments: _members(2, _inputValue),
    isRepeatable: parts.random.nextBool(),
    locations: parts.some(3, () => parts.pick(_locations), min: 1),
    appliedDirectives: _applied(),
  );

  SchemaField _field(String name) => SchemaField(
    name,
    parts.type(),
    description: _description(),
    arguments: _members(2, _inputValue),
    appliedDirectives: _applied(),
  );

  InputValue _inputValue(String name) => InputValue(
    name,
    parts.type(),
    description: _description(),
    defaultValue: parts.chance(40) ? parts.value(isConst: true) : null,
    appliedDirectives: _applied(),
  );

  /// Up to [max] members made by [make], each with its own name.
  List<T> _members<T>(int max, T Function(String name) make) => List.generate(
    parts.random.nextInt(max + 1),
    (index) => make(_unique(index)),
  );

  /// A random name made unique by [index]; no built-in name ends in `_`
  /// and a digit, and neither does `Query`.
  String _unique(int index) => '${parts.enumValueName().value}_$index';

  String? _description() => parts.description()?.value;

  List<AppliedDirective> _applied() => [
    for (final directive in parts.directives(isConst: true))
      AppliedDirective(directive.name.value, arguments: directive.arguments),
  ];
}
```

Create `packages/typed_graphql_conformance/test/fuzz/schema_dump.dart`:

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

/// Every part of a schema but its spans as lines of text, so two schemas
/// compare equal exactly when they hold the same elements. Type
/// references and values are written by the language [Printer]; the SDL
/// printer is what the round trip tests, so the dump does not use it.
final class SchemaDump {
  /// Creates the dump; it keeps no state.
  const SchemaDump();

  static const Printer _printer = Printer();

  /// The lines of [schema].
  List<String> of(Schema schema) => [
    'roots ${schema.queryTypeName} ${schema.mutationTypeName} '
        '${schema.subscriptionTypeName}',
    ..._described('schema', schema.description, schema.appliedDirectives),
    for (final directive in schema.directives) ..._directive(directive),
    for (final type in schema.types) ..._type(type),
  ];

  List<String> _type(SchemaType type) => [
    ..._described(
      '${type.runtimeType} ${type.name}',
      type.description,
      type.appliedDirectives,
    ),
    ...switch (type) {
      ScalarType() => const <String>[],
      ObjectType(:final interfaces, :final fields) ||
      InterfaceType(:final interfaces, :final fields) => [
        'implements ${interfaces.map(_printer.print).join(' & ')}',
        for (final field in fields) ..._field(field),
      ],
      UnionType(:final memberTypes) => [
        'members ${memberTypes.map(_printer.print).join(' | ')}',
      ],
      EnumType(:final values) => [
        for (final value in values)
          ..._described(
            'value ${value.name}',
            value.description,
            value.appliedDirectives,
          ),
      ],
      InputObjectType(:final fields) => [
        for (final field in fields) ..._inputValue(field),
      ],
    },
  ];

  List<String> _directive(SchemaDirective directive) => [
    ..._described(
      'directive ${directive.name} repeatable ${directive.isRepeatable} '
      'on ${directive.locations.join(' | ')}',
      directive.description,
      directive.appliedDirectives,
    ),
    for (final argument in directive.arguments) ..._inputValue(argument),
  ];

  List<String> _field(SchemaField field) => [
    ..._described(
      'field ${field.name}: ${_printer.print(field.type)}',
      field.description,
      field.appliedDirectives,
    ),
    for (final argument in field.arguments) ..._inputValue(argument),
  ];

  List<String> _inputValue(InputValue value) => _described(
    'input ${value.name}: ${_printer.print(value.type)} = '
    '${switch (value.defaultValue) {
      final defaultValue? => _printer.print(defaultValue),
      null => 'none',
    }}',
    value.description,
    value.appliedDirectives,
  );

  /// The [header] of an element, its description and its directives.
  List<String> _described(
    String header,
    String? description,
    List<AppliedDirective> directives,
  ) => [
    header,
    '  description ${jsonEncode(description)}',
    for (final directive in directives)
      '  @${directive.name}'
          '(${directive.arguments.map(_printer.print).join(', ')})',
  ];
}
```

- [ ] **Step 2: Write the properties**

Print, build, compare the dumps, and print again: the text must not change. A second test checks that the generator reaches every type kind, directive definitions, roots and descriptions, so it cannot quietly stop covering one. The budget is M2b's `FuzzBudget` (500 iterations in CI, `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` for more).

Create `packages/typed_graphql_conformance/test/fuzz/schema_round_trip_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';
import 'random_parts.dart';
import 'random_schema.dart';
import 'schema_dump.dart';

/// R10.4 and spec §11 of M3, property 1: a random schema, printed as SDL
/// and built again, holds the same elements, and prints the same text.
void main() {
  final budget = FuzzBudget(defaultIterations: 500);
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true, maxTokens: null),
  );
  const printer = SchemaPrinter();
  const dump = SchemaDump();

  Schema rebuilt(String text, String reason) {
    final source = Source(text);
    final document = switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
    };
    return switch (const SchemaBuilder().fromSdl(document, source: source)) {
      BuildSuccess(:final schema) => schema,
      BuildFailure(:final diagnostics) => fail('$reason\n$diagnostics'),
    };
  }

  test('print then build gives the same schema and the same text', () {
    for (var index = 0; index < budget.iterations; index++) {
      final schema = RandomSchema(
        RandomParts(budget.randomFor(index)),
      ).schema();
      final text = printer.print(schema);
      final reason = '${budget.replay(index)}\n$text';
      // An empty document is a syntax error (spec §2.2), so an empty
      // schema is checked to be one instead.
      if (text.isEmpty) {
        expect(dump.of(schema), dump.of(Schema()), reason: reason);
        continue;
      }
      final built = rebuilt(text, reason);
      expect(dump.of(built), dump.of(schema), reason: reason);
      expect(printer.print(built), text, reason: reason);
    }
  });

  test('the generator makes every kind of schema element', () {
    final kinds = <String>{};
    for (var index = 0; index < 200; index++) {
      final parts = RandomParts(Random(FuzzBudget.defaultSeed + index));
      final schema = RandomSchema(parts).schema();
      kinds.addAll([
        for (final type in schema.types) '${type.runtimeType}',
        if (schema.directives.isNotEmpty) 'directive',
        if (schema.typeNamed('Query') != null) 'Query',
        if (schema.queryTypeName != null) 'query root',
        if (schema.mutationTypeName != null) 'mutation root',
        if (schema.description != null) 'schema description',
        if (schema.appliedDirectives.isNotEmpty) 'schema directive',
        for (final line in dump.of(schema))
          if (line.contains(' = ') && !line.endsWith('= none')) 'default value',
      ]);
    }
    expect(kinds, {
      'ScalarType',
      'ObjectType',
      'InterfaceType',
      'UnionType',
      'EnumType',
      'InputObjectType',
      'directive',
      'Query',
      'query root',
      'mutation root',
      'schema description',
      'schema directive',
      'default value',
    });
  });
}
```

- [ ] **Step 3: Run the fuzzer**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/fuzz/schema_round_trip_fuzz_test.dart)
```

Expected: `+2: All tests passed!` at once: it tests Tasks 6–13. A failure is a library bug or a generator that broke a rule above: report it with the replay line, never weaken the property.

While the plan was verified, the property also held for 50 000 cases, and a printer that dropped `repeatable` failed it:

```sh
(cd packages/typed_graphql_conformance && TYPED_GRAPHQL_FUZZ_ITERATIONS=50000 dart test test/fuzz/schema_round_trip_fuzz_test.dart)
```

- [ ] **Step 4: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+387: All tests passed!`

- [ ] **Step 5: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -23,3 +23,5 @@
   by the same mapping test; `SchemaPort`, the port helpers. Ported
   graphql-js schema suites: `printSchema-test.ts`, `buildASTSchema-test.ts`,
   `extendSchema-test.ts`.
+- SDL round-trip fuzzer (R10.4): random schemas printed as SDL build back
+  to the same elements and print the same text.
```

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -45,7 +45,9 @@ A failure names its case and the `Random` seed that replays it.
 `round_trip_fuzz_test.dart` prints random documents and coordinates and
 parses them back; `hostile_text_fuzz_test.dart` feeds random and mutated
 text to every parser entry point and checks that it reports, within the
-sink limit, and never throws.
+sink limit, and never throws. `schema_round_trip_fuzz_test.dart` prints
+random schemas as SDL and builds them back: the rebuilt schema holds the
+same elements (`SchemaDump`) and prints the same text.
 
 ## License
 
```

- [ ] **Step 6: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 7: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/test/fuzz/random_schema.dart packages/typed_graphql_conformance/test/fuzz/schema_dump.dart packages/typed_graphql_conformance/test/fuzz/schema_round_trip_fuzz_test.dart
git commit -q -m "test(typed_graphql_conformance): add the SDL round-trip fuzzer" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 20: Fuzz hostile SDL

Spec §11, property 2, for SDL.

**Files:**
- Modify: `packages/typed_graphql_conformance/CHANGELOG.md`, `packages/typed_graphql_conformance/README.md`
- Test: `packages/typed_graphql_conformance/test/fuzz/hostile_sdl_fuzz_test.dart`

**Interfaces:**
- Consumes: Tasks 6–11; M2b: `FuzzBudget`, `SourceSpan.excerpt`; M1: `DiagnosticSink.defaultMaxErrors`.
- Produces:
  - `test/fuzz/hostile_sdl_fuzz_test.dart`, three tests.

- [ ] **Step 1: Write the fuzzer**

Spec §11, property 2, for SDL (the brief moves it into M3a; spec §1 has it in M3b, see "Spec deviations and findings", 7). Random texts from type-system pieces over a few names, and mutated valid SDL, are parsed and built with `fromSdl` and with `extend` onto a base schema; a text that does not parse is built from the parser's partial document, so the builder meets broken definitions too. Nothing may throw, each build gives at most `maxErrors + 1` diagnostics, and each diagnostic has an excerpt. The random texts must also reach every code from `GQL100` to `GQL110`, so the pieces cannot quietly stop covering one; and `type A` repeated 300 times must stop at the sink's limit with `GQL000`. The budget is 1 000 iterations in CI.

Create `packages/typed_graphql_conformance/test/fuzz/hostile_sdl_fuzz_test.dart`:

```dart
@TestOn('vm')
library;

import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'fuzz_budget.dart';

/// R10.4 and spec §11 of M3, property 2 for SDL: hostile type-system
/// text, built or used to extend a schema, never throws, ends, and gives
/// at most `maxErrors + 1` diagnostics, each at a place an excerpt can
/// show.
void main() {
  final budget = FuzzBudget(defaultIterations: 1000);
  const parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );
  const builder = SchemaBuilder();

  /// Definitions over a few names, so that repeats, unknown targets,
  /// kind mismatches and built-in names are common.
  const pieces = [
    '"""desc""" type A { a: String }',
    'type A { a: Int a: Int }',
    'type B implements A { a(x: Int, x: Int): A }',
    'interface A { a: String }',
    'union U = A | B',
    'enum E { A B A }',
    'input I { a: Int a: Int }',
    'scalar A',
    'scalar String',
    'scalar __Schema',
    'extend type A { b: Int }',
    'extend type Query { a: Int }',
    'extend interface A @d',
    'extend union U = Query',
    'extend enum E { A }',
    'extend input I { b: Int }',
    'extend scalar B @d',
    'extend scalar String @d',
    'extend type Missing @d',
    'directive @d on FIELD',
    'directive @d(a: Int, a: Int) on FIELD',
    'directive @skip on FIELD',
    'extend directive @d @d',
    'extend directive @include @d',
    'extend directive @missing @d',
    'schema { query: A query: B }',
    'schema { mutation: B }',
    'extend schema { query: A }',
    'extend schema @d',
    'query { a }',
    'fragment F on A { a }',
  ];

  final base = switch (builder.fromSdl(
    parser
        .parse(Source('type Query { a: String } enum E { A }'))
        .requireDocument(),
  )) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => fail('$diagnostics'),
  };

  String randomSdl(Random random) => List.generate(
    random.nextInt(30),
    (_) => pieces[random.nextInt(pieces.length)],
  ).join('\n');

  /// [text] with one to five cuts, copies and insertions.
  String mutate(Random random, String text) {
    var mutated = text;
    for (var step = random.nextInt(5); step >= 0; step--) {
      final start = random.nextInt(mutated.length + 1);
      final end = min(mutated.length, start + random.nextInt(40));
      mutated = switch (random.nextInt(3)) {
        0 => mutated.replaceRange(start, end, ''),
        1 => mutated.replaceRange(start, start, mutated.substring(start, end)),
        _ => mutated.replaceRange(
          start,
          start,
          pieces[random.nextInt(pieces.length)],
        ),
      };
    }
    return mutated;
  }

  /// The diagnostics of building [text] and of extending the base schema
  /// with it, each checked to be bounded and placed.
  List<Diagnostic> buildBoth(String text, String reason) {
    final source = Source(text);
    final document = switch (parser.parse(source)) {
      ParseSuccess(:final document) => document,
      ParseFailure(:final partial) => partial,
    };
    final results = [
      builder.fromSdl(document, source: source),
      builder.extend(base, document, source: source),
    ];
    for (final result in results) {
      expect(
        result.diagnostics.length,
        lessThanOrEqualTo(DiagnosticSink.defaultMaxErrors + 1),
        reason: reason,
      );
      for (final diagnostic in result.diagnostics) {
        expect(diagnostic.span?.excerpt, isNotNull, reason: reason);
      }
    }
    return [for (final result in results) ...result.diagnostics];
  }

  test('random definitions never throw and reach every build diagnostic', () {
    final codes = <String>{};
    for (var index = 0; index < budget.iterations; index++) {
      final text = randomSdl(budget.randomFor(index));
      final reason = '${budget.replay(index)}\n$text';
      codes.addAll([
        for (final diagnostic in buildBoth(text, reason)) diagnostic.code.id,
      ]);
    }
    expect(codes, {
      for (var id = 100; id <= 110; id++) 'GQL$id',
    });
  });

  test('mutated definitions never throw and report a bounded list', () {
    for (var index = 0; index < budget.iterations; index++) {
      final random = budget.randomFor(index);
      final text = mutate(random, randomSdl(random));
      buildBoth(text, '${budget.replay(index)}: ${text.codeUnits}');
    }
  });

  test('many repeated definitions reach the sink limit and stop there', () {
    final diagnostics = buildBoth('type A\n' * 300, 'repeats');
    expect(diagnostics, hasLength(2 * (DiagnosticSink.defaultMaxErrors + 1)));
    expect(diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
  });
}
```

- [ ] **Step 2: Run the fuzzer**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test test/fuzz/hostile_sdl_fuzz_test.dart)
```

Expected: `+3: All tests passed!` at once, since it tests finished code.

- [ ] **Step 3: Run the conformance suite**

Run:

```sh
(cd packages/typed_graphql_conformance && dart test)
```

Expected: `+390: All tests passed!`

- [ ] **Step 4: Update the documents**

In `packages/typed_graphql_conformance/CHANGELOG.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -25,3 +25,6 @@
   `extendSchema-test.ts`.
 - SDL round-trip fuzzer (R10.4): random schemas printed as SDL build back
   to the same elements and print the same text.
+- Hostile-SDL fuzzer (R10.4): random and mutated type-system text, built
+  and used to extend a schema, stays within the sink limit, reaches every
+  build diagnostic and never throws.
```

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -47,7 +47,10 @@ parses them back; `hostile_text_fuzz_test.dart` feeds random and mutated
 text to every parser entry point and checks that it reports, within the
 sink limit, and never throws. `schema_round_trip_fuzz_test.dart` prints
 random schemas as SDL and builds them back: the rebuilt schema holds the
-same elements (`SchemaDump`) and prints the same text.
+same elements (`SchemaDump`) and prints the same text;
+`hostile_sdl_fuzz_test.dart` builds random and mutated type-system text,
+and extends a schema with it, and checks that the builder reports every
+kind of problem, within the sink limit, and never throws.
 
 ## License
 
```

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add packages/typed_graphql_conformance/CHANGELOG.md packages/typed_graphql_conformance/README.md packages/typed_graphql_conformance/test/fuzz/hostile_sdl_fuzz_test.dart
git commit -q -m "test(typed_graphql_conformance): add the hostile-SDL fuzzer" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

### Task 21: Documents, full verification and the handoff

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `docs/superpowers/HANDOFF.md`, `packages/typed_graphql/README.md`, `packages/typed_graphql/lib/typed_graphql.dart`, `packages/typed_graphql_conformance/README.md`

**Interfaces:**
- Consumes: Tasks 1–20.
- Produces:
  - the status in `CLAUDE.md`, the READMEs and the barrel's library comment; the "Learned in M3a" notes;
  - the evidence that M3a is done, and a handoff that says so.

- [ ] **Step 1: Update the documents**

The core README gets a "Building and printing a schema" section. Its example was run, and the output shown is what it printed. `CLAUDE.md` gets the schema layer and "Learned in M3a".

In `CLAUDE.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -25,7 +25,10 @@ Status: under construction. M1 (foundations) delivered the workspace, the
 code rules, CI, the diagnostics model and the protocol data types. M2
 (language) delivers the syntax trees, the lexer, the parser, the printer,
 visitors and transformers, schema coordinates, source excerpts, every
-graphql-js language suite and the language fuzzers.
+graphql-js language suite and the language fuzzers. M3a (schema core)
+delivers the schema model, SDL building and extension, the SDL printer,
+scalar codecs, the graphql-js schema builder, extension and printer suites
+and the SDL fuzzers.
 
 ## Documents
 
@@ -303,6 +306,15 @@ Learned in M2b:
   opens that extension's body, as in graphql-js: a shorthand query can
   only come first.
 
+Learned in M3a:
+- `Definition` is abstract, not sealed: a `switch` statement over it needs
+  no `default`, and a `default` would swallow kinds added later. Name every
+  case.
+- A `for` condition is evaluated on every pass: `i < random.nextInt(n)`
+  draws a new bound each time. Draw the count once (`List.generate`).
+- An empty document is a syntax error (spec §2.2), so an empty schema
+  prints text that does not build back; a round trip treats it apart.
+
 **Dart style the lints do not check.** Acronyms longer than two letters are
 words (`Json`, `Sse`); doc comments start with a one-sentence summary and
 refer to identifiers in `[brackets]`; a boolean property starts with
@@ -361,6 +373,7 @@ fails when it finds none.
 - Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`
   and `mapping/schema.csv`, checked by `test/mapping_test.dart` there; port
   helpers in its `test/support/` (`SchemaPort` for the schema suites).
-- Fuzzers: `packages/typed_graphql_conformance/test/fuzz/`;
-  `TYPED_GRAPHQL_FUZZ_ITERATIONS` and `TYPED_GRAPHQL_FUZZ_SEED` tune them.
+- Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
+  round trip, hostile SDL); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
+  `TYPED_GRAPHQL_FUZZ_SEED` tune them.
 - CI: `.github/workflows/ci.yml`.
```

In `README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -58,8 +58,9 @@ void main() {
 ```
 
 > **Status: under construction.** Nothing is published to pub.dev yet, and
-> every API may change before 0.1.0. Stage M2 (language) is done: the
-> parser, the printer and visitors are in; the type system (M3) comes next.
+> every API may change before 0.1.0. Stage M2 (language) is done, and
+> M3a brings the schema: building it from SDL, extending and printing it.
+> Schema validation and introspection (M3b) come next.
 
 ## Table of contents
 
@@ -100,13 +101,13 @@ This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.
 
 | Package | Role | Status |
 |---|---|---|
-| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language (M1, M2) |
+| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL and scalar codecs (M1, M2, M3a) |
 | [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
 | [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
 | [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
 | [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
 | [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
-| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language suites and fuzzers (M2) |
+| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language and schema suites, fuzzers (M2, M3a) |
 
 ## Install
 
````

In `packages/typed_graphql/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

````diff
@@ -12,8 +12,10 @@ web (dart2js and dart2wasm). Part of
 
 > **Status: under construction.** This release has the diagnostics model, the
 > protocol data types, and the language: syntax trees, the lexer, the
-> parser, the printer, visitors and schema coordinates. The type system
-> arrives in M3 and validation in M4 (see the
+> parser, the printer, visitors and schema coordinates; and the schema:
+> its model, building and extending it from SDL, printing it, and scalar
+> codecs. Schema validation and introspection arrive in M3b, and document
+> validation in M4 (see the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).
 
 ## Contents
@@ -21,6 +23,7 @@ web (dart2js and dart2wasm). Part of
 - [Install](#install)
 - [Parsing and printing](#parsing-and-printing)
 - [Visiting and rewriting](#visiting-and-rewriting)
+- [Building and printing a schema](#building-and-printing-a-schema)
 - [Reading the wire format](#reading-the-wire-format)
 - [Diagnostics](#diagnostics)
 - [License](#license)
@@ -176,6 +179,93 @@ hero.graphql:2:12
 3 | }
 ```
 
+## Building and printing a schema
+
+`SchemaBuilder().fromSdl(document, source:)` builds a `Schema` from SDL,
+every `extend` included, and `extend(schema, document, source:)` adds a
+document to an existing schema. Both return a sealed `BuildResult`: a
+`BuildSuccess`, or a `BuildFailure` with every problem as a diagnostic and
+the schema built from the rest. The built-in scalars, directives and
+introspection types are in every schema without being listed.
+`SchemaPrinter` prints a schema as graphql-js's `printSchema` does, and
+`ScalarCodecs` holds the codecs that turn JSON into scalar values and back.
+
+```dart
+import 'package:typed_graphql/typed_graphql.dart';
+
+void main() {
+  const parser = Parser();
+  const builder = SchemaBuilder();
+  const printer = SchemaPrinter();
+
+  final source = Source('''
+type Query {
+  hero(episode: Episode = JEDI): Character
+}
+
+enum Episode { NEWHOPE EMPIRE JEDI }
+
+interface Character {
+  name: String!
+}
+
+extend enum Episode { ROGUE_ONE @deprecated(reason: "Not a saga film.") }
+''', name: 'schema.graphql');
+  final schema = switch (builder.fromSdl(
+    parser.parse(source).requireDocument(),
+    source: source,
+  )) {
+    BuildSuccess(:final schema) => schema,
+    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
+  };
+  print(printer.print(schema));
+
+  if (schema.typeNamed('Episode') case EnumType(:final values)) {
+    for (final value in values) {
+      print('${value.name}: ${value.deprecationReason ?? 'current'}');
+    }
+  }
+
+  // Every problem is a diagnostic with a code and a place.
+  final extension = Source('extend type Droid { id: ID }', name: 'more.graphql');
+  final result = builder.extend(
+    schema,
+    parser.parse(extension).requireDocument(),
+    source: extension,
+  );
+  result.diagnostics.forEach(print);
+
+  // Scalar codecs turn JSON values into Dart values and back.
+  final codecs = ScalarCodecs();
+  print(codecs.codecFor('Int')?.decode(JsonNumber(42.0)));
+}
+```
+
+It prints:
+
+```text
+type Query {
+  hero(episode: Episode = JEDI): Character
+}
+
+enum Episode {
+  NEWHOPE
+  EMPIRE
+  JEDI
+  ROGUE_ONE @deprecated(reason: "Not a saga film.")
+}
+
+interface Character {
+  name: String!
+}
+NEWHOPE: current
+EMPIRE: current
+JEDI: current
+ROGUE_ONE: Not a saga film.
+more.graphql:1:13: error GQL109: Cannot extend type "Droid" because it is not defined.
+DecodeSuccess(42)
+```
+
 ## Reading the wire format
 
 Bad input never throws. `JsonReader` turns text into a `JsonValue`, a sealed
@@ -225,7 +315,8 @@ is an `ExecutionResult` (it has `data`, maybe `null`) or a
 
 ## Diagnostics
 
-The parser reports through this model, and the validator will:
+The parser and the schema builder report through this model, and the
+validator will:
 
 - `Source` is a document and its name; `locationOf(offset)` gives a 1-based
   line and column, counted in UTF-16 code units.
````

In `packages/typed_graphql_conformance/README.md`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -9,7 +9,8 @@
 > **Status: under construction.** Stage M2 of the
 > [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)
 > ports every graphql-js language suite and adds the language fuzzers;
-> nothing is exported.
+> M3a ports the graphql-js schema builder, extension and printer suites
+> and adds the SDL fuzzers. Nothing is exported.
 
 ## Ported suites
 
```

In `packages/typed_graphql/lib/typed_graphql.dart`, apply this change (a unified diff: `-` lines go, `+` lines come, the others are context):

```diff
@@ -2,8 +2,9 @@
 /// wire protocol, with diagnostics instead of exceptions.
 ///
 /// Under construction: this release has the diagnostics model, the protocol
-/// data types, and the language (syntax trees, lexer, parser, printer,
-/// visitors, transformers and schema coordinates).
+/// data types, the language (syntax trees, lexer, parser, printer,
+/// visitors, transformers and schema coordinates) and the schema (model,
+/// SDL building, extension and printing, scalar codecs).
 library;
 
 export 'src/diagnostics/diagnostic.dart';
```

- [ ] **Step 2: Run every suite the way CI does**

```sh
dart pub get
dart format --output=none --set-exit-if-changed packages test
dart analyze --fatal-infos
dart test
for p in packages/*/; do (cd "$p" && dart test) || exit 1; done
(cd packages/typed_graphql && dart test --compiler exe)
(cd packages/typed_graphql && dart test -p chrome --compiler dart2js)
(cd packages/typed_graphql && dart test -p chrome --compiler dart2wasm)
(cd packages/typed_graphql_conformance && dart test --compiler exe)
(cd packages/typed_graphql && dart pub publish --dry-run)
```

Expected:
- format and analyze are clean;
- the root suite gives `+34`, the core `+557` on the VM and as exe, and the five skeleton packages `+2` each;
- the conformance package gives `+390` on the VM and as exe, with `reference/` fetched;
- the core gives `+545` in Chrome with each compiler (the VM-only tests are not counted there);
- the publish dry run ends with `Package has 0 warnings.`

- [ ] **Step 3: Check that the schema layer stays pure**

Run: `grep -rln "dart:io" packages/typed_graphql/lib || echo "no dart:io"`

Expected: `no dart:io` (R0.6). `layers_test.dart` passed in Step 2, so `schema/` imports only `diagnostics/`, `language/` and itself.

- [ ] **Step 4: Record the result in the handoff**

In `docs/superpowers/HANDOFF.md`:
- set the line that starts with `Last updated:` to the first line below;
- add the second line as a table row after the row that starts with `| M2 Language |`.

Leave everything else as it is.

```markdown
Last updated: 2026-10-14 (M3a implemented, final review pending). Read this
```

```markdown
| M3 Type system | [spec](specs/2026-10-14-m3-type-system-design.md) | M3a: [plan](plans/2026-10-14-m3a-schema-core.md) | M3a implemented on its branch, final review pending; then the M3b plan (validation, introspection) |
```

- [ ] **Step 5: Run the green check**

Run the commands of "The green check".

Expected: format changes 0 files, analyze prints `No issues found!`, and every suite ends with `All tests passed!`.

- [ ] **Step 6: Commit**

```sh
git add CLAUDE.md README.md docs/superpowers/HANDOFF.md packages/typed_graphql/README.md packages/typed_graphql/lib/typed_graphql.dart packages/typed_graphql_conformance/README.md
git commit -q -m "docs: record the M3a schema core" \
  -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Requirement coverage

| Id | Requirement (verbatim from `docs/requirements.md`) | Where |
|---|---|---|
| R0.2 | No `dynamic` and no `Map<String, dynamic>` in any public signature; arbitrary JSON is `JsonValue` / `JsonObject` | Tasks 14–15: codecs and `LiteralConverter` take and give `JsonValue`; the lints and the code rules in every green check |
| R0.3 | Bad input (documents, schemas, variables, responses) never throws: results are sealed types carrying every diagnostic. Exceptions only for programmer errors and inside user resolvers | Tasks 6–11 (`BuildResult`, `GQL100`–`GQL110`), Tasks 14–15 (`DecodeFailure`), Task 20 (hostile SDL) |
| R0.6 | The core package is pure Dart: no `dart:io`, no dependencies except `meta`; it compiles with dart2js and dart2wasm | `layers_test.dart` in every green check; Task 21, Steps 2–3 |
| R0.7 | Spec conformance is measured with ported graphql-js v17 suites and a coverage mapping table | Tasks 16–18: `mapping/schema.csv`, 144 rows over three graphql-js files |
| R2.1 | Immutable `Schema` model with a sealed `NamedType` family; type references by name; no resolvers in the model | Tasks 1, 2, 5 (the family is `SchemaType`: finding 1) |
| R2.2 | SDL → `Schema`, including every kind of `extend` | Tasks 6–11; Tasks 17–18 |
| R2.5 | `Schema` → SDL printer | Tasks 12–13; Tasks 16, 19 |
| R2.6 | Built-in scalars with exact coercion boundaries and built-in directives `@skip @include @deprecated @specifiedBy @oneOf`; `@defer` / `@stream` opt-in | Task 4 (built-ins), Task 5 (lookups, opt-in), Task 7 (no redefinition), Task 14 (boundaries) |
| R2.9 | `ScalarCodec<T>` shared by server and client; literals go through a JSON-like value | Tasks 14–15 |
| R10.2 | Size-limit ratchet and core layer-direction tests | Every green check; the allowlists stay empty |
| R10.3 | `typed_graphql_conformance` with ported graphql-js suites and a coverage mapping table | Tasks 16–18 |
| R10.4 | Parse → print → parse fuzzing | Task 19 (SDL round trip), Task 20 (hostile SDL) |

R2.3, R2.4, R2.7 and R2.8 (validation, `ValidSchema`, introspection, coordinate resolution) are M3b's (spec §1).

## Open questions

Each has the plan's choice; the plan runs as written unless the user decides otherwise.

1. **Keep the `Schema*` names?** `SchemaType`, `SchemaField`, `SchemaEnumValue` and `SchemaDirective` avoid a clash with the language nodes the barrel already exports (finding 1). The alternative, the spec's names, needs a prefix import wherever both layers meet, which is every builder file and most user code. Recommended: keep them, and correct spec §3.
2. **Print every applied directive?** The plan prints them all (decision 6); graphql-js prints only `@deprecated`, `@specifiedBy` and `@oneOf`. Keeping them makes the SDL round trip exact and the printed SDL the schema the server has. Recommended: keep.
3. **List the built-ins in `Schema.types`?** The plan finds them through `typeNamed` without listing them (decision 2). Introspection (M3b) needs them listed in `__Schema.types`, which `Schema.toIntrospection()` can add itself. Recommended: keep them out of the list.
4. **Keep extension spans?** The model has no extension nodes (decision 3); each member keeps its own span. `SchemaDiff` (M13) or an editor integration may want the span of the `extend` itself. Recommended: add it when a consumer needs it.
5. **`encode` throws?** `ScalarCodec.encode` throws `ArgumentError` for a value the type cannot hold (decision 8), on the reasoning that only code produces output values. The executor (M5) will have to turn that into a field error. Recommended: keep, and revisit in the M5 spec.

## Self-review

- **Spec coverage.** Every item of the M3a row of the spec's section 1 has a task: the model (Tasks 1, 2, 5), built-ins (Task 4), SDL to `Schema` with every `extend` and the extension of a schema (Tasks 3, 6–11), `Schema` to SDL (Tasks 12–13), `ScalarCodec` (Tasks 14–15), `mapping/schema.csv` with the `schemaPrinter`, `buildASTSchema` and `extendSchema` ports (Tasks 16–18), the SDL round-trip fuzzer (Task 19), and, beyond the row, the hostile-SDL fuzzer (Task 20).
- **Verified code.** Every code block was applied, task by task, to a copy of `main` at `302b1e6`, and every one of the 21 commits passed the green check. Each TDD task was seen failing before its implementation with the message quoted in its "see them fail" step, and passing after with the count quoted; Tasks 16–18 were seen failing on the coverage check with an empty table. The core tests also passed with `--compiler exe` (`+557`) and in Chrome with dart2js and dart2wasm (`+545` each); the conformance suite passed with `--compiler exe` (`+390`). `dart pub publish --dry-run` gave 0 warnings.
- **Code rules.** 34 new `lib/` files; the largest has 292 lines (`built_in_sdl.dart`, mostly SDL text), the next 204 (`type_extender.dart`). The longest new method has about 30 lines (`UniqueDefinitions.types`). The largest test file has 358 lines (`extend_schema_interfaces_test.dart`). No allowlist entry, no `// ignore:`, no top-level function besides `main`, and no `dynamic`.
- **Names and types.** The names in each task's "Interfaces" match the code in its steps, and later tasks use the same names.
- **No placeholders.** Every file is given whole or as a diff that was applied.

## Execution handoff

Two ways to run this plan:

1. **Subagent-driven (recommended).** Dispatch a fresh `implementer` subagent (model `sonnet`) for each task, then a `reviewer` subagent (model `sonnet`) on that task. A final whole-branch review with model `opus` comes at the end. Use superpowers:subagent-driven-development. Tasks 6–11 grow one `SchemaAssembly` and its collaborators through diffs that depend on each other's internal names, which the "Interfaces" blocks pin, and a fresh reviewer per task catches drift early.
2. **Native.** Run the tasks in this session with superpowers:executing-plans, with a checkpoint after Tasks 5, 11, 15 and 18.

Work on a branch `m3a-schema-core` in a worktree, from `main` at `302b1e6`. Fetch `reference/` once (`tool/fetch_reference.sh`). Do not push, tag or publish without the user's yes.
