# typed_graphql_server

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-server-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**A fully typed GraphQL server for Dart: a typed schema builder, the execution engine, subscriptions, DataLoader and transport-agnostic HTTP, graphql-ws and graphql-sse handlers.** Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** The typed schema builder works (stage M5a):
> you can declare a schema in typed Dart code, build it, check it and print
> its SDL. Execution arrives in M5b, see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md).

**Not usable yet.** This package cannot execute a request yet; the part of typed_graphql that works today is the core package, [typed_graphql](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql), and the schema builder of this one.

Today: `ExecutableSchemaBuilder` declares scalars, enums, input objects, objects with typed fields and arguments, interfaces and unions, and `build` returns a validated `ExecutableSchema` or throws a `SchemaBuildError` with diagnostics. The [Schema Builder guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_server/doc/schema_builder.md) shows each step.

Planned: execution (M5b), introspection and subscriptions (M5c), look-ahead, authorization and cancellation (M5d), the `GraphQLServer` pipeline with APQ, trusted documents and DataLoader (M6), and the GraphQL over HTTP, graphql-ws and graphql-sse handlers (M7).

## License

MIT — see [LICENSE](LICENSE).
