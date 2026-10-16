import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/http_fixture.dart';

void main() {
  final http = HttpFixture();

  setUp(() => http.contexts = 0);

  Future<void> expectRefusal(
    HttpResponseData response,
    int status,
    String code,
  ) async {
    expect((response.status, await http.code(response)), (status, code));
    expect(http.contexts, 0);
  }

  group('the content type', () {
    test('is required', () async {
      final response = await http.handler().handle(
        http.postBytes(utf8.encode('{"query":"{ hello }"}')),
      );
      await expectRefusal(response, 415, 'GQL421');
      expect(
        await http.message(response),
        'A POST request must have the content type application/json.',
      );
    });

    test('must not be text/plain', () async {
      final response = await http.handler().handle(
        http.post(
          {'query': '{ hello }'},
          headers: {'content-type': 'text/plain'},
        ),
      );
      await expectRefusal(response, 415, 'GQL421');
    });

    test('must not be a form', () async {
      final response = await http.handler().handle(
        http.post(
          {'query': '{ hello }'},
          headers: {'content-type': 'application/x-www-form-urlencoded'},
        ),
      );
      await expectRefusal(response, 415, 'GQL421');
    });

    test('must not name another charset', () async {
      final response = await http.handler().handle(
        http.post(
          {'query': '{ hello }'},
          headers: {'content-type': 'application/json; charset=latin1'},
        ),
      );
      await expectRefusal(response, 415, 'GQL421');
    });

    test('must not carry another parameter', () async {
      final response = await http.handler().handle(
        http.post(
          {'query': '{ hello }'},
          headers: {'content-type': 'application/json; profile=x'},
        ),
      );
      await expectRefusal(response, 415, 'GQL421');
    });
  });

  group('the size', () {
    test('is refused by content-length before the body is read', () async {
      var isListened = false;
      final controller = StreamController<List<int>>(
        onListen: () => isListened = true,
      );
      // Never listened to, so closing would wait for a listener forever.
      addTearDown(() => unawaited(controller.close()));
      final response = await http
          .handler(
            options: const HttpOptions(maxBodyBytes: 100),
          )
          .handle(
            http.postStream(
              controller.stream,
              headers: {
                'content-type': 'application/json',
                'content-length': '101',
              },
            ),
          );
      await expectRefusal(response, 413, 'GQL423');
      expect(isListened, isFalse);
      expect(
        await http.message(response),
        'The request body is larger than 100 bytes.',
      );
    });

    test('is counted when content-length is missing', () async {
      final response = await http
          .handler(
            options: const HttpOptions(maxBodyBytes: 1000),
          )
          .handle(
            http.postStream(
              Stream.fromIterable([
                List.filled(600, 0x20),
                List.filled(600, 0x20),
              ]),
              headers: {'content-type': 'application/json'},
            ),
          );
      await expectRefusal(response, 413, 'GQL423');
    });

    test('is counted when content-length lies', () async {
      final response = await http
          .handler(
            options: const HttpOptions(maxBodyBytes: 100),
          )
          .handle(
            http.postStream(
              Stream.value(List.filled(500, 0x20)),
              headers: {
                'content-type': 'application/json',
                'content-length': '5',
              },
            ),
          );
      await expectRefusal(response, 413, 'GQL423');
    });

    test('allows a body of exactly maxBodyBytes', () async {
      const body = '{"query":"{ hello }"}';
      final response = await http
          .handler(
            options: const HttpOptions(maxBodyBytes: body.length),
          )
          .handle(
            http.postBytes(
              utf8.encode(body),
              headers: {
                'content-type': 'application/json',
                'content-length': '${body.length}',
              },
            ),
          );
      expect(response.status, 200);
    });
  });

  group('the time', () {
    test('is limited for the whole body with 408', () async {
      var isCancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      );
      addTearDown(controller.close);
      final response = await http
          .handler(
            options: const HttpOptions(bodyTimeout: Duration(milliseconds: 1)),
          )
          .handle(
            http.postStream(
              controller.stream,
              headers: {'content-type': 'application/json'},
            ),
          );
      await expectRefusal(response, 408, 'GQL427');
      expect(isCancelled, isTrue);
      expect(
        await http.message(response),
        'The request body did not arrive within 1 ms.',
      );
    });

    test('is 400 when the host reports an error in the body', () async {
      final response = await http.handler().handle(
        http.postStream(
          Stream.error(StateError('connection reset')),
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectRefusal(response, 400, 'GQL424');
      expect(
        await http.message(response),
        'The request body could not be read.',
      );
    });
  });

  group('the JSON', () {
    test('is refused with 400 when it is invalid', () async {
      final response = await http.handler().handle(
        http.postBytes(
          utf8.encode('{"query":'),
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectRefusal(response, 400, 'GQL424');
    });

    test('is refused with 400 when it is nested too deep', () async {
      final response = await http
          .handler(
            options: const HttpOptions(maxJsonDepth: 4),
          )
          .handle(
            http.postBytes(
              utf8.encode('[[[[[[[[[[]]]]]]]]]]'),
              headers: {'content-type': 'application/json'},
            ),
          );
      await expectRefusal(response, 400, 'GQL424');
    });

    test('is refused with 422 when it is not an object', () async {
      final response = await http.handler().handle(http.post('{ hello }'));
      await expectRefusal(response, 422, 'GQL425');
    });

    test('is refused with 422 when a field has the wrong type', () async {
      final response = await http.handler().handle(http.post({'query': 1}));
      await expectRefusal(response, 422, 'GQL425');
    });

    test(
      'is refused with 422 when it is an array and batching is off',
      () async {
        final response = await http.handler().handle(
          http.post([
            {'query': '{ hello }'},
          ]),
        );
        await expectRefusal(response, 422, 'GQL428');
      },
    );
  });

  group('the GET parameters', () {
    test('refuse a repeated query with 422', () async {
      final response = await http.handler().handle(
        HttpRequestData(
          method: 'GET',
          uri: Uri.parse('/graphql?query={a}&query={b}'),
          headers: HttpFixture.preflight,
        ),
      );
      await expectRefusal(response, 422, 'GQL425');
    });
  });
}
