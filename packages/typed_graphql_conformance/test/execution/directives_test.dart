import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/directives-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final schema = b.build(
    query: b.object<Object?>(
      'TestType',
      fields: (t) => [
        t.field('a', b.string.nullable).pure((_) => 'a'),
        t.field('b', b.string.nullable).pure((_) => 'b'),
      ],
    ),
  );
  const both = {'a': 'a', 'b': 'b'};
  const onlyA = {'a': 'a'};

  group('Execute: handles directives', () {
    group('works without directives', () {
      test('basic query works', () async {
        expect(
          await port.json(schema, '{ a, b }'),
          {'data': both},
        );
      });
    });

    group('works on scalars', () {
      test('if true includes scalar', () async {
        expect(
          await port.json(schema, '{ a, b @include(if: true) }'),
          {'data': both},
        );
      });

      test('if false omits on scalar', () async {
        expect(
          await port.json(schema, '{ a, b @include(if: false) }'),
          {'data': onlyA},
        );
      });

      test('unless false includes scalar', () async {
        expect(
          await port.json(schema, '{ a, b @skip(if: false) }'),
          {'data': both},
        );
      });

      test('unless true omits scalar', () async {
        expect(
          await port.json(schema, '{ a, b @skip(if: true) }'),
          {'data': onlyA},
        );
      });
    });

    group('works on fragment spreads', () {
      test('if false omits fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @include(if: false)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': onlyA},
        );
      });

      test('if true includes fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @include(if: true)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': both},
        );
      });

      test('unless false includes fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @skip(if: false)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': both},
        );
      });

      test('unless true omits fragment spread', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ...Frag @skip(if: true)
        }
        fragment Frag on TestType {
          b
        }
      '''),
          {'data': onlyA},
        );
      });
    });

    group('works on inline fragment', () {
      test('if false omits inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @include(if: false) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });

      test('if true includes inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @include(if: true) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless false includes inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @skip(if: false) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless true includes inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... on TestType @skip(if: true) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });
    });

    group('works on anonymous inline fragment', () {
      test('if false omits anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... @include(if: false) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });

      test('if true includes anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... @include(if: true) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless false includes anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query Q {
          a
          ... @skip(if: false) {
            b
          }
        }
      '''),
          {'data': both},
        );
      });

      test('unless true includes anonymous inline fragment', () async {
        expect(
          await port.json(schema, '''
        query {
          a
          ... @skip(if: true) {
            b
          }
        }
      '''),
          {'data': onlyA},
        );
      });
    });

    group('works with skip and include directives', () {
      test('include and no skip', () async {
        expect(
          await port.json(schema, '''
        {
          a
          b @include(if: true) @skip(if: false)
        }
      '''),
          {'data': both},
        );
      });

      test('include and skip', () async {
        expect(
          await port.json(schema, '''
        {
          a
          b @include(if: true) @skip(if: true)
        }
      '''),
          {'data': onlyA},
        );
      });

      test('no include or skip', () async {
        expect(
          await port.json(schema, '''
        {
          a
          b @include(if: false) @skip(if: false)
        }
      '''),
          {'data': onlyA},
        );
      });
    });
  });
}
