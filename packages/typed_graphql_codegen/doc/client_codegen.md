# Client Code Generation

`typed_graphql_codegen` turns a GraphQL schema and the `.graphql` operations
of a Dart project into typed client code. It reads the configuration file,
loads the schema, parses and validates every document as one fragment graph,
and reports each problem as a diagnostic at `file:line:column`. It generates
the schema-types library (the enums and input objects the documents use,
with the scalars mapped to Dart types) and a library per document: the
classes of its operations, variables, data and fragments, the minified
document with its SHA-256, and the persisted-operations manifest. The
command line (`generate` and `check`) reads the project from disk, takes the
schema from a file or a URL and writes the generated files. Bad input never
throws: a problem is a diagnostic with a stable code, in a sealed result or a
list.

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
not expand `${NAME}`; the command line does (see "Command line").

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
  final declaration = RegExp(r'^(?:final|sealed) class (\w+)', multiLine: true);
  for (final file in generation.files) {
    final names = [
      for (final match in declaration.allMatches(file.text)) match[1],
    ];
    print('${file.path}: ${names.join(', ')}');
  }
}
```

It prints:

```text
lib/schema.graphql.dart: Role, RoleUnknown
role.graphql.dart: GetRoleQuery, GetRoleData
```

## Command line

The same engine runs from a terminal, in the folder of the project:

```text
dart run typed_graphql_codegen generate
dart run typed_graphql_codegen check
dart run typed_graphql_codegen generate --config path/to/typed_graphql.yaml
```

`--config` (`-c`) names the configuration file; it defaults to
`typed_graphql.yaml` in the working directory, and every path in it is
relative to the file's folder. `--help` prints the usage.

`generate` reads the configuration, the schema and the documents, runs the
checks and, when there is no error, writes each generated file whose text
differs from what is on disk (creating folders as needed). It prints
`Wrote N files.` or `Nothing to write.` and never deletes a file: a library
whose document you removed stays until you delete it, and neither `generate`
nor `check` looks at it, so `check` can be clean while a stale library is
still compiled. A file is written through a temporary file and a rename; a
file that cannot be written is a `GQL510` and the others are still written.
The `documents` globs do not follow symbolic links, and an invalid glob is a
`GQL501`. `check` writes nothing;
it reports a `GQL509` for each generated file that is missing or differs, and
prints `Up to date.` when none does, so a CI job can run it to catch generated
code that was not regenerated. Nothing is written when a document has an
error, and an error in one file blocks every file.

A diagnostic is printed to the error stream as
`path:line:column: severity GQLnnn: message`, followed by the excerpt of its
place; one without a place has no path. A file the command must read (the
configuration, the schema, a document) that cannot be read is a `GQL510`.

| Exit code | Meaning |
|---|---|
| `0` | Success; warnings such as `GQL506` do not change it. |
| `1` | At least one error: a problem in the project, a failed schema fetch, or (for `check`) an outdated file. |
| `64` | The command line itself is wrong: a missing or unknown command or option. The usage is printed. |

When `schema` is a URL, the command posts the full introspection query to it
(the response may be an introspection result or a GraphQL response around
one) and uses the result as the schema. A network failure, a timeout, a
redirect (not followed: the diagnostic names the URL to put in `schema`), a
body over 64 MiB, a non-success status or an unreadable body is a `GQL510`;
a body that is not an introspection result is a `GQL502`. A `${NAME}` in a
value of `headers` is replaced by the environment variable `NAME`; a
variable that is not set or is empty is a `GQL501`, and so is a value that
is not ASCII. The tool never prints a header value, and it hides them (and
the user information and query of the URL) in what it prints of the server's
answer, but a server can echo a value in a form it changed, so keep secrets
out of URLs. Everything printed is free of terminal control characters. The
command sends the headers also over plain `http`; use `https` for secrets.
Put secrets in `headers`, not in `typed_graphql.yaml`:

```text
schema: https://example.com/graphql
headers:
  Authorization: Bearer ${GRAPHQL_TOKEN}
