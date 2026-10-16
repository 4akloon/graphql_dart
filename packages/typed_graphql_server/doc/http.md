# HTTP

`GraphQLHttpHandler` serves GraphQL over HTTP on top of a `GraphQLServer`
(R5.5). It knows no web framework: a host adapter converts its own request
into an `HttpRequestData`, calls the handler and writes the
`HttpResponseData` it gets back. This guide describes the values the two
sides exchange.

## The values

An `HttpRequestData` holds the method, the full URI, the headers (names are
lower-cased), the body as a stream of byte chunks, and optionally the host's
own request object and a `CancelSignal` the host cancels when the client goes
away. The body is a stream so that the handler can stop reading at its size
limit; a host that has the bytes passes `Stream.value(bytes)`.

An `HttpResponseData` holds a status, headers and a body. The body is a
`FixedBody` (all bytes known) or a `StreamedBody` (chunks written as they
come).

```dart
import 'dart:convert';

import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final request = HttpRequestData(
    method: 'POST',
    uri: Uri.parse('http://localhost/graphql'),
    headers: {'Content-Type': 'application/json'},
    body: Stream.value(utf8.encode('{"query":"{ hello }"}')),
  );
  final response = HttpResponseData(
    200,
    headers: {'Content-Type': 'application/json'},
    body: FixedBody(utf8.encode('{"data":{"hello":"Hello"}}')),
  );
  print(request.header('CONTENT-TYPE'));
  print(response.headers['content-type']);
  print(response.status);
}
```

It prints:

```text
application/json
application/json
200
```
