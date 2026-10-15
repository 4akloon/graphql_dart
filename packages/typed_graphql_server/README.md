# typed_graphql_server

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-server-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** Stage M5 is complete. The typed schema
> builder (M5a), query execution (M5b), introspection and subscriptions (M5c),
> look-ahead, authorization and cancellation (M5d) work: you can declare a
> schema in typed Dart code, parse and validate a request with the core, and
> execute it, with variables, specified null propagation, error behaviours,
> masking and field middleware, answer introspection queries, run a
> subscription over a stream of events, read which fields a request selected
> under a field, guard fields with an authorizer and stop a request with a
> cancel signal or a timeout. DataLoader (M6a) works too: `BatchLoader` and
> `GroupedLoader` batch and cache the loads of one request. The request
> pipeline (M6b) works: `GraphQLServer` serves a transport-agnostic request
> with a document cache, the limits and the cost limit of a production or
> development profile, CSRF prevention, extensions and error masking.
> Persisted queries come later in M6, the HTTP, graphql-ws and graphql-sse
> handlers in M7. See the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).

## Contents

- [Install](#install)
- [Should I use this?](#should-i-use-this)
- [A quick tour](#a-quick-tour)
- [Guides](#guides)
- [License](#license)

## Install

Nothing is on pub.dev yet. To try it from the repository:

```yaml
dependencies:
  typed_graphql_server:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql_server
```

## Should I use this?

- **Use it when** you want to serve GraphQL from Dart and have the compiler
  check resolvers: a field's result type is fixed by its declaration, an
  argument is read with its type, and a bad request or a bad resolver result
  is a value in the response, not an exception
  ([Schema Builder](doc/schema_builder.md#objects-and-fields),
  [Execution](doc/execution.md#executing-a-request)).
- **You do not need it when** you only call a GraphQL server: that is the
  client package, not usable yet. Today it also has no HTTP or
  WebSocket handler: you decode the request yourself and call
  `GraphQLServer.handle` (the handlers are M7).
- **What it replaces**: resolvers written against `Map<String, dynamic>`, where
  a wrong result type or a misspelled argument name fails at run time in the
  middle of a request. Here the wrong type does not compile, and every error
  that does happen reaches the client as a coded `GraphQLError`
  ([errors and masking](doc/execution.md#field-errors-and-masking)).
- **Which package**: this one for the server side. It needs the core,
  [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql),
  to parse and validate documents.

## A quick tour

Declare the schema, then serve a request with `GraphQLServer`: it parses and
validates the document, applies the limits of its profile and executes. Every
resolver here is synchronous; a resolver may also return a `Future`. The same
program is in [example/example.dart](example/example.dart).

```dart
import 'dart:io';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

final class Book {
  const Book(this.title, this.pages);

  final String title;
  final int? pages;
}

Future<void> main() async {
  // Declare the schema in typed Dart: a wrong result type does not compile.
  final b = ExecutableSchemaBuilder<Object?>();
  final book = b.object<Book>(
    'Book',
    fields: (t) => [
      t.field('title', b.string).pure((book) => book.title),
      t.field('pages', b.int.nullable).pure((book) => book.pages),
    ],
  );
  final limit = Arg('limit', b.int, defaultValue: 10);
  final query = b.object<Object?>(
    'Query',
    fields: (t) => [
      t
          .field('books', b.list(book), args: [limit])
          .resolve(
            (parent, args, context, info) =>
                const [Book('Dune', 412), Book('Emma', null)].take(
                  args.get(limit),
                ),
          ),
    ],
  );
  final schema = b.build(query: query);

  // Serve it: the server parses and validates the document (cached),
  // applies the limits of its profile (production unless you pick one),
  // builds the context and executes. It knows nothing of HTTP.
  final server = GraphQLServer<Object?>(
    schema: schema,
    contextFactory: (request) => null,
  );
  final response = await server.handle(
    ServerRequest(
      params: const GraphQLRequest(
        query: '{ books(limit: 2) { title pages } }',
      ),
      info: RequestInfo(
        method: 'POST',
        uri: Uri.parse('http://localhost/graphql'),
        headers: {'content-type': 'application/json'},
      ),
    ),
  );

  // The response is a value: an outcome a transport maps to a status, and
  // a body that writes itself as JSON.
  if (response case SingleResponse(:final outcome, :final body)) {
    stdout.writeln(outcome.name);
    stdout.writeln(body);
  }
}
```

It prints:

```text
executed
{"data":{"books":[{"title":"Dune","pages":412},{"title":"Emma","pages":null}]}}
```

## Guides

- [Server](doc/server.md): `GraphQLServer`, requests, responses and outcomes,
  profiles, limits and the cost limit, CSRF prevention, the document cache,
  extensions, errors and masking.
- [Schema Builder](doc/schema_builder.md): refs, objects, fields, arguments,
  scalars, enums, input objects, interfaces and unions, building the schema.
- [Execution](doc/execution.md): executing a request, variables, request errors
  and field errors, error behaviours, masking and `onError`, middleware,
  abstract types, limits and the plan cache.
- [Introspection](doc/introspection.md): `__schema` and `__type`, the same
  answer as the core, `IntrospectionPolicy`, root types without a root value.
- [Subscriptions](doc/subscriptions.md): source streams, one event at a time,
  rejected and failed subscriptions.
- [DataLoader](doc/dataloader.md): batching and caching loads per request with
  `BatchLoader` and `GroupedLoader`, missing keys, `maxBatchSize`.
- [Look-ahead](doc/lookahead.md): the fields a request selected under a field,
  `fingerprint` as a DataLoader key, `ColumnAllowlist`.
- [Authorization](doc/authorization.md): rules on fields and types, the
  `Authorizer`, deny messages, `AuthorizationCoverage`.
- [Cancellation](doc/cancellation.md): `CancelSignal`, timeouts, what
  resolvers and subscriptions see.

## License

MIT — see [LICENSE](LICENSE).
