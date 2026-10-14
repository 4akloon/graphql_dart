# CLAUDE.md

Guidance for working in this repository. It is binding for people and agents.

## Project

`typed_graphql` is a from-scratch GraphQL implementation for Dart: the whole
specification (September2025 edition) and its protocols, fully typed on the
server and the client. It is a Dart pub workspace of pure-Dart packages:

| Package | Role | Stage |
|---|---|---|
| `packages/typed_graphql` | Core: `diagnostics/`, `language/`, `protocol/`, `schema/`, `validation/`; depends only on `meta` | M1–M4 |
| `packages/typed_graphql_server` | Typed schema builder, executor, request pipeline, transport handlers | M5–M7 |
| `packages/typed_graphql_shelf` | `shelf` adapter (HTTP, WebSocket, GraphiQL in development) | M7 |
| `packages/typed_graphql_client` | Client runtime: links, transports, normalized cache | M11–M12 |
| `packages/typed_graphql_codegen` | Code generation engine and CLI, without `analyzer` | M8, M10 |
| `packages/typed_graphql_builder` | `build_runner` builders; the only `analyzer` user | M9 |
| `packages/typed_graphql_conformance` | `publish_to: none`: ported graphql-js suites, fuzzers, benchmarks | M2 on |

Minimum SDK: Dart 3.13 (`sdk: ^3.13.0`) in every package and in generated
code. No dependency on `package:gql` or its ecosystem.

Status: under construction. M1 (foundations) delivered the workspace, the
code rules, CI, the diagnostics model and the protocol data types. M2
(language) delivers the syntax trees, the lexer, the parser, the printer,
visitors and transformers, schema coordinates, source excerpts, every
graphql-js language suite and the language fuzzers. M3a (schema core)
delivers the schema model, SDL building and extension, the SDL printer,
scalar codecs, the graphql-js schema builder, extension and printer suites
and the SDL fuzzers. M3c (core documentation) delivers the guides, the
example and the dartdoc categories.

## Documents

- `docs/requirements.md` - requirements R0–R11; quote their ids in specs,
  plans and tests.
- `docs/roadmap.md` - stages M1–M16 and the rules for plans.
- `docs/superpowers/specs/2026-10-13-typed-graphql-design.md` - the
  architecture; a stage spec refines it, never overrides it silently.
- `docs/superpowers/plans/` - one plan per stage; `HANDOFF.md` - where the
  work stands and the rules the user set. Read it first in a new session.
- `docs/research/` - the research and the decisions log (`README.md`).
- `reference/` (git-ignored) - the specifications, protocols and graphql-js;
  fetch them with `tool/fetch_reference.sh`. Never edit it.

## Commands

```sh
dart pub get                                                  # repo root, once and after pubspec edits
dart format --output=none --set-exit-if-changed packages test # must change 0 files
dart analyze --fatal-infos                                    # repo root; must print "No issues found!"
dart test                                                     # repo root: the code rules
cd packages/typed_graphql && dart test                        # one package (every package has tests)
cd packages/typed_graphql && dart test --compiler exe         # AOT (sealed switches, sdk#56010)
cd packages/typed_graphql && dart test -p chrome --compiler dart2js
cd packages/typed_graphql && dart test -p chrome --compiler dart2wasm
cd packages/typed_graphql && dart test test/doc               # snippets, links, category tags
cd packages/typed_graphql && dart doc                         # must report "Found 0 warnings and 0 errors"
cd packages/<package> && dart pub publish --dry-run           # never without --dry-run
```

Git commands run from the repo root. Commits are Conventional Commits with the
package as the scope: `feat(typed_graphql): ...`, `test(workspace): ...`,
`ci: ...`, `docs: ...`, `refactor(...)`.

## Architecture

**Core layers.** `packages/typed_graphql/lib/src/` has one folder per layer,
lowest first: `diagnostics`, `language`, `protocol`, `schema`, `validation`. A
library imports only its own layer and the layers before it; the core imports
no platform library but `dart:async`, `dart:collection`, `dart:convert`,
`dart:core`, `dart:math`, `dart:typed_data`, and no package but `meta`.
`test/quality/layers_test.dart` enforces this (R0.6, R10.2). Libraries in
`lib/src/` import each other with relative paths, never through the barrel.

