# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- Typed refs: `OutputRef<T>` and `InputRef<T>`, `LeafRef<T>` for scalars and
  enums, `.nullable`, `b.list` and `b.inputList`; the built-in scalars
  `b.int`, `b.float`, `b.string`, `b.boolean` and `b.id`.
- `ExecutableSchemaBuilder<C>` declares custom scalars over a core
  `ScalarCodec` (`scalar`), enums over Dart enums (`enumType`,
  `EnumValueMapping`), input objects (`inputObject`, `oneOfInputObject`),
  object types (`object`, `ObjectOptions`), interfaces and unions
  (`interface`, `union`, `resolveType`, field inheritance through listed
  interfaces).
- Typed fields in two steps: `t.field(name, type, ...)` fixes the result
  type, then `pure`, `resolve`, `resolveWith` or `declareOnly`; `deprecated`
  and `withDirectives` modify the stub. A resolver of the wrong type does
  not compile (checked by the compile-failure tests).
- Typed arguments: `Arg`, `Arg.optional` with the core's `Optional`,
  `Present` and `Absent`, `Arguments`, `ArgumentsDef` for an arguments class.
- `ExecutableSchemaBuilder.build` assembles the declared types into a
  validated `ExecutableSchema<C>`; the builder's own checks (`GQL300`-`GQL302`)
  and the core validator report through `SchemaBuildError`. `BuildOptions<C>`
  holds the directives, `includesDeferAndStream`, the description, the plan
  cache size and the middleware.
- `FieldInfo` (field name, parent type name, response path) is the last
  argument of a resolver.
- The Schema Builder and Execution guides, with the dartdoc categories
  `builder` and `execution`.
- A bad default on an interface field argument is reported once (`GQL302`),
  not once per implementing type; the reason keeps the value and name of an
  `ArgumentError.value`.
- An interface counts only the objects that list it themselves as possible
  types, as graphql-js does.
- `pure` on a field that was given `args` is an `ArgumentError`.
- `GraphQLException`: an error a resolver, scalar or input object `decode` throws on purpose; its message and extensions reach the client unmasked.
- `BuildOptions.planCacheSize` (default 1000): operation plans (field collection per condition key, constant arguments coerced once) are cached per `ExecutableSchema`, least recently used first out.
- `ExecutableSchema.execute` runs a `ValidDocument` and returns
  `FutureOr<ResponsePayload>`: a query of synchronous resolvers returns an
  `ExecutionResult` at once. Request errors (`GQL320`-`GQL323`, bad
  variables) are a `RequestErrorResult`. Mutation root fields run one after
  another.
- Field errors follow the specified null propagation; errors the library
  makes carry `extensions.code` (`GQL330`-`GQL337`). Unexpected errors are
  masked (`Unexpected error.`) unless `maskErrors` is off; `GraphQLException`
  reaches the client as it is.
- `ExecutionOptions` (`rootValue`, `source`, `errorBehavior`, `maskErrors`,
  `onError`, `includesSuggestions`, `maxCoercionErrors`, `maxDepth`,
  `maxSteps`), `ErrorBehavior` (`propagate`, `nullValue`, `halt`) and the
  `ErrorHook` typedef. `maxDepth` (256) and `maxSteps` (10 000 000) end
  runaway executions with `GQL336` and `GQL337`.
- **Breaking:** `FieldInfo` carries the parent `ObjectType`, `returnType`,
  `fieldNodes`, `operation`, `variables`, `schema` and `rootValue`, and its
  `path` is a `ResponsePath` (`toList()` gives the segments).
- Field middleware: `FieldResolver<C>`, `FieldMiddleware<C>`, `DirectiveMiddleware<C>` and `FieldSite`; `FieldStub.withMiddleware`, `BuildOptions.middleware` and
  `BuildOptions.directiveMiddleware`. Chains are composed once per field at
  build time (global, field, directive slots; outermost first); the pure lane
  and an empty chain are called directly. A slot for an undefined directive is
  an `ArgumentError`.
- Variables and arguments are coerced with graphql-js's messages (all problems
  of a variable, `GQL310`-`GQL314`); literals substitute variables; the
  operation plan caches field collection per `@skip`/`@include`/`@defer`
  condition.
- The README shows a working program, `example/example.dart`, which a test
  keeps identical to it.
- The errors of a response come in document order whatever finished first. A
  throw while completing a value (`isTypeOf`, `resolveType`, a codec, a lazy
  iterable) is a field error, never a thrown `execute`. A codec's
  `ArgumentError` is `GQL332` with its message; a `RangeError` is masked. A
  too-deep field runs no resolver, and a too-deep list reports `GQL336` once.
