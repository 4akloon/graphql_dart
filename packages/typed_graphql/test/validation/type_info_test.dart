import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

/// Records what [TypeInfo] says at each node of a kind it is asked about.
final class _Recorder extends ValidationRule {
  _Recorder(this.describe);

  final String? Function(Node node, TypeInfo info) describe;
  final List<String> lines = [];

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _RecordingVisitor(this, context.typeInfo);
}

final class _RecordingVisitor extends AstVisitor {
  _RecordingVisitor(this.recorder, this.info);

  final _Recorder recorder;
  final TypeInfo info;

  @override
  VisitAction enter(Node node) {
    if (recorder.describe(node, info) case final line?) {
      recorder.lines.add(line);
    }
    return VisitAction.next;
  }
}

void main() {
  final checked = Checked('''
type Query {
  pet(id: ID! = "1", filter: Filter): Pet
  pets(ids: [[ID!]]): [Pet]
  scalar: Int
}
interface Pet { name: String }
type Dog implements Pet { name: String barks: Boolean }
type Cat implements Pet { name: String }
union Animal = Dog | Cat
input Filter { color: Color = RED, nested: Filter }
enum Color { RED GREEN }
directive @tag(label: String = "x") on FIELD
''');
  const printer = Printer();
  String text(TypeRef? type) => type == null ? '-' : printer.print(type);

  List<String> record(
    String document,
    String? Function(Node node, TypeInfo info) describe,
  ) {
    final recorder = _Recorder(describe);
    checked.validate(document, validator: DocumentValidator(rules: [recorder]));
    return recorder.lines;
  }

  test('a field has its parent type, definition and type', () {
    final lines = record('{ pet { name ... on Dog { barks } } }', (node, info) {
      if (node is! Field) {
        return null;
      }
      return '${node.name.value}: ${info.parentType?.name} '
          '${info.fieldDefinition?.name} ${text(info.type)}';
    });
    expect(lines, [
      'pet: Query pet Pet',
      'name: Pet name String',
      'barks: Dog barks Boolean',
    ]);
  });

  test('meta-fields resolve where graphql-js resolves them', () {
    final lines = record(
      '{ __typename __schema { __typename } pet { __typename __type } }',
      (node, info) =>
          node is Field ? '${node.name.value}: ${text(info.type)}' : null,
    );
    expect(lines, [
      '__typename: String!',
      '__schema: __Schema!',
      '__typename: String!',
      'pet: Pet',
      '__typename: String!',
      // __type exists only on the query root.
      '__type: -',
    ]);
  });

  test('unknown fields and types give nulls', () {
    final lines = record(
      '{ missing { name } ... on Missing { scalar } }',
      (node, info) => node is Field
          ? '${node.name.value}: ${info.parentType?.name} ${text(info.type)}'
          : null,
    );
    expect(lines, ['missing: Query -', 'name: null -', 'scalar: null -']);
  });

  test('an inline fragment without a type condition keeps the type', () {
    final lines = record(
      '{ pet { ... { name } } }',
      (node, info) => node is InlineFragment ? text(info.type) : null,
    );
    expect(lines, ['Pet']);
  });

  test('arguments, list items and input fields have input types', () {
    final lines = record(
      r'query ($c: Color) { pet(id: 1, filter: { color: $c, nested: {} }) '
      'pets(ids: [[1]]) { name } }',
      (node, info) => switch (node) {
        Argument(:final name) || ObjectField(:final name) =>
          '${name.value}: ${text(info.inputType)} '
              'default ${info.defaultValue == null ? '-' : printer.print(info.defaultValue!)}',
        ListValue() =>
          'list: ${text(info.inputType)} in '
              '${text(info.parentInputType)}',
        Variable(:final name) =>
          '\$${name.value}: ${text(info.inputType)} in '
              '${text(info.parentInputType)}',
        _ => null,
      },
    );
    expect(lines, [
      // A variable definition's variable has the definition's type.
      r'$c: Color in -',
      'id: ID! default "1"',
      'filter: Filter default -',
      'color: Color default RED',
      r'$c: Color in Filter',
      'nested: Filter default -',
      'ids: [[ID!]] default -',
      'list: [ID!] in [[ID!]]',
      'list: ID! in [ID!]',
    ]);
  });

  test('a variable definition has its input type', () {
    final lines = record(
      r'query ($a: [Color!], $b: Pet, $c: Missing) { scalar }',
      (node, info) => node is VariableDefinition ? text(info.inputType) : null,
    );
    expect(lines, ['[Color!]', '-', '-']);
  });

  test('an enum value, a directive and an argument have definitions', () {
    final lines = record(
      '{ pet(filter: { color: GREEN }) { name @tag(label: "a") } }',
      (node, info) => switch (node) {
        EnumValue() => 'enum ${info.enumValue?.name}',
        Directive() => 'directive ${info.directive?.name}',
        Argument() =>
          'argument ${info.argument?.name} '
              'of ${info.directive?.name ?? info.fieldDefinition?.name}',
        _ => null,
      },
    );
    expect(lines, [
      'argument filter of pet',
      'enum GREEN',
      'directive tag',
      'argument label of tag',
    ]);
  });

  test('state is left behind when the walk leaves a node', () {
    final lines = record(
      '{ pet(id: 1) { name } scalar }',
      (node, info) => node is Field && node.name.value == 'scalar'
          ? '${info.argument} ${info.directive} ${info.parentType?.name} '
                '${text(info.inputType)}'
          : null,
    );
    expect(lines, ['null null Query -']);
  });
}
