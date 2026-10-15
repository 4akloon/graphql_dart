# M10 Client code generation: stage design

Status: written for the owner's review 2026-10-15 (the open questions are at
the end) and updated after the implementation: the final diagnostic numbering
(`GQL500`-`GQL511`, section 9), the deviations and decisions taken while
implementing and by the review rulings (section 16) and open questions 7-12
(section 17). Every decision below was checked by implementing the four plans
on the branch `m10-final`, one commit per plan task, with every suite green on
the VM. Refines section 6 "Client" of
[the architecture](2026-10-13-typed-graphql-design.md) and never overrides it
silently; deviations are listed in section 16. Requirements: R0.2, R0.3,
R0.5, R7.1–R7.10, R10.2, R11.1–R11.3 ([requirements](../../requirements.md)).

## 1. Scope and delivery

M10 builds `packages/typed_graphql_codegen` (the engine and its CLI) and the
small runtime contract the generated code compiles against. One spec, **four
plans**, each merged after the one before it and each leaving the tree green:

| Plan | Content |
|---|---|
| **M10a** Front end | The dependencies; `CodegenConfig` read from `typed_graphql.yaml` (R7.1); `SchemaLoader` (SDL or an introspection result, validated); `ProjectDocuments`, the project's documents as one fragment graph with every diagnostic at `file:line:col` (R7.2); the codegen validation rules; `ClientGenerator.check`; `GQL500`–`GQL506` |
| **M10b** Runtime and schema types | `Optional<T>` in the core (`protocol/`); the generated-code contract in `typed_graphql_client` (`GraphQLOperation`, `OperationDocument`, `DataCodec` and its kinds, `DataContext`, `DataObject`, `DataEquality`); the emitter base (`DartWriter`, `DartNames`, `Imports`); enums (R7.6), input objects with `@oneOf` (R7.7), scalar mapping (R7.8); the schema-types library; the name checks (`GQL507`, `GQL508`); the golden harness and the analysis test (R7.10) |
| **M10c** Operations and fragments | The selection planner (field collection, variants, fragment accessors, conditions); data, fragment and polymorphic classes (R7.3–R7.5); variables classes (R7.7); operation classes with their metadata (R7.9: minified document with `__typename`, name, sha256); the persisted-operations manifest; the naming checks of operations and fragments (`GQL507`), the subscription-root and introspection checks (`GQL504`), the class limit (`GQL511`); `JsonMerger` in the client; goldens |
| **M10d** CLI and documentation | `bin/typed_graphql_codegen.dart` with `generate` and `check`, schema from an introspection URL, output writing (`GQL509`, `GQL510`); the Client Code Generation guide, the example, the README, `docs/discovery.md`, `llms.txt`, `CLAUDE.md`, the handoff |

