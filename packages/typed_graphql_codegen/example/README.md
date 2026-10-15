# typed_graphql_codegen example

A small project whose generated code is checked in.

- `typed_graphql.yaml`: the configuration.
- `schema.graphql`: the schema.
- `lib/user.graphql`: the operation `GetUser`.
- `lib/schema.graphql.dart` and `lib/user.graphql.dart`: the generated code.

To regenerate the code after a change, run in this folder:

```sh
dart run typed_graphql_codegen generate
```

`dart run typed_graphql_codegen check` exits with 1 when a generated file is
out of date. The test `test/example_test.dart` of the package runs the
generator on these inputs and expects the checked-in files byte for byte.

This folder has its own `pubspec.yaml` (`publish_to: none`) and is a member
of the repository's pub workspace: the generated code imports
`typed_graphql` and `typed_graphql_client`, which the code generator itself
does not depend on, so the repository's `dart analyze` needs them here.
