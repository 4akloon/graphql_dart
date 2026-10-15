import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/input_object_emitter.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';

void main() {
  String emit(String sdl, String name) {
    final document = const Parser().parse(Source(sdl)).requireDocument();
    final schema =
        (const SchemaBuilder().fromSdl(document) as BuildSuccess).schema;
    final DartWriter writer = DartWriter();
    InputObjectEmitter(
      TypeMapper(schema, const {}),
    ).emit(schema.typeNamed(name)! as InputObjectType, writer, Imports());
    return writer.text;
  }

  test('a regular input object with every kind of field', () {
    expect(
      emit('''
enum Role { ADMIN }
input UserFilter {
  role: Role
  name: String = "x"
  limit: Int! = 10
  ids: [ID!]!
  tags: [String!]
  nested: UserFilter
}
''', 'UserFilter'),
      r'''
/// The input object `UserFilter`.
final class UserFilter implements client.DataObject {
  /// Creates the input object.
  const UserFilter({
    required this.ids,
    this.role = const graphql.Optional.absent(),
    this.name = const graphql.Optional.absent(),
    this.limit = const graphql.Optional.absent(),
    this.tags = const graphql.Optional.absent(),
    this.nested = const graphql.Optional.absent(),
  });

  factory UserFilter._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => UserFilter(
    role: _roleCodec.optionalField(json, 'role', context),
    name: _nameCodec.optionalField(json, 'name', context),
    limit: _limitCodec.optionalField(json, 'limit', context),
    ids: _idsCodec.field(json, 'ids', context),
    tags: _tagsCodec.optionalField(json, 'tags', context),
    nested: _nestedCodec.optionalField(json, 'nested', context),
  );

  /// Reads and writes the values of `UserFilter`.
  static const client.DataCodec<UserFilter> codec =
      client.ObjectDataCodec(UserFilter._read);

  static const client.DataCodec<Role?> _roleCodec =
      client.NullableDataCodec(Role.codec);

  static const client.DataCodec<String?> _nameCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<int> _limitCodec =
      client.ScalarDataCodec(graphql.IntCodec());

  static const client.DataCodec<List<String>> _idsCodec =
      client.ListDataCodec(client.ScalarDataCodec(graphql.IdCodec()));

  static const client.DataCodec<List<String>?> _tagsCodec =
      client.NullableDataCodec(
        client.ListDataCodec(client.ScalarDataCodec(graphql.StringCodec())),
      );

  static const client.DataCodec<UserFilter?> _nestedCodec =
      client.NullableDataCodec(UserFilter.codec);

  /// The field `role`.
  final graphql.Optional<Role?> role;

  /// The field `name`. Its default is `"x"`.
  final graphql.Optional<String?> name;

  /// The field `limit`. Its default is `10`.
  final graphql.Optional<int> limit;

  /// The field `ids`.
  final List<String> ids;

  /// The field `tags`.
  final graphql.Optional<List<String>?> tags;

  /// The field `nested`.
  final graphql.Optional<UserFilter?> nested;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (role case graphql.Present(:final value))
      'role': _roleCodec.write(value),
    if (name case graphql.Present(:final value))
      'name': _nameCodec.write(value),
    if (limit case graphql.Present(:final value))
      'limit': _limitCodec.write(value),
    'ids': _idsCodec.write(ids),
    if (tags case graphql.Present(:final value))
      'tags': _tagsCodec.write(value),
    if (nested case graphql.Present(:final value))
      'nested': _nestedCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is UserFilter &&
      other.role == role &&
      other.name == name &&
      other.limit == limit &&
      const client.DataEquality().equals(other.ids, ids) &&
      const client.DataEquality().equals(other.tags, tags) &&
      other.nested == nested;

  @override
  int get hashCode => Object.hashAll([
    role.hashCode,
    name.hashCode,
    limit.hashCode,
    const client.DataEquality().hash(ids),
    const client.DataEquality().hash(tags),
    nested.hashCode,
  ]);

  @override
  String toString() =>
      'UserFilter(role: $role, name: $name, limit: $limit, ids: $ids, '
      'tags: $tags, nested: $nested)';
}
''',
    );
  });

  test('a oneOf input object has a sealed class and a variant per field', () {
    expect(
      emit('''
input Leaf { a: Int }
input SearchBy @oneOf { name: String, id: ID, leaf: Leaf }
''', 'SearchBy'),
      r'''
/// The input object `SearchBy`: exactly one of its fields is given.
sealed class SearchBy implements client.DataObject {
  factory SearchBy._read(graphql.JsonObject json, client.DataContext context) =>
      switch (json.fields.keys.toList()) {
        ['name'] => SearchByName(_nameCodec.field(json, 'name', context)),
        ['id'] => SearchById(_idCodec.field(json, 'id', context)),
        ['leaf'] => SearchByLeaf(_leafCodec.field(json, 'leaf', context)),
        _ => throw const client.DataFormatException(
          'Expected exactly one of the fields name, id, leaf.',
        ),
      };

  /// Reads and writes the values of `SearchBy`.
  static const client.DataCodec<SearchBy> codec =
      client.ObjectDataCodec(SearchBy._read);

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<Leaf> _leafCodec = Leaf.codec;
}

/// [SearchBy] with its field `name`.
final class SearchByName implements SearchBy {
  /// Creates the input object with its field `name`.
  const SearchByName(this.name);

  /// The field `name`.
  final String name;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'name': SearchBy._nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) => other is SearchByName && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SearchByName($name)';
}

/// [SearchBy] with its field `id`.
final class SearchById implements SearchBy {
  /// Creates the input object with its field `id`.
  const SearchById(this.id);

  /// The field `id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': SearchBy._idCodec.write(id),
  });

  @override
  bool operator ==(Object other) => other is SearchById && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SearchById($id)';
}

/// [SearchBy] with its field `leaf`.
final class SearchByLeaf implements SearchBy {
  /// Creates the input object with its field `leaf`.
  const SearchByLeaf(this.leaf);

  /// The field `leaf`.
  final Leaf leaf;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'leaf': SearchBy._leafCodec.write(leaf),
  });

  @override
  bool operator ==(Object other) => other is SearchByLeaf && other.leaf == leaf;

  @override
  int get hashCode => leaf.hashCode;

  @override
  String toString() => 'SearchByLeaf($leaf)';
}
''',
    );
  });

  test('names that need a dollar and a field named other', () {
    expect(
      emit('''
input Odd {
  default: Int!
  _id: ID
  other: [Int!]
}
''', 'Odd'),
      r'''
/// The input object `Odd`.
final class Odd implements client.DataObject {
  /// Creates the input object.
  const Odd({
    required this.default$,
    this.$id = const graphql.Optional.absent(),
    this.other = const graphql.Optional.absent(),
  });

  factory Odd._read(graphql.JsonObject json, client.DataContext context) =>
      Odd(
        default$: _default$Codec.field(json, 'default', context),
        $id: _$idCodec.optionalField(json, '_id', context),
        other: _otherCodec.optionalField(json, 'other', context),
      );

  /// Reads and writes the values of `Odd`.
  static const client.DataCodec<Odd> codec = client.ObjectDataCodec(Odd._read);

  static const client.DataCodec<int> _default$Codec =
      client.ScalarDataCodec(graphql.IntCodec());

  static const client.DataCodec<String?> _$idCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.IdCodec()));

  static const client.DataCodec<List<int>?> _otherCodec =
      client.NullableDataCodec(
        client.ListDataCodec(client.ScalarDataCodec(graphql.IntCodec())),
      );

  /// The field `default`.
  final int default$;

  /// The field `_id`.
  final graphql.Optional<String?> $id;

  /// The field `other`.
  final graphql.Optional<List<int>?> other;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'default': _default$Codec.write(default$),
    if ($id case graphql.Present(:final value)) '_id': _$idCodec.write(value),
    if (other case graphql.Present(:final value))
      'other': _otherCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is Odd &&
      other.default$ == default$ &&
      other.$id == $id &&
      const client.DataEquality().equals(other.other, this.other);

  @override
  int get hashCode => Object.hashAll([
    default$.hashCode,
    $id.hashCode,
    const client.DataEquality().hash(other),
  ]);

  @override
  String toString() =>
      'Odd(default\$: ${default$}, \$id: ${$id}, other: $other)';
}
''',
    );
  });

  test('a deprecated field and a described type with a code fence', () {
    expect(
      emit('''
"""
Odd names.

```
code
```
"""
input Doc {
  "Field doc."
  old: String @deprecated(reason: "Use x.")
  plain: String @deprecated
}
''', 'Doc'),
      r'''
/// Odd names.
///
/// ```text
/// code
/// ```
final class Doc implements client.DataObject {
  /// Creates the input object.
  const Doc({
    this.old = const graphql.Optional.absent(),
    this.plain = const graphql.Optional.absent(),
  });

  factory Doc._read(graphql.JsonObject json, client.DataContext context) =>
      Doc(
        old: _oldCodec.optionalField(json, 'old', context),
        plain: _plainCodec.optionalField(json, 'plain', context),
      );

  /// Reads and writes the values of `Doc`.
  static const client.DataCodec<Doc> codec = client.ObjectDataCodec(Doc._read);

  static const client.DataCodec<String?> _oldCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  static const client.DataCodec<String?> _plainCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  /// Field doc.
  ///
  /// Deprecated: Use x.
  final graphql.Optional<String?> old;

  /// The field `plain`.
  ///
  /// Deprecated: No longer supported
  final graphql.Optional<String?> plain;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    if (old case graphql.Present(:final value)) 'old': _oldCodec.write(value),
    if (plain case graphql.Present(:final value))
      'plain': _plainCodec.write(value),
  });

  @override
  bool operator ==(Object other) =>
      other is Doc &&
      other.old == old &&
      other.plain == plain;

  @override
  int get hashCode => Object.hashAll([old.hashCode, plain.hashCode]);

  @override
  String toString() => 'Doc(old: $old, plain: $plain)';
}
''',
    );
  });
}
