import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of a subscription test: the source it listens to and what
/// happened around it.
final class Bus {
  /// The source; tests close it, or the subscription cancels it.
  late final StreamController<int> controller = StreamController<int>(
    onCancel: () => isCancelled = true,
  );

  bool isCancelled = false;

  /// Ends the source; a source nobody listened to stays pending.
  void dispose() => unawaited(controller.close());
  final List<String> log = [];

  /// When set, the resolver of event 1 waits for it.
  Completer<void>? gate;
}

/// A schema with one subscription field per behaviour under test.
final class SubscriptionFixture {
  SubscriptionFixture({BuildOptions<Bus>? options}) {
    final b = ExecutableSchemaBuilder<Bus>();
    final by = Arg('by', b.int);
    late final ObjectTypeDef<Object?> query;
    query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('noop', b.string).pure((_) => 'noop')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('count', b.int)
            .subscribe(
              (parent, args, context, info) => context.controller.stream,
            ),
        t.field('labeled', b.string.nullable).subscribeWith<int>(
          (parent, args, context, info) => context.controller.stream,
          (event, args, context, info) async {
            context.log.add('start $event');
            if (event == 1) {
              await context.gate?.future;
            } else if (event == 2) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
            if (event == 3) {
              throw StateError('bad event');
            }
            return 'n$event';
          },
        ),
        t
            .field('scaled', b.int, args: [by])
            .subscribe(
              (parent, args, context, info) =>
                  context.controller.stream.map((e) => e * args.get(by)),
            ),
        t
            .field('late', b.int)
            .subscribe(
              (parent, args, context, info) async => context.controller.stream,
            ),
        t
            .field('throwing', b.int)
            .subscribe((parent, args, context, info) => throw StateError('no')),
        t
            .field('failing', b.int)
            .subscribe(
              (parent, args, context, info) =>
                  Future<Stream<int>>.error(StateError('no future')),
            ),
      ],
    );
    built = b.build(
      query: query,
      subscription: subscription,
      options: options,
    );
  }

  late final ExecutableSchema<Bus> built;

  Document parse(String text) => const Parser(
    options: ParserOptions(maxTokens: null, maxDepth: null),
  ).parse(Source(text)).requireDocument();

  ValidDocument validDocument(String text) =>
      ValidDocument.assumeValid(built.schema, parse(text));

  Future<SubscriptionResult> subscribe(
    String text,
    Bus bus, {
    String? operationName,
    JsonObject? variables,
    ExecutionOptions options = const ExecutionOptions(),
  }) async => built.subscribe(
    validDocument(text),
    context: bus,
    operationName: operationName,
    variables: variables,
    options: options,
  );
}
