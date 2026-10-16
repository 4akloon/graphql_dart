# Client

`GraphQLClient` sends the operations `typed_graphql_codegen` generates and
returns typed responses. This guide grows with the client; this section
covers cancellation.

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
