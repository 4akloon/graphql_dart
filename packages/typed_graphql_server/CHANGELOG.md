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