Out of scope: `@defer` / `@stream` in client documents (R7.13, M14: reported
as unsupported, section 9), cache selection metadata (R7.11, M12; the planner
already holds what it needs, section 15), dangerous-change warnings (R7.12,
M13), the `build_runner` builder (R7.10's builder half, M9), `@catch` and
test data builders (R7.14, later), fragment arguments (roadmap "Later").

## 2. Packages and layering

| Package | M10 adds | May import |
|---|---|---|
| `typed_graphql` | `Optional<T>` (`protocol/optional.dart`); the `GQL5xx` codes | unchanged (R0.6) |
| `typed_graphql_client` | `lib/src/operation/`: what generated code compiles against (section 8) | the core; no new package |
| `typed_graphql_codegen` | the engine (`lib/src/config/`, `schema/`, `documents/`, `plan/`, `emit/`, `generator/`) and the CLI (`lib/src/cli/`, `bin/`) | the core; `yaml`, `crypto`, `path` in the engine; `args`, `glob` and `dart:io` only in `cli/` |

- **The engine has no `dart:io`.** Its input is text keyed by path, its output
  is text keyed by path. The CLI (M10d) and the `build_runner` builder (M9)
  are two thin readers and writers around it, so R7.10's "the CLI and
  `build_runner` produce identical files" holds by construction. A test
  checks that no library under `lib/src/` outside `cli/` imports `dart:io`,
  and that the barrel reaches no `dart:io`: the CLI classes are not exported
  (`bin/` and the tests import `src/cli/`), so M9's builder and any non-VM
  user can import the engine.
- **No `analyzer`, no `dart_style`** (R6.5; `dart_style` depends on
  `analyzer`). The emitter lays the code out itself (section 7).
- **Generated code imports** the core and `typed_graphql_client`, both with
  a prefix (`as graphql`, `as client`), so a schema type named `Field`,
  `Source` or `Optional` never collides with a runtime name; the only
  reserved names are those of `dart:core` the generated code uses
  (`GQL508`, section 9). The schema-types library and the libraries of
  spread fragments are imported without a prefix (their names are checked
  project-wide, `GQL507`/`GQL508`); custom scalar libraries as `scalar_<n>`.
  `client` and `graphql` are reserved member names, so a field cannot shadow
  a prefix.
- **`Optional<T>` lives in the core** because the server (R4.4, M5) and the
  client (R7.7) share it: a sealed `Optional<T>` = `Present<T>(value)` |
  `Absent<T>()`, value equality, `const Optional.absent()` and
  `const Optional.present(value)` (open question 1).

## 3. Configuration (M10a; R7.1)

`typed_graphql.yaml`, next to `pubspec.yaml`; every path is relative to the
file and written with `/`:

```yaml
schema: schema.graphql            # SDL, an introspection result (.json) or a URL
documents:                        # globs; default lib/**.graphql
  - lib/**.graphql
schema_types: lib/schema.graphql.dart   # enums and input objects; this is the default
persisted_operations: build/persisted_operations.json   # optional
scalars:                          # optional
  DateTime:
    type: DateTime                                  # a dart:core type
    codec: package:my_app/codecs.dart#DateTimeCodec # a const ScalarCodec<DateTime>
  Money:
    type: package:my_app/money.dart#Money
    codec: package:my_app/codecs.dart#MoneyCodec
headers:                          # optional, only with a URL schema
  Authorization: Bearer ${GITHUB_TOKEN}
```

`CodegenConfig.parse(text, path:)` returns the sealed `ConfigResult`
(`ConfigSuccess(config)` | `ConfigFailure(diagnostics)`). The YAML is read
with `package:yaml`; a diagnostic points at the YAML node through the
node's offsets (`Source(yamlText, name: path)`). Problems: YAML syntax
(`GQL500`), a missing required key, a value of the wrong kind, an unknown
key, a malformed `type` or `codec` reference, an absolute path or one with
`..` (`GQL501`). `${NAME}` in a header value is read from the environment by
the CLI, never by the engine, and a missing variable is `GQL501`.

## 4. Schema loading (M10a)

`SchemaLoader.load(SchemaText)` takes the schema's path and text. A path
ending in `.json` is an introspection result (`JsonReader`, then the `data`
member if the object has one, then `SchemaBuilder.fromIntrospection`);
anything else is SDL (`Parser`, `SchemaBuilder.fromSdl` with the source, so
diagnostics point into the file). The schema is then validated
(`SchemaValidator`); the result is `ValidSchema` or the diagnostics. Errors
in the JSON itself are `GQL502` with the JSON path. A URL is fetched by the
CLI (section 12), which hands the engine the response text as `<url>.json`.

## 5. Documents, the fragment graph and validation (M10a; R7.2)

`ProjectDocuments.read(files)` parses each `.graphql` file with its own
`Source(text, name: path)`, so a syntax error is reported at `file:line:col`.
A file with a syntax error stops the run after every file was parsed (its
fragments would be missing, and every spread of them would be a second,
misleading error).

The fragment graph is the whole project: the files, sorted by path, are
concatenated into one document (each text followed by a line break) whose
`Source` is the project, and a `ProjectSourceMap` maps an offset of the
project back to its file and the offset in it. The concatenation is parsed
once more (it parses: two documents that parse alone parse together, since
each ends at a token boundary and the added line break ends a trailing
comment), with `maxTokens` off (each file was already counted). The core
`DocumentValidator` then validates the project document with
`ClientGenerator.rules`: `DocumentValidator.specifiedRules` without
`NoUnusedFragmentsRule` (a fragment may exist only for the application's own
reads) and `LoneAnonymousOperationRule` (operations must be named anyway),
plus `NamedOperationsRule` (`GQL503`) and `UnsupportedDirectivesRule`
(`GQL504`, `@defer` and `@stream` until M14), `UnsupportedIntrospectionRule`
(`GQL504` at a `__schema` or `__type` field: the generator has no classes for
the introspection types yet; `__typename` stays supported) and
`SubscriptionRootRule` (`GQL504`, section 6). A file with no tokens (empty,
only whitespace, commas or comments) adds nothing; a project of only such
files is `GQL506` as for no files. Each diagnostic's span and
related spans are translated through the map, so every message carries the
file's name, line and column (`lib/user.graphql:3:5: error GQL205: ...`).
Uniqueness of operation and fragment names is therefore project-wide, which
is also what the generated libraries need (they import each other).

No step recurses over a document: parsing is the core's, validation is the
core's one walk, and the codegen rules are `AstVisitor`s.

## 6. The selection model (M10c; R7.3–R7.5)

The planner turns each operation and fragment into a tree of **shapes**,
with an explicit work stack (no recursion over the document):

- **Field collection.** A shape is the fields of one or more selection sets
  (the field nodes of one response name are merged, as the spec's
  `CollectFields` merges them) on a parent type. Fields written directly and
  in inline fragments count; a fragment spread does not add its fields, it
  adds a **fragment accessor** (masking by shape, R7.4): `data.user.fragments
  .userCard` is the fragment's own class, decoded from the same JSON object.
- **Applicability.** On an object type every inline fragment and spread
  applies (validation guarantees the overlap). On an interface or union `P`,
  a condition `C` applies to the base only when `C` is `P` itself or an
  interface `P` implements; any other condition narrows to the possible
  types of both, even when it covers every possible type of `P` today
  (deviation 8: robust to a union member or implementer added later). A
  selection on an abstract type without narrowings is a plain class.
- **Variants** (R7.5). A shape on an abstract type is a sealed class: the
  base fields (and accessors) are getters of the sealed class; each concrete
  type that some narrowing condition reaches is one variant with the base
  fields merged with every narrowing that applies to it; the mandatory
  `…Unknown` variant holds `typename` and the base fields, and is chosen
  for every other `__typename`, known to the schema or not.
- **Merged sub-shapes.** The base declares a field (or the fragment
  accessor holder) only when every variant selects it with the same nodes,
  so its class is the same in every variant. When a variant re-selects a
  field with more subfields or more spreads, the field is not on the base
  and every variant, `…Unknown` included, has its own class for it
  (deviation 7: a class with `==` may not be implemented,
  `avoid_implementing_value_types`).
- **Class sharing and the limit.** Each operation and fragment is planned
  once. A nested class whose named type, list of selection nodes (by
  identity) and conditions equal those of a class planned before reuses
  that class's name. Planning stops at 10000 classes per operation or
  fragment with `GQL511` at its name, so a document whose unshared variant
  fields would give R^depth classes ends fast.
- **Nullability.** A field's Dart type follows its schema type; a field
  under `@skip` or `@include` (on itself or on an enclosing inline fragment)
  is nullable, and absent in the JSON means null. A conditional fragment
  spread is a nullable accessor whose condition is evaluated at decode time
  from the operation's variables (`DataContext`, section 8), with the
  variable's default when it was not given (the data class passes the
  operation's Boolean variable defaults to `DataContext`, read by
  `flag(name)`; a fragment's standalone `decode` has no defaults, the
  operation passes its own).
