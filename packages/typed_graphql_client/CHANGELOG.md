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
