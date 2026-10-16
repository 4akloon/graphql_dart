# Links

A request goes from the client through a chain of links to a terminating
link that talks to the server. This guide grows with the links; this
section covers what travels through them.

## Requests, results and context

A `LinkRequest` holds the operation's `document` (name, type, text and
hash), its `variables`, optional `extensions` and a `LinkContext`. Its
`body` is the request as it is sent. It is immutable: a link forwards a
copy made with `withContext`, `withExtensions` or `withDocumentText`.

A link answers with a stream of `LinkResult` values: a `LinkPayload` (the
response as the server sent it) or a `LinkFailure` (a `ClientFailure`).
Failures are values, never stream errors.

A `LinkContext` holds `ContextEntry` values; `entry<T>()` reads the last
entry of a type and `withEntry` gives a new context with an entry
replaced. Two entries come with the client: `RequestHeaders` adds HTTP
headers to one request, and `HttpResponseInfo` tells the status and the
headers of the answer a result came from.

```text
final context = LinkContext([RequestHeaders({'X-Trace': 'abc'})]);
context.entry<RequestHeaders>()?.values; // {x-trace: abc}
```

## Writing a link

A link extends `Link` and implements `request(request, forward)`. A middle
link calls `forward` with the request, changed or not, and returns the
answer, changed or not; a terminating link answers itself. `Link.from`
runs links in order: each one's `forward` calls the next.

```text
final class TraceLink extends Link {
  @override
  Stream<LinkResult> request(LinkRequest request, NextLink forward) {
    final headers = request.context.entry<RequestHeaders>() ?? RequestHeaders({});
    return forward(request.withContext(
      request.context.withEntry(headers.withHeader('x-trace', 'abc')),
    ));
  }
}
```

Cancelling the subscription to a link's stream must end what the link
started: a link built from stream operations (`map`, `asyncExpand`,
`async*`) does so by itself.

## Routing and context

`SplitLink(test:, whenTrue:, whenFalse:)` sends each request down one of
two links; the usual split sends subscriptions over a socket and the rest
over HTTP. `ContextLink(update)` rewrites the context of each request
before forwarding it, for headers computed at the time of the request; an
exception of `update` is a `NetworkFailure` result.

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
  final http = MockLink()
    ..addData(JsonObject({'hello': JsonString('over HTTP')}));
  final sockets = MockLink();
  final client = GraphQLClient(
    link: Link.from([
      ContextLink(
        (request) =>
            request.context.withEntry(RequestHeaders({'X-Trace': 'abc'})),
      ),
      SplitLink(
        test: (request) => request.type == OperationType.subscription,
        whenTrue: sockets,
        whenFalse: http,
      ),
    ]),
  );
  if (await client.query(const HelloQuery()) case GraphQLData(:final data)) {
    print(data);
  }
  print(http.requests.single.context.entry<RequestHeaders>()?.values);
  print(sockets.requests.length);
}
```

It prints:

```text
over HTTP
{x-trace: abc}
0
```

## Backoff

`Backoff(initialDelay:, maxDelay:, multiplier:)` says how long to wait
before a retry or a reconnection. The ceiling of retry `n` (from 0) is
`initialDelay` times `multiplier` to the power `n`, at most `maxDelay`;
`delayFor(n, random)` draws a wait between zero and that ceiling ("full
jitter"), so clients that failed together do not retry together. The
defaults are 300 ms, 30 s and 2.

```text
const Backoff().ceilingFor(0); // 0:00:00.300000
const Backoff().ceilingFor(3); // 0:00:02.400000
```

## Testing with MockLink

`MockLink` is a terminating link for tests: it records every request in
`requests` and answers each with the next queued answer. `addData`,
`addErrors`, `addFailure` and `add` queue one result, `addStream` many; an
`operationName` makes an answer serve only that operation. A request with
no answer left gets a `StateError`, a bug in the test.
