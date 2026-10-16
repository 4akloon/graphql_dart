import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_transport.dart';
import '../support/test_operations.dart';

void main() {
  final uri = Uri.parse('https://example.com/graphql');
  late FakeTransport transport;

  setUp(() => transport = FakeTransport());

  SseLink linkOf({int maxEventBytes = 4096}) =>
      SseLink(uri: uri, transport: transport, maxEventBytes: maxEventBytes);

  Future<List<LinkResult>> send([SseLink? using]) => (using ?? linkOf())
      .request(
        LinkRequest.of(const TicksSubscription()),
        (request) => const Stream.empty(),
      )
      .toList();

  List<int> bytes(String text) => utf8.encode(text);

  void serve(String text) =>
      transport.answer(text, contentType: 'text/event-stream');

  ClientFailure failureOf(LinkResult result) => (result as LinkFailure).failure;

  const tick = 'event: next\ndata: {"data":{"ticks":1}}\n\n';
  const complete = 'event: complete\ndata:\n\n';

  group('a stream of unexpected events', () {
    test('an unknown event type is GQL473', () async {
      serve('event: ping\ndata: {}\n\n$complete');
      final results = await send();
      expect(failureOf(results.single), isA<EventStreamFailure>());
    });

    test('an event without a type is GQL473', () async {
      serve('data: {"data":{"ticks":1}}\n\n$complete');
      final results = await send();
      expect(failureOf(results.single), isA<EventStreamFailure>());
    });

    test('a next with invalid JSON is GQL464', () async {
      serve('event: next\ndata: {not json\n\n$complete');
      final results = await send();
      expect(
        failureOf(results.single).code,
        DiagnosticCode.malformedResponse,
      );
    });

    test('a next that is not a GraphQL response is GQL464', () async {
      serve('event: next\ndata: {"hello":1}\n\n$complete');
      final results = await send();
      expect(
        failureOf(results.single).code,
        DiagnosticCode.malformedResponse,
      );
    });

    test('a next nested past maxResponseDepth is GQL464', () async {
      serve(
        'event: next\ndata: {"data":{"a":{"b":{"c":{"d":1}}}}}\n\n$complete',
      );
      final results = await send(
        SseLink(uri: uri, transport: transport, maxResponseDepth: 3),
      );
      expect(
        failureOf(results.single).code,
        DiagnosticCode.malformedResponse,
      );
    });

    test('a stream that ends without complete is GQL473', () async {
      serve(tick);
      final results = await send();
      expect(results.first, isA<LinkPayload>());
      expect(failureOf(results.last), isA<EventStreamFailure>());
    });

    test('an empty stream is GQL473', () async {
      serve('');
      expect(failureOf((await send()).single), isA<EventStreamFailure>());
    });
  });

  group('a stream that is read well', () {
    test('one byte per chunk', () async {
      transport.answerStream(
        Stream.fromIterable([
          for (final byte in bytes('$tick$tick$complete')) [byte],
        ]),
      );
      final responses = await GraphQLClient(
        link: linkOf(),
      ).subscribe(const TicksSubscription()).toList();
      expect(responses, hasLength(2));
    });

    test('with CR line ends', () async {
      serve(
        'event: next\rdata: {"data":{"ticks":1}}\r\r'
        'event: complete\rdata:\r\r',
      );
      expect(await send(), hasLength(1));
    });

    test('with 10000 comment lines before an event', () async {
      serve('${': keep-alive\n' * 10000}$tick$complete');
      expect(await send(), hasLength(1));
    });

    test('with comments forever between events, in constant space', () async {
      var isCancelled = false;
      Stream<List<int>> body() async* {
        try {
          yield bytes(tick);
          while (true) {
            yield bytes(': keep-alive\n' * 100);
          }
        } finally {
          isCancelled = true;
        }
      }

      transport.answerStream(body());
      final first = await linkOf()
          .request(
            LinkRequest.of(const TicksSubscription()),
            (request) => const Stream.empty(),
          )
          .first;
      expect(first, isA<LinkPayload>());
      await Future<void>.delayed(Duration.zero);
      expect(isCancelled, isTrue);
    });
  });

  group('a stream that is too long', () {
    test('a line that never ends is GQL463 and cancels the body', () async {
      var isCancelled = false;
      Stream<List<int>> body() async* {
        try {
          while (true) {
            yield bytes('x' * 1000);
          }
        } finally {
          isCancelled = true;
        }
      }

      transport.answerStream(body());
      final results = await send();
      expect(failureOf(results.single).code, DiagnosticCode.responseTooLarge);
      expect(isCancelled, isTrue);
    });

    test('an event with endless data lines is GQL463', () async {
      var isCancelled = false;
      Stream<List<int>> body() async* {
        try {
          yield bytes('event: next\n');
          while (true) {
            yield bytes('data: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n');
          }
        } finally {
          isCancelled = true;
        }
      }

      transport.answerStream(body());
      final results = await send();
      expect(failureOf(results.single).code, DiagnosticCode.responseTooLarge);
      expect(isCancelled, isTrue);
    });

    test('an event is counted alone, not the whole stream', () async {
      serve(tick * 200 + complete);
      expect(await send(linkOf(maxEventBytes: 100)), hasLength(200));
    });
  });

  group('an answer that is not a stream', () {
    test('2xx application/json is read as one result', () async {
      transport.answer('{"data":{"ticks":9}}', contentType: 'application/json');
      final results = await send();
      expect(results.single, isA<LinkPayload>());
    });

    test('2xx text/html is GQL462', () async {
      transport.answer('<html></html>', contentType: 'text/html');
      expect(
        failureOf((await send()).single).code,
        DiagnosticCode.unsupportedResponseType,
      );
    });

    test('2xx without a content type is GQL462', () async {
      transport.answerWith(
        (request) async => TransportResponse(
          statusCode: 200,
          body: Stream.value(bytes(tick)),
        ),
      );
      expect(
        failureOf((await send()).single).code,
        DiagnosticCode.unsupportedResponseType,
      );
    });

    test('an event stream with a 500 status is GQL461', () async {
      transport.answer(tick, status: 500, contentType: 'text/event-stream');
      expect(failureOf((await send()).single), isA<HttpStatusFailure>());
    });
  });

  group('bad bytes and a broken connection', () {
    test('invalid UTF-8 in the stream is GQL464', () async {
      transport.answerStream(
        Stream.fromIterable([
          bytes(tick),
          [0xC0, 0xAF, 0x0A, 0x0A],
        ]),
      );
      final results = await send();
      expect(results.first, isA<LinkPayload>());
      expect(failureOf(results.last).code, DiagnosticCode.malformedResponse);
    });

    test('a character cut off by the end of the body is GQL464', () async {
      transport.answerStream(
        Stream.fromIterable([
          bytes(tick),
          [0xE2, 0x82],
        ]),
      );
      final results = await send();
      expect(failureOf(results.last).code, DiagnosticCode.malformedResponse);
    });

    test('a body that throws is GQL460, after the events before it', () async {
      Stream<List<int>> body() async* {
        yield bytes(tick);
        throw Exception('connection reset');
      }

      transport.answerStream(body());
      final results = await send();
      expect(results.first, isA<LinkPayload>());
      expect(failureOf(results.last), isA<NetworkFailure>());
    });
  });
}
