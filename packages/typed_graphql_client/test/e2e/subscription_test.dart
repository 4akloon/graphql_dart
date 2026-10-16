import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/test_operations.dart';
import 'support/pipeline_transport.dart';
import 'support/test_server.dart';
import 'support/tick_source.dart';

void main() {
  late TickSource ticks;
  late GraphQLClient client;

  GraphQLClient clientOver(TickSource source) => GraphQLClient(
    link: SseLink(
      uri: Uri.parse('http://localhost/graphql'),
      transport: PipelineTransport(const TestServer().build(ticks: source)),
    ),
  );

  setUp(() {
    ticks = TickSource();
    client = clientOver(ticks);
  });

  group('server-sent events over the pipeline', () {
    test('a subscription delivers the ticks and ends', () async {
      final responses = await client
          .subscribe(const TicksSubscription())
          .toList();
      expect(
        responses.map((response) => (response as GraphQLData<int>).data),
        [1, 2, 3],
      );
    });

    test('cancelling after the first tick cancels the source', () async {
      // An endless source only a cancel can end: with the finite one, the
      // server would cancel it itself when it ran out of ticks.
      ticks = TickSource(isEndless: true);
      client = clientOver(ticks);
      final subscription = client
          .subscribe(const TicksSubscription())
          .listen(null);
      final first = Completer<GraphQLResponse<int>>();
      subscription.onData(first.complete);
      await first.future;
      await subscription.cancel();
      await ticks.whenCancelled;
      expect(ticks.isCancelled, isTrue);
    });

    test('a query through the link gives the data', () async {
      final response = await client.query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'hello');
    });
  });
}