- **`__typename`.** The operation's document gets an unaliased `__typename`
  at the end of every field's selection set that lacks an unconditional
  one, so every polymorphic object can be told apart; a `__typename` under
  `@include` or `@skip` does not count, and is itself a nullable member. The
  root gets it only when a spread (direct or inside an inline fragment) of a
  fragment that plans as a sealed base sits at the root of a query or
  mutation; at the root of a subscription that case is `GQL504` at the
  spread (a subscription root may not select an introspection field), and
  an inline fragment alone is fine. An anonymous subscription is only
  `GQL503`. `__typename` the user selected unconditionally is the field
  `typename`.

## 7. Generated code (M10b, M10c)

**Files.** For each document `lib/a/user.graphql`, one standalone library
`lib/a/user.graphql.dart` (never a `part`, R6.1's rule for clients too) with
its operations and fragments; one schema-types library (`schema_types`) with
the enums and input objects the project uses, pruned to what the operations'
selections and variables reach. A library imports the libraries of the
fragments it spreads and the schema-types library, by relative path, only
when it uses them. Output is deterministic (R7.10): declarations in document
order, schema types sorted by name, imports sorted, no hash order anywhere.

**Layout.** The header is `// GENERATED CODE - DO NOT MODIFY BY HAND.`,
`// Generated by typed_graphql_codegen from <path>.` and
`// dart format off`, so a project's `dart format` leaves the file alone.
`DartWriter` writes two-space blocks and, like the formatter, puts an
argument or parameter list on one line when it fits in 80 columns and one
item per line with a trailing comma otherwise. The code passes
`dart analyze --fatal-infos` with this repository's lints plus
`strict-casts`, as library code (`public_member_api_docs` included: every
public declaration has a doc comment, from the schema description when
there is one).

**Names** (open question 2). An operation `GetUser` gives `GetUserQuery`
(`…Mutation`, `…Subscription`), `GetUserData` and `GetUserVariables`; a
fragment `UserCard` gives `UserCard`; a nested shape is its parent's name
followed by the capitalised Dart name of the response name
(`GetUserDataUserFriends`); a variant appends the type name
(`GetUserDataNodeUser`, `GetUserDataNodeUnknown`); an accessor holder
appends `Fragments`. A Dart member name is the response name in
lowerCamelCase (`user_name` → `userName`), `__typename` is `typename`,
another leading underscore becomes `$` (`_id` → `$id`), and a Dart reserved
word or a member every class has (`hashCode`, `toString`, `toJson`,
`fragments`, ...) gets a `$` suffix (`default$`); GraphQL names cannot
contain `$`, so these never collide with another field. Two declarations
that still end with one name are `GQL507`, at the second selection, with
the first as related; so are two enum values or input fields that map to one
Dart member, and two documents that would write one file. A name that hides
a `dart:core` type the code uses is `GQL508`. Names are never changed to
avoid a collision.

**Data classes** (R7.3). `final class` (or a `sealed` base with `final`
variants), `const` constructor with named parameters, `final` fields,
`==`, `hashCode` (lists compared by `DataEquality`), `toString`, and
`toJson()` that writes the response names, the `__typename` the document
asked for and the accessors' fields, so `decode(toJson())` gives an equal
value; when a class spreads fragments, `toJson` merges their JSON with
`client.JsonMerger` (objects by key recursively, lists by index; a later
`null` never replaces a value), since a class and a fragment may select one
response name with different subfields. Each class declares its own private
codecs, so a class is self-contained. Each top-level class (operation data,
fragment) has
`static DecodeResult<X> decode(JsonObject json, {JsonObject variables})`,
which never throws (R0.3), and `static const DataCodec<X> codec` for the
libraries that spread it.

**Enums** (R7.6; open question 3). The typed_openapi pattern the
architecture names: `sealed class Status implements DataEnum` with
`factory Status.parse(String raw)`, `enum StatusKnown implements Status`
(one value per GraphQL value, lowerCamelCase, `$` for reserved words, the
GraphQL name in `raw`, `@Deprecated` from `@deprecated`) and
`final class StatusUnknown(raw) implements Status`. `parse` loops over
`StatusKnown.values`: a `switch` naming a deprecated value trips
`deprecated_member_use_from_same_package`; `@Deprecated` goes only on enum
values, and a deprecated field says so in its doc comment. A `switch` over a
`Status` is exhaustive and still compiles when the server adds a value.

**Input objects and variables** (R7.7). A `final class` per input object
the variables reach, with named parameters: a non-null field without a
default is `required T`; a nullable field, or one with a default, is
`Optional<T?>` (`Optional<T>` for a non-null one with a default), defaulting
to `const Optional.absent()`, so absence and `null` stay apart only where
the spec tells them apart. A `@oneOf` input object is a sealed class with
one variant per field (`SearchByName(String name)`), so exactly one field
is set by construction. `GetUserVariables` follows the same rules over the
operation's variable definitions and is omitted when there are none.
`toJson()` writes only present values. Input objects also get a reader, so
their codecs are symmetric and the goldens check a round trip.

**Scalars** (R7.8). `String`, `ID` → `String`; `Int` → `int`; `Float` →
`double`; `Boolean` → `bool`, through the core's codecs. A custom scalar in
`scalars:` is the configured Dart type through `const <Codec>()` (a
`ScalarCodec<T>` with a const constructor); an unmapped custom scalar is
`graphql.JsonValue`, never `dynamic`. A mapping for a scalar the schema does
not have is `GQL505`.

**Operation classes and metadata** (R7.9). `final class GetUserQuery
extends client.GraphQLQuery<GetUserData>` (mutation and subscription
alike) holds the variables and exposes `static const OperationDocument
document` (name, the minified document with `__typename` and every fragment
it uses, sorted by name after the operation, and its sha256 in lowercase
hex), `variablesJson`, and `decodeData(JsonObject)` returning a
`DecodeResult<GetUserData>`. The persisted-operations manifest, when
configured, is Apollo's `apollo-persisted-query-manifest` format (version
1): `{"format": ..., "version": 1, "operations": [{"id", "name", "type",
"body"}]}`, operations sorted by name (open question 4).

