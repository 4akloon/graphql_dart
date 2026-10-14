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

What works today: the diagnostics model and the wire protocol types.

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
> every API may change before 0.1.0. Stage M1 (foundations) is the current
> one; the parser arrives in M2.

## Table of contents

- [Why typed_graphql](#why-typed_graphql)
- [Packages](#packages)
- [Install](#install)
- [Getting started](#getting-started)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Why typed_graphql

No Dart package implements GraphQL as a whole. `package:gql` is tooling
without execution or introspection, the server packages are not
spec-complete, and `@defer` / `@stream` exist nowhere in Dart
([research](docs/research/README.md)). typed_graphql takes the design every
serious implementation converged on: a hand-written error-resilient parser,
typestate for validated schemas and documents, validation rules fused into
one walk, a synchronous fast path in the executor, and document-first,
operation-based client code generation.

- **Typed end to end.** Arbitrary JSON is `JsonValue`, a sealed family you
  can switch over; there is no `dynamic` in any public signature.
- **Every problem at once (from M2).** Parsing and validation will report
  every diagnostic with a stable code (`GQL0xx`–`GQL5xx`) and a source
  location.
- **Conformance is measured (from M2).** The graphql-js v17 suites will be
  ported with a mapping table, and every suite will also run AOT-compiled and
  in the browser. M1 already runs its own tests on the VM, dart2js and
  dart2wasm.
- **Independent.** No dependency on `package:gql`; the core is pure Dart and
  depends only on `meta`.

## Packages

This repository is a Dart **pub workspace**. Dart SDK: `^3.13.0`.

| Package | Role | Status |
|---|---|---|
| [`typed_graphql`](packages/typed_graphql) | Core: language, type system, validation, wire protocol, diagnostics. Pure Dart, depends only on `meta`. | diagnostics and protocol types (M1) |
| [`typed_graphql_server`](packages/typed_graphql_server) | Typed schema builder, executor, subscriptions, DataLoader, HTTP / graphql-ws / graphql-sse handlers. | skeleton (M5) |
| [`typed_graphql_shelf`](packages/typed_graphql_shelf) | `shelf` adapter with an optional GraphiQL page. | skeleton (M7) |
| [`typed_graphql_client`](packages/typed_graphql_client) | Client runtime: links, transports, normalized cache, `MockLink`. | skeleton (M11) |
| [`typed_graphql_codegen`](packages/typed_graphql_codegen) | Code generation engine and CLI, without `analyzer`. | skeleton (M8, M10) |
| [`typed_graphql_builder`](packages/typed_graphql_builder) | `build_runner` builders and the annotation front end. | skeleton (M9) |
| [`typed_graphql_conformance`](packages/typed_graphql_conformance) | Repository tool: ported graphql-js suites, fuzzers, benchmarks. Never published. | skeleton (M2) |

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
- `Source`, `SourceSpan`, `Diagnostic` and `DiagnosticSink` are the
  diagnostics model the parser and validator will report through.

## Documentation

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
