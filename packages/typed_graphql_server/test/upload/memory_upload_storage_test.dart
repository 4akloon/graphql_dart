import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

void main() {
  const storage = MemoryUploadStorage();

  Future<Upload> storeChunks(List<List<int>> chunks) => storage.store(
    'notes.txt',
    'text/plain',
    Stream.fromIterable(chunks),
  );

  group('MemoryUploadStorage', () {
    test('keeps the file name and the media type', () async {
      final upload = await storeChunks([utf8.encode('hi')]);
      expect(upload.filename, 'notes.txt');
      expect(upload.mediaType, 'text/plain');
    });

    test('joins the chunks and reports the length', () async {
      final upload = await storeChunks([utf8.encode('he'), utf8.encode('llo')]);
      expect(upload.length, 5);
      expect(
        utf8.decode(
          (await upload.openRead().toList()).expand((c) => c).toList(),
        ),
        'hello',
      );
    });

    test('every openRead starts at the first byte', () async {
      final upload = await storeChunks([utf8.encode('abc')]);
      final first = await upload.openRead().expand((chunk) => chunk).toList();
      final second = await upload.openRead().expand((chunk) => chunk).toList();
      expect(second, first);
    });

    test('an empty file has length zero', () async {
      expect((await storeChunks([])).length, 0);
    });

    test('lets the error of the content through', () async {
      final failing = Stream<List<int>>.multi((controller) {
        controller
          ..add([1])
          ..addError(StateError('over the limit'))
          ..close();
      });
      await expectLater(
        storage.store('a', 'b', failing),
        throwsA(isA<StateError>()),
      );
    });

    test('release of an upload does nothing and does not throw', () async {
      final upload = await storeChunks([utf8.encode('x')]);
      await storage.release(upload);
      expect(upload.length, 1);
    });
  });
}