## 8. The runtime contract (`typed_graphql_client`, M10b)

What generated code compiles against; M11 builds the client on it:

| Type | Role |
|---|---|
| `GraphQLOperation<D>` (`GraphQLQuery`, `GraphQLMutation`, `GraphQLSubscription`) | `document`, `variablesJson`, `decodeData`, `toRequest()` → core `GraphQLRequest`; the three subclasses let `client.query` accept only queries (R8.1) |
| `OperationDocument` | const: `name`, `type` (`OperationType`), `text`, `sha256` |
| `DataCodec<T>` | `read(json, context)` / `write(value)`; `field(object, key, context)`; `decode(json, context)` → `DecodeResult<T>`; kinds `ScalarDataCodec`, `JsonDataCodec`, `EnumDataCodec`, `ObjectDataCodec`, `NullableDataCodec`, `ListDataCodec` |
| `DataFormatException` | internal: thrown by `read` on a bad value with its path, caught by `decode`; never leaves a public decode (R0.3) |
| `DataContext` | the operation's variables (defaults applied) for conditional fragment spreads |
| `DataObject`, `DataEnum` | what `toJson` writes for objects and enums |
| `DataEquality` | deep `==` and `hashCode` of nested lists |

## 9. Diagnostics

| Code | Name | When |
|---|---|---|
| `GQL500` | `configSyntax` | `typed_graphql.yaml` is not YAML |
| `GQL501` | `invalidConfig` | a missing, unknown or mistyped key or reference in the configuration |
| `GQL502` | `invalidSchemaInput` | the schema file is not a schema: not JSON, no `__schema`, or unreadable |
| `GQL503` | `anonymousOperation` | an operation without a name |
| `GQL504` | `unsupportedInDocument` | `@defer`, `@stream`, a `__schema` or `__type` field, or a spread of a fragment that plans as a sealed base at a subscription root |
| `GQL505` | `unknownScalarMapping` | `scalars:` names a scalar the schema does not have |
| `GQL506` | `noDocuments` | no file matches `documents`, or every match is empty (a warning) |
| `GQL507` | `generatedNameCollision` | two generated declarations, two members of one class (enum values and input fields included) or two generated files with one Dart name or path |
| `GQL508` | `reservedTypeName` | a generated type name that is a `dart:core` name the code uses |
| `GQL509` | `outputOutdated` | `check`: a generated file is missing or differs from what `generate` would write |
| `GQL510` | `inputUnreadable` | the CLI cannot read or write a file, list the documents or fetch the schema URL |
| `GQL511` | `tooManyGeneratedClasses` | an operation or fragment would generate more than 10000 classes |

