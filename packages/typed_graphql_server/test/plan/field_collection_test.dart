import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/coercion/coercion_result.dart';
import 'package:typed_graphql_server/src/plan/field_plan.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';

import 'plan_fixture.dart';

void main() {
  final fx = PlanFixture();

  group('collection', () {
    test('keeps the order of first appearance and merges by response key', () {
      final node = fx.root('{ b a: a c b: a b }');
      expect(fx.keys(node), ['b', 'a', 'c']);
      expect(node.fields.first.nodes, hasLength(3));
    });

    test('merges the nodes of one key across fragments', () {
      final node = fx.root('{ a ...F a } fragment F on Query { a b }');
      expect(fx.keys(node), ['a', 'b']);
      expect(node.fields.first.nodes, hasLength(3));
    });

    test('an alias is the response key and the field name stays', () {
      final plan = fx.root('{ x: a }').fields.single;
      expect(plan.responseKey, 'x');
      expect(plan.fieldName, 'a');
      expect(plan.field?.name, 'a');
    });

    test('__typename has no schema field', () {
      expect(fx.root('{ __typename }').fields.single.field, isNull);
    });
  });

  group('skip and include', () {
    test('literals drop and keep fields', () {
      final node = fx.root(
        '{ a @skip(if: true) b @skip(if: false) c @include(if: false) '
        'a @include(if: true) }',
      );
      expect(fx.keys(node), ['b', 'a']);
    });

    test('variables decide per request', () {
      const text = r'query ($v: Boolean!) { a @skip(if: $v) b }';
      expect(fx.keys(fx.root(text, {'v': true})), ['b']);
      expect(fx.keys(fx.root(text, {'v': false})), ['a', 'b']);
    });

    test('skip wins over include', () {
      expect(
        fx.root('{ a @skip(if: true) @include(if: true) b }').fields,
        hasLength(1),
      );
    });

    test('a skipped fragment spread and inline fragment drop their fields', () {
      final node = fx.root(
        '{ ...F @skip(if: true) ... @include(if: false) { c } b } '
        'fragment F on Query { a }',
      );
      expect(fx.keys(node), ['b']);
    });

    test('variables in fragments are condition variables', () {
      final plan = fx.plan(
        r'query ($v: Boolean!, $w: Boolean!) { ...F } '
        r'fragment F on Query { a @skip(if: $v) ... @include(if: $w) { b } }',
      );
      expect(plan.conditionVariables, ['v', 'w']);
    });

    test('a variable without a boolean is a problem of the node', () {
      final node = fx.root(r'query ($v: Boolean) { a @skip(if: $v) }');
      expect(node.fields, isEmpty);
      expect(node.problem?.message, contains('@skip(if:)'));
    });
  });

  group('type conditions', () {
    final dog = fx.objectType('Dog');
    final cat = fx.objectType('Cat');

    test('a fragment on an interface applies to its implementations', () {
      final field = fx
          .root('{ pet { ...P } } fragment P on Pet { name }')
          .fields
          .single;
      expect(fx.keys(field.childFor(dog)), ['name']);
    });

    test('a fragment on another object type does not apply', () {
      final field = fx
          .root('{ pet { ... on Cat { meows } name } }')
          .fields
          .single;
      expect(fx.keys(field.childFor(dog)), ['name']);
      expect(fx.keys(field.childFor(cat)), ['meows', 'name']);
    });

    test('fragments on a union apply to its members', () {
      final field = fx
          .root(
            '{ found { ... on Found { __typename } ... on Dog { barks } } }',
          )
          .fields
          .single;
      expect(fx.keys(field.childFor(cat)), ['__typename']);
      expect(fx.keys(field.childFor(dog)), ['__typename', 'barks']);
    });

    test('the child node is the same object for the same type', () {
      final field = fx.root('{ pet { name } }').fields.single;
      expect(field.childFor(dog), same(field.childFor(dog)));
      expect(field.childFor(dog), isNot(same(field.childFor(cat))));
    });

    test('the selection sets of merged nodes are collected together', () {
      final field = fx.root('{ pet { name } pet { barks } }').fields.single;
      expect(fx.keys(field.childFor(fx.objectType('Dog'))), ['name', 'barks']);
    });
  });

  group('fragments', () {
    test('a fragment spread twice is collected once', () {
      final node = fx.root('{ ...F ...F } fragment F on Query { a }');
      expect(node.fields.single.nodes, hasLength(1));
    });

    test('a fragment reached by two routes is collected once', () {
      final node = fx.root(
        '{ ...A ...B } fragment A on Query { ...C } '
        'fragment B on Query { ...C } fragment C on Query { a }',
      );
      expect(node.fields.single.nodes, hasLength(1));
    });

    test('an unknown fragment adds nothing', () {
      expect(fx.keys(fx.root('{ ...Nope a }')), ['a']);
    });

    test('a fan-out of 2^20 spreads is planned in linear time', () {
      const depth = 20;
      final text = StringBuffer('{ ...F0 }');
      for (var i = 0; i < depth; i++) {
        text.write(
          'fragment F$i on Query { f$i: a ...F${i + 1} ...F${i + 1} }',
        );
      }
      text.write('fragment F$depth on Query { f$depth: a }');
      final stopwatch = Stopwatch()..start();
      final node = fx.root(text.toString());
      stopwatch.stop();
      expect(node.fields, hasLength(depth + 1));
      expect(
        [for (final field in node.fields) field.nodes.length],
        everyElement(1),
        reason: 'each fragment was expanded once, not 2^20 times',
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('a deeply nested selection does not overflow the stack', () {
      // Built by hand: the parser bounds nesting by `maxDepth`.
      var selectionSet = SelectionSet([Field(null, const Name('a'))]);
      for (var i = 0; i < 20000; i++) {
        selectionSet = SelectionSet([InlineFragment(null, selectionSet)]);
      }
      final document = Document([
        OperationDefinition(OperationType.query, selectionSet),
      ]);
      final plan = switch (fx.result(document)) {
        PlanReady(:final plan) => plan,
        PlanRejected() => fail('expected a plan'),
      };
      expect(fx.keys(plan.rootFor(plan.keyFor(const <String, Object?>{}))), [
        'a',
      ]);
    });
  });

  group('defer', () {
    test('fields of a deferred fragment are deferred', () {
      final node = fx.root('{ a ... @defer { b } }');
      expect([for (final f in node.fields) f.isDeferred], [false, true]);
    });

    test('a field also written outside the fragment is not deferred', () {
      final node = fx.root('{ ... @defer { a } a }');
      expect(node.fields.single.isDeferred, isFalse);
    });

    test('if: false does not defer', () {
      final node = fx.root('{ ... @defer(if: false) { a } }');
      expect(node.fields.single.isDeferred, isFalse);
    });

    test('a variable if is part of the key', () {
      const text = r'query ($d: Boolean!) { ... @defer(if: $d) { a } }';
      expect(fx.root(text, {'d': true}).fields.single.isDeferred, isTrue);
      expect(fx.root(text, {'d': false}).fields.single.isDeferred, isFalse);
    });

    test('a spread nested in a deferred fragment is deferred', () {
      final node = fx.root('{ ... @defer { ...F } } fragment F on Query { a }');
      expect(node.fields.single.isDeferred, isTrue);
    });
  });

  group('arguments', () {
    List<Object?> valuesOf(FieldPlan plan, [Map<String, Object?>? variables]) =>
        switch (plan.argumentsFor(variables ?? const {})) {
          CoercionSuccess(value: final Map<String, Object?> map) => [
            for (final entry in map.entries) '${entry.key}=${entry.value}',
          ],
          CoercionSuccess() => fail('a map'),
          CoercionFailure(:final problems) => [problems.single.message],
        };

    test('constant arguments are coerced', () {
      final plan = fx.root('{ user(id: 3) }').fields.single;
      expect(valuesOf(plan), ['id=3']);
    });

    test('constant arguments are coerced once', () {
      final plan = fx.root('{ user(id: 3) }').fields.single;
      expect(plan.argumentsFor(const {}), same(plan.argumentsFor(const {})));
    });

    test('a constant failure is the problem and is remembered', () {
      final plan = fx.root('{ user }').fields.single;
      expect(valuesOf(plan), [
        'Argument "Query.user(id:)" of required type "Int!" was not provided.',
      ]);
      expect(plan.argumentsFor(const {}), same(plan.argumentsFor(const {})));
    });

    test('arguments with variables are coerced for each request', () {
      final plan = fx.root(r'query ($i: Int!) { user(id: $i) }').fields.single;
      expect(valuesOf(plan, {'i': 1}), ['id=1']);
      expect(valuesOf(plan, {'i': 2}), ['id=2']);
    });

    test('a field with no arguments gets none', () {
      expect(valuesOf(fx.root('{ a }').fields.single), isEmpty);
    });

    test('__typename gets none', () {
      expect(valuesOf(fx.root('{ __typename }').fields.single), isEmpty);
    });
  });
}
