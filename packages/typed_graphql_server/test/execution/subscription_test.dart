import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'subscription_fixture.dart';

void main() {
  late SubscriptionFixture fixture;
  late Bus bus;

  setUp(() {
    fixture = SubscriptionFixture();
    bus = Bus();
    addTearDown(() => bus.dispose());
  });

  Future<Stream<ExecutionResult>> started(
    String text, {
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await fixture.subscribe(
      text,
      bus,
      variables: variables,
      options: options,
    );
    return switch (result) {
      SubscriptionStarted(:final results) => results,
      SubscriptionRejected(:final error) => fail(
        'rejected: ${error.toJson()}',
      ),
    };
  }

  Future<Map<String, Object?>> rejection(
    String text, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async {
    final result = await fixture.subscribe(
      text,
      bus,
      operationName: operationName,
      variables: variables,
      options: options,
    );
    return switch (result) {
      SubscriptionRejected(:final error) => error.toJson().toJson(),
      SubscriptionStarted() => fail('started'),
    };
  }

  Map<String, Object?> jsonOf(ExecutionResult result) =>
      result.toJson().toJson();

  String codeOfFirst(Map<String, Object?> json) =>
      (((json['errors']! as List<Object?>).first!
                  as Map<String, Object?>)['extensions']!
              as Map<String, Object?>)['code']!
          as String;

  test('each source event is a result, in order', () async {
    final results = await started('subscription { count }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await bus.controller.close();
    expect(await collected, [
      {
        'data': {'count': 1},
      },
      {
        'data': {'count': 2},
      },
    ]);
  });

  test('async event resolvers keep the order of the events', () async {
    final results = await started('subscription { labeled }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await bus.controller.close();
    expect((await collected).map((json) => json['data']), [
      {'labeled': 'n1'},
      {'labeled': 'n2'},
    ]);
  });

  test('an event is executed only after the one before is answered', () async {
    bus.gate = Completer<void>();
    final results = await started('subscription { labeled }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bus.log, ['start 1']);
    bus.gate!.complete();
    await bus.controller.close();
    expect(await collected, hasLength(2));
    expect(bus.log, ['start 1', 'start 2']);
  });

  test('a field error inside an event stays in that result', () async {
    final results = await started('subscription { labeled }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(3)
      ..add(4);
    await bus.controller.close();
    final all = await collected;
    expect(all[0]['data'], {'labeled': null});
    expect(codeOfFirst(all[0]), 'GQL330');
    expect(all[1], {
      'data': {'labeled': 'n4'},
    });
  });

  test('cancelling the response subscription cancels the source', () async {
    final results = await started('subscription { count }');
    final subscription = results.listen((_) {});
    bus.controller.add(1);
    await Future<void>.delayed(Duration.zero);
    expect(bus.isCancelled, isFalse);
    await subscription.cancel();
    expect(bus.isCancelled, isTrue);
  });

  test('the source is not listened to before the results are', () async {
    await started('subscription { count }');
    expect(bus.controller.hasListener, isFalse);
  });

  test('pause and resume pass through to the source', () async {
    final results = await started('subscription { count }');
    final subscription = results.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    subscription.pause();
    expect(bus.controller.isPaused, isTrue);
    subscription.resume();
    await Future<void>.delayed(Duration.zero);
    expect(bus.controller.isPaused, isFalse);
    await subscription.cancel();
  });

  test('the end of the source closes the results', () async {
    final results = await started('subscription { count }');
    final done = results.toList();
    await bus.controller.close();
    expect(await done, isEmpty);
  });

  test('a source error is a last masked result, then the end', () async {
    final results = await started('subscription { count }');
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..addError(StateError('secret'));
    final all = await collected;
    expect(all, hasLength(2));
    expect(all[1], {
      'data': null,
      'errors': [
        {
          'message': 'Unexpected error.',
          'extensions': {'code': 'GQL340'},
        },
      ],
    });
    expect(bus.isCancelled, isTrue);
  });

  test('a source error goes through onError', () async {
    final seen = <Object>[];
    final results = await started(
      'subscription { count }',
      options: ExecutionOptions(
        onError: (error, stackTrace, reported) {
          seen.add(error);
          return null;
        },
      ),
    );
    final collected = results.map(jsonOf).toList();
    bus.controller.addError(StateError('x'));
    await collected;
    expect(seen, [isA<StateError>()]);
  });

  test('variables reach the source and the events', () async {
    final results = await started(
      r'subscription ($by: Int!) { scaled(by: $by) }',
      variables: JsonObject({'by': JsonNumber(10)}),
    );
    final collected = results.map(jsonOf).toList();
    bus.controller.add(2);
    await bus.controller.close();
    expect(await collected, [
      {
        'data': {'scaled': 20},
      },
    ]);
  });

  test('a source function may answer with a future of the stream', () async {
    final results = await started('subscription { late }');
    final collected = results.map(jsonOf).toList();
    bus.controller.add(7);
    await bus.controller.close();
    expect(await collected, [
      {
        'data': {'late': 7},
      },
    ]);
  });

  test('a query is refused with GQL324', () async {
    final json = await rejection('{ noop }');
    expect(codeOfFirst(json), 'GQL324');
  });

  test('an unknown operation name is a request error', () async {
    final json = await rejection(
      'subscription A { count }',
      operationName: 'B',
    );
    expect(codeOfFirst(json), 'GQL320');
  });

  test('an unusable variable is a request error', () async {
    final json = await rejection(
      r'subscription ($by: Int!) { scaled(by: $by) }',
    );
    expect(codeOfFirst(json), 'GQL310');
  });

  test('a source function that throws rejects the subscription', () async {
    final json = await rejection('subscription { throwing }');
    final error =
        (json['errors']! as List<Object?>).single! as Map<String, Object?>;
    expect(error['path'], ['throwing']);
    expect(error['message'], 'Unexpected error.');
    expect(codeOfFirst(json), 'GQL330');
  });

  test('a source future that fails rejects, through onError', () async {
    final seen = <Object>[];
    final json = await rejection(
      'subscription { failing }',
      options: ExecutionOptions(
        onError: (error, stackTrace, reported) {
          seen.add(error);
          return null;
        },
      ),
    );
    expect(codeOfFirst(json), 'GQL330');
    expect(seen, [isA<StateError>()]);
  });

  test('execute runs a subscription operation once, as a query', () async {
    final payload = await fixture.built.execute(
      fixture.validDocument('subscription { labeled }'),
      context: bus,
      options: const ExecutionOptions(rootValue: 5),
    );
    expect(payload.toJson().toJson(), {
      'data': {'labeled': 'n5'},
    });
  });

  test('global middleware wraps the resolution of each event', () async {
    final seen = <String>[];
    final wrapped = SubscriptionFixture(
      options: BuildOptions<Bus>(
        middleware: [
          (next, site) => (parent, args, context, info) {
            seen.add('${site.field.name}:$parent');
            return next(parent, args, context, info);
          },
        ],
      ),
    );
    final result = await wrapped.subscribe('subscription { count }', bus);
    final results = (result as SubscriptionStarted).results;
    final collected = results.map(jsonOf).toList();
    bus.controller
      ..add(1)
      ..add(2);
    await bus.controller.close();
    await collected;
    expect(seen, ['count:1', 'count:2']);
  });
}
