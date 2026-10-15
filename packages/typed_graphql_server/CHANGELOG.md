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
  fails reads as absent) and its own `selection`. `ColumnWhitelist` maps field
  names to sorted, de-duplicated columns. `isDeferred` arrives with
  incremental delivery.
- The Look-ahead guide and its dartdoc category `lookahead`.
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
