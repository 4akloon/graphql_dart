import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

import '../support/fake_transport.dart';
import '../support/test_operations.dart';

void main() {
  final uri = Uri.parse('https://example.com/graphql');
  late FakeTransport transport;

  setUp(() => transport = FakeTransport());

  GraphQLClient clientOf(HttpLink link) => GraphQLClient(link: link);

  group('sends', () {
    test('a POST with the JSON body to the URI', () async {
      transport.answer('{"data":{"greet":"hi"}}');
      await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).query(const GreetQuery('Ann'));
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri, uri);
      expect(jsonDecode(transport.bodies.single), {
        'query': r'query Greet($name:String!){greet(name:$name)}',
        'operationName': 'Greet',
        'variables': {'name': 'Ann'},
      });
      expect(
        request.contentLength,
        utf8.encode(transport.bodies.single).length,
      );
    });

    test('the JSON content type and the accept header', () async {
      transport.answer('{"data":{"hello":"world"}}');
      await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).query(const HelloQuery());
      expect(transport.requests.single.headers, {
        'accept': 'application/graphql-response+json, application/json;q=0.9',
        'content-type': 'application/json',
      });
    });

    test('the link headers over its own and the context headers over '
        'the link headers', () async {
      transport.answer('{"data":{"hello":"world"}}');
      await clientOf(
        HttpLink(
          uri: uri,
          transport: transport,
          headers: {'Accept': 'application/json', 'X-App': 'a', 'X-User': 'b'},
        ),
      ).query(
        const HelloQuery(),
        context: LinkContext([
          RequestHeaders({'X-User': 'c'}),
        ]),
      );
      expect(transport.requests.single.headers, {
        'accept': 'application/json',
        'content-type': 'application/json',
        'x-app': 'a',
        'x-user': 'c',
      });
    });

    test('the JSON content type over a configured one', () async {
      transport.answer('{"data":{"hello":"world"}}');
      await clientOf(
        HttpLink(
          uri: uri,
          transport: transport,
          headers: {'Content-Type': 'text/plain'},
        ),
      ).query(
        const HelloQuery(),
        context: LinkContext([
          RequestHeaders({'CONTENT-TYPE': 'text/xml'}),
        ]),
      );
      expect(
        transport.requests.single.headers['content-type'],
        'application/json',
      );
    });

    test('no query text when the request sends the hash alone', () async {
      transport.answer('{"data":{"hello":"world"}}');
      final link = HttpLink(uri: uri, transport: transport);
      await link
          .request(
            LinkRequest.of(
              const HelloQuery(),
            ).withDocumentText(sendsDocumentText: false),
            (request) => const Stream.empty(),
          )
          .toList();
      expect(jsonDecode(transport.bodies.single), {'operationName': 'Hello'});
    });
  });

  group('answers', () {
    test('with the data and the HTTP status in the context', () async {
      transport.answer('{"data":{"hello":"world"}}');
      final response = await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).query(const HelloQuery());
      final data = response as GraphQLData<String>;
      expect(data.data, 'world');
      expect(data.context.entry<HttpResponseInfo>()?.statusCode, 200);
    });

    test('a subscription with GQL468 without sending it', () async {
      final response = await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).subscribe(const TicksSubscription()).first;
      final failure = (response as GraphQLTransportFailure).failure;
      expect(failure.code, DiagnosticCode.operationNotSupportedByLink);
      expect(transport.requests, isEmpty);
    });

    test('an exception of the transport with a network failure', () async {
      transport.answerWith(
        (request) async => throw const FormatException('refused'),
      );
      final response = await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).query(const HelloQuery());
      final failure = (response as GraphQLTransportFailure).failure;
      expect((failure as NetworkFailure).cause.toString(), contains('refused'));
    });

    test('a network failure message hides the query string', () async {
      transport.answerWith(
        (request) async => throw Exception(
          'Connection failed, uri=https://example.com/graphql?variables=secret',
        ),
      );
      final response = await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).query(const HelloQuery());
      final message = (response as GraphQLTransportFailure).failure.message;
      expect(message, contains('https://example.com/graphql'));
      expect(message, isNot(contains('secret')));
    });

    test('an exception of the body with a network failure', () async {
      transport.answerWith(
        (request) async => TransportResponse(
          statusCode: 200,
          headers: {'content-type': 'application/json'},
          body: Stream.error(const FormatException('reset')),
        ),
      );
      final response = await clientOf(
        HttpLink(uri: uri, transport: transport),
      ).query(const HelloQuery());
      expect(
        (response as GraphQLTransportFailure).failure,
        isA<NetworkFailure>(),
      );
    });
  });

  group('timeout', () {
    test('aborts a slow request with RequestTimedOut', () {
      fakeAsync((async) {
        transport.hang();
        GraphQLResponse<String>? response;
        unawaited(
          clientOf(
            HttpLink(
              uri: uri,
              transport: transport,
              timeout: const Duration(seconds: 5),
            ),
          ).query(const HelloQuery()).then((value) => response = value),
        );
        async.elapse(const Duration(seconds: 4));
        expect(response, isNull);
        async.elapse(const Duration(seconds: 1));
        final failure = (response as GraphQLTransportFailure).failure;
        expect(failure, isA<RequestTimedOut>());
      });
    });

    test('leaves no timer once the answer has come', () {
      fakeAsync((async) {
        transport.answer('{"data":{"hello":"world"}}');
        unawaited(
          clientOf(
            HttpLink(
              uri: uri,
              transport: transport,
              timeout: const Duration(seconds: 5),
            ),
          ).query(const HelloQuery()),
        );
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  test('cancelling aborts the request', () async {
    transport.hang();
    final token = CancelToken();
    final response = clientOf(
      HttpLink(uri: uri, transport: transport),
    ).query(const HelloQuery(), cancelToken: token);
    await pumpEventQueue();
    final aborted = transport.requests.single.abortTrigger;
    token.cancel('left');
    await expectLater(aborted, completes);
    expect(
      ((await response) as GraphQLTransportFailure).failure,
      isA<RequestCancelled>(),
    );
  });

  test('refuses a depth outside what the JSON reader supports', () {
    expect(
      () => HttpLink(uri: uri, transport: transport, maxResponseDepth: 0),
      throwsRangeError,
    );
  });
}
