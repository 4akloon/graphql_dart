# typed_graphql: requirements

Date: 2026-10-13. Architecture: [superpowers/specs/2026-10-13-typed-graphql-design.md](superpowers/specs/2026-10-13-typed-graphql-design.md).
Stages: [roadmap.md](roadmap.md). Research and decisions: [research/README.md](research/README.md).

Tags: **[MUST]** — required for the stage that owns it; **[SHOULD]** — expected,
may move to a later stage with a recorded reason; **[LATER]** — out of the current
roadmap, kept so the design leaves room for it. The last column is the owning
stage.

## R0. Product principles

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R0.1 | The baseline is the GraphQL **September2025** edition; working-draft (`main`) additions are available behind options | MUST | M2–M5 |
| R0.2 | No `dynamic` and no `Map<String, dynamic>` in any public signature; arbitrary JSON is `JsonValue` / `JsonObject` | MUST | all |
| R0.3 | Bad input (documents, schemas, variables, responses) never throws: results are sealed types carrying every diagnostic. Exceptions only for programmer errors and inside user resolvers | MUST | all |
| R0.4 | No dependency on `package:gql` or its ecosystem, and no bridge package | MUST | all |
| R0.5 | `sdk: ^3.13.0` in every package and in generated code; stable Dart 3.13 features are used, no experiment flags | MUST | all |
| R0.6 | The core package is pure Dart: no `dart:io`, no dependencies except `meta`; it compiles with dart2js and dart2wasm | MUST | M1–M4 |
| R0.7 | Spec conformance is measured with ported graphql-js v17 suites and a coverage mapping table | MUST | M2–M5 |

## R1. Language

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R1.1 | Lexer: full-Unicode source, all token and ignored-token kinds, exact block-string algorithm, `\uXXXX` (with surrogate pairs) and `\u{...}` escapes with scalar-value validation | MUST | M2 |
| R1.2 | Lexer never throws; malformed input yields an error token and a diagnostic; comments are kept as trivia | MUST | M2 |
| R1.3 | Parser covers the whole September2025 executable and type-system grammar, including descriptions on executable definitions and every type-system extension | MUST | M2 |
| R1.4 | `ParserOptions` enables working-draft grammar (directive extensions, empty selection sets) and has an extension point for experimental productions | MUST | M2 |
| R1.5 | Error-resilient parsing: one pass reports every syntax error; `ParseSuccess` / `ParseFailure(partial)`; the partial document omits what failed, the AST has no error node variants | MUST | M2 |
| R1.6 | `maxTokens` and `maxDepth` limits | MUST | M2 |
| R1.7 | Every node has `start`/`end` offsets; `Source` computes line/column lazily | MUST | M2 |
| R1.8 | Sealed, immutable AST of `final` classes; `NonNullType` is a wrapper; numeric literals keep their raw lexeme; `isEquivalentTo` ignores positions | MUST | M2 |
| R1.9 | `AstVisitor` with no-op defaults, `ParallelVisitor`, `AstTransformer` | MUST | M2 |
| R1.10 | `Printer`: canonical and minified output; parse → print → parse is stable | MUST | M2 |
| R1.11 | Schema coordinates: parse and print | MUST | M2 |
| R1.12 | Stable `DiagnosticCode` catalog with ranges `GQL0xx`–`GQL5xx`, each code documented | MUST | M1 |
| R1.13 | Lossless CST for a formatter and an LSP, lowering to the same AST | LATER | — |
| R1.14 | Fragment arguments grammar, once the RFC reaches Proposal | LATER | — |

