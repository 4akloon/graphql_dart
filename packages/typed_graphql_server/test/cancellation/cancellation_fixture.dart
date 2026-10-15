import 'dart:async';

import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// The context of a cancellation test: what the resolvers saw, and the
/// gate they wait for.
final class Probe {
  final List<String> log = [];

  /// The run's signal as the slow resolver saw it.
  CancelSignal? seen;

  /// Whether the signal was already cancelled when the slow resolver ended.
  bool? wasCancelledAtEnd;

  /// Resolvers that wait stop here until the test completes it.
  final Completer<void> gate = Completer<void>();

  /// The caller's signal, for a resolver that cancels it.
  CancelSignal? caller;

  /// The source of the subscription fields.
  // `late`: the callback reads a field of this object.
  late final StreamController<int> source = StreamController<int>(
    onCancel: () => isSourceCancelled = true,
  );

  bool isSourceCancelled = false;

  /// What the `pending` subscription field's source function returns: a
  /// future the test completes when it wants.
  final Completer<Stream<int>> pendingSource = Completer<Stream<int>>();

  /// Ends the source; one nobody listened to stays pending.
  void dispose() => unawaited(source.close());
}

/// Records the timers created with the watched duration, to tell that none
/// is left running.
final class TimerTracker {
  TimerTracker(this.watched);

  final Duration watched;
  final List<Timer> _created = [];

  /// Runs [body] so that the timers it starts are recorded.
  R run<R>(R Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        if (duration == watched) {
          _created.add(timer);
        }
        return timer;
      },
    ),
  );

  int get created => _created.length;

  bool get isIdle => _created.every((timer) => !timer.isActive);
}

/// A schema with one field per behaviour under test.
final class CancellationFixture {
  CancellationFixture() {
    final b = ExecutableSchemaBuilder<Probe>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [
        t.field('sync', b.string).pure((_) => 'ok'),
        t.field('slow', b.string).resolve((parent, args, context, info) async {
          context.log.add('slow start');
          context.seen = info.cancelSignal;
          await context.gate.future;
          context.wasCancelledAtEnd = info.cancelSignal.isCancelled;
          return 'slow';
        }),
        t.field('cancelsItself', b.string).resolve((
          parent,
          args,
          context,
          info,
        ) {
          context.caller?.cancel('stop');
          return 'done';
        }),
        t.field('after', b.string).resolve((parent, args, context, info) {
          context.log.add('after start');
          return 'after';
        }),
      ],
    );
    final mutation = b.object<Object?>(
      'Mutation',
      fields: (t) => [
        t.field('first', b.string).resolve((parent, args, context, info) async {
          context.log.add('first start');
          await context.gate.future;
          return 'first';
        }),
        t.field('second', b.string).resolve((parent, args, context, info) {
          context.log.add('second start');
          return 'second';
        }),
      ],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t
            .field('ticks', b.int)
            .subscribe((parent, args, context, info) => context.source.stream),
        t
            .field('pending', b.int)
            .subscribe(
              (parent, args, context, info) => context.pendingSource.future,
            ),
        t.field('held', b.int).subscribeWith<int>(
          (parent, args, context, info) => context.source.stream,
          (event, args, context, info) async {
            context.log.add('held $event');
            context.seen = info.cancelSignal;
            await context.gate.future;
            return event;
          },
        ),
      ],
    );
    built = b.build(
      query: query,
      mutation: mutation,
      subscription: subscription,
    );
  }

  // `late`: assigned at the end of the constructor body.
  late final ExecutableSchema<Probe> built;

  ValidDocument document(String text) => ValidDocument.assumeValid(
    built.schema,
    const Parser(
      options: ParserOptions(maxTokens: null, maxDepth: null),
    ).parse(Source(text)).requireDocument(),
  );

  FutureOr<ResponsePayload> execute(
    String text,
    Probe probe, {
    ExecutionOptions options = const ExecutionOptions(),
    String? operationName,
  }) => built.execute(
    document(text),
    context: probe,
    options: options,
    operationName: operationName,
  );

  FutureOr<SubscriptionResult> subscribe(
    String text,
    Probe probe, {
    ExecutionOptions options = const ExecutionOptions(),
  }) => built.subscribe(document(text), context: probe, options: options);

  /// The `extensions.code` of the only error of [result].
  static String codeOf(ResponsePayload result) {
    final json = result.toJson().toJson();
    final errors = json['errors'] as List<Object?>;
    final error = errors.single as Map<String, Object?>;
    return (error['extensions'] as Map<String, Object?>)['code'] as String;
  }

  /// The message of the only error of [result].
  static String messageOf(ResponsePayload result) {
    final json = result.toJson().toJson();
    final errors = json['errors'] as List<Object?>;
    return (errors.single as Map<String, Object?>)['message'] as String;
  }
}
