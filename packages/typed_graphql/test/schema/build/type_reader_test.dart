import 'package:test/test.dart';
import 'package:typed_graphql/src/schema/build/element_reader.dart';
import 'package:typed_graphql/src/schema/build/node_spans.dart';
import 'package:typed_graphql/src/schema/build/type_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../sdl.dart';

void main() {
  final sdl = Sdl('''
"A date" scalar Date @specifiedBy(url: "https://example.com/date")
type Query implements Node & Entity @key { id: ID! when: Date }
interface Node implements Entity { id: ID! }
union Result @tag = Query | Other
enum Color { RED GREEN }
input Filter @oneOf { color: Color = RED, limit: Int }
''');
  final reader = TypeReader(ElementReader(NodeSpans(sdl.source)));
  final types = sdl.all<TypeDefinition>().map(reader.type).toList();

  test('reads each definition into a type of its kind', () {
    expect(types.map((type) => type.name), [
      'Date',
      'Query',
      'Node',
      'Result',
      'Color',
      'Filter',
    ]);
    expect(types[0], isA<ScalarType>());
    expect(types[1], isA<ObjectType>());
    expect(types[2], isA<InterfaceType>());
    expect(types[3], isA<UnionType>());
    expect(types[4], isA<EnumType>());
    expect(types[5], isA<InputObjectType>());
  });

  test('reads a scalar with its description and @specifiedBy', () {
    final date = types[0] as ScalarType;
    expect(date.description, 'A date');
    expect(date.specifiedByUrl, 'https://example.com/date');
  });

  test('keeps implemented interfaces and union members as names', () {
    final query = types[1] as ObjectType;
    expect(query.interfaces.map((type) => type.name.value), [
      'Node',
      'Entity',
    ]);
    final node = types[2] as InterfaceType;
    expect(node.interfaces.single.name.value, 'Entity');
    final result = types[3] as UnionType;
    expect(result.memberTypes.map((type) => type.name.value), [
      'Query',
      'Other',
    ]);
  });

  test('reads the members of each kind', () {
    expect((types[1] as ObjectType).fields.map((field) => field.name), [
      'id',
      'when',
    ]);
    expect((types[4] as EnumType).values.map((value) => value.name), [
      'RED',
      'GREEN',
    ]);
    final filter = types[5] as InputObjectType;
    expect(filter.fields.map((field) => field.name), ['color', 'limit']);
    expect(filter.isOneOf, isTrue);
  });

  test('reads the directives applied to a type', () {
    expect(types[1].appliedDirectives.single.name, 'key');
    expect(types[3].appliedDirectives.single.name, 'tag');
  });

  test('gives a type the span of its whole definition', () {
    expect(types[0].span?.text, startsWith('"A date" scalar Date'));
    expect(types[4].span?.text, 'enum Color { RED GREEN }');
  });
}
