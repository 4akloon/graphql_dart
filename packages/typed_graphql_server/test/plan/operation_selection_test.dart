import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/plan/plan_result.dart';

import 'plan_fixture.dart';

void main() {
  final fx = PlanFixture();

  GraphQLError rejected(String text, [String? name]) =>
      switch (fx.result(fx.parse(text), name)) {
        PlanRejected(:final error) => error,
        PlanReady() => fail('expected a request error'),
      };

  String codeOf(GraphQLError error) =>
      (error.extensions!.fields['code']! as JsonString).value;

  test('a lone anonymous operation is chosen without a name', () {
    expect(fx.plan('{ a }').operation.name, isNull);
  });

  test('the operation with the requested name is chosen', () {
    final plan = fx.plan('query One { a } query Two { b }', 'Two');
    expect(plan.operation.name?.value, 'Two');
  });

  test('a document without an operation is GQL322', () {
    final error = rejected('fragment F on Query { a }');
    expect(error.message, 'Must provide an operation.');
    expect(codeOf(error), 'GQL322');
  });

  test('several operations and no name is GQL321', () {
    final error = rejected('query One { a } query Two { b }');
    expect(
      error.message,
      'Must provide operation name if query contains multiple operations.',
    );
    expect(codeOf(error), 'GQL321');
  });

  test('an unknown operation name is GQL320', () {
    final error = rejected('query One { a }', 'Nope');
    expect(error.message, 'Unknown operation named "Nope".');
    expect(codeOf(error), 'GQL320');
  });

  test('a missing root type is GQL323', () {
    final error = rejected('mutation { a }');
    expect(
      error.message,
      'Schema is not configured to execute mutation operation.',
    );
    expect(codeOf(error), 'GQL323');
  });
}
