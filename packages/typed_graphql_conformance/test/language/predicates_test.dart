// Ported from graphql-js src/language/__tests__/predicates-test.ts; see
// mapping/language.csv.
//
// Adapted throughout: graphql-js's predicates are Dart's sealed families,
// so `filterNodes` tests one parsed node of each kind with `is`.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../support/node_samples.dart';

void main() {
  final samples = const NodeSamples().byKind();

  List<String> filterNodes(bool Function(Node node) predicate) => [
    for (final MapEntry(key: kind, value: node) in samples.entries)
      if (predicate(node)) kind,
  ];

  group('AST node predicates', () {
    test('has a sample of every kind but FragmentArgument', () {
      expect(samples, hasLength(49));
    });

    test('isDefinitionNode', () {
      expect(filterNodes((node) => node is Definition), [
        'DirectiveDefinition',
        'DirectiveExtension',
        'EnumTypeDefinition',
        'EnumTypeExtension',
        'FragmentDefinition',
        'InputObjectTypeDefinition',
        'InputObjectTypeExtension',
        'InterfaceTypeDefinition',
        'InterfaceTypeExtension',
        'ObjectTypeDefinition',
        'ObjectTypeExtension',
        'OperationDefinition',
        'ScalarTypeDefinition',
        'ScalarTypeExtension',
        'SchemaDefinition',
        'SchemaExtension',
        'UnionTypeDefinition',
        'UnionTypeExtension',
      ]);
    });

    test('isExecutableDefinitionNode', () {
      expect(filterNodes((node) => node is ExecutableDefinition), [
        'FragmentDefinition',
        'OperationDefinition',
      ]);
    });

    test('isSelectionNode', () {
      expect(filterNodes((node) => node is Selection), [
        'Field',
        'FragmentSpread',
        'InlineFragment',
      ]);
    });

    test('isValueNode', () {
      expect(filterNodes((node) => node is Value), [
        'BooleanValue',
        'EnumValue',
        'FloatValue',
        'IntValue',
        'ListValue',
        'NullValue',
        'ObjectValue',
        'StringValue',
        'Variable',
      ]);
    });

    // Adapted: there is no isConstValueNode; a const value is one that
    // parseValue accepts with isConst.
    test('isConstValueNode', () {
      bool isConst(String text) =>
          const Parser().parseValue(Source(text), isConst: true)
              is ParseElementSuccess<Value>;

      expect(isConst('"value"'), isTrue);
      expect(isConst(r'$var'), isFalse);

      expect(isConst('{ field: "value" }'), isTrue);
      expect(isConst(r'{ field: $var }'), isFalse);

      expect(isConst('[ "value" ]'), isTrue);
      expect(isConst(r'[ $var ]'), isFalse);
    });

    test('isTypeNode', () {
      expect(filterNodes((node) => node is TypeRef), [
        'ListType',
        'NamedType',
        'NonNullType',
      ]);
    });

    test('isTypeSystemDefinitionNode', () {
      expect(filterNodes((node) => node is TypeSystemDefinition), [
        'DirectiveDefinition',
        'EnumTypeDefinition',
        'InputObjectTypeDefinition',
        'InterfaceTypeDefinition',
        'ObjectTypeDefinition',
        'ScalarTypeDefinition',
        'SchemaDefinition',
        'UnionTypeDefinition',
      ]);
    });

    test('isTypeDefinitionNode', () {
      expect(filterNodes((node) => node is TypeDefinition), [
        'EnumTypeDefinition',
        'InputObjectTypeDefinition',
        'InterfaceTypeDefinition',
        'ObjectTypeDefinition',
        'ScalarTypeDefinition',
        'UnionTypeDefinition',
      ]);
    });

    test('isTypeSystemExtensionNode', () {
      expect(filterNodes((node) => node is TypeSystemExtension), [
        'DirectiveExtension',
        'EnumTypeExtension',
        'InputObjectTypeExtension',
        'InterfaceTypeExtension',
        'ObjectTypeExtension',
        'ScalarTypeExtension',
        'SchemaExtension',
        'UnionTypeExtension',
      ]);
    });

    test('isTypeExtensionNode', () {
      expect(filterNodes((node) => node is TypeExtension), [
        'EnumTypeExtension',
        'InputObjectTypeExtension',
        'InterfaceTypeExtension',
        'ObjectTypeExtension',
        'ScalarTypeExtension',
        'UnionTypeExtension',
      ]);
    });

    test('isSchemaCoordinateNode', () {
      expect(filterNodes((node) => node is SchemaCoordinate), [
        'ArgumentCoordinate',
        'DirectiveArgumentCoordinate',
        'DirectiveCoordinate',
        'MemberCoordinate',
        'TypeCoordinate',
      ]);
    });
  });
}
