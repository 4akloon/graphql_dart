import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/execution_port.dart';

// Ported from the two sibling-error tests of graphql-js
// src/execution/__tests__/cancellation-test.ts, which run without an abort
// signal; mapping/execution.csv says why they are adapted. Spec 18.13 of M5:
// the executor waits for the resolvers that already started, so a late
// sibling is still run and its error still reported.
void main() {
  const port = ExecutionPort();

  Future<Map<String, Object?>> runBubbling({
    required Future<String> boom,
    required Future<String> Function() side,
    required bool isSideObject,
    required String text,
  }) async {
    final b = ExecutableSchemaBuilder<Object?>();
    final lateSide = b.object<String>(
      'LateSide',
      fields: (t) => [t.field('value', b.string.nullable).pure((_) => 'late')],
    );
    final parent = b.object<Object?>(
      'Parent',
      fields: (t) => [
        t
            .field('boom', b.string)
            .resolve((parent, args, context, info) => boom),
        if (isSideObject)
          t
              .field('side', lateSide.nullable)
              .resolve((parent, args, context, info) => side())
        else
          t
              .field('side', b.string.nullable)
              .resolve((parent, args, context, info) => side()),
      ],
    );
    final schema = b.build(
      query: b.object<Object?>(
        'Query',
        fields: (t) => [
          t
              .field('parent', parent.nullable)
              .resolve((parent, args, context, info) => Object()),
          t.field('other', b.string.nullable).pure((_) => 'ok'),
        ],
      ),
    );
    return port.withoutCodes(await port.run(schema, text));
  }

  const bubbled = <String, Object?>{
    'data': {'parent': null, 'other': 'ok'},
    'errors': [
      {
        'message': 'boom',
        'locations': [
          {'line': 1, 'column': 12},
        ],
        'path': ['parent', 'boom'],
      },
    ],
  };

  group('Execute: Cancellation', () {
    test('suppresses sibling errors after a non-null error bubbles', () async {
      final boom = Completer<String>();
      final side = Completer<String>();
      final result = runBubbling(
        boom: boom.future,
        side: () => side.future,
        isSideObject: false,
        text: '{ parent { boom side } other }',
      );
      boom.completeError(const GraphQLException('boom'));
      await Future<void>.delayed(Duration.zero);
      side.completeError(const GraphQLException('side'));
      expect(await result, {
        ...bubbled,
        'errors': [
          ...(bubbled['errors']! as List<Object?>),
          {
            'message': 'side',
            'locations': [
              {'line': 1, 'column': 17},
            ],
            'path': ['parent', 'side'],
          },
        ],
      });
    });

    test(
      'should stop late sibling object completion after non-null bubbling returns a response',
      () async {
        final boom = Completer<String>();
        final side = Completer<String>();
        final result = runBubbling(
          boom: boom.future,
          side: () => side.future,
          isSideObject: true,
          text: '{ parent { boom side { value } } other }',
        );
        boom.completeError(const GraphQLException('boom'));
        await Future<void>.delayed(Duration.zero);
        side.complete('late value');
        expect(await result, bubbled);
      },
    );
  });
}
