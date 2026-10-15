# Client Code Generation

`typed_graphql_codegen` turns a GraphQL schema and the `.graphql` operations
of a Dart project into typed client code. This version checks a project: it
reads the configuration file, loads the schema, parses and validates every
document as one fragment graph, and reports each problem as a diagnostic at
`file:line:column`. It does not write code yet; generation arrives with the
next part of the stage. Bad input never throws: a problem is a diagnostic
with a stable code, in a sealed result or a list.

## Configuration

The project is described by `typed_graphql.yaml`, read by
`CodegenConfig.parse`. Every path is relative to the file's folder and uses
`/` as separator. A key that is not listed, a mistyped value or a malformed
path is a `GQL501`; text that is not YAML is a `GQL500`.

| Key | Default | Meaning |
|---|---|---|
| `schema` | required | The schema: a file (SDL, or an introspection result when the path ends with `.json`) or an `http` or `https` URL. |
| `documents` | `lib/**.graphql` | A glob or a list of globs of the operation documents. |
| `schema_types` | `lib/schema.graphql.dart` | The generated file of the schema's types; the path ends with `.dart`. |
| `persisted_operations` | none | The persisted operations manifest; the path ends with `.json`. Nothing is written when it is missing. |
| `scalars` | none | The custom scalars: each name maps to a `type` and a `codec`. |
| `headers` | none | The HTTP headers of the introspection request. Allowed only when `schema` is a URL. |

A custom scalar is mapped to the Dart type of its values and to the codec
that reads and writes it, a class with a `const` constructor that implements
`ScalarCodec` of that type. Both are written as `<library>#<Name>`, such as
`package:my_app/codecs.dart#MomentCodec`. The `type` of a `dart:core` type
may be its bare name, such as `DateTime`; a `codec` always names its
library. The scalars and the headers are kept sorted by name.

```text
schema: https://example.com/graphql
documents:
  - lib/**.graphql
  - test/**.graphql
schema_types: lib/schema.graphql.dart
persisted_operations: lib/operations.json
scalars:
  Moment:
    type: DateTime
    codec: package:my_app/codecs.dart#MomentCodec
headers:
  Authorization: Bearer token
```

The values of `headers` are kept as written: the configuration reader does
not expand `${NAME}`.

## Checking a project

`CodegenConfig.parse` returns a `ConfigSuccess` or a `ConfigFailure` with the
problems. `ClientGenerator(config).check` takes the schema file and the
document files, each a `ProjectFile` with its path and text, and returns
every diagnostic in report order. The files are given, not read, so the
engine itself touches no file system.

The documents are validated with the specified rules, except that a fragment
nobody spreads is not an error; every operation must be named (`GQL503`). The
fragments of all the files form one graph, so a document may spread a
fragment that another file declares:

```dart
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  final result = CodegenConfig.parse('''
schema: schema.graphql
documents: queries/**.graphql
scalars:
  Moment:
    type: DateTime
    codec: package:my_app/codecs.dart#MomentCodec
''', path: 'typed_graphql.yaml');
  if (result is! ConfigSuccess) {
    throw StateError('the configuration is valid');
  }
  final diagnostics = ClientGenerator(result.config).check(
    schema: const ProjectFile('schema.graphql', '''
type Query {
  user: User
}

type User {
  name: String
  joined: Moment
}

scalar Moment
'''),
    documents: const [
      ProjectFile('queries/user.graphql', 'query User { user { ...Name } }'),
      ProjectFile('queries/name.graphql', 'fragment Name on User { nam }'),
    ],
  );
  for (final diagnostic in diagnostics) {
    print(diagnostic);
  }
}
```

It prints:

```text
queries/name.graphql:1:25: error GQL205: Cannot query field "nam" on type "User". Did you mean "name"?
```

A project with no error is ready to generate; a warning does not stop it.

## Diagnostics

The codes of the code generator are the range `GQL5xx`. Ids are public API
and are never reused.

| Code | Severity | Reported when |
|---|---|---|
| `GQL500` | error | `typed_graphql.yaml` is not valid YAML. |
| `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path or Dart reference is malformed. |
| `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
| `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
| `GQL504` | error | A document uses `@defer` or `@stream`, which the generator does not support yet. |
| `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
| `GQL506` | warning | No document matches `documents`. |
| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`). |
| `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |

The problems of the schema and of the documents keep the codes of the core:
the schema's `GQL1xx` and the operation rules' `GQL2xx`.
