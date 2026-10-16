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

## Persisted queries

`PersistedQueryLink({isAutomatic: true})` sends the hash of the document
instead of its text, to a server that stores persisted documents (the
Persisted Documents guide of `typed_graphql_server`). The request carries
`extensions.persistedQuery` with `version` 1 and the document's `sha256Hash`,
merged into any extensions the request has, and no `query`.

In the automatic mode (APQ) the first request of a query is the hash alone:

- The server answers `PersistedQueryNotFound` (or `extensions.code` `GQL410`
  or `PERSISTED_QUERY_NOT_FOUND`): the link sends the request again with the
  text and the hash, and delivers that answer. The server stores the text
  once it has validated it, so the next request can be the hash alone.
- The server answers `PersistedQueryNotSupported` (`GQL412`,
  `PERSISTED_QUERY_NOT_SUPPORTED`): the link sends the text alone, and sends
  text alone for every later request.
- Anything else is delivered as it is.

With `isAutomatic: false` (trusted documents) the link sends the hash alone
and delivers whatever comes back, such as the server's `GQL415` for a hash it
does not know. The link applies to queries and mutations; a subscription and a
request with `UploadFiles` pass through. Cancelling the call cancels whichever
attempt is running.

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
    ..addErrors([GraphQLError('PersistedQueryNotFound')])
    ..addData(JsonObject({'hello': JsonString('world')}));
  final client = GraphQLClient(link: Link.from([PersistedQueryLink(), mock]));
  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    print(data);
  }
  for (final request in mock.requests) {
    print(
      '${request.body.query ?? '<no text>'} | '
      '${request.extensions?['persistedQuery']}',
    );
  }
}
```

It prints:

```text
world
<no text> | {"version":1,"sha256Hash":"f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623"}
query Hello{hello} | {"version":1,"sha256Hash":"f6004747575e6561b67c600f28196e3c7648ef73797a3078da3e4658ddf6b623"}
```

## Authentication

`AuthLink(token:, refresh:, headerName:, scheme:, isUnauthorized:)` adds the
header `authorization: Bearer <token>` to each request. `token` gives the
token (a `String?`, possibly from a `Future`; null sends no header);
`headerName` and `scheme` change the header, and an empty `scheme` sends the
bare token. The header joins the request's `RequestHeaders`.

When the answer is a 401, an `HttpStatusFailure` with status 401 or a payload
whose `HttpResponseInfo` says 401 (`isUnauthorized` replaces that test), and
`refresh` was given, the link asks `token` once more. A token that changed
meanwhile, because another request already renewed it, is sent as it is.
Otherwise `refresh` runs, once for all the requests that wait for it at the
same time, and the request is sent again with the token it gives. A request is
sent again at most once, so a second 401 is the answer, and so is the first
when `refresh` is missing or gives null. A mutation can be sent again safely:
a 401 refuses the request before the server runs it.

An `Exception` thrown by `token` or `refresh` is a `LinkFailure` holding an
`AuthenticationFailure`; the request is not sent again.

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
  var token = 'expired';
  final mock = MockLink()
    ..addFailure(HttpStatusFailure(401))
    ..addData(JsonObject({'hello': JsonString('world')}));
  final client = GraphQLClient(
    link: Link.from([
      AuthLink(token: () => token, refresh: () async => token = 'fresh'),
      mock,
    ]),
  );
  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    print(data);
  }
  for (final request in mock.requests) {
    print(request.context.entry<RequestHeaders>()?.values);
  }
}
```

It prints:

```text
world
{authorization: Bearer expired}
{authorization: Bearer fresh}
```

## The order of a chain

The policies are middle links, so their order in `Link.from` matters. The
recommended order, from the client toward the transport:

1. `DedupeLink` first, so that identical queries share everything below it,
   the retries included.
2. `RetryLink` next, so that every attempt passes through the links below it
   again and gets a current token.
3. `AuthLink`, so that the header is added whatever the transport sends, and
   so that a 401 that comes back through the persisted query link is seen.
4. `PersistedQueryLink` last of the policies, because it decides what goes on
   the wire (the hash or the text) and its second request is part of one
   attempt, not a retry.
5. Then a `SplitLink` whose branches are the terminating links of your
   transports, one for subscriptions and one for the rest.

The program sends one query through the whole chain. The first attempt is
lost to the network, the second asks for a document the server does not know,
the third is refused for its token, and the fourth succeeds. The `MockLink`
shows what reached the transport.

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
  var token = 'expired';
  final mock = MockLink()
    ..addFailure(NetworkFailure(const FormatException('connection lost')))
    ..addErrors([GraphQLError('PersistedQueryNotFound')])
    ..addFailure(HttpStatusFailure(401))
    ..addData(JsonObject({'hello': JsonString('world')}));
  final client = GraphQLClient(
    link: Link.from([
      DedupeLink(),
      RetryLink(
        policy: const RetryPolicy(
          backoff: Backoff(initialDelay: Duration.zero),
        ),
      ),
      AuthLink(token: () => token, refresh: () async => token = 'fresh'),
      PersistedQueryLink(),
      mock,
    ]),
  );
  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    print(data);
  }
  for (final request in mock.requests) {
    final sent = request.body.query == null ? 'hash alone' : 'text and hash';
    final headers = request.context.entry<RequestHeaders>();
    print('$sent, ${headers?.values['authorization']}');
  }
}
```

It prints:

```text
world
hash alone, Bearer expired
hash alone, Bearer expired
text and hash, Bearer expired
hash alone, Bearer fresh
```

## Limits

`AuthLink` sets no timeout on `token()` or `refresh()`: a callback that never
completes keeps its requests waiting, so give them a timeout of your own.

`PersistedQueryLink` stops sending hashes for the life of the link after a
`PersistedQueryNotSupported` answer or a `GQL412`; create a new link to try
hashes again.

The key of `DedupeLink` is the request body and its `RequestHeaders`; other
context entries do not tell two requests apart.
