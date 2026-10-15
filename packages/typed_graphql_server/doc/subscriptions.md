# Subscriptions

A subscription operation turns a stream of events into a stream of
responses. `ExecutableSchema.subscribe` starts one: it runs the source
function of the operation's root field, then executes the selection set once
for every event the source stream emits. It builds on the Schema Builder and
Execution guides; the response to each event is an `ExecutionResult`, like
the response to a query.

## Declaring a subscription

A subscription root field takes its events from a source, declared on the
field stub with `subscribe` or `subscribeWith`. `subscribe` takes a function
that returns the `Stream` (or a `Future` of it) of values of the field's own
type: each item is completed as the value of the field. `subscribeWith<E>`
takes a source of events of another type `E` and a second function that turns
each event into the field's value, as graphql-js's field `resolve` does next
to its `subscribe`. The source function gets the root value, the arguments,
the context and the `FieldInfo` once, when the subscription starts. The root
type may be declared with `Object?` as its parent, so no root value is needed.

`subscribe` answers a `FutureOr<SubscriptionResult>`, sealed:
`SubscriptionStarted(results)` holds the stream of responses, and
`SubscriptionRejected(error)` the request error of a subscription that could
not start. Cancelling the listener of `results` cancels the source stream;
when the source is done, `results` closes. The programs here use a finite
source so that they end.

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
  final limit = Arg('to', b.int);
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      // Each item of the stream is the value of the field.
      t
          .field('count', b.int, args: [limit])
          .subscribe(
            (parent, args, context, info) => Stream.fromIterable([
              for (var i = 1; i <= args.get(limit); i++) i,
            ]),
          ),
      // The events are raw words; `resolve` turns each into the field's value.
      t
          .field('shout', b.string)
          .subscribeWith<String>(
            (parent, args, context, info) =>
                Stream.fromIterable(const ['hey', 'ho']),
            (event, args, context, info) => event.toUpperCase(),
          ),
    ],
  );
  final schema = b.build(query: query, subscription: subscription);

  final started = await schema.subscribe(
    check(schema, 'subscription { count(to: 3) }'),
    context: null,
  );
  if (started case SubscriptionStarted(:final results)) {
    await for (final result in results) {
      print(result.toJson());
    }
  }

  final shouts = await schema.subscribe(
    check(schema, 'subscription { shout }'),
    context: null,
  );
  if (shouts case SubscriptionStarted(:final results)) {
    print(await results.map((result) => result.toJson()).toList());
  }

  // A query is not a subscription: the request is rejected, not thrown.
  final rejected = await schema.subscribe(
    check(schema, '{ hello }'),
    context: null,
  );
  if (rejected case SubscriptionRejected(:final error)) {
    print(error.toJson());
  }
}
```

It prints:

```text
{"data":{"count":1}}
{"data":{"count":2}}
{"data":{"count":3}}
[{"data":{"shout":"HEY"}}, {"data":{"shout":"HO"}}]
{"errors":[{"message":"Expected subscription operation.","extensions":{"code":"GQL324"}}]}
```

## One event at a time

Events are executed one at a time and in order. While an event executes, the
source subscription is paused; a source error, or the end of the source, is
seen after the event in flight. A single-subscription source then waits for
the resolvers. A broadcast source, the usual publish and subscribe channel,
keeps buffering inside its paused subscription without bound, so the
application must bound it (drop or sample events before they reach the
stream). Pausing and resuming `results` pause and resume the source, and the
source is listened to only when `results` is. The field errors of an event
are in that event's result, with the null propagation of a query, and do not
end the stream. An unexpected library error while executing an event ends
the stream with a `GQL340` result.

The source function runs when the subscription starts, before anyone listens
to `results`. A response stream that is never listened to has therefore
already called it: when the source registers eagerly, listen to `results` or
drop it promptly.

Global and field middleware wrap the per-event resolution, not the source
function, and the parent that middleware sees is the event.

## Failures

A subscription that cannot start is a `SubscriptionRejected`, never a throw:
a document whose operation is not a subscription (`GQL324`, "Expected
subscription operation."), a root field that is skipped or undefined
(`GQL322`, "The subscription selects no root field."), bad variables or
arguments, and a source function that throws or whose future fails. The
last is the field error of the root field, masked like any other (`GQL330`)
unless it is a `GraphQLException`. These request errors carry no `locations`.

A source stream that fails only after it has been listened to cannot be seen
when the subscription starts. It becomes the last result of `results`, an
error result with the code `GQL340` (or the message and extensions of a
`GraphQLException`), and `results` then closes. `@defer` and `@stream` in a
subscription are ignored until M14.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

ValidDocument check(ExecutableSchema<Object?> schema, String text) =>
    const DocumentValidator().validate(
      schema.schema,
      const Parser().parse(Source(text)).requireDocument(),
    ) as ValidDocument;

Stream<int> flaky() async* {
  yield 1;
  throw StateError('The feed is down.');
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      t
          .field('ticks', b.int)
          .subscribe((parent, args, context, info) => flaky()),
      t
          .field('broken', b.int)
          .subscribe(
            (parent, args, context, info) => throw StateError('No feed.'),
          ),
    ],
  );
  final schema = b.build(query: query, subscription: subscription);

  // A failure while the source stream is created rejects the request.
  final rejected = await schema.subscribe(
    check(schema, 'subscription { broken }'),
    context: null,
  );
  if (rejected case SubscriptionRejected(:final error)) {
    print(error.toJson());
  }

  // A failure after the stream started is its last result; then it closes.
  final started = await schema.subscribe(
    check(schema, 'subscription { ticks }'),
    context: null,
  );
  if (started case SubscriptionStarted(:final results)) {
    await for (final result in results) {
      print(result.toJson());
    }
    print('closed');
  }
}
```

It prints:

```text
{"errors":[{"message":"Unexpected error.","path":["broken"],"extensions":{"code":"GQL330"}}]}
{"data":{"ticks":1}}
{"errors":[{"message":"Unexpected error.","extensions":{"code":"GQL340"}}],"data":null}
closed
```

## Subscriptions and execute

`execute` on a subscription operation runs it once, as a query, with the root
value as the single event, as graphql-js does. Use `subscribe` to get the
stream.
