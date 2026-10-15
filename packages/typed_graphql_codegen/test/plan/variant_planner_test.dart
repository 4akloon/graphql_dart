import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/shape_planner.dart';

import '../support/plan_description.dart';
import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  const description = PlanDescription();

  String plan(String document, {String schema = planSchema}) {
    final fixture = PlanFixture(schema, document);
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    final operation = fixture.document.definitions
        .whereType<OperationDefinition>()
        .first;
    return description.describe(planner.planOperation(operation));
  }

  test('the target FindNode plans a base, two variants and Unknown', () {
    final target = Directory('../../.superpowers/m10-target');
    final schema = File('${target.path}/schema.graphql').readAsStringSync();
    final document = File('${target.path}/user.graphql').readAsStringSync();
    expect(
      plan(
        document.substring(document.indexOf('query FindNode')) +
            document.substring(
              document.indexOf('fragment UserCard'),
              document.indexOf('query FindNode'),
            ),
        schema: schema,
      ),
      '''
FindNodeData (operationData on Query)
  node: Node <- node -> FindNodeDataNode
FindNodeDataNode (sealed nested on Node, of FindNodeData.node)
  id: ID! <- id
  variants: User=FindNodeDataNodeUser, Bot=FindNodeDataNodeBot, unknown=FindNodeDataNodeUnknown
FindNodeDataNodeUser (variant on User, implements FindNodeDataNode)
  @override id: ID! <- id
  name: String! <- name
  fragments: FindNodeDataNodeUserFragments
FindNodeDataNodeUserFragments (holder of FindNodeDataNodeUser)
  userCard: UserCard
FindNodeDataNodeBot (variant on Bot, implements FindNodeDataNode)
  @override id: ID! <- id
  model: String <- model
FindNodeDataNodeUnknown (unknownVariant on Node, implements FindNodeDataNode)
  @override id: ID! <- id''',
    );
  });

  test('a union without shared fields plans one class per narrowing', () {
    expect(
      plan('query { actor { ... on User { name } ... on Bot { model } } }'),
      '''
Data (operationData on Query)
  actor: Actor <- actor -> DataActor
DataActor (sealed nested on Actor, of Data.actor)
  variants: User=DataActorUser, Bot=DataActorBot, unknown=DataActorUnknown
DataActorUser (variant on User, implements DataActor)
  name: String <- name
DataActorBot (variant on Bot, implements DataActor)
  model: String <- model
DataActorUnknown (unknownVariant on Actor, implements DataActor)''',
    );
  });

  group('a base field a variant re-selects', () {
    const schema = '''
interface Node { owner: Owner }
type Owner { id: ID!, name: String }
type User implements Node { owner: Owner }
type Bot implements Node { owner: Owner }
type Query { node: Node }
''';

    test('is dropped from the base, with a class per variant', () {
      expect(
        plan(
          'query { node { owner { id } ... on User { owner { name } } } }',
          schema: schema,
        ),
        '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  owner: Owner <- owner -> DataNodeUserOwner
DataNodeUserOwner (nested on Owner, of DataNodeUser.owner)
  id: ID! <- id
  name: String <- name
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  owner: Owner <- owner -> DataNodeUnknownOwner
DataNodeUnknownOwner (nested on Owner, of DataNodeUnknown.owner)
  id: ID! <- id''',
      );
    });

    test('stays shared when no variant re-selects it', () {
      expect(
        plan(
          'query { node { owner { id } ... on User { __typename } } }',
          schema: schema,
        ),
        '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  owner: Owner <- owner -> DataNodeOwner
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeOwner (nested on Owner, of DataNode.owner)
  id: ID! <- id
DataNodeUser (variant on User, implements DataNode)
  @override owner: Owner <- owner -> DataNodeOwner
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  @override owner: Owner <- owner -> DataNodeOwner''',
      );
    });
  });

  test('a narrowing inside a narrowing reaches only the inner types', () {
    expect(
      plan('query { actor { ... on Node { ... on User { name } } } }'),
      '''
Data (operationData on Query)
  actor: Actor <- actor -> DataActor
DataActor (sealed nested on Actor, of Data.actor)
  variants: User=DataActorUser, Bot=DataActorBot, unknown=DataActorUnknown
DataActorUser (variant on User, implements DataActor)
  name: String <- name
DataActorBot (variant on Bot, implements DataActor)
DataActorUnknown (unknownVariant on Actor, implements DataActor)''',
    );
  });

  test('a narrowing under @include makes its fields conditional', () {
    expect(
      plan(
        r'query($x: Boolean!) { actor { ... on User @include(if: $x) { name } } }',
      ),
      '''
Data (operationData on Query)
  actor: Actor <- actor -> DataActor
DataActor (sealed nested on Actor, of Data.actor)
  variants: User=DataActorUser, unknown=DataActorUnknown
DataActorUser (variant on User, implements DataActor)
  name: String <- name (conditional)
DataActorUnknown (unknownVariant on Actor, implements DataActor)''',
    );
  });

  test('a fragment spread on the interface is a shared holder', () {
    expect(
      plan(
        'query { node { ...NodeCard ... on User { name } } }\n'
        'fragment NodeCard on Node { id }',
      ),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  fragments: DataNodeFragments
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeFragments (holder of DataNode)
  nodeCard: NodeCard
DataNodeUser (variant on User, implements DataNode)
  name: String <- name
  fragments: DataNodeFragments (override)
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  fragments: DataNodeFragments (override)''',
    );
  });

  test('a variant that adds a fragment drops the base holder', () {
    expect(
      plan(
        'query { node { ...NodeCard ... on User { ...NodeCard @include(if: true) ...UserCard } } }\n'
        'fragment NodeCard on Node { id }\nfragment UserCard on User { name }',
      ),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  fragments: DataNodeUserFragments
DataNodeUserFragments (holder of DataNodeUser)
  nodeCard: NodeCard
  userCard: UserCard
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  fragments: DataNodeUnknownFragments
DataNodeUnknownFragments (holder of DataNodeUnknown)
  nodeCard: NodeCard''',
    );
  });

  test('an abstract selection without narrowings stays a plain class', () {
    expect(
      plan('query { node { id } }'),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (nested on Node, of Data.node)
  id: ID! <- id''',
    );
  });

  test(
    'a condition on an interface the parent implements is not a variant',
    () {
      const schema = '''
interface Node { id: ID! }
interface Entity implements Node { id: ID!, label: String }
type Admin implements Entity & Node { id: ID!, label: String }
type Query { entity: Entity }
''';
      expect(
        plan('query { entity { ... on Node { id } label } }', schema: schema),
        '''
Data (operationData on Query)
  entity: Entity <- entity -> DataEntity
DataEntity (nested on Entity, of Data.entity)
  id: ID! <- id
  label: String <- label''',
      );
    },
  );

  test('a fragment on an interface with variants is a polymorphic fragment', () {
    final fixture = PlanFixture(
      planSchema,
      'query { node { ...F } }\nfragment F on Node { id ... on User { name } }',
    );
    final planner = ShapePlanner(fixture.schema, fixture.fragments);
    expect(
      description.describe(planner.planFragment(fixture.fragments['F']!)),
      '''
F (sealed fragment on Node)
  id: ID! <- id
  variants: User=FUser, unknown=FUnknown
FUser (variant on User, implements F)
  @override id: ID! <- id
  name: String <- name
FUnknown (unknownVariant on Node, implements F)
  @override id: ID! <- id''',
    );
  });

  test('an aliased __typename stays a field of a polymorphic shape', () {
    expect(
      plan('query { node { ... on User { name } kind: __typename } }'),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  kind: String! <- kind
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  name: String <- name
  @override kind: String! <- kind
DataNodeUnknown (unknownVariant on Node, implements DataNode)
  @override kind: String! <- kind''',
    );
  });

  test('a selected __typename is not a field of a polymorphic shape', () {
    expect(
      plan('query { node { __typename ... on User { name } } }'),
      '''
Data (operationData on Query)
  node: Node <- node -> DataNode
DataNode (sealed nested on Node, of Data.node)
  variants: User=DataNodeUser, unknown=DataNodeUnknown
DataNodeUser (variant on User, implements DataNode)
  name: String <- name
DataNodeUnknown (unknownVariant on Node, implements DataNode)''',
    );
  });

  test('fifty possible types plan fifty variants in schema order', () {
    final names = [for (var i = 0; i < 50; i++) 'T$i'];
    final schema = [
      'interface Node { id: ID! }',
      for (final name in names) 'type $name implements Node { id: ID! }',
      'type Query { node: Node }',
    ].join('\n');
    final lines = plan(
      'query { node { ${[for (final name in names.reversed) '... on $name { id }'].join(' ')} } }',
      schema: schema,
    ).split('\n');
    final variants = lines.firstWhere((line) => line.startsWith('  variants:'));
    expect(
      variants,
      '  variants: ${[for (final name in names) '$name=DataNode$name'].join(', ')}'
      ', unknown=DataNodeUnknown',
    );
  });
}
