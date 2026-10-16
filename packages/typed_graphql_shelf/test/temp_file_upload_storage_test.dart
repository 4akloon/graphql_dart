@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';
import 'package:typed_graphql_shelf/src/file_upload.dart';
import 'package:typed_graphql_shelf/typed_graphql_shelf.dart';

final bool _isRoot =
    !Platform.isWindows &&
    Process.runSync('id', ['-u']).stdout.toString().trim() == '0';

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

  test('stores in a private directory by default', () async {
    final byDefault = TempFileUploadStorage();
    final upload = await byDefault.store('a', 'b', Stream.value([1]));
    addTearDown(() async {
      await byDefault.release(upload);
      (upload as FileUpload).file.parent.deleteSync();
    });
    final parent = (upload as FileUpload).file.parent;
    expect(parent.parent.path, Directory.systemTemp.path);
    expect(await upload.openRead().toList(), [
      [1],
    ]);
  });

  test(
    'makes the default directory readable by its owner only',
    () async {
      final byDefault = TempFileUploadStorage();
      final upload = await byDefault.store('a', 'b', Stream.value([1]));
      final parent = (upload as FileUpload).file.parent;
      addTearDown(() async {
        await byDefault.release(upload);
        parent.deleteSync();
      });
      expect(FileStat.statSync(parent.path).mode & 511, 448);
    },
    skip: Platform.isWindows ? 'POSIX modes only' : false,
  );

  Future<void> expectsNoDirectoryLeft(
    Future<ProcessResult> Function(List<String> arguments) chmod,
  ) async {
    String? made;
    final failing = TempFileUploadStorage(
      runChmod: (arguments) {
        made = arguments.last;
        return chmod(arguments);
      },
    );
    await expectLater(
      failing.store('a', 'b', Stream.value([1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(Directory(made!).existsSync(), isFalse);
  }

  test('passes -- before the path to chmod', () async {
    List<String>? seen;
    final spying = TempFileUploadStorage(
      runChmod: (arguments) {
        seen = arguments;
        return Process.run('chmod', arguments);
      },
    );
    final upload = await spying.store('a', 'b', Stream.value([1]));
    final parent = (upload as FileUpload).file.parent;
    addTearDown(() async {
      await spying.release(upload);
      parent.deleteSync();
    });
    expect(seen, ['700', '--', parent.path]);
  }, skip: Platform.isWindows ? 'POSIX modes only' : false);

  test('removes the directory when chmod exits non-zero', () async {
    await expectsNoDirectoryLeft(
      (arguments) async => ProcessResult(1, 1, '', 'denied'),
    );
  }, skip: Platform.isWindows ? 'POSIX modes only' : false);

  test('removes the directory when chmod cannot be run', () async {
    await expectsNoDirectoryLeft(
      (arguments) => throw const ProcessException('chmod', []),
    );
  }, skip: Platform.isWindows ? 'POSIX modes only' : false);

  test('uses one default directory for every upload', () async {
    final byDefault = TempFileUploadStorage();
    final first = await byDefault.store('a', 'b', Stream.value([1]));
    final second = await byDefault.store('a', 'b', Stream.value([2]));
    addTearDown(() async {
      await byDefault.release(first);
      await byDefault.release(second);
      (first as FileUpload).file.parent.deleteSync();
    });
    expect(
      (first as FileUpload).file.parent.path,
      (second as FileUpload).file.parent.path,
    );
  });

  test('refuses to reuse a file that already exists', () async {
    final first = TempFileUploadStorage(
      directory: directory,
      random: Random(7),
    );
    final second = TempFileUploadStorage(
      directory: directory,
      random: Random(7),
    );
    final kept = await first.store('a', 'b', Stream.value([1]));
    await expectLater(
      second.store('a', 'b', Stream.value([2])),
      throwsA(isA<PathExistsException>()),
    );
    expect(await kept.openRead().toList(), [
      [1],
    ]);
  });

  test('fails the store when the file vanishes before its length', () async {
    Stream<List<int>> vanishing() async* {
      yield [1];
      for (final entry in directory.listSync()) {
        entry.deleteSync();
      }
    }

    await expectLater(
      storage.store('a', 'b', vanishing()),
      throwsA(isA<FileSystemException>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test(
    'reports the original failure when the partial file cannot be deleted',
    () async {
      Stream<List<int>> failing() async* {
        yield [1];
        Process.runSync('chmod', ['500', directory.path]);
        throw const FormatException('too long');
      }

      addTearDown(() => Process.runSync('chmod', ['700', directory.path]));
      await expectLater(
        storage.store('a', 'b', failing()),
        throwsA(isA<FormatException>()),
      );
    },
    skip: Platform.isWindows || _isRoot
        ? 'needs POSIX modes and a user that is not root'
        : false,
  );

  test('cannot read an upload after its release', () async {
    final upload = await storage.store('a', 'b', Stream.value([1]));
    await storage.release(upload);
    await expectLater(
      upload.openRead().drain<void>(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
