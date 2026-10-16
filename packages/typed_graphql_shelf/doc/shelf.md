# shelf adapter

`typed_graphql_shelf` serves a `GraphQLServer` from a shelf application. The
adapter is thin: `GraphQLShelfHandler` turns each shelf `Request` into the
`HttpRequestData` of `typed_graphql_server`, runs `GraphQLHttpHandler` and
writes its `HttpResponseData` as a shelf `Response`. The limits, the media
types, the status codes and the GraphiQL page are the HTTP guide's of
`typed_graphql_server`.

## The handler

```text
final class GraphQLShelfHandler<C> {
  GraphQLShelfHandler(GraphQLServer<C> server, {HttpOptions http});
  FutureOr<Response> call(Request request);
}
```

The handler is a shelf `Handler`: pass `handler.call` to `shelf_io.serve`, or
mount it in a router at the path of the endpoint. Routing, CORS and logging
stay with shelf. The page of GraphiQL sends its queries to the path the
browser opened it at, so any mount point works.

## What the adapter decides

- Header names are lower-case and repeated headers are joined with `, `, as
  shelf gives them.
- A body is read from the request only when the handler needs it, and never
  past its size limit.
- A streamed body (an event stream) is written with `shelf.io.buffer_output`
  off, so each event reaches the client when it is written. `shelf_io` cancels
  the subscription when the client goes away, which ends the work behind it.
- No `CancelSignal` is given to the handler, because shelf does not report a
  client that went away outside a streamed body.
