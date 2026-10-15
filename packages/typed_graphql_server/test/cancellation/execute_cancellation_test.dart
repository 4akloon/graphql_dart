import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'cancellation_fixture.dart';

void main() {
  final fixture = CancellationFixture();
  const patience = Duration(seconds: 2);

  group('a signal cancelled before execute', () {
    test('gives the cancelled result without a Future', () {
      final probe = Probe();
      final signal = CancelSignal()..cancel();
      final result = fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(result, isNot(isA<Future<Object?>>()));
      result as ExecutionResult;
      expect(result.data, isNull);
      expect(CancellationFixture.codeOf(result), 'GQL350');
      expect(
        CancellationFixture.messageOf(result),
        'Execution was cancelled.',
      );
      expect(probe.log, isEmpty);
    });

    test('loses to a request error', () {
      final signal = CancelSignal()..cancel();
      final result = fixture.execute(
        '{ sync }',
        Probe(),
        operationName: 'Missing',
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(result, isA<RequestErrorResult>());
    });
  });

  group('cancelling during an execution', () {
    test('completes at once and the resolver sees the signal', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(pending, isA<Future<Object?>>());
      expect(probe.seen?.isCancelled, isFalse);
      signal.cancel('client left');
      final result = await (pending as Future<ResponsePayload>).timeout(
        patience,
      );
      expect(CancellationFixture.codeOf(result), 'GQL350');
      expect((result as ExecutionResult).data, isNull);
      expect(probe.seen?.isCancelled, isTrue);
      expect(probe.seen?.reason, 'client left');
    });

    test('drops what a resolver returns afterwards', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      signal.cancel();
      final result = await (pending as Future<ResponsePayload>);
      probe.gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(probe.wasCancelledAtEnd, isTrue);
      expect((result as ExecutionResult).data, isNull);
      expect(result.errors, hasLength(1));
    });

    test('after a halt keeps the halt error', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        '{ slow sync after }',
        probe,
        options: ExecutionOptions(cancelSignal: signal, maxSteps: 1),
      );
      signal.cancel();
      final result = await (pending as Future<ResponsePayload>);
      probe.gate.complete();
      expect(CancellationFixture.codeOf(result), 'GQL337');
    });

    test('starts no field after it', () async {
      final probe = Probe();
      final signal = CancelSignal();
      final pending = fixture.execute(
        'mutation { first second }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      signal.cancel();
      probe.gate.complete();
      final result = await (pending as Future<ResponsePayload>);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(CancellationFixture.codeOf(result), 'GQL350');
      expect(probe.log, ['first start']);
    });

    test('by a resolver of a synchronous query stays synchronous', () {
      final probe = Probe();
      final signal = CancelSignal();
      probe.caller = signal;
      final result = fixture.execute(
        '{ cancelsItself }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect(CancellationFixture.codeOf(result as ExecutionResult), 'GQL350');
    });
  });

  group('the timeout', () {
    test('ends a slow execution with GQL351', () async {
      final result = await (fixture.execute(
        '{ slow }',
        Probe(),
        options: const ExecutionOptions(timeout: Duration(milliseconds: 20)),
      ) as Future<ResponsePayload>).timeout(patience);
      expect((result as ExecutionResult).data, isNull);
      expect(CancellationFixture.codeOf(result), 'GQL351');
      expect(
        CancellationFixture.messageOf(result),
        'Execution timed out after 20 ms.',
      );
    });

    test('shows the resolver a cancelled signal', () async {
      final probe = Probe();
      await (fixture.execute(
        '{ slow }',
        probe,
        options: const ExecutionOptions(timeout: Duration(milliseconds: 20)),
      ) as Future<ResponsePayload>).timeout(patience);
      expect(probe.seen?.isCancelled, isTrue);
    });

    test('keeps a synchronous query synchronous', () {
      final result = fixture.execute(
        '{ sync }',
        Probe(),
        options: const ExecutionOptions(timeout: Duration(minutes: 5)),
      );
      expect(result, isNot(isA<Future<Object?>>()));
      expect((result as ExecutionResult).errors, isEmpty);
    });

    test('is not exceeded by a query that answers in time', () async {
      final probe = Probe()..gate.complete();
      final result = await fixture.execute(
        '{ slow }',
        probe,
        options: const ExecutionOptions(timeout: Duration(minutes: 5)),
      );
      expect((result as ExecutionResult).errors, isEmpty);
    });
  });

  group('the timer', () {
    const watched = Duration(minutes: 5);
    const options = ExecutionOptions(timeout: watched);

    test('is cancelled when a synchronous run ends', () {
      final tracker = TimerTracker(watched);
      tracker.run(() => fixture.execute('{ sync }', Probe(), options: options));
      expect(tracker.created, 1);
      expect(tracker.isIdle, isTrue);
    });

    test('is cancelled when an asynchronous run ends', () async {
      final tracker = TimerTracker(watched);
      final probe = Probe()..gate.complete();
      final pending = tracker.run(
        () => fixture.execute('{ slow }', probe, options: options),
      );
      expect(tracker.isIdle, isFalse);
      await pending;
      expect(tracker.created, 1);
      expect(tracker.isIdle, isTrue);
    });

    test('is cancelled when the signal ends the run', () async {
      final tracker = TimerTracker(watched);
      final signal = CancelSignal();
      final pending = tracker.run(
        () => fixture.execute(
          '{ slow }',
          Probe(),
          options: ExecutionOptions(timeout: watched, cancelSignal: signal),
        ),
      );
      signal.cancel();
      await pending;
      expect(tracker.isIdle, isTrue);
    });

    test('is not started for a request error', () {
      final tracker = TimerTracker(watched);
      final result = tracker.run(
        () => fixture.execute(
          '{ sync }',
          Probe(),
          operationName: 'Missing',
          options: options,
        ),
      );
      expect(result, isA<RequestErrorResult>());
      expect(tracker.created, 0);
    });
  });

  group('the caller signal', () {
    test('is not cancelled by a timeout', () async {
      final signal = CancelSignal();
      await (fixture.execute(
        '{ slow }',
        Probe(),
        options: ExecutionOptions(
          cancelSignal: signal,
          timeout: const Duration(milliseconds: 10),
        ),
      ) as Future<ResponsePayload>).timeout(patience);
      expect(signal.isCancelled, isFalse);
    });

    test('is not cancelled when the run finishes', () {
      final signal = CancelSignal();
      fixture.execute(
        '{ sync }',
        Probe(),
        options: ExecutionOptions(cancelSignal: signal),
      );
      expect(signal.isCancelled, isFalse);
    });

    test('keeps no listener after the run', () async {
      final signal = CancelSignal();
      final probe = Probe()..gate.complete();
      await fixture.execute(
        '{ slow }',
        probe,
        options: ExecutionOptions(cancelSignal: signal),
      );
      probe.seen?.cancel();
      signal.cancel();
      expect(signal.isCancelled, isTrue);
    });
  });

  test('a call without a signal or timeout never sees a cancelled signal', () {
    final probe = Probe()..gate.complete();
    final result = fixture.execute('{ slow after }', probe);
    expect(result, isA<Future<Object?>>());
    expect(probe.seen?.isCancelled, isFalse);
  });
}
