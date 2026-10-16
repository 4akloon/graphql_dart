# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package is not usable yet.
- The contract generated code compiles against: `GraphQLQuery`,
  `GraphQLMutation`, `GraphQLSubscription` (sealed `GraphQLOperation`),
  `OperationDocument`, `DataCodec` with the scalar, enum, object, nullable,
  list and JSON kinds, `DataContext`, `DataEquality`, `DataEnum`,
  `DataObject` and `DataFormatException`; the Generated Operations guide.
- `JsonMerger` merges the JSON of a class and its fragments deeply (objects by
  key, arrays by index), so generated `toJson` keeps every field of
  overlapping nested selections; a null never replaces a value.
- `CancelToken`: the caller's request to stop a call; the start of the
  Client guide.
- `ClientFailure`, a sealed family with a code each: `NetworkFailure`,
  `HttpStatusFailure`, `ResponseFormatFailure`, `DataFormatFailure`,
  `RequestCancelled`, `RequestTimedOut`, `UnsupportedOperation`,
  `SocketFailure`, `EventStreamFailure`, `AuthenticationFailure`.
- `LinkRequest`, `LinkResult` (`LinkPayload`, `LinkFailure`), `LinkContext`,
  `ContextEntry`, `RequestHeaders` and `HttpResponseInfo`; the start of the
  Links guide.
- `Link`, `NextLink` and `Link.from` (a chain), and `MockLink`, a
  terminating link for tests that records requests and serves queued
  answers (R8.5).
- `GraphQLClient` (`query`, `mutate`, `subscribe`, with a context and a
  cancel token) and the sealed `GraphQLResponse` (`GraphQLData`,
  `GraphQLErrors`, `GraphQLTransportFailure`) (R8.1, R8.2).
- `SplitLink` (route a request to one of two links) and `ContextLink`
  (rewrite a request's context before forwarding it).
- `Backoff`: exponential delays with full jitter, for retries and
  reconnections.
- `UploadFile`, `UploadFileCodec` (the `Upload` scalar's codec, which
  writes a file as its marker) and `UploadFiles` (the files of a request,
  in its context); the start of the Uploads guide.
- `RetryLink`, `RetryPolicy` and `Idempotent`: queries, and mutations marked
  idempotent, are sent again after a network failure, a timeout or a
  retryable HTTP status, after the backoff's delay; the start of the Request
  Policies guide.
- `DedupeLink`: identical queries in flight share one forwarded request, each
  caller keeping its own stream and its own cancellation.
- `PersistedQueryLink`: sends the document's hash instead of its text; in the
  automatic mode it falls back to the text when the server does not know the
  hash or stores no queries, in the trusted mode it never sends the text.
- `AuthLink`: adds an authorization header from a token callback and, on a 401,
  renews the token (one refresh for all requests waiting at once) and sends
  the request again once; a throwing callback is an `AuthenticationFailure`.
- The Request Policies guide completes with the recommended order of a chain
  and a program that runs all four policies over a `MockLink`.
- A link, a callback or a refresh that throws now ends the request of
  `RetryLink`, `AuthLink`, `PersistedQueryLink` and `DedupeLink` with an error
  event, not an uncaught error; `RetryLink` no longer retries after a payload
  was delivered; `TokenRenewal` no longer hands back a refused token after a
  failed refresh; `RequestHeaders` and `LinkContext` print header names only.
