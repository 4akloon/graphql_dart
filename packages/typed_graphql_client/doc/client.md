# Client

`GraphQLClient` sends the operations `typed_graphql_codegen` generates and
returns typed responses. This guide grows with the client; these sections
cover failures and cancellation.

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
