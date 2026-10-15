# Server

`GraphQLServer` serves GraphQL requests over an `ExecutableSchema`: it
parses and validates the document (cached), applies the limits and the
protections of its profile, builds the context and executes (R5.1). It
knows nothing of HTTP: a transport, or a host framework's adapter, decodes a
`ServerRequest` and writes the `ServerResponse` back. This guide covers the
request and the response, profiles and limits, the cost limit, CSRF
prevention, the document cache, extensions and errors.

## Serving a request

A server takes the schema and a context factory, which builds the context
of each request from its `RequestInfo`. The factory runs once per request,
after every check of the server has passed, so a refused request never
builds a context.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Viewer {
  const Viewer(this.name);

  final String name;
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Viewer>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('hello', b.string)
          .resolve((parent, args, context, info) => 'Hello, ${context.name}!'),
    ],
  );
  final server = GraphQLServer<Viewer>(
    schema: b.build(query: query),
    contextFactory: (request) => Viewer(request.header('x-user') ?? 'guest'),
  );
  final response = await server.handle(
    ServerRequest(
      params: const GraphQLRequest(query: '{ hello }'),
      info: RequestInfo(
        method: 'POST',
        uri: Uri.parse('http://localhost/graphql'),
        headers: {'Content-Type': 'application/json', 'X-User': 'Ada'},
      ),
    ),
  );
  switch (response) {
    case SingleResponse(:final outcome, :final body):
      print('${outcome.name} $body');
    case StreamResponse():
      print('a subscription stream');
  }
}
```

It prints:

```text
executed {"data":{"hello":"Hello, Ada!"}}
```

`handle` never throws: every refusal and every failure is a response.

## Requests and responses

- `RequestInfo` holds the method, the URI and the headers of a request, and
  `source`, the host's own request object, which the library never reads.
  Header names are lower-cased when it is made, and `header` finds one by
  any case. A transport joins repeated values with `, `.
- `ServerRequest` holds the `GraphQLRequest` (query, operation name,
  variables, extensions), the `RequestInfo` and an optional `CancelSignal`
  the caller owns, for example cancelled when the client disconnects.
- `ServerResponse` is sealed: a `SingleResponse` holds a `ResponsePayload`
  and its JSON `body`; a `StreamResponse` holds the results of a
  subscription. Both have an `outcome` and `headers`, a hint the transport
  adds to its own. `withHeaders` returns a copy with more headers.

`ServerOutcome` is the status-like part, which the HTTP transport (M7) maps
to a status code:

| Outcome | When |
|---|---|
| `executed` | the operation ran; `data` may be `null` after field errors |
| `requestError` | the request cannot run: no query, a syntax or validation error, a limit, CSRF, an unknown operation, bad variables, or a `GraphQLException` from the context factory or an extension |
| `methodNotAllowed` | a mutation in a `GET` request; the headers say `allow: POST` |
| `internalError` | an unexpected error of server code (the context factory, an extension), masked by the profile |

A `GET` request may run a query or a subscription, never a mutation:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final mutation = b.object<Object?>(
    'Mutation',
    fields: (t) => [t.field('bump', b.int).pure((_) => 1)],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query, mutation: mutation),
    contextFactory: (request) => null,
  );
  for (final (method, text) in [
    ('GET', '{ hello }'),
    ('GET', 'mutation { bump }'),
    ('POST', '{ hello'),
  ]) {
    final response = await server.handle(
      ServerRequest(
        params: GraphQLRequest(query: text),
        info: RequestInfo(
          method: method,
          uri: Uri.parse('http://localhost/graphql'),
          headers: {'graphql-require-preflight': '1'},
        ),
      ),
    );
    if (response case SingleResponse(:final outcome, :final body)) {
      print('$method ${outcome.name} ${response.headers}');
      print(body);
    }
  }
}
```

It prints:

```text
GET executed {}
{"data":{"hello":"world"}}
GET methodNotAllowed {allow: POST}
{"errors":[{"message":"A mutation can only be sent with the POST method.","extensions":{"code":"GQL402"}}]}
POST requestError {}
{"errors":[{"message":"Expected Name, found <EOF>.","locations":[{"line":1,"column":8}],"extensions":{"code":"GQL007"}}]}
```

## Profiles

A `ServerProfile` holds every protection. `GraphQLServer` uses
`ServerProfile.production` unless told otherwise, so a forgotten profile
does not expose a server; `ServerProfile.development` is chosen explicitly.

| Setting | `development` | `production` |
|---|---|---|
| `introspection` | `enabled` | `disabled` (`__schema` and `__type` are field errors, `__typename` works) |
| `includesSuggestions` | `true` | `false` (no "Did you mean" in messages) |
| `maskErrors` | `false` | `true` |
| `csrfPrevention` | `CsrfPrevention()` | `CsrfPrevention()` |
| `limits` | `ServerLimits.development` | `ServerLimits.production` |
| `timeout` | none | none |

