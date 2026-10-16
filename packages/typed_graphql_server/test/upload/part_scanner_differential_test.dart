@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:mime/mime.dart';
import 'package:test/test.dart';
import 'package:typed_graphql_server/src/upload/part_header_scanner.dart';

// `@` stands for the boundary. Each body is a fragment `package:mime` may
// read as parts with long headers, framed in ways a crafted request may use.
// Bytes after a closing delimiter are left out: `package:mime` stalls or
// loops on them when they arrive in a later chunk.
const _bodies = <String>[
  '--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  'x--@--\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  'junk --@-- \r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '\n--@--\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '\r--@--\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  'pre\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  'pre --@ \r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx: y\r\n\r\n--@--\r\n',
  '--@\r\nx: y\r\n\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@ \t\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@\r\n\r\nz\r\n--@--\r\n',
  '--@\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n\r\n--@--\r\n',
  '--@--\r\n',
  '--@--',
  '--@\r\n',
  '--@\r\nx-a: bbbbbbbbbbbb',
  '--@\r\nx-a: bbbbbbbbbbbb\r\n',
  '--@\r\nx-a: b\r\n b\r\n b\r\n b\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-aaaaaaaaaaaaaa: b\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-aaaaaaaaaaaaaa\r\n\r\nc\r\n--@--\r\n',
  '--@\r\na: b\r\nc: d\r\ne: f\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\n--@x\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\n-@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\n\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\n\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\n--@\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\n:\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nxxxxxxxxxxxxxxxxxxxx\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-a: bbbbbbbbbbbb\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-a: bb\nbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '\r\n\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  'x--@\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '-\r\n--@\r\nx-a: bbbbbbbbbbbb\r\n\r\nc\r\n--@--\r\n',
  '--@\r\nx-a:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\r\n\r\n--@--\r\n',
  '--@\r\nx-a: b\r\n\r\ncontent--@ not a delimiter\r\n--@--\r\n',
];

/// The parser as an oracle for the scanner.
final class ParserOracle {
  const ParserOracle(this.boundary);

  final String boundary;

  List<List<int>> chunks(List<int> bytes, int? size) {
    if (size == null) return [bytes];
    return [
      for (var at = 0; at < bytes.length; at += size)
        bytes.sublist(at, at + size > bytes.length ? bytes.length : at + size),
    ];
  }

  /// The size of the largest header (name and value) any part has, as the
  /// parser reads the body: what the scanner must bound. A malformed body
  /// ends the parts the parser could read, and one that stalls (bytes after
  /// the closing delimiter) is given a moment, then left.
  Future<int> largestHeader(List<List<int>> chunks) async {
    var largest = 0;
    Future<void> read() async {
      final done = Completer<void>();
      final subscription = MimeMultipartTransformer(boundary)
          .bind(Stream.fromIterable(chunks))
          .listen(
            (part) {
              largest = math.max(largest, _sizeOf(part));
              part.drain<void>().ignore();
            },
            onError: (Object error) {},
            onDone: done.complete,
          );
      await done.future.timeout(
        const Duration(milliseconds: 20),
        onTimeout: () {},
      );
      await subscription.cancel();
    }

    // The parser reports a malformed header on the part stream as well.
    await runZonedGuarded(read, (error, stackTrace) {})!;
    return largest;
  }

  int _sizeOf(MimeMultipart part) => part.headers.entries
      .map((header) => header.key.length + header.value.length)
      .fold(0, math.max);

  bool scannerRefuses(int cap, List<List<int>> chunks) {
    final scanner = PartHeaderScanner(boundary, cap);
    return chunks.any((chunk) => !scanner.admits(chunk));
  }

  /// The cases where the parser reads a header over a cap that the scanner
  /// admits.
  Future<List<String>> misses(String template) async {
    final bytes = utf8.encode(template.replaceAll('@', boundary));
    final missed = <String>[];
    for (final size in [1, 7, null]) {
      final parts = chunks(bytes, size);
      final largest = await largestHeader(parts);
      final caps = [for (var cap = 4; cap <= 10; cap++) cap];
      missed.addAll([
        for (final cap in caps)
          if (largest > cap && !scannerRefuses(cap, parts))
            '${jsonEncode(template)} chunk $size cap $cap',
      ]);
    }
    return missed;
  }
}

void main() {
  group('the scanner against package:mime', () {
    for (final boundary in ['B', 'BB', '-B']) {
      test(
        'refuses every body whose parser reads a header over the cap, '
        'boundary $boundary',
        () async {
          final oracle = ParserOracle(boundary);
          final failures = <String>[];
          for (final template in _bodies) {
            failures.addAll(await oracle.misses(template));
          }
          expect(failures, isEmpty);
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  });
}