## R2. Type system

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R2.1 | Immutable `Schema` model with a sealed `NamedType` family; type references by name; no resolvers in the model | MUST | M3 |
| R2.2 | SDL → `Schema`, including every kind of `extend` | MUST | M3 |
| R2.3 | Schema validation with every type-system rule of the spec (interfaces incl. transitive, unions, input cycles, `@oneOf`, reserved names, directives); result `ValidSchema` / `InvalidSchema` | MUST | M3 |
| R2.4 | `ValidSchema` is a `final class` with a private constructor; `assumeValid()` is the only bypass | MUST | M3 |
| R2.5 | `Schema` → SDL printer | MUST | M3 |
| R2.6 | Built-in scalars with exact coercion boundaries and built-in directives `@skip @include @deprecated @specifiedBy @oneOf`; `@defer` / `@stream` opt-in | MUST | M3 |
| R2.7 | Introspection query generation (with options for working-draft fields) and introspection JSON → `Schema` | MUST | M3 |
| R2.8 | Schema coordinates resolve against a schema | MUST | M3 |
| R2.9 | `ScalarCodec<T>` shared by server and client; literals go through a JSON-like value | MUST | M3 |
| R2.10 | `SchemaDiff`: breaking / dangerous / safe changes with schema coordinates | MUST | M13 |

## R3. Operation validation

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R3.1 | All 30 rules of Section 5, each a separate class with its own ported tests | MUST | M4 |
| R3.2 | All rules run in one walk (`ParallelVisitor` + `TypeInfo`) | MUST | M4 |
| R3.3 | `OverlappingFieldsCanBeMerged` is not quadratic (Sangria algorithm) | MUST | M4 |
| R3.4 | Result `ValidDocument` / `InvalidDocument`; a `ValidDocument` is bound to its `ValidSchema` | MUST | M4 |
| R3.5 | Opt-in limit rules: `MaxDepth`, `MaxComplexity`, `MaxAliases`, `MaxDirectives`, `NoIntrospection` | MUST | M4 |
| R3.6 | A public API for custom rules | MUST | M4 |
| R3.7 | `@defer` / `@stream` validation rules | MUST | M14 |
| R3.8 | Cost analysis rule `MaxCost` following the IBM draft `@cost` / `@listSize` directives (not yet in the specification, so schemas stay portable); the directives are opt-in built-in directives defined when the analyzer is built | MUST | M4 |

## R4. Execution and the typed builder

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R4.1 | `SchemaBuilder<C>` with `OutputRef<R>` (non-null by default, `.nullable`, lists) producing `ExecutableSchema`; a wrong resolver result type does not compile | MUST | M5 |
| R4.2 | Resolvers `(parent, args, ctx, info)` returning `FutureOr<R>`; a pure getter lane | MUST | M5 |
| R4.3 | Typed arguments: `Arg<T>` keys and argument classes | MUST | M5 |
| R4.4 | Input objects with `decode`; `Optional<T?>` where absence differs from `null`; enums from Dart enums | MUST | M5 |
| R4.5 | Abstract types: default `value is P` resolution and an explicit exhaustive `switch` | MUST | M5 |
| R4.6 | An invalid built schema throws `SchemaBuildError` with every diagnostic | MUST | M5 |
| R4.7 | Variable coercion with request errors separate from field errors | MUST | M5 |
| R4.8 | `OperationPlan` cached in an LRU with single-flight compilation; it records `@defer` / `@stream` usage | MUST | M5 |
| R4.9 | No `Future` for synchronous fields; `Future.wait` only for two or more asynchronous siblings; serial mutations | MUST | M5 |
| R4.10 | Null propagation per the spec, with error behaviour `propagate` / `null` / `halt` as a parameter | MUST | M5 |
| R4.11 | Resolver exceptions become `GraphQLError`s with `path` and `locations`; `GraphQLException` passes through, other exceptions are masked by default | MUST | M5 |
| R4.12 | Field middleware composed once per field at build time; an empty chain is a direct call | MUST | M5 |
| R4.13 | Subscriptions: source stream → response stream, with unsubscribe | MUST | M5 |
| R4.14 | Introspection as ordinary types over the `ValidSchema`; `IntrospectionPolicy` | MUST | M5 |
| R4.15 | DataLoader: `BatchLoader`, `GroupedLoader`, request-scoped, microtask dispatch plus level flush | MUST | M6 |
| R4.16 | `executeIncrementally` for `@defer` / `@stream` | MUST | M14 |
| R4.17 | Allocation and throughput benchmarks of the executor | MUST | M5 |
| R4.18 | Look-ahead: `info.selection`, a tree of the requested fields computed once from the `OperationPlan` (fragments flattened, `@skip` / `@include` applied, type conditions resolved with `forType`, aliases and arguments per occurrence, `__typename` hidden, a `fingerprint` per sub-selection usable as a DataLoader key, `@defer`red fields flagged `isDeferred`); string-path access (`has('posts.comments')`, children and arguments accessors); typed field handles only if the builder yields them at no extra cost. The field-to-column mapping lives at the call site; the library offers only an allowlist helper and no built-in preload | MUST | M5 |
| R4.19 | `Authorizer`: a typed hook called by the executor around field resolution and exposed to look-ahead and the pipeline, plus a lint / test helper that reports schema fields and types with no authorization coverage; no policy engine | MUST | M5 |
| R4.20 | `CancelSignal` in the execution context, observable by resolvers; an execution timeout in the pipeline options; cancellation and timeout reported as errors with stable codes (`GQL3xx`); subscriptions end on cancellation | MUST | M5 |

