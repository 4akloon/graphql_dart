import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_codegen/src/plan/collected_selection.dart';
import 'package:typed_graphql_codegen/src/plan/condition.dart';

import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  CollectedSelection collect(
    String body,
    String parent, {
    String field = 'user',
    String fragments = '',
  }) {
    final declared = [
      for (final name in ['v', 'w'])
        if (body.contains('\$$name')) '\$$name: Boolean!',
    ];
    final variables = declared.isEmpty ? '' : '(${declared.join(', ')})';
    final fixture = PlanFixture(
      planSchema,
      'query $variables { $body }\n$fragments',
    );
    return fixture.collector.collect(fixture.type(parent), [
      fixture.sourceOf(field),
    ]);
  }

  List<String> fieldsOf(CollectedSelection selection) => [
    for (final group in selection.fields)
      '${group.responseName}:${group.fieldName}'
          '${group.isConditional ? '?' : ''}x${group.nodes.length}',
  ];

  test('fields merge by response name in first-occurrence order', () {
    final selection = collect('user { name id name }', 'User');
    expect(fieldsOf(selection), ['name:namex2', 'id:idx1']);
  });

  test('an alias keeps a field apart', () {
    final selection = collect('user { name other: name }', 'User');
    expect(fieldsOf(selection), ['name:namex1', 'other:namex1']);
  });

  test('a group knows its schema field', () {
    final selection = collect('user { friend { id } }', 'User');
    expect(selection.fields.single.definition.name, 'friend');
  });

  test('a field with a variable condition is conditional', () {
    final selection = collect(r'user { name @include(if: $v) }', 'User');
    expect(fieldsOf(selection), ['name:name?x1']);
  });

  test('a group is conditional only when every node is', () {
    final selection = collect(
      r'user { name @include(if: $v) name }',
      'User',
    );
    expect(fieldsOf(selection), ['name:namex2']);
  });

  test('a group of conditional nodes is conditional', () {
    final selection = collect(
      r'user { name @include(if: $v) name @skip(if: $w) }',
      'User',
    );
    expect(fieldsOf(selection), ['name:name?x2']);
  });

  test('a field in a conditional inline fragment is conditional', () {
    final selection = collect(
      r'user { ... @include(if: $v) { name } }',
      'User',
    );
    expect(fieldsOf(selection), ['name:name?x1']);
  });

  test('inline fragments without a condition and on the parent merge', () {
    final selection = collect(
      'user { id ... { name } ... on User { name model: id } }',
      'User',
    );
    expect(fieldsOf(selection), ['id:idx1', 'name:namex2', 'model:idx1']);
  });

  test('a condition on an implemented interface applies', () {
    final selection = collect('user { ... on Node { id } }', 'User');
    expect(fieldsOf(selection), ['id:idx1']);
  });

  test('a nested User inside Node under a union narrows', () {
    final selection = collect(
      'actor { ... on Node { id ... on User { name } } }',
      'Actor',
      field: 'actor',
    );
    expect(fieldsOf(selection), isEmpty);
    expect(selection.narrowings.map((n) => n.typeCondition), ['Node']);
  });

  test('a narrowing inside an applied fragment is recorded', () {
    final selection = collect(
      'node { id ... on Node { ... on User { name } } }',
      'Node',
      field: 'node',
    );
    expect(fieldsOf(selection), ['id:idx1']);
    expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
  });

  test('a narrowing inline fragment under @include is recorded', () {
    final selection = collect(
      r'node { ... on User @include(if: $v) { name } }',
      'Node',
      field: 'node',
    );
    expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
  });

  test('a disjoint condition is dropped', () {
    final selection = collect(
      'node { ... on Bot { model } }',
      'User',
      field: 'node',
    );
    expect(selection.narrowings, isEmpty);
    expect(fieldsOf(selection), isEmpty);
  });

  test('a spread becomes a use, not fields', () {
    final selection = collect(
      'user { ...F }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(fieldsOf(selection), isEmpty);
    expect(selection.fragments.single.fragmentName, 'F');
    expect(selection.fragments.single.whenAny, [<Condition>[]]);
    expect(selection.fragments.single.isConditional, isFalse);
  });

  test('a spread of a narrowing fragment is a narrowing', () {
    final selection = collect(
      r'node { ...F @skip(if: $w) }',
      'Node',
      field: 'node',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.narrowings.map((n) => n.typeCondition), ['User']);
    expect(selection.fragments, isEmpty);
  });

  test('a spread inherits the conditions of an inline fragment', () {
    final selection = collect(
      r'user { ... @include(if: $v) { ...F @skip(if: $w) } }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.fragments.single.whenAny, [
      [const Condition('v', true), const Condition('w', false)],
    ]);
  });

  test(
    'a fragment spread twice, unconditional and conditional, is unconditional',
    () {
      final selection = collect(
        r'user { ...F @include(if: $v) ...F }',
        'User',
        fragments: 'fragment F on User { name }',
      );
      expect(selection.fragments.single.whenAny, [<Condition>[]]);
    },
  );

  test('a fragment spread twice under two conditions keeps both', () {
    final selection = collect(
      r'user { ...F @include(if: $v) ...F @skip(if: $w) }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.fragments.single.whenAny, [
      [const Condition('v', true)],
      [const Condition('w', false)],
    ]);
    expect(selection.fragments.single.isConditional, isTrue);
  });

  test('the same condition twice is not repeated', () {
    final selection = collect(
      r'user { ...F @include(if: $v) ...F @include(if: $v) }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(selection.fragments.single.whenAny, [
      [const Condition('v', true)],
    ]);
  });

  test('include(if: false) drops a field, a spread and a fragment', () {
    final selection = collect(
      'user { name @include(if: false) ...F @skip(if: true) '
          '... @include(if: false) { id } }',
      'User',
      fragments: 'fragment F on User { name }',
    );
    expect(fieldsOf(selection), isEmpty);
    expect(selection.fragments, isEmpty);
  });

  test('an aliased __typename is an ordinary String! field', () {
    final selection = collect('user { kind: __typename }', 'User');
    expect(fieldsOf(selection), ['kind:__typenamex1']);
    expect(
      const Printer().print(selection.fields.single.definition.type),
      'String!',
    );
    expect(selection.selectsTypename, isFalse);
  });

  test('an unaliased __typename only sets selectsTypename', () {
    final selection = collect('user { __typename id }', 'User');
    expect(fieldsOf(selection), ['id:idx1']);
    expect(selection.selectsTypename, isTrue);
  });

  test('__typename on a union parent is found', () {
    final selection = collect('actor { __typename }', 'Actor', field: 'actor');
    expect(selection.selectsTypename, isTrue);
  });

  test('a field sub-selection is not walked', () {
    final selection = collect('user { friend { name } }', 'User');
    expect(fieldsOf(selection), ['friend:friendx1']);
  });

  test('several sources collect in order', () {
    final fixture = PlanFixture(
      planSchema,
      'query { user { id } node { id } }',
    );
    final selection = fixture.collector.collect(fixture.type('User'), [
      fixture.sourceOf('user'),
      fixture.sourceOf('node'),
    ]);
    expect(fieldsOf(selection), ['id:idx2']);
  });

  test('a selection set 1000 inline fragments deep collects', () {
    const depth = 1000;
    final body = '${'... on User { ' * depth}name${' }' * depth}';
    final fixture = PlanFixture(
      planSchema,
      'query { user { $body } }',
      maxDepth: null,
    );
    final selection = fixture.collector.collect(fixture.type('User'), [
      fixture.sourceOf('user'),
    ]);
    expect(fieldsOf(selection), ['name:namex1']);
  });

  group('__typename', () {
    test('an unconditional one on an object is not a field group', () {
      final selection = collect('user { __typename id }', 'User');
      expect(selection.selectsTypename, isTrue);
      expect(fieldsOf(selection), ['id:idx1']);
    });

    test('a conditional one on an object is a conditional field', () {
      final selection = collect(
        r'user { __typename @include(if: $v) id }',
        'User',
      );
      expect(selection.selectsTypename, isFalse);
      expect(fieldsOf(selection), ['__typename:__typename?x1', 'id:idx1']);
      expect(selection.fields.first.isConditional, isTrue);
    });

    test('an unconditional one beside a conditional one wins', () {
      final selection = collect(
        r'user { __typename @include(if: $v) __typename id }',
        'User',
      );
      expect(selection.selectsTypename, isTrue);
      expect(fieldsOf(selection), ['id:idx1']);
    });

    test('a conditional one on an abstract type is always read', () {
      final selection = collect(
        r'node { __typename @include(if: $v) id }',
        'Node',
        field: 'node',
      );
      expect(selection.selectsTypename, isTrue);
      expect(fieldsOf(selection), ['id:idx1']);
    });
  });
}
