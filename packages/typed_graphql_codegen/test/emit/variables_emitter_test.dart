import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';
import 'package:typed_graphql_codegen/src/emit/type_mapper.dart';
import 'package:typed_graphql_codegen/src/emit/variables_emitter.dart';

import '../support/operation_fixture.dart';
import '../support/plan_fixture.dart';

void main() {
  String emit(String operationName) {
    final fixture = PlanFixture(operationSchema, operationDocument);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .firstWhere((operation) => operation.name?.value == operationName);
    final writer = DartWriter();
    VariablesEmitter(
      TypeMapper(fixture.schema, const {}),
    ).emit(operation, writer, Imports());
    return writer.text;
  }

  test('required, defaulted and required variables', () {
    expect(emit('GetUser'), r'''
/// The variables of the query `GetUser`.
final class GetUserVariables implements client.DataObject {
  /// Creates the variables.
  const GetUserVariables({
    required this.id,
    required this.full,
    this.withFriends = const graphql.Optional.absent(),
  });

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  static const client.DataCodec<bool?> _withFriendsCodec =
      client.NullableDataCodec(client.ScalarDataCodec(graphql.BooleanCodec()));

  static const client.DataCodec<bool> _fullCodec =
      client.ScalarDataCodec(graphql.BooleanCodec());

  /// The variable `$id`.
  final String id;

  /// The variable `$withFriends`; its default is `false`.
  final graphql.Optional<bool?> withFriends;

  /// The variable `$full`.
  final bool full;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
    if (withFriends case graphql.Present(:final value))
      'withFriends': _withFriendsCodec.write(value),
    'full': _fullCodec.write(full),
  });

  @override
  bool operator ==(Object other) =>
      other is GetUserVariables &&
      other.id == id &&
      other.withFriends == withFriends &&
      other.full == full;

  @override
  int get hashCode => Object.hashAll([
    id.hashCode,
    withFriends.hashCode,
    full.hashCode,
  ]);

  @override
  String toString() =>
      'GetUserVariables(id: $id, withFriends: $withFriends, full: $full)';
}
''');
  });

  test('a single required variable', () {
    expect(emit('FindNode'), r'''
/// The variables of the query `FindNode`.
final class FindNodeVariables implements client.DataObject {
  /// Creates the variables.
  const FindNodeVariables({required this.id});

  static const client.DataCodec<String> _idCodec =
      client.ScalarDataCodec(graphql.IdCodec());

  /// The variable `$id`.
  final String id;

  @override
  graphql.JsonObject toJson() => graphql.JsonObject({
    'id': _idCodec.write(id),
  });

  @override
  bool operator ==(Object other) =>
      other is FindNodeVariables &&
      other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FindNodeVariables(id: $id)';
}
''');
  });

  test('an optional list variable compares by item', () {
    expect(
      emit('SearchAll'),
      allOf(
        contains('  final graphql.Optional<List<String>?> tags;\n'),
        contains(
          '      const client.DataEquality().equals(other.tags, tags);\n',
        ),
      ),
    );
  });
}
