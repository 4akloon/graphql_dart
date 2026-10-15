# Cancellation

Work nobody waits for any more should stop: a client that disconnected, a
request that took too long. The executor cannot know either, so the caller
tells it. A request can be stopped from outside with a `CancelSignal`, or by a time
limit. `CancelSignal` is a plain class the caller creates and cancels: it has
no tie to a transport, so an HTTP handler that sees the client leave, a
WebSocket handler that receives a stop message and a test all use it the same
way. Give it to `ExecutionOptions.cancelSignal`; set
`ExecutionOptions.timeout` for a time limit. The executor only listens to the
signal and never cancels it.

A resolver sees the run's own signal as `FieldInfo.cancelSignal`: it fires
when the caller's signal does or the timeout elapses, so a resolver doing long
work can check `isCancelled` or await `whenCancelled` and stop. Read it; do
not cancel it, which would cancel the whole run.

```dart
import 'dart:async';
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('slow', b.string).resolve((parent, args, context, info) async {
        await info.cancelSignal.whenCancelled;
        return 'stopped';
      }),
    ],
  );
  final schema = b.build(query: query);
  final document = ValidDocument.assumeValid(
    schema.schema,
    const Parser().parse(Source('{ slow }')).requireDocument(),
  );

  final timedOut = await schema.execute(
    document,
    context: null,
    options: const ExecutionOptions(timeout: Duration(milliseconds: 20)),
  );
  print(jsonEncode((timedOut as ExecutionResult).toJson().toJson()));

  final signal = CancelSignal();
  final running = schema.execute(
    document,
    context: null,
    options: ExecutionOptions(cancelSignal: signal),
  );
  signal.cancel('client left');
  final cancelled = await running;
  print(jsonEncode((cancelled as ExecutionResult).toJson().toJson()));
}
```

It prints:

```text
{"errors":[{"message":"Execution timed out after 20 ms.","extensions":{"code":"GQL351"}}],"data":null}
{"errors":[{"message":"Execution was cancelled.","extensions":{"code":"GQL350"}}],"data":null}
```

Once the run is cancelled no resolver starts, and `execute` completes at once
with `data: null` and one error: `GQL350` "Execution was cancelled." or, for
the timeout, `GQL351` "Execution timed out after N ms." Whatever the
resolvers still running return is dropped. graphql-js rejects the promise
instead. A query of synchronous resolvers with a timeout still returns
without a `Future`: the timer ends before `execute` returns, and it ends with
the run in every case.

A signal that is already cancelled gives the cancelled result without running
a resolver. Request errors win over it: an unknown operation or unusable
variables are `RequestErrorResult`s whatever the signal says.

## One signal per request

Make a `CancelSignal` for each request, not one for the server: cancelling it
ends only that request. The caller owns the signal. The executor listens to
it and never cancels it, and it removes its listener when the run ends, so a
signal may outlive many runs. A transport that hosts the executor creates the
signal when it accepts a request and cancels it when the connection closes or
a stop message arrives; the timeout is a safety net for requests nobody
cancels.

## What a resolver sees

`FieldInfo.cancelSignal` is the run's own signal, not the caller's. Without a
signal or a timeout it is a signal that never fires. The executor races the
pending result against the signal once, at the root, and checks `isCancelled`
before it starts each field, so after a cancellation no new resolver runs. A
resolver that already runs is not interrupted: it should check `isCancelled`
between steps or race its work against `whenCancelled`, as the first program
does. What it returns afterwards is dropped.

## Subscriptions

For `ExecutableSchema.subscribe` the signal and the timeout last as long as
the subscription. When one fires, the stream delivers one last result with the
cancellation error, the source subscription is cancelled and the stream
closes; the event being executed is dropped. A signal already cancelled at
`subscribe` gives a `SubscriptionRejected` with `GQL350`. The timeout starts
at `subscribe`; the listener on the caller's signal attaches when the response
stream is listened to.

```dart
import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final source = StreamController<String>();
  final subscription = b.object<Object?>(
    'Subscription',
    fields: (t) => [
      t
          .field('news', b.string)
          .subscribe((parent, args, context, info) => source.stream),
    ],
  );
  final schema = b.build(query: query, subscription: subscription);
  final document = ValidDocument.assumeValid(
    schema.schema,
    const Parser().parse(Source('subscription { news }')).requireDocument(),
  );

  final signal = CancelSignal();
  final started = await schema.subscribe(
    document,
    context: null,
    options: ExecutionOptions(cancelSignal: signal),
  );
  if (started case SubscriptionStarted(:final results)) {
    final done = results.forEach((result) => print(result.toJson()));
    source.add('first');
    await Future<void>.delayed(Duration.zero);
    signal.cancel();
    await done;
    print('source cancelled: ${!source.hasListener}');
  }
}
```

It prints:

```text
{"data":{"news":"first"}}
{"errors":[{"message":"Execution was cancelled.","extensions":{"code":"GQL350"}}],"data":null}
source cancelled: true
```

## Listen to the stream, or drop the signal

A response stream that is never listened to has already called the source
function and holds a listener on the caller's signal until that signal is
cancelled. Listen to the stream, or cancel the signal, as soon as you decide
not to use the subscription; a signal per request makes the second free.