- Introspection: `__schema` and `__type(name:)` on the query root answer what
  `Schema.toIntrospection(IntrospectionQuery.full)` writes, through internal
  bindings for the `__Schema`, `__Type`, `__Field`, `__InputValue`,
  `__EnumValue` and `__Directive` objects registered by `build`.
  `ExecutionOptions.introspection` takes `IntrospectionPolicy`: `disabled`
  makes `__schema` and `__type` a `GQL338` field error; `__typename` still works.
  `__type` answers only for the types `__schema` lists, in the order of
  `IntrospectionListing`; global middleware does not wrap introspection fields.
- Subscriptions: `t.field(...).subscribe(source)` (each event is the field's
  value) and `subscribeWith<E>(source, resolve)` declare a subscription root
  field; `build` reports `GQL303` for a source outside the subscription root
  or a root field without one. `ExecutableSchema.subscribe` answers a
  `SubscriptionStarted` with a single-subscription stream of
  `ExecutionResult`s (one event at a time, in order, the source paused while
  an event executes, so a broadcast source buffers without bound inside its
  paused subscription and the application must bound it; cancel, pause and
  resume reach the source; a source error, or an unexpected library error
  while executing an event, is a last masked `GQL340` result; the source
  function has already run when the stream is never listened to) or a
  `SubscriptionRejected` (request errors, `GQL324` for a query or mutation, a
  failing source function). `execute` on a subscription runs it once as a
  query.
- The Introspection and Subscriptions guides, with the dartdoc categories
  `introspection` and `subscription`.
- Look-ahead: `FieldInfo.selection` is a `FieldSelection` of the fields the
  request selected under the field (fragments flattened, `@skip` and
  `@include` applied, `__typename` hidden), built when first read.
  `fields`, `forType`, `has('posts.comments')`, `fieldsNamed` and
  `fingerprint` (canonical, for DataLoader keys); `SelectedField` has `name`,
  `alias`, `responseKey`, `arguments` (coerced on first read; an argument that
  fails reads as absent) and its own `selection`. `ColumnAllowlist` maps field
  names to sorted, de-duplicated columns. `isDeferred` arrives with
  incremental delivery.
- The Look-ahead guide and its dartdoc category `lookahead`.
- Look-ahead walks are bounded: a selection over an interface with many
  implementations costs its distinct nodes, not their product per level, a
  fingerprint reads fields over the same nodes once and lists identical
  entries once, and every walk spends the run's `maxSteps` budget (a read that
  would not fit throws `GQL337` as that field's error). Fields that share a
  response key but differ in name or arguments across object types stay apart.
- Authorization: `Authorization.requires` and `Authorization.public` rules on a
  field (`.withAuthorization`) or an object type (`ObjectOptions.authorization`),
  an `Authorizer<C>` in `BuildOptions.authorizer` that answers `Allow` or `Deny`
  (a `GQL352` field error) after argument coercion and before the middleware,
  on every lane, `GQL304` for a guarded field without an authorizer,
  `SelectedField.authorization`, `AuthorizationCoverage.uncovered` and the
  Authorization guide.
- Cancellation (R4.20): `CancelSignal` (`cancel`, `isCancelled`, `whenCancelled`,
  `reason`; no platform import), `ExecutionOptions.cancelSignal` and `timeout`,
  and `FieldInfo.cancelSignal`, the run's own signal. A cancelled or timed-out
  run starts no field, completes at once with `data: null` and one `GQL350` or
  `GQL351` error, and drops later resolver results; a synchronous query with a
  timeout stays synchronous, and the timer ends with the run. A subscription
  ends with a final cancellation result, cancels its source and closes; a
  signal cancelled at `subscribe` is a `SubscriptionRejected`. The Cancellation
  guide and its dartdoc category `cancellation`.
- A subscription starts its timer and its listener on the caller's signal at
  `subscribe` and releases both when the run's signal fires, also for a response
  stream nobody listens to; a finished stream stops listening to the run's signal.
- Documentation: the barrel states that M5 is complete, the Authorization guide
  warns that a redeclared interface field is unguarded without its own rule.
- A subscription field's authorization runs once, at subscribe, not for each
  event.
- Coerced arguments are unmodifiable (the argument map, input-object maps and
  lists), so a resolver cannot change the cached arguments of later requests.
- The `ExecutableSchema` and `FieldDef` constructors, `FieldDef.lane`,
  `FieldDef.middleware` and `CancelSignal.listenerCount` are `@internal`.
- A run that halted (for example `GQL337`) and is then cancelled answers with
  the halt error, not `GQL350`.
- `BatchLoader` batches and caches loads by key within a request (dispatch
  after the microtask queue drains, `maxBatchSize`, `prime`, `clear`);
  `MissingValueException` for a key the batch function left out. The DataLoader
  guide and its dartdoc category `dataloader`.
