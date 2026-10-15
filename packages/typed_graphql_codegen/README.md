# typed_graphql_codegen

![Dart](https://img.shields.io/badge/Dart-%5E3.13-0175C2?logo=dart&logoColor=white)
![Role](https://img.shields.io/badge/role-codegen-blue)
![Part of](https://img.shields.io/badge/part%20of-typed__graphql-purple)

**Check a GraphQL project for Dart client code generation: read `typed_graphql.yaml`, load the schema and validate the `.graphql` operations, with every problem reported at its file, line and column.** So far it generates the library of the enums and input objects the operations use; operation classes are not generated yet. Part of [typed_graphql](https://github.com/4akloon/graphql_dart).

> **Status: under construction.** This release reads the project's
> configuration, `typed_graphql.yaml` (`CodegenConfig`), and checks a project:
> `ClientGenerator.check` loads the schema, parses and validates the
> `.graphql` documents as one fragment graph, and reports every problem with
> its file, line and column. `ClientGenerator.generate` also writes the
> schema-types library; operation classes and the CLI arrive in M10 and the SDL-first server generator in M8 (see the
> [roadmap](https://github.com/4akloon/graphql_dart/blob/main/docs/roadmap.md)).

It does not depend on `analyzer`. The
[Client Code Generation guide](https://github.com/4akloon/graphql_dart/blob/main/packages/typed_graphql_codegen/doc/client_codegen.md)
lists the configuration keys, shows a check and a generation, describes the generated enums, input objects and scalars, and lists the codes `GQL500` to
`GQL508`.

## License

MIT — see [LICENSE](LICENSE).
