@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

void main() {
  late Directory directory;
  late TempFileUploadStorage storage;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('typed_graphql_shelf_');
    storage = TempFileUploadStorage(directory: directory);
  });

  tearDown(() => directory.deleteSync(recursive: true));

  Future<String> read(Stream<List<int>> bytes) async =>
      utf8.decode([for (final chunk in await bytes.toList()) ...chunk]);

  test('reads back the bytes it stored', () async {
    final upload = await storage.store(
      'a.txt',
      'text/plain',
      Stream.fromIterable([utf8.encode('hel'), utf8.encode('lo')]),
    );
    expect(await read(upload.openRead()), 'hello');
  });

  test('keeps the file name and media type', () async {
    final upload = await storage.store(
      'a.txt',
      'text/plain',
      Stream.value(utf8.encode('x')),
    );
    expect((upload.filename, upload.mediaType), ('a.txt', 'text/plain'));
  });

  test('reports the byte count as the length', () async {
    final upload = await storage.store(
      'a.bin',
      'application/octet-stream',
      Stream.value([1, 2, 3, 4, 5]),
    );
    expect(upload.length, 5);
  });

  test('opens the content from the first byte every time', () async {
    final upload = await storage.store('a', 'b', Stream.value([7, 8]));
    await upload.openRead().drain<void>();
    expect(await upload.openRead().toList(), [
      [7, 8],
    ]);
  });

  test('stores two uploads of one name in two files', () async {
    final first = await storage.store('a', 'b', Stream.value([1]));
    final second = await storage.store('a', 'b', Stream.value([2]));
    expect(directory.listSync(), hasLength(2));
    expect(await first.openRead().toList(), [
      [1],
    ]);
    expect(await second.openRead().toList(), [
      [2],
    ]);
  });

  final hostileNames = [
    '../../etc/passwd',
    '/etc/passwd',
    r'..\..\windows\system32',
    'a\u0000b.txt',
    'a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/a/',
    'x' * 10000,
    '',
  ];
  for (var i = 0; i < hostileNames.length; i++) {
    final hostile = hostileNames[i];
    test('never uses hostile file name number $i as a path', () async {
      final upload = await storage.store(hostile, 'b', Stream.value([1]));
      final file = directory.listSync().single;
      expect(file.parent.path, directory.path);
      expect(
        file.uri.pathSegments.last,
        matches(RegExp(r'^upload_[0-9a-f]{32}$')),
      );
      expect(upload.filename, hostile);
      await storage.release(upload);
      expect(directory.listSync(), isEmpty);
    });
  }

  test('ignores the release of an upload it did not store', () async {
    final foreign = await const MemoryUploadStorage().store(
      'a',
      'b',
      Stream.value([1]),
    );
    await expectLater(storage.release(foreign), completes);
  });

  test('deletes the file on release', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    expect(directory.listSync(), isEmpty);
  });

  test('releases an upload twice without failing', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    await expectLater(storage.release(upload), completes);
  });

  test('leaves no file when the content stream fails', () async {
    final content = Stream<List<int>>.multi((controller) {
      controller
        ..add([1, 2, 3])
        ..addError(const FormatException('too long'));
      controller.close();
    });
    await expectLater(
      storage.store('a', 'b', content),
      throwsA(isA<FormatException>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('stores in the system temporary directory by default', () async {
    final byDefault = TempFileUploadStorage();
    final upload = await byDefault.store('a', 'b', Stream.value([1]));
    addTearDown(() => byDefault.release(upload));
    expect(await upload.openRead().toList(), [
      [1],
    ]);
  });

  test('cannot read an upload after its release', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    await expectLater(
      upload.openRead().drain<void>(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
