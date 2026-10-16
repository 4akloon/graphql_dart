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

  SseLink linkOf() => SseLink(uri: uri, transport: transport);

  List<int> bytes(String text) => utf8.encode(text);

  Future<List<LinkResult>> send(
    LinkRequest request, [
    SseLink? using,
  ]) => (using ?? linkOf())
      .request(request, (request) => const Stream.empty())
      .toList();

  LinkRequest ticks() => LinkRequest.of(const TicksSubscription());

  const twoTicks =
      'event: next\ndata: {"data":{"ticks":1}}\n\n'
      'event: next\ndata: {"data":{"ticks":2}}\n\n'
      'event: complete\ndata:\n\n';

  ClientFailure failureOf(LinkResult result) => (result as LinkFailure).failure;

  group('sends', () {
    test('a POST with the JSON body and the stream headers', () async {
      transport.answer(twoTicks, contentType: 'text/event-stream');
      await send(ticks());
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri, uri);
      expect(request.headers, {
        'accept': 'text/event-stream',
        'content-type': 'application/json',
      });
      expect(jsonDecode(transport.bodies.single), {
        'query': 'subscription Ticks{ticks}',
        'operationName': 'Ticks',
      });
      expect(request.contentLength, bytes(transport.bodies.single).length);
    });

    test('the protocol headers over the link and the context ones', () async {
      transport.answer(twoTicks, contentType: 'text/event-stream');
      await send(
        LinkRequest.of(
          const TicksSubscription(),
          context: LinkContext([
            RequestHeaders({'X-User': 'c'}),
          ]),
        ),
        SseLink(
          uri: uri,
          transport: transport,
          headers: {
            'Accept': 'text/plain',
            'Content-Type': 'text/plain',
            'X-User': 'b',
            'X-App': 'a',
          },
        ),
      );
      expect(transport.requests.single.headers, {
        'accept': 'text/event-stream',
        'content-type': 'application/json',
        'x-user': 'c',
        'x-app': 'a',
      });
    });

    test('a query too, as a POST', () async {
      transport.answer(
        'event: next\ndata: {"data":{"hello":"world"}}\n\n'
        'event: complete\ndata:\n\n',
        contentType: 'text/event-stream',
      );
      final response = await GraphQLClient(
        link: linkOf(),
      ).query(const HelloQuery());
      expect((response as GraphQLData<String>).data, 'world');
      expect(transport.requests.single.method, 'POST');
    });

    test('nothing for a request with files, which is GQL468', () async {
      final results = await send(
        LinkRequest.of(
          const RenameMutation('a'),
          context: LinkContext([
            UploadFiles([
              UploadFile.fromBytes([1], filename: 'a'),
            ]),
          ]),
        ),
      );
      expect(transport.requests, isEmpty);
      final failure = failureOf(results.single) as UnsupportedOperation;
      expect(failure.code, DiagnosticCode.operationNotSupportedByLink);
    });
  });

  group('reads', () {
    test('every next event in order, with the HTTP status', () async {
      transport.answer(twoTicks, contentType: 'text/event-stream');
      final results = await send(ticks());
      expect(results, hasLength(2));
      for (final (index, result) in results.indexed) {
        final payload = result as LinkPayload;
        expect(
          (payload.payload as ExecutionResult).data,
          JsonObject({'ticks': JsonNumber(index + 1)}),
        );
        expect(payload.context.entry<HttpResponseInfo>()?.statusCode, 200);
      }
    });

    test('a charset parameter on the content type', () async {
      transport.answer(
        twoTicks,
        contentType: 'text/event-stream; charset=utf-8',
      );
      expect(await send(ticks()), hasLength(2));
    });

    test('a subscription through the client, end to end', () async {
      transport.answer(twoTicks, contentType: 'text/event-stream');
      final responses = await GraphQLClient(
        link: linkOf(),
      ).subscribe(const TicksSubscription()).toList();
      expect([for (final r in responses) (r as GraphQLData<int>).data], [1, 2]);
    });

    test(
      'a complete event ends the stream and releases the connection',
      () async {
        final body = StreamController<List<int>>()
          ..add(bytes('event: complete\ndata:\n\n'));
        transport.answerStream(body.stream);
        expect(await send(ticks()), isEmpty);
        expect(body.hasListener, isFalse);
        await body.close();
      },
    );

    test('an event of another type as GQL473, and ends', () async {
      transport.answer(
        'event: next\ndata: {"data":{"ticks":1}}\n\n'
        'event: ping\ndata: x\n\n'
        'event: next\ndata: {"data":{"ticks":2}}\n\n',
        contentType: 'text/event-stream',
      );
      final results = await send(ticks());
      expect(results, hasLength(2));
      expect(
        failureOf(results.last).message,
        'The event stream sent an event of type "ping", which graphql-sse '
        'does not define.',
      );
      expect(failureOf(results.last).code, DiagnosticCode.malformedEventStream);
    });

    test('an event without a type as GQL473', () async {
      transport.answer('data: {}\n\n', contentType: 'text/event-stream');
      expect(
        failureOf((await send(ticks())).single).message,
        contains('"message"'),
      );
    });

    test('a body that ends before complete as GQL473', () async {
      transport.answer(
        'event: next\ndata: {"data":{"ticks":1}}\n\n',
        contentType: 'text/event-stream',
      );
      final results = await send(ticks());
      expect(results, hasLength(2));
      expect(
        failureOf(results.last).message,
        'The event stream ended without a complete event.',
      );
    });

    test('a next that is not a GraphQL response as GQL464, and ends', () async {
      transport.answer(
        'event: next\ndata: [1]\n\nevent: next\ndata: {"data":{}}\n\n',
        contentType: 'text/event-stream',
      );
      final results = await send(ticks());
      expect(results, hasLength(1));
      expect(failureOf(results.single).code, DiagnosticCode.malformedResponse);
    });

    test('an exception of the body as GQL460', () async {
      transport.answerStream(Stream.error(Exception('reset')));
      final results = await send(ticks());
      expect(failureOf(results.single), isA<NetworkFailure>());
    });

    test('an exception of the transport as GQL460', () async {
      transport.answerWith((request) async => throw Exception('refused'));
      expect(failureOf((await send(ticks())).single), isA<NetworkFailure>());
    });

    test('a transport failure message hides the query string', () async {
      transport.answerWith(
        (request) async => throw Exception(
          'Connection failed, uri=https://example.com/graphql?api_key=secret',
        ),
      );
      final message = failureOf((await send(ticks())).single).message;
      expect(message, contains('https://example.com/graphql'));
      expect(message, isNot(contains('secret')));
    });

    test('a body failure message hides the query string', () async {
      transport.answerStream(
        Stream.error(
          Exception('Reset, uri=https://example.com/graphql?api_key=secret'),
        ),
      );
      final message = failureOf((await send(ticks())).single).message;
      expect(message, isNot(contains('secret')));
    });

    test('a single answer failure message hides the query string', () async {
      transport.answerWith(
        (request) async => TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: Stream.error(
            Exception('Reset, uri=https://example.com/graphql?api_key=secret'),
          ),
        ),
      );
      final message = failureOf((await send(ticks())).single).message;
      expect(message, isNot(contains('secret')));
    });
  });

  group('other answers', () {
    test('a 400 with GraphQL errors is an errors response', () async {
      transport.answer(
        '{"errors":[{"message":"bad"}]}',
        status: 400,
      );
      final response = await GraphQLClient(
        link: linkOf(),
      ).subscribe(const TicksSubscription()).first;
      expect((response as GraphQLErrors<int>).errors.single.message, 'bad');
    });

    test('a 2xx application/json answer is one result', () async {
      transport.answer(
        '{"data":{"ticks":5}}',
        contentType: 'application/json',
      );
      final results = await send(ticks());
      expect(results.single, isA<LinkPayload>());
    });

    test('a 2xx text/html answer as GQL462', () async {
      transport.answer('<html>', contentType: 'text/html');
      expect(
        failureOf((await send(ticks())).single).code,
        DiagnosticCode.unsupportedResponseType,
      );
    });

    test('an event stream in another charset as GQL462', () async {
      transport.answer(
        twoTicks,
        contentType: 'text/event-stream; charset=latin1',
      );
      expect(
        failureOf((await send(ticks())).single).code,
        DiagnosticCode.unsupportedResponseType,
      );
    });

    test('a 500 as GQL461', () async {
      transport.answer('oops', status: 500, contentType: 'text/plain');
      expect(failureOf((await send(ticks())).single), isA<HttpStatusFailure>());
    });
  });

  group('limits', () {
    test(
      'an event past maxEventBytes is GQL463 and cancels the body',
      () async {
        var isCancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => isCancelled = true,
        )..add(bytes('event: next\ndata: ${'x' * 100}\n\n'));
        transport.answerStream(body.stream);
        final results = await send(
          ticks(),
          SseLink(uri: uri, transport: transport, maxEventBytes: 50),
        );
        expect(
          failureOf(results.single).code,
          DiagnosticCode.responseTooLarge,
        );
        expect(
          failureOf(results.single).message,
          'An event is longer than 50 bytes.',
        );
        expect(isCancelled, isTrue);
        await body.close();
      },
    );

    test('invalid UTF-8 as GQL464', () async {
      transport.answerStream(
        Stream.value([0x64, 0xFF, 0x0A, 0x0A]),
      );
      expect(
        failureOf((await send(ticks())).single).code,
        DiagnosticCode.malformedResponse,
      );
    });

    test('a negative maxEventBytes is a RangeError', () {
      expect(
        () => SseLink(uri: uri, transport: transport, maxEventBytes: -1),
        throwsRangeError,
      );
    });

    test('a depth outside the supported range is a RangeError', () {
      for (final depth in [0, JsonReader.maxSupportedDepth + 1]) {
        expect(
          () =>
              SseLink(uri: uri, transport: transport, maxResponseDepth: depth),
          throwsRangeError,
        );
      }
    });

    test('the default event limit is 16 MiB', () {
      expect(SseLink.defaultMaxEventBytes, 16 * 1024 * 1024);
    });
  });

  group('cancelling', () {
    test('aborts the request and cancels the body', () async {
      var isCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      )..add(bytes('event: next\ndata: {"data":{"ticks":1}}\n\n'));
      transport.answerStream(body.stream);
      var isAborted = false;
      final received = Completer<LinkResult>();
      final subscription = linkOf()
          .request(ticks(), (request) => const Stream.empty())
          .listen(received.complete);
      await received.future;
      unawaited(
        transport.requests.single.abortTrigger?.then((_) => isAborted = true),
      );
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(isAborted, isTrue);
      expect(isCancelled, isTrue);
      await body.close();
    });

    test('before the answer arrives aborts the request', () async {
      transport.hang();
      final subscription = linkOf()
          .request(ticks(), (request) => const Stream.empty())
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      var isAborted = false;
      unawaited(
        transport.requests.single.abortTrigger?.then((_) => isAborted = true),
      );
      await subscription.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(isAborted, isTrue);
    });
  });
}
