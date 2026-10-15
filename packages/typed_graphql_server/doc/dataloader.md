# DataLoader

A list of 100 users where each user shows its company is 101 queries if every
`company` resolver asks the database for its own row: one for the list and one
per user (the N+1 problem). A `BatchLoader` collects the keys the resolvers ask
for during one level of the response and hands them to one function that
fetches them all, so the same request is two queries. It also remembers what it
loaded, so a key asked twice costs one fetch.

## A loader in the context

A loader belongs to one request. Create it in the code that makes the context
(in the request pipeline, the context factory), so its cache and its batches
never cross requests: a value one user may see must not be served from another
user's cache. The library keeps no global loader.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Context {
  Context(this.companies);

  final BatchLoader<int, String> companies;
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Context>();
  final user = b.object<int>(
    'User',
    fields: (t) => [
      t.field('company', b.string).resolve((parent, args, context, info) {
        return context.companies.load(parent);
      }),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('users', b.list(user)).pure((_) => const [1, 2, 3]),
    ],
  );
  final schema = b.build(query: query);
  final document = ValidDocument.assumeValid(
    schema.schema,
    const Parser().parse(Source('{ users { company } }')).requireDocument(),
  );

  final context = Context(
    BatchLoader<int, String>((keys) {
      print('fetching $keys');
      return {for (final key in keys) key: 'Company $key'};
    }),
  );
  final result = await schema.execute(document, context: context);
  print((result as ExecutionResult).toJson().toJson());
}
```

It prints:

```text
fetching [1, 2, 3]
{data: {users: [{company: Company 1}, {company: Company 2}, {company: Company 3}]}}
```

The function gets the distinct keys in the order they were asked and returns a
map. It may be asynchronous: its type is `FutureOr<Map<K, V>>`.

## When a batch is dispatched

The first `load` of a batch schedules its dispatch for when the microtask queue
has drained (a zero-duration timer). Everything that runs before that joins the
batch: the resolvers of one level, and also a resolver that `await`s a
completed future before it calls `load`, however many times. The executor needs
no hook for this. A `load` after the dispatch started begins the next batch.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final loader = BatchLoader<int, int>((keys) {
    print('batch $keys');
    return {for (final key in keys) key: key * 10};
  });

  Future<int> later(int awaits, int key) async {
    for (var i = 0; i < awaits; i++) {
      await Future<void>.value();
    }
    return loader.load(key);
  }

  print(await Future.wait([later(0, 1), later(3, 2), later(8, 3)]));
  print(await loader.load(4));
}
```

It prints:

```text
batch [1, 2, 3]
[10, 20, 30]
batch [4]
40
```

`loadMany(keys)` loads several keys at once and returns the values in the order
given; it fails when any key fails.

## De-duplication and the cache

A key asked twice in one batch is sent once, and both callers get the same
future. With `cachesValues` (the default) a loaded, pending or primed value is
also reused for the loader's lifetime, so a later `load` of the key does not
call the function again.

- `prime(key, value)` puts a value you already have into the cache, for
  example the rows a list query returned, so that `load` of those keys fetches
  nothing. It never replaces a value that is already cached.
- `clear(key)` and `clearAll()` forget cached values. Call them after a
  mutation that changed what the loader would return. Futures already handed
  out still complete.
- `cachesValues: false` turns the cache off; keys asked in the same batch are
  still sent once.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final loader = BatchLoader<int, String>((keys) {
    print('fetching $keys');
    return {for (final key in keys) key: 'name $key'};
  });

  print(await Future.wait([loader.load(1), loader.load(1), loader.load(2)]));
  print(await loader.load(1));
  loader.prime(3, 'primed');
  print(await loader.load(3));
  loader.clear(1);
  print(await loader.load(1));
}
```

It prints:

```text
fetching [1, 2]
[name 1, name 1, name 2]
name 1
primed
fetching [1]
name 1
```

## Missing keys

A key the function leaves out of its map has no value. When the value type is
nullable (`BatchLoader<int, String?>`) the future completes with `null`.
Otherwise it fails with a `MissingValueException` that holds the key; a
resolver that lets it escape is a field error, masked like any other.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final optional = BatchLoader<int, String?>((keys) => {1: 'one'});
  print(await Future.wait([optional.load(1), optional.load(2)]));

  final required = BatchLoader<int, String>((keys) => {1: 'one'});
  try {
    await required.load(2);
  } on MissingValueException catch (error) {
    print(error);
  }
}
```

It prints:

```text
[one, null]
MissingValueException: the batch function returned no value for key 2
```

## maxBatchSize

`maxBatchSize` caps the keys of one call. A batch with more keys is split in
order into calls of at most that many, for a database that limits the size of
an `IN` list. A value below 1 is an `ArgumentError`.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final loader = BatchLoader<int, int>((keys) {
    print('call $keys');
    return {for (final key in keys) key: key};
  }, maxBatchSize: 2);
  await loader.loadMany([1, 2, 3, 4, 5]);
}
```

It prints:

```text
call [1, 2]
call [3, 4]
call [5]
```

## Errors

If the function throws, or its future fails, every key of that call fails with
the same error. A failure is not cached: the next `load` of those keys calls
the function again. The loader listens to every future it creates, so a failed
batch never becomes an uncaught error by itself; the future you get back is
yours to await, and a resolver that returns it reports the failure as a field
error.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  var isDown = true;
  final loader = BatchLoader<int, int>((keys) {
    if (isDown) {
      throw StateError('database is down');
    }
    return {for (final key in keys) key: key};
  });

  try {
    await loader.loadMany([1, 2]);
  } on StateError catch (error) {
    print(error.message);
  }
  isDown = false;
  print(await loader.loadMany([1, 2]));
}
```

It prints:

```text
database is down
[1, 2]
```
