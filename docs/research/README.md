# typed_graphql: research summary and decisions

Date: **2026-10-13**. Compiled from five parallel studies; the primary sources
(specifications at fixed commits, source code, issues) and details are in files
`01…05` of this folder. The specifications themselves are in the git-ignored
`reference/` (fetch with `tool/fetch_reference.sh`). Architecture:
[../superpowers/specs/2026-10-13-typed-graphql-design.md](../superpowers/specs/2026-10-13-typed-graphql-design.md).
Requirements: [../requirements.md](../requirements.md).

| File | Topic |
|---|---|
| [01-spec-and-protocols.md](01-spec-and-protocols.md) | Spec editions and their diff, full feature inventory, the 30 validation rules, RFC status, protocols (HTTP, graphql-ws, graphql-sse, uploads, APQ, Relay, Federation), implementation checklist |
| [02-dart-ecosystem.md](02-dart-ecosystem.md) | `gql`, ferry, graphql_flutter, graphql_codegen, leto and others; the defects catalog D1–D15 |
| [03-server-prior-art.md](03-server-prior-art.md) | graphql-js, graphql-java, apollo-rs, async-graphql, juniper, Hot Chocolate, Caliban, Sangria, gqlgen, Pothos, Grats and more; the recommended server architecture |
| [04-client-prior-art.md](04-client-prior-art.md) | Apollo Kotlin and iOS, graphql-codegen, gql.tada, Relay, urql, Apollo Client 4, cynic, Strawberry Shake; the recommended client design |
| [05-dart-language-and-platform.md](05-dart-language-and-platform.md) | Dart 3.13 features, performance facts, codegen ecosystem churn, the SDK constraint |

Legend: ✅ take · ⚠️ adapt · ❌ avoid.

---

## 0. Briefly

1. **The niche is open.** No Dart package implements GraphQL as a whole. `gql` is
   tooling without execution or introspection, and its validator checks almost
   nothing about operations against a schema (02 §0.1–0.2). Server packages (leto,
   the angel3 line) are not spec-complete. `@defer` / `@stream` exist nowhere in
   Dart (02 D12).
2. **The baseline is September2025.** It adds `@oneOf`, schema coordinates,
   descriptions on executable definitions, wider `@deprecated`, full Unicode. The
   `main` working draft goes further (empty selection sets, directive extensions,
   deprecation of directives) and is not a release (01 §1).
3. **graphql-js v17 is released** and is our conformance corpus. Its `@defer` /
   `@stream` remain experimental because incremental delivery is still an RFC draft
   (01 §8).
4. **Nullability work has not settled.** The Nullability WG was archived on
   2026-02-05 in favour of "service capabilities + `onError`"; semantic nullability
   and fragment arguments are Strawman. We leave extension points, nothing more
   (01 §9–10).
5. **Every serious implementation converges on the same core:** a hand-written,
   error-resilient parser; typestate for validated schemas and documents; rules
   fused into one walk; a synchronous fast path in the executor; middleware composed
   at build time; a cached operation plan (03 §0).
6. **The real choice is where server types come from.** Dart has no runtime
   reflection in AOT and no macros, but has reified generics and `build_runner`.
   That makes a typed builder viable as the runtime IR, with code generators on top
   (03 §19.3).
7. **Clients converge too:** document-first, operation-based pruned codegen;
   mandatory `Unknown` variants for unions, interfaces and enums; two-variant
   `Optional`; a `Stream`-returning link chain; a record store with an optimistic
   overlay and explicit GC (04 §0).
8. **Dart 3.13 is the latest stable and ships in Flutter 3.47 stable**, so
   `^3.13.0` excludes nobody on current Flutter (05 §0).

## 1. Decisions (2026-10-13)

