import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/data_class_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/plan/data_class_role.dart';
import 'package:typed_graphql_codegen/src/plan/planned_class.dart';

import '../support/class_emission.dart';

const _schema = '''
enum Role { ADMIN }
scalar DateTime
scalar Cursor
interface Node { id: ID! }
type User implements Node {
  id: ID!
  "The display name."
  name: String!
  role: Role!
  createdAt: DateTime
  cursor: Cursor
  friends(first: Int): [User!]!
}
type Query { user(id: ID!): User }
''';

void main() {
  final fragments = ClassEmission(_schema, r'''
query GetUser($withFriends: Boolean!, $full: Boolean!) {
  user(id: "1") {
    ...UserCard @include(if: $full)
    role
    createdAt
    cursor
    friends(first: 2) @include(if: $withFriends) {
      id
      name
    }
  }
}
fragment UserCard on User { id name }
''');

  test('a nested class of a list field', () {
    expect(fragments.emit('GetUserDataUserFriends'), r'''
/// The items of the field `friends` of [GetUserDataUser].
final class GetUserDataUserFriends implements client.DataObject {
  /// Creates the value.
  const GetUserDataUserFriends({required this.id, required this.name});

  factory GetUserDataUserFriends._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUserFriends(
    id: _idCodec.field(json, 'id', context),
    name: _nameCodec.field(json, 'name', context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUserFriends> codec =
      client.ObjectDataCodec(GetUserDataUserFriends._read);

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// The field `id`.
  final String id;

  /// The display name.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUserFriends && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hashAll([id, name]);

  @override
  String toString() => 'GetUserDataUserFriends(id: $id, name: $name)';
}
''');
  });

  test('a class with conditional fields and a fragment holder', () {
    expect(fragments.emit('GetUserDataUser'), r'''
/// The field `user` of [GetUserData].
final class GetUserDataUser implements client.DataObject {
  /// Creates the value.
  const GetUserDataUser({
    required this.role,
    required this.fragments,
    this.createdAt,
    this.cursor,
    this.friends,
  });

  factory GetUserDataUser._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => GetUserDataUser(
    role: _roleCodec.field(json, 'role', context),
    createdAt: _createdAtCodec.field(json, 'createdAt', context),
    cursor: _cursorCodec.field(json, 'cursor', context),
    friends: _friendsCodec.field(json, 'friends', context),
    fragments: GetUserDataUserFragments._read(json, context),
  );

  /// Reads and writes the value.
  static const client.DataCodec<GetUserDataUser> codec =
      client.ObjectDataCodec(GetUserDataUser._read);

  static const client.DataCodec<Role> _roleCodec = Role.codec;

  static const client.DataCodec<graphql.JsonValue?> _createdAtCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  static const client.DataCodec<graphql.JsonValue?> _cursorCodec =
      client.NullableDataCodec(client.JsonDataCodec());

  static const client.DataCodec<List<GetUserDataUserFriends>?> _friendsCodec =
      client.NullableDataCodec(
        client.ListDataCodec(GetUserDataUserFriends.codec),
      );

  /// The field `role`.
  final Role role;

  /// The field `createdAt`.
  final graphql.JsonValue? createdAt;

  /// The field `cursor`.
  final graphql.JsonValue? cursor;

  /// The field `friends`; null when `@include` or `@skip` left it out.
  final List<GetUserDataUserFriends>? friends;

  /// The fragments spread on this value.
  final GetUserDataUserFragments fragments;

  @override
  graphql.JsonObject toJson() => const client.JsonMerger().merge([
    fragments.toJson(),
    graphql.JsonObject({
      'role': _roleCodec.write(role),
      'createdAt': _createdAtCodec.write(createdAt),
      'cursor': _cursorCodec.write(cursor),
      'friends': _friendsCodec.write(friends),
    }),
  ]);

  @override
  bool operator ==(Object other) =>
      other is GetUserDataUser &&
      other.role == role &&
      other.createdAt == createdAt &&
      other.cursor == cursor &&
      const client.DataEquality().equals(other.friends, friends) &&
      other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([
    role,
    createdAt,
    cursor,
    const client.DataEquality().hash(friends),
    fragments,
  ]);

  @override
  String toString() =>
      'GetUserDataUser(role: $role, createdAt: $createdAt, cursor: $cursor, friends: $friends, fragments: $fragments)';
}
''');
  });

  test('a fragment class has decode', () {
    expect(fragments.emitFragment('UserCard', 'UserCard'), r'''
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

  /// The display name.
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
''');
  });

  test('a class without members', () {
    final writer = DartWriter();
    const plan = DataClassPlan(
      name: 'Empty',
      role: DataClassRole.nested,
      typeName: 'User',
      fields: [],
    );
    final mapper = TypeMapper(
      (const SchemaBuilder().fromSdl(
        const Parser().parse(Source(_schema)).requireDocument(),
      ) as BuildSuccess).schema,
      const {},
    );
    DataClassEmitter(mapper).emit(plan, 'Nothing.', writer, Imports());
    expect(writer.text, '''
/// Nothing.
final class Empty implements client.DataObject {
  /// Creates the value.
  const Empty();

  factory Empty._read(graphql.JsonObject json, client.DataContext context) =>
      const Empty();

  /// Reads and writes the value.
  static const client.DataCodec<Empty> codec =
      client.ObjectDataCodec(Empty._read);

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({});

  @override
  bool operator ==(Object other) => other is Empty;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Empty()';
}
''');
  });

  test('a class that is not a fragment or a field is a programmer error', () {
    const plan = DataClassPlan(
      name: 'GetData',
      role: DataClassRole.operationData,
      typeName: 'Query',
      fields: [],
    );
    expect(
      () => DataClassEmitter(
        TypeMapper(
          (const SchemaBuilder().fromSdl(
            const Parser().parse(Source(_schema)).requireDocument(),
          ) as BuildSuccess).schema,
          const {},
        ),
      ).emit(plan, 'Data.', DartWriter(), Imports()),
      throwsStateError,
    );
  });
}
