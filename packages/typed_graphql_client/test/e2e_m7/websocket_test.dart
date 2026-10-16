import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../e2e/support/e2e_operations.dart';
import '../e2e/support/test_server.dart';
import '../e2e/support/tick_source.dart';
import '../support/test_operations.dart';
import 'support/socket_pair.dart';

void main() {
  final upgrade = RequestInfo(
    method: 'GET',
    uri: Uri.parse('ws://localhost/graphql'),
  );

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  late TickSource ticks;
  late List<SocketPair> pairs;
  late List<Future<void>> sessions;
  late WebSocketLink link;
  late GraphQLClient client;

  WebSocketLink linkTo(
    GraphQLWsHandler<Object?> handler, {
    FutureOr<JsonObject?> Function()? connectionParams,
    int retryAttempts = 5,
  }) => WebSocketLink(
    connect: () async {
      final pair = SocketPair();
      pairs.add(pair);
      sessions.add(handler.serve(pair.server, upgrade));
      return pair.client;
    },
    connectionParams: connectionParams,
    retryAttempts: retryAttempts,
    backoff: const Backoff(
      initialDelay: Duration(milliseconds: 1),
      maxDelay: Duration(milliseconds: 1),
    ),
  );

  setUp(() {
    ticks = TickSource();
    pairs = [];
    sessions = [];
    link = linkTo(
      GraphQLWsHandler<Object?>(const TestServer().build(ticks: ticks)),
    );
    client = GraphQLClient(link: link);
  });

  tearDown(() => link.dispose());

  group('WebSocketLink against the M7 handler', () {
    test('a query gives the data over one socket', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(pairs, hasLength(1));
    });

    test('a subscription gives every event and ends', () async {
      final events = await client.subscribe(const TicksSubscription()).toList();
      expect(events.map((e) => (e as GraphQLData<int>).data), [1, 2, 3]);
    });

    test('cancelling a subscription cancels the server source', () async {
      final endless = TickSource(isEndless: true);
      final other = linkTo(
        GraphQLWsHandler<Object?>(const TestServer().build(ticks: endless)),
      );
      addTearDown(other.dispose);
      final first = await GraphQLClient(
        link: other,
      ).subscribe(const TicksSubscription()).first;
      expect((first as GraphQLData<int>).data, 1);
      await endless.whenCancelled;
      expect(endless.isCancelled, isTrue);
    });

    test('a request error arrives as errors', () async {
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
    });

    test('connectionParams reach onConnect', () async {
      final seen = <JsonObject?>[];
      final handler = GraphQLWsHandler<Object?>(
        const TestServer().build(),
        options: GraphQLWsOptions(
          onConnect: (info) {
            seen.add(info.connectionParams);
            return const AcceptConnection();
          },
        ),
      );
      final params = JsonObject({'token': const JsonString('t')});
      final other = linkTo(handler, connectionParams: () => params);
      addTearDown(other.dispose);
      await GraphQLClient(link: other).query(const HelloQuery());
      expect(seen, [params]);
    });

    test('a refused connection ends in GQL471 with code 4403', () async {
      final handler = GraphQLWsHandler<Object?>(
        const TestServer().build(),
        options: GraphQLWsOptions(
          onConnect: (info) => const RefuseConnection(),
        ),
      );
      final other = linkTo(handler, retryAttempts: 1);
      addTearDown(other.dispose);
      final response = await GraphQLClient(
        link: other,
      ).query(const HelloQuery());
      final failure = (response as GraphQLTransportFailure<String>).failure;
      expect(failure, isA<SocketFailure>());
      expect((failure as SocketFailure).closeCode, 4403);
    });

    test('dispose closes the socket with 1000 and ends the session', () async {
      await client.query(const HelloQuery());
      await link.dispose();
      await Future.wait(sessions);
      expect(pairs.single.closeCode, 1000);
    });
  });
}
