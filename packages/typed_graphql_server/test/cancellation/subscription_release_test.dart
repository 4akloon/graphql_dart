import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);

  Future<Stream<ExecutionResult>> started(
    Probe probe,
    ExecutionOptions options, {
    String field = 'ticks',
  }) async {
    final result = await fixture.subscribe(
      'subscription { $field }',
      probe,
      options: options,
    );
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
    };
  }

  group('a response stream nobody listens to', () {
    const watched = Duration(minutes: 5);

    test(
      'keeps its listener on the caller signal until it is cancelled',
      () async {
        final signal = CancelSignal();
        await started(Probe(), ExecutionOptions(cancelSignal: signal));
        expect(signal.listenerCount, 1);
      },
    );

    test('releases the timer when the caller cancels', () async {
      final tracker = TimerTracker(watched);
      final signal = CancelSignal();
      await tracker.run(
        () => started(
          Probe(),
          ExecutionOptions(cancelSignal: signal, timeout: watched),
        ),
      );
      expect(tracker.isIdle, isFalse);
      signal.cancel();
      expect(tracker.isIdle, isTrue);
    });

    test('releases the caller listener when the timeout fires', () async {
      final signal = CancelSignal();
      await started(
        Probe(),
        ExecutionOptions(
          cancelSignal: signal,
          timeout: const Duration(milliseconds: 10),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(signal.listenerCount, 0);
    });
  });

  test(
    'a finished stream leaves no listener of its own on the run signal',
    () async {
      final probe = Probe()..gate.complete();
      final results = await started(
        probe,
        ExecutionOptions(cancelSignal: CancelSignal()),
        field: 'held',
      );
      final collected = results.toList();
      probe.source.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await probe.source.close();
      final all = await collected.timeout(patience);
      expect(all, hasLength(1));
      // The one left is the run's own release, not the stream's.
      expect(probe.seen?.listenerCount, 1);
      expect(() => probe.seen?.cancel(), returnsNormally);
    },
  );
}
