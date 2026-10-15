import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of these tests: the source, and what the event resolver saw.
final class Feed {
  Feed(this.source);

  final Stream<int> source;
  final List<String> log = [];
  int running = 0;
  int mostRunning = 0;

  /// When set, every resolver waits for it.
  Completer<void>? gate;
}

/// Builds the schema of these tests and starts subscriptions on it.
final class FlowHarness {
  /// Creates a harness.
  const FlowHarness();

  ExecutableSchema<Feed> schema() {
    final b = ExecutableSchemaBuilder<Feed>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('noop', b.string).pure((_) => 'noop')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t.field('count', b.int).subscribeWith<int>(
          (parent, args, context, info) => context.source,
          (
            event,
            args,
            context,
            info,
          ) async {
            context.running++;
            if (context.running > context.mostRunning) {
              context.mostRunning = context.running;
            }
            context.log.add('start $event');
            await (context.gate?.future ??
                Future<void>.delayed(const Duration(milliseconds: 1)));
            context.log.add('end $event');
            context.running--;
            return event;
          },
        ),
      ],
    );
    return b.build(query: query, subscription: subscription);
  }

  Future<Stream<ExecutionResult>> started(Feed feed) async {
    final built = schema();
    final document = const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source('subscription { count }')).requireDocument();
    final result = await built.subscribe(
      ValidDocument.assumeValid(built.schema, document),
      context: feed,
    );
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail('rejected: ${error.toJson()}'),
    };
  }

  Object? dataOf(ExecutionResult result) => result.toJson().toJson()['data'];
}

void main() {
  const harness = FlowHarness();
  final started = harness.started;
  final dataOf = harness.dataOf;
  test(
    'a source that delivers inside listen runs one event at a time',
    () async {
      late final StreamController<int> controller;
      controller = StreamController<int>.broadcast(
        sync: true,
        onListen: () => controller
          ..add(1)
          ..add(2)
          ..add(3),
      );
      final feed = Feed(controller.stream);
      final results = await started(feed);
      final collected = <Object?>[];
      final done = Completer<void>();
      results.listen((result) {
        collected.add(dataOf(result));
        if (collected.length == 3) {
          done.complete();
        }
      });
      await done.future;
      expect(collected, [
        {'count': 1},
        {'count': 2},
        {'count': 3},
      ]);
      expect(feed.mostRunning, 1);
      expect(feed.log, [
        'start 1',
        'end 1',
        'start 2',
        'end 2',
        'start 3',
        'end 3',
      ]);
      await controller.close();
    },
  );

  test('a source whose cancel fails leaves no uncaught error', () async {
    final uncaught = <Object>[];
    await runZonedGuarded(
      () async {
        final controller = StreamController<int>(
          onCancel: () => Future<void>.error(StateError('cancel failed')),
        );
        addTearDown(controller.close);
        final results = await started(Feed(controller.stream));
        final collected = results.toList();
        controller.addError(StateError('source failed'));
        expect(await collected, hasLength(1));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      (error, stackTrace) => uncaught.add(error),
    );
    expect(uncaught, isEmpty);
  });

  test(
    'an event in flight when the consumer cancels gives no result',
    () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final gate = Completer<void>();
      final feed = Feed(controller.stream)..gate = gate;
      final results = await started(feed);
      final collected = <ExecutionResult>[];
      final subscription = results.listen(collected.add);
      controller.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(feed.log, ['start 1']);
      await subscription.cancel();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(collected, isEmpty);
    },
  );

  test('a source error during an event comes after its result', () async {
    final controller = StreamController<int>();
    addTearDown(controller.close);
    final gate = Completer<void>();
    final feed = Feed(controller.stream)..gate = gate;
    final results = await started(feed);
    final collected = results.map(dataOf).toList();
    controller
      ..add(1)
      ..addError(StateError('late failure'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();
    expect(await collected, [
      {'count': 1},
      null,
    ]);
  });

  test(
    'the end of the source during an event comes after its result',
    () async {
      final controller = StreamController<int>();
      addTearDown(controller.close);
      final gate = Completer<void>();
      final feed = Feed(controller.stream)..gate = gate;
      final results = await started(feed);
      final collected = results.map(dataOf).toList();
      controller
        ..add(1)
        ..close().ignore();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      expect(await collected, [
        {'count': 1},
      ]);
    },
  );
}