**Diagnostics** (`diagnostics/`).
- `Source(body, name:)` holds a document; `locationOf(offset)` gives a
  1-based `SourceLocation` (column in UTF-16 code units). The table of line
  starts is built on the first call. `\r\n`, `\n` and `\r` end a line.
- `SourceSpan(source, start, end)` is a range of offsets; a diagnostic points
  at one. `SourceSpan.excerpt` (`SourceExcerpt`) shows its start in its
  lines with a caret, as graphql-js's `printSourceLocation`.
- `DiagnosticCode` is the catalog: one enum value per problem, id `GQLnxx`,
  a doc comment that says when it is reported. Ids are public API: never
  renumber, reuse or remove one. Ranges: `GQL0xx` syntax, `GQL1xx` type
  system, `GQL2xx` operation validation, `GQL3xx` coercion and execution,
  `GQL4xx` transports, `GQL5xx` code generation; `GQL000` is the sink limit.
- `Diagnostic(code, severity, message, span:, related:)`; equal when all
  five are, so tests compare lists of diagnostics.
- `DiagnosticSink` collects diagnostics in report order and stops after
  `maxErrors` errors (default 100) with one `GQL000`. Lexer, parser and rules
  take a sink through their constructor; the public API turns it into a
  sealed result.

**Language** (`language/`; M2).
- `ast/`: every node extends `Node` (`start`, `end`, `children` in
  graphql-js key order, `withChildren`, `isEquivalentTo`). Leaves are
  `const`; a node with a list copies it with `List.unmodifiable`. A node
  overrides `rebuildFrom(ChildReader)` for `withChildren`; the two
  type-system families delegate it to a `*_rebuilder.dart` (size limit).
  `scalars` lists what `isEquivalentTo` compares besides children.
- `lexer/`: `Token` (`kind`, `start`, `end`, `value`) and `TokenKind`, whose
  `description` is how messages name it. `BlockString` holds the spec's
  `BlockStringValue` and graphql-js's printing rules; lexer and printer share
  it. `Lexer(source, sink).advance()` never throws: bad text becomes one
  `error` token over the run and one diagnostic, with graphql-js's message
  minus "Syntax Error: ". `maxTokens` is counted here (R1.6). Scanners
  (`*_scanner.dart`) share a `SourceReader` (text, `describe`, `report`);
  `CharacterClass` holds the character tests. `SchemaCoordinateLexer`
  lexes a schema coordinate: names, `.`, `(`, `)`, `:`, `@` and no
  ignored tokens; any other character is a `GQL001` (`GQL002` for a lone
  surrogate) "Invalid character". `TokenKind.dot` exists for it only. Both
  lexers implement `TokenSource`, which the parser reads.
- `parser/`: `Parser(options:)` is const and stateless; each call builds a
  `TokenCursor` (current token, one lookahead, graphql-js's `expect*`,
  `many`, `any`, `delimitedMany`, `nested` for `maxDepth`) and grammar
  collaborators (`*_parser.dart`) over it. A syntax error is reported by
  `TokenCursor.fail`, which throws the internal `SyntaxAbort`; it never
  leaves `Parser`. The cursor is silent at error tokens (the lexer
  reported them) and at an offset that already has a diagnostic.
  `Recovery` resynchronises (R1.5): `Parser.parse` drops a failed
  definition and skips to the next definition keyword or description, or to
  a `{` that follows a `}` or starts the document; `SelectionParser` drops a failed selection and skips to a name, `...` or
  `}`; both only at the bracket `balance` where the failed part started,
  and always consume a token. A selection set left empty fails too.
  Type-system definitions and extensions share `TypeMemberParser`.
  `DefinitionGrammar` is the internal extension point for working-draft and
  experimental productions (R1.4): `DefinitionParser` asks each registered
  grammar before the base ones. `DirectiveExtensionGrammar` is always
  registered; with `allowDirectiveExtensions` off, it and the directive
  definition's draft parts report `GQL014` instead of a generic error.
  `Parser.parseSchemaCoordinate` runs `SchemaCoordinateParser` over a
  cursor on a `SchemaCoordinateLexer` (the cursor reads any
  `TokenSource`); `ParserOptions` do not apply to it. A directive
  definition's locations are checked against `DirectiveLocation`
  (`ast/directive_location.dart`), whose `spelling` is the SDL name.
