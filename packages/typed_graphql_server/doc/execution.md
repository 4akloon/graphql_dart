# Execution

`ExecutableSchema.execute` runs a validated document (the full Execution
guide arrives with the rest of M5b). The package holds the two types the
builder hands to it.

`ExecutableSchema<C>` is what `ExecutableSchemaBuilder.build` returns: the
validated core `ValidSchema` (`schema`) and the run-time tables of the
resolvers behind it (`bindings`). `C` is the context type the resolvers
receive. The schema's SDL is
`const SchemaPrinter().print(executable.schema.schema)`.

`FieldInfo` is the last argument of a `resolve` closure: the field's name
(`fieldName`), the name of the object type it is selected on
(`parentTypeName`) and its response `path` from the root, a `ResponsePath`
whose `toList()` gives the core's `PathSegment`s. It also carries the
parent `ObjectType`, the `returnType`, the `fieldNodes`, the `operation`, the
raw `variables`, the `schema` and the `rootValue`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('where', b.string)
          .resolve(
            (parent, args, context, info) =>
                '${info.parentTypeName}.${info.fieldName}',
          ),
    ],
  );
  final executable = b.build(query: query);
  print(executable.schema.schema.queryTypeName);
}
```

It prints:

```text
Query
```
