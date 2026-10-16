import 'dart:io';
import 'dart:math';

import 'package:meta/meta.dart';
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
/// Without a `directory`, the storage makes its own under
/// `Directory.systemTemp` on the first upload and sets its mode to `0700` on
/// POSIX (with `chmod`; if that fails the upload fails), so other local users
/// can neither list nor open the files. The
/// directory is left behind, empty, when the process ends: the system's
/// temporary directory cleaning removes it. A `directory` you give is used as
/// it is, with its own permissions, and must exist: make it private yourself.
///
/// {@category shelf}
final class TempFileUploadStorage implements UploadStorage {
  /// Creates a storage that writes under [directory], which must exist, or
  /// under a private directory of its own when it is null. [random] is for
  /// tests that need two storages to choose the same name.
  TempFileUploadStorage({
    this.directory,
    @visibleForTesting Random? random,
    @visibleForTesting
    Future<ProcessResult> Function(List<String> arguments)? runChmod,
  }) : _random = random ?? Random.secure(),
       _runChmod = runChmod ?? ((arguments) => Process.run('chmod', arguments));

  /// The directory given to the constructor, or null for the private one.
  final Directory? directory;
  final Random _random;
  final Future<ProcessResult> Function(List<String> arguments) _runChmod;
  Future<Directory>? _privateDirectory;

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
      final upload = FileUpload(file, filename, mediaType, await file.length());
      isStored = true;
      return upload;
    } finally {
      // A failed content stream (a limit, a broken request) or a file that
      // cannot be measured must not leave a partial file; its own failure goes
      // on to the caller.
      if (!isStored) await _discard(file, sink);
    }
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
    final target = await _target();
    final name = [
      for (var i = 0; i < 16; i++)
        _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    return File('${target.path}/upload_$name').create(exclusive: true);
  }

  Future<Directory> _target() => switch (directory) {
    final given? => Future.value(given),
    null => _privateDirectory ??= _createPrivate(),
  };

  // `createTemp` makes the directory with the process's umask, not `0700`
  // (dart:io has no `chmod`), so on POSIX the mode is set before any file is
  // made, and a directory that cannot be made private is not used. A failure
  // is not remembered: the next upload tries again.
  Future<Directory> _createPrivate() async {
    try {
      final directory = await Directory.systemTemp.createTemp(
        'typed_graphql_uploads_',
      );
      if (!Platform.isWindows) await _restrict(directory);
      return directory;
    } on Exception {
      _privateDirectory = null;
      rethrow;
    }
  }

  Future<void> _restrict(Directory directory) async {
    try {
      final result = await _runChmod(['700', '--', directory.path]);
      if (result.exitCode == 0) return;
    } on ProcessException {
      // No `chmod` to run (a minimal image): the directory is not private.
    }
    await directory.delete();
    throw FileSystemException(
      'Cannot make the upload directory private',
      directory.path,
    );
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
    } on FileSystemException {
      // Nothing was written, or the file cannot be removed; either way the
      // original failure is the one the caller sees.
    }
  }
}
