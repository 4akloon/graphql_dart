import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

class _NumberHolder {
  _NumberHolder(this.theNumber);

  int theNumber;
}

class _Root {
  _Root(int originalNumber) : numberHolder = _NumberHolder(originalNumber);

  final _NumberHolder numberHolder;

  _NumberHolder immediatelyChangeTheNumber(int? newNumber) {
    numberHolder.theNumber = newNumber!;
    return numberHolder;
  }

  Future<_NumberHolder> promiseToChangeTheNumber(int? newNumber) async {
    await Future<void>.delayed(Duration.zero);
    return immediatelyChangeTheNumber(newNumber);
  }

  _NumberHolder failToChangeTheNumber() =>
      throw const GraphQLException('Cannot change the number');

  Future<_NumberHolder> promiseAndFailToChangeTheNumber() async {
    await Future<void>.delayed(Duration.zero);
    throw const GraphQLException('Cannot change the number');
  }
}

// Ported from graphql-js src/execution/__tests__/mutations-test.ts;
// mapping/execution.csv says which tests are adapted or skipped, and why.
void main() {
  const port = ExecutionPort();
  final b = ExecutableSchemaBuilder<Object?>();
  final newNumber = Arg('newNumber', b.int.nullable);
  final numberHolderType = b.object<_NumberHolder>(
    'NumberHolder',
    fields: (t) => [
      t.field('theNumber', b.int.nullable).pure((holder) => holder.theNumber),
      t.field('promiseToGetTheNumber', b.int.nullable).resolve((
        holder,
        args,
        context,
        info,
      ) async {
        await Future<void>.delayed(Duration.zero);
        return holder.theNumber;
      }),
    ],
  );
  final schema = b.build(
    query: b.object<_Root>(
      'Query',
      fields: (t) => [
        t
            .field('numberHolder', numberHolderType.nullable)
            .pure((root) => root.numberHolder),
      ],
    ),
    mutation: b.object<_Root>(
      'Mutation',
      fields: (t) => [
        t
            .field(
              'immediatelyChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) =>
                  root.immediatelyChangeTheNumber(args.get(newNumber)),
            ),
        t
            .field(
              'promiseToChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) =>
                  root.promiseToChangeTheNumber(args.get(newNumber)),
            ),
        t
            .field(
              'failToChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) => root.failToChangeTheNumber(),
            ),
        t
            .field(
              'promiseAndFailToChangeTheNumber',
              numberHolderType.nullable,
              args: [newNumber],
            )
            .resolve(
              (root, args, context, info) =>
                  root.promiseAndFailToChangeTheNumber(),
            ),
      ],
    ),
  );

  group('Execute: Handles mutation execution ordering', () {
    test('evaluates mutations serially', () async {
      final result = await port.json(
        schema,
        '''
      mutation M {
        first: immediatelyChangeTheNumber(newNumber: 1) {
          theNumber
        },
        second: promiseToChangeTheNumber(newNumber: 2) {
          theNumber
        },
        third: immediatelyChangeTheNumber(newNumber: 3) {
          theNumber
        }
        fourth: promiseToChangeTheNumber(newNumber: 4) {
          theNumber
        },
        fifth: immediatelyChangeTheNumber(newNumber: 5) {
          theNumber
        }
      }
    ''',
        options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
      );

      expect(
        result,
        equals({
          'data': {
            'first': {'theNumber': 1},
            'second': {'theNumber': 2},
            'third': {'theNumber': 3},
            'fourth': {'theNumber': 4},
            'fifth': {'theNumber': 5},
          },
        }),
      );
    });

    test('does not include illegal mutation fields in output', () {
      final result = port.payload<Object?>(
        schema,
        'mutation { thisIsIllegalDoNotIncludeMe }',
        context: null,
        options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
      );

      expect(result, isNot(isA<Future<Object?>>()));
      expect(
        port.withoutCodes(result as ResponsePayload),
        equals({'data': <String, Object?>{}}),
      );
    });

    test(
      'evaluates mutations correctly in the presence of a failed mutation',
      () async {
        final result = await port.json(
          schema,
          '''

      mutation M {
        first: immediatelyChangeTheNumber(newNumber: 1) {
          theNumber
        },
        second: promiseToChangeTheNumber(newNumber: 2) {
          theNumber
        },
        third: failToChangeTheNumber(newNumber: 3) {
          theNumber
        }
        fourth: promiseToChangeTheNumber(newNumber: 4) {
          theNumber
        },
        fifth: immediatelyChangeTheNumber(newNumber: 5) {
          theNumber
        }
        sixth: promiseAndFailToChangeTheNumber(newNumber: 6) {
          theNumber
        }
      }
    ''',
          options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
        );

        expect(
          result,
          equals({
            'data': {
              'first': {'theNumber': 1},
              'second': {'theNumber': 2},
              'third': null,
              'fourth': {'theNumber': 4},
              'fifth': {'theNumber': 5},
              'sixth': null,
            },
            'errors': [
              {
                'message': 'Cannot change the number',
                'locations': [
                  {'line': 9, 'column': 9},
                ],
                'path': ['third'],
              },
              {
                'message': 'Cannot change the number',
                'locations': [
                  {'line': 18, 'column': 9},
                ],
                'path': ['sixth'],
              },
            ],
          }),
        );
      },
    );

    test('Mutation inside of a fragment', () async {
      final result = await port.json(
        schema,
        '''
      mutation M {
        ...MutationFragment
        second: immediatelyChangeTheNumber(newNumber: 2) {
          theNumber
        }
      }
      fragment MutationFragment on Mutation {
        first: promiseToChangeTheNumber(newNumber: 1) {
          theNumber
        },
      }
    ''',
        options: ExecutionOptions(rootValue: _Root(6), maskErrors: false),
      );

      expect(
        result,
        equals({
          'data': {
            'first': {'theNumber': 1},
            'second': {'theNumber': 2},
          },
        }),
      );
    });
  });
}
