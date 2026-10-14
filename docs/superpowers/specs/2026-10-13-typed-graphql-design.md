# typed_graphql: architecture design

Date: 2026-10-13. Status: **approved in conversation** (sections 1–7), binding for
all stages. Requirements: [../../requirements.md](../../requirements.md). Stages:
[../../roadmap.md](../../roadmap.md). Research and the decisions log:
[../../research/README.md](../../research/README.md).

Each roadmap stage gets its own design spec in this folder when it starts. A stage
spec refines names and signatures; it does not change the decisions below without
the user's approval.

---

## 0. Goal and principles

`typed_graphql` is a from-scratch GraphQL implementation for Dart that covers the
whole specification and its protocols, and is **fully typed** on both the server and
the client. The previous attempt (a line-by-line port of graphql-java, still in
`lib/`) is discarded and deleted in M1.

1. **Spec-complete.** Baseline is the **September2025** edition. Grammar and
   introspection additions from the `main` working draft are available behind
   parser options. RFC-stage proposals (incremental delivery, `onError`, fragment
   arguments) have extension points and land only when they stabilise or behind an
   opt-in.
2. **Fully typed public API.** No `dynamic`, no `Map<String, dynamic>` in a public
   signature. Arbitrary JSON is `JsonValue`, a sealed class family
   (`JsonNull`, `JsonBool`, `JsonNumber`, `JsonString`, `JsonArray`,
   `JsonObject`), not an extension type: an extension type cannot be sealed or
   matched with `is`.
3. **No exceptions on bad input.** Parsing, validation, coercion and client calls
   return sealed results with every diagnostic. Exceptions are reserved for
   programmer errors (`ArgumentError`, `StateError`, `SchemaBuildError`) and for
   user resolvers, whose exceptions the executor turns into `GraphQLError`s.
4. **Independent of `package:gql`.** Own AST, transports and client; no bridge
   package (user decision).
5. **Latest Dart.** `sdk: ^3.13.0` everywhere, generated code included. Every stable
   3.13 feature is used where it fits: primary constructors, private named
   parameters, dot shorthands, null-aware elements, sealed classes and exhaustive
   `switch`, records, extension types. No experiment flags.
6. **Core is pure Dart.** No `dart:io`, no dependencies except `meta`; compiles with
   dart2js and dart2wasm.
7. **Conformance is measured, not claimed.** The graphql-js v17 test suites are
   ported with a mapping table; the parser is fuzzed; suites also run AOT-compiled.

## 1. Packages

A Dart pub workspace (`packages/*`). Packages are split by consumer, not by every
internal layer.

| Package | Contents | Depends on |
|---|---|---|
| `typed_graphql` | Core: `language/`, `schema/`, `validation/`, `protocol/`, `diagnostics/` | `meta` |
| `typed_graphql_server` | Typed schema builder, execution engine, subscriptions, DataLoader, request pipeline and extensions, transport-agnostic HTTP / graphql-ws / graphql-sse handlers | core |
| `typed_graphql_shelf` | `shelf` adapter (HTTP + WebSocket), optional GraphiQL page in development | server, `shelf`, `shelf_web_socket` |
| `typed_graphql_client` | Client runtime: `GraphQLClient`, links, transports, normalized cache, `MockLink` | core, `http`, `web_socket_channel` |
| `typed_graphql_codegen` | Code generation engine + CLI, **no `analyzer`**: client (`.graphql` → Dart) and server SDL-first | core |
| `typed_graphql_builder` | `build_runner` builders wrapping the engine + the annotation front end (the only package that depends on `analyzer`) | codegen, `build`, `source_gen`, `analyzer` |
| `typed_graphql_conformance` | `publish_to: none`. Ported graphql-js suites runner, fuzzers, benchmarks | all |

Later packages: `typed_graphql_federation` (subgraph role, M15),
`typed_graphql_flutter` (only if the `Stream` API proves insufficient), a
persistent cache backend. The dartnest integration lives in the dartnest
repository as its adapter.