The ids are final and public API once released: the first draft of this
table numbered `noDocuments` `GQL508` and the name codes `GQL506`/`GQL507`;
`GQL511` was added by the M10c review and lands after `GQL509`/`GQL510` in
time, but the catalog stays in id order. Name problems are limited like
every other run (`DiagnosticSink`, `GQL000` after 100 errors).

Syntax, schema and validation problems keep their core codes (`GQL0xx`,
`GQL1xx`, `GQL2xx`).

## 10. Hostile input and limits (R0.3)

- Nothing the engine reads throws: configuration, schema, documents and
  responses become diagnostics or `DecodeFailure`s. A bug is the only way
  to an exception; the tests feed the engine broken YAML, broken JSON,
  every syntax error class and invalid documents.
- Documents keep the parser's `maxDepth` (128) and `maxTokens` (15000) per
  file; validation keeps its step budget (`GQL230`). The planner's work is
  linear in the document with each spread fragment planned once per
  spreading shape (a fragment's own class is planned once, its accessors
  never re-plan it); variants are bounded by the possible types, equal
  nested classes are shared, and an operation or fragment stops at 10000
  classes (`GQL511`).
- No recursion over documents or shapes: the planner and the emitter use
  explicit stacks. Generated decoders nest one call per selection level,
  bounded by the document's depth (128).
