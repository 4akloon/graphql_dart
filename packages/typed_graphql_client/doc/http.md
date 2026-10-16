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

## HttpLink

`HttpLink` is the terminating link for queries and mutations. It sends
each as a `POST` with a JSON body to its `uri`, asking for
`application/graphql-response+json` first and plain JSON second. The
program below answers from memory with a transport of its own:

```dart
import 'dart:convert';

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

final class InMemoryServer implements HttpTransport {
  @override
  Future<TransportResponse> send(TransportRequest request) async {
    final body = await utf8.decodeStream(request.body ?? const Stream.empty());
    print('${request.method} ${request.uri} ${request.headers['accept']}');
    print(body);
    return TransportResponse(
      statusCode: 200,
      headers: {'content-type': 'application/graphql-response+json'},
      body: Stream.value(utf8.encode('{"data":{"hello":"world"}}')),
    );
  }
}

Future<void> main() async {
  final client = GraphQLClient(
    link: HttpLink(
      uri: Uri.parse('https://example.com/graphql'),
      transport: InMemoryServer(),
      timeout: const Duration(seconds: 30),
    ),
  );
  switch (await client.query(const HelloQuery())) {
    case GraphQLData(:final data, :final context):
      final status = context.entry<HttpResponseInfo>()?.statusCode;
      print('data: $data (HTTP $status)');
    case GraphQLErrors(:final errors):
      print('errors: ${errors.first.message}');
    case GraphQLTransportFailure(:final failure):
      print('failure: $failure');
  }
}
```

It prints:

```text
POST https://example.com/graphql application/graphql-response+json, application/json;q=0.9
{"query":"query Hello{hello}","operationName":"Hello"}
data: world (HTTP 200)
```

Headers come from three places, each over the one before: the link's own
(`accept`, `content-type`), the `headers` given to the link, and the
`RequestHeaders` entries of the request's context. Names are compared in
lower case. The exception is a multipart request: its `content-type` carries
the boundary of the body, so it is set last and no other header can replace
it.

With `usesGetForQueries: true`, a query goes as a `GET` request whose
`query`, `operationName`, `variables` and `extensions` (the last two as
JSON) are query parameters added to the URI's own, so a cache or a CDN can
keep the answer. A mutation is always a `POST`. A `GET` carries the header
`graphql-require-preflight: true`, which a server's CSRF prevention asks of
requests a browser could send from another site.

A `GET` puts the variables in the URL, so proxies and servers may log them:
keep secrets out of the variables of queries sent this way. A server or a
proxy that refuses a URL that is too long answers `414`, which arrives as an
`HttpStatusFailure`.

Redirects are the business of the `http.Client`, not of the link.
`PackageHttpTransport` sets nothing, so `package:http`'s defaults apply on
the VM: a `GET` follows up to five redirects, and a `POST` follows none, so a
`307` or `308` answer to a `POST` is an `HttpStatusFailure`. A browser
client follows redirects by the rules of `fetch`.

A subscription needs a streaming transport: `HttpLink` answers it with
`UnsupportedOperation` (`GQL468`) without sending anything. Send
subscriptions to the WebSocket or SSE link with a `SplitLink` (see the
Links guide).

## Reading the answer

The link reads the answer by the GraphQL over HTTP rules:

| Content type | Status | Result |
|---|---|---|
| `application/graphql-response+json` | any | the GraphQL response |
| `application/json` | 2xx | the GraphQL response |
| `application/json` | other | `HttpStatusFailure` (`GQL461`) |
| another or none | other than 2xx | `HttpStatusFailure` (`GQL461`) |
| another or none | 2xx | `ResponseFormatFailure` (`GQL462`) |

A charset other than UTF-8 is `GQL462`. The body is counted while it
arrives: past `maxResponseBytes` (16 MiB by default) the link aborts the
request with `GQL463`. Bytes that are not UTF-8, text that is not JSON,
JSON nested deeper than `maxResponseDepth` (512 by default) and JSON that
is not a GraphQL response are `GQL464`, with the path of the bad value.
The response's context holds an `HttpResponseInfo` with the status and
headers. The body of a `TransportResponse` is copied while it is read, so a
transport may reuse its chunks. The limits cannot protect the caller's own
variables: a variable value nested deeply enough overflows the stack of
`jsonEncode` before anything is sent.

An `Exception` of the transport, or of the body stream, is a
`NetworkFailure` (`GQL460`); the query string of any URL in its text is
removed, because `package:http` prints the whole URL of a `GET`. With a `timeout`, a request that has not
finished in time is aborted with `RequestTimedOut` (`GQL467`). Cancelling
the call aborts the request through the transport's `abortTrigger`.