Rationale:
- **One core package with internal layers**, as `graphql` in JS. The import
  direction is a total order, lowest layer first: `diagnostics` < `language` <
  `protocol` < `schema` < `validation`. A layer imports only itself and lower
  layers; in particular `protocol` depends on `diagnostics` and `language`. A
  test in `test/quality/` enforces it.
- **The executor lives in the server package.** A Flutter app depends on
  `typed_graphql_client` and the core only; generated operations embed their
  documents as strings, so no parser runs at client runtime. Client tests that need
  an in-memory server take `typed_graphql_server` as a dev dependency.
- **`analyzer` is isolated in `typed_graphql_builder`.** The engine reads `.graphql`
  with our own parser, so the CLI and `build_runner` share it, and analyzer major
  version churn touches only the annotation front end.

## 2. Language layer (`typed_graphql`, `language/`)

**Editions.** The full September2025 grammar by default: `@oneOf`, descriptions on
operations and fragments, full Unicode source text, schema coordinates.
`ParserOptions` switches on working-draft grammar (directive extensions, empty
selection sets) and, later, experimental RFC grammar (fragment arguments, only once
it reaches Proposal). The parser has a dedicated extension point for such
productions.

**Source and positions.** `Source` (with `SourceLocation` and `SourceSpan`) lives
in `diagnostics/`, the lowest layer, because `Diagnostic` points at spans; the
language layer uses it. `Source(body, name:)` builds its line-start table lazily,
only when a line/column is needed (error `locations`). Every node stores `start` and
`end` offsets (UTF-16 code units).

**Lexer.** Scans with `codeUnitAt` and an `int` cursor. Never throws: malformed input
yields an error token plus a diagnostic. Exact block-string dedent, both `\uXXXX`
(with surrogate pairs) and `\u{...}` escapes with scalar-value validation. Comments
are kept as trivia tokens so a future formatter and LSP do not need a new lexer.

**Parser.** Hand-written recursive descent, one method per grammar production.
Error-resilient: after an error it resynchronises at definition and selection
boundaries, so one pass reports every syntax error. Limits against abuse:
`maxTokens`, `maxDepth`.

```dart
sealed class ParseResult {
  List<Diagnostic> get diagnostics;   // every error and warning, not only the first
}
final class ParseSuccess extends ParseResult {
  Document get document;              // diagnostics hold warnings only
}
final class ParseFailure extends ParseResult {
  Document get partial;               // constructs that failed to parse are omitted
}
```

`ParseFailure.partial` omits what could not be parsed; the AST has **no error or
missing node variants**, so exhaustive switches stay clean for valid documents.
`requireDocument()` on the result throws `GraphQLSyntaxException` with all
diagnostics; it exists for tests and scripts and is the caller's choice.

**AST.** Sealed families of `final` classes with primary constructors, immutable
lists, `const` where possible:
- `Definition` → `ExecutableDefinition` (`OperationDefinition`,
  `FragmentDefinition`), `TypeSystemDefinition` (schema, six type kinds,
  directive), `TypeSystemExtension` (schema and six type kinds; directive extension
  behind the working-draft option);
- `Selection` → `Field | FragmentSpread | InlineFragment`;
- `Value` → `Variable | IntValue | FloatValue | StringValue | BooleanValue |
  NullValue | EnumValue | ListValue | ObjectValue`;
- `TypeRef` → `NamedType | ListType | NonNullType` — a canonical wrapper, not an
  `isNonNull` flag.

`IntValue` and `FloatValue` keep the raw lexeme; the number is parsed during
coercion, so large values are not lost. Nodes do not override `==`;
`isEquivalentTo(other)` compares structure and ignores positions.

**Traversal and printing.** `AstVisitor` with no-op defaults for every node kind,
dispatching through an exhaustive `switch`. `ParallelVisitor` fuses several visitors
into one walk. `AstTransformer` rebuilds only the changed branches (codegen uses it
to add `__typename`). `Printer` emits canonical output and a minified form for the
wire and for APQ hashing.

**Diagnostics.** `Diagnostic(code, severity, message, span)`. The `DiagnosticCode`
catalog has stable codes with a doc comment each:

