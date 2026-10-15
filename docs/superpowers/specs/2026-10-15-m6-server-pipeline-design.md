# M6 Server pipeline: stage design

Stage M6 of the [roadmap](../../roadmap.md): the request pipeline
`GraphQLServer`, the document cache, `ServerExtension`, limits and the cost
limit, automatic persisted queries, trusted documents, CSRF prevention,
`ServerProfile` and DataLoader (R4.15, R5.1–R5.4, R5.14, R5.15). It refines
section 5 (and the DataLoader bullet of section 4) of the architecture spec
(`2026-10-13-typed-graphql-design.md`) on top of M5's `ExecutableSchema`
(`2026-10-15-m5-execution-design.md`); every change to either is listed in
section 15, and every decision left to the owner in section 17.

## 1. Scope and delivery

M6 lives in `packages/typed_graphql_server`. The core changes only for the
diagnostic codes (section 13). The package stays transport-agnostic: it
imports no `dart:io`, no `dart:html`, no web framework (M5 spec §17); HTTP
framing, media types, status codes, WebSocket and SSE are M7's. M6 is split
into three sub-stages, each independently mergeable, each with its plan:

| Sub-stage | Delivers | Requirements | Plan |
|---|---|---|---|
| M6a | `BatchLoader`, `GroupedLoader`, `MissingValueException`; the DataLoader guide | R4.15 | `2026-10-15-m6a-dataloader.md` |
| M6b | `GraphQLServer`, `RequestInfo`, `ServerRequest`, `ServerResponse`, `ServerOutcome`, the document cache, `ServerExtension` and its phases, `ServerProfile`, `ServerLimits` (depth, aliases, directives, tokens, document length) and the cost limit, CSRF prevention, error masking and the error hook in the pipeline; `GQL400`-`GQL403`; the Server guide | R5.1–R5.4 (limits, introspection policy, masking, CSRF), R5.14, R5.15 | `2026-10-15-m6b-request-pipeline.md` |
| M6c | Automatic persisted queries (`PersistedQueryStore`, `MemoryPersistedQueryStore`), trusted documents (`TrustedDocuments`, read from M10's manifest); `GQL410`-`GQL415`; the Persisted Documents guide; the stage's last documents | R5.4 (APQ, trusted documents) | `2026-10-15-m6c-persisted-documents.md` |

Status (2026-10-15): M6a is done and M6b Tasks 1-10 are done on branch
`m6-final`. M6b Tasks 11-13 and all of M6c are planned: the controller wrote
and verified them in a scratch copy, and their plans carry the verified code
(section 18).

Out of scope: request batching (R5.12, LATER), response cache and tracing
(LATER), HTTP, uploads, graphql-ws and graphql-sse (M7), `@defer` and
`@stream` delivery (M14).

## 2. Layering

New folders in `packages/typed_graphql_server/lib/src/`, each a dartdoc
category with its guide:

| Folder | Holds | Category, guide | Sub-stage |
|---|---|---|---|
| `dataloader/` | `BatchLoader`, `GroupedLoader`, `MissingValueException`, the internal queue | `dataloader`, `doc/dataloader.md` | M6a |
| `server/` | `GraphQLServer`, the request and response values, `ServerExtension` and the phase values, `ServerProfile`, `ServerLimits`, `CsrfPrevention`, and the internal pipeline steps, document cache, hashing and error mapping | `server`, `doc/server.md` | M6b |
| `persisted/` | `PersistedQueryStore`, `MemoryPersistedQueryStore`, `TrustedDocuments`, the internal APQ and trusted-document steps | `persisted`, `doc/persisted_documents.md` | M6c |

`server/` and `persisted/` import each other (the server places the
persisted steps; they implement its extension API), as `builder/` and
`execution/` do in M5.

Dependencies: the server gains `crypto` (SHA-256 for the document cache,
APQ and trusted documents; pure Dart, runs on the VM, AOT, dart2js and
dart2wasm) and `lib/` may import `dart:convert` (UTF-8). The import rule
(`test/quality/import_rule.dart`) allows exactly these two besides M5's
set (section 15 item 15). `crypto` is pinned as the codegen pins it
(`^3.0.6`).

## 3. The request and the response (R5.1)

A transport, or a host framework's adapter, hands the pipeline a
transport-agnostic value and gets one back.

- `RequestInfo` (M5 spec §17.5): `method` (`String`, as the transport
  names it, `GET` and `POST` for HTTP), `uri` (`Uri`), `headers` (an
  unmodifiable map whose names are lower-cased at construction; a
  transport joins repeated values with `, `), `source` (`Object?`, the
  host's own request object, never read by the library). `header(name)`
  reads a header by any case.
- `ServerRequest`: `params` (the core's `GraphQLRequest`: query, operation
  name, variables, extensions; decoding the body is the transport's job),
  `info` (`RequestInfo`), `cancelSignal` (`CancelSignal?`, owned by the
  caller, for example cancelled when the client disconnects).
- `ServerResponse`, sealed, each with `outcome` and `headers` (a hint the
  transport adds to its own; lower-case names):
  - `SingleResponse(payload)`: a `ResponsePayload` (M5's `ExecutionResult`
    or `RequestErrorResult`); `body` is `payload.toJson()`.
  - `StreamResponse(results)`: a `Stream<ExecutionResult>`, for a
    subscription; a transport that cannot stream refuses it (M7).
  - `withHeaders(map)` returns a copy with the headers added.
- `ServerOutcome` (enum), the status-like part, which M7 maps to an HTTP
  status by media type:
  - `executed`: the operation ran; the result has `data` (maybe `null`
    after field errors, cancellation or a timeout).
  - `requestError`: the request is not executable: no query, a syntax or
    validation error, a limit, the cost limit, CSRF, a persisted query or
    trusted document problem, an operation that cannot be selected,
    variables that do not coerce, or a `GraphQLException` thrown by the
    context factory or an extension. No `data`.
  - `methodNotAllowed`: a mutation in a request whose method is not `POST`
    (section 6); headers
    hint `allow: POST`.
  - `internalError`: an unexpected error in the pipeline itself (the
    context factory, an extension, a store), masked by the profile.
- `ContextFactory<C>` = `FutureOr<C> Function(RequestInfo request)` (M5
  spec §17.5). It runs once per executed request, after the document is
  accepted and every limit has passed (section 6), so a refused request
  never builds a context.

`GraphQLServer<C>.handle(ServerRequest request)` returns
`Future<ServerResponse>` and never throws for anything a client sends
(R0.3): every refusal is a `SingleResponse` with `requestError` or
`methodNotAllowed`, every failure of server code an `internalError`. A
query and a mutation give a `SingleResponse`; a subscription a
`StreamResponse` (started) or a `SingleResponse` (rejected).

## 4. `GraphQLServer<C>` (R5.1)

```text
GraphQLServer<C>({
  required ExecutableSchema<C> schema,
  required ContextFactory<C> contextFactory,
  ServerProfile profile = ServerProfile.production,
  List<ServerExtension<C>> extensions = const [],
  List<ValidationRule> validationRules = DocumentValidator.recommendedRules,
  ErrorHook? onError,
  PersistedQueryStore? persistedQueries,   // M6c
  TrustedDocuments? trustedDocuments,      // M6c
  int documentCacheSize = 1000,
})
Future<ServerResponse> handle(ServerRequest request)
```

- `schema` is M5's built `ExecutableSchema`; the server never builds one
  and never instantiates resolvers or services (M5 spec §17.1).
- `validationRules` are the base rules (custom rules, R3.6, go here); the
  server appends the limit rules of `profile.limits` (section 8).
- `onError` is M5's `ErrorHook`: it is passed to every execution and also
  sees every unexpected error of the pipeline (context factory, extension,
  store) before masking, so a host logs once (M5 spec §17.3).
- `persistedQueries` and `trustedDocuments` together are an
  `ArgumentError` (section 11).
- A negative `documentCacheSize` is an `ArgumentError`; `0` disables the
  cache.

## 5. The document cache (R5.2)

- The text is hashed with SHA-256 (lower-case hex of its UTF-8 bytes) and
  the cache is an LRU keyed by that hash, holding `documentCacheSize`
  entries. A key is computed by the server from the text it parses, never
  taken from the client, so a client-sent hash cannot poison the cache.
- An entry holds the `Source` and the outcome of parsing and validating:
  a syntax failure, an invalid document (both as their errors) or a
  `ValidDocument`. Failures are cached too (they are deterministic for one
  server), so a repeated bad document costs one hash and a lookup.
- The same `ValidDocument` (and `Document`) object comes back for the same
  text, so M5's `PlanCache`, keyed by `Document` identity, hits across
  requests.
- Parsing and validation are synchronous, so compiling one text is
  single-flight by construction, as M5's plans are.
- Memory is bounded: entries are bounded by `documentCacheSize`, and a
  text longer than `ServerLimits.maxDocumentLength` is refused before it
  is hashed (section 8), so each entry is bounded too.
- The parser runs with `ParserOptions(maxTokens: limits.maxTokens)`; the
  validator with `rules` (section 4), `includesSuggestions` of the profile
  and its default step budget (`GQL230`).
- Diagnostics become `GraphQLError`s with the diagnostic's message, its
  `locations` (the place first, then related places, as the core's
  `Diagnostic.locations`) and `extensions.code` = the diagnostic's id.

## 6. The pipeline (R5.1, R5.3)

One request, in order; each refusal ends it with a `SingleResponse`:

1. **Request phase.** The `onRequest` hooks of the user's extensions,
   outermost first, then CSRF prevention (section 10). Inside them:
2. **Length.** A `query` longer than `limits.maxDocumentLength` is
   `GQL401`, before any hashing.
3. **Document phase.** The `onDocument` hooks of the user's extensions,
   then trusted documents or APQ (section 11), then the core step: no text
   is `GQL400` ("Must provide query string."); the length check again (a
   text from a store); the cache (section 5). A refusal is
   `DocumentRejected(errors)` and becomes `requestError`.
4. **Operation.** The operation is selected with the executor's own
   `OperationSelection` (September2025 6.1 `GetOperation`: the only
   operation when no name is given, else the last one with the name), so
   the checks below judge the operation that runs (section 15 item 22).
   When none can be selected the pipeline goes on and M5's `execute`
   reports `GQL320`-`GQL323`. A mutation when
   `RequestInfo.method` is not `POST` (compared ignoring case; an
   allow-list, so an unknown or empty method fails closed) is `GQL402`,
   `methodNotAllowed`, headers `allow: POST` (GraphQL over HTTP: a `GET`
   request must not run a mutation; only the pipeline knows the operation type, so M6 holds the
   rule, section 15 item 11). A subscription over `GET` is allowed (SSE).
5. **Cost.** With `limits.maxCost`, the selected operation's cost with the
   request's variables (section 9) above the maximum is `GQL238`.
6. **Context.** `contextFactory(request.info)`.
7. **Execution phase.** The `onExecute` hooks of the user's extensions,
   then the core step: `schema.execute` for a query or mutation,
   `schema.subscribe` for a subscription, with the `ExecutionOptions` of
   section 12. `ExecutionResult` → `executed`; `RequestErrorResult` →
   `requestError`; `SubscriptionStarted` → `StreamResponse` (`executed`);
   `SubscriptionRejected` → `requestError`.

Errors: a `GraphQLException` thrown by the context factory or an extension
becomes a `requestError` with its message and extensions, as a resolver's
does (M5 §7); any other error goes to `onError` and becomes `GQL330`
("Unexpected error.", masked) or, with `maskErrors` off, the error's
`toString()`, outcome `internalError`. A hook that throws inside `onError`
gives the masked error.

Every refusal before step 6 means no context was built and no resolver ran
("limits before work").

## 7. `ServerExtension` (R5.3)

```text
abstract class ServerExtension<C> {
  const ServerExtension();
  Future<ServerResponse> onRequest(ServerRequest request, RequestHandler next) => next(request);
  Future<DocumentResult> onDocument(DocumentRequest request, DocumentHandler next) => next(request);
  Future<ServerResponse> onExecute(ExecutionRequest<C> request, ExecutionHandler<C> next) => next(request);
}
typedef RequestHandler = Future<ServerResponse> Function(ServerRequest request);
typedef DocumentHandler = Future<DocumentResult> Function(DocumentRequest request);
typedef ExecutionHandler<C> = Future<ServerResponse> Function(ExecutionRequest<C> request);
```

- Three phases, each a `next`-chained hook with a default that calls
  `next`: the whole request, resolving the document (text to
  `ValidDocument`), and execution (with the context and the options).
  An extension may refuse (return without `next`), rewrite the value it
  passes on, or look at what comes back.
- `DocumentRequest`: `request` (the `ServerRequest`), `text` (`String?`,
  the document text so far, first `params.query`); `withText(text)`.
- `DocumentResult`, sealed: `DocumentAccepted(document, source, hash)`
  (`ValidDocument`, its `Source`, the SHA-256 the cache used) and
  `DocumentRejected(errors)`.
- `ExecutionRequest<C>`: `request`, `document` (`ValidDocument`),
  `operationType` (`OperationType?`, null when no operation could be
  selected), `context` (`C`), `options` (`ExecutionOptions`);
  `withContext(context)`, `withOptions(options)`.
- The chains are composed once, when the server is built (a fold over the
  list), so a request costs one closure call per extension per phase.
- The user's extensions are outermost, so their hooks see every request,
  refused ones included; the built-in steps (CSRF, trusted documents, APQ)
  are internal `ServerExtension`s that the server places inside them in a
  fixed order, so no list order can put an unchecked step before a
  security check (section 15 item 3).
- There is no field-level `resolve` hook: per-field interception is M5's
  field middleware (`BuildOptions.middleware`), composed when the schema
  is built (section 15 item 2).

## 8. `ServerProfile` and `ServerLimits` (R5.4, R5.15)

`ServerProfile` is one value holding every protection; two constants and
one `with*` method per protection (each method takes one parameter, the
code rules' limit, and returns a copy):

| Field | `development` | `production` | `with*` |
|---|---|---|---|
| `introspection` (`IntrospectionPolicy`) | `enabled` | `disabled` | `withIntrospection` |
| `includesSuggestions` | `true` | `false` | `withSuggestions` |
| `maskErrors` | `false` | `true` | `withErrorMasking` |
| `csrfPrevention` (`CsrfPrevention?`, null is off) | `CsrfPrevention()` | `CsrfPrevention()` | `withCsrfPrevention` |
| `limits` (`ServerLimits`) | `ServerLimits.development` | `ServerLimits.production` | `withLimits` |
| `timeout` (`Duration?`) | null | null | `withTimeout` |

`ServerLimits` (const; a null limit is off):

| Field | Applied by | `development` | `production` |
|---|---|---|---|
| `maxDocumentLength` (code units) | the pipeline, before hashing (`GQL401`) | 100 000 | 100 000 |
| `maxTokens` | `ParserOptions.maxTokens` | 15 000 | 15 000 |
| `maxDepth` | `MaxDepthRule` (`GQL232`) | null | 15 |
| `maxAliases` | `MaxAliasesRule` | null | 15 |
| `maxDirectives` | `MaxDirectivesRule` | null | 50 |
| `maxCost` (`double?`) | the cost step (section 9, `GQL238`) | null | 10 000 |
| `defaultListSize` | the cost step | 10 | 10 |

- `GraphQLServer` defaults to `production`: a forgotten profile must not
  expose a server (decisions log 2026-10-14). The development profile is
  chosen explicitly.
- The parser's own depth bound (`ParserOptions.maxDepth`, 128) and the
  executor's `maxDepth` and `maxSteps` keep their M2 and M5 defaults in
  both profiles; they bound the library, not the application.
- Introspection: `production` gives M5's `IntrospectionPolicy.disabled`
  (`__schema` and `__type` are `GQL338` field errors, `__typename` works).
  A server that admits introspection for some callers does so in an
  `onExecute` hook with `withOptions`.
- Batching off (R5.15): batching is not implemented (R5.12 is LATER), so
  both profiles answer one operation per request; a batch flag arrives
  with batching (section 15 item 7). GraphiQL (development) is M7's.

## 9. The cost limit (R5.14)

- With `limits.maxCost`, after the document is accepted and the operation
  selected, the pipeline computes `CostAnalysis(schema.schema,
  defaultListSize:).costOf(document, operation, variables:)` with the
  request's raw variables, and refuses an operation whose field cost or
  type cost is above `maxCost` with `GQL238` ("The operation \"Name\" has
  a field cost of A and a type cost of B, more than the maximum of C.", the
  wording of `MaxCostRule`; an anonymous operation is "The anonymous
  operation").
- A slicing value that names no size (an explicit null, which overrides the
  variable's default as in September2025 6.4.1; a non-number; a negative
  number; neither a value nor a default) sizes the field as if the argument
  were not given: the argument's default, then `assumedSize`, then
  `defaultListSize`. Zero is a size. A client cannot lower the cost by
  sending a value the executor would refuse or treat as absent (section 15
  item 21; M6b Task 11 changes the core's `ListSizes`).
- Per request, not in validation: `MaxCostRule` counts a slicing variable
  with its default or `defaultListSize`, so `users(first: $n)` with
  `n = 1000000` would pass it. The request's values are what the server
  will execute (section 15 item 8).
- `@cost` and `@listSize` count when the schema declares them (M4's
  `includesCostDirectives` or SDL); otherwise every weight is its default.
- Work: the walk is polynomial in the document (M4 spec), the document is
  bounded by `maxTokens` and `maxDocumentLength`, and a hostile-input test
  bounds its time.

## 10. CSRF prevention (R5.4, R5.15)

`const CsrfPrevention()` (headers `CsrfPrevention.defaultHeaders`) or
`CsrfPrevention.withHeaders(List<String>)`.
A request passes when either:

1. it has a `content-type` header whose media type (the part before `;`,
   trimmed, lower-cased, of the form `type/subtype` with token characters)
   is none of `application/x-www-form-urlencoded`, `multipart/form-data`,
   `text/plain` (the types a browser sends cross-site without a
   preflight); or
2. one of `requestHeaders` is present with a non-empty value (a custom
   header forces a preflight).

Otherwise it is `GQL403`, `requestError` ("This operation has been blocked
as a potential Cross-Site Request Forgery (CSRF). ..."). A missing or
unparsable `content-type` falls to rule 2. This is Apollo Server's and
GraphQL Yoga's rule. `defaultHeaders` are `graphql-require-preflight`,
`apollo-require-preflight` and `x-apollo-operation-name` (the last two so
Apollo clients pass). The rule reads `RequestInfo` only and applies to
every request, whatever the method; the M7 handlers describe their
requests (a WebSocket after its upgrade, for example) so that the rule
holds for them; the M7 spec decides how (section 16).

## 11. Persisted documents (M6c; R5.4)

Both read `extensions.persistedQuery` (`{"version": 1, "sha256Hash":
"<64 lower-case hex digits>"}`), Apollo's shape, which M10's manifest
(`apollo-persisted-query-manifest`, ids are the SHA-256 of the minified
body) and Apollo clients use.

**Automatic persisted queries** (`persistedQueries: PersistedQueryStore`):

- `PersistedQueryStore` (interface): `FutureOr<String?> read(String
  hash)`, `FutureOr<void> write(String hash, String text)`;
  `MemoryPersistedQueryStore({int capacity = 1000})` is an LRU.
- Hash and no text: read the store; a miss is `GQL410` with the message
  `PersistedQueryNotFound` (the text Apollo clients match to resend the
  full text, section 17 item 5); a hit continues with the stored text.
- Hash and text: the SHA-256 of the text must equal the hash, else
  `GQL411` and nothing is stored (no cache poisoning: a hash always names
  its own text). The text is written to the store only after the core
  step accepted it (it parses and validates), so a store holds only
  executable documents.
- A stored text is checked against `maxDocumentLength` and hashed again
  when read; a text that does not match its hash counts as missing
  (`GQL410`), so a shared store written by someone else cannot change what
  a hash runs. A store error is an unexpected error (`GQL330`).
- A malformed extension (not an object, version not `1`, a hash that is
  not 64 lower-case hex digits) is `GQL413`, with the message "Invalid
  persisted query: <reason>." A JSON `null` extension is no extension. An
  empty `query` with a hash is the hash alone (some clients send `""`).
- Without APQ and trusted documents, a hash with no text is `GQL412`
  (`PersistedQueryNotSupported`, the text Apollo clients match to stop
  sending hashes); with a text the extension is ignored.

**Trusted documents** (`trustedDocuments: TrustedDocuments`):

- `TrustedDocuments(Map<String, String> documents)` (id to text; an id
  that is not the SHA-256 of its text is an `ArgumentError`, a programmer
  error) and `static DecodeResult<TrustedDocuments> decode(JsonValue
  manifest)` for M10's manifest (format and version checked; only `id`
  and `body` of an entry are read; a bad entry or an id that does not match
  its body is a `DecodeFailure` with its path, such as
  `$.operations[0].id: expected the SHA-256 of the body`).
- Hash and no text: the trusted text, or `GQL415` (unknown id: "No
  trusted document has the id \"<hash>\"."; the hash is 64 hex digits, so
  echoing it is safe). No text and no hash goes on to the core step
  (`GQL400`).
- A text (with or without a hash): accepted only if its SHA-256 is a
  trusted id (and, with a hash, equal to it: `GQL411`); otherwise
  `GQL414` ("Only trusted documents are allowed."). Any other text is
  refused, whitespace changes included: nothing is guessed.
- A malformed extension is `GQL413`, as with APQ.
- APQ and trusted documents together are an `ArgumentError`: APQ would
  let a client register any text, which trusted documents forbid (section
  15 item 13).

## 12. Execution options (R5.15)

Per request the core execution step builds `ExecutionOptions(source:
<the cached Source>, maskErrors: profile.maskErrors, onError: onError,
includesSuggestions: profile.includesSuggestions, introspection:
profile.introspection, cancelSignal: request.cancelSignal, timeout:
profile.timeout for a query or mutation, none for a subscription)`; every
other field keeps M5's default. A subscription gets no timeout: a timeout
would end a long-lived stream (section 15 item 16). An `onExecute` hook may
replace the options.

## 13. DataLoader (M6a; R4.15)

```text
final class BatchLoader<K, V> {
  BatchLoader(FutureOr<Map<K, V>> Function(List<K> keys) load,
      {int? maxBatchSize, bool cachesValues = true});
  Future<V> load(K key);
  Future<List<V>> loadMany(Iterable<K> keys);
  void prime(K key, V value);
  void clear(K key);
  void clearAll();
}
final class GroupedLoader<K, V> {   // one-to-many
  GroupedLoader(FutureOr<Map<K, List<V>>> Function(List<K> keys) load,
      {int? maxBatchSize, bool cachesValues = true});
  Future<List<V>> load(K key);       // a missing key is []
  ... loadMany, prime, clear, clearAll as above
}
```

- **Dispatch.** The first `load` of a batch schedules its dispatch for when
  the microtask queue has drained (a zero-duration `Timer`), so the keys of
  every resolver of one level, including resolvers that `await` completed
  futures before they call `load`, go into one call. There is no
  executor-forced level flush (section 15 item 5).
- **De-duplication and cache.** A key asked twice in one batch is sent
  once. With `cachesValues` (default) a loaded or pending value is reused
  for the loader's lifetime; `prime` adds a value, `clear` and `clearAll`
  drop them (after a mutation). A failed batch is not cached: every key's
  future fails with the error, and the keys are loaded again on the next
  `load`. No future of the loader's own is left without a listener, so a
  failed batch never becomes an uncaught error.
- **Missing keys.** A key the batch function leaves out completes with
  `null` when `V` is nullable (`null is V`); otherwise its future fails
  with `MissingValueException(key)` (an `Exception`, masked like any
  resolver error).
- **`maxBatchSize`.** Keys are split into calls of at most that many, in
  order; a non-positive value is an `ArgumentError`.
- **Request scope.** A loader belongs to one request: the context factory
  creates the loaders in the context `C`, so their caches and batches never
  cross requests. The library holds no global loader state. A test runs
  two concurrent requests through `GraphQLServer` and checks that neither
  sees the other's keys or values.

## 14. Diagnostics and hostile input (R0.3)

New codes (`GQL4xx`, "transports and protocols"); tens per concern: 400
request checks, 410 persisted documents. Added in one core commit at the
start of the sub-stage that reports them (M5 spec §18 item 12):

| Id | Name | Sub-stage | When |
|---|---|---|---|
| GQL400 | `queryRequired` | M6b | no document text and no persisted id resolved one ("Must provide query string.") |
| GQL401 | `documentTooLong` | M6b | the text is longer than `maxDocumentLength` |
| GQL402 | `mutationRequiresPost` | M6b | a mutation in a request whose method is not `POST` |
| GQL403 | `csrfRequestBlocked` | M6b | CSRF prevention refused the request |
| GQL410 | `persistedQueryNotFound` | M6c | APQ: a hash the store does not hold |
| GQL411 | `persistedQueryHashMismatch` | M6c | the hash is not the SHA-256 of the text |
| GQL412 | `persistedQueryNotSupported` | M6c | a hash without text and no APQ or trusted documents |
| GQL413 | `invalidPersistedQuery` | M6c | a malformed `extensions.persistedQuery` |
| GQL414 | `untrustedDocument` | M6c | a text that is not a trusted document |
| GQL415 | `unknownTrustedDocument` | M6c | a hash that names no trusted document |

Reused: `GQL238` (the doc comment adds the pipeline's per-request cost),
`GQL330` (adds masked errors of the pipeline), the parser's `GQL0xx`, the
validator's `GQL2xx`, M5's `GQL3xx`.

Hostile-input tests (one file per concern under
`test/server/hostile_*_test.dart` and `test/persisted/hostile_*_test.dart`,
`test/dataloader/`):

- **Limits before work:** a deep, alias-heavy, directive-heavy, costly (by
  literal and by variable), too long or too many-token document is refused
  with no context built and no resolver called (counters in the test
  context factory and resolvers); the cost walk of a fragment fan-out
  document finishes within a time bound.
- **CSRF:** `GET` without headers, `POST` with each simple type, with
  parameters and odd case (`Text/Plain; charset=utf-8`), an unparsable
  type, an empty preflight header are refused; JSON or a non-empty
  preflight header pass.
- **APQ poisoning:** a hash with another text is refused and never stored;
  an invalid document is never stored; malformed extensions; uppercase or
  short hashes; the store stays bounded.
- **Trusted documents:** any text outside the set (a whitespace change
  included) is refused; an unknown id is refused; a manifest with a
  forged id is a `DecodeFailure`; APQ cannot be combined.
- **Masking:** in production a throwing context factory, extension or store
  is `GQL330` with `onError` seeing the raw error; in development the
  message is the error's text.
- **Document cache:** bounded; a failure is cached; the same `Document`
  object comes back (the plan cache hits).
- **DataLoader:** no cross-request leakage under concurrency; a failed
  batch is retried and leaves no uncaught error (`runZonedGuarded`).

## 15. Deviations from the architecture spec and M5

1. `GraphQLServer<C>(schema, extensions: [...], contextFactory: ...)` takes
   named parameters only (`schema:`, `contextFactory:`, `profile:`, ...),
   and `handle(ServerRequest)` is the one entry for queries, mutations and
   subscriptions.
2. `ServerExtension` has no `resolve` hook: the server receives a built
   `ExecutableSchema`, so per-field interception stays M5's build-time
   field middleware, which is the "folded only when overridden" design.
3. The built-in protections (CSRF, APQ, trusted documents, limits, the cost
   limit, introspection policy, masking) are settings of the profile and
   the server, placed in a fixed order, not entries of `extensions`; CSRF,
   APQ and trusted documents are internal `ServerExtension`s.
4. The document cache key is the SHA-256 of the text (R5.2 "by query
   hash"), computed by the server, never a client's hash.
5. DataLoader dispatches after the microtask queue drains instead of "a
   microtask plus a forced flush by the executor at level boundaries": the
   executor starts a level's fields in one synchronous pass or microtask
   burst, so a drained queue is the level boundary, and the executor stays
   free of loader knowledge.
6. `BatchLoader.load` returns `Future<V>`; a missing key is `null` only for
   a nullable `V`, else `MissingValueException`.
7. Batching is not built (R5.12 is LATER): "batching off" holds in both
   profiles and there is no batching flag until batching exists.
8. The cost limit runs per request with the request's variables
   (`CostAnalysis.costOf`), not as `MaxCostRule` in validation, which
   counts variables with their defaults.
9. CSRF prevention is an M6 pipeline step that reads `RequestInfo`, so a
   host that is not M7's transport gets it too; the roadmap's "applied at
   the transport" holds because M7's handlers go through the pipeline.
10. The context is created after the document is accepted and every limit
    passed, not when the request arrives.
11. The pipeline refuses a mutation unless the method is `POST` (a GraphQL over HTTP
    rule, M7's area): only the pipeline knows the operation type.
12. APQ errors carry `extensions.code` `GQL410`/`GQL412` like every library
    error and Apollo's messages (`PersistedQueryNotFound`,
    `PersistedQueryNotSupported`), not Apollo's `PERSISTED_QUERY_NOT_FOUND`
    code.
13. APQ and trusted documents cannot be combined (`ArgumentError`).
14. `GQL238` and `GQL330` are also reported by the pipeline (doc comments
    extended); no id changes meaning.
15. `typed_graphql_server` depends on `crypto` and imports `dart:convert`
    (M5 spec §2 allowed only `meta`).
16. `profile.timeout` applies to queries and mutations, not subscriptions.
17. `ServerProfile` is a final class with two constants and `with*`
    methods, not an enum: each protection is configurable on its own and
    the code rules allow no six-parameter `copyWith`.
18. Persisted ids come from `extensions.persistedQuery.sha256Hash`; the
    `documentId` parameter of the GraphQL over HTTP persisted-documents
    proposal is not read (`GraphQLRequest` has no such field).
19. `ServerLimits.maxDocumentLength` is a limit the architecture spec does
    not list (depth, cost, aliases, tokens): it bounds hashing, the cache
    and the stores before any parsing.
20. Production introspection is M5's `IntrospectionPolicy.disabled` (field
    errors), not `NoIntrospectionRule` (a validation refusal), so
    `__typename` keeps working and one cached validation serves both
    policies.
21. **The M4 cost semantics change** (core, `ListSizes`): a slicing value
    that names no size no longer counts as 0 or as its literal; it sizes
    the field as if the argument were absent (section 9). It is a breaking
    entry in the core changelog and changes `CostAnalysis` and
    `MaxCostRule` results for such documents.
22. The operation the pipeline checks is selected by M5's
    `OperationSelection` (the last operation with the name), not by its own
    lookup: with caller-supplied rules that drop `UniqueOperationNames`, a
    first-match lookup let a client name two operations alike so that the
    `GET` and cost checks judged one and the executor ran the other.
23. A `DocumentRejected` with no error (a bug in an extension) is reported
    as the masked `GQL330`, `internalError`: a request error must carry an
    error.
24. Extension hooks are trusted server code. A `DocumentAccepted` an
    `onDocument` hook builds runs without validation by the server, and an
    `onExecute` hook that rewrites the operation name or variables is not
    costed again (the `onExecute` doc says so). The cached rejection lists
    are unmodifiable, so a hook cannot change what later requests see.
25. `GraphQLServer.handle` catches `on Object` at the outermost boundary,
    as M5's executor does around a resolver, so an `Error` thrown by user
    code (the context factory, an extension, a store) still gives a
    response. CLAUDE.md says "never catch `Error`"; this boundary is the
    exception (section 17 item 13).
26. CSRF prevention trims a preflight header's value: a value of only
    whitespace does not pass (stricter than Apollo Server, which accepts
    any non-empty value).
27. The `ServerLimits` checks (positive limits, a non-negative
    `defaultListSize`) are `const` asserts, active only in debug builds,
    because the profile constants must be `const`. In a release build a
    negative `defaultListSize` reaches `CostAnalysis`, whose `RangeError` the
    pipeline reports as `GQL330` per request (section 17 item 15).
28. A stored APQ text is hashed again on read (section 11), at the cost of
    one SHA-256 per hash-only request, so the store is not a trust boundary.

## 16. Left for M7

- How the WebSocket and SSE handlers describe their requests to the CSRF
  rule (an upgrade request is a `GET` without a content type), and their
  own `Origin` checks.
- A transport that carries many operations over one connection (WebSocket,
  `graphql-ws`) has no HTTP method per message: it must pass `POST` in the `RequestInfo` of each message, or
  the mutation guard (section 6 step 4) refuses its mutations.
- Status codes per media type from `ServerOutcome`; body size limits;
  decoding `GET` parameters and JSON bodies into `GraphQLRequest`.
- GraphiQL in the development profile.

## 17. Open questions for the owner

Each has the recommendation this stage follows until the owner decides.

1. **Default profile.** `production` when the parameter is left out
   (recommended: secure by default, decisions log 2026-10-14) or a required
   parameter.
2. **Production limits.** Depth 15, aliases 15, directives 50, cost 10 000,
   tokens 15 000, document length 100 000 code units (recommended: generous
   for real clients, far below abuse) or other values.
3. **CSRF in development.** On (recommended: it only refuses requests a
   browser could forge; JSON clients and GraphiQL pass) or off.
4. **Masking in development.** Off (recommended: the developer sees the
   error) or on in both profiles.
5. **APQ error codes.** `GQL410`/`GQL412` with Apollo's messages
   (recommended: one code scheme; Apollo clients match the message) or
   Apollo's `PERSISTED_QUERY_NOT_FOUND` codes.
6. **DataLoader dispatch.** After the microtask queue drains, no executor
   flush (recommended: batches across `await`s, no coupling) or a microtask
   with an executor flush per level.
7. **Missing loader keys.** `null` for a nullable `V`, else
   `MissingValueException` (recommended: a non-null field gets a non-null
   future) or `Future<V?>` always.
8. **Cost limit timing.** Per request with variables (recommended) or
   `MaxCostRule` at validation (cached, but blind to variables).
9. **APQ with trusted documents.** An `ArgumentError` (recommended) or
   trusted documents silently win.
10. **CSRF header names.** `graphql-require-preflight` plus Apollo's two
    (recommended: Apollo clients pass) or only our own.
11. **A failing APQ store.** The request fails as `internalError`
    (recommended: nothing is silent) or the store is skipped.
12. **`documentId`.** Not read in M6 (recommended: decide with the M11
    client) or read now as an alias of the persisted hash.
13. **Catching `Error` at the boundary.** `handle` catches `on Object`
    (recommended: a server must answer whatever user code throws, as M5's
    executor does; amend CLAUDE.md to name the two boundaries) or lets an
    `Error` escape `handle`.
14. **Values that name no size.** Size the field as if the argument were
    absent (recommended and planned in M6b Task 11: a client cannot lower
    the cost) or refuse such a request at the cost step.
15. **Release-mode limit checks.** Keep the `const` asserts (recommended
    for now) and add a runtime `ArgumentError` for bad limits in the
    `GraphQLServer` factory in a follow-up, or leave them debug-only. Not
    planned in M6.
16. **Extension trust.** Hooks are trusted server code (recommended:
    documented; a hook that needs a check calls `next`) or the server
    re-validates a hook-built document and re-costs a rewritten request.
17. **APQ hashing on read.** Hash every stored text again (recommended: a
    shared store is not trusted) or trust the store.

## 18. Notes for the implementers

- **Order.** M6b Tasks 11, 12, 13, then M6c Tasks 1-6, in one worktree on
  `m6-final`. They share `pipeline_assembly.dart`, `graphql_server.dart`,
  `server_fixture.dart`, the changelogs and the stage documents, so they
  cannot run in parallel. Only M6c Task 2 (the store files) is independent
  of the M6b tasks, and it is too small to be worth a second worktree.
- **Provenance.** Every remaining task is one verified commit of the
  controller's scratch copy (made with `git archive` of `m6-final` at
  `62173b7`, outside the repository). The plans paste the full new files
  and the exact diffs, so a task applies to the tree the task before it
  leaves. A hunk that does not apply means the tree drifted: apply it with
  `git apply --3way` or stop and report.
- **Shared interfaces** (M6b, used unchanged by M6c): `PipelineAssembly`
  (where the built-in extensions are placed), `ExtensionChain`,
  `PipelineErrors.coded`, `DocumentHash`, `DocumentLength.violation`,
  `DocumentRequest.withText`, `DocumentAccepted`/`DocumentRejected`, and
  the test fixture `ServerFixture`.
- **Verification already done** in the scratch copy after the last task:
  format, analyze, the root suite (353), the core suite (1514), the server
  suite (1155) and the server's `dart doc` (0 warnings). Still to run: the
  `--compiler exe` suites and `pub publish --dry-run` (in the final review),
  and Chrome (left to CI).
- **After the tasks:** the final whole-branch review of `m6-final`, one fix
  round and a scoped re-review, then the owner's merge.
