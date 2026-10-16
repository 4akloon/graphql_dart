import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'support/multipart_body.dart';
import 'support/reader_fixture.dart';
import 'support/upload_http_fixture.dart';

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

  MultipartBody twoFiles(List<int> firstContent) => MultipartBody()
      .field('operations', ReaderFixture.operations)
      .field('map', '{"0":["variables.f"]}')
      .file('0', firstContent)
      .rawPart(
        'content-disposition: form-data; name="1"; filename="b"\r\n'
        'x-big: ${'a' * 100000}',
        [1],
      );

  Future<void> expectHeaderRefusal(MultipartBody body) async {
    fixture.expectRefusal(
      await fixture.refusalOf(fixture.readBody(body)),
      413,
      DiagnosticCode.uploadTooLarge,
      'A part header is larger than 8192 bytes.',
    );
    fixture.expectNothingKept();
  }

  group('a file that looks like a closing delimiter', () {
    test('control: an ordinary first file leaves the cap in force', () {
      return expectHeaderRefusal(twoFiles(utf8.encode('hello')));
    });

    test('at the start of its content does not close the body', () {
      return expectHeaderRefusal(twoFiles(utf8.encode('--testBoundary--')));
    });

    test(
      'at the start of its content, in single bytes, does not close',
      () async {
        fixture.expectRefusal(
          await fixture.refusalOf(
            fixture.readBody(
              twoFiles(utf8.encode('--testBoundary--')),
              chunkSize: 1,
            ),
          ),
          413,
          DiagnosticCode.uploadTooLarge,
          'A part header is larger than 8192 bytes.',
        );
      },
    );

    test('a body cut inside such a file is still a cut body', () async {
      final bytes = MultipartBody()
          .field('operations', ReaderFixture.operations)
          .field('map', '{"0":["variables.f"]}')
          .file('0', utf8.encode('--testBoundary--'))
          .bytes;
      final cut = bytes.sublist(0, bytes.length - 20);
      final refusal = await fixture.refusalOf(
        fixture.read(MultipartBody().stream(source: cut)),
      );
      expect(refusal.code, DiagnosticCode.malformedMultipartRequest);
    });
  });

  group('transport padding', () {
    List<int> padded(String from, String to) {
      final text = utf8.decode(fixture.valid().bytes);
      return utf8.encode(text.replaceAll(from, to));
    }

    test(
      'before the closing dashes is a closed body with any epilogue',
      () async {
        final bytes = [
          ...padded('--testBoundary--\r\n', '--testBoundary \t--\r\n'),
          ...List.filled(100000, 0x61),
        ];
        final content = await fixture.contentOf(
          fixture.read(MultipartBody().stream(source: bytes)),
        );
        expect(content.stored.length, 1);
      },
    );

    test('after a delimiter is read', () async {
      final bytes = padded('--testBoundary\r\n', '--testBoundary \t\r\n');
      final content = await fixture.contentOf(
        fixture.read(MultipartBody().stream(source: bytes)),
      );
      expect(content.stored.length, 1);
    });

    test('after the delimiter of a big header does not hide the header', () {
      final text = utf8
          .decode(twoFiles([1]).bytes)
          .replaceAll('--testBoundary\r\n', '--testBoundary \t\r\n');
      return fixture
          .refusalOf(
            fixture.read(MultipartBody().stream(source: utf8.encode(text))),
          )
          .then((refusal) => expect(refusal.status, 413));
    });
  });

  group('the boundary', () {
    late UploadHttpFixture http;

    setUp(() => http = UploadHttpFixture());

    Future<(int, String?)> post(
      MultipartBody body, {
      String? contentType,
      List<int>? bytes,
    }) async {
      final response = await http.handler().handle(
        http.post(
          body,
          contentType: contentType,
          stream: bytes == null ? null : body.stream(source: bytes),
        ),
      );
      return (response.status, await http.code(response));
    }

    MultipartBody bodyWith(String boundary, {String header = ''}) =>
        MultipartBody(boundary: boundary)
            .field(
              'operations',
              jsonEncode({
                'query': UploadHttpFixture.uploadOperation,
                'variables': {'f': null},
              }),
            )
            .field('map', '{"0":["variables.f"]}')
            .rawPart(
              'content-disposition: form-data; name="0"; filename="a"'
              '${header.isEmpty ? '' : '\r\n$header'}',
              [1],
            );

    test(
      'with a non-ASCII character is refused before the body is read',
      () async {
        final body = bodyWith('bé', header: 'x-big: ${'a' * 100000}');
        final latin1Bytes = latin1.encode(utf8.decode(body.bytes));
        expect(await post(body, bytes: latin1Bytes), (400, 'GQL440'));
        http.expectUntouched();
      },
    );

    test('of 71 characters is refused', () async {
      expect(await post(bodyWith('a' * 71)), (400, 'GQL440'));
    });

    test('of 70 characters is accepted', () async {
      expect((await post(bodyWith('a' * 70))).$1, 200);
    });

    test('in quotes, ending with a space, is refused', () async {
      expect(
        await post(
          bodyWith('abc '),
          contentType: 'multipart/form-data; boundary="abc "',
        ),
        (400, 'GQL440'),
      );
    });

    test('with a character outside bchars is refused', () async {
      expect(await post(bodyWith('ab@c')), (400, 'GQL440'));
    });

    test('in quotes, with a space inside, is accepted', () async {
      final body = bodyWith('abc def');
      expect(
        (await post(
          body,
          contentType: 'multipart/form-data; boundary="abc def"',
        )).$1,
        200,
      );
    });
  });
}
