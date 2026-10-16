import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import '../server/support/hostile_fixture.dart';
import '../server/support/server_fixture.dart';
import 'support/http_fixture.dart';

/// A body that counts the bytes pulled from it and notes when it is cancelled.
final class CountingBody {
  CountingBody(this.chunkSize, this.chunkCount);

  final int chunkSize;
  final int chunkCount;
  int pulled = 0;
  bool isCancelled = false;

  Stream<List<int>> get stream async* {
    try {
      for (var index = 0; index < chunkCount; index++) {
        pulled += chunkSize;
        yield List.filled(chunkSize, 0x20);
      }
    } finally {
      isCancelled = true;
    }
  }
}

void main() {
  final http = HttpFixture();
  final hostile = HostileFixture();

  const chunk = 65536;
  const tenMebibytes = 10 * 1024 * 1024;
  const json = {'content-type': 'application/json'};

  setUp(() {
    hostile.built = 0;
    hostile.resolved = 0;
  });

  GraphQLHttpHandler<Ctx> handler([
    HttpOptions options = const HttpOptions(),
  ]) => http.handlerOver(hostile.server(), options: options);

  Future<void> expectRefused(
    HttpResponseData response,
    int status,
    String code,
  ) async {
    expect((response.status, await http.code(response)), (status, code));
    expect(hostile.built, 0, reason: 'no context may be built');
    expect(hostile.resolved, 0, reason: 'no resolver may run');
  }

  group('a body', () {
    test('declared at 10 MiB is refused without reading a byte', () async {
      final body = CountingBody(chunk, tenMebibytes ~/ chunk);
      final response = await handler().handle(
        http.postStream(
          body.stream,
          headers: {...json, 'content-length': '$tenMebibytes'},
        ),
      );
      await expectRefused(response, 413, 'GQL423');
      expect(body.pulled, 0);
    });

    test('of 10 MiB without a length is cut after the limit', () async {
      final body = CountingBody(chunk, tenMebibytes ~/ chunk);
      final response = await handler().handle(
        http.postStream(body.stream, headers: json),
      );
      await expectRefused(response, 413, 'GQL423');
      expect(body.pulled, lessThanOrEqualTo(1048576 + chunk));
      expect(body.isCancelled, isTrue);
    });

    test('with a lying low length is cut after the limit', () async {
      final body = CountingBody(chunk, tenMebibytes ~/ chunk);
      final response = await handler().handle(
        http.postStream(body.stream, headers: {...json, 'content-length': '2'}),
      );
      await expectRefused(response, 413, 'GQL423');
      expect(body.pulled, lessThanOrEqualTo(1048576 + chunk));
    });

    test('that never ends is a timeout and is released', () async {
      var isCancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      );
      addTearDown(controller.close);
      final response = await handler(
        const HttpOptions(bodyTimeout: Duration(milliseconds: 1)),
      ).handle(http.postStream(controller.stream, headers: json));
      await expectRefused(response, 408, 'GQL427');
      expect(isCancelled, isTrue);
    });

    test('that trickles one byte at a time is a timeout', () async {
      final trickle = Stream<List<int>>.periodic(
        const Duration(milliseconds: 1),
        (_) => [0x20],
      );
      final response = await handler(
        const HttpOptions(bodyTimeout: Duration(milliseconds: 30)),
      ).handle(http.postStream(trickle, headers: json));
      await expectRefused(response, 408, 'GQL427');
    });

    test('that is not UTF-8 is a 400', () async {
      final response = await handler().handle(
        // The bad byte sits inside a string: replaced by U+FFFD the JSON would
        // still be valid and the query would run.
        http.postBytes([
          ...utf8.encode('{"query":"{ hello }","operationName":"'),
          0xff,
          ...utf8.encode('"}'),
        ], headers: json),
      );
      await expectRefused(response, 400, 'GQL424');
    });

    test('that starts with a byte-order mark is a 400', () async {
      final response = await handler().handle(
        http.postBytes([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode('{"query":"{ hello }"}'),
        ], headers: json),
      );
      await expectRefused(response, 400, 'GQL424');
    });

    test('nested 100,000 arrays deep is a quick 400', () async {
      final response = await handler().handle(
        http.postBytes(utf8.encode('[' * 100000), headers: json),
      );
      await expectRefused(response, 400, 'GQL424');
    });

    test('nested 100,000 objects deep is a quick 400', () async {
      final response = await handler().handle(
        http.postBytes(utf8.encode('{"a":' * 100000), headers: json),
      );
      await expectRefused(response, 400, 'GQL424');
    });

    test('without a content type is a 415', () async {
      final response = await handler().handle(
        http.postBytes(utf8.encode('{"query":"{ hello }"}')),
      );
      await expectRefused(response, 415, 'GQL421');
    });

    test('as text/plain is a 415', () async {
      final response = await handler().handle(
        http.postBytes(
          utf8.encode('{"query":"{ hello }"}'),
          headers: {'content-type': 'text/plain'},
        ),
      );
      await expectRefused(response, 415, 'GQL421');
    });

    test('as a form is a 415', () async {
      final response = await handler().handle(
        http.postBytes(
          utf8.encode('query=%7B+hello+%7D'),
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );
      await expectRefused(response, 415, 'GQL421');
    });
  });

  group('a URI', () {
    test('of 9 KiB is a 414', () async {
      final response = await handler().handle(
        http.get({'query': 'a' * 9216}),
      );
      await expectRefused(response, 414, 'GQL426');
    });

    test('with 10,000 repeated parameters is a 414 by default', () async {
      final response = await handler().handle(
        HttpRequestData(
          method: 'GET',
          uri: Uri(
            path: '/graphql',
            query: List.filled(10000, 'query=a').join('&'),
          ),
          headers: HttpFixture.preflight,
        ),
      );
      await expectRefused(response, 414, 'GQL426');
    });

    test('with 10,000 repeated query parameters is a 422', () async {
      final response = await handler(const HttpOptions(maxUriLength: 1 << 20))
          .handle(
            HttpRequestData(
              method: 'GET',
              uri: Uri(
                path: '/graphql',
                query: List.filled(10000, 'query=a').join('&'),
              ),
              headers: HttpFixture.preflight,
            ),
          );
      await expectRefused(response, 422, 'GQL425');
    });

    test('with variables nested 100,000 deep is a quick 422', () async {
      final response = await handler(const HttpOptions(maxUriLength: 1 << 21))
          .handle(
            http.get({
              'query': '{ hello }',
              'variables': '{"a":' * 100000,
            }),
          );
      await expectRefused(response, 422, 'GQL425');
    });
  });

  group('an Accept header', () {
    test('of 10,000 ranges is answered quickly', () async {
      final accept = [
        for (var index = 0; index < 10000; index++) 'text/x$index',
        'application/json;q=0.5',
      ].join(', ');
      final response = await handler().handle(
        http.get(
          {'query': '{ hello }'},
          headers: {
            ...HttpFixture.preflight,
            'accept': accept,
          },
        ),
      );
      expect(response.status, 200);
      expect(hostile.resolved, 1);
    });

    test('of 10,000 ranges that allow nothing is a 406', () async {
      final accept = [
        for (var index = 0; index < 10000; index++) 'text/x$index',
      ].join(', ');
      final response = await handler().handle(
        http.get(
          {'query': '{ hello }'},
          headers: {
            ...HttpFixture.preflight,
            'accept': accept,
          },
        ),
      );
      await expectRefused(response, 406, 'GQL422');
    });
  });
}
