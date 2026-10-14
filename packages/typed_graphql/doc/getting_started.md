# Getting Started

`typed_graphql` is the core of [typed_graphql](https://github.com/4akloon/graphql_dart),
GraphQL for Dart written from scratch and fully typed. It reads, checks,
prints and transforms GraphQL, and it speaks the wire format. It is pure
Dart, depends only on `meta`, and runs on the VM, AOT, dart2js and dart2wasm.

The package is built in layers. A layer imports only the layers before it:

| Layer | Topic | What it gives you |
|---|---|---|
| diagnostics | **Diagnostics** | `Source`, `SourceSpan`, `Diagnostic`, `DiagnosticCode`, `DiagnosticSink` |
| language | **Language** | `Parser`, `Printer`, the syntax tree, `AstWalker`, `AstTransformer`, schema coordinates |
| protocol | **Wire Protocol** | `JsonValue`, `JsonReader`, `GraphQLRequest`, `ResponsePayload`, `GraphQLError` |
| schema | **Schema**, **Scalars & Codecs** | `Schema`, `SchemaBuilder`, `SchemaPrinter`, `ScalarCodec` |

Everything is exported from one library, `package:typed_graphql/typed_graphql.dart`.

## Install

Nothing is on pub.dev yet. To use it from the repository:

```yaml
dependencies:
  typed_graphql:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql
```

## A first program

Parse an operation and print it the way graphql-js does, then build a schema
from SDL:

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  final query = Source('query Hero { hero { name } }', name: 'hero.graphql');
  if (parser.parse(query) case ParseSuccess(:final document)) {
    print(const Printer().print(document));
  }

  final sdl = Source('type Query { hero: String }', name: 'schema.graphql');
  final result = const SchemaBuilder().fromSdl(
    parser.parse(sdl).requireDocument(),
    source: sdl,
  );
  switch (result) {
    case BuildSuccess(:final schema):
      print('query root: ${schema.queryTypeName}');
    case BuildFailure(:final diagnostics):
      diagnostics.forEach(print);
  }
}
```

It prints:

```text
query Hero {
  hero {
    name
  }
}
query root: Query
```

## Four rules

- **Bad input never throws.** A syntax error, an invalid schema or a mistyped
  JSON body becomes a value you inspect: a diagnostic or a `DecodeFailure`.
  Exceptions are for programmer errors only (`ArgumentError`, `RangeError`, `StateError`).
- **Results are sealed.** `ParseSuccess` or `ParseFailure`, `BuildSuccess` or
  `BuildFailure`, `DecodeSuccess` or `DecodeFailure`: a `switch` over them is
  checked by the compiler, and a parse or build failure carries the partial
  result.
- **Every problem has a code and a place.** A `Diagnostic` has a stable id
  (`GQL008`), a message and the span of the source it is about. All of them
  are reported in one pass, not only the first.
- **No `dynamic`.** Arbitrary JSON is a `JsonValue`, a sealed family you can
  switch over.

## Where to go next

- **Language** — parse, print, walk and rewrite documents; schema coordinates.
- **Diagnostics** — sources, spans, codes, and how to report your own.
- **Wire Protocol** — requests, responses and errors as typed values.
- **Schema** — build a schema from SDL, extend it, print it.
- **Scalars & Codecs** — the built-in scalar codecs and your own.
- **Introspection** — the introspection query, a schema's answer, and a
  schema built from an answer.

The API reference lists every type under the same topics.
