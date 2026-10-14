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

## Reading an answer

`SchemaBuilder().fromIntrospection(json)` builds a schema from an answer and
returns a `BuildResult`, like `fromSdl`. The built-in scalars, directives and
introspection types in the answer stay built-in. A deprecation comes back as
SDL writes it: a deprecated element with the default reason, "No longer
supported", is a bare `@deprecated`, and so is `isDeprecated: true` with no
reason. Printed SDL therefore matches what a server built from SDL has.

Where the reader differs from graphql-js's `buildClientSchema`:

- A directive in the answer named like a built-in (`include`, `skip`,
  `deprecated`, `specifiedBy`, `oneOf`) is dropped, whatever its definition.
  graphql-js drops built-in types only.
- A directive named `defer` or `stream` is dropped too and switches on
  `includesDeferAndStream`, whatever its arguments.
- Directive deprecation (`isDeprecated` of a directive) is ignored: it is
  working-draft, and the built-in `@deprecated` cannot be applied to a
  directive definition, so keeping it would make the schema invalid.
- Two types with one name both build and the validator reports `GQL101`;
  graphql-js keeps the last.

A broken answer (a missing field, a value of the wrong JSON type, an unknown
kind, a reference to a type the answer does not list, an `ofType` chain deeper
than the query reads) gives a `GQL150` to `GQL155` diagnostic whose message
starts with the JSON path of the problem; the elements it is about are left
out of the partial schema. Like `fromSdl`, it does not validate: a schema from
a server you do not trust goes through `SchemaValidator` next (see "Validating
a schema" in the Schema topic).

Validating costs work and memory in proportion to the size of the schema: the
rules are linear in its size, but a hostile server can send a very large
answer. The reader bounds only what it can, such as the `ofType` chain
(100 wrappers) and the text of a value in a message. Limit the size of the
answer you accept before you decode it.

```dart
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  final source = Source('''
"The entry point."
type Query {
  hero(episode: Episode = JEDI): String @deprecated(reason: "Use heroes.")
  heroes: [String!]!
}

enum Episode { NEWHOPE EMPIRE JEDI }
''');
  final document = const Parser().parse(source).requireDocument();
  final schema = switch (const SchemaBuilder().fromSdl(document)) {
    BuildSuccess(:final schema) => schema,
    BuildFailure(:final diagnostics) => throw StateError('$diagnostics'),
  };

  // The server's answer, read back into a schema on the client.
  final result = schema.toIntrospection();
  if (const SchemaBuilder().fromIntrospection(result) case BuildSuccess(
    schema: final client,
  )) {
    print(const SchemaPrinter().print(client));
  }

  // A broken answer: every problem says where it is.
  const text = '{"__schema": {"queryType": {"name": "Query"}, "types": [{}]}}';
  if (const JsonReader().parse(text) case DecodeSuccess(:final value)) {
    const SchemaBuilder().fromIntrospection(value).diagnostics.forEach(print);
  }
}
```

It prints:

```text
"""The entry point."""
type Query {
  hero(episode: Episode = JEDI): String @deprecated(reason: "Use heroes.")
  heroes: [String!]!
}

enum Episode {
  NEWHOPE
  EMPIRE
  JEDI
}
error GQL151: $.__schema.types[0]: Introspection result missing name.
error GQL154: $.__schema.queryType: Invalid or incomplete schema, unknown type: Query. Ensure that a full introspection query is used in order to build a client schema.
```
