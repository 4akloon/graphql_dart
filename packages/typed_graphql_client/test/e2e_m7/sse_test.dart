import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../e2e/support/e2e_operations.dart';
import '../e2e/support/test_server.dart';
import '../e2e/support/tick_source.dart';
import '../support/test_operations.dart';
import 'support/handler_transport.dart';

void main() {
  late TickSource ticks;
  late HandlerTransport transport;
  late GraphQLClient client;

  String? codeOf(GraphQLError error) => switch (error.extensions?['code']) {
    JsonString(:final value) => value,
    _ => null,
  };

  setUp(() {
    ticks = TickSource();
    transport = HandlerTransport(
      GraphQLHttpHandler<Object?>(const TestServer().build(ticks: ticks)),
    );
    client = GraphQLClient(
      link: SseLink(
        uri: Uri.parse('http://localhost/graphql/stream'),
        transport: transport,
      ),
    );
  });

  group('SseLink against the M7 handler', () {
    test('a subscription gives every event and ends', () async {
      final events = await client.subscribe(const TicksSubscription()).toList();
      expect(events.map((e) => (e as GraphQLData<int>).data), [1, 2, 3]);
      expect(transport.contentTypes.single, startsWith('text/event-stream'));
    });

    test('cancelling a subscription cancels the server source', () async {
      final endless = TickSource(isEndless: true);
      final other = GraphQLClient(
        link: SseLink(
          uri: Uri.parse('http://localhost/graphql/stream'),
          transport: HandlerTransport(
            GraphQLHttpHandler<Object?>(
              const TestServer().build(ticks: endless),
            ),
          ),
        ),
      );
      final first = await other.subscribe(const TicksSubscription()).first;
      expect((first as GraphQLData<int>).data, 1);
      await endless.whenCancelled;
      expect(endless.isCancelled, isTrue);
    });

    test('a query is one next event', () async {
      final response = await client.query(const GreetQuery('Ada'));
      expect((response as GraphQLData<String>).data, 'Hello, Ada!');
      expect(transport.statuses, [200]);
    });

    test('a validation error arrives inside the accepted stream', () async {
      final response = await client.query(const UnknownFieldQuery());
      final errors = (response as GraphQLErrors<String>).errors;
      expect(errors.map(codeOf), ['GQL205']);
      expect(transport.contentTypes.single, startsWith('text/event-stream'));
    });
  });
}
