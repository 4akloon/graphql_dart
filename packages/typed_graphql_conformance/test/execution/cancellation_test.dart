import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/cancellation_schema.dart';
import '../support/execution_port.dart';

// Ported from graphql-js src/execution/__tests__/cancellation-test.ts (the
// queries and mutations; the subscriptions are in
// cancellation_subscription_test.dart and the sibling errors in
// cancellation_bubbling_test.dart); mapping/execution.csv says which tests
// are adapted or skipped, and why. graphql-js rejects with "This operation
// was aborted" where `execute` completes with a GQL350 result (spec 18.9 of
// M5), so every result is compared with `cancelled`.
void main() {
  const port = ExecutionPort();
  final fixture = CancellationSchema();
  const cancelled = <String, Object?>{
    'errors': [
      {
        'message': 'Execution was cancelled.',
        'extensions': {'code': 'GQL350'},
      },
    ],
    'data': null,
  };
  const patience = Duration(seconds: 2);

  FutureOr<ResponsePayload> run(
    String text,
    CancellationProbe probe,
    CancelSignal signal,
  ) => port.payload(
    fixture.schema,
    text,
    context: probe,
    options: ExecutionOptions(maskErrors: false, cancelSignal: signal),
  );

  Future<Map<String, Object?>> settled(
    FutureOr<ResponsePayload> pending,
  ) async => (await Future<ResponsePayload>.value(
    pending,
  ).timeout(patience)).toJson().toJson();

  Future<void> later() => Future<void>.delayed(const Duration(milliseconds: 5));

  const nestedQuery = 'query { todo { id author { id } } }';

  group('Execute: Cancellation', () {
    test(
      'should stop the execution when aborted during object field completion',
      () async {
        final probe = CancellationProbe()
          ..todo = () async => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(probe.log, isEmpty);
      },
    );

    test(
      'should provide access to the abort signal within resolvers',
      () async {
        var isNotified = false;
        final probe = CancellationProbe()
          ..todo = () => CancellationTodo((info) async {
            unawaited(
              info.cancelSignal.whenCancelled.then((_) => isNotified = true),
            );
            await Future<void>.delayed(Duration.zero);
            throw StateError(
              'some random other error that does not show up in response',
            );
          });
        final signal = CancelSignal();
        final pending = run('query { todo { id } }', probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(isNotified, isTrue);
      },
    );

    test(
      'should stop the execution when aborted during object field completion with a custom error',
      () async {
        final probe = CancellationProbe()
          ..todo = () async => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        final reason = StateError('Custom abort error');
        signal.cancel(reason);
        expect(await settled(pending), cancelled);
        expect(signal.reason, same(reason));
        await later();
        expect(probe.log, isEmpty);
      },
    );

    test(
      'rejects with the aborted execution error while initial result is pending',
      () async {
        final probe = CancellationProbe();
        final signal = CancelSignal();
        final pending = run('query { blocker }', probe, signal);
        await probe.blockerStarted.future;
        signal.cancel(StateError('Custom abort error'));
        final result = await settled(pending);
        probe.blockerValue.complete('ok');
        await later();
        expect(result, cancelled);
      },
    );

    test(
      'throws the aborted execution error with a completed initial result in the atypical internal resolver-abort case',
      () {
        final signal = CancelSignal();
        final probe = CancellationProbe()
          ..aborter = () {
            signal.cancel(StateError('Custom abort error'));
            return 'done';
          };
        final result = run('query { aborter }', probe, signal);
        expect(result, isNot(isA<Future<Object?>>()));
        expect((result as ExecutionResult).toJson().toJson(), cancelled);
      },
    );

    test(
      'should stop the execution when aborted during nested object field completion',
      () async {
        final probe = CancellationProbe()
          ..todo = () => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(probe.log, ['author']);
      },
    );

    test(
      'should stop the execution when aborted despite a hanging resolver',
      () async {
        final probe = CancellationProbe()
          ..todo = () => Completer<CancellationTodo?>().future;
        final signal = CancelSignal();
        final pending = run(nestedQuery, probe, signal);
        signal.cancel();
        expect(await settled(pending), cancelled);
      },
    );

    test(
      'should stop the execution when aborted with proper null bubbling',
      () async {
        final probe = CancellationProbe()
          ..nonNullableTodo = () async => CancellationTodo.of('1');
        final signal = CancelSignal();
        final pending = run(
          'query { nonNullableTodo { id author { id } } }',
          probe,
          signal,
        );
        signal.cancel();
        expect(await settled(pending), cancelled);
        await later();
        expect(probe.log, isEmpty);
      },
    );

    test('should stop the execution when aborted mid-mutation', () async {
      final probe = CancellationProbe();
      final signal = CancelSignal();
      final pending = run('mutation { foo bar }', probe, signal);
      signal.cancel();
      expect(await settled(pending), cancelled);
      await later();
      expect(probe.log, ['foo']);
    });

    test('should stop the execution when aborted pre-execute', () {
      final probe = CancellationProbe();
      probe.todo = () {
        probe.log.add('todo');
        return null;
      };
      final signal = CancelSignal()..cancel();
      final result = run(nestedQuery, probe, signal);
      expect(result, isNot(isA<Future<Object?>>()));
      expect((result as ExecutionResult).toJson().toJson(), cancelled);
      expect(probe.log, isEmpty);
    });

    test(
      'should stop the execution when aborted before cancellation is wired',
      () async {
        final signal = CancelSignal();
        final probe = CancellationProbe()
          ..aborter = () {
            signal.cancel(StateError('Custom abort error'));
            return Completer<String?>().future;
          };
        final pending = run('query { aborter }', probe, signal);
        expect(await settled(pending), cancelled);
      },
    );
  });
}
