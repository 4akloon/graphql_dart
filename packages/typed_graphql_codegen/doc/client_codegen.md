# Client Code Generation

`typed_graphql_codegen` turns a GraphQL schema and the `.graphql` operations
of a Dart project into typed client code. This version checks a project and
generates the library of the schema's types: the enums and input objects the
documents use, with the scalars mapped to Dart types. It reads the
configuration file, loads the schema, parses and validates every document as
one fragment graph, and reports each problem as a diagnostic at
`file:line:column`; classes for operations and fragments arrive next. Bad
input never throws: a problem is a diagnostic with a stable code, in a sealed
result or a list.

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

## Generating

`ClientGenerator(config).generate` takes the same files as `check` and
returns a `GenerationResult`: the diagnostics of `check`, and the files to
write, each a `GeneratedFile` with a path and a text. A result with an error
has no files. The engine writes nothing itself; the caller (the command line
or a `build_runner` builder) puts the files on disk.

```dart
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

void main() {
  final result = CodegenConfig.parse(
    'schema: schema.graphql\n',
    path: 'typed_graphql.yaml',
  );
  if (result is! ConfigSuccess) {
    throw StateError('the configuration is valid');
  }
  final generation = ClientGenerator(result.config).generate(
    schema: const ProjectFile('schema.graphql', '''
type Query {
  role: Role
}

enum Role {
  ADMIN
  GUEST @deprecated(reason: "Use ADMIN.")
}
'''),
    documents: const [ProjectFile('role.graphql', 'query GetRole { role }')],
  );
  for (final file in generation.files) {
    print('// ${file.path}');
    print(file.text);
  }
}
```

It prints:

```text
// lib/schema.graphql.dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off

import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The enum `Role`.
sealed class Role implements client.DataEnum {
  /// The value named [raw]: a [RoleKnown], or a [RoleUnknown] for a name
  /// this code does not know.
  factory Role.parse(String raw) {
    for (final value in RoleKnown.values) {
      if (value.raw == raw) return value;
    }
    return RoleUnknown(raw);
  }

  /// Reads and writes the values of `Role`.
  static const client.DataCodec<Role> codec = client.EnumDataCodec(Role.parse);
}

/// The values of [Role] this code knows.
enum RoleKnown implements Role {
  /// `ADMIN`.
  admin('ADMIN'),

  /// `GUEST`.
  @Deprecated('Use ADMIN.')
  guest('GUEST');

  const RoleKnown(this.raw);

  @override
  final String raw;
}

/// A value of [Role] this code does not know, such as one added to the
/// schema after the code was generated.
final class RoleUnknown implements Role {
  /// Creates the value named [raw].
  const RoleUnknown(this.raw);

  @override
  final String raw;

  @override
  bool operator ==(Object other) => other is RoleUnknown && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'RoleUnknown($raw)';
}

// role.graphql.dart
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from role.graphql.
// dart format off
```

## Document libraries

Each document file gets a library at its own path plus `.dart`
(`lib/user.graphql` becomes `lib/user.graphql.dart`), in path order after the
schema-types library. A document without a fragment gets a library with only
the header. The library of a file holds the classes of the fragments defined
in it, in document order, and imports only what they use: the runtime, custom
scalar libraries, the schema types when a field is an enum or an input object,
and the library of another file when a fragment spreads one defined there.
Imports of generated libraries are relative and unprefixed, which is safe
because generated names are unique in the project.

A fragment `UserCard` is the class `UserCard`. Each composite field of its
selection is a class named after the field (`UserCardFriends`), and the
fragments spread on a selection are the members of a `...Fragments` class
that the value holds as `fragments`:

```text
final class UserCardFragments implements client.DataObject {
  const UserCardFragments({this.userName});

  /// The fragment `UserName`; null when `@include` or `@skip` left it out.
  final UserName? userName;
}
```

A spread under `@include` or `@skip` is nullable; the context of a read says
which variables are true. `UserCard.decode(json, variables: ...)` reads a
fragment on its own, and `toJson` writes it back; `==` compares lists by
content. The golden `test/goldens/fragments` is analyzed and run like the
other goldens.

## Schema types

The file at `schema_types` holds what the documents reach: the enums and
input objects they use, directly or through other input objects. The examples
below are excerpts of the golden files in the package's
`test/goldens/schema_types`, which the tests regenerate, analyze and run.

