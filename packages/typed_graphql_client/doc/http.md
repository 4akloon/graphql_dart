# HTTP

The client sends queries and mutations over GraphQL over HTTP. The link
does not depend on one HTTP library: it hands each request to an
`HttpTransport`, a one-method interface.

## Transports

`PackageHttpTransport` adapts any `http.Client` of `package:http`, so the
same client code runs on the VM, in Flutter and in a browser:

```text
import 'package:http/http.dart' as http;

final transport = PackageHttpTransport(http.Client());
```

The client you pass belongs to you: close it when the app no longer needs
it. On the browser, `http.Client()` is the fetch-based `BrowserClient`; a
Flutter app may pass `cupertino_http` or `cronet_http` instead.

A transport of your own implements `send`: it takes a `TransportRequest`
(method, URL, headers in lower case, a body stream, its length when known
and an `abortTrigger`) and returns a `TransportResponse` (status, headers,
body stream). It reports a lost connection by throwing an `Exception`, and
closes the connection when `abortTrigger` completes. Tests and in-memory
servers implement it directly.
