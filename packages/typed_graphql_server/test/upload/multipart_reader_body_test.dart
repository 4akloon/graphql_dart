import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/multipart_body.dart';
import 'support/reader_fixture.dart';

void main() {
  late ReaderFixture fixture;

  setUp(() => fixture = ReaderFixture());

  group('the body', () {
    test('past maxRequestBytes is too large', () async {
      fixture = ReaderFixture(
        limits: const UploadLimits(
          maxFiles: 3,
          maxFileBytes: 5000,
          maxRequestBytes: 400,
          maxFieldBytes: 200,
        ),
      );
      final body = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', List.filled(1000, 1));
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body, chunkSize: 50)),
        413,
        DiagnosticCode.uploadTooLarge,
        'The request body is larger than 400 bytes.',
      );
      fixture.expectNothingKept();
      expect(fixture.storage.stored, 0);
    });

    test('truncated inside a file is malformed and leaves nothing', () async {
      final bytes = fixture.valid().bytes;
      final body = MultipartBody();
      final truncated = bytes.sublist(0, bytes.length - 30);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.read(body.stream(source: truncated))),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The multipart request is malformed.',
      );
      fixture.expectNothingKept();
    });

    test('truncated inside a header is malformed', () async {
      final bytes = fixture.valid().bytes;
      final cut = utf8.decode(bytes).indexOf('name="0"') + 3;
      fixture.expectRefusal(
        await fixture.refusalOf(
          fixture.read(MultipartBody().stream(source: bytes.sublist(0, cut))),
        ),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The multipart request is malformed.',
      );
    });

    test('with a bad header name is malformed', () async {
      final body = MultipartBody().rawPart('bad header: x', [1]);
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.readBody(body)),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The multipart request is malformed.',
      );
    });

    test('that is not multipart at all is malformed', () async {
      fixture.expectRefusal(
        await fixture.refusalOf(
          fixture.read(Stream.value(utf8.encode('{"query":"q"}'))),
        ),
        400,
        DiagnosticCode.malformedMultipartRequest,
        'The multipart request is malformed.',
      );
    });

    test('that never ends is a timeout and the body is cancelled', () async {
      var isCancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () => isCancelled = true,
      )..add(utf8.encode('--testBoundary\r\ncontent-disposition: form-data; '));
      addTearDown(controller.close);
      final result = await fixture.refusalOf(
        fixture.read(
          controller.stream,
          timeout: const Duration(milliseconds: 50),
        ),
      );
      fixture.expectRefusal(
        result,
        408,
        DiagnosticCode.requestBodyTimeout,
        'The request body did not arrive within 50 ms.',
      );
      expect(isCancelled, isTrue);
    });

    test('that stalls inside a file is a timeout and stores nothing', () async {
      final controller = StreamController<List<int>>()
        ..add(
          utf8.encode(
            '--testBoundary\r\ncontent-disposition: form-data; name="operations"'
            '\r\n\r\n${ReaderFixture.operations}\r\n'
            '--testBoundary\r\ncontent-disposition: form-data; name="map"'
            '\r\n\r\n{"0":["variables.f"]}\r\n'
            '--testBoundary\r\ncontent-disposition: form-data; name="0"; '
            'filename="a"\r\n\r\nabc',
          ),
        );
      addTearDown(controller.close);
      final result = await fixture.refusalOf(
        fixture.read(
          controller.stream,
          timeout: const Duration(milliseconds: 50),
        ),
      );
      expect(result.status, 408);
      fixture.expectNothingKept();
      expect(fixture.storage.stored, 0);
    });

    test('that fails is unreadable', () async {
      final controller = StreamController<List<int>>()
        ..add(utf8.encode('--testBoundary\r\ncontent-disposition: '));
      addTearDown(controller.close);
      Timer(
        const Duration(milliseconds: 10),
        () => controller.addError(const ConnectionReset()),
      );
      fixture.expectRefusal(
        await fixture.refusalOf(fixture.read(controller.stream)),
        400,
        DiagnosticCode.malformedRequestBody,
        'The request body could not be read.',
      );
    });

    test('that fails inside a file leaves nothing', () async {
      final controller = StreamController<List<int>>()
        ..add(
          utf8.encode(
            '--testBoundary\r\ncontent-disposition: form-data; name="operations"'
            '\r\n\r\n${ReaderFixture.operations}\r\n'
            '--testBoundary\r\ncontent-disposition: form-data; name="map"'
            '\r\n\r\n{"0":["variables.f"]}\r\n'
            '--testBoundary\r\ncontent-disposition: form-data; name="0"'
            '\r\n\r\nabc',
          ),
        );
      addTearDown(controller.close);
      Timer(
        const Duration(milliseconds: 10),
        () => controller.addError(const ConnectionReset()),
      );
      expect(
        (await fixture.refusalOf(fixture.read(controller.stream))).status,
        400,
      );
      fixture.expectNothingKept();
      expect(fixture.storage.failed, 1);
    });
  });
}
