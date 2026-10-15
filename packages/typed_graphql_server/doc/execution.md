# Execution

`ExecutableSchema<C>.execute` runs a validated document against the schema
the builder made and answers with a response value. It builds on the Schema
Builder guide's schemas and on the core's parsing and validation: `execute` takes a `ValidDocument`, the typestate that
`DocumentValidator` returns for a document it accepted, so an unchecked
document cannot reach it.

## Executing a request

`execute(document, {required context, operationName, variables, options})`
returns a `FutureOr<ResponsePayload>`. A query whose resolvers all return
values at once completes synchronously: you get the `ExecutionResult`
itself, not a `Future`. As soon as one resolver returns a `Future`, so does
`execute`. A `pure` field (a getter over the parent, with no arguments or
context) is the fast path: it has no middleware chain and nothing to wait
for.

`ResponsePayload` is sealed. An `ExecutionResult` holds `data` and `errors`
(field errors, next to the data that could still be produced); a
`RequestErrorResult` holds only `errors`, for a request that could not start.
Both write themselves with `toJson()`. The `context` is the `C` of the
schema, handed to every resolver. A `ValidDocument` made against another
schema, or a `rootValue` the root type does not accept, is an `ArgumentError`:
that is a programmer's mistake, not bad input.

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
    fields: (t) => [
      t.field('now', b.string).pure((_) => 'today'),
      t.field('later', b.string).resolve((p, args, c, info) async => 'soon'),
    ],
  );
  final schema = b.build(query: query);

  final fast = schema.execute(check(schema, '{ now }'), context: null);
  print(fast is ExecutionResult);
  final slow = schema.execute(check(schema, '{ now later }'), context: null);
  print(slow is Future<ResponsePayload>);
  print((await slow).toJson());
}
```

It prints:

```text
true
true
{"data":{"now":"today","later":"soon"}}
```

`ExecutionOptions` holds everything else, per call: `rootValue` (the parent
of the root fields), `source` (the text the document was parsed from, which
gives errors their `locations`), `errorBehavior`, `maskErrors`, `onError`,
`includesSuggestions` ("Did you mean" in messages), `maxCoercionErrors`
(50), `maxDepth` (256) and `maxSteps` (10 000 000). The examples below leave
`source` out to keep their output short.

Mutation root fields run one after another, as the specification asks. In
every other selection set the fields are started in document order, and the
ones that wait are waited for together.

## Variables and request errors

Variable values arrive as a `JsonObject` and are coerced against the
operation's variable definitions before anything runs: defaults apply, a
missing required variable is refused, and an input object or custom scalar
goes through its `decode`. Arguments are coerced afterwards, per field, with
the variables substituted; constant arguments are coerced once and kept in
the plan.

A request that cannot start is a `RequestErrorResult` with no `data`: an
unknown `operationName`, no operation, a `subscription` the schema does not
have, or a variable that does not coerce. Its errors carry a code (`GQL320`
to `GQL323` for the operation, `GQL310` to `GQL312` for variables) and have
no `locations`. A variable error is reported for each problem, up to
`maxCoercionErrors`. A problem inside one field's arguments is different: it
is a field error, so the other fields still run.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> show(
  ExecutableSchema<Object?> schema,
  String text, {
  JsonObject? variables,
  String? operationName,
  ExecutionOptions options = const ExecutionOptions(),
}) async {
  final response = await schema.execute(
    check(schema, text),
    context: null,
    variables: variables,
    operationName: operationName,
    options: options,
  );
  print(response.toJson());
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final name = Arg('name', b.string);
  final times = Arg('times', b.int, defaultValue: 1);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('greet', b.string, args: [name, times])
          .resolve(
            (p, args, c, info) =>
                'Hello, ${args.get(name)}! ' * args.get(times),
          ),
    ],
  );
  final schema = b.build(query: query);
  const text =
      r'query Hi($who: String!, $n: Int) { greet(name: $who, times: $n) }';

  await show(
    schema,
    text,
    variables: JsonObject({'who': const JsonString('Ann')}),
  );
  await show(
    schema,
    text,
    variables: JsonObject({'who': const JsonString('Ann'), 'n': JsonNumber(2)}),
  );
  await show(schema, text, variables: JsonObject({'who': JsonNumber(7)}));
  await show(schema, text, operationName: 'Other');
}
```

