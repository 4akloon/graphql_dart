# Look-ahead

A resolver often loads more than the request needs: every column of a row,
every relation of an entity. Look-ahead lets it read, before it loads, which
fields the request selected under its own field. `FieldInfo.selection` is a
`FieldSelection`, a view of the operation plan with the request's variables:
fragments are flattened, `@skip` and `@include` are applied, and meta fields
(`__typename` and every other name that starts with `__`) are left out.
Nothing is collected until a member is read, so a resolver that never asks
pays nothing. The guide builds on the Schema Builder and Execution guides.

## Reading the selection

`fields` lists the `SelectedField`s in collection order, one per response key.
A `SelectedField` has the schema `name`, the `responseKey`, the `alias` (null
when the request gave none), its `arguments` and its own `selection`, which is
empty for a leaf.

`has('posts.title')` tests a path of field names, never aliases, through the
nested selections. `fieldsNamed('posts')` lists every occurrence of a name, so
two aliases of one field give two entries.

`SelectedField.arguments` is an `Arguments`, read with the same `Arg` that
declared the argument. The variables are substituted and the defaults applied
when it is first read.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final post = b.object<Object?>(
    'Post',
    fields: (t) => [t.field('title', b.string).pure((_) => 'A post')],
  );
  final first = Arg('first', b.int, defaultValue: 10);
  final user = b.object<Object?>(
    'User',
    fields: (t) => [
      t.field('name', b.string).pure((_) => 'Ada'),
      t.field('email', b.string).pure((_) => 'ada@example.com'),
      t
          .field('posts', b.list(post), args: [first])
          .resolve((parent, args, context, info) => const []),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('me', user).resolve((parent, args, context, info) {
        final selection = info.selection;
        print([for (final field in selection.fields) field.responseKey]);
        print(selection.has('email'));
        print(selection.has('posts.title'));
        for (final posts in selection.fieldsNamed('posts')) {
          print('posts(first: ${posts.arguments.get(first)})');
        }
        return const Object();
      }),
    ],
  );
  final schema = b.build(query: query);
  final document = const Parser()
      .parse(
        Source('''
query Page(\$withEmail: Boolean!) {
  me {
    __typename
    writer: name
    ...Contact
    posts(first: 3) { title }
  }
}

fragment Contact on User {
  email @include(if: \$withEmail)
}
'''),
      )
      .requireDocument();
  await schema.execute(
    ValidDocument.assumeValid(schema.schema, document),
    context: null,
    variables: JsonObject({'withEmail': JsonBool(false)}),
  );
}
```

It prints:

```text
[writer, posts]
false
true
posts(first: 3)
```

The fragment `Contact` is flattened into `me`, but `@include(if: false)`
removes its only field, and `__typename` never shows.

## Abstract types

Under a field of an interface or union type, `fields` holds what every
possible type collects, merged by response key in possible-type order.
`forType(name)` narrows the view to one object type: the fields that apply to
it, including those from `... on Name` fragments. An unknown name, or a type
that cannot occur there, gives an empty selection.

## A key for a DataLoader

`fingerprint` is a canonical text of the selection: the field names (not the
aliases) sorted, the arguments written as JSON of the coerced values with the
object keys sorted, the children nested. Two selections that ask for the same
fields with the same arguments have the same fingerprint, whatever the order,
the aliases or the fragments of their requests. Use it as a cache or
DataLoader key, so that a batch is shared only between requests that want the
same data. It is built with an explicit stack, so a deep selection cannot
overflow the stack.

`ColumnWhitelist` turns a selection into database columns. It maps field
names to columns, adds the `always` columns (a key, say), ignores the fields
it does not know and returns the sorted, de-duplicated list. It preloads
nothing and writes no SQL: the resolver builds the query.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final user = b.object<Object?>(
    'User',
    fields: (t) => [
      t.field('id', b.id).pure((_) => '1'),
      t.field('name', b.string).pure((_) => 'Ada'),
      t.field('email', b.string).pure((_) => 'ada@example.com'),
    ],
  );
  final columns = ColumnWhitelist(
    {'name': 'full_name', 'email': 'email_address'},
    always: ['id'],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('me', user).resolve((parent, args, context, info) {
        print(info.selection.fingerprint);
        print(columns.columnsFor(info.selection));
        return const Object();
      }),
    ],
  );
  final schema = b.build(query: query);
  for (final text in ['{ me { email name } }', '{ me { n: name } }']) {
    final document = const Parser().parse(Source(text)).requireDocument();
    await schema.execute(
      ValidDocument.assumeValid(schema.schema, document),
      context: null,
    );
  }
}
```

It prints:

```text
email,name
[email_address, full_name, id]
name
[full_name, id]
```

An alias does not change the fingerprint: `n: name` and `name` give the same
text.

## What the selection does not do

- `SelectedField.arguments` reads an argument whose value fails coercion as
  absent. Reading a required argument that way throws, which the resolver's
  error masking turns into `GQL330`; the executor reports the real coercion
  error when that field runs, so no problem is silent.
- There is no `isDeferred`: `@defer` is not executed yet, so the property
  arrives with incremental delivery.
- Typed handles such as `has(user.posts)` are not provided; paths are field
  names.
- Look-ahead is read only: it never changes what the executor runs.
