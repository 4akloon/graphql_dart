import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/http/request_decoding.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/multipart_body.dart';
import 'support/reader_fixture.dart';

void main() {
  late ReaderFixture fixture;

  setUp(() {
    fixture = ReaderFixture(
      limits: const UploadLimits(
        maxFiles: 3,
        maxFileBytes: 100000,
        maxRequestBytes: 1000000,
        maxFieldBytes: 200,
      ),
    );
  });

  MultipartBody withFileHeaders(String extraHeaders) => MultipartBody()
      .field('operations', ReaderFixture.operations)
      .field('map', '{"0":["variables.f"]}')
      .rawPart(
        'content-disposition: form-data; name="0"; filename="a"\r\n'
        '$extraHeaders',
        [1, 2, 3],
      );

  void expectHeaderRefusal(DecodingRefusal refusal) => fixture.expectRefusal(
    refusal,
    413,
    DiagnosticCode.uploadTooLarge,
    'A part header is larger than 8192 bytes.',
  );

  group('the headers of a part', () {
    test('one 100 KB header is refused', () async {
      final body = withFileHeaders('x-big: ${'a' * 100000}');
      expectHeaderRefusal(await fixture.refusalOf(fixture.readBody(body)));
      fixture.expectNothingKept();
    });

    test('one 100 KB header cut in small chunks is refused', () async {
      final body = withFileHeaders('x-big: ${'a' * 100000}');
      expectHeaderRefusal(
        await fixture.refusalOf(fixture.readBody(body, chunkSize: 1000)),
      );
    });

    test('a thousand tiny headers are refused', () async {
      final body = withFileHeaders(
        [for (var i = 0; i < 1000; i++) 'x-$i: 1'].join('\r\n'),
      );
      expectHeaderRefusal(await fixture.refusalOf(fixture.readBody(body)));
    });

    test('a big header of the first part is refused', () async {
      final body = MultipartBody().rawPart(
        'content-disposition: form-data; name="operations"\r\n'
        'x-big: ${'a' * 100000}',
        utf8.encode(ReaderFixture.operations),
      );
      expectHeaderRefusal(await fixture.refusalOf(fixture.readBody(body)));
    });

    test('headers within the limit are accepted', () async {
      final body = withFileHeaders('x-medium: ${'a' * 4000}');
      expect(
        (await fixture.contentOf(fixture.readBody(body))).stored.length,
        1,
      );
    });

    test('a file much larger than a header is not a header', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', List.filled(50000, 7));
      expect(
        (await fixture.contentOf(fixture.readBody(body))).stored.length,
        1,
      );
    });

    test('a body cut in single bytes is read whole', () async {
      final content = await fixture.contentOf(
        fixture.readBody(fixture.valid(), chunkSize: 1),
      );
      expect(content.stored.length, 1);
    });
  });

  group('the file name and the media type', () {
    test('a file name of 255 characters is accepted', () async {
      final long = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', [1], filename: 'a' * 255);
      expect(
        (await fixture.contentOf(fixture.readBody(long))).stored.length,
        1,
      );
    });

    test('a file name of 256 characters is refused', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', [1], filename: 'a' * 256);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'A file name is longer than 255 characters.',
      );
      fixture.expectNothingKept();
      expect(fixture.storage.stored + fixture.storage.failed, 0);
    });

    test('a media type of 128 characters is refused', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', [1], contentType: 'a/${'b' * 126}');
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'A media type is longer than 127 characters.',
      );
    });

    test('a media type of 127 characters is accepted', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', [1], contentType: 'a/${'b' * 125}');
      expect(
        (await fixture.contentOf(fixture.readBody(body))).stored.length,
        1,
      );
    });
  });

  group('the read', () {
    test('a hundred thousand tiny chunks complete', () async {
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', List.filled(100000, 1));
      final all = body.bytes;
      final chunks = Stream<List<int>>.fromIterable([
        for (var i = 0; i < all.length; i++) [all[i]],
      ]);
      final content = await fixture.contentOf(fixture.read(chunks));
      expect(content.stored.length, 1);
    });

    test('a client that goes away fails the body and cancels it', () async {
      var isCancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      )..add(utf8.encode('--testBoundary\r\ncontent-disposition: form-data; '));
      addTearDown(controller.close);
      final signal = CancelSignal();
      final result = fixture.refusalOf(
        fixture.read(controller.stream, cancelSignal: signal),
      );
      await Future<void>.delayed(Duration.zero);
      signal.cancel();
      fixture.expectRefusal(
        await result,
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body could not be read.',
      );
      expect(isCancelled, isTrue);
    });

    test('failed releases are all reported and all attempted', () async {
      fixture = ReaderFixture(releaseThrows: true);
      final body = MultipartBody()
          .field('operations', ReaderFixture.listOperations)
          .field('map', '{"0":["variables.files.0"],"1":["variables.files.1"]}')
          .file('0', [1])
          .file('1', [2])
          .file('2', [3]);
      await fixture.refusalOf(fixture.readBody(body));
      expect(fixture.storage.released, 2);
      expect(fixture.releaseErrors, hasLength(2));
    });
  });
}
