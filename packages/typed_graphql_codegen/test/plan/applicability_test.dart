import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/plan/applicability.dart';
import 'package:typed_graphql_codegen/src/plan/type_condition_match.dart';

import '../support/plan_fixture.dart';
import 'plan_schema.dart';

void main() {
  final fixture = PlanFixture(planSchema, planNoop);
  final applicability = Applicability(fixture.schema);

  TypeConditionMatch match(String condition, String parent) =>
      applicability.match(condition, fixture.type(parent));

  group('object parent', () {
    test('applies for itself', () {
      expect(match('User', 'User'), TypeConditionMatch.applies);
    });

    test('applies for an interface it implements', () {
      expect(match('Node', 'User'), TypeConditionMatch.applies);
    });

    test('applies for a union it belongs to', () {
      expect(match('Actor', 'User'), TypeConditionMatch.applies);
    });

    test('never for another object', () {
      expect(match('Bot', 'User'), TypeConditionMatch.never);
    });

    test('never for an interface it does not implement', () {
      expect(match('Entity', 'User'), TypeConditionMatch.never);
    });

    test('never for a union it is not in', () {
      expect(match('Thing', 'Bot'), TypeConditionMatch.never);
    });
  });

  group('interface parent', () {
    test('applies for itself', () {
      expect(match('Node', 'Node'), TypeConditionMatch.applies);
    });

    test('applies for an interface it implements', () {
      expect(match('Node', 'Entity'), TypeConditionMatch.applies);
    });

    test('narrows for an implementer', () {
      expect(match('User', 'Node'), TypeConditionMatch.narrows);
    });

    test('narrows for a sibling interface with common implementers', () {
      expect(match('Named', 'Node'), TypeConditionMatch.narrows);
    });

    test('narrows for an interface that implements it', () {
      expect(match('Entity', 'Node'), TypeConditionMatch.narrows);
    });

    test('never for an interface with no common implementer', () {
      expect(match('Entity', 'Named'), TypeConditionMatch.never);
    });
  });

  group('union parent', () {
    test('applies for itself', () {
      expect(match('Actor', 'Actor'), TypeConditionMatch.applies);
    });

    test('narrows for a member', () {
      expect(match('User', 'Actor'), TypeConditionMatch.narrows);
    });

    test('narrows for an interface all its members implement', () {
      expect(match('Node', 'Actor'), TypeConditionMatch.narrows);
    });

    test('narrows for an interface some members implement', () {
      expect(match('Named', 'Actor'), TypeConditionMatch.narrows);
    });

    test('never for a disjoint object', () {
      expect(match('Group', 'Actor'), TypeConditionMatch.never);
    });
  });

  test('reach lists the parent types the condition covers, in order', () {
    expect(
      [
        for (final type in applicability.reach('Named', fixture.type('Node')))
          type.name,
      ],
      ['User'],
    );
  });

  test('reach of a union condition within a union parent', () {
    expect(
      [
        for (final type in applicability.reach('Thing', fixture.type('Actor')))
          type.name,
      ],
      ['User'],
    );
  });

  test('reach of an unknown condition is empty', () {
    expect(applicability.reach('Nope', fixture.type('Node')), isEmpty);
  });
}
