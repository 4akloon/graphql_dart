import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/execution/pending_values.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'execution_fixture.dart';

void main() {
  final f = ExecutionFixture();
  const errorsOf = ExecutionFixture.errorsOf;
  const codeOf = ExecutionFixture.codeOf;

  group('mutations', () {
    test('root fields run one after another', () async {
      final context = Ctx();
      final json = await f.json(
        'mutation { first second third }',
        context: context,
      );
      expect(context.log, ['first', 'second', 'third']);
      expect(
        json['data'],
        equals({'first': 'first', 'second': 'second', 'third': 'third'}),
      );
    });

    test('queries start async fields together', () async {
      final context = Ctx();
      final result = f.run('{ slow quick }', context: context);
      expect(result, isA<Future<Object?>>());
      await result;
    });

    test('a failing non-null mutation field stops the next', () async {
      final context = Ctx();
      final json = await f.json(
        'mutation { boom second }',
        context: context,
      );
      expect(context.log, ['boom']);
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
    });
  });

  group('limits', () {
    test('maxDepth ends a branch with GQL336', () async {
      final json = await f.json(
        '{ self { self { self { hello } } } }',
        options: const ExecutionOptions(maxDepth: 3),
      );
      expect(codeOf(errorsOf(json).single), 'GQL336');
      expect(json['data'], isNull);
    });

    test('a query within maxDepth is unaffected', () async {
      final json = await f.json(
        '{ self { self { hello } } }',
        options: const ExecutionOptions(maxDepth: 3),
      );
      expect(json.containsKey('errors'), isFalse);
    });

    test('maxDepth counts list levels', () async {
      final json = await f.json(
        '{ strings }',
        options: const ExecutionOptions(maxDepth: 1),
      );
      expect(codeOf(errorsOf(json).first), 'GQL336');
    });

    test('a list that is too deep reports once, not per item', () async {
      final json = await f.json(
        '{ numbers }',
        options: const ExecutionOptions(maxDepth: 1),
      );
      expect(errorsOf(json), hasLength(1));
      expect(codeOf(errorsOf(json).single), 'GQL336');
      expect(json['data'], {'numbers': null});
    });

    test('maxSteps halts with GQL337 and null data', () async {
      final json = await f.json(
        '{ hello strings }',
        options: const ExecutionOptions(maxSteps: 2),
      );
      expect(json['data'], isNull);
      expect(errorsOf(json), hasLength(1));
      expect(codeOf(errorsOf(json).single), 'GQL337');
    });
  });

  group('PendingValues', () {
    test('builds at once when nothing is pending', () {
      final pending = PendingValues()
        ..add(JsonNumber(1))
        ..add(JsonNumber(2));
      final result = pending.finishWith(JsonArray.new);
      expect(result, isNot(isA<Future<Object?>>()));
      expect(result, JsonArray([JsonNumber(1), JsonNumber(2)]));
    });

    test('chains one pending value', () async {
      final pending = PendingValues()
        ..add(JsonNumber(1))
        ..add(Future<JsonValue?>.value(JsonNumber(2)));
      final result = pending.finishWith(JsonArray.new);
      expect(result, isA<Future<Object?>>());
      expect(
        await result,
        JsonArray([JsonNumber(1), JsonNumber(2)]),
      );
    });

    test('waits for several pending values in order', () async {
      final pending = PendingValues()
        ..add(
          Future<JsonValue?>.delayed(
            const Duration(milliseconds: 10),
            () => JsonNumber(1),
          ),
        )
        ..add(Future<JsonValue?>.value(JsonNumber(2)))
        ..add(JsonNumber(3));
      expect(
        await pending.finishWith(JsonArray.new),
        JsonArray([
          JsonNumber(1),
          JsonNumber(2),
          JsonNumber(3),
        ]),
      );
    });

    test('a failed value gives null', () {
      final pending = PendingValues()
        ..add(JsonNumber(1))
        ..add(null);
      expect(pending.finishWith(JsonArray.new), isNull);
    });

    test('abandon waits for the pending values', () async {
      var done = false;
      final pending = PendingValues()
        ..add(
          Future<JsonValue?>.delayed(const Duration(milliseconds: 10), () {
            done = true;
            return null;
          }),
        );
      expect(await pending.abandon<JsonArray>(), isNull);
      expect(done, isTrue);
    });
  });
}
