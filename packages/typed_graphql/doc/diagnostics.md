# Diagnostics

Every problem the package finds in a document, a schema or a payload is a
`Diagnostic`: a stable code, a severity, a message for people and the place in
the source it is about. Parsing and building a schema return diagnostics
instead of throwing, and validation will report through the same model.

## Sources and spans

A `Source` is the text of a document and the name diagnostics show for it.
`locationOf(offset)` gives a 1-based line and column; the column counts
UTF-16 code units, as `String.codeUnitAt` does. A line ends with `\n`, `\r\n`
or `\r`.

A `SourceSpan` is a range of a `Source`: offsets from `start` up to, not
including, `end`. Its `location` is the line and column of `start`, its `text`
is the text it covers, and its `excerpt` shows the line the way graphql-js's
`printSourceLocation` does.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('{\n  hero {\n    name\n  }\n}', name: 'hero.graphql');

  print(source.locationOf(15));
  final span = SourceSpan(source, 15, 19);
  print(span);
  print(span.text);
  print(span.excerpt);
}
```

It prints:

```text
3:5
hero.graphql:3:5
name
hero.graphql:3:5
2 |   hero {
3 |     name
  |     ^
4 |   }
```

The table of line starts is built on the first call to `locationOf`, so a
document that reports nothing is never scanned for lines.

## Reading a diagnostic

A `Diagnostic` has a `code` (a `DiagnosticCode`), a `severity`
(`DiagnosticSeverity.error` or `warning`), a `message`, the `span` it is about
(null when it has no place in a source) and `related` spans that explain it,
such as the first definition of a duplicated name. Two diagnostics are equal
when all five are, so a test can compare lists of them.

`toString` gives the form terminals and editors link to:
`name:line:column: severity GQLnnn: message`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final broken = Source(
    'query { a(x: ) }\nfragment F on { b }',
    name: 'bad.graphql',
  );
  for (final diagnostic in const Parser().parse(broken).diagnostics) {
    print(diagnostic);
    print('  ${diagnostic.code.id}, error: ${diagnostic.isError}');
  }

  final twice = Source(
    'type A { a: Int }\ntype A { b: Int }',
    name: 'dup.graphql',
  );
  final built = const SchemaBuilder().fromSdl(
    const Parser().parse(twice).requireDocument(),
    source: twice,
  );
  final duplicate = built.diagnostics.single;
  print(duplicate);
  print('first one at ${duplicate.related.single}');
  print('locations ${duplicate.locations}');
}
```

It prints:

```text
bad.graphql:1:14: error GQL008: Unexpected ")".
  GQL008, error: true
bad.graphql:2:15: error GQL007: Expected Name, found "{".
  GQL007, error: true
dup.graphql:2:6: error GQL101: There can be only one type named "A".
first one at dup.graphql:1:1
locations [2:6, 1:1]
```

## Codes

`DiagnosticCode` is the catalog: one value per problem, each with an `id`
such as `GQL008` and a doc comment that says when it is reported. The hundreds
digit is the area:

| Ids | Area |
|---|---|
| `GQL0xx` | lexer and syntax |
| `GQL1xx` | type system: building a schema |
| `GQL2xx` | operation validation |
| `GQL3xx` | coercion and execution |
| `GQL4xx` | transports and protocols |
| `GQL5xx` | code generation |

`GQL000` belongs to no area: a sink reports it when its limit is reached. An id
is public API and is never renumbered, reused or removed. New releases add
codes, so do not switch over `DiagnosticCode` exhaustively; match the codes you
handle and keep a wildcard.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('query { a(x: ) }', name: 'bad.graphql');
  for (final diagnostic in const Parser().parse(source).diagnostics) {
    final advice = switch (diagnostic.code) {
      DiagnosticCode.unexpectedToken => 'a value is missing',
      DiagnosticCode.tokenLimitExceeded => 'the document is too long',
      _ => 'see ${diagnostic.code.id}',
    };
    print('${diagnostic.code.id}: $advice');
  }
}
```

It prints:

```text
GQL008: a value is missing
```

## Collecting diagnostics

A `DiagnosticSink` collects diagnostics in the order they are reported; the
order is never changed. It keeps at most `maxErrors` errors (100 by default,
the limit graphql-js uses for validation). The next error adds one
`GQL000` error instead, `isFull` becomes true and every later report is
ignored, so a hostile document cannot produce an unbounded list. Warnings do
not count against the limit.

The lexer, the parser and the schema builder have a sink inside; their public
API turns it into a sealed result. Use a sink yourself when you write a check
of your own:

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('type A\ntype B\ntype C', name: 'types.graphql');
  final sink = DiagnosticSink(maxErrors: 2);
  for (final (index, name) in ['A', 'B', 'C'].indexed) {
    final start = source.body.indexOf('type $name') + 5;
    sink.report(
      Diagnostic(
        DiagnosticCode.duplicateTypeName,
        DiagnosticSeverity.error,
        'There can be only one type named "$name".',
        span: SourceSpan(source, start, start + 1),
      ),
    );
  }
  sink.diagnostics.forEach(print);
  print('hasErrors: ${sink.hasErrors}, isFull: ${sink.isFull}');
}
```

It prints:

```text
types.graphql:1:6: error GQL101: There can be only one type named "A".
types.graphql:2:6: error GQL101: There can be only one type named "B".
types.graphql:3:6: error GQL000: Too many errors: the limit of 2 was reached and the rest are not reported.
hasErrors: true, isFull: true
```

## Diagnostics on the wire

A diagnostic becomes the `GraphQLError` of a response: `locations` lists the
line and column of the span and then of each related span, which is the shape
the specification gives an error's `locations`. See the Wire Protocol topic
for the response types.

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('{ hero(id: ) }');
  final failure = const Parser().parse(source);
  final response = RequestErrorResult(
    errors: [
      for (final diagnostic in failure.diagnostics)
        GraphQLError(
          diagnostic.message,
          locations: diagnostic.locations,
          extensions: JsonObject({'code': JsonString(diagnostic.code.id)}),
        ),
    ],
  );
  print(jsonEncode(response.toJson()));
}
```

It prints:

```text
{"errors":[{"message":"Unexpected \")\".","locations":[{"line":1,"column":12}],"extensions":{"code":"GQL008"}}]}
```
