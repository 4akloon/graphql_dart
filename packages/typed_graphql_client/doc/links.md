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

## Testing with MockLink

`MockLink` is a terminating link for tests: it records every request in
`requests` and answers each with the next queued answer. `addData`,
`addErrors`, `addFailure` and `add` queue one result, `addStream` many; an
`operationName` makes an answer serve only that operation. A request with
no answer left gets a `StateError`, a bug in the test.
