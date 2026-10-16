# WebSocket

The graphql-ws transport (the `graphql-transport-ws` subprotocol) serves
queries, mutations and subscriptions over one WebSocket connection.

This guide is completed with the handler itself. For now it names the pieces
a host provides and configures: a `GraphQLSocket` over its own WebSocket,
`GraphQLWsOptions` for the limits and the origins it accepts, and a
`ConnectionHook` that decides, from the `connection_init` payload, whether to
acknowledge a connection.

The options have safe defaults:

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const options = GraphQLWsOptions();
  print(options.connectionInitTimeout);
  print(options.maxOperations);
  print(options.maxMessageLength);
}
```

It prints:

```text
0:00:03.000000
100
1048576
```