| Range | Area |
|---|---|
| `GQL0xx` | lexer and syntax |
| `GQL1xx` | type system (building and validating a schema) |
| `GQL2xx` | operation validation (the spec rule name in the doc comment) |
| `GQL3xx` | coercion and execution |
| `GQL4xx` | transports and protocols |
| `GQL5xx` | code generation |

Internally the lexer, parser and rules receive a `DiagnosticSink` through the
constructor; results are assembled at the public API boundary.

Later, a separate package: a lossless CST for a formatter and an LSP, lowering to
the same AST.

## 3. Type system and validation (`typed_graphql`, `schema/` + `validation/`)

**Schema model.** An immutable `Schema`: an ordered map of name →
`sealed class NamedType` (`ScalarType | ObjectType | InterfaceType | UnionType |
EnumType | InputObjectType`), directive definitions and root types. Type references
hold names, not objects, so a cyclic graph stays immutable without `late`. **The
schema has no resolvers**: it is the type-system model shared by the client
generator, the schema diff and the server. The server keeps
`ExecutableSchema` = `ValidSchema` + resolver bindings separately (§4).

Built-ins: scalars `Int` (32-bit signed), `Float` (finite IEEE 754), `String`,
`Boolean`, `ID`; directives `@skip`, `@include`, `@deprecated`, `@specifiedBy`,
`@oneOf`. `@defer` and `@stream` are opt-in.

**Sources of a schema.**
- `SchemaBuilder.fromSdl(document)`, including every kind of `extend`;
- `fromIntrospection(json)`: the client generator loads a remote schema this way;
- the server's typed builder (§4) produces the same model.

Back again: `Schema` → SDL. Schema coordinates (`User.posts(first:)`,
`@deprecated`) are parsed, printed and resolved against a schema; diagnostics and
the schema diff refer to them.

**Schema validation.** Every type-system rule of the spec: interface implementation
(including transitive interfaces), union members, input cycles through non-null
fields, `@oneOf` rules, reserved `__` names, self-referencing directives. Result:
`ValidSchema` or `InvalidSchema(diagnostics)`. `ValidSchema` is a `final class`
with a private constructor, obtainable only from `validate()` or the explicit
`ValidSchema.assumeValid()` (trusted schemas, faster start-up). Not an extension
type: an extension type's representation is reachable by a cast, so it cannot
guard an invariant.

**Operation validation.**
- The 30 rules of Section 5, each its own `ValidationRule` class with
  `enter`/`leave` dispatching through a `switch` on the sealed node type.
  `TypeInfo` tracks the current parent type, field and input type.
