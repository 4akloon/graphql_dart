# typed_graphql

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-core-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**GraphQL for Dart, written from scratch and fully typed: the language, the
type system, validation and the wire protocol, with diagnostics instead of
exceptions.** Pure Dart, depends only on `meta`, runs on the VM, AOT and the
web (dart2js and dart2wasm). Part of
[typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** This release has the diagnostics model and
> the protocol data types. The parser arrives in M2, the type system in M3 and
> validation in M4 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

## Contents

- [Install](#install)
- [Reading the wire format](#reading-the-wire-format)
- [Diagnostics](#diagnostics)
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

## Reading the wire format

Bad input never throws. `JsonReader` turns text into a `JsonValue`, a sealed
family you can switch over; the `decode` methods turn a `JsonValue` into
`GraphQLRequest`, `GraphQLError` or `ResponsePayload`. Each step gives a
`DecodeResult`: a `DecodeSuccess`, or a `DecodeFailure` that says where the
input is wrong.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const reader = JsonReader();

  // A request body from the wire: unknown keys are ignored.
  final request = switch (reader.parse('{"query": "{ hero { name } }"}')) {
    DecodeSuccess(:final value) => GraphQLRequest.decode(value),
    final DecodeFailure failure => failure,
  };
  print(request);

  // A failure says where the input is wrong.
  final response = switch (reader.parse('{"errors": [{"message": 7}]}')) {
    DecodeSuccess(:final value) => ResponsePayload.decode(value),
    final DecodeFailure failure => failure,
  };
  print(response);

  // Spans turn offsets into lines and columns.
  final source = Source('{\n  hero\n}', name: 'hero.graphql');
  print(SourceSpan(source, 4, 8));
}
```

It prints:

```text
DecodeSuccess(GraphQLRequest({"query":"{ hero { name } }"}))
$.errors[0].message: expected a string
hero.graphql:2:3
```

`JsonReader` rejects input nested deeper than `maxDepth` (512 by default)
before decoding it, and numbers too large to be finite. A `ResponsePayload`
is an `ExecutionResult` (it has `data`, maybe `null`) or a
`RequestErrorResult` (no `data`, at least one error).

## Diagnostics

The parser and the validator will report through this model:

- `Source` is a document and its name; `locationOf(offset)` gives a 1-based
  line and column, counted in UTF-16 code units.
- `SourceSpan` is a range of a `Source`.
- `Diagnostic` is one problem: a `DiagnosticCode` with a stable id
  (`GQL000`), a severity, a message, a span and related spans.
- `DiagnosticSink` collects diagnostics in order and stops at `maxErrors`
  errors (100 by default), reporting `GQL000` once.

## License

MIT — see [LICENSE](LICENSE).
