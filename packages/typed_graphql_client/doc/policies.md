# Request Policies

Request policies are middle links that make a plain transport survive the
real world: they send a request again after a failure that may pass, add
what the server needs, or save bytes. Each one forwards the request to the
rest of the chain.

## Retrying

`RetryLink(policy:, random:)` sends a request again when it got no GraphQL
response and the reason may pass. `RetryPolicy(maxAttempts: 3, backoff:,
retryIf:)` decides how often (the first attempt counts) and how long to wait
(`Backoff`, full jitter). By default it retries a `NetworkFailure`, a
`RequestTimedOut` and an `HttpStatusFailure` with status 408, 429, 500, 502,
503 or 504; `retryIf` replaces that decision. A GraphQL error is an answer
and is never retried. When the attempts run out, the last failure is
delivered.

It retries queries. A mutation is retried only when its context holds
`Idempotent()`, because a lost answer does not say whether the server applied
it; a subscription is forwarded unchanged (the WebSocket link reconnects on
its own). Cancelling the call cancels the wait and the running attempt.
The files of a request with `UploadFiles` are sent again on each attempt.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class HelloQuery extends GraphQLQuery<String> {
  const HelloQuery();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Hello',
    type: OperationType.query,
    text: 'query Hello{hello}',
    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<String> decodeData(JsonObject data) => switch (data['hello']) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a string', path: [PathKey('hello')]),
  };
}

Future<void> main() async {
  final mock = MockLink()
    ..addFailure(NetworkFailure(const FormatException('connection lost')))
    ..addData(JsonObject({'hello': JsonString('world')}));
  final client = GraphQLClient(
    link: Link.from([
      RetryLink(
        policy: const RetryPolicy(
          maxAttempts: 2,
          backoff: Backoff(initialDelay: Duration.zero),
        ),
      ),
      mock,
    ]),
  );
  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    print(data);
  }
  print('sent ${mock.requests.length} times');
}
```

It prints:

```text
world
sent 2 times
```

A mutation joins in by saying it is safe to send twice:

```text
client.mutate(
  const RenameMutation('a'),
  context: LinkContext([const Idempotent()]),
);
```

## Sharing identical queries

`DedupeLink()` lets identical queries that are in flight at the same time
share one forwarded request. Two queries are identical when their bodies
(document, variables and extensions, compared as JSON values) and their
`RequestHeaders` are equal. Each caller gets the shared result through its
own stream; a caller that cancels leaves the others their result, and the
forwarded request is cancelled when the last caller cancels. The sharing ends
at the first result, so a query sent later goes out again: the link is not a
cache. Mutations, subscriptions and requests with `UploadFiles` pass through.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class HelloQuery extends GraphQLQuery<String> {
  const HelloQuery();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Hello',
    type: OperationType.query,
    text: 'query Hello{hello}',
    sha256: 'f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<String> decodeData(JsonObject data) => switch (data['hello']) {
    JsonString(:final value) => DecodeSuccess(value),
    _ => const DecodeFailure('expected a string', path: [PathKey('hello')]),
  };
}

Future<void> main() async {
  final mock = MockLink()
    ..addData(JsonObject({'hello': JsonString('world')}))
    ..addData(JsonObject({'hello': JsonString('again')}));
  final client = GraphQLClient(link: Link.from([DedupeLink(), mock]));
  final responses = await Future.wait([
    client.query(const HelloQuery()),
    client.query(const HelloQuery()),
  ]);
  for (final response in responses) {
    if (response case GraphQLData(:final data)) {
      print(data);
    }
  }
  print('sent ${mock.requests.length} time');
  await client.query(const HelloQuery());
  print('sent ${mock.requests.length} times');
}
```

It prints:

```text
world
world
sent 1 time
sent 2 times
```
