import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'support/multipart_body.dart';
import 'support/reader_fixture.dart';

void main() {
  late ReaderFixture fixture;

  setUp(() => fixture = ReaderFixture());

  group('the files', () {
    test('a slow storage does not make a complete body look cut', () async {
      // Each chunk takes the storage a turn of the event loop.
      final content = await fixture.contentOf(
        fixture.readBody(fixture.valid(), chunkSize: 8),
      );
      expect(content.stored.length, 1);
    });

    test('a file the map does not name is refused', () async {
      final body = fixture.valid().file('1', [2]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The request contains a file the map does not name.',
      );
      fixture.expectNothingKept();
    });

    test('the same file part twice is refused', () async {
      final body = fixture.valid().file('0', [2]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The request contains a file the map does not name.',
      );
      fixture.expectNothingKept();
    });

    test('a file the request does not contain is refused', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.listOperations)
          .field('map', '{"0":["variables.files.0"],"1":["variables.files.1"]}')
          .file('0', [1]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The map names a file the request does not contain.',
      );
      fixture.expectNothingKept();
      expect(fixture.storage.released, 1);
    });

    test('a file over maxFileBytes is too large and leaves nothing', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', List.filled(21, 1));
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        413,
        DiagnosticCode.uploadTooLarge,
        'A file is larger than 20 bytes.',
      );
      expect(fixture.storage.stored, 0);
      expect(fixture.storage.failed, 1);
      fixture.expectNothingKept();
    });

    test('a file of exactly maxFileBytes is accepted', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', List.filled(20, 1));
      expect(
        (await fixture.contentOf(fixture.readBody(body))).stored.length,
        1,
      );
    });

    test('files stored before a refusal are released', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.listOperations)
          .field('map', '{"0":["variables.files.0"],"1":["variables.files.1"]}')
          .file('0', [1])
          .file('1', List.filled(21, 1));
      await fixture.refusalOf(fixture.readBody(body));
      expect(fixture.storage.stored, 1);
      expect(fixture.storage.released, 1);
      fixture.expectNothingKept();
    });

    test('a release that throws does not change the refusal', () async {
      fixture = ReaderFixture(releaseThrows: true);
      final body = MultipartBody()
          .field('operations', ReaderFixture.listOperations)
          .field('map', '{"0":["variables.files.0"],"1":["variables.files.1"]}')
          .file('0', [1]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The map names a file the request does not contain.',
      );
    });

    test('a part without content-disposition is refused', () async {
      final body = MultipartBody().rawPart('content-type: text/plain', [1]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'A multipart field must have a content-disposition of form-data with a name.',
      );
    });

    test('a part that is not form-data is refused', () async {
      final body = MultipartBody().rawPart(
        'content-disposition: attachment; name="operations"',
        [1],
      );
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'A multipart field must have a content-disposition of form-data with a name.',
      );
    });
  });
}