Each setting has a `with*` method that returns a copy:
`withIntrospection`, `withSuggestions`, `withErrorMasking`,
`withCsrfPrevention` (null turns it off), `withLimits` and `withTimeout`
(queries and mutations only: a timeout would end a subscription).

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final schema = b.build(query: query);
  for (final profile in [
    ServerProfile.production,
    ServerProfile.production.withIntrospection(IntrospectionPolicy.enabled),
  ]) {
    final server = GraphQLServer<Object?>(
      schema: schema,
      contextFactory: (request) => null,
      profile: profile,
    );
    final response = await server.handle(
      ServerRequest(
        params: const GraphQLRequest(
          query: '{ __typename __schema { queryType { name } } }',
        ),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    if (response case SingleResponse(:final body)) print(body);
  }
}
```

It prints:

```text
{"errors":[{"message":"GraphQL introspection has been disabled, but the requested query contained the field \"__schema\".","locations":[{"line":1,"column":14}],"path":["__schema"],"extensions":{"code":"GQL338"}}],"data":null}
{"data":{"__typename":"Query","__schema":{"queryType":{"name":"Query"}}}}
```

A server that admits introspection for some callers only does so in an
`onExecute` hook with `withOptions` (see Extensions below).

## Limits and the cost limit

`ServerLimits` bounds the work a request can ask for; a null limit is off.
Every limit is checked before the context is built and before any resolver
runs.

| Limit | Applied by | `development` | `production` |
|---|---|---|---|
| `maxDocumentLength` | the server, before hashing (`GQL401`) | 100 000 | 100 000 |
| `maxTokens` | the parser (`GQL006`) | 15 000 | 15 000 |
| `maxDepth` | `MaxDepthRule` (`GQL232`) | none | 15 |
| `maxAliases` | `MaxAliasesRule` (`GQL233`) | none | 15 |
| `maxDirectives` | `MaxDirectivesRule` (`GQL234`) | none | 50 |
| `maxCost` | the cost limit (`GQL238`) | none | 10 000 |
| `defaultListSize` | the cost limit | 10 | 10 |

The depth, alias and directive rules join the server's `validationRules`
(by default `DocumentValidator.recommendedRules`; custom rules go there
too). The cost limit runs per request, after the operation is selected,
with the request's variables: a slicing argument such as `first: $n` is
counted with the value the client sent, which a validation rule cannot see
(see the Operation Validation guide of the core for how a cost is counted).
A list field the schema gives no size counts `defaultListSize` items.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Item {
  const Item(this.name);

  final String name;
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  // Late: the fields run on first use, after the assignment.
  late final ObjectTypeDef<Item> item;
  item = b.object<Item>(
    'Item',
    fields: (t) => [
      t.field('name', b.string).pure((item) => item.name),
      t.field('children', b.list(item)).pure((item) => const <Item>[]),
    ],
  );
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t.field('items', b.list(item)).pure((_) => const [Item('a')]),
    ],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => null,
  );
  for (final text in [
    '{ items { children { name } } }',
    '{ items { children { children { children { name } } } } }',
  ]) {
    final response = await server.handle(
      ServerRequest(
        params: GraphQLRequest(query: text),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    if (response case SingleResponse(:final body)) print(body);
  }
}
```

It prints:

```text
{"data":{"items":[{"children":[]}]}}
{"errors":[{"message":"The anonymous operation has a field cost of 1111 and a type cost of 11111, more than the maximum of 10000.","locations":[{"line":1,"column":1}],"extensions":{"code":"GQL238"}}]}
```

To change one limit, pass a whole `ServerLimits`:
`ServerProfile.production.withLimits(const ServerLimits(maxDepth: 10, maxCost: 50000))`
keeps the length and token defaults and turns the alias and directive
limits off.

## CSRF prevention

A browser sends a cross-site `GET`, or a `POST` with a "simple" content
type, without asking the server first, carrying the user's cookies.
`CsrfPrevention` (on in both profiles) refuses such a request (`GQL403`)
unless it shows it is not one: either its `content-type` is not
`application/x-www-form-urlencoded`, `multipart/form-data` or `text/plain`
(JSON passes), or it has a non-empty value for one of `requestHeaders`,
headers a browser only sends after a preflight. The defaults are
`graphql-require-preflight` and Apollo's `apollo-require-preflight` and
`x-apollo-operation-name`, so their clients pass. A `GET` request needs one
of the headers.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => null,
  );
  for (final headers in [
    {'content-type': 'text/plain'},
    {'content-type': 'text/plain', 'graphql-require-preflight': '1'},
    {'content-type': 'application/json; charset=utf-8'},
  ]) {
    final response = await server.handle(
      ServerRequest(
        params: const GraphQLRequest(query: '{ hello }'),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: headers,
        ),
      ),
    );
    if (response case SingleResponse(:final outcome)) print(outcome.name);
  }
}
```

It prints:

```text
requestError
executed
executed
```

`withCsrfPrevention(CsrfPrevention(requestHeaders: ['x-my-client']))`
replaces the header list; `withCsrfPrevention(null)` turns the check off,
for a server no browser can reach.

## The document cache

The server keeps the outcome of parsing and validating a text in an LRU
cache of `documentCacheSize` entries (1000 by default, 0 turns it off). The
key is the SHA-256 of the text, computed by the server, never a hash a
client sent. A rejected document is cached too, so a repeated bad request
costs a hash and a lookup. The same text gives the same `ValidDocument`
object, so the executor's plan cache hits as well. A text longer than
`maxDocumentLength` is refused before it is hashed, so every entry is
bounded.

## Extensions

A `ServerExtension` hooks into the three phases of a request. Each hook
receives the value of its phase and `next`; it may refuse by answering
without calling `next`, pass on a rewritten value, or look at what comes
back.

- `onRequest(ServerRequest, next)` wraps the whole request; CSRF
  prevention is inside it.
- `onDocument(DocumentRequest, next)` wraps resolving the text to a
  `ValidDocument`; `withText` replaces the text, and the result is
  `DocumentAccepted` or `DocumentRejected`.
- `onExecute(ExecutionRequest, next)` wraps the execution;
  `withContext` and `withOptions` replace the context and the
  `ExecutionOptions`.

The first extension in `extensions` is the outermost: it sees every
request, refused ones included. The built-in checks sit inside the user's
extensions in a fixed order (CSRF prevention, then persisted documents: see
the Persisted Documents guide), so no list order runs a step before a
security check, and a user's `onDocument` sees the text a hash names only
after it returns from `next`. Per-field interception is field middleware, set when the schema is
built (see the Execution guide).

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class RequireKey extends ServerExtension<Object?> {
  const RequireKey();

  @override
  Future<ServerResponse> onRequest(
    ServerRequest request,
    RequestHandler next,
  ) async {
    if (request.info.header('x-api-key') == 'secret') return next(request);
    return SingleResponse(
      RequestErrorResult(errors: [GraphQLError('An API key is required.')]),
      outcome: ServerOutcome.requestError,
    );
  }
}

final class OperationHeader extends ServerExtension<Object?> {
  const OperationHeader();

  @override
  Future<ServerResponse> onExecute(
    ExecutionRequest<Object?> request,
    ExecutionHandler<Object?> next,
  ) async {
    final response = await next(request);
    final type = request.operationType?.name ?? 'none';
    return response.withHeaders({'x-operation': type});
  }
}

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => null,
    extensions: const [RequireKey(), OperationHeader()],
  );
  for (final key in ['wrong', 'secret']) {
    final response = await server.handle(
      ServerRequest(
        params: const GraphQLRequest(query: '{ hello }'),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: {'content-type': 'application/json', 'x-api-key': key},
        ),
      ),
    );
    if (response case SingleResponse(:final body)) {
      print('${response.headers} $body');
    }
  }
}
```

