# Introspection

A client learns a server's schema by asking it: `__schema` returns the whole
schema and `__type(name:)` one type (September2025 section 4.2).
`ExecutableSchema` answers both by itself. There are no resolvers to write and
nothing to register: the answer is read from the schema the builder made, so
it cannot disagree with what the server executes. This guide shows an
introspection query, the guarantee about its answer, how to switch it off, and
how to declare the root types so that no root value is needed. It builds on
the Schema Builder and Execution guides.

## Asking the schema about itself

An introspection query is an ordinary document: validate it, execute it. The
meta fields `__schema` and `__type` exist on the query root type only, and
`__typename` on every object. The types and fields of the answer are the
specification's `__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue`
and `__Directive`, with the enums `__TypeKind` and `__DirectiveLocation`. A
type's `description` is the one given to the builder, and a field that is not
null is reported as a `NON_NULL` wrapper around its type.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<String>(
    'Book',
    description: 'A book in the library.',
    fields: (t) => [
      t.field('title', b.string).pure((title) => title),
      t.field('pages', b.int.nullable).pure((title) => title.length),
    ],
  );
  // The root type takes no parent value: `Object?` accepts the default
  // `null` root value.
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('books', b.list(book)).pure((_) => const ['Dune']),
    ],
  );
  final schema = b.build(query: query);

  const text = '''
{
  __type(name: "Book") {
    name
    description
    fields { name type { kind name ofType { kind name } } }
  }
}''';
  final response = await schema.execute(check(schema, text), context: null);
  print(response.toJson());

  final counts = await schema.execute(
    check(schema, '{ __schema { queryType { name } types { name } } }'),
    context: null,
  );
  print(counts.toJson());
}
```

It prints:

```text
{"data":{"__type":{"name":"Book","description":"A book in the library.","fields":[{"name":"title","type":{"kind":"NON_NULL","name":null,"ofType":{"kind":"SCALAR","name":"String"}}},{"name":"pages","type":{"kind":"SCALAR","name":"Int","ofType":null}}]}}}
{"data":{"__schema":{"queryType":{"name":"Query"},"types":[{"name":"Book"},{"name":"Query"},{"name":"String"},{"name":"Int"},{"name":"Boolean"},{"name":"__Schema"},{"name":"__Type"},{"name":"__TypeKind"},{"name":"__Field"},{"name":"__InputValue"},{"name":"__EnumValue"},{"name":"__Directive"},{"name":"__DirectiveLocation"}]}}}
```

`__schema { types }` lists the schema's own types first, in the order they
were created, then the built-in scalars the schema uses, then the
introspection types. The listing is the core's `IntrospectionListing`, shared
with `Schema.toIntrospection`, so both give the same order. `fields`,
`enumValues`, `args` and `inputFields` take `includeDeprecated`, and a field
or enum value marked deprecated carries its `deprecationReason`.
`possibleTypes` of an abstract type lists its object types in the core's
order, `specifiedByURL` and `isOneOf` read the scalar and the input object,
and a default value is printed as GraphQL text.

## The same answer as the core

The server and the core agree: executing `IntrospectionQuery.full` gives the
`data` that `toIntrospection` writes for the schema, so a client built with
`SchemaBuilder().fromIntrospection` sees the schema the server built. This
edition's introspection has none of graphql-js 17's working-draft parts:
directive deprecation (`__Schema.directives(includeDeprecated:)`,
`__Directive.isDeprecated`) and the `DIRECTIVE_DEFINITION` and
`FRAGMENT_VARIABLE_DEFINITION` locations are not there.

## Turning introspection off

`ExecutionOptions.introspection` takes an `IntrospectionPolicy`: `enabled`
(the default) or `disabled`. When it is disabled `__schema` and `__type` are
field errors with the code `GQL338`; `__schema` is non-null, so its error
nulls `data`. `__typename` still works, because it describes the response,
not the schema. The check is made by field name on every execution, so a
field reached through a fragment is refused too. Global middleware never
wraps introspection fields. To refuse such a query before it runs, use the
core's `NoIntrospectionRule` at validation time.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final schema = b.build(query: query);

  // The full introspection query gets what the core writes for the schema.
  final full = await schema.execute(
    check(schema, IntrospectionQuery.full.text),
    context: null,
  );
  final expected = schema.schema.schema.toIntrospection();
  print(full is ExecutionResult && full.data == expected);

  // A server that hides its schema turns the policy off.
  const closed = ExecutionOptions(introspection: IntrospectionPolicy.disabled);
  final hidden = await schema.execute(
    check(schema, '{ __typename __schema { queryType { name } } }'),
    context: null,
    options: closed,
  );
  print(hidden.toJson());
}
```

It prints:

```text
true
{"errors":[{"message":"GraphQL introspection has been disabled, but the requested query contained the field \"__schema\".","path":["__schema"],"extensions":{"code":"GQL338"}}],"data":null}
```

## Root types without a root value

`execute` hands `ExecutionOptions.rootValue` (`null` by default) to the root
fields as their parent, and the root type must accept it. A root type
declared with the parent type `Object?` accepts `null` and needs no root
value: write `b.object<Object?>('Query', ...)`, as the programs above do, and
execute without `rootValue`. A root type declared with another Dart type,
such as `b.object<Library>('Query', ...)`, needs a `Library` in `rootValue`,
and that holds for an introspection query too. A `rootValue` the root type
does not accept is an `ArgumentError`.
