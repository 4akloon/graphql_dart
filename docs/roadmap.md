# typed_graphql stage map

Date: 2026-10-13. Each stage gets its own design spec in `superpowers/specs/` and a
plan in `superpowers/plans/`, and each delivers a working, tested result.
Requirements: [requirements.md](requirements.md). Architecture:
[superpowers/specs/2026-10-13-typed-graphql-design.md](superpowers/specs/2026-10-13-typed-graphql-design.md).
Decisions: [research/README.md](research/README.md).

## Stages

### Core (critical path)

| # | Stage | What appears | Requirements | Depends on |
|---|---|---|---|---|
| M1 | Foundations | Pub workspace with all package skeletons (`sdk: ^3.13.0`); the old `lib/`, `example/`, `test/` deleted; `analysis_options.yaml` adapted from typed_openapi's; size-limit and layer-direction ratchet tests; CI (minimum SDK + stable, AOT, dart2js/dart2wasm, publish dry-run); `Source` with a lazy line table and spans; the `DiagnosticCode` catalog, `Diagnostic`, `DiagnosticSink`; `protocol/` data types (`GraphQLError`, request, response, `JsonValue`); `CLAUDE.md`, `CONTRIBUTING.md`, `docs/superpowers/HANDOFF.md` | R0.5, R0.6, R1.7 (Source), R1.12, R10.1, R10.2, R10.5, R11.4 | — |
| M2 | Language | Lexer, error-resilient parser of the September2025 grammar with working-draft options and limits, sealed AST, `isEquivalentTo`, visitors, `ParallelVisitor`, transformer, printer, schema coordinates; graphql-js lexer, parser, printer and visitor suites ported; round-trip fuzzing; the conformance package starts here; carried over from M1: give `Diagnostic` value equality (`==` / `hashCode`), because the ported suites compare lists of diagnostics, and enable the analyzer's strict-inference and strict-raw-types (staged in `analysis_options.yaml`) | R0.1, R0.7, R1.1–R1.11, R10.3, R10.4 | M1 |
| M3 | Type system | `Schema` model, SDL → `Schema` with extensions, schema validation → `ValidSchema`, `Schema` → SDL, built-ins, coordinates resolution, introspection query and introspection JSON → `Schema`, `ScalarCodec`; graphql-js `buildASTSchema` / `extendSchema` / type-validation suites ported | R2.1–R2.9 | M2 |
| M3c | Core documentation catch-up | `packages/typed_graphql/doc/` guides for what M2 and M3a shipped (`getting_started`, `language`, `diagnostics`, `schema`, `protocol`, `scalars`), `dartdoc_options.yaml` with categories, `example/example.dart`, the root README's Documentation section linking the guides; every public member documented (checked) | R11.1–R11.3 | M3b |
| M4 | Operation validation | `TypeInfo`, the 30 rules, one-walk validation, `ValidDocument`, opt-in limit rules, the `MaxCost` analysis rule with the opt-in `@cost` / `@listSize` built-in directives (IBM draft), custom rule API; graphql-js validation suites ported per rule | R3.1–R3.6, R3.8 | M3 |

### Server branch

| # | Stage | What appears | Requirements | Depends on |
|---|---|---|---|---|
| M5 | Execution | Typed `SchemaBuilder`, `ExecutableSchema`, variable coercion, `OperationPlan` and its cache, the `FutureOr` executor with the pure lane, error behaviours, masking, field middleware, introspection resolvers, subscriptions; look-ahead (`info.selection`), the `Authorizer` hook and its coverage lint, `CancelSignal` and execution timeout; graphql-js execution suites ported; benchmarks | R4.1–R4.14, R4.17–R4.20 | M4 |
| M6 | Server pipeline | `GraphQLServer`, document caches, `ServerExtension`, limits, APQ, trusted documents, CSRF prevention, the cost limit, `ServerProfile` (`development` / `production`), DataLoader | R4.15, R5.1–R5.4, R5.14, R5.15 | M5 |
| M7 | Transports | GraphQL over HTTP (CSRF protection and the batching policy applied at the transport), multipart uploads, graphql-ws, graphql-sse, `typed_graphql_shelf` with the GraphiQL page | R5.5–R5.9 | M6 |
| M8 | SDL-first generator | The shared server emitter in `typed_graphql_codegen`; type and field binding; abstract resolver classes; directive slots; generated selection classes for look-ahead; goldens | R6.1, R6.2 | M5, M10 |
| M9 | `build_runner` and annotations | `typed_graphql_builder`: builders for the client engine and the SDL-first generator, the annotation front end, `schema.graphql` emission | R6.3–R6.5, R7.10 | M8 |