It prints:

```text
{"data":{"greet":"Hello, Ann! "}}
{"data":{"greet":"Hello, Ann! Hello, Ann! "}}
{"errors":[{"message":"Variable \"$who\" has invalid value: String cannot represent a non string value: 7","extensions":{"code":"GQL310"}}]}
{"errors":[{"message":"Unknown operation named \"Other\".","extensions":{"code":"GQL320"}}]}
```

## Field errors and masking

A resolver reports an error by throwing, or by returning a failed `Future`;
both are caught. The error becomes a `GraphQLError` with the field's `path`
and, when `options.source` is given, its `locations`, and the field is null.
If the field is non-null, the null propagates to the nearest nullable parent,
as the specification asks (section 6.4.4); the executor does this with a
returned sentinel, not by unwinding the stack. When a root field is non-null,
`data` itself is null.

What the client sees depends on what was thrown:

- A `GraphQLException(message, {extensions})` is meant for the client: its
  message and extensions are sent as they are.
- Anything else is a bug as far as the client is concerned and is masked:
  the message is `Unexpected error.` with `extensions.code` `GQL330`, so a
  database address or a stack trace never leaves the server. Set
  `maskErrors: false` in development to see the error's `toString()`.
- An error the library makes (a value of the wrong kind, a null for a
  non-null field, an abstract type it cannot resolve) carries its code too,
  `GQL331` to `GQL337`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Future<void> show(
  ExecutableSchema<Object?> schema,
  String text, {
  ExecutionOptions options = const ExecutionOptions(),
}) async {
  final response = await schema.execute(
    check(schema, text),
    context: null,
    options: options,
  );
  print(response.toJson());
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('ok', b.string).pure((_) => 'fine'),
      t
          .field('broken', b.string.nullable)
          .resolve((p, args, c, info) => throw StateError('hunter2')),
      t
          .field('forbidden', b.string.nullable)
          .resolve(
            (p, args, c, info) => throw GraphQLException(
              'Not allowed.',
              extensions: JsonObject({'code': const JsonString('FORBIDDEN')}),
            ),
          ),
      t
          .field('required', b.string)
          .resolve((p, args, c, info) => throw StateError('lost')),
    ],
  );
  final schema = b.build(query: query);

  await show(schema, '{ ok broken forbidden }');
  await show(
    schema,
    '{ ok broken }',
    options: const ExecutionOptions(maskErrors: false),
  );
  await show(schema, '{ ok required }');
}
```

It prints:

```text
{"errors":[{"message":"Unexpected error.","path":["broken"],"extensions":{"code":"GQL330"}},{"message":"Not allowed.","path":["forbidden"],"extensions":{"code":"FORBIDDEN"}}],"data":{"ok":"fine","broken":null,"forbidden":null}}
{"errors":[{"message":"Bad state: hunter2","path":["broken"],"extensions":{"code":"GQL330"}}],"data":{"ok":"fine","broken":null}}
{"errors":[{"message":"Unexpected error.","path":["required"],"extensions":{"code":"GQL330"}}],"data":null}
```

## Error behaviours

`ExecutionOptions.errorBehavior` chooses what an error does to the data:

- `ErrorBehavior.propagate` (the default) follows the specification: a null
  that reaches a non-null position nulls its parent, up to the nearest
  nullable field.
- `ErrorBehavior.nullValue` stops an error at its own field, even when the
  field is non-null: the response holds a null where a non-null was
  declared. A client that reads `errors` and tolerates nulls wants this.
- `ErrorBehavior.halt` ends the execution at the first error: `data` is null
  and `errors` holds that error.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final user = b.object<Object?>(
    'User',
    fields: (t) => [
      t.field('id', b.int).pure((_) => 7),
      t
          .field('name', b.string)
          .resolve((p, args, c, info) => throw GraphQLException('No name.')),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('user', user.nullable).pure((_) => 1),
      t.field('other', b.string).pure((_) => 'still here'),
    ],
  );
  final schema = b.build(query: query);
  final document = const DocumentValidator().validate(
    schema.schema,
    const Parser()
        .parse(Source('{ user { id name } other }'))
        .requireDocument(),
  ) as ValidDocument;

  for (final behavior in ErrorBehavior.values) {
    final response = await schema.execute(
      document,
      context: null,
      options: ExecutionOptions(errorBehavior: behavior),
    );
    print('${behavior.name}: ${response.toJson()}');
  }
}
```

