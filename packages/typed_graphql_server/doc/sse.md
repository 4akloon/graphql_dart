# Server-sent events

GraphQL over server-sent events (R5.8) streams the results of a subscription,
or of any operation, as `text/event-stream`. `GraphQLHttpHandler` answers
event streams in the distinct connections mode and in the single connection
mode of the graphql-sse protocol.

This guide is written in steps. So far it holds the pieces of the event
stream itself.

## Distinct connections mode

`HttpOptions.sse` is `SseOptions()` by default; `null` turns event streams off,
and `Accept: text/event-stream` alone is then `406` (`GQL422`). A `GET` or
`POST` whose `Accept` prefers `text/event-stream` is answered with an event
stream of its own operation, and `*/*` still gets
`application/graphql-response+json`. A subscription sends one `next` event
per result; a query, a mutation or a request error (a parse or validation
error included) sends one `next` event; each stream ends with `complete`. A
`GET` mutation is `405`, `500` is `500` and the refusals that precede the
pipeline (`415`, `413`, `400`) stay JSON. A batch cannot be answered as an
event stream (`406`), and a multipart `POST` does not offer one. When the
client goes away, the subscription is cancelled.

## Event streams

An event stream answers `200` with `content-type: text/event-stream;
charset=utf-8` and `cache-control: no-cache`. It sends no `connection` header:
the header is hop-by-hop and forbidden in HTTP/2. The body is written as it
comes and starts with a comment (`:`), which flushes the headers through
proxies. Events are `next`, one per result, and `complete`.

`SseOptions.keepAliveInterval` (12 seconds by default) is how long a stream
may stay silent before the server writes another comment, so that proxies and
load balancers do not close an idle connection:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const options = SseOptions(keepAliveInterval: Duration(seconds: 5));
  print(options.keepAliveInterval.inSeconds);
}
```

It prints:

```text
5
```
