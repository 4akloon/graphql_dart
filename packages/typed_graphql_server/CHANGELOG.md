# Changelog

## 0.0.1 - Unreleased

- Package skeleton.
- `repository` points at the package folder; pub.dev is expected to rewrite
  relative README links from it (to confirm at M16).
- The README says the package cannot execute requests yet.
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
- Typed arguments: `Arg`, `Arg.optional` with `Optional`, `Present` and
  `Absent`, `Arguments`, `ArgumentsDef` for an arguments class.
- `ExecutableSchemaBuilder.build` assembles the declared types into a
  validated `ExecutableSchema<C>`; the builder's own checks (`GQL300`-`GQL302`)
  and the core validator report through `SchemaBuildError`. `BuildOptions`
  holds the directives, `includesDeferAndStream` and the description.
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
- **Breaking:** `BuildOptions` is generic (`BuildOptions<C>`) and `build` takes `BuildOptions<C>?`.
