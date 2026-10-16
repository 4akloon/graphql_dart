@TestOn('vm')
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/src/upload/part_header_scanner.dart';
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

  // The parser takes the first delimiter at byte 0 or after a CRLF, so a
  // `--B` elsewhere in the preamble is not a delimiter, even a closing one.
  const preambles = [
    'x--testBoundary--\r\n',
    'junk --testBoundary-- \r\n',
    '\n--testBoundary--\r\n',
  ];

  List<int> bigHeaderBody(String preamble) => [
    ...utf8.encode(preamble),
    ...MultipartBody().rawPart(
      'content-disposition: form-data; name="x"\r\n'
      'x-big: ${'a' * 100000}',
      [1],
    ).bytes,
  ];

  group('a preamble that looks like a delimiter', () {
    for (final preamble in preambles) {
      for (final chunkSize in [null, 1, 7]) {
        test('${jsonEncode(preamble)} in chunks of $chunkSize '
            'does not hide a large header', () async {
          final refusal = await fixture.refusalOf(
            fixture.read(
              MultipartBody().stream(
                source: bigHeaderBody(preamble),
                chunkSize: chunkSize,
              ),
            ),
          );
          fixture.expectRefusal(
            refusal,
            413,
            DiagnosticCode.uploadTooLarge,
            'A part header is larger than 8192 bytes.',
          );
        });
      }
    }

    test('is refused by the scanner itself', () {
      for (final preamble in preambles) {
        final scanner = PartHeaderScanner('testBoundary', 8192);
        expect(
          scanner.admits(bigHeaderBody(preamble)),
          isFalse,
          reason: preamble,
        );
      }
    });

    test('a long preamble with --B and no CRLF is not a header', () {
      final scanner = PartHeaderScanner('B', 8);
      final preamble = utf8.encode('x--B${'p' * 100}');
      expect(scanner.admits(preamble), isTrue);
      expect(scanner.isCut, isFalse);
    });

    test('the cap is exact: a header block of the cap size passes', () {
      // The line break after the delimiter and the blank line count.
      List<int> body(int headerBytes) => utf8.encode(
        '--B\r\n${'a' * (headerBytes - 6)}\r\n\r\nx',
      );
      expect(PartHeaderScanner('B', 10).admits(body(10)), isTrue);
      expect(PartHeaderScanner('B', 10).admits(body(11)), isFalse);
    });

    test('a delimiter at byte 0 still starts the first part', () {
      final scanner = PartHeaderScanner('B', 8);
      expect(scanner.admits(utf8.encode('--B\r\nx-a: ${'a' * 20}')), isFalse);
    });
  });
}
