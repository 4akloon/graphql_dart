# Introspection

Introspection is how a client asks a server for its schema (September2025,
"Introspection"). The client sends the introspection query; the server answers
it with a JSON description of its schema, which the client can build a schema
from. The types of this topic write the query, answer it from a `Schema`, and
read an answer back.

## The introspection query

`IntrospectionQuery` writes the query a client sends. Its `text` has the
fields and fragments of graphql-js's `getIntrospectionQuery`, and its flags
choose the optional fields: `includesDescriptions` (on by default),
`includesSpecifiedByUrl`, `includesDirectiveIsRepeatable`,
`includesSchemaDescription`, `includesInputValueDeprecation`, `includesOneOf`,
and the working-draft `includesDirectiveDeprecation`. `IntrospectionQuery.full`
asks for every field of September2025. `typeDepth` (9 by default, at most 100)
is how many `ofType` levels the query reads for a wrapped type.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  print(IntrospectionQuery.full.text.split('\n').first);
  print(IntrospectionQuery.full.text.contains('isOneOf'));
  print(const IntrospectionQuery().text.contains('isOneOf'));
}
```

It prints:

```text
query IntrospectionQuery {
true
false
```

## Answering from a schema

`schema.toIntrospection(query)` writes the `data` a server answers the query
with, as a `JsonObject`. It writes only the fields the query reads, so the
answer to a narrower query is smaller. A union lists every member as a
possible type, even one that is not an object type, so the validator still
sees it on the client. Introspect a validated schema: a reference to a type
the schema does not have is an `ArgumentError`.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
type Query { hero: Character }
interface Character { name: String! }
type Droid implements Character { name: String! }
''');
  final document = const Parser().parse(source).requireDocument();
  final schema = switch (const SchemaBuilder().fromSdl(document)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };

  final result = schema.toIntrospection();
  if (result.fields['__schema'] case JsonObject(:final fields)) {
    print(fields['queryType']);
    if (fields['types'] case JsonArray(:final items)) {
      for (final type in items) {
        if (type case JsonObject(
          fields: {
            'name': JsonString(value: final name),
            'possibleTypes': JsonArray(items: final possible),
          },
        )) {
          print('$name: $possible');
        }
      }
    }
  }
}
```

It prints:

```text
{"name":"Query","kind":"OBJECT"}
Character: [{"kind":"OBJECT","name":"Droid","ofType":null}]
```