- `printer/`: `Printer` prints any node as graphql-js's `print` does, to
  the character (80-column wrapping included), through collaborators:
  `ValuePrinter` (values, types, arguments, directives), `ExecutablePrinter`,
  `TypeMemberPrinter`, `TypeSystemPrinter`, `ExtensionPrinter`, over the
  `PrintLayout` combinators (`join`, `wrap`, `indent`, `block`) and
  `QuotedString`. An empty selection set prints as `{}`.
  `Printer(isMinified: true)` passes the canonical text through `Minifier`
  (graphql-js's `stripIgnoredCharacters`: a space only between two
  non-punctuators or before `...`, block strings in their shortest form).
  A `SchemaCoordinate` prints the same in both forms and never goes
  through `Minifier`, whose document lexer would reject its `.`.
- `visitor/`: `AstWalker().walk(root, visitor)` walks depth-first through
  `children` with its own stack (no recursion), calling
  `AstVisitor.enter` (returns `VisitAction.next`, `skip` or `stop`) and
  `leave`; a skipped node is not left, a stop leaves nothing.
  `ParallelVisitor` keeps a skip or stop state per visitor, as graphql-js's
  `visitInParallel`; it is stateful, so use one per walk.
  `AstTransformer.transform` rewrites bottom-up, also without recursion:
  `rewrite(node)` sees rewritten children and returns the node, a
  replacement or null (removed); the parent is rebuilt with
  `withChildren`, so removing a required child is a `StateError`.

**Protocol** (`protocol/`).
- `JsonValue` is a sealed family (`JsonNull`, `JsonBool`, `JsonNumber`,
  `JsonString`, `JsonArray`, `JsonObject`): the type of arbitrary JSON in
  every public signature (R0.2). Values compare by value; `1` equals `1.0`;
  `JsonNumber.asInt` is the safe-integer view.
- `JsonReader` turns untrusted text or `jsonDecode` output into a
  `JsonValue`, or a `DecodeFailure` with a path (non-finite numbers, too deep
  nesting, non-JSON objects).
- `DecodeResult<T>` = `DecodeSuccess<T>(value)` | `DecodeFailure(message,
  path:)`; `inside(segment)` prefixes the path. `PathSegment` =
  `PathKey(name)` | `PathIndex(index)`.
- `GraphQLError`, `GraphQLRequest` and `ResponsePayload` (`ExecutionResult` |
  `RequestErrorResult`) read with a static `decode(JsonValue)` and write with
  `toJson()`; equality is equality of their JSON.

**Schema** (`schema/`; M3). Imports `diagnostics`, `language` and
`protocol`.
- `model/`: the immutable schema model (R2.1). Its elements are
  `SchemaField`, `InputValue` (arguments and input fields),
  `SchemaEnumValue`, `SchemaDirective` and `AppliedDirective`; the spec's
  names `FieldDefinition`, `EnumValueDefinition`, `DirectiveDefinition` and
  `NamedType` already name language nodes, so the schema's take a
  `Schema` prefix. `SchemaType` is the sealed family of named types
  (`ScalarType`, `ObjectType`, `InterfaceType`, `UnionType`, `EnumType`,
  `InputObjectType`). Types are language `TypeRef` nodes (implemented
  interfaces and union members `NamedType` nodes), resolved by name;
  defaults and directive arguments are constant language `Value` nodes.
  Every element has `SourceSpan? span`. `deprecationReason`,
  `specifiedByUrl` and `isOneOf` read the applied directives through the
  internal `AppliedDirectives`; the directives stay in the element's list.
  Elements compare by identity. `SchemaDirective.locations` are
  `DirectiveLocation` values; a code-built node with another spelling is an
  `ArgumentError` in the reader.
