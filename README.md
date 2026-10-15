# typed_graphql

[![CI](https://github.com/4akloon/graphql_dart/actions/workflows/ci.yml/badge.svg)](https://github.com/4akloon/graphql_dart/actions/workflows/ci.yml)
![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Status](https://img.shields.io/badge/status-under%20construction-orange)
![License](https://img.shields.io/badge/license-MIT-brightgreen)

**GraphQL for Dart, written from scratch and fully typed: the whole
September2025 specification and its protocols, on the server and on the
client, with diagnostics instead of exceptions.**

What it is built to be (see the [roadmap](docs/roadmap.md)):

- 🧾 **Spec-complete language** — an error-resilient parser that reports every
  syntax error in one pass, a sealed AST, a printer and visitors (M2).
- 🧱 **Type system and validation** — SDL and introspection to a validated
  schema, all 30 validation rules in one walk (M3, M4).
- 🖥️ **Typed server** — a typed schema builder, a `FutureOr` executor,
  subscriptions, DataLoader, GraphQL over HTTP, graphql-ws and graphql-sse
  (M5–M9).
- 📱 **Typed client** — operation-based code generation, links, a normalized
  cache (M10–M12).
- 🚫 **No `dynamic`, no exceptions on bad input** — sealed results that carry
  every diagnostic, each with a stable code.

What works today: the language (parse, print, visit and transform queries and
SDL), the schema (build it from SDL, extend, print and validate it, introspection
both ways, schema coordinates), operation validation, the wire protocol types,
scalar codecs and the diagnostics model; and, in `typed_graphql_server`, a
typed schema builder, the execution of a validated operation, introspection,
subscriptions, look-ahead at the requested fields, field authorization,
cancellation, DataLoader and a transport-agnostic request pipeline
(`GraphQLServer`: limits, the cost limit, CSRF prevention, extensions,
automatic persisted queries and trusted documents).

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const body = '''
{
  "errors": [
    {
      "message": "Name for character with ID 1002 could not be fetched.",
      "locations": [{"line": 6, "column": 7}],
      "path": ["hero", "heroFriends", 1, "name"]
    }
  ],
  "data": {"hero": {"name": "R2-D2", "heroFriends": [null, null]}}
}''';

  final payload = switch (const JsonReader().parse(body)) {
    DecodeSuccess(:final value) => ResponsePayload.decode(value),
    final DecodeFailure failure => failure,
  };
  switch (payload) {
    case DecodeSuccess(value: ExecutionResult(:final data, :final errors)):
      print('data: $data');
      print('first error at ${errors.first.path}');
    case DecodeSuccess(value: RequestErrorResult(:final errors)):
      print('the request failed: ${errors.first.message}');
    case final DecodeFailure failure:
      print('not a GraphQL response: $failure');
  }
}
```

> **Status: under construction.** Nothing is published to pub.dev yet, and
> every API may change before 0.1.0. Stages M2 (language) and M3
> (the schema: building it from SDL, extending, printing and validating it,
> resolving schema coordinates, and introspection in both directions) are
> done, and so is M4 (operation validation by the specification's 30 rules,
> limits and cost analysis).

## Table of contents

- [Why typed_graphql](#why-typed_graphql)
- [Packages](#packages)
- [Install](#install)
- [Getting started](#getting-started)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Why typed_graphql

GraphQL in Dart is often handled by hand: regular expressions over query
text, `Map<String, dynamic>` for responses, exceptions for bad input. Each
fails late and far from its cause. This repository is built to cover the whole
specification, `@defer` and `@stream` included, with one design: a
hand-written error-resilient parser, typestate for validated schemas and
documents, validation rules fused into one walk, a synchronous fast path in
the executor, and document-first, operation-based client code generation (the
reasoning is in the [research](docs/research/README.md)). Compared with those
approaches:

- **Typed end to end.** Arbitrary JSON is `JsonValue`, a sealed family you
  can switch over, not a dynamic map; there is no `dynamic` in any public
  signature.
- **Every problem at once.** The parser reports every syntax error in one
  pass, and schema building and validation report every diagnostic, each with
  a stable code (`GQL0xx`-`GQL5xx`) and a source location; so does
  operation validation.
- **Conformance is measured.** The graphql-js v17 language and schema suites
  are ported with a mapping table (`typed_graphql_conformance`), and the core
  tests also run AOT-compiled and in the browser (dart2js and dart2wasm). The
  validation and execution suites are ported too.
- **Independent.** The core is pure Dart and depends only on `meta`.

## Packages

This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.

| Package | Role | Status |
|---|---|---|
| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics, protocol types, the language, the schema model, SDL, scalar codecs, schema validation, introspection, operation validation, limits and cost analysis (M1, M2, M3, M4) |
| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | builder, query execution, introspection, subscriptions, look-ahead, authorization, cancellation (M5, complete), DataLoader, the request pipeline and persisted documents (M6, complete) |
| [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | under construction (the generated-code contract, M10; the rest M11) |
| [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | under construction (M10) |
| [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | language, schema, introspection, validation and execution suites, fuzzers, benchmarks (M2-M5) |

## Install

Nothing is on pub.dev yet. To try the core from this repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## Getting started

The core reads untrusted JSON into typed values and never throws on bad
input:

- `JsonReader().parse(text)` gives a `JsonValue`, or a `DecodeFailure` that
  says where the input is wrong (`$.errors[0].message: expected a string`).
- `GraphQLRequest.decode`, `GraphQLError.decode` and `ResponsePayload.decode`
  read the GraphQL wire format; `toJson()` writes it.
- `Parser().parse(Source(text))` gives a `Document`, or every syntax error
  as a `Diagnostic` with a code and a place; `Printer().print(node)` prints
  it back the way graphql-js does.
- `AstWalker` walks a tree with an `AstVisitor`, `AstTransformer` rewrites
  one, and `Parser().parseSchemaCoordinate` reads `Query.hero(episode:)`.

## Documentation

Guides for the core package, `typed_graphql`. Every program in them is run by
the test suite, so what they print is what the package does:

- [Getting started](packages/typed_graphql/doc/getting_started.md) · [Language](packages/typed_graphql/doc/language.md) ·
  [Diagnostics](packages/typed_graphql/doc/diagnostics.md) · [Wire protocol](packages/typed_graphql/doc/protocol.md) ·
  [Schema](packages/typed_graphql/doc/schema.md) · [Scalars and codecs](packages/typed_graphql/doc/scalars.md) · [Introspection](packages/typed_graphql/doc/introspection.md)
- API reference: run `dart doc` in `packages/typed_graphql` and open
  `doc/api/index.html`; the types are grouped under the same topics.
- A runnable [example](packages/typed_graphql/example/example.dart)

For contributors and the design:

- [Roadmap](docs/roadmap.md) · [Requirements](docs/requirements.md) ·
  [Architecture](docs/superpowers/specs/2026-10-13-typed-graphql-design.md)
- [Research and decisions](docs/research/README.md)
- [CLAUDE.md](CLAUDE.md) — the repository guide for contributors and AI agents

## Contributing

Setup, commands, the design rules and the coding conventions are in
**[CONTRIBUTING.md](CONTRIBUTING.md)**. The short version:

```sh
dart pub get
dart analyze --fatal-infos
dart test && (cd packages/typed_graphql && dart test)
```

## License

MIT — see [LICENSE](LICENSE).
