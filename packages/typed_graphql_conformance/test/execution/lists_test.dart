import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';
import '../support/list_field_schema.dart';
import '../support/unchecked_ref.dart';

// An iterable that counts how often its iterator is advanced, standing in for
// the hand-written JavaScript iterators of the graphql-js tests.
class _CountingIterable extends Iterable<Object?> {
  _CountingIterable(this._step);

  final ({bool isDone, Object? value}) Function(int call) _step;

  int calls = 0;

  @override
  Iterator<Object?> get iterator => _CountingIterator(this);
}

class _CountingIterator implements Iterator<Object?> {
  _CountingIterator(this._owner);

  final _CountingIterable _owner;

  Object? _current;

  @override
  Object? get current => _current;

  @override
  bool moveNext() {
    _owner.calls++;
    final step = _owner._step(_owner.calls);
    if (step.isDone) {
      return false;
    }
    _current = step.value;
    return true;
  }
}

class _Indexed {
  const _Indexed(this.index);

  final int index;
}

// Ported from graphql-js src/execution/__tests__/lists-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  const schemas = ListFieldSchema();
  const listOfString = ListType(NamedType(Name('String')));
  const listOfInt = ListType(NamedType(Name('Int')));
  const listOfNonNullInt = ListType(NonNullType(NamedType(Name('Int'))));
  const nullBubbled = {
    'message': 'Cannot return null for non-nullable field Query.listField.',
    'locations': [
      {'line': 1, 'column': 3},
    ],
    'path': ['listField', 1],
  };

  Map<String, Object?> badAtListField(String message) => {
    'data': {'listField': null},
    'errors': [
      {
        'message': message,
        'locations': [
          {'line': 1, 'column': 3},
        ],
        'path': ['listField'],
      },
    ],
  };

  Future<Map<String, Object?>> complete(
    Object? Function() read, {
    TypeRef type = listOfString,
    String scalarName = 'String',
  }) => port.json(
    schemas.build(type, read, scalarName: scalarName),
    '{ listField }',
  );

  Future<void> delayedReject(String message) async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    throw GraphQLException(message);
  }

  group('Execute: Accepts any iterable as list value', () {
    // graphql-js's executeSync: the response must not wait.
    Map<String, Object?> completeSync(Object? listField) {
      final result = port.payload<Object?>(
        schemas.build(listOfString, () => listField, scalarName: 'String'),
        '{ listField }',
        context: null,
      );
      expect(result, isNot(isA<Future<Object?>>()));
      return port.withoutCodes(result as ResponsePayload);
    }

    test('Accepts a Set as a List value', () {
      const items = ['apple', 'banana', 'apple', 'coconut'];
      final listField = {...items};

      expect(
        completeSync(listField),
        equals({
          'data': {
            'listField': ['apple', 'banana', 'coconut'],
          },
        }),
      );
    });

    test('Accepts a Generator function as a List value', () {
      Iterable<String> listField() sync* {
        yield 'one';
        yield '2';
        yield 'true';
      }

      expect(
        completeSync(listField()),
        equals({
          'data': {
            'listField': ['one', '2', 'true'],
          },
        }),
      );
    });

    test('Does not accept (Iterable) String-literal as a List value', () {
      expect(
        completeSync('Singular'),
        equals(
          badAtListField(
            'Expected Iterable, but did not find one for field '
            '"Query.listField".',
          ),
        ),
      );
    });

    test('Does not call iterator `return` when iteration throws', () {
      final listField = _CountingIterable(
        (call) => call == 1
            ? throw const GraphQLException('bad')
            : (isDone: true, value: null),
      );

      expect(completeSync(listField), equals(badAtListField('bad')));
      expect(listField.calls, 1);
    });
  });

  group('Execute: Handles abrupt completion in synchronous iterables', () {
    test('drains the iterator when `next` throws', () async {
      final listField = _CountingIterable(
        (call) => switch (call) {
          1 => (isDone: false, value: 'ok'),
          2 => throw const GraphQLException('bad'),
          _ => (isDone: true, value: null),
        },
      );

      expect(await complete(() => listField), equals(badAtListField('bad')));
      expect(listField.calls, 2);
    });

    test(
      'drains the iterator when a null bubbles up from a non-null item',
      () async {
        const values = [1, null, 2];
        final listField = _CountingIterable(
          (call) => call > values.length
              ? (isDone: true, value: null)
              : (isDone: false, value: values[call - 1]),
        );

        expect(
          await complete(
            () => listField,
            type: listOfNonNullInt,
            scalarName: 'Int',
          ),
          equals({
            'data': {'listField': null},
            'errors': [nullBubbled],
          }),
        );
        expect(listField.calls, 2);
      },
    );
  });

  group('Execute: Accepts async iterables as list value', () {
    Future<Map<String, Object?>> completeObjectList(
      FutureOr<String> Function(_Indexed item) resolve, {
      bool isNonNullable = false,
    }) {
      final b = ExecutableSchemaBuilder<Object?>();
      final wrapper = b.object<_Indexed>(
        'ObjectWrapper',
        fields: (t) => [
          t
              .field('index', b.string)
              .resolve((item, args, context, info) => resolve(item)),
        ],
      );
      const wrapperType = NamedType(Name('ObjectWrapper'));
      final schema = b.build(
        query: b.object<Object?>(
          'Query',
          fields: (t) => [
            t
                .field(
                  'listField',
                  UncheckedRef(
                    ListType(
                      isNonNullable
                          ? const NonNullType(wrapperType)
                          : wrapperType,
                    ),
                    wrapper,
                  ),
                )
                .pure((_) => const [_Indexed(0), _Indexed(1), _Indexed(2)]),
          ],
        ),
      );
      return port.json(schema, '{ listField { index } }');
    }

    test('Handles promises from `completeValue` in AsyncIterables', () async {
      expect(
        await completeObjectList((item) => Future.value('${item.index}')),
        equals({
          'data': {
            'listField': [
              {'index': '0'},
              {'index': '1'},
              {'index': '2'},
            ],
          },
        }),
      );
    });

    test(
      'Handles rejected promises from `completeValue` in AsyncIterables',
      () async {
        expect(
          await completeObjectList((item) {
            if (item.index == 2) {
              return Future.error(const GraphQLException('bad'));
            }
            return Future.value('${item.index}');
          }),
          equals({
            'data': {
              'listField': [
                {'index': '0'},
                {'index': '1'},
                null,
              ],
            },
            'errors': [
              {
                'message': 'bad',
                'locations': [
                  {'line': 1, 'column': 15},
                ],
                'path': ['listField', 2, 'index'],
              },
            ],
          }),
        );
      },
    );

    test(
      'handles mixture of sync and async errors in AsyncIterables',
      () async {
        final uncaught = <Object>[];
        final result = await runZonedGuarded(
          () => completeObjectList((item) {
            if (item.index == 0) {
              return delayedReject('bad').then((_) => 'x');
            }
            throw const GraphQLException('also bad');
          }, isNonNullable: true),
          (error, stackTrace) => uncaught.add(error),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          result,
          equals({
            'data': {'listField': null},
            'errors': [
              {
                'message': 'also bad',
                'locations': [
                  {'line': 1, 'column': 15},
                ],
                'path': ['listField', 1, 'index'],
              },
              // The executor waits for the resolver that had started, so its
              // late error is in the response (graphql-js drops it).
              {
                'message': 'bad',
                'locations': [
                  {'line': 1, 'column': 15},
                ],
                'path': ['listField', 0, 'index'],
              },
            ],
          }),
        );
        expect(uncaught, isEmpty);
      },
    );

    test('Handles nulls yielded by async generator', () async {
      Iterable<int?> listField() sync* {
        yield 1;
        yield null;
        yield 2;
      }

      Future<Map<String, Object?>> run(TypeRef type) =>
          complete(listField, type: type, scalarName: 'Int');

      expect(
        await run(listOfInt),
        equals({
          'data': {
            'listField': [1, null, 2],
          },
        }),
      );
      expect(
        await run(const NonNullType(listOfInt)),
        equals({
          'data': {
            'listField': [1, null, 2],
          },
        }),
      );
      expect(
        await run(listOfNonNullInt),
        equals({
          'data': {'listField': null},
          'errors': [nullBubbled],
        }),
      );
      expect(
        await run(const NonNullType(listOfNonNullInt)),
        equals({
          'data': null,
          'errors': [nullBubbled],
        }),
      );
    });
  });
}