- All rules run in **one walk** through `ParallelVisitor`.
- `OverlappingFieldsCanBeMerged` uses the Sangria algorithm, not the quadratic one
  from graphql-js (#2185).
- Result: `ValidDocument` or `InvalidDocument(diagnostics)`. A `ValidDocument` is
  bound to the `ValidSchema` it was validated against; the executor checks it is
  the same schema and otherwise throws `ArgumentError`.
- Opt-in rules: `MaxDepth`, `MaxComplexity` (per-field cost), `MaxAliases`,
  `MaxDirectives`, `NoIntrospection`, plus a public API for custom rules. The
  infrastructure is in the core; the server enables the limits by default.
- Variable values are not checked here; they are coerced at execution.

**Scalars.** One interface in the core, `ScalarCodec<T>`: `decode(Object? json)`
returns a sealed `DecodeSuccess<T>(value)` / `DecodeFailure(message)` (bad input is
a result, not an exception), `Object? encode(T value)`. A literal from the AST is
first converted to a JSON-like value, so no separate `parseLiteral` is needed. The same codec serves the server (coercion,
serialisation) and the client (decoding responses, encoding variables).

**Schema diff (M13).** `SchemaDiff.compare(old, new)` classifies changes as breaking
/ dangerous / safe (a port of graphql-js `findSchemaChanges`), with schema
coordinates. Used in backend CI and by the client generator to warn about
dangerous changes, exactly the cases where `Unknown` variants matter.

## 4. Server (`typed_graphql_server` + generators)

**The typed builder is the runtime IR.** Hand-written code and both generators
target it.

```dart
final b = SchemaBuilder<AppContext>();
final first = Arg('first', b.int, defaultValue: 10);              // Arg<int>
final user = b.object<User>('User', (t) => [
  t.pure('name', b.string, (u) => u.name),                         // sync lane, no middleware
  t.field('posts', b.list(post), args: [first],
      (u, args, ctx, info) => ctx.posts.load(u.id, args[first])),
]);
final schema = b.build(query: queryType, mutation: mutationType); // ExecutableSchema
```

(Final method names are decided in the M5 spec.)

- `OutputRef<R>` is non-null by default, as in Dart; `.nullable` gives
  `OutputRef<R?>`, `b.list(x)` gives `OutputRef<List<X>>`. A resolver cannot return
  `null` for a non-null field: it does not compile.
- A resolver takes `(parent, args, ctx, info)`, as in graphql-js; unused ones are
  `_`. A pure getter lane takes only the parent and skips middleware and `FutureOr`
  checks.
- Arguments: typed keys (`args[first]`; reading an undeclared argument is a
  `StateError`) or an arguments class (`args: PostsArgs.def`, the resolver receives
  `PostsArgs`). The generators use the second form.
- Input objects: `InputObjectDef<T>` with `decode`. `Optional<T?>` only where
  absence differs from `null`.
- Enums: `b.enumType('Status', Status.values)` from a plain Dart enum, names and
  deprecations configurable.
- Union and interface: Dart generics are reified, so `ObjectTypeDef<P>` checks
  `value is P` and `resolveType` works with no code. The explicit form is an
  exhaustive `switch` over a sealed class.
- `build()` throws `SchemaBuildError` with every diagnostic when the schema is
  invalid: the schema is the developer's code, not user input, so this is a
  programmer error found at start-up.

**Execution.**
- API: `execute(ValidDocument, …)` → `FutureOr<ExecutionResult>`; `subscribe` →
  `Stream<ExecutionResult>`; `executeIncrementally` → `Stream` of incremental
  payloads (opt-in, M14).
- `CoerceVariableValues` with request errors kept apart from field errors.
- `OperationPlan`: built once per (document, operation name) — merged fields per
  (object type, selection set), coerced literal arguments, `@skip`/`@include`
  conditions, and `@defer`/`@stream` usage from day one. LRU cache with single-flight
  compilation.
- `FutureOr` fast path: a synchronous field allocates no `Future`; `Future.wait`
  runs only when at least two sibling fields are asynchronous; no `async` on hot
  paths. Mutations run serially.
- Error behaviour is a parameter: `propagate` (the spec default), `null`, `halt`
  (the `onError` proposal). A resolver exception becomes a `GraphQLError` with
  `path` and `locations`. A thrown `GraphQLException(message, extensions:)` reaches
  the client as is; other exceptions are masked by default.
- Field middleware is composed once per field at build time, in the order global →
  type → field → directive slots. An empty chain is a direct call.
- DataLoader: `BatchLoader<K, V>` and `GroupedLoader<K, V>`, request-scoped,
  de-duplicated, dispatched after the current microtask burst, with a forced flush
  by the executor at level boundaries.
- Introspection: ordinary object types whose resolvers read the `ValidSchema`; an
  `IntrospectionPolicy`, off by default in production profiles.

**Generators.** Both emit builder code through one shared emitter; only the input
model differs (analyzer elements vs a parsed `ValidSchema`). They never rewrite user
files and never emit `part` files: each output is a standalone library
`*.graphql.dart`.
- **Annotations** (`typed_graphql_builder`, M9): `@GraphQLObject`, `@Field`,
  `@Ignore`, `@GraphQLInput`, `@Query` / `@Mutation` / `@Subscription`. A sealed
  class maps to a union or interface; `T` / `T?` gives nullability; parameter
  defaults give argument defaults; `///` gives descriptions; `@Deprecated` gives
  `@deprecated`; `Future<T>` / `FutureOr<T>` / `Stream<T>` unwrap to `T`. Also emits
  `schema.graphql` for review, diff and the client generator.
- **SDL-first** (`typed_graphql_codegen`, M8): binds GraphQL types to existing Dart
  classes (or generates models), binds fields to getters with a type check (a
  mismatch is a build error), generates abstract resolver classes only for fields
  that do not bind, turns directives into typed middleware slots.

## 5. Server pipeline and transports

**Pipeline.** `GraphQLServer<C>(schema, extensions: […], contextFactory: …)` runs
`request → parse → validate → execute | subscribe`. Parsed documents and
`ValidDocument`s are cached by the hash of the query text. `ServerExtension` has
phase hooks chained through `next`; its `resolve` hook is folded into field
middleware only when overridden. The typed context `C` comes from a factory over
the request data.

**Built-in extensions.** Limits (depth, cost, aliases, tokens); APQ (sha256 in
`extensions.persistedQuery`, `PersistedQueryNotFound`, pluggable store); trusted
documents (an allowlist from the manifest the client generator emits); the
introspection policy and error masking; CSRF prevention (GET requires a header or a
non-simple content type). Later: response cache, OpenTelemetry-style tracing,
request batching.

**Transport-agnostic handlers.** The handler core is
`HttpRequestData → HttpResponseData`, without `dart:io`:
- GraphQL over HTTP: GET for queries only, POST for everything; negotiation of
  `application/graphql-response+json` vs `application/json` by `Accept`; status
  codes per the spec.
- Uploads: the jaydenseric multipart request spec, an `Upload` scalar.
- graphql-ws (`graphql-transport-ws`): the full state machine (`connection_init` /
  `connection_ack`, ping/pong, `subscribe` / `next` / `error` / `complete`), close
  codes `4400`–`4429`, the init timeout. The legacy `subscriptions-transport-ws` is
  not supported.
- graphql-sse: both "distinct connections" and "single connection" modes.
- Incremental delivery over `multipart/mixed`: opt-in, with `executeIncrementally`
  (M14).

All protocol message types live in the core (`protocol/`) and are shared with the
client.

**Adapters.** `typed_graphql_shelf` (HTTP and WebSocket handlers, an optional
GraphiQL page in development). Others (`dart:io` directly, dart_frog) are one small
class each. Later: `typed_graphql_federation` for the subgraph role; the vocabulary
(Apollo Federation v2 vs GraphQL Foundation Composite Schemas) is chosen at that
stage.

## 6. Client (`typed_graphql_client` + code generation)

**Declaring operations.** `.graphql` files next to the code; the schema comes from a
file or an introspection URL in `typed_graphql.yaml`. The generator merges all
project documents into one fragment graph, validates them with the core validator
(every error at once, with `file:line:col`), and emits a standalone library
`*.graphql.dart` per `.graphql` file. The CLI and `build_runner` run the same engine
and produce byte-identical output.

**Generated shapes.** One type per operation, pruned to the selected fields
(operation-based, never whole-schema response-based codegen).
- Data: `final class` with eagerly decoded fields, `==`, `hashCode`, `toString`,
  `toJson`. `==` matters for Flutter: a cache update that yields equal data causes no
  rebuild.
- Fragments: a class per fragment, reached through `data.user.fragments.userCard`
  (as in Apollo Kotlin). Fields selected only by a fragment are absent from the
  operation class, so masking falls out of the shape.
- Union and interface: a sealed class per selection set with a variant per type
  condition and a mandatory `…Unknown(typename)` variant; interface fields are on the
  base class.
- Enum: `sealed X` → `XKnown(XValue value)` (a plain Dart enum) | `XUnknown(String
  raw)`, the typed_openapi pattern.
- Variables: a class with named parameters; `Optional<T?>` only where absence
  differs from `null`; non-null variables are `required`.
- Scalars: the config maps a scalar to a Dart type and a `ScalarCodec`; an unmapped
  custom scalar is `JsonValue`, never `dynamic`.
- Metadata: the minified document with `__typename` added, the operation name and
  its sha256 (APQ, trusted documents); a persisted-operations manifest for the
  server; compact selection metadata for the normalized cache, so the cache needs no
  parser at runtime.

**Runtime.**
- `client.query` and `client.mutate` return `Future<GraphQLResponse<D>>`;
  `watchQuery` and `subscribe` return `Stream`s.
- No exceptions:

  | Variant | When |
  |---|---|
  | `GraphQLData<D>(data, errors)` | data present; `errors` may be non-empty (partial data) |
  | `GraphQLErrors(errors)` | request error, no data |
  | `GraphQLTransportFailure(cause)` | network, HTTP or decoding failure |

- `Link` returns a `Stream` and forwards to the next link. Built in: `HttpLink` over
  any `http.Client` (cupertino_http, cronet_http, a dio adapter); `WebSocketLink`
  (graphql-transport-ws, reconnection, lazy connection); `SseLink`; `SplitLink`;
  `RetryLink`; `DedupeLink`; `ApqLink`; `AuthLink` with token refresh; multipart
  uploads.
- Normalized cache (v1): records keyed by cache id (`typePolicies` in the config,
  default `__typename:id`); fetch policies `cacheFirst`, `networkOnly`, `cacheOnly`,
  `cacheAndNetwork`, `noCache`; `watchQuery` re-emits on change; an optimistic layer
  separate from the base store for safe rollback; mark-and-sweep GC rooted at active
  watches; typed `readFragment` / `writeFragment`.
- Testing: `MockLink` queues responses and records requests.

Later: client `@defer` / `@stream`; `@catch` / `FieldResult` once `onError`
stabilises; Relay connection pagination; a persistent sqlite cache; generated test
data builders; `typed_graphql_flutter` if needed.

## 7. Quality, conformance and documentation

**Code rules.** The typed_openapi rules (its `CLAUDE.md`, `CONTRIBUTING.md`) apply,
with `analysis_options.yaml` adapted from typed_openapi's (comments rewritten; extra lints
`simple_directive_paths`, `no_dynamic_casts`, `no_raw_types`) and the SDK floor raised to 3.13
(primary constructors allowed). In short: files in `lib/` ≤ 300 lines, test files
≤ 500, methods ≤ 40, ≤ 5 parameters, nesting ≤ 3, one public class or sealed family
per file, all enforced by a ratchet test; no `part` files, no top-level functions
outside `main`, no `utils`/`helpers` files, no `dynamic`, no catch without `on`.
The core's layer direction is enforced by a test.