It prints:

```text
{} {"errors":[{"message":"An API key is required."}]}
{x-operation: query} {"data":{"hello":"world"}}
```

## Errors and masking

A `GraphQLException` thrown by the context factory or an extension is a
`requestError` with its message and extensions, as a resolver's is a field
error. Any other error is unexpected: the server passes it to `onError`
(the executor's `ErrorHook`, which also sees every resolver's error, so a
host logs in one place) and answers `internalError` with `GQL330`, its
message masked as "Unexpected error." when the profile masks errors and the
error's `toString()` when it does not. A hook that throws gives the masked
error.

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

Future<void> main() async {
  final b = ExecutableSchemaBuilder<Object?>();
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
  );
  final server = GraphQLServer<Object?>(
    schema: b.build(query: query),
    contextFactory: (request) => switch (request.header('authorization')) {
      null => throw const GraphQLException('Sign in first.'),
      _ => throw StateError('the session store is down'),
    },
    onError: (error, stackTrace, reported) {
      print('logged: $error');
      return null;
    },
  );
  for (final headers in [
    {'content-type': 'application/json'},
    {'content-type': 'application/json', 'authorization': 'Bearer x'},
  ]) {
    final response = await server.handle(
      ServerRequest(
        params: const GraphQLRequest(query: '{ hello }'),
        info: RequestInfo(
          method: 'POST',
          uri: Uri.parse('http://localhost/graphql'),
          headers: headers,
        ),
      ),
    );
    if (response case SingleResponse(:final outcome, :final body)) {
      print('${outcome.name} $body');
    }
  }
}
```

It prints:

```text
requestError {"errors":[{"message":"Sign in first."}]}
logged: Bad state: the session store is down
internalError {"errors":[{"message":"Unexpected error.","extensions":{"code":"GQL330"}}]}
```

## Diagnostic codes

| Code | When |
|---|---|
| `GQL400` | the request has no document text: "Must provide query string." |
| `GQL401` | the text is longer than `maxDocumentLength` |
| `GQL402` | a mutation in a `GET` request |
| `GQL403` | CSRF prevention refused the request |
| `GQL238` | the operation costs more than `maxCost` with the request's variables |
| `GQL330` | an unexpected error of the context factory, an extension or a persisted query store |
| `GQL410`-`GQL415` | a persisted query or trusted document problem (Persisted Documents guide) |

The parser's `GQL0xx`, the validator's `GQL2xx` and the executor's `GQL3xx`
codes reach the client unchanged.