| Question | Decision |
|---|---|
| Name | `typed_graphql`, packages `typed_graphql_*`; `graphql_schema`, `graphql_server`, `graphql_client`, `graphql_codegen` are taken on pub.dev |
| Priority | The shared core first (language, type system, validation); then the server and the client as parallel roadmap branches |
| Relation to `package:gql` | **Full independence**: own AST, transports and client, no bridge package (the research suggested a bridge, 02 §0.10; rejected by the user) |
| Spec baseline | September2025; working-draft grammar and introspection behind options; RFCs only with extension points or opt-in |
| SDK | `^3.13.0` everywhere, generated code included; all stable 3.13 features (primary constructors included, unlike typed_openapi's 3.10 floor) |
| Packages | Split by consumer: one core package with internal layers; server; shelf adapter; client; codegen engine + CLI (no `analyzer`); builder (the only `analyzer` user); conformance tool (research 03 suggested a package per layer; rejected as too fine) |
| Error model | No exceptions on bad input; sealed results with every diagnostic; exceptions only for programmer errors and inside user resolvers |
| AST | Sealed `final` classes; `NonNullType` wrapper; raw numeric lexemes; no `==` override, `isEquivalentTo` instead; a failed parse returns a partial document without error nodes |
| Typestate | `ValidSchema`, `ValidDocument`: `final class` + private constructor (not extension types, which a cast can forge) |
| Server typing | A typed builder as the runtime IR, usable without codegen; two generators emitting builder code: annotations (`typed_graphql_builder`) and SDL-first (`typed_graphql_codegen`) |
| Executor | `FutureOr` fast path, pure lane, cached plan, middleware folded at build, error behaviour as a parameter |
| Client codegen | Document-first, operation-based, pruned; eager `final` data classes with `==`; fragments through `fragments` accessors (masking by shape) |
| Generated shapes | Unions / interfaces: sealed + mandatory `Unknown`; enums: `XKnown(XValue)` / `XUnknown(raw)`; `Optional<T?>` only where absence differs from `null`; unknown scalars are `JsonValue` |
| Generated files | Standalone `*.graphql.dart` libraries, never `part` files (research 04 suggested part files; rejected by the code rules) |
| Backing map + extension types for data (research 04 §13) | Rejected: extension types are erased, so they cannot form sealed hierarchies or support `is`; eager `final` classes are simpler to debug and give `==` |
| Client errors | `GraphQLResponse` sealed: `GraphQLData`, `GraphQLErrors`, `GraphQLTransportFailure` |
| Transports | graphql-transport-ws only (no legacy `subscriptions-transport-ws`); graphql-sse both modes; jaydenseric uploads; APQ and trusted documents |
| Federation | Later (M15); Apollo Federation v2 vs Composite Schemas chosen at that stage |
| Code style | typed_openapi rules and `analysis_options.yaml` |
| User documentation style | basalt (README skeleton, `doc/*.md` guides with dartdoc categories, CHANGELOG format) |
| Process documents | typed_openapi structure, in English |

## 2. What we take, by layer

| Layer | ✅ Take | ❌ Avoid | Source |
|---|---|---|---|
| Lexer | `codeUnitAt` cursor; never throws; comments as trivia | dropping comments (graphql-js #2241) | 03 §19.2 |
| Parser | recursive descent, resynchronisation, all errors in one pass | throw on first error (graphql-js #1426) | 03 §4.1 (apollo-parser) |
| AST | sealed families, `NonNullType` wrapper | `isNonNull` flag, recomputed `==` (gql, 02 D3–D4) | 02, 03 §8 |
| Visitors | no-op defaults, `ParallelVisitor` | fully abstract visitor with ~40 methods (gql, 02 D6) | 02, 03 §2.4 |
| Validation | one class per rule, one walk, Sangria overlap algorithm | quadratic overlap check (graphql-js #2185) | 03 §2.4, §12 |
| Typestate | `Valid<T>` with a private constructor | forgeable wrappers | 03 §4.3 (apollo-compiler) |
| Executor | `FutureOr`, pure lane, plan cache, single flight | a `Future` per field (graphql-java #3331), per-request field collection (graphql-js #4008) | 03 §10, §19.5 |
| Middleware | composed once at build; `next`-chained extensions | 20-hook instrumentation, monkey-patching | 03 §5, §10, §16 |
| DataLoader | batch and grouped loaders, request-scoped, microtask dispatch | laziness-dependent designs | 03 §10, §11 |
| Server typing | typed builder IR + annotations + SDL-first | runtime reflection | 03 §19.3 |
| Client codegen | document-first, operation-based, pruned | response-based blowup (Apollo Kotlin #3144), built_value output size (ferry #143, #558) | 04 §0.1, 02 D8 |
| Abstract types on the client | sealed with `Unknown` | `__typename` handling that breaks under obfuscation (gql #242, ferry #319) | 04 §0.2, 02 D7 |
| Cache | record store, typePolicies, optimistic overlay, explicit GC | in-place optimistic mutation | 04 §0.9–0.10 |
| Links | `Stream`-returning chain | `Future`-only links retrofitted for `@defer` | 04 §0.8 |
| APQ | working APQ + trusted documents | graphql_flutter's "out of service" APQ (02 D10) | 01 §12.7, 02 |

## 3. Open questions (decided at their stage)

| Question | Stage |
|---|---|
| Exact builder method names (`t.field` / `t.pure`, argument classes) | M5 spec |
| Generated naming scheme for nested selection classes | M10 spec |
| Federation vocabulary: Apollo v2, Composite Schemas or both | M15 spec |
| Whether `typed_graphql_flutter` is needed at all | after M12 |
| When to adopt `onError` / semantic nullability | when the spec PR lands |
