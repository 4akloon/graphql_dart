import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();
  const errorsOf = ExecutionFixture.errorsOf;
  const codeOf = ExecutionFixture.codeOf;

  group('null propagation', () {
    test('a failing nullable field is null with an error', () async {
      final json = await f.json('{ hello fail }');
      expect(json['data'], equals({'hello': 'world', 'fail': null}));
      expect(errorsOf(json), [
        {
          'message': 'Unexpected error.',
          'path': ['fail'],
          'extensions': {'code': 'GQL330'},
        },
      ]);
    });

    test('a failing non-null field nulls the whole data at the root', () async {
      final json = await f.json('{ hello failNonNull }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });

    test('null propagates to the nearest nullable parent', () async {
      final json = await f.json('{ selfNullable { hello } hello }');
      expect(json['data'], equals({'selfNullable': null, 'hello': 'world'}));
    });

    test('null in a non-null field is GQL331 with the field named', () async {
      final json = await f.json('{ forced }');
      expect(json['data'], isNull);
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Cannot return null for non-nullable field Query.forced.',
      );
      expect(codeOf(errorsOf(json).single), 'GQL331');
    });

    test('a codec that encodes null breaks a non-null field', () async {
      final json = await f.json('{ weird }');
      expect(json['data'], isNull);
      expect(codeOf(errorsOf(json).single), 'GQL331');
    });

    test('a failing nullable item leaves the others', () async {
      final json = await f.json('{ items { id maybe } }');
      expect(
        json['data'],
        equals({
          'items': [
            {'id': 1, 'maybe': 'm'},
            {'id': 2, 'maybe': null},
            {'id': 3, 'maybe': 'm'},
          ],
        }),
      );
      expect(
        ((errorsOf(json).single! as Map<String, Object?>)['path']!),
        ['items', 1, 'maybe'],
      );
    });

    test(
      'a failing non-null field in an item nulls the non-null list',
      () async {
        final json = await f.json('{ items { label } }');
        expect(json['data'], isNull);
        expect(
          (errorsOf(json).single! as Map<String, Object?>)['path'],
          ['items', 1, 'label'],
        );
      },
    );

    test('a null item of a nullable item type is null', () async {
      final json = await f.json('{ numbers }');
      expect(
        json['data'],
        equals({
          'numbers': [1, null, 3],
        }),
      );
      expect(json.containsKey('errors'), isFalse);
    });

    test('a non-iterable for a list is GQL335', () async {
      final json = await f.json('{ notAList }');
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['message'],
        'Expected Iterable, but did not find one for field "Query.notAList".',
      );
      expect(codeOf(errorsOf(json).single), 'GQL335');
    });

    test('a lazy iterable that throws is a field error', () async {
      final json = await f.json('{ lazy }');
      expect(json['data'], equals({'lazy': null}));
      expect(codeOf(errorsOf(json).single), 'GQL330');
    });

    test('an async failure of a non-null field propagates', () async {
      final json = await f.json('{ hello failLaterNonNull }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });

    test('an async failure of a nullable field is null', () async {
      final json = await f.json('{ hello failLater }');
      expect(json['data'], equals({'hello': 'world', 'failLater': null}));
    });

    test('siblings after a sync non-null failure are not started', () async {
      final json = await f.json('{ failNonNull fail }');
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });
  });

  group('error behaviour', () {
    const nullValue = ExecutionOptions(errorBehavior: ErrorBehavior.nullValue);

    test('nullValue stops a non-null failure at its field', () async {
      final json = await f.json(
        '{ hello failNonNull }',
        options: nullValue,
      );
      expect(json['data'], equals({'hello': 'world', 'failNonNull': null}));
      expect(errorsOf(json), hasLength(1));
    });

    test('nullValue nulls a non-null violation at its field', () async {
      final json = await f.json('{ forced hello }', options: nullValue);
      expect(json['data'], equals({'forced': null, 'hello': 'world'}));
      expect(codeOf(errorsOf(json).single), 'GQL331');
    });

    test('nullValue keeps the other items of a list', () async {
      final json = await f.json('{ items { id label } }', options: nullValue);
      expect(
        json['data'],
        equals({
          'items': [
            {'id': 1, 'label': 'i'},
            {'id': 2, 'label': null},
            {'id': 3, 'label': 'i'},
          ],
        }),
      );
    });

    test('halt ends with null data and the first error only', () async {
      final json = await f.json(
        '{ fail failNonNull hello }',
        options: const ExecutionOptions(errorBehavior: ErrorBehavior.halt),
      );
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });

    test('halt ignores the errors of async siblings after the first', () async {
      final json = await f.json(
        '{ failLater fail }',
        options: const ExecutionOptions(errorBehavior: ErrorBehavior.halt),
      );
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
      expect(
        (errorsOf(json).single! as Map<String, Object?>)['path'],
        ['fail'],
      );
    });
  });
}
