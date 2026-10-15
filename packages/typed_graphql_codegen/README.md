# typed_graphql_codegen

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-codegen-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Generate typed Dart client code from a GraphQL schema and `.graphql` operations, from the command line or in code, with every problem reported at its file, line and column.** It reads `typed_graphql.yaml`, loads the schema from a file or a URL, validates the documents and writes the library of the enums and input objects the operations use and, per document, the classes of its operations, variables, data and fragments, with the minified document, its SHA-256 and the persisted-operations manifest. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** The client generator and its command line
> work; the classes need `typed_graphql_client`, which holds only the contract
> the generated code compiles against until M11. The SDL-first server
> generator (M8) and the `build_runner` builder (M9) are not built yet (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

Quick start. Write `typed_graphql.yaml` next to your `pubspec.yaml`:

```yaml
schema: schema.graphql
documents: lib/**.graphql
```

Then run it; `check` exits with 1 when a generated file is out of date:

```sh
dart run typed_graphql_codegen generate
dart run typed_graphql_codegen check
```

It does not depend on `analyzer`. The
[Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
lists the configuration keys, the command line and its exit codes, describes
the generated enums, input objects, scalars, operations and fragments, and
lists the codes `GQL500` to `GQL511`. The
[example](https://github.com/4akloon/graphql_dart/tree/main/packages/typed_graphql_codegen/example)
is a small project with its generated code checked in.

## License

MIT — see [LICENSE](LICENSE).
