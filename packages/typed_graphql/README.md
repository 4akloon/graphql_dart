# typed_graphql

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-core-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**GraphQL for Dart, written from scratch and fully typed: the language, the
type system, validation and the wire protocol, with diagnostics instead of
exceptions.** Pure Dart, depends only on `meta`, runs on the VM, AOT and the
web (dart2js and dart2wasm). Part of
[typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** This release has the diagnostics model, the
> protocol data types, and the language: syntax trees, the lexer, the
> parser, the printer, visitors and schema coordinates. The type system
> arrives in M3 and validation in M4 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

## Contents

- [Install](#install)
- [Parsing and printing](#parsing-and-printing)
- [Visiting and rewriting](#visiting-and-rewriting)
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

## Parsing and printing

`Parser` turns a `Source` into a `Document`, or a `ParseFailure` with every
syntax error it found: after an error it skips to the next definition or
selection and goes on. `Printer` prints any node the way graphql-js prints
it; `Printer(isMinified: true)` drops every character that does not matter.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const parser = Parser();

  // Every syntax error in one pass, each with a stable code and a place.
  final broken = Source(
    'query { a(x: ) }\nfragment F on { b }',
    name: 'bad.graphql',
  );
  if (parser.parse(broken) case ParseFailure(:final diagnostics)) {
    diagnostics.forEach(print);
  }

  // A document prints back the way graphql-js prints it.
  final source = Source(
    r'query Hero($id:ID!){hero(id:$id){name ...on Droid{primaryFunction}}}',
  );
  if (parser.parse(source) case ParseSuccess(:final document)) {
    print(const Printer().print(document));
    print(const Printer(isMinified: true).print(document));
  }
}
```

It prints:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
bad.graphql:2:15: error GQL007: Expected Name, found "{".
query Hero($id: ID!) {
  hero(id: $id) {
    name
    ... on Droid {
      primaryFunction
    }
  }
}
query Hero($id:ID!){hero(id:$id){name ...on Droid{primaryFunction}}}
```

`ParserOptions` bound the work on untrusted text: `maxTokens` (15 000 by
default) and `maxDepth` (128). Working-draft syntax, such as
`extend directive`, is off unless `allowDirectiveExtensions` is set.

## Visiting and rewriting

`AstWalker` walks a tree depth-first and calls an `AstVisitor` on the way
in and out; `enter` returns `VisitAction.next`, `skip` (not this node's
children) or `stop`. `ParallelVisitor` runs several visitors in one walk.
`AstTransformer` rewrites a tree bottom-up: `rewrite` returns the node, a
replacement or `null` to remove it, and the original tree stays as it was.
Neither recurses, so a tree of any depth is safe on the web too.
`Parser().parseSchemaCoordinate` reads a schema coordinate, and a
`SourceSpan` shows its line the way graphql-js's `printLocation` does.

```dart
import 'package:typed_graphql/typed_graphql.dart';

/// Counts the fields of a document.
final class FieldCounter extends AstVisitor {
  int count = 0;

  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      count++;
    }
    return VisitAction.next;
  }
}

/// Adds `__typename` to every selection set that lacks it.
final class AddTypename extends AstTransformer {
  const AddTypename();

  @override
  Node? rewrite(Node node) => switch (node) {
    SelectionSet(:final selections) when !selections.any(_isTypename) =>
      SelectionSet([...selections, Field(null, const Name('__typename'))]),
    _ => node,
  };

  static bool _isTypename(Selection selection) =>
      selection is Field && selection.name.value == '__typename';
}

void main() {
  const parser = Parser();
  const printer = Printer(isMinified: true);
  if (parser.parse(Source('{ hero { name friends { name } } }'))
      case ParseSuccess(:final document)) {
    final counter = FieldCounter();
    const AstWalker().walk(document, counter);
    print(counter.count);
    if (const AddTypename().transform(document) case final Node rewritten) {
      print(printer.print(rewritten));
    }
  }

  // A schema coordinate names one element of a schema.
  if (parser.parseSchemaCoordinate(Source('Query.hero(episode:)'))
      case ParseElementSuccess(:final value)) {
    print('${value.runtimeType}: ${const Printer().print(value)}');
  }

  // A span shows the line it points at, as graphql-js does.
  final source = Source('{\n  hero(id: )\n}', name: 'hero.graphql');
  if (parser.parse(source) case ParseFailure(:final diagnostics)) {
    for (final diagnostic in diagnostics) {
      print(diagnostic);
      print(diagnostic.span?.excerpt);
    }
  }
}
```

It prints:

```text
4
{hero{name friends{name __typename}__typename}__typename}
ArgumentCoordinate: Query.hero(episode:)
hero.graphql:2:12: error GQL008: Unexpected ")".
hero.graphql:2:12
1 | {
2 |   hero(id: )
  |            ^
3 | }
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

The parser reports through this model, and the validator will:

- `Source` is a document and its name; `locationOf(offset)` gives a 1-based
  line and column, counted in UTF-16 code units.
- `SourceSpan` is a range of a `Source`; `excerpt` shows its line and the
  lines around it, with a caret.
- `Diagnostic` is one problem: a `DiagnosticCode` with a stable id
  (`GQL000`), a severity, a message, a span and related spans.
- `DiagnosticSink` collects diagnostics in order and stops at `maxErrors`
  errors (100 by default), reporting `GQL000` once.

## License

MIT — see [LICENSE](LICENSE).
