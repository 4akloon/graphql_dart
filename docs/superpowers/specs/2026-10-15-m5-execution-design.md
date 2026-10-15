# M5 Execution: stage design

Stage M5 of the [roadmap](../../roadmap.md): the typed schema builder, the
executable schema, variable and argument coercion, the operation plan and
its cache, the `FutureOr` executor, error behaviours and masking, field
middleware, introspection, subscriptions, look-ahead, the `Authorizer`
hook, cancellation and benchmarks (R4.1–R4.14, R4.17–R4.20). It refines
section 4 of the architecture spec
(`2026-10-13-typed-graphql-design.md`); every change to it is listed in
section 18.

## 1. Scope and delivery

M5 lives in `packages/typed_graphql_server`. The core changes only where
the server needs a public piece of it: the `GQL3xx` diagnostic codes and
the export of `Suggestions`. M5 is split into four sub-stages; each is
independently mergeable, leaves the tree green and has its own plan in
`docs/superpowers/plans/`:

| Sub-stage | Delivers | Requirements | Plan |
|---|---|---|---|
| M5a | The typed builder: refs, scalars, enums, arguments, input objects, object, interface and union types, `build()`, `ExecutableSchema`, `SchemaBuildError`; the Schema Builder guide | R4.1, R4.3–R4.6 | `2026-10-15-m5a-typed-builder.md` |
| M5b | Variable and argument coercion, `OperationPlan` and its cache, the executor, null propagation, error behaviours, masking, middleware, abstract types at run time; the graphql-js execution suites; the Execution guide, the example, discovery | R4.2, R4.7–R4.12 | `2026-10-15-m5b-execution-core.md` |
| M5c | Introspection resolvers and `IntrospectionPolicy`, subscriptions; their suites and guide sections | R4.13, R4.14 | `2026-10-15-m5c-introspection-and-subscriptions.md` |
| M5d | Look-ahead, `Authorizer` and its coverage check, `CancelSignal` and the timeout, the cancellation suite, benchmarks; the stage's last documents | R4.17–R4.20 | `2026-10-15-m5d-lookahead-authorization-cancellation.md` |

Out of scope: DataLoader (R4.15, M6), `executeIncrementally` (R4.16, M14),
the request pipeline, `ServerProfile` and transports (M6, M7), generated
code (M8, M9).

## 2. Layering

`packages/typed_graphql_server/lib/src/` has one folder per concern. The
core imports only through `package:typed_graphql/typed_graphql.dart`
(never `src/`). Unlike the core's layers, the folders have no import
order: the builder creates an `ExecutableSchema` that runs the executor,
and the executor reads the builder's definitions, so `builder/` and
`execution/` import each other; each folder still holds one concern.

| Folder | Holds | Sub-stage |
|---|---|---|
| `builder/` | refs, type and field definitions, `ExecutableSchemaBuilder`, the schema assembly, `SchemaBuildError` | M5a |
| `coercion/` | variable, argument and input-object coercion, the value inspector | M5b |
| `plan/` | `OperationPlan`, field collection, `PlanCache` | M5b |
| `execution/` | `ExecutableSchema.execute`, the executor, errors, `ExecutionOptions`, `FieldInfo`, middleware composition | M5a (`FieldInfo`, `ExecutableSchema`), M5b |
| `introspection/` | the `__Schema` family as object types, `IntrospectionPolicy` | M5c |
| `subscription/` | `subscribe`, `SubscriptionResult` | M5c |
| `lookahead/` | `FieldSelection`, `SelectedField`, `ColumnAllowlist` | M5d |
| `authorization/` | `Authorizer`, `Authorization`, `AuthorizationCoverage` | M5d |
| `cancellation/` | `CancelSignal` | M5d |

A quality test in the server package (`test/quality/imports_test.dart`)
checks that `lib/` imports only `dart:async`, `dart:collection`,
`dart:core`, `dart:math`, `package:meta` and the core barrel: the server
runs on the VM, AOT, dart2js and dart2wasm like the core (R0.6), and no
transport (section 17).

The package depends on `typed_graphql` and, when a class first needs
`@immutable`, `meta`; nothing else.

## 3. The typed builder (M5a; R4.1, R4.3–R4.6)

### 3.1 Names

The core already exports `SchemaBuilder` (SDL to `Schema`), so the
server's builder is `ExecutableSchemaBuilder<C>`; `C` is the context type
every resolver receives. The architecture spec's `SchemaBuilder<C>` is
renamed (section 18).

```text
final b = ExecutableSchemaBuilder<AppContext>();
final first = Arg('first', b.int, defaultValue: 10);              // Arg<int>
late final ObjectTypeDef<User> user = b.object<User>('User', fields: (t) => [
  t.field('name', b.string).pure((u) => u.name),                   // sync lane
  t.field('posts', b.list(post), args: [first])
      .resolve((u, args, ctx, info) => ctx.posts(u.id, args.get(first))),
]);
final schema = b.build(query: query);                            // ExecutableSchema<AppContext>
```

### 3.2 Why a field is declared in two steps

Dart generic inference is covariant: in
`field<R>(String name, OutputRef<R> type, FutureOr<R> Function(P) resolve)`
a closure returning `String?` makes `R` `String?`, and `b.string`
(`OutputRef<String>`) is accepted as an `OutputRef<String?>`, so a
nullable result for a non-null field compiles. This was checked with Dart
3.13.5. Two shapes reject it: `R` fixed before the closure is inferred
(`t.field(name, type)` returns a `FieldStub<P, R, C>`, then
`.pure(...)` / `.resolve(...)` take a closure whose return type is
already `R`), or `R` in a closure parameter. The builder uses the first:
`t.field('name', b.string).pure((u) => u.nick)` with `nick` a `String?`
is a compile error (`return_of_invalid_type_from_closure`). A VM test
compiles fixtures that must fail (`test/compile/`, see section 3.10).

### 3.3 Refs

- `OutputRef<R>`: a GraphQL output type whose Dart value is `R`. Non-null
  by default; `.nullable` gives `OutputRef<R?>`. `b.list(item)` gives
  `OutputRef<Iterable<R>>` (non-null list).