### Client branch

| # | Stage | What appears | Requirements | Depends on |
|---|---|---|---|---|
| M10 | Client code generation | `typed_graphql_codegen` engine and CLI: config, schema loading, the project fragment graph, validation with file positions, emitter for data / fragment / union / enum / variables classes, operation metadata, persisted-operations manifest, goldens | R7.1–R7.10 | M4 |
| M11 | Client runtime | `GraphQLClient`, `GraphQLResponse`, links (HTTP, WebSocket, SSE, split, retry, dedupe, APQ, auth, uploads), `MockLink`; end-to-end tests against an in-memory `typed_graphql_server` once M7 exists | R8.1–R8.5 | M10 |
| M12 | Normalized cache | Record store, `typePolicies`, fetch policies, `watchQuery`, optimistic layer, GC, typed fragment reads and writes; cache metadata in generated code | R7.11, R9.1–R9.6 | M11 |

### After both branches

| # | Stage | What appears | Requirements | Depends on |
|---|---|---|---|---|
| M13 | Schema diff | `SchemaDiff` (port of graphql-js `findSchemaChanges`), a CLI command, dangerous-change warnings in the client generator | R2.10, R7.12 | M3 (can start any time after it), M10 for the warnings |
| M14 | Incremental delivery | `@defer` / `@stream`: validation rules, `executeIncrementally`, `multipart/mixed` and SSE framing, client support; tracks graphql-spec#1110 | R3.7, R4.16, R5.10, R7.13 | M7, M12 |
| M15 | Federation subgraph | `typed_graphql_federation`; the vocabulary (Apollo Federation v2 or Composite Schemas) chosen in the stage spec | R5.11 | M7 |
| M16 | Release | Full-stack example (shelf server + client with generated code), README polish, nightly differential testing against graphql-js and the `graphql-http` audit, pub.dev publishing | R10.6, R11.1, R11.5 | all |

## Order

1. M1 → M2 → M3 → M4 is the critical path; nothing else starts before M4, except
   M13's diff engine after M3.
2. After M4 the server branch (M5 → M6 → M7) and the client branch (M10 → M11 →
   M12) run in parallel.
3. M8 needs both M5 (the builder it targets) and M10 (the engine and config it
   extends); M9 follows M8.
4. The first useful result: after M4 the core validates real schemas and operations
   with full diagnostics. The first running server: after M7. The first generated
   client: after M11.

## Later (not in a stage)

`@catch` / `FieldResult` and `onError` once standardised; fragment arguments; a
persistent sqlite cache; Relay connection helpers (server and client); request
batching, response cache, tracing; `typed_graphql_flutter`; generated test data
builders; a lossless CST, formatter and LSP.

## Rules for plans

- One plan = one stage. Tasks of 2–5 minutes each, TDD, one commit per task.
- The plan contains all the code, without stubs. The code is checked (tests,
  `dart analyze`, `dart format`) before it goes into the plan.
- New diagnostic codes go into the `DiagnosticCode` catalog with a doc comment.
- A ported graphql-js test is recorded in the conformance mapping table in the same
  commit.
- Documentation ships with the stage (R11.1–R11.3), not in M16: the plan has a
  task for the stage's `packages/<pkg>/doc/*.md` guide, its category entry in
  `dartdoc_options.yaml`, a compiling snippet under `example/`, and the README and
  `CHANGELOG.md` changes. The plan's self-review checks that task exists.
