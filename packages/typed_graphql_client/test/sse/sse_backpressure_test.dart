import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_transport.dart';
import '../support/test_operations.dart';

void main() {
  final uri = Uri.parse('https://example.com/graphql');
  late FakeTransport transport;
  late Completer<TransportResponse> answer;

  setUp(() {
    transport = FakeTransport();
    answer = Completer<TransportResponse>();
    transport.answerWith((request) => answer.future);
  });

  Stream<LinkResult> open() => SseLink(uri: uri, transport: transport).request(
    LinkRequest.of(const TicksSubscription()),
    (request) => const Stream.empty(),
  );

  TransportResponse respond(Stream<List<int>> body) => TransportResponse(
    statusCode: 200,
    headers: {'content-type': 'text/event-stream'},
    body: body,
  );

  test('pausing before the answer arrives pauses the body', () async {
    final body = StreamController<List<int>>();
    final subscription = open().listen((_) {})..pause();
    await Future<void>.delayed(Duration.zero);
    answer.complete(respond(body.stream));
    await Future<void>.delayed(Duration.zero);
    expect(body.isPaused, isTrue);
    await subscription.cancel();
  });

  test('resuming lets the buffered events through', () async {
    final body = StreamController<List<int>>();
    final results = <LinkResult>[];
    final subscription = open().listen(results.add)..pause();
    await Future<void>.delayed(Duration.zero);
    answer.complete(respond(body.stream));
    await Future<void>.delayed(Duration.zero);
    body.add(utf8.encode('event: next\ndata: {"data":{"ticks":1}}\n\n'));
    await Future<void>.delayed(Duration.zero);
    expect(results, isEmpty);
    subscription.resume();
    await Future<void>.delayed(Duration.zero);
    expect(results, hasLength(1));
    await subscription.cancel();
  });

  test('cancelling before the answer arrives cancels the late body', () async {
    var isCancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () => isCancelled = true,
    );
    final subscription = open().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    answer.complete(respond(body.stream));
    await Future<void>.delayed(Duration.zero);
    expect(isCancelled, isTrue);
  });
}