- `build/BuiltIns` (const): the five built-in scalars, the five specified
  directives, `defer` and `stream` (graphql-js's definitions, not in the
  specified five) and the introspection types, read once from the internal
  `BuiltInSdl` text of September2025 Appendix D; they have no span.
- `Schema` (`schema.dart`) lists only what was declared; `typeNamed` and
  `directiveNamed` fall back to `BuiltIns` (`defer` and `stream` only with
  `includesDeferAndStream`). Roots are names (`queryTypeName`, ...,
  `rootTypeName(OperationType)`).
- `build/SchemaBuilder` (const, `includesDeferAndStream`): `fromSdl(document,
  source:)` returns the sealed `BuildResult` (`BuildSuccess(schema)` |
  `BuildFailure(partial, diagnostics)`). A run sorts the definitions
  (`DocumentDefinitions`), assembles them (`SchemaAssembly`) and reports into
  a `BuildReport`, which orders the errors by node offset before a
  `DiagnosticSink` limits them. Without `source` every span is null.
- Construction problems use graphql-js's SDL-rule messages; a repeat points
  at its name and relates to the span of the definition it repeats; the
  first definition wins (`UniqueDefinitions`). `MemberFilter` drops repeated
  members and arguments from syntax nodes with `withChildren` before the
  readers see them. `SchemaDefinitionReader` applies the schema definition
  and `extend schema`; default roots fill only the operations that no schema
  definition or extension names, and only without a schema definition.
  `TypeExtender` appends an extension's members, interfaces, union members
  and directives after the type's own, in document order, and keeps the
  definition's span; the extensions of one type are grouped and applied in
  one pass, so N extensions cost linear time.
  `extend(schema, document, source:)` is the same run over a base schema,
  without default roots; a member the base already has is "already exists in
  the schema" (no related span). `DirectiveExtender` applies
  `extend directive`.
- `print/SchemaPrinter` (const): graphql-js's `printSchema` layout through
  `TypePrinter` (a type or directive definition) and `MemberPrinter`
  (descriptions, member blocks, arguments, applied directives); values and
  types go through the language `Printer`. Unlike graphql-js it prints
  every applied directive as written. The schema block is printed when the
  schema has roots and either a description, applied directives, a root with
  another name than its operation's default, or a non-root type named
  `Query`, `Mutation` or `Subscription` (stricter than graphql-js, so the
  printed SDL builds back to the same roots). `includesBuiltIns` prints, in
  order: built-in directives, own directives, built-in scalars, own types,
  introspection types.
- `scalars/`: `ScalarCodec<T>` (`decode(JsonValue)` → `DecodeResult<T>`,
  never throws; `encode(T)` → `JsonValue`, an `ArgumentError` for a value the
  type cannot hold) and the five built-in codecs with graphql-js's messages.
  A codec is not a field of `ScalarType` (R2.9): `ScalarCodecs` maps names to
  codecs (`withCodec` gives a new registry; built-ins cannot be replaced).
  `LiteralConverter` turns a constant `Value` into the `JsonValue` a codec
  decodes (an enum value becomes its name), so codecs have no
  `parseLiteral`.

**Error model.** Bad input never throws (R0.3): it becomes diagnostics or a
`DecodeFailure` in a sealed result. Exceptions are for programmer errors only:
`ArgumentError`, `RangeError`, `StateError`.

## Code rules

The rules follow typed_openapi's (R10.1). `analysis_options.yaml` is adapted
from typed_openapi's: its comments are this repo's own, and it additionally
enables `simple_directive_paths`, `no_dynamic_casts` and `no_raw_types`, and
the analyzer's `strict-inference` and `strict-raw-types` (write `<Object?>[]`
where a literal has no context type).
The workspace suite in `test/quality/` (run `dart test` at the root) enforces
what a lint cannot (R10.2).

