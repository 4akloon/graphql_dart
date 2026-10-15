import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../support/cancellation_schema.dart';
import '../support/execution_port.dart';

// Ported from the subscription tests of graphql-js
// src/execution/__tests__/cancellation-test.ts; mapping/execution.csv says
// which tests are adapted or skipped, and why. A cancelled subscription
// ends with one last GQL350 result instead of a rejected `next()`
// (spec 18.9 of M5), and a subscription that cannot start is a
// `SubscriptionRejected` value (spec 18.30).
void main() {
  const port = ExecutionPort();
  final fixture = CancellationSchema();
  const fooEvent = <String, Object?>{
    'data': {'foo': 'foo'},
  };
  const cancelled = <String, Object?>{
    'errors': [
      {
        'message': 'Execution was cancelled.',
        'extensions': {'code': 'GQL350'},
      },
    ],
    'data': null,
  };

  Future<SubscriptionResult> subscribe(
    CancellationProbe probe,
    CancelSignal signal,
  ) async => port.subscribe<CancellationProbe>(
    fixture.schema,
    'subscription { foo }',
    context: probe,
    options: ExecutionOptions(maskErrors: false, cancelSignal: signal),
  );

  Future<StreamIterator<Map<String, Object?>>> open(
    CancellationProbe probe,
    CancelSignal signal,
  ) async => switch (await subscribe(probe, signal)) {
    SubscriptionStarted(:final results) => StreamIterator(
      results.map((result) => result.toJson().toJson()),
    ),
    SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
  };

  group('Execute: Cancellation', () {
    test('should successfully wrap the subscription', () async {
      final probe = CancellationProbe()
        ..source = () async => Stream.value('foo');
      final events = await open(probe, CancelSignal());
      expect(await events.moveNext(), isTrue);
      expect(events.current, fooEvent);
      expect(await events.moveNext(), isFalse);
    });

    test(
      'should stop the execution when aborted during subscription',
      () async {
        final source = StreamController<String>();
        final probe = CancellationProbe()..source = () => source.stream;
        final signal = CancelSignal();
        final events = await open(probe, signal);
        source.add('foo');
        expect(await events.moveNext(), isTrue);
        expect(events.current, fooEvent);
        signal.cancel();
        expect(await events.moveNext(), isTrue);
        expect(events.current, cancelled);
        expect(await events.moveNext(), isFalse);
        expect(source.hasListener, isFalse);
        await source.close();
      },
    );

    test(
      'should stop the execution when aborted during subscription returned asynchronously',
      () async {
        final source = StreamController<String>();
        final probe = CancellationProbe()..source = () async => source.stream;
        final signal = CancelSignal();
        final events = await open(probe, signal);
        source.add('foo');
        expect(await events.moveNext(), isTrue);
        expect(events.current, fooEvent);
        signal.cancel();
        expect(await events.moveNext(), isTrue);
        expect(events.current, cancelled);
        expect(await events.moveNext(), isFalse);
        expect(source.hasListener, isFalse);
        await source.close();
      },
    );
  });
}
