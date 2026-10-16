# typed_graphql_shelf

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-adapter-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**The shelf adapter of typed_graphql_server: GraphQL over HTTP and WebSocket handlers for shelf, with an optional GraphiQL page in development.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** Stage M7 is complete: `GraphQLShelfHandler`
> is a shelf `Handler` that serves a `GraphQLServer` over HTTP (`GET` and
> `POST`, JSON and multipart uploads, batching, server-sent events) and, with
> `webSocket` set, over graphql-ws; `TempFileUploadStorage` keeps uploaded
> files in a private temporary directory; under `ServerProfile.development` a browser that
> opens the endpoint gets the GraphiQL page. See the
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
  typed_graphql_shelf:
    git:
      url: https://github.com/4akloon/graphql_dart
      path: packages/typed_graphql_shelf
```

## Should I use this?

- **Use it when** you serve GraphQL with `typed_graphql_server` from a shelf
  application and want HTTP, WebSocket and server-sent events from one
  handler.
- **You do not need it when** you use another web framework: the HTTP and
  graphql-ws handlers of `typed_graphql_server` take a small adapter, which
  this package is for shelf.
- **Know before you deploy**: the WebSocket frame limit is per frame; a
  message split into many frames is not bounded in total, so run it behind a
  proxy that caps the size of a message. Without `HttpOptions.onError` an
  unexpected error is a `500` that is not logged.
- **Which package**: this one next to
  [typed_graphql_server](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_server),
  which builds the schema and runs the requests.

## A quick tour

Build a `GraphQLServer`, wrap it in a `GraphQLShelfHandler` and give the
handler to `shelf_io.serve`; routing, CORS and logging stay with shelf. The
runnable program is [example/example.dart](example/example.dart); the guide
has one that posts a query and prints the answer.

```text
final handler = GraphQLShelfHandler<Object?>(
  server,
  webSocket: const GraphQLWsOptions(),
);
await shelf_io.serve(handler.call, InternetAddress.loopbackIPv4, 8080);
```

## Guides

- [shelf adapter](doc/shelf.md): the handler, a first program, WebSocket,
  uploads, GraphiQL and what the adapter decides.

## License

MIT — see [LICENSE](LICENSE).
