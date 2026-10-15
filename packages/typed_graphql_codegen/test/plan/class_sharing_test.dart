import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_description.dart';
import '../support/plan_fixture.dart';

const _schema = '''
interface Node { id: ID! }
interface Named { tag: Tag }
type Tag { label: String }
type A implements Node & Named { id: ID!, tag: Tag }
type B implements Node & Named { id: ID!, tag: Tag }
type C implements Node { id: ID! }
type Query { node: Node, a: Node }
''';

void main() {
  const description = PlanDescription();

  ShapePlanner plannerOf(PlanFixture fixture) =>
      ShapePlanner(fixture.schema, fixture.fragments);

  OperationDefinition firstOperation(PlanFixture fixture) =>
      fixture.document.definitions.whereType<OperationDefinition>().first;

  test('variants that select a field with the same nodes share its class', () {
    final fixture = PlanFixture(
      _schema,
      'query { node { id ... on Named { tag { label } } } }',
    );
    final plan = plannerOf(fixture).planOperation(firstOperation(fixture));
    expect(
      description.describe(plan),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  id: ID! <- id
  variants: A=DataNodeA, B=DataNodeB, unknown=DataNodeUnknown
DataNodeA (variant on A, implements DataNode)
  @override id: ID! <- id
  tag: Tag <- tag -> DataNodeATag
DataNodeATag (nested on Tag, of DataNodeA.tag)
  label: String <- label
DataNodeB (variant on B, implements DataNode)
  @override id: ID! <- id
  tag: Tag <- tag -> DataNodeATag
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  @override id: ID! <- id''',
    );
  });

  test('a document that needs more than the limit is cut off', () {
    final fields = [
      for (var index = 0; index <= ShapePlanner.maxClasses; index++)
        'f$index: a { id }',
    ].join(' ');
    final fixture = PlanFixture(_schema, 'query { $fields }');
    final planner = plannerOf(fixture);
    final operation = firstOperation(fixture);
    expect(planner.planOperation(operation), isEmpty);
    expect(planner.exceedsLimit(operation), isTrue);
  });

  test('a document at the limit is planned', () {
    final fields = [
      for (var index = 0; index < ShapePlanner.maxClasses - 3; index++)
        'f$index: a { id }',
    ].join(' ');
    final fixture = PlanFixture(_schema, 'query { $fields }');
    final planner = plannerOf(fixture);
    final operation = firstOperation(fixture);
    expect(planner.planOperation(operation), hasLength(greaterThan(9990)));
    expect(planner.exceedsLimit(operation), isFalse);
  });

  test('a definition is planned once', () {
    final fixture = PlanFixture(_schema, 'query { node { id } }');
    final planner = plannerOf(fixture);
    final operation = firstOperation(fixture);
    expect(
      identical(
        planner.planOperation(operation),
        planner.planOperation(operation),
      ),
      isTrue,
    );
  });

  test(
    'a field every variant selects differently is planned once per list',
    () {
      // At each level the base `z` has the next level inside, and each type
      // adds a `z` of its own: the base `z` is not shared by the variants, so
      // planned per variant the classes would number (types + 1) to the power
      // of the depth, from a document of linear size.
      const types = 5;
      const depth = 4;
      final schema = StringBuffer('interface N { id: ID!, z: N }\n')
        ..writeln('type Query { n: N }');
      for (var type = 0; type < types; type++) {
        schema.writeln('type T$type implements N { id: ID!, z: N }');
      }
      final own = [
        for (var type = 0; type < types; type++) '... on T$type { z { id } }',
      ].join(' ');
      var body = 'id';
      for (var level = 0; level < depth; level++) {
        body = 'id z { $body } $own';
      }
      final fixture = PlanFixture('$schema', 'query { n { $body } }');
      final planner = plannerOf(fixture);
      final operation = firstOperation(fixture);
      final classes = planner.planOperation(operation);
      expect(planner.exceedsLimit(operation), isFalse);
      expect(classes.length, lessThan(200));
    },
  );
}
