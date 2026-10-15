import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/plan/condition_key.dart';
import 'package:typed_graphql_server/src/plan/lru_map.dart';
import 'package:typed_graphql_server/src/plan/operation_plan.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';

import 'plan_fixture.dart';

void main() {
  OperationPlan planned(PlanFixture fx, Document document, [String? name]) =>
      switch (fx.result(document, name)) {
        PlanReady(:final plan) => plan,
        PlanRejected() => fail('expected a plan'),
      };

  group('PlanCache', () {
    test('the same document and name give the same plan', () {
      final fx = PlanFixture();
      final document = fx.parse('{ a }');
      expect(planned(fx, document), same(planned(fx, document)));
      expect(fx.cache.hitCount, 1);
      expect(fx.cache.missCount, 1);
    });

    test('an equal document that is another object has its own plan', () {
      final fx = PlanFixture();
      expect(
        planned(fx, fx.parse('{ a }')),
        isNot(same(planned(fx, fx.parse('{ a }')))),
      );
    });

    test('the operation name is part of the key', () {
      final fx = PlanFixture();
      final document = fx.parse('query One { a } query Two { b }');
      expect(
        planned(fx, document, 'One'),
        isNot(same(planned(fx, document, 'Two'))),
      );
    });

    test('a request error is not cached', () {
      final fx = PlanFixture();
      fx.result(fx.parse('{ a }'), 'Nope');
      expect(fx.cache.length, 0);
    });

    test('the least recently used plan is evicted', () {
      final fx = PlanFixture(planCacheSize: 2);
      final first = fx.parse('{ a }');
      final second = fx.parse('{ b }');
      final third = fx.parse('{ c }');
      final firstPlan = planned(fx, first);
      planned(fx, second);
      planned(fx, first); // a hit makes `second` the oldest
      planned(fx, third);
      expect(planned(fx, first), same(firstPlan));
      final missesBefore = fx.cache.missCount;
      planned(fx, second);
      expect(fx.cache.missCount, missesBefore + 1);
      expect(fx.cache.length, 2);
    });

    test('a size of zero keeps no plan', () {
      final fx = PlanFixture(planCacheSize: 0);
      final document = fx.parse('{ a }');
      expect(planned(fx, document), isNot(same(planned(fx, document))));
    });
  });

  group('LruMap', () {
    test('contains does not count as a use', () {
      final map = LruMap<int, String>(2)
        ..store(1, 'one')
        ..store(2, 'two');
      expect(map.contains(1), isTrue);
      map.store(3, 'three');
      expect(map.contains(1), isFalse);
      expect(map.contains(2), isTrue);
    });
  });

  group('condition keys', () {
    test('equal booleans give equal keys', () {
      expect(ConditionKey([true, null]), ConditionKey([true, null]));
      expect(
        ConditionKey([true, null]).hashCode,
        ConditionKey([true, null]).hashCode,
      );
      expect(ConditionKey([true]), isNot(ConditionKey([false])));
      expect(ConditionKey([true]), isNot(ConditionKey([true, true])));
    });

    test('the root node is memoised per key', () {
      final fx = PlanFixture();
      final plan = fx.plan(r'query ($v: Boolean!) { a @skip(if: $v) b }');
      final yes = plan.keyFor({'v': true});
      final no = plan.keyFor({'v': false});
      expect(plan.rootFor(yes), same(plan.rootFor(yes)));
      expect(plan.rootFor(yes), isNot(same(plan.rootFor(no))));
    });

    test('a plan remembers at most 16 keys, least recently used first', () {
      final fx = PlanFixture();
      final names = [for (var i = 0; i < 17; i++) 'v$i'];
      final plan = fx.plan(
        'query (${[for (final n in names) '\$$n: Boolean!'].join(', ')}) '
        '{ ${[for (final n in names) 'a @skip(if: \$$n)'].join(' ')} }',
      );
      ConditionKey keyWith(int index) => plan.keyFor({
        for (var i = 0; i < names.length; i++) names[i]: i == index,
      });
      final first = plan.rootFor(keyWith(0));
      for (var i = 1; i < OperationPlan.maxConditionKeys; i++) {
        plan.rootFor(keyWith(i));
      }
      expect(plan.rootFor(keyWith(0)), same(first));
      final second = plan.rootFor(keyWith(1));
      plan.rootFor(keyWith(16)); // evicts the oldest, which is key 2
      expect(plan.rootFor(keyWith(0)), same(first));
      expect(plan.rootFor(keyWith(1)), same(second));
    });
  });
}