## R5. Server pipeline and transports

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R5.1 | `GraphQLServer<C>` pipeline `request → parse → validate → execute / subscribe`; a typed context factory | MUST | M6 |
| R5.2 | Caching of parsed and validated documents by query hash | MUST | M6 |
| R5.3 | `ServerExtension` with `next`-chained phase hooks | MUST | M6 |
| R5.4 | Built-in extensions: limits, APQ, trusted documents, introspection policy, error masking, CSRF prevention | MUST | M6 |
| R5.5 | GraphQL over HTTP: GET / POST, media-type negotiation, status codes per the spec | MUST | M7 |
| R5.6 | Multipart uploads (jaydenseric spec), `Upload` scalar | MUST | M7 |
| R5.7 | graphql-ws (`graphql-transport-ws`): full state machine and close codes | MUST | M7 |
| R5.8 | graphql-sse: distinct-connections and single-connection modes | MUST | M7 |
| R5.9 | Transport handlers without `dart:io`; a `shelf` adapter with an optional GraphiQL page | MUST | M7 |
| R5.10 | Incremental delivery over `multipart/mixed` and SSE | MUST | M14 |
| R5.11 | Federation subgraph support (vocabulary chosen at the stage) | MUST | M15 |
| R5.12 | Response cache, OpenTelemetry-style tracing, request batching | LATER | — |
| R5.13 | Relay helpers: connection builder, `Node` interface | LATER | — |
| R5.14 | Cost limit in the request pipeline: a cost analyzer enforces a configured maximum, using `@cost` / `@listSize` (R3.8) | MUST | M6 |
| R5.15 | `ServerProfile` with `development` and `production`; `production` is secure by default: introspection, "did you mean" suggestions and batching off; errors masked (generic message, stable code, details only in logs and extensions hooks); depth, cost and alias limits and CSRF protection on; `development` is permissive (introspection, suggestions, GraphiQL in the shelf adapter); each protection is also configurable on its own | MUST | M6 |

## R6. Server code generation

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R6.1 | One emitter shared by both front ends; output is standalone `*.graphql.dart` libraries (no `part`), user files are never rewritten | MUST | M8 |
| R6.2 | SDL-first: bind types to existing classes or generate models; bind fields to getters with a type check; abstract resolver classes only for unbound fields; directives as typed middleware slots | MUST | M8 |
| R6.3 | Annotations: `@GraphQLObject`, `@Field`, `@Ignore`, `@GraphQLInput`, root annotations; sealed → union / interface; nullability, defaults, descriptions and deprecations from Dart | MUST | M9 |
| R6.4 | The annotation front end emits `schema.graphql` | MUST | M9 |
| R6.5 | `analyzer` is used only in `typed_graphql_builder` | MUST | M9 |

