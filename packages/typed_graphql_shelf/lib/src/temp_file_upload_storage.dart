import 'dart:io';
import 'dart:math';

import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'file_upload.dart';

/// An [UploadStorage] that writes each upload to a file in a temporary
/// directory and deletes the file on release.
///
/// It suits files too big for `MemoryUploadStorage`: the content never
/// waits in memory, and the size is bounded by `UploadLimits`. The files are
/// named at random, never after what the client sent, so a hostile file name
/// cannot reach another path.
///
/// {@category shelf}
final class TempFileUploadStorage implements UploadStorage {
  /// Creates a storage that writes under [directory], which must exist, or
  /// under `Directory.systemTemp` when it is null.
  TempFileUploadStorage({Directory? directory})
    : _directory = directory ?? Directory.systemTemp;

  final Directory _directory;
  final Random _random = Random.secure();

  @override
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  ) async {
    final file = await _newFile();
    final sink = file.openWrite();
    var isStored = false;
    try {
      await sink.addStream(content);
      await sink.close();
      isStored = true;
    } finally {
      // A failed content stream (a limit, a broken request) must not leave a
      // partial file; its own failure goes on to the caller.
      if (!isStored) await _discard(file, sink);
    }
    return FileUpload(file, filename, mediaType, await file.length());
  }

  @override
  Future<void> release(Upload upload) async {
    if (upload is! FileUpload) {
      return;
    }
    try {
      await upload.file.delete();
    } on PathNotFoundException {
      // Released twice, or removed from outside: nothing is left to free.
    }
  }

  // `exclusive` makes the creation fail rather than reuse a file that
  // another request, or another process, already made.
  Future<File> _newFile() async {
    final name = [
      for (var i = 0; i < 16; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    return File('${_directory.path}/upload_$name').create(exclusive: true);
  }

  Future<void> _discard(File file, IOSink sink) async {
    try {
      await sink.close();
    } on Exception {
      // The sink may hold the error of the failed content again; the
      // original failure is the one the caller sees.
    }
    try {
      await file.delete();
    } on PathNotFoundException {
      // Nothing was written.
    }
  }
}
