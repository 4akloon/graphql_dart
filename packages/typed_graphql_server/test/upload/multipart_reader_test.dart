import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'support/multipart_body.dart';
import 'support/reader_fixture.dart';

void main() {
  late ReaderFixture fixture;

  setUp(() => fixture = ReaderFixture());

  group('a valid request', () {
    test('has its null replaced by the token of the file', () async {
      final content = await fixture.contentOf(
        fixture.readBody(fixture.valid()),
      );
      final token = content.stored.tokens.single;
      expect(
        content.operations.toJson(),
        {
          'query': r'mutation ($f: Upload!) { upload(file: $f) }',
          'variables': {'f': token},
        },
      );
    });

    test('registers the upload under its token', () async {
      final content = await fixture.contentOf(
        fixture.readBody(fixture.valid()),
      );
      final upload = fixture.uploads.registry.lookup(
        content.stored.tokens.single,
      );
      final bytes = await upload!.openRead().expand((c) => c).toList();
      expect(utf8.decode(bytes), 'hello');
    });

    test('passes the file name and the media type to the storage', () async {
      await fixture.contentOf(
        fixture.readBody(
          MultipartBody()
              .field('operations', ReaderFixture.operations)
              .field('map', '{"0":["variables.f"]}')
              .file(
                '0',
                [1, 2],
                filename: 'a.bin',
                contentType: 'application/x-test',
              ),
        ),
      );
      expect(fixture.storage.filenames, ['a.bin']);
      expect(fixture.storage.mediaTypes, ['application/x-test']);
    });

    test('defaults the file name and the media type', () async {
      await fixture.contentOf(
        fixture.readBody(
          MultipartBody()
              .field('operations', ReaderFixture.operations)
              .field('map', '{"0":["variables.f"]}')
              .file('0', [1], filename: null, contentType: null),
        ),
      );
      expect(fixture.storage.filenames, ['']);
      expect(fixture.storage.mediaTypes, ['application/octet-stream']);
    });

    test('reads a body that arrives one byte at a time', () async {
      final content = await fixture.contentOf(
        fixture.readBody(fixture.valid(), chunkSize: 1),
      );
      expect(content.stored.length, 1);
    });

    test('puts two files in a list', () async {
      final content = await fixture.contentOf(
        fixture.readBody(
          MultipartBody()
              .field('operations', ReaderFixture.listOperations)
              .field(
                'map',
                '{"0":["variables.files.0"],"1":["variables.files.1"]}',
              )
              .file('0', [1])
              .file('1', [2]),
        ),
      );
      final files =
          ((content.operations as JsonObject)['variables']!
                  as JsonObject)['files']!
              as JsonArray;
      expect(
        files.items.map((item) => (item as JsonString).value),
        content.stored.tokens,
      );
    });

    test('puts one file at two places', () async {
      final content = await fixture.contentOf(
        fixture.readBody(
          MultipartBody()
              .field('operations', ReaderFixture.listOperations)
              .field('map', '{"0":["variables.files.0","variables.files.1"]}')
              .file('0', [1]),
        ),
      );
      expect(content.stored.length, 1);
      expect(fixture.storage.stored, 1);
    });

    test('puts a file into the item of a batch', () async {
      final content = await fixture.contentOf(
        fixture.readBody(
          MultipartBody()
              .field(
                'operations',
                '[{"query":"a"},{"query":"b","variables":{"f":null}}]',
              )
              .field('map', '{"0":["1.variables.f"]}')
              .file('0', [1]),
        ),
      );
      final batch = content.operations as JsonArray;
      final variables =
          (batch.items[1] as JsonObject)['variables']! as JsonObject;
      expect(variables['f'], JsonString(content.stored.tokens.single));
    });

    test('accepts a request with no file', () async {
      final content = await fixture.contentOf(
        fixture.readBody(
          MultipartBody()
              .field('operations', '{"query":"{ a }"}')
              .field('map', '{}'),
        ),
      );
      expect(content.stored.length, 0);
    });

    test(
      'is not touched by the release of its uploads before the caller',
      () async {
        final content = await fixture.contentOf(
          fixture.readBody(fixture.valid()),
        );
        expect(fixture.storage.released, 0);
        await content.stored.release();
        expect(fixture.storage.released, 1);
        expect(fixture.uploads.registry.length, 0);
      },
    );
  });

  group('the fields', () {
    test('operations must come first', () async {
      final body = MultipartBody()
          .field('map', '{}')
          .field('operations', '{"query":"q"}');
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The first field of a multipart request must be operations.',
      );
    });

    test('map must come second', () async {
      final body = MultipartBody().field('operations', '{"query":"q"}').file(
        '0',
        [1],
      );
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The second field of a multipart request must be map.',
      );
    });

    test('a body with no operations is refused', () async {
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(MultipartBody())),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The first field of a multipart request must be operations.',
      );
    });

    test('a body that ends after operations is refused', () async {
      fixture.expectRefusal(
        await fixture.refusalOf(
          fixture.readBody(
            MultipartBody().field('operations', '{"query":"q"}'),
          ),
        ),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The second field of a multipart request must be map.',
      );
    });

    test('operations that is not JSON is refused', () async {
      fixture.expectRefusal(
        await fixture.refusalOf(
          fixture.readBody(
            MultipartBody().field('operations', '{').field('map', '{}'),
          ),
        ),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The operations field is not valid JSON.',
      );
    });

    test('operations that is not UTF-8 is refused', () async {
      fixture.expectRefusal(
        await fixture.refusalOf(
          fixture.readBody(
            MultipartBody()
                .fieldBytes('operations', [0xff, 0xfe])
                .field('map', '{}'),
          ),
        ),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The operations field is not valid JSON.',
      );
    });

    test('operations nested deeper than maxJsonDepth is refused', () async {
      final body = MultipartBody()
          .field('operations', '${'[' * 10}${']' * 10}')
          .field('map', '{}');
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.read(body.stream(), maxJsonDepth: 5)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The operations field is not valid JSON.',
      );
    });

    test('map that is not JSON is refused', () async {
      fixture.expectRefusal(
        await fixture.refusalOf(
          fixture.readBody(
            MultipartBody()
                .field('operations', '{"query":"q"}')
                .field('map', 'x'),
          ),
        ),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The map field is not valid JSON.',
      );
    });

    test('operations over maxFieldBytes is too large', () async {
      final body = MultipartBody()
          .field('operations', '{"query":"${'a' * 300}"}')
          .field('map', '{}');
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        413,
        DiagnosticCode.uploadTooLarge,
        'The operations field is larger than 200 bytes.',
      );
    });

    test('map over maxFieldBytes is too large', () async {
      final body = MultipartBody()
          .field('operations', '{"query":"q"}')
          .field('map', '{"${'a' * 300}":["variables.f"]}');
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        413,
        DiagnosticCode.uploadTooLarge,
        'The map field is larger than 200 bytes.',
      );
    });

    test('a map with a bad path is refused with the map\'s message', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["query"]}')
          .file('0', [1]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'A map path must name a null value inside variables.',
      );
    });

    test(
      'a map with too many keys is refused before any file is read',
      () async {
        final body = MultipartBody()
            .field('operations', ReaderFixture.operations)
            .field('map', '{"a":["variables.f"],"b":[],"c":[],"d":[]}')
            .file('a', [1]);
        fixture.expectRefusal(
          await fixture.refusalOf(fixture.readBody(body)),
          413,
          DiagnosticCode.tooManyUploads,
          'The map may name at most 3 files.',
        );
        expect(fixture.storage.stored, 0);
      },
    );
  });
}