## R7. Client code generation

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R7.1 | Config `typed_graphql.yaml`; schema from a file or an introspection URL | MUST | M10 |
| R7.2 | All documents form one fragment graph and are validated with every diagnostic reported as `file:line:col` | MUST | M10 |
| R7.3 | Operation-based, pruned data classes with `==`, `hashCode`, `toString`, `toJson` | MUST | M10 |
| R7.4 | Fragment classes reached through `fragments`; masking by shape | MUST | M10 |
| R7.5 | Union / interface: sealed class with a mandatory `Unknown` variant | MUST | M10 |
| R7.6 | Enum: `XKnown(XValue)` / `XUnknown(raw)` | MUST | M10 |
| R7.7 | Variables classes; `Optional<T?>` only where absence differs from `null` | MUST | M10 |
| R7.8 | Scalar mapping with codecs; unmapped custom scalars are `JsonValue` | MUST | M10 |
| R7.9 | Operation metadata (minified document with `__typename`, name, sha256) and a persisted-operations manifest | MUST | M10 |
| R7.10 | Deterministic output; the CLI and `build_runner` produce identical files; golden tests | MUST | M10 (CLI), M9 (builder) |
| R7.11 | Cache selection metadata in generated code | MUST | M12 |
| R7.12 | Warnings about dangerous schema changes | MUST | M13 |
| R7.13 | Client `@defer` / `@stream` | MUST | M14 |
| R7.14 | `@catch` / `FieldResult` codegen; generated test data builders | LATER | — |

## R8. Client runtime

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R8.1 | `GraphQLClient`: `query`, `mutate` (`Future`), `watchQuery`, `subscribe` (`Stream`) | MUST | M11 |
| R8.2 | `GraphQLResponse<D>` sealed: `GraphQLData`, `GraphQLErrors`, `GraphQLTransportFailure`; nothing throws | MUST | M11 |
| R8.3 | `Link` chain returning `Stream` | MUST | M11 |
| R8.4 | Links: HTTP over any `http.Client`, WebSocket (graphql-transport-ws), SSE, split, retry, dedupe, APQ, auth with refresh, multipart uploads | MUST | M11 |
| R8.5 | `MockLink` for tests | MUST | M11 |
| R8.6 | Relay connection pagination helpers | LATER | — |
| R8.7 | `typed_graphql_flutter` widgets | LATER | — |

## R9. Normalized cache

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R9.1 | Record store keyed by cache id; `typePolicies` with default `__typename:id` | MUST | M12 |
| R9.2 | Fetch policies `cacheFirst`, `networkOnly`, `cacheOnly`, `cacheAndNetwork`, `noCache` | MUST | M12 |
| R9.3 | `watchQuery` re-emits on change | MUST | M12 |
| R9.4 | Optimistic layer separate from the base store | MUST | M12 |
| R9.5 | Mark-and-sweep GC rooted at active watches | MUST | M12 |
| R9.6 | Typed `readFragment` / `writeFragment` | MUST | M12 |
| R9.7 | Persistent sqlite backend with a versioned format | LATER | — |

## R10. Quality and conformance

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R10.1 | typed_openapi code rules; its `analysis_options.yaml` adapted from typed_openapi's (comments rewritten; extra lints `simple_directive_paths`, `no_dynamic_casts`, `no_raw_types`) | MUST | M1 |
| R10.2 | Size-limit ratchet and core layer-direction tests | MUST | M1 |
| R10.3 | `typed_graphql_conformance` with ported graphql-js suites and a coverage mapping table | MUST | M2 onward |
| R10.4 | Parse → print → parse fuzzing | MUST | M2 |
| R10.5 | CI: minimum SDK + stable; AOT runs; dart2js and dart2wasm for the core and the client; publish dry-run | MUST | M1 |
| R10.6 | Differential testing against graphql-js and the `graphql-http` audit, nightly | SHOULD | M16 |

## R11. Documentation

| ID | Requirement | Tag | Stage |
|---|---|---|---|
| R11.1 | basalt-style root README and package READMEs | MUST | each stage, polished in M16 |
| R11.2 | `packages/*/doc/*.md` guides tied to dartdoc categories; every public member documented | MUST | each stage |
| R11.3 | A CHANGELOG per package with `**Breaking:**` entries | MUST | each stage |
| R11.4 | Process documents in English (`docs/`), `CLAUDE.md`, `CONTRIBUTING.md` | MUST | M1 |
| R11.5 | A full-stack example: shelf server and a client using generated code | MUST | M16 |
