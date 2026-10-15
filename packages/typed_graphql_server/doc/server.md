# Server

This guide describes `RequestInfo`, the request a transport hands to the
server. It grows with the request pipeline.

`RequestInfo` holds the method, the URI and the headers of a request. Header
names are lower-cased when it is made, and `header` finds one by any case.

```dart
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  final info = RequestInfo(
    method: 'POST',
    uri: Uri.parse('http://localhost/graphql'),
    headers: {'Content-Type': 'application/json'},
  );
  print(info.headers.keys.join(', '));
  print(info.header('CONTENT-TYPE'));
}
```

It prints:

```text
content-type
application/json
```
