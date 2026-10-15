import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);
  const text = 'subscription { pending }';

  Future<SubscriptionResult> subscribeTo(
    Probe probe,
    ExecutionOptions options,
  ) async => fixture.subscribe(text, probe, options: options);

  SubscriptionRejected rejected(SubscriptionResult result) =>
      result is SubscriptionRejected
      ? result
      : fail('expected a rejection, got $result');

  test('a cancel while the source is pending rejects with GQL350', () async {
    final signal = CancelSignal();
    final pending = subscribeTo(
      Probe(),
      ExecutionOptions(cancelSignal: signal),
    );
    signal.cancel();
    final error = rejected(await pending.timeout(patience)).error;
    expect(CancellationFixture.codeOf(error), 'GQL350');
    expect(CancellationFixture.messageOf(error), 'Execution was cancelled.');
  });

  test('a timeout while the source is pending rejects with GQL351', () async {
    final result = await subscribeTo(
      Probe(),
      const ExecutionOptions(timeout: Duration(milliseconds: 20)),
    ).timeout(patience);
    final error = rejected(result).error;
    expect(CancellationFixture.codeOf(error), 'GQL351');
    expect(
      CancellationFixture.messageOf(error),
      'Execution timed out after 20 ms.',
    );
  });

  test('a stream that arrives after the cancel is never listened to', () async {
    final probe = Probe();
    final late = StreamController<int>();
    final signal = CancelSignal();
    final pending = subscribeTo(probe, ExecutionOptions(cancelSignal: signal));
    signal.cancel();
    await pending.timeout(patience);
    probe.pendingSource.complete(late.stream);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(late.hasListener, isFalse);
    unawaited(late.close());
  });

  test('an error that arrives after the cancel leaks nothing', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = subscribeTo(
        probe,
        ExecutionOptions(cancelSignal: signal),
      );
      signal.cancel();
      await pending.timeout(patience);
      probe.pendingSource.completeError(StateError('late'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }, (error, stackTrace) => uncaught.add(error));
    expect(uncaught, isEmpty);
  });

  test('the timer and the signal listener are released', () async {
    const watched = Duration(minutes: 5);
    final tracker = TimerTracker(watched);
    final signal = CancelSignal();
    final pending = tracker.run(
      () => subscribeTo(
        Probe(),
        ExecutionOptions(cancelSignal: signal, timeout: watched),
      ),
    );
    signal.cancel();
    await pending.timeout(patience);
    expect(tracker.created, 1);
    expect(tracker.isIdle, isTrue);
  });
}