- Deterministic output: inputs sorted by path, declarations in document
  order, schema types and imports sorted, the manifest sorted by name.
  The same input gives byte-identical output on every run and platform.

## 11. Goldens and the analysis test (R7.10)

`test/goldens/<case>/` holds an input project (`typed_graphql.yaml`,
`schema.graphql`, documents) and the expected output as `*.dart.golden`
(not analyzed in place, not formatted, not counted by the code rules).
`golden_test.dart` runs the engine and compares every file; with
`UPDATE_GOLDENS=1` it rewrites them first. `generated_code_test.dart`
(`@TestOn('vm')`) writes every golden case into a temporary package that
depends on the core and the client by path, with this repository's
`analysis_options.yaml` plus `strict-casts`, runs `dart analyze
--fatal-infos` there, and runs a decode / `toJson` round trip program
against each case's sample responses. It is tagged `analysis` and skips itself
with a reason when `Platform.resolvedExecutable` is not the `dart` tool
(under `--compiler exe`); the JIT run covers it.

## 12. CLI (M10d)

`dart run typed_graphql_codegen generate [--config typed_graphql.yaml]`
reads the configuration, the schema (a file, or a URL fetched with
`IntrospectionQuery.full` over `dart:io`'s `HttpClient`, `headers` applied)
and the documents (`package:glob`), runs the engine, writes the files that
changed and prints every diagnostic as `path:line:col: severity code:
message` followed by the source excerpt. `check` does the same without
writing and reports each file that would change (`GQL509`). Exit codes: 0
done (warnings allowed), 1 diagnostics with errors, 64 usage. The CLI never
deletes a file; generated files whose document was removed are ignored by
both commands.

What the CLI does with hostile input, all decided by the M10d review:

- **Files.** Documents are listed with `followLinks: false` (a symbolic link
  is not followed); an invalid glob is `GQL501`, a listing failure
  `GQL510`. Output is written to `<path>.tmp` in the same folder and renamed
  (atomic); an unwritable output, or an output `check` cannot read (a
  directory, not UTF-8), is `GQL510` and the other files are still handled.
  No I/O error leaves the CLI as an exception.
- **HTTP.** The fetch does not follow redirects: a 3xx is `GQL510` naming
  the status and the `Location` (without user information and query), to
  put in `schema`. The body is capped at 64 MiB, counted while reading. A
  request that cannot be built, a timeout (30 s), a refused connection and a
  body that is not UTF-8 each have their own `GQL510` message; a 200 that is
  not JSON is `GQL502`. Plain `http` is accepted (documented).
- **Secrets.** `${NAME}` that is unset or empty, or a header value that is
  not ASCII or holds a control character, is `GQL501` and nothing is sent.
  Every text echoed from the response (a body excerpt, `errors[0].message`)
  and every printed URL (the diagnostic path `<url>.json` included) has the
  expanded header values replaced by `***`, URL user information and query
  removed, and control characters escaped.

## 13. Documentation (R11.1–R11.3)

The codegen package gets `doc/client_codegen.md` ("Client Code
Generation": configuration, the generated shapes, scalars, operations and
the manifest, the CLI, diagnostics), `dartdoc_options.yaml` with the
`codegen` category, `example/` (a configuration, a schema, a document and
the generated library, compiled by a test), a README that says what works,
and its CHANGELOG; `typed_graphql_client` says in its README and CHANGELOG
that only the generated-code contract exists. `docs/discovery.md` gets the
"Dart GraphQL code generator" query unlocked, `llms.txt` an entry,
`CLAUDE.md` a "Codegen" paragraph, the handoff the stage row.

## 14. Determinism and identity of CLI and builder output

The engine's only inputs are the configuration text, the schema text and
the documents' paths and texts; its only output is `GeneratedFile(path,
text)`s and diagnostics. The CLI and M9's builder must hand it the same
inputs; M9 adds a test that both produce byte-identical files for the
golden cases.

## 15. How later stages use the engine

- **M11 (client runtime)** implements `GraphQLClient` over
  `GraphQLOperation`: `toRequest()` for the wire, `document.sha256` for APQ,
  `decodeData` for `GraphQLData<D>`; the `GraphQLQuery` / `GraphQLMutation`
  / `GraphQLSubscription` split types `query`, `mutate` and `subscribe`.
- **M12 (normalized cache, R7.11)** adds a `SelectionMetadataEmitter` that
  writes, from the same shapes, a compact `static const` selection tree per
  operation and fragment (response name, field name, arguments as written,
  type conditions), plus `readFragment` / `writeFragment` over each
  fragment's `codec`. The shapes already carry what it needs: field names,
  arguments, conditions and type conditions.
- **M8 (SDL-first server generator)** reuses `CodegenConfig` (a `server:`
  section), `SchemaLoader`, `DartWriter`, `DartNames`, `Imports`, the enum
  and input-object emitters (the server decodes the same inputs) and the
  golden and analysis harness; its own emitter targets the M5 builder.
- **M9 (`build_runner`)** wraps `ClientGenerator.generate` in an aggregate
  builder: it globs the documents, reads the schema and writes the same
  `GeneratedFile`s.
- **M13 (schema diff)** adds dangerous-change warnings to `check`.

## 16. Deviations from the architecture spec

1. Enums follow typed_openapi's actual pattern, `enum StatusKnown
   implements Status`, instead of a wrapper `StatusKnown(StatusValue)`
   over a second enum: the values are the `Status` themselves, so a switch
   is exhaustive without unwrapping (open question 3).
2. The runtime contract lives in `typed_graphql_client` from M10 on (the
   architecture assigns the package to M11), and `Optional<T>` lives in the
   core (the architecture names it for both sides without a home).
3. Generated libraries end their header with `// dart format off`: the
   engine cannot run the formatter (it depends on `analyzer`), and a
   project's `dart format` must not rewrite generated files.