Every generated file starts with a header. `// dart format off` is part of
it: the text is not formatted by hand, and a project that runs
`dart format` must not rewrite generated files, or the next generation would
differ from what is on disk.

```text
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from schema.graphql.
// dart format off
```

### Enums

An enum is a `sealed class` with a parser, an `enum` of the values the code
knows (`XKnown`, with the Dart name in lower camel case and the GraphQL name
as `raw`) and a class for any other name (`XUnknown`). A server may add a
value after the code was generated; the client then reads it as `XUnknown`
instead of failing, and a `switch` over the sealed class must handle it. A
deprecated value is `@Deprecated`, and descriptions become doc comments.

```text
sealed class Role implements client.DataEnum {
  factory Role.parse(String raw) {
    for (final value in RoleKnown.values) {
      if (value.raw == raw) return value;
    }
    return RoleUnknown(raw);
  }
}

enum RoleKnown implements Role {
  admin('ADMIN'),
  editor('EDITOR'),
  @Deprecated('Use EDITOR.')
  viewer('VIEWER');
}
```

```text
String label(Role role) => switch (role) {
  RoleKnown.admin => 'Administrator',
  RoleKnown.editor || RoleKnown.viewer => 'Other',
  RoleUnknown(:final raw) => 'Unknown role $raw',
};
```

### Input objects

An input object is a `final class` with a `const` constructor, a `codec`, a
`toJson`, value equality and `toString`. The shape of a field follows its
type and default:

| Field | Dart | Constructor |
|---|---|---|
| `ids: [ID!]!` (non-null, no default) | `List<String>` | `required` |
| `role: Role` (nullable) | `Optional<Role?>` | absent unless given |
| `name: String = "x"` (nullable, with a default) | `Optional<String?>` | absent unless given; the doc comment shows the default |
| `limit: Int! = 10` (non-null, with a default) | `Optional<int>` | absent unless given |

A field that is not given is `Optional.absent()`, which is not the same as
`null`: `toJson` writes only the present values, so the server applies its
default to an absent field and sees an explicit `null` otherwise. A name that
Dart reserves (`default`) gets a `$` suffix (`default$`); the JSON key stays
`default`.

```text
final class UserFilter implements client.DataObject {
  const UserFilter({
    required this.ids,
    this.role = const graphql.Optional.absent(),
    this.name = const graphql.Optional.absent(),
  });

  final graphql.Optional<Role?> role;
  final List<String> ids;

  graphql.JsonObject toJson() => graphql.JsonObject({
    if (role case graphql.Present(:final value))
      'role': _roleCodec.write(value),
    'ids': _idsCodec.write(ids),
  });
}
```

### `@oneOf` input objects

An input object with `@oneOf` is a `sealed class` with one `final class`
variant per field, `SearchByName` for the field `name`; the type system then
allows exactly one field, as the specification does. Reading a value with
none or several fields is a `DataFormatException`.

```text
sealed class SearchBy implements client.DataObject { ... }

final class SearchByName implements SearchBy {
  const SearchByName(this.name);
  final String name;
}

final class SearchById implements SearchBy {
  const SearchById(this.id);
  final String id;
}
```

### Scalars

The built-in scalars have a fixed mapping:

| Scalar | Dart type | Codec |
|---|---|---|
| `Int` | `int` | `IntCodec` |
| `Float` | `double` | `FloatCodec` |
| `String` | `String` | `StringCodec` |
| `Boolean` | `bool` | `BooleanCodec` |
| `ID` | `String` | `IdCodec` |

A custom scalar listed under `scalars:` in `typed_graphql.yaml` uses its
`type` and its `codec`; the generated file imports the codec's library with a
prefix. A custom scalar without a mapping is a `JsonValue`: the generator
guesses nothing, and the value stays as the server sent it.

```text
scalars:
  DateTime:
    type: DateTime
    codec: package:scalar_codecs/scalar_codecs.dart#DateTimeCodec
```

```text
final graphql.Optional<DateTime?> since;
final graphql.Optional<graphql.JsonValue?> after;
```

### Pruning

Only what the documents reach is generated. In the golden schema, the enum
`Unused` and the input object `Unreached` are not used by any operation, so
they have no class; `Role`, `UserFilter` (and `UserFilter`'s own field types),
`SearchBy` and `Paging` are. A project with no document gets an empty
library, and a schema is free to be large.

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
