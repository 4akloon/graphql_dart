import 'dart:async';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../../http/support/http_fixture.dart';
import '../../server/support/server_fixture.dart';

/// A schema whose subscription ticks every 10 ms for ever and counts the
/// events it resolves, to observe whether the work stopped.
final class CountingSubscription {
  CountingSubscription() {
    final b = ExecutableSchemaBuilder<Ctx>();
    final query = b.object<Object?>(
      'Query',
      fields: (t) => [t.field('hello', b.string).pure((_) => 'world')],
    );
    final subscription = b.object<Object?>(
      'Subscription',
      fields: (t) => [
        t.field('count', b.string).subscribeWith<int>(
          (parent, args, context, info) => _ticks(),
          (event, args, context, info) {
            resolved++;
            return 'n$event';
          },
        ),
      ],
    );
    server = GraphQLServer<Ctx>(
      schema: b.build(query: query, subscription: subscription),
      contextFactory: (_) => const Ctx('default'),
      profile: ServerProfile.development,
    );
  }

  /// Completes when the source of the subscription has been cancelled.
  final Completer<void> cancelled = Completer<void>();

  // Ticks every 10 ms for ever; the `finally` runs when a listener cancels.
  Stream<int> _ticks() async* {
    try {
      for (var n = 0; ; n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        yield n;
      }
    } finally {
      cancelled.complete();
    }
  }

  /// How many events the subscription has resolved.
  int resolved = 0;

  // Set by the constructor, once the schema exists.
  late final GraphQLServer<Ctx> server;
}

/// The HTTP fixture plus readers for event streams.
final class SseFixture {
  final HttpFixture http = HttpFixture();

  /// The `Accept` header of a client that wants an event stream.
  static const Map<String, String> eventStreamClient = {
    'accept': 'text/event-stream',
  };

  /// The frames of the body of [response] once it has ended, without the
  /// comments.
  Future<List<String>> frames(HttpResponseData response) async => [
    for (final frame in (await http.text(response)).split('\n\n'))
      if (frame.isNotEmpty && !frame.startsWith(':')) frame,
  ];

  /// A `GET` that asks for an event stream.
  HttpRequestData getStream(Map<String, String> params) => http.get(
    params,
    headers: {...HttpFixture.preflight, ...eventStreamClient},
  );

  /// A `POST` of [query] that asks for an event stream.
  HttpRequestData postQuery(String query) =>
      http.post({'query': query}, headers: eventStreamClient);
}
