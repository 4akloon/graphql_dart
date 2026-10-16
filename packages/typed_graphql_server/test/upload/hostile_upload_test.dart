import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:typed_graphql_server/src/upload/memory_upload.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/multipart_body.dart';
import 'support/upload_http_fixture.dart';

void main() {
  late UploadHttpFixture fixture;

  setUp(() => fixture = UploadHttpFixture());

  Future<void> expectRefused(
    HttpResponseData response,
    int status,
    String code, [
    String? message,
  ]) async {
    expect((response.status, await fixture.code(response)), (status, code));
    if (message != null) expect(await fixture.message(response), message);
  }

  MultipartBody withMap(String map, {String? operations}) => MultipartBody()
      .field(
        'operations',
        operations ?? '{"query":"{ ok }","variables":{"f":null}}',
      )
      .field('map', map)
      .file('0', utf8.encode('x'));

  group('a forged request', () {
    test(
      'without the preflight header stores nothing and reads nothing',
      () async {
        var pulled = 0;
        final response = await fixture.handler().handle(
          fixture.post(
            fixture.single(),
            hasPreflight: false,
            stream: fixture.single().stream().map((chunk) {
              pulled += chunk.length;
              return chunk;
            }),
          ),
        );
        await expectRefused(response, 403, 'GQL403');
        expect(pulled, 0);
        fixture.expectUntouched();
      },
    );
  });

  group('the structure', () {
    test('without a boundary is refused', () async {
      final response = await fixture.handler().handle(
        fixture.post(fixture.single(), contentType: 'multipart/form-data'),
      );
      await expectRefused(response, 400, 'GQL440');
      fixture.expectUntouched();
    });

    test('with the map before the operations is refused', () async {
      final body = MultipartBody()
          .field('map', '{}')
          .field('operations', '{"query":"{ ok }"}');
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(
        response,
        400,
        'GQL440',
        'The first field of a multipart request must be operations.',
      );
      fixture.expectUntouched();
    });

    test('with a file before the map is refused', () async {
      final body = MultipartBody()
          .field('operations', '{"query":"{ ok }"}')
          .file('0', utf8.encode('x'))
          .field('map', '{"0":["variables.f"]}');
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(
        response,
        400,
        'GQL440',
        'The second field of a multipart request must be map.',
      );
      fixture.expectUntouched();
    });

    test('with a part the map does not name is refused', () async {
      final body = fixture.single().file('stranger', utf8.encode('x'));
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(
        response,
        400,
        'GQL440',
        'The request contains a file the map does not name.',
      );
      expect(fixture.resolved, 0);
      expect(fixture.storage.held, isEmpty);
      expect(fixture.uploads.registry.length, 0);
    });

    test('whose body ends in the middle of a file is refused', () async {
      final bytes = fixture.single().bytes;
      final response = await fixture.handler().handle(
        fixture.post(
          fixture.single(),
          stream: Stream.value(bytes.sublist(0, bytes.length - 20)),
        ),
      );
      await expectRefused(response, 400, 'GQL440');
      fixture.expectNothingKept();
    });

    test('whose operations are nested 100,000 deep is refused', () async {
      final deep = '${'[' * 100000}${']' * 100000}';
      final body = MultipartBody().field('operations', deep).field('map', '{}');
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(
        response,
        400,
        'GQL440',
        'The operations field is not valid JSON.',
      );
      fixture.expectUntouched();
    });
  });

  group('the map', () {
    test('naming 10,000 paths is refused', () async {
      final paths = [for (var i = 0; i < 10000; i++) 'variables.f$i'];
      final body = withMap(jsonEncode({'0': paths}));
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(
        response,
        413,
        'GQL442',
        'The map may name at most 10 paths.',
      );
      fixture.expectUntouched();
    });

    test('naming 10,000 files is refused', () async {
      final body = withMap(
        jsonEncode({
          for (var i = 0; i < 10000; i++) '$i': ['variables.f$i'],
        }),
      );
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(response, 413, 'GQL442');
      fixture.expectUntouched();
    });

    for (final (name, map, operations) in [
      ('query', '{"0":["query"]}', null),
      (
        'extensions',
        '{"0":["extensions.a"]}',
        '{"query":"{ ok }","extensions":{"a":null}}',
      ),
      (
        'operationName',
        '{"0":["operationName"]}',
        '{"query":"{ ok }","operationName":null}',
      ),
      ('a value that is not null', '{"0":["variables.g"]}', null),
    ]) {
      test('with a path into $name is refused', () async {
        final response = await fixture.handler().handle(
          fixture.post(
            withMap(
              map,
              operations:
                  operations ??
                  '{"query":"{ ok }","variables":{"f":null,"g":"text"}}',
            ),
          ),
        );
        await expectRefused(
          response,
          400,
          'GQL440',
          'A map path must name a null value inside variables.',
        );
        fixture.expectUntouched();
      });
    }
  });

  group('the files', () {
    test('over the file limit leave nothing in the storage', () async {
      fixture = UploadHttpFixture(
        limits: const UploadLimits(maxFileBytes: 5),
      );
      final response = await fixture.handler().handle(
        fixture.post(fixture.single(content: 'longer than five')),
      );
      await expectRefused(
        response,
        413,
        'GQL441',
        'A file is larger than 5 bytes.',
      );
      expect(fixture.storage.stored, 0);
      fixture.expectNothingKept();
    });

    test('over the file count leave nothing in the storage', () async {
      fixture = UploadHttpFixture(limits: const UploadLimits(maxFiles: 1));
      final body = MultipartBody()
          .field(
            'operations',
            '{"query":"{ ok }","variables":{"a":null,"b":null}}',
          )
          .field('map', '{"0":["variables.a"],"1":["variables.b"]}')
          .file('0', utf8.encode('x'))
          .file('1', utf8.encode('y'));
      final response = await fixture.handler().handle(fixture.post(body));
      await expectRefused(
        response,
        413,
        'GQL442',
        'The map may name at most 1 files.',
      );
      fixture.expectUntouched();
    });

    test('in a body over the request limit stop the read', () async {
      fixture = UploadHttpFixture(
        limits: const UploadLimits(maxRequestBytes: 400),
      );
      final bytes = fixture.single(content: 'x' * 100000).bytes;
      var pulled = 0;
      final chunks =
          Stream.fromIterable([
            for (var start = 0; start < bytes.length; start += 100)
              Uint8List.fromList(
                bytes.sublist(
                  start,
                  start + 100 > bytes.length ? bytes.length : start + 100,
                ),
              ),
          ]).map((chunk) {
            pulled += chunk.length;
            return chunk;
          });
      final response = await fixture.handler().handle(
        fixture.post(fixture.single(), stream: chunks),
      );
      await expectRefused(
        response,
        413,
        'GQL441',
        'The request body is larger than 400 bytes.',
      );
      expect(pulled, lessThan(bytes.length));
      fixture.expectNothingKept();
    });
  });

  group('a token sent as a literal', () {
    test('of a request that is over is a coercion error', () async {
      final token = fixture.uploads.registry.register(
        MemoryUpload('secret.txt', 'text/plain', Uint8List.fromList([1])),
      );
      fixture.uploads.registry.remove([token]);
      final response = await fixture.handler().handle(
        HttpRequestData(
          method: 'POST',
          uri: Uri.parse('/graphql'),
          headers: const {'content-type': 'application/json'},
          body: Stream.value(
            utf8.encode(
              jsonEncode({
                'query': UploadHttpFixture.uploadOperation,
                'variables': {'f': token},
              }),
            ),
          ),
        ),
      );
      final body = (await fixture.json(response))! as Map<String, Object?>;
      expect(body['errors'], isNotEmpty);
      expect(fixture.resolved, 0);
    });

    test('that was never issued is a coercion error', () async {
      final response = await fixture.handler().handle(
        HttpRequestData(
          method: 'POST',
          uri: Uri.parse('/graphql'),
          headers: const {'content-type': 'application/json'},
          body: Stream.value(
            utf8.encode(
              jsonEncode({
                'query': UploadHttpFixture.uploadOperation,
                'variables': {'f': 'upload:${'0' * 32}'},
              }),
            ),
          ),
        ),
      );
      final body = (await fixture.json(response))! as Map<String, Object?>;
      expect(body['errors'], isNotEmpty);
      expect(fixture.resolved, 0);
    });
  });
}