**Limits** (all lines count, comments and blanks included: use `wc -l`):

| Unit | Limit | Checked by |
|---|---|---|
| File in `lib/` or `bin/` | 300 lines | ratchet, allowlist may only shrink |
| File in `test/` or `tool/` | 500 lines | ratchet |
| Method, getter, operator, constructor in `lib/` | 40 lines | ratchet |
| Parameters of a method in `lib/` | 5 (constructors exempt) | rule |
| Nesting of `if`/`for`/`while`/`switch`/`try` | 3 levels | rule |
| Public types per file in `lib/` | one public class or sealed family | rule |

Allowed by no exception: `part` files, top-level functions other than
`main`, `utils`/`helpers`/`common`/`misc` files in `lib/`, `dynamic`, a
`catch` without `on`. Permanently exempt from the size limit: the catalog
`diagnostics/diagnostic_code.dart`. Nothing else is exempt; the allowlists in
`test/quality/code_rules_test.dart` start empty and stay so.

**Before you write.** Run `wc -l` on the file you are about to extend. If the
change would take it past the limit, extract first, in its own commit.

**How to decompose.** Split by responsibility into collaborator classes, one
per file, in the layer folder. A helper made public to leave a file stays out
of the barrel unless it is API. No hidden state passed through fields: pass a
parameter or a small immutable object. Do not abstract for a future need.

**Readability.** Names say what a thing is or does; no abbreviations, no
`Helper`/`Manager`/`Impl`. Booleans read as a state (`isFull`, `hasErrors`).
A comment says why (a spec section, a requirement id, a trap), never what.
Prefer a `switch` over a sealed type or a record to `is` chains; no `!` where
a pattern can promote; no `late` without a comment on why it is set before it
is read.

**Dart 3.13.** Use primary constructors, dot shorthands, null-aware elements
(`'key': ?value`), patterns, records, sealed and `final` classes. Learned in
M1:
- `public_member_api_docs` reports an undocumented primary constructor: give
  the class a body with a documented `this;`.
- `@immutable` only on a class whose constructors can all be `const`, or
  `prefer_const_constructors_in_immutables` fires; subclasses inherit it.
- A non-late field initializer can read a non-declaring parameter
  (`final List<T> items = List.unmodifiable(items);`); a `late` one cannot.
- `==` of a generic class checks `is C<Object?>`, not `is C<T>`, or two equal
  values with different static types differ.
- In tests, `expect` arguments have no context type: write full names, not
  dot shorthands.

Learned in M2a:
- An empty `case` in a `switch` statement falls through to the next case;
  to skip an item, test it with `if (...) continue;` before the `switch`.
- `prefer_interpolation_to_compose_strings` rejects `+` on strings; use
  interpolation, or adjacent literals for a long text.
- A multi-line literal drops a line break right after its opening quotes;
  write `'\n'` in front when the text must start with one.
- An overriding method may widen a parameter type: a node class outside the
  library overrides `rebuildFrom(Object? read)` without the internal
  `ChildReader`.

Learned in M2b:
- Recursion over a syntax tree overflows the stack on the web long before
  the VM; walk deep structures with an explicit stack.
- A cascade cannot stand in a branch of `?:`: `c ? [...]..sort() : x` does
  not parse. Write an `if` with two returns.
- In a document, `{` after a body-less type extension (`extend enum E @d`)
  opens that extension's body, as in graphql-js: a shorthand query can
  only come first.

Learned in M3a:
- `Definition` is abstract, not sealed: a `switch` statement over it needs
  no `default`, and a `default` would swallow kinds added later. Name every
  case.
- A `for` condition is evaluated on every pass: `i < random.nextInt(n)`
  draws a new bound each time. Draw the count once (`List.generate`).
- An empty document is a syntax error (spec §2.2), so an empty schema
  prints text that does not build back; a round trip treats it apart.

**Dart style the lints do not check.** Acronyms longer than two letters are
words (`Json`, `Sse`); doc comments start with a one-sentence summary and
refer to identifiers in `[brackets]`; a boolean property starts with
"Whether"; never silence a lint (`// ignore:` is not used); no nullable
`Future`, `Stream` or collection return; never catch `Error`.