- `InputRef<T>`: a GraphQL input type decoded to `T`. `.nullable` gives
  `InputRef<T?>`; `b.inputList(item)` gives `InputRef<List<T>>`.
- Every ref knows its core `TypeRef` (`NamedType`, `ListType`,
  `NonNullType` nodes built once) and its named definition. An input ref
  also knows how to give its Dart value from a coerced value (`List<T>`
  must be a real `List<T>`, not `List<Object?>`: generics are reified).
- Leaf definitions (`ScalarTypeDef<T>`, `EnumTypeDef<E>`) are both
  `OutputRef` and `InputRef`; their `.nullable` is a leaf ref too.
- Built-in scalars: `b.int` (`int`), `b.float` (`double`), `b.string`,
  `b.boolean` (`bool`), `b.id` (`String`), backed by the core codecs.
- Custom scalars: `b.scalar<T>(name, codec, {description,
  specifiedByUrl})` over a core `ScalarCodec<T>`.
- Enums: `b.enumType<E extends Enum>(name, values, {mapping,
  description})`, where `EnumValueMapping<E>({nameOf, descriptionOf,
  deprecationReasonOf})` groups the per-value callbacks; `nameOf`
  defaults to `Enum.name` (open question 3).
- The code rules allow five parameters per method (section 18), so
  settings past five go into a parameter object (`EnumValueMapping`,
  `ObjectOptions`), a second method (`b.oneOfInputObject`) or a fluent
  modifier on the field stub (section 3.4).

### 3.4 Object types and fields

- `b.object<P>(name, {required fields, interfaces, description,
  options})` returns `ObjectTypeDef<P>`, an
  `OutputRef<P>`. `fields` is a thunk `(FieldsBuilder<P, C> t) => [...]`
  evaluated by `build()`, so types may refer to each other (`late final`
  or class fields; documented). `ObjectOptions({isTypeOf, directives,
  authorization})` holds the rarer settings.
- `t.field(name, type, {args, description})` returns
  `FieldStub<P, R, C>`; a stub is not a `FieldDef`, so a field without a
  resolver does not compile. Modifiers return a new stub:
  `.deprecated(reason)`, `.withDirectives([...])`,
  `.withMiddleware([...])` (M5b), `.withAuthorization(...)` (M5d). Its
  completions:
  - `.pure(R Function(P parent))`: the pure lane (R4.2): synchronous, no
    arguments, no middleware, no `FieldInfo` allocated. A guarded field
    (section 12) still goes through the `Authorizer`.
  - `.resolve(FutureOr<R> Function(P parent, Arguments args, C context,
    FieldInfo info))`.
  - `.resolveWith<A>(ArgumentsDef<A> def, FutureOr<R> Function(P, A, C,
    FieldInfo))`: an arguments class (R4.3); `def` lists the `Arg`s and
    decodes an `Arguments` into `A`.
  - `.subscribe(Stream<R> Function(P, Arguments, C, FieldInfo))` and
    `.subscribeWith<E>(source, resolve)` for subscription root fields
    (M5c adds them; M5a declares neither).
  - `.declareOnly()` on an interface field: no resolver, every
    implementing object must declare the field (the core validator
    reports one that does not).
- The executor calls resolvers through wrappers created where `P`, `R`
  and `C` are known, so the cast of the parent is one checked `as P` in
  the wrapper.
- `__typename` is answered by the executor, not by a field definition.

### 3.5 Arguments (R4.3)

- `Arg<T>(name, InputRef<T> type, {T? defaultValue, description,
  deprecationReason})`. A null `defaultValue` means "no default": a
  nullable argument without a value is `null` anyway, and an `Optional`
  argument (below) tells absence apart. Dart operators cannot be generic,
  so the architecture spec's `args[first]` is `args.get(first)`
  (section 18).
- `Arguments.get<T>(Arg<T> arg)`: the coerced value; an argument the
  field did not declare is a `StateError`.
- `Arg.optional<T>(name, InputRef<T> type)` is an `Arg<Optional<T>>`:
  `Optional<T>` is sealed, `Present<T>(value)` | `Absent()` (R4.4), for
  inputs where absence differs from `null` (partial updates).
- `ArgumentsDef<A>(List<Arg<Object?>> args, A Function(Arguments) decode)`.

### 3.6 Input objects and enums (R4.4)

- `b.inputObject<T>(name, {required fields, required decode, encode,
  description})` and `b.oneOfInputObject<T>(...)` (the same with
  `@oneOf`): `fields` is a thunk returning `Arg`s (input fields are
  arguments in all but name), `decode(Arguments values)` gives `T`
  (one `Arguments` class reads field arguments and input fields), `encode(T)` gives a `JsonObject` and is needed only when a
  default value of this type must be printed (build error otherwise).
- A `decode` that throws `GraphQLException` rejects the value with its
  message; any other exception is masked (section 9).
- Enums map Dart values to names both ways; a Dart value outside the
  definition is a serialization error at run time.

### 3.7 Interfaces and unions (R4.5)

- `b.interface<P>(name, {required fields, interfaces, description,
  resolveType})`. An object type that lists the interface inherits every
  interface field it does not declare, resolver included; this needs the
  object's `P` to be a subtype of the interface's `P`, checked at build
  with `<A>[] is List<B>` (`GQL300`), because Dart has no contravariant
  type parameter to check it at compile time.
- `b.union<P>(name, {required List<ObjectTypeDef<P>> members,
  resolveType, description})`: covariance checks the members at compile
  time (`ObjectTypeDef<Cat>` is an `ObjectTypeDef<Pet>`).
- Type resolution: an explicit `resolveType: (P value) => ObjectTypeDef`
  (an exhaustive `switch` over a sealed class), or by default the first
  possible type whose `isTypeOf` (default `value is P`) accepts the
  value, in possible-type order. When two possible types' Dart types
  overlap and the abstract type has no `resolveType` and neither has an
  explicit `isTypeOf`, the default would guess: a build error (`GQL301`).

### 3.8 Building (R4.6)

`b.build({required query, mutation, subscription, middleware,
directiveMiddleware, directives, includesDeferAndStream, description,
planCacheSize})`:

1. Every definition created through `b` is part of the schema, in
   creation order (so implementations reachable only through an interface
   need no `types:` list).
2. Field thunks run once; each `FieldDef` becomes a core `SchemaField`,
   each definition a core `SchemaType`, arguments and input fields
   `InputValue`s with default values as core `Value` literals (encoded
   with the codec, the enum map or the input object's `encode`).
3. The builder's own checks run (`GQL300`–`GQL304`), then the core
   `SchemaValidator`.
4. Any error throws `SchemaBuildError(diagnostics)` with every diagnostic
   (a programmer error: the schema is code). Its `toString` lists them.
5. Otherwise `ExecutableSchema<C>` holds the `ValidSchema` and the
   binding tables by type name: field bindings (resolver wrapper, lane,
   arguments, middleware chain), type resolution, codecs, enum maps,
   input decoders.

### 3.9 `ExecutableSchema<C>`

`schema` (the `ValidSchema`), `execute` (M5b), `subscribe` (M5c). The SDL
is `const SchemaPrinter().print(schema.schema)`.

### 3.10 Compile-time checks (R4.1)

`test/compile/` holds fixtures under `test/compile/fixtures/` (not
`*_test.dart`, so the test runner ignores them; the analyzer still sees
them, so each fixture that must fail is a `.dart.txt` file). A VM test
copies each into `.dart_tool/compile_fixtures/` and runs `dart compile
kernel`, expecting failure and a named error code in the output; one
fixture that must compile guards against a broken harness.

## 4. Coercion (M5b; R4.7)

### 4.1 Values

Coerced values are Dart values: scalars as their codec's `T`, enums as
the Dart value, lists as `List<Object?>`, input objects as their
`decode` result. `Arguments.get` and `InputValues.get` give the typed
value through the ref (`List<T>` rebuilt, `Optional` wrapped).

### 4.2 Variables

`VariableCoercion` follows September2025 §6.4.1 `CoerceVariableValues`
and graphql-js 17 `coerceVariableValues` / `validateInputValue`, with its
messages to the character (`Variable "$x" has invalid value at .a[0]:
...`, `Expected value of non-null type "T" not to be null.`, "Did you
mean" through the core's `Suggestions`, values printed by `ValueInspector`
as graphql-js's `inspect`). The first `maxCoercionErrors` (50) errors are
kept, then "Too many errors processing variables, error limit reached.
Execution aborted."; errors are request errors (`RequestErrorResult`),
apart from field errors (R4.7). A default value is coerced from its
literal; a custom scalar's literal goes through `LiteralConverter` and
the codec.

### 4.3 Arguments

`ArgumentCoercion` follows §6.4.1 `CoerceArgumentValues` and graphql-js
`getArgumentValues`: literals (with variables substituted), defaults,
`Optional` absence. A field whose arguments are all constant has them
coerced once per plan node (section 5); a failure is a field error at
that field. Input objects with `@oneOf` follow the September2025 rules.

### 4.4 Depth

A value from `JsonReader` has at most 512 levels, but a `JsonObject` built
in code has no bound, and recursive input objects make depth follow the
value. Coercion recurses (the JSON reader's precedent: bounded recursion
fits the stack on every platform up to `JsonReader.maxSupportedDepth`,
1000 levels), and a value nested deeper than that is a coercion error
("nested too deeply"), never a stack overflow.

## 5. The operation plan (M5b; R4.8)

- `OperationPlan`: built per (document identity, operation name): the
  operation, its root type, the fragments by name, the variable
  definitions, the condition variables (variables used by `@skip` /
  `@include`), and whether `@defer` / `@stream` are used.
- A request computes a condition key, the booleans of the condition
  variables. `plan.rootFor(key)` gives the root `PlanNode`; a node holds
  the fields collected for one object type (§6.3.2 `CollectFields`,
  explicit stack, each fragment once per collection), merged by response
  key; each `FieldPlan` has its field nodes, its `SchemaField`, its
  argument plan (constant arguments coerced once), `isDeferred`, and its
  child nodes per runtime object type, built on first use and memoised.
- Per plan, at most 16 condition keys are memoised (LRU); a plan is
  immutable apart from those memo tables, which only grow by
  deterministic values, so sharing a plan between concurrent executions
  is safe on the single-threaded event loop.
- `PlanCache` is an LRU keyed by the `Document` instance (syntax nodes
  compare by identity) and the operation name, `planCacheSize` entries
  (1000) per `ExecutableSchema`. Compilation is synchronous, so it is
  single-flight by construction: no two executions can compile one plan
  at the same time (R4.8).
- `@defer` and `@stream` (when the schema includes them) are recorded on
  the plan and executed inline in M5 (section 18).

## 6. The executor (M5b; R4.2, R4.9, R4.10)

- `execute(ValidDocument document, {required C context, String?
  operationName, JsonObject? variables, ExecutionOptions options})`
  returns `FutureOr<ResponsePayload>`: an `ExecutionResult`, or a
  `RequestErrorResult` for request errors (no operation, unknown name,
  unsupported operation type, variable coercion). A `ValidDocument` of
  another schema is an `ArgumentError`, and so is a `rootValue` the root
  type's Dart type does not accept.
- `ExecutionOptions` (const) holds everything else, per call: `rootValue`,
  `source`, `errorBehavior`, `maskErrors`, `onError`,
  `includesSuggestions`, `maxCoercionErrors` (50), `maxDepth` (256),
  `maxSteps` (10 000 000), and later `introspection` (M5c),
  `cancelSignal` and `timeout` (M5d). The code rules allow five
  parameters, and a pipeline (M6) builds one options value per request
  from its configuration and the request.
- `FutureOr` everywhere: a field whose resolver returns a value completes
  synchronously, so a query with only synchronous resolvers returns an
  `ExecutionResult`, not a `Future` (tested). Sibling fields are started in
  order; with no pending sibling the object completes at once, with one it
  chains `.then`, with two or more it uses `Future.wait` (R4.9). No
  `async` function on the hot path.
- Mutations run their root fields serially (§6.2.2).
- Result values are built as `JsonValue`s directly; an object's keys are
  inserted in collection order, so asynchronous completion keeps the order.
- Null propagation (§6.4.4) uses a sentinel returned from completion, not
  an exception. `ErrorBehavior` (the `onError` proposal) is an option:
  `propagate` (default, the spec), `null` (an error makes the field null
  and stops there, even when non-null), `halt` (the first error ends the
  execution: `data` is null, `errors` holds that error).
- Leaf serialization: Int range and Float finiteness with graphql-js's
  messages (`Int cannot represent non 32-bit signed integer value: ...`),
  enum values outside the definition (`Enum "E" cannot represent value:
  ...`), custom codecs through `encode`.
- Depth: completion recurses once per field and list level; past
  `ExecutionOptions.maxDepth` (256) a field error (`GQL336`) ends that
  branch. Documents are already bounded by the parser (`maxDepth` 128).
- Work: each completed value is a step; past `maxSteps` (10 000 000) the
  execution halts with `GQL337` (section 16).

## 7. Errors and masking (M5b; R4.11)

- A resolver's synchronous throw or failed future is caught with
  `on Object catch` and becomes a `GraphQLError` with `path` and
  `locations` (the field nodes' offsets in `options.source`, the text
  the document was parsed from, as `DocumentValidator.validate` takes it;
  `ValidDocument` does not keep it, and the core stays unchanged).
- `GraphQLException(message, {extensions})` (an `Exception` in the server
  package) reaches the client as is.
- Any other error is masked by default (`maskErrors: true`):
  `Unexpected error.` with `extensions.code` `GQL330`. With
  `maskErrors: false` the message is the error's `toString()`.
- `ExecutionOptions.onError(Object error, StackTrace stackTrace,
  GraphQLError reported)` returns `GraphQLError?`. It runs for every
  error thrown by user code (resolvers, middleware, `decode`, codecs, the
  authorizer, subscription sources), before the masked or raw error is
  recorded: `reported` is what would be recorded, a non-null result
  replaces it. A host logs and maps errors here (section 17); an
  exception thrown by the hook itself is recorded as the masked error.
- Every error the library itself creates carries `extensions: {code:
  "GQL3xx"}` (section 18); a `GraphQLException`'s extensions are kept as
  given.

## 8. Field middleware (M5b; R4.12)

`typedef FieldResolver<C> = FutureOr<Object?> Function(Object? parent,
Arguments args, C context, FieldInfo info)` and
`typedef FieldMiddleware<C> = FieldResolver<C> Function(FieldResolver<C>
next, FieldSite field)`, where `FieldSite` names the parent type and the
`SchemaField`. Chains are composed once per field at build time in the
order global → field → directive slots (`directiveMiddleware`,
keyed by directive name, applied to fields carrying that directive in
declaration order); the outermost runs first. A middleware may return
`next` unchanged for fields it ignores, so it costs nothing there; an
empty chain is the resolver itself (a direct call). The pure lane has no
chain. There is no type-level slot: a global middleware sees
`FieldSite.parentType` at build time and returns `next` for other types,
which costs nothing (section 18).

## 9. Introspection (M5c; R4.14)

`__Schema`, `__Type`, `__Field`, `__InputValue`, `__EnumValue`,
`__Directive` are ordinary internal object types with pure resolvers over
the core model (`ValidSchema`, `SchemaType`, `SchemaField`, ...); a list
or non-null `__Type` is a small internal wrapper value. `__schema` and
`__type(name:)` are meta fields of the query root, `__typename` of every
object. `ExecutionOptions.introspection` takes `IntrospectionPolicy`:
`enabled` (default) or `disabled`, which makes `__schema` and `__type` a
field error (`GQL338`); `__typename` always works. A test checks that
executing `IntrospectionQuery.full` gives exactly
`schema.toIntrospection(IntrospectionQuery.full)`. The production default
off comes with `ServerProfile` in M6.

## 10. Subscriptions (M5c; R4.13)

- `subscribe(document, {...})` returns
  `FutureOr<SubscriptionResult>`, sealed: `SubscriptionStarted(Stream<
  ExecutionResult> results)` or `SubscriptionRejected(RequestErrorResult
  error)` (request errors, and §6.2.3.1 source-stream errors: a resolver
  that throws or fails).
- Each source event is executed as §6.2.3.2 `MapSourceToResponseEvent`,
  one at a time and in order; an event's field errors are in its result.
- Cancelling the result subscription cancels the source subscription
  (unsubscribe). A source stream error emits a final result with the
  masked error (`GQL340`) and closes the stream (section 18); a source
  stream done closes it.
- `execute` on a subscription operation runs it as a query once over the
  `rootValue`, as graphql-js does.

## 11. Look-ahead (M5d; R4.18)

`info.selection` is a `FieldSelection`: a view of the plan nodes of the
current field with the request's variables; nothing is computed until a
member is read.

- `fields`: the `SelectedField`s in collection order (fragments
  flattened, `@skip` / `@include` applied, `__typename` hidden). For an
  abstract field type, the fields every possible type collects, merged by
  response key in possible-type order; `forType(name)` gives one object
  type's view.
- `has('posts.comments')`: a path of field names (not aliases).
- `fieldsNamed(name)`: every occurrence (aliases differ).
- `SelectedField`: `name`, `responseKey`, `alias`, `arguments`
  (`Arguments`, coerced on first read), `isDeferred`, `selection` (its own
  `FieldSelection`), `authorization` (section 12).
- `fingerprint`: a canonical string of the sub-selection (field names
  sorted, arguments printed in sorted key order, children nested), usable
  as a DataLoader key; built with an explicit stack.
- `ColumnAllowlist({fieldName: column}, {always})`:
  `columnsFor(selection)` gives the sorted, de-duplicated columns of the
  requested fields the map knows, plus `always`. No preload, no SQL.
- Typed handles (`has(user.posts)`): not in M5; the builder does not
  yield them at no extra cost (open question 6).

## 12. Authorization (M5d; R4.19)

- `Authorization` (sealed): `Authorization.public()` (no check, counted
  as covered) or `Authorization.requires(List<String> requirements)`. It
  is set on an object type (`ObjectOptions.authorization`, every field
  of the type) or on a field (`.withAuthorization(...)`, wins over the
  type).
- `Authorizer<C>.authorize(FieldAccess<C> access)` returns
  `FutureOr<AuthorizationDecision>` (`Allow` | `Deny(message?)`), called
  only for guarded fields, after argument coercion and before the
  middleware chain. `FieldAccess` holds the parent, the arguments, the
  context, the `FieldInfo` (and so the look-ahead) and the requirements.
  A deny is a field error (`GQL352`, default message `Not authorized to
  access Type.field.`); an authorizer exception is masked.
- `ExecutableSchema.authorizer` is set by `BuildOptions.authorizer`; a schema
  with guarded fields and no authorizer is a build error (`GQL304`).
- `AuthorizationCoverage(executableSchema).uncovered`: the coordinates
  (`Type.field`) of fields with no authorization on the field or its type,
  introspection excluded, sorted; meant for `expect(...uncovered,
  isEmpty)` in an application's tests. No policy engine.

## 13. Cancellation and timeout (M5d; R4.20)

- `CancelSignal` is a plain class owned by the caller: `CancelSignal()`,
  `cancel([Object? reason])`, `isCancelled`, `whenCancelled` (a
  `Future<void>`), `reason`; no platform import, no tie to a transport
  (section 17).
- `ExecutionOptions.cancelSignal` (one per request or subscription) and
  `timeout`. The executor links them into one internal signal, exposed as
  `info.cancelSignal`; the caller's signal is only listened to.
- Once cancelled, no new resolver starts, and `execute` completes promptly
  (it races the pending completion against the signal) with `data: null`
  and one error: `GQL350` "Execution was cancelled." or `GQL351`
  "Execution timed out after N ms." Results of resolvers that finish later
  are dropped. graphql-js rejects instead (section 18).
- A subscription ends on cancellation: a final error result, then the
  source subscription is cancelled and the stream closes.
- A sync-only execution with a timeout stays synchronous: the timer is
  cancelled before returning.

## 14. Benchmarks (M5d; R4.17)

`packages/typed_graphql_conformance/benchmark/execution_benchmark.dart`
(a `main`, run by hand, not in CI) measures throughput (operations per
second) and resident memory growth for: a synchronous query of 1 000
objects × 10 fields, the same with asynchronous resolvers, a nested query
with fragments, and the full introspection query. A smoke test runs each
scenario once in CI. The allocation guarantee that matters is tested in
the server suite: a sync-only query returns a non-`Future` value.

## 15. Diagnostics (GQL3xx)

Builder problems are `Diagnostic`s in a `SchemaBuildError`; execution
problems are `GraphQLError`s whose `extensions.code` is the id. All are
in `DiagnosticCode`, added in a core commit at the start of the
sub-stage that reports them (section 18):

| Id | Name | Sub-stage | When |
|---|---|---|---|
| GQL300 | `incompatibleImplementation` | M5a | an object's Dart type is not a subtype of an interface's Dart type it lists |
| GQL301 | `ambiguousTypeResolution` | M5a | possible types of an abstract type have overlapping Dart types and no `resolveType` / `isTypeOf` decides |
| GQL302 | `unencodableDefaultValue` | M5a | a default value cannot be written as a literal |
| GQL303 | `misplacedSubscriptionField` | M5c | a `subscribe` field outside the subscription root, or a root field without one |
| GQL304 | `missingAuthorizer` | M5d | guarded fields and no `authorizer` |
| GQL310 | `invalidVariableValue` | M5b | a variable value is invalid or a required one is missing |
| GQL311 | `invalidVariableDefault` | M5b | a variable's default cannot be coerced (custom scalar literal) |
| GQL312 | `tooManyVariableErrors` | M5b | `maxCoercionErrors` reached |
| GQL313 | `invalidArgumentValue` | M5b | an argument cannot be coerced at run time |
| GQL314 | `inputDecodeFailed` | M5b | an input object's `decode` threw something other than `GraphQLException` |
| GQL320 | `unknownOperation` | M5b | no operation with the requested name |
| GQL321 | `operationNameRequired` | M5b | several operations and no name |
| GQL322 | `noOperation` | M5b | the document has no operation |
| GQL323 | `unsupportedOperationType` | M5b | the schema has no root for the operation type |
| GQL324 | `subscriptionRequired` | M5c | `subscribe` called with a query or mutation |
| GQL330 | `unexpectedError` | M5b | a masked resolver, codec or decode error |
| GQL331 | `nullNonNullField` | M5b | null for a non-null field |
| GQL332 | `unserializableValue` | M5b | a leaf value cannot be serialized |
| GQL333 | `unresolvedAbstractType` | M5b | no possible type accepts the value |
| GQL334 | `impossibleRuntimeType` | M5b | `resolveType` gave a type that is not possible, or one whose Dart type does not hold the value |
| GQL335 | `unexpectedValue` | M5b | a value of the wrong Dart shape reached completion (e.g. a non-`Iterable` for a list) |
| GQL336 | `maxExecutionDepthExceeded` | M5b | `maxDepth` exceeded |
| GQL337 | `maxExecutionStepsExceeded` | M5b | `maxSteps` exceeded |
| GQL338 | `introspectionNotAllowed` | M5c | `__schema` or `__type` with `IntrospectionPolicy.disabled` |
| GQL340 | `subscriptionSourceFailed` | M5c | the source stream emitted an error |
| GQL350 | `executionCancelled` | M5d | the cancel signal fired |
| GQL351 | `executionTimedOut` | M5d | the timeout elapsed |
| GQL352 | `notAuthorized` | M5d | the `Authorizer` denied a field |

The tens are reserved per concern (300 build, 310 coercion, 320
operation selection, 330 completion, 340 subscriptions, 350 control).

## 16. Hostile input and limits (R0.3)

- Bad input never throws: an unknown operation, bad variables, a failing
  resolver, a value of the wrong shape, cancellation and every limit end
  as a `RequestErrorResult` or errors in an `ExecutionResult`.
  `ArgumentError` / `StateError` remain for programmer errors (another
  schema's `ValidDocument`, a wrong `rootValue`, reading an undeclared
  argument).
- No recursion over a document: field collection, the fingerprint and
  the introspection type walk use explicit stacks. Completion and coercion
  recurse along the response and the value, bounded by `maxDepth` (256)
  and 1000 levels; the parser bounds documents (128).
- Work: exponential fragment fan-out (`{ a: x { ...F } b: x { ...F } }`
  nested) multiplies response size, not plan size: collection is per
  (object type, field-node list) and memoised; execution is bounded by
  `maxSteps`. The validation `MaxCostRule` (M4) is the pipeline's guard
  (M6).
- Caches are bounded: `planCacheSize` plans, 16 condition keys per plan.
- Variables: at most `maxCoercionErrors` errors; a `JsonObject` of any
  size coerces in linear time.

## 17. Hosting inside other frameworks

The server is embedded by adapters that live outside this repository
(for example one for the sibling project dartnest; neither package
depends on the other). These constraints keep that possible:

1. **No resolver instantiation.** The builder never constructs resolver
   or service instances. Resolvers are closures; the objects they need
   come from the per-request context `C` (a service locator or a
   user-supplied factory reachable through `ctx`). The Schema Builder
   guide shows the pattern; no builder API takes a `Type` to instantiate.
2. **A plain cancellation signal.** `CancelSignal` (section 13) is created
   and cancelled by the caller, has no platform or transport dependency,
   and `execute` / `subscribe` take one per request or subscription.
3. **An error hook before masking.** `ExecutionOptions.onError`
   (section 7) sees the raw error, its stack trace and the error that
   would be recorded, and may return a replacement.
4. **Transport-agnostic.** `typed_graphql_server`'s `lib/src` imports no
   `dart:io`, `dart:html`, `dart:isolate`, `package:shelf` or other web
   framework; the folder test of section 2 enforces it, and `CLAUDE.md`
   states it as a rule of the package. Transports are M7's handlers over
   plain request and response data.
5. **The context contract.** In M5, `execute` and `subscribe` take the
   context value `context: C` and nothing else creates one. M6's pipeline
   adds the factory `FutureOr<C> Function(RequestInfo request)`, where
   `RequestInfo` holds the method, the URI, the headers and an optional
   `Object? source` (the host's own request object); M5 fixes nothing
   that would conflict with it.

## 18. Deviations from the architecture spec

1. `SchemaBuilder<C>` is `ExecutableSchemaBuilder<C>`: the core exports
   `SchemaBuilder`.
2. `args[first]` is `args.get(first)`: Dart operators cannot be generic.
3. `t.pure(name, type, getter)` / `t.field(name, type, resolver)` are
   `t.field(name, type).pure(getter)` / `.resolve(resolver)`: a one-call
   form infers `R` from the closure and lets a wrong result compile
   (section 3.2).
4. `b.list(x)` gives `OutputRef<Iterable<X>>`, not `List<X>`; input lists
   are `b.inputList(x)` and give `List<X>`.
5. `execute` returns `FutureOr<ResponsePayload>`: request errors are a
   `RequestErrorResult`, whose type says "no data".
6. `subscribe` returns `FutureOr<SubscriptionResult>`, not a bare
   `Stream`, so request errors are not a stream event.
7. Every library-made error has `extensions.code`; graphql-js has none.
   The conformance port helper drops it before comparing.
8. `@defer` / `@stream` run inline in `execute`; graphql-js 17's
   `execute` refuses them ("would unexpectedly produce multiple
   payloads"). `executeIncrementally` (M14) delivers them in parts.
9. Cancellation and timeout complete `execute` with an error result;
   graphql-js rejects the promise.
10. A source stream error ends a subscription with a final error result;
    graphql-js rethrows it to the consumer.
11. Builder methods take at most five parameters (the code rules), so
    some settings move to parameter objects, a second method or fluent
    stub modifiers (section 3.3, 3.4), and the type-level middleware slot
    is dropped: a global middleware filters by parent type at build time
    for free.
12. New codes are added to the core catalog in one core commit at the
    start of each sub-stage, not in the server commit that first reports
    each, so core and server commits stay apart (the task's rule); the
    catalog test still sees each code used by a test before the stage
    ends.
13. The executor waits for the resolvers that already started before it
    answers, so a late error of a branch that a sibling's null already
    discarded is still in the response; graphql-js answers first and drops
    it. Waiting keeps `onError` and the error log complete and never
    leaves work running behind a finished response
    (`executor_errors_test.dart`, `nonnull_multiple_test.dart`).
14. Operation request errors (`GQL320`-`GQL323`) carry no `locations`, and
    a `RequestErrorResult` has no `data: null`: the type says "no data"
    (`executor_operations_test.dart`).
15. A resolver reports an error by throwing or failing its future. A
    returned error value, a thrown value that is not an `Error` or
    `Exception` and an empty rejection are JavaScript-only: a Dart value
    is never an error, and anything thrown is masked like any other
    unexpected error (`executor_errors_test.dart`).
16. When two errors both reach the response they come in document order;
    graphql-js orders them by completion time, which a deterministic
    response must not depend on (`nonnull_multiple_test.dart`).
17. A typed list holds values, not futures or errors; a field may return
    a `Future` of the whole list. A list stops at its first failing or
    null item without draining the iterable, and an async iterable is not
    a list value (M14 brings streams of items)
    (`lists_nullability_test.dart`, `lists_test.dart`).
18. A `String` field takes a Dart `String`: there is no number-to-string
    serialization, because the builder fixes the result type at compile
    time (`lists_test.dart`).
19. An argument reports only its first problem, where graphql-js lists all
    of them (a field fails at its first bad argument); a variable
    reports every problem, up to `maxCoercionErrors`. The
    problems arrive as one variable or argument error each, with the path
    in the message, not as (message, path) pairs
    (`validate_input_value_test.dart`, `validate_input_literal_test.dart`).
20. A codec's failure message is reported as it is, without graphql-js's
    "Expected value of type X" wrapper, so a codec owns its message
    (`validate_input_value_test.dart`).
21. A custom scalar has no literal parser (R2.9): a literal is converted
    to JSON and decoded by the codec, and a Boolean variable used where a
    list is expected is refused, where graphql-js passes it through
    (`coerce_input_literal_test.dart`).
22. JSON has no `undefined` and no `NaN`: a missing value is a key left
    out, and a test that needs `NaN` uses another invalid value
    (`variables_lists_test.dart`, `coerce_input_value_test.dart`).
23. Fragment arguments (experimental in graphql-js) and
    `@experimental_disableErrorPropagation` are not supported; the second
    is `ErrorBehavior.nullValue` for the whole request. The tests are
    `skipped` in `mapping/execution.csv`
    (`error_propagation_test.dart`).
24. `resolveType` and `isTypeOf` are synchronous and take only the value
    (no context, info or promise), and `resolveType` returns a definition,
    never a name, so graphql-js's messages for an unknown or misspelled
    type name are unreachable. There is no default `__typename`-key
    resolution (`abstract_test.dart`).
25. Enum values are Dart enum values, with no internal values: the tests
    with a "bad" complex internal value or a string given for an enum
    cannot be written (`enum_type_test.dart`).
26. Introspection follows the September2025 edition, which lacks graphql-js
    17's working-draft parts: directive deprecation
    (`__Schema.directives(includeDeprecated:)`, `__Directive.isDeprecated`)
    and the `DIRECTIVE_DEFINITION` and `FRAGMENT_VARIABLE_DEFINITION`
    locations are not in the results (`introspection_test.dart`).
27. `@deprecated` on a directive definition is refused (`GQL118`), so the two
    graphql-js tests about deprecated directives are `skipped`
    (`introspection_deprecation_test.dart`).
28. An `Arg` has no explicit `null` default: a null default means "no
    default", so introspection says `defaultValue: null` where graphql-js
    says `'null'` (`introspection_test.dart`).
29. `@defer` and `@stream` in a subscription are ignored, not refused, until
    M14, so graphql-js's two "returns errors with @defer / @stream" tests are
    `skipped` (`subscribe_publish_test.dart`).
30. A subscription that cannot start is a `SubscriptionRejected` value, never
    a throw: a non-subscription operation is `GQL324` ("Expected
    subscription operation."), a root field that is skipped or undefined is
    `GQL322` ("The subscription selects no root field."), and these request
    errors carry no `locations` (`subscribe_initialization_test.dart`).
31. A source stream that errors only after it has been listened to cannot be
    seen at start: it becomes the final `GQL340` result of the stream, which
    then closes, where graphql-js rejects `next()` (item 10)
    (`subscribe_publish_test.dart`).
32. Events are executed one at a time and in order. The source subscription
    is paused while an event executes, and a source error or its end waits
    for the event in flight, also when the source delivers synchronously
    inside `listen` (`subscribe_publish_test.dart`,
    `subscription_flow_test.dart`). A single-subscription source then waits;
    a broadcast source keeps buffering inside its paused subscription
    without bound, so the application must bound it. An unexpected library
    error while executing an event ends the stream with a `GQL340` result. A
    response stream that is never listened to has already called the source
    function: listen to it or drop it promptly when the source registers
    eagerly.
33. `execute` needs a root value that the root type accepts, introspection
    queries included: a root typed `Object?` or `void` takes `null`, any
    other root takes a value of its Dart type. A guide shows how to declare a
    root that needs none (`introspection_test.dart`,
    `union_interface_test.dart`).
34. `CancelSignal.cancel(reason)` keeps the reason in `CancelSignal.reason`;
    the `GQL350` message is always "Execution was cancelled.", where
    graphql-js surfaces the abort reason's message
    (`cancellation_test.dart`).
35. `SelectedField.isDeferred` (section 11) is not in M5: no `@defer` is
    executed, so it would always be false. It arrives with incremental
    delivery.
36. `SelectedField.arguments` reads an argument whose value fails coercion
    as absent. Reading a required one then throws, which the resolver's
    error masking turns into `GQL330`; the executor reports the real
    coercion error when that field runs, so no problem is silent. Reading
    `arguments` in look-ahead runs the user `decode`; what it throws there is
    dropped, and `onError` sees it only when the field itself runs.
37. Look-ahead hides every meta field (a name starting with `__`), not only
    `__typename`.
38. The executor races the pending result against cancellation once, at the
    root, and checks `isCancelled` before it starts each field. A resolver
    already running is not interrupted; its result is dropped. A halt (for
    example `GQL337`) wins over a cancellation that arrives after it: the
    response carries the halt error, not `GQL350`.
39. Request errors win over an already-cancelled signal: an unknown
    operation or unusable variables are a `RequestErrorResult`, and no timer
    starts for them.
40. `GQL304` is one diagnostic that lists every guarded field as
    `Type.field`, not one diagnostic per field.
41. An object field that redeclares an interface field does not inherit the
    interface field's authorization rule: the rule guards the
    implementations that inherit the field.
42. A subscription's timeout timer and its listener on the caller's
    `CancelSignal` start at `subscribe`, not at `listen`. When the run's signal
    fires (the caller cancels or the timeout elapses) the cancellation
    releases both even if nobody listens to the response stream. A stream never
    listened to, with no cancel and no timeout, keeps its listener on the
    caller's signal until that signal is cancelled or collected; the guide
    says to listen to the stream or drop the signal.
43. Look-ahead walks spend the run's step counter (the one `maxSteps` limits).
    Collecting a selection and building a fingerprint (by the size of its
    text) charge it; a charge that would pass the limit spends nothing and
    throws a `GraphQLException` with `GQL337` and the executor's step message,
    which is the error of the field whose resolver read the selection, not a
    halt. Plan nodes are listed once per (field nodes, object type) and a
    fingerprint reads fields over the same nodes once, so a selection costs
    in proportion to the request unless its text itself fans out.
44. `SelectedField`s merge by response key, field name and printed arguments,
    not by response key alone (spec 11): object types that cannot overlap may
    give one alias to different fields, and `FieldsInSetCanMerge` allows it.
45. A subscription field's authorization guards the source only: the
    authorizer runs once, at subscribe, not for each event. Authorization is
    a per-request decision, as for a query; a per-event check would cost one
    call per event and turn a revoked permission into a stream of GQL352
    events. A server that must re-check per event does so in the event
    resolver. `execute` on a subscription never opens the source, so it
    authorizes the field itself: the guarded lane runs the guard.
46. Coerced arguments are frozen: the argument map, the map of each coerced
    input object and each coerced list are unmodifiable. A plan caches the
    arguments of a field without variables across requests, so a resolver
    writing to `Arguments.coerced` would change later requests; it gets an
    `UnsupportedError` instead.

## 19. Conformance (R0.7, R10.3)

`mapping/execution.csv` in the conformance package records each
graphql-js test of `src/execution/__tests__` and the execution-related
`type/__tests__` (`introspection-test.ts`, `enumType-test.ts`) and
`utilities/__tests__` (`coerceInputValue-test.ts`,
`validateInputValue-test.ts`) as `ported`, `adapted` or `skipped` with a
reason; `mapping_test.dart` checks the table covers every `it` of those
files. `test/support/execution_port.dart` builds the graphql-js test
schemas with the builder and compares results as JSON with the codes
dropped. JavaScript-only suites (`AbortedGraphQLExecutionError`,
`AsyncWorkTracker`, `cancellablePromise`, `collectIteratorPromises`,
`diagnostics-*`, `mapAsyncIterable`, `withConcurrentAbruptClose`, `hooks`,
`incremental`) are recorded as skipped with the reason. Tests of
JavaScript-only behaviour (default resolvers reading properties, `this`,
promise-like values, symbol keys) are skipped with the reason; tests whose
outcome differs by a deviation of section 18 are `adapted`.

## 20. Documentation (R11.1–R11.3)

- Guides in `packages/typed_graphql_server/doc/`: `schema_builder.md`
  (M5a), `execution.md` (M5b: coercion, plans, errors, masking,
  middleware), sections added to them in M5c (introspection,
  subscriptions) and M5d (look-ahead, authorization, cancellation);
  `dartdoc_options.yaml` ties them to the categories `builder`,
  `execution`, `introspection`, `subscription`, `lookahead`,
  `authorization`, `cancellation`.
- The server's documentation suite (`test/doc/`) reuses the core's
  `DocFiles`, `DocSnippets`, `SnippetRunner` by relative import, as the
  discovery suite does: snippets run and match their output, every
  exported type has its category, the README's first program is
  `example/example.dart` (from M5b).
- README: M5a changes the banner to say the builder works and execution
  does not yet; M5b removes "Not usable yet." and shows a working example;
  `llms.txt`, the root README's table, the core README's "You do not need
  it when" line and `docs/discovery.md` ("execute a GraphQL query dart"
  becomes yes; "GraphQL subscriptions server dart" in M5c) follow in the
  sub-stage that makes them true.

## 21. Open questions for the owner

Each has the recommendation this stage follows until the owner decides;
the list is also in `.superpowers/m5-open-questions.md`.

1. **Builder name.** `ExecutableSchemaBuilder<C>` (recommended; no clash
   with the core's `SchemaBuilder`) or `SchemaBuilder<C>` with a
   `hide` in every file that imports both packages.
2. **Two-step fields.** `t.field(name, type).pure(...)` (recommended;
   the only shape that makes a wrong result type a compile error without
   an extra parameter) or a one-call form with a typed `info` parameter.
3. **Enum value names.** `Enum.name` as is (recommended: no hidden
   renaming) or `SCREAMING_SNAKE_CASE` by default.
4. **Error codes in responses.** Always `extensions.code` on
   library-made errors (recommended: stable codes are R0.3's promise and
   clients can branch on them) or only when masking.
5. **`@defer` / `@stream` in `execute`.** Inline (recommended: clients
   that use them work today; the RFC lets a server not defer) or refuse
   as graphql-js 17 does.
6. **Typed look-ahead handles.** Not in M5 (recommended): `has(user.posts)`
   needs field handles the builder would have to keep and return, which
   is extra cost; string paths and generated selection classes (M8) cover
   it.
7. **Default `maxSteps`.** 10 000 000 completed values (recommended: far
   above a legitimate response, far below an exponential one) or off by
   default and set by `ServerProfile.production` in M6.
8. **Cancellation result.** An error result (recommended: R0.3, nothing
   throws for input; the pipeline maps it to a status) or a thrown
   `CancelledException` as graphql-js rejects.
9. **When codes are added.** In one core commit at the start of each
   sub-stage (recommended: core changes stay in their own commits) or in
   the server commit that first reports each, as `CLAUDE.md` says.

Found while building M5 (each is implemented as recommended):

10. **`GQL301` rule.** Reported for an abstract type without `resolveType`
    when two possible types have overlapping Dart types, unless both have
    an explicit `isTypeOf`; only the first such pair per abstract type
    (recommended) or a warning, or no report when either has `isTypeOf`
    (looser: declaration order then decides).
11. **`Arg.optional` and nullability.** `Arg.optional` keeps the ref's
    nullability, so `Arg.optional('x', b.string)` is a required `String!`
    and `Optional` only tells absent from present (recommended; the guides
    show `b.string.nullable`) or `Arg.optional` makes the ref nullable.
12. **`resolveType` / `isTypeOf` take only the value.** Synchronous and
    without the context (recommended: the type follows from the Dart
    value, usually a sealed `switch`) or `FutureOr<ObjectTypeDef>
    Function(P, C)`, a future per abstract value.
13. **Look-ahead and the step budget.** A look-ahead walk charges the
    run's `maxSteps` counter and a refused charge is a `GQL337` error of
    the reading field (recommended: one budget bounds all work of a run;
    section 18 item 43) or a separate look-ahead budget.
14. **The cancel reason.** `GQL350`'s message is always "Execution was
    cancelled." and the reason stays in `CancelSignal.reason`
    (recommended: a reason may hold internal detail; section 18 item 34)
    or the reason's text becomes the message, as graphql-js does.
15. **When a guarded subscription is authorized.** Once, at `subscribe`:
    the rule guards the source, not each event (recommended: one decision
    per request, as for a query, and no authorizer call per event; section
    18 item 45) or on every event, a deny becoming a `GQL352` error in that
    event's result while the stream goes on.
