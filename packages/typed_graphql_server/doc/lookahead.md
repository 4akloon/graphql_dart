# Look-ahead

A resolver can see which fields the request selected under its own field, so
it can load only those: `FieldInfo.selection` is a `FieldSelection`, a view
of the operation plan with fragments flattened, `@skip` and `@include`
applied and `__typename` left out. Nothing is collected until a member is
read.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final b = ExecutableSchemaBuilder<Object?>();
  final user = b.object<Object?>(
    'User',
    fields: (t) => [
      t.field('name', b.string).pure((_) => 'Ada'),
      t.field('email', b.string).pure((_) => 'ada@example.com'),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('me', user).resolve((parent, args, context, info) {
        print(info.selection.has('email'));
        print(info.selection.fingerprint);
        return null;
      }),
    ],
  );
  final schema = b.build(query: query);
  final document = const Parser()
      .parse(Source('{ me { name email } }'))
      .requireDocument();
  schema.execute(
    ValidDocument.assumeValid(schema.schema, document),
    context: null,
  );
}
```

It prints:

```text
true
email,name
```

`fields` lists the `SelectedField`s; `forType(name)` narrows the selection of
an abstract type to one object type (an unknown name gives an empty
selection); `has('posts.comments')` tests a path of field names; `fieldsNamed`
lists every occurrence of a name. `fingerprint` is a canonical text, equal
for two selections that ask for the same fields and arguments, to use as a
cache or DataLoader key. `ColumnWhitelist` turns a selection into the sorted
columns of the fields it knows.