**Conformance** (`typed_graphql_conformance`):
- ported graphql-js v17 suites (lexer, parser, printer, visitor, each validation
  rule, execution, introspection, coercion) with a mapping table "graphql-js file →
  our test" that shows coverage;
- parse → print → parse round-trip fuzzing;
- later, nightly: differential testing against graphql-js (same schema and query,
  same result) and the `graphql-http` audit against the shelf server.

**CI.** A matrix of the minimum SDK and stable; suites also under
`dart compile exe` (AOT sealed-switch bug sdk#56010); the core and the client under
`-p chrome` with dart2js and dart2wasm; golden tests for generated code; parser and
executor-allocation benchmarks.

**Documentation.** User documentation follows basalt: the root README (banner →
badges → pitch → code → Why → packages table → Getting started → feature sections
linking to guides), a README per package, `packages/*/doc/*.md` guides tied to
dartdoc categories, a CHANGELOG per package with `**Breaking:**` entries. Process
documents follow typed_openapi, in English: `docs/requirements.md`,
`docs/roadmap.md`, `docs/research/`, `docs/superpowers/{specs,plans,HANDOFF.md}`,
`CLAUDE.md`, `CONTRIBUTING.md`. Each stage updates the documentation of what it
ships.

**Knowledge base.** `tool/fetch_reference.sh` fetches the specifications, protocols
and graphql-js into the git-ignored `reference/`; `reference/README.md` records the
commits.