4. A field under `@skip` / `@include` is nullable in the generated class
   whatever its schema type, and a conditional fragment spread is a
   nullable accessor decided by the variables at decode time.
5. Variant classes are per concrete type reached by a narrowing condition,
   not per written type condition: an interface condition inside a union
   yields one variant per implementing member, so each object is exactly
   one variant.
6. Every operation and fragment of the project is validated together;
   `NoUnusedFragmentsRule` and `LoneAnonymousOperationRule` are not run
   (section 5).
7. **Variants drop a re-selected field from the base.** The architecture
   lets a variant's class for a re-selected field `implements` the base's
   class; that trips `avoid_implementing_value_types` (the classes override
   `==`). A base getter exists only for a field every variant selects with
   the same nodes; otherwise every variant (`…Unknown` included) has its own
   class and code that reads the field through the base must switch on the
   variant (section 6, open question 8).
8. **Applicability on an abstract parent.** A type condition applies to the
   base only when it is the parent itself or an interface the parent
   implements; every other condition narrows to concrete types, even when it
   covers every possible type today (section 6, open question 9).

Decisions taken during the implementation and by the review rulings, which
refine the architecture without overriding it:

9. `Optional` lives in the core's `protocol/` (open question 1) and the
   generated-code contract in `typed_graphql_client` (open question 11).
10. Enum `parse` loops over `XKnown.values` (section 7).
11. Each generated class declares its own private codecs (section 7).
12. `DataContext` carries the operation's Boolean variable defaults
    (`flag(name)`, section 6).
