import 'package:test/test.dart';

/// graphql-js's node builders of `schema-parser-test.ts` (`nameNode`,
/// `typeNode`, `fieldNode`, `fieldNodeWithArgs`, `enumValueNode`,
/// `inputValueNode`) as `AstJson` maps, shared by the files the suite is
/// split into.
final class SchemaNodes {
  /// Creates the builders; they keep no state.
  const SchemaNodes();

  /// A location, graphql-js's `{ start, end }`.
  Map<String, int> loc(int start, int end) => {'start': start, 'end': end};

  /// A `Document` node.
  Map<String, Object?> document(
    List<Object?> definitions,
    Map<String, int> loc,
  ) => {'kind': 'Document', 'definitions': definitions, 'loc': loc};

  /// A `Name` node.
  Map<String, Object?> nameNode(String name, Map<String, int> loc) => {
    'kind': 'Name',
    'value': name,
    'loc': loc,
  };

  /// A `NamedType` node.
  Map<String, Object?> typeNode(String name, Map<String, int> loc) => {
    'kind': 'NamedType',
    'name': nameNode(name, loc),
    'loc': loc,
  };

  /// A `FieldDefinition` node without arguments.
  Map<String, Object?> fieldNode(
    Object? name,
    Object? type,
    Map<String, int> loc,
  ) => fieldNodeWithArgs(name, type, null, loc);

  /// A `FieldDefinition` node.
  Map<String, Object?> fieldNodeWithArgs(
    Object? name,
    Object? type,
    Object? arguments,
    Map<String, int> loc,
  ) => {
    'kind': 'FieldDefinition',
    'description': null,
    'name': name,
    'arguments': arguments,
    'type': type,
    'directives': null,
    'loc': loc,
  };

  /// An `EnumValueDefinition` node.
  Map<String, Object?> enumValueNode(String name, Map<String, int> loc) => {
    'kind': 'EnumValueDefinition',
    'name': nameNode(name, loc),
    'description': null,
    'directives': null,
    'loc': loc,
  };

  /// An `InputValueDefinition` node.
  Map<String, Object?> inputValueNode(
    Object? name,
    Object? type,
    Object? defaultValue,
    Map<String, int> loc,
  ) => {
    'kind': 'InputValueDefinition',
    'name': name,
    'description': null,
    'type': type,
    'defaultValue': defaultValue,
    'directives': null,
    'loc': loc,
  };

  /// graphql-js's `toDeepNestedProperty('definitions[0].<key>')`: the field
  /// [key] of the first definition of a [document] from `ParserPort.parse`.
  Object? firstDefinition(Object? document, String key) {
    if (document case {
      'definitions': [final Map<String, Object?> first, ...],
    }) {
      return first[key];
    }
    fail('$document has no definitions');
  }
}
