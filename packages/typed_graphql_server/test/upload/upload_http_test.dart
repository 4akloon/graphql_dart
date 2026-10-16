import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/multipart_body.dart';
import 'support/upload_http_fixture.dart';

void main() {
  late UploadHttpFixture fixture;

  setUp(() => fixture = UploadHttpFixture());

  group('a multipart request', () {
    test('delivers its file to the resolver', () async {
      final response = await fixture.handler().handle(
        fixture.post(fixture.single()),
      );
      expect(response.status, 200);
      expect(await fixture.json(response), {
        'data': {'upload': 'file.txt:hello'},
      });
    });

    test('delivers two files in a list variable', () async {
      final body = MultipartBody()
          .field(
            'operations',
            jsonEncode({
              'query': r'mutation ($f: [Upload!]!) { uploadMany(files: $f) }',
              'variables': {
                'f': [null, null],
              },
            }),
          )
          .field('map', '{"0":["variables.f.0"],"1":["variables.f.1"]}')
          .file('0', utf8.encode('a'), filename: 'a.txt')
          .file('1', utf8.encode('b'), filename: 'b.txt');
      final response = await fixture.handler().handle(fixture.post(body));
      expect(await fixture.json(response), {
        'data': {'uploadMany': 'a.txt:a,b.txt:b'},
      });
    });

    test('runs as a batch when batching is on', () async {
      final operation = {
        'query': UploadHttpFixture.uploadOperation,
        'variables': {'f': null},
      };
      final body = MultipartBody()
          .field('operations', jsonEncode([operation, operation]))
          .field('map', '{"0":["0.variables.f"],"1":["1.variables.f"]}')
          .file('0', utf8.encode('x'), filename: 'x.txt')
          .file('1', utf8.encode('y'), filename: 'y.txt');
      final response = await fixture
          .handler(batching: const BatchPolicy(allowsMutations: true))
          .handle(fixture.post(body));
      expect(await fixture.json(response), [
        {
          'data': {'upload': 'x.txt:x'},
        },
        {
          'data': {'upload': 'y.txt:y'},
        },
      ]);
    });

    test('is refused as a batch when batching is off', () async {
      final body = MultipartBody()
          .field('operations', '[{"query":"{ ok }"}]')
          .field('map', '{}');
      final response = await fixture.handler().handle(fixture.post(body));
      expect((response.status, await fixture.code(response)), (422, 'GQL428'));
    });

    test('is released after the response is built', () async {
      await fixture.handler().handle(fixture.post(fixture.single()));
      expect(fixture.storage.stored, 1);
      expect(fixture.storage.released, 1);
      expect(fixture.storage.held, isEmpty);
      expect(fixture.uploads.registry.length, 0);
    });

    test('is released when the operation is invalid', () async {
      final body = MultipartBody()
          .field('operations', '{"query":"{ nope }","variables":{"f":null}}')
          .field('map', '{"0":["variables.f"]}')
          .file('0', utf8.encode('x'));
      final response = await fixture.handler().handle(fixture.post(body));
      expect(response.status, 422);
      expect(fixture.storage.held, isEmpty);
      expect(fixture.uploads.registry.length, 0);
    });

    test('is answered although a release throws', () async {
      fixture = UploadHttpFixture(releaseThrows: true);
      final response = await fixture.handler().handle(
        fixture.post(fixture.single()),
      );
      expect(response.status, 200);
      expect(fixture.storage.released, 1);
      expect(fixture.uploads.registry.length, 0);
    });

    test('is unaffected by a GET', () async {
      final response = await fixture.handler().handle(
        HttpRequestData(
          method: 'GET',
          uri: Uri(path: '/graphql', queryParameters: {'query': '{ ok }'}),
          headers: const {'graphql-require-preflight': 'true'},
        ),
      );
      expect(await fixture.json(response), {
        'data': {'ok': 'ok'},
      });
    });
  });

  group('a multipart request refused by the transport', () {
    test('is a 415 when uploads are off', () async {
      final response = await fixture
          .handler(isUploadEnabled: false)
          .handle(fixture.post(fixture.single()));
      expect((response.status, await fixture.code(response)), (415, 'GQL421'));
      expect(
        await fixture.message(response),
        'A POST request must have the content type application/json.',
      );
    });

    test('names both content types in the 415 when uploads are on', () async {
      final response = await fixture.handler().handle(
        fixture.post(fixture.single(), contentType: 'text/plain'),
      );
      expect(
        await fixture.message(response),
        'A POST request must have the content type application/json or '
        'multipart/form-data.',
      );
    });

    test('is a 400 without a boundary', () async {
      final response = await fixture.handler().handle(
        fixture.post(fixture.single(), contentType: 'multipart/form-data'),
      );
      expect((response.status, await fixture.code(response)), (400, 'GQL440'));
      expect(
        await fixture.message(response),
        'The multipart request has no boundary.',
      );
      fixture.expectUntouched();
    });

    test('is a 413 when its content-length is over the limit', () async {
      fixture = UploadHttpFixture(
        limits: const UploadLimits(maxRequestBytes: 100),
      );
      final response = await fixture.handler().handle(
        fixture.post(fixture.single(), headers: {'content-length': '101'}),
      );
      expect((response.status, await fixture.code(response)), (413, 'GQL441'));
      expect(
        await fixture.message(response),
        'The request body is larger than 100 bytes.',
      );
      fixture.expectUntouched();
    });
  });

  group('CSRF prevention', () {
    test('refuses a forged request before reading the body', () async {
      var pulled = 0;
      final response = await fixture
          .handler(profile: ServerProfile.production)
          .handle(
            fixture.post(
              fixture.single(),
              hasPreflight: false,
              stream: fixture.single().stream().map((chunk) {
                pulled += chunk.length;
                return chunk;
              }),
            ),
          );
      expect((response.status, await fixture.code(response)), (403, 'GQL403'));
      expect(await fixture.message(response), const CsrfPrevention().refusal);
      expect(pulled, 0);
      fixture.expectUntouched();
    });

    test('lets a request with the preflight header through', () async {
      final response = await fixture
          .handler(profile: ServerProfile.production)
          .handle(
            fixture.post(
              fixture.single(),
              hasPreflight: false,
              headers: {'apollo-require-preflight': 'true'},
            ),
          );
      expect(response.status, 200);
      expect(await fixture.json(response), {
        'data': {'upload': 'file.txt:hello'},
      });
    });
  });

  group('HttpOptions with uploads', () {
    test('refuses a limit that is not positive', () {
      final uploads = Uploads(limits: const UploadLimits(maxFiles: 0));
      expect(
        () => GraphQLHttpHandler<Object?>(
          fixture.handler().server,
          options: HttpOptions(uploads: uploads),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.name,
            'name',
            'maxFiles',
          ),
        ),
      );
    });
  });
}
