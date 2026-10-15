import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  late ExecutableSchemaBuilder<Object?> b;

  setUp(() => b = ExecutableSchemaBuilder<Object?>());

  List<Diagnostic> problemsOf(void Function() build) {
    Object? thrown;
    try {
      build();
    } on Object catch (error) {
      thrown = error;
    }
    if (thrown case SchemaBuildError(:final diagnostics)) return diagnostics;
    fail('build did not throw a SchemaBuildError: $thrown');
  }

  group('GQL303', () {
    test('a subscribe source outside the subscription root', () {
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('ticks', b.int)
              .subscribe((parent, args, context, info) => Stream.value(1)),
        ],
      );
      final problems = problemsOf(() => b.build(query: query));
      expect(problems.map((problem) => problem.code), [
        DiagnosticCode.misplacedSubscriptionField,
      ]);
      expect(
        problems.single.message,
        'Field "Query.ticks" has a subscribe source but "Query" is not the '
        'subscription root type.',
      );
    });

    test('a subscription root field without a source', () {
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final subscription = b.object<Object?>(
        'Subscription',
        fields: (t) => [t.field('ticks', b.int).pure((_) => 1)],
      );
      final problems = problemsOf(
        () => b.build(query: query, subscription: subscription),
      );
      expect(problems.map((problem) => problem.code), [
        DiagnosticCode.misplacedSubscriptionField,
      ]);
      expect(
        problems.single.message,
        'Field "Subscription.ticks" of the subscription root type has no '
        'subscribe source: declare it with subscribe or subscribeWith.',
      );
    });

    test('a correct subscription root builds', () {
      final query = b.object<Object?>(
        'Query',
        fields: (t) => [t.field('ok', b.boolean).pure((_) => true)],
      );
      final subscription = b.object<Object?>(
        'Subscription',
        fields: (t) => [
          t
              .field('ticks', b.int)
              .subscribe((parent, args, context, info) => Stream.value(1)),
        ],
      );
      expect(
        () => b.build(query: query, subscription: subscription),
        returnsNormally,
      );
    });
  });
}
