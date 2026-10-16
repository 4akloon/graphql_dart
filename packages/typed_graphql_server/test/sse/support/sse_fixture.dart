import 'dart:async';
import 'dart:convert';

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

  /// The header that carries the token of a single-connection stream.
  static const String tokenHeader = 'x-graphql-event-stream-token';

  /// Options with single connection mode on.
  HttpOptions singleOptions({
    SingleConnectionOptions limits = const SingleConnectionOptions(),
    BatchPolicy? batching,
  }) => HttpOptions(
    batching: batching,
    sse: SseOptions(
      keepAliveInterval: const Duration(hours: 1),
      singleConnection: limits,
    ),
  );

  /// A `PUT` that asks for a reservation.
  HttpRequestData put({Map<String, String> headers = const {}}) =>
      HttpRequestData(
        method: 'PUT',
        uri: Uri.parse('/graphql'),
        headers: headers,
      );

  /// A `GET` that connects the stream of [token], in the header or, with
  /// [isInQuery], in the `token` parameter.
  HttpRequestData connect(String token, {bool isInQuery = false}) =>
      HttpRequestData(
        method: 'GET',
        uri: Uri(
          path: '/graphql',
          queryParameters: isInQuery ? {'token': token} : null,
        ),
        headers: {
          ...eventStreamClient,
          if (!isInQuery) tokenHeader: token,
        },
      );

  /// A `POST` of [query] as operation [id] on the stream of [token].
  HttpRequestData operation(
    String token,
    String query, {
    Object? id = 'op',
  }) => http.post(
    {
      'query': query,
      'extensions': {'operationId': ?id},
    },
    headers: {...HttpFixture.modernClient, tokenHeader: token},
  );

  /// A `DELETE` that cancels operation [id] on the stream of [token].
  HttpRequestData cancel(String token, {String? id}) => HttpRequestData(
    method: 'DELETE',
    uri: Uri(
      path: '/graphql',
      queryParameters: id == null ? null : {'operationId': id},
    ),
    headers: {tokenHeader: token},
  );

  /// Reserves a stream on [handler] and returns its token.
  Future<String> reserve(GraphQLHttpHandler<Ctx> handler) async =>
      http.text(await handler.handle(put()));
}

/// Reads the body of a live event stream as it arrives.
final class StreamReader {
  StreamReader(HttpResponseData response) {
    _subscription = (response.body as StreamedBody).chunks.listen(
      (chunk) => _text += utf8.decode(chunk),
      onDone: () => isDone = true,
    );
  }

  // Set in the constructor body, which runs before any chunk can arrive.
  late final StreamSubscription<List<int>> _subscription;
  String _text = '';

  /// Whether the body has ended.
  bool isDone = false;

  /// The frames received so far, without the comments.
  List<String> get frames => [
    for (final frame in _text.split('\n\n'))
      if (frame.isNotEmpty && !frame.startsWith(':')) frame,
  ];

  /// The frames once at least [count] have arrived (or three seconds passed).
  Future<List<String>> waitFor(int count) async {
    final clock = Stopwatch()..start();
    while (frames.length < count && clock.elapsedMilliseconds < 3000) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return frames;
  }

  /// Stops reading, as a client that goes away.
  Future<void> cancel() => _subscription.cancel();
}
