import 'dart:async';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/server_fixture.dart';
import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();

  setUp(() => http.contexts = 0);

  group('media types', () {
    test('answers a GET with application/graphql-response+json', () async {
      final response = await http.handler().handle(
        http.get(
          {'query': '{ hello }'},
          headers: {
            ...HttpFixture.preflight,
            ...HttpFixture.modernClient,
          },
        ),
      );
      expect(response.status, 200);
      expect(
        response.headers['content-type'],
        'application/graphql-response+json; charset=utf-8',
      );
      expect(await http.text(response), '{"data":{"hello":"world"}}');
    });

    test('answers a legacy Accept with application/json', () async {
      final response = await http.handler().handle(
        http.post(
          {'query': '{ hello }'},
          headers: {'accept': 'application/json'},
        ),
      );
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('answers a missing Accept with application/json', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ hello }'}),
      );
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
    });

    test('answers an Accept it cannot satisfy with 406', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ hello }'}, headers: {'accept': 'text/html'}),
      );
      expect(response.status, 406);
      expect(await http.code(response), 'GQL422');
      expect(
        await http.message(response),
        'The Accept header allows none of application/graphql-response+json, '
        'application/json and text/event-stream.',
      );
    });

    test('writes a refusal as application/json', () async {
      final response = await http.handler().handle(
        http.post({'query': '{ hello }'}, headers: {'accept': 'text/html'}),
      );
      expect(
        response.headers['content-type'],
        'application/json; charset=utf-8',
      );
    });
  });

  group('requests', () {
    test('runs a POST query', () async {
      final response = await http.handler().handle(
        http.post({
          'query': r'query Q($n: String!) { greet(name: $n) }',
          'operationName': 'Q',
          'variables': {'n': 'Ann'},
        }),
      );
      expect(await http.json(response), {
        'data': {'greet': 'Ann'},
      });
    });

    test('accepts a content type with an upper-case utf-8 charset', () async {
      final response = await http.handler().handle(
        http.post(
          {'query': '{ hello }'},
          headers: {'content-type': 'Application/JSON; charset=UTF-8'},
        ),
      );
      expect(response.status, 200);
    });

    test('runs a GET query with variables in the query string', () async {
      final response = await http.handler().handle(
        http.get({
          'query': r'query($n: String!) { greet(name: $n) }',
          'variables': '{"n":"Bo"}',
        }),
      );
      expect(await http.json(response), {
        'data': {'greet': 'Bo'},
      });
    });

    test('matches the method ignoring case', () async {
      final response = await http.handler().handle(
        HttpRequestData(
          method: 'get',
          uri: Uri(path: '/graphql', queryParameters: {'query': '{ hello }'}),
          headers: HttpFixture.preflight,
        ),
      );
      expect(response.status, 200);
    });

    test('passes the extension header on to the response', () async {
      final response = await http
          .handler(
            extensions: const [HeaderExtension()],
          )
          .handle(http.post({'query': '{ hello }'}));
      expect(response.headers['x-extension'], 'yes');
    });

    test('hands the pipeline the method, URI and source', () async {
      RequestInfo? seen;
      const source = Object();
      await http
          .handler(
            contextFactory: (info) {
              seen = info;
              return const Ctx('x');
            },
          )
          .handle(
            HttpRequestData(
              method: 'POST',
              uri: Uri.parse('http://host/graphql?a=b'),
              headers: const {'content-type': 'application/json'},
              body: Stream.value('{"query":"{ hello }"}'.codeUnits),
              source: source,
            ),
          );
      expect(
        (seen?.method, seen?.uri.toString()),
        ('POST', 'http://host/graphql?a=b'),
      );
      expect(seen?.source, same(source));
    });

    test('lets the cancel signal reach the pipeline', () async {
      final signal = CancelSignal();
      Timer.run(signal.cancel);
      final response = await http.handler().handle(
        http.post(
          {'query': '{ slow }'},
          headers: HttpFixture.modernClient,
          cancelSignal: signal,
        ),
      );
      expect((response.status, await http.code(response)), (294, 'GQL350'));
    });
  });

  group('refusals before the pipeline', () {
    test('refuses a PUT with 405 and the allowed methods', () async {
      final response = await http.handler().handle(
        HttpRequestData(method: 'PUT', uri: Uri.parse('/graphql')),
      );
      expect((response.status, await http.code(response)), (405, 'GQL420'));
      expect(response.headers['allow'], 'GET, POST');
      expect(
        await http.message(response),
        'Only GET and POST requests are supported.',
      );
    });

    test('refuses OPTIONS with 405', () async {
      final response = await http.handler().handle(
        HttpRequestData(method: 'OPTIONS', uri: Uri.parse('/graphql')),
      );
      expect(response.status, 405);
    });

    test('refuses a URI longer than maxUriLength with 414', () async {
      final response = await http
          .handler(
            options: const HttpOptions(maxUriLength: 40),
          )
          .handle(http.get({'query': '{ hello hello hello hello hello }'}));
      expect((response.status, await http.code(response)), (414, 'GQL426'));
      expect(
        await http.message(response),
        'The request URI is longer than 40 characters.',
      );
    });

    test('checks the URI before the method', () async {
      final response = await http
          .handler(
            options: const HttpOptions(maxUriLength: 10),
          )
          .handle(
            HttpRequestData(method: 'PUT', uri: Uri.parse('/a/long/path/here')),
          );
      expect(response.status, 414);
    });

    test('checks the method before the Accept header', () async {
      final response = await http.handler().handle(
        HttpRequestData(
          method: 'PUT',
          uri: Uri.parse('/graphql'),
          headers: const {'accept': 'text/html'},
        ),
      );
      expect(response.status, 405);
    });

    test('builds no context for a refusal', () async {
      await http.handler().handle(
        http.post({'query': '{ hello }'}, headers: {'accept': 'text/html'}),
      );
      expect(http.contexts, 0);
    });
  });

  group('the constructor', () {
    void expectRejected(HttpOptions options, String name) {
      expect(
        () => http.handler(options: options),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', name),
        ),
      );
    }

    test('rejects a zero maxBodyBytes', () {
      expectRejected(const HttpOptions(maxBodyBytes: 0), 'maxBodyBytes');
    });

    test('rejects a zero bodyTimeout', () {
      expectRejected(
        const HttpOptions(bodyTimeout: Duration.zero),
        'bodyTimeout',
      );
    });

    test('rejects a negative bodyTimeout', () {
      expectRejected(
        const HttpOptions(bodyTimeout: Duration(seconds: -1)),
        'bodyTimeout',
      );
    });

    test('rejects a zero maxJsonDepth', () {
      expectRejected(const HttpOptions(maxJsonDepth: 0), 'maxJsonDepth');
    });

    test('rejects a maxJsonDepth above what the JSON reader supports', () {
      expectRejected(const HttpOptions(maxJsonDepth: 1001), 'maxJsonDepth');
    });

    test('rejects a zero maxUriLength', () {
      expectRejected(const HttpOptions(maxUriLength: 0), 'maxUriLength');
    });

    test('accepts the defaults', () {
      expect(http.handler, returnsNormally);
    });
  });
}