It prints:

```text
propagate: {"errors":[{"message":"No name.","path":["user","name"]}],"data":{"user":null,"other":"still here"}}
nullValue: {"errors":[{"message":"No name.","path":["user","name"]}],"data":{"user":{"id":7,"name":null},"other":"still here"}}
halt: {"errors":[{"message":"No name.","path":["user","name"]}],"data":null}
```

## Reporting errors with onError

`ExecutionOptions.onError(error, stackTrace, reported)` runs for every error
thrown by user code (resolvers, middleware, `decode`, codecs), before the
masked or raw error is recorded. `reported` is what would be recorded;
return a `GraphQLError` to replace it, or `null` to keep it. This is where a
host logs the stack trace that the client never sees, and maps its own
exception types to codes. A hook that throws is recorded as the masked
error, so it cannot break the response.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('lookup', b.string.nullable)
          .resolve((p, args, c, info) => throw ArgumentError('no such row')),
    ],
  );
  final schema = b.build(query: query);
  final document = const DocumentValidator().validate(
    schema.schema,
    const Parser().parse(Source('{ lookup }')).requireDocument(),
  ) as ValidDocument;

  final response = await schema.execute(
    document,
    context: null,
    options: ExecutionOptions(
      onError: (error, stackTrace, reported) {
        print('logged: $error');
        return GraphQLError(
          'The lookup failed.',
          path: reported.path,
          extensions: JsonObject({'code': const JsonString('LOOKUP_FAILED')}),
        );
      },
    ),
  );
  print(response.toJson());
}
```

It prints:

```text
logged: Invalid argument(s): no such row
{"errors":[{"message":"The lookup failed.","path":["lookup"],"extensions":{"code":"LOOKUP_FAILED"}}],"data":{"lookup":null}}
```

## Middleware

A middleware wraps resolvers. A `FieldMiddleware<C>` takes the `next`
resolver and a `FieldSite` (the parent `ObjectType` and the `SchemaField`)
and returns a resolver. Chains are composed once, when the schema is built,
in the order global (`BuildOptions.middleware`), then field
(`FieldStub.withMiddleware`), then directive (`BuildOptions.directiveMiddleware`,
keyed by the directive's name and applied to the fields that carry it); the
outermost runs first. A middleware that does not care about a field returns
`next` unchanged, which costs nothing per request, and a field with no
middleware is called directly. There is no slot for a whole type: a global
middleware looks at `site.parentType` and returns `next` for the others. A
`pure` field has no chain, so combining it with middleware is an
`ArgumentError`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final log = <String>[];
  final b = ExecutableSchemaBuilder<String>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('hello', b.string.nullable).resolve((p, args, c, info) => 'hi'),
      t
          .field('secret', b.string.nullable)
          .withMiddleware([
            (next, site) =>
                (parent, args, role, info) => role == 'admin'
                ? next(parent, args, role, info)
                : throw GraphQLException('Admins only.'),
          ])
          .resolve((p, args, c, info) => 'the code'),
    ],
  );
  final schema = b.build(
    query: query,
    options: BuildOptions<String>(
      middleware: [
        (next, site) => (parent, args, role, info) {
          log.add('${site.parentType.name}.${site.field.name}');
          return next(parent, args, role, info);
        },
      ],
    ),
  );
  final document = const DocumentValidator().validate(
    schema.schema,
    const Parser().parse(Source('{ hello secret }')).requireDocument(),
  ) as ValidDocument;

  for (final role in ['guest', 'admin']) {
    final response = await schema.execute(document, context: role);
    print('$role: ${response.toJson()}');
  }
  print(log);
}
```