- `GroupedLoader` loads the list of children of a key (posts by author id) in
  one batch, with the cache and failure behaviour of `BatchLoader`; a missing
  key is an empty list and the lists it hands out are unmodifiable.
- `RequestInfo`, `ServerRequest`, `ServerResponse` (`SingleResponse`,
  `StreamResponse`), `ServerOutcome` and `ContextFactory`: the values the
  request pipeline takes and returns. Header names are lower-case.
- `ServerProfile` (`development`, `production`, one `with*` method per
  protection), `ServerLimits` and `CsrfPrevention`: the protections of a
  server as values that compare by value.
- `GraphQLServer<C>`: `handle(ServerRequest)` runs the request pipeline
  (document length, `GQL400`/`GQL401`, the document cache, the operation
  lookup, `GQL402` for a mutation over `GET`, the context factory, execution
  or subscription with the options of the `ServerProfile`) and never throws;
  unexpected errors go to `onError` and are masked (`GQL330`) per the profile.
- `ServerExtension<C>`: three hooks (`onRequest`, `onDocument`, `onExecute`),
  each with a default that calls `next`, passed to `GraphQLServer.extensions`
  (the first is the outermost and sees even the requests CSRF prevention
  refuses). `RequestHandler`, `DocumentHandler` and `ExecutionHandler<C>` are
  the `next` types; `DocumentRequest` (`withText`), the sealed
  `DocumentResult` (`DocumentAccepted` with the hash the server computed,
  `DocumentRejected`) and `ExecutionRequest<C>` (`withContext`,
  `withOptions`) are what the hooks take and return.
- CSRF prevention (`GQL403`) runs in the request phase when the profile has a
  `CsrfPrevention`: a request without a content type a browser cannot send
  cross-site and without a preflight header is refused before any other step.
- The cost limit (`ServerLimits.maxCost`, `defaultListSize`) runs for each
  request after the operation is selected and before the context is built: a
  request whose field cost or type cost is over the limit is refused with
  `GQL238` and `MaxCostRule`'s message. Slicing arguments given as variables
  count with the request's values.
- The Server guide and the example now serve a request with
  `GraphQLServer`.
- `PersistedQueryStore`, where a server keeps automatic persisted queries,
  and `MemoryPersistedQueryStore`, a bounded in-memory LRU.
- `GraphQLServer(persistedQueries:)` turns on automatic persisted queries:
  a hash alone runs a stored text (`GQL410` when it is not stored), a text
  with its hash is checked (`GQL411`) and stored once it validates, a
  malformed `extensions.persistedQuery` is `GQL413`. Without a store a hash
  alone is `GQL412`. A stored text is hashed again when read.
- `TrustedDocuments` (built from a map or decoded from the manifest
  `typed_graphql_codegen` writes) and `GraphQLServer(trustedDocuments:)`: a
  hash runs its trusted text (`GQL415` when none), a text runs only when it
  is trusted to the character (`GQL414`). Combined with `persistedQueries`
  it is an `ArgumentError`.
- The document cache is keyed by the text itself and bounded by the total
  length of the cached texts too: `GraphQLServer(documentCacheMaxLength:)`
  (default 4,000,000 characters) drops the least recently used documents to
  stay under it and never keeps a longer text.
- A mutation is refused with `GQL402` unless the method is `POST` (compared
  ignoring case): `GET`, `HEAD`, `PUT`, `DELETE`, `PATCH` and an empty method
  are refused.
- A trusted document runs the manifest's text, not the client's, so a text
  with a lone surrogate (which hashes like the same text with U+FFFD) cannot
  run or poison the cache entry of the trusted one.
- **Breaking:** `CsrfPrevention(requestHeaders:)` became
  `CsrfPrevention.withHeaders(headers)`, which copies the list;
  `requestHeaders` is unmodifiable.
- Automatic persisted queries do not write a text the store already holds.
- Documentation: the barrel, the package description and the README say what
  works today (the transports come with M7); the Server guide states what
  `ServerProfile.production` sets (no timeout), that the `ServerLimits` checks
  are `assert`s and how each bad value behaves in a release build, that a
  resolver must cap a slicing argument, that extension hooks are trusted
  server code, which errors become a response only in `handle`, and that the
  pipeline does not bound a hanging context factory, store or hook.
- Tests: a server built without `profile:` is checked to be a production
  server, a failing store write is checked to be answered as `GQL330`, and
  the wall-clock assertion and most real sleeps of the pipeline tests are
  gone.
- `ServerRequest.allowedOperationTypes` (default `ServerRequest.allOperationTypes`):
  a transport that cannot deliver an operation type narrows it, and the
  pipeline refuses another type with `GQL431` before the cost limit and the
  context factory (a `GET` mutation is still `GQL402`).
- `GraphQLServer.profile`: the profile the server was built with, which
  transports read.