13. Input objects get a reader too, so their codecs are symmetric
    (section 7).
14. The schema-types library and fragment libraries are imported without a
    prefix; names are checked project-wide (section 2).
15. Member collisions (enum values, input fields) and file collisions are
    `GQL507`, like type-name collisions (section 7).
16. Nested classes with the same type, selection nodes and conditions are
    shared, and planning stops at 10000 classes with `GQL511` (section 6).
17. A `__typename` under `@include` / `@skip` is a nullable member and never
    stands in for the one the generator adds (section 6).
18. `__schema` and `__type` in a document are `GQL504` until the generator
    has classes for the introspection types (section 5).
19. The `GQL504` subscription-root rule covers only a spread of a fragment
    that plans as a sealed base; an inline fragment alone is fine, and an
    anonymous subscription is only `GQL503` (section 6).
20. `toJson` merges a class and its fragments with `client.JsonMerger`
    (deep, by key and index; a later `null` keeps the earlier value)
    (section 7).
21. The CLI classes are kept out of the engine barrel (section 2).
22. The CLI does not follow redirects, caps the schema body at 64 MiB,
    redacts secrets in everything it prints, lists documents with
    `followLinks: false` and writes atomically through `<path>.tmp`
    (section 12).
23. An empty or comment-only document adds nothing (section 5).

## 17. Open questions for the owner

1. **Where `Optional<T>` lives.** Recommendation: the core's `protocol/`
   (M10b adds it), and M5 uses the same type for arguments and input
   objects; the alternative, one per package, makes generated server and
   client code disagree.
2. **Nested class names.** Recommendation: parent name plus capitalised
   response name (`GetUserDataUserFriends`), collisions reported
   (`GQL507`) rather than renamed; the alternative is Apollo Kotlin's
   singularised type names, which guess.
3. **Enum shape.** Recommendation: `enum StatusKnown implements Status`
   (deviation 1) rather than the architecture's wrapper class.
4. **Manifest format.** Recommendation: Apollo's
   `apollo-persisted-query-manifest` v1 (GraphOS, Apollo Router and
   several servers read it); M6's trusted documents read the same file.
5. **`Optional` for nullable variables.** Recommendation: as R7.7 says,
   `Optional<T?>` for every nullable variable and input field, since a
   server may tell absence from `null` for any argument; a later option
   could make them plain `T?` for teams that never rely on it.
6. **Environment in headers.** Recommendation: `${NAME}` in a header
   value only, read by the CLI, so tokens stay out of the configuration.
7. **Diagnostic numbering.** The draft table numbered `noDocuments`
   `GQL508` and the name codes `GQL506`/`GQL507`; the implemented catalog
   is `GQL505` unknownScalarMapping, `GQL506` noDocuments (warning),
   `GQL507` generatedNameCollision, `GQL508` reservedTypeName, `GQL509`
   outputOutdated, `GQL510` inputUnreadable, `GQL511`
   tooManyGeneratedClasses. Recommendation: keep it (section 9); the ids
   are public API once released, and M5 appends its own codes in the
   `GQL3xx` range, so merging the catalogs is textual only.
8. **Variants: drop from the base** (deviation 7). Recommendation: keep it;
   the cost is that a field re-selected by a variant is read through a
   switch on the variant.
9. **Applicability on an abstract parent** (deviation 8). Recommendation:
   keep it, so adding a union member or an implementer never changes which
   class a field is declared on.
10. **A selection on an abstract type without narrowings** is a plain
    class, with no sealed base and no `…Unknown` variant, since there is
    nothing to tell apart. Recommendation: keep it.
11. **Runtime code ahead of M11.** The generated-code contract lives in
    `typed_graphql_client` from M10 on, and the package says it holds only
    that contract until M11. Recommendation: keep it; M11 builds the client
    on the same types.
12. **`__typename` in the document.** It is added to every field selection
    set that lacks an unconditional one (not to fragment definitions or
    inline fragments, which the field around them covers), and to the
    operation root only for a spread of a fragment that plans as a sealed
    base; at a subscription root that case is `GQL504`. Recommendation:
    keep it; the alternative, adding `__typename` everywhere, changes every
    document's text and hash for no reader.