It prints:

```text
guest: {"errors":[{"message":"Admins only.","path":["secret"]}],"data":{"hello":"hi","secret":null}}
admin: {"data":{"hello":"hi","secret":"the code"}}
[Query.hello, Query.secret, Query.hello, Query.secret]
```

## Abstract types

The object type of an interface or union value is chosen at run time.
Without help, the first possible type whose `accepts` takes the value wins,
which is enough when the Dart types differ. Pass `resolveType` to `interface`
or `union` to choose yourself: it is synchronous, takes the value and returns
the object type definition, so a misspelled type name cannot happen. Give
both object types an `isTypeOf` (in `ObjectOptions`) instead when they
overlap in Dart and you prefer to keep the choice with the types. A value no
type accepts is `GQL333`; a `resolveType` result that cannot hold the value
is `GQL334`.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Item {
  const Item(this.title, {required this.isFilm});

  final String title;
  final bool isFilm;
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<Item>(
    'Book',
    fields: (t) => [t.field('title', b.string).pure((item) => item.title)],
  );
  final film = b.object<Item>(
    'Film',
    fields: (t) => [t.field('title', b.string).pure((item) => item.title)],
  );
  final media = b.union<Item>(
    'Media',
    members: [book, film],
    resolveType: (item) => item.isFilm ? film : book,
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('shelf', b.list(media))
          .pure(
            (_) => const [
              Item('Dune', isFilm: false),
              Item('Alien', isFilm: true),
            ],
          ),
    ],
  );
  final schema = b.build(query: query);
  final document = const DocumentValidator().validate(
    schema.schema,
    const Parser()
        .parse(Source('{ shelf { __typename ... on Film { title } } }'))
        .requireDocument(),
  ) as ValidDocument;

  print((await schema.execute(document, context: null)).toJson());
}
```

It prints:

```text
{"data":{"shelf":[{"__typename":"Book"},{"__typename":"Film","title":"Alien"}]}}
```

## Limits and the plan cache

Two options end runaway executions with an error instead of a hung process.
`maxDepth` (256) bounds how deep completion nests: a value below it is a
field error `GQL336` and that branch ends. `maxSteps` (10 000 000) bounds the
work, one step per completed value: past it the execution halts with
`GQL337` and no data. The parser bounds documents before they get here;
these two bound what the data makes of them (long lists, a recursive type).

The first run of a document plans it: it collects the fields for each
combination of `@skip`, `@include` and `@defer` conditions, expands every
fragment once, and coerces constant arguments once. The plan is cached per
schema, least recently used first out, by document and operation name.
`BuildOptions.planCacheSize` sets how many (1000; 0 keeps none). A request
error is never cached.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Node {
  const Node(this.next);

  final Node? next;
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  late final ObjectTypeDef<Node> node;
  node = b.object<Node>(
    'Node',
    fields: (t) => [
      t.field('next', node.nullable).pure((parent) => parent.next),
      t.field('id', b.int).pure((_) => 1),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('head', node).pure((_) => const Node(Node(Node(null)))),
    ],
  );
  final schema = b.build(
    query: query,
    options: const BuildOptions<Object?>(planCacheSize: 100),
  );
  final document = const DocumentValidator().validate(
    schema.schema,
    const Parser()
        .parse(Source('{ head { next { next { id } } } }'))
        .requireDocument(),
  ) as ValidDocument;

  for (final options in const [
    ExecutionOptions(),
    ExecutionOptions(maxDepth: 3),
    ExecutionOptions(maxSteps: 3),
  ]) {
    final response = await schema.execute(
      document,
      context: null,
      options: options,
    );
    print(response.toJson());
  }
}
```

It prints:

```text
{"data":{"head":{"next":{"next":{"id":1}}}}}
{"errors":[{"message":"Execution exceeds the maximum depth of 3.","path":["head","next","next","id"],"extensions":{"code":"GQL336"}}],"data":{"head":{"next":{"next":null}}}}
{"errors":[{"message":"Execution exceeds the limit of 3 completed values.","path":["head","next","next","id"],"extensions":{"code":"GQL337"}}],"data":null}
```