- `CostBudget` and `ServerRequest.costBudget`: requests that share a budget
  also share one `maxCost`, which bounds their summed field cost and summed
  type cost. The request that would pass it is refused with `GQL430` and is
  not charged; a request over the limit alone is still `GQL238`.
- `HttpRequestData`, `HttpResponseData`, `FixedBody` and `StreamedBody`: the
  values a host adapter exchanges with the HTTP transport (the HTTP guide).
- `GraphQLHttpHandler<C>` and `HttpOptions`: GraphQL over HTTP for any web
  framework. It serves `GET` and `POST` with JSON bodies, negotiates
  `application/graphql-response+json` and `application/json` (a missing
  `Accept` is the legacy type), writes results with the status codes of the
  specification (`294` for a partial result, switchable with
  `usesPartialSuccessStatus`), reads the body within `maxBodyBytes` and
  `bodyTimeout` whatever `content-length` says, bounds JSON nesting
  (`maxJsonDepth`) and the URI (`maxUriLength`), and never throws.
- `BatchPolicy` and `HttpOptions.batching`: opt-in batches of requests (a JSON
  array), run in order with one shared `CostBudget`; a mutation or
  subscription item is `GQL431` in its slot.
- `HttpOptions.onError`: the error hook of the HTTP handler, called with a
  bug caught at its outermost boundary (answered `500`, `GQL330`) and its
  stack trace, like the hook of `GraphQLServer`.
- Every HTTP response varies on `Accept`; a transport refusal is
  `cache-control: no-store`; the echoed text of an unexpected error is cut at
  500 characters; the body read copies its chunks, stops when the host's
  cancel signal fires, and starts its timer only once the stream is
  listened to; a batch stops running items when the client has gone (the
  rest are `GQL350`).
- The transport codes `GQL420`-`GQL431`.
- The HTTP guide, with the dartdoc category `http`.
- `Upload`, `UploadStorage`, `MemoryUploadStorage`, `UploadLimits` and `Uploads`: the `Upload` scalar for multipart file uploads (its codec is input only), where a file waits during a request, and the limits of a request. The Uploads guide, with the dartdoc category `upload`.
- The multipart request reader (internal): reads `operations`, `map` and the files in order with `package:mime`, bounds every part and the body, refuses with `GQL440`-`GQL442`, `GQL427` and `GQL424`, and releases stored files on any refusal. Depends on `mime`.
- `HttpOptions.uploads`: `GraphQLHttpHandler` reads `multipart/form-data` requests of the GraphQL multipart request specification (queries, mutations and batches) when it holds an `Uploads` value; otherwise they stay `415` (`GQL421`), and the message of the `415` names both content types when uploads are on. CSRF prevention runs before the body is read (`403`, `GQL403`), the boundary and the declared length are checked first, and the files are removed from the registry and released in a `finally` after the response is built, whatever happened. The constructor of the handler refuses a non-positive `UploadLimits` value with an `ArgumentError`.
- The Uploads guide is complete (wiring, a runnable program, limits, CSRF, storage) and the HTTP guide points to it.
- `SseOptions` and the event stream (internal): the options of server-sent event streams (`keepAliveInterval`) and a response body that writes a first comment, keep-alive comments, `next` and `complete` events, and pauses, resumes and cancels its source with the client. The Server-sent events guide, with the dartdoc category `sse`.
- `HttpOptions.sse` (default `SseOptions()`, null turns event streams off): a `GET` or `POST` whose `Accept` prefers `text/event-stream` (offered last, never for a multipart `POST`) is answered with its own event stream, the distinct connections mode of graphql-sse: a subscription is one `next` event per result, a query, a mutation or a request error one `next`, each followed by `complete`. `405` and `500` and the refusals before the pipeline stay JSON; a batch is `406` (`GQL422`); cancelling the body cancels the subscription. The `406` message names every offered type. The constructor refuses a non-positive `keepAliveInterval`. A request that CSRF prevention blocks stays a `403` JSON refusal.
- `SingleConnectionOptions` and `SseOptions.singleConnection`: the single connection mode of graphql-sse, off by default. `PUT` reserves a stream (a token of 32 hex digits from `Random.secure`), a `GET` with the token connects it, a `POST` with the token and `extensions.operationId` runs an operation on it (`202`, its events carry the id and are held until the stream is listened to) and `DELETE ?operationId=` cancels one. Limits: `maxReservations`, `reservationTimeout` and `maxOperationsPerStream`; refusals `GQL433`-`GQL438`; closing the stream cancels its operations and drops the reservation.
- The Server-sent events guide is complete (both modes, the flow, limits, keep-alive, proxies, a runnable program), the HTTP guide points to it and the SSE hostile-input tests cover reservations, tokens, floods, slow and departing clients and cross-site requests.
