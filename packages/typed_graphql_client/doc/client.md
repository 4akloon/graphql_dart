# Client

`GraphQLClient` sends the operations `typed_graphql_codegen` generates and
returns typed responses. A client holds one `Link`, the chain its requests
go through (see the Links guide).

## Sending an operation

`query`, `mutate` and `subscribe` take a generated operation of the
matching kind. `query` and `mutate` complete with one `GraphQLResponse`;
`subscribe` returns a stream that starts the subscription when it is
listened to and gives one response per event. The response is a sealed
family:

| Response | When |
|---|---|
| `GraphQLData(data, errors)` | the operation ran; `errors` is not empty for partial data |
| `GraphQLErrors(errors)` | the request was refused, or an error left no data (`"data": null`) |
| `GraphQLTransportFailure(failure)` | no GraphQL response: see Failures below |

The program below stands a hand-written operation in for a generated one
and a `MockLink` in for a server. The second answer has a number where the
operation expects a string, so it does not fit the operation's classes.

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
  final link = MockLink()
    ..addData(JsonObject({'hello': JsonString('world')}))
    ..addData(JsonObject({'hello': JsonNumber(1)}))
    ..addErrors([GraphQLError('Cannot query field "hello".')]);
  final client = GraphQLClient(link: link);
  for (var i = 0; i < 3; i++) {
    switch (await client.query(const HelloQuery())) {
      case GraphQLData(:final data):
        print('data: $data');
      case GraphQLErrors(:final errors):
        print('errors: ${errors.first.message}');
      case GraphQLTransportFailure(:final failure):
        print('failure: $failure');
    }
  }
}
```

It prints:

```text
data: world
failure: GQL465: The data does not fit the operation: $.hello: expected a string
errors: Cannot query field "hello".
```

A response carries the `context` its terminating link wrote, such as the
HTTP status in `HttpResponseInfo`, and the response's `extensions`.

## Failures

When a request gets no GraphQL response, the client reports why as a
`ClientFailure`, a sealed family whose every kind has a stable `code`:

| Failure | Code | When |
|---|---|---|
| `NetworkFailure` | `GQL460` | the transport threw or the connection was lost |
| `HttpStatusFailure` | `GQL461` | an HTTP status outside 2xx without a GraphQL body |
| `ResponseFormatFailure` | `GQL462`-`GQL464` | an unreadable content type, a body too long, a body that is not a GraphQL response |
| `DataFormatFailure` | `GQL465` | `data` that does not fit the operation's classes |
| `RequestCancelled` | `GQL466` | the caller cancelled |
| `RequestTimedOut` | `GQL467` | a link's timeout passed |
| `UnsupportedOperation` | `GQL468`, `GQL469` | no link can carry the request, or the chain ended without a result |
| `SocketFailure` | `GQL470`-`GQL472` | a WebSocket broke the protocol, closed for good or was not acknowledged |
| `EventStreamFailure` | `GQL473` | a server-sent event stream broke the protocol |
| `AuthenticationFailure` | `GQL474` | the token callback threw |

The links report these codes: `HttpLink`, `WebSocketLink` and `SseLink` the
transport failures (`GQL460`-`GQL464`, `GQL467`, `GQL468`), `WebSocketLink`
`GQL470`-`GQL472`, `SseLink` `GQL473` and `AuthLink` `GQL474`; the client
itself reports `GQL465`, `GQL466` and `GQL469`.

Nothing a server or a network does makes the client throw.

## Cancelling a call

A `CancelToken` belongs to the caller: create one, pass it to a call, and
cancel it when the answer is no longer needed. The client listens to it and
never cancels it.

```text
final token = CancelToken();
token.cancel('the user left the page');
token.isCancelled; // true
token.reason;      // 'the user left the page'
```

Only the first `cancel` has an effect, and `whenCancelled` completes, never
with an error, once the token is cancelled.

Cancelling completes a pending `query` or `mutate` at once with
`GraphQLTransportFailure(RequestCancelled(reason))`, and ends a `subscribe`
stream with that failure as its last event. The client then cancels its
subscription to the link chain, which ends the request in every link: an
HTTP request is aborted (`HttpLink`), a WebSocket subscription is
completed (`WebSocketLink`) and a server-sent event stream is closed
(`SseLink`). A token
already cancelled answers without calling the link at all.

Cancelling the subscription to a `subscribe` stream ends the subscription
the same way, without a last event.
