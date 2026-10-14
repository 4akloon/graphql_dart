# typed_graphql

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-core-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Parse, print and transform GraphQL queries and SDL in Dart, build and
validate a schema from SDL, and decode GraphQL responses into sealed
`ResponsePayload` values, with every syntax error reported in one pass with
its line and column.** Pure Dart, depends only on `meta`, runs on the VM, AOT
and the web (dart2js and dart2wasm). Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** This release has the diagnostics model, the
> protocol data types, the language (syntax trees, lexer, parser, printer,
> visitors, transformers, schema coordinates) and the schema (its model, building and
> extending it from SDL, printing it, scalar codecs, validating it,
> introspection both ways, resolving schema coordinates). Document validation
> arrives in M4 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

## Contents

- [Install](#install)
- [Should I use this?](#should-i-use-this)
- [A quick tour](#a-quick-tour)
- [Guides](#guides)
- [License](#license)

## Install

Nothing is on pub.dev yet. To try it from the repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## Should I use this?

- **Use it when** you need to parse, print, rewrite or inspect GraphQL text,
  or build and validate a schema from SDL, in Dart (VM, web or Wasm), and want
  every problem as a diagnostic with a stable code (and a place when the
  source is given), or a decode failure with a path
  ([Language](doc/language.md#parsing-a-document),
  [Schema](doc/schema.md#building-a-schema-from-sdl),
  [Diagnostics](doc/diagnostics.md#reading-a-diagnostic)).
- **You do not need it when** you only send a query string to a server and
  read the JSON back. Today it also does not validate an operation against a
  schema or execute one: operation validation arrives in this package in M4,
  and execution in `typed_graphql_server` (M5).
- **What it replaces**: matching GraphQL text with regular expressions or
  string splitting, and reading responses as `Map<String, dynamic>`. A regular
  expression does not see comments, block strings or nested selections, and
  fails silently on them; a dynamic map reads `errors` and `path` without
  checking their shape, so a wrong field is a runtime cast error far from its
  cause. Here a document is a syntax tree, and `ResponsePayload.decode` checks
  a response and names the path of a wrong field
  ([Wire protocol](doc/protocol.md#responses),
  [decode results](doc/protocol.md#decode-results)).
- **Which package**: this one, the core, which depends only on `meta`. The
  server, client and code generation packages build on it and are not usable
  yet.

## A quick tour

Bad input never throws: a syntax error or a problem in the SDL is a value you
inspect. The same program is in [example/example.dart](example/example.dart).

```dart
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  // Every syntax error in one pass, each with a stable code and a place.
  final broken = Source('query { a(x: ) }', name: 'bad.graphql');
  if (parser.parse(broken) case ParseFailure(:final diagnostics)) {
    diagnostics.forEach(stdout.writeln);
  }

  // A document prints back the way graphql-js prints it.
  final query = Source('query Hero{hero{name}}', name: 'hero.graphql');
  if (parser.parse(query) case ParseSuccess(:final document)) {
    stdout.writeln(const Printer().print(document));
  }

  // SDL builds a schema; a problem in it is a diagnostic, not an exception.
  final sdl = Source('type Query { hero: String }', name: 'schema.graphql');
  final result = const SchemaBuilder().fromSdl(
    parser.parse(sdl).requireDocument(),
    source: sdl,
  );
  switch (result) {
    case BuildSuccess(:final schema):
      stdout.writeln('query root: ${schema.queryTypeName}');
    case BuildFailure(:final diagnostics):
      diagnostics.forEach(stdout.writeln);
  }
}
```

It prints:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
query Hero {
  hero {
    name
  }
}
query root: Query
```

## Guides

Each guide is a short, runnable walk through one layer; every program in them
is run by the test suite, so what they print is what the package does.

| Guide | Covers |
|---|---|
| [Getting started](doc/getting_started.md) | The layers, the four rules, a first program |
| [Language](doc/language.md) | Parse, print, visit and rewrite documents; schema coordinates; tokens |
| [Diagnostics](doc/diagnostics.md) | Sources, spans, codes, the sink |
| [Wire protocol](doc/protocol.md) | `JsonValue`, requests, responses, errors |
| [Schema](doc/schema.md) | Build a schema from SDL, read it, validate it, extend it, print it; resolve coordinates |
| [Scalars and codecs](doc/scalars.md) | The built-in codecs and your own |
| [Introspection](doc/introspection.md) | Write the introspection query, answer it from a schema, build a schema from an answer |

The API reference is generated by `dart doc` and groups every type under the
same topics. Run it in this directory and open `doc/api/index.html`.

## License

MIT — see [LICENSE](LICENSE).
