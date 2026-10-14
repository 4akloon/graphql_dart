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
