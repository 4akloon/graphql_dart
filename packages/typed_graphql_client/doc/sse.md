# Server-sent events

`SseLink` sends queries, mutations and subscriptions over server-sent
events, in graphql-sse's distinct connections mode: one HTTP request, one
event stream, one operation. It is the way to run subscriptions where a
WebSocket is not available or not wanted. Like `HttpLink`, it does not
depend on one HTTP library: it uses an `HttpTransport` (see the HTTP
guide), whose response body may arrive in pieces.

## SseLink

The program below answers a subscription from memory with an event stream
of two `next` events and a `complete`:

```dart
import 'dart:convert';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

final class TicksSubscription extends GraphQLSubscription<int> {
  const TicksSubscription();

  @override
  OperationDocument get document => const OperationDocument(
    name: 'Ticks',
    type: OperationType.subscription,
    text: 'subscription Ticks{ticks}',
    sha256: '14c970476cf383579b21ff6dbb8326a9f2e3ea340def21bcb5bf9cf9b1af1f38',
  );

  @override
  JsonObject get variablesJson => JsonObject({});

  @override
  DecodeResult<int> decodeData(JsonObject data) => switch (data['ticks']) {
    JsonNumber(:final asInt?) => DecodeSuccess(asInt),
    _ => const DecodeFailure('expected an integer', path: [PathKey('ticks')]),
  };
}

final class InMemoryServer implements HttpTransport {
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    print('${request.method} ${request.uri} ${request.headers['accept']}');
    return TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'text/event-stream'},
      body: Stream.fromIterable([
        utf8.encode('event: next\ndata: {"data":{"ticks":1}}\n\n'),
        utf8.encode('event: next\ndata: {"data":{"ticks":2}}\n\n'),
        utf8.encode('event: complete\ndata:\n\n'),
      ]),
    );
  }
}

Future<void> main() async {
  final client = GraphQLClient(
    link: SseLink(
      uri: Uri.parse('https://example.com/graphql'),
      transport: InMemoryServer(),
    ),
  );
  await for (final response in client.subscribe(const TicksSubscription())) {
    switch (response) {
      case GraphQLData(:final data):
        print('tick $data');
      case GraphQLErrors(:final errors):
        print('errors: ${errors.first.message}');
      case GraphQLTransportFailure(:final failure):
        print('failure: $failure');
    }
  }
  print('done');
}
```

It prints:

```text
POST https://example.com/graphql text/event-stream
tick 1
tick 2
done
```

## What the link sends

Every operation, a query or a mutation too, is a `POST` with the JSON body
`{"query": ..., "operationName": ..., "variables": ...}` and the headers
`accept: text/event-stream` and `content-type: application/json`. Other
headers come from the `headers` given to the link and the `RequestHeaders`
entries of the request's context, the second over the first; names are
compared in lower case. These two headers describe the stream and the body,
so no configured header replaces them.

A request with `UploadFiles` in its context is not sent: the link answers
`UnsupportedOperation` (`GQL468`). Send files over `HttpLink` with a
`SplitLink`.

Route subscriptions to `SseLink` and everything else to `HttpLink` with a
`SplitLink` (see the Links guide):

```text
SplitLink(
  test: (request) => request.type == OperationType.subscription,
  whenTrue: sseLink,
  whenFalse: httpLink,
)
```

## How it reads the stream

The body is parsed as an event stream (WHATWG HTML, "Interpreting an event
stream"), as UTF-8, across any split of the chunks. Each event is handled
as it arrives:

| Answer | Result |
|---|---|
| a `next` event | the GraphQL response in its data, with an `HttpResponseInfo` in the context |
| a `complete` event | the stream ends and the connection closes |
| an event of another type, or of no type but with data | `EventStreamFailure` (`GQL473`), then the stream ends |
| an event with no type and empty data | ignored |
| the body ends before `complete` | `EventStreamFailure` (`GQL473`), then the stream ends |
| a `next` that is not a GraphQL response | `ResponseFormatFailure` (`GQL464`), then the stream ends |
| a 2xx event stream in a charset other than UTF-8 | `ResponseFormatFailure` (`GQL462`) |
| any other answer | read as `HttpLink` reads it |

A failure ends the stream and closes the connection. An answer that is
not an event stream, such as the `400` with a GraphQL response a server
sends for a bad request, is read by the rules of the HTTP guide: a GraphQL
response is a payload (so the client reports its errors), plain JSON with
a 2xx status is one result, and anything else is `GQL461` or `GQL462`. An
`Exception` of the transport or of the body stream is a `NetworkFailure`
(`GQL460`).

## Limits

An event, and the line being read, may hold at most `maxEventBytes` bytes
(16 MiB by default). Past it the link cancels the body and reports
`ResponseFormatFailure` (`GQL463`). Events completed earlier in the same
chunk are still delivered before the failure. Only the `event` and `data`
lines add to the count of an event; a comment or an unused field (`id`,
`retry`) is bounded by the same limit while its line is being read, and is
dropped as soon as it ends, so a server that sends only keep-alive comments
costs no memory. Bytes that are
not UTF-8 are `GQL464`, as is JSON nested deeper than `maxResponseDepth`
(512 by default).

## Cancelling

graphql-sse stops an operation by closing the connection. Cancelling the
result stream (or the call's `CancelToken`) completes the request's
`abortTrigger`, which the transport answers by closing the connection, and
cancels the body subscription. Pausing the stream pauses the body. The
link has no timeout, because a subscription lives as long as it is
listened to.

Single connection mode, where one stream carries every operation and
separate requests start them, is not supported.
