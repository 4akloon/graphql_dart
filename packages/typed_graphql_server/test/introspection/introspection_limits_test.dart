import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'introspection_fixture.dart';

void main() {
  List<String> codesOf(Map<String, Object?> json) => [
    for (final error in (json['errors'] ?? const <Object?>[]) as List<Object?>)
      ((error! as Map<String, Object?>)['extensions']!
              as Map<String, Object?>)['code']!
          as String,
  ];

  // `fields { type {` repeated: the types of the fixture refer to each other,
  // so the walk branches at every level.
  String cyclicQuery(int levels) =>
      '{ __schema { types { ${'fields { type { ' * levels}name'
      '${' } }' * levels} } } }';

  test(
    'global middleware skips introspection and wraps other fields',
    () async {
      final seen = <String>[];
      final fixture = IntrospectionFixture(
        middleware: [
          (next, site) => (parent, args, context, info) {
            seen.add(site.field.name);
            return next(parent, args, context, info);
          },
        ],
      );
      final json = await fixture.json(
        '{ search { __typename } __schema { queryType { name } } '
        '__type(name: "Account") { fields { name } } }',
      );
      expect(json['errors'], isNull);
      expect(seen, ['search']);
    },
  );

  group('hostile queries', () {
    final fixture = IntrospectionFixture();

    test('a deep walk over cyclic types ends with GQL336', () async {
      final json = await fixture.json(
        cyclicQuery(4),
        options: const ExecutionOptions(maxDepth: 6),
      );
      expect(codesOf(json), contains('GQL336'));
    });

    test('a branching walk is stopped by maxSteps with GQL337', () async {
      final json = await fixture.json(
        cyclicQuery(60),
        options: const ExecutionOptions(maxSteps: 5000),
      );
      expect(codesOf(json), ['GQL337']);
      expect(json['data'], isNull);
    });

    test('an ofType chain 300 levels deep ends without error', () async {
      final json = await fixture.json(
        '{ __schema { types { fields { type { ${'ofType { ' * 300}name'
        '${' }' * 300} } } } } }',
      );
      expect(json['errors'], isNull);
    });
  });
}
