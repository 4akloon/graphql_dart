# Cancellation

A request can be stopped from outside with a `CancelSignal`, or by a time
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

For `ExecutableSchema.subscribe` the signal and the timeout last as long as
the subscription. When one fires, the stream delivers one last result with the
cancellation error, the source subscription is cancelled and the stream
closes; the event being executed is dropped. A signal already cancelled at
`subscribe` gives a `SubscriptionRejected` with `GQL350`.