```

The `example/` folder of the package is a small project with its generated
code checked in; `test/example_test.dart` generates it again and compares the
files byte for byte.

## Document libraries

Each document file gets a library at its own path plus `.dart`
(`lib/user.graphql` becomes `lib/user.graphql.dart`), in path order after the
schema-types library. A document without an operation or a fragment gets a
library with only the header. The library of a file holds the classes of the
operations and fragments defined in it, in document order, and imports only
what they use: the runtime, custom
scalar libraries, the schema types when a field is an enum or an input object,
and the library of another file when a selection spreads a fragment defined
there.
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

A selection on an interface or a union that spreads inline fragments or
fragments on other types generates a sealed class. `NodeCard` on `Node`
with `... on User` and `... on Bot` is a sealed `NodeCard` that reads the
`__typename`, `NodeCardUser` and `NodeCardBot`, and `NodeCardUnknown` for any
other type, which a server may add later. A `switch` over the sealed class is
exhaustive. The sealed class declares `typename` and every field that all
classes select in the same way, and `fragments` when they all spread the same
fragments; `NodeCardUnknown` keeps the `typename` it was read with. The golden
`test/goldens/polymorphic` is analyzed and run like the other goldens.

## Operations

Each document file gets a library at its own path plus `.dart` with the
classes of its operations and fragments, in document order. This program
generates the library of one document, a query with a variable and a
fragment, from a schema with a `User` that has a nullable `email`:

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
  user(id: ID!): User
}

type User {
  id: ID!
  name: String!
  email: String
}
'''),
    documents: const [
      ProjectFile('lib/user.graphql', '''
query GetUser(\$id: ID!) {
  user(id: \$id) {
    ...UserCard
    email
  }
}

fragment UserCard on User {
  id
  name
}
'''),
    ],
  );
  final declaration = RegExp(r'^(?:final|sealed) class (\w+)', multiLine: true);
  for (final file in generation.files) {
    if (file.path != 'lib/user.graphql.dart') continue;
    final names = [
      for (final match in declaration.allMatches(file.text)) match[1],
    ];
    print(names.join('\n'));
  }
}
```

It prints:

```text
GetUserQuery
GetUserVariables
GetUserData
GetUserDataUser
GetUserDataUserFragments
UserCard
```

The library starts with the header and the operation class, whose document is
what is sent; the full text of the library is:

```text
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by typed_graphql_codegen from lib/user.graphql.
// dart format off

import 'package:typed_graphql/typed_graphql.dart' as graphql;
import 'package:typed_graphql_client/typed_graphql_client.dart' as client;

/// The query `GetUser`.
final class GetUserQuery extends client.GraphQLQuery<GetUserData> {
  /// Creates the query with its [variables].
  const GetUserQuery(this.variables);

  /// The document of `GetUser` as it is sent.
  static const client.OperationDocument operationDocument =
      client.OperationDocument(
        name: 'GetUser',
        type: graphql.OperationType.query,
        text: r'query GetUser($id:ID!){user(id:$id){...UserCard email __typename}}fragment UserCard on User{id name}',
        sha256:
          '5fce2865ff25bb570a05850d6426f8ef67cb5f50f27cf6919cbfadf5f7566f36',
      );

  /// The variables the query is sent with.
  final GetUserVariables variables;

  @override
  client.OperationDocument get document => operationDocument;

  @override
  graphql.JsonObject get variablesJson => variables.toJson();

  @override
  graphql.DecodeResult<GetUserData> decodeData(graphql.JsonObject data) =>
      GetUserData.decode(data, variables: variablesJson);
}

/// The variables of the query `GetUser`.
final class GetUserVariables implements client.DataObject {
  /// Creates the variables.
  const GetUserVariables({required this.id});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The variable `$id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is GetUserVariables && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GetUserVariables(id: $id)';
}