**Tests.** Tests come in the same commit as the code; a new branch of logic
has a test that fails without it. A test names the behaviour and checks one
thing. Tests that need `dart:io` start with `@TestOn('vm')`, because the core
suite also runs in Chrome. Every package keeps at least one test: `dart test`
fails when it finds none.

**Documentation.** A program in a guide is a fence tagged `dart`: complete
(imports and `main`), formatted by `dart format`, followed by a line ending
in `It prints:` and a `text` fence with its exact output; a fragment or a
signature is a `text` fence. A guide has no relative link (dartdoc breaks
it) and names another guide by its topic. Every exported public type has
`/// {@category <folder>}` in its doc comment (`schema/scalars/` is
`scalars`); a new exported folder needs its category in
`dartdoc_options.yaml` and its guide. `dart doc` reports 0 warnings. A stage
that adds API adds its section to the guide of its layer in the same commit.

**Self-review before saying "done".**
1. `wc -l` of every file touched, and the longest method added.
2. Could a new reader say in one sentence what each new class and method is
   for? If not, rename or split.
3. Is there code, a parameter or a flag nothing uses yet? Remove it.
4. Format, analyze and every affected suite are clean, and `CLAUDE.md`,
   `docs/` and the package `CHANGELOG.md` say what changed.

## Design rules

- **Nothing is guessed silently.** Every problem in user input is a
  diagnostic with a stable code and a place, or a `DecodeFailure` with a
  path.
- **A new diagnostic code** goes into `DiagnosticCode` in id order, with a
  doc comment, in the commit that first reports it.
- **No `dynamic`, no `Map<String, dynamic>`** in a public signature;
  arbitrary JSON is `JsonValue`.
- **The core stays pure Dart** and runs on the VM, AOT, dart2js and
  dart2wasm. `analyzer` is used only by `typed_graphql_builder`.
- **Dependencies arrive with the stage that first uses them.** M1 declares
  only workspace packages, `meta`, `test` and `lints`.
- **Conformance is measured.** A ported graphql-js test is recorded in the
  conformance mapping table in the same commit (from M2).
- **Deterministic output.** Printers and generators sort what they emit and
  never iterate a hash-ordered collection.

## Process

- One stage = one design spec and one plan in `docs/superpowers/`. Plans hold
  all the code, checked before they are written; tasks are TDD, one commit
  each, and every task leaves the tree green.
- Repository text is English. User-facing changes go into the package's
  `CHANGELOG.md` (`## 0.0.1 - Unreleased`, `- **Breaking:** ...` for breaking
  entries).
- Outward actions (pushing, tags, publishing, issues, PRs) need the user's
  explicit yes. `dart pub publish` runs only with `--dry-run`.

## Where things are

- Code rules suite: `test/quality/` at the workspace root (`code_rules.dart`
  and its scanners).
- Core layer test: `packages/typed_graphql/test/quality/layers_test.dart`.
- Guides: `packages/typed_graphql/doc/*.md`, tied to the dartdoc categories
  by `packages/typed_graphql/dartdoc_options.yaml`; the example is
  `packages/typed_graphql/example/example.dart`. The documentation suite is
  `packages/typed_graphql/test/doc/`.
- Diagnostic catalog: `packages/typed_graphql/lib/src/diagnostics/diagnostic_code.dart`.
- Conformance mapping tables: `packages/typed_graphql_conformance/mapping/language.csv`
  and `mapping/schema.csv`, checked by `test/mapping_test.dart` there; port
  helpers in its `test/support/` (`SchemaPort` for the schema suites).
- Fuzzers: `packages/typed_graphql_conformance/test/fuzz/` (language, SDL
  round trip, hostile SDL); `TYPED_GRAPHQL_FUZZ_ITERATIONS` and
  `TYPED_GRAPHQL_FUZZ_SEED` tune them.
- CI: `.github/workflows/ci.yml`.
