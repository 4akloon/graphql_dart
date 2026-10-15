import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();
  const errorsOf = ExecutionFixture.errorsOf;

  group('masking', () {
    test('an unexpected error is masked with GQL330', () async {
      final json = await f.json('{ fail }');
      expect(errorsOf(json).single, {
        'message': 'Unexpected error.',
        'path': ['fail'],
        'extensions': {'code': 'GQL330'},
      });
    });

    test('maskErrors false shows the error text', () async {
      final json = await f.json(
        '{ failNonNull hello }',
        options: const ExecutionOptions(
          maskErrors: false,
          errorBehavior: ErrorBehavior.nullValue,
        ),
      );
      final error = errorsOf(json).single! as Map<String, Object?>;
      expect(error['message'], contains('secret detail'));
    });

    test('a GraphQLException reaches the client as it is', () async {
      final json = await f.json('{ exception }');
      expect(errorsOf(json).single, {
        'message': 'custom',
        'path': ['exception'],
        'extensions': {'k': 'v'},
      });
    });

    test('an async failure is masked too', () async {
      final json = await f.json('{ failLater }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Unexpected error.',
      );
    });
  });

  group('onError', () {
    test(
      'sees the raw error, its stack trace and the reported error',
      () async {
        final seen = <(Object, StackTrace, GraphQLError)>[];
        await f.json(
          '{ fail }',
          options: ExecutionOptions(
            onError: (error, stackTrace, reported) {
              seen.add((error, stackTrace, reported));
              return null;
            },
          ),
        );
        expect(seen, hasLength(1));
        expect(seen.single.$1, isA<StateError>());
        expect(seen.single.$3.message, 'Unexpected error.');
      },
    );

    test('a replacement is recorded instead', () async {
      final json = await f.json(
        '{ fail }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) =>
              GraphQLError('replaced', path: reported.path),
        ),
      );
      expect(errorsOf(json).single, {
        'message': 'replaced',
        'path': ['fail'],
      });
    });

    test('a throwing hook records the masked error', () async {
      final json = await f.json(
        '{ exception }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) => throw StateError('hook'),
        ),
      );
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Unexpected error.',
      );
    });

    test('is called for an async failure', () async {
      var calls = 0;
      await f.json(
        '{ failLater }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            calls++;
            return null;
          },
        ),
      );
      expect(calls, 1);
    });

    test('is not called for the library own errors', () async {
      var calls = 0;
      await f.json(
        '{ forced }',
        options: ExecutionOptions(
          onError: (error, stackTrace, reported) {
            calls++;
            return null;
          },
        ),
      );
      expect(calls, 0);
    });
  });

  group('locations', () {
    test('are given with the source', () async {
      const text = '{\n  fail\n}';
      final json = await f.json(
        text,
        options: ExecutionOptions(source: Source(text)),
      );
      expect((errorsOf(json).single! as Map<String, Object?>)['locations'], [
        {'line': 2, 'column': 3},
      ]);
    });

    test('of an invalid argument value are those of the value', () async {
      const text = '{\n  greet(name: null)\n}';
      final json = await f.json(
        text,
        options: ExecutionOptions(source: Source(text)),
      );
      expect((errorsOf(json).single! as Map<String, Object?>)['locations'], [
        {'line': 2, 'column': 15},
      ]);
    });

    test('are absent without the source', () async {
      final json = await f.json('{ fail }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>).containsKey(
          'locations',
        ),
        isFalse,
      );
    });
  });

  group('leaf values', () {
    test('an Int past 32 bits is GQL332', () async {
      final json = await f.json('{ overflow }');
      expect(json['data'], equals({'overflow': null}));
      expect(errorsOf(json).single, {
        'message':
            'Int cannot represent non 32-bit signed integer value: 3000000000',
        'path': ['overflow'],
        'extensions': {'code': 'GQL332'},
      });
    });

    test('a Float that is not finite is GQL332', () async {
      final json = await f.json('{ nan }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Float cannot represent non numeric value: NaN',
      );
    });

    test('an enum value the schema does not declare is GQL332', () async {
      final json = await f.json('{ mood }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Enum "Mood" cannot represent value: Mood.sad',
      );
    });
  });

  group('abstract types', () {
    test('an interface value resolves to the first accepting type', () async {
      expect(
        await f.json(
          '{ pet { name } found { ... on Dog { name } ... on Cat { name } } }',
        ),
        equals({
          'data': {
            'pet': {'name': 'rex'},
            'found': [
              {'name': 'rex'},
              {'name': 'tom'},
            ],
          },
        }),
      );
    });
  });
}