/// The data of the query `GetUser`.
final class GetUserData implements client.DataObject {
  /// Creates the data.
  const GetUserData({this.user});

  factory GetUserData._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserData(user: _userCodec.field(json, 'user', context));

  /// Reads and writes the data.
  static const client.DataCodec<GetUserData> codec =
      client.ObjectDataCodec(GetUserData._read);

  static const client.DataCodec<GetUserDataUser?> _userCodec =
      client.NullableDataCodec(GetUserDataUser.codec);

  /// The field `user`.
  final GetUserDataUser? user;

  /// Reads [json], the `data` of a response to the query sent with
  /// [variables].
  static graphql.DecodeResult<GetUserData> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({'user': _userCodec.write(user)});

  @override
  bool operator ==(Object other) => other is GetUserData && other.user == user;

  @override
  int get hashCode => user.hashCode;

  @override
  String toString() => 'GetUserData(user: $user)';
}

/// The field `user` of [GetUserData].
final class GetUserDataUser implements client.DataObject {
  /// Creates the value.
  const GetUserDataUser({required this.fragments, this.email});

  factory GetUserDataUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUser(
    email: _emailCodec.field(json, 'email', context),
    fragments: GetUserDataUserFragments._read(json, context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUser> codec =
      client.ObjectDataCodec(GetUserDataUser._read);

  static const client.DataCodec<String?> _emailCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  /// The field `email`.
  final String? email;

  /// The fragments spread on this value.
  final GetUserDataUserFragments fragments;

  @override
  graphql.JsonObject toJson() => const client.JsonMerger().merge([
    fragments.toJson(),
    graphql.JsonObject({'email': _emailCodec.write(email)}),
  ]);

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUser &&
      other.email == email &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([email, fragments]);

  @override
  String toString() => 'GetUserDataUser(email: $email, fragments: $fragments)';
}

/// The fragments spread on [GetUserDataUser].
final class GetUserDataUserFragments implements client.DataObject {
  /// Creates the fragments.
  const GetUserDataUserFragments({required this.userCard});

  factory GetUserDataUserFragments._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUserFragments(userCard: UserCard.codec.read(json, context));

  /// The fragment `UserCard`.
  final UserCard userCard;

  @override
  graphql.JsonObject toJson() =>
      graphql.JsonObject({...userCard.toJson().fields});

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUserFragments && other.userCard == userCard;

  @override
  int get hashCode => userCard.hashCode;

  @override
  String toString() => 'GetUserDataUserFragments(userCard: $userCard)';
}

/// The fragment `UserCard` on `User`.
final class UserCard implements client.DataObject {
  /// Creates the fragment.
  const UserCard({required this.id, required this.name});

  factory UserCard._read(graphql.JsonObject json, client.DataContext context) =>
      UserCard(
        id: _idCodec.field(json, 'id', context),
        name: _nameCodec.field(json, 'name', context),
      );

  /// Reads and writes the fragment.
  static const client.DataCodec<UserCard> codec =
      client.ObjectDataCodec(UserCard._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The field `name`.
  final String name;

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<UserCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is UserCard && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'UserCard(id: $id, name: $name)';
}
```
The sections below describe the parts of that output.

### Names

An operation `GetUser` is four things, in this order in its file: the class
`GetUserQuery` (`GetUserMutation`, `GetUserSubscription`), the class
`GetUserVariables` when the operation has variables, the class `GetUserData`,
and the classes under the data. A fragment `UserCard` is the class `UserCard`.

| Class | Name |
|---|---|
| Operation | operation name and kind: `GetUserQuery` |
| Variables | `GetUserVariables` |
| Data | `GetUserData` |
| A composite field | the owner's name and the field's: `GetUserDataUser`, then `GetUserDataUserFriends` |
| Fragments holder | the owner's name and `Fragments`: `GetUserDataUserFragments` |
| A variant of an abstract selection | the base's name and the type's: `FindNodeDataNodeUser`; `FindNodeDataNodeUnknown` for any other type |

A GraphQL name is turned into a Dart one: classes in upper camel case
(`get_user` is `GetUser`), members in lower camel case. A name that Dart
reserves (`default`) or that the generated class already has (`toJson`,
`fragments`) gets a `$` suffix (`default$`); the JSON key stays as written.
GraphQL names cannot contain `$`, so the suffix never collides with another
name. When two names would still be one, the project is not generated (see
`GQL507` below).

### Fragments and masking

A fragment spread is not merged into the fields around it: the spread
fragment is a member of a `...Fragments` class that the value holds as
`fragments`. A component reads the fields of its own fragment and nothing
else (data masking, R7.4):

```text
final data = GetUserData.decode(json, variables: variables);
final card = data.user?.fragments.userCard; // a UserCard
final email = data.user?.email; // selected by the query itself
```

The fields of the fragment are not on `data.user`, so a change in the
fragment cannot break a reader that does not use it. `UserCard.decode` reads
a fragment on its own.

### Abstract types

A selection on an interface or a union that tells types apart is a sealed
class, as `FindNodeDataNode` in the golden `test/goldens/operations`: one
class per type the selection tells apart, and `…Unknown` for any other type,
which a server may add later. The sealed class declares `typename` and every
field that all its classes select in the same way, with the same type, and
`fragments` when they all spread the same fragments; a class that selects
more than that declares the rest. A `switch` over it is exhaustive:

```text
String describe(FindNodeDataNode node) => switch (node) {
  FindNodeDataNodeUser(:final name) => 'user $name',
  FindNodeDataNodeBot(:final model) => 'bot $model',
  FindNodeDataNodeUnknown(:final typename) => 'something else: $typename',
};
```

### `@include` and `@skip`

A field under `@include` or `@skip` is nullable, whatever its type in the
schema, and a fragment spread under them is a nullable member of the
`...Fragments` class. Which of them are present is decided when the data is
read, from the variables of the request: `GetUserQuery.decodeData` passes
them, and the defaults of the operation's `Boolean` variables fill those that
were not sent. `GetUserData.decode(json, variables: ...)` does the same for a
caller that has the JSON and the variables.

```text
/// The field `friends`; null when `@include` or `@skip` left it out.
final List<GetUserDataUserFriends>? friends;
```

### Variables

The variables class has a field per variable, like an input object without a
reader: a non-null variable without a default is `required`, any other is an
`Optional` that is absent unless given, and `toJson` writes only the present
values. An absent variable is not sent, so the server applies the
variable's default; `Optional.present(null)` sends an explicit `null`. An
operation without variables has a `const` constructor without arguments and
no variables class.

```text
const GetUserVariables({
  required this.id,
  required this.full,
  this.withFriends = const graphql.Optional.absent(),
});
```

`GetUserQuery(GetUserVariables(id: '1', full: true)).toRequest()` is the
request to send.

### The document text and the manifest

The `operationDocument` is the text as it is sent: the operation and every
fragment it spreads, transitively, sorted by name and minified. It adds
`__typename` to the selection set of every field that has one, so the client
can read the type of any object; fragment definitions and inline fragments
get none, because the field around them has it. The operation's own
selection set gets it only when a fragment that becomes a sealed class (a
fragment on an interface or a union with an inline fragment or spread on
other types inside) is spread at its top level, as that class needs to read
it; inline fragments at the root never need it. A `__typename` under
`@include` or `@skip` does not count: the unconditional one is added next to
it. A subscription cannot select `__typename` at its root, so a subscription
that spreads such a fragment at its top level (`GQL504`) cannot be generated. The `sha256` is
the SHA-256 of the text in UTF-8, in lowercase hexadecimal: the id of a
persisted query.

With `persisted_operations` set, `generate` also writes that file, last: a
JSON manifest in the format of Apollo's persisted-query manifest, with the
`id` (the `sha256`), `name`, `type` and `body` (the minified text) of every
operation, sorted by name, the same values the operation classes carry:

```text
{
  "format": "apollo-persisted-query-manifest",
  "version": 1,
  "operations": [
    {
      "id": "5b5057baca5f3def257f426d2cc1dae2068ddc332af9eea24882bb95be829e61",
      "name": "Everyone",
      "type": "query",
      "body": "query Everyone{node(id:\"1\"){id __typename}}"
    }
  ]
}
```

### Decoding

`GetUserData.decode(json, variables: ...)` reads the `data` of a response and
never throws: a value of the wrong shape, a missing required field or an
unreadable scalar is a `DecodeFailure` with a message and the path of the
value in the response. `toJson` writes the data back: the fields the value
holds, under their response names, with `__typename` where the selection
reads it, and `null` for a conditional field that was absent. A class and the
fragments it spreads may select the same field with different sub-fields;
`toJson` merges their JSON deeply (`JsonMerger` of the client), so each
side's sub-fields are written. `==` compares by value, lists by content.

A fragment's own `decode` has no operation around it: a Boolean variable that
`variables` lacks counts as false, not as its default in the operation (an
operation's `decode` passes its own defaults).

```text
switch (GetUserData.decode(json, variables: variables)) {
  case DecodeSuccess(:final value):
    print(value.user?.email);
  case DecodeFailure(:final message, :final path):
    print('$message at $path');
}
```

### Checked names

Before anything is written, every class and member the generator would
declare is checked: two classes with one name, two members of one class with
one Dart name and two files with one path are a `GQL507`, whatever declares
them.

The goldens `test/goldens/fragments`, `test/goldens/polymorphic` and
`test/goldens/operations` are regenerated, analyzed and run by the tests.

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
| `GQL501` | error | A configuration key is missing, unknown or mistyped, or a path, glob or Dart reference is malformed; or a schema URL header uses a `${NAME}` variable that is not set or is empty, or expands to a value that is not ASCII. |
| `GQL502` | error | The schema file is not JSON, or is JSON that is not an object, when it should be an introspection result. |
| `GQL503` | error | An operation has no name; the generated classes are named after the operation. |
| `GQL504` | error | A document uses `@defer` or `@stream`, or selects an introspection field (`__schema`, `__type`), which the generator does not support yet; or a subscription spreads, at its root, a fragment that becomes a sealed class (directly or through other fragments or inline fragments): the sealed class would need `__typename` there, and a subscription cannot select it. |
| `GQL505` | error | The configuration maps a scalar that the schema does not declare as a custom scalar: it is unknown, is not a scalar, or is built in. |
| `GQL506` | warning | No document matches `documents`. |
| `GQL507` | error | The generator would declare one Dart name twice, such as an enum `Role` and an input object `RoleKnown` (the enum also declares `RoleKnown` and `RoleUnknown`), a class of an operation and a fragment, two members of one class (such as the fields `user_name` and `userName`, or two fragments `UserCard` and `userCard`), or two files at one path. |
| `GQL508` | error | A name the generator would declare hides a Dart type the generated code uses, such as `List`, or a `dart:core` type a scalar is mapped to. |
| `GQL509` | error | `check` found a generated file that is missing or differs from what `generate` would write. |
| `GQL510` | error | The command line cannot read the configuration, the schema file or a document, cannot list the documents glob, cannot fetch the schema URL (a network failure, a timeout, a redirect, a body over 64 MiB, a non-success status or an unreadable body), or cannot write a generated file. |
| `GQL511` | error | An operation or fragment would generate more than 10000 classes, for instance a selection on an interface that reaches many types, repeated under many aliases. |

The problems of the schema and of the documents keep the codes of the core:
the schema's `GQL1xx` and the operation rules' `GQL2xx`.
