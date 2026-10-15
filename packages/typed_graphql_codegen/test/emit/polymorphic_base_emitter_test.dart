import 'package:test/test.dart';

import '../support/class_emission.dart';

const _schema = '''
interface Node { id: ID! }
type User implements Node { id: ID! name: String! owner: User friends(first: Int): [User!]! }
type Bot implements Node { id: ID! model: String }
type Query { node(id: ID!): Node }
''';

void main() {
  test('the sealed base of a fragment on an interface', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...NodeCard } }
fragment NodeCard on Node { id ... on User { name } ... on Bot { model } }
''');
    expect(emission.emitFragment('NodeCard', 'NodeCard'), '''
/// The fragment `NodeCard` on `Node`: a class per type the selection tells
/// apart, and [NodeCardUnknown] for any other type.
sealed class NodeCard implements client.DataObject {
  factory NodeCard._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => NodeCardUser._read(json, context),
    'Bot' => NodeCardBot._read(json, context),
    _ => NodeCardUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<NodeCard> codec =
      client.ObjectDataCodec(NodeCard._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<NodeCard> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The field `id`.
  String get id;
}
''');
  });

  test('a variant has the fields it overrides from the base', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...NodeCard } }
fragment NodeCard on Node { id ... on User { name } ... on Bot { model } }
''');
    expect(emission.emitFragment('NodeCard', 'NodeCardBot'), r'''
/// [NodeCard] when its type is `Bot`.
final class NodeCardBot implements NodeCard {
  /// Creates the value.
  const NodeCardBot({required this.id, this.model});

  factory NodeCardBot._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardBot(
    id: _idCodec.field(json, 'id', context),
    model: _modelCodec.field(json, 'model', context),
  );

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<String?> _modelCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.StringCodec()));

  @override
  String get typename => 'Bot';

  @override
  final String id;

  /// The field `model`.
  final String? model;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': const graphql.JsonString('Bot'),
    'id': _idCodec.write(id),
    'model': _modelCodec.write(model),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardBot && other.id == id && other.model == model;

  @override
  int get hashCode => Object.hashAll([id, model]);

  @override
  String toString() => 'NodeCardBot(id: $id, model: $model)';
}
''');
  });

  test('the unknown variant holds the type name', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...NodeCard } }
fragment NodeCard on Node { id ... on User { name } ... on Bot { model } }
''');
    expect(emission.emitFragment('NodeCard', 'NodeCardUnknown'), r'''
/// [NodeCard] when its type is none of those the selection tells apart.
final class NodeCardUnknown implements NodeCard {
  /// Creates the value.
  const NodeCardUnknown({required this.typename, required this.id});

  factory NodeCardUnknown._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => NodeCardUnknown(
    typename: _typenameCodec.field(json, '__typename', context),
    id: _idCodec.field(json, 'id', context),
  );

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  @override
  final String typename;

  @override
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    '__typename': _typenameCodec.write(typename),
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is NodeCardUnknown && other.typename == typename && other.id == id;

  @override
  int get hashCode => Object.hashAll([typename, id]);

  @override
  String toString() => 'NodeCardUnknown(typename: $typename, id: $id)';
}
''');
  });

  test('a base with a shared holder declares the fragments', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...Held } }
fragment Held on Node { ...Idf ... on User { name } ... on Bot { model } }
fragment Idf on Node { id }
''');
    expect(emission.emitFragment('Held', 'Held'), '''
/// The fragment `Held` on `Node`: a class per type the selection tells apart,
/// and [HeldUnknown] for any other type.
sealed class Held implements client.DataObject {
  factory Held._read(
    graphql.JsonObject json,
    client.DataContext context,
  ) => switch (_typenameCodec.field(json, '__typename', context)) {
    'User' => HeldUser._read(json, context),
    'Bot' => HeldBot._read(json, context),
    _ => HeldUnknown._read(json, context),
  };

  /// Reads and writes the fragment.
  static const client.DataCodec<Held> codec =
      client.ObjectDataCodec(Held._read);

  static const client.DataCodec<String> _typenameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  /// Reads [json], an object the fragment was spread on, in the response
  /// to an operation sent with [variables].
  static graphql.DecodeResult<Held> decode(
    graphql.JsonObject json, {
    graphql.JsonObject? variables,
  }) => codec.decode(json, client.DataContext(variables));

  /// The name of the value's type, `__typename`.
  String get typename;

  /// The fragments spread on this value.
  HeldFragments get fragments;
}
''');
  });

  test('a variant overrides the shared holder', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...Held } }
fragment Held on Node { ...Idf ... on User { name } ... on Bot { model } }
fragment Idf on Node { id }
''');
    expect(emission.emitFragment('Held', 'HeldUser'), r'''
/// [Held] when its type is `User`.
final class HeldUser implements Held {
  /// Creates the value.
  const HeldUser({required this.name, required this.fragments});

  factory HeldUser._read(graphql.JsonObject json, client.DataContext context) =>
      HeldUser(
        name: _nameCodec.field(json, 'name', context),
        fragments: HeldFragments._read(json, context),
      );

  static const client.DataCodec<String> _nameCodec =
      client.ScalarDataCodec(graphql.StringCodec());

  @override
  String get typename => 'User';

  /// The field `name`.
  final String name;

  @override
  final HeldFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
    'name': _nameCodec.write(name),
  });

  @override
  bool operator ==(Object other) =>
      other is HeldUser && other.name == name && other.fragments == fragments;

  @override
  int get hashCode => Object.hashAll([name, fragments]);

  @override
  String toString() => 'HeldUser(name: $name, fragments: $fragments)';
}
''');
  });

  test('a variant with a holder of its own does not override', () {
    final emission = ClassEmission(_schema, '''
query Q { node(id: "1") { ...Own } }
fragment Own on Node { ... on User { ...U } ... on Bot { model } }
fragment U on User { name }
''');
    expect(emission.emitFragment('Own', 'OwnUser'), r'''
/// [Own] when its type is `User`.
final class OwnUser implements Own {
  /// Creates the value.
  const OwnUser({required this.fragments});

  factory OwnUser._read(graphql.JsonObject json, client.DataContext context) =>
      OwnUser(fragments: OwnUserFragments._read(json, context));

  @override
  String get typename => 'User';

  /// The fragments spread on this value.
  final OwnUserFragments fragments;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    ...fragments.toJson().fields,
    '__typename': const graphql.JsonString('User'),
  });

  @override
  bool operator ==(Object other) =>
      other is OwnUser && other.fragments == fragments;

  @override
  int get hashCode => fragments.hashCode;

  @override
  String toString() => 'OwnUser(fragments: $fragments)';
}
''');
  });
}
