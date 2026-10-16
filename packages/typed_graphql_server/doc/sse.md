# Server-sent events

GraphQL over server-sent events (R5.8) streams the results of a subscription,
or of any operation, as `text/event-stream`. `GraphQLHttpHandler` answers
event streams in the distinct connections mode and in the single connection
mode of the graphql-sse protocol.

This guide is written in steps. So far it holds the pieces of the event
stream itself.

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
