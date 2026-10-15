import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);

  Future<Stream<ExecutionResult>> started(
    String text,
    Probe probe,
    ExecutionOptions options,
  ) async {
    final result = await fixture.subscribe(text, probe, options: options);
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
    };
  }

  test('a signal cancelled before subscribe rejects with GQL350', () async {
    final signal = CancelSignal()..cancel();
    final probe = Probe();
    final result = await fixture.subscribe(
      'subscription { ticks }',
      probe,
      options: ExecutionOptions(cancelSignal: signal),
    );
    expect(result, isA<SubscriptionRejected>());
    final error = (result as SubscriptionRejected).error;
    expect(CancellationFixture.codeOf(error), 'GQL350');
    expect(probe.isSourceCancelled, isFalse);
  });

  test('cancelling ends the stream with a final GQL350 result', () async {
    final probe = Probe();
    final signal = CancelSignal();
    final results = await started(
      'subscription { ticks }',
      probe,
      ExecutionOptions(cancelSignal: signal),
    );
    final collected = results.toList();
    probe.source.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    signal.cancel();
    final all = await collected.timeout(patience);
    expect(all, hasLength(2));
    expect(all.first.data, isNotNull);
    expect(all.last.data, isNull);
    expect(CancellationFixture.codeOf(all.last), 'GQL350');
    expect(probe.isSourceCancelled, isTrue);
    probe.dispose();
  });

  test('the timeout ends the stream with a final GQL351 result', () async {
    final probe = Probe();
    final results = await started(
      'subscription { ticks }',
      probe,
      const ExecutionOptions(timeout: Duration(milliseconds: 20)),
    );
    final all = await results.toList().timeout(patience);
    expect(all, hasLength(1));
    expect(CancellationFixture.codeOf(all.single), 'GQL351');
    expect(
      CancellationFixture.messageOf(all.single),
      'Execution timed out after 20 ms.',
    );
    expect(probe.isSourceCancelled, isTrue);
    probe.dispose();
  });

  test('cancelling drops the event being executed', () async {
    final probe = Probe();
    final signal = CancelSignal();
    final results = await started(
      'subscription { held }',
      probe,
      ExecutionOptions(cancelSignal: signal),
    );
    final collected = results.toList();
    probe.source.add(1);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(probe.log, ['held 1']);
    signal.cancel();
    probe.gate.complete();
    final all = await collected.timeout(patience);
    expect(all, hasLength(1));
    expect(CancellationFixture.codeOf(all.single), 'GQL350');
    probe.dispose();
  });

  test('the caller signal is not cancelled by the timeout', () async {
    final probe = Probe();
    final signal = CancelSignal();
    final results = await started(
      'subscription { ticks }',
      probe,
      ExecutionOptions(
        cancelSignal: signal,
        timeout: const Duration(milliseconds: 10),
      ),
    );
    await results.toList().timeout(patience);
    expect(signal.isCancelled, isFalse);
    probe.dispose();
  });

  group('the timer', () {
    const watched = Duration(minutes: 5);
    const options = ExecutionOptions(timeout: watched);

    test('is cancelled when the source ends', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe();
      final results = await tracker.run(
        () => started('subscription { ticks }', probe, options),
      );
      expect(tracker.created, 1);
      final collected = results.toList();
      expect(tracker.isIdle, isFalse);
      await probe.source.close();
      await collected.timeout(patience);
      expect(tracker.isIdle, isTrue);
    });

    test('is cancelled when the consumer cancels', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe();
      final results = await tracker.run(
        () => started('subscription { ticks }', probe, options),
      );
      final subscription = results.listen((_) {});
      await subscription.cancel();
      expect(tracker.isIdle, isTrue);
      expect(probe.isSourceCancelled, isTrue);
    });

    test('is cancelled when the signal ends the stream', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe();
      final signal = CancelSignal();
      final results = await tracker.run(
        () => started(
          'subscription { ticks }',
          probe,
          ExecutionOptions(timeout: watched, cancelSignal: signal),
        ),
      );
      final collected = results.toList();
      signal.cancel();
      await collected.timeout(patience);
      expect(tracker.isIdle, isTrue);
      probe.dispose();
    });

    test('is cancelled when the subscription is rejected', () async {
      final tracker = TimerTracker(watched);
      final result = await tracker.run(
        () => fixture.subscribe('{ sync }', Probe(), options: options),
      );
      expect(result, isA<SubscriptionRejected>());
      expect(tracker.isIdle, isTrue);
    });
  });
}
